"""OVERDUB enemy: turret — a bolted-down ruin plinth carrying a retrofitted tape-deck gun head.

    blender --background --python art/enemies/turret.py -- [--out assets/models/enemies/turret.glb]
                                                           [--previews art/previews/enemies/turret]
                                                           [--no-anim-previews]

Reads as: a fixed emplacement (octagonal ceramic plinth, hazard collar, floor clamps) with a long
single barrel that points unmistakably where it will shoot. The head is a reel-to-reel deck: two
open reels on top wind up while it charges; the charge orb in the muzzle swells during the
telegraph and is spent by the shot. One eye: the hooded sensor above the barrel.

Rig "Rig": root, hatch (base service panel), aim (game-driven yaw, never keyed), turn (animated
scan/sway/lift under aim), head (pitch), barrel (recoil), charge (muzzle orb scale), coil.0..2 (the
three charge coils on the barrel, lit breech to muzzle by the telegraph), eye, reel.L / reel.R.
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common2 as C  # noqa: E402

PIVOT_Z = 0.66  # head trunnion height (before the final SCALE)
REEL_X = 0.086  # reel centres either side of the deck centre line
DEAD_PITCH = 11.0  # death: the head pitch at which the barrel sleeve comes to rest on the turntable rim
COILS = (0.205, 0.275, 0.345)  # charge coil positions along the barrel (from the breech)
SCALE = 1.2  # authored at 0.92 tall; shipped at ~1.1


def build_base(sk: C.Skin) -> None:
    seg16 = 11.25
    # Floor flange and tapered 16-sided plinth.
    flange = C.lathe("flange", [(0, 0), (0.41, 0), (0.41, 0.03), (0.385, 0.06), (0, 0.06)], "ceramic_dark", 16,
                     angle0=seg16)
    plinth = C.lathe("plinth", [(0, 0.05), (0.37, 0.05), (0.32, 0.38), (0.30, 0.41), (0, 0.41)], "ceramic", 16,
                     angle0=seg16)
    band = C.hazard_band("plinth_hazard", 0.376, 0.085, 0.185, stripes=16, r_top=0.362, angle0=seg16, polygon=16)
    # Panel seams: every other facet above the hazard collar is a separate inset ceramic slab.
    C.inset_faces(plinth, lambda c, n: abs(n.z) < 0.5 and c.z > 0.19 and
                  int(((math.degrees(math.atan2(c.y, c.x)) + 360.0) % 360.0) // 22.5) % 2 == 0, 0.014, -0.006, "ceramic_dark")
    rune_ring = C.ring("rune_ring", 0.334, 0.30, 0.016, "rune_glow", 16, loc=(0, 0, 0.335))
    rune_ring.rotation_euler.z = math.radians(seg16)
    # Bearing on top of the plinth.
    bearing = C.cyl("bearing", 0.29, 0.06, "metal", 32, z0=0.41, bevel=0.012)
    bearing_ring = C.torus("bearing_ring", 0.29, 0.016, "brass", 32, 8, loc=(0, 0, 0.468))
    # Lift column: hidden inside the turntable at rest, shown when the head rises to fire.
    column = C.cyl("lift_column", 0.15, 0.12, "metal_light", 24, z0=0.42)
    # Floor clamps at the diagonals, each with two bolts, plus small chips cut from the plinth rim.
    clamps = []
    for k, a in enumerate((45, 135, 225, 315)):
        ar = math.radians(a)
        c, s = math.cos(ar), math.sin(ar)
        cl = C.box(f"clamp{k}", (0.13, 0.09, 0.055), "brass", loc=(0.365 * c, 0.365 * s, 0.085), rot=(0, 0, a), bevel=0.012)
        clamps.append(cl)
        lip = C.box(f"clamp_lip{k}", (0.05, 0.1, 0.11), "brass", loc=(0.34 * c, 0.34 * s, 0.11), rot=(0, 0, a),
                    bevel=0.01, taper=(0.7, 1.0))
        clamps.append(lip)
        pts = [(0.395 * c - 0.03 * s, 0.395 * s + 0.03 * c, 0.112), (0.395 * c + 0.03 * s, 0.395 * s - 0.03 * c, 0.112)]
        clamps.append(C.bolts(f"clamp_bolts{k}", pts, (0, 0, 1), r=0.016, h=0.014, mat="metal_light"))
    # Rune glyphs on the two front-flank facets.
    gl = []
    for side in (-1, 1):
        a = math.radians(-90 + side * 45)
        n = (math.cos(a), math.sin(a), 0)
        rr = 0.3397 * math.cos(math.radians(11.25)) + 0.002
        o = (n[0] * rr, n[1] * rr, 0.25)
        u = (-n[1], n[0], 0)
        v = (-n[0] * 0.149, -n[1] * 0.149, 0.989)
        gl.append(C.glyphs(f"plinth_glyph{side}", [[(-0.035, -0.05), (-0.035, 0.05), (0.0, 0.02), (0.035, 0.05), (0.035, -0.05)],
                                                    [(-0.015, -0.03), (0.015, -0.03)]], o, u, v, 0.012, 0.01))
    for ob in [flange, plinth, band, rune_ring, bearing, bearing_ring, column, *clamps, *gl]:
        sk.rigid(ob, "root")

    # Service hatch on the front facet (falls open on death).
    hatch = C.box("hatch", (0.15, 0.022, 0.13), "ceramic_dark", loc=(0, -0.342, 0.252), rot=(-8.5, 0, 0), bevel=0.008)
    hb = C.bolts("hatch_bolts", [(x, -0.355 + 0.0, z) for x in (-0.06, 0.06) for z in (0.2, 0.3)], (0, -1, 0.15),
                 r=0.011, h=0.008, mat="brass")
    hg = C.glyphs("hatch_glyph", [[(0, -0.04), (0, 0.04)], [(-0.03, 0.04), (0, 0.01), (0.03, 0.04)], [(-0.025, -0.04), (0.025, -0.04)]],
                  (0, -0.353, 0.252), (1, 0, 0), (0, 0.149, 0.989), 0.011, 0.01)
    for ob in (hatch, hb, hg):
        sk.rigid(ob, "hatch")


def build_yoke(sk: C.Skin) -> None:
    table = C.cyl("turntable", 0.26, 0.055, "metal_light", 32, z0=0.47, bevel=0.012)
    parts = [table]
    for side in (-1, 1):
        cheek = C.prism(f"cheek{side}", [(-0.16, 0.50), (0.17, 0.50), (0.15, 0.62), (0.06, 0.77), (-0.06, 0.78), (-0.15, 0.66)],
                        0.05, "ceramic_dark", bevel=0.01)
        C.xf(cheek, (0, 0, 0), (0, 0, 90))
        C.place(cheek, (side * 0.205, 0, 0))
        parts.append(cheek)
        hz = C.hazard_panel(f"cheek_hazard{side}", (0.17, 0.008, 0.07), 0.035, rot=(0, 0, 90), frame=0.0)
        C.place(hz, (side * 0.232, -0.02, 0.585))
        parts.append(hz)
        hub = C.cyl(f"trunnion{side}", 0.062, 0.07, "brass", 20, rot=(0, 90, 0), bevel=0.01)
        C.place(hub, (side * 0.215, 0, PIVOT_Z))
        cap = C.cyl(f"trunnion_cap{side}", 0.035, 0.03, "metal_light", 6, rot=(0, 90, 0), bevel=0.006)
        C.place(cap, (side * 0.258, 0, PIVOT_Z))
        parts += [hub, cap]
    for p in parts:
        sk.rigid(p, "turn")


def build_head(sk: C.Skin) -> None:
    head = []
    housing = C.box("housing", (0.32, 0.44, 0.24), "ceramic", loc=(0, 0.03, 0.68), bevel=0.035, seg=2, taper=(0.92, 0.9))
    # A dark service seam and a rune channel along both flanks.
    C.inset_faces(housing, lambda c, n: abs(n.x) > 0.95 and abs(c.y - 0.03) < 0.16, 0.025, -0.01, "metal")
    head.append(housing)
    deck = C.box("deck", (0.27, 0.36, 0.02), "metal", loc=(0, 0.04, 0.80), bevel=0.006)
    head.append(deck)
    # Tape head block and guides at the front of the deck, with the tape threaded from both reels.
    thead = C.box("tape_head", (0.08, 0.035, 0.04), "metal_light", loc=(0, -0.085, 0.83), bevel=0.008)
    gap = C.box("tape_head_gap", (0.006, 0.006, 0.036), "charge_glow", loc=(0, -0.104, 0.83))
    guides = [C.cyl(f"guide{s}", 0.009, 0.05, "brass", 8, loc=(s * 0.07, -0.085, 0.835)) for s in (-1, 1)]
    tape = []
    for s in (-1, 1):
        for a, b in (((s * 0.158, 0.09), (s * 0.075, -0.08)), ((s * 0.075, -0.08), (s * 0.04, -0.105))):
            ax, ay = a
            bx, by = b
            ln = math.hypot(bx - ax, by - ay)
            ang = math.degrees(math.atan2(by - ay, bx - ax))
            tape.append(C.box(f"tape{s}{ax}", (ln + 0.006, 0.009, 0.024), "tape", loc=((ax + bx) / 2, (ay + by) / 2, 0.832), rot=(0, 0, ang)))
    tape.append(C.box("tape_front", (0.086, 0.009, 0.024), "tape", loc=(0, -0.106, 0.832)))
    head += [thead, gap, *guides, *tape]
    # Sensor pod: the single eye, hooded, above the barrel.
    pod = C.cyl("sensor_pod", 0.066, 0.12, "metal", 24, rot=(90, 0, 0), bevel=0.01)
    C.place(pod, (0, -0.15, 0.84))
    lens = C.lathe("lens", [(0, -0.01), (0.05, -0.01), (0.05, 0.004), (0.043, 0.016), (0.026, 0.026), (0, 0.03)], "eye_glow", 24,
                   rot=(90, 0, 0))
    C.place(lens, (0, -0.212, 0.84))
    bezel = C.ring("lens_bezel", 0.07, 0.048, 0.024, "brass", 24, rot=(90, 0, 0), bevel=0.006)
    C.place(bezel, (0, -0.212, 0.84))
    hood = C.prism("hood", [(-0.09, 0.0), (0.09, 0.0), (0.068, 0.036), (-0.068, 0.036)], 0.17, "ceramic_dark", bevel=0.008)
    C.place(hood, (0, -0.155, 0.905))
    head += [pod, bezel, hood]
    sk.rigid(lens, "eye")
    # Back counterweight: a speaker cabinet with its cone facing back, and a VU meter on the left flank.
    cab = C.box("speaker_cab", (0.28, 0.12, 0.2), "metal", loc=(0, 0.295, 0.675), bevel=0.02)
    cone = C.lathe("speaker_cone", [(0, -0.02), (0.085, -0.02), (0.085, 0.006), (0.075, 0.012), (0.03, -0.006),
                                    (0.018, 0.004), (0, 0.006)], ["brass", "speaker"], 24, rot=(-90, 0, 0),
                   band_mats=[1, 0, 0, 1, 1, 1])
    C.place(cone, (0, 0.357, 0.675))
    grille = [C.box(f"grille{i}", (0.18, 0.008, 0.008), "metal_light", loc=(0, 0.372, 0.675 + z)) for i, z in enumerate((-0.04, 0.0, 0.04))]
    head += [cab, cone, *grille]
    for s in (-1, 1):
        meter = C.box(f"vu{s}", (0.01, 0.12, 0.06), "meter_glow", loc=(s * 0.148, 0.10, 0.70), bevel=0.003)
        frame = C.box(f"vu_frame{s}", (0.012, 0.14, 0.08), "brass", loc=(s * 0.143, 0.10, 0.70), bevel=0.006)
        needle = C.box(f"vu_needle{s}", (0.006, 0.006, 0.05), "hazard_dark", loc=(s * 0.155, 0.095, 0.70), rot=(30, 0, 0))
        head += [meter, frame, needle]
    gl = C.glyphs("head_glyphs", [[(-0.12, 0.0), (-0.06, 0.0), (-0.03, 0.03), (0.03, -0.03), (0.06, 0.0), (0.12, 0.0)]],
                  (0, 0.03, 0.802), (0, 1, 0), (1, 0, 0), 0.01, 0.006)
    gl2 = C.glyphs("head_glyphs_front", [[(-0.11, -0.04), (-0.11, 0.04), (0.11, 0.04)], [(0.11, -0.04), (0.06, -0.04)]],
                   (0, -0.178, 0.68), (1, 0, 0), (0, 0, 1), 0.01, 0.008)
    # Cable from the turntable to the head (soft: blended between turn and head).
    cable = C.tube("head_cable", [(0.09, 0.2, 0.53), (0.12, 0.28, 0.56), (0.11, 0.33, 0.60), (0.08, 0.36, 0.64)], 0.018, "cable", 8)
    head += [gl, gl2]
    for p in head:
        sk.rigid(p, "head")
    sk.auto(cable, ["turn", "head"])

    # Reels lying flat on the deck.
    for side, bone in ((1, "reel.L"), (-1, "reel.R")):
        x = side * REEL_X
        base = C.lathe(f"reel_base{side}", [(0, 0), (0.082, 0), (0.082, 0.008), (0.06, 0.01), (0.06, 0.034),
                                             (0.024, 0.034), (0.024, 0.052), (0.016, 0.058), (0, 0.058)],
                       ["brass", "tape", "metal"], 28, band_mats=[0, 0, 0, 1, 1, 2, 2, 2], loc=(x, 0.10, 0.81))
        rim = C.ring(f"reel_rim{side}", 0.082, 0.064, 0.01, "brass", 28, loc=(x, 0.10, 0.849), bevel=0.003)
        spokes = [C.box(f"reel_spoke{side}{k}", (0.05, 0.022, 0.01), "brass",
                        loc=(x + 0.042 * math.cos(math.radians(a)), 0.10 + 0.042 * math.sin(math.radians(a)), 0.849),
                        rot=(0, 0, a)) for k, a in enumerate((90, 210, 330))]
        for p in (base, rim, *spokes):
            sk.rigid(p, bone)


def build_barrel(sk: C.Skin) -> None:
    # Profile along local Z (breech at 0, muzzle at 0.70); rotated to point -Y.
    prof = [(0, 0.0), (0.095, 0.0), (0.095, 0.12), (0.112, 0.125), (0.112, 0.15), (0.086, 0.155),
            (0.086, 0.19), (0.078, 0.195), (0.078, 0.215), (0.086, 0.22),
            (0.086, 0.26), (0.078, 0.265), (0.078, 0.285), (0.086, 0.29),
            (0.086, 0.33), (0.078, 0.335), (0.078, 0.355), (0.086, 0.36),
            (0.086, 0.42), (0.058, 0.45), (0.056, 0.60), (0.078, 0.605), (0.078, 0.70),
            (0.042, 0.70), (0.042, 0.64), (0, 0.64)]
    # materials: 0 metal, 1 brass, 2 metal_light. The grooves between the sleeves seat the charge coils.
    bands = [0, 0, 1, 1, 1, 2, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0]
    barrel = C.lathe("barrel", prof, ["metal", "brass", "metal_light"], 28, band_mats=bands, rot=(90, 0, 0))
    C.place(barrel, (0, -0.14, PIVOT_Z))
    haz = C.hazard_band("barrel_hazard", 0.062, 0.47, 0.58, stripes=6, slant=1.5, rot=(90, 0, 0), sub=3)
    C.place(haz, (0, -0.14, PIVOT_Z))
    # Charge coils: three glowing rings, each on its own bone; the telegraph lights them one after
    # another from breech to muzzle (they swell), so the wind-up is a countdown the player can read.
    for k, z in enumerate(COILS):
        coil = C.torus(f"coil{k}", 0.081, 0.0125, "charge_glow", 28, 8, rot=(90, 0, 0))
        C.place(coil, (0, -0.14 - z, PIVOT_Z))
        sk.rigid(coil, f"coil.{k}")
    # Muzzle brake side vents and a sight rail on top of the sleeve.
    vents = []
    for s in (-1, 1):
        vents.append(C.box(f"brake{s}", (0.03, 0.07, 0.05), "metal", loc=(s * 0.085, -0.79, PIVOT_Z), bevel=0.006))
    rail = C.box("rail", (0.03, 0.22, 0.02), "brass", loc=(0, -0.42, PIVOT_Z + 0.09), bevel=0.005)
    for p in (barrel, haz, *vents, rail):
        sk.rigid(p, "barrel")
    orb = C.lathe("charge_orb", [(0, -0.035), (0.0134, -0.0323), (0.0247, -0.0247), (0.0323, -0.0134), (0.035, 0.0),
                                 (0.0323, 0.0134), (0.0247, 0.0247), (0.0134, 0.0323), (0, 0.035)], "charge_glow", 16,
                  rot=(90, 0, 0))
    C.place(orb, (0, -0.80, PIVOT_Z))
    sk.rigid(orb, "charge")


def build_rig() -> C.RigBuilder:
    rb = C.RigBuilder()
    rb.bone("root", (0, 0, 0), (0, 0, 0.25))
    rb.bone("hatch", (0, -0.345, 0.19), (0, -0.335, 0.31), "root")
    rb.bone("aim", (0, 0, 0.47), (0, 0, 0.72), "root")
    rb.bone("turn", (0, 0, 0.47), (0, 0, 0.62), "aim")
    rb.bone("head", (0, 0, PIVOT_Z), (0, -0.25, PIVOT_Z), "turn")
    rb.bone("barrel", (0, -0.14, PIVOT_Z), (0, -0.55, PIVOT_Z), "head")
    rb.bone("charge", (0, -0.80, PIVOT_Z), (0, -0.90, PIVOT_Z), "barrel")
    rb.bone("eye", (0, -0.212, 0.84), (0, -0.30, 0.84), "head")
    rb.bone("reel.L", (REEL_X, 0.10, 0.81), (REEL_X, 0.10, 0.89), "head", spin=True)
    rb.bone("reel.R", (-REEL_X, 0.10, 0.81), (-REEL_X, 0.10, 0.89), "head", spin=True)
    for k, z in enumerate(COILS):
        rb.bone(f"coil.{k}", (0, -0.14 - z, PIVOT_Z), (0, -0.14 - z - 0.05, PIVOT_Z), "barrel")
    return rb


def animate(rig) -> list:
    A = C.Animator(rig, never_key=("aim",))
    COIL = ("coil.0", "coil.1", "coil.2")

    def coils(*vals) -> dict:
        return {b: {"s": v} for b, v in zip(COIL, vals)}

    # idle: a watchful hum. The head breathes, sweeps a few degrees either side, the reels creep,
    # the muzzle orb pulses and a faint pulse runs down the coils.
    A.begin("idle", 2.0, loop=True)
    A.spin("reel.L", 120)
    A.spin("reel.R", 120)
    ripple = [C.piecewise([(0, 1.0), (10 + 8 * k, 1.0), (16 + 8 * k, 1.14), (24 + 8 * k, 1.0), (60, 1.0)]) for k in range(3)]
    A.overlay = lambda f: {b: {"s": ripple[k](f)} for k, b in enumerate(COIL)}
    A.pose(0, {"head": {"r": (-1, 0, 0)}, "charge": {"s": 1.0}})
    A.pose(15, {"turn": {"r": (0, 0, 4), "l": (0, 0, 0.004)}, "head": {"r": (1.0, 0, 0)}, "charge": {"s": 1.1}})
    A.pose(30, {"turn": {"l": (0, 0, 0.008)}, "head": {"r": (2.0, 0, 0)}, "charge": {"s": 1.25}})
    A.pose(45, {"turn": {"r": (0, 0, -4), "l": (0, 0, 0.004)}, "head": {"r": (0.5, 0, 0)}, "charge": {"s": 1.1}})
    A.pose(60, {"head": {"r": (-1, 0, 0)}, "charge": {"s": 1.0}})
    A.end()

    # move (stationary): a slow scanning sweep of the head under the game's aim.
    A.begin("move", 2.0, loop=True)
    A.spin("reel.L", 240)
    A.spin("reel.R", 240)
    A.pose(0, {"turn": {"r": (0, 0, 0)}, "head": {"r": (-2, 0, 0)}})
    A.pose(15, {"turn": {"r": (0, 0, 18)}, "head": {"r": (-5, 0, 0)}, "charge": {"s": 1.1}})
    A.pose(30, {"turn": {"r": (0, 0, 0)}, "head": {"r": (-1, 0, 0)}})
    A.pose(45, {"turn": {"r": (0, 0, -18)}, "head": {"r": (-5, 0, 0)}, "charge": {"s": 1.1}})
    A.pose(60, {"turn": {"r": (0, 0, 0)}, "head": {"r": (-2, 0, 0)}})
    A.end()

    # telegraph (scrubbed 0..1 by the game): every quarter adds something, so progress reads at
    # any instant. The head pops up on its lift column and the barrel draws back (0-40 %), the
    # three coils light in turn from breech to muzzle (20 / 45 / 70 %), the muzzle orb grows the
    # whole time and the locked head trembles at the end.
    coil_t = [C.piecewise([(0, 1.0), (3 + 7.5 * k, 1.0), (8 + 7.5 * k, 1.75), (12 + 7.5 * k, 1.55), (30, 1.6)]) for k in range(3)]
    orb_t = C.piecewise([(0, 1.0), (6, 1.3), (14, 1.7), (22, 2.3), (27, 2.9), (30, 3.1)])
    A.begin("telegraph", 1.0)
    A.overlay = lambda f: {"eye": {"s": C.EYE_TELEGRAPH(f)}, "charge": {"s": orb_t(f)},
                           **{b: {"s": coil_t[k](f)} for k, b in enumerate(COIL)}}
    A.spin("reel.L", 0, curve=lambda t: 900 * t * t)
    A.spin("reel.R", 0, curve=lambda t: 900 * t * t)
    A.pose(0, {"head": {"r": (-1, 0, 0)}})
    A.pose(4, {"head": {"r": (4, 0, 0)}, "turn": {"l": (0, 0, -0.012)}})
    A.pose(10, {"head": {"r": (-5, 0, 0)}, "turn": {"l": (0, 0, 0.045)}, "barrel": {"l": (0, 0.05, 0)}})
    A.pose(16, {"head": {"r": (-2, 0, 0)}, "turn": {"l": (0, 0, 0.04)}, "barrel": {"l": (0, 0.09, 0)}})
    A.pose(22, {"head": {"r": (0.5, 0, 0)}, "turn": {"l": (0, 0, 0.04)}, "barrel": {"l": (0, 0.105, 0)}})
    A.pose(24, {"head": {"r": (1.6, 0, 0)}, "turn": {"l": (0, 0, 0.042), "r": (0, 0, 1.2)}, "barrel": {"l": (0, 0.11, 0)}})
    A.pose(26, {"head": {"r": (0.2, 0, 0)}, "turn": {"l": (0, 0, 0.038), "r": (0, 0, -1.2)}, "barrel": {"l": (0, 0.112, 0)}})
    A.pose(28, {"head": {"r": (1.6, 0, 0)}, "turn": {"l": (0, 0, 0.042), "r": (0, 0, 1.0)}, "barrel": {"l": (0, 0.115, 0)}})
    A.pose(30, {"head": {"r": (1, 0, 0)}, "turn": {"l": (0, 0, 0.04)}, "barrel": {"l": (0, 0.12, 0)}})
    A.end()

    # attack: the shot on frame 2 (barrel slams forward past rest, coils and orb are spent, the head
    # kicks up and the whole mount drops), then a damped return.
    coil_a = [C.piecewise([(0, 1.6), (1, 2.0), (3, 0.8), (10 + 3 * k, 0.8), (20 + 3 * k, 1.0), (30, 1.0)]) for k in range(3)]
    orb_a = C.piecewise([(0, 3.1), (1, 3.6), (3, 0.3), (10, 0.35), (22, 0.85), (30, 1.0)])
    A.begin("attack", 1.0)
    A.overlay = lambda f: {"eye": {"s": C.EYE_ATTACK(f)}, "charge": {"s": orb_a(f)},
                           **{b: {"s": coil_a[k](f)} for k, b in enumerate(COIL)}}
    A.spin("reel.L", 0, curve=lambda t: 900 + 500 * C.ease_out(t))
    A.spin("reel.R", 0, curve=lambda t: 900 + 500 * C.ease_out(t))
    A.pose(0, {"head": {"r": (1, 0, 0)}, "turn": {"l": (0, 0, 0.04)}, "barrel": {"l": (0, 0.12, 0)}}, "LINEAR")
    A.pose(1, {"head": {"r": (2, 0, 0)}, "turn": {"l": (0, 0, 0.03)}, "barrel": {"l": (0, -0.05, 0)}}, "LINEAR")
    A.pose(3, {"head": {"r": (-13, 0, 0)}, "turn": {"l": (0, 0, -0.02)}, "barrel": {"l": (0, 0.16, 0)}})
    A.pose(7, {"head": {"r": (-9, 0, 0)}, "turn": {"l": (0, 0, -0.012)}, "barrel": {"l": (0, 0.13, 0)}})
    A.pose(15, {"head": {"r": (-1, 0, 0)}, "turn": {"l": (0, 0, 0.004)}, "barrel": {"l": (0, 0.04, 0)}})
    A.pose(22, {"head": {"r": (1, 0, 0)}, "barrel": {"l": (0, 0.01, 0)}})
    A.pose(30, {"head": {"r": (-1, 0, 0)}})
    A.end()

    # stagger: knocked off its lock, the head rattles in the yoke and settles.
    A.begin("stagger", 1.0)
    flick = C.piecewise([(0, 1.0), (3, 0.5), (8, 1.4), (13, 0.7), (18, 1.1), (22, 1.0), (30, 1.0)])
    A.overlay = lambda f: {"eye": {"s": C.EYE_STAGGER(f)}, "charge": {"s": flick(f)},
                           **{b: {"s": flick(f - 2 * k)} for k, b in enumerate(COIL)}}
    A.spin("reel.L", 0, curve=lambda t: 70 * math.sin(t * 18) * (1 - t))
    A.spin("reel.R", 0, curve=lambda t: -70 * math.sin(t * 18) * (1 - t))
    A.pose(0, {"head": {"r": (-1, 0, 0)}})
    A.pose(3, {"turn": {"r": (0, 0, 22), "l": (0, 0, -0.012)}, "head": {"r": (-18, 0, 0)}, "barrel": {"r": (5, 0, 0), "l": (0, 0.06, 0)}})
    A.pose(8, {"turn": {"r": (0, 0, -14), "l": (0, 0, 0.01)}, "head": {"r": (11, 0, 0)}, "barrel": {"r": (-3, 0, 0)}})
    A.pose(13, {"turn": {"r": (0, 0, 8)}, "head": {"r": (-6, 0, 0)}})
    A.pose(18, {"turn": {"r": (0, 0, -4)}, "head": {"r": (3, 0, 0)}})
    A.pose(24, {"turn": {"r": (0, 0, 1.5)}, "head": {"r": (-2, 0, 0)}})
    A.pose(30, {"head": {"r": (-1, 0, 0)}})
    A.end()

    # death: an overload flash, then the head slews aside, drops and pitches over until the barrel
    # rests on the turntable rim (no further: it must not sink into the plinth), the coils and orb go out one by one and the service hatch falls open.
    coil_d = [C.piecewise([(0, 1.0), (4, 1.9), (9 + 3 * k, 1.2), (13 + 3 * k, 0.05), (30, 0.05)]) for k in range(3)]
    orb_d = C.piecewise([(0, 1.0), (4, 2.6), (10, 0.3), (17, 0.05), (30, 0.02)])
    A.begin("death", 1.0)
    A.overlay = lambda f: {"eye": {"s": C.EYE_DEATH(f)}, "charge": {"s": orb_d(f)},
                           **{b: {"s": coil_d[k](f)} for k, b in enumerate(COIL)}}
    A.spin("reel.L", 0, curve=lambda t: 260 * C.ease_out(t))
    A.spin("reel.R", 0, curve=lambda t: 200 * C.ease_out(t))
    A.pose(0, {"head": {"r": (-1, 0, 0)}})
    A.pose(4, {"head": {"r": (-14, 0, 0)}, "turn": {"l": (0, 0, 0.02)}})
    A.pose(10, {"head": {"r": (10, 0, 0)}, "turn": {"r": (0, 0, 9), "l": (0, 0, -0.01)}, "hatch": {"r": (35, 0, 0)}})
    A.pose(17, {"head": {"r": (DEAD_PITCH + 3, 0, 0)}, "turn": {"r": (0, 0, 24), "l": (0, 0, -0.03)}, "barrel": {"l": (0, -0.03, 0)},
                "hatch": {"r": (104, 0, 0)}})
    A.pose(22, {"head": {"r": (DEAD_PITCH - 3, 0, 0)}, "turn": {"r": (0, 0, 27), "l": (0, 0, -0.026)}, "barrel": {"l": (0, -0.03, 0)},
                "hatch": {"r": (92, 0, 0)}})
    A.pose(30, {"head": {"r": (DEAD_PITCH, 0, 0)}, "turn": {"r": (0, 0, 26), "l": (0, 0, -0.03)}, "barrel": {"l": (0, -0.035, 0)},
                "hatch": {"r": (100, 0, 0)}})
    A.end()
    return A.actions


def build() -> tuple:
    C.reset_scene()
    rb = build_rig()
    rig = rb.finish()
    sk = C.Skin(rig)
    build_base(sk)
    build_yoke(sk)
    build_head(sk)
    build_barrel(sk)
    body = sk.build("turret")
    C.uv_unwrap(body)
    C.scale_model(rig, [body], SCALE)
    actions = animate(rig)
    return rig, body, actions


def main() -> None:
    args = C.script_args()
    out = args["out"] or os.path.join(C.REPO, "assets", "models", "enemies", "turret.glb")
    prev = args["previews"] or os.path.join(C.REPO, "art", "previews", "enemies", "turret")
    rig, body, actions = build()
    if args["quick"]:  # --quick: build and run the floor check only (pose tuning)
        C.floor_report(rig, [body], actions, step=1)
        return
    C.export_glb(out)
    tris, lo, hi = C.mesh_stats([body])
    print(f"turret: {tris} triangles, rest bounds {tuple(round(x, 3) for x in lo)} .. {tuple(round(x, 3) for x in hi)}")
    C.floor_report(rig, [body], actions)
    pv = C.Previewer(prev, floor_tiles=2)
    pv.turnaround([body])
    pv.iso([body])
    pv.thumbnail([body])
    if args["anim"]:
        lo, hi = pv.frame_bounds([body], 0.08)
        lo.z = 0
        pv.action_frames(rig, [body], actions, 8, (300, 300), lo, hi)
    C.run_sheets("turret", prev)


if __name__ == "__main__":
    main()
