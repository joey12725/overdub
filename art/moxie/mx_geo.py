"""Geometry helpers for the Moxie build: lofts, sweeps, lathes, rounded boxes, materials.

Everything is built in Blender's coordinates: metres, Z up, the character faces -Y (glTF/Godot
+Z after export), her left side is +X. Helpers return plain bpy objects linked into the scene;
the build scripts compose them, assign materials and weights, then join everything into one
skinned mesh.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

TAU = math.tau


# --------------------------------------------------------------------------------------------
# small math
# --------------------------------------------------------------------------------------------

def V(x, y, z):
    return Vector((x, y, z))


def lerp(a, b, t):
    return a + (b - a) * t


def clamp(x, lo, hi):
    return lo if x < lo else hi if x > hi else x


def smoothstep(e0, e1, x):
    if e0 == e1:
        return 0.0 if x < e0 else 1.0
    t = clamp((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def interp_profile(profile, t):
    """Piecewise-linear lookup in [(t, value), ...] sorted by t (values may be numbers or tuples)."""
    if t <= profile[0][0]:
        return profile[0][1]
    for (t0, v0), (t1, v1) in zip(profile, profile[1:]):
        if t <= t1:
            u = (t - t0) / (t1 - t0) if t1 > t0 else 0.0
            u = u * u * (3 - 2 * u)  # smooth between control values
            if isinstance(v0, tuple):
                return tuple(lerp(a, b, u) for a, b in zip(v0, v1))
            return lerp(v0, v1, u)
    return profile[-1][1]


def catmull(points, samples_per_seg=6):
    """Centripetal-ish Catmull-Rom through the control points, returns a dense polyline."""
    pts = [Vector(p) for p in points]
    if len(pts) < 2:
        return pts
    ext = [pts[0] + (pts[0] - pts[1])] + pts + [pts[-1] + (pts[-1] - pts[-2])]
    out = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for s in range(samples_per_seg):
            t = s / samples_per_seg
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(pts[-1].copy())
    return out


def resample(poly, count):
    """Resample a polyline to `count` points evenly spaced by arc length."""
    lens = [0.0]
    for a, b in zip(poly, poly[1:]):
        lens.append(lens[-1] + (b - a).length)
    total = lens[-1]
    out = []
    j = 0
    for i in range(count):
        d = total * i / (count - 1)
        while j < len(lens) - 2 and lens[j + 1] < d:
            j += 1
        seg = lens[j + 1] - lens[j]
        u = (d - lens[j]) / seg if seg > 1e-9 else 0.0
        out.append(poly[j].lerp(poly[j + 1], u))
    return out


def frames_along(points, up_hint):
    """Parallel-transport frames (tangent, normal, binormal) along a polyline.

    `up_hint` (a Vector or a callable(i, point) -> Vector) seeds/steers the normal so flat
    cross-sections (hair locks, straps) lie the way the caller wants.
    """
    n = len(points)
    tangents = []
    for i in range(n):
        if i == 0:
            t = points[1] - points[0]
        elif i == n - 1:
            t = points[-1] - points[-2]
        else:
            t = points[i + 1] - points[i - 1]
        tangents.append(t.normalized())
    frames = []
    for i in range(n):
        up = up_hint(i, points[i]) if callable(up_hint) else Vector(up_hint)
        t = tangents[i]
        nrm = up - t * up.dot(t)
        if nrm.length < 1e-6:
            nrm = t.orthogonal()
        nrm.normalize()
        b = t.cross(nrm).normalized()
        frames.append((t, nrm, b))
    return frames


# --------------------------------------------------------------------------------------------
# object creation
# --------------------------------------------------------------------------------------------

def collection():
    col = bpy.data.collections.get("Moxie_parts")
    if col is None:
        col = bpy.data.collections.new("Moxie_parts")
        bpy.context.scene.collection.children.link(col)
    return col


def obj_from_bmesh(name, bm, material=None, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    collection().objects.link(obj)
    if material is not None:
        set_material(obj, material)
    if smooth:
        me.shade_smooth()
    return obj


def ring_points(center, xaxis, yaxis, rx, ry, n, shape=None, phase=0.0):
    """Ellipse ring; `shape(a)` scales the radius per angle (a=0 along +xaxis)."""
    pts = []
    for k in range(n):
        a = phase + TAU * k / n
        s = shape(a) if shape else 1.0
        pts.append(center + xaxis * (math.cos(a) * rx * s) + yaxis * (math.sin(a) * ry * s))
    return pts


def loft(name, rings, material=None, closed=True, cap_start=False, cap_end=False,
         cap_start_point=None, cap_end_point=None, smooth=True, uv=None):
    """Bridge consecutive rings (same vertex count) with quads.

    closed: rings wrap around. Caps fan to a centre point (better under subdivision than an ngon).
    uv(i_ring, k_vertex) -> (u, v) optional per-loop UVs.
    """
    bm = bmesh.new()
    n = len(rings[0])
    vs = [[bm.verts.new(p) for p in ring] for ring in rings]
    uv_layer = bm.loops.layers.uv.new("UVMap") if uv else None
    seg = n if closed else n - 1
    for i in range(len(rings) - 1):
        for k in range(seg):
            k2 = (k + 1) % n
            f = bm.faces.new((vs[i][k], vs[i][k2], vs[i + 1][k2], vs[i + 1][k]))
            if uv_layer:
                for loop, (ii, kk) in zip(f.loops, ((i, k), (i, k + 1), (i + 1, k + 1), (i + 1, k))):
                    loop[uv_layer].uv = uv(ii, kk)
    if closed:
        for idx, flag, pt in ((0, cap_start, cap_start_point), (len(rings) - 1, cap_end, cap_end_point)):
            if not flag:
                continue
            ring = vs[idx]
            c = pt if pt is not None else sum((v.co for v in ring), Vector()) / n
            cv = bm.verts.new(c)
            for k in range(n):
                bm.faces.new((ring[k], ring[(k + 1) % n], cv))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bmesh(name, bm, material, smooth)


def tube_along(name, path, radius_fn, n=10, material=None, up=V(0, 0, 1), shape=None,
               cap_start=True, cap_end=True, ry_fn=None, point_end=False):
    """Sweep an ellipse along a polyline. radius_fn(t)->rx ; ry_fn(t)->ry (defaults to rx).

    The ellipse's x axis is the frame normal (steered by `up`), y axis the binormal.
    point_end: the last ring collapses to the end point (tapered tip).
    """
    fr = frames_along(path, up)
    rings = []
    m = len(path)
    for i, (p, (t, nrm, b)) in enumerate(zip(path, fr)):
        u = i / (m - 1)
        rx = radius_fn(u)
        ry = ry_fn(u) if ry_fn else rx
        if point_end and i == m - 1:
            rx = ry = 1e-4
        rings.append(ring_points(p, nrm, b, rx, ry, n, shape))
    return loft(name, rings, material, closed=True, cap_start=cap_start,
                cap_end=cap_end and not point_end, cap_start_point=path[0], cap_end_point=path[-1])


def lathe(name, profile, n=16, material=None, center=V(0, 0, 0), axis_mat=None, cap_start=True,
          cap_end=True):
    """Revolve [(radius, height), ...] around the local Z axis, then transform by axis_mat."""
    rings = []
    for r, h in profile:
        rings.append(ring_points(V(0, 0, h), V(1, 0, 0), V(0, 1, 0), max(r, 1e-4), max(r, 1e-4), n))
    obj = loft(name, rings, material, closed=True, cap_start=cap_start, cap_end=cap_end,
               cap_start_point=V(0, 0, profile[0][1]), cap_end_point=V(0, 0, profile[-1][1]))
    m = axis_mat if axis_mat is not None else Matrix.Identity(4)
    obj.data.transform(Matrix.Translation(center) @ m)
    return obj


def rounded_box(name, size, bevel=0.004, segments=1, material=None, matrix=None, smooth=False):
    """Box of `size` (x, y, z) centred on the origin with bevelled edges, transformed by matrix."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = V(v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) * 0.45),
                        segments=segments, affect='EDGES', profile=0.5)
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
    obj = obj_from_bmesh(name, bm, material, smooth=True)
    if not smooth:
        obj.data.set_sharp_from_angle(angle=math.radians(35))
    return obj


