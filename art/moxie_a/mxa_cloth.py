"""Cloth helpers: shells lifted off the body (inheriting its skin weights), hem trims, weight sampling."""
import bpy, bmesh, math
from mathutils import Vector
from mathutils.kdtree import KDTree
import mxa_util as U
from mxa_build import MB, path_frames


class WeightSampler:
    """Skin weights of the nearest body vertices (inverse-distance blend), for gear and lofted cloth."""

    def __init__(self, obj):
        me = obj.data
        self.names = [g.name for g in obj.vertex_groups]
        self.w = []
        self.kd = KDTree(len(me.vertices))
        for v in me.vertices:
            self.kd.insert(v.co, v.index)
            self.w.append({self.names[g.group]: g.weight for g in v.groups if g.weight > 1e-4})
        self.kd.balance()

    def at(self, p, k=6, only=None, exclude=None):
        acc = {}
        for co, i, d in self.kd.find_n(p, k):
            f = 1.0 / (d * d + 1e-6)
            for n, w in self.w[i].items():
                if only and not any(n.startswith(o) or n == o for o in only):
                    continue
                if exclude and any(n.startswith(o) for o in exclude):
                    continue
                acc[n] = acc.get(n, 0) + w * f
        tot = sum(acc.values())
        if tot <= 0:
            return {}
        acc = {n: w / tot for n, w in acc.items() if w / tot > 0.01}
        tot = sum(acc.values())
        return {n: w / tot for n, w in acc.items()}


def shell_from(body, name, keep_vert, material):
    """New object made of the body faces whose vertices all pass keep_vert(co); weights come along."""
    me = body.data.copy(); me.name = name
    ob = U.new_obj(name, me)
    for vg in body.vertex_groups:
        ob.vertex_groups.new(name=vg.name)
    bm = bmesh.new(); bm.from_mesh(me)
    dele = [f for f in bm.faces if not all(keep_vert(v.co) for v in f.verts)]
    bmesh.ops.delete(bm, geom=dele, context='FACES')
    # the VRoid body is triangle soup split along UV seams: weld it and rebuild quads
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=1e-5)
    bmesh.ops.join_triangles(bm, faces=list(bm.faces), angle_face_threshold=math.radians(60),
                             angle_shape_threshold=math.radians(60))
    for f in bm.faces:
        f.material_index = 0
        f.smooth = True
    bm.to_mesh(me); bm.free()
    me.materials.clear(); me.materials.append(U.mat(material))
    # the copied custom normals no longer describe the reshaped cloth
    try:
        U.active(ob); bpy.ops.mesh.customdata_custom_splitnormals_clear()
    except Exception:
        pass
    return ob


def cut_object(ob, field, delete_outside=True, inside_mat=None, faces_filter=None):
    """Cut an object along the zero line of field(co) (positive = keep / inside)."""
    bm = bmesh.new(); bm.from_mesh(ob.data)
    fs = [f for f in bm.faces if (faces_filter is None or faces_filter(f))]
    ins, outs = U.split_by_field(bm, fs, lambda v: field(v.co))
    if inside_mat is not None:
        i = U.mat_slot(ob, U.mat(inside_mat))
        for f in ins:
            f.material_index = i
    if delete_outside:
        bmesh.ops.delete(bm, geom=outs, context='FACES')
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(ob.data); bm.free()


def displace(ob, fn):
    """co' = fn(co, normal) for every vertex."""
    me = ob.data
    nrm = [v.normal.copy() for v in me.vertices]
    for v, n in zip(me.vertices, nrm):
        v.co = fn(v.co.copy(), n)
    me.update()


def subsurf(ob, levels=1):
    U.active(ob)
    md = ob.modifiers.new('ss', 'SUBSURF'); md.levels = levels; md.render_levels = levels
    md.boundary_smooth = 'PRESERVE_CORNERS'
    bpy.ops.object.modifier_apply(modifier='ss')


def smooth_verts(ob, iters=2, factor=0.5, keep_border=True):
    bm = bmesh.new(); bm.from_mesh(ob.data)
    vs = [v for v in bm.verts if not (keep_border and v.is_boundary)]
    for _ in range(iters):
        bmesh.ops.smooth_vert(bm, verts=vs, factor=factor, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bm.to_mesh(ob.data); bm.free()


def border_loops(ob):
    """Ordered boundary loops as lists of vertex indices."""
    bm = bmesh.new(); bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    edges = [e for e in bm.edges if e.is_boundary]
    nxt = {}
    for e in edges:
        a, b = e.verts[0].index, e.verts[1].index
        nxt.setdefault(a, []).append(b); nxt.setdefault(b, []).append(a)
    seen = set(); loops = []
    for start in list(nxt):
        if start in seen:
            continue
        loop = [start]; seen.add(start); cur = start; prev = None
        while True:
            cand = [n for n in nxt[cur] if n != prev and n not in seen]
            if not cand:
                break
            prev, cur = cur, cand[0]
            loop.append(cur); seen.add(cur)
        loops.append(loop)
    bm.free()
    return loops


def trim_loop(mb, ob, loop, radius, m, sides=6, scale_y=1.0, push=0.0, min_len=0.0, closed=True, weights=None):
    """Add a rolled hem (a tube) along one ordered border loop of `ob`. Ring weights are copied from
    the cloth vertices so the hem deforms with the cloth."""
    me = ob.data
    names = [g.name for g in ob.vertex_groups]
    # drop vertices that are too close together (cut borders can be very dense)
    pts = []; idx = []
    for i in loop:
        co = me.vertices[i].co
        if pts and (co - pts[-1]).length < min_len:
            continue
        pts.append(co.copy()); idx.append(i)
    if closed and len(pts) > 2 and (pts[0] - pts[-1]).length < min_len:
        pts.pop(); idx.pop()
    if len(pts) < 3:
        return
    n = len(pts)
    rings = []
    for k in range(n):
        a = pts[(k - 1) % n] if (closed or k > 0) else pts[k]
        b = pts[(k + 1) % n] if (closed or k < n - 1) else pts[k]
        T = (b - a).normalized()
        N = me.vertices[idx[k]].normal.copy()
        N = (N - T * N.dot(T)).normalized()
        S = T.cross(N).normalized()
        v = me.vertices[idx[k]]
        w = weights if weights is not None else {names[g.group]: g.weight for g in v.groups if g.weight > 1e-4}
        c = pts[k] + N * push
        rings.append(mb.ring(c, S, N, [(math.cos(2 * math.pi * j / sides) * radius * scale_y,
                                        math.sin(2 * math.pi * j / sides) * radius) for j in range(sides)], w))
    mb.loft(rings, m)
    if closed:
        mb.loft([rings[-1], rings[0]], m)
    else:
        mb.face(rings[0][::-1], m); mb.face(rings[-1], m)


def delete_faces(ob, pred):
    """Delete faces whose centre passes pred(co)."""
    bm = bmesh.new(); bm.from_mesh(ob.data)
    dele = [f for f in bm.faces if pred(f.calc_center_median())]
    bmesh.ops.delete(bm, geom=dele, context='FACES')
    bm.to_mesh(ob.data); bm.free()
