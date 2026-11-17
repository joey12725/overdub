"""Belt kit and small gear: choker, wrist devices, belt with Walkman / pouches / tools, hanging
straps, headphone cable."""
import math

import numpy as np

from mc_gear import basis, finish, lathe
from mc_util import (V, Mesh, catmull, circle_profile, cylinder, loft, norm, rbox, resample, sweep,
                     torus)


def build_choker():
    from mc_head import NECK_CUT_Z, NECK_R, neck_centre_y
    m = Mesh()
    c = V(0, neck_centre_y(NECK_CUT_Z), NECK_CUT_Z)
    prof = circle_profile(6, 0.0075, 0.0022, power=3.0)
    rings = []
    for k in range(24):
        a = 2 * math.pi * k / 24
        out = V(math.sin(a), -math.cos(a) * 0.96, 0)
        p = c + out * (NECK_R + 0.0035)
        rings.append([p + V(0, 0, 1) * px + norm(out) * py for px, py in prof])
    rings.append(rings[0])
    loft(np.array(rings), "choker", m)
    ring_c = c + V(0, -(NECK_R + 0.0075), -0.012)
    torus(ring_c, V(0, 1, 0.15), 0.0085, 0.0018, "metal", m, n=16, m=6)
    cylinder(c + V(0, -(NECK_R + 0.006), -0.002), c + V(0, -(NECK_R + 0.0065), -0.006), 0.003,
             "metal", m, n=8)
    return finish(m, "Choker", 50)


def build_wrist_devices():
    """Chunky forearm devices with glowing screens; a strap band hides the glove/arm seam."""
    m = Mesh()
    for s in (1, -1):
        ax = V(s, 0, 0)
        base = V(s * 0.542, 0.011, 1.300)
        lathe(m, base, ax, [(0.0255, 0.0), (0.0300, 0.002), (0.0310, 0.012), (0.0290, 0.014),
                            (0.0290, 0.017), (0.0320, 0.019), (0.0325, 0.036), (0.0300, 0.038),
                            (0.0300, 0.041), (0.0312, 0.043), (0.0305, 0.052), (0.0255, 0.054)],
              "device", n=16, cap_end=False)
        hc = base + ax * 0.027 + V(0, 0, 0.0335)
        rbox(hc, (0.024, 0.021, 0.0075), 0.0035, "device", m, seg=2)
        rbox(hc + V(0, 0, 0.0068), (0.0185, 0.0155, 0.0016), 0.0008, "screen_glow", m, seg=1)
        rbox(hc + V(0, -0.0235, -0.003), (0.012, 0.004, 0.0045), 0.0015, "hp_yellow", m, seg=1)
        for i in range(3):
            cylinder(hc + V(s * (-0.012 + 0.012 * i), 0.021, -0.001),
                     hc + V(s * (-0.012 + 0.012 * i), 0.0255, -0.001), 0.0032, "metal", m, n=8)
        rbox(base + ax * 0.028 + V(0, -0.0335, 0), (0.016, 0.0050, 0.012), 0.002, "metal_dark", m, seg=1)
        rbox(base + ax * 0.028 + V(0, -0.0390, 0), (0.010, 0.0012, 0.004), 0.0006, "screen_glow", m, seg=1)
        lathe(m, V(s * 0.598, 0.0095, 1.300), ax, [(0.0200, 0.0), (0.0262, 0.002), (0.0270, 0.022),
                                                 (0.0255, 0.026), (0.0200, 0.027)], "glove", n=16,
              cap_end=False)
        rbox(V(s * 0.609, 0.0095, 1.300 + 0.0265), (0.008, 0.009, 0.0025), 0.001, "metal", m, seg=1)
    return finish(m, "WristDevices", 40)


BELT_Z = 0.908
BELT_RX, BELT_RY, BELT_YC = 0.1425, 0.1075, 0.016