def cylinder(name, radius, depth, n=12, material=None, matrix=None, bevel=0.0, smooth_angle=40):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=n, radius1=radius,
                          radius2=radius, depth=depth)
    if bevel > 0:
        rim = [e for e in bm.edges if not e.is_manifold or len(e.link_faces) == 2 and
               abs(e.link_faces[0].normal.z) != abs(e.link_faces[1].normal.z)]
        bmesh.ops.bevel(bm, geom=rim, offset=bevel, segments=2, affect='EDGES', profile=0.5)
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
    obj = obj_from_bmesh(name, bm, material, smooth=True)
    obj.data.set_sharp_from_angle(angle=math.radians(smooth_angle))
    return obj


def flat_strip(name, path, width_fn, thickness, up_fn, material=None, n_across=2):
    """A thin ribbon (straps, laces, graphics) swept along `path`, lying across `up_fn` normal.

    width is measured along the binormal (tangent x normal); thickness along the normal.
    """
    fr = frames_along(path, up_fn)
    m = len(path)
    rings = []
    for i, (p, (t, nrm, b)) in enumerate(zip(path, fr)):
        w = width_fn(i / (m - 1)) * 0.5
        h = thickness * 0.5
        rings.append([p + b * w + nrm * h, p - b * w + nrm * h, p - b * w - nrm * h, p + b * w - nrm * h])
    return loft(name, rings, material, closed=True, cap_start=True, cap_end=True, smooth=False)


