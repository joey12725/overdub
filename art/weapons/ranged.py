"""
The five ranged weapons (data/gear.json, slot "ranged"). Each is worn on Moxie's LEFT forearm.
Authoring space is Godot space with this frame:
  origin  the wrist mount: the top of the forearm, about 60% of the way from elbow to wrist
  +Z      toward the hand = the muzzle direction
  +Y      away from the arm (straight up when the arm is held level)
  the forearm's axis runs along Z at y = -ARM_R; the cuff is a full ring around it.
Every weapon has a `Muzzle` empty whose +Z is the direction of fire, and a `Mount` empty at the origin.
Concepts: docs/reference/generated/weapons/<id>.png
"""
from __future__ import annotations

import math

from mathutils import Matrix

import wlib as L
from wlib import (apply, band, box, cyl, empty, hexbolt, join, knob, lathe, move, prism, ribbon, ring,
                  rounded_rect, screw, smooth_path, sphere, star, tube)
from melee import bolt_decal, cassette_decal, decal, off2, rot2, sc2, star_decal, vial
import projectiles

ARM_R = 0.036          # forearm radius the cuff is sized for
CUFF_IN = 0.039


def cuff(z0=-0.07, z1=0.045, trim="weapon_accent"):
    """The wrist bracer every launcher bolts to (R02 detail sheet: dark band, bright trims, a
    little waveform screen), plus the mount plate on top."""
    P = []
    zc, hl = (z0 + z1) / 2, (z1 - z0) / 2
    c = (0, -ARM_R, zc)
    P.append(ring(CUFF_IN + 0.0045, 0, c, "Z", "weapon_black", n=18, flat=(0.0045, hl)))
    for z in (z0 + 0.008, z1 - 0.008):
        P.append(ring(CUFF_IN + 0.006, 0, (0, -ARM_R, z), "Z", trim, n=18, flat=(0.0045, 0.006)))
    P.append(ring(CUFF_IN + 0.0055, 0, (0, -ARM_R, zc - 0.012), "Z", "weapon_paper", n=18, flat=(0.0042, 0.011), rot=(0, 5, 0)))
    # buckle on the outer side, screen on the inner side
    P.append(box((0.012, 0.03, 0.036), (CUFF_IN + 0.01, -ARM_R, zc + 0.01), mat="weapon_metal", bev=0.004))
    P.append(box((0.008, 0.034, 0.05), (-(CUFF_IN + 0.009), -ARM_R, zc), mat="weapon_dark", bev=0.003))
    P.append(box((0.004, 0.022, 0.036), (-(CUFF_IN + 0.0135), -ARM_R, zc), mat="weapon_glow"))
    # mount plate
    P.append(box((0.066, 0.014, z1 - z0 - 0.012), (0, 0.012, zc), mat="weapon_steel", bev=0.004))
    for sx in (-1, 1):
        for z in (z0 + 0.02, z1 - 0.02):
            P.append(hexbolt(0.006, 0.008, (sx * 0.024, 0.021, z), "Y"))
    return P


def cable(pts, mat="weapon_accent", r=0.004):
    return tube(smooth_path(pts, 3), r, mat, n=5, up=(0, 1, 0))


# ───────────────────────────── mixtape rocket ─────────────────────────────

