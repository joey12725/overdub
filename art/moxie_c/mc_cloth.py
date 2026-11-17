"""Soft goods: cargo pants, crop top, chest strap, gloves, jacket. Each garment is its own thick
mesh with modelled folds; tight pieces are fitted to the sculpted body SDF."""
import math

import bmesh
import bpy
import numpy as np

import mc_body
from mc_body import body_sdf
from mc_util import (V, Mesh, Rand, activate, catmull, circle_profile, get_co, hash3,
                     laplacian_fast, loft, material, norm, resample, sdf_march, sdf_normal,
                     sdf_project, set_co, smoothstep, solidify, subsurf, sweep, to_object)

# --------------------------------------------------------------------------- pants

LEG_TOP = 0.800
LEG_BOT = 0.290
NL = 22                      # verts per leg ring
NP = 32                      # verts per pelvis ring
DELTA = 2 * math.pi / NL


def leg_centre(z):
    t = (LEG_TOP - z) / (LEG_TOP - LEG_BOT)
    return V(0.090 + 0.026 * t, 0.014 + 0.008 * t)


def leg_radii(z):
    # baggy low-rise cargo legs ballooning over a rolled cuff that sits mid-shin (build space)
    zs = [0.80, 0.76, 0.66, 0.56, 0.47, 0.40, 0.36, 0.33, 0.305, 0.29]
    rx = [0.098, 0.100, 0.106, 0.110, 0.114, 0.118, 0.116, 0.106, 0.088, 0.078]
    ry = [0.112, 0.110, 0.106, 0.103, 0.102, 0.103, 0.101, 0.094, 0.082, 0.074]
    return float(np.interp(z, zs[::-1], rx[::-1])), float(np.interp(z, zs[::-1], ry[::-1]))


def pants_folds(co, nrm):
    """Displacement (metres along the normal) that sculpts drape and bunching into the legs."""
    x, y, z = co[:, 0], co[:, 1], co[:, 2]
    side = np.sign(x + 1e-9)
    c = np.array([leg_centre(v) for v in z])
    psi = np.arctan2(-(y - c[:, 1]), -(np.abs(x) - c[:, 0]))      # 0 = inward, pi/2 = front
    d = np.zeros(len(co))
    leg = z < 0.80
    # ankle stack: horizontal bunching above the cuff
    a = smoothstep(0.50, 0.37, z) * smoothstep(0.300, 0.330, z)
    ph = z / 0.046 * 2 * math.pi + 1.6 * np.sin(2 * psi + side * 0.7) + 0.9 * np.sin(psi * 3 + 2.0)
    s = np.sin(ph)
    d += a * 0.0085 * (s + 0.35 * np.sin(2 * ph + 1.0))
    # knee: diagonal compression folds, strongest at the back and inside
    k = np.exp(-((z - 0.475) / 0.085) ** 2)
    d += k * 0.0060 * np.sin(psi * 3.0 + (z - 0.47) * 55 * side + 0.5) * (0.6 + 0.4 * np.cos(psi))
    # thigh: long soft drape folds running down from the hip
    th = smoothstep(0.50, 0.60, z) * smoothstep(0.86, 0.74, z)
    d += th * 0.0050 * np.sin(psi * 4.0 + (z - 0.6) * 9.0 + side * 1.3)
    # crotch / hip tension folds
    cr = np.exp(-((z - 0.79) / 0.05) ** 2)
    d += cr * 0.0045 * np.sin(psi * 2.0 - (z - 0.79) * 70 + 1.0)
    # general slight irregularity
    d += 0.0016 * hash3(co * 1.7, 3.0)
    d *= np.where(z > 0.895, 0.0, 1.0) * smoothstep(0.293, 0.312, z)
    return d


def _leg_ring(z, shrink_inner=True):
    c = leg_centre(z)
    rx, ry = leg_radii(z)
    pts = []
    for j in range(NL):
        psi = 3 * DELTA + j * DELTA
        dx = -math.cos(psi)              # psi 0 -> inward (-x)
        dy = -math.sin(psi)              # psi pi/2 -> front (-y)
        r_in = min(rx, c[0] - (0.006 + 0.024 * min(1.0, max(0.0, (0.76 - z) / 0.26))))   # daylight between the legs
        px = c[0] + dx * (r_in if dx < 0 else rx)
        py = c[1] + dy * ry
        pts.append((px, py, z))
    return pts


