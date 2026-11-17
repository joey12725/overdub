"""Grunt: the baseline ruin-security walker (assets/models/enemies/grunt.glb).

Reads as: a squat, broad ceramic sentinel (~1.3 tall) with a tape-head helmet and ONE orange eye,
a speaker cone set into its chest, a tape-deck backpack with two exposed reels, and a capstan
mallet carried forward in its right clamp (hazard-banded, the part that hurts). It marches at the
nearest self and slams the mallet down on its beat (telegraph = mallet raised overhead with a
charge ring swelling on the head; attack = overhead slam into the 120-degree cone in front).

Run:  blender --background --python art/enemies/grunt.py -- [--no-export] [--no-stills] [--no-sheets]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import common as C  # noqa: E402
from common import K  # noqa: E402

# ------------------------------------------------------------------------------------------
# Skeleton (Blender axes: Z up, front -Y, the grunt's right side is -X)
# ------------------------------------------------------------------------------------------
HIP_Z = 0.50
BONES = [
    ("root", (0, 0, 0), (0, 0, 0.2), None),
    ("hips", (0, 0, HIP_Z), (0, 0, 0.62), "root"),
    ("chest", (0, 0, 0.62), (0, 0, 1.0), "hips"),
    ("head", (0, -0.01, 1.0), (0, -0.01, 1.2), "chest"),
    ("eye", (0, -0.16, 1.1), (0, -0.26, 1.1), "head"),
    # Reel bones: head -> tail is the AXLE (common.make_rig lays the bone across it with local X on
    # the axle, the axis the game spins). The game turns reel.L by +t and reel.R by -t, so the two
    # axles point opposite ways and both reels wind the same way, like a real cassette.
    ("reel.L", (0.105, 0.31, 0.85), (0.105, 0.41, 0.85), "chest"),
    ("reel.R", (-0.105, 0.31, 0.85), (-0.105, 0.21, 0.85), "chest"),
]
# Arms: the left hangs; the right is bent forward so the clamp holds the mallet upright in front.
ARM = {
    "L": {"sh": (0.35, 0, 0.93), "el": (0.37, 0, 0.70), "wr": (0.37, -0.05, 0.47), "end": (0.37, -0.07, 0.37)},
    "R": {"sh": (-0.35, 0, 0.93), "el": (-0.37, 0, 0.70), "wr": (-0.37, -0.2, 0.6), "end": (-0.37, -0.29, 0.6)},
}
GRIP = (-0.37, -0.25, 0.6)          # where the mallet handle passes through the right clamp
HEAD_C = (-0.37, -0.25, 1.02)       # mallet head centre
for s, x in (("L", 1), ("R", -1)):
    a = ARM[s]
    BONES += [
        (f"upper_arm.{s}", a["sh"], a["el"], "chest"),
        (f"forearm.{s}", a["el"], a["wr"], f"upper_arm.{s}"),
        (f"hand.{s}", a["wr"], a["end"], f"forearm.{s}"),
        (f"thigh.{s}", (0.14 * x, 0, HIP_Z), (0.15 * x, -0.02, 0.29), "hips"),
        (f"shin.{s}", (0.15 * x, -0.02, 0.29), (0.15 * x, 0.01, 0.085), f"thigh.{s}"),
        (f"foot.{s}", (0.15 * x, 0.01, 0.085), (0.15 * x, -0.13, 0.03), f"shin.{s}"),
    ]
BONES.append(("charge", HEAD_C, (HEAD_C[0], HEAD_C[1], HEAD_C[2] + 0.1), "hand.R"))


# ------------------------------------------------------------------------------------------
# Model
# ------------------------------------------------------------------------------------------

def torso():
    parts = []
    # Main ceramic shell: a broad chamfered block, wider at the shoulders.
    t = C.box("torso", (0.56, 0.40, 0.40), loc=(0, 0, 0.81), mat="ceramic", taper=(1.12, 1.05), cuts=1)
    # Recessed front panel (speaker bay) and side panels (rune grooves) cut as real insets.
    C.inset_faces(t, lambda c, n: n.y < -0.9, thickness=0.045, depth=-0.018, mat="ceramic_dark", individual=False)
    C.inset_faces(t, lambda c, n: abs(n.x) > 0.9 and c.z > 0.8, thickness=0.03, depth=-0.012)
    C.bevel(t, 0.035, 2, limit_deg=35)
    C.chip(t, loc=(0.27, -0.2, 1.01), size=(0.12, 0.1, 0.1), rot=(30, 20, 40))
    parts.append(C.tag(t, "chest"))
    # Belly band: dark inscribed metal ring where shell meets the hip block.
    belly = C.box("belly", (0.5, 0.36, 0.08), loc=(0, 0.0, 0.62), mat="metal")
    C.bevel(belly, 0.015, 1)
    parts.append(C.tag(belly, "chest"))
    # Speaker cone set into the chest (front, -Y): brass rim, dark cone, dust cap.
    spk = C.lathe("speaker", [(0.0, 0.028), (0.03, 0.022), (0.042, 0.0), (0.105, 0.012),
                              (0.122, 0.018), (0.142, 0.018), (0.142, 0.034), (0.11, 0.036)],
                  loc=(0, -0.186, 0.79), rot=(90, 0, 0), segments=24, mat=["speaker", "brass"],
                  mats=[0, 0, 0, 1, 1, 1, 1])
    parts.append(C.tag(spk, "chest"))
    # Four rim bolts.
    for i, (bx, bz) in enumerate(((0.12, 0.12), (-0.12, 0.12), (0.12, -0.12), (-0.12, -0.12))):
        b = C.cyl(f"bolt{i}", 0.014, 0.014, 0.02, loc=(bx, -0.2, 0.79 + bz), rot=(90, 0, 0), verts=6, mat="brass")
        parts.append(C.tag(b, "chest"))
    # Collar: brass yoke around the head socket.
    collar = C.lathe("collar", [(0.13, 0.0), (0.17, 0.0), (0.17, 0.03), (0.15, 0.05), (0.12, 0.05)],
                     loc=(0, -0.01, 0.99), segments=20, mat="brass")
    parts.append(C.tag(collar, "chest"))
    # Rune grooves on both side panels.
    glyph = [[(-0.06, -0.08), (-0.06, 0.08), (0.02, 0.0), (0.07, 0.09)], [(0.0, -0.09), (0.07, -0.02)]]
    for x, rz in ((0.297, 90), (-0.297, -90)):
        r = C.rune_groove(f"rune_side{x}", glyph, loc=(x, 0.0, 0.84), rot=(0, 0, rz), width=0.014)
        parts.append(C.tag(r, "chest"))
    # Tape-deck backpack: dark metal case, two exposed reels, a VU meter on top.
    pack = C.box("pack", (0.42, 0.14, 0.32), loc=(0, 0.25, 0.84), mat="metal")
    C.inset_faces(pack, lambda c, n: n.y > 0.9, thickness=0.02, depth=-0.012, mat="screen")
    C.bevel(pack, 0.02, 2)
    parts.append(C.tag(pack, "chest"))
    meter = C.box("vu", (0.18, 0.06, 0.06), loc=(0, 0.22, 1.02), mat="metal_light", taper=(1.0, 0.7))
    C.inset_faces(meter, lambda c, n: n.y > 0.5, thickness=0.008, depth=-0.006, mat="meter_glow")
    C.bevel(meter, 0.008, 1)
    parts.append(C.tag(meter, "chest"))
    for s, x in (("L", 0.105), ("R", -0.105)):
        parts += reel(s, x)
    # Tape path: the strand runs off the top of one pack, over a brass playback head between the
    # reels, onto the other (a wide flat ribbon, so it never thins to a shimmering line).
    run = C.box("tape_run", (0.21, 0.026, 0.01), loc=(0, 0.318, 0.921), mat="tape")
    parts.append(C.tag(run, "chest"))
    phead = C.box("play_head", (0.05, 0.04, 0.035), loc=(0, 0.318, 0.94), mat="brass", taper=(0.7, 1.0))
    C.bevel(phead, 0.006, 1)
    parts.append(C.tag(phead, "chest"))
    return parts


def reel(side, x):
    """An exposed tape reel facing backward (+Y): brass flange, wound tape, six-spoke hub."""
    y, z = 0.32, 0.85
    out = []
    fl = C.cyl(f"flange.{side}", 0.085, 0.085, 0.012, loc=(x, y + 0.012, z), rot=(90, 0, 0), verts=24, mat="brass")
    tape = C.cyl(f"tape.{side}", 0.066, 0.066, 0.03, loc=(x, y - 0.005, z), rot=(90, 0, 0), verts=24, mat="tape")
    hub = C.cyl(f"hub.{side}", 0.026, 0.026, 0.05, loc=(x, y + 0.01, z), rot=(90, 0, 0), verts=6, mat="metal_light")
    out += [fl, tape, hub]
    for i in range(3):
        sp = C.box(f"spoke.{side}{i}", (0.11, 0.012, 0.014), loc=(x, y + 0.02, z), rot=(0, i * 60, 0), mat="metal_light")
        out.append(sp)
    return [C.tag(o, f"reel.{side}") for o in out]


def head():
    parts = []
    # Tape-head helmet: a chamfered block narrowing upward with a vertical head-gap slot on top.
    h = C.box("head", (0.29, 0.28, 0.2), loc=(0, -0.02, 1.1), mat="ceramic", taper=(0.82, 0.8))
    C.inset_faces(h, lambda c, n: n.z > 0.9, thickness=0.05, depth=-0.03, mat="metal")
    C.bevel(h, 0.03, 2)
    parts.append(C.tag(h, "head"))
    # Brow visor over the eye socket (brass), with side cheek guards.
    brow = C.extrude_poly("brow", [(-0.15, 0.0), (0.15, 0.0), (0.12, 0.035), (-0.12, 0.035)], 0.07,
                          loc=(0, -0.15, 1.15), rot=(-15, 0, 0), mat="brass")
    C.bevel(brow, 0.008, 1)
    parts.append(C.tag(brow, "head"))
    # Eye socket (dark metal) and the single lens on its own bone.
    sock = C.cyl("socket", 0.068, 0.075, 0.05, loc=(0, -0.155, 1.095), rot=(90, 0, 0), verts=20, mat="metal")
    C.bevel(sock, 0.006, 1)
    parts.append(C.tag(sock, "head"))
    lens = C.lathe("lens", [(0.0, 0.035), (0.03, 0.03), (0.048, 0.015), (0.05, 0.0)],
                   loc=(0, -0.175, 1.095), rot=(90, 0, 0), segments=20, mat="eye_glow")
    parts.append(C.tag(lens, "eye"))
    # Tape guides: two capstan posts on the crown, the tape-head read from far away.
    for x in (0.075, -0.075):
        g = C.cyl(f"guide{x}", 0.021, 0.021, 0.1, loc=(x, 0.0, 1.24), verts=10, mat="metal_light")
        gc = C.cyl(f"guidecap{x}", 0.036, 0.036, 0.02, loc=(x, 0.0, 1.29), verts=12, mat="brass")
        parts += [C.tag(g, "head"), C.tag(gc, "head")]
    return parts


def hips():
    parts = []
    pel = C.box("pelvis", (0.36, 0.26, 0.14), loc=(0, 0.01, 0.53), mat="metal", taper=(1.1, 1.0))
    C.bevel(pel, 0.02, 1)
    parts.append(C.tag(pel, "hips"))
    # Ceramic tassets front/back and the hip joint housings.
    f = C.box("tasset_f", (0.24, 0.035, 0.16), loc=(0, -0.15, 0.49), rot=(-12, 0, 0), mat="ceramic_dark", taper=(1.15, 1.0))
    b = C.box("tasset_b", (0.28, 0.035, 0.14), loc=(0, 0.15, 0.5), rot=(12, 0, 0), mat="ceramic_dark")
    for o in (f, b):
        C.bevel(o, 0.01, 1)
        parts.append(C.tag(o, "hips"))
    for x in (0.14, -0.14):
        j = C.cyl(f"hipjoint{x}", 0.07, 0.07, 0.07, loc=(x, 0.0, HIP_Z), rot=(0, 90, 0), verts=12, mat="metal_light")
        C.bevel(j, 0.01, 1)
        parts.append(C.tag(j, "hips"))
    return parts


def bellows(name, a, b, r, folds, soft):
    """Rubber accordion boot between two joints (a soft, blended part)."""
    import mathutils
    va, vb = mathutils.Vector(a), mathutils.Vector(b)
    length = (vb - va).length
    prof = []
    for i in range(folds * 2 + 1):
        z = length * i / (folds * 2)
        prof.append((r * (1.0 if i % 2 == 0 else 0.78), z))
    o = C.lathe(name, prof, segments=14, mat="cable")
    d = (vb - va).normalized()
    q = mathutils.Vector((0, 0, 1)).rotation_difference(d)
    o.data.transform(mathutils.Matrix.Translation(va) @ q.to_matrix().to_4x4())
    return C.tag(o, soft=soft)


def arm(s, x):
    parts = []
    a = ARM[s]
    # Pauldron: a heavy ceramic shoulder cap with a brass trim band and a chip knocked out.
    p = C.box(f"pauldron.{s}", (0.2, 0.3, 0.16), loc=(0.39 * x, 0, 0.98), rot=(0, 18 * x, 0), mat="ceramic", taper=(0.75, 0.85))
    C.bevel(p, 0.04, 2)
    if s == "L":
        C.chip(p, loc=(0.47, -0.15, 1.04), size=(0.08, 0.08, 0.08), rot=(40, 10, 30))
    trim = C.box(f"ptrim.{s}", (0.215, 0.31, 0.03), loc=(0.395 * x, 0, 0.905), rot=(0, 18 * x, 0), mat="brass")
    C.bevel(trim, 0.006, 1)
    parts += [C.tag(p, f"upper_arm.{s}"), C.tag(trim, f"upper_arm.{s}")]
    ua = C.cyl(f"uarm.{s}", 0.05, 0.045, 0.2, verts=12, mat="metal_light")
    C.along(ua, a["sh"], a["el"], 0.55)
    parts.append(C.tag(ua, f"upper_arm.{s}"))
    el, wr = a["el"], a["wr"]
    elbow_in = tuple(el[i] + (wr[i] - el[i]) * 0.25 for i in range(3))
    above = (el[0], el[1], el[2] + 0.06)
    parts.append(bellows(f"elbow.{s}", above, elbow_in, 0.055, 2, [f"upper_arm.{s}", f"forearm.{s}"]))
    # Forearm bracer: tapered ceramic block, narrow at the elbow, widening to the clamp.
    fa = C.box(f"bracer.{s}", (0.15, 0.16, 0.2), mat="ceramic", taper=(0.78, 0.78))
    C.inset_faces(fa, lambda c, n: abs(n.x) > 0.8, thickness=0.02, depth=-0.008, mat="ceramic_dark")
    C.place(fa, rot=(180, 0, 0))
    C.along(fa, wr, el, 0.42)
    C.bevel(fa, 0.025, 2)
    parts.append(C.tag(fa, f"forearm.{s}"))
    band = C.box(f"wband.{s}", (0.16, 0.17, 0.03), mat="brass")
    C.along(band, el, wr, 0.92)
    C.bevel(band, 0.006, 1)
    parts.append(C.tag(band, f"forearm.{s}"))
    # Clamp hand: a metal knuckle block with two heavy jaws (machine, not a human hand).
    end = a["end"]
    kb = C.box(f"knuckle.{s}", (0.12, 0.13, 0.09), mat="metal")
    C.along(kb, wr, end, 0.55)
    C.bevel(kb, 0.015, 1)
    parts.append(C.tag(kb, f"hand.{s}"))
    for j, jx in enumerate((0.05, -0.05)):
        jaw = C.box(f"jaw.{s}{j}", (0.035, 0.1, 0.11), mat="ceramic_dark", taper=(0.7, 0.8))
        C.along(jaw, (end[0] + jx, end[1] + (wr[1] - end[1]) * 0.2, end[2] + (wr[2] - end[2]) * 0.2),
                (end[0] + jx, 2 * end[1] - wr[1], 2 * end[2] - wr[2]), 0.3)
        C.bevel(jaw, 0.01, 1)
        parts.append(C.tag(jaw, f"hand.{s}"))
    return parts


def mallet():
    """Capstan mallet held upright in the right clamp: handle up, ceramic drum head across the
    swing plane (along Y), hazard-banded end caps, charge ring on its own bone."""
    parts = []
    x, y = GRIP[0], GRIP[1]
    hz = HEAD_C[2]
    handle = C.cyl("handle", 0.024, 0.024, 0.5, loc=(x, y, (0.46 + hz) / 2), verts=10, mat="metal_light")
    parts.append(C.tag(handle, "hand.R"))
    pom = C.cyl("pommel", 0.03, 0.04, 0.05, loc=(x, y, 0.47), verts=10, mat="brass")
    parts.append(C.tag(pom, "hand.R"))
    grip = C.tube("grip_wrap", [(x, y, 0.66), (x, y, 0.72), (x, y, 0.78)], 0.031, mat="cable", smooth=False)
    parts.append(C.tag(grip, "hand.R"))
    # Head: a ceramic drum lying along Y (the swing plane), brass-banded, hazard caps.
    hd = C.lathe("mallet_head", [(0.0, -0.14), (0.07, -0.14), (0.088, -0.125), (0.088, 0.125),
                                 (0.07, 0.14), (0.0, 0.14)], segments=20, mat="ceramic")
    C.place(hd, loc=HEAD_C, rot=(90, 0, 0))
    C.bevel(hd, 0.008, 1)
    parts.append(C.tag(hd, "hand.R"))
    for yc in (-0.125, 0.125):
        cap = C.cyl(f"mcap{yc}", 0.091, 0.091, 0.055, loc=(x, y + yc, hz), rot=(90, 0, 0), verts=20, mat="hazard")
        C.hazard_bands(cap, direction=(0, 0.5, 1), period=0.03)
        parts.append(C.tag(cap, "hand.R"))
    collar = C.cyl("mcollar", 0.05, 0.04, 0.05, loc=(x, y, hz - 0.1), verts=12, mat="brass")
    parts.append(C.tag(collar, "hand.R"))
    # Charge ring (its own bone): swells during the telegraph.
    ring = C.torus("charge_ring", 0.097, 0.013, loc=HEAD_C, rot=(90, 0, 0), seg=24, ring=6, mat="charge_glow")
    parts.append(C.tag(ring, "charge"))
    # Rune groove across the drum side.
    r = C.rune_groove("mallet_rune", [[(-0.05, 0.0), (0.05, 0.0)], [(-0.02, 0.03), (0.0, 0.0), (0.02, 0.03)]],
                      loc=(x - 0.09, y, hz), rot=(0, 0, -90), width=0.01)
    parts.append(C.tag(r, "hand.R"))
    # Patch cable from the backpack into the mallet pommel (soft: follows chest and arm).
    cab = C.tube("patch", [(-0.2, 0.26, 0.76), (-0.33, 0.3, 0.62), (-0.46, 0.12, 0.5), (-0.42, -0.12, 0.42),
                           (x, y, 0.45)], 0.016, mat="cable", segments=3)
    parts.append(C.tag(cab, soft=["chest", "upper_arm.R", "forearm.R", "hand.R"]))
    return parts


def leg(s, x):
    parts = []
    th = C.cyl(f"thigh.{s}", 0.065, 0.055, 0.19, loc=(0.145 * x, -0.01, 0.40), verts=12, mat="metal_light")
    parts.append(C.tag(th, f"thigh.{s}"))
    plate = C.box(f"thighplate.{s}", (0.05, 0.15, 0.17), loc=(0.2 * x, -0.01, 0.41), mat="ceramic_dark")
    C.bevel(plate, 0.012, 1)
    parts.append(C.tag(plate, f"thigh.{s}"))
    parts.append(bellows(f"knee.{s}", (0.147 * x, -0.015, 0.33), (0.15 * x, -0.01, 0.25), 0.062, 2,
                         [f"thigh.{s}", f"shin.{s}"]))
    cap = C.box(f"kneecap.{s}", (0.13, 0.07, 0.12), loc=(0.15 * x, -0.085, 0.29), rot=(10, 0, 0), mat="ceramic", taper=(0.8, 0.8))
    C.bevel(cap, 0.025, 2)
    parts.append(C.tag(cap, f"shin.{s}"))
    gr = C.box(f"greave.{s}", (0.15, 0.17, 0.17), loc=(0.15 * x, 0.0, 0.17), mat="ceramic", taper=(0.85, 0.85))
    C.inset_faces(gr, lambda c, n: n.y < -0.9, thickness=0.025, depth=-0.01, mat="ceramic_dark")
    C.bevel(gr, 0.025, 2)
    parts.append(C.tag(gr, f"shin.{s}"))
    ank = C.cyl(f"ankle.{s}", 0.045, 0.045, 0.1, loc=(0.15 * x, 0.01, 0.085), rot=(0, 90, 0), verts=10, mat="metal")
    parts.append(C.tag(ank, f"foot.{s}"))
    # Foot: a heavy wedge, long toe forward (reads the facing), split toe groove.
    ft = C.box(f"foot.{s}", (0.18, 0.3, 0.085), loc=(0.15 * x, -0.04, 0.0425), mat="ceramic_dark", taper=(0.85, 0.7))
    C.inset_faces(ft, lambda c, n: n.y < -0.9, thickness=0.012, depth=-0.01, mat="metal")
    C.bevel(ft, 0.02, 2)
    parts.append(C.tag(ft, f"foot.{s}"))
    toe = C.box(f"toecap.{s}", (0.17, 0.05, 0.05), loc=(0.15 * x, -0.19, 0.03), mat="brass")
    C.bevel(toe, 0.012, 1)
    parts.append(C.tag(toe, f"foot.{s}"))
    return parts


def build_model(rig):
    parts = torso() + head() + hips() + mallet()
    for s, x in (("L", 1), ("R", -1)):
        parts += arm(s, x) + leg(s, x)
    return C.bind(rig, parts, "Body")


# ------------------------------------------------------------------------------------------
# Animation (rotations in armature axes, degrees; see common.py for the sign convention)
# ------------------------------------------------------------------------------------------

def actions(rig):
    acts = {}
    # idle: 2 s. Breathing bob, a slow head scan, reels turning, the mallet weighed in the hand.
    a = C.Anim(rig, "idle", 2.0, loop=True)
    a.key(0, {"hips": K(loc=(0, 0, 0)), "chest": K(rx=1), "head": K(rz=0), "upper_arm.R": K(rx=-4),
              "forearm.R": K(rx=-2), "hand.R": K(rx=-3), "upper_arm.L": K(ry=3), "forearm.L": K(rx=0)})
    a.key(12, {"head": K(rz=18, rx=3)})
    a.key(18, {"head": K(rz=20, rx=3)})          # the scan dwells at each end: it is looking
    a.key(30, {"hips": K(loc=(0, 0, -0.024)), "chest": K(rx=5), "upper_arm.R": K(rx=-12), "forearm.R": K(rx=-12),
               "hand.R": K(rx=10), "upper_arm.L": K(ry=7), "forearm.L": K(rx=-8)})
    a.key(42, {"head": K(rz=-18, rx=3)})
    a.key(48, {"head": K(rz=-20, rx=3)})
    a.spin("reel.L", "Y", 1, step=5)
    a.spin("reel.R", "Y", 1, step=5)
    acts["idle"] = a.build()

    # move: 0.8 s, two heavy steps. Mallet arm swings less (it carries the weight).
    a = C.Anim(rig, "move", 0.8, loop=True)
    for f, lead in ((0, "L"), (12, "R")):
        other = "R" if lead == "L" else "L"
        a.key(f, {
            f"thigh.{lead}": K(-26), f"shin.{lead}": K(10), f"foot.{lead}": K(16),
            f"thigh.{other}": K(20), f"shin.{other}": K(18), f"foot.{other}": K(-30),
            "hips": K(rz=7 if lead == "L" else -7, loc=(0, 0, -0.025)),
            "chest": K(rx=6, rz=-8 if lead == "L" else 8),
            "upper_arm.L": K(20 if lead == "L" else -24),
            "upper_arm.R": K(-14 if lead == "L" else -4), "forearm.R": K(-10),
            "head": K(rz=6 if lead == "L" else -6),
        })
    for f, lead in ((6, "L"), (18, "R")):
        other = "R" if lead == "L" else "L"
        a.key(f, {
            f"thigh.{lead}": K(4), f"shin.{lead}": K(4), f"foot.{lead}": K(-8),
            f"thigh.{other}": K(-18), f"shin.{other}": K(52), f"foot.{other}": K(-22),
            "hips": K(rz=0, loc=(0, 0, 0.012)),
            "chest": K(rx=8, rz=0),
            "upper_arm.L": K(0), "upper_arm.R": K(-9), "forearm.R": K(-12),
            "head": K(rz=0),
        })
    a.spin("reel.L", "Y", 1, step=3)
    a.spin("reel.R", "Y", 1, step=3)
    acts["move"] = a.build()

    # telegraph: 1 s wind-up. Plant wide, lean back and twist right, mallet hauled overhead,
    # charge ring swelling and trembling at the top. Scrubbed by the game: every frame reads.
    wind = {
        "hips": K(rz=-10, loc=(0, 0.02, -0.03)),
        "chest": K(rx=-14, rz=-22, ry=-6),
        "head": K(rx=10, rz=18),
        # Mallet hauled straight up and cocked back over the right shoulder: the hazard head ends
        # well above the helmet, clear of the body from every camera side.
        "upper_arm.R": K(rx=-150, ry=-12), "forearm.R": K(rx=-20), "hand.R": K(rx=135),
        "upper_arm.L": K(rx=-50, ry=20), "forearm.L": K(rx=-30),
        "thigh.L": K(rx=-22, ry=8), "shin.L": K(30), "foot.L": K(-8),
        "thigh.R": K(rx=14, ry=-8), "shin.R": K(26), "foot.R": K(-40),
    }
    a = C.Anim(rig, "telegraph", 1.0, loop=False)
    a.key(0, {"charge": K(s=1.0)})
    a.key(8, {"upper_arm.R": K(rx=-62, ry=-8), "forearm.R": K(rx=-12), "hand.R": K(rx=48), "chest": K(rx=-4, rz=-10),
              "hips": K(loc=(0, 0.01, -0.03)), "charge": K(s=1.2)})
    a.key(20, dict(wind, charge=K(s=1.6)))
    a.key(24, {"charge": K(s=1.45), "chest": K(rx=-15, rz=-23, ry=-6)})
    a.key(27, {"charge": K(s=1.75)})
    a.key(30, dict(wind, chest=K(rx=-16, rz=-24, ry=-6), charge=K(s=1.8)))
    acts["telegraph"] = a.build()

    # attack: 1 s. Slam lands by frame 4 (13 %), held so the hit reads, recovery after.
    slam = {
        "hips": K(rz=8, loc=(0, -0.05, -0.068)),
        "chest": K(rx=34, rz=14),
        "head": K(rx=-14, rz=-6),
        "upper_arm.R": K(rx=-45, ry=-6), "forearm.R": K(rx=20), "hand.R": K(rx=95),
        "upper_arm.L": K(rx=30, ry=24), "forearm.L": K(rx=-20),
        "thigh.L": K(rx=-40, ry=6), "shin.L": K(52), "foot.L": K(-12),
        "thigh.R": K(rx=26, ry=-6), "shin.R": K(30), "foot.R": K(-52),
    }
    a = C.Anim(rig, "attack", 1.0, loop=False)
    a.key(0, dict(wind, chest=K(rx=-16, rz=-24, ry=-6), charge=K(s=1.8)))
    a.key(2, {"upper_arm.R": K(rx=-95, ry=-10), "forearm.R": K(rx=5), "hand.R": K(rx=110), "chest": K(rx=6, rz=-4), "charge": K(s=2.2)})
    a.key(4, dict(slam, charge=K(s=2.3)))
    a.key(6, {"chest": K(rx=31, rz=12), "hips": K(rz=8, loc=(0, -0.05, -0.062)), "charge": K(s=1.2)})
    a.key(12, dict(slam, chest=K(rx=30, rz=12), charge=K(s=0.9)))
    a.key(22, {"chest": K(rx=6, rz=2), "upper_arm.R": K(rx=-20), "forearm.R": K(rx=-8), "hand.R": K(rx=4),
               "hips": K(loc=(0, -0.01, -0.02)), "head": K(rx=-2), "charge": K(s=1.0),
               "thigh.L": K(-8), "shin.L": K(10), "foot.L": K(-2), "thigh.R": K(6), "shin.R": K(8), "foot.R": K(-14),
               "upper_arm.L": K(rx=6, ry=6), "forearm.L": K(rx=-6)})
    a.key(30, {b: K() for b in ("hips", "chest", "head", "upper_arm.R", "forearm.R", "hand.R", "upper_arm.L",
                                "forearm.L", "thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R", "charge")})
    acts["attack"] = a.build()

    # stagger: 1 s. Knocked back off balance, arms thrown out, eye flickers, wobbles back upright.
    a = C.Anim(rig, "stagger", 1.0, loop=False)
    a.key(0, {"eye": K(s=1.0)})
    a.key(3, {"hips": K(rx=-6, loc=(0, 0.09, -0.005)), "chest": K(rx=-26, ry=8), "head": K(rx=-22, rz=10),
              "upper_arm.L": K(rx=-40, ry=50), "upper_arm.R": K(rx=-50, ry=-45), "forearm.L": K(-30),
              "forearm.R": K(-20), "thigh.L": K(-24), "shin.L": K(20), "foot.L": K(10),
              "thigh.R": K(10), "shin.R": K(4), "foot.R": K(-12), "eye": K(s=0.45)})
    a.key(6, {"eye": K(s=1.1)})
    a.key(9, {"eye": K(s=0.5)})
    a.key(11, {"hips": K(rx=-2, loc=(0, 0.11, -0.04)), "chest": K(rx=-10, ry=-6), "head": K(rx=-6, rz=-8),
               "upper_arm.L": K(rx=-14, ry=24), "upper_arm.R": K(rx=-20, ry=-20), "eye": K(s=1.0)})
    a.key(18, {"hips": K(loc=(0, 0.1, -0.03)), "chest": K(rx=9, ry=3), "head": K(rx=6, rz=4),
               "upper_arm.L": K(rx=6, ry=8), "upper_arm.R": K(rx=-4, ry=-6)})
    a.key(24, {"chest": K(rx=-3), "head": K(rx=-2), "hips": K(loc=(0, 0.1, -0.01))})
    a.key(30, {"hips": K(loc=(0, 0.1, 0)), "chest": K(), "head": K(), "upper_arm.L": K(), "upper_arm.R": K(),
               "forearm.L": K(), "forearm.R": K(), "thigh.L": K(), "shin.L": K(), "foot.L": K(),
               "thigh.R": K(), "shin.R": K(), "foot.R": K(), "eye": K(s=1.0)})
    acts["stagger"] = a.build()

    # death: 1 s. Power cut: the eye irises shut, knees buckle, it slumps forward onto its knees,
    # the helmet pops off and rolls to the floor, a reel flies off the backpack, the mallet drops.
    a = C.Anim(rig, "death", 1.0, loop=False)
    slump_hips = (0, 0, -0.22)
    chest_rx = 58
    a.key(0, {"eye": K(s=1.0), "chest": K(), "head": K(), "reel.L": K(), "hips": K()})
    a.key(4, {"eye": K(s=1.35), "chest": K(rx=-12), "head": K(rx=-10), "hips": K(loc=(0, 0.02, 0.0)),
              "upper_arm.L": K(ry=20), "upper_arm.R": K(ry=-20)})
    a.key(10, {"eye": K(s=0.4), "head": K(rx=-25, loc=(0, 0, 0.08)),
               "reel.L": K(ry=200, loc=(0.06, 0.12, 0.06))})
    a.key(14, {"hips": K(loc=(0, -0.02, -0.12)), "chest": K(rx=20), "thigh.L": K(-40), "thigh.R": K(-35),
               "shin.L": K(70), "shin.R": K(64), "foot.L": K(-20), "foot.R": K(-20), "eye": K(s=0.15)})
    a.key(20, {"eye": K(s=0.05)})
    # Kneeling slump: thighs near vertical, shins flat back along the floor, chest folded forward.
    final = {
        "hips": K(rx=-6, loc=slump_hips),
        "chest": K(rx=chest_rx, rz=6),
        "thigh.L": K(rx=-8, ry=6), "shin.L": K(rx=92), "foot.L": K(rx=-84),
        "thigh.R": K(rx=-4, ry=-6), "shin.R": K(rx=90), "foot.R": K(rx=-86),
        "upper_arm.L": K(rx=-28, ry=24), "forearm.L": K(rx=-10),
        "upper_arm.R": K(rx=-48, ry=-18), "forearm.R": K(rx=-6), "hand.R": K(rx=105, rz=30),
        "head": K(rx=-95, rz=60, loc=C.parent_local((chest_rx - 6, 0, 0), (0.16, -0.22, -0.47))),
        "reel.L": K(ry=520, rx=80, loc=C.parent_local((chest_rx - 6, 0, 0), (0.24, 0.32, -0.62))),
        "eye": K(s=0.02),
    }
    a.key(22, dict(final, chest=K(rx=chest_rx + 6, rz=6), hips=K(rx=-6, loc=(0, 0, -0.24))))
    a.key(26, {"chest": K(rx=chest_rx - 3, rz=6)})
    a.key(30, final)
    acts["death"] = a.build()
    return acts


def build():
    rig = C.make_rig(BONES)
    body = build_model(rig)
    acts = actions(rig)
    C.clear_pose(rig)
    return rig, [body], acts


if __name__ == "__main__":
    C.run("grunt", build)