def mixtape_rocket():
    """An open cassette-deck well with one fat cassette rocket lying loaded in it (object `Round`,
    hide it while the launcher recharges). Short, boxy, heavy; flipped-up deck door as blast shield."""
    P = cuff()
    P.append(box((0.128, 0.052, 0.2), (0, 0.045, 0.02), mat="weapon_main", bev=0.009, seg=2))
    P.append(box((0.104, 0.008, 0.172), (0, 0.071, 0.024), mat="weapon_black", bev=0.002))       # tape well floor
    for sx in (-1, 1):
        P.append(box((0.013, 0.03, 0.25), (sx * 0.0575, 0.083, 0.05), mat="weapon_steel", bev=0.004))   # launch rails
        P.append(box((0.017, 0.034, 0.022), (sx * 0.0575, 0.083, 0.17), mat="weapon_accent", bev=0.004))
        P.append(box((0.017, 0.034, 0.022), (sx * 0.0575, 0.083, -0.06), mat="weapon_accent", bev=0.004))
        for z in (-0.02, 0.06, 0.12):
            P.append(screw(0.005, (sx * 0.064, 0.083, z), "X" if sx > 0 else "-X"))
    # front bumper with hazard chevrons
    P.append(box((0.134, 0.03, 0.02), (0, 0.04, 0.124), mat="weapon_accent", bev=0.005))
    for k in range(-2, 3):
        P.append(box((0.012, 0.031, 0.021), (k * 0.026, 0.04, 0.1245), rot=(0, 0, 25), mat="weapon_black"))
    # flipped-up deck door: frame, window, hinge
    door = [box((0.118, 0.085, 0.01), (0, 0.0425, 0), mat="weapon_dark", bev=0.003),
            box((0.084, 0.05, 0.012), (0, 0.045, 0), mat="weapon_glow", bev=0.002),
            box((0.1, 0.012, 0.014), (0, 0.078, 0), mat="weapon_accent", bev=0.003)]
    for d in door:
        move(d, (0, 0.074, -0.082), rot=(-28, 0, 0))
    P += door
    P.append(cyl(0.008, 0.13, (0, 0.074, -0.082), "X", "weapon_steel", n=8))
    # targeting chip with its screen and aerial, on the outer side
    P.append(box((0.026, 0.05, 0.07), (0.076, 0.05, -0.02), mat="weapon_dark", bev=0.005))
    P.append(box((0.006, 0.026, 0.036), (0.09, 0.054, -0.02), mat="weapon_glow", bev=0.002))
    P.append(tube([(0.078, 0.07, -0.045), (0.082, 0.12, -0.06), (0.084, 0.165, -0.085)], 0.0025, "weapon_steel", n=4))
    P.append(sphere(0.007, (0.084, 0.165, -0.085), "weapon_accent2", n=8))
    P.append(cable([(0.086, 0.03, -0.04), (0.094, 0.0, -0.03), (0.07, -0.02, -0.015), (0.052, -0.03, -0.01)]))
    # eject / arm controls on the back
    for x in (-0.03, 0.0):
        P += knob(0.012, 0.014, (x, 0.045, -0.08), "-Z", "weapon_black", "weapon_paper", n=10)
    P.append(box((0.022, 0.022, 0.012), (0.034, 0.045, -0.084), mat="weapon_hot_glow", bev=0.003))
    # stickers
    P += star_decal((-0.064, 0.044, 0.05), "-X", 0.016)
    P += bolt_decal((-0.064, 0.044, -0.01), "-X", 0.018, 90, "weapon_paper")
    P += cassette_decal((-0.064, 0.044, -0.05), "-X", 0.034, 0, "weapon_accent")
    body = join(P, "Weapon")
    rocket = join(projectiles.missile_parts(0.8, (0, 0.092, 0.07)), "Round")
    return {"objs": [body, rocket],
            "empties": [empty("Mount", (0, 0, 0)), empty("Muzzle", (0, 0.092, 0.215))], "style": "launcher"}


# ───────────────────────────── needle rail ─────────────────────────────