def build_pants():
    verts, faces, uvs = [], [], {}

    def add(p):
        verts.append(p)
        return len(verts) - 1
    pel = [(0.918, 0.131, 0.096), (0.895, 0.141, 0.103), (0.865, 0.150, 0.110), (0.832, 0.155, 0.114),
           (0.800, 0.157, 0.115)]
    prings = []
    for (z, rx, ry) in pel:
        ring = []
        for k in range(NP):
            t = 2 * math.pi * k / NP
            ring.append(add((math.sin(t) * rx, 0.016 - math.cos(t) * ry, z)))
        prings.append(ring)
    V0, V1 = 0.76, 1.0
    for r in range(len(pel) - 1):
        for k in range(NP):
            f = (prings[r][k], prings[r][(k + 1) % NP], prings[r + 1][(k + 1) % NP], prings[r + 1][k])
            v0 = V1 - (V1 - V0) * r / (len(pel) - 1)
            v1 = V1 - (V1 - V0) * (r + 1) / (len(pel) - 1)
            uvs[len(faces)] = [(k / NP, v0), ((k + 1) / NP, v0), ((k + 1) / NP, v1), (k / NP, v1)]
            faces.append(f)
    split = prings[-1]
    cz = [0.786, 0.773, 0.768, 0.773, 0.786]
    cy = [-0.070, -0.035, 0.012, 0.060, 0.092]
    crotch = [add((0.0, y, z)) for y, z in zip(cy, cz)]
    zs = [0.765, 0.730, 0.695, 0.660, 0.625, 0.590, 0.555, 0.520, 0.488, 0.458, 0.430, 0.404, 0.380,
          0.358, 0.338, 0.321, 0.307, 0.296]
    for side in (1, -1):
        if side > 0:
            first = [split[k] for k in range(0, 17)] + crotch[::-1]
        else:
            first = [split[(NP - k) % NP] for k in range(0, 17)] + crotch[::-1]
        prev = first
        u_off = 0.0 if side > 0 else 0.5
        zprev = LEG_TOP
        for z in zs:
            ring = [add((p[0] * side, p[1], p[2])) for p in _leg_ring(z)]
            for j in range(NL):
                a0, a1, b0, b1 = prev[j], prev[(j + 1) % NL], ring[j], ring[(j + 1) % NL]
                va = 0.74 * (zprev - LEG_BOT) / (LEG_TOP - LEG_BOT)
                vb = 0.74 * (z - LEG_BOT) / (LEG_TOP - LEG_BOT)
                ua, ub = u_off + 0.5 * j / NL, u_off + 0.5 * (j + 1) / NL
                if side > 0:
                    faces.append((a0, a1, b1, b0))
                    uvs[len(faces) - 1] = [(ua, va), (ub, va), (ub, vb), (ua, vb)]
                else:
                    faces.append((a0, b0, b1, a1))
                    uvs[len(faces) - 1] = [(ua, va), (ua, vb), (ub, vb), (ub, va)]
            prev = ring
            zprev = z
    m = Mesh()
    m.add(np.array(verts), faces, "pants_olive")
    m.uv = {i: u for i, u in uvs.items()}
    ob = to_object("Pants", m)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data)
    bm.free()
    subsurf(ob, 1)
    # folds
    co = get_co(ob)
    ob.data.update()
    nrm = np.array([v.normal[:] for v in ob.data.vertices])
    co = co + nrm * pants_folds(co, nrm)[:, None]
    set_co(ob, co)
    co = laplacian_fast(co, ob.data, k=0.25, iters=1)
    set_co(ob, co)

    # cuffs, waistband, cargo pockets
    m2 = Mesh()
    for side in (1, -1):
        c = leg_centre(0.296)
        prof = circle_profile(8, 0.020, 0.0085, power=3.0)
        ring_pts = []
        for j in range(28):
            a = 2 * math.pi * j / 28
            ring_pts.append((side * (c[0] + math.cos(a) * 0.080), c[1] + math.sin(a) * 0.077, 0.296))
        ring_pts = np.array(ring_pts)
        rings = []
        for j in range(28):
            a = 2 * math.pi * j / 28
            out = V(math.cos(a) * side, math.sin(a), 0)
            wob = 0.004 * math.sin(a * 3 + side)
            rings.append([ring_pts[j] + V(0, 0, 1) * (px + wob) + out * py for px, py in prof])
        rings.append(rings[0])
        loft(np.array(rings), "pants_cuff", m2, flip=(side > 0))
        # cargo pocket on the outer thigh
        pc = V(side * 0.172, 0.010, 0.585)
        _pocket(m2, pc, side)
    # waistband
    prof = circle_profile(8, 0.016, 0.0055, power=3.0)
    rings = []
    for k in range(40):
        t = 2 * math.pi * k / 40
        base = V(math.sin(t) * 0.134, 0.016 - math.cos(t) * 0.099, 0.915)
        out = norm(V(math.sin(t) * 0.099, -math.cos(t) * 0.134, 0))
        rings.append([base + V(0, 0, 1) * px + out * py for px, py in prof])
    rings.append(rings[0])
    loft(np.array(rings), "pants_dark", m2, flip=True)
    ob2 = to_object("PantsTrim", m2)
    bm = bmesh.new()
    bm.from_mesh(ob2.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob2.data)
    bm.free()
    return ob, ob2


