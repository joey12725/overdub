"""Stage 6: hard-surface gear, all modelled from scratch with mb_geo.Builder.

  Boots       chunky high-tops: lofted upper, three-layer lugged sole, tongue, yellow laces + bow
  Belt        utility belt with buckle, yellow cassette Walkman (cable to the headphones), pouches,
              glow canisters, carabiner, wrench, red hanging straps
  Headphones  big yellow over-ear cups with the triangle graphic, cushions, headband, yokes
  WristDev    chunky wrist devices with small glowing screens (both forearms)
  Choker      band + ring
Every part records the humanoid bone it is rigidly bound to (face attribute 'rigid_bone'); parts with
no bone get their weights from the body in the rig stage.
"""
import bpy, bmesh, sys, os, json, math, random
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mb_util as U
import mb_toon as T
import mb_geo as G
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

U.open_stage("s05_outfit")
body = bpy.data.objects["Body"]
rig = bpy.data.objects["MH_Rig"]
L = json.loads(body["landmarks"])
rnd = random.Random(3)
_keep = []


def bvh_of(o):
    bm_ = bmesh.new()
    bm_.from_mesh(o.data)
    _keep.append(bm_)
    return BVHTree.FromBMesh(bm_)


def J(name, tail=False):
    b = rig.data.bones[name]
    return Vector(b.tail_local if tail else b.head_local)


def mir(v):
    return Vector((-v.x, v.y, v.z))


YEL = "#f2b61f"
DARK = "#28232b"
MET = "#a3a19b"

