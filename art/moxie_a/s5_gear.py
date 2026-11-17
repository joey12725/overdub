"""Stage 5 - jacket and gear: oversized off-shoulder jacket with yellow lining, yellow headphones
with the triangle graphic, choker, diagonal chest strap, utility belt with the cassette Walkman,
pouches, tools, glowing vial, crimson hanging straps, cargo pockets, cable, wrist devices.
Adds the secondary-motion bones for the jacket flaps and straps. Reads work/s4.blend, saves s5.blend.
"""
import bpy, bmesh, sys, os, math, random
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mxa_util as U
import mxa_cloth as CL
import mxa_build as MBm
from mxa_build import MB, catmull, resample

U.PALETTE.update({'cable': U.PALETTE['phones'], 'headphones_glow': '#FFE27A', 'jacket_patch': '#E9E0CF'})
X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
HEAD = {'Head': 1.0}; HIPS = {'Hips': 1.0}
TORSO = ['Hips', 'Spine', 'Chest', 'UpperChest']


def sstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def bvh_of(objs, xmax=9.0):
    verts = []; polys = []
    for ob in objs:
        base = len(verts)
        verts += [v.co.copy() for v in ob.data.vertices]
        polys += [tuple(base + i for i in p.vertices) for p in ob.data.polygons
                  if all(abs(ob.data.vertices[i].co.x) < xmax for i in p.vertices)]
    return BVHTree.FromPolygons(verts, polys)


def around(bvh, c, d, off, far=0.6):
    """Surface point seen from outside along -d towards c, pushed out by off."""
    d = d.normalized()
    hit = bvh.ray_cast(c + d * far, -d, far)
    p = hit[0] if hit[0] is not None else c
    return p + d * off


FLAT = [(-1, -1), (-1, 1), (-0.6, 1.25), (0.6, 1.25), (1, 1), (1, -1)]


def headphones(mb):
    for s in (1, -1):
        c = Vector((0.101 * s, 0.047, 1.424))
        ax = X * s
        # one lathed shell: cushion, rounded yellow cup, flat dark face plate
        prof = [(0.000, 0.040, 'phones_pad'), (0.003, 0.049, 'phones_pad'), (0.011, 0.050, 'phones_pad'),
                (0.014, 0.056, 'phones'), (0.022, 0.058, 'phones'), (0.032, 0.056, 'phones'), (0.040, 0.050, 'phones'),
                (0.044, 0.041, 'phones'), (0.0445, 0.038, 'phones_dark')]
        rings = []
        for d, r, m in prof:
            rings.append(mb.ring(c + ax * d, Y, Z, [(math.cos(2 * math.pi * k / 24) * r, math.sin(2 * math.pi * k / 24) * r)
                                                    for k in range(24)], HEAD))
        for i in range(len(prof) - 1):
            mb.loft(rings[i:i + 2], prof[i + 1][2], flip=(s < 0))
        mb.face(rings[-1] if s > 0 else rings[-1][::-1], 'phones_dark')
        mb.face(rings[0][::-1] if s > 0 else rings[0], 'phones_pad')
        # the triangle graphic (emissive: the game recolours `headphones_glow` to the cassette colour)
        o = c + ax * 0.0455
        tri = [o + Z * 0.027, o + Y * 0.025 - Z * 0.017, o - Y * 0.025 - Z * 0.017]
        tin = [o + (p - o) * 0.52 for p in tri]
        a = [mb.vert(p + ax * 0.002, HEAD) for p in tri]; b = [mb.vert(p + ax * 0.002, HEAD) for p in tin]
        for i in range(3):
            j = (i + 1) % 3
            q = [a[i], a[j], b[j], b[i]]
            mb.face(q if s < 0 else q[::-1], 'headphones_glow')
        # yoke
        mb.box(c + ax * 0.026 + Z * 0.060, ax * 0.010, Y * 0.014, Z * 0.022, 'phones_dark', HEAD, bevel=0.003)
    # band
    pts = [Vector((-0.127, 0.040, 1.492)), Vector((-0.117, 0.034, 1.556)), Vector((-0.070, 0.028, 1.606)), Vector((0, 0.026, 1.622)),
           Vector((0.070, 0.028, 1.606)), Vector((0.117, 0.034, 1.556)), Vector((0.127, 0.040, 1.492))]
    path = resample(catmull(pts, 60), 22)
    c0 = Vector((0, 0.03, 1.47))
    mb.strip(path, FLAT, 'phones', HEAD, up=lambda i, p: p - c0, width=lambda t: (0.021, 0.0055))
    mb.strip(path[5:-5], FLAT, 'phones_dark', HEAD, up=lambda i, p: p - c0, width=lambda t: (0.015, 0.0068))


