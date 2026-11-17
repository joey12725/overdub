"""
Projectile models, one per ranged archetype (assets/models/projectiles/<archetype>.glb) plus the
enemy bolt and the boss shock. Authoring space is Godot space: nose along +Z, origin at the centre
of the collision circle, +Y up.
"""
from __future__ import annotations

import math

import wlib as L
from wlib import (box, cyl, empty, join, lathe, move, prism, ring, rounded_rect, sphere, star, tube)
from melee import decal, off2, sc2

L.PALETTE.update({"bolt_glow": "#ff6a1a", "bolt_dark": "#2a1a1c", "shock_glow": "#ffb347", "shock_dark": "#3a1c14"})


def missile_parts(k=1.0, at=(0, 0, 0)):
    """A cassette shell with bottle-rocket guts: flat body, squashed nose, nozzle, four fins."""
    P = []
    P.append(box((0.1, 0.034, 0.16), (0, 0, -0.01), mat="weapon_main", bev=0.006))
    for n, s in (("Y", 1), ("-Y", -1)):
        y = s * 0.017
        P.append(decal(rounded_rect(0.084, 0.12, 0.006, 1), (0, y, -0.01), n, "weapon_paper", 1))
        P.append(decal(rounded_rect(0.084, 0.022, 0.004, 1), (0, y, 0.035), n, "weapon_accent", 2))
        P.append(decal(rounded_rect(0.06, 0.036, 0.006, 1), (0, y, -0.022), n, "weapon_black", 2))
        for sx in (-1, 1):
            P.append(decal(off2(sc2(star(1, 0.6, 6), 0.011), sx * 0.017, -0.022), (0, y, 0), n, "weapon_accent2", 3))
            P.append(L.screw(0.004, (sx * 0.043, y, -0.08), n))
            P.append(L.screw(0.004, (sx * 0.043, y, 0.06), n))
    nose = lathe([(0, 0), (0.05, 0), (0.047, 0.03), (0.032, 0.07), (0.012, 0.095), (0, 0.1)], (0, 0, 0), "Z", "weapon_accent", n=14)
    move(nose, (0, 0, 0.07), scale=(1, 0.42, 1))
    P.append(nose)
    tip = lathe([(0, 0), (0.0325, 0), (0.012, 0.027), (0, 0.032)], (0, 0, 0), "Z", "weapon_accent2", n=14)
    move(tip, (0, 0, 0.14), scale=(1, 0.42, 1))
    P.append(tip)
    P.append(box((0.104, 0.038, 0.012), (0, 0, 0.068), mat="weapon_steel", bev=0.003))
    # nozzle and flame
    P.append(lathe([(0, 0), (0.016, 0), (0.016, -0.012), (0.03, -0.05), (0.024, -0.05), (0.01, -0.014), (0, -0.014)], (0, 0, -0.09), "Z", "weapon_steel", n=10))
    P.append(lathe([(0, -0.016), (0.02, -0.04), (0.014, -0.075), (0, -0.11)], (0, 0, -0.09), "Z", "weapon_hot_glow", n=8))
    P.append(box((0.06, 0.03, 0.014), (0, 0, -0.095), mat="weapon_dark", bev=0.003))
    # fins
    for sx in (-1, 1):
        P.append(prism([(sx * 0.05, -0.02), (sx * 0.098, -0.1), (sx * 0.098, -0.14), (sx * 0.05, -0.088)], 0.007, (0, 0, 0), "Y", "weapon_accent", bev=0.002))
        P.append(prism([(-0.03, sx * 0.017), (-0.1, sx * 0.058), (-0.135, sx * 0.058), (-0.088, sx * 0.017)], 0.007, (0, 0, 0), "X", "weapon_accent", bev=0.002))
    for p in P:
        move(p, at, scale=(k, k, k))
    return P


def missile():
    o = join(missile_parts(), "Projectile")
    return {"objs": [o], "empties": [empty("Nose", (0, 0, 0.172)), empty("Tail", (0, 0, -0.14))]}