def extrude_polygon(name, pts2d, depth, matrix, material=None, bevel=0.0):
    """Extrude a 2D polygon (list of (x, y), CCW) along local Z by depth, then transform."""
    bm = bmesh.new()
    bot = [bm.verts.new(V(x, y, 0)) for x, y in pts2d]
    top = [bm.verts.new(V(x, y, depth)) for x, y in pts2d]
    n = len(pts2d)
    bm.faces.new(list(reversed(bot)))
    bm.faces.new(top)
    for k in range(n):
        k2 = (k + 1) % n
        bm.faces.new((bot[k], bot[k2], top[k2], top[k]))
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=[e for e in bm.edges if len(e.link_faces) == 2 and
                                  e.calc_face_angle(0) > 0.6],
                        offset=bevel, segments=1, affect='EDGES')
    bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = obj_from_bmesh(name, bm, material, smooth=True)
    obj.data.set_sharp_from_angle(angle=math.radians(30))
    return obj


def basis(x, y, z, origin=V(0, 0, 0)):
    """4x4 matrix with the given column axes and translation."""
    m = Matrix.Identity(4)
    for r in range(3):
        m[r][0], m[r][1], m[r][2], m[r][3] = x[r], y[r], z[r], origin[r]
    return m


def look_basis(origin, forward, up):
    """Matrix whose local +Z = forward (normal), +Y = up projected, +X = Y x Z."""
    z = Vector(forward).normalized()
    y = Vector(up) - z * Vector(up).dot(z)
    y.normalize()
    x = y.cross(z)
    return basis(x, y, z, origin)


# --------------------------------------------------------------------------------------------
# modifiers / editing
# --------------------------------------------------------------------------------------------

def apply_modifiers(obj):
    with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj],
                                   selected_editable_objects=[obj]):
        for mod in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)


def subsurf(obj, levels=1, apply=True):
    mod = obj.modifiers.new("Subsurf", 'SUBSURF')
    mod.levels = levels
    mod.render_levels = levels
    mod.uv_smooth = 'PRESERVE_CORNERS'
    if apply:
        apply_modifiers(obj)
    return obj


def solidify(obj, thickness, offset=-1.0, material_offset=0, rim_material_offset=0, apply=True,
             even=True):
    mod = obj.modifiers.new("Solidify", 'SOLIDIFY')
    mod.thickness = thickness
    mod.offset = offset
    mod.use_even_offset = even
    mod.use_rim = True
    mod.material_offset = material_offset
    mod.material_offset_rim = rim_material_offset
    if apply:
        apply_modifiers(obj)
    return obj


def mirror_x(obj, apply=True, merge=0.0005):
    mod = obj.modifiers.new("Mirror", 'MIRROR')
    mod.use_axis[0] = True
    mod.use_clip = True
    mod.use_mirror_merge = True
    mod.merge_threshold = merge
    if apply:
        apply_modifiers(obj)
    return obj


def transform(obj, matrix):
    obj.data.transform(matrix)
    return obj


def duplicate(obj, name):
    o2 = obj.copy()
    o2.data = obj.data.copy()
    o2.name = name
    collection().objects.link(o2)
    return o2