# =================================================================== BOOTS
def boot(sgn):
    s = "Left" if sgn > 0 else "Right"
    b = G.Builder("Boot" + s[0])
    b.set_bone(s + "Foot")
    m_main = b.mat("shoes_main", "#e6dac0")
    m_dark = b.mat("shoes_dark", "#4b3a36")
    m_acc = b.mat("shoes_accent", YEL)
    m_sole = b.mat("shoes_sole", "#f1e8d4")
    m_tread = b.mat("shoes_tread", "#3a2f2c")
    m_lace = b.mat("shoes_lace", "#f5c021")
    m_in = b.mat("shoes_inner", "#231c1c")
    ank = J("foot.L")
    cx, heel_y, LEN = ank.x, ank.y + 0.062, 0.275
    toe_out = math.radians(6)

    def W(u):       # half width along the foot, heel (0) -> toe (1)
        return float(np.interp(u, [0, 0.06, 0.2, 0.45, 0.72, 0.9, 0.97, 1.0], [0.012, 0.034, 0.044, 0.046, 0.056, 0.048, 0.030, 0.008]))

    def Hh(u):      # height of the upper above the sole
        return float(np.interp(u, [0, 0.30, 0.40, 0.50, 0.62, 0.8, 0.94, 1.0], [0.205, 0.205, 0.180, 0.112, 0.082, 0.064, 0.052, 0.030]))

    def to_world(lx, u, zz):
        y = heel_y - u * LEN
        # toe-out rotation about the ankle
        dx, dy = lx, y - ank.y
        rx = dx * math.cos(toe_out) + (-dy) * math.sin(toe_out) * 1.0
        ry = dy * math.cos(toe_out) + dx * math.sin(toe_out)
        return Vector(((cx + rx) * sgn, ank.y + ry, zz))

    # footprint outline: param list of (u, side)
    NU = 13
    us = [0.0, 0.04, 0.12, 0.24, 0.36, 0.48, 0.60, 0.72, 0.82, 0.90, 0.955, 0.985, 1.0]
    outline = [(u, 1) for u in us] + [(u, -1) for u in us[-2:0:-1]]
    NO = len(outline)

    def ring(grow, zz, wfun=W):
        return [b.bm.verts.new(to_world(sd * (wfun(u) + grow), u + (grow * 0.6 / LEN) * (1 if u > 0.9 else (-1 if u < 0.08 else 0)), zz)) for (u, sd) in outline]

    def band(r0, r1, mi, smooth=True):
        fs = []
        for i in range(NO):
            i2 = (i + 1) % NO
            fs.append(b.bm.faces.new((r0[i], r0[i2], r1[i2], r1[i])))
        b._tag(fs, mi, smooth)

    # sole: tread, chunky midsole with a groove, welt
    Z0 = 0.0
    r = [ring(0.004, Z0), ring(0.010, Z0 + 0.004), ring(0.010, Z0 + 0.014), ring(0.004, Z0 + 0.017),
         ring(0.012, Z0 + 0.020), ring(0.014, Z0 + 0.034), ring(0.009, Z0 + 0.041), ring(0.004, Z0 + 0.044)]
    b._tag([b.bm.faces.new(r[0][::-1])], m_tread, False)
    band(r[0], r[1], m_tread)
    band(r[1], r[2], m_tread)
    band(r[2], r[3], m_tread)
    band(r[3], r[4], m_sole)
    band(r[4], r[5], m_sole)
    band(r[5], r[6], m_sole)
    band(r[6], r[7], m_dark)
    ZS = Z0 + 0.044
    # lugs round the tread
    for i in range(0, NO, 2):
        u, sd = outline[i]
        if 0.05 < u < 0.97:
            p = to_world(sd * (W(u) + 0.013), u, 0.009)
            nrm = Vector((sd * sgn, 0, 0))
            b.box(G.place(p, nrm, Vector((0, 0, 1))), (0.016, 0.020, 0.008), m_tread, bevel=0.002)

    # upper: loft of the outline, closing over the toe, open at the shaft
    JL = 9
    rings = []
    for j in range(JL + 1):
        zr = j / JL
        row = []
        for (u, sd) in outline:
            shaft = float(np.clip((0.47 - u) / 0.12, 0, 1))
            dome = max(1 - zr ** 2.4, 0.0) ** 0.5
            sc = dome * (1 - shaft) + (1.0 - 0.16 * zr ** 1.5) * shaft
            # the heel leans forward a little as it rises; the shaft front leans back
            du = 0.0
            if u < 0.1:
                du = 0.030 * zr
            lx = sd * (W(u) - 0.003) * sc
            if u in (0.0, 1.0):
                lx = sd * max(W(u) - 0.003, 0.001) * sc
            row.append(b.bm.verts.new(to_world(lx, u + du, ZS + Hh(u) * (zr ** 0.85))))
        rings.append(row)
    for j in range(JL):
        zr = (j + 0.5) / JL
        for i in range(NO):
            i2 = (i + 1) % NO
            u = (outline[i][0] + outline[i2][0]) / 2
            if u > 0.80 and zr < 0.75:
                mi = m_dark if u > 0.9 or zr < 0.3 else m_main        # toe bumper + cap
                if u <= 0.9 and zr >= 0.3:
                    mi = m_main
            elif u < 0.20 and zr < 0.5:
                mi = m_dark                                            # heel counter
            elif u < 0.47 and zr > 0.84:
                mi = m_dark                                            # padded collar
            elif 0.30 < u < 0.52 and zr < 0.26:
                mi = m_acc                                             # yellow side flash
            else:
                mi = m_main
            b._tag([b.bm.faces.new((rings[j][i], rings[j][i2], rings[j + 1][i2], rings[j + 1][i]))], mi)
    b._tag([b.bm.faces.new(rings[0][::-1])], m_dark, False)
    # shaft opening plug + collar roll
    shaft_top = [v for v, (u, sd) in zip(rings[JL], outline) if u < 0.44]
    c_top = sum((v.co for v in shaft_top), Vector()) / len(shaft_top)
    b.cyl(G.place(c_top + Vector((0, 0, -0.012)), Vector((0, 0, 1))), 0.038, 0.02, m_in, sides=14)
    order = sorted(shaft_top, key=lambda v: math.atan2(v.co.y - c_top.y, v.co.x - c_top.x))
    b.tube([v.co.copy() for v in order], 0.009, m_dark, sides=6, closed=True)

    # tongue + laces along the instep ridge and up the shaft front
    def ridge(u, off=0.0):
        return to_world(0.0, u, ZS + Hh(u) + off)

    lace_u = [0.74, 0.68, 0.62, 0.56, 0.515, 0.48, 0.455, 0.435]
    tong = [ridge(u, 0.002) for u in np.linspace(0.78, 0.40, 14)]
    b.ribbon(tong + [tong[-1] + Vector((0, 0.012, 0.035))], Vector((0, -0.5, 1)).normalized(), 0.040, 0.007, m_main)
    lw = 0.021
    prev = None
    for k, u in enumerate(lace_u):
        zc = ZS + Hh(u) * 0.93 + 0.004
        a = to_world(-lw, u, zc)
        c = to_world(lw, u, zc)
        mid = ridge(u, 0.010)
        b.tube(G.smooth_path([a, mid, c], 6), 0.0032, m_lace, sides=6)
        for e in (a, c):
            b.cyl(G.place(e, Vector((0, -0.3, 1))), 0.0048, 0.004, m_dark, sides=8)
        if prev:
            b.tube(G.smooth_path([prev[0], (prev[0] + c) / 2 + Vector((0, -0.002, 0.008)), c], 6), 0.003, m_lace, sides=6)
            b.tube(G.smooth_path([prev[1], (prev[1] + a) / 2 + Vector((0, -0.002, 0.011)), a], 6), 0.003, m_lace, sides=6)
        prev = (a, c)
    # bow
    top = ridge(lace_u[-1], 0.012)
    for sd in (1, -1):
        loop = [top, top + Vector((sd * sgn * 0.030, -0.014, 0.012)), top + Vector((sd * sgn * 0.046, -0.022, -0.006)),
                top + Vector((sd * sgn * 0.026, -0.020, -0.014)), top + Vector((0, -0.006, 0.0))]
        b.tube(G.smooth_path(loop, 12), 0.0032, m_lace, sides=6)
        tail = [top, top + Vector((sd * sgn * 0.014, -0.022, -0.020)), top + Vector((sd * sgn * 0.026, -0.030, -0.052))]
        b.tube(G.smooth_path(tail, 8), 0.003, m_lace, sides=6)
    # side triangle badge and heel pull loop
    for sd in (1,):
        u0 = 0.27
        base_p = to_world(sd * (W(u0) + 0.002), u0, ZS + 0.105)
        nrm = Vector((sd * sgn, 0, 0))
        tri = [base_p + Vector((0, -0.020, -0.014)), base_p + Vector((0, 0.020, -0.014)), base_p + Vector((0, 0, 0.020))]
        b.poly([p + nrm * 0.0035 for p in tri], m_acc, thick=0.002, normal=nrm)
        tri2 = [base_p + (p - base_p) * 0.45 + Vector((0, 0, -0.002)) for p in tri]
        b.poly([p + nrm * 0.006 for p in tri2], m_dark, thick=0.001, normal=nrm)
    hp = to_world(0, 0.03, ZS + 0.20)
    b.tube(G.smooth_path([hp + Vector((0, 0.004, -0.02)), hp + Vector((0, 0.022, 0.0)), hp + Vector((0, 0.010, 0.024)), hp + Vector((0, -0.004, 0.006))], 10),
           0.0045, m_acc, sides=6, flat=2.0, up=Vector((1, 0, 0)))
    return b.finish()


