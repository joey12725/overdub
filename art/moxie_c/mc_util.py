"""Shared helpers for the Moxie (candidate C) build: numpy SDF sculpting, lofts/sweeps, bpy glue.

Conventions (Blender): Z up, the character faces -Y, her left is +X, metres. glTF export turns
that into Godot's Y up / facing +Z.
"""
import math

import bmesh
import bpy
import numpy as np

# --------------------------------------------------------------------------- maths

def V(*a):
    return np.array(a, dtype=np.float64)


def smoothstep(a, b, x):
    t = np.clip((np.asarray(x, dtype=np.float64) - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def norm(v):
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-12)


def catmull(pts, n, closed=False):
    """Sample a Catmull-Rom spline through pts (k,d) at n points (uniform in parameter)."""
    pts = np.asarray(pts, dtype=np.float64)
    k = len(pts)
    if closed:
        ts = np.linspace(0, k, n, endpoint=False)
    else:
        ts = np.linspace(0, k - 1, n)
    out = []
    for t in ts:
        i = int(math.floor(t))
        if not closed and i >= k - 1:
            i = k - 2
        u = t - i

        def P(j):
            if closed:
                return pts[j % k]
            return pts[min(max(j, 0), k - 1)]
        p0, p1, p2, p3 = P(i - 1), P(i), P(i + 1), P(i + 2)
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u
                          + (-p0 + 3 * p1 - 3 * p2 + p3) * u ** 3))
    return np.array(out)