def needle_rail():
    """Twin rails reaching well past the fist, copper tape-head coils either side of the breech, a
    wheel magazine of phonograph needles standing on top. The longest, thinnest silhouette."""
    P = cuff()
    P.append(box((0.07, 0.046, 0.13), (0, 0.042, -0.015), mat="weapon_main", bev=0.007))
    P.append(box((0.062, 0.008, 0.07), (0, 0.068, 0.012), mat="weapon_accent", bev=0.003))
    P += star_decal((0.012, 0.0722, 0.03), "Y", 0.011)
    P += cassette_decal((-0.01, 0.0722, 0.0), "Y", 0.03, 90)
    # rails with pointed tips and the glow between them
    for sx in (-1, 1):
        x = sx * 0.016
        P.append(box((0.009, 0.014, 0.37), (x, 0.045, 0.235), mat="weapon_metal", bev=0.003))
        P.append(prism([(-0.0045, 0), (0.0045, 0), (0.0045 - sx * 0.0045, 0.03)], 0.014, (x, 0.045, 0.42), "Y", "weapon_metal"))
        # coils: two per side
        for z in (0.085, 0.14):
            P.append(cyl(0.017, 0.04, (sx * 0.04, 0.045, z), "Z", "weapon_copper", n=12))
            for dz in (-0.022, 0.022):
                P.append(cyl(0.02, 0.006, (sx * 0.04, 0.045, z + dz), "Z", "weapon_steel", n=12))
            for dz in (-0.01, 0.0, 0.01):
                P.append(ring(0.0172, 0, (sx * 0.04, 0.045, z + dz), "Z", "weapon_dark", n=12, flat=(0.0012, 0.0012)))
        P.append(box((0.03, 0.02, 0.1), (sx * 0.035, 0.03, 0.11), mat="weapon_dark", bev=0.004))
    P.append(box((0.016, 0.004, 0.33), (0, 0.045, 0.235), mat="weapon_glow"))
    for z in (0.2, 0.3, 0.39):
        P.append(box((0.048, 0.02, 0.012), (0, 0.045, z), mat="weapon_accent" if z < 0.38 else "weapon_steel", bev=0.003))
    # needle wheel magazine (axis X) on top of the breech
    wc = (0, 0.098, -0.03)
    P.append(cyl(0.04, 0.022, wc, "X", "weapon_dark", n=16, bev=0.003))
    for sx in (-1, 1):
        P.append(cyl(0.03, 0.004, (sx * 0.012, wc[1], wc[2]), "X", "weapon_pink_glow", n=16))
        P.append(cyl(0.011, 0.008, (sx * 0.015, wc[1], wc[2]), "X", "weapon_accent", n=8, bev=0.002))
    for k in range(9):
        a = math.radians(-20 + k * 27.5)
        nd = lathe([(0, 0), (0.0035, 0), (0.0025, 0.022), (0, 0.04)], (0, 0, 0), "Y", "weapon_metal", n=4)
        move(nd, (0, 0.038, 0))
        move(nd, wc, rot=(-90 + math.degrees(a), 0, 0))
        P.append(nd)
    P.append(box((0.03, 0.03, 0.03), (0, 0.068, -0.03), mat="weapon_steel", bev=0.004))
    # tape head at the back, cable
    P.append(box((0.044, 0.032, 0.022), (0, 0.045, -0.088), mat="weapon_metal", bev=0.006))
    P.append(box((0.003, 0.033, 0.023), (0, 0.045, -0.089), mat="weapon_black"))
    P.append(cable([(0.03, 0.04, -0.07), (0.06, 0.01, -0.06), (0.06, -0.03, -0.03), (0.05, -0.036, 0.0)]))
    P += vial((-0.04, 0.05, -0.04), "Z", 0.008, 0.04, "weapon_pink_glow", "weapon_dark")
    w = join(P, "Weapon")
    return {"objs": [w], "empties": [empty("Mount", (0, 0, 0)), empty("Muzzle", (0, 0.045, 0.45))], "style": "rail"}


# ───────────────────────────── bleedthrough emitter ─────────────────────────────

