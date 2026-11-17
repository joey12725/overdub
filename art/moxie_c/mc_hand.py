"""Hands: five articulated fingers on a quad cage (20-vert palm rings, 8-vert finger tubes sharing
web vertices at the knuckles, thumb bridged into the side of the palm), shaped by an SDF.
Built for the left hand (+X, palm down, thumb forward = -Y); the right is mirrored."""
import math

import bmesh
import bpy
import numpy as np

from mc_util import (V, Mesh, boundary_verts, get_co, laplacian_fast, norm, rot_axis, sd_box,
                     sd_cone, sd_ellipsoid, sdf_normal, sdf_project, set_co, smin, subsurf,
                     to_object)

WRIST_X = 0.612
Z0 = 1.300
Y0 = 0.008

FINGERS = {  # base, yaw (deg, + = toward the back / pinky side), segment lengths, base radius
    "Index": (V(0.6925, Y0 - 0.0270, Z0 + 0.0000), -5.0, (0.0300, 0.0205, 0.0170), 0.0086),
    "Middle": (V(0.6965, Y0 - 0.0085, Z0 + 0.0010), 0.0, (0.0325, 0.0225, 0.0180), 0.0088),
    "Ring": (V(0.6925, Y0 + 0.0100, Z0 + 0.0000), 5.0, (0.0300, 0.0205, 0.0170), 0.0084),
    "Little": (V(0.6850, Y0 + 0.0270, Z0 - 0.0015), 11.0, (0.0235, 0.0160, 0.0150), 0.0076),
}
CURL = (9.0, 13.0, 11.0)
THUMB = (V(0.6260, Y0 - 0.0260, Z0 - 0.0040), -42.0, (0.0330, 0.0280, 0.0235), 0.0112)
THUMB_CURL = (16.0, 6.0, 8.0)


def chain(base, yaw, lens, curls):
    """Joint positions of a finger: 4 points (3 segments)."""
    pts = [np.array(base)]
    pitch = 0.0
    y = math.radians(yaw)
    for ln, c in zip(lens, curls):
        pitch += math.radians(c)
        d = V(math.cos(y) * math.cos(pitch), math.sin(y) * math.cos(pitch), -math.sin(pitch))
        pts.append(pts[-1] + d * ln)
    return np.array(pts)


def joints_left():
    """Finger joint chains for the rig (left hand, world space)."""
    out = {k: chain(b, yw, ln, CURL) for k, (b, yw, ln, r) in FINGERS.items()}
    out["Thumb"] = chain(THUMB[0], THUMB[1], THUMB[2], THUMB_CURL)
    return out


def hand_sdf(p):
    palm = sd_box(p, V(0.652, Y0 - 0.002, Z0), V(0.044, 0.0360, 0.0120), 0.0115)
    wrist = sd_cone(p, V(0.560, 0.010, Z0), V(0.625, 0.009, Z0), 0.0228, 0.0215, scale=(1, 1, 0.9))
    d = smin(palm, wrist, 0.016)
    thenar = sd_ellipsoid(p, V(0.640, Y0 - 0.026, Z0 - 0.006), V(0.026, 0.014, 0.012))
    d = smin(d, thenar, 0.010)
    knuck = sd_cone(p, V(0.690, Y0 - 0.027, Z0 + 0.002), V(0.684, Y0 + 0.027, Z0 + 0.001), 0.0100,
                    0.0090)
    d = smin(d, knuck, 0.008)
    f = None
    for name, (b, yw, ln, r) in FINGERS.items():
        c = chain(b, yw, ln, CURL)
        rr = [r, r * 0.93, r * 0.84, r * 0.74]
        for i in range(3):
            s = sd_cone(p, c[i], c[i + 1], rr[i], rr[i + 1])
            f = s if f is None else np.minimum(f, s)
    d = smin(d, f, 0.005)
    c = chain(THUMB[0], THUMB[1], THUMB[2], THUMB_CURL)
    r = THUMB[3]
    rr = [r * 1.12, r, r * 0.90, r * 0.74]
    t = None
    for i in range(3):
        s = sd_cone(p, c[i], c[i + 1], rr[i], rr[i + 1])
        t = s if t is None else smin(t, s, 0.003)
    d = smin(d, t, 0.007)
    return d


def _ring(c, d, r, n=8):
    side = norm(np.cross(V(0, 0, 1), d))
    up = np.cross(d, side)
    out = []
    for k in range(n):
        a = math.radians(-45 + 45 * k)
        out.append(c + r * (math.cos(a) * up + math.sin(a) * side))
    return out


