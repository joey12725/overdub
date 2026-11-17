"""OVERDUB enemy: boss — the Archivist, the stationary colossus that remembers committed tapes.

    blender --background --python art/enemies/boss.py -- [--out assets/models/enemies/boss.glb]
                                                         [--previews art/previews/enemies/boss]
                                                         [--no-anim-previews]

Reads as: the dungeon's centrepiece. A stepped rune dais (3x3 tiles) carrying a reel-to-reel
machine of ruin stone and brass: two huge tape reels on its shoulders thread a tape across its
face — a recording head with one great eye — and above it a slowly turning halo of small screens,
each one replaying (it is watching and remembering). Its chest is a glowing memory core under
three removable armour layers (separate objects the game hides as phases advance):
  Armor_1  outer ceramic breastplate/backplate (the back has a grille window: hit it from behind)
  Armor_2  brass louvre shutters
  Armor_3  inner rune cage
Two long arms end in splicing blades for the cleave. ~3.2 tall.

Rig "Rig": root, body, chest, core (scale pulse), head, halo (spin) + screen.00..07, reel.L/R
(spin), shoulder/upper_arm/forearm/blade .L/.R.
"""
from __future__ import annotations

import math
import os
import sys

import bmesh
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common2 as C  # noqa: E402

N_SCREENS = 8
HALO_R = 0.5
HALO_C = Vector((0.0, 0.42, 2.64))  # aureole centre, behind the head
HALO_TILT = 78.0                    # ring axis tilted from vertical toward the front (degrees): nearly upright
HALO_M = Matrix.Translation(HALO_C) @ Matrix.Rotation(math.radians(HALO_TILT), 4, "X")
SCREEN_TILT = 30.0                  # screens turned from radial-outward toward the ring axis (the front)
HEAD_Y = -0.18
REEL_X = 0.98
REEL_Z = 2.38
REEL_R = 0.6
REEL_TILT = 22  # reels turn outward from the front by this much (degrees about Z)
SCALE = 0.97  # authored at 3.31 tall; shipped at ~3.2


def screen_angle(i: int) -> float:
    """Angle of screen i in the halo ring's own plane (90 = top of the aureole)."""
    return 90.0 + 360.0 * i / N_SCREENS


def to_halo(ob):
    """Move a part built in the ring frame (ring in the XY plane, axis +Z) onto the aureole."""
    C.bake(ob)
    ob.data.transform(HALO_M)
    return ob


# ───────────────────────────── base and body ─────────────────────────────