def pierce():
    P = [lathe([(0, -0.27), (0.013, -0.26), (0.013, -0.19), (0.0075, -0.175), (0.0075, 0.08), (0.004, 0.2), (0, 0.3)], axis="Z", mat="weapon_metal", n=8),
         ring(0.0145, 0, (0, 0, -0.205), "Z", "weapon_accent", n=8, flat=(0.003, 0.012)),
         ring(0.0145, 0, (0, 0, -0.245), "Z", "weapon_accent2", n=8, flat=(0.003, 0.008)),
         lathe([(0, -0.165), (0.0105, -0.16), (0.0105, 0.03), (0, 0.06)], axis="Z", mat="weapon_glow", n=6),
         lathe([(0, 0.27), (0.0035, 0.285), (0, 0.305)], axis="Z", mat="weapon_glow", n=4)]
    for a in (0, 120, 240):
        r = math.radians(a)
        P.append(box((0.003, 0.02, 0.05), (0.016 * math.sin(r), 0.016 * math.cos(r), -0.245), rot=(0, 0, -a), mat="weapon_steel"))
    o = join(P, "Projectile")
    return {"objs": [o], "empties": [empty("Nose", (0, 0, 0.305)), empty("Tail", (0, 0, -0.27))]}


def phase():
    P = [sphere(0.07, (0, 0, 0.02), "weapon_violet_glow", n=14, scale=(1, 1, 1.25)),
         sphere(0.03, (0, 0, 0.075), "weapon_paper", n=8, scale=(1, 1, 1.2))]
    for (z, R, r, tilt) in ((-0.03, 0.105, 0.011, 6), (-0.13, 0.08, 0.009, -8), (-0.215, 0.052, 0.007, 10)):
        P.append(ring(R, r, (0, 0, z), "Z", "weapon_violet_glow", n=18, m=5, rot=(tilt, tilt * 0.6, 0)))
    # A-side / B-side brackets: the solid, non-glowing part
    for a in (0, 180):
        br = lathe([(0.118, -0.018), (0.132, -0.018), (0.132, 0.018), (0.118, 0.018)], (0, 0, 0.0), "Z", "weapon_main", n=6, closed=True, arc=70)
        move(br, rot=(0, 0, a - 35))
        P.append(br)
        r = math.radians(a)
        P.append(box((0.03, 0.022, 0.03), (0.14 * math.cos(r), 0.14 * math.sin(r), 0), mat="weapon_metal", bev=0.004))
    o = join(P, "Projectile")
    return {"objs": [o], "empties": [empty("Nose", (0, 0, 0.108)), empty("Tail", (0, 0, -0.22))]}


def arc_parts():
    P = [lathe([(0, -0.075), (0.088, -0.075), (0.1, -0.062), (0.1, 0.045), (0.11, 0.045), (0.11, 0.07), (0.09, 0.07), (0.09, 0.06), (0, 0.06)], axis="Z", mat="weapon_dark", n=18),
         lathe([(0.09, 0.066), (0.035, 0.036), (0, 0.036), (0, 0.03), (0.04, 0.03), (0.09, 0.058)], axis="Z", mat="weapon_black", n=18, closed=True),
         ring(0.094, 0.007, (0, 0, 0.072), "Z", "weapon_green_glow", n=18, m=5),
         lathe([(0, 0.034), (0.034, 0.034), (0.028, 0.05), (0.014, 0.06), (0, 0.062)], axis="Z", mat="weapon_main", n=12)]
    for z in (-0.04, 0.012):
        P.append(ring(0.101, 0, (0, 0, z), "Z", "weapon_main", n=18, flat=(0.003, 0.009)))
    for k in range(6):
        a = math.radians(k * 60)
        P.append(L.screw(0.006, (0.1 * math.cos(a), 0.1 * math.sin(a), 0.0575), "Z"))
    # bail handle over the back and a hazard label
    P.append(tube(L.smooth_path([(-0.07, 0, -0.07), (-0.06, 0, -0.115), (0, 0, -0.13), (0.06, 0, -0.115), (0.07, 0, -0.07)], 3), 0.007, "weapon_steel", n=6, up=(0, 1, 0)))
    P.append(cyl(0.03, 0.012, (0, 0, -0.078), "Z", "weapon_accent", n=10, bev=0.003))
    P.append(box((0.07, 0.006, 0.04), (0, 0.1, -0.014), mat="weapon_accent", bev=0.002))
    P.append(box((0.03, 0.007, 0.03), (0, 0.101, -0.014), rot=(0, 45, 0), mat="weapon_black"))
    return P