objs = [boot(1), boot(-1)]

# =================================================================== BELT + GEAR
pants_bvh = bvh_of(bpy.data.objects["Pants"])
body_bvh = bvh_of(body)
gb = G.Builder("BeltGear")
gb.set_bone("Hips")
m_belt = gb.mat("belt", "#2b2327")
m_met = gb.mat("metal", MET)
m_yel = gb.mat("gear_yellow", YEL)
m_dk = gb.mat("gear_dark", "#2f2a33")
m_grey = gb.mat("gear_grey", "#6f6a72")
m_red = gb.mat("strap_red", "#c8324a")
m_cyan = gb.mat("canister_glow", "#58e6e0", emit=1.5)
m_scr = gb.mat("screen_glow", "#6ff0e6", emit=1.5)
m_org = gb.mat("gear_orange", "#e2632b")


def hip_pt(az, zz, off=0.0):
    """Point on the outside of the pants at azimuth az (0 = front, +90 = her left) and height zz."""
    d = Vector((math.sin(az), -math.cos(az), 0))
    o = Vector((0, -0.02, zz))
    h = pants_bvh.ray_cast(o + d * 0.27, -d, 0.27)     # start inside the reach of the hands
    if h[0] is None:
        h2 = body_bvh.ray_cast(o + d * 0.27, -d, 0.27)
        p = h2[0] if h2[0] is not None else o + d * 0.12
    else:
        p = h[0]
    return p + d * off, d


