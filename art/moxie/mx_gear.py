"""Moxie's gear: the yellow cassette Walkman at her right hip (CHAR-06) with its cable up to the
headphones, belt pouches and scavenged tools (glowing vial, wrench, a little scanner), the red/pink
hanging straps, and the chunky wrist devices with glowing screens on both wrists (CHAR-09).
"""
import math

from mathutils import Matrix, Vector

import mx_skel as S
from mx_body import arm_point_at, tag
from mx_geo import (TAU, V, basis, interp_profile, catmull, cylinder, extrude_polygon, flat_strip, lathe,
                    look_basis, mirror_copy, resample, rounded_box, set_material, tube_along)
from mx_hair import CUP_C
from mx_outfit import PANTS_TOP, belt_z, body_point, leg_surface


def pelvis_surface(x, z, front=True, off=0.0):
    """Point on the outside of the pants/belt at height z with the given x (front or back)."""
    hw, fd, bd, cy, _sq = interp_profile([(r[0], r[1:]) for r in reversed(PANTS_TOP)], min(z, PANTS_TOP[0][0]))
    hw, fd, bd = hw + off, fd + off, bd + off
    k = 2.0 / 2.2
    best = None
    for i in range(361):
        a = (-math.pi if front else 0.0) + math.pi * i / 360
        c, s = math.cos(a), math.sin(a)
        ex = math.copysign(abs(c) ** k, c)
        ey = math.copysign(abs(s) ** k, s)
        p = V(hw * ex, cy + (fd if s < 0 else bd) * ey, z)
        if best is None or abs(p.x - x) < abs(best.x - x):
            best = p
    return best


# --------------------------------------------------------------------------------------------
# Walkman + cable
# --------------------------------------------------------------------------------------------

WALKMAN_X = -0.098


def walkman_matrix():
    x = WALKMAN_X
    z = belt_z(x) - 0.012
    p = pelvis_surface(x, z, True, 0.030)
    out = V(p.x, p.y - 0.012, 0).normalized()
    out = (out + V(0, -0.6, 0)).normalized()
    return look_basis(p, out, V(0, 0, 1))


def make_walkman():
    m = walkman_matrix()
    parts = []
    W, H, D = 0.086, 0.064, 0.026
    parts.append(rounded_box("walkman_body", (W, H, D), bevel=0.006, segments=2, material='walkman', matrix=m))
    # cassette window: dark inset with two metal reels and a tape strip
    win = m @ Matrix.Translation(V(0.0, -0.004, D * 0.5))
    parts.append(rounded_box("walkman_window", (0.058, 0.030, 0.004), bevel=0.003, material='dark', matrix=win))
    for sx in (-1, 1):
        parts.append(cylinder("walkman_reel", 0.0075, 0.004, n=10, material='metal',
                              matrix=win @ Matrix.Translation(V(sx * 0.016, 0.0, 0.002))))
        parts.append(cylinder("walkman_hub", 0.0035, 0.005, n=6, material='dark',
                              matrix=win @ Matrix.Translation(V(sx * 0.016, 0.0, 0.003))))
    # label stripe above the window
    parts.append(rounded_box("walkman_label", (0.060, 0.008, 0.003), bevel=0.0012, material='dark',
                             matrix=m @ Matrix.Translation(V(0, 0.020, D * 0.5))))
    # transport buttons on top
    for i in range(4):
        parts.append(rounded_box("walkman_btn", (0.012, 0.008, 0.010), bevel=0.002,
                                 material='dark' if i % 2 else 'metal',
                                 matrix=m @ Matrix.Translation(V(-0.024 + i * 0.015, H * 0.5 + 0.003, 0.0))))
    # side volume wheel
    parts.append(cylinder("walkman_wheel", 0.010, 0.006, n=12, material='metal',
                          matrix=m @ Matrix.Translation(V(W * 0.5 + 0.002, 0.008, 0.0)) @
                          Matrix.Rotation(math.pi / 2, 4, 'Y')))
    # belt clip behind
    parts.append(rounded_box("walkman_clip", (0.026, 0.050, 0.006), bevel=0.002, material='metal',
                             matrix=m @ Matrix.Translation(V(0.0, 0.010, -D * 0.5 - 0.004))))
    for p in parts:
        tag(p, "pelvis")
    return parts