def _pocket(m, c, side):
    """Bellows cargo pocket with a flap, hugging the outer thigh."""
    from mc_util import rbox, rot_axis
    R = rot_axis(V(0, 0, 1), math.radians(0))
    b = rbox(V(0, 0, 0), (0.014, 0.052, 0.062), 0.008, "pants_olive", seg=2)
    b.transform(t=c + V(side * 0.004, 0, 0))
    m.merge(b)
    f = rbox(V(0, 0, 0), (0.0155, 0.055, 0.020), 0.006, "pants_dark", seg=2)
    f.transform(t=c + V(side * 0.007, 0, 0.050))
    m.merge(f)
    s = rbox(V(0, 0, 0), (0.004, 0.006, 0.006), 0.002, "metal", seg=1)
    s.transform(t=c + V(side * 0.022, 0, 0.040))
    m.merge(s)


def build_shins():
    """Bare lower legs: visible between the rolled cuffs and the boot tops, and through the knee tear."""
    m = Mesh()
    zs = np.array([0.560, 0.520, 0.480, 0.440, 0.400, 0.360, 0.320, 0.280, 0.240, 0.205])
    rad = np.array([0.050, 0.047, 0.044, 0.043, 0.044, 0.043, 0.039, 0.034, 0.031, 0.033])
    for side in (1, -1):
        rings = []
        for z, r in zip(zs, rad):
            t = (0.48 - z) / (0.48 - 0.09)
            cx, cy = 0.094 + 0.006 * t, 0.004 + 0.020 * t + 0.008 * math.sin(max(0.0, min(1.0, (0.44 - z) / 0.2)) * math.pi)
            rings.append([(side * (cx + math.cos(a) * r * 0.94), cy + math.sin(a) * r, z)
                          for a in np.linspace(0, 2 * math.pi, 14, endpoint=False)])
        loft(np.array(rings), "skin", m, flip=(side > 0))
    ob = to_object("Shins", m)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data)
    bm.free()
    return ob


# --------------------------------------------------------------------------- fitted pieces

def offset_surface(pts, off):
    """Project points to the body surface and push them out by off."""
    p = sdf_project(body_sdf, pts, iters=8)
    n = sdf_normal(body_sdf, p)
    return p + n * off


def _torso_point(theta, z, off):
    """Point on the torso at azimuth theta (0 = front, + toward her left) and height z."""
    d = V(math.sin(theta), -math.cos(theta), 0)
    o = V(0, 0.012, z) + d * 0.4
    hit = sdf_march(body_sdf, o[None, :], -d[None, :], tmax=0.4)[0]
    return hit + d * off