def build_dais(sk: C.Skin) -> None:
    prof = [(0, 0), (1.45, 0), (1.45, 0.11), (1.39, 0.17), (1.26, 0.17), (1.26, 0.30), (1.19, 0.345), (0.86, 0.345),
            (0.86, 0.40), (0, 0.40)]
    dais = C.lathe("dais", prof, ["ceramic_dark", "ceramic"], 48, band_mats=[0, 0, 0, 0, 1, 1, 1, 1, 1], angle0=7.5)
    # Paving seams on the top tier: every other 15-degree sector a separate slab.
    C.inset_faces(dais, lambda c, n: n.z > 0.9 and 0.9 < math.hypot(c.x, c.y) < 1.2 and
                  int(((math.degrees(math.atan2(c.y, c.x)) + 367.5) % 360) // 15) % 2 == 0, 0.015, -0.006, "ceramic_dark",
                  individual=False)
    band = C.hazard_band("dais_hazard", 1.268, 0.185, 0.285, stripes=36, slant=1, angle0=7.5, rows=2)
    rune = C.ring("dais_rune", 1.12, 1.06, 0.012, "rune_glow", 48, loc=(0, 0, 0.347))
    parts = [dais, band, rune]
    for k in range(8):
        a = math.radians(22.5 + 45 * k)
        c, s = math.cos(a), math.sin(a)
        parts.append(C.box(f"clamp{k}", (0.24, 0.16, 0.08), "brass", loc=(1.36 * c, 1.36 * s, 0.13), rot=(0, 0, math.degrees(a)), bevel=0.02))
        parts.append(C.bolts(f"clamp_bolt{k}", [(1.40 * c - 0.04 * s, 1.40 * s + 0.04 * c, 0.17), (1.40 * c + 0.04 * s, 1.40 * s - 0.04 * c, 0.17)],
                             (0, 0, 1), 0.022, 0.02, "metal_light"))
    # Rune glyphs set into the top tier between the slabs.
    for k in range(6):
        a = math.radians(60 * k + 30)
        o = (0.99 * math.cos(a), 0.99 * math.sin(a), 0.346)
        u = (-math.sin(a), math.cos(a), 0)
        v = (math.cos(a), math.sin(a), 0)
        parts.append(C.glyphs(f"dais_glyph{k}", [[(-0.07, -0.05), (0.0, 0.05), (0.07, -0.05)], [(-0.04, 0.0), (0.04, 0.0)],
                                                  [(0.0, 0.05), (0.0, -0.06)]], o, u, v, 0.018, 0.012))
    for p in parts:
        sk.rigid(p, "root")
    # Feed cables from the dais into the body (soft between root and body).
    for k, a in enumerate((50, 130, 230, 310)):
        r = math.radians(a)
        c, s = math.cos(r), math.sin(r)
        cab = C.tube(f"feed{k}", [(1.0 * c, 1.0 * s, 0.37), (0.95 * c, 0.95 * s, 0.55), (0.78 * c, 0.78 * s, 0.75), (0.68 * c, 0.68 * s, 0.95)],
                     0.045, "cable", 8, res=4)
        sk.blend(cab, ["root", "body"], 3.0)


def build_body(sk: C.Skin) -> None:
    prof = [(0, 0.38), (0.74, 0.38), (0.8, 0.5), (0.72, 0.9), (0.63, 1.3), (0.67, 1.4), (0, 1.4)]
    trunk = C.lathe("trunk", prof, "metal", 40)
    parts = [trunk,
             C.torus("trunk_ring_lo", 0.79, 0.035, "brass", 40, 5, loc=(0, 0, 0.52)),
             C.torus("trunk_ring_hi", 0.665, 0.03, "brass", 40, 5, loc=(0, 0, 1.33))]
    # Eight ceramic buttress ribs between the two brass rings, clear of the four feed cables and
    # flanking the front. Each leans in with the taper of the trunk.
    for k in range(8):
        rib = C.prism(f"rib{k}", [(-0.075, 0.0), (0.075, 0.0), (0.05, 0.7), (-0.05, 0.7)], 0.09, "ceramic", bevel=0.014)
        C.place(rib, (0, 0, 0), (0, 0, 90))
        C.place(rib, (0, 0, 0), (0, -11.5, 0))
        C.place(rib, (0.79, 0, 0.57))
        C.place(rib, (0, 0, 0), (0, 0, 22.5 + 45 * k))
        parts.append(rib)
    for p in parts:
        sk.rigid(p, "body")


def build_chest(sk: C.Skin) -> None:
    parts = [C.cyl("chest_floor", 0.78, 0.09, "brass", 32, z0=1.38, bevel=0.02),
             C.cyl("chest_collar", 0.72, 0.12, "metal", 40, z0=2.16, bevel=0.025, r_top=0.6),
             C.cyl("neck", 0.34, 0.2, "metal_light", 24, z0=2.26, bevel=0.02)]
    for k in range(6):
        a = math.radians(60 * k)
        parts.append(C.box(f"post{k}", (0.07, 0.07, 0.72), "metal_light", loc=(0.7 * math.cos(a), 0.7 * math.sin(a), 1.82), bevel=0.012))
    # Shoulder yokes carrying the reel axles and the arm sockets.
    for s in (-1, 1):
        parts.append(C.box(f"yoke{s}", (0.5, 0.36, 0.3), "metal", loc=(s * 0.66, 0.06, 2.08), rot=(0, s * -12, 0), bevel=0.04, seg=2))
        boom = C.cyl(f"boom{s}", 0.09, 0.4, "metal_light", 16, rot=(90, 0, 0))
        C.place(boom, (s * REEL_X, 0.25, REEL_Z), (0, 0, s * REEL_TILT))
        parts.append(boom)
        parts.append(C.cyl(f"socket{s}", 0.16, 0.18, "brass", 16, rot=(0, 90, 0), loc=(s * 0.86, -0.02, 1.86), bevel=0.02))
    for p in parts:
        sk.rigid(p, "chest")
    # The memory core: a glowing spool with brass end caps (its own bone so it can pulse).
    core = [C.cyl("core", 0.4, 0.62, "core_glow", 24, z0=1.48),
            C.cyl("core_cap_lo", 0.46, 0.06, "brass", 24, z0=1.46, bevel=0.015),
            C.cyl("core_cap_hi", 0.46, 0.06, "brass", 24, z0=2.08, bevel=0.015),
            C.cyl("core_spindle", 0.12, 0.8, "metal", 12, z0=1.4)]
    for p in core:
        sk.rigid(p, "core")


def build_head(sk: C.Skin) -> None:
    hy = HEAD_Y
    block = C.box("head_block", (0.82, 0.52, 0.58), "ceramic", loc=(0, hy + 0.1, 2.62), bevel=0.06, seg=2, taper=(0.9, 0.92))
    C.inset_faces(block, lambda c, n: abs(n.x) > 0.9, 0.04, -0.015, "ceramic_dark")
    # The recording head: a polished half-drum face with its gap and one great lens.
    face = C.lathe("head_face", [(0, -0.24), (0.27, -0.24), (0.29, -0.2), (0.29, 0.2), (0.27, 0.24), (0, 0.24)], "metal_light", 32)
    C.place(face, (0, hy - 0.13, 2.6))
    gap_top = C.box("head_gap_top", (0.03, 0.04, 0.09), "eye_glow", loc=(0, hy - 0.405, 2.795))
    gap_bot = C.box("head_gap_bot", (0.025, 0.04, 0.1), "eye_glow", loc=(0, hy - 0.41, 2.43))
    bezel = C.ring("lens_bezel", 0.185, 0.132, 0.08, "brass", 32, rot=(90, 0, 0), bevel=0.015)
    C.place(bezel, (0, hy - 0.43, 2.6))
    lens = C.lathe("lens", [(0, -0.02), (0.137, -0.02), (0.137, 0.008), (0.118, 0.03), (0.075, 0.048), (0, 0.056)], "eye_glow", 32,
                   rot=(90, 0, 0))
    C.place(lens, (0, hy - 0.43, 2.6))
    brow = C.prism("brow", [(-0.4, 0.0), (0.4, 0.0), (0.3, 0.1), (-0.3, 0.1)], 0.3, "ceramic_dark", bevel=0.02)
    C.place(brow, (0, hy - 0.22, 2.83))
    parts = [block, face, gap_top, gap_bot, bezel, brow]
    sk.rigid(lens, "eye")
    # Tape guides either side of the head; the halo collar on top.
    for s in (-1, 1):
        parts.append(C.cyl(f"guide{s}", 0.035, 0.34, "brass", 12, loc=(s * 0.36, hy - 0.34, 2.5)))
        parts.append(C.cyl(f"guide_cap{s}", 0.055, 0.03, "metal", 12, loc=(s * 0.36, hy - 0.34, 2.68)))
        parts.append(C.hazard_panel(f"cheek_hazard{s}", (0.012, 0.3, 0.12), 0.06, loc=(s * 0.345, hy + 0.08, 2.47), bevel=0.003))
    parts.append(C.cyl("halo_collar", 0.16, 0.12, "metal", 16, z0=2.86, bevel=0.02))
    parts.append(C.glyphs("brow_runes", [[(-0.26, 0.0), (-0.16, 0.05), (-0.06, 0.0), (0.06, 0.0), (0.16, 0.05), (0.26, 0.0)]],
                          (0, hy - 0.371, 2.88), (1, 0, 0), (0, -0.5, 0.87), 0.016, 0.014))
    for p in parts:
        sk.rigid(p, "head")


def build_halo(sk: C.Skin) -> None:
    """The aureole of memory screens: a brass ring behind the head, tilted to face forward, with
    eight small CRTs (each replaying) and tiny reels between them. It turns slowly on its axis."""
    parts = [C.torus("halo_ring", HALO_R, 0.038, "brass", 40, 6),
             C.torus("halo_inner", HALO_R - 0.09, 0.026, "metal", 32, 5, loc=(0, 0, -0.02)),
             C.cyl("halo_hub", 0.13, 0.12, "brass", 16, bevel=0.02),
             C.cyl("halo_hub_cap", 0.07, 0.05, "rune_glow", 8, loc=(0, 0, 0.07))]
    for k in range(4):
        a = math.radians(45 + 90 * k)
        parts.append(C.tube(f"halo_strut{k}", [(0.1 * math.cos(a), 0.1 * math.sin(a), 0.0),
                                               (0.3 * math.cos(a), 0.3 * math.sin(a), 0.03),
                                               (HALO_R * math.cos(a), HALO_R * math.sin(a), 0.0)], 0.028, "metal", 6))
    # Little reels between the screens, lying on the ring.
    for k in range(N_SCREENS):
        a = math.radians(screen_angle(k) + 180.0 / N_SCREENS)
        x, y = HALO_R * math.cos(a), HALO_R * math.sin(a)
        parts.append(C.lathe(f"mini_reel{k}", [(0, 0), (0.07, 0), (0.07, 0.012), (0.05, 0.016), (0.05, 0.04), (0.07, 0.044),
                                                (0.07, 0.056), (0, 0.056)], ["brass", "tape"], 12, band_mats=[0, 0, 0, 1, 0, 0, 0],
                             loc=(x, y, 0.02)))
    for p in parts:
        to_halo(p)
        sk.rigid(p, "halo")
    # Support arm from the back of the head into the hub (rides the head; the ring spins on it).
    sup = C.tube("halo_support", [(0, 0.2, 2.62), (0, 0.4, 2.62), tuple(HALO_M @ Vector((0, 0, -0.07)))], 0.05, "metal_light", 8)
    sk.rigid(sup, "head")
    for k in range(N_SCREENS):
        a = math.radians(screen_angle(k))
        bone = f"screen.{k:02d}"
        crt = C.box(f"crt{k}", (0.26, 0.16, 0.2), "metal", loc=(0, 0.02, 0), bevel=0.025, seg=1, taper=(0.8, 0.8))
        glass = C.box(f"crt_glass{k}", (0.2, 0.02, 0.14), "screen_glow", loc=(0, -0.065, 0), bevel=0.012)
        bez = C.box(f"crt_bezel{k}", (0.25, 0.025, 0.19), "brass", loc=(0, -0.055, 0), bevel=0.01)
        C.inset_faces(bez, lambda c, n: n.y < -0.9, 0.025, 0.0, None)
        scan = C.box(f"crt_scan{k}", (0.15, 0.022, 0.012), "screen", loc=(0, -0.073, 0.02 - 0.03 * (k % 3)))
        mount = C.box(f"crt_mount{k}", (0.06, 0.12, 0.06), "metal_light", loc=(0, 0.1, 0.0), bevel=0.01)
        scr = C.join_raw(f"screen{k}", [crt, glass, bez, scan, mount])
        # Built facing -Y. In the ring frame: tip it so it faces radially outward but turned
        # SCREEN_TILT toward the ring axis (+Z, the front), swing it to its angle, move it onto the aureole.
        C.place(scr, (0, 0, 0), (-SCREEN_TILT, 0, 0))
        C.place(scr, (0, 0, 0), (0, 0, math.degrees(a) + 90))
        C.place(scr, ((HALO_R + 0.09) * math.cos(a), (HALO_R + 0.09) * math.sin(a), 0.0))
        to_halo(scr)
        sk.rigid(scr, bone)


def build_reels(sk: C.Skin) -> None:
    for s, side in ((1, "L"), (-1, "R")):
        parts = [C.lathe(f"pack{side}", [(0.12, -0.07), (0.42, -0.07), (0.42, 0.07), (0.12, 0.07), (0.12, -0.07)], "tape", 32, cap=False),
                 C.ring(f"flange_back{side}", REEL_R, 0.1, 0.03, "brass", 36, loc=(0, 0, -0.085), bevel=0.01),
                 C.ring(f"rim_front{side}", REEL_R, REEL_R - 0.07, 0.035, "brass", 36, loc=(0, 0, 0.085), bevel=0.01),
                 C.cyl(f"reel_hub{side}", 0.13, 0.26, "metal", 20, bevel=0.02),
                 C.cyl(f"reel_hubcap{side}", 0.07, 0.06, "brass", 6, loc=(0, 0, 0.15), bevel=0.01)]
        for k in range(3):
            a = 90 + 120 * k
            parts.append(C.box(f"spoke{side}{k}", (0.42, 0.14, 0.035), "brass",
                               loc=(0.32 * math.cos(math.radians(a)), 0.32 * math.sin(math.radians(a)), 0.085), rot=(0, 0, a), bevel=0.01))
            hole = math.radians(a + 60)
            parts.append(C.glyphs(f"reel_rune{side}{k}", [[(-0.06, 0), (0.06, 0)], [(0, -0.04), (0, 0.04)]],
                                  (0.5 * math.cos(hole), 0.5 * math.sin(hole), 0.07), (-math.sin(hole), math.cos(hole), 0),
                                  (math.cos(hole), math.sin(hole), 0), 0.014, 0.01))
        reel = C.join_raw(f"reel_{side}", parts)
        # Axle along local Z -> along -Y (face to the front), turned outward, placed on the shoulder.
        C.place(reel, (0, 0, 0), (90, 0, 0))
        C.place(reel, (0, 0, 0), (0, 0, s * REEL_TILT))
        C.place(reel, (s * REEL_X, 0.0, REEL_Z))
        sk.rigid(reel, f"reel.{side}")
    # The tape: from each reel pack, around the guides and across the face below the lens.
    hy = HEAD_Y
    pts = []
    for s in (1, -1):
        pts_side = [(s * (REEL_X - 0.38), -0.08, REEL_Z - 0.26), (s * 0.5, hy - 0.3, 2.42), (s * 0.38, hy - 0.39, 2.4)]
        pts.append(pts_side)
    path = pts[0] + [(0.0, hy - 0.45, 2.4)] + list(reversed(pts[1]))
    tape = C.tube("tape_strand", path, 0.026, "tape", 6, res=8)
    sk.blend(tape, ["chest", "head"], 6.0)


def build_arm(sk: C.Skin, s: int) -> None:
    side = "L" if s > 0 else "R"
    sh = Vector((s * 0.92, -0.02, 1.86))
    el = Vector((s * 1.22, -0.3, 1.36))
    wr = Vector((s * 1.2, -0.78, 0.86))
    upper = [C.tube(f"upper{side}", [tuple(sh), tuple(sh.lerp(el, 0.5) + Vector((s * 0.03, 0, 0.02))), tuple(el)], 0.1, "metal_light", 12),
             C.box(f"upper_plate{side}", (0.09, 0.3, 0.42), "ceramic", loc=tuple(sh.lerp(el, 0.5) + Vector((s * 0.1, 0, 0.02))),
                   rot=(-30, s * 30, 0), bevel=0.025)]
    for p in upper:
        sk.rigid(p, f"upper_arm.{side}")
    sk.rigid(C.cyl(f"shoulder_ball{side}", 0.17, 0.22, "metal", 24, rot=(0, 90, 0), loc=tuple(sh), bevel=0.03), f"shoulder.{side}")
    elbow = C.cyl(f"elbow{side}", 0.13, 0.24, "brass", 24, rot=(0, 90, 0), loc=tuple(el), bevel=0.025)
    fore = C.box(f"forearm{side}", (0.26, 0.26, 0.62), "ceramic", bevel=0.04, seg=2, taper=(0.8, 0.8))
    d = (wr - el)
    q = Vector((0, 0, -1)).rotation_difference(d.normalized())
    fore.rotation_mode = "QUATERNION"
    fore.rotation_quaternion = q
    fore.location = el.lerp(wr, 0.5)
    band = C.box(f"forearm_band{side}", (0.29, 0.29, 0.05), "brass", bevel=0.01)
    band.rotation_mode = "QUATERNION"
    band.rotation_quaternion = q
    band.location = el.lerp(wr, 0.78)
    for p in (elbow, fore, band):
        sk.rigid(p, f"forearm.{side}")
    # Splicing blade: a long angled cutter with a hazard-striped spine.
    blade = C.prism(f"blade{side}", [(-0.09, 0.0), (0.09, 0.0), (0.14, -0.45), (0.05, -1.0), (-0.01, -1.1), (-0.07, -0.6)],
                    0.085, "metal_light", bevel=0.012)
    spine = C.hazard_panel(f"blade_spine{side}", (0.09, 0.1, 0.46), 0.07, loc=(-0.01, 0, -0.26), bevel=0.006)
    clamp = C.box(f"blade_clamp{side}", (0.2, 0.16, 0.12), "metal", loc=(0, 0, 0.0), bevel=0.02)
    bl = C.join_raw(f"blade_{side}", [blade, spine, clamp])
    dir_b = Vector((s * -0.25, -0.85, -0.47)).normalized()
    qb = Vector((0, 0, -1)).rotation_difference(dir_b)
    C.place(bl, (0, 0, 0), (0, 0, 90 if s > 0 else -90))
    bl.rotation_mode = "QUATERNION"
    bl.rotation_quaternion = qb
    bl.location = wr
    sk.rigid(bl, f"blade.{side}")


def armor_1(sk: C.Skin) -> None:
    """Outer ceramic shell: full ring with a grille window at the back (the weak spot)."""
    prof = [(0.8, 1.42), (0.86, 1.6), (0.88, 1.8), (0.85, 2.0), (0.78, 2.16)]
    shell = C.lathe("armor1_shell", prof, "ceramic", 48, cap=False)
    bm = bmesh.new()
    bm.from_mesh(shell.data)
    kill = []
    for f in bm.faces:
        c = f.calc_center_median()
        ang = math.degrees(math.atan2(c.y, c.x))
        if abs(ang - 90) < 28 and 1.55 < c.z < 2.05:
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(shell.data)
    bm.free()
    C.mod_solidify(shell, 0.06, 1.0)
    C.apply_modifiers(shell)
    C.resmooth(shell, 40)
    C.recolor(shell, "ceramic_dark", lambda c, n: abs(math.degrees(math.atan2(c.y, c.x)) + 90) > 60 and c.z < 1.55)
    parts = [shell,
             C.hazard_band("armor1_hazard", 0.868, 1.44, 1.56, stripes=28, slant=1, r_top=0.925, rows=2),
             C.torus("armor1_rim", 0.8, 0.03, "brass", 48, 5, loc=(0, 0, 2.17))]
    for k in range(5):
        parts.append(C.box(f"armor1_grille{k}", (0.34, 0.05, 0.035), "metal", loc=(0, 0.86, 1.62 + 0.09 * k), bevel=0.008))
    rune = C.glyphs("armor1_rune", [[(-0.22, -0.12), (-0.1, 0.14), (0.0, -0.06), (0.1, 0.14), (0.22, -0.12)], [(-0.12, -0.18), (0.12, -0.18)]],
                    (0, -0.94, 1.84), (1, 0, 0), (0, 0, 1), 0.034, 0.03)
    # The breastplate is round: wrap the ward rune onto it (its ends used to stand off the surface).
    parts.append(C.project_onto(rune, shell, (0, -0.94, 1.84), (0, -1, 0), lift=0.006))
    for p in parts:
        sk.rigid(p, "chest")


def armor_2(sk: C.Skin) -> None:
    """Brass louvre shutters around the core."""
    parts = []
    n = 20
    for k in range(n):
        a = 360.0 * k / n
        sl = C.box(f"louvre{k}", (0.17, 0.025, 0.64), "brass", bevel=0.0)
        C.place(sl, (0, 0, 0), (0, 0, 35))
        C.place(sl, (0, -0.64, 1.8), (0, 0, 0))
        C.place(sl, (0, 0, 0), (0, 0, a))
        parts.append(sl)
    parts.append(C.torus("louvre_ring_lo", 0.64, 0.025, "metal", 32, 5, loc=(0, 0, 1.5)))
    parts.append(C.torus("louvre_ring_hi", 0.64, 0.025, "metal", 32, 5, loc=(0, 0, 2.1)))
    for p in parts:
        sk.rigid(p, "chest")


def armor_3(sk: C.Skin) -> None:
    """Inner rune cage: dark bars and glowing rune hoops."""
    parts = []
    for k in range(12):
        a = math.radians(15 + 30 * k)
        parts.append(C.box(f"cage_bar{k}", (0.05, 0.05, 0.66), "metal", loc=(0.53 * math.cos(a), 0.53 * math.sin(a), 1.8), rot=(0, 0, math.degrees(a)), bevel=0.01))
    for z in (1.6, 1.8, 2.0):
        parts.append(C.torus(f"cage_hoop{z}", 0.53, 0.018, "rune_glow", 32, 5, loc=(0, 0, z)))
    for p in parts:
        sk.rigid(p, "chest")


def build_rig() -> C.RigBuilder:
    rb = C.RigBuilder()
    rb.bone("root", (0, 0, 0), (0, 0, 0.4))
    rb.bone("body", (0, 0, 0.42), (0, 0, 1.38), "root")
    rb.bone("chest", (0, 0, 1.38), (0, 0, 2.25), "body", connect=True)
    rb.bone("core", (0, 0, 1.78), (0, 0, 2.0), "chest")
    rb.bone("head", (0, HEAD_Y, 2.3), (0, HEAD_Y, 2.8), "chest")
    rb.bone("eye", (0, HEAD_Y - 0.43, 2.6), (0, HEAD_Y - 0.6, 2.6), "head")
    rb.bone("halo", tuple(HALO_M @ Vector((0, 0, 0))), tuple(HALO_M @ Vector((0, 0, 0.25))), "head", spin=True)
    for k in range(N_SCREENS):
        a = math.radians(screen_angle(k))
        c, s = math.cos(a), math.sin(a)
        rb.bone(f"screen.{k:02d}", tuple(HALO_M @ Vector((HALO_R * c, HALO_R * s, 0))),
                tuple(HALO_M @ Vector(((HALO_R + 0.2) * c, (HALO_R + 0.2) * s, 0))), "halo")
    for s, side in ((1, "L"), (-1, "R")):
        t = math.radians(s * REEL_TILT)
        ax = Vector((math.sin(t), -math.cos(t), 0))  # reel axle: to the front, turned outward (matches build_reels)
        rb.bone(f"reel.{side}", (s * REEL_X, 0.0, REEL_Z), tuple(Vector((s * REEL_X, 0.0, REEL_Z)) + ax * 0.3), "chest", spin=True)
        sh = Vector((s * 0.92, -0.02, 1.86))
        el = Vector((s * 1.22, -0.3, 1.36))
        wr = Vector((s * 1.2, -0.78, 0.86))
        tip = wr + Vector((s * -0.25, -0.85, -0.47)).normalized() * 1.05
        rb.bone(f"shoulder.{side}", (s * 0.55, -0.02, 1.86), tuple(sh), "chest")
        rb.bone(f"upper_arm.{side}", tuple(sh), tuple(el), f"shoulder.{side}", connect=True)
        rb.bone(f"forearm.{side}", tuple(el), tuple(wr), f"upper_arm.{side}", connect=True)
        rb.bone(f"blade.{side}", tuple(wr), tuple(tip), f"forearm.{side}", connect=True)
    return rb


# ───────────────────────────── animation ─────────────────────────────


def screens(tilt: float, wave: float = 0.0, phase: float = 0.0, look: float | None = None) -> dict:
    """Screen poses: each tilts about its ring tangent (+ = further down/out). `wave` adds a ripple
    around the ring; `look` (degrees, ring angle) tilts the screens on that side down harder."""
    out = {}
    for k in range(N_SCREENS):
        a = screen_angle(k)
        ar = math.radians(a)
        tangent = HALO_M.to_3x3() @ Vector((-math.sin(ar), math.cos(ar), 0))
        ang = tilt + wave * math.sin(math.radians(phase) + k * 2 * math.pi / N_SCREENS * 2)
        if look is not None:
            d = math.cos(math.radians(a - look))
            ang += 18 * max(0.0, d) - 10 * max(0.0, -d)
        e = Quaternion(tangent, math.radians(-ang)).to_euler("XYZ")
        out[f"screen.{k:02d}"] = {"r": tuple(math.degrees(x) for x in e)}
    return out


def P(*dicts) -> dict:
    out = {}
    for d in dicts:
        out.update(d)
    return out


WIND = P({"chest": {"r": (-4, 0, -22)}, "body": {"r": (0, 0, -6)}, "head": {"r": (8, 0, 18)}, "core": {"s": 1.22},
          "shoulder.R": {"r": (0, 12, -10)}, "upper_arm.R": {"r": (-20, 55, -55)}, "forearm.R": {"r": (-25, 0, 0)}, "blade.R": {"r": (0, 0, -20)},
          "shoulder.L": {"r": (0, -4, 0)}, "upper_arm.L": {"r": (-28, 0, 20)}, "forearm.L": {"r": (-12, 0, 0)}},
         screens(-14))

CLEAVE = P({"chest": {"r": (6, 0, 30)}, "body": {"r": (0, 0, 8)}, "head": {"r": (10, 0, -10)}, "core": {"s": 1.1},
            "shoulder.R": {"r": (0, 4, 14)}, "upper_arm.R": {"r": (-62, 20, 72)}, "forearm.R": {"r": (-10, 0, 10)}, "blade.R": {"r": (0, 0, 20)},
            "upper_arm.L": {"r": (-10, 0, 30)}, "forearm.L": {"r": (-6, 0, 0)}},
           screens(-8))


def animate(rig) -> list:
    A = C.Animator(rig)
    REELS = ("reel.L", "reel.R")
    step = 360.0 / N_SCREENS

    A.begin("idle", 2.0, loop=True)
    A.spin("reel.L", 120)
    A.spin("reel.R", 120)
    A.spin("halo", step)
    for f, k in ((0, 0.0), (15, 0.5), (30, 1.0), (45, 0.5), (60, 0.0)):
        A.pose(f, P({"body": {"l": (0, 0, 0.02 * k)}, "chest": {"r": (-1.5 * k, 0, 0)}, "core": {"s": 1.0 + 0.06 * k},
                     "head": {"r": (2 * (1 - k), 0, 0)}, "upper_arm.L": {"r": (-3 * k, 0, 0)}, "upper_arm.R": {"r": (-3 * k, 0, 0)}},
                    screens(0, 4, f * 6)))
    A.end()

    A.begin("move", 2.0, loop=True)  # stationary: it scans the room, screens following its gaze
    A.spin("reel.L", 240)
    A.spin("reel.R", 240)
    A.spin("halo", step * 2)
    for f, yaw in ((0, 0), (15, 20), (30, 0), (45, -20), (60, 0)):
        A.pose(f, P({"head": {"r": (3, 0, yaw)}, "chest": {"r": (0, 0, yaw * 0.3)}, "core": {"s": 1.03},
                     "upper_arm.L": {"r": (-4, 0, yaw * 0.2)}, "upper_arm.R": {"r": (-4, 0, yaw * 0.2)}},
                    screens(2, 4, f * 6, look=90 - yaw * 4)))
    A.end()

    A.begin("telegraph", 1.0)  # cleave wind-up: right arm sweeps back and up, all screens lock on
    A.overlay = C.eye_overlay(C.EYE_TELEGRAPH)
    A.spin("reel.L", 0, curve=lambda t: 600 * t * t)
    A.spin("reel.R", 0, curve=lambda t: 600 * t * t)
    A.spin("halo", 0, curve=lambda t: 180 * t * t)
    A.pose(0, screens(0))
    A.pose(8, P(C_mix(WIND, 0.35)))
    A.pose(18, P(C_mix(WIND, 0.85)))
    A.pose(24, WIND)
    A.pose(30, P(WIND, {"chest": {"r": (-5, 0, -24)}, "upper_arm.R": {"r": (-22, 58, -58)}, "core": {"s": 1.3}}))
    A.end()

    A.begin("attack", 1.0)  # the cleave: a wide sweep across the front, then recovery
    A.overlay = C.eye_overlay(C.EYE_ATTACK)
    A.spin("reel.L", 0, curve=lambda t: 600 + 400 * C.ease_out(t))
    A.spin("reel.R", 0, curve=lambda t: 600 + 400 * C.ease_out(t))
    A.spin("halo", 0, curve=lambda t: 180 + 90 * C.ease_out(t))
    A.pose(0, P(WIND, {"chest": {"r": (-5, 0, -24)}, "upper_arm.R": {"r": (-22, 58, -58)}, "core": {"s": 1.3}}), "LINEAR")
    A.pose(3, P(C_blend(WIND, CLEAVE, 0.5), {"upper_arm.R": {"r": (-60, 50, 10)}}), "LINEAR")
    A.pose(6, CLEAVE)
    A.pose(11, P(CLEAVE, {"chest": {"r": (5, 0, 27)}}))
    A.pose(20, C_mix(CLEAVE, 0.4))
    A.pose(30, screens(0))
    A.end()

    A.begin("stagger", 1.0)  # jolted: tape jams, screens rattle, arms sag
    A.overlay = C.eye_overlay(C.EYE_STAGGER)
    A.spin("reel.L", 0, curve=lambda t: 40 * math.sin(t * 25) * (1 - t))
    A.spin("reel.R", 0, curve=lambda t: -40 * math.sin(t * 25) * (1 - t))
    A.spin("halo", 0, curve=lambda t: 25 * math.sin(t * 14) * (1 - t))
    A.pose(0, screens(0))
    A.pose(3, P({"body": {"r": (-5, 3, 0), "l": (0, 0.04, -0.03)}, "chest": {"r": (-9, 0, 6)}, "head": {"r": (-14, 0, -12)}, "core": {"s": 0.85},
                 "upper_arm.L": {"r": (-8, -8, 0)}, "upper_arm.R": {"r": (-6, 8, 0)}, "forearm.L": {"r": (-6, 0, 0)}, "forearm.R": {"r": (-5, 0, 0)}},
                screens(20, 14, 0)))
    A.pose(9, P({"body": {"r": (3, -2, 0)}, "chest": {"r": (6, 0, -4)}, "head": {"r": (10, 0, 8)}, "core": {"s": 1.1},
                 "upper_arm.L": {"r": (2, 0, 0)}, "upper_arm.R": {"r": (2, 0, 0)}}, screens(-6, 10, 120)))
    A.pose(16, P({"chest": {"r": (-3, 0, 2)}, "head": {"r": (-4, 0, -3)}}, screens(6, 6, 240)))
    A.pose(23, P({"chest": {"r": (1, 0, 0)}, "head": {"r": (2, 0, 1)}}, screens(-2, 3, 0)))
    A.pose(30, screens(0))
    A.end()

    A.begin("death", 1.0)  # the archive fails: arms crash to the dais, the head bows, screens hang
    A.overlay = C.eye_overlay(C.EYE_DEATH)
    A.spin("reel.L", 0, curve=lambda t: 300 * C.ease_out(t))
    A.spin("reel.R", 0, curve=lambda t: 240 * C.ease_out(t))
    A.spin("halo", 0, curve=lambda t: 70 * C.ease_out(t))
    A.pose(0, screens(0))
    A.pose(5, P({"chest": {"r": (-10, 0, 0)}, "head": {"r": (-18, 0, 0)}, "core": {"s": 1.35},
                 "upper_arm.L": {"r": (-30, 0, 15)}, "upper_arm.R": {"r": (-30, 0, -15)}}, screens(-15)))
    # It ends slumped forward, propped on its two blades: their tips come down on the floor in front
    # of the dais (the arms give way by exactly the amount the body tips, so no blade passes
    # through the dais or the floor on the way).
    dead = P({"body": {"r": (8, 0, 4), "l": (0, -0.04, -0.12)}, "chest": {"r": (13, 0, 6)}, "head": {"r": (38, 0, 10)}, "core": {"s": 0.45},
              "shoulder.L": {"r": (0, -8, 0)}, "shoulder.R": {"r": (0, 8, 0)},
              "upper_arm.L": {"r": (-12, -8, 0)}, "upper_arm.R": {"r": (-12.2, 8, 0)}, "forearm.L": {"r": (0, 0, 0)}, "forearm.R": {"r": (0, 0, 0)}},
             screens(42, 10, 30))
    A.pose(14, C_mix(dead, 0.8))
    A.pose(20, P(dead, {"chest": {"r": (15, 0, 7)}, "head": {"r": (42, 0, 12)},
                        "upper_arm.L": {"r": (-14.5, -8, 0)}, "upper_arm.R": {"r": (-16.3, 8, 0)}}))
    A.pose(25, dead)
    A.pose(30, dead)
    A.end()
    return A.actions


def C_mix(pose: dict, t: float) -> dict:
    return C_blend({}, pose, t)


def C_blend(a: dict, b: dict, t: float) -> dict:
    out = {}
    for k in set(a) | set(b):
        pa, pb = a.get(k, {}), b.get(k, {})
        d = {}
        for ch in ("r", "l"):
            va, vb = pa.get(ch, (0, 0, 0)), pb.get(ch, (0, 0, 0))
            d[ch] = tuple(x + (y - x) * t for x, y in zip(va, vb))
        sa, sb = pa.get("s", 1.0), pb.get("s", 1.0)
        d["s"] = sa + (sb - sa) * t
        out[k] = d
    return out


# ───────────────────────────── build ─────────────────────────────


def build() -> tuple:
    C.reset_scene()
    rig = build_rig().finish()
    sk = C.Skin(rig)
    build_dais(sk)
    build_body(sk)
    build_chest(sk)
    build_head(sk)
    build_halo(sk)
    build_reels(sk)
    for s in (1, -1):
        build_arm(sk, s)
    body = sk.build("Archivist")
    armors = []
    for i, fn in enumerate((armor_1, armor_2, armor_3), start=1):
        ask = C.Skin(rig)
        fn(ask)
        armors.append(ask.build(f"Armor_{i}"))
    for ob in [body, *armors]:
        C.uv_unwrap(ob)
    C.scale_model(rig, [body, *armors], SCALE)
    actions = animate(rig)
    return rig, body, armors, actions


def main() -> None:
    args = C.script_args()
    out = args["out"] or os.path.join(C.REPO, "assets", "models", "enemies", "boss.glb")
    prev = args["previews"] or os.path.join(C.REPO, "art", "previews", "enemies", "boss")
    rig, body, armors, actions = build()
    if args["quick"]:  # --quick: build and run the floor check only (pose tuning)
        C.floor_report(rig, [body, *armors], actions, step=1, frames={"death": [10, 14, 20, 30], "stagger": [3]})
        return
    C.export_glb(out)
    objs = [body, *armors]
    tris, lo, hi = C.mesh_stats(objs)
    print(f"boss: {tris} triangles, rest bounds {tuple(round(x, 3) for x in lo)} .. {tuple(round(x, 3) for x in hi)}")
    C.floor_report(rig, objs, actions)
    pv = C.Previewer(prev, floor_tiles=3)
    pv.turnaround(objs)
    pv.iso(objs)
    pv.thumbnail(objs)
    # Phase stills: armour removed layer by layer (what the game shows as phases advance).
    lo, hi = pv.frame_bounds(objs)
    lo.z = 0
    for i in range(4):
        for k, a in enumerate(armors):
            a.hide_render = k < i
        pv.shoot(f"phase_{i}_iso", C.ISO_YAW, C.ISO_PITCH, lo, hi, (600, 600))
        pv.shoot(f"phase_{i}_back", 200, 20, lo, hi, (600, 600))
    for a in armors:
        a.hide_render = False
    if args["anim"]:
        lo, hi = pv.frame_bounds(objs, 0.1)
        lo.z = 0
        pv.action_frames(rig, objs, actions, 8, (320, 320), lo, hi)
    C.run_sheets("boss", prev)


if __name__ == "__main__":
    main()
