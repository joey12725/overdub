"""Shielder: the walker behind a tower shield (assets/models/enemies/shielder.glb).

Reads as: a tall ceramic temple-pillar body on stout column legs, carrying a big curved door-slab
shield in front with a speaker cone at its heart ringed by a teal projector glow; its single orange
eye rides on a periscope tape head that peers over the shield's top edge. An amplifier pack on its
back feeds the shield through a patch cable. Only two selves working together can hurt it: one
pops the shield, the other strikes while it is down (the game hides the separate `Shield` mesh
while it is popped). It walks at the nearest self and bashes with the shield
(telegraph = shield hauled back and to the side, crouched, projector ring swelling;
attack = a stepping shove straight ahead).

Run:  blender --background --python art/enemies/shielder.py -- [--no-export] [--no-stills] [--no-sheets]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import common as C  # noqa: E402
from common import K  # noqa: E402

# ------------------------------------------------------------------------------------------
# Skeleton (Blender axes: Z up, front -Y, the shielder's right side is -X)
# ------------------------------------------------------------------------------------------
HIP_Z = 0.5
SH_C = (0.05, -0.44, 0.69)        # shield centre (front face is at about y = -0.48)
SH_W, SH_H = 0.8, 0.98            # shield width / height
BONES = [
    ("root", (0, 0, 0), (0, 0, 0.2), None),
    ("hips", (0, 0, HIP_Z), (0, 0, 0.62), "root"),
    ("chest", (0, 0, 0.62), (0, 0, 1.04), "hips"),
    ("head", (0, 0.02, 1.04), (0, 0.02, 1.24), "chest"),
    ("eye", (0, -0.1, 1.3), (0, -0.2, 1.3), "head"),
    ("upper_arm.L", (0.25, 0, 0.93), (0.31, -0.06, 0.72), "chest"),
    ("forearm.L", (0.31, -0.06, 0.72), (0.2, -0.33, 0.7), "upper_arm.L"),
    ("shield", SH_C, (SH_C[0], SH_C[1], SH_C[2] + 0.2), "forearm.L"),
    ("charge", (SH_C[0], SH_C[1] - 0.05, SH_C[2]), (SH_C[0], SH_C[1] - 0.15, SH_C[2]), "shield"),
    ("upper_arm.R", (-0.25, 0, 0.93), (-0.3, -0.02, 0.71), "chest"),
    ("forearm.R", (-0.3, -0.02, 0.71), (-0.24, -0.25, 0.64), "upper_arm.R"),
    ("hand.R", (-0.24, -0.25, 0.64), (-0.2, -0.33, 0.63), "forearm.R"),
]
for s, x in (("L", 1), ("R", -1)):
    BONES += [
        (f"thigh.{s}", (0.13 * x, 0, HIP_Z), (0.15 * x, 0.0, 0.28), "hips"),
        (f"shin.{s}", (0.15 * x, 0.0, 0.28), (0.15 * x, 0.02, 0.09), f"thigh.{s}"),
        (f"foot.{s}", (0.15 * x, 0.02, 0.09), (0.15 * x, -0.1, 0.04), f"shin.{s}"),
    ]


# ------------------------------------------------------------------------------------------
# Shield (separate mesh object `Shield`)
# ------------------------------------------------------------------------------------------

def shield_parts():
    cx, cy, cz = SH_C
    parts = []
    # Door slab: sliced into columns, bent so the face bulges forward, corners chipped off by
    # booleans (a temple door's chamfered octagon), brass frame around an inset ceramic panel.
    slab = C.box("shield_slab", (SH_W, 0.07, SH_H), loc=SH_C, mat="brass")
    C.slice_planes(slab, (1, 0, 0), [cx + SH_W * f for f in (-0.375, -0.25, -0.125, 0.0, 0.125, 0.25, 0.375)])
    C.slice_planes(slab, (0, 0, 1), [cz + SH_H * f for f in (-0.3, 0.0, 0.3)])
    C.inset_faces(slab, lambda c, n: n.y < -0.9, thickness=0.055, depth=-0.012, mat="ceramic", individual=False)
    for v in slab.data.vertices:
        u = (v.co.x - cx) / (SH_W / 2)
        v.co.y += 0.07 * u * u
    for sx in (1, -1):
        for sz in (1, -1):
            C.chip(slab, loc=(cx + sx * SH_W / 2, cy, cz + sz * SH_H / 2), size=(0.2, 0.4, 0.2), rot=(0, 45, 0))
    C.set_material_where(slab, "metal", lambda c: c.y > cy + 0.025)
    C.bevel(slab, 0.012, 1, limit_deg=50)
    parts.append(C.tag(slab, "shield"))
    # Speaker cone at the heart: brass surround, dark cone, phase plug.
    spk = C.lathe("shield_speaker", [(0.0, 0.05), (0.035, 0.045), (0.05, 0.02), (0.06, 0.0), (0.17, 0.03),
                                     (0.19, 0.04), (0.215, 0.04), (0.215, 0.055), (0.19, 0.06)],
                  segments=28, mat=["speaker", "brass"], mats=[1, 1, 0, 0, 1, 1, 1, 1])
    C.place(spk, loc=(cx, cy - 0.035, cz + 0.05), rot=(90, 0, 0))
    parts.append(C.tag(spk, "shield"))
    # Projector ring (charge bone): the shield's field emitter, swells on the telegraph.
    ring = C.torus("shield_ring", 0.235, 0.018, seg=32, ring=6, mat="shield_glow")
    C.place(ring, loc=(cx, cy - 0.095, cz + 0.05), rot=(90, 0, 0))
    parts.append(C.tag(ring, "charge"))
    # Four emitter studs at the ring's quarters.
    for i in range(4):
        a = i * math.pi / 2 + math.pi / 4
        st = C.cyl(f"stud{i}", 0.025, 0.02, 0.04, loc=(cx + 0.27 * math.cos(a), cy - 0.07, cz + 0.05 + 0.27 * math.sin(a)),
                   rot=(90, 0, 0), verts=8, mat="metal_light")
        parts.append(C.tag(st, "shield"))
    # Hazard-striped bash edge along the bottom (the part that hurts).
    edge = C.box("bash_edge", (SH_W * 0.62, 0.09, 0.09), loc=(cx, cy - 0.01, cz - SH_H / 2 + 0.06), mat="hazard")
    C.hazard_bands(edge, direction=(1, 0, 1), period=0.05)
    C.bevel(edge, 0.01, 1)
    parts.append(C.tag(edge, "shield"))
    # Rune grooves in the upper corners of the panel.
    g1 = [[(-0.045, -0.04), (0.0, 0.05), (0.045, -0.04), (-0.045, -0.04)], [(0.0, 0.05), (0.0, -0.07)]]
    g2 = [[(0.0, 0.06), (0.0, -0.06)], [(-0.045, 0.035), (0.04, -0.005)], [(-0.04, -0.025), (0.0, -0.05)]]
    for g, x in ((g1, cx - 0.22), (g2, cx + 0.22)):
        r = C.rune_groove(f"srune{x}", g, loc=(x, cy - 0.034 + 0.07 * (0.22 / (SH_W / 2)) ** 2, cz + 0.33), width=0.014)
        parts.append(C.tag(r, "shield"))
    # Back: dark metal strongback, cross strut and the grip the forearm clamps.
    vbar = C.box("strong_v", (0.07, 0.04, SH_H * 0.8), loc=(cx, cy + 0.05, cz), mat="metal")
    hbar = C.box("strong_h", (SH_W * 0.78, 0.04, 0.07), loc=(cx, cy + 0.05, cz + 0.02), mat="metal")
    grip = C.box("grip", (0.05, 0.08, 0.2), loc=(cx + 0.15, cy + 0.1, cz), mat="metal_light")
    for o in (vbar, hbar, grip):
        C.bevel(o, 0.01, 1)
        parts.append(C.tag(o, "shield"))
    return parts


# ------------------------------------------------------------------------------------------
# Body
# ------------------------------------------------------------------------------------------

def torso():
    parts = []
    # Temple pillar torso: an octagonal ceramic column, each facet recessed like a fluted pilaster.
    col = C.lathe("pillar", [(0.0, 0.6), (0.2, 0.6), (0.235, 0.7), (0.245, 0.86), (0.22, 1.0), (0.17, 1.06),
                             (0.0, 1.06)], segments=8, mat="ceramic")
    C.place(col, rot=(0, 0, 22.5))
    C.inset_faces(col, lambda c, n: abs(n.z) < 0.5 and 0.7 < c.z < 0.95, thickness=0.02, depth=-0.012,
                  mat="ceramic_dark")
    C.bevel(col, 0.012, 1, limit_deg=30)
    parts.append(C.tag(col, "chest"))
    for z, r in ((0.66, 0.225), (0.98, 0.232)):
        band = C.cyl(f"band{z}", r, r, 0.035, loc=(0, 0, z), verts=8, mat="brass")
        C.place(band, rot=(0, 0, 22.5))
        parts.append(C.tag(band, "chest"))
    # Vertical rune grooves on the side facets.
    for x, rz in ((0.236, 90), (-0.236, -90)):
        r = C.rune_groove(f"prune{x}", [[(0.0, -0.08), (0.0, 0.08)], [(-0.03, 0.04), (0.0, 0.0), (0.03, 0.04)]],
                          loc=(x, 0.0, 0.82), rot=(0, 0, rz), width=0.013)
        parts.append(C.tag(r, "chest"))
    # Shoulder domes.
    for x in (1, -1):
        d = C.lathe(f"shoulder{x}", [(0.0, -0.02), (0.11, -0.02), (0.11, 0.03), (0.08, 0.08), (0.0, 0.1)],
                    segments=14, mat="ceramic_dark")
        C.place(d, loc=(0.25 * x, 0.0, 0.95), rot=(0, 25 * x, 0))
        C.bevel(d, 0.008, 1)
        parts.append(C.tag(d, f"upper_arm.{'L' if x == 1 else 'R'}"))
    # Amplifier pack on the back with a VU meter and two capstan posts.
    amp = C.box("amp", (0.3, 0.14, 0.34), loc=(0, 0.27, 0.86), mat="metal", taper=(0.9, 1.0))
    C.inset_faces(amp, lambda c, n: n.y > 0.9, thickness=0.03, depth=-0.012, mat="speaker")
    C.bevel(amp, 0.02, 2)
    parts.append(C.tag(amp, "chest"))
    vu = C.box("vu", (0.16, 0.03, 0.07), loc=(0, 0.345, 0.96), mat="metal_light")
    C.inset_faces(vu, lambda c, n: n.y > 0.9, thickness=0.01, depth=-0.006, mat="meter_glow")
    parts.append(C.tag(vu, "chest"))
    for x in (0.1, -0.1):
        p = C.cyl(f"cap{x}", 0.03, 0.03, 0.08, loc=(x, 0.27, 1.07), verts=12, mat="brass")
        parts.append(C.tag(p, "chest"))
    # Patch cable from the amp to the shield arm (soft).
    cab = C.tube("amp_cable", [(0.15, 0.3, 0.76), (0.32, 0.22, 0.62), (0.36, 0.0, 0.62), (0.3, -0.22, 0.66),
                               (0.2, -0.34, 0.68)], 0.018, mat="cable", segments=3)
    parts.append(C.tag(cab, soft=["chest", "upper_arm.L", "forearm.L"]))
    return parts


def head():
    parts = []
    collar = C.lathe("collar", [(0.1, 1.03), (0.15, 1.03), (0.14, 1.07), (0.08, 1.09)], segments=16, mat="brass")
    parts.append(C.tag(collar, "chest"))
    # Periscope stalk and the tape-head sensor block riding on top.
    stalk = C.cyl("stalk", 0.04, 0.035, 0.2, loc=(0, 0.02, 1.15), verts=12, mat="metal_light")
    parts.append(C.tag(stalk, "head"))
    blk = C.box("scope", (0.2, 0.2, 0.13), loc=(0, -0.0, 1.3), mat="ceramic", taper=(0.85, 0.8))
    C.inset_faces(blk, lambda c, n: n.z > 0.9, thickness=0.03, depth=-0.02, mat="metal")
    C.bevel(blk, 0.025, 2)
    parts.append(C.tag(blk, "head"))
    hood = C.box("hood", (0.19, 0.08, 0.03), loc=(0, -0.1, 1.36), rot=(-14, 0, 0), mat="brass")
    C.bevel(hood, 0.006, 1)
    parts.append(C.tag(hood, "head"))
    sock = C.cyl("socket", 0.05, 0.055, 0.04, loc=(0, -0.095, 1.3), rot=(90, 0, 0), verts=16, mat="metal")
    parts.append(C.tag(sock, "head"))
    lens = C.lathe("lens", [(0.0, 0.03), (0.024, 0.026), (0.038, 0.012), (0.04, 0.0)], segments=16, mat="eye_glow")
    C.place(lens, loc=(0, -0.11, 1.3), rot=(90, 0, 0))
    parts.append(C.tag(lens, "eye"))
    # Antenna: a stout capstan post with a brass cap (the same tape-guide post the grunt wears),
    # thick enough to survive at game scale instead of a hairline that shimmers.
    ant = C.cyl("antenna", 0.019, 0.019, 0.1, loc=(0.06, 0.04, 1.41), verts=12, mat="metal_light")
    cap = C.cyl("antenna_cap", 0.032, 0.032, 0.018, loc=(0.06, 0.04, 1.465), verts=12, mat="brass")
    parts += [C.tag(ant, "head"), C.tag(cap, "head")]
    return parts


def arms():
    parts = []
    # Left (shield) arm: piston upper arm, ceramic forearm sleeve reaching under the shield.
    for s, sh, el, wr in (("L", (0.25, 0, 0.93), (0.31, -0.06, 0.72), (0.2, -0.33, 0.7)),
                          ("R", (-0.25, 0, 0.93), (-0.3, -0.02, 0.71), (-0.24, -0.25, 0.64))):
        ua = C.cyl(f"uarm.{s}", 0.05, 0.045, 0.22, verts=12, mat="metal_light")
        C.along(ua, sh, el, 0.5)
        parts.append(C.tag(ua, f"upper_arm.{s}"))
        jt = C.cyl(f"elbow.{s}", 0.055, 0.055, 0.09, loc=el, rot=(0, 90, 0), verts=12, mat="metal")
        parts.append(C.tag(jt, f"forearm.{s}"))
        fa = C.box(f"sleeve.{s}", (0.13, 0.13, 0.24), mat="ceramic", taper=(0.8, 0.8))
        C.place(fa, rot=(180, 0, 0))
        C.along(fa, wr, el, 0.45)
        C.bevel(fa, 0.022, 2)
        parts.append(C.tag(fa, f"forearm.{s}"))
    # Shield clamp on the left wrist (part of the body: stays when the shield is hidden).
    clamp = C.box("shield_clamp", (0.12, 0.1, 0.12), loc=(0.18, -0.36, 0.7), mat="metal")
    C.bevel(clamp, 0.015, 1)
    parts.append(C.tag(clamp, "forearm.L"))
    # Right fist: a heavy capstan knuckle that braces the shield's back.
    fist = C.cyl("fist", 0.07, 0.07, 0.12, loc=(-0.21, -0.3, 0.63), rot=(90, 0, 0), verts=14, mat="ceramic_dark")
    C.bevel(fist, 0.015, 1)
    ring = C.cyl("fist_band", 0.074, 0.074, 0.03, loc=(-0.21, -0.27, 0.63), rot=(90, 0, 0), verts=14, mat="brass")
    parts += [C.tag(fist, "hand.R"), C.tag(ring, "hand.R")]
    return parts


def hips_legs():
    parts = []
    pel = C.lathe("pelvis", [(0.0, 0.44), (0.19, 0.44), (0.22, 0.52), (0.2, 0.6), (0.0, 0.6)], segments=8, mat="metal")
    C.place(pel, rot=(0, 0, 22.5))
    C.bevel(pel, 0.01, 1)
    parts.append(C.tag(pel, "hips"))
    for s, x in (("L", 1), ("R", -1)):
        hj = C.cyl(f"hipj.{s}", 0.07, 0.07, 0.08, loc=(0.14 * x, 0, HIP_Z), rot=(0, 90, 0), verts=12, mat="metal_light")
        parts.append(C.tag(hj, "hips"))
        # Column legs: a fluted ceramic drum thigh, bellows knee, a column-base foot.
        th = C.lathe(f"thigh.{s}", [(0.0, 0.3), (0.08, 0.3), (0.09, 0.36), (0.085, 0.46), (0.0, 0.46)],
                     segments=10, mat="ceramic")
        C.place(th, loc=(0.145 * x, 0.0, 0.0))
        C.bevel(th, 0.008, 1)
        parts.append(C.tag(th, f"thigh.{s}"))
        kn = C.lathe(f"knee.{s}", [(0.07, 0.22), (0.055, 0.25), (0.07, 0.28), (0.055, 0.31)], segments=12, mat="cable")
        C.place(kn, loc=(0.15 * x, 0.0, 0.0))
        parts.append(C.tag(kn, soft=[f"thigh.{s}", f"shin.{s}"]))
        sh = C.lathe(f"shin.{s}", [(0.0, 0.1), (0.075, 0.1), (0.085, 0.13), (0.075, 0.23), (0.0, 0.23)],
                     segments=10, mat="ceramic_dark")
        C.place(sh, loc=(0.15 * x, 0.01, 0.0))
        C.bevel(sh, 0.008, 1)
        parts.append(C.tag(sh, f"shin.{s}"))
        ft = C.lathe(f"foot.{s}", [(0.0, 0.0), (0.12, 0.0), (0.12, 0.035), (0.1, 0.05), (0.075, 0.085), (0.0, 0.085)],
                     segments=12, mat="ceramic")
        C.place(ft, loc=(0.15 * x, -0.015, 0.0), scale=(1.0, 1.2, 1.0))
        C.bevel(ft, 0.008, 1)
        parts.append(C.tag(ft, f"foot.{s}"))
        toe = C.box(f"toe.{s}", (0.1, 0.06, 0.04), loc=(0.15 * x, -0.15, 0.02), mat="brass", taper=(0.8, 0.7))
        C.bevel(toe, 0.01, 1)
        parts.append(C.tag(toe, f"foot.{s}"))
    return parts


# ------------------------------------------------------------------------------------------
# Animation
# ------------------------------------------------------------------------------------------

def actions(rig):
    acts = {}
    a = C.Anim(rig, "idle", 2.0, loop=True)
    # idle: the pillar breathes and shifts its weight behind the shield, the shield arm re-seats the
    # slab, the periscope sweeps and dwells, the projector ring pulses like a standby lamp.
    a.key(0, {"hips": K(), "chest": K(), "head": K(), "upper_arm.L": K(), "forearm.L": K(), "upper_arm.R": K(),
              "charge": K(s=1.0)})
    a.key(12, {"head": K(rz=20, rx=2)})
    a.key(15, {"charge": K(s=1.12)})
    a.key(20, {"head": K(rz=22, rx=2)})
    a.key(30, {"hips": K(rz=-3, loc=(0.012, 0, -0.022)), "chest": K(rx=4, rz=-3), "upper_arm.L": K(rx=-4),
               "forearm.L": K(rx=-5), "upper_arm.R": K(rx=-6), "charge": K(s=1.0)})
    a.key(42, {"head": K(rz=-20, rx=2)})
    a.key(45, {"charge": K(s=1.12)})
    a.key(50, {"head": K(rz=-22, rx=2)})
    acts["idle"] = a.build()

    # move: 1 s heavy plod behind the shield; shield steady, body rocking side to side.
    a = C.Anim(rig, "move", 1.0, loop=True)
    for f, lead in ((0, "L"), (15, "R")):
        o = "R" if lead == "L" else "L"
        a.key(f, {f"thigh.{lead}": K(-22), f"shin.{lead}": K(8), f"foot.{lead}": K(14),
                  f"thigh.{o}": K(18), f"shin.{o}": K(14), f"foot.{o}": K(-32),
                  "hips": K(ry=4 if lead == "L" else -4, loc=(0, 0, -0.02)),
                  "chest": K(ry=-3 if lead == "L" else 3, rx=3), "upper_arm.R": K(rx=-8 if lead == "L" else 4),
                  "head": K(ry=3 if lead == "L" else -3)})
    for f, lead in ((8, "L"), (23, "R")):
        o = "R" if lead == "L" else "L"
        a.key(f, {f"thigh.{lead}": K(2), f"shin.{lead}": K(2), f"foot.{lead}": K(-4),
                  f"thigh.{o}": K(-14), f"shin.{o}": K(44), f"foot.{o}": K(-26),
                  "hips": K(loc=(0, 0, 0.012)), "chest": K(rx=4)})
    acts["move"] = a.build()

    # telegraph: crouch, shield hauled back to the left shoulder, right fist braced, projector
    # ring swelling and trembling.
    wind = {
        # Deep crouch, the whole body coiled away to its left with the slab hauled back and up to
        # the shoulder, eye still on the target: a big silhouette change that opens the body up.
        "hips": K(rz=14, loc=(0, 0.06, -0.1)),
        "chest": K(rx=-10, rz=30),
        "head": K(rz=-36, rx=8),
        "upper_arm.L": K(rx=30, ry=18), "forearm.L": K(rx=-22, rz=22),
        "upper_arm.R": K(rx=-20, ry=-10), "forearm.R": K(rx=-20),
        "thigh.L": K(-30, ry=6), "shin.L": K(40), "foot.L": K(-10),
        "thigh.R": K(14, ry=-6), "shin.R": K(26), "foot.R": K(-40),
    }
    a = C.Anim(rig, "telegraph", 1.0, loop=False)
    a.key(0, {"charge": K(s=1.0)})
    a.key(10, {"chest": K(rz=10), "hips": K(rz=6, loc=(0, 0.02, -0.03)), "upper_arm.L": K(rx=12, ry=6),
               "charge": K(s=1.1)})
    a.key(22, dict(wind, charge=K(s=1.42)))
    a.key(25, {"charge": K(s=1.3)})
    a.key(28, {"charge": K(s=1.5)})
    a.key(30, dict(wind, chest=K(rx=-11, rz=32), charge=K(s=1.48)))
    acts["telegraph"] = a.build()

    # attack: stepping shove — the shield punches straight ahead by frame 5, holds, recovers.
    shove = {
        "hips": K(rz=-6, loc=(0, -0.12, -0.05)),
        "chest": K(rx=16, rz=-10),
        "head": K(rx=-10, rz=8),
        "upper_arm.L": K(rx=-30, ry=-4), "forearm.L": K(rx=6, rz=-6),
        "upper_arm.R": K(rx=-50), "forearm.R": K(rx=-24),
        "thigh.L": K(-40), "shin.L": K(36), "foot.L": K(6),
        "thigh.R": K(28), "shin.R": K(10), "foot.R": K(-36),
    }
    a = C.Anim(rig, "attack", 1.0, loop=False)
    a.key(0, dict(wind, chest=K(rx=-11, rz=32), charge=K(s=1.48)))
    a.key(3, {"chest": K(rx=6, rz=4), "upper_arm.L": K(rx=-10), "forearm.L": K(rz=4), "charge": K(s=1.6)})
    a.key(5, dict(shove, charge=K(s=1.7)))
    a.key(8, {"chest": K(rx=13, rz=-8), "charge": K(s=1.1)})
    a.key(14, dict(shove, charge=K(s=1.0)))
    a.key(30, {b: K() for b in ("hips", "chest", "head", "upper_arm.L", "forearm.L", "upper_arm.R", "forearm.R",
                                "thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R", "charge")})
    acts["attack"] = a.build()

    a = C.Anim(rig, "stagger", 1.0, loop=False)
    a.key(0, {"eye": K(s=1.0)})
    a.key(3, {"hips": K(rx=-8, loc=(0, 0.08, -0.01)), "chest": K(rx=-20, ry=-10), "head": K(rx=-24, rz=14),
              "upper_arm.L": K(rx=-40, ry=30), "forearm.L": K(rz=20), "upper_arm.R": K(rx=-30, ry=-40),
              "thigh.L": K(-18), "shin.L": K(16), "foot.L": K(8), "thigh.R": K(10), "shin.R": K(4), "foot.R": K(-10),
              "eye": K(s=0.4)})
    a.key(6, {"eye": K(s=1.1)})
    a.key(9, {"eye": K(s=0.45)})
    a.key(12, {"hips": K(rx=-2, loc=(0, 0.11, -0.02)), "chest": K(rx=-6, ry=6), "head": K(rx=-4, rz=-8),
               "upper_arm.L": K(rx=-10, ry=8), "forearm.L": K(rz=4), "upper_arm.R": K(rx=-6, ry=-10), "eye": K(s=1.0)})
    a.key(20, {"chest": K(rx=6), "head": K(rx=4), "hips": K(loc=(0, 0.11, -0.02))})
    a.key(30, {b: K() for b in ("chest", "head", "upper_arm.L", "forearm.L", "upper_arm.R", "thigh.L", "shin.L",
                                "foot.L", "thigh.R", "shin.R", "foot.R")})
    a.key(30, {"hips": K(loc=(0, 0.11, 0)), "eye": K(s=1.0)})
    acts["stagger"] = a.build()

    # death: the shield arm drops and the shield falls face-down in front, the pillar sags to its
    # knees and topples back, the periscope folds over, the eye shutters.
    a = C.Anim(rig, "death", 1.0, loop=False)
    a.key(0, {"eye": K(s=1.0), "hips": K(), "chest": K(), "shield": K()})
    a.key(4, {"eye": K(s=1.35), "chest": K(rx=-8), "head": K(rx=-14), "upper_arm.L": K(rx=10)})
    a.key(10, {"eye": K(s=0.4), "shield": K(rx=30, loc=(0, -0.05, -0.1))})
    a.key(14, {"hips": K(loc=(0, 0.0, -0.12)), "thigh.L": K(-40), "thigh.R": K(-34), "shin.L": K(70),
               "shin.R": K(64), "foot.L": K(-24), "foot.R": K(-24), "eye": K(s=0.15)})
    final = {
        "hips": K(rx=-4, loc=(0, 0.06, -0.15)),
        "chest": K(rx=-58, rz=10),
        "head": K(rx=60, rz=-20),
        "thigh.L": K(-70, ry=10), "shin.L": K(100), "foot.L": K(-28),
        "thigh.R": K(-64, ry=-10), "shin.R": K(94), "foot.R": K(-28),
        "upper_arm.L": K(rx=50, ry=30), "forearm.L": K(rx=10),
        "upper_arm.R": K(rx=40, ry=-40), "forearm.R": K(rx=10),
        "shield": K(rx=90, loc=(0.0, -0.5, -0.36)),
        "eye": K(s=0.02),
    }
    a.key(22, dict(final, chest=K(rx=-64, rz=10)))
    a.key(26, {"chest": K(rx=-55, rz=10)})
    a.key(30, final)
    acts["death"] = a.build()
    return acts


def build():
    rig = C.make_rig(BONES)
    # The shield is bound first (its corner chips use boolean cutters that bind() cleans up).
    shield = C.bind(rig, shield_parts(), "Shield", auto=False)
    body = C.bind(rig, torso() + head() + arms() + hips_legs(), "Body")
    acts = actions(rig)
    C.clear_pose(rig)
    return rig, [body, shield], acts


if __name__ == "__main__":
    C.run("shielder", build)
