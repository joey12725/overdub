"""Hair: a scalp shell plus sculpted, tapered strand clumps (bangs, side locks, swept-back
sections converging on two high scrappy pigtails, flyaways). Head-local build, moved to world."""
import math

import numpy as np

from mc_head import HEAD_C, head_sdf
from mc_util import (V, Mesh, Rand, catmull, loft, norm, resample, rot_axis, sdf_march, to_object,
                     torus, get_co, set_co)

C0 = V(0.0, 0.005, 0.0)                       # ray origin for the spherical head parametrisation
TIE = V(0.102, 0.072, 0.058)                  # left pigtail tie (head-local); right is mirrored
PIG_DIR = norm(V(0.80, 0.58, 0.10))

# cross-section of a clump: x across (-1..1), y outward. A soft ridge with crisp side edges.
SECTION = np.array([(-1.0, 0.0), (-0.55, 0.62), (0.0, 0.9), (0.55, 0.62), (1.0, 0.0),
                    (0.45, -0.28), (-0.45, -0.28)])


def sph(phi, theta):
    p, t = math.radians(phi), math.radians(theta)
    return V(math.sin(p) * math.sin(t), -math.cos(p) * math.sin(t), math.cos(t))


def surf(dirs, off=0.0):
    """Points on the head surface along unit directions from C0, pushed out by off (array ok)."""
    dirs = np.asarray(dirs).reshape(-1, 3)
    hit = sdf_march(_skull, C0 + dirs * 0.3, -dirs, tmax=0.3)
    off = np.broadcast_to(np.asarray(off, dtype=np.float64), (len(dirs),))
    return hit + dirs * off[:, None]


def _skull(p):
    """Head without the neck dip: hair should not follow the neck inwards."""
    return head_sdf(p)


def strand(mesh, path, normals, width, thick, mat, n=10, root_w=0.55, peak=0.3, tip_pow=1.5,
           twist=0.0, section=SECTION):
    """Sweep a tapered clump along path (k,3) with outward normals (k,3)."""
    path = np.asarray(path)
    k = len(path)
    pts = catmull(path, n)
    nr = catmull(normals, n)
    t = np.linspace(0, 1, n)
    tang = np.gradient(pts, axis=0)
    tang = norm(tang)
    nr = nr - tang * (nr * tang).sum(axis=1, keepdims=True)
    nr = norm(nr)
    bn = np.cross(tang, nr)
    w = np.where(t < peak, root_w + (1 - root_w) * np.sin(0.5 * math.pi * t / peak),
                 np.maximum(1 - ((t - peak) / (1 - peak)) ** tip_pow, 0.0) ** 0.8)
    w = np.maximum(w, 0.03)
    rings = np.empty((n, len(section), 3))
    for i in range(n):
        Ni, Bi = nr[i], bn[i]
        if twist:
            Rm = rot_axis(tang[i], twist * t[i])
            Ni, Bi = Rm @ Ni, Rm @ Bi
        th = thick * (0.55 + 0.45 * w[i]) * min(1.0, w[i] * 3.0)
        rings[i] = pts[i] + section[:, :1] * width * 0.5 * w[i] * Bi + section[:, 1:2] * th * Ni
    loft(rings, mat, mesh, cap0=True, cap1=True, flip=True)
    return pts


def _sph_path(keys):
    """keys: list of (phi, theta, off). Returns path points and outward normals."""
    keys = np.asarray(keys, dtype=np.float64)
    kk = catmull(keys, max(6, len(keys) * 2))
    dirs = np.array([sph(a, b) for a, b, _ in kk])
    pts = surf(dirs, kk[:, 2])
    return pts, dirs