NB = 64
bpts, bn = [], []
for i in range(NB):
    az = 2 * math.pi * i / NB
    zz = 0.905 - 0.016 * math.sin(az) - 0.006 * math.cos(az)        # slung lower on her right
    p, d = hip_pt(az, zz, 0.004)
    bpts.append(p)
    bn.append(d)
for _ in range(4):
    bpts = [(bpts[(i - 1) % NB] + bpts[i] * 2 + bpts[(i + 1) % NB]) / 4 for i in range(NB)]
gb.ribbon(bpts, bn, 0.036, 0.006, m_belt, closed=True)
for i in range(0, NB, 4):      # eyelets / studs
    gb.cyl(G.place(bpts[i] + bn[i] * 0.0065, bn[i]), 0.0042, 0.003, m_met, sides=8)


def belt_frame(az_deg, drop=0.0, out=0.0):
    i = int(round((az_deg % 360) / 360 * NB)) % NB
    p = bpts[i] + bn[i] * (0.006 + out) + Vector((0, 0, -drop))
    tan = (bpts[(i + 1) % NB] - bpts[(i - 1) % NB]).normalized()
    return p, bn[i], tan


# buckle
p, nrm, tan = belt_frame(4)
gb.box(G.place(p, nrm, tan), (0.050, 0.044, 0.008), m_met, bevel=0.003)
gb.box(G.place(p + nrm * 0.004, nrm, tan), (0.030, 0.026, 0.006), m_dk, bevel=0.002)
# belt loops
for azd in (40, 150, 215, 320):
    p, nrm, tan = belt_frame(azd)
    gb.box(G.place(p, nrm, tan), (0.012, 0.050, 0.006), m_belt, bevel=0.002)

# ---- the Walkman on her right-front hip
p, nrm, tan = belt_frame(-42, drop=0.048, out=0.010)
WM = G.place(p + nrm * 0.016, nrm, tan)          # local x = along belt, y = up-ish (z x x), z = outward
up_l = Vector((0, 1, 0))
gb.box(WM, (0.098, 0.070, 0.032), m_yel, bevel=0.006, segs=3)
gb.box(WM @ Matrix.Translation((0, -0.004, 0.0165)), (0.066, 0.036, 0.004), m_dk, bevel=0.003)          # cassette window
for sx in (-0.016, 0.016):
    gb.cyl(WM @ Matrix.Translation((sx, -0.004, 0.019)), 0.0085, 0.003, m_met, sides=12)
    gb.cyl(WM @ Matrix.Translation((sx, -0.004, 0.0205)), 0.0035, 0.003, m_dk, sides=8)
gb.box(WM @ Matrix.Translation((0, 0.024, 0.0165)), (0.070, 0.008, 0.003), m_dk, bevel=0.001)           # label strip
for k in range(4):                                                                                      # top keys
    gb.box(WM @ Matrix.Translation((-0.030 + k * 0.020, 0.038, 0.004)), (0.014, 0.008, 0.012), m_dk if k else m_org, bevel=0.002)