def mirror_copy(obj, name):
    """Mirror a part across X (her left <-> right), fixing normals."""
    o2 = duplicate(obj, name)
    o2.data.transform(Matrix.Scale(-1, 4, V(1, 0, 0)))
    o2.data.flip_normals()
    return o2


def displace_verts(obj, fn):
    """fn(co: Vector) -> Vector (new position)."""
    for v in obj.data.vertices:
        v.co = fn(v.co.copy())
    obj.data.update()


def assign_material_by(obj, fn):
    """fn(face_center: Vector, normal: Vector) -> material name or None (keep)."""
    me = obj.data
    for poly in me.polygons:
        name = fn(poly.center.copy(), poly.normal.copy())
        if name is None:
            continue
        idx = slot_index(obj, name)
        poly.material_index = idx


def join(objs, name):
    target = objs[0]
    with bpy.context.temp_override(active_object=target, object=target, selected_objects=objs,
                                   selected_editable_objects=objs):
        bpy.ops.object.join()
    target.name = name
    target.data.name = name
    return target


# --------------------------------------------------------------------------------------------
# materials
# --------------------------------------------------------------------------------------------

def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgb(h):
    h = h.lstrip('#')
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


# Flat base colours (sRGB hex). R01 is the palette authority (requirements chapter 17).
PALETTE = {
    'skin': '#C68C62',
    'hair': '#4A2E24',
    'hair_dark': '#2C1A16',
    'shoes_dark': '#4A3328',
    'eye': '#251A1C',
    'face_paint': '#F3EADC',
    'headphones': '#F5B819',
    'headphones_glow': '#FFF1B8',
    'headphones_dark': '#2C2729',
    'top': '#EADFCC',
    'top_trim': '#2E292B',
    'top_graphic': '#CBBC9F',
    'jacket': '#3A2A26',
    'jacket_lining': '#E9A81C',
    'pants': '#5F5B3E',
    'pants_graphic': '#F0B21C',
    'strap': '#B3204C',
    'belt': '#3A3330',
    'walkman': '#F2B41A',
    'pouch': '#4A433E',
    'glove': '#2B2628',
    'wrist_device': '#3D3B40',
    'wrist_device_glow': '#62F2E6',
    'shoes': '#B8A48C',
    'shoes_lace': '#F5B819',
    'shoes_sole': '#E6DCC8',
    'dark': '#2E2320',
    'metal': '#A3A2A6',
}

EMISSIVE = {'headphones_glow', 'wrist_device_glow'}


def get_material(name):
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    col = hex_rgb(PALETTE[name]) + (1.0,)
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = 0.8
    if name in EMISSIVE:
        bsdf.inputs["Emission Color"].default_value = col
        bsdf.inputs["Emission Strength"].default_value = 1.0
    mat.diffuse_color = col  # Workbench preview colour
    return mat


def set_material(obj, name):
    obj.data.materials.clear()
    obj.data.materials.append(get_material(name))


def slot_index(obj, name):
    mat = get_material(name)
    for i, m in enumerate(obj.data.materials):
        if m == mat:
            return i
    obj.data.materials.append(mat)
    return len(obj.data.materials) - 1


def add_material(obj, name):
    return slot_index(obj, name)


def conform(decal, target, normal, base=0.0006, thickness=None):
    """Wrap a flat extruded decal (built by extrude_polygon with plane normal `normal`) onto the
    surface of `target`: every vertex is moved to the nearest point of the target's surface and
    pushed out along the surface normal - the back layer by `base`, the front layer by
    `base + thickness` - so the decal hugs curved cloth instead of floating off it."""
    from mathutils.bvhtree import BVHTree
    me = target.data
    tree = BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    nrm = Vector(normal).normalized()
    hs = [v.co.dot(nrm) for v in decal.data.vertices]
    lo, hi = min(hs), max(hs)
    th = thickness if thickness is not None else (hi - lo)
    for v, h in zip(decal.data.vertices, hs):
        loc, n, _i, _d = tree.find_nearest(v.co)
        if loc is None:
            continue
        if n.dot(nrm) < 0:
            n = -n
        layer = (h - lo) / (hi - lo) if hi - lo > 1e-9 else 0.0
        v.co = loc + n * (base + layer * th)
    decal.data.update()
    return decal
