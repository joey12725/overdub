"""Hair clump generator: sweeps a tapered lens-shaped section along a smooth path (strand clumps as
real geometry, not cards), with UVs (u across the clump, v root -> tip) for a strand gradient texture."""
import bpy, bmesh, math, random
from mathutils import Vector


def catmull(pts, n):
    """Resample a polyline of Vectors with a centripetal-ish Catmull-Rom spline into n+1 points."""
    P = [pts[0] + (pts[0] - pts[1])] + list(pts) + [pts[-1] + (pts[-1] - pts[-2])]
    segs = len(pts) - 1
    out = []
    for i in range(n + 1):
        u = i / n * segs
        k = min(int(u), segs - 1)
        t = u - k
        p0, p1, p2, p3 = P[k], P[k + 1], P[k + 2], P[k + 3]
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    return out


def width_profile(t, root=0.55, power=2.0, belly=0.28):
    a = root + (1 - root) * min(t / belly, 1.0) ** 0.8
    return a * max(1.0 - t ** power, 0.0) ** 0.85


SECTION = [(0.5, 0.0), (0.24, 0.85), (-0.2, 1.0), (-0.5, 0.0), (-0.22, -0.42), (0.22, -0.42)]   # (across, up)


def add_clump(bm, uv, pts, normals, width, thick, segs=9, root=0.55, power=2.0, twist=0.0, belly=0.28, vshift=0.0, ridge=1.0):
    """pts: control points (Vectors) root -> tip; normals: per-control-point outward hints (or one Vector)."""
    path = catmull(pts, segs)
    if isinstance(normals, Vector):
        nh = [normals] * (segs + 1)
    else:
        nh = catmull(normals, segs)
    rings = []
    m = len(SECTION)
    for i, p in enumerate(path):
        t = i / segs
        tan = (path[min(i + 1, segs)] - path[max(i - 1, 0)]).normalized()
        n = nh[i] - tan * nh[i].dot(tan)
        if n.length < 1e-6:
            n = tan.orthogonal()
        n.normalize()
        b = tan.cross(n).normalized()
        if twist:
            a = twist * t
            n, b = n * math.cos(a) + b * math.sin(a), b * math.cos(a) - n * math.sin(a)
        w = width * width_profile(t, root, power, belly)
        th = thick * width_profile(t, max(root, 0.7), power, belly)
        if i == segs:
            rings.append([bm.verts.new(p)])
            continue
        ring = []
        for (a_, u_) in SECTION:
            ring.append(bm.verts.new(p + b * (a_ * w) + n * (u_ * th * (ridge if u_ > 0 else 1.0))))
        rings.append(ring)
    for i in range(segs):
        v0 = i / segs + vshift
        v1 = (i + 1) / segs + vshift
        r0, r1 = rings[i], rings[i + 1]
        for j in range(m):
            j2 = (j + 1) % m
            u0, u1 = j / m, (j + 1) / m
            if len(r1) == 1:
                f = bm.faces.new((r0[j], r0[j2], r1[0]))
                uvs = [(u0, v0), (u1, v0), ((u0 + u1) / 2, v1)]
            else:
                f = bm.faces.new((r0[j], r0[j2], r1[j2], r1[j]))
                uvs = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
            f.smooth = True
            for lp, q in zip(f.loops, uvs):
                lp[uv].uv = q
    f = bm.faces.new(rings[0][::-1])
    for lp in f.loops:
        lp[uv].uv = (0.5, vshift)
    return rings