def bleed_emitter():
    """A-side and B-side tape heads facing each other across a gap, feeding a horn of floating
    rings that widen toward the muzzle; a little tape loop turns on top. Round, ringed, eerie."""
    P = cuff(trim="weapon_accent2")
    P.append(box((0.086, 0.04, 0.12), (0, 0.04, -0.015), mat="weapon_main", bev=0.008))
    P.append(box((0.07, 0.008, 0.07), (0, 0.062, -0.03), mat="weapon_dark", bev=0.003))
    cy = 0.082
    # the two heads
    for sx, cap in ((1, "weapon_accent"), (-1, "weapon_accent2")):
        P.append(box((0.024, 0.04, 0.034), (sx * 0.034, cy, 0.03), mat="weapon_metal", bev=0.006))
        P.append(box((0.006, 0.03, 0.006), (sx * 0.021, cy, 0.03), mat="weapon_black"))
        P.append(box((0.026, 0.01, 0.036), (sx * 0.034, cy + 0.022, 0.03), mat=cap, bev=0.003))
        P.append(box((0.02, 0.03, 0.03), (sx * 0.036, cy - 0.03, 0.03), mat="weapon_dark", bev=0.003))
    P.append(sphere(0.013, (0, cy, 0.03), "weapon_violet_glow", n=10))
    # the horn: three rings on three struts
    rings = ((0.075, 0.034, 0.007, "weapon_main"), (0.13, 0.05, 0.0075, "weapon_violet_glow"), (0.195, 0.068, 0.009, "weapon_main"))
    for (z, R, r, m) in rings:
        P.append(ring(R, r, (0, cy, z), "Z", m, n=20, m=6))
    P.append(ring(0.058, 0.004, (0, cy, 0.197), "Z", "weapon_violet_glow", n=20, m=4))
    P.append(ring(0.026, 0.003, (0, cy, 0.077), "Z", "weapon_violet_glow", n=14, m=4))
    for a in (-90, 30, 150):
        r = math.radians(a)
        pts = [(0.03 * math.cos(r), cy + 0.03 * math.sin(r), 0.045)] + [(R * math.cos(r), cy + R * math.sin(r), z) for (z, R, _r, _m) in rings]
        P.append(tube(pts, 0.0045, "weapon_steel", n=5, up=(0, 1, 0)))
    # tape loop on two spools behind the heads
    sp = ((-0.024, 0.07, -0.045), (0.024, 0.07, -0.045))
    for c in sp:
        P.append(cyl(0.015, 0.014, c, "Y", "weapon_paper", n=12, bev=0.002))
        P.append(cyl(0.006, 0.02, c, "Y", "weapon_steel", n=6))
    loop = []
    for k in range(17):
        a = 2 * math.pi * k / 16
        loop.append((0.042 * math.cos(a), 0.071, -0.045 + 0.019 * math.sin(a)))
    P.append(ribbon(loop, 0.003, 0.012, "weapon_tape", up=(0, 1, 0)))
    # B-side dial on the back, vial, cable
    P += knob(0.016, 0.016, (0, 0.04, -0.075), "-Z", "weapon_black", "weapon_accent", n=12)
    P += vial((0.05, 0.04, -0.03), "Z", 0.009, 0.05, "weapon_violet_glow", "weapon_dark")
    P.append(cable([(-0.04, 0.03, -0.06), (-0.064, 0.0, -0.05), (-0.06, -0.03, -0.02)], "weapon_accent2"))
    P += star_decal((-0.0436, 0.04, 0.0), "-X", 0.012)
    w = join(P, "Weapon")
    return {"objs": [w], "empties": [empty("Mount", (0, 0, 0)), empty("Muzzle", (0, cy, 0.21))], "style": "emitter"}


# ───────────────────────────── bass drop ─────────────────────────────

BASS_TILT = 40.0