def build_hand_left():
    verts, faces, tag = [], [], []     # tag: (finger name or None)

    def add(p, t=None):
        verts.append(np.array(p, dtype=float))
        tag.append(t)
        return len(verts) - 1

    xs = [WRIST_X, 0.630, 0.650, 0.670, 0.690]
    rings = []
    names = list(FINGERS.keys())
    ys_centre = [FINGERS[n][0][1] for n in names]
    # 9 column y positions: gaps and centres
    cols = []
    for i in range(4):
        left = ys_centre[i] - 0.0095 if i == 0 else 0.5 * (ys_centre[i - 1] + ys_centre[i])
        cols += [left, ys_centre[i]]
    cols.append(ys_centre[3] + 0.0090)
    cols = np.array(cols)
    for ri, x in enumerate(xs):
        s = 0.62 + 0.38 * min(1.0, ri / 2.0)          # narrower toward the wrist
        T = [add((x, Y0 + (y - Y0) * s, Z0 + 0.012)) for y in cols]
        Sb = add((x, Y0 + (cols[-1] - Y0) * s + 0.004, Z0))
        B = [add((x, Y0 + (y - Y0) * s, Z0 - 0.012)) for y in cols]
        Sf = add((x, Y0 + (cols[0] - Y0) * s - 0.004, Z0))
        rings.append((T, Sb, B, Sf))

    def ring_loop(r):
        T, Sb, B, Sf = r
        return T + [Sb] + B[::-1] + [Sf]
    thumb_hole = set()
    for ri in range(len(xs) - 1):
        a, b = ring_loop(rings[ri]), ring_loop(rings[ri + 1])
        n = len(a)
        for k in range(n):
            # the two faces touching Sf (front side) on rows 1-2 and 2-3 are the thumb opening
            if ri in (1, 2) and k in (n - 2, n - 1):
                continue
            faces.append((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
    # fingers
    T4, Sb4, B4, Sf4 = rings[-1]
    webs = [Sf4]
    for i in range(1, 4):
        webs.append(add((xs[-1] + 0.001, cols[2 * i], Z0)))
    webs.append(Sb4)
    for i, nm in enumerate(names):
        b, yw, ln, r = FINGERS[nm]
        c = chain(b, yw, ln, CURL)
        prev = [T4[2 * i], T4[2 * i + 1], T4[2 * i + 2], webs[i + 1], B4[2 * i + 2], B4[2 * i + 1],
                B4[2 * i], webs[i]]
        # ring stations along the finger: (segment, t)
        stations = [(0, 0.30), (0, 0.62), (0, 0.90), (1, 0.12), (1, 0.50), (1, 0.88), (2, 0.14),
                    (2, 0.50), (2, 0.78), (2, 1.0)]
        rr = [r, r * 0.93, r * 0.84, r * 0.74]
        for (sg, t) in stations:
            cpt = c[sg] + (c[sg + 1] - c[sg]) * t
            d = norm(c[sg + 1] - c[sg])
            rad = rr[sg] + (rr[sg + 1] - rr[sg]) * t
            ring = [add(p, nm) for p in _ring(cpt, d, rad)]
            for k in range(8):
                faces.append((prev[k], prev[(k + 1) % 8], ring[(k + 1) % 8], ring[k]))
            prev = ring
        d = norm(c[3] - c[2])
        tip = add(c[3] + d * rr[3] * 1.0, nm)
        for k in range(0, 8, 2):
            faces.append((prev[k], prev[(k + 1) % 8], prev[(k + 2) % 8], tip))
    # thumb
    (T1, _, B1, S1), (T2, _, B2, S2), (T3, _, B3, S3) = rings[1], rings[2], rings[3]
    prev = [T1[0], T2[0], T3[0], S3, B3[0], B2[0], B1[0], S1]
    c = chain(THUMB[0], THUMB[1], THUMB[2], THUMB_CURL)
    r = THUMB[3]
    rr = [r * 1.12, r, r * 0.90, r * 0.74]
    stations = [(0, 0.72), (0, 0.95), (1, 0.20), (1, 0.55), (1, 0.88), (2, 0.14), (2, 0.50), (2, 0.78), (2, 1.0)]
    for (sg, t) in stations:
        cpt = c[sg] + (c[sg + 1] - c[sg]) * t
        d = norm(c[sg + 1] - c[sg])
        rad = rr[sg] + (rr[sg + 1] - rr[sg]) * t
        ring = [add(p, "Thumb") for p in _ring(cpt, d, rad)]
        for k in range(8):
            faces.append((prev[k], prev[(k + 1) % 8], ring[(k + 1) % 8], ring[k]))
        prev = ring
    d = norm(c[3] - c[2])
    tip = add(c[3] + d * rr[3] * 1.0, "Thumb")
    for k in range(0, 8, 2):
        faces.append((prev[k], prev[(k + 1) % 8], prev[(k + 2) % 8], tip))

    m = Mesh()
    m.add(np.array(verts), faces, "skin")
    ob = to_object("HandL", m)
    # finger tags as vertex groups (they survive subdivision and drive the skin weights)
    for nm in names + ["Thumb"]:
        g = ob.vertex_groups.new(name="tag_" + nm)
        idx = [i for i, t in enumerate(tag) if t == nm]
        g.add(idx, 1.0, 'REPLACE')
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data)
    bm.free()

    def proj(iters):
        co = get_co(ob)
        b = boundary_verts(ob.data)
        new = sdf_project(hand_sdf, co, iters=iters)
        new[b, 0] = WRIST_X
        set_co(ob, new)
    proj(10)
    co = get_co(ob)
    b = boundary_verts(ob.data)
    palm = (co[:, 0] < 0.70)
    for _ in range(4):
        new = laplacian_fast(co, ob.data, mask=(~b) & palm, k=0.3)
        new[~b] = sdf_project(hand_sdf, new[~b], iters=3)
        co = new
    set_co(ob, co)
    subsurf(ob, 1)
    proj(6)
    return ob


def mirror_object(ob, name):
    new = ob.copy()
    new.data = ob.data.copy()
    new.name = name
    new.data.name = name
    bpy.context.scene.collection.objects.link(new)
    co = get_co(new)
    co[:, 0] *= -1
    set_co(new, co)
    new.data.flip_normals()
    new.data.update()
    return new