def belt_pt(theta_deg, out=0.0, dz=0.0):
    t = math.radians(theta_deg)
    tilt = 0.012 * math.sin(t)          # the belt sits a little lower on her right
    return V(math.sin(t) * (BELT_RX + out), BELT_YC - math.cos(t) * (BELT_RY + out), BELT_Z + tilt + dz)


def belt_frame(theta_deg):
    """(out, tangent, up) at a belt azimuth."""
    t = math.radians(theta_deg)
    out = norm(V(math.sin(t) * BELT_RY, -math.cos(t) * BELT_RX, 0))
    up = V(0, 0, 1)
    tang = np.cross(up, out)
    return out, tang, up


def _frame_R(theta_deg):
    out, tang, up = belt_frame(theta_deg)
    return np.stack([tang, out, up], axis=1)        # local x = along belt, y = outward, z = up


def build_belt_kit():
    m = Mesh()
    prof = circle_profile(8, 0.0155, 0.0036, power=4.0)
    rings = []
    for k in range(40):
        th = 360.0 * k / 40
        out, tang, up = belt_frame(th)
        p = belt_pt(th)
        rings.append([p + up * px + out * py for px, py in prof])
    rings.append(rings[0])
    loft(np.array(rings), "belt", m)
    R0 = _frame_R(4)
    rbox(belt_pt(4, 0.005), (0.026, 0.0045, 0.021), 0.003, "metal", m, seg=2, R=R0)
    rbox(belt_pt(4, 0.0085), (0.017, 0.003, 0.013), 0.002, "walkman", m, seg=1, R=R0)
    for th in (-28, 30, 150, 210):
        rbox(belt_pt(th, 0.003), (0.006, 0.0035, 0.020), 0.0015, "pouch_dark", m, seg=1, R=_frame_R(th))

    # ---- Walkman on her right front hip
    th = -42
    Rw = _frame_R(th)
    out, tang, up = belt_frame(th)
    wc = belt_pt(th, 0.023, -0.056)
    rbox(wc, (0.050, 0.0150, 0.036), 0.005, "walkman", m, seg=2, R=Rw)
    rbox(wc + out * 0.0140 + up * 0.004, (0.034, 0.0022, 0.0190), 0.003, "walkman_dark", m, seg=1, R=Rw)
    for sg in (-1, 1):
        q = wc + tang * 0.0145 * sg + up * 0.004
        cylinder(q + out * 0.0150, q + out * 0.0177, 0.0072, "teeth", m, n=12, bevel=0.0006)
        cylinder(q + out * 0.0175, q + out * 0.0185, 0.0028, "walkman_dark", m, n=8)
    rbox(wc + out * 0.0150 - up * 0.0250, (0.034, 0.0015, 0.0048), 0.001, "walkman_dark", m, seg=1, R=Rw)
    for i in range(4):
        rbox(wc + up * 0.0375 + tang * (-0.030 + 0.020 * i), (0.0072, 0.009, 0.003), 0.001,
             "walkman_dark" if i else "strap_pink", m, seg=1, R=Rw)
    rbox(wc - tang * 0.0515, (0.0025, 0.010, 0.023), 0.001, "walkman_dark", m, seg=1, R=Rw)
    rbox(wc + out * 0.0153 + tang * 0.041 + up * 0.026, (0.003, 0.001, 0.003), 0.0005, "screen_glow", m,
         seg=1, R=Rw)
    rbox(belt_pt(th, 0.007, -0.006), (0.014, 0.004, 0.022), 0.002, "metal_dark", m, seg=1, R=Rw)

    # ---- left hip: scanner pouch with a screen, glowing vial
    th = 48
    Rp = _frame_R(th)
    out, tang, up = belt_frame(th)
    pc = belt_pt(th, 0.019, -0.046)
    rbox(pc, (0.031, 0.0155, 0.037), 0.006, "pouch", m, seg=2, R=Rp)
    rbox(pc + up * 0.026 + out * 0.003, (0.033, 0.0165, 0.013), 0.005, "pouch_dark", m, seg=2, R=Rp)
    rbox(pc + out * 0.0150 - up * 0.008, (0.019, 0.002, 0.014), 0.002, "device", m, seg=1, R=Rp)
    rbox(pc + out * 0.0166 - up * 0.008, (0.0155, 0.001, 0.0105), 0.001, "screen_glow", m, seg=1, R=Rp)
    rbox(pc + out * 0.018 + up * 0.026, (0.006, 0.002, 0.006), 0.001, "metal", m, seg=1, R=Rp)
    th = 86
    out, tang, up = belt_frame(th)
    vc = belt_pt(th, 0.018, -0.030)
    cylinder(vc + up * 0.012, vc - up * 0.052, 0.0125, "vial_glow", m, n=14)
    cylinder(vc + up * 0.010, vc + up * 0.024, 0.0145, "metal_dark", m, n=14, bevel=0.002)
    cylinder(vc - up * 0.050, vc - up * 0.062, 0.0145, "metal_dark", m, n=14, bevel=0.002)
    rbox(vc - out * 0.010 - up * 0.02, (0.012, 0.004, 0.040), 0.002, "pouch_dark", m, seg=1, R=_frame_R(th))
    torus(vc + up * 0.030, tang, 0.008, 0.0018, "metal", m, n=12, m=5)
    # ---- hanging gadgets on short webbing drops (front of each hip), as in the concept
    for th, drop, body, w, h in ((-17, 0.098, "device", 0.026, 0.034), (22, 0.108, "pouch", 0.030, 0.038)):
        Rg = _frame_R(th)
        out, tang, up = belt_frame(th)
        top = belt_pt(th, 0.006, -0.010)
        gc = belt_pt(th, 0.020, -drop)
        rbox((top + gc) / 2 + out * 0.002, (0.0075, 0.0022, drop / 2 - 0.012), 0.001, "strap_dark", m, seg=1, R=Rg)
        torus(top - up * 0.006 + out * 0.004, tang, 0.0085, 0.0020, "metal", m, n=12, m=5)
        rbox(gc, (w, 0.0135, h), 0.006, body, m, seg=2, R=Rg)
        rbox(gc + up * (h - 0.004) + out * 0.002, (w + 0.002, 0.0145, 0.008), 0.003, "walkman", m, seg=1, R=Rg)
        rbox(gc + out * 0.0135 - up * 0.004, (w * 0.66, 0.0016, h * 0.46), 0.002, "walkman_dark", m, seg=1, R=Rg)
        rbox(gc + out * 0.0150 - up * 0.004, (w * 0.52, 0.0010, h * 0.34), 0.001, "screen_glow", m, seg=1, R=Rg)
        for sg in (-1, 1):
            rbox(gc + tang * sg * (w + 0.001) - up * 0.006, (0.0030, 0.0090, h * 0.5), 0.001, "metal_dark", m, seg=1, R=Rg)
        rbox(gc - up * (h + 0.003), (w * 0.5, 0.0080, 0.0050), 0.002, "metal", m, seg=1, R=Rg)
    # tool roll on the back
    th = 168
    Rb = _frame_R(th)
    out, tang, up = belt_frame(th)
    bc = belt_pt(th, 0.018, -0.030)
    rbox(bc, (0.050, 0.016, 0.028), 0.008, "pouch", m, seg=2, R=Rb)
    rbox(bc + up * 0.018 + out * 0.003, (0.052, 0.017, 0.012), 0.005, "pouch_dark", m, seg=2, R=Rb)
    for i in (-1, 1):
        rbox(bc + tang * 0.028 * i + out * 0.017, (0.004, 0.002, 0.026), 0.001, "strap_dark", m, seg=1, R=Rb)
    # wrench hanging at the back-left
    th = 128
    out, tang, up = belt_frame(th)
    wb = belt_pt(th, 0.012, -0.012)
    torus(wb, tang, 0.0075, 0.0018, "metal", m, n=12, m=5)
    cylinder(wb - up * 0.010, wb - up * 0.085, 0.0042, "metal", m, n=8)
    torus(wb - up * 0.093, out, 0.0085, 0.0034, "metal", m, n=12, m=5,
          arc=(math.radians(-50), math.radians(230)))
    # small canister pouches on her right side
    for th, mat in ((-78, "pouch"), (-104, "pouch_dark")):
        out, tang, up = belt_frame(th)
        pc = belt_pt(th, 0.014, -0.030)
        rbox(pc, (0.018, 0.012, 0.027), 0.005, mat, m, seg=2, R=_frame_R(th))
        rbox(pc + up * 0.020 + out * 0.002, (0.0195, 0.013, 0.009), 0.004,
             "pouch_dark" if mat == "pouch" else "pouch", m, seg=2, R=_frame_R(th))
    return finish(m, "BeltKit", 40)