def bass_drop():
    """A stubby mortar tube tilted 40 degrees up, a subwoofer cone for a breech. Fat and
    upward-pointing: the only launcher whose silhouette leaves the line of the arm."""
    P = cuff()
    P.append(box((0.09, 0.034, 0.11), (0, 0.035, -0.01), mat="weapon_dark", bev=0.007))
    pivot = (0, 0.075, -0.03)
    T = []
    T.append(lathe([(0, 0.02), (0.045, 0.02), (0.045, 0.16), (0.062, 0.16), (0.062, 0.135), (0.054, 0.13), (0.054, -0.07), (0, -0.07)], axis="Z", mat="weapon_dark", n=18))
    T.append(ring(0.058, 0, (0, 0, 0.148), "Z", "weapon_main", n=18, flat=(0.0055, 0.013)))
    T.append(ring(0.046, 0.004, (0, 0, 0.158), "Z", "weapon_green_glow", n=18, m=4))
    for z in (-0.02, 0.07):
        T.append(ring(0.0555, 0, (0, 0, z), "Z", "weapon_main", n=18, flat=(0.003, 0.012)))
    # subwoofer breech, facing back
    T.append(lathe([(0, -0.07), (0.054, -0.07), (0.078, -0.105), (0.078, -0.12), (0.066, -0.12), (0.024, -0.09), (0, -0.09)], axis="Z", mat="weapon_black", n=18))
    T.append(ring(0.072, 0.007, (0, 0, -0.121), "Z", "weapon_main", n=18, m=5))
    T.append(lathe([(0, -0.088), (0.026, -0.09), (0.02, -0.104), (0, -0.11)], axis="Z", mat="weapon_accent", n=12))
    for k in range(6):
        a = math.radians(k * 60 + 30)
        T.append(screw(0.005, (0.078 * math.cos(a), 0.078 * math.sin(a), -0.108), "-Z"))
    # carry strap along the top, sight post, sticker
    T.append(ribbon(smooth_path([(0, 0.056, -0.03), (0, 0.082, 0.0), (0, 0.086, 0.05), (0, 0.058, 0.09)], 3), 0.02, 0.005, "weapon_paper", up=(0, 1, 0)))
    T.append(box((0.008, 0.03, 0.008), (0, 0.07, 0.14), mat="weapon_accent", bev=0.002))
    T += star_decal((0.0548, 0.0, 0.025), "X", 0.014)
    T += star_decal((-0.0548, 0.0, 0.025), "-X", 0.014)
    rot = Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(-BASS_TILT), 4, "X")
    for t in L.flat(T):
        apply(t, rot)
    P += T
    # trunnion and bipod struts
    P.append(cyl(0.016, 0.126, pivot, "X", "weapon_accent", n=10, bev=0.003))
    for sx in (-1, 1):
        P.append(box((0.012, 0.06, 0.03), (sx * 0.06, 0.05, -0.03), mat="weapon_steel", bev=0.003))
        tip = rot @ L.Vector((sx * 0.05, -0.03, 0.1))
        P.append(tube([(sx * 0.04, 0.024, 0.05), tuple(tip)], 0.006, "weapon_steel", n=6, up=(1, 0, 0)))
        P.append(sphere(0.009, (sx * 0.04, 0.024, 0.05), "weapon_accent", n=8))
        # level meter
        for k in range(5):
            P.append(box((0.004, 0.012, 0.013), (sx * 0.046, 0.036, -0.05 + k * 0.018), mat="weapon_green_glow" if k < 4 else "weapon_hot_glow"))
    P.append(cable([(0.03, 0.03, -0.062), (0.058, 0.0, -0.06), (0.056, -0.03, -0.03)]))
    w = join(P, "Weapon")
    mz = rot @ L.Vector((0, 0, 0.165))
    return {"objs": [w], "empties": [empty("Mount", (0, 0, 0)), empty("Muzzle", tuple(mz), rot=(-BASS_TILT, 0, 0))], "style": "mortar"}


# ───────────────────────────── static spray ─────────────────────────────