def resample(poly, n, closed=False):
    """Resample a polyline to n points evenly spaced by arc length."""
    poly = np.asarray(poly, dtype=np.float64)
    if closed:
        poly = np.vstack([poly, poly[:1]])
    seg = np.linalg.norm(np.diff(poly, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    if closed:
        q = np.linspace(0, s[-1], n, endpoint=False)
    else:
        q = np.linspace(0, s[-1], n)
    out = np.empty((n, poly.shape[1]))
    for d in range(poly.shape[1]):
        out[:, d] = np.interp(q, s, poly[:, d])
    return out


def rot_axis(axis, ang):
    axis = np.asarray(axis, dtype=np.float64)
    axis = axis / np.linalg.norm(axis)
    x, y, z = axis
    c, s = math.cos(ang), math.sin(ang)
    C = 1 - c
    return np.array([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
                     [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
                     [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])


def hash3(p, seed=0.0):
    """Cheap deterministic pseudo-noise in [-1,1] per point (smooth, sum of sines)."""
    p = np.asarray(p)
    x, y, z = p[..., 0], p[..., 1], p[..., 2]
    s = seed * 1.7
    return (np.sin(x * 37.1 + y * 17.3 + s) * np.cos(z * 29.7 - x * 11.9 + s * 2.3)
            + 0.5 * np.sin(y * 53.3 + z * 41.1 + s * 0.7) * np.cos(x * 61.7 + s)) / 1.5


class Rand:
    """Tiny deterministic RNG (so rebuilds are identical)."""

    def __init__(self, seed):
        self.r = np.random.RandomState(seed)

    def u(self, a=0.0, b=1.0):
        return float(self.r.uniform(a, b))

    def n(self, s=1.0):
        return float(self.r.normal(0, s))


# --------------------------------------------------------------------------- SDF

def sd_ellipsoid(p, c, r):
    q = (p - c) / r
    k0 = np.linalg.norm(q, axis=-1)
    k1 = np.linalg.norm(q / r, axis=-1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def sd_sphere(p, c, r):
    return np.linalg.norm(p - c, axis=-1) - r


def sd_cone(p, a, b, ra, rb, scale=None):
    """Round cone / capsule from a (radius ra) to b (radius rb). scale squashes space first
    (anisotropic cross-sections): scale=(sx,sy,sz) multiplies offsets from the axis start."""
    a = np.asarray(a, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64)
    pa = p - a
    ba = b - a
    if scale is not None:
        sc = np.asarray(scale, dtype=np.float64)
        pa = pa / sc
        ba = ba / sc
    t = np.clip((pa @ ba) / (ba @ ba), 0.0, 1.0)
    d = np.linalg.norm(pa - t[..., None] * ba, axis=-1)
    r = ra + (rb - ra) * t
    out = d - r
    if scale is not None:
        out = out * float(np.min(scale))
    return out


def sd_box(p, c, h, r=0.0):
    q = np.abs(p - c) - (np.asarray(h) - r)
    return np.linalg.norm(np.maximum(q, 0.0), axis=-1) + np.minimum(np.max(q, axis=-1), 0.0) - r


def smin(a, b, k):
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.minimum(a, b) - h * h * k * 0.25


def smax(a, b, k):
    return -smin(-a, -b, k)


def sdf_grad(f, p, e=4e-4):
    g = np.empty_like(p)
    for i in range(3):
        d = np.zeros(3)
        d[i] = e
        g[:, i] = (f(p + d) - f(p - d)) / (2 * e)
    return g


def sdf_project(f, p, iters=8, damp=1.0):
    """Move points onto the zero level set along the gradient."""
    p = np.array(p, dtype=np.float64)
    for _ in range(iters):
        g = sdf_grad(f, p)
        gg = np.maximum((g * g).sum(axis=1), 1e-10)
        p = p - damp * (f(p) / gg)[:, None] * g
    return p


def sdf_normal(f, p):
    return norm(sdf_grad(f, p))


def sdf_march(f, origin, direction, tmax=1.0, steps=80):
    """Sphere-trace from origin along direction (per point); returns hit points."""
    o = np.asarray(origin, dtype=np.float64)
    d = norm(np.asarray(direction, dtype=np.float64))
    o = np.broadcast_to(o, d.shape) if o.ndim == 1 else o
    t = np.zeros(len(d))
    for _ in range(steps):
        v = f(o + t[:, None] * d)
        t = np.minimum(t + np.maximum(v, 0.0) * 0.8, tmax)
    return o + t[:, None] * d


# --------------------------------------------------------------------------- mesh building

class Mesh:
    """Accumulates vertices / polygons / per-face material names / uvs."""

    def __init__(self):
        self.v = []
        self.f = []
        self.m = []
        self.uv = {}      # face index -> list of (u,v)
        self.nv = 0

    def add(self, verts, faces, mat, uvs=None):
        verts = np.asarray(verts, dtype=np.float64).reshape(-1, 3)
        base = self.nv
        self.v.append(verts)
        self.nv += len(verts)
        for i, fc in enumerate(faces):
            if uvs is not None:
                self.uv[len(self.f)] = [tuple(uvs[j]) for j in fc]
            self.f.append(tuple(int(j) + base for j in fc))
            self.m.append(mat)
        return base

    def merge(self, other):
        base = self.nv
        for arr in other.v:
            self.v.append(arr)
        self.nv += other.nv
        n0 = len(self.f)
        for i, fc in enumerate(other.f):
            self.f.append(tuple(j + base for j in fc))
            self.m.append(other.m[i])
        for k, u in other.uv.items():
            self.uv[k + n0] = u
        return base

    def verts(self):
        return np.vstack(self.v) if self.v else np.zeros((0, 3))

    def mirrored(self, axis=0):
        """A mirrored copy (faces flipped)."""
        o = Mesh()
        vv = self.verts().copy()
        vv[:, axis] *= -1
        o.v = [vv]
        o.nv = len(vv)
        o.f = [tuple(reversed(fc)) for fc in self.f]
        o.m = list(self.m)
        o.uv = {k: list(reversed(u)) for k, u in self.uv.items()}
        return o

    def transform(self, R=None, t=None, s=None):
        vv = self.verts()
        if s is not None:
            vv = vv * s
        if R is not None:
            vv = vv @ np.asarray(R).T
        if t is not None:
            vv = vv + np.asarray(t)
        self.v = [vv]
        return self


def tube_faces(nr, n, closed=True, flip=False):
    """Quads for nr rings of n verts (ring r, vert i -> r*n+i)."""
    fs = []
    m = n if closed else n - 1
    for r in range(nr - 1):
        for i in range(m):
            a = r * n + i
            b = r * n + (i + 1) % n
            c = (r + 1) * n + (i + 1) % n
            d = (r + 1) * n + i
            fs.append((a, d, c, b) if flip else (a, b, c, d))
    return fs


def loft(rings, mat, mesh=None, cap0=False, cap1=False, flip=False, closed=True):
    """rings: (R,N,3). Normals face outward when ring verts run counter-clockwise seen from the
    loft direction's tip (pass flip=True otherwise)."""
    rings = np.asarray(rings, dtype=np.float64)
    R, N, _ = rings.shape
    mesh = mesh or Mesh()
    fs = tube_faces(R, N, closed, flip)
    verts = rings.reshape(-1, 3)
    extra = []
    if cap0:
        c = rings[0].mean(axis=0)
        ci = len(verts) + len(extra)
        extra.append(c)
        for i in range(N):
            a, b = i, (i + 1) % N
            fs.append((ci, a, b) if flip else (ci, b, a))
    if cap1:
        c = rings[-1].mean(axis=0)
        ci = len(verts) + len(extra)
        extra.append(c)
        o = (R - 1) * N
        for i in range(N):
            a, b = o + i, o + (i + 1) % N
            fs.append((ci, b, a) if flip else (ci, a, b))
    if extra:
        verts = np.vstack([verts, np.array(extra)])
    mesh.add(verts, fs, mat)
    return mesh


def frames_along(path, up_hint):
    """Parallel-transport frames along a polyline. Returns tangents T, normals N, binormals B."""
    path = np.asarray(path, dtype=np.float64)
    n = len(path)
    T = np.zeros_like(path)
    T[1:-1] = path[2:] - path[:-2]
    T[0] = path[1] - path[0]
    T[-1] = path[-1] - path[-2]
    T = norm(T)
    up = np.asarray(up_hint, dtype=np.float64)
    N = np.zeros_like(path)
    v = up - T[0] * (up @ T[0])
    if np.linalg.norm(v) < 1e-6:
        v = np.cross(T[0], V(1, 0, 0))
    N[0] = v / np.linalg.norm(v)
    for i in range(1, n):
        v = N[i - 1] - T[i] * (N[i - 1] @ T[i])
        N[i] = v / max(np.linalg.norm(v), 1e-9)
    B = np.cross(T, N)
    return T, N, B


def sweep(path, profile, scale, up_hint, mat, mesh=None, twist=None, cap0=True, cap1=True,
          thick=None):
    """Sweep a 2D profile (k,2) (x along binormal, y along normal) along path.
    scale: per-point width scale (n,) ; thick: per-point scale for profile y (defaults to scale)."""
    path = np.asarray(path, dtype=np.float64)
    T, N, B = frames_along(path, up_hint)
    prof = np.asarray(profile, dtype=np.float64)
    n = len(path)
    scale = np.broadcast_to(np.asarray(scale, dtype=np.float64), (n,))
    thick = scale if thick is None else np.broadcast_to(np.asarray(thick, dtype=np.float64), (n,))
    rings = np.empty((n, len(prof), 3))
    for i in range(n):
        Ni, Bi = N[i], B[i]
        if twist is not None:
            Rm = rot_axis(T[i], float(np.broadcast_to(twist, (n,))[i]))
            Ni, Bi = Rm @ Ni, Rm @ Bi
        rings[i] = path[i] + prof[:, :1] * scale[i] * Bi + prof[:, 1:2] * thick[i] * Ni
    return loft(rings, mat, mesh, cap0=cap0, cap1=cap1)


def circle_profile(n, rx=1.0, ry=1.0, power=2.0):
    a = np.linspace(0, 2 * math.pi, n, endpoint=False)
    c, s = np.cos(a), np.sin(a)
    e = 2.0 / power
    return np.stack([rx * np.sign(c) * np.abs(c) ** e, ry * np.sign(s) * np.abs(s) ** e], axis=1)


def rbox(c, h, r, mat, mesh=None, seg=2, R=None):
    """Rounded box centred at c with half extents h and corner radius r (bevelled cube)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=2.0)
    for v in bm.verts:
        v.co.x *= h[0]
        v.co.y *= h[1]
        v.co.z *= h[2]
    if r > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=r, segments=seg, profile=0.5,
                        affect='EDGES')
    vs = np.array([v.co[:] for v in bm.verts])
    fs = [tuple(v.index for v in f.verts) for f in bm.faces]
    bm.free()
    if R is not None:
        vs = vs @ np.asarray(R).T
    vs = vs + np.asarray(c)
    mesh = mesh or Mesh()
    mesh.add(vs, fs, mat)
    return mesh


def cylinder(a, b, r, mat, mesh=None, n=16, bevel=0.0, r2=None, caps=True):
    """Cylinder from a to b, optional bevelled rims (bevel = chamfer size)."""
    a = np.asarray(a, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64)
    r2 = r if r2 is None else r2
    L = np.linalg.norm(b - a)
    path = [a, b]
    rad = [r, r2]
    if bevel > 0:
        d = (b - a) / L
        path = [a, a + d * bevel, b - d * bevel, b]
        rad = [r - bevel, r, r2, r2 - bevel]
    up = V(0, 0, 1) if abs((b - a)[2]) < 0.9 * L else V(1, 0, 0)
    return sweep(np.array(path), circle_profile(n), np.array(rad), up, mat, mesh, cap0=caps,
                 cap1=caps)


def torus(c, axis, R, r, mat, mesh=None, n=24, m=8, arc=(0, 2 * math.pi), squash=1.0):
    c = np.asarray(c, dtype=np.float64)
    axis = norm(np.asarray(axis, dtype=np.float64))
    u = np.cross(axis, V(0, 0, 1))
    if np.linalg.norm(u) < 1e-6:
        u = V(1, 0, 0)
    u = norm(u)
    w = np.cross(axis, u)
    full = abs(arc[1] - arc[0] - 2 * math.pi) < 1e-6
    aa = np.linspace(arc[0], arc[1], n, endpoint=not full)
    rings = []
    for a in aa:
        d = math.cos(a) * u + math.sin(a) * w
        ring = []
        for j in range(m):
            b = 2 * math.pi * j / m
            ring.append(c + d * (R + r * math.cos(b)) + axis * (r * squash * math.sin(b)))
        rings.append(ring)
    rings = np.array(rings)
    mesh = mesh or Mesh()
    if full:
        rings = np.vstack([rings, rings[:1]])
        return loft(rings, mat, mesh, flip=True)
    return loft(rings, mat, mesh, cap0=True, cap1=True, flip=True)


# --------------------------------------------------------------------------- bpy glue

PALETTE = {}


def srgb_to_lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def hexcol(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def material(name):
    """Get/create a material from PALETTE: name -> (hex, roughness, emission_strength[, texture])."""
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    spec = PALETTE[name]
    col = srgb_to_lin(hexcol(spec[0]))
    rough = spec[1] if len(spec) > 1 else 0.8
    emit = spec[2] if len(spec) > 2 else 0.0
    tex = spec[3] if len(spec) > 3 else None
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*col, 1.0)
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = 0.2
    if emit > 0:
        b.inputs["Emission Color"].default_value = (*col, 1.0)
        b.inputs["Emission Strength"].default_value = emit
    if tex:
        img = bpy.data.images.load(tex, check_existing=True)
        tn = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tn.image = img
        mat.node_tree.links.new(tn.outputs["Color"], b.inputs["Base Color"])
        b.inputs["Base Color"].default_value = (1, 1, 1, 1)
    mat.use_backface_culling = False
    return mat


def to_object(name, mesh, smooth=True, collection=None, merge=0.0):
    """Create a bpy mesh object from a Mesh."""
    me = bpy.data.meshes.new(name)
    vv = mesh.verts()
    me.from_pydata([tuple(p) for p in vv], [], mesh.f)
    names = []
    for m in mesh.m:
        if m not in names:
            names.append(m)
    for n in names:
        me.materials.append(material(n))
    idx = {n: i for i, n in enumerate(names)}
    me.polygons.foreach_set("material_index", [idx[m] for m in mesh.m])
    if mesh.uv:
        uvl = me.uv_layers.new(name="UVMap")
        for pi, poly in enumerate(me.polygons):
            u = mesh.uv.get(pi)
            if u:
                for k, li in enumerate(poly.loop_indices):
                    uvl.data[li].uv = u[k]
    me.update()
    me.validate()
    if smooth:
        me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    ob = bpy.data.objects.new(name, me)
    (collection or bpy.context.scene.collection).objects.link(ob)
    if merge > 0:
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=merge)
        bm.to_mesh(me)
        bm.free()
    return ob


def activate(ob):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def subsurf(ob, levels=1, simple=False, crease=True):
    activate(ob)
    m = ob.modifiers.new("ss", 'SUBSURF')
    m.levels = levels
    m.subdivision_type = 'SIMPLE' if simple else 'CATMULL_CLARK'
    m.use_creases = crease
    m.boundary_smooth = 'PRESERVE_CORNERS' if False else 'ALL'
    bpy.ops.object.modifier_apply(modifier=m.name)
    return ob


def get_co(ob):
    n = len(ob.data.vertices)
    a = np.empty(n * 3)
    ob.data.vertices.foreach_get("co", a)
    return a.reshape(-1, 3)


def set_co(ob, co):
    ob.data.vertices.foreach_set("co", np.asarray(co, dtype=np.float64).reshape(-1))
    ob.data.update()


def mesh_adjacency(me):
    n = len(me.vertices)
    adj = [[] for _ in range(n)]
    for e in me.edges:
        a, b = e.vertices
        adj[a].append(b)
        adj[b].append(a)
    return adj


def boundary_verts(me):
    bm = bmesh.new()
    bm.from_mesh(me)
    out = np.zeros(len(bm.verts), dtype=bool)
    for e in bm.edges:
        if e.is_boundary:
            out[e.verts[0].index] = True
            out[e.verts[1].index] = True
    bm.free()
    return out


def laplacian(co, adj, mask=None, k=0.5, iters=1):
    co = co.copy()
    idx = [i for i in range(len(co)) if adj[i] and (mask is None or mask[i])]
    for _ in range(iters):
        new = co.copy()
        for i in idx:
            new[i] = co[i] * (1 - k) + k * co[adj[i]].mean(axis=0)
        co = new
    return co


def laplacian_fast(co, me, mask=None, k=0.5, iters=1):
    """Vectorised umbrella smoothing using the edge list."""
    ne = len(me.edges)
    ev = np.empty(ne * 2, dtype=np.int32)
    me.edges.foreach_get("vertices", ev)
    ev = ev.reshape(-1, 2)
    n = len(co)
    deg = np.zeros(n)
    np.add.at(deg, ev[:, 0], 1)
    np.add.at(deg, ev[:, 1], 1)
    deg = np.maximum(deg, 1)
    co = co.copy()
    for _ in range(iters):
        acc = np.zeros_like(co)
        np.add.at(acc, ev[:, 0], co[ev[:, 1]])
        np.add.at(acc, ev[:, 1], co[ev[:, 0]])
        avg = acc / deg[:, None]
        new = co * (1 - k) + k * avg
        if mask is not None:
            new[~mask] = co[~mask]
        co = new
    return co


def solidify(ob, thickness, offset=1.0, rim_mat=None, apply=True):
    activate(ob)
    m = ob.modifiers.new("solid", 'SOLIDIFY')
    m.thickness = thickness
    m.offset = offset
    m.use_even_offset = True
    m.use_quality_normals = True
    if apply:
        bpy.ops.object.modifier_apply(modifier=m.name)
    return ob


def join(obs, name):
    obs = [o for o in obs if o is not None]
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    if len(obs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def tri_count(obs):
    t = 0
    for o in obs:
        if o.type == 'MESH':
            t += sum(len(p.vertices) - 2 for p in o.data.polygons)
    return t


def shade_auto(ob, angle=40):
    """Smooth shading with sharp edges above an angle (for hard-surface gear)."""
    me = ob.data
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    activate(ob)
    try:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    except Exception:
        pass
    bm = bmesh.new()
    bm.from_mesh(me)
    ca = math.radians(angle)
    for e in bm.edges:
        if len(e.link_faces) == 2:
            e.smooth = e.calc_face_angle(0.0) < ca
    bm.to_mesh(me)
    bm.free()
    me.update()