gb.box(WM @ Matrix.Translation((0.051, 0.0, 0.0)), (0.006, 0.050, 0.020), m_dk, bevel=0.002)             # side grip
gb.cyl(WM @ Matrix.Translation((-0.038, 0.037, 0.0)) @ Matrix.Rotation(math.pi / 2, 4, 'X'), 0.005, 0.008, m_met, sides=10)   # jack
gb.box(G.place(p + Vector((0, 0, 0.040)) + nrm * 0.004, nrm, tan), (0.022, 0.05, 0.008), m_belt, bevel=0.002)            # hanger strap
walkman_jack = WM @ Vector((-0.038, 0.043, 0.0))

# ---- pouches
for azd, sz, drop, col in ((62, (0.060, 0.075, 0.034), 0.040, m_dk), (118, (0.070, 0.062, 0.030), 0.034, m_grey), (-128, (0.062, 0.070, 0.032), 0.036, m_dk)):
    p, nrm, tan = belt_frame(azd, drop=drop, out=0.006)
    M = G.place(p + nrm * (sz[2] / 2), nrm, tan)
    gb.box(M, sz, col, bevel=0.007, segs=2)
    gb.box(M @ Matrix.Translation((0, sz[1] * 0.27, sz[2] * 0.5)), (sz[0] * 1.04, sz[1] * 0.5, 0.006), m_belt, bevel=0.002)
    gb.cyl(M @ Matrix.Translation((0, sz[1] * 0.08, sz[2] * 0.5 + 0.004)), 0.006, 0.004, m_met, sides=10)
    gb.box(M @ Matrix.Translation((0, -sz[1] * 0.3, sz[2] * 0.5)), (sz[0] * 0.5, 0.008, 0.004), m_yel, bevel=0.001)

# ---- glow canisters hanging on her left-front
for k, (azd, ln, col) in enumerate(((28, 0.085, m_cyan), (16, 0.070, m_cyan))):
    p, nrm, tan = belt_frame(azd, drop=0.030, out=0.004)
    top_ = p + nrm * 0.016
    axis = Vector((0, 0, -1))
    M = G.place(top_ + axis * (ln / 2 + 0.012), axis, tan)
    gb.cyl(M, 0.0135, ln, col, sides=14)
    for e in (-1, 1):
        gb.cyl(M @ Matrix.Translation((0, 0, e * (ln / 2 + 0.005))), 0.0155, 0.012, m_dk if e > 0 else m_met, sides=14, bevel=0.002)
    for e in (-0.25, 0.25):
        gb.cyl(M @ Matrix.Translation((0, 0, e * ln)), 0.0148, 0.004, m_dk, sides=14)
    gb.torus(G.place(top_ + Vector((0, 0, 0.004)), tan), 0.011, 0.0025, m_met, seg=14, sub=6)
    gb.box(G.place(p + Vector((0, 0, 0.026)), nrm, tan), (0.012, 0.04, 0.006), m_belt, bevel=0.002)

# ---- carabiner + wrench on her left hip, small tool handles at the back
p, nrm, tan = belt_frame(92, drop=0.034, out=0.004)
gb.torus(G.place(p + nrm * 0.01, tan), 0.020, 0.0034, m_met, seg=18, sub=6, flat=1.0)
wr_top = p + Vector((0, 0, -0.020)) + nrm * 0.012
gb.box(G.place(wr_top + Vector((0, 0, -0.050)), nrm, tan), (0.012, 0.100, 0.005), m_met, bevel=0.002)
gb.torus(G.place(wr_top + Vector((0, 0, -0.108)), nrm), 0.011, 0.0045, m_met, seg=12, sub=6, arc=0.8)
gb.torus(G.place(wr_top + Vector((0, 0, 0.004)), nrm), 0.009, 0.004, m_met, seg=12, sub=6)
for k, azd in enumerate((170, 186, 200)):
    p, nrm, tan = belt_frame(azd, drop=0.0, out=0.004)
    gb.cyl(G.place(p + nrm * 0.012 + Vector((0, 0, 0.012)), Vector((0, 0, 1))), 0.008, 0.07, (m_yel, m_dk, m_org)[k], sides=10, bevel=0.002)