def build_top():
    """Light crop top: chest band with a scooped neckline, two shoulder straps, dark trim."""
    m = Mesh()
    NT, NZ = 44, 5
    hem = 1.128
    OFF = 0.0042

    def top_z(theta):
        a = abs(((math.degrees(theta) + 180) % 360) - 180)       # 0 front .. 180 back
        if a < 70:
            x = a / 70
            return (1.236 + 0.030 * math.sin(min(1.0, x / 0.60) * math.pi / 2) ** 2
                    - 0.052 * smooth01((x - 0.62) / 0.38))
        if a < 110:
            return 1.214
        x = (a - 110) / 70
        return (1.214 + 0.046 * math.sin(min(1.0, x / 0.5) * math.pi / 2) ** 2
                - 0.012 * smooth01((x - 0.5) / 0.5))

    def smooth01(t):
        t = min(1.0, max(0.0, t))
        return t * t * (3 - 2 * t)
    rings = []
    tops = []
    for j in range(NZ + 1):
        row = []
        for i in range(NT):
            th = 2 * math.pi * i / NT
            z = hem + (top_z(th) - hem) * j / NZ
            row.append(_torso_point(th, z, OFF))
        rings.append(row)
    rings = np.array(rings)
    loft(rings, "top_light", m)
    # straps: from the front top edge over the shoulder to the back
    for s in (1, -1):
        x0 = 0.064
        path = []
        for t in np.linspace(0, 1, 15):
            ang = math.pi * (0.06 + 0.88 * t)             # front -> over -> back
            y = 0.014 - math.cos(ang) * 0.12
            z = 1.245 + math.sin(ang) * 0.12
            xx = x0 + 0.010 * math.sin(ang)
            path.append((s * xx, y, z))
        path = np.array(path)
        widths = np.interp(np.linspace(0, 1, 15), [0, 0.25, 0.5, 0.75, 1], [0.021, 0.015, 0.0135, 0.015, 0.021])
        left = path - V(s, 0, 0) * widths[:, None]
        right = path + V(s, 0, 0) * widths[:, None]
        cols = []
        for a in np.linspace(0, 1, 5):
            pts = left + (right - left) * a
            pts = offset_surface(pts, OFF)
            cols.append(pts)
        cols = np.array(cols)            # (5, 15, 3)
        strip = np.transpose(cols, (1, 0, 2))
        loft(strip, "top_light", m, closed=False)
    ob = to_object("Top", m, merge=0.0)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data)
    bm.free()
    co = get_co(ob)
    # outward check: flip if normals point inward
    ob.data.update()
    nrm = np.array([v.normal[:] for v in ob.data.vertices])
    if (nrm[:, :2] * (co[:, :2] - V(0, 0.012))).sum() < 0:
        ob.data.flip_normals()
    solidify(ob, 0.0030, offset=1.0)
    # trim: hem band and neckline piping
    t = Mesh()
    prof = circle_profile(6, 0.0075, 0.0034, power=3.0)
    ringsT = []
    for i in range(NT):
        th = 2 * math.pi * i / NT
        p = _torso_point(th, hem + 0.004, OFF + 0.0022)
        d = V(math.sin(th), -math.cos(th), 0)
        ringsT.append([p + V(0, 0, 1) * px + d * py for px, py in prof])
    ringsT.append(ringsT[0])
    loft(np.array(ringsT), "top_trim", t)
    prof2 = circle_profile(6, 0.0034, 0.0030)
    ringsN = []
    for i in range(NT):
        th = 2 * math.pi * i / NT
        p = _torso_point(th, top_z(th), OFF + 0.0020)
        d = V(math.sin(th), -math.cos(th), 0)
        ringsN.append([p + V(0, 0, 1) * px + d * py for px, py in prof2])
    ringsN.append(ringsN[0])
    loft(np.array(ringsN), "top_trim", t)
    # faded graphic on the chest: a chevron-star, as a thin inlay
    g = []
    for (dx, dz) in ((0.0, 0.030), (0.012, 0.004), (0.036, 0.004), (0.016, -0.012), (0.024, -0.036),
                     (0.0, -0.020), (-0.024, -0.036), (-0.016, -0.012), (-0.036, 0.004), (-0.012, 0.004)):
        g.append((dx * 0.9, -0.2, 1.182 + dz * 0.9))
    g = np.array(g)
    gp = sdf_march(body_sdf, g, np.tile(V(0, 1, 0), (len(g), 1)), tmax=0.4)
    gp = gp + sdf_normal(body_sdf, gp) * (OFF + 0.0036)
    cen = gp.mean(axis=0) + V(0, -0.001, 0)
    fs = [(10, i, (i + 1) % 10) for i in range(10)]
    t.add(np.vstack([gp, cen[None, :]]), fs, "top_graphic")
    ob2 = to_object("TopTrim", t)
    bm = bmesh.new()
    bm.from_mesh(ob2.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    for f in bm.faces:
        if len(f.verts) == 3 and f.normal.y > 0:
            f.normal_flip()
    bm.to_mesh(ob2.data)
    bm.free()
    return ob, ob2


def build_chest_strap():
    """Diagonal strap: over her left shoulder, under her right arm, with a buckle on the chest."""
    m = Mesh()
    pc = V(0.0, 0.012, 1.210)
    d1 = norm(V(0.60, 0.0, 0.80))
    d2 = V(0, 1, 0)
    nrm = np.cross(d1, d2)
    N = 48
    centre = []
    for i in range(N):
        a = 2 * math.pi * i / N
        d = math.cos(a) * d1 + math.sin(a) * d2
        hit = sdf_march(body_sdf, (pc + d * 0.45)[None, :], -d[None, :], tmax=0.45)[0]
        centre.append(hit + d * 0.0115)
    centre = np.array(centre)
    # smooth the loop a little (it rides over the top and the bust)
    for _ in range(3):
        centre = 0.5 * centre + 0.25 * (np.roll(centre, 1, axis=0) + np.roll(centre, -1, axis=0))
    prof = circle_profile(6, 0.0135, 0.0026, power=4.0)
    rings = []
    for i in range(N):
        tang = norm(centre[(i + 1) % N] - centre[i - 1])
        out = norm(np.cross(tang, nrm))
        if out @ (centre[i] - pc) < 0:
            out = -out
        rings.append([centre[i] + nrm * px + out * py for px, py in prof])
    rings.append(rings[0])
    loft(np.array(rings), "strap_dark", m)
    # buckle on the front of the chest
    from mc_util import rbox
    front = [i for i in range(N) if centre[i][1] < 0]
    bi = min(front, key=lambda i: abs(centre[i][0] + 0.012))
    tang = norm(centre[(bi + 1) % N] - centre[bi - 1])
    out = norm(np.cross(tang, nrm))
    if out @ (centre[bi] - pc) < 0:
        out = -out
    Rm = np.stack([tang, nrm, out], axis=1)
    b = rbox(V(0, 0, 0), (0.013, 0.019, 0.0045), 0.002, "metal", seg=2, R=Rm)
    b.transform(t=centre[bi] + out * 0.003)
    m.merge(b)
    b2 = rbox(V(0, 0, 0), (0.0075, 0.012, 0.0052), 0.0015, "strap_dark", seg=1, R=Rm)
    b2.transform(t=centre[bi] + out * 0.0036)
    m.merge(b2)
    ob = to_object("ChestStrap", m)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def build_gloves(hand, name):
    """Fingerless glove: the palm, the back of the hand and the first knuckle, as an offset shell
    of the hand mesh itself (so it deforms exactly like the hand)."""
    import mc_hand
    side = 1 if name.endswith("L") else -1
    co = get_co(hand)
    lco = co * V(side, 1, 1)
    J = mc_hand.joints_left()
    keep = np.zeros(len(co), dtype=bool)
    # palm region: everything before the knuckle line; fingers: first 55 % of the first phalanx
    lim = np.full(len(co), 1e9)
    tagw = {}
    for nm in ("Index", "Middle", "Ring", "Little", "Thumb"):
        g = hand.vertex_groups.get("tag_" + nm)
        w = np.zeros(len(co))
        for v in hand.data.vertices:
            for ge in v.groups:
                if ge.group == g.index:
                    w[v.index] = ge.weight
        tagw[nm] = w
    anyf = np.zeros(len(co))
    for nm, w in tagw.items():
        c = J[nm]
        d = norm(c[1] - c[0])
        t = (lco - c[0]) @ d / np.linalg.norm(c[1] - c[0])
        frac = 0.50 if nm != "Thumb" else 0.92
        ok = t < frac
        keep |= (w > 0.5) & ok
        anyf = np.maximum(anyf, w)
    keep |= anyf <= 0.5
    bm = bmesh.new()
    bm.from_mesh(hand.data)
    bm.verts.ensure_lookup_table()
    faces = [f for f in bm.faces if all(keep[v.index] for v in f.verts)]
    m = Mesh()
    idx = {}
    vs, fs = [], []
    hand.data.update()
    nrm = np.array([v.normal[:] for v in hand.data.vertices])
    for f in faces:
        fi = []
        for v in f.verts:
            if v.index not in idx:
                idx[v.index] = len(vs)
                vs.append(co[v.index] + nrm[v.index] * 0.0017)
            fi.append(idx[v.index])
        fs.append(fi)
    bm.free()
    m.add(np.array(vs), fs, "glove")
    # knuckle guard plate and a wrist strap
    ob = to_object("Glove" + name[-1], m)
    return ob