def walkman_jack():
    m = walkman_matrix()
    return m @ V(0.030, 0.034, 0.002)


def make_cable():
    jack = walkman_jack()
    pts = [jack, jack + V(0.004, -0.006, 0.020)]
    for x, z, off in ((-0.070, 0.960, 0.016), (-0.048, 1.030, 0.014), (-0.026, 1.095, 0.026),
                      (-0.012, 1.160, 0.026), (-0.010, 1.215, 0.020)):
        pts.append(body_point(x, z, off))
    # up the collarbone, round the side of the neck behind the jaw line, into the right cup
    pts += [V(-0.030, -0.036, 1.268), V(-0.058, -0.004, 1.300), V(-0.082, 0.024, 1.340),
            CUP_C * V(-1, 1, 1) + V(0.010, -0.010, -0.050)]
    pts[-1] = V(-CUP_C.x + 0.008, CUP_C.y - 0.012, CUP_C.z - 0.046)
    pts = [S.head_xform(p) if p.z > 1.33 else p for p in pts]
    path = resample(catmull(pts, 6), 32)
    cable = tube_along("cable", path, lambda t: 0.0028, n=4, up=V(0, -1, 0))
    set_material(cable, 'walkman')
    plug = cylinder("cable_plug", 0.0045, 0.014, n=8, material='dark',
                    matrix=look_basis(jack + V(0, 0, 0.004), V(0, 0, 1), V(0, -1, 0)))
    cable["wspec"] = "cable"
    tag(plug, "pelvis")
    return [cable, plug]


# --------------------------------------------------------------------------------------------
# pouches and tools (her left hip), scanner on the right thigh
# --------------------------------------------------------------------------------------------

def make_pouches():
    parts = []
    for x, w, h, d, front in ((0.118, 0.050, 0.060, 0.030, True), (0.152, 0.040, 0.052, 0.028, True)):
        z = belt_z(x) - 0.020
        p = pelvis_surface(x, z, front, 0.020 + d * 0.5)
        out = V(p.x, p.y - 0.012, 0).normalized()
        m = look_basis(p, out, V(0, 0, 1))
        parts.append(rounded_box("pouch", (w, h, d), bevel=0.007, segments=2, material='pouch', matrix=m,
                                 smooth=True))
        parts.append(rounded_box("pouch_flap", (w + 0.004, 0.022, d * 0.5), bevel=0.004, material='pouch',
                                 matrix=m @ Matrix.Translation(V(0, h * 0.5 - 0.008, d * 0.32)), smooth=True))
        parts.append(rounded_box("pouch_tab", (0.012, 0.016, 0.004), bevel=0.0015, material='walkman',
                                 matrix=m @ Matrix.Translation(V(0, h * 0.5 - 0.018, d * 0.58))))
    # back-side pouch
    x = 0.128
    z = belt_z(x) - 0.024
    p = pelvis_surface(x, z, False, 0.017)
    out = V(p.x, p.y - 0.012, 0).normalized()
    m = look_basis(p, out, V(0, 0, 1))
    parts.append(rounded_box("pouch_back", (0.060, 0.056, 0.034), bevel=0.008, segments=2, material='pouch',
                             matrix=m, smooth=True))
    parts.append(rounded_box("pouch_back_flap", (0.064, 0.022, 0.018), bevel=0.004, material='dark',
                             matrix=m @ Matrix.Translation(V(0, 0.020, 0.012)), smooth=True))
    # wrench dangling from a ring beside the pouches
    x = 0.086
    z = belt_z(x) - 0.030
    p = pelvis_surface(x, z, True, 0.022)
    wm = look_basis(p, V(p.x, p.y - 0.012, 0).normalized(), V(0.15, 0, 1)) @ Matrix.Translation(V(0, -0.050, 0.004))
    parts.append(rounded_box("wrench_shaft", (0.010, 0.070, 0.004), bevel=0.0015, material='metal', matrix=wm))
    jaw = [(-0.012, 0.0), (0.012, 0.0), (0.014, 0.020), (0.006, 0.022), (0.004, 0.010), (-0.004, 0.010),
           (-0.006, 0.022), (-0.014, 0.020)]
    parts.append(extrude_polygon("wrench_jaw", jaw, 0.005, wm @ Matrix.Translation(V(0, -0.033, -0.0025))
                                 @ Matrix.Rotation(math.pi, 4, 'Z'), 'metal'))
    parts.append(lathe("wrench_ring", [(0.008, -0.002), (0.010, 0.0), (0.008, 0.002)], n=10, material='metal',
                       cap_start=False, cap_end=False,
                       axis_mat=Matrix.Rotation(math.pi / 2, 4, 'X'), center=wm @ V(0, 0.040, 0)))
    for q in parts:
        tag(q, "pelvis")
    return parts


