"""
WORLD-05: the time machine, the campaign's final treasure. Requirements leave its look open beyond
"time machine at the bottom"; this design ties it to the tape mechanics:

- an ancient octagonal dais of inscribed stone, steps ringed with rune light (the "ruins" layer);
- a gyroscope of three concentric rune rings standing upright above it (the "temporal" machine);
- two giant tape reels flanking the front, threaded through a brass playhead, like a cassette
  whose window is the machine's heart (the "music / tape" layer, echoing Moxie's Walkman);
- a glowing faceted Heart suspended between a pedestal claw and the crown emitter.

Footprint about 3 x 3 tiles, about 3 units tall. Separate objects, each with its origin on its
own rotation centre, so the game can animate them:

  Body        static: dais, pylons, pedestal, playhead, tape path, back machinery
  Ring_Outer  rune ring in the XZ plane (Godot: XY plane, facing +Z); spins about its local Z (Godot)
  Ring_Mid    gimbal ring, rest pose turned 50 degrees about the vertical
  Ring_Inner  inner ring, rest pose tilted 65 degrees about the horizontal X axis
  Heart       the glowing crystal at the rings' centre (core_glow)
  Reel_L / Reel_R   giant tape reels; spin about their local Godot Z (Blender Y) axis
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
from mathutils import Vector

import decor_lib as L
from decor_lib import M
from decor_containers import rivets
from decor_structures import glyph_strokes

C_Z = 1.66          # ring / heart centre height
R_OUT = 1.12        # outer ring radius (centre line)


def octagon_tier(r, z0, z1, mat, bev=0.02, r_top=None):
    """A flat-faced octagonal tier (faces aligned with X / Y)."""
    rt = r if r_top is None else r_top
    obj = L.lathe([(0.0, z0), (r, z0), (rt, z1), (0.0, z1)], mat=mat, n=8)
    L.place(obj, rot=(0, 0, 22.5))
    # lathe radius is to the corners; scale so the flats sit at r
    k = 1.0 / math.cos(math.radians(22.5))
    obj.data.transform(L.xform(scale=(k, k, 1.0)))
    return L.bevel(obj, bev, 1, angle=30)


def ring_square(R, radial, depth, mat, n=48):
    """A ring of rectangular section in the XZ plane (axis Y), centred on the origin."""
    obj = L.torus(R, radial / 2, rot=(90, 0, 0), mat=mat, n=n, m=4, square=True)
    # torus(square) has section radial x radial; stretch depth along Y
    obj.data.transform(L.xform(scale=(1.0, depth / radial, 1.0)))
    return L.bevel(obj, min(radial, depth) * 0.12, 1, angle=40)


def ring_inlays(R, depth, count, mat="rune_glow", seed=1, both=True, length=0.1, width=0.03):
    """Glowing rune strokes set into the front (and back) face of a ring in the XZ plane."""
    rng = random.Random(seed)
    out = []
    for k in range(count):
        a = 2 * math.pi * (k + 0.5) / count
        tang = math.degrees(a) + 90
        kind = k % 3
        for side in ((-1, 1) if both else (-1,)):
            y = side * (depth / 2 + 0.004)
            if kind == 0:      # tangential dash
                out.append(L.box((length, 0.012, width), (math.cos(a) * R, y, math.sin(a) * R), rot=(0, -tang, 0), mat=mat))
            elif kind == 1:    # radial tick pair
                for d in (-0.025, 0.025):
                    aa = a + d / R
                    out.append(L.box((width * 0.8, 0.012, length * 0.7),
                                     (math.cos(aa) * R, y, math.sin(aa) * R), rot=(0, -tang, 0), mat=mat))
            else:              # chevron
                for s in (-1, 1):
                    out.append(L.box((length * 0.6, 0.012, width * 0.8),
                                     (math.cos(a) * R, y, math.sin(a) * R), rot=(0, -tang + s * 35, 0), mat=mat))
        _ = rng
    return out


def build_ring_outer():
    radial, depth = 0.16, 0.2
    parts = [ring_square(R_OUT, radial, depth, "brass", n=56)]
    # Raised rims on both faces and the inlaid script.
    for side in (-1, 1):
        parts.append(L.torus(R_OUT + radial / 2 - 0.012, 0.014, loc=(0, side * depth / 2, 0), rot=(90, 0, 0),
                             mat="metal_dark", n=56, m=4, square=True))
        parts.append(L.torus(R_OUT - radial / 2 + 0.012, 0.014, loc=(0, side * depth / 2, 0), rot=(90, 0, 0),
                             mat="metal_dark", n=56, m=4, square=True))
    parts += ring_inlays(R_OUT, depth, 24, seed=3, length=0.11, width=0.032)
    # Four clamp blocks at the cardinal points and the crown emitter pointing at the heart.
    for k in range(4):
        a = k * math.pi / 2
        parts.append(L.box((0.12, depth + 0.06, radial + 0.08), (math.cos(a) * R_OUT, 0, math.sin(a) * R_OUT),
                           rot=(0, -math.degrees(a) + 90, 0), mat="metal_dark", bev=0.02))
    top = R_OUT - radial / 2
    parts.append(L.lathe([(0.0, 0.0), (0.09, 0.0), (0.11, -0.06), (0.06, -0.3), (0.0, -0.42)], loc=(0, 0, top + 0.02),
                         mat="metal", n=8))
    parts.append(L.cyl(0.03, 0.08, loc=(0, 0, top - 0.42), mat="core_glow", n=8, r2=0.0))
    # Crown fins above the ring top: the silhouette's tip.
    for s in (-1, 0, 1):
        parts.append(L.prism([(-0.05, 0.0), (0.05, 0.0), (0.02, 0.26 - abs(s) * 0.08), (-0.02, 0.26 - abs(s) * 0.08)],
                             0.05, loc=(s * 0.14, 0, R_OUT + radial / 2 + 0.03), rot=(0, s * -12, 0), mat="brass",
                             bev=0.008))
    parts.append(L.sphere(0.05, loc=(0, 0, R_OUT + radial / 2 + 0.3), mat="core_glow", subdiv=1))
    ring = L.join(parts, "Ring_Outer")
    L.finish(ring, smooth_angle=35)
    ring.location = (0, 0, C_Z)
    return ring


def build_ring_mid():
    R, radial, depth = 0.84, 0.1, 0.1
    parts = [ring_square(R, radial, depth, "metal", n=44)]
    parts += ring_inlays(R, depth, 18, mat="rune_glow", seed=5, length=0.08, width=0.026)
    # Pivot pins out to the outer ring along its local X.
    for s in (-1, 1):
        parts.append(L.cyl(0.035, R_OUT - R - 0.07, loc=(s * (R + (R_OUT - R) / 2 - 0.03), 0, 0), rot=(0, 90, 0),
                           mat="brass", n=10))
        parts.append(L.cyl(0.06, 0.05, loc=(s * (R + 0.04), 0, 0), rot=(0, 90, 0), mat="metal_dark", n=10))
    ring = L.join(parts, "Ring_Mid")
    L.finish(ring, smooth_angle=35)
    ring.location = (0, 0, C_Z)
    ring.rotation_euler = (0, 0, math.radians(50))
    return ring


def build_ring_inner():
    R, radial, depth = 0.6, 0.08, 0.09
    parts = [ring_square(R, radial, depth, "brass", n=40)]
    parts.append(L.torus(R, 0.012, rot=(90, 0, 0), loc=(0, -depth / 2 - 0.004, 0), mat="core_glow", n=40, m=4,
                         square=True))
    parts.append(L.torus(R, 0.012, rot=(90, 0, 0), loc=(0, depth / 2 + 0.004, 0), mat="core_glow", n=40, m=4,
                         square=True))
    for s in (-1, 1):
        parts.append(L.cyl(0.03, 0.84 - R - 0.04, loc=(0, 0, s * (R + (0.84 - R) / 2 - 0.02)), mat="metal", n=8))
    ring = L.join(parts, "Ring_Inner")
    L.finish(ring, smooth_angle=35)
    ring.location = (0, 0, C_Z)
    ring.rotation_euler = (math.radians(65), 0, math.radians(50))
    return ring


def build_heart():
    """A double-pointed faceted crystal with an orbiting band of shards."""
    parts = [L.lathe([(0.0, -0.42), (0.16, -0.16), (0.24, -0.02), (0.22, 0.1), (0.13, 0.26), (0.0, 0.44)],
                     mat="core_glow", n=6)]
    rng = random.Random(12)
    for k in range(6):
        a = 2 * math.pi * k / 6 + 0.3
        r = 0.36
        sh = L.lathe([(0.0, -0.07), (0.04, 0.0), (0.0, 0.08)], mat="core_glow", n=4)
        L.place(sh, (math.cos(a) * r, math.sin(a) * r, rng.uniform(-0.08, 0.08)), (rng.uniform(-30, 30), 20, math.degrees(a)))
        parts.append(sh)
    heart = L.join(parts, "Heart")
    heart.data.transform(L.xform(scale=1.3))
    L.flat(heart)
    heart.location = (0, 0, C_Z)
    return heart


def build_reel(name, x, y, z, r=0.48):
    """A giant cassette reel: tape pack between two slotted flanges, toothed hub. Axis = Y."""
    parts = []
    w = 0.2
    parts.append(L.cyl(r * 0.78, w - 0.02, rot=(90, 0, 0), mat="tape", n=32))
    parts.append(L.cyl(r * 0.3, w + 0.04, rot=(90, 0, 0), mat="paint_yellow", n=16))
    for side in (-1, 1):
        flange = L.cyl(r, 0.025, loc=(0, side * w / 2, 0), rot=(90, 0, 0), mat="metal_dark", n=40)
        # Three window slots through each flange (booleans), like a cassette reel.
        cutters = []
        for k in range(3):
            a = 2 * math.pi * k / 3 + math.pi / 2
            c = L.cyl(r * 0.24, 0.2, loc=(math.cos(a) * r * 0.58, side * w / 2, math.sin(a) * r * 0.58), rot=(90, 0, 0),
                      mat="metal_dark", n=20)
            cutters.append(c)
        cut = L.join(cutters, "cutter")
        mod = flange.modifiers.new("Slots", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.object = cut
        mod.solver = "EXACT"
        flange = L.apply_modifiers(flange)
        bpy.data.objects.remove(cut, do_unlink=True)
        parts.append(L.bevel(flange, 0.006, 1, angle=40))
        parts.append(L.torus(r, 0.02, loc=(0, side * w / 2, 0), rot=(90, 0, 0), mat="brass", n=40, m=4, square=True))
    # Hub teeth (the cassette drive spline) on the front.
    for k in range(6):
        a = 2 * math.pi * k / 6
        parts.append(L.box((0.05, 0.05, 0.05), (math.cos(a) * r * 0.22, -w / 2 - 0.035, math.sin(a) * r * 0.22),
                           rot=(0, -math.degrees(a), 0), mat="metal_dark"))
    parts.append(L.cyl(0.07, 0.06, loc=(0, -w / 2 - 0.03, 0), rot=(90, 0, 0), mat="core_glow", n=12))
    reel = L.join(parts, name)
    L.finish(reel, smooth_angle=35)
    reel.location = (x, y, z)
    return reel


def build_body(reel_pos, reel_r):
    parts = []
    # ── Dais: three octagonal tiers of inscribed stone.
    parts.append(octagon_tier(1.47, 0.0, 0.16, "stone_dark", bev=0.03))
    parts.append(octagon_tier(1.24, 0.16, 0.3, "stone", bev=0.025))
    parts.append(octagon_tier(1.02, 0.3, 0.4, "metal_dark", bev=0.02, r_top=0.98))
    # Rune light along the first step (octagonal ring, eight segments).
    for k in range(8):
        a = math.radians(45 * k)
        mid = Vector((math.sin(a), -math.cos(a), 0)) * 1.355
        parts.append(L.box((1.355 * 2 * math.tan(math.radians(22.5)) - 0.1, 0.04, 0.012),
                           (mid.x, mid.y, 0.166), rot=(0, 0, math.degrees(a)), mat="rune_glow"))
    # Glyphs on the second tier's eight faces.
    for k in range(8):
        a = math.radians(45 * k)
        g = glyph_strokes(k, (-0.05, 0.19), 0.05, 0.018, 0.012, 0.0)
        gl = L.join(g, "glyph")
        L.place(gl, (0, 0, 0), (0, 0, 0))
        gl.data.transform(L.xform((math.sin(a) * 1.245, -math.cos(a) * 1.245, 0), (0, 0, math.degrees(a))))
        parts.append(gl)
    # Floor rune circle on the top platform.
    parts.append(L.torus(0.82, 0.018, loc=(0, 0, 0.405), mat="rune_glow", n=48, m=4, square=True))
    for k in range(12):
        a = 2 * math.pi * k / 12
        parts.append(L.box((0.14, 0.03, 0.012), (math.cos(a) * 0.7, math.sin(a) * 0.7, 0.405), rot=(0, 0, math.degrees(a)),
                           mat="rune_glow"))
    # Hazard trim on the front step face (the scavengers' addition).
    parts.append(L.hazard_box((0.9, 0.03, 0.1), (0, -1.47 + 0.0, 0.08), period=0.12))
    # ── Pylons holding the outer ring at its horizontal axis.
    for sx in (-1, 1):
        x = sx * (R_OUT + 0.22)
        py = L.prism([(-0.17, 0.0), (0.17, 0.0), (0.12, C_Z + 0.25 - 0.3), (-0.12, C_Z + 0.25 - 0.3)], 0.34,
                     loc=(x, 0, 0.3), mat="metal", bev=0.025)
        parts.append(py)
        parts.append(L.box((0.4, 0.42, 0.14), (x, 0, 0.37), mat="metal_dark", bev=0.02))
        parts.append(L.box((0.05, 0.03, 1.0), (x, -0.175, 0.95), mat="neon_glow"))
        parts += rivets([(x + dx, -0.176, z) for dx in (-0.09, 0.09) for z in (0.55, 1.0, 1.4)], r=0.016)
        # Bearing collar that the ring's clamp sits in.
        parts.append(L.cyl(0.13, 0.24, loc=(x - sx * 0.02, 0, C_Z), rot=(0, 90, 0), mat="metal_dark", n=16, bev=0.015))
        parts.append(L.cyl(0.07, 0.1, loc=(x + sx * 0.12, 0, C_Z), rot=(0, 90, 0), mat="brass", n=12))
        parts.append(L.cyl(0.05, 0.05, loc=(x + sx * 0.18, 0, C_Z), rot=(0, 90, 0), mat="core_glow", n=12))
    # ── Pedestal claw under the heart.
    parts.append(L.lathe([(0.0, 0.4), (0.3, 0.4), (0.3, 0.48), (0.16, 0.56), (0.12, 0.9), (0.18, 0.98), (0.0, 0.98)],
                         mat="metal", n=8))
    for k in range(3):
        a = 2 * math.pi * k / 3 + math.pi / 2
        d = Vector((math.cos(a), math.sin(a), 0))
        pts = [tuple(d * 0.12 + Vector((0, 0, 0.95))), tuple(d * 0.3 + Vector((0, 0, 1.08))),
               tuple(d * 0.24 + Vector((0, 0, 1.22)))]
        parts.append(L.tube(pts, 0.035, mat="brass", res=1, radii=[1.0, 0.8, 0.5]))
    # ── Tape path: from the left reel under through the playhead to the right reel.
    (lx, ly, lz), (rx, ry, rz) = reel_pos
    pack = reel_r * 0.78
    head_z = 0.62
    guides = [(-0.42, ly, head_z), (0.42, ly, head_z)]
    for gx, gy, gz in guides:
        parts.append(L.cyl(0.06, 0.24, loc=(gx, gy, gz), rot=(90, 0, 0), mat="brass", n=14))
        parts.append(L.cyl(0.025, 0.36, loc=(gx, gy + 0.06, gz - 0.12), mat="metal_dark", n=8))
    tape_pts = [(lx + 0.05, ly, lz - pack), (-0.42, ly, head_z - 0.06), (0.0, ly, head_z - 0.07),
                (0.42, ly, head_z - 0.06), (rx - 0.05, ry, rz - pack)]
    tape = L.ribbon(tape_pts, 0.16, 0.012, mat="tape", resolution_u=10)
    tape.data.transform(L.xform(rot=(0, 0, 0)))
    parts.append(tape)
    # Playhead block touching the tape from below, with a glowing gap.
    parts.append(L.box((0.3, 0.24, 0.14), (0, ly, head_z - 0.15), mat="brass", bev=0.02, taper=(0.75, 1.0)))
    parts.append(L.box((0.03, 0.26, 0.02), (0, ly, head_z - 0.075), mat="core_glow"))
    parts.append(L.box((0.2, 0.2, 0.18), (0, ly + 0.02, head_z - 0.32), mat="metal_dark", bev=0.02))
    # Reel spindles and mounting brackets down into the dais.
    for (x, y, z) in reel_pos:
        parts.append(L.cyl(0.05, 0.3, loc=(x, y + 0.2, z), rot=(90, 0, 0), mat="metal", n=10))
        parts.append(L.prism([(-0.16, 0.0), (0.16, 0.0), (0.07, z - 0.28 + 0.05), (-0.07, z - 0.28 + 0.05)], 0.12,
                             loc=(x, y + 0.34, 0.28), mat="metal_dark", bev=0.015))
        parts.append(L.cyl(0.09, 0.08, loc=(x, y + 0.32, z), rot=(90, 0, 0), mat="metal_dark", n=12))
    # ── Back machinery: capacitor tubes and conduits feeding the pylons.
    for sx in (-1, 1):
        x = sx * 0.62
        parts.append(L.cyl(0.13, 0.12, loc=(x, 0.78, 0.46), mat="metal_dark", n=12, bev=0.01))
        parts.append(L.cyl(0.085, 1.1, loc=(x, 0.78, 1.07), mat="neon_glow", n=12))
        for z in (0.75, 1.15, 1.55):
            parts.append(L.torus(0.095, 0.018, loc=(x, 0.78, z), mat="brass", n=14, m=4, square=True))
        parts.append(L.cyl(0.12, 0.1, loc=(x, 0.78, 1.66), mat="metal_dark", n=12, bev=0.01))
        parts.append(L.tube([(x, 0.78, 1.7), (x + sx * 0.2, 0.7, 1.95), (sx * (R_OUT + 0.22), 0.25, 1.95),
                             (sx * (R_OUT + 0.22), 0.12, C_Z + 0.12)], 0.04, mat="rubber", res=1))
    parts.append(L.box((1.0, 0.3, 0.3), (0, 0.85, 0.55), mat="metal", bev=0.03))
    for k in range(5):
        parts.append(L.box((0.12, 0.02, 0.18), (-0.36 + k * 0.18, 0.69, 0.55), mat="metal_dark"))
    # Scavenger touch: a yellow cable and a little cassette deck patched into the dais front.
    parts.append(L.box((0.26, 0.14, 0.09), (0.62, -1.18, 0.345), mat="paint_yellow", bev=0.015))
    parts.append(L.box((0.14, 0.012, 0.04), (0.62, -1.252, 0.35), mat="hazard_dark"))
    parts.append(L.tube([(0.74, -1.12, 0.33), (0.92, -0.9, 0.42), (1.02, -0.5, 0.45), (1.1, -0.18, 0.6)], 0.018,
                        mat="rubber", res=1))
    body = L.join(parts, "Body")
    return L.finish(body, smooth_angle=35)


def time_machine():
    reel_r = 0.48
    ry = -0.62
    reel_pos = [(-0.86, ry, 0.98), (0.86, ry, 0.98)]
    body = build_body(reel_pos, reel_r)
    reels = [build_reel("Reel_L", *reel_pos[0], r=reel_r), build_reel("Reel_R", *reel_pos[1], r=reel_r)]
    rings = [build_ring_outer(), build_ring_mid(), build_ring_inner()]
    heart = build_heart()
    return [body] + rings + [heart] + reels
