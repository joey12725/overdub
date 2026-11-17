"""
The six melee weapons (data/gear.json, slot "melee"). Authoring space is Godot space:
origin at the grip centre, business end +Y, edge / striking face toward +Z, thin axis X.
Each builder returns a spec: {"objs": [mesh/armature objects], "empties": [...], ...}.
Concepts: docs/reference/generated/weapons/<id>.png
"""
from __future__ import annotations

import math

import bmesh
import bpy
from mathutils import Vector

import wlib as L
from wlib import (band, bevel, bolt_outline, box, copy, cyl, empty, hexbolt, join, knob, lathe,
                  loft, mirror, move, prism, ribbon, ring, rounded_rect, screw, smooth_path, sphere,
                  star, sweep, tube, wrap)


# ───────────────────────────── decals (stickers as geometry) ─────────────────────────────

def rot2(outline, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return [(u * c - v * s, u * s + v * c) for u, v in outline]


def sc2(outline, k, kv=None):
    kv = k if kv is None else kv
    return [(u * k, v * kv) for u, v in outline]


def off2(outline, du, dv):
    return [(u + du, v + dv) for u, v in outline]


def decal(outline, loc, n="X", mat="weapon_accent", layer=1, t=0.0012):
    """A sticker: thin prism lying on a face whose outward normal is n (X, -X, Y, -Y, Z, -Z).
    Outline axes: X -> (u=+Z, v=+Y); Z -> (u=+X, v=+Y); Y -> (u=+X, v=+Z). Layers stack outward."""
    ax = n[-1]
    sgn = -1.0 if n.startswith("-") else 1.0
    d = sgn * (layer - 0.5) * t
    o = [0, 0, 0]
    o["XYZ".index(ax)] = d
    return prism(outline, t, (loc[0] + o[0], loc[1] + o[1], loc[2] + o[2]), ax, mat)


def cassette_decal(loc, n="X", w=0.06, deg=0.0, body="weapon_accent2", layer=1):
    h = w * 0.62
    parts = [decal(rot2(rounded_rect(w, h, w * 0.08, 2), deg), loc, n, "weapon_paper", layer),
             decal(rot2(rounded_rect(w * 0.86, h * 0.78, w * 0.06, 2), deg), loc, n, body, layer + 1),
             decal(rot2(rounded_rect(w * 0.6, h * 0.3, w * 0.04, 2), deg), loc, n, "weapon_black", layer + 2)]
    for sx in (-1, 1):
        hub = off2(sc2(star(1, 1, 4, 45), w * 0.055), sx * w * 0.17, 0)
        parts.append(decal(rot2(hub, deg), loc, n, "weapon_paper", layer + 3))
    return parts


def star_decal(loc, n="X", r=0.03, deg=0.0, mat="weapon_accent", rim="weapon_black", layer=1):
    return [decal(rot2(star(r * 1.25, r * 0.6), deg), loc, n, rim, layer),
            decal(rot2(star(r, r * 0.45), deg), loc, n, mat, layer + 1)]


def bolt_decal(loc, n="X", s=0.05, deg=0.0, mat="weapon_accent", layer=1):
    return [decal(rot2(bolt_outline(s), deg), loc, n, mat, layer)]


def circle(r, n=16):
    return [(r * math.cos(2 * math.pi * i / n), r * math.sin(2 * math.pi * i / n)) for i in range(n)]


def smiley_decal(loc, n="X", r=0.018, layer=1):
    return [decal(circle(r * 1.15, 12), loc, n, "weapon_black", layer),
            decal(circle(r, 12), loc, n, "weapon_accent", layer + 1),
            decal(off2(circle(r * 0.16, 6), -r * 0.35, r * 0.25), loc, n, "weapon_black", layer + 2),
            decal(off2(circle(r * 0.16, 6), r * 0.35, r * 0.25), loc, n, "weapon_black", layer + 2),
            decal(off2(sc2(rounded_rect(1.1, 0.26, 0.12, 1), r), 0, -r * 0.38), loc, n, "weapon_black", layer + 2)]


def vial(loc, axis="Y", r=0.012, h=0.06, glow="weapon_glow", cap="weapon_accent"):
    """A glowing capsule with caps (the cyan/magenta tubes on Moxie's belt)."""
    d = {"X": (1, 0, 0), "Y": (0, 1, 0), "Z": (0, 0, 1)}[axis]
    parts = [cyl(r, h, loc, axis, glow, n=10)]
    for s in (-1, 1):
        p = tuple(loc[i] + d[i] * s * (h / 2 + r * 0.3) for i in range(3))
        parts.append(cyl(r * 1.25, r * 0.7, p, axis, cap, n=10, bev=r * 0.15))
    return parts


def ribbon_tail(y, mat="weapon_accent2", side=1.0, length=0.16, r=0.024):
    """A knotted cloth strip hanging from a shaft at height y."""
    parts = [band(r - 0.003, y, 0.022, mat, t=0.006)]
    for k, (dx, ln) in enumerate(((0.012, length), (-0.014, length * 0.72))):
        pts = smooth_path([(dx, y, -r * side), (dx * 1.6, y - ln * 0.25, -(r + 0.035) * side),
                           (dx * 2.2, y - ln * 0.62, -(r + 0.03) * side), (dx * 2.0, y - ln, -(r + 0.05) * side)], 3)
        parts.append(ribbon(pts, 0.024, 0.004, mat, up=(0, 0, 1), scale=None))
    parts.append(box((0.03, 0.026, 0.02), (0, y, -(r + 0.006) * side), mat=mat, bev=0.005))
    return parts


# ───────────────────────────── splice blade ─────────────────────────────

def splice_blade():
    """Tape-splicing knife grown into a broad single-edged short sword: straight spine, deep belly,
    45-degree splice-cut tip. Guard = aluminium splicing block; cyan waveform capsule in the fuller."""
    P = []
    zb = -0.06
    st = [  # y, edge z, thickness
        (0.150, 0.074, 0.016), (0.26, 0.084, 0.016), (0.40, 0.092, 0.016), (0.52, 0.092, 0.016),
        (0.60, 0.084, 0.015), (0.67, 0.062, 0.013), (0.73, 0.026, 0.011), (0.775, -0.012, 0.008), (0.805, -0.052, 0.004)]
    body, edge = [], []
    for (y, ze, t) in st:
        zs = max(zb + 0.003, ze - 0.044)
        body.append([(-t / 2, y, zb), (-t / 2, y, zs), (t / 2, y, zs), (t / 2, y, zb)])
        edge.append([(-t / 2, y, zs), (0, y, ze), (t / 2, y, zs)])
    P.append(loft(body, "weapon_dark"))
    P.append(loft(edge, "weapon_main"))
    # painted spine
    P.append(box((0.021, 0.47, 0.012), (0, 0.39, zb - 0.002), mat="weapon_accent", bev=0.003))
    for y in (0.2, 0.34, 0.48, 0.6):
        P.append(box((0.025, 0.014, 0.018), (0, y, zb - 0.002), mat="weapon_steel", bev=0.002))
    # stickers, both faces
    for n, s in (("X", 1), ("-X", -1)):
        x = s * 0.008
        P += bolt_decal((x, 0.50, 0.004), n, 0.062, 8 * s, "weapon_accent")
        P += cassette_decal((x, 0.375, -0.012), n, 0.062, 90)
        P += star_decal((x, 0.305, 0.022), n, 0.017)
        P += smiley_decal((x, 0.60, -0.022), n, 0.014)
        # ground-edge scratches
        P.append(decal([(-0.004, -0.03), (0.0, -0.03), (0.012, 0.03), (0.008, 0.03)], (x * 0.6, 0.3, 0.05), n, "weapon_paper", 1, 0.0008))
    # magenta tape wraps near the tip
    for (y, deg, w) in ((0.655, 14, 0.024), (0.668, -18, 0.02), (0.215, 0, 0.016)):
        ze = 0.07 if y > 0.3 else 0.08
        P.append(box((0.021, w, ze - zb + 0.004), (0, y, (ze + zb) / 2 - 0.004), rot=(deg, 0, 0), mat="weapon_accent2", bev=0.002))
    # waveform capsule clamped in the fuller + its feed pipe
    P += vial((0, 0.245, -0.004), "Y", 0.017, 0.062)
    for s in (-1, 1):
        for k, h in enumerate((0.012, 0.03, 0.018, 0.04, 0.022, 0.012)):
            P.append(box((0.002, 0.004, h * 0.55), (s * 0.0176, 0.222 + k * 0.009, -0.004), mat="weapon_paper"))
    P.append(tube(smooth_path([(0, 0.16, -0.066), (0, 0.2, -0.082), (0, 0.27, -0.086), (0, 0.33, -0.074), (0, 0.345, -0.058)], 3),
                  0.0055, "weapon_accent", n=6, up=(1, 0, 0)))
    # guard: splicing block
    P.append(box((0.05, 0.062, 0.2), (0, 0.117, 0.008), mat="weapon_metal", bev=0.006))
    for z in (-0.104, 0.12):
        P.append(box((0.058, 0.07, 0.034), (0, 0.117, z), mat="weapon_accent", bev=0.007))
        for s in (-1, 1):
            P.append(screw(0.007, (s * 0.029, 0.117, z), "X" if s > 0 else "-X"))
    for s, n in ((1, "X"), (-1, "-X")):
        x = s * 0.025
        P.append(box((0.004, 0.016, 0.18), (x, 0.117, 0.008), mat="weapon_black"))             # tape channel
        P.append(box((0.005, 0.07, 0.007), (x, 0.117, 0.035), rot=(45 * s, 0, 0), mat="weapon_black"))   # 45 cut
        P.append(box((0.005, 0.064, 0.007), (x, 0.117, -0.03), mat="weapon_black"))             # 90 cut
        for (y, z) in ((0.095, -0.07), (0.139, -0.07), (0.095, 0.086), (0.139, 0.086)):
            P.append(screw(0.0055, (x, y, z), n))
    # grip
    P += wrap(0.0175, -0.072, 0.074, 5, "weapon_grip", 0.016, 0.0035)
    P.append(band(0.019, 0.012, 0.02, "weapon_accent2"))
    P.append(cyl(0.023, 0.016, (0, 0.08, 0), "Y", "weapon_steel", n=12, bev=0.003))
    # pommel: yellow cap, steel D-ring, cassette charm
    P.append(cyl(0.024, 0.026, (0, -0.084, 0), "Y", "weapon_accent", n=10, bev=0.005))
    P.append(ring(0.024, 0.006, (0, -0.116, 0), "X", "weapon_steel", n=14, m=6))
    P.append(tube(smooth_path([(0, -0.138, 0.004), (0.004, -0.16, 0.014), (0, -0.182, 0.018)], 3), 0.003, "weapon_steel", n=5))
    P.append(box((0.012, 0.062, 0.042), (0, -0.212, 0.02), rot=(8, 0, 0), mat="weapon_accent2", bev=0.004))
    for s in (-1, 1):
        P.append(box((0.003, 0.03, 0.03), (s * 0.006, -0.212, 0.02), rot=(8, 0, 0), mat="weapon_paper"))
        P.append(box((0.004, 0.012, 0.022), (s * 0.0065, -0.214, 0.02), rot=(8, 0, 0), mat="weapon_black"))
    w = join(P, "Weapon")
    return {"objs": [w], "empties": [empty("Grip", (0, 0, 0)), empty("Tip", (0, 0.805, -0.052)),
                                     empty("TrailStart", (0, 0.16, 0.074)), empty("TrailEnd", (0, 0.775, -0.012))],
            "style": "blade", "hands": 1}


# ───────────────────────────── stylus shiv ─────────────────────────────

def stylus_shiv():
    """A tone arm held as a dagger: counterweight pommel, gimbal ring guard, thin arm tube, a boxy
    cartridge headshell with its finger lift, and the stylus filed out into a long needle."""
    P = []
    # counterweight pommel with dial marks
    P.append(lathe([(0, -0.142), (0.02, -0.142), (0.026, -0.136), (0.026, -0.094), (0.021, -0.088), (0.012, -0.086), (0, -0.086)], axis="Y", mat="weapon_metal", n=14))
    P.append(band(0.0262, -0.127, 0.008, "weapon_accent", n=14))
    for k in range(10):
        a = 2 * math.pi * k / 10
        P.append(box((0.003, 0.014, 0.003), (0.027 * math.cos(a), -0.108, 0.027 * math.sin(a)), rot=(0, -math.degrees(a), 0), mat="weapon_black"))
    # arm tube, straight through the grip then a slight S toward the headshell
    arm = [(0, -0.09, 0), (0, 0.06, 0), (0, 0.11, 0), (0, 0.155, 0.006), (0, 0.195, 0.012)]
    P.append(tube(smooth_path(arm, 3), 0.0075, "weapon_metal", n=8))
    # grip sleeve
    P += wrap(0.0165, -0.078, 0.052, 5, "weapon_grip", 0.013, 0.003)
    P.append(band(0.0178, -0.07, 0.012, "weapon_accent2"))
    P.append(band(0.0178, 0.044, 0.012, "weapon_accent2"))
    # gimbal / pivot ring: the guard
    P.append(ring(0.03, 0.0065, (0, 0.07, 0), "Y", "weapon_accent", n=16, m=6))
    P.append(cyl(0.013, 0.02, (0, 0.07, 0), "Y", "weapon_steel", n=10, bev=0.003))
    for a in (0, 90, 180, 270):
        r = math.radians(a)
        P.append(cyl(0.004, 0.02, (0.02 * math.cos(r), 0.07, 0.02 * math.sin(r)), "X", "weapon_steel", n=6, rot=(0, -a, 0)))
    # anti-skate weight on a wire
    P.append(tube(smooth_path([(0.03, 0.07, 0), (0.046, 0.06, 0), (0.05, 0.035, 0)], 3), 0.002, "weapon_steel", n=4))
    P.append(sphere(0.008, (0.05, 0.03, 0), "weapon_accent2", n=8))
    # headshell: plate + cartridge + finger lift
    P.append(box((0.03, 0.078, 0.008), (0, 0.232, -0.002), mat="weapon_dark", bev=0.003))
    P.append(box((0.024, 0.05, 0.03), (0, 0.24, 0.018), mat="weapon_main", bev=0.004))
    P.append(box((0.026, 0.012, 0.032), (0, 0.262, 0.018), mat="weapon_accent", bev=0.003))
    P.append(box((0.027, 0.03, 0.006), (0, 0.238, 0.03), mat="weapon_accent2"))
    for x in (-0.009, 0.009):
        P.append(screw(0.004, (x, 0.222, -0.006), "-Z"))
        P.append(screw(0.004, (x, 0.25, -0.006), "-Z"))
    lift = smooth_path([(0.014, 0.25, -0.002), (0.03, 0.262, -0.004), (0.04, 0.285, -0.012), (0.044, 0.3, -0.026)], 3)
    P.append(ribbon(lift, 0.004, 0.009, "weapon_metal", up=(0, 0, 1)))
    # cartridge wires
    for k, (m, dx) in enumerate((("weapon_accent", -0.008), ("weapon_accent2", -0.003), ("weapon_glow", 0.003), ("weapon_paper", 0.008))):
        P.append(tube(smooth_path([(dx, 0.214, 0.014), (dx * 1.6, 0.196, 0.024 + 0.003 * k), (dx * 0.6, 0.178, 0.014)], 3), 0.0016, m, n=4))
    # the needle: cantilever collar then a long filed spike, canted toward +Z
    P.append(cyl(0.008, 0.016, (0, 0.274, 0.02), "Y", "weapon_steel", n=8, bev=0.002))
    spike = [(0, 0.28, 0.02), (0, 0.33, 0.021), (0, 0.38, 0.022), (0, 0.425, 0.023)]
    P.append(tube(spike, 0.0062, "weapon_metal", n=6, scale=[1.0, 0.8, 0.5, 0.06]))
    P.append(lathe([(0, 0.398), (0.006, 0.408), (0, 0.432)], (0, 0, 0.0228), "Y", "weapon_pink_glow", n=4))
    P.append(ring(0.0085, 0.0022, (0, 0.3, 0.0205), "Y", "weapon_pink_glow", n=8, m=4))
    w = join(P, "Weapon")
    return {"objs": [w], "empties": [empty("Grip", (0, 0, 0)), empty("Tip", (0, 0.432, 0.023)),
                                     empty("TrailStart", (0, 0.275, 0.02)), empty("TrailEnd", (0, 0.432, 0.023))],
            "style": "shiv", "hands": 1}


# ───────────────────────────── amp sledge ─────────────────────────────

def amp_sledge():
    """Guitar amp head clamped across a scaffold pole. Long axis of the amp = strike axis (Z):
    steel-plated striking face at +Z, glowing valves in a cage at -Z, grille and knobs on +X."""
    P = []
    hy, hx, hz = 0.89, 0.27, 0.48          # head centre height, width (X), length (Z)
    hh = 0.29                              # head height (Y)
    y0, y1 = hy - hh / 2, hy + hh / 2
    # pole
    P.append(cyl(0.023, 1.0, (0, 0.28, 0), "Y", "weapon_steel", n=12))
    P += wrap(0.0235, 0.3, 0.52, 4, "weapon_accent", 0.03, 0.002, core=False)          # hazard stripes
    P += wrap(0.025, 0.1, 0.25, 5, "weapon_paper", 0.02, 0.0035)                         # bandage tape
    P += wrap(0.0255, -0.13, 0.1, 7, "weapon_grip", 0.018, 0.0035)                       # grip
    P += ribbon_tail(-0.15, "weapon_accent2", 1.0, 0.2, 0.024)
    P.append(cyl(0.027, 0.045, (0, -0.2, 0), "Y", "weapon_accent", n=12, bev=0.005))
    P.append(ring(0.02, 0.005, (0, -0.24, 0), "X", "weapon_steel", n=12, m=6))
    for y in (0.54, 0.08):
        P.append(cyl(0.026, 0.016, (0, y, 0), "Y", "weapon_metal", n=12, bev=0.003))
    # scaffold couplers under the head
    for y in (0.60, 0.69):
        P.append(box((0.07, 0.05, 0.075), (0, y, 0), mat="weapon_metal", bev=0.008))
        P.append(cyl(0.006, 0.15, (0, y, 0.0), "Z", "weapon_steel", n=6))
        for z in (-0.066, 0.066):
            P.append(hexbolt(0.013, 0.014, (0, y, z), "Z"))
        P.append(box((0.076, 0.012, 0.03), (0, y, 0), mat="weapon_steel", bev=0.002))
    P.append(box((0.1, 0.022, 0.2), (0, y0 - 0.011, 0), mat="weapon_steel", bev=0.004))   # saddle plate
    for z in (-0.07, 0.07):
        for x in (-0.035, 0.035):
            P.append(hexbolt(0.008, 0.01, (x, y0 - 0.026, z), "Y"))
    # amp body
    P.append(box((hx, hh, hz), (0, hy, 0), mat="weapon_main", bev=0.014, seg=2))
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                c = (sx * (hx / 2 - 0.016), hy + sy * (hh / 2 - 0.016), sz * (hz / 2 - 0.016))
                P.append(box((0.042, 0.042, 0.042), c, mat="weapon_metal", bev=0.009))
                P.append(screw(0.005, (c[0] + sx * 0.021, c[1], c[2]), "X" if sx > 0 else "-X"))
    # +X face: grille cloth, star, control strip
    fx = hx / 2
    P.append(box((0.008, 0.15, hz - 0.075), (fx, hy + 0.04, 0), mat="weapon_black", bev=0.003))
    P += [decal(sc2(star(1, 0.5), 0.07), (fx + 0.004, hy + 0.04, -0.03), "X", "weapon_accent", 1),
          decal(sc2(star(1, 0.5), 0.046), (fx + 0.004, hy + 0.04, -0.03), "X", "weapon_black", 2)]
    P.append(box((0.008, 0.07, hz - 0.075), (fx, hy - 0.085, 0), mat="weapon_metal", bev=0.003))
    for k in range(5):
        P += knob(0.014, 0.018, (fx + 0.004, hy - 0.085, -0.15 + k * 0.056), "X", "weapon_black", "weapon_paper", n=10)
    P.append(box((0.008, 0.034, 0.03), (fx + 0.003, hy - 0.085, 0.172), mat="weapon_hot_glow", bev=0.003))
    # -X face: back panel with vents and stickers
    bx = -hx / 2
    P.append(box((0.008, hh - 0.075, hz - 0.075), (bx, hy, 0), mat="weapon_dark", bev=0.003))
    for k in range(6):
        P.append(box((0.006, 0.085, 0.014), (bx - 0.003, hy - 0.04, -0.17 + k * 0.03), mat="weapon_black"))
    P += cassette_decal((bx - 0.004, hy + 0.045, 0.08), "-X", 0.08, 8)
    P += bolt_decal((bx - 0.004, hy - 0.03, 0.105), "-X", 0.04, -10, "weapon_accent2")
    P.append(decal(rot2(rounded_rect(0.09, 0.022, 0.004, 1), 28), (bx - 0.004, hy + 0.05, -0.06), "-X", "weapon_paper", 1))
    # top: carry handle, star sticker
    hpts = smooth_path([(0, y1 + 0.004, -0.09), (0, y1 + 0.04, -0.07), (0, y1 + 0.05, 0), (0, y1 + 0.04, 0.07), (0, y1 + 0.004, 0.09)], 4)
    P.append(ribbon(hpts, 0.034, 0.012, "weapon_black", up=(0, 1, 0)))
    for z in (-0.09, 0.09):
        P.append(box((0.05, 0.012, 0.034), (0, y1 + 0.005, z), mat="weapon_metal", bev=0.003))
    P += star_decal((0.07, y1, 0.13), "Y", 0.022)
    P.append(decal(rot2(rounded_rect(0.1, 0.024, 0.004, 1), 30), (-0.05, y1, -0.11), "Y", "weapon_paper", 1))
    # +Z striking face: steel plate, bolts, wear chevron
    fz = hz / 2
    P.append(box((hx - 0.05, hh - 0.05, 0.03), (0, hy, fz + 0.008), mat="weapon_steel", bev=0.008))
    P.append(box((hx - 0.1, hh - 0.1, 0.012), (0, hy, fz + 0.026), mat="weapon_metal", bev=0.004))
    for sx in (-1, 1):
        for sy in (-1, 1):
            P.append(hexbolt(0.011, 0.012, (sx * (hx / 2 - 0.05), hy + sy * (hh / 2 - 0.05), fz + 0.024), "Z"))
    P += [decal(sc2(star(1, 0.5), 0.05), (0, hy, fz + 0.032), "Z", "weapon_accent", 1)]
    # -Z end: valves in a wire cage
    bz = -hz / 2
    P.append(box((hx - 0.06, hh - 0.07, 0.016), (0, hy, bz - 0.006), mat="weapon_dark", bev=0.004))
    for x in (-0.058, 0.058):
        P.append(cyl(0.03, 0.016, (x, hy + 0.01, bz - 0.02), "Z", "weapon_steel", n=10, bev=0.003))
        P.append(lathe([(0, 0), (0.024, 0), (0.024, 0.058), (0.016, 0.074), (0.006, 0.08), (0, 0.08)], (x, hy + 0.01, bz - 0.026), "-Z", "weapon_hot_glow", n=10))
        P.append(cyl(0.008, 0.05, (x, hy + 0.01, bz - 0.055), "Z", "weapon_paper", n=6))
    for yy in (hy - 0.055, hy + 0.075):
        P.append(tube([(-0.11, yy, bz), (-0.11, yy, bz - 0.11), (0.11, yy, bz - 0.11), (0.11, yy, bz)], 0.004, "weapon_steel", n=5, up=(0, 1, 0)))
    for x in (-0.11, 0, 0.11):
        P.append(tube([(x, hy - 0.055, bz - 0.11), (x, hy + 0.075, bz - 0.11)], 0.004, "weapon_steel", n=5, up=(1, 0, 0)))
    # guitar cable: jack on the amp underside, coiled round the pole
    P.append(cyl(0.012, 0.03, (0.06, y0 - 0.012, 0.1), "Y", "weapon_dark", n=8, bev=0.002))
    cab = [(0.06, y0 - 0.03, 0.1), (0.07, y0 - 0.08, 0.085), (0.05, 0.66, 0.05)] + L.helix(0.03, 0.62, 0.36, 2.5, "Y", steps=8, phase=0.6)
    P.append(tube(smooth_path(cab, 2), 0.0055, "weapon_accent", n=5, up=(1, 0, 0)))
    w = join(P, "Weapon")
    return {"objs": [w], "empties": [empty("Grip", (0, 0, 0)), empty("Grip2", (0, 0.36, 0)),
                                     empty("Tip", (0, hy, fz + 0.032)),
                                     empty("TrailStart", (0, y0 + 0.01, fz + 0.03)), empty("TrailEnd", (0, y1 - 0.01, fz + 0.03))],
            "style": "blunt", "hands": 2}


# ───────────────────────────── reel lash ─────────────────────────────

LASH_BONES = 10
LASH_LEN = 1.80
LASH_W = 0.046
LASH_T = 0.007


def lash_twist(s):
    """The tape's rest twist about its own length (radians): flat (width along X) at the reel and
    at the tip, one full turn in between so it shows from every camera."""
    return math.pi * 2.0 * (s * s * (3 - 2 * s))



def lash_path(s):
    """Rest shape of the lash (s = 0..1 along it): out along +Y with a shallow S in the YZ plane."""
    y = 0.34 + LASH_LEN * s
    z = 0.04 + 0.09 * math.sin(s * math.pi * 2.0) * (0.35 + 0.65 * s) - 0.03 * s
    return Vector((0, y, z))


def reel_lash():
    """A hand reel of steel-cored tape. Inline handle; open metal reel (axis X) above the grip with
    its crank; cassette drive pack behind; guide arm and eyelet; the lash is skinned to a bone chain."""
    P = []
    # handle
    P += wrap(0.0185, -0.075, 0.07, 5, "weapon_paper", 0.018, 0.0035)
    P.append(cyl(0.024, 0.03, (0, -0.088, 0), "Y", "weapon_accent", n=10, bev=0.005))
    P.append(ring(0.019, 0.005, (0, -0.118, 0), "X", "weapon_steel", n=12, m=6))
    P += vial((0, -0.01, -0.03), "Y", 0.009, 0.06, "weapon_pink_glow", "weapon_dark")
    P.append(cyl(0.024, 0.018, (0, 0.078, 0), "Y", "weapon_dark", n=10, bev=0.003))
    # frame block + cassette drive pack on the back (-Z)
    P.append(box((0.05, 0.12, 0.05), (0, 0.145, -0.012), mat="weapon_dark", bev=0.006))
    P.append(box((0.07, 0.115, 0.03), (0, 0.15, -0.062), mat="weapon_steel", bev=0.005))
    P.append(box((0.076, 0.1, 0.014), (0, 0.15, -0.084), mat="weapon_paper", bev=0.003))
    P.append(box((0.064, 0.05, 0.006), (0, 0.158, -0.092), mat="weapon_black", bev=0.002))
    for y in (0.14, 0.176):
        P.append(cyl(0.011, 0.006, (0, y, -0.096), "Z", "weapon_pink_glow", n=8))
    P.append(box((0.086, 0.022, 0.05), (0, 0.128, -0.07), mat="weapon_paper", bev=0.003))          # tape strap
    P += star_decal((0.0, 0.108, -0.0915), "-Z", 0.012)
    P += vial((0.0, 0.215, -0.062), "X", 0.009, 0.05, "weapon_glow", "weapon_accent")
    # reel: two flanges with three windows, tape pack between, hub, crank on +X
    rc = (0, 0.2, 0.05)
    R = 0.098
    for sx in (-1, 1):
        fl = lathe([(0, 0), (R, 0), (R, 0.005), (0, 0.005)], (sx * 0.03 - 0.0025, rc[1], rc[2]), "X", "weapon_metal", n=30)
        cuts = []
        for k in range(3):
            a0 = 90 + k * 120 + 22
            pts = [(R * 0.82 * math.cos(math.radians(a0 + t * 76 / 6)), R * 0.82 * math.sin(math.radians(a0 + t * 76 / 6))) for t in range(7)]
            pts += [(R * 0.38 * math.cos(math.radians(a0 + 76 - t * 76 / 3)), R * 0.38 * math.sin(math.radians(a0 + 76 - t * 76 / 3))) for t in range(4)]
            cuts.append(prism(pts, 0.03, (sx * 0.03, rc[1], rc[2]), "X", "weapon_dark"))
        L.boolean(fl, cuts)
        P.append(fl)
        P.append(cyl(0.03, 0.008, (sx * 0.036, rc[1], rc[2]), "X", "weapon_accent", n=12, bev=0.002))
        for k in range(3):
            a = math.radians(30 + k * 120)
            P.append(screw(0.004, (sx * 0.0325, rc[1] + 0.088 * math.sin(a), rc[2] + 0.088 * math.cos(a)), "X" if sx > 0 else "-X"))
    P.append(cyl(R * 0.74, 0.05, rc, "X", "weapon_tape", n=24))
    P.append(cyl(0.022, 0.09, rc, "X", "weapon_steel", n=10))
    # crank
    P.append(box((0.008, 0.016, 0.085), (0.05, rc[1] - 0.012, rc[2] + 0.03), rot=(-22, 0, 0), mat="weapon_metal", bev=0.003))
    P.append(cyl(0.012, 0.012, (0.05, rc[1], rc[2]), "X", "weapon_steel", n=8, bev=0.002))
    P.append(cyl(0.012, 0.05, (0.08, rc[1] - 0.027, rc[2] + 0.066), "X", "weapon_accent", n=10, bev=0.004))
    # yoke under the reel and the guide arm to the eyelet
    P.append(box((0.094, 0.03, 0.03), (0, 0.118, 0.022), mat="weapon_accent", bev=0.005))
    arm = [(0.0, 0.15, 0.105), (0, 0.24, 0.155), (0, 0.3, 0.13), (0, 0.33, 0.085)]
    for sx in (-1, 1):
        P.append(ribbon(smooth_path([(sx * 0.044, p[1], p[2]) for p in [(0, 0.12, 0.03), (0, 0.2, 0.05)]], 2), 0.02, 0.006, "weapon_accent", up=(1, 0, 0)))
    P.append(ribbon(smooth_path([(0.044, 0.2, 0.05), (0.044, 0.27, 0.06), (0.04, 0.32, 0.042)], 3), 0.016, 0.006, "weapon_accent", up=(1, 0, 0)))
    P.append(ribbon(smooth_path([(-0.044, 0.2, 0.05), (-0.044, 0.27, 0.06), (-0.04, 0.32, 0.042)], 3), 0.016, 0.006, "weapon_accent", up=(1, 0, 0)))
    P.append(cyl(0.013, 0.076, (0, 0.325, 0.024), "X", "weapon_metal", n=12, bev=0.003))   # guide roller
    for sx in (-1, 1):
        P.append(cyl(0.02, 0.006, (sx * 0.04, 0.325, 0.03), "X", "weapon_steel", n=12))
    # tape leaving the pack over the roller (static part)
    feed = smooth_path([(0, 0.2, 0.05 + R * 0.74), (0, 0.26, 0.108), (0, 0.31, 0.066), (0, 0.34, 0.04)], 3)
    P.append(ribbon(feed, LASH_W, 0.005, "weapon_tape", up=(0, 0, 1)))
    P += bolt_decal((0.0256, 0.13, -0.012), "X", 0.02, -20)
    handle = join(P, "Weapon")

    # the lash: ribbon along lash_path, skinned
    n_seg = LASH_BONES * 4
    secs = []
    for i in range(n_seg + 1):
        u = i / n_seg
        p = lash_path(u)
        t = (lash_path(min(1.0, u + 0.005)) - lash_path(max(0.0, u - 0.005))).normalized()
        side = Vector((1, 0, 0))
        upv = t.cross(side).normalized()
        tw = lash_twist(u)
        a_ = side * math.cos(tw) + upv * math.sin(tw)
        b_ = upv * math.cos(tw) - side * math.sin(tw)
        w_, h_ = LASH_W / 2, LASH_T / 2
        secs.append([p - a_ * w_ - b_ * h_, p + a_ * w_ - b_ * h_, p + a_ * w_ + b_ * h_, p - a_ * w_ + b_ * h_])
    lash_parts = [loft(secs, "weapon_tape")]
    # shine stripe and splice marks
    for k in range(1, LASH_BONES):
        p = lash_path(k / LASH_BONES)
        t = (lash_path(k / LASH_BONES + 0.01) - p).normalized()
        ang = math.degrees(math.atan2(t.z, t.y))
        mk = box((LASH_W + 0.004, 0.016, LASH_T + 0.003), (0, 0, 0), mat="weapon_paper" if k % 3 else "weapon_accent")
        move(mk, (0, 0, 0), rot=(0, math.degrees(lash_twist(k / LASH_BONES)), 0))
        move(mk, tuple(p), rot=(ang, 0, 0))
        lash_parts.append(mk)
    # weighted leader clip
    e = lash_path(1.0)
    lash_parts.append(box((0.04, 0.05, 0.014), (0, e.y + 0.02, e.z), mat="weapon_steel", bev=0.004))
    lash_parts.append(prism([(-0.02, 0), (0.02, 0), (0.008, 0.07), (-0.008, 0.07)], 0.012, (0, e.y + 0.045, e.z), "Z", "weapon_metal", bev=0.003))
    lash_parts.append(box((0.044, 0.012, 0.018), (0, e.y + 0.012, e.z), mat="weapon_glow", bev=0.003))
    lash = join(lash_parts, "Lash")
    # armature
    arm_d = bpy.data.armatures.new("LashRig")
    rig = bpy.data.objects.new("LashRig", arm_d)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    joints = [lash_path(i / LASH_BONES) for i in range(LASH_BONES + 1)]
    joints[-1] = Vector((0, e.y + 0.115, e.z))
    prev = None
    for i in range(LASH_BONES):
        b = arm_d.edit_bones.new("lash_%02d" % i)
        b.head, b.tail = joints[i], joints[i + 1]
        b.align_roll(Vector((0, 0, 1)))
        if prev is not None:
            b.parent = prev
            b.use_connect = True
        prev = b
    bpy.ops.object.mode_set(mode="OBJECT")
    groups = [lash.vertex_groups.new(name="lash_%02d" % i) for i in range(LASH_BONES)]
    for v in lash.data.vertices:
        s = (v.co.y - 0.34) / LASH_LEN * LASH_BONES
        i = min(LASH_BONES - 1, max(0, int(math.floor(s))))
        f = s - i
        if s >= LASH_BONES:
            groups[-1].add([v.index], 1.0, "REPLACE")
        elif f < 0.5 and i > 0:
            groups[i - 1].add([v.index], 0.5 - f, "REPLACE")
            groups[i].add([v.index], 0.5 + f, "REPLACE")
        elif f >= 0.5 and i < LASH_BONES - 1:
            groups[i].add([v.index], 1.5 - f, "REPLACE")
            groups[i + 1].add([v.index], f - 0.5, "REPLACE")
        else:
            groups[i].add([v.index], 1.0, "REPLACE")
    lash.parent = rig
    md = lash.modifiers.new("Armature", "ARMATURE")
    md.object = rig
    tip = (0, e.y + 0.115, e.z)
    return {"objs": [handle, rig, lash],
            "empties": [empty("Grip", (0, 0, 0)), empty("LashRoot", (0, 0.34, 0.04)), empty("Tip", tip),
                        empty("TrailStart", (0, 0.34 + LASH_LEN * 0.45, lash_path(0.45).z)), empty("TrailEnd", tip)],
            "style": "whip", "hands": 1}


# ───────────────────────────── speaker knuckles ─────────────────────────────

def _gauntlet():
    """Right gauntlet. Frame: origin at the centre of the closed fist, +Y = punch direction (along
    the hand bone, wrist -> knuckles), +Z = back of the hand, thumb on -X."""
    P = []
    # back-of-hand plate (glove leather + pink armour plate)
    P.append(box((0.094, 0.1, 0.014), (0, -0.012, 0.036), mat="weapon_black", bev=0.005))
    P.append(prism(rounded_rect(0.08, 0.07, 0.014, 2), 0.012, (0, -0.012, 0.047), "Z", "weapon_main", bev=0.003))
    # two tweeter domes on the back plate
    for x in (-0.02, 0.02):
        P.append(ring(0.014, 0.004, (x, -0.014, 0.054), "Z", "weapon_metal", n=12, m=5))
        P.append(lathe([(0, 0), (0.012, 0), (0.009, 0.007), (0, 0.01)], (x, -0.014, 0.053), "Z", "weapon_pink_glow", n=10))
    P += star_decal((0.0, 0.012, 0.053), "Z", 0.008)
    # knuckle-duster frame
    P.append(box((0.112, 0.026, 0.07), (0, 0.05, 0.004), mat="weapon_steel", bev=0.008))
    for x in (-0.05, 0.05):
        P.append(hexbolt(0.009, 0.012, (x, 0.05, 0.042), "Z"))
        P.append(box((0.016, 0.07, 0.016), (x, 0.012, 0.038), mat="weapon_steel", bev=0.004))
    # the driver: basket ring, pink cone, yellow dust cap, facing +Y
    cy = 0.064
    P.append(lathe([(0, 0), (0.05, 0), (0.06, 0.012), (0.06, 0.03), (0.053, 0.03), (0.02, 0.008), (0, 0.008)], (0, cy, 0.004), "Y", "weapon_main", n=20))
    P.append(ring(0.057, 0.0, (0, cy + 0.03, 0.004), "Y", "weapon_metal", n=20, flat=(0.006, 0.004)))
    P.append(ring(0.047, 0.004, (0, cy + 0.027, 0.004), "Y", "weapon_black", n=20, m=5))
    P.append(lathe([(0, 0.006), (0.02, 0.006), (0.016, 0.02), (0.008, 0.026), (0, 0.027)], (0, cy, 0.004), "Y", "weapon_accent", n=12))
    for k in range(6):
        a = math.radians(k * 60 + 30)
        P.append(screw(0.0045, (0.057 * math.cos(a), cy + 0.034, 0.004 + 0.057 * math.sin(a)), "Y"))
    P.append(ring(0.034, 0.0025, (0, cy + 0.018, 0.004), "Y", "weapon_pink_glow", n=16, m=4))
    # magnet + voice-coil can behind the frame, on the back of the hand
    P.append(cyl(0.026, 0.03, (0, 0.03, 0.06), "Y", "weapon_dark", n=12, bev=0.004))
    P.append(cyl(0.02, 0.012, (0, 0.012, 0.06), "Y", "weapon_copper", n=12))
    # wrist strap with buckle and jack
    P.append(ring(0.04, 0.0, (0, -0.088, 0.0), "Y", "weapon_black", n=16, flat=(0.005, 0.017)))
    P.append(ring(0.0425, 0.0, (0, -0.088, 0.0), "Y", "weapon_accent", n=16, flat=(0.003, 0.005)))
    P.append(box((0.034, 0.03, 0.012), (0, -0.088, 0.046), mat="weapon_metal", bev=0.004))
    P.append(box((0.02, 0.016, 0.006), (0, -0.088, 0.054), mat="weapon_glow", bev=0.002))
    P.append(box((0.07, 0.03, 0.01), (0, -0.062, 0.04), rot=(-8, 0, 0), mat="weapon_black", bev=0.003))
    # coiled speaker wire: magnet -> wrist jack (thumb side)
    wire = [(-0.02, 0.02, 0.07), (-0.045, 0.0, 0.066), (-0.052, -0.04, 0.05), (-0.044, -0.08, 0.03)]
    P.append(tube(smooth_path(wire, 4), 0.004, "weapon_accent", n=5, up=(0, 0, 1)))
    P.append(cyl(0.007, 0.022, (-0.044, -0.088, 0.024), "Y", "weapon_metal", n=8, bev=0.002))
    return join(P, "Gauntlet_R")


def speaker_knuckles():
    r = _gauntlet()
    l = mirror(r, "X")
    l.name = "Gauntlet_L"
    l.data.name = "Gauntlet_L"
    return {"objs": [r, l], "empties": [empty("Grip", (0, 0, 0)), empty("Tip", (0, 0.098, 0.004)),
                                        empty("TrailStart", (0, 0.094, -0.05)), empty("TrailEnd", (0, 0.094, 0.06))],
            "style": "gauntlet", "hands": 2}


# ───────────────────────────── vinyl glaive ─────────────────────────────

def vinyl_glaive():
    """A sharpened twelve-inch on a broom handle. The record lies in the swing plane (YZ) ahead of
    the shaft, on a turntable spindle so it can spin (separate object "Disc", axis X)."""
    P = []
    top = 0.93
    # shaft: wood, with wraps and stickers
    P.append(cyl(0.019, top + 0.5, (0, (top - 0.5) / 2, 0), "Y", "weapon_wood", n=10))
    P.append(lathe([(0, -0.56), (0.03, -0.56), (0.032, -0.5), (0.024, -0.45), (0.0, -0.45)], axis="Y", mat="weapon_black", n=12))
    P.append(band(0.0245, -0.44, 0.02, "weapon_accent", n=12))
    P += wrap(0.0205, -0.08, 0.09, 6, "weapon_paper", 0.018, 0.003)
    P += wrap(0.0205, 0.36, 0.44, 3, "weapon_paper", 0.018, 0.003)
    P += wrap(0.0205, -0.36, -0.28, 3, "weapon_paper", 0.018, 0.003)
    P += ribbon_tail(0.62, "weapon_accent2", 1.0, 0.13, 0.021)
    P.append(band(0.0205, 0.69, 0.03, "weapon_black", n=12))
    P.append(band(0.0205, 0.2, 0.03, "weapon_accent2", n=12))
    for (y, m) in ((0.27, "weapon_accent"), (0.52, "weapon_accent"), (-0.18, "weapon_accent")):
        P += star_decal((0.0195, y, 0), "X", 0.012, 0, m)
        P += star_decal((-0.0195, y, 0), "-X", 0.012, 0, m)
    # bracket head: clamp block, cassette, vial, fork arms to the spindle
    dc = (0.0, 1.15, 0.15)        # disc centre
    R = 0.30
    P.append(cyl(0.027, 0.07, (0, top - 0.02, 0), "Y", "weapon_steel", n=12, bev=0.004))
    P.append(box((0.07, 0.07, 0.085), (0, top + 0.03, 0.005), mat="weapon_steel", bev=0.008))
    for sx, n in ((1, "X"), (-1, "-X")):
        P.append(box((0.008, 0.045, 0.066), (sx * 0.037, top + 0.03, 0.005), mat="weapon_accent", bev=0.003))
        P += cassette_decal((sx * 0.041, top + 0.03, 0.005), n, 0.052, 0)
        arm = [(sx * 0.03, top + 0.05, 0.0), (sx * 0.03, 1.03, 0.03), (sx * 0.03, 1.1, 0.09), (sx * 0.03, dc[1], dc[2])]
        P.append(ribbon(smooth_path(arm, 3), 0.03, 0.01, "weapon_steel", up=(1, 0, 0)))
        arm2 = [(sx * 0.03, top + 0.03, 0.04), (sx * 0.03, 1.02, 0.12), (sx * 0.03, dc[1], dc[2])]
        P.append(ribbon(smooth_path(arm2, 3), 0.022, 0.01, "weapon_steel", up=(1, 0, 0)))
        P.append(cyl(0.022, 0.012, (sx * 0.034, dc[1], dc[2]), "X", "weapon_metal", n=12, bev=0.002))
        P.append(hexbolt(0.01, 0.01, (sx * 0.042, dc[1], dc[2]), "X"))
        for (y, z) in ((top + 0.05, 0.0), (1.02, 0.02)):
            P.append(screw(0.006, (sx * 0.036, y, z), n))
    P += vial((0, top + 0.03, -0.055), "Y", 0.012, 0.055, "weapon_pink_glow", "weapon_dark")
    P.append(tube(smooth_path([(0, top + 0.07, -0.055), (0, top + 0.11, -0.06), (0, 1.06, -0.03), (0, dc[1] - 0.02, 0.06)], 3), 0.0045, "weapon_accent", n=5))
    P.append(cyl(0.006, 0.07, dc, "X", "weapon_steel", n=6))
    shaft = join(P, "Weapon")

    # the record (built around its own centre, then placed)
    D = []
    t = 0.007
    D.append(lathe([(0, -t / 2), (R - 0.034, -t / 2), (R - 0.034, t / 2), (0, t / 2)], axis="X", mat="weapon_main", n=36))
    D.append(lathe([(R - 0.034, -t / 2), (R - 0.004, -0.0022), (R, 0), (R - 0.004, 0.0022), (R - 0.034, t / 2)], axis="X", mat="weapon_metal", n=36, closed=True))
    for sx, n in ((1, "X"), (-1, "-X")):
        x = sx * t / 2
        for rr in (0.135, 0.17, 0.205, 0.238):
            D.append(ring(rr, 0, (x, 0, 0), "X", "weapon_dark", n=28, flat=(0.0035, 0.0012)))
        D.append(cyl(0.1, 0.0026, (x, 0, 0), "X", "weapon_accent", n=24))
        D += [decal(off2(sc2(star(1, 0.45), 0.03), 0.0, 0.05), (x + sx * 0.0013, 0, 0), n, "weapon_black", 1)]
        for k in range(3):
            D.append(decal(off2(rounded_rect(0.1 - k * 0.018, 0.007, 0.002, 1), 0, -0.045 - k * 0.014), (x + sx * 0.0013, 0, 0), n, "weapon_black", 1))
        # 45 adapter: three-lobed yellow spider
        ad = []
        for k in range(24):
            a = 2 * math.pi * k / 24
            rr = 0.03 + 0.009 * math.cos(3 * a)
            ad.append((rr * math.cos(a), rr * math.sin(a)))
        D.append(prism(ad, 0.008, (sx * (t / 2 + 0.006), 0, 0), "X", "weapon_accent", bev=0.002))
        D.append(cyl(0.012, 0.006, (sx * (t / 2 + 0.011), 0, 0), "X", "weapon_steel", n=10))
    # chips in the cutting rim (so the spin reads)
    for a in (20, 140, 250):
        r = math.radians(a)
        D.append(box((0.012, 0.012, 0.03), (0, (R - 0.012) * math.sin(r), (R - 0.012) * math.cos(r)), rot=(-a, 0, 0), mat="weapon_accent2"))
    disc = join(D, "Disc")
    disc.location = Vector(dc)
    tipa = math.radians(40)
    return {"objs": [shaft, disc],
            "empties": [empty("Grip", (0, 0, 0)), empty("Grip2", (0, -0.3, 0)),
                        empty("Tip", (0, dc[1] + R * math.sin(tipa), dc[2] + R * math.cos(tipa))),
                        empty("TrailStart", (0, dc[1] - R * 0.5, dc[2] + R * 0.866)),
                        empty("TrailEnd", (0, dc[1] + R, dc[2])),
                        empty("DiscAxis", dc)],
            "style": "polearm", "hands": 2}


MELEE = {
    "splice_blade": (splice_blade, "#e8e6df"),
    "stylus_shiv": (stylus_shiv, "#c0c4cc"),
    "amp_sledge": (amp_sledge, "#ffd23f"),
    "reel_lash": (reel_lash, "#5a3b2a"),
    "speaker_knuckles": (speaker_knuckles, "#ff4fa3"),
    "vinyl_glaive": (vinyl_glaive, "#1b1b1f"),
}