def make_hanging_straps():
    """R01's magenta webbing straps at her right hip: one clips to the belt at the front of the hip,
    sweeps down the outside of the thigh in a loose U and clips back on behind the hip; the other
    drops from the same clip down the outer leg to mid-shin with a metal buckle partway along.
    Both are slightly twisted 5 mm webbing and sit to the side of the leg, clear of the zig-zag."""
    parts = []

    def outer(z, a, off):
        # point beside her right leg (built on the left-leg surface, mirrored)
        q = leg_surface(z, a, off)
        return V(-q.x, q.y, q.z)

    xa = -0.118
    za = belt_z(xa) - 0.004
    clip_a = pelvis_surface(xa, za, True, 0.014)
    xb = -0.160
    clip_b = pelvis_surface(xb, belt_z(xb) - 0.004, True, 0.014)
    # U-loop: front clip -> down the outer thigh -> back up to the rear clip
    loop = [clip_a, clip_a + V(0.004, -0.008, -0.040),
            outer(0.740, -1.15, 0.012), outer(0.650, -1.00, 0.016), outer(0.600, -0.70, 0.020),
            outer(0.640, -0.40, 0.016), outer(0.730, -0.15, 0.012), clip_b + V(-0.008, 0.0, -0.040), clip_b]
    tail = [clip_a + V(0.004, -0.004, -0.006), clip_a + V(0.006, -0.010, -0.050),
            outer(0.720, -1.00, 0.010), outer(0.600, -0.82, 0.012), outer(0.500, -0.58, 0.013),
            outer(0.420, -0.40, 0.012), outer(0.360, -0.33, 0.012)]
    for name, ctrl, w, twist in (("hang_loop", loop, 0.026, 0.9), ("hang_tail", tail, 0.024, -0.7)):
        path = resample(catmull(ctrl, 6), 26 if name == "hang_loop" else 20)
        n_ = len(path)

        def up(j, p, n_=n_, twist=twist):
            c = V(-0.10, 0.004, p.z)
            r = V(p.x - c.x, p.y - c.y, 0)
            r = r.normalized() if r.length > 1e-6 else V(-1, 0, 0)
            ang = twist * math.sin(math.pi * j / (n_ - 1))
            side = V(0, 0, 1).cross(r)
            return r * math.cos(ang) + side * math.sin(ang)
        parts.append(flat_strip(name, path, lambda t, w=w: w, 0.005, up, 'strap'))
        if name == "hang_tail":
            # buckle partway down and a metal tip on the end
            for idx, size in ((9, (w + 0.010, 0.020, 0.008)), (n_ - 1, (w + 0.004, 0.012, 0.007))):
                pnt = path[idx]
                d = (path[min(idx + 1, n_ - 1)] - path[idx - 1]).normalized()
                nrm = up(idx, pnt)
                parts.append(rounded_box("strap_buckle", size, bevel=0.002, material='metal',
                                         matrix=look_basis(pnt + nrm * 0.003, nrm, -d)))
    # the belt clips
    nrm = V(clip_a.x, clip_a.y - 0.012, 0).normalized()
    parts.append(rounded_box("strap_clip", (0.034, 0.030, 0.010), bevel=0.003, material='metal',
                             matrix=look_basis(clip_a + nrm * 0.004, nrm, V(0, 0, 1))))
    nrm_b = V(clip_b.x, clip_b.y - 0.012, 0).normalized()
    parts.append(rounded_box("strap_clip", (0.030, 0.026, 0.009), bevel=0.003, material='metal',
                             matrix=look_basis(clip_b + nrm_b * 0.004, nrm_b, V(0, 0, 1))))
    for q in parts:
        q["wspec"] = "hangstrap"
    return parts


