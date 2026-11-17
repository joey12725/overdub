"""Stalker: the fast, lean hunter (assets/models/enemies/stalker.glb).

Reads as: a forward-pitched digitigrade machine (~1.4 tall to the tail tip) with a segmented
ceramic carapace, brass tape-head vanes down its back, a long wedge head carrying ONE orange eye,
two long scythe-blade forelimbs held low in front, and a cable tail that arcs up behind it with a
tape-head stinger. It runs across the room after the FARTHEST self and lunges along a line
(telegraph = coils low, blades cocked high, tail raised with its charge glow swelling;
attack = a long low lunge with both blades slashing forward).

Run:  blender --background --python art/enemies/stalker.py -- [--no-export] [--no-stills] [--no-sheets]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import common as C  # noqa: E402
from common import K  # noqa: E402
from mathutils import Vector  # noqa: E402

# ------------------------------------------------------------------------------------------
# Skeleton (Blender axes: Z up, front -Y, the stalker's right side is -X)
# ------------------------------------------------------------------------------------------
HIP = (0, 0.10, 0.66)
SPINE = (0, -0.07, 0.73)
CHEST = (0, -0.27, 0.78)
NECK = (0, -0.40, 0.80)
HEAD = (0, -0.50, 0.84)
HEAD_TIP = (0, -0.72, 0.83)
HD = (0, HEAD[1] + 0.44, HEAD[2] - 1.03)   # head-group offset from the layout the head was drawn at


def hp(p):
    """Head-group point: drawn relative to a head at (0, -0.44, 1.03), moved to HEAD."""
    return (p[0] + HD[0], p[1] + HD[1], p[2] + HD[2])

TAIL = [(0, 0.13, 0.67), (0, 0.30, 0.72), (0, 0.44, 0.86), (0, 0.50, 1.04), (0, 0.48, 1.22)]

LEG = {  # left side; the right mirrors in X
    "hip": (0.12, 0.08, 0.66), "knee": (0.15, -0.08, 0.44), "hock": (0.15, 0.12, 0.2),
    "ankle": (0.15, 0.07, 0.045), "toe": (0.15, -0.1, 0.02),
}
ARM = {"sh": (0.14, -0.33, 0.78), "el": (0.19, -0.45, 0.58), "tip": (0.2, -0.85, 0.42)}


def mx(p, x):
    return (p[0] * x, p[1], p[2])


BONES = [
    ("root", (0, 0, 0), (0, 0, 0.2), None),
    ("hips", HIP, SPINE, "root"),
    ("spine", SPINE, CHEST, "hips"),
    ("chest", CHEST, NECK, "spine"),
    ("neck", NECK, HEAD, "chest"),
    ("head", HEAD, HEAD_TIP, "neck"),
    ("eye", hp((0, -0.6, 1.065)), hp((0, -0.7, 1.065)), "head"),
]
for i in range(4):
    BONES.append((f"tail.{i + 1:03d}", TAIL[i], TAIL[i + 1], "hips" if i == 0 else f"tail.{i:03d}"))
BONES.append(("charge", (0, 0.475, 1.27), (0, 0.475, 1.35), "tail.004"))
for s, x in (("L", 1), ("R", -1)):
    BONES += [
        (f"upper_arm.{s}", mx(ARM["sh"], x), mx(ARM["el"], x), "chest"),
        (f"blade.{s}", mx(ARM["el"], x), mx(ARM["tip"], x), f"upper_arm.{s}"),
        (f"thigh.{s}", mx(LEG["hip"], x), mx(LEG["knee"], x), "hips"),
        (f"shin.{s}", mx(LEG["knee"], x), mx(LEG["hock"], x), f"thigh.{s}"),
        (f"foot.{s}", mx(LEG["hock"], x), mx(LEG["ankle"], x), f"shin.{s}"),
        (f"toe.{s}", mx(LEG["ankle"], x), mx(LEG["toe"], x), f"foot.{s}"),
    ]


# ------------------------------------------------------------------------------------------
# Model
# ------------------------------------------------------------------------------------------

def shell(name, a, b, size, bone, lift=0.03, taper=(0.8, 0.85), mat="ceramic"):
    """A carapace segment along a->b whose top (local +Y after alignment) faces up/back."""
    o = C.box(name, size, mat=mat, taper=taper)
    C.inset_faces(o, lambda c, n: n.y > 0.9, thickness=0.025, depth=-0.01, mat="ceramic_dark")
    C.along(o, a, b)
    C.place(o, loc=(0, 0, lift))
    C.bevel(o, 0.022, 2)
    return C.tag(o, bone)


def body():
    parts = []
    parts.append(shell("shell_hip", (0, 0.16, 0.67), (0, -0.03, 0.72), (0.22, 0.17, 0.2), "hips"))
    parts.append(shell("shell_mid", (0, 0.0, 0.72), (0, -0.22, 0.76), (0.25, 0.19, 0.25), "spine"))
    parts.append(shell("shell_chest", (0, -0.21, 0.76), (0, -0.42, 0.8), (0.27, 0.21, 0.23), "chest", taper=(0.75, 0.8)))
    # Under-frame: a dark inscribed metal spine hose that bends with the body (soft).
    hose = C.tube("spine_hose", [(0, 0.14, 0.64), (0, 0.0, 0.68), (0, -0.18, 0.71), (0, -0.36, 0.74), (0, -0.48, 0.8)],
                  0.055, mat="metal", segments=3)
    parts.append(C.tag(hose, soft=["hips", "spine", "chest", "neck"]))
    # Brass tape-head vanes down the back, swept back like hackles.
    fin = [(0.0, 0.0), (0.12, 0.0), (0.2, 0.14), (0.15, 0.15), (0.04, 0.05)]
    for name, (y, z), bone, sc, tilt in (("vane1", (0.04, 0.8), "hips", 0.75, -14),
                                         ("vane2", (-0.13, 0.85), "spine", 1.0, -12),
                                         ("vane3", (-0.32, 0.88), "chest", 0.9, -10)):
        v = C.extrude_poly(name, [(py * sc, pz * sc) for py, pz in fin], 0.018, plane="YZ", mat="brass")
        C.place(v, loc=(0, y, z), rot=(tilt, 0, 0))
        C.bevel(v, 0.004, 1)
        parts.append(C.tag(v, bone))
    # Rune grooves along both carapace flanks.
    glyph = [[(-0.08, 0.0), (-0.02, 0.03), (0.04, -0.02), (0.09, 0.02)], [(0.0, -0.03), (0.0, 0.04)]]
    for x, rz in ((0.128, 90), (-0.128, -90)):
        r = C.rune_groove(f"rune{x}", glyph, loc=(x, -0.12, 0.76), rot=(-8, 0, rz), width=0.01)
        parts.append(C.tag(r, "spine"))
    # Hip drums.
    for x in (0.12, -0.12):
        d = C.cyl(f"hipdrum{x}", 0.06, 0.06, 0.06, loc=(x, 0.08, 0.66), rot=(0, 90, 0), verts=14, mat="metal_light")
        C.bevel(d, 0.008, 1)
        parts.append(C.tag(d, "hips"))
    # Tape reels bolted to the outside of each haunch (the retrofit layer: brass flange, wound
    # pack, hex hub), rigid on the hips so the thighs swing under them.
    for x in (1, -1):
        pk = C.cyl(f"hreel_tape{x}", 0.06, 0.06, 0.026, loc=(0.172 * x, 0.08, 0.66), rot=(0, 90, 0), verts=24, mat="tape")
        fl = C.cyl(f"hreel_flange{x}", 0.074, 0.074, 0.012, loc=(0.19 * x, 0.08, 0.66), rot=(0, 90, 0), verts=24, mat="brass")
        hb = C.cyl(f"hreel_hub{x}", 0.024, 0.024, 0.02, loc=(0.2 * x, 0.08, 0.66), rot=(0, 90, 0), verts=6, mat="metal_light")
        parts += [C.tag(pk, "hips"), C.tag(fl, "hips"), C.tag(hb, "hips")]
    # Shoulder yoke.
    yoke = C.box("yoke", (0.32, 0.1, 0.07), loc=(0, -0.34, 0.75), rot=(-10, 0, 0), mat="metal")
    C.bevel(yoke, 0.015, 1)
    parts.append(C.tag(yoke, "chest"))
    return parts


def head():
    parts = []
    # Long wedge head, side profile extruded across X then pinched toward the snout.
    prof = [(0.06, 0.07), (0.02, 0.09), (-0.14, 0.05), (-0.23, 0.0), (-0.2, -0.04), (-0.12, -0.06), (0.05, -0.05)]
    h = C.extrude_poly("head", prof, 0.17, plane="YZ", mat="ceramic")
    for v in h.data.vertices:
        t = max(0.0, min(1.0, (0.06 - v.co.y) / 0.29))
        v.co.x *= 1.0 - 0.55 * t
    C.place(h, loc=HEAD)
    C.bevel(h, 0.015, 2, limit_deg=30)
    parts.append(C.tag(h, "head"))
    # Dark metal brow plate and socket, the single eye on its bone.
    brow = C.box("brow", (0.12, 0.12, 0.025), loc=hp((0, -0.55, 1.105)), rot=(-16, 0, 0), mat="metal", taper=(0.7, 1.0))
    C.bevel(brow, 0.008, 1)
    parts.append(C.tag(brow, "head"))
    sock = C.cyl("socket", 0.048, 0.054, 0.03, loc=hp((0, -0.6, 1.065)), rot=(70, 0, 0), verts=16, mat="metal")
    parts.append(C.tag(sock, "head"))
    lens = C.lathe("lens", [(0.0, 0.03), (0.024, 0.026), (0.037, 0.012), (0.039, 0.0)], segments=16, mat="eye_glow")
    C.place(lens, loc=hp((0, -0.61, 1.07)), rot=(70, 0, 0))
    parts.append(C.tag(lens, "eye"))
    # Brass tape-guide cheeks and two swept antenna pins (read as the tape head).
    for x in (1, -1):
        ch = C.box(f"cheek{x}", (0.02, 0.14, 0.07), loc=hp((0.07 * x, -0.47, 1.03)), rot=(0, 0, 8 * x), mat="brass", taper=(1.0, 0.7))
        C.bevel(ch, 0.005, 1)
        pin = C.cyl(f"pin{x}", 0.017, 0.011, 0.2, verts=10, mat="metal_light")   # thick enough not to shimmer
        C.along(pin, hp((0.05 * x, -0.44, 1.1)), hp((0.09 * x, -0.28, 1.2)), 0.5)
        parts += [C.tag(ch, "head"), C.tag(pin, "head")]
    neck = C.cyl("neck", 0.04, 0.045, 0.14, verts=12, mat="metal_light")
    C.along(neck, NECK, HEAD, 0.5)
    parts.append(C.tag(neck, "neck"))
    return parts


def blade_arm(s, x):
    parts = []
    sh, el, tip = mx(ARM["sh"], x), mx(ARM["el"], x), mx(ARM["tip"], x)
    pad = C.box(f"shoulder.{s}", (0.1, 0.13, 0.1), loc=(sh[0] + 0.02 * x, sh[1], sh[2] + 0.01), mat="ceramic", taper=(0.7, 0.8))
    C.bevel(pad, 0.02, 2)
    parts.append(C.tag(pad, f"upper_arm.{s}"))
    ua = C.cyl(f"uarm.{s}", 0.04, 0.032, 0.24, verts=10, mat="metal_light")
    C.along(ua, sh, el, 0.5)
    parts.append(C.tag(ua, f"upper_arm.{s}"))
    # Elbow housing: a pivot drum with a brass clamp the blade is bolted into.
    hub = C.cyl(f"pivot.{s}", 0.045, 0.045, 0.07, loc=el, rot=(0, 90, 0), verts=14, mat="metal")
    C.bevel(hub, 0.008, 1)
    parts.append(C.tag(hub, f"blade.{s}"))
    clamp = C.box(f"clamp.{s}", (0.05, 0.12, 0.07), mat="brass")
    C.along(clamp, el, tip, 0.0)
    C.place(clamp, loc=(Vector(tip) - Vector(el)).normalized() * 0.06)
    C.bevel(clamp, 0.008, 1)
    parts.append(C.tag(clamp, f"blade.{s}"))
    # The scythe: a thin curved blade (side profile), tip hooking down; local u runs along the bone.
    L = (Vector(tip) - Vector(el)).length
    prof_u = [(0.04, 0.03), (0.25, 0.05), (0.42, 0.045), (L + 0.06, -0.03), (L + 0.07, -0.12),
              (L - 0.02, -0.05), (0.3, -0.02), (0.04, -0.025)]
    bl = C.extrude_poly(f"blade.{s}", [(-u, v) for u, v in prof_u], 0.016, plane="YZ", mat="blade")
    # Thin the cutting edge: pinch the lower outline toward the centre plane.
    for vtx in bl.data.vertices:
        if vtx.co.z < -0.01:
            vtx.co.x *= 0.35
    ang = math.degrees(math.atan2(-(tip[2] - el[2]), -(tip[1] - el[1])))
    C.place(bl, loc=el, rot=(ang, 0, 0))
    C.bevel(bl, 0.003, 1)
    parts.append(C.tag(bl, f"blade.{s}"))
    # Hazard-banded back spine along the blade (the part that hurts).
    spine = C.box(f"bspine.{s}", (0.03, 0.32, 0.03), mat="hazard")
    C.place(spine, loc=(0, -0.24, 0.05))
    C.place(spine, loc=el, rot=(ang, 0, 0))
    C.hazard_bands(spine, direction=(0, 1, 0.8), period=0.035)
    parts.append(C.tag(spine, f"blade.{s}"))
    return parts


def leg(s, x):
    parts = []
    p = {k: mx(v, x) for k, v in LEG.items()}
    th = C.box(f"thigh.{s}", (0.1, 0.13, 0.26), mat="ceramic", taper=(0.75, 0.7))
    C.along(th, p["hip"], p["knee"], 0.45)
    C.inset_faces(th, lambda c, n: abs(n.x) > 0.9, thickness=0.02, depth=-0.008, mat="ceramic_dark")
    C.bevel(th, 0.02, 2)
    parts.append(C.tag(th, f"thigh.{s}"))
    kn = C.cyl(f"knee.{s}", 0.04, 0.04, 0.08, loc=p["knee"], rot=(0, 90, 0), verts=12, mat="metal")
    parts.append(C.tag(kn, f"shin.{s}"))
    sh = C.cyl(f"shinrod.{s}", 0.038, 0.03, 0.3, verts=10, mat="metal_light")
    C.along(sh, p["knee"], p["hock"], 0.5)
    parts.append(C.tag(sh, f"shin.{s}"))
    guard = C.box(f"shinguard.{s}", (0.075, 0.035, 0.22), mat="ceramic_dark", taper=(0.6, 1.0))
    C.along(guard, p["knee"], p["hock"], 0.45)
    C.place(guard, loc=(0, -0.03, -0.02))
    C.bevel(guard, 0.008, 1)
    parts.append(C.tag(guard, f"shin.{s}"))
    hk = C.cyl(f"hock.{s}", 0.035, 0.035, 0.07, loc=p["hock"], rot=(0, 90, 0), verts=12, mat="brass")
    parts.append(C.tag(hk, f"foot.{s}"))
    mt = C.cyl(f"meta.{s}", 0.032, 0.026, 0.17, verts=10, mat="metal_light")
    C.along(mt, p["hock"], p["ankle"], 0.5)
    parts.append(C.tag(mt, f"foot.{s}"))
    # Three claw toes splayed forward (blade-like, ceramic dark).
    for j, dx in enumerate((-0.035, 0.0, 0.035)):
        claw = C.extrude_poly(f"claw.{s}{j}", [(0.03, 0.0), (0.0, 0.035), (-0.13, 0.008), (-0.15, -0.0)], 0.022,
                              plane="YZ", mat="ceramic_dark")
        C.place(claw, loc=(p["ankle"][0] + dx, p["ankle"][1] + 0.02, 0.0), rot=(0, 0, -dx * 300))
        C.bevel(claw, 0.004, 1)
        parts.append(C.tag(claw, f"toe.{s}"))
    heel = C.box(f"heel.{s}", (0.06, 0.07, 0.05), loc=(p["ankle"][0], p["ankle"][1] + 0.03, 0.04), mat="metal")
    parts.append(C.tag(heel, f"toe.{s}"))
    return parts


def tail():
    parts = []
    t = C.tube("tail", TAIL + [(0, 0.475, 1.27)], 0.034, mat="cable", segments=4,
               radii=[1.0, 0.9, 0.8, 0.7, 0.6, 0.55])
    bones = ["hips"] + [f"tail.{i:03d}" for i in range(1, 5)]
    parts.append(C.tag(t, soft=bones))
    # Ceramic vertebra rings, one rigid per tail bone.
    for i in range(4):
        a, b = Vector(TAIL[i]), Vector(TAIL[i + 1])
        r = C.cyl(f"vert{i}", 0.05 - i * 0.006, 0.045 - i * 0.006, 0.05, verts=12, mat="ceramic_dark")
        C.along(r, a, b, 0.5)
        C.bevel(r, 0.008, 1)
        parts.append(C.tag(r, f"tail.{i + 1:03d}"))
    # Stinger: a tape-head block with brass guides and the charge glow tip on its own bone.
    head = C.box("stinger", (0.06, 0.05, 0.08), loc=(0, 0.475, 1.24), mat="metal")
    C.bevel(head, 0.01, 1)
    parts.append(C.tag(head, "tail.004"))
    for x in (0.04, -0.04):
        g = C.cyl(f"sguide{x}", 0.014, 0.014, 0.1, loc=(x, 0.475, 1.27), verts=8, mat="brass")
        parts.append(C.tag(g, "tail.004"))
    tip = C.lathe("charge_tip", [(0.0, 0.0), (0.032, 0.035), (0.0, 0.1)], segments=6, mat="charge_glow")
    C.place(tip, loc=(0, 0.475, 1.27))
    parts.append(C.tag(tip, "charge"))
    return parts


def build_model(rig):
    parts = body() + head() + tail()
    for s, x in (("L", 1), ("R", -1)):
        parts += blade_arm(s, x) + leg(s, x)
    return C.bind(rig, parts, "Body")


# ------------------------------------------------------------------------------------------
# Animation
# ------------------------------------------------------------------------------------------
LEGS = ("thigh", "shin", "foot", "toe")


def actions(rig):
    acts = {}
    # idle: 2 s. Low, twitchy: breathing, sharp head ticks, tail sway, blades flexing.
    a = C.Anim(rig, "idle", 2.0, loop=True)
    a.key(0, {"hips": K(loc=(0, 0, 0)), "chest": K(rx=0), "head": K(), "neck": K(),
              "tail.001": K(), "tail.002": K(), "tail.003": K(), "tail.004": K(),
              "blade.L": K(), "blade.R": K()})
    a.key(12, {"neck": K(rz=-18, rx=4), "head": K(rz=-6)})
    a.key(16, {"neck": K(rz=-20, rx=4)})
    a.key(30, {"hips": K(loc=(0, 0, -0.015)), "chest": K(rx=4), "tail.001": K(rz=10), "tail.002": K(rz=10),
               "tail.003": K(rz=12, rx=-6), "tail.004": K(rz=10), "blade.L": K(rx=-8), "blade.R": K(rx=-6)})
    a.key(36, {"neck": K(rz=16, rx=-2), "head": K(rz=8)})
    a.key(40, {"neck": K(rz=18, rx=-2)})
    a.key(48, {"neck": K(rz=0, rx=0), "head": K(rz=0), "tail.003": K(rz=-8), "tail.004": K(rz=-10)})
    acts["idle"] = a.build()

    # move: 0.6 s sprint, two strides, body low and pitched further forward, blades swept back,
    # tail streaming out behind.
    a = C.Anim(rig, "move", 0.6, loop=True)
    tail_stream = {"tail.001": K(rx=-26), "tail.002": K(rx=-14), "tail.003": K(rx=-8), "tail.004": K(rx=-4)}
    for f, lead in ((0, "L"), (9, "R")):
        o = "R" if lead == "L" else "L"
        a.key(f, dict(tail_stream, **{
            f"thigh.{lead}": K(-38), f"shin.{lead}": K(-6), f"foot.{lead}": K(28), f"toe.{lead}": K(10),
            f"thigh.{o}": K(34), f"shin.{o}": K(-10), f"foot.{o}": K(-10), f"toe.{o}": K(-30),
            "hips": K(rx=10, rz=8 if lead == "L" else -8, loc=(0, 0, -0.022)),
            "spine": K(rx=6), "chest": K(rx=4, rz=-6 if lead == "L" else 6),
            "neck": K(rx=-14), "head": K(rx=-4),
            "upper_arm.L": K(rx=30 if lead == "L" else 22), "upper_arm.R": K(rx=22 if lead == "L" else 30),
            "blade.L": K(rx=-30), "blade.R": K(rx=-30),
        }))
    for f, lead in ((4, "L"), (13, "R")):
        o = "R" if lead == "L" else "L"
        a.key(f, {
            f"thigh.{lead}": K(4), f"shin.{lead}": K(4), f"foot.{lead}": K(-6), f"toe.{lead}": K(0),
            f"thigh.{o}": K(-30), f"shin.{o}": K(-50), f"foot.{o}": K(60), f"toe.{o}": K(20),
            "hips": K(rx=10, loc=(0, 0, 0.03)),
            "tail.001": K(rx=-20), "tail.002": K(rx=-18), "tail.003": K(rx=-12), "tail.004": K(rx=-10),
        })
    acts["move"] = a.build()

    # telegraph: 1 s. Coils low, rears the blades high and back, raises the tail; the stinger's
    # charge glow swells and quivers. Ends in the cocked pose the lunge starts from.
    coil = {
        # Mantis threat: haunches sink, the chest rears, and both scythes are cocked high and forward
        # in an open V beyond the head (never crossing the body), so from any side the wind-up is
        # one big silhouette change.
        "hips": K(rx=4, loc=(0, 0.06, -0.12)),
        "spine": K(rx=-4), "chest": K(rx=-12),
        "neck": K(rx=18), "head": K(rx=6),
        "upper_arm.L": K(rx=-62, ry=14), "upper_arm.R": K(rx=-62, ry=-14),
        "blade.L": K(rx=-12), "blade.R": K(rx=-12),
        "thigh.L": K(-44, ry=4), "shin.L": K(34), "foot.L": K(26), "toe.L": K(-24),
        "thigh.R": K(-44, ry=-4), "shin.R": K(34), "foot.R": K(26), "toe.R": K(-24),
        "tail.001": K(rx=18), "tail.002": K(rx=22), "tail.003": K(rx=24), "tail.004": K(rx=30),
    }
    a = C.Anim(rig, "telegraph", 1.0, loop=False)
    a.key(0, {"charge": K(s=1.0)})
    a.key(10, {"hips": K(rx=2, loc=(0, 0.03, -0.06)), "upper_arm.L": K(rx=-28, ry=8), "upper_arm.R": K(rx=-28, ry=-8),
               "blade.L": K(rx=-22), "blade.R": K(rx=-22), "neck": K(rx=8), "charge": K(s=1.4),
               "tail.001": K(rx=8), "tail.002": K(rx=10), "tail.003": K(rx=10), "tail.004": K(rx=12)})
    a.key(22, dict(coil, charge=K(s=2.2)))
    a.key(25, {"charge": K(s=1.9), "tail.004": K(rx=30, rz=10)})
    a.key(28, {"charge": K(s=2.5), "tail.004": K(rx=30, rz=-10)})
    a.key(30, dict(coil, hips=K(rx=4, loc=(0, 0.07, -0.13)), charge=K(s=2.4)))
    acts["telegraph"] = a.build()

    # attack: 1 s. The lunge: body stretches long and low, blades scythe down and forward together
    # by frame 5, hold the reach, then recover upright.
    reach = {
        "hips": K(rx=14, loc=(0, -0.16, -0.08)),
        "spine": K(rx=10), "chest": K(rx=12),
        "neck": K(rx=-24), "head": K(rx=-6),
        "upper_arm.L": K(rx=-52, ry=10, rz=-10), "upper_arm.R": K(rx=-52, ry=-10, rz=10),
        "blade.L": K(rx=16), "blade.R": K(rx=16),
        "thigh.L": K(-54), "shin.L": K(8), "foot.L": K(68), "toe.L": K(-36),
        "thigh.R": K(50), "shin.R": K(-38), "foot.R": K(-2), "toe.R": K(-24),
        "tail.001": K(rx=-40), "tail.002": K(rx=-12), "tail.003": K(rx=-6), "tail.004": K(rx=-4),
    }
    a = C.Anim(rig, "attack", 1.0, loop=False)
    a.key(0, dict(coil, hips=K(rx=4, loc=(0, 0.07, -0.13)), charge=K(s=2.4)))
    a.key(3, {"upper_arm.L": K(rx=-70, ry=12), "upper_arm.R": K(rx=-70, ry=-12), "blade.L": K(rx=-14), "blade.R": K(rx=-14),
              "hips": K(rx=12, loc=(0, -0.06, -0.08)), "charge": K(s=1.4)})
    a.key(5, dict(reach, charge=K(s=0.9)))
    a.key(8, {"blade.L": K(rx=22), "blade.R": K(rx=22), "upper_arm.L": K(rx=-48, ry=10, rz=-10),
              "upper_arm.R": K(rx=-48, ry=-10, rz=10)})
    a.key(14, dict(reach, charge=K(s=1.0)))
    a.key(24, {"hips": K(rx=4, loc=(0, -0.03, -0.02)), "spine": K(rx=2), "chest": K(rx=2), "neck": K(rx=-6),
               "head": K(), "upper_arm.L": K(rx=-8), "upper_arm.R": K(rx=-8), "blade.L": K(rx=8), "blade.R": K(rx=8),
               "thigh.L": K(-12), "shin.L": K(-2), "foot.L": K(12), "toe.L": K(2),
               "thigh.R": K(8), "shin.R": K(-2), "foot.R": K(-2), "toe.R": K(-6),
               "tail.001": K(rx=-8), "tail.002": K(rx=-3), "tail.003": K(), "tail.004": K()})
    a.key(30, {b: K() for b in ("hips", "spine", "chest", "neck", "head", "upper_arm.L", "upper_arm.R",
                                "blade.L", "blade.R", "thigh.L", "shin.L", "foot.L", "toe.L", "thigh.R",
                                "shin.R", "foot.R", "toe.R", "tail.001", "tail.002", "tail.003",
                                "tail.004", "charge")})
    acts["attack"] = a.build()

    # stagger: 1 s. Jolted back and up onto its hocks, blades flung wide, head whipped, eye
    # flickering; skitters back to its crouch.
    a = C.Anim(rig, "stagger", 1.0, loop=False)
    a.key(0, {"eye": K(s=1.0)})
    a.key(3, {"hips": K(rx=-16, loc=(0, 0.1, 0.0)), "spine": K(rx=-10), "chest": K(rx=-12, ry=10),
              "neck": K(rx=-30, rz=20), "head": K(rx=-14),
              "upper_arm.L": K(rx=-60, ry=40), "upper_arm.R": K(rx=-50, ry=-50),
              "blade.L": K(rx=-40), "blade.R": K(rx=-20),
              "thigh.L": K(-10), "shin.L": K(10), "foot.L": K(10),
              "thigh.R": K(14), "shin.R": K(4), "foot.R": K(-14),
              "tail.001": K(rx=-20, rz=20), "tail.002": K(rx=-20, rz=20), "tail.003": K(rz=20), "eye": K(s=0.4)})
    a.key(6, {"eye": K(s=1.1)})
    a.key(9, {"eye": K(s=0.5)})
    a.key(12, {"hips": K(rx=-4, loc=(0, 0.14, -0.02)), "chest": K(rx=-2, ry=-6), "neck": K(rx=-8, rz=-14),
               "upper_arm.L": K(rx=-16, ry=12), "upper_arm.R": K(rx=-14, ry=-12),
               "tail.001": K(rz=-12), "tail.002": K(rz=-12), "tail.003": K(rz=-10), "eye": K(s=1.0)})
    a.key(20, {"hips": K(rx=3, loc=(0, 0.13, -0.03)), "chest": K(rx=4, ry=2), "neck": K(rx=6, rz=4)})
    a.key(30, {b: K() for b in ("chest", "spine", "neck", "head", "upper_arm.L", "upper_arm.R", "blade.L",
                                "blade.R", "thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R",
                                "tail.001", "tail.002", "tail.003")})
    a.key(30, {"hips": K(loc=(0, 0.13, 0)), "eye": K(s=1.0)})
    acts["stagger"] = a.build()

    # death: 1 s. Spasm, legs give out, it crashes onto its side, blades splay limp, the tail
    # coils down and the eye shutters closed.
    a = C.Anim(rig, "death", 1.0, loop=False)
    a.key(0, {"eye": K(s=1.0), "hips": K()})
    a.key(4, {"hips": K(rx=-12, loc=(0, 0.04, 0.04)), "neck": K(rx=-34), "chest": K(rx=-10),
              "upper_arm.L": K(rx=-70, ry=30), "upper_arm.R": K(rx=-70, ry=-30), "eye": K(s=1.4),
              "tail.002": K(rx=-30), "tail.003": K(rx=-30)})
    a.key(10, {"eye": K(s=0.5), "hips": K(rx=-6, ry=25, loc=(0.03, 0.02, -0.08))})
    a.key(16, {"eye": K(s=0.15)})
    final = {
        "hips": K(rx=6, ry=76, loc=(0.1, 0.0, -0.475)),
        "spine": K(rx=8, rz=-6), "chest": K(rx=12, rz=-10),
        "neck": K(rx=30, rz=-14), "head": K(rx=10, rz=-10),
        "upper_arm.L": K(rx=-30, ry=55), "upper_arm.R": K(rx=-50, ry=30),
        "blade.L": K(rx=-25), "blade.R": K(rx=-60),
        "thigh.L": K(-60, ry=25), "shin.L": K(60), "foot.L": K(-10), "toe.L": K(30),
        "thigh.R": K(-30), "shin.R": K(30), "foot.R": K(20), "toe.R": K(30),
        "tail.001": K(rx=50, ry=-10), "tail.002": K(rx=40, ry=-15), "tail.003": K(rx=30, ry=-15),
        "tail.004": K(rx=20, ry=-10),
        "eye": K(s=0.02),
    }
    a.key(20, dict(final, hips=K(rx=6, ry=84, loc=(0.11, 0.0, -0.485))))
    a.key(24, {"hips": K(rx=6, ry=72, loc=(0.1, 0.0, -0.465))})
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
    C.run("stalker", build)