def choker(mb, ws, bvh):
    c = Vector((0, 0.030, 1.322))
    pts = [around(bvh, c, Vector((math.sin(a), -math.cos(a), 0.0)), 0.0035, 0.2) for a in [2 * math.pi * i / 20 for i in range(20)]]
    w = ws.at(c, only=['Neck', 'Head']) or {'Neck': 1.0}
    n = len(pts)
    rings = []
    for i, p in enumerate(pts):
        N = (p - c).normalized();
        rings.append(mb.ring(p, Z, N, [(-0.008, -0.002), (-0.008, 0.003), (0.008, 0.003), (0.008, -0.002)], w))
    mb.loft(rings, 'choker'); mb.loft([rings[-1], rings[0]], 'choker')
    f = pts[0]
    ring = [f + Vector((math.cos(a) * 0.011, -0.004, -0.012 + math.sin(a) * 0.011)) for a in [2 * math.pi * i / 12 for i in range(12)]]
    r = mb.tube(ring, 0.0026, 'metal', w, sides=5, up=-Y, cap0=False, cap1=False)
    mb.loft([r[-1], r[0]], 'metal')


def chest_strap(mb, ws, bvh):
    L = Vector((0.074, 0.0, 1.292)); R = Vector((-0.118, 0.0, 1.085))
    c = (L + R) / 2 + Vector((0, 0.01, 0))
    u = (L - R).normalized(); v = -Y
    pts = []
    n = 40
    for i in range(n):
        a = 2 * math.pi * i / n
        d = u * math.cos(a) * 1.0 + v * math.sin(a)
        pts.append(around(bvh, c, d, 0.0065, 0.5))
    rings = []
    nrm = u.cross(v).normalized()
    for i, p in enumerate(pts):
        N = (p - c); N = (N - nrm * N.dot(nrm)).normalized()
        w = ws.at(p - N * 0.01, exclude=['LeftUpperArm', 'RightUpperArm', 'LeftLowerArm', 'RightLowerArm', 'Neck', 'Head'])
        rings.append(mb.ring(p, nrm, N, [(-0.015, -0.003), (-0.015, 0.003), (0.015, 0.003), (0.015, -0.003)], w))
    mb.loft(rings, 'strap'); mb.loft([rings[-1], rings[0]], 'strap')
    # buckle on the chest
    i = n // 4 + 1
    p = pts[i]; N = (p - c).normalized(); T = (pts[i + 1] - pts[i - 1]).normalized()
    w = ws.at(p, only=TORSO)
    mb.box(p + N * 0.004, T * 0.017, nrm * 0.020, N * 0.005, 'buckle', w, bevel=0.002)
    mb.box(p + N * 0.007, T * 0.009, nrm * 0.012, N * 0.004, 'strap', w, bevel=0.001)


