"""Procedural mesh builder used by the hair / outfit / gear stages (Blender 4.5)."""
import bpy, math
from mathutils import Vector
from mxa_util import mat, new_obj, active


def catmull(ctrl, n):
    """Sample a Catmull-Rom spline through `ctrl` (Vectors) at n+1 points."""
    P = [Vector(c) for c in ctrl]
    P = [P[0] + (P[0] - P[1])] + P + [P[-1] + (P[-1] - P[-2])]
    segs = len(P) - 3
    out = []
    for i in range(n + 1):
        t = i / n * segs
        k = min(int(t), segs - 1); u = t - k
        p0, p1, p2, p3 = P[k], P[k + 1], P[k + 2], P[k + 3]
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u
                          + (-p0 + 3 * p1 - 3 * p2 + p3) * u ** 3))
    return out


def resample(pts, n):
    """Resample a polyline to n+1 points evenly spaced by arc length."""
    d = [0.0]
    for a, b in zip(pts, pts[1:]):
        d.append(d[-1] + (b - a).length)
    out = []
    j = 0
    for i in range(n + 1):
        s = d[-1] * i / n
        while j < len(pts) - 2 and d[j + 1] < s:
            j += 1
        u = (s - d[j]) / max(1e-9, d[j + 1] - d[j])
        out.append(pts[j].lerp(pts[j + 1], u))
    return out


def path_frames(path, up=None):
    """(T, N, S) per point; N is kept close to `up` (Vector or callable(i, p) -> Vector)."""
    out = []
    prevN = None
    for i, p in enumerate(path):
        a = path[max(0, i - 1)]; b = path[min(len(path) - 1, i + 1)]
        T = (b - a).normalized()
        u = up(i, p) if callable(up) else (up or prevN or Vector((0, 0, 1)))
        N = u - T * u.dot(T)
        if N.length < 1e-5:
            q = prevN or Vector((1, 0, 0))
            N = q - T * q.dot(T)
            if N.length < 1e-5:
                N = T.orthogonal()
        N.normalize()
        S = T.cross(N).normalized()
        out.append((T, N, S)); prevN = N
    return out