STRAPS = [(-62, 0.33, 0.012), (-90, 0.24, -0.010)]     # belt azimuth, length, sway


def strap_chain(i):
    """Centre line (4 points) of hanging strap i (world space), for the mesh and its bones."""
    th, L, sway = STRAPS[i]
    out, tang, up = belt_frame(th)
    p0 = belt_pt(th, 0.022, -0.050)
    pts = [p0]
    for k in range(1, 4):
        f = k / 3
        pts.append(p0 + out * (0.012 * math.sin(f * math.pi * 0.8) + 0.012 * f) - up * L * f
                   + tang * sway * f * f * 3)
    return np.array(pts)


def build_straps():
    """Red/pink webbing straps hanging from the belt on her right side."""
    m = Mesh()
    for i, (th, L, sway) in enumerate(STRAPS):
        out, tang, up = belt_frame(th)
        ctr = catmull(strap_chain(i), 14)
        prof = circle_profile(8, 0.0125, 0.0018, power=4.0)
        rings = []
        for j in range(len(ctr)):
            tw = 0.25 * math.sin(j * 0.5 + i)
            tg = norm(tang + out * tw)
            oo = norm(np.cross(tg, V(0, 0, 1)))
            if oo @ out < 0:
                oo = -oo
            rings.append([ctr[j] + tg * px + oo * py for px, py in prof])
        loft(np.array(rings), "strap_pink", m, cap0=True, cap1=True)
        Rs = np.stack([tang, out, up], axis=1)
        rbox(ctr[-1] - up * 0.004, (0.0150, 0.004, 0.011), 0.002, "metal", m, seg=1, R=Rs)
        rbox(ctr[len(ctr) // 2] + out * 0.002, (0.0140, 0.0035, 0.008), 0.0015, "metal_dark", m, seg=1, R=Rs)
    return finish(m, "Straps", 40)


CABLE_PTS = np.array([(-0.090, 0.016, 1.420), (-0.094, -0.004, 1.392), (-0.086, -0.050, 1.335),
                      (-0.070, -0.094, 1.262), (-0.060, -0.112, 1.180), (-0.090, -0.108, 1.090),
                      (-0.128, -0.086, 1.010), (-0.150, -0.060, 0.952), (-0.128, -0.094, 0.915),
                      (-0.106, -0.108, 0.893)])


def build_cable():
    m = Mesh()
    path = resample(catmull(CABLE_PTS, 60), 32)
    sweep(path, circle_profile(5), 0.0030, V(1, 0, 0), "cable", m)
    cylinder(CABLE_PTS[0] + V(0, 0, 0.012), CABLE_PTS[0] - V(0, 0, 0.004), 0.0048, "hp_dark", m, n=8)
    cylinder(CABLE_PTS[-1] + V(0, 0, 0.004), CABLE_PTS[-1] - V(0, 0, 0.010), 0.0048, "walkman_dark",
             m, n=8)
    return finish(m, "Cable", 60)