def static_spray():
    """A shorted-out boombox strapped speakers-up, with a wide fan nozzle of five spark emitters.
    Wide, short, fan-fronted: its width matches the 40-degree spread."""
    P = cuff()
    by = 0.056
    P.append(box((0.18, 0.066, 0.1), (0, by, -0.015), mat="weapon_main", bev=0.009, seg=2))
    top = by + 0.033
    for sx in (-1, 1):
        x = sx * 0.055
        P.append(ring(0.031, 0, (x, top, -0.012), "Y", "weapon_metal", n=16, flat=(0.005, 0.004)))
        P.append(lathe([(0, 0.0), (0.028, 0.004), (0.028, -0.002), (0, -0.002)], (x, top, -0.012), "Y", "weapon_black", n=16))
        P += [decal(off2(sc2(star(1, 0.48), 0.014), x, -0.012), (0, top + 0.004, 0), "Y", "weapon_accent", 1)]
        for k in range(4):
            a = math.radians(45 + 90 * k)
            P.append(screw(0.0035, (x + 0.031 * math.cos(a), top + 0.004, -0.012 + 0.031 * math.sin(a)), "Y"))
    P.append(box((0.04, 0.006, 0.05), (0, top, -0.01), mat="weapon_black", bev=0.002))
    P += cassette_decal((0, top + 0.003, -0.01), "Y", 0.032, 0)
    for k in range(5):
        P.append(box((0.016, 0.008, 0.01), (-0.04 + k * 0.02, top, -0.056), mat="weapon_paper" if k != 2 else "weapon_hot_glow", bev=0.002))
    P += bolt_decal((0.0, top, 0.027), "Y", 0.012, 90, "weapon_accent2")
    # carry handle (taped), aerial, crank
    hp = [(-0.075, by + 0.01, -0.06), (-0.075, by + 0.03, -0.1), (0.075, by + 0.03, -0.1), (0.075, by + 0.01, -0.06)]
    P.append(tube(hp, 0.007, "weapon_dark", n=6, up=(0, 1, 0)))
    P.append(cyl(0.01, 0.07, (0, by + 0.03, -0.1), "X", "weapon_paper", n=8))
    P.append(tube([(0.082, top, -0.05), (0.1, top + 0.07, -0.085), (0.105, top + 0.13, -0.14)], 0.0028, "weapon_steel", n=4))
    P.append(sphere(0.007, (0.105, top + 0.13, -0.14), "weapon_accent2", n=8))
    P.append(cyl(0.012, 0.014, (-0.096, by, -0.02), "X", "weapon_steel", n=8, bev=0.002))
    P.append(box((0.008, 0.014, 0.06), (-0.104, by, -0.045), mat="weapon_metal", bev=0.003))
    P.append(cyl(0.011, 0.04, (-0.124, by, -0.07), "X", "weapon_accent", n=10, bev=0.003))
    # the fan nozzle
    fan = [(-0.045, 0.03), (0.045, 0.03), (0.125, 0.165), (-0.125, 0.165)]
    P.append(prism(fan, 0.05, (0, by - 0.004, 0), "Y", "weapon_accent", bev=0.006))
    P.append(box((0.228, 0.032, 0.008), (0, by - 0.004, 0.166), mat="weapon_black", bev=0.002))
    for sx in (-1, 1):
        P.append(decal([(sx * 0.03, 0.06), (sx * 0.05, 0.06), (sx * 0.1, 0.14), (sx * 0.08, 0.14)], (0, by + 0.021, 0), "Y", "weapon_paper", 1))
    P.append(decal([(-0.01, 0.06), (0.01, 0.06), (0.01, 0.14), (-0.01, 0.14)], (0, by + 0.021, 0), "Y", "weapon_black", 1))
    for k in range(-2, 3):
        yaw = k * 10.0
        e = [cyl(0.009, 0.03, (0, 0, 0.012), "Z", "weapon_steel", n=8, bev=0.002),
             lathe([(0, 0.026), (0.0075, 0.03), (0.004, 0.045), (0, 0.062)], axis="Z", mat="weapon_glow", n=6),
             ring(0.011, 0, (0, 0, 0.004), "Z", "weapon_copper", n=8, flat=(0.002, 0.004))]
        for o in e:
            move(o, (k * 0.05, by - 0.004, 0.165), rot=(0, yaw, 0))
        P += e
    P.append(cable([(0.05, 0.03, -0.06), (0.066, 0.0, -0.05), (0.058, -0.03, -0.02)]))
    w = join(P, "Weapon")
    return {"objs": [w], "empties": [empty("Mount", (0, 0, 0)), empty("Muzzle", (0, by - 0.004, 0.23))], "style": "boombox"}


RANGED = {
    "mixtape_rocket": (mixtape_rocket, "#ff4d6d"),
    "needle_rail": (needle_rail, "#c0c4cc"),
    "bleed_emitter": (bleed_emitter, "#8a5cff"),
    "bass_drop": (bass_drop, "#7dff6b"),
    "static_spray": (static_spray, "#3ec5ff"),
}