def arc():
    o = join(arc_parts(), "Projectile")
    return {"objs": [o], "empties": [empty("Nose", (0, 0, 0.075)), empty("Tail", (0, 0, -0.13))]}


def burst():
    P = [lathe([(0, -0.075), (0.024, -0.012), (0, 0.065)], axis="Z", mat="weapon_paper", n=4)]
    for (rx, ry, rz) in ((32, 0, 0), (-32, 0, 0), (0, 32, 45), (0, -32, 45)):
        P.append(lathe([(0, -0.105), (0.013, -0.03), (0, 0.045)], (0, 0, 0), "Z", "weapon_glow", n=4, rot=(rx, ry, rz)))
    P.append(lathe([(0, -0.02), (0.034, 0.0), (0, 0.02)], axis="Z", mat="weapon_glow", n=6))
    o = join(P, "Projectile")
    return {"objs": [o], "empties": [empty("Nose", (0, 0, 0.065)), empty("Tail", (0, 0, -0.105))]}


def bolt():
    """Enemy bolt: a hot orange shard in a dark machined collar with three vanes."""
    P = [lathe([(0, -0.17), (0.02, -0.1), (0.036, 0.01), (0.018, 0.09), (0, 0.15)], axis="Z", mat="bolt_glow", n=6),
         lathe([(0.03, -0.07), (0.046, -0.06), (0.05, -0.02), (0.04, -0.005), (0.03, -0.005)], axis="Z", mat="bolt_dark", n=6, closed=True)]
    for a in (0, 120, 240):
        v = prism([(-0.02, 0.04), (-0.13, 0.085), (-0.16, 0.07), (-0.07, 0.04)], 0.008, (0, 0, 0), "X", "bolt_dark", bev=0.002)
        move(v, rot=(0, 0, a))
        P.append(v)
    o = join(P, "Projectile")
    return {"objs": [o], "empties": [empty("Nose", (0, 0, 0.15)), empty("Tail", (0, 0, -0.17))]}


def shock():
    """Boss shockwave shot: a crescent of the expanding ring, convex toward +Z, with jagged teeth."""
    R = 0.34
    P = []
    P.append(lathe([(R - 0.05, 0), (R - 0.01, 0.04), (R + 0.02, 0), (R - 0.01, -0.04)], (0, 0, -R), "Y", "shock_glow", n=14, closed=True, arc=100, rot=(0, 220, 0)))
    P.append(lathe([(R - 0.075, 0), (R - 0.05, 0.022), (R - 0.04, 0), (R - 0.05, -0.022)], (0, 0, -R), "Y", "shock_dark", n=14, closed=True, arc=100, rot=(0, 220, 0)))
    for k in range(-3, 4):
        a = math.radians(k * 13)
        x, z = (R + 0.01) * math.sin(a), -R + (R + 0.01) * math.cos(a)
        h = 0.07 if k % 2 == 0 else 0.045
        P.append(lathe([(0, 0), (0.016, 0.012), (0, h)], (x, 0, z), "Z", "shock_glow", n=4, rot=(0, math.degrees(a), 0)))
    o = join(P, "Projectile")
    return {"objs": [o], "empties": [empty("Nose", (0, 0, 0.08)), empty("Tail", (0, 0, -0.1))]}


PROJECTILES = {
    "missile": (missile, "#ff4d6d"),
    "pierce": (pierce, "#c0c4cc"),
    "phase": (phase, "#8a5cff"),
    "arc": (arc, "#7dff6b"),
    "burst": (burst, "#3ec5ff"),
    "bolt": (bolt, "#ff6a1a"),
    "shock": (shock, "#ff6a1a"),
}