def build_hair():
    rnd = Rand(7)
    m = Mesh()
    # ------------------------------------------------------------------ scalp shell
    NA, NT = 36, 9
    rings = []
    for j in range(NT + 1):
        row = []
        for i in range(NA):
            phi = 360.0 * i / NA
            a = abs(((phi + 180) % 360) - 180)
            # hairline as the polar angle limit per azimuth
            if a < 55:
                lim = 62 + 6 * (a / 55) ** 2
            elif a < 100:
                lim = 68 + (118 - 68) * ((a - 55) / 45) ** 1.2
            else:
                lim = 118 + 16 * min(1.0, (a - 100) / 50)
            th = max(1.5, lim * j / NT)
            row.append(sph(phi, th))
        rings.append(row)
    dirs = np.array(rings).reshape(-1, 3)
    pts = surf(dirs, 0.0085).reshape(NT + 1, NA, 3)
    loft(pts[1:], "hair_dark", m, cap0=True, flip=True)

    # ------------------------------------------------------------------ bangs
    def bang(p0, t0, p1, t1, w, lift=0.012, mat="hair", flick=0.004, thick=0.0055, mid=None):
        mp = (p0 + p1) / 2 if mid is None else mid
        keys = [(p0, t0, 0.0035), (lerpf(p0, mp, 0.6), lerpf(t0, t1, 0.33), lift * 0.9),
                (lerpf(mp, p1, 0.6), lerpf(t0, t1, 0.70), lift), (p1, t1, lift * 0.8 + flick)]
        pts, nr = _sph_path(keys)
        strand(m, pts, nr, w * 1.25, thick, mat, n=10, peak=0.25, tip_pow=2.3)

    def lerpf(a, b, t):
        return a + (b - a) * t
    front = [  # phi_root, theta_root, phi_tip, theta_tip, width
        (3, 20, -4, 108, 0.016), (-8, 23, -19, 92, 0.031), (-20, 25, -41, 100, 0.034),
        (-34, 27, -60, 95, 0.032), (-48, 30, -80, 110, 0.030), (10, 23, 17, 90, 0.031),
        (22, 25, 39, 98, 0.034), (36, 27, 58, 93, 0.032), (50, 30, 78, 108, 0.030)]
    for (a0, t0, a1, t1, w) in front:
        bang(a0, t0, a1 + rnd.n(2), t1 + rnd.n(2), w, lift=0.0165, flick=0.007)
    under = [(-3, 17, -11, 84, 0.030), (6, 17, 8, 82, 0.028), (30, 22, 47, 88, 0.032),
             (-28, 22, -49, 89, 0.032), (-58, 34, -86, 98, 0.030), (60, 34, 88, 98, 0.030),
             (16, 20, 28, 86, 0.028), (-14, 20, -30, 85, 0.028)]
    for (a0, t0, a1, t1, w) in under:
        bang(a0, t0, a1, t1, w, lift=0.0110, mat="hair_dark", flick=0.001)
    # side locks in front of the ears, down to the jaw
    for s in (1, -1):
        bang(s * 60, 40, s * 68, 132, 0.026, lift=0.013, flick=0.012, thick=0.006)
        bang(s * 70, 44, s * 78, 120, 0.024, lift=0.010, mat="hair_dark", flick=0.006, thick=0.005)
        for a in (128, 152, 174):
            bang(s * a, 100, s * (a + 6), 150 + (a % 7), 0.030, lift=0.008, flick=0.014, mat="hair_dark" if a == 152 else "hair")

    # ------------------------------------------------------------------ swept sections to the ties
    for s in (1, -1):
        tie = TIE * V(s, 1, 1)
        td = norm(tie - C0)
        tphi = math.degrees(math.atan2(td[0], -td[1]))
        tth = math.degrees(math.acos(td[2]))
        roots = [(s * 14, 26), (s * 38, 30), (s * 62, 38), (s * 84, 52), (s * 100, 80), (s * 118, 104),
                 (s * 142, 112), (s * 166, 108), (s * 176, 70), (s * 176, 36), (s * 150, 22),
                 (s * 60, 14)]
        for i, (a0, t0) in enumerate(roots):
            a1, t1 = tphi, tth
            if abs(a0 - a1) > 180:
                a0 = a0 - 360 * np.sign(a0 - a1)
            reach = float(np.linalg.norm(tie - C0) - np.linalg.norm(surf([td])[0] - C0)) - 0.004
            keys = [(a0, t0, 0.006), (lerpf(a0, a1, 0.35), lerpf(t0, t1, 0.35), 0.012),
                    (lerpf(a0, a1, 0.72), lerpf(t0, t1, 0.72), 0.016 + 0.25 * reach), (a1, t1, reach)]
            pts, nr = _sph_path(keys)
            strand(m, pts, nr, 0.034, 0.0055, "hair" if i % 2 == 0 else "hair_dark", n=9,
                   root_w=0.75, peak=0.35, tip_pow=2.2)

    pm = Mesh()
    # ------------------------------------------------------------------ pigtails
    for s in (1, -1):
        tie = TIE * V(s, 1, 1)
        axis = PIG_DIR * V(s, 1, 1)
        torus(tie + axis * 0.002, axis, 0.0150, 0.0070, "hair_tie", m, n=14, m=6)
        torus(tie + axis * 0.013, axis, 0.0150, 0.0070, "hair_tie", m, n=14, m=6)
        u = norm(np.cross(axis, V(0, 0, 1)))
        v = np.cross(axis, u)
        # a big airy ball of spiky crescent locks: directions spread over a wide cone around the
        # tie axis (golden-angle spiral), each lock bending sideways/downward into a hooked tip
        NC = 22
        ball = tie + axis * 0.105
        for i in range(NC):
            f = (i + 0.5) / NC
            polar = math.radians(10 + 92 * f ** 0.8)
            ang = i * 2.39996 + (0.4 if s > 0 else 1.1)
            side = math.cos(ang) * u + math.sin(ang) * v
            d0 = norm(axis * math.cos(polar) + side * math.sin(polar))
            L = (0.225 - 0.055 * f) * (1 + rnd.u(-0.12, 0.18))
            down = V(0, 0, -1) - d0 * float(V(0, 0, -1) @ d0)
            swirl = np.cross(axis, d0) * (1 if i % 2 else -1)
            c = norm(swirl * 0.85 + down * (0.55 + rnd.u(0, 0.5)) + side * 0.2)
            if d0[2] > 0.35:                       # the top locks flick up and out instead of drooping
                c = norm(swirl * 0.9 + side * 0.5 + V(s * 0.3, 0.2, 0.3))
            p0 = tie + axis * 0.004 + side * 0.006
            p1 = p0 + d0 * L * 0.40
            p2 = p1 + norm(d0 + c * 0.75) * L * 0.33
            p3 = p2 + norm(d0 * 0.55 + c * 1.7) * L * 0.27
            path = np.array([p0, p1, p2, p3])
            nr = norm(path - ball + d0 * 0.03)
            nr[0] = norm(side + axis * 0.2)
            wd = (0.074 - 0.014 * f) * (1 + rnd.u(-0.15, 0.2))
            strand(pm, path, nr, wd, 0.0190, "hair" if i % 3 else "hair_dark",
                   n=11, root_w=0.28, peak=0.42, tip_pow=1.15, twist=rnd.u(-0.35, 0.35))
        # thin escaped strands
        for j in range(0):
            ang = rnd.u(0, 2 * math.pi)
            side = math.cos(ang) * u + math.sin(ang) * v
            d0 = norm(axis + side * 1.1)
            p0 = tie
            p1 = p0 + d0 * 0.10
            p2 = p1 + norm(d0 + V(0, 0, -0.5) + side * 0.4) * 0.09
            p3 = p2 + norm(d0 * 0.3 + V(0, 0, 0.6) + side * 0.8) * 0.06
            path = np.array([p0, p1, p2, p3])
            strand(pm, path, norm(path - tie + side * 0.03), 0.010, 0.0035, "hair", n=9, root_w=0.5)

    # ------------------------------------------------------------------ flyaways on top
    for (a, t0, lean, L) in ((0, 12, V(0.1, -0.5, 1), 0.068), (-28, 15, V(-0.7, -0.3, 1), 0.072),
                             (28, 15, V(0.7, -0.3, 1), 0.068), (-65, 20, V(-1, 0.1, 0.9), 0.058),
                             (65, 20, V(1, 0.1, 0.9), 0.058), (170, 22, V(0.2, 0.7, 1), 0.056),
                             (-120, 18, V(-0.6, 0.6, 1), 0.050)):
        p0 = surf([sph(a, t0)], 0.004)[0]
        d = norm(lean)
        p1 = p0 + d * L * 0.5
        p2 = p1 + norm(d + V(0.4 * np.sign(lean[0] + 1e-6), -0.2, -0.5)) * L * 0.5
        p3 = p2 + norm(d + V(0.6 * np.sign(lean[0] + 1e-6), -0.3, -1.2)) * L * 0.35
        path = np.array([p0, p1, p2, p3])
        strand(m, path, np.tile(norm(V(d[0], d[1] - 0.6, 0.2)), (4, 1)), 0.020, 0.0060, "hair", n=9, root_w=0.7,
               peak=0.3, tip_pow=1.6)

    out = []
    import bmesh
    for name, mesh in (("Hair", m), ("Pigtails", pm)):
        ob = to_object(name, mesh)
        set_co(ob, get_co(ob) + HEAD_C)
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(ob.data)
        bm.free()
        out.append(ob)
    return out


def pigtail_chain(side):
    """Three-bone chain (4 points, world space) through a pigtail for secondary motion."""
    tie = TIE * V(side, 1, 1)
    axis = PIG_DIR * V(side, 1, 1)
    p0 = tie
    p1 = p0 + axis * 0.085
    p2 = p1 + norm(axis * 0.9 + V(side * 0.15, 0.1, -0.35)) * 0.075
    p3 = p2 + norm(axis * 0.6 + V(side * 0.2, 0.1, -0.8)) * 0.065
    return np.array([p0, p1, p2, p3]) + HEAD_C
