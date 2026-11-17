"""Build-time integrity check: no floating parts.

Every modelled part (before the parts are joined into the single skinned mesh) must be attached
to the body: its surface has to intersect, or come within `tol` of, another part that is itself
attached. Parts are graph nodes, contacts are edges, and everything not connected to the torso
is reported as floating. build.py refuses to export while anything floats - this is what catches
decals or strap tips that drift off the cloth they belong to.
"""
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def _islands(obj):
    """Split a part into its connected pieces: (name, BVH tree, vertex list) per piece."""
    me = obj.data
    parent = list(range(len(me.vertices)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for p in me.polygons:
        r = find(p.vertices[0])
        for v in p.vertices[1:]:
            parent[find(v)] = r
    groups = {}
    for p in me.polygons:
        groups.setdefault(find(p.vertices[0]), []).append(tuple(p.vertices))
    out = []
    for k, (root, polys) in enumerate(sorted(groups.items(), key=lambda kv: -len(kv[1]))):
        ids = sorted({v for poly in polys for v in poly})
        remap = {v: i for i, v in enumerate(ids)}
        verts = [me.vertices[v].co.copy() for v in ids]
        tree = BVHTree.FromPolygons(verts, [tuple(remap[v] for v in poly) for poly in polys])
        out.append((obj.name if k == 0 else "%s#%d" % (obj.name, k), tree, verts))
    return out


def _bbox(verts, pad):
    lo = Vector((min(v.x for v in verts), min(v.y for v in verts), min(v.z for v in verts)))
    hi = Vector((max(v.x for v in verts), max(v.y for v in verts), max(v.z for v in verts)))
    return lo - Vector((pad, pad, pad)), hi + Vector((pad, pad, pad))


def _boxes_touch(a, b):
    return all(a[0][k] <= b[1][k] and b[0][k] <= a[1][k] for k in range(3))


def floating_parts(parts, tol=0.002, root_name="torso"):
    data = []
    for p in parts:
        for name, tree, verts in _islands(p):
            data.append((name, tree, verts, _bbox(verts, tol)))
    n = len(data)
    adj = [set() for _ in range(n)]
    for i in range(n):
        pi, ti, vi, bi = data[i]
        for j in range(i + 1, n):
            pj, tj, vj, bj = data[j]
            if not _boxes_touch(bi, bj):
                continue
            touch = bool(ti.overlap(tj))
            if not touch:
                for verts, tree in ((vi, tj), (vj, ti)):
                    for v in verts:
                        if tree.find_nearest(v, tol)[0] is not None:
                            touch = True
                            break
                    if touch:
                        break
            if touch:
                adj[i].add(j)
                adj[j].add(i)
    root = next((k for k in range(n) if data[k][0] == root_name), 0)
    seen = {root}
    stack = [root]
    while stack:
        k = stack.pop()
        for m in adj[k]:
            if m not in seen:
                seen.add(m)
                stack.append(m)
    out = [data[k][0] for k in range(n) if k not in seen]
    for k in range(n):
        if k in seen:
            continue
        # report the closest attached part, to make the fix obvious
        pk, tk, vk, bk = data[k]
        best = (1e9, "")
        for m in seen:
            pm, tm, vm, bm = data[m]
            for v in vk[::max(1, len(vk) // 60)]:
                hit = tm.find_nearest(v)
                if hit[0] is not None and hit[3] < best[0]:
                    best = (hit[3], pm)
        print("  floating %-20s nearest attached part %s at %.4f m" % (pk, best[1], best[0]))
    return out