def _hip_frame(x, z, front, off, tilt=0.0):
    p = pelvis_surface(x, z, front, off)
    out = V(p.x, p.y - 0.012, 0).normalized()
    return look_basis(p, out, V(math.sin(tilt), 0, math.cos(tilt))), p, out


def make_belt_tools():
    """CHAR-09's futuristic tool belt (R01): a hex canister with a glowing vial, a screen gadget in
    a yellow frame, a carabiner cluster with a key, a multitool and a boxy battery pack, some hung
    on short chains so they break the silhouette below the belt line."""
    parts = []
    # hex canister with a cyan glowing vial, hanging on a chain behind her right hip
    x = -0.156
    zb = belt_z(x)
    top = pelvis_surface(x, zb - 0.020, False, 0.006)
    hang = top + V(top.x, top.y - 0.012, 0).normalized() * 0.016 + V(0, 0, -0.058)
    sd = (hang + V(0, 0, 0.034) - top)
    parts.append(rounded_box("canister_strap", (0.010, sd.length + 0.012, 0.004), bevel=0.0012, material='belt',
                             matrix=look_basis(top + sd * 0.5, V(top.x, top.y - 0.012, 0).normalized(),
                                               sd.normalized())))
    cm = Matrix.Translation(hang) @ Matrix.Rotation(math.radians(-8), 4, 'Y')
    parts.append(cylinder("canister_cap", 0.017, 0.010, n=6, material='metal',
                          matrix=cm @ Matrix.Translation(V(0, 0, 0.030))))
    parts.append(cylinder("canister_cap", 0.017, 0.010, n=6, material='metal',
                          matrix=cm @ Matrix.Translation(V(0, 0, -0.030))))
    parts.append(cylinder("canister_vial", 0.0125, 0.052, n=8, material='wrist_device_glow', matrix=cm))
    for k in range(3):
        a = TAU * k / 3
        parts.append(rounded_box("canister_bar", (0.004, 0.004, 0.054), bevel=0.001, material='walkman',
                                 matrix=cm @ Matrix.Translation(V(math.cos(a) * 0.0145, math.sin(a) * 0.0145, 0))))
    # screen gadget in a yellow frame, clipped at the back of her right hip
    m, p, out = _hip_frame(-0.104, belt_z(-0.104) - 0.030, False, 0.016)
    parts.append(rounded_box("gadget_frame", (0.050, 0.044, 0.020), bevel=0.005, material='walkman', matrix=m))
    parts.append(rounded_box("gadget_body", (0.040, 0.034, 0.008), bevel=0.003, material='wrist_device',
                             matrix=m @ Matrix.Translation(V(0, 0, 0.008))))
    parts.append(rounded_box("gadget_screen", (0.028, 0.020, 0.004), bevel=0.0015, material='wrist_device_glow',
                             matrix=m @ Matrix.Translation(V(0, 0.002, 0.012))))
    parts.append(cylinder("gadget_antenna", 0.002, 0.030, n=5, material='metal',
                          matrix=m @ Matrix.Translation(V(0.018, 0.034, 0.0))))
    # boxy battery pack at the back, a little right of centre, with a yellow stripe and a glow cell
    m, p, out = _hip_frame(-0.036, belt_z(-0.036) - 0.028, False, 0.018)
    parts.append(rounded_box("battery", (0.060, 0.046, 0.026), bevel=0.005, material='pouch', matrix=m))
    parts.append(rounded_box("battery_stripe", (0.062, 0.010, 0.027), bevel=0.002, material='walkman',
                             matrix=m @ Matrix.Translation(V(0, 0.010, 0))))
    parts.append(rounded_box("battery_cell", (0.012, 0.008, 0.004), bevel=0.0012, material='wrist_device_glow',
                             matrix=m @ Matrix.Translation(V(0.018, -0.010, 0.013))))
    # multitool in a holster at the back-left
    m, p, out = _hip_frame(0.060, belt_z(0.060) - 0.034, False, 0.012)
    parts.append(rounded_box("multitool_holster", (0.030, 0.064, 0.016), bevel=0.004, material='belt', matrix=m))
    parts.append(rounded_box("multitool", (0.020, 0.050, 0.010), bevel=0.003, material='metal',
                             matrix=m @ Matrix.Translation(V(0, 0.030, 0.002))))
    parts.append(rounded_box("multitool_grip", (0.021, 0.022, 0.011), bevel=0.003, material='walkman',
                             matrix=m @ Matrix.Translation(V(0, 0.046, 0.002))))
    # carabiner cluster with a key, hanging off the belt at her left front hip
    x = 0.140
    top = pelvis_surface(x, belt_z(x) - 0.010, True, 0.016)
    out = V(top.x, top.y - 0.012, 0).normalized()
    for k, (dx, ang, size) in enumerate(((0.0, 0.0, 1.0), (0.008, 0.35, 0.85), (-0.006, -0.30, 0.75))):
        c = top + V(dx, 0, -0.024 * size) + out * 0.004 * k
        mk = look_basis(c, out, V(math.sin(ang), 0, math.cos(ang)))
        pts = [V(-0.008, 0.024, 0), V(0.008, 0.024, 0), V(0.011, 0.0, 0), V(0.006, -0.024, 0),
               V(-0.006, -0.024, 0), V(-0.011, 0.0, 0)]
        pts = [mk @ (q * size) for q in pts]
        ring = tube_along("carabiner", resample(catmull(pts + [pts[0]], 4), 10), lambda t: 0.0022, n=4,
                          up=out, cap_start=False, cap_end=False)
        set_material(ring, 'metal' if k != 1 else 'walkman')
        parts.append(ring)
    km = look_basis(top + V(0.004, 0.0, -0.054), out, V(0.3, 0, 1))
    parts.append(rounded_box("key_bow", (0.016, 0.016, 0.003), bevel=0.002, material='metal', matrix=km))
    parts.append(rounded_box("key_blade", (0.006, 0.026, 0.002), bevel=0.0008, material='metal',
                             matrix=km @ Matrix.Translation(V(0, -0.020, 0))))
    for q in parts:
        tag(q, "pelvis")
    return parts