class MB:
    """Accumulates vertices (with skin weights), faces and material names, then builds an object."""

    def __init__(self):
        self.v = []; self.w = []; self.f = []; self.fm = []

    def vert(self, co, w):
        self.v.append(Vector(co)); self.w.append(w)
        return len(self.v) - 1

    def face(self, idx, m):
        self.f.append(tuple(idx)); self.fm.append(m)

    def loft(self, rings, m, closed=True, cap0=False, cap1=False, flip=False):
        """rings: lists of vertex indices (same length). Quads between consecutive rings."""
        n = len(rings[0])
        for a, b in zip(rings, rings[1:]):
            rng = range(n) if closed else range(n - 1)
            for i in rng:
                j = (i + 1) % n
                q = (a[i], a[j], b[j], b[i])
                self.face(q[::-1] if flip else q, m)
        if cap0:
            self.face(rings[0] if flip else rings[0][::-1], m if cap0 is True else cap0)
        if cap1:
            self.face(rings[-1][::-1] if flip else rings[-1], m if cap1 is True else cap1)

    def ring(self, c, X, Y, pts, w):
        return [self.vert(c + X * u + Y * v, w) for u, v in pts]

    def tube(self, path, radius, m, w, sides=8, up=None, cap0=True, cap1=True, scale_y=1.0):
        """Round tube along a polyline. radius: float or callable(t). w: dict or callable(t, p)."""
        frames = path_frames(path, up)
        rings = []
        n = len(path) - 1
        for i, (p, (T, N, S)) in enumerate(zip(path, frames)):
            t = i / max(1, n)
            r = radius(t) if callable(radius) else radius
            ww = w(t, p) if callable(w) else w
            pts = [(math.cos(2 * math.pi * k / sides) * r, math.sin(2 * math.pi * k / sides) * r * scale_y)
                   for k in range(sides)]
            rings.append(self.ring(p, S, N, pts, ww))
        self.loft(rings, m, cap0=cap0, cap1=cap1)
        return rings

    def strip(self, path, section, m, w, up=None, cap0=True, cap1=True, width=None, flip=False):
        """Loft an arbitrary closed section (list of (u, v)) along a path. width: callable(t) ->
        (su, sv) scale of the section. Returns rings."""
        frames = path_frames(path, up)
        rings = []
        n = len(path) - 1
        for i, (p, (T, N, S)) in enumerate(zip(path, frames)):
            t = i / max(1, n)
            su, sv = width(t) if width else (1, 1)
            ww = w(t, p) if callable(w) else w
            rings.append(self.ring(p, S, N, [(u * su, v * sv) for u, v in section], ww))
        self.loft(rings, m, cap0=cap0, cap1=cap1, flip=flip)
        return rings

    def box(self, c, X, Y, Z, m, w, bevel=0.0, mats=None):
        """Chamfered box centred at c with half-extent vectors X, Y, Z. mats: optional dict keyed
        '+x','-x','+y','-y','+z','-z' (and 'e' for the chamfers)."""
        mats = mats or {}
        c = Vector(c)
        hx, hy, hz = X.length, Y.length, Z.length
        ux, uy, uz = X.normalized(), Y.normalized(), Z.normalized()
        b = min(bevel, hx * 0.9, hy * 0.9, hz * 0.9)
        idx = {}
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    base = c + ux * sx * hx + uy * sy * hy + uz * sz * hz
                    if b <= 0:
                        i = self.vert(base, w)
                        idx[(sx, sy, sz, 'x')] = idx[(sx, sy, sz, 'y')] = idx[(sx, sy, sz, 'z')] = i
                    else:
                        idx[(sx, sy, sz, 'x')] = self.vert(base - uy * sy * b - uz * sz * b, w)
                        idx[(sx, sy, sz, 'y')] = self.vert(base - ux * sx * b - uz * sz * b, w)
                        idx[(sx, sy, sz, 'z')] = self.vert(base - ux * sx * b - uy * sy * b, w)

        def poly(q, key, n):
            p = [self.v[i] for i in q]
            if (p[1] - p[0]).cross(p[2] - p[0]).dot(n) < 0:
                q = q[::-1]
            self.face(q, mats.get(key, m))
        for s in (-1, 1):
            poly([idx[(s, -1, -1, 'x')], idx[(s, 1, -1, 'x')], idx[(s, 1, 1, 'x')], idx[(s, -1, 1, 'x')]], '+x' if s > 0 else '-x', ux * s)
            poly([idx[(-1, s, -1, 'y')], idx[(1, s, -1, 'y')], idx[(1, s, 1, 'y')], idx[(-1, s, 1, 'y')]], '+y' if s > 0 else '-y', uy * s)
            poly([idx[(-1, -1, s, 'z')], idx[(1, -1, s, 'z')], idx[(1, 1, s, 'z')], idx[(-1, 1, s, 'z')]], '+z' if s > 0 else '-z', uz * s)
        if b > 0:
            for sy in (-1, 1):
                for sz in (-1, 1):
                    poly([idx[(-1, sy, sz, 'y')], idx[(1, sy, sz, 'y')], idx[(1, sy, sz, 'z')], idx[(-1, sy, sz, 'z')]], 'e', uy * sy + uz * sz)
            for sx in (-1, 1):
                for sz in (-1, 1):
                    poly([idx[(sx, -1, sz, 'x')], idx[(sx, 1, sz, 'x')], idx[(sx, 1, sz, 'z')], idx[(sx, -1, sz, 'z')]], 'e', ux * sx + uz * sz)
            for sx in (-1, 1):
                for sy in (-1, 1):
                    poly([idx[(sx, sy, -1, 'x')], idx[(sx, sy, 1, 'x')], idx[(sx, sy, 1, 'y')], idx[(sx, sy, -1, 'y')]], 'e', ux * sx + uy * sy)
            for sx in (-1, 1):
                for sy in (-1, 1):
                    for sz in (-1, 1):
                        poly([idx[(sx, sy, sz, 'x')], idx[(sx, sy, sz, 'y')], idx[(sx, sy, sz, 'z')]], 'e', ux * sx + uy * sy + uz * sz)

    def disc(self, c, X, Y, r, m, w, sides=16, depth=None):
        """Flat disc (n-gon) or, with depth (Vector), a capped cylinder from c to c + depth."""
        pts = [(math.cos(2 * math.pi * k / sides) * r, math.sin(2 * math.pi * k / sides) * r) for k in range(sides)]
        a = self.ring(Vector(c), X.normalized(), Y.normalized(), pts, w)
        if depth is None:
            self.face(a, m)
            return a
        b = self.ring(Vector(c) + depth, X.normalized(), Y.normalized(), pts, w)
        n = X.cross(Y)
        flip = n.dot(depth) < 0
        self.loft([a, b], m, cap0=True, cap1=True, flip=flip)
        return a, b

    def build(self, name, weighted_normals=False, merge=0.0):
        me = bpy.data.meshes.new(name)
        me.from_pydata([v[:] for v in self.v], [], self.f)
        ob = new_obj(name, me)
        names = []
        for m in self.fm:
            if m not in names:
                names.append(m)
        for nme in names:
            me.materials.append(mat(nme))
        for p, m in zip(me.polygons, self.fm):
            p.material_index = names.index(m)
            p.use_smooth = True
        groups = {}
        for i, w in enumerate(self.w):
            for g, x in w.items():
                if x <= 0:
                    continue
                vg = groups.get(g)
                if vg is None:
                    vg = groups[g] = ob.vertex_groups.new(name=g)
                vg.add([i], x, 'REPLACE')
        me.update()
        if weighted_normals:
            active(ob)
            md = ob.modifiers.new('wn', 'WEIGHTED_NORMAL'); md.keep_sharp = False; md.weight = 50
            bpy.ops.object.modifier_apply(modifier='wn')
        return ob


def add_bone(rig, name, head, tail, parent, deform=True):
    active(rig, 'EDIT')
    eb = rig.data.edit_bones.new(name)
    eb.head = head; eb.tail = tail
    eb.parent = rig.data.edit_bones[parent]
    eb.use_connect = False
    eb.use_deform = deform
    bpy.ops.object.mode_set(mode='OBJECT')


def chain_weights(t, names, root=None, root_blend=0.12):
    """Smooth weights along a bone chain for a point at fraction t (0..1) of the chain length."""
    n = len(names)
    s = t * n
    w = {}
    for i, nm in enumerate(names):
        x = 1 - abs(s - (i + 0.5))
        if i == 0 and s < 0.5:
            x = 1.0
        if i == n - 1 and s > n - 0.5:
            x = 1.0
        if x > 0:
            w[nm] = x
    if root and t < root_blend:
        k = 1 - t / root_blend
        w = {a: b * (1 - k) for a, b in w.items()}
        w[root] = w.get(root, 0) + k
    tot = sum(w.values())
    return {a: b / tot for a, b in w.items()}