objs.append(gb.finish())

# ---- red hanging straps (their own object: driven by the Strap bones)
sb = G.Builder("Straps")
m_red = sb.mat("strap_red", "#c8324a")
m_met2 = sb.mat("metal", MET)
m_dk2 = sb.mat("gear_dark", "#2f2a33")
strap_roots = []
for k, (azd, ln, wdt) in enumerate(((-20, 0.40, 0.030), (-66, 0.31, 0.026))):
    sb.set_bone("Strap%d" % (k + 1))
    p, nrm, tan = belt_frame(azd, drop=0.016, out=0.002)
    pts, nrms = [], []
    for q in range(13):
        t = q / 12
        zz = p.z - ln * t
        az = math.radians(azd) + 0.10 * t * (1 if k == 0 else -1)
        hp, d = hip_pt(az, zz, 0.010 + 0.014 * math.sin(math.pi * t))
        hp.z = zz
        pts.append(hp)
        nrms.append(d)
    sb.ribbon(pts, nrms, wdt, 0.004, m_red)
    for t_i, sz in ((4, (0.014, wdt + 0.008, 0.008)), (10, (0.020, wdt + 0.010, 0.009))):
        tanv = (pts[t_i + 1] - pts[t_i - 1]).normalized()
        sb.box(G.place(pts[t_i] + nrms[t_i] * 0.004, nrms[t_i], tanv), sz, m_met2 if t_i == 10 else m_dk2, bevel=0.002)
    strap_roots.append([list(pts[0]), list(pts[-1])])
so = sb.finish()
so["strap_roots"] = json.dumps(strap_roots)
objs.append(so)

# =================================================================== HEADPHONES
hb = G.Builder("Headphones")
hb.set_bone("Head")
h_yel = hb.mat("phones_yellow", "#f6bd1d")
h_dk = hb.mat("phones_dark", "#2a2529")
h_met = hb.mat("metal", MET)
h_red = hb.mat("phones_red", "#d3303c")
z_ear = L["z_eye"] - 0.004
y_ear = -0.012
cup_c = {}
for sgn in (1, -1):
    h = body_bvh.ray_cast(Vector((sgn * 0.4, y_ear, z_ear)), Vector((-sgn, 0, 0)), 0.5)
    xs = abs(h[0].x) if h[0] is not None else 0.1
    xs = min(xs, 0.108)
    xs += 0.004
    outv = Vector((sgn, 0.06, 0.0)).normalized()
    c0 = Vector((sgn * (xs - 0.004), y_ear, z_ear))
    M = G.place(c0, outv, Vector((0, 0, 1)))
    hb.torus(M @ Matrix.Translation((0, 0, 0.010)), 0.050, 0.017, h_dk, seg=22, sub=8, flat=0.9)          # cushion
    hb.cyl(M @ Matrix.Translation((0, 0, 0.032)), 0.068, 0.030, h_yel, sides=28, bevel=0.008)                # shell
    hb.cyl(M @ Matrix.Translation((0, 0, 0.050)), 0.056, 0.008, h_yel, sides=28, bevel=0.003)                # raised face
    hb.torus(M @ Matrix.Translation((0, 0, 0.0485)), 0.058, 0.0030, h_dk, seg=28, sub=6)                     # inlay ring
    # the triangle graphic
    tri = [Vector((-0.024, -0.028, 0.0545)), Vector((-0.024, 0.028, 0.0545)), Vector((0.032, 0.0, 0.0545))]
    if sgn < 0:
        tri = [Vector((-p.x, p.y, p.z)) for p in tri][::-1]
    hb.poly([M @ p for p in tri], h_dk, thick=0.0018, normal=outv)
    tri_in = [Vector((p.x * 0.45 + (0.002 if sgn > 0 else -0.002), p.y * 0.45, 0.0565)) for p in tri]
    hb.poly([M @ p for p in tri_in], h_yel, thick=0.001, normal=outv)
    hb.box(M @ Matrix.Translation((0.0, -0.060, 0.030)), (0.012, 0.020, 0.012), h_red, bevel=0.003)          # red tab at the back
    cup_c[sgn] = M @ Vector((0, 0, 0.03))
    # yoke: fork from the band end down both sides of the cup
    for fy in (-1, 1):
        yoke = [M @ Vector((0.0, fy * 0.070, 0.032)), M @ Vector((0.036, fy * 0.068, 0.034)), M @ Vector((0.076, fy * 0.034, 0.028)), M @ Vector((0.088, 0, 0.018))]
        hb.tube(G.smooth_path(yoke, 8), 0.0055, h_dk, sides=6)
        hb.cyl(M @ Matrix.Translation((0, fy * 0.070, 0.032)) @ Matrix.Rotation(math.pi / 2, 4, 'X'), 0.007, 0.008, h_met, sides=8)
