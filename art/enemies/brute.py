"""OVERDUB enemy: brute — a hulking, hunched ruin golem with a giant capstan hammer for a right arm.

    blender --background --python art/enemies/brute.py -- [--out assets/models/enemies/brute.glb]
                                                          [--previews art/previews/enemies/brute]
                                                          [--no-anim-previews]

Reads as: slow, armoured, hard to shove — a wide ceramic boulder of a torso on short planted legs,
huge pauldrons, a tiny sunken head with one eye slit, two tape reels on its back feeding a cable
to the right arm, which ends in a hazard-striped capstan drum (the slam). The left arm ends in a
three-pronged clamp it leans on. ~2.0 tall, ~1.9 wide.

Rig "Rig": root, hips, spine, chest, head, reel.L/R (spin), shoulder/upper_arm/forearm .L/.R,
hand.L, hammer (spin: the capstan drum), thigh/shin/foot .L/.R.
"""
from __future__ import annotations

import math
import os
import sys

import bmesh
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common2 as C  # noqa: E402

SPEAKER_Z = 1.27  # chest speaker centre: below the head so both read from the front
HEAD_Z = 1.64     # centre of the helm
EYE_Y = -0.612    # front of the eye lens


# ───────────────────────────── torso ─────────────────────────────


def torso_shell():
    """Half box shaped by hand (x >= 0), then Mirror + Subdivision Surface with creases: a hunched
    ceramic boulder, wide at the shoulders, narrow at the waist, humped at the back."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x = (v.co.x + 0.5) * 0.50          # 0 .. 0.50
        v.co.y = v.co.y * 0.80 + 0.03           # -0.37 .. 0.43
        v.co.z = 1.0 + (v.co.z + 0.5) * 0.86    # 1.0 .. 1.86
    # Two horizontal loop cuts (belly and chest lines), one vertical cut (front/back mass split).
    for z in (1.28, 1.6):
        bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), plane_co=(0, 0, z), plane_no=(0, 0, 1))
    bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), plane_co=(0.25, 0, 0), plane_no=(1, 0, 0))
    for v in bm.verts:
        x, y, z = v.co
        if z < 1.01:                       # waist: narrow, tucked
            v.co.x *= 0.62
            v.co.y = y * 0.7 + 0.02
        elif z < 1.3:                      # belly
            v.co.x *= 0.86
            if y < 0:
                v.co.y = y * 0.92
        elif z < 1.61:                     # chest: widest
            v.co.x *= 1.06
            if y < 0:
                v.co.y = y * 1.08
        else:                              # shoulders and hump
            if y > 0:
                v.co.z += 0.06             # the hump rises behind the head
                v.co.y = y * 1.05
            else:
                v.co.z -= 0.02
                v.co.y = y * 0.72          # front top slopes back: the head sits low in front
    ob = C.bm_to_object("torso_shell", bm, ["ceramic"], None)
    # Remove the mirror-plane faces (x == 0) so the mirror merges cleanly.
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if all(abs(v.co.x) < 1e-4 for v in f.verts)], context="FACES")
    bm.to_mesh(ob.data)
    bm.free()
    C.crease_edges(ob, lambda a, b: True, 0.3)
    C.mod_mirror(ob)
    C.mod_subsurf(ob, 2)
    C.apply_modifiers(ob)
    C.resmooth(ob, 50)
    return ob


def build_torso(sk: C.Skin) -> None:
    shell = torso_shell()
    # Carve three dark seams across the shell (separate plates of the old casing).
    C.recolor(shell, "ceramic_dark", lambda c, n: n.y > 0.55 and c.z > 1.35)  # weathered back hump
    sk.rigid(shell, "chest")
    parts = []
    # Chest speaker: the retrofit, set into the front of the casing.
    # It sits below the head (the head used to hide it) on a short brass throat let into the belly.
    sz = SPEAKER_Z
    sy = C.ray_hit(shell, (0.12, -2.0, sz), (0, 1, 0)).y - 0.03  # front face of the speaker rim
    spk = C.lathe("chest_speaker", [(0, -0.09), (0.2, -0.09), (0.215, -0.03), (0.215, 0.02), (0.19, 0.035), (0.075, -0.012),
                                    (0.045, 0.012), (0, 0.016)],
                  ["brass", "speaker"], 32, band_mats=[1, 0, 0, 0, 1, 1, 1], rot=(90, 0, 0))
    C.place(spk, (0, sy + 0.035, sz))
    for k, z in enumerate((-0.085, 0.0, 0.085)):
        w = 0.4 if k == 1 else 0.33
        parts.append(C.box(f"speaker_bar{k}", (w, 0.024, 0.026), "metal", loc=(0, sy - 0.008, sz + z), bevel=0.007))
    rim_bolts = C.bolts("speaker_bolts", [(0.2 * math.cos(a), sy + 0.004, sz + 0.2 * math.sin(a))
                                          for a in [math.radians(45 + 90 * i) for i in range(4)]], (0, -1, 0), 0.02, 0.02)
    parts += [spk, rim_bolts]
    # VU meter strip above the speaker.
    parts.append(C.box("vu_frame", (0.26, 0.04, 0.07), "brass", loc=(0, -0.37, 1.64), rot=(-25, 0, 0), bevel=0.01))
    parts.append(C.box("vu_glass", (0.21, 0.02, 0.04), "meter_glow", loc=(0, -0.388, 1.645), rot=(-25, 0, 0)))
    # Rune channels on the flanks.
    for s in (-1, 1):
        g = C.glyphs(f"torso_runes{s}", [[(-0.16, -0.12), (-0.04, 0.0), (-0.04, 0.16)], [(0.02, -0.14), (0.02, 0.06), (0.12, 0.16)],
                                          [(-0.04, 0.0), (0.02, 0.06)]],
                     (s * 0.505, 0.02, 1.42), (0, -s, 0), (0, 0, 1), 0.024, 0.02)
        # The shell is a subdivided boulder: drape the inlay on it (it used to hang in the air beside it).
        parts.append(C.project_onto(g, shell, (s * 0.505, 0.02, 1.42), (s, 0, 0), lift=0.006))
    # Crown inlay: the casing's old ward rune, running back from the head over the top of the shell
    # (the largest surface the game camera sees).
    crown = C.glyphs("crown_rune", [[(0.0, -0.2), (0.0, 0.3)], [(-0.2, 0.0), (0.0, 0.14), (0.2, 0.0)],
                                    [(-0.13, -0.16), (0.0, -0.06), (0.13, -0.16)], [(-0.07, 0.3), (0.07, 0.3)]],
                     (0, 0.02, 1.95), (1, 0, 0), (0, 1, 0), 0.026, 0.02)
    parts.append(C.project_onto(crown, shell, (0, 0.02, 1.95), (0, 0, 1), lift=0.008))
    # Back: a hazard service panel and the reel rack.
    hz_y = C.ray_hit(shell, (0.1, 2.0, 1.25), (0, -1, 0)).y
    parts.append(C.hazard_panel("back_hazard", (0.42, 0.03, 0.2), 0.07, loc=(0, hz_y + 0.004, 1.25), rot=(-10, 0, 0), bevel=0.008, frame=0.025))
    rack = C.box("reel_rack", (0.62, 0.1, 0.12), "metal", loc=(0, 0.42, 1.62), bevel=0.02)
    parts.append(rack)
    for s in (-1, 1):
        parts.append(C.cyl(f"reel_axle{s}", 0.04, 0.16, "metal_light", 8, rot=(-60, 0, 0), loc=(s * 0.24, 0.47, 1.70)))
    # Collar around the sunken neck.
    parts.append(C.torus("collar", 0.21, 0.05, "metal", 28, 8, loc=(0, -0.25, 1.63), rot=(-30, 0, 0)))
    for p in parts:
        sk.rigid(p, "chest")

    # Reels on the back (spin bones), tilted back so they read above the shoulders.
    for s, bone in ((1, "reel.L"), (-1, "reel.R")):
        r = []
        r.append(C.lathe(f"reel{s}", [(0.04, -0.035), (0.24, -0.035), (0.24, -0.02), (0.17, -0.016), (0.17, 0.016), (0.24, 0.02), (0.24, 0.035),
                                       (0.04, 0.035), (0.04, -0.035)], ["brass", "tape"], 32, band_mats=[0, 0, 0, 1, 0, 0, 0, 0], cap=False))
        for k in range(3):
            a = 90 + 120 * k
            r.append(C.box(f"reel_spoke{s}{k}", (0.15, 0.03, 0.075), "brass",
                           loc=(0.11 * math.cos(math.radians(a)), 0.11 * math.sin(math.radians(a)), 0), rot=(0, 0, a)))
        r.append(C.cyl(f"reel_hub{s}", 0.055, 0.09, "metal", 16, bevel=0.01))
        ob = C.join_raw(f"reel_{bone}", r)
        C.place(ob, (0, 0, 0), (-60, 0, 0))
        C.place(ob, (s * 0.24, 0.53, 1.735))
        sk.rigid(ob, bone)
    # Tape strand between the reels.
    tape = C.tube("back_tape", [(0.25, 0.40, 1.945), (0.12, 0.37, 1.975), (0.0, 0.36, 1.985), (-0.12, 0.37, 1.975), (-0.25, 0.40, 1.945)], 0.018, "tape", 6)
    sk.rigid(tape, "chest")
    # The cable from the reel rack to the hammer arm (soft: automatic weights, corrected).
    cab = C.tube("arm_cable", [(-0.2, 0.47, 1.58), (-0.45, 0.42, 1.68), (-0.72, 0.22, 1.5), (-0.86, 0.12, 1.15), (-0.9, 0.0, 0.9)],
                 0.032, "cable", 8)
    sk.auto(cab, ["chest", "shoulder.R", "upper_arm.R", "forearm.R"])


def build_head(sk: C.Skin) -> None:
    hz = HEAD_Z
    helm = C.box("helm", (0.4, 0.34, 0.28), "ceramic_dark", loc=(0, -0.43, hz), bevel=0.045, seg=2, taper=(0.84, 0.86))
    C.inset_faces(helm, lambda c, n: n.y < -0.9, 0.035, -0.025, "metal")
    lens = C.lathe("eye", [(0, -0.01), (0.078, -0.01), (0.078, 0.008), (0.066, 0.022), (0.04, 0.034), (0, 0.04)], "eye_glow", 24,
                   rot=(90, 0, 0))
    C.place(lens, (0.0, EYE_Y + 0.04, hz))
    bezel = C.ring("eye_bezel", 0.1, 0.074, 0.03, "brass", 24, rot=(90, 0, 0), bevel=0.008)
    C.place(bezel, (0.0, EYE_Y + 0.045, hz))
    brow = C.box("brow", (0.46, 0.17, 0.075), "ceramic", loc=(0, -0.52, hz + 0.14), rot=(12, 0, 0), bevel=0.022, seg=2)
    # Tape-guide posts on the crown: the reel tape runs over the head.
    guides = [C.cyl(f"guide{s}", 0.024, 0.12, "brass", 12, loc=(s * 0.12, -0.38, hz + 0.18)) for s in (-1, 1)]
    caps = [C.cyl(f"guide_cap{s}", 0.038, 0.022, "metal_light", 12, loc=(s * 0.12, -0.38, hz + 0.245), bevel=0.005) for s in (-1, 1)]
    for p in (helm, bezel, brow, *guides, *caps):
        sk.rigid(p, "head")
    sk.rigid(lens, "eye")


def build_hips(sk: C.Skin) -> None:
    pelvis = C.box("pelvis", (0.56, 0.42, 0.24), "metal", loc=(0, 0.02, 0.78), bevel=0.04, seg=2)
    parts = [pelvis]
    # Ceramic skirt plates.
    for name, loc, rot, size in (("skirt_f", (0, -0.21, 0.73), (8, 0, 0), (0.36, 0.05, 0.26)),
                                 ("skirt_b", (0, 0.25, 0.75), (-8, 0, 0), (0.4, 0.05, 0.24)),
                                 ("skirt_l", (0.31, 0.02, 0.74), (0, -10, 0), (0.05, 0.3, 0.22)),
                                 ("skirt_r", (-0.31, 0.02, 0.74), (0, 10, 0), (0.05, 0.3, 0.22))):
        parts.append(C.box(name, size, "ceramic_dark", loc=loc, rot=rot, bevel=0.015))
    parts.append(C.glyphs("skirt_rune", [[(-0.08, -0.06), (0, 0.07), (0.08, -0.06)], [(0, 0.07), (0, -0.08)]],
                          (0, -0.24, 0.73), (1, 0, 0), (0, 0.14, 0.99), 0.016, 0.014))
    for p in parts:
        sk.rigid(p, "hips")
    # Rubber bellows between pelvis and torso: the one soft part of the body.
    prof = []
    z = 0.86
    for i in range(7):
        prof.append((0.29 if i % 2 == 0 else 0.25, z))
        z += 0.035
    bel = C.lathe("bellows", [(0, 0.86)] + prof + [(0, prof[-1][1])], "cable", 32)
    sk.blend(bel, ["hips", "spine", "chest"], 3.0)


def build_leg(sk: C.Skin, s: int) -> None:
    side = "L" if s > 0 else "R"
    x = s * 0.27
    thigh = [C.cyl(f"thigh{side}", 0.125, 0.34, "metal_light", 16, loc=(x * 1.04, 0.01, 0.56)),
             C.torus(f"hip_ring{side}", 0.14, 0.034, "brass", 20, 8, loc=(x, 0.02, 0.70), rot=(0, 90, 0)),
             C.box(f"thigh_plate{side}", (0.08, 0.26, 0.27), "ceramic", loc=(x + s * 0.125, 0.0, 0.57), bevel=0.025, seg=2)]
    for p in thigh:
        sk.rigid(p, f"thigh.{side}")
    shin = [C.box(f"knee{side}", (0.27, 0.22, 0.16), "ceramic_dark", loc=(x * 1.08, -0.08, 0.40), bevel=0.035, seg=2),
            C.box(f"greave{side}", (0.32, 0.33, 0.28), "ceramic", loc=(x * 1.1, 0.0, 0.23), bevel=0.045, seg=2, taper=(0.85, 0.85)),
            C.box(f"greave_band{side}", (0.335, 0.345, 0.045), "brass", loc=(x * 1.1, 0.0, 0.16), bevel=0.012)]
    for p in shin:
        sk.rigid(p, f"shin.{side}")
    foot = [C.box(f"foot{side}", (0.35, 0.46, 0.12), "ceramic_dark", loc=(x * 1.1, -0.06, 0.06), bevel=0.035, seg=2, taper=(0.93, 0.88))]
    for k, dx in enumerate((-0.105, 0.0, 0.105)):
        foot.append(C.box(f"toe{side}{k}", (0.09, 0.12, 0.08), "brass", loc=(x * 1.1 + dx, -0.31, 0.045), bevel=0.022, seg=2, taper=(0.8, 0.7)))
    for p in foot:
        sk.rigid(p, f"foot.{side}")


def pauldron(name: str, s: int):
    dome = C.lathe(name, [(0.34, -0.08), (0.338, 0.0), (0.325, 0.07), (0.3, 0.135), (0.26, 0.19), (0.2, 0.238), (0.11, 0.27), (0.0, 0.28)],
                   "ceramic", 32, cap=False)
    C.mod_solidify(dome, 0.05, -1)
    C.apply_modifiers(dome)
    C.resmooth(dome, 45)
    rim = C.torus(name + "_rim", 0.335, 0.027, "brass", 32, 8, loc=(0, 0, -0.08))
    stud = C.cyl(name + "_stud", 0.055, 0.05, "metal_light", 12, loc=(0, 0, 0.285), bevel=0.012)
    ob = C.join_raw(name, [dome, rim, stud])
    C.place(ob, (0, 0, 0), (0, s * 28, 0))
    return ob


def build_arm(sk: C.Skin, s: int) -> None:
    side = "L" if s > 0 else "R"
    sh_x = s * 0.62
    p = pauldron(f"pauldron{side}", s)
    C.place(p, (sh_x, 0.0, 1.70))
    sk.rigid(p, f"shoulder.{side}")
    if s > 0:
        o, u, v = (sh_x + 0.1, -0.2, 1.78), Vector((1, 0, -0.45)), Vector((0, 0.6, 1))
        g = C.glyphs("pauldron_rune", [[(-0.1, -0.05), (0, 0.06), (0.1, -0.05)], [(0, 0.06), (0, -0.12)], [(-0.05, -0.12), (0.05, -0.12)]],
                     o, u, v, 0.022, 0.016)
        sk.rigid(C.project_onto(g, p, o, u.normalized().cross(v.normalized()), 0.5, lift=0.012), "shoulder.L")
    else:
        # Hazard paint on the hammer-arm shoulder: a band of stripes following the dome above its rim.
        hz = C.hazard_band("pauldron_hazard", 0.346, -0.045, 0.045, stripes=14, slant=1, r_top=0.338, rows=2)
        bm = bmesh.new()
        bm.from_mesh(hz.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if not (-150 < math.degrees(math.atan2(f.calc_center_median().y,
                                                                                       f.calc_center_median().x)) < -30)],
                         context="FACES")
        bm.to_mesh(hz.data)
        bm.free()
        C.place(hz, (0, 0, 0), (0, s * 28, 0))
        C.place(hz, (sh_x, 0.0, 1.70))
        sk.rigid(hz, "shoulder.R")
    sk.rigid(C.cyl(f"shoulder_joint{side}", 0.13, 0.2, "metal", 20, rot=(0, 90, 0), loc=(s * 0.55, 0, 1.6), bevel=0.02), f"shoulder.{side}")
    big = 1.15 if s < 0 else 1.0
    ux, ex = s * 0.64, s * (0.76 if s < 0 else 0.72)
    upper = [C.tube(f"upper{side}", [(ux, 0, 1.52), (ex, -0.05, 1.16)], 0.095 * big, "metal_light", 12),
             C.box(f"upper_plate{side}", (0.07, 0.22, 0.3), "ceramic_dark", loc=((ux + ex) / 2 + s * 0.1, -0.02, 1.36), rot=(0, s * 12, 0), bevel=0.02)]
    for q in upper:
        sk.rigid(q, f"upper_arm.{side}")
    sk.rigid(C.cyl(f"elbow{side}", 0.12 * big, 0.2 * big, "brass", 20, rot=(0, 90, 0), loc=(ex, -0.05, 1.15), bevel=0.02), f"forearm.{side}")
    if s > 0:
        fore = [C.box("gauntlet.L", (0.24, 0.26, 0.42), "ceramic", loc=(0.73, -0.12, 0.93), rot=(-14, 0, 0), bevel=0.04, seg=2, taper=(1.1, 1.1)),
                C.box("gauntlet_band.L", (0.26, 0.28, 0.04), "brass", loc=(0.73, -0.15, 0.80), rot=(-14, 0, 0), bevel=0.01)]
        for q in fore:
            sk.rigid(q, "forearm.L")
        hand = [C.box("palm.L", (0.2, 0.2, 0.1), "metal", loc=(0.74, -0.19, 0.67), bevel=0.02)]
        for k, (dx, dy) in enumerate(((-0.07, -0.06), (0.07, -0.06), (0.0, 0.07))):
            prong = C.prism(f"prong{k}", [(-0.025, 0.0), (0.025, 0.0), (0.02, -0.16), (-0.005, -0.2)], 0.05, "metal_light", bevel=0.006)
            C.place(prong, (0.74 + dx, -0.19 + dy, 0.64), (0, 0, 0))
            hand.append(prong)
        for q in hand:
            sk.rigid(q, "hand.L")
    else:
        fore = [C.box("gauntlet.R", (0.28, 0.3, 0.4), "ceramic", loc=(-0.79, -0.1, 0.94), rot=(-14, 0, 0), bevel=0.04, seg=2, taper=(1.12, 1.1)),
                C.cyl("piston_a", 0.045, 0.42, "metal_light", 12, loc=(-0.95, -0.08, 0.93), rot=(-14, 0, 0)),
                C.cyl("piston_b", 0.045, 0.42, "metal_light", 12, loc=(-0.63, -0.08, 0.93), rot=(-14, 0, 0)),
                C.box("wrist_ring", (0.32, 0.32, 0.06), "brass", loc=(-0.81, -0.16, 0.73), bevel=0.015)]
        for q in fore:
            sk.rigid(q, "forearm.R")
        # Capstan hammer: a drum along the hammer bone axis with a studded striking face below.
        prof = [(0, 0.30), (0.20, 0.30), (0.27, 0.27), (0.27, 0.22), (0.24, 0.20), (0.24, -0.16), (0.27, -0.18), (0.28, -0.24),
                (0.25, -0.27), (0, -0.27)]
        drum = C.lathe("capstan", prof, ["brass", "metal", "metal_light"], 32, band_mats=[0, 0, 0, 0, 1, 2, 2, 2, 2])
        band = C.hazard_band("capstan_hazard", 0.247, -0.13, 0.17, stripes=8, slant=2, rows=6)
        studs = C.bolts("capstan_studs", [(0.15 * math.cos(math.radians(a)), 0.15 * math.sin(math.radians(a)), -0.27) for a in range(0, 360, 60)]
                        + [(0, 0, -0.27)], (0, 0, -1), 0.04, 0.035, "metal")
        hm = C.join_raw("hammer_head", [drum, band, studs])
        C.place(hm, (-0.81, -0.18, 0.43))
        sk.rigid(hm, "hammer")
        # Charge ring: hidden inside the drum at rest; the telegraph swells it out as a glowing band.
        ring = C.torus("capstan_charge", 0.2, 0.03, "charge_glow", 32, 8, loc=(-0.81, -0.18, 0.45))
        sk.rigid(ring, "charge")


def build_rig() -> C.RigBuilder:
    rb = C.RigBuilder()
    rb.bone("root", (0, 0, 0), (0, 0, 0.3))
    rb.bone("hips", (0, 0.02, 0.70), (0, 0.02, 0.92), "root")
    rb.bone("spine", (0, 0.02, 0.92), (0, 0.0, 1.20), "hips", connect=True)
    rb.bone("chest", (0, 0.0, 1.20), (0, -0.04, 1.70), "spine", connect=True)
    rb.bone("head", (0, -0.34, 1.52), (0, -0.38, 1.76), "chest")
    for s, side in ((1, "L"), (-1, "R")):
        rb.bone(f"reel.{side}", (s * 0.24, 0.53, 1.735), (s * 0.24, 0.53 + 0.1 * math.cos(math.radians(60)), 1.735 + 0.1 * math.sin(math.radians(60))),
                "chest", spin=True)
        rb.bone(f"shoulder.{side}", (s * 0.18, 0, 1.62), (s * 0.56, 0, 1.62), "chest")
        ex = s * (0.76 if s < 0 else 0.72)
        rb.bone(f"upper_arm.{side}", (s * 0.62, 0, 1.58), (ex, -0.05, 1.15), f"shoulder.{side}")
        wx = s * (0.81 if s < 0 else 0.74)
        rb.bone(f"forearm.{side}", (ex, -0.05, 1.15), (wx, -0.17, 0.72), f"upper_arm.{side}", connect=True)
        rb.bone(f"thigh.{side}", (s * 0.27, 0.02, 0.72), (s * 0.29, 0.0, 0.40), "hips")
        rb.bone(f"shin.{side}", (s * 0.29, 0.0, 0.40), (s * 0.30, 0.0, 0.11), f"thigh.{side}", connect=True)
        rb.bone(f"foot.{side}", (s * 0.30, 0.0, 0.11), (s * 0.30, -0.24, 0.06), f"shin.{side}", connect=True)
    rb.bone("hand.L", (0.74, -0.17, 0.72), (0.74, -0.2, 0.5), "forearm.L", connect=True)
    rb.bone("hammer", (-0.81, -0.17, 0.72), (-0.81, -0.18, 0.2), "forearm.R", connect=True, spin=True)
    rb.bone("charge", (-0.81, -0.18, 0.45), (-0.81, -0.18, 0.35), "hammer")
    rb.bone("eye", (0.0, EYE_Y + 0.04, HEAD_Z), (0.0, EYE_Y - 0.06, HEAD_Z), "head")
    return rb


# ───────────────────────────── animation ─────────────────────────────


def walk_pose(phase: int) -> dict:
    """Heavy two-step walk. phase 0: left foot planted forward; 1: passing (right leg lifted);
    2: right forward; 3: passing (left lifted)."""
    def legs(fwd: str, back: str) -> dict:
        return {f"thigh.{fwd}": {"r": (-20, 0, 0)}, f"shin.{fwd}": {"r": (8, 0, 0)}, f"foot.{fwd}": {"r": (12, 0, 0)},
                f"thigh.{back}": {"r": (16, 0, 0)}, f"shin.{back}": {"r": (14, 0, 0)}, f"foot.{back}": {"r": (-30, 0, 0)}}

    def passing(plant: str, lift: str) -> dict:
        return {f"thigh.{plant}": {"r": (2, 0, 0)}, f"shin.{plant}": {"r": (4, 0, 0)}, f"foot.{plant}": {"r": (-6, 0, 0)},
                f"thigh.{lift}": {"r": (-26, 0, 0)}, f"shin.{lift}": {"r": (46, 0, 0)}, f"foot.{lift}": {"r": (-20, 0, 0)}}
    if phase in (0, 2):
        f, b = ("L", "R") if phase == 0 else ("R", "L")
        p = legs(f, b)
        roll = 3 if phase == 0 else -3
        p.update({"hips": {"l": (0, 0, -0.05), "r": (0, roll, 0)}, "chest": {"r": (6, -roll, 0)},
                  "upper_arm.L": {"r": (14 if f == "L" else -10, 0, 0)}, "upper_arm.R": {"r": (-8 if f == "L" else 8, 0, 0)},
                  "forearm.R": {"r": (-6, 0, 0)}, "head": {"r": (-4, 0, 0)}})
        return p
    plant, lift = ("L", "R") if phase == 1 else ("R", "L")
    p = passing(plant, lift)
    roll = 4 if plant == "L" else -4
    p.update({"hips": {"l": (0, 0, 0.0), "r": (0, roll, 0)}, "chest": {"r": (4, -roll * 0.5, 0)},
              "upper_arm.L": {"r": (2, 0, 0)}, "upper_arm.R": {"r": (0, 0, 0)}, "forearm.R": {"r": (-4, 0, 0)},
              "head": {"r": (-2, 0, 0)}})
    return p


WIND = {  # end of the telegraph: hammer cocked overhead, body coiled back and twisted, crouched
    "hips": {"l": (0, 0.03, -0.07), "r": (0, 0, -6)},
    "spine": {"r": (-6, 0, -6)},
    "chest": {"r": (-10, 4, -10)},
    "head": {"r": (-8, 0, 6)},
    "shoulder.R": {"r": (0, 18, 0)},
    "upper_arm.R": {"r": (-168, 0, -10)},
    "forearm.R": {"r": (-32, 0, 0)},
    "shoulder.L": {"r": (0, -6, 0)},
    "upper_arm.L": {"r": (-55, 0, 18)},
    "forearm.L": {"r": (-20, 0, 0)},
    "thigh.L": {"r": (-26, 0, 0)}, "shin.L": {"r": (30, 0, 0)}, "foot.L": {"r": (-4, 0, 0)},
    "thigh.R": {"r": (8, 0, 0)}, "shin.R": {"r": (22, 0, 0)}, "foot.R": {"r": (-30, 0, 0)},
}

SLAM = {  # impact: the capstan face lands flat on the floor in front (checked: hammer z = 0), body folded over it
    "hips": {"l": (0, -0.06, -0.14), "r": (0, 0, 4)},
    "spine": {"r": (14, 0, 4)},
    "chest": {"r": (26, -4, 10)},
    "head": {"r": (-22, 0, -4)},
    "shoulder.R": {"r": (0, -6, 0)},
    "upper_arm.R": {"r": (-66, 0, 26)},
    "forearm.R": {"r": (10, 0, 0)},
    "upper_arm.L": {"r": (-10, 0, 22)},
    "forearm.L": {"r": (-25, 0, 0)},
    "thigh.L": {"r": (-40, 0, 0)}, "shin.L": {"r": (48, 0, 0)}, "foot.L": {"r": (-8, 0, 0)},
    "thigh.R": {"r": (16, 0, 0)}, "shin.R": {"r": (34, 0, 0)}, "foot.R": {"r": (-50, 0, 0)},
}


def mix(a: dict, b: dict, t: float) -> dict:
    out = {}
    for k in set(a) | set(b):
        pa, pb = a.get(k, {}), b.get(k, {})
        d = {}
        for ch in ("r", "l"):
            va, vb = pa.get(ch, (0, 0, 0)), pb.get(ch, (0, 0, 0))
            d[ch] = tuple(x + (y - x) * t for x, y in zip(va, vb))
        out[k] = d
    return out


def over(a: dict, b: dict) -> dict:
    """Pose a with the bones listed in b replaced."""
    out = dict(a)
    out.update(b)
    return out


DEAD_MID = {  # knees buckling, the body starting to fold
    "hips": {"l": (0, 0.0, 0), "r": (6, 0, 0)},
    "thigh.L": {"r": (-48, 0, 0)}, "shin.L": {"r": (84, 0, 0)}, "foot.L": {"r": (-30, 0, 0)},
    "thigh.R": {"r": (-42, 0, 0)}, "shin.R": {"r": (80, 0, 0)}, "foot.R": {"r": (-34, 0, 0)},
    "chest": {"r": (8, 0, 4)}, "head": {"r": (10, 0, 0)},
    "upper_arm.L": {"r": (-20, 0, 12)}, "upper_arm.R": {"r": (-30, 0, -12)}, "forearm.R": {"r": (-10, 0, 0)},
}

DEAD = {  # final rest: kneeling, folded forward, hammer and clamp on the floor
    "hips": {"l": (0, -0.1, 0), "r": (22, 0, 3)},
    "thigh.L": {"r": (-82, 0, 0)}, "shin.L": {"r": (124, 0, 0)}, "foot.L": {"r": (-64, 0, 0)},
    "thigh.R": {"r": (-78, 0, 0)}, "shin.R": {"r": (122, 0, 0)}, "foot.R": {"r": (-66, 0, 0)},
    "spine": {"r": (12, 0, 0)}, "chest": {"r": (26, 0, 5)}, "head": {"r": (28, 0, 10)},
    "shoulder.R": {"r": (0, -8, 0)}, "upper_arm.R": {"r": (-104, 0, -22)}, "forearm.R": {"r": (-8, 0, 0)},
    "shoulder.L": {"r": (0, 8, 0)}, "upper_arm.L": {"r": (-62, 0, 26)}, "forearm.L": {"r": (-10, 0, 0)},
}

DEAD_BOUNCE = {  # the small rebound after the body lands
    "hips": {"l": (0, -0.1, 0), "r": (19, 0, 3)}, "chest": {"r": (22, 0, 5)}, "head": {"r": (22, 0, 9)},
    "upper_arm.R": {"r": (-110, 0, -22)}, "upper_arm.L": {"r": (-68, 0, 26)},
}


def animate(rig, body) -> list:
    A = C.Animator(rig)
    # Every action ends with A.ground(): the hips are shifted per frame so the lowest part rests on the
    # floor. The key poses below set the attitude of the body; its height follows from the legs.
    REELS = ("reel.L", "reel.R")

    A.begin("idle", 2.0, loop=True)
    for r in REELS:
        A.spin(r, 120)
    # A slow heave: the chest rises and rolls, the weight shifts from foot to foot, the hammer arm
    # hangs heavy and swings a little late, the head tracks from side to side.
    breath = C.piecewise([(0, 1.0), (30, 1.12), (60, 1.0)])
    A.overlay = lambda f: {"charge": {"s": breath(f)}}
    rest = {"hips": {"l": (0, 0, -0.012), "r": (0, 1.5, 0)}, "spine": {"r": (2, 0, 0)}, "chest": {"r": (3, -1.5, 0)},
            "upper_arm.L": {"r": (-4, 0, 0)}, "upper_arm.R": {"r": (3, 0, -2)}, "forearm.R": {"r": (-2, 0, 0)}, "head": {"r": (2, 0, 9)}}
    A.pose(0, rest)
    A.pose(15, {"hips": {"l": (0, 0, 0.0)}, "spine": {"r": (0, 0, 0)}, "chest": {"r": (0, 0, 0), "l": (0, 0, 0.02)},
                "upper_arm.L": {"r": (0, 0, 0)}, "upper_arm.R": {"r": (0, 0, -3)}, "forearm.R": {"r": (-5, 0, 0)}, "head": {"r": (-1, 0, 3)}})
    A.pose(30, {"hips": {"l": (0, 0, 0.012), "r": (0, -1.5, 0)}, "spine": {"r": (-2, 0, 0)}, "chest": {"r": (-3, 1.5, 0), "l": (0, 0, 0.034)},
                "upper_arm.L": {"r": (4, 0, 2)}, "upper_arm.R": {"r": (-4, 0, -1)}, "forearm.R": {"r": (-3, 0, 0)}, "head": {"r": (-3, 0, -9)}})
    A.pose(45, {"hips": {"l": (0, 0, 0.0)}, "spine": {"r": (0, 0, 0)}, "chest": {"r": (0, 0, 0), "l": (0, 0, 0.016)},
                "upper_arm.L": {"r": (1, 0, 1)}, "upper_arm.R": {"r": (-1, 0, 0)}, "forearm.R": {"r": (2, 0, 0)}, "head": {"r": (0, 0, -3)}})
    A.pose(60, rest)
    A.ground([body])
    A.end()

    A.begin("move", 1.2, loop=True)
    for r in REELS:
        A.spin(r, 240)
    for i, f in enumerate((0, 9, 18, 27, 36)):
        A.pose(f, walk_pose(i % 4))
    A.ground([body])
    A.end()

    A.begin("telegraph", 1.0)
    charge = C.piecewise([(0, 1.0), (10, 1.05), (22, 1.3), (30, 1.36)])
    A.overlay = lambda f: {"eye": {"s": C.EYE_TELEGRAPH(f)}, "charge": {"s": charge(f)}}
    for r in REELS:
        A.spin(r, 0, curve=lambda t: 700 * t * t)
    A.spin("hammer", 0, curve=lambda t: 1080 * t * t)
    A.pose(0, {})
    A.pose(6, mix({}, WIND, 0.25))
    A.pose(14, mix({}, WIND, 0.7))
    A.pose(22, WIND)
    A.pose(26, over(WIND, {"chest": {"r": (-12, 4, -11)}, "upper_arm.R": {"r": (-172, 0, -10)}}))
    A.pose(30, over(WIND, {"hips": {"l": (0, 0.03, -0.075), "r": (0, 0, -6)}}))
    A.ground([body])
    A.end()

    A.begin("attack", 1.0)
    spent = C.piecewise([(0, 1.36), (5, 1.45), (9, 1.0), (30, 1.0)])
    A.overlay = lambda f: {"eye": {"s": C.EYE_ATTACK(f)}, "charge": {"s": spent(f)}}
    for r in REELS:
        A.spin(r, 0, curve=lambda t: 700 + 300 * C.ease_out(t))
    A.spin("hammer", 0, curve=lambda t: 1080 + 360 * C.ease_out(t))
    A.pose(0, WIND, "LINEAR")
    A.pose(3, mix(WIND, SLAM, 0.55), "LINEAR")
    A.pose(5, SLAM)
    A.pose(9, over(SLAM, {"hips": {"l": (0, -0.06, -0.125), "r": (0, 0, 4)}, "chest": {"r": (24, -4, 9)}}))
    A.pose(16, mix(SLAM, {}, 0.25))
    A.pose(24, mix(SLAM, {}, 0.8))
    A.pose(30, {})
    A.ground([body])
    A.end()

    A.begin("stagger", 1.0)
    A.overlay = C.eye_overlay(C.EYE_STAGGER)
    A.pose(0, {})
    A.pose(4, {"hips": {"l": (0, 0.1, -0.03), "r": (0, 6, 0)}, "chest": {"r": (-20, 0, 8)}, "head": {"r": (-22, 0, -10)},
               "upper_arm.L": {"r": (-40, 0, 25)}, "upper_arm.R": {"r": (-30, 0, -15)}, "forearm.R": {"r": (-25, 0, 0)},
               "thigh.L": {"r": (-12, 0, 0)}, "shin.L": {"r": (10, 0, 0)}, "thigh.R": {"r": (14, 0, 0)}, "shin.R": {"r": (20, 0, 0)},
               "foot.R": {"r": (-25, 0, 0)}})
    A.pose(10, {"hips": {"l": (0, 0.12, -0.06), "r": (0, -3, 0)}, "chest": {"r": (10, 0, -6)}, "head": {"r": (8, 0, 6)},
                "upper_arm.L": {"r": (-10, 0, 10)}, "upper_arm.R": {"r": (10, 0, -5)}, "thigh.L": {"r": (-14, 0, 0)},
                "shin.L": {"r": (16, 0, 0)}, "thigh.R": {"r": (6, 0, 0)}, "shin.R": {"r": (10, 0, 0)}})
    A.pose(17, {"hips": {"l": (0, 0.06, -0.02)}, "chest": {"r": (-5, 0, 3)}, "head": {"r": (-4, 0, -2)}})
    A.pose(24, {"hips": {"l": (0, 0.02, 0)}, "chest": {"r": (2, 0, 0)}})
    A.pose(30, {})
    A.ground([body])
    A.end()

    # death: jolted upright, the knees give, it drops to a kneel and folds forward; the hammer arm
    # is flung out and the capstan thuds onto the floor beside it, one small bounce, then still.
    A.begin("death", 1.0)
    A.overlay = lambda f: {"eye": {"s": C.EYE_DEATH(f)}, "charge": {"s": C.piecewise([(0, 1.0), (5, 1.3), (12, 0.6), (20, 0.05), (30, 0.05)])(f)}}
    for r in REELS:
        A.spin(r, 0, curve=lambda t: 200 * C.ease_out(t))
    A.pose(0, {})
    A.pose(5, {"chest": {"r": (-16, 0, -6)}, "head": {"r": (-25, 0, 0)}, "upper_arm.L": {"r": (-30, 0, 20)},
               "upper_arm.R": {"r": (-20, 0, -12)}, "hips": {"l": (0, 0.03, 0)}})
    A.pose(12, DEAD_MID)
    A.pose(19, DEAD)
    A.pose(23, over(DEAD, DEAD_BOUNCE))
    A.pose(30, DEAD)
    A.ground([body])
    A.end()
    return A.actions


def build() -> tuple:
    C.reset_scene()
    rig = build_rig().finish()
    sk = C.Skin(rig)
    build_torso(sk)
    build_head(sk)
    build_hips(sk)
    for s in (1, -1):
        build_leg(sk, s)
        build_arm(sk, s)
    body = sk.build("brute")
    C.uv_unwrap(body)
    actions = animate(rig, body)
    return rig, body, actions


def main() -> None:
    args = C.script_args()
    out = args["out"] or os.path.join(C.REPO, "assets", "models", "enemies", "brute.glb")
    prev = args["previews"] or os.path.join(C.REPO, "art", "previews", "enemies", "brute")
    rig, body, actions = build()
    if args["quick"]:  # --quick: build and run the floor check only (pose tuning)
        C.floor_report(rig, [body], actions, step=1, frames={"attack": [5], "death": [19, 30]})
        return
    C.export_glb(out)
    tris, lo, hi = C.mesh_stats([body])
    print(f"brute: {tris} triangles, rest bounds {tuple(round(x, 3) for x in lo)} .. {tuple(round(x, 3) for x in hi)}")
    C.floor_report(rig, [body], actions)
    pv = C.Previewer(prev, floor_tiles=2)
    pv.turnaround([body])
    pv.iso([body])
    pv.thumbnail([body])
    if args["anim"]:
        lo, hi = pv.frame_bounds([body], 0.1)
        lo = Vector((lo.x - 0.2, lo.y - 0.5, 0.0))
        hi = Vector((hi.x + 0.1, hi.y + 0.2, hi.z + 0.5))
        pv.action_frames(rig, [body], actions, 8, (300, 300), lo, hi)
    C.run_sheets("brute", prev)


if __name__ == "__main__":
    main()