def belt_and_gear(mb, ws, bvh, rig):
    def bz(phi):   # the belt follows the low-rise waist: lower in front
        return 0.893 - 0.022 * math.cos(phi)

    def bp(phi_deg, off=0.006, dz=0.0):
        a = math.radians(phi_deg)
        z = bz(a) + dz
        return around(bvh, Vector((0, 0.008, z)), Vector((math.sin(a), -math.cos(a), 0)), off, 0.5)

    def frame(phi_deg, dz=0.0):
        p = bp(phi_deg, 0.006, dz)
        N = Vector((p.x, p.y - 0.008, 0)).normalized()
        T = Z.cross(N).normalized()
        return p, N, T
    n = 48
    rings = []
    for i in range(n):
        p, N, T = frame(360 * i / n)
        rings.append(mb.ring(p, Z, N, [(-0.019, -0.003), (-0.019, 0.004), (0.019, 0.004), (0.019, -0.003)], HIPS))
    mb.loft(rings, 'belt'); mb.loft([rings[-1], rings[0]], 'belt')
    # eyelets / loops
    for phi in range(20, 360, 40):
        p, N, T = frame(phi)
        mb.box(p + N * 0.004, T * 0.006, Z * 0.024, N * 0.003, 'pants_dark', HIPS, bevel=0.001)
    # buckle
    p, N, T = frame(0)
    mb.box(p + N * 0.006, T * 0.030, Z * 0.024, N * 0.006, 'metal', HIPS, bevel=0.004)
    mb.box(p + N * 0.011, T * 0.018, Z * 0.013, N * 0.004, 'walkman', HIPS, bevel=0.002)

    # ---- Walkman on her right hip (R01), clipped to the belt
    p, N, T = frame(-38, -0.030)
    c = p + N * 0.016
    mb.box(c, T * 0.046, Z * 0.034, N * 0.013, 'walkman', HIPS, bevel=0.004)
    mb.box(c + N * 0.0125 + Z * 0.004, T * 0.034, Z * 0.016, N * 0.002, 'walkman_dark', HIPS, bevel=0.001)
    for sx in (-1, 1):   # cassette reels
        mb.disc(c + N * 0.0146 + Z * 0.004 + T * sx * 0.016, T, Z, 0.0075, 'phones_pad', HIPS, sides=10, depth=N * 0.0015)
    mb.box(c + N * 0.0125 - Z * 0.022, T * 0.030, Z * 0.005, N * 0.0016, 'walkman_dark', HIPS, bevel=0.0008)
    for k in range(4):   # transport buttons on top
        mb.box(c + Z * 0.036 + T * (-0.027 + 0.018 * k), T * 0.007, Z * 0.004, N * 0.007,
               'paint_red' if k == 3 else 'walkman_dark', HIPS, bevel=0.001)
    mb.box(c - N * 0.012 + Z * 0.02, T * 0.012, Z * 0.022, N * 0.004, 'metal', HIPS, bevel=0.001)   # belt clip
    walk_top = c + Z * 0.036 + T * 0.036

    # ---- pouches
    def pouch(phi, w, h, d, dz=-0.03, flap=True):
        p, N, T = frame(phi, dz)
        c = p + N * (d + 0.004)
        mb.box(c, T * w, Z * h, N * d, 'pouch', HIPS, bevel=0.006)
        if flap:
            mb.box(c + Z * (h * 0.5) + N * 0.003, T * (w + 0.003), Z * (h * 0.52), N * (d + 0.002), 'belt', HIPS, bevel=0.006)
            mb.disc(c + N * (d + 0.005) + Z * 0.004, T, Z, 0.006, 'metal', HIPS, sides=8, depth=N * 0.003)
    pouch(48, 0.030, 0.038, 0.016)
    pouch(128, 0.026, 0.032, 0.014)
    pouch(178, 0.050, 0.030, 0.015, dz=-0.026)
    pouch(-140, 0.022, 0.034, 0.013)
    # ---- device with a little screen on her left hip
    p, N, T = frame(86, -0.046)
    c = p + N * 0.014
    mb.box(c, T * 0.026, Z * 0.034, N * 0.011, 'phones', HIPS, bevel=0.004)
    mb.box(c + N * 0.011 + Z * 0.006, T * 0.018, Z * 0.014, N * 0.0015, 'screen_glow', HIPS, bevel=0.0008)
    mb.box(c + N * 0.011 - Z * 0.02, T * 0.016, Z * 0.004, N * 0.0015, 'walkman_dark', HIPS, bevel=0.0008)
    # ---- glowing vial + wrench hanging on carabiners
    def hang_ring(phi, dz=-0.03):
        p, N, T = frame(phi, dz)
        c = p + N * 0.008
        pts = [c + T * math.cos(a) * 0.010 + Z * (math.sin(a) * 0.016) for a in [2 * math.pi * i / 10 for i in range(10)]]
        r = mb.tube(pts, 0.0026, 'metal', HIPS, sides=5, up=N, cap0=False, cap1=False)
        mb.loft([r[-1], r[0]], 'metal')
        return c - Z * 0.016, N, T
    c, N, T = hang_ring(108)
    mb.disc(c, T, N, 0.0125, 'metal', HIPS, sides=10, depth=-Z * 0.012)
    mb.disc(c - Z * 0.012, T, N, 0.0105, 'vial_glow', HIPS, sides=10, depth=-Z * 0.058)
    mb.disc(c - Z * 0.070, T, N, 0.0125, 'metal', HIPS, sides=10, depth=-Z * 0.010)
    c, N, T = hang_ring(-84)
    mb.box(c - Z * 0.050, T * 0.006, Z * 0.050, N * 0.0025, 'metal', HIPS, bevel=0.001)
    for sx in (-1, 1):
        mb.box(c - Z * 0.106 + T * sx * 0.010, T * 0.004, Z * 0.012, N * 0.003, 'metal', HIPS, bevel=0.001)
    mb.box(c - Z * 0.096, T * 0.014, Z * 0.005, N * 0.003, 'metal', HIPS, bevel=0.001)
    c, N, T = hang_ring(-112)
    mb.disc(c, T, N, 0.010, 'metal', HIPS, sides=10, depth=-Z * 0.010)
    mb.disc(c - Z * 0.010, T, N, 0.0085, 'paint_red', HIPS, sides=10, depth=-Z * 0.044)

    # ---- crimson straps hanging down her right thigh, each with a clasp; two bones each
    for name, phi, length, wdt in (('RibbonA', -58, 0.36, 0.014), ('RibbonB', -22, 0.26, 0.012)):
        top, N, T = frame(phi, -0.012)
        steps = 12
        pts = []
        for i in range(steps + 1):
            z = top.z - length * i / steps
            a = math.radians(phi)
            pts.append(around(bvh, Vector((-0.075, 0.01, z)) if z < 0.8 else Vector((0, 0.008, z)),
                              Vector((math.sin(a), -math.cos(a), 0)), 0.012 + 0.010 * math.sin(math.pi * i / steps), 0.5))
        mid = pts[steps // 2]
        MBm.add_bone(rig, name + '1', pts[0], mid, 'Hips')
        MBm.add_bone(rig, name + '2', mid, pts[-1], name + '1')

        def w(t, p, name=name):
            return MBm.chain_weights(t, [name + '1', name + '2'], root='Hips', root_blend=0.08)
        mb.strip(pts, [(-1, -1), (-1, 1), (1, 1), (1, -1)], 'ribbon', w, up=lambda i, p, N=N: N, width=lambda t: (wdt, 0.0025))
        e = pts[-1]
        mb.box(e - Z * 0.008, T * (wdt + 0.004), Z * 0.012, N * 0.005, 'metal', {name + '2': 1.0}, bevel=0.002)
        mb.box(pts[steps // 3], T * (wdt + 0.003), Z * 0.007, N * 0.0045, 'metal', {name + '1': 1.0}, bevel=0.0015)

    # ---- cargo pockets on the outer thighs (weights follow the thigh)
    for s, S in ((1, 'Left'), (-1, 'Right')):
        c0 = Vector((0.091 * s, 0.012, 0.635))
        d = Vector((s, 0.12, 0)).normalized()
        p = around(bvh, c0, d, 0.0, 0.4)
        T = Z.cross(d).normalized()
        w = {S + 'UpperLeg': 1.0}
        mb.box(p + d * 0.004, T * 0.046, Z * 0.062, d * 0.016, 'pants', w, bevel=0.008)
        mb.box(p + d * 0.008 + Z * 0.040, T * 0.049, Z * 0.024, d * 0.016, 'pants_dark', w, bevel=0.006)
        mb.disc(p + d * 0.024 + Z * 0.030, T, Z, 0.006, 'metal', w, sides=8, depth=d * 0.003)

    # ---- cable from the Walkman to her right headphone cup (a slack loop by the hip, then up the torso)
    ex = ['LeftUpperArm', 'RightUpperArm', 'LeftLowerArm', 'RightLowerArm', 'LeftShoulder', 'RightShoulder', 'RightUpperLeg', 'LeftUpperLeg']
    cab = [walk_top, walk_top + Vector((-0.03, -0.04, 0.02)), Vector((-0.16, -0.10, 0.86)), Vector((-0.15, -0.10, 0.96)),
           Vector((-0.105, -0.085, 1.06)), Vector((-0.075, -0.105, 1.15)), Vector((-0.062, -0.075, 1.24)),
           Vector((-0.072, -0.030, 1.315)), Vector((-0.112, 0.030, 1.345)), Vector((-0.118, 0.047, 1.376))]
    path = resample(catmull(cab, 80), 40)

    def wc(t, p):
        if p.z > 1.30:
            return ws.at(p, only=['Neck', 'Head']) or HEAD
        if p.z < 1.0:
            return HIPS if p.z < 0.93 else (ws.at(p, only=TORSO) or HIPS)
        return ws.at(p, exclude=ex) or HIPS
    mb.tube(path, 0.0052, 'cable', wc, sides=6)


def wrist_devices(mb):
    for s, S in ((1, 'Left'), (-1, 'Right')):
        w = {S + 'LowerArm': 1.0}
        ax = X * s
        c = Vector((0.478 * s, 0.025, 1.260))
        mb.disc(c - ax * 0.028, Y, Z, 0.0335, 'wrist', w, sides=14, depth=ax * 0.056)
        for dx in (-0.028, 0.028):
            mb.disc(c + ax * dx - ax * 0.004, Y, Z, 0.0365, 'belt', w, sides=14, depth=ax * 0.008)
        top = c + Z * 0.038
        big = 1.0 if s > 0 else 0.82
        mb.box(top, ax * 0.030 * big, Y * 0.027 * big, Z * 0.010, 'phones' if s > 0 else 'wrist', w, bevel=0.004)
        mb.box(top + Z * 0.010, ax * 0.021 * big, Y * 0.018 * big, Z * 0.0015, 'screen_glow', w, bevel=0.001)
        mb.box(top + Z * 0.004 + Y * 0.030 * big, ax * 0.008, Y * 0.004, Z * 0.004, 'paint_red', w, bevel=0.001)
        mb.box(top + Z * 0.004 - ax * 0.034 * big, ax * 0.004, Y * 0.012, Z * 0.005, 'metal', w, bevel=0.001)
        # bandage wraps up the forearm
        for k in range(3):
            x0 = 0.425 - 0.022 * k
            mb.disc(Vector((x0 * s, 0.025, 1.260)), Y, Z, 0.0325 + 0.0012 * k, 'paint_white', w, sides=12, depth=ax * 0.015)


def jacket(mb, ws, rig):
    J = 'jacket'
    # ---- sleeves
    for s, S in ((1, 'Left'), (-1, 'Right')):
        n = 24; sides = 16
        rings_o = []; rings_i = []
        for i in range(n + 1):
            t = i / n
            x = 0.168 + (0.408 - 0.168) * t
            cz = 1.262 - 0.016 * math.sin(math.pi * min(1, t * 1.1)) - 0.010 * (1 - t)
            r = (0.080 + 0.010 * math.sin(math.pi * t * 0.9)) * (1 - 0.47 * sstep(0.80, 0.96, t))
            wv = ws.at(Vector((x * s, 0.025, 1.26)), only=[S + 'UpperArm', S + 'LowerArm', S + 'Hand', S + 'Shoulder'])
            ro = []; ri = []
            for k in range(sides):
                a = 2 * math.pi * k / sides
                fold = 0.0075 * math.exp(-((t - 0.52) / 0.2) ** 2) * math.sin(52 * x + 2.0 * math.sin(2 * a + s))
                fold += 0.0060 * sstep(0.62, 0.80, t) * (1 - sstep(0.93, 0.97, t)) * math.sin(70 * x + 1.5 * math.sin(3 * a))
                fold += 0.004 * math.sin(3 * a + 9 * x)
                rr = r + fold
                sag = 1.0 + 0.16 * max(0.0, -math.sin(a))      # the cloth hangs below the arm
                p = Vector((x * s, 0.025 + math.cos(a) * rr, cz + math.sin(a) * rr * sag))
                ro.append(mb.vert(p, wv))
                if t < 0.35:
                    ri.append(mb.vert(Vector((x * s, 0.025 + math.cos(a) * (rr - 0.005), cz + math.sin(a) * (rr - 0.005) * sag)), wv))
            rings_o.append(ro)
            if ri:
                rings_i.append(ri)
        flip = s < 0
        mb.loft(rings_o[:-2], J, flip=flip)
        mb.loft(rings_o[-3:], 'jacket_rib', flip=flip, cap1=True)
        mb.loft(rings_i, 'jacket_lining', flip=not flip)
        mb.loft([rings_o[0], rings_i[0]], 'jacket_lining', flip=not flip)
        # ribbed cuff + yellow band
        for xx, rr, mm in ((0.396, 0.047, 'jacket_trim'), (0.407, 0.044, 'jacket_rib')):
            wv = ws.at(Vector((xx * s, 0.025, 1.26)), only=[S + 'LowerArm', S + 'Hand'])
            circ = [Vector((xx * s, 0.025 + math.cos(a) * rr, 1.258 + math.sin(a) * rr)) for a in [2 * math.pi * i / 14 for i in range(14)]]
            r_ = mb.tube(circ, 0.007, mm, wv, sides=6, up=lambda i, p: Vector((0, p.y - 0.025, p.z - 1.258)), cap0=False, cap1=False)
            mb.loft([r_[-1], r_[0]], mm)
        # rolled yellow collar edge at the sleeve opening (the lining folded over the shoulder)
        t0 = rings_o[0]
        pts = [mb.v[i].copy() for i in t0]
        wv = ws.at(Vector((0.17 * s, 0.025, 1.26)), only=[S + 'UpperArm', S + 'Shoulder'])
        r_ = mb.tube(pts, 0.013, 'jacket_lining', wv, sides=6, up=lambda i, p: Vector((0, p.y - 0.025, p.z - 1.25)), cap0=False, cap1=False)
        mb.loft([r_[-1], r_[0]], 'jacket_lining')
        # chevron patch on the upper sleeve (R01)
        for k in range(2):
            cx = (0.245 + 0.030 * k) * s
            for sy in (-1, 1):
                a = Vector((cx, 0.025 + sy * 0.004, 1.262 + 0.070)); b = Vector((cx - 0.020 * s, 0.025 + sy * 0.040, 1.262 + 0.058))
                mb.tube([a, b], 0.0055, 'jacket_patch', ws.at(Vector((cx, 0.025, 1.26)), only=[S + 'UpperArm']), sides=5, scale_y=0.5, up=Z)

    # ---- body: a U-shaped panel round the back, open in front, hanging off the upper arms
    MBm.add_bone(rig, 'JacketBack', Vector((0, 0.135, 1.13)), Vector((0, 0.150, 0.985)), 'Chest')
    MBm.add_bone(rig, 'JacketL', Vector((0.175, -0.045, 1.15)), Vector((0.165, -0.075, 0.985)), 'Chest')
    MBm.add_bone(rig, 'JacketR', Vector((-0.175, -0.045, 1.15)), Vector((-0.165, -0.075, 0.985)), 'Chest')
    nu, nv = 44, 12
    A = math.radians(152)
    grid_o = []; grid_i = []
    for j in range(nv + 1):
        v = j / nv
        ro = []; ri = []
        for i in range(nu + 1):
            a = -A + 2 * A * i / nu          # 0 = back centre
            sa, ca = math.sin(a), math.cos(a)
            front = sstep(math.radians(95), A, abs(a))
            ztop = 1.218 + 0.070 * sstep(0.25, 1.0, abs(sa)) * (1 - 0.55 * front) - 0.02 * front
            zbot = 0.985 + 0.02 * abs(sa) - 0.03 * front
            z = ztop + (zbot - ztop) * v
            rx = 0.212 * (1 + 0.06 * v) - 0.050 * front
            ry = (0.118 if ca > 0 else 0.118) * (1 + 0.10 * v)
            fold = 0.008 * (0.3 + 0.7 * v) * math.sin(7 * a + 2.5 * math.sin(5 * v + 1)) + 0.004 * math.sin(13 * a + 4 * v)
            p = Vector((sa * (rx + fold), 0.020 + ca * (ry + fold) - 0.035 * front, z))
            base = ws.at(Vector((p.x * 0.35, p.y * 0.4, z)), only=TORSO) or {'Chest': 1.0}
            S = 'Left' if p.x > 0 else 'Right'
            ka = sstep(0.10, 0.20, abs(p.x)) * sstep(1.02, 1.20, z) * 0.78
            kf = sstep(0.25, 1.0, v) * 0.85
            flap = 'JacketBack' if abs(a) < math.radians(62) else ('JacketL' if a > 0 else 'JacketR')
            w = {k: x * (1 - ka) * (1 - kf) for k, x in base.items()}
            w[S + 'UpperArm'] = w.get(S + 'UpperArm', 0) + ka * (1 - kf)
            w[flap] = kf
            ro.append(mb.vert(p, w))
            n_in = Vector((-sa * ry, -ca * rx, 0)).normalized()
            ri.append(mb.vert(p + n_in * 0.006, w))
        grid_o.append(ro); grid_i.append(ri)
    for j in range(nv):
        mat_o = 'jacket_rib' if j == nv - 1 else J
        mb.loft([grid_o[j], grid_o[j + 1]], mat_o, closed=False)
        mb.loft([grid_i[j], grid_i[j + 1]], 'jacket_lining', closed=False, flip=True)

    def edge_tube(idx, r, m, sy=1.0):
        pts = [mb.v[i].copy() for i in idx]
        frames = MBm.path_frames(pts, lambda i, p: Vector((p.x, p.y - 0.02, 0)))
        rings = []
        for k, (p, (T, N, S_)) in enumerate(zip(pts, frames)):
            rings.append(mb.ring(p, S_, N, [(math.cos(2 * math.pi * q / 6) * r * sy, math.sin(2 * math.pi * q / 6) * r) for q in range(6)], mb.w[idx[k]]))
        mb.loft(rings, m, cap0=True, cap1=True)
    edge_tube(grid_o[0], 0.020, 'jacket_lining', 1.25)                     # fat rolled collar, lining side out
    edge_tube(grid_o[-1], 0.011, 'jacket_rib', 1.3)                       # ribbed hem
    edge_tube([row[0] for row in grid_o], 0.007, 'jacket_trim')           # front edges, yellow
    edge_tube([row[-1] for row in grid_o], 0.007, 'jacket_trim')
    # zip pull + pocket bars on the front flaps
    for s in (1, -1):
        i = nu - 3 if s > 0 else 3
        p = mb.v[grid_o[7][i]]
        mb.box(p + Vector((0, -0.006, 0)), X * 0.004, Y * 0.004, Z * 0.022, 'jacket_trim', mb.w[grid_o[7][i]], bevel=0.001)


def main():
    random.seed(5)
    bpy.ops.wm.open_mainfile(filepath=os.path.join(U.WORK, 's4.blend'))
    rig = bpy.data.objects['Rig']; ref = bpy.data.objects['BodyRef']
    ws = CL.WeightSampler(ref)
    torso = bvh_of([ref, bpy.data.objects['Top']], 0.128)
    lower = bvh_of([bpy.data.objects['Pants']])
    mb = MB()
    headphones(mb)
    choker(mb, ws, torso)
    chest_strap(mb, ws, torso)
    belt_and_gear(mb, ws, lower, rig)
    wrist_devices(mb)
    gear = mb.build('Gear', weighted_normals=True)
    mj = MB()
    jacket(mj, ws, rig)
    jk = mj.build('Jacket')
    for ob in (gear, jk):
        ob.parent = rig
        md = ob.modifiers.new('Armature', 'ARMATURE'); md.object = rig
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(U.WORK, 's5.blend'))
    for ob in (gear, jk):
        print('S5', ob.name, sum(len(p.vertices) - 2 for p in ob.data.polygons))
    print('S5 OK')


if __name__ == '__main__':
    main()