# headband over the crown
c1, c2 = cup_c[1], cup_c[-1]
top_z = L["z_top"] + 0.052
band = []
bup = []
for i in range(25):
    t = i / 24
    a = math.pi * t
    # super-ellipse arch from the left cup over the top to the right cup, tilted slightly back
    xx = math.cos(a)
    zz = math.sin(a)
    p = Vector((abs(xx) ** 0.80 * math.copysign(1, xx) * (abs(c1.x) + 0.012), y_ear + 0.022 * zz, (z_ear + 0.085) + (top_z - z_ear - 0.085) * zz ** 0.72))
    band.append(p)
    bup.append(Vector((xx * 0.8, 0, zz + 0.2)).normalized())
hb.ribbon(band, bup, 0.044, 0.012, h_yel, mi_in=h_dk)
for i in (5, 19):
    tan = (band[i + 1] - band[i - 1]).normalized()
    hb.box(G.place(band[i] + bup[i] * 0.005, bup[i], tan), (0.030, 0.040, 0.016), h_dk, bevel=0.003)
objs.append(hb.finish())

# ---- cable: Walkman jack up to the right cup (weights come from the body)
cb = G.Builder("Cable")
c_yel = cb.mat("cable_yellow", "#e9b11c")
rc = cup_c[-1]
path = [walkman_jack, walkman_jack + Vector((-0.012, -0.020, 0.030)), Vector((-0.118, -0.100, 1.00)), Vector((-0.085, -0.118, 1.10)),
        Vector((-0.050, -0.070, 1.235)), Vector((-0.070, -0.035, 1.315)), rc + Vector((0.012, -0.012, -0.075)), rc + Vector((0.0, -0.004, -0.058))]
cb.tube(G.smooth_path(path, 44), 0.0034, c_yel, sides=6)
objs.append(cb.finish())