# --------------------------------------------------------------------------------------------
# wrist devices
# --------------------------------------------------------------------------------------------

def make_wrist_device():
    d0 = 0.442
    c = arm_point_at(d0)
    t = S.FOREARM_DIR
    up = V(0, 0, 1)
    m = look_basis(c, t, up)       # local Z along the forearm, Y up-ish
    parts = []
    band = lathe("wrist_band", [(0.024, -0.020), (0.030, -0.018), (0.031, -0.008), (0.031, 0.008),
                                (0.030, 0.018), (0.024, 0.020)], n=12, material='wrist_device',
                 cap_start=False, cap_end=False)
    band.data.transform(m)
    band.data.set_sharp_from_angle(angle=math.radians(40))
    parts.append(band)
    # yellow ridge rings
    for dz in (-0.017, 0.017):
        r = lathe("wrist_ring", [(0.030, -0.003), (0.033, -0.002), (0.033, 0.002), (0.030, 0.003)], n=12,
                  material='walkman', cap_start=False, cap_end=False)
        r.data.transform(m @ Matrix.Translation(V(0, 0, dz)))
        parts.append(r)
    # screen module on the back of the wrist (dorsal = lateral/up in rest)
    dorsal = (V(1, 0, 0.6) - t * V(1, 0, 0.6).dot(t)).normalized()
    mm = look_basis(c + dorsal * 0.031, dorsal, t)
    parts.append(rounded_box("wrist_module", (0.032, 0.040, 0.014), bevel=0.004, material='wrist_device',
                             matrix=mm))
    parts.append(rounded_box("wrist_screen", (0.022, 0.026, 0.004), bevel=0.0015, material='wrist_device_glow',
                             matrix=mm @ Matrix.Translation(V(0, 0.002, 0.007))))
    parts.append(cylinder("wrist_knob", 0.004, 0.008, n=8, material='walkman',
                          matrix=mm @ Matrix.Translation(V(0.018, -0.012, 0.002)) @ Matrix.Rotation(math.pi / 2, 4, 'Y')))
    for p in parts:
        tag(p, "forearm.L")
    return parts


def build_gear():
    wd = make_wrist_device()
    wr = [mirror_copy(p, p.name + ".R") for p in wd]
    for p in wr:
        p["wspec"] = "forearm.R"
    return (make_walkman() + make_cable() + make_pouches() + make_belt_tools() + make_hanging_straps()
            + wd + wr)
