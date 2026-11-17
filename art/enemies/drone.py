"""Drone: the hovering reel craft (assets/models/enemies/drone.glb).

Reads as: a squat ceramic lens-shaped hull (~0.6 across with its rotors) floating about 1.2 up,
crowned by a big spinning tape reel with three windows, girdled by a counter-rotating ducted
propeller ring, ONE orange eye on the hull's front, and a tape-head emitter horn slung underneath
on a gimbal. The game yaws/pitches the emitter through the `aim` bone (never keyed here). It keeps
its distance and fires on the off-beat (telegraph = rotors spin up, the hull rears back, the
emitter cocks and its charge glow swells in the horn mouth; attack = recoil kick and bolt).

Run:  blender --background --python art/enemies/drone.py -- [--no-export] [--no-stills] [--no-sheets]
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import common as C  # noqa: E402
from common import K  # noqa: E402

HZ = 1.2            # hull centre height
AIM = (0, 0, 1.06)  # gimbal pivot under the hull
MUZZLE_Y = -0.27

BONES = [
    ("root", (0, 0, 0), (0, 0, 0.2), None),
    ("body", (0, 0, HZ - 0.1), (0, 0, HZ + 0.12), "root"),
    ("eye", (0, -0.17, HZ + 0.035), (0, -0.27, HZ + 0.035), "body"),
    ("reel", (0, 0, HZ + 0.12), (0, 0, HZ + 0.22), "body"),
    ("prop", (0, 0, HZ - 0.07), (0, 0, HZ + 0.01), "body"),
    # Game-driven: rest straight up (identity in Godot), yaw about its local Y, pitch about X.
    ("aim", AIM, (AIM[0], AIM[1], AIM[2] + 0.1), "body"),
    ("emitter", (0, 0, 0.96), (0, 0, 1.04), "aim"),
    ("charge", (0, MUZZLE_Y + 0.025, 0.95), (0, MUZZLE_Y + 0.025, 1.03), "emitter"),
]


def hull():
    parts = []
    z = HZ
    h = C.lathe("hull", [(0.0, z - 0.1), (0.1, z - 0.095), (0.16, z - 0.055), (0.18, z + 0.0), (0.17, z + 0.05),
                         (0.12, z + 0.1), (0.0, z + 0.11)], segments=16, mat="ceramic")
    # Recessed side panels on the upper shell, like the family's inset seams.
    C.inset_faces(h, lambda c, n: c.z > z + 0.005 and abs(n.z) < 0.6, thickness=0.012, depth=-0.008,
                  mat="ceramic_dark")
    C.bevel(h, 0.006, 1, limit_deg=35)
    parts.append(C.tag(h, "body"))
    eq = C.torus("equator", 0.182, 0.018, loc=(0, 0, z), seg=32, ring=6, mat="brass")
    parts.append(C.tag(eq, "body"))
    # Eye: dark socket with a hood, the single lens on its bone.
    sock = C.cyl("socket", 0.068, 0.074, 0.06, loc=(0, -0.16, z + 0.035), rot=(90, 0, 0), verts=18, mat="metal")
    C.bevel(sock, 0.006, 1)
    parts.append(C.tag(sock, "body"))
    hood = C.extrude_poly("hood", [(-0.09, 0.0), (0.09, 0.0), (0.07, 0.03), (-0.07, 0.03)], 0.07, mat="brass")
    C.place(hood, loc=(0, -0.17, z + 0.095), rot=(-20, 0, 0))
    parts.append(C.tag(hood, "body"))
    lens = C.lathe("lens", [(0.0, 0.036), (0.032, 0.031), (0.05, 0.014), (0.053, 0.0)], segments=18, mat="eye_glow")
    C.place(lens, loc=(0, -0.185, z + 0.035), rot=(90, 0, 0))
    parts.append(C.tag(lens, "eye"))
    # Rune grooves on the flanks and a VU strip on the back.
    for x, rz in ((0.16, 90), (-0.16, -90)):
        r = C.rune_groove(f"rune{x}", [[(-0.04, -0.02), (0.0, 0.025), (0.04, -0.02)], [(0.0, 0.025), (0.0, -0.03)]],
                          loc=(x, 0.0, z + 0.035), rot=(0, 0, rz), width=0.009)
        parts.append(C.tag(r, "body"))
    vu = C.box("vu", (0.1, 0.03, 0.035), loc=(0, 0.16, z + 0.035), rot=(-20, 0, 0), mat="metal_light")
    C.inset_faces(vu, lambda c, n: n.y > 0.5, thickness=0.006, depth=-0.005, mat="meter_glow")
    parts.append(C.tag(vu, "body"))
    # Spindle that carries the reel, and the strut arms that carry the propeller duct.
    sp = C.cyl("spindle", 0.03, 0.03, 0.08, loc=(0, 0, z + 0.13), verts=10, mat="metal_light")
    parts.append(C.tag(sp, "body"))
    for i in range(3):
        a = math.radians(90 + i * 120)
        st = C.box(f"strut{i}", (0.16, 0.038, 0.03), loc=(0.25 * math.cos(a), 0.25 * math.sin(a), z - 0.05),
                   rot=(0, 0, math.degrees(a)), mat="metal")
        parts.append(C.tag(st, "body"))
    duct = C.lathe("duct", [(0.27, z - 0.085), (0.3, z - 0.08), (0.305, z - 0.02), (0.28, z - 0.015),
                            (0.27, z - 0.085)], segments=36, mat="metal")
    parts.append(C.tag(duct, "body"))
    lip = C.torus("duct_lip", 0.29, 0.012, loc=(0, 0, z - 0.018), seg=36, ring=6, mat="brass")
    parts.append(C.tag(lip, "body"))
    # Prow: a brass wedge on the front of the duct, so the facing reads from above even when the
    # reel hides the hull (the game camera looks down at 35 degrees).
    prow = C.extrude_poly("prow", [(-0.085, 0.0), (0.085, 0.0), (0.03, -0.085), (-0.03, -0.085)], 0.05, plane="XY",
                          mat="brass")
    C.place(prow, loc=(0, -0.285, z - 0.05))
    C.bevel(prow, 0.01, 2)
    parts.append(C.tag(prow, "body"))
    # Hazard-banded keel under the hull where the emitter yoke hangs.
    keel = C.box("keel", (0.07, 0.16, 0.05), loc=(0, -0.02, z - 0.1), mat="hazard")
    C.hazard_bands(keel, direction=(0, 1, 0.6), period=0.03)
    C.bevel(keel, 0.008, 1)
    parts.append(C.tag(keel, "body"))
    return parts


def reel():
    """The crowning tape reel: a brass flange with three windows over a wound tape pack, 6-spoke hub."""
    parts = []
    z = HZ + 0.18
    fl = C.cyl("flange", 0.24, 0.24, 0.014, loc=(0, 0, z + 0.025), verts=40, mat="brass")
    for i in range(3):
        a = math.radians(30 + i * 120)
        w = C.cyl(f"window{i}", 0.07, 0.07, 0.1, loc=(0.145 * math.cos(a), 0.145 * math.sin(a), z + 0.025), verts=16)
        C.cut(fl, w)
    C.bevel(fl, 0.004, 1)
    parts.append(C.tag(fl, "reel"))
    low = C.cyl("flange_low", 0.24, 0.24, 0.012, loc=(0, 0, z - 0.03), verts=40, mat="metal")
    parts.append(C.tag(low, "reel"))
    tape = C.cyl("tape", 0.17, 0.17, 0.042, loc=(0, 0, z), verts=40, mat="tape")
    parts.append(C.tag(tape, "reel"))
    hub = C.cyl("hub", 0.05, 0.05, 0.07, loc=(0, 0, z + 0.01), verts=6, mat="metal_light")
    C.bevel(hub, 0.006, 1)
    parts.append(C.tag(hub, "reel"))
    cap = C.lathe("hubcap", [(0.0, z + 0.075), (0.035, z + 0.06), (0.04, z + 0.045), (0.0, z + 0.045)],
                  segments=12, mat="ceramic_dark")
    parts.append(C.tag(cap, "reel"))
    return parts


def prop():
    """Counter-rotating propeller inside the duct: six pitched blades on a ring hub."""
    parts = []
    z = HZ - 0.05
    ring = C.torus("prop_hub", 0.2, 0.012, loc=(0, 0, z), seg=28, ring=6, mat="metal")
    parts.append(C.tag(ring, "prop"))
    for i in range(6):
        a = i * 60.0
        b = C.box(f"blade{i}", (0.075, 0.045, 0.012), mat="metal_light", taper=(1.0, 1.0))
        C.place(b, rot=(30, 0, 0))
        C.place(b, loc=(0.235, 0, 0))
        C.place(b, loc=(0, 0, z), rot=(0, 0, a))
        parts.append(C.tag(b, "prop"))
    return parts


def emitter():
    parts = []
    # Gimbal yoke (aim bone): a fork from the keel down around the emitter's trunnion.
    ball = C.lathe("gimbal", [(0.0, 1.03), (0.04, 1.04), (0.05, 1.07), (0.035, 1.1), (0.0, 1.1)], segments=12,
                   mat="metal")
    parts.append(C.tag(ball, "aim"))
    for x in (0.055, -0.055):
        fork = C.box(f"fork{x}", (0.02, 0.05, 0.11), loc=(x, 0.0, 1.0), mat="metal_light")
        C.bevel(fork, 0.006, 1)
        parts.append(C.tag(fork, "aim"))
    # The emitter (recoils on its own bone): a tape-head block with a flared horn forward.
    body = C.box("emit_body", (0.085, 0.14, 0.08), loc=(0, 0.0, 0.96), mat="ceramic_dark")
    C.inset_faces(body, lambda c, n: abs(n.x) > 0.9, thickness=0.012, depth=-0.006, mat="metal")
    C.bevel(body, 0.012, 1)
    parts.append(C.tag(body, "emitter"))
    trun = C.cyl("trunnion", 0.022, 0.022, 0.13, loc=(0, 0.0, 0.98), rot=(0, 90, 0), verts=10, mat="brass")
    parts.append(C.tag(trun, "emitter"))
    horn = C.lathe("horn", [(0.025, 0.0), (0.03, 0.06), (0.042, 0.13), (0.07, 0.19), (0.075, 0.2),
                            (0.062, 0.2), (0.035, 0.13), (0.022, 0.06), (0.018, 0.0)], segments=18,
                   mat=["metal_light", "brass"], mats=[0, 0, 0, 1, 1, 1, 1, 1])
    C.place(horn, loc=(0, -0.07, 0.95), rot=(90, 0, 0))
    parts.append(C.tag(horn, "emitter"))
    band = C.cyl("horn_band", 0.04, 0.04, 0.03, loc=(0, -0.12, 0.95), rot=(90, 0, 0), verts=14, mat="hazard")
    C.hazard_bands(band, direction=(1, 0, 1), period=0.02)
    parts.append(C.tag(band, "emitter"))
    # Charge glow: sits just inside the horn mouth and swells out past the rim on the telegraph,
    # so it is seen from the game camera and not only down the barrel.
    glow = C.lathe("muzzle_glow", [(0.0, -0.01), (0.016, -0.006), (0.024, 0.0), (0.016, 0.01), (0.0, 0.016)],
                   segments=12, mat="charge_glow")
    C.place(glow, loc=(0, MUZZLE_Y + 0.025, 0.95), rot=(90, 0, 0))
    parts.append(C.tag(glow, "charge"))
    # Feed cable from the hull into the emitter's back (soft: follows body, aim and emitter).
    cab = C.tube("feed", [(0.0, 0.12, HZ - 0.08), (0.0, 0.14, 1.03), (0.0, 0.09, 0.96)], 0.012, mat="cable")
    parts.append(C.tag(cab, soft=["body", "aim", "emitter"]))
    return parts


# ------------------------------------------------------------------------------------------
# Animation
# ------------------------------------------------------------------------------------------

def spin_keys(a, bone, frames, angles, lift=None):
    """Linear keys about the armature Z axis at the given frames/angles (degrees). `lift(frame)`
    optionally returns a Z offset (the reel riding up its spindle as it winds up)."""
    for f, ang in zip(frames, angles):
        k = K(rz=ang, interp="LINEAR")
        if lift is not None:
            k["loc"] = (0.0, 0.0, lift(f))
        a.key(f, {bone: k})


def spin_ramp(a, bone, start_deg_per_frame, end_deg_per_frame, end_frame, step=2, stop_at=None, lift=None):
    """Spin with a linearly changing speed (spin-up / spin-down) from frame 0 to end_frame."""
    ang, f = 0.0, 0
    frames, angles = [0], [0.0]
    while f < end_frame:
        f2 = min(end_frame, f + step)
        for ff in range(f, f2):
            t = ff / max(1, end_frame)
            ang += start_deg_per_frame + (end_deg_per_frame - start_deg_per_frame) * t
        frames.append(f2)
        angles.append(ang)
        f = f2
    spin_keys(a, bone, frames, angles, lift)


def actions(rig):
    acts = {}
    a = C.Anim(rig, "idle", 2.0, loop=True)
    # idle: a lazy figure-of-eight hover; the emitter hunts a little on its trunnion.
    a.key(0, {"body": K(loc=(0, 0, 0)), "emitter": K()})
    a.key(15, {"body": K(rx=4, ry=-5, loc=(0.012, 0, 0.035)), "emitter": K(rx=-7)})
    a.key(30, {"body": K(loc=(0, 0, 0.0)), "emitter": K()})
    a.key(45, {"body": K(rx=-4, ry=5, loc=(-0.012, 0, -0.035)), "emitter": K(rx=6)})
    a.spin("reel", "Z", 3, step=2)
    a.spin("prop", "Z", -5, step=2)
    acts["idle"] = a.build()

    a = C.Anim(rig, "move", 1.0, loop=True)
    a.key(0, {"body": K(rx=14, loc=(0, 0, 0.0)), "emitter": K(rx=-6)})
    a.key(8, {"body": K(rx=16, ry=-4, loc=(0, 0, 0.025))})
    a.key(15, {"body": K(rx=14, loc=(0, 0, 0.0)), "emitter": K(rx=-10)})
    a.key(23, {"body": K(rx=16, ry=4, loc=(0, 0, -0.02))})
    a.spin("reel", "Z", 3, step=2)
    a.spin("prop", "Z", -5, step=2)
    acts["move"] = a.build()

    # telegraph: rears back, emitter cocks back on its slide, rotors spin up, the charge glow
    # swells in the horn mouth and quivers.
    a = C.Anim(rig, "telegraph", 1.0, loop=False)
    # The hull rears back hard and climbs, the reel rides up its spindle as it winds up, the emitter
    # cocks back and the charge swells out of the horn mouth.
    a.key(0, {"body": K(), "emitter": K(), "charge": K(s=1.0)})
    a.key(10, {"body": K(rx=-9, loc=(0, 0.03, 0.04)), "emitter": K(loc=(0, 0.02, 0)), "charge": K(s=1.8)})
    a.key(22, {"body": K(rx=-22, loc=(0, 0.07, 0.1)), "emitter": K(loc=(0, 0.05, 0.0)), "charge": K(s=3.3)})
    a.key(25, {"charge": K(s=2.9), "body": K(rx=-22, ry=3, loc=(0, 0.07, 0.1))})
    a.key(28, {"charge": K(s=3.7), "body": K(rx=-22, ry=-3, loc=(0, 0.07, 0.1))})
    a.key(30, {"body": K(rx=-23, loc=(0, 0.07, 0.1)), "emitter": K(loc=(0, 0.055, 0.0)), "charge": K(s=3.6)})
    spin_ramp(a, "reel", 18.0, 40.0, 30, lift=lambda f: 0.07 * min(1.0, f / 22.0))
    spin_ramp(a, "prop", -30.0, -60.0, 30)
    acts["telegraph"] = a.build()

    # attack: the bolt leaves on frame 2 — emitter slams forward then kicks back, the hull is
    # shoved back by the recoil, charge flashes and empties; settles by the end.
    a = C.Anim(rig, "attack", 1.0, loop=False)
    a.key(0, {"body": K(rx=-23, loc=(0, 0.07, 0.1)), "emitter": K(loc=(0, 0.055, 0.0)), "charge": K(s=3.6)})
    a.key(2, {"emitter": K(loc=(0, -0.04, 0.0)), "charge": K(s=4.0), "body": K(rx=6, loc=(0, 0.0, 0.05))})
    a.key(5, {"emitter": K(loc=(0, 0.07, 0.0)), "charge": K(s=0.4), "body": K(rx=-26, loc=(0, 0.12, 0.08))})
    a.key(9, {"emitter": K(loc=(0, 0.03, 0.0)), "body": K(rx=-14, loc=(0, 0.1, 0.05))})
    a.key(18, {"emitter": K(loc=(0, 0.0, 0.0)), "body": K(rx=4, loc=(0, 0.04, 0.01)), "charge": K(s=0.7)})
    a.key(30, {"emitter": K(), "body": K(), "charge": K(s=1.0)})
    spin_ramp(a, "reel", 40.0, 16.0, 30, lift=lambda f: 0.07 * max(0.0, 1.0 - f / 4.0))
    spin_ramp(a, "prop", -60.0, -28.0, 30)
    acts["attack"] = a.build()

    # stagger: knocked into a wobbling roll, drops altitude, eye flickers, recovers level.
    a = C.Anim(rig, "stagger", 1.0, loop=False)
    a.key(0, {"body": K(), "eye": K(s=1.0)})
    a.key(3, {"body": K(rx=-28, ry=34, loc=(0, 0.12, -0.08)), "eye": K(s=0.4)})
    a.key(6, {"eye": K(s=1.1)})
    a.key(9, {"body": K(rx=10, ry=-20, loc=(0, 0.16, -0.14)), "eye": K(s=0.5)})
    a.key(13, {"eye": K(s=1.0)})
    a.key(16, {"body": K(rx=-6, ry=10, loc=(0, 0.17, -0.1))})
    a.key(23, {"body": K(rx=3, ry=-3, loc=(0, 0.17, -0.04))})
    a.key(30, {"body": K(loc=(0, 0.17, 0.0))})
    spin_ramp(a, "reel", 6.0, 18.0, 30)
    spin_ramp(a, "prop", -8.0, -30.0, 30)
    acts["stagger"] = a.build()

    # death: power cut — rotors wind down, it lurches, drops and crashes nose-first onto the
    # floor, bounces, and the reel shears off its spindle and rolls flat beside the wreck.
    a = C.Anim(rig, "death", 1.0, loop=False)
    a.key(0, {"body": K(), "eye": K(s=1.0)})
    a.key(4, {"body": K(rx=-10, ry=14, loc=(0, 0.02, 0.06)), "eye": K(s=1.4)})
    a.key(9, {"eye": K(s=0.4)})
    a.key(15, {"body": K(rx=30, ry=-10, loc=(0, -0.08, -0.78)), "eye": K(s=0.15), "emitter": K()})
    a.key(18, {"body": K(rx=40, ry=-14, loc=(0, -0.1, -0.955)), "emitter": K(rx=-35, loc=(0, 0.03, 0.07))})
    a.key(22, {"body": K(rx=30, ry=-16, loc=(0, -0.11, -0.86))})
    a.key(26, {"body": K(rx=36, ry=-18, loc=(0, -0.12, -0.96)), "eye": K(s=0.02)})
    a.key(30, {"body": K(rx=34, ry=-18, loc=(0, -0.12, -0.95)), "eye": K(s=0.02),
               "emitter": K(rx=-35, loc=(0, 0.03, 0.07))})
    for f, ang in zip((0, 4, 8, 12), (0, 70, 130, 175)):
        a.key(f, {"reel": K(rz=ang, interp="LINEAR")})
    # Shear off at 16: thrown up and out, lands flat beside the hull.
    a.key(16, {"reel": K(rz=205, loc=(0, 0, 0))})
    a.key(21, {"reel": K(rz=280, rx=-40, loc=C.parent_local((36, -18, 0), (0.32, 0.06, 0.12)))})
    a.key(26, {"reel": K(rz=330, rx=-70, ry=10, loc=C.parent_local((34, -18, 0), (0.42, 0.12, -0.3)))})
    a.key(30, {"reel": K(rz=340, rx=-34, ry=18, loc=C.parent_local((34, -18, 0), (0.44, 0.14, -0.31)))})
    spin_ramp(a, "prop", -30.0, 0.0, 22, step=2)
    a.key(30, {"prop": K(rz=a.keys["prop"][22]["rot"][2])})
    acts["death"] = a.build()
    return acts


def build():
    rig = C.make_rig(BONES)
    body = C.bind(rig, hull() + reel() + prop() + emitter(), "Body")
    acts = actions(rig)
    C.clear_pose(rig)
    return rig, [body], acts


if __name__ == "__main__":
    C.run("drone", build)