# =================================================================== WRIST DEVICES
EL, WR = J("lowerarm01.L"), J("wrist.L")
for sgn, s in ((1, "Left"), (-1, "Right")):
    wb = G.Builder("WristDev" + s[0])
    wb.set_bone(s + "LowerArm")
    w_dk = wb.mat("device_dark", "#2c2730")
    w_yel = wb.mat("gear_yellow", YEL)
    w_met = wb.mat("metal", MET)
    w_scr = wb.mat("screen_glow", "#6ff0e6", emit=1.5)
    el = Vector((EL.x * sgn, EL.y, EL.z))
    wr = Vector((WR.x * sgn, WR.y, WR.z))
    ax = (wr - el).normalized()
    ln = 0.074 if sgn > 0 else 0.058
    c = wr - ax * (0.030 + ln / 2)
    side = ax.cross(Vector((0, 0, 1))).normalized()
    upv = side.cross(ax).normalized()                  # roughly up / back of the forearm
    M = G.place(c, ax, upv)                             # local x = up side of the arm
    wb.cyl(M, 0.0385, ln, w_dk, sides=20, bevel=0.005)
    for e in (-1, 1):
        wb.torus(M @ Matrix.Translation((0, 0, e * (ln / 2 - 0.006))), 0.039, 0.0045, w_yel if e < 0 else w_met, seg=20, sub=6)
    # display block on the outer/top side, tilted towards the viewer
    out_dir = (upv * 0.75 + side * (-0.65 * sgn)).normalized()
    D = G.place(c + out_dir * 0.040, out_dir, ax)
    wb.box(D, (ln * 0.86, 0.050, 0.016), w_dk, bevel=0.004)
    wb.box(D @ Matrix.Translation((0, 0, 0.0085)), (ln * 0.62, 0.036, 0.003), w_scr, bevel=0.001)
    wb.box(D @ Matrix.Translation((ln * 0.36, 0, 0.0085)), (0.008, 0.034, 0.004), w_yel, bevel=0.001)
    for k in range(3):
        wb.cyl(D @ Matrix.Translation((-ln * 0.3 + k * 0.014, -0.029, 0.002)) @ Matrix.Rotation(math.pi / 2, 4, 'X'), 0.0035, 0.006, w_met, sides=8)
    # strap buckle underneath
    wb.box(G.place(c - out_dir * 0.040, -out_dir, ax), (ln * 0.5, 0.026, 0.008), w_met, bevel=0.002)
    objs.append(wb.finish())

# =================================================================== CHOKER
ck = G.Builder("Choker")
ck.set_bone("Neck")
k_dk = ck.mat("choker", "#231e22")
k_met = ck.mat("metal", MET)
pts, nr = [], []
for i in range(28):
    az = 2 * math.pi * i / 28
    d = Vector((math.sin(az), -math.cos(az), 0))
    zz = 1.318 + 0.010 * math.cos(az)
    o = Vector((0, -0.012, zz))
    h = body_bvh.ray_cast(o, d, 0.2)
    r = (h[0] - o).length if h[0] is not None else 0.04
    pts.append(o + d * (r + 0.0015))
    nr.append(d)
ck.ribbon(pts, nr, 0.017, 0.004, k_dk, closed=True)
ck.torus(G.place(pts[0] + Vector((0, -0.006, -0.017)), Vector((0, 1, 0.25))), 0.011, 0.0028, k_met, seg=16, sub=6)
ck.box(G.place(pts[0] + nr[0] * 0.004, nr[0], Vector((1, 0, 0))), (0.012, 0.014, 0.005), k_met, bevel=0.002)
objs.append(ck.finish())

print("tris:", {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs})
print("TOTAL tris:", sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.data.objects if o.type == 'MESH'))
U.save_stage("s06_gear")

if "--norender" not in sys.argv:
    rig.hide_render = True
    T.toonify([o for o in bpy.data.objects if o.type == 'MESH'], outline=0.0028)
    U.render_views(os.path.join(U.WIP, "s06_full.png"), views=("front", "q", "side", "back"), center=(0, 0, 0.84), scale=1.85,
                   res=(560, 1000), setup=T.setup_eevee)
    U.render_views(os.path.join(U.WIP, "s06_det.png"), views=("front", "q", (-60, 10)), center=(0, -0.05, 0.85), scale=0.55,
                   res=(700, 700), setup=T.setup_eevee)
    U.render_views(os.path.join(U.WIP, "s06_chest.png"), views=("front", "q", "back"), center=(0, -0.05, 1.2), scale=0.5,
                   res=(700, 700), setup=T.setup_eevee)
    U.render_views(os.path.join(U.WIP, "s06_feet.png"), views=("q", "side", (-40, 20)), center=(0.0, -0.05, 0.15), scale=0.5,
                   res=(700, 500), setup=T.setup_eevee)
