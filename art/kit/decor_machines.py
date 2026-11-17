"""Machinery and utilities: pipe, console, generator, vent, lamp, neon, cable, wave_screen.

Front = -Y in Blender (Godot +Z). Animated parts are separate objects with their origin on the
rotation axis: generator / vent "Fan" (spins about its local Godot Z for vent__lower and X for
generator), console / wave_screen "Screen" (0-1 UVs, the game may draw on it).
"""
from __future__ import annotations

import math
import random

import bmesh
from mathutils import Vector

import decor_lib as L
from decor_containers import paneled_box, rivets, star


def pipe_run(points, r, mat, bend=None, seg=6, res=3):
    path = L.fillet_path(points, bend if bend is not None else r * 2.0, seg)
    return L.tube([tuple(p) for p in path], r, mat=mat, smooth=False, res=res, caps=True)


def flange_x(x, y, z, r, mat="rust", t=0.04):
    """A pipe flange collar on a run along X."""
    return L.cyl(r, t, loc=(x, y, z), rot=(0, 90, 0), mat=mat, n=14, bev=0.006)


def flange_z(x, y, z, r, mat="rust", t=0.04):
    return L.cyl(r, t, loc=(x, y, z), mat=mat, n=14, bev=0.006)


def clamp_post(x, y, z_pipe, r_pipe, mat_post="metal_dark", mat_clamp="metal", foot=True):
    """A floor bracket: a square post carrying a clamp ring around a pipe running along X."""
    parts = [L.box((0.05, 0.05, z_pipe - r_pipe), (x, y, (z_pipe - r_pipe) / 2), mat=mat_post, bev=0.006),
             L.torus(r_pipe + 0.012, 0.016, loc=(x, y, z_pipe), rot=(0, 90, 0), mat=mat_clamp, n=16, m=4,
                     square=True)]
    if foot:
        parts.append(L.box((0.12, 0.1, 0.02), (x, y, 0.01), mat=mat_post, bev=0.004))
        parts += rivets([(x - 0.04, y, 0.022), (x + 0.04, y, 0.022)], r=0.01, axis="z", mat=mat_clamp)
    return parts


# ───────────────────────────── pipe ─────────────────────────────

def pipe_upper():
    """Yellow utility main (R03): rises out of the floor, runs one tile along X and dives back
    down; rusty flanges, a floor bracket, a red valve wheel, a gauge and a thin conduit beside it."""
    r = 0.07
    H = 0.56
    parts = [pipe_run([(-0.42, 0, 0.0), (-0.42, 0, H), (0.42, 0, H), (0.42, 0, 0.0)], r, "paint_yellow", bend=0.15)]
    for x in (-0.42, 0.42):
        parts.append(flange_z(x, 0, 0.02, r + 0.04, t=0.04))
        parts += rivets([(x + math.cos(a) * (r + 0.025), math.sin(a) * (r + 0.025), 0.045)
                         for a in (0.4, 2.0, 3.6, 5.2)], r=0.011, axis="z", mat="metal_dark")
        parts.append(flange_z(x, 0, 0.3, r + 0.02, t=0.035))
    parts.append(flange_x(0.02, 0, H, r + 0.025, t=0.035))
    parts.append(flange_x(0.07, 0, H, r + 0.025, t=0.035))
    parts += clamp_post(0.24, 0, H, r)
    # Valve: stem, gland, wheel with spokes.
    vx = -0.17
    parts.append(L.cyl(0.03, 0.08, loc=(vx, 0, H + r + 0.03), mat="metal_dark", n=10))
    parts.append(L.cyl(0.018, 0.08, loc=(vx, 0, H + r + 0.1), mat="metal", n=8))
    wheel_z = H + r + 0.13
    parts.append(L.torus(0.085, 0.014, loc=(vx, 0, wheel_z), mat="red_paint", n=20, m=6))
    for a in (0, 60, 120):
        parts.append(L.box((0.17, 0.016, 0.012), (vx, 0, wheel_z), rot=(0, 0, a), mat="red_paint"))
    parts.append(L.cyl(0.022, 0.026, loc=(vx, 0, wheel_z), mat="metal_dark", n=8))
    # Pressure gauge on the left riser, facing front.
    parts.append(L.cyl(0.018, 0.06, loc=(-0.42, -r - 0.02, 0.42), rot=(90, 0, 0), mat="metal", n=8))
    parts.append(L.cyl(0.055, 0.03, loc=(-0.42, -r - 0.06, 0.42), rot=(90, 0, 0), mat="brass", n=16, bev=0.005))
    parts.append(L.cyl(0.045, 0.006, loc=(-0.42, -r - 0.076, 0.42), rot=(90, 0, 0), mat="casing", n=16))
    parts.append(L.box((0.006, 0.004, 0.04), (-0.42, -r - 0.08, 0.43), rot=(0, 35, 0), mat="red_paint"))
    # Thin conduit following the main a little behind it, clipped to it.
    cr = 0.022
    parts.append(pipe_run([(-0.34, 0.12, 0.0), (-0.34, 0.12, H - 0.08), (0.36, 0.12, H - 0.08),
                           (0.36, 0.12, 0.0)], cr, "metal_dark", bend=0.07, res=2))
    for x in (-0.05, 0.3):
        parts.append(L.box((0.03, 0.14, 0.03), (x, 0.06, H - 0.08), mat="metal"))
    body = L.join(parts, "Body")
    return [L.finish(body, smooth_angle=40)]


def pipe_lower():
    """Heavy conduit (R04): a fat dark pipe out of an inscribed floor socket, a big elbow, a run
    along X with neon coupling rings and hazard-banded clamps, back down into a second socket."""
    r = 0.11
    H = 0.62
    parts = [pipe_run([(-0.36, 0, 0.0), (-0.36, 0, H), (0.36, 0, H), (0.36, 0, 0.0)], r, "metal", bend=0.24)]
    for x in (-0.36, 0.36):
        parts.append(L.box((0.3, 0.3, 0.06), (x, 0, 0.03), mat="metal_dark", bev=0.015))
        parts.append(L.cyl(r + 0.035, 0.12, loc=(x, 0, 0.12), mat="metal_dark", n=16, bev=0.01))
        parts.append(L.cyl(r + 0.012, 0.03, loc=(x, 0, 0.2), mat="neon_glow", n=16))
        parts += rivets([(x + sx * 0.11, sy * 0.11, 0.065) for sx in (-1, 1) for sy in (-1, 1)], r=0.013,
                        axis="z", mat="paint_yellow")
    # Couplings on the run: ribbed collars with a glowing core ring.
    for x in (-0.08, 0.12):
        parts.append(flange_x(x - 0.035, 0, H, r + 0.03, mat="metal_dark", t=0.035))
        parts.append(L.cyl(r + 0.012, 0.035, loc=(x, 0, H), rot=(0, 90, 0), mat="neon_glow", n=16))
        parts.append(flange_x(x + 0.035, 0, H, r + 0.03, mat="metal_dark", t=0.035))
    # Hazard-striped saddle clamp over the top.
    parts.append(L.hazard_box((0.09, 2 * r + 0.06, 0.05), (0.26, 0, H + r + 0.01), period=0.06,
                              direction=(0, 1, 1)))
    # Inscription strip along the run's front face.
    for k, (x, a) in enumerate(((-0.22, 0), (-0.19, 50), (0.0, 0), (0.03, -50), (0.06, 0))):
        parts.append(L.box((0.012, 0.01, 0.07), (x, -r - 0.002, H), rot=(0, a, 0), mat="rune_glow"))
    body = L.join(parts, "Body")
    return [L.finish(body, smooth_angle=40)]


# ───────────────────────────── console ─────────────────────────────

def keys_grid(cols, rows, x0, x1, y0, y1, z, rot_x, mat="casing", key=0.032):
    out = []
    for i in range(cols):
        for j in range(rows):
            x = x0 + (x1 - x0) * (i + 0.5) / cols
            y = y0 + (y1 - y0) * (j + 0.5) / rows
            out.append(L.box((key, key * 0.9, 0.014), (x, y, z), mat=mat, bev=0.003))
    return out


def console_upper():
    """Scavenger terminal (R03): a chunky CRT bolted onto a yellow utility cabinet, keyboard
    shelf, cassette slot, antenna and patch cables. "Screen" is the CRT face."""
    parts = []
    z0 = 0.03  # cabinet sits on rubber feet
    parts.append(paneled_box((0.62, 0.42, 0.5), (0, 0.02, z0 + 0.25), body="paint_yellow", frame="metal_dark",
                             inset=0.045, depth=0.015, faces=("x", "y"), bev=0.012, name="cab"))
    parts.append(L.box((0.66, 0.46, 0.04), (0, 0.02, z0 + 0.52), mat="metal_dark", bev=0.01))
    # Louvres on the right side.
    for k in range(4):
        parts.append(L.box((0.012, 0.26, 0.022), (0.318, 0.02, z0 + 0.14 + k * 0.06), rot=(25, 0, 0),
                           mat="metal_dark"))
    # Cassette deck slot in the cabinet front.
    parts.append(L.box((0.24, 0.02, 0.07), (-0.08, -0.195, z0 + 0.3), mat="metal_dark", bev=0.006))
    parts.append(L.box((0.18, 0.012, 0.022), (-0.08, -0.208, z0 + 0.3), mat="hazard_dark"))
    for k in range(3):
        parts.append(L.box((0.035, 0.03, 0.025), (0.12 + k * 0.045, -0.2, z0 + 0.3),
                           mat="red_paint" if k == 0 else "casing", bev=0.004))
    # Keyboard shelf: a slab tilted toward the viewer with a grid of keys on it.
    shelf_m = L.xform((0, -0.27, z0 + 0.45), (-12, 0, 0))
    kb = L.box((0.56, 0.2, 0.05), (0, 0, 0.025), mat="casing", bev=0.008)
    keys = L.join(keys_grid(9, 3, -0.23, 0.23, -0.075, 0.075, 0.057, 0), "keys")
    for o in (kb, keys):
        L.transform_obj(o, shelf_m)
    parts += [kb, keys]
    # Brackets under the shelf.
    for sx in (-1, 1):
        parts.append(L.prism([(0.0, 0.0), (0.0, 0.1), (-0.12, 0.1)], 0.03, loc=(sx * 0.22, -0.19, z0 + 0.34),
                             rot=(0, 0, 90), mat="metal_dark"))
    # CRT: tapered box body, bezel, recessed screen.
    crt_c = Vector((0.02, 0.06, z0 + 0.54))
    shell = L.box((0.44, 0.34, 0.36), (crt_c.x, crt_c.y + 0.02, crt_c.z + 0.18), mat="casing", bev=0.03, seg=2)
    back = L.box((0.32, 0.18, 0.26), (crt_c.x, crt_c.y + 0.26, crt_c.z + 0.17), mat="casing", bev=0.03, seg=2,
                 taper=(0.8, 0.8))
    parts += [shell, back]
    parts.append(L.box((0.38, 0.03, 0.29), (crt_c.x, crt_c.y - 0.15, crt_c.z + 0.185), mat="metal_dark", bev=0.012))
    screen = L.screen_quad("Screen", 0.31, 0.22, loc=(crt_c.x, crt_c.y - 0.168, crt_c.z + 0.19))
    # Knobs and a status LED under the screen.
    for k in range(2):
        parts.append(L.cyl(0.018, 0.02, loc=(crt_c.x + 0.12 + k * 0.045, crt_c.y - 0.16, crt_c.z + 0.035),
                           rot=(90, 0, 0), mat="metal_dark", n=10))
    parts.append(L.box((0.03, 0.012, 0.014), (crt_c.x - 0.13, crt_c.y - 0.162, crt_c.z + 0.035), mat="led_glow"))
    # Antenna: a bent rod with a tip bead, taped to the CRT.
    parts.append(L.tube([(crt_c.x - 0.15, crt_c.y + 0.1, crt_c.z + 0.36), (crt_c.x - 0.2, crt_c.y + 0.12, crt_c.z + 0.6),
                         (crt_c.x - 0.12, crt_c.y + 0.16, crt_c.z + 0.78)], 0.008, mat="metal", res=1))
    parts.append(L.sphere(0.022, loc=(crt_c.x - 0.12, crt_c.y + 0.16, crt_c.z + 0.79), mat="red_paint", subdiv=1))
    parts.append(L.box((0.06, 0.07, 0.03), (crt_c.x - 0.15, crt_c.y + 0.1, crt_c.z + 0.365), mat="graffiti"))
    # Patch cables looping from the CRT back down the cabinet side to the floor.
    parts.append(L.tube([(crt_c.x + 0.1, crt_c.y + 0.34, crt_c.z + 0.15), (0.2, 0.36, 0.45), (0.33, 0.3, 0.3),
                         (0.36, 0.2, 0.08), (0.42, 0.05, 0.015)], 0.016, mat="rubber", res=1))
    parts.append(L.tube([(crt_c.x - 0.05, crt_c.y + 0.34, crt_c.z + 0.1), (-0.1, 0.34, 0.35), (-0.3, 0.32, 0.1),
                         (-0.4, 0.22, 0.015)], 0.013, mat="red_paint", res=1))
    # Feet.
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(L.cyl(0.03, 0.03, loc=(sx * 0.26, 0.02 + sy * 0.16, 0.015), mat="rubber", n=8))
    body = L.join(parts, "Body")
    return [L.finish(body), screen]


def console_lower():
    """Inscribed terminal (R04): a slanted plated cabinet with a hooded screen, a control deck of
    lit buttons, neon edge strips and an etched glyph panel. "Screen" is the slanted display."""
    W = 0.62
    # Side profile in (y, z): back, roof, hood, screen leaning back under the hood, control desk.
    prof = [(0.22, 0.0), (0.22, 1.0), (0.04, 1.06), (-0.16, 0.98), (-0.16, 0.93), (-0.04, 0.9), (-0.1, 0.62),
            (-0.32, 0.56), (-0.32, 0.5), (-0.2, 0.46), (-0.2, 0.0)]
    cheek_prof = [(0.24, 0.0), (0.24, 1.03), (0.04, 1.09), (-0.19, 0.99), (-0.19, 0.91), (-0.13, 0.6),
                  (-0.35, 0.57), (-0.35, 0.47), (-0.22, 0.44), (-0.22, 0.0)]
    # prism() extrudes an (x, z) outline along Y; a quarter turn about Z makes outline-x the depth (Y).
    body_core = L.prism(prof, W - 0.08, mat="metal", bev=0.012)
    L.place(body_core, rot=(0, 0, 90))
    parts = [body_core]
    for sx in (-1, 1):
        cheek = L.prism(cheek_prof, 0.05, mat="metal_dark", bev=0.012)
        L.place(cheek, rot=(0, 0, 90))
        L.place(cheek, (sx * (W / 2 - 0.02), 0, 0))
        parts.append(cheek)
        # Neon strip running up the front edge of each cheek.
        x = sx * (W / 2 + 0.008)
        parts.append(L.tube([(x, -0.225, 0.05), (x, -0.225, 0.43), (x, -0.355, 0.47), (x, -0.355, 0.57),
                             (x, -0.135, 0.6), (x, -0.195, 0.91)], 0.012, mat="neon_glow", smooth=False, res=1))
    # Screen bezel and the display on the face from (-0.1, 0.62) up to (-0.04, 0.9).
    dy, dz = 0.06, 0.28
    tilt = -math.degrees(math.atan2(dy, dz))
    ln = math.hypot(dy, dz)
    nrm = Vector((0, -dz / ln, dy / ln))
    mid = Vector((0, -0.07, 0.76))
    parts.append(L.box((0.48, 0.025, 0.28), tuple(mid + nrm * 0.004), rot=(tilt, 0, 0), mat="metal_dark", bev=0.008))
    screen = L.screen_quad("Screen", 0.4, 0.22, loc=tuple(mid + nrm * 0.0175), rot=(tilt, 0, 0))
    # Control deck between (-0.32, 0.56) and (-0.1, 0.62): lit buttons and a stick.
    deck = math.degrees(math.atan2(0.06, 0.22))
    for i, mat in enumerate(("neon_glow", "screen_glow", "paint_yellow", "neon_glow", "screen_glow")):
        x = -0.2 + i * 0.1
        y = -0.17
        z = 0.56 + (y + 0.32) * 0.06 / 0.22 + 0.008
        parts.append(L.cyl(0.026, 0.03, loc=(x, y, z), rot=(deck, 0, 0), mat=mat, n=10))
    parts.append(L.box((0.12, 0.07, 0.03), (0.0, -0.27, 0.575), rot=(deck, 0, 0), mat="metal_dark", bev=0.006))
    parts.append(L.cyl(0.012, 0.07, loc=(0.0, -0.27, 0.62), mat="metal", n=6))
    parts.append(L.sphere(0.026, loc=(0.0, -0.27, 0.66), mat="paint_yellow", subdiv=1))
    # Etched glyph panel on the lower front.
    parts.append(L.box((0.4, 0.015, 0.3), (0, -0.205, 0.24), mat="metal_dark", bev=0.005))
    for x, z, ln, ang in ((-0.12, 0.24, 0.2, 0), (-0.08, 0.3, 0.08, 45), (-0.08, 0.18, 0.08, -45), (0.0, 0.24, 0.2, 0),
                          (0.06, 0.3, 0.1, 0), (0.1, 0.24, 0.12, 90), (0.14, 0.18, 0.08, 0)):
        parts.append(L.box((0.014, 0.01, ln), (x, -0.214, z), rot=(0, ang, 0), mat="rune_glow"))
    # Hood light bar and a base plinth with hazard stripes.
    parts.append(L.box((W - 0.1, 0.03, 0.02), (0, -0.14, 0.92), mat="screen_glow"))
    parts.append(L.hazard_box((W + 0.06, 0.48, 0.06), (0, 0.01, 0.03), period=0.1, bev=0.008))
    # Cable bundle out the back into the floor.
    for k, x in enumerate((-0.12, 0.0, 0.12)):
        parts.append(L.tube([(x, 0.2, 0.7), (x, 0.32, 0.55), (x + 0.03, 0.34, 0.2), (x + 0.05, 0.42, 0.015)],
                            0.018, mat="rubber" if k != 1 else "neon_glow", res=1))
    body = L.join(parts, "Body")
    return [L.finish(body), screen]


# ───────────────────────────── generator ─────────────────────────────

def _drum_x(r, length, mat, cap_mat, ribs=3, rib_mat=None, centre=(0, 0, 0)):
    cx, cy, cz = centre
    parts = [L.cyl(r, length, loc=centre, rot=(0, 90, 0), mat=mat, n=20)]
    for sgn in (-1, 1):
        cap = L.lathe([(0.0, 0.07), (r * 0.55, 0.06), (r * 0.92, 0.03), (r + 0.02, 0.0), (r + 0.02, -0.03), (0, -0.03)],
                      mat=cap_mat, n=20)
        L.place(cap, (cx + sgn * length / 2, cy, cz), (0, 90 * sgn, 0))
        parts.append(cap)
    for k in range(ribs):
        x = cx - length / 2 + length * (k + 1) / (ribs + 1)
        parts.append(L.torus(r + 0.006, 0.012, loc=(x, cy, cz), rot=(0, 90, 0), mat=rib_mat or cap_mat, n=24, m=4,
                             square=True))
    return parts


def generator_upper():
    """Field generator (R03 modules): a yellow tank on a hazard-striped skid, a radiator with a
    spinning "Fan" (origin on its hub, axis = local X), control box with gauge and lamp,
    an exhaust stack and a fuel line."""
    parts = []
    parts.append(L.hazard_box((0.92, 0.58, 0.08), (0, 0, 0.04), period=0.12, bev=0.008))
    for sy in (-1, 1):
        parts.append(L.box((0.94, 0.05, 0.05), (0, sy * 0.24, 0.105), mat="metal_dark", bev=0.008))
    # Saddles.
    for x in (-0.22, 0.18):
        parts.append(L.prism([(-0.22, 0.0), (0.22, 0.0), (0.16, 0.2), (-0.16, 0.2)], 0.06, loc=(x, 0, 0.08),
                             rot=(0, 0, 90), mat="metal_dark", bev=0.008))
    centre = (-0.04, 0.0, 0.38)
    parts += _drum_x(0.23, 0.62, "paint_yellow", "rust", ribs=2, rib_mat="metal_dark", centre=centre)
    # Stencil star on the tank.
    parts.append(star(0.07, (-0.04, -0.235, 0.4), mat="hazard_dark", depth=0.01))
    # Radiator housing at +X with fan grille.
    rx = 0.36
    rad = paneled_box((0.16, 0.5, 0.5), (rx, 0, 0.35), body="metal", frame="metal_dark", inset=0.03,
                      depth=0.01, faces=("y", "top"), bev=0.01, name="rad")
    cutter = L.cyl(0.19, 0.1, loc=(rx + 0.08, 0, 0.35), rot=(0, 90, 0), mat="metal_dark", n=24)
    mod = rad.modifiers.new("Cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    mod.solver = "EXACT"
    rad = L.apply_modifiers(rad)
    import bpy
    bpy.data.objects.remove(cutter, do_unlink=True)
    parts.append(rad)
    parts.append(L.cyl(0.19, 0.02, loc=(rx - 0.02, 0, 0.35), rot=(0, 90, 0), mat="mortar", n=24))
    parts.append(L.torus(0.19, 0.018, loc=(rx + 0.085, 0, 0.35), rot=(0, 90, 0), mat="metal_dark", n=24, m=6))
    for a in (0, 90):
        parts.append(L.box((0.012, 0.38, 0.016), (rx + 0.09, 0, 0.35), rot=(a, 0, 0), mat="metal_dark"))
    fan = L.fan_blades(0.17, n=5, hub=0.04, mat="metal", name="Fan")
    fan.data.transform(L.xform(rot=(0, 0, 90)))      # rotor axis local Y -> X
    fan.location = (rx + 0.06, 0, 0.35)
    # Control box on top with a gauge, a warm indicator and switches.
    parts.append(L.box((0.26, 0.2, 0.16), (-0.14, 0.02, 0.66), mat="metal", bev=0.015))
    parts.append(L.cyl(0.045, 0.02, loc=(-0.19, -0.085, 0.67), rot=(90, 0, 0), mat="brass", n=14))
    parts.append(L.cyl(0.036, 0.006, loc=(-0.19, -0.097, 0.67), rot=(90, 0, 0), mat="casing", n=14))
    parts.append(L.cyl(0.022, 0.03, loc=(-0.08, -0.085, 0.69), rot=(90, 0, 0), mat="warm_glow", n=10))
    for k in range(2):
        parts.append(L.box((0.016, 0.03, 0.04), (-0.1 + k * 0.04, -0.09, 0.63), rot=(20, 0, 0), mat="metal_dark"))
    # Exhaust stack with a rain cap.
    parts.append(pipe_run([(0.08, 0.1, 0.55), (0.08, 0.1, 0.72), (0.08, 0.16, 0.95)], 0.035, "metal_dark", bend=0.08,
                          res=2))
    parts.append(L.cyl(0.055, 0.025, loc=(0.08, 0.16, 0.97), mat="rust", n=10, r2=0.03))
    # Fuel line from the tank to the floor.
    parts.append(L.tube([(-0.32, -0.12, 0.4), (-0.42, -0.2, 0.3), (-0.46, -0.24, 0.1), (-0.52, -0.3, 0.02)], 0.016,
                        mat="rubber", res=1))
    body = L.join(parts, "Body")
    L.finish(fan, smooth_angle=30)
    return [L.finish(body, smooth_angle=35), fan]


def generator_lower():
    """Chronal capacitor (R04 prop library): a glowing neon cylinder held between two heavy
    plated end housings on a skid, wrapped in a cage, fed by conduits."""
    parts = []
    parts.append(L.hazard_box((0.96, 0.56, 0.07), (0, 0, 0.035), period=0.12, bev=0.008))
    cz = 0.4
    for sx in (-1, 1):
        x = sx * 0.33
        parts.append(paneled_box((0.24, 0.46, 0.62), (x, 0, 0.38), body="metal", frame="metal_dark", inset=0.035,
                                 depth=0.012, faces=("x", "y", "top"), bev=0.015, name="end"))
        parts.append(L.cyl(0.2, 0.05, loc=(x - sx * 0.13, 0, cz), rot=(0, 90, 0), mat="metal_dark", n=20, bev=0.008))
        # Vent slots on the housing top and a neon status bar on the front.
        for k in range(3):
            parts.append(L.box((0.16, 0.02, 0.012), (x, -0.12 + k * 0.08, 0.695), mat="metal_dark"))
        parts.append(L.box((0.04, 0.015, 0.22), (x, -0.235, 0.4), mat="screen_glow"))
        parts += rivets([(x + dx, -0.236, z) for dx in (-0.08, 0.08) for z in (0.15, 0.62)], r=0.012)
    # The core: glass sleeve, glowing tube, and rings.
    parts.append(L.cyl(0.14, 0.44, loc=(0, 0, cz), rot=(0, 90, 0), mat="neon_glow", n=20))
    for x in (-0.1, 0.1):
        parts.append(L.torus(0.16, 0.016, loc=(x, 0, cz), rot=(0, 90, 0), mat="paint_yellow", n=24, m=4, square=True))
    # Cage bars.
    for k in range(6):
        a = 2 * math.pi * k / 6 + 0.3
        parts.append(L.cyl(0.012, 0.44, loc=(0, math.cos(a) * 0.185, cz + math.sin(a) * 0.185), rot=(0, 90, 0),
                           mat="metal_dark", n=6))
    # Conduits from the housings down into the floor at the back.
    for sx in (-1, 1):
        parts.append(L.tube([(sx * 0.33, 0.22, 0.5), (sx * 0.36, 0.34, 0.4), (sx * 0.38, 0.38, 0.12),
                             (sx * 0.4, 0.44, 0.015)], 0.025, mat="rubber", res=1))
    body = L.join(parts, "Body")
    return [L.finish(body, smooth_angle=35)]


# ───────────────────────────── vent ─────────────────────────────

def vent_upper():
    """The R03 air-conditioner: a pale rounded casing on feet, round fan grille on the front
    with the "Fan" rotor behind it (origin on the hub, axis = local Godot Z), side louvres,
    copper lines to the floor and a rust streak."""
    W, D, H = 0.66, 0.4, 0.58
    z0 = 0.06
    shell = L.box((W, D, H), (0, 0, z0 + H / 2), mat="casing", bev=0.05, seg=3)
    # Hollow the grille opening: inset the front face region with a cylinder boolean.
    cutter = L.cyl(0.22, 0.2, loc=(-0.06, -D / 2, z0 + H / 2), rot=(90, 0, 0), mat="metal_dark", n=28)
    mod = shell.modifiers.new("Cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    mod.solver = "EXACT"
    shell = L.apply_modifiers(shell)
    import bpy
    bpy.data.objects.remove(cutter, do_unlink=True)
    parts = [shell]
    cx, cz = -0.06, z0 + H / 2
    # Recess back wall (dark) inside the opening.
    parts.append(L.cyl(0.225, 0.02, loc=(cx, -D / 2 + 0.1, cz), rot=(90, 0, 0), mat="mortar", n=28))
    # Grille: rings + cross bars at the front.
    for rr in (0.22, 0.15, 0.08):
        parts.append(L.torus(rr, 0.01, loc=(cx, -D / 2 - 0.004, cz), rot=(90, 0, 0), mat="metal", n=28, m=4))
    for a in (0, 90):
        parts.append(L.box((0.44, 0.012, 0.016), (cx, -D / 2 - 0.004, cz), rot=(0, a, 0), mat="metal"))
    fan = L.fan_blades(0.19, n=3, hub=0.045, mat="metal", hub_mat="metal_dark", name="Fan", chord=0.14)
    fan.location = (cx, -D / 2 + 0.06, cz)
    # Side louvres (+X face) and a control strip on the front right.
    for k in range(6):
        parts.append(L.box((0.02, D - 0.1, 0.022), (W / 2 + 0.004, 0, z0 + 0.12 + k * 0.07), rot=(-30, 0, 0),
                           mat="metal"))
    parts.append(L.box((0.09, 0.02, 0.4), (0.23, -D / 2 - 0.004, cz), mat="metal", bev=0.006))
    parts.append(L.box((0.05, 0.012, 0.03), (0.23, -D / 2 - 0.012, cz + 0.12), mat="led_glow"))
    for k in range(3):
        parts.append(L.box((0.05, 0.012, 0.012), (0.23, -D / 2 - 0.012, cz - 0.02 - k * 0.04), mat="metal_dark"))
    # Feet and copper refrigerant lines.
    for sx in (-1, 1):
        parts.append(L.box((0.08, D + 0.04, 0.06), (sx * 0.24, 0, 0.03), mat="metal_dark", bev=0.01))
    for k, dz in enumerate((0.0, 0.07)):
        parts.append(pipe_run([(W / 2 - 0.02, 0.1 + k * 0.05, z0 + 0.2 + dz), (W / 2 + 0.08, 0.1 + k * 0.05, z0 + 0.2 + dz),
                               (W / 2 + 0.08, 0.1 + k * 0.05, 0.0)], 0.016, "brass", bend=0.04, res=1))
    body = L.join(parts, "Body")
    L.finish(fan)
    return [L.finish(body, smooth_angle=35), fan]


def vent_lower():
    """Turbine vent (R04): a heavy square frame standing on the floor holding a big round fan
    behind spokes, with a hot orange rim glow and hazard corners. "Fan" spins about local Godot Z."""
    S, D = 0.82, 0.3
    cz = S / 2 + 0.04
    frame = paneled_box((S, D, S), (0, 0, cz), body="metal", frame="metal_dark", inset=0.05, depth=0.012,
                        faces=("x", "top"), bev=0.02, name="frame")
    cutter = L.cyl(0.32, D + 0.2, loc=(0, 0, cz), rot=(90, 0, 0), mat="metal_dark", n=32)
    mod = frame.modifiers.new("Cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    mod.solver = "EXACT"
    frame = L.apply_modifiers(frame)
    import bpy
    bpy.data.objects.remove(cutter, do_unlink=True)
    parts = [frame]
    # Shroud ring lining the hole, glowing rim behind it, and a back plate.
    parts.append(L.lathe([(0.32, -D / 2 - 0.01), (0.345, -D / 2 - 0.02), (0.345, -D / 2 + 0.01), (0.32, D / 2 - 0.02),
                          (0.3, D / 2 - 0.02)], mat="metal_dark", n=32, loc=(0, 0, cz), rot=(-90, 0, 0)))
    parts.append(L.torus(0.3, 0.02, loc=(0, 0.03, cz), rot=(90, 0, 0), mat="warm_glow", n=32, m=6))
    parts.append(L.cyl(0.31, 0.02, loc=(0, D / 2 - 0.03, cz), rot=(90, 0, 0), mat="mortar", n=32))
    # Front spokes and hub cap.
    for k in range(6):
        parts.append(L.box((0.64, 0.016, 0.026), (0, -D / 2 + 0.005, cz), rot=(0, 30 * k, 0), mat="metal_dark"))
    parts.append(L.cyl(0.07, 0.04, loc=(0, -D / 2 + 0.0, cz), rot=(90, 0, 0), mat="paint_yellow", n=16, bev=0.008))
    fan = L.fan_blades(0.29, n=7, hub=0.08, pitch=32, mat="metal", hub_mat="metal_dark", name="Fan", chord=0.16)
    fan.location = (0, 0.0, cz)
    # Hazard corners and feet.
    for sx in (-1, 1):
        for sz in (0, 1):
            parts.append(L.hazard_box((0.14, D + 0.02, 0.14), (sx * (S / 2 - 0.07), 0, 0.04 + 0.07 + sz * (S - 0.14)),
                                      period=0.07, bev=0.01))
        parts.append(L.box((0.2, D + 0.14, 0.04), (sx * (S / 2 - 0.12), 0, 0.02), mat="metal_dark", bev=0.01))
    # Inscribed band across the top with a glyph line.
    for k, (x, a) in enumerate(((-0.12, 0), (-0.06, 60), (0.0, 0), (0.06, -60), (0.12, 0))):
        parts.append(L.box((0.014, 0.01, 0.07), (x, -D / 2 - 0.006, S - 0.02), rot=(0, a, 0), mat="rune_glow"))
    body = L.join(parts, "Body")
    L.finish(fan)
    return [L.finish(body, smooth_angle=35), fan]


# ───────────────────────────── lamp ─────────────────────────────

def lamp_upper():
    """Hanging lantern on a pipe post (R03 prop library): bolted foot, post, curled arm, a caged
    lantern with a warm glowing core and a pull chain of beads."""
    parts = [L.box((0.28, 0.28, 0.05), (0, 0, 0.025), mat="metal_dark", bev=0.012)]
    parts += rivets([(sx * 0.1, sy * 0.1, 0.052) for sx in (-1, 1) for sy in (-1, 1)], r=0.012, axis="z", mat="metal")
    parts.append(L.cyl(0.05, 0.12, loc=(0, 0, 0.1), mat="paint_yellow", n=12, r2=0.035))
    parts.append(L.cyl(0.04, 1.32, loc=(0, 0, 0.78), mat="paint_yellow", n=12))
    parts.append(L.cyl(0.04, 0.04, loc=(0, 0, 0.6), mat="metal_dark", n=12))
    # Arm: up, curl over and out toward the front-right with a hook.
    arm = [(0, 0, 1.42), (0.0, 0, 1.5), (0.1, -0.08, 1.56), (0.24, -0.18, 1.5), (0.26, -0.2, 1.42)]
    parts.append(L.tube(arm, 0.03, mat="paint_yellow", res=1))
    parts.append(L.sphere(0.035, loc=(0, 0, 1.44), mat="metal_dark", subdiv=1))
    # Lantern hanging under the hook (sized to read at game scale).
    lx, ly, lz = 0.26, -0.2, 1.1
    k = 1.45
    parts.append(L.torus(0.035, 0.01, loc=(lx, ly, 1.4), rot=(90, 0, 30), mat="metal_dark", n=10, m=4))
    parts.append(L.lathe([(0.0, 0.22 * k), (0.05 * k, 0.2 * k), (0.12 * k, 0.13 * k), (0.13 * k, 0.11 * k),
                          (0.0, 0.11 * k)], loc=(lx, ly, lz), mat="metal_dark", n=12))
    parts.append(L.cyl(0.11 * k, 0.04, loc=(lx, ly, lz - 0.1 * k), mat="metal_dark", n=12))
    parts.append(L.cyl(0.085 * k, 0.2 * k, loc=(lx, ly, lz), mat="warm_glow", n=12))
    for i in range(6):
        a = 2 * math.pi * i / 6
        parts.append(L.cyl(0.011, 0.22 * k, loc=(lx + math.cos(a) * 0.1 * k, ly + math.sin(a) * 0.1 * k, lz),
                           mat="metal_dark", n=5))
    parts.append(L.torus(0.1 * k, 0.012, loc=(lx, ly, lz + 0.02), mat="metal_dark", n=14, m=4))
    # Bead pull-chain.
    for k in range(5):
        parts.append(L.sphere(0.012, loc=(lx + 0.06, ly, lz - 0.2 - k * 0.03), mat="brass", subdiv=1))
    # Cable taped down the post.
    parts.append(L.tube([(0.035, 0.02, 1.38), (0.04, 0.03, 0.8), (0.05, 0.03, 0.2), (0.15, 0.08, 0.015)], 0.012,
                        mat="rubber", res=1))
    body = L.join(parts, "Body")
    return [L.finish(body, smooth_angle=40)]


def lamp_lower():
    """Utility floodlight (R04): an I-beam post on a hazard-striped plinth with a caged lamp head
    tilted down toward the front, a neon status ring and a conduit."""
    parts = [L.hazard_box((0.32, 0.32, 0.1), (0, 0, 0.05), period=0.08, bev=0.012)]
    # I-beam: web + two flanges.
    parts.append(L.box((0.02, 0.1, 1.25), (0, 0, 0.72), mat="metal"))
    for sx in (-1, 1):
        parts.append(L.box((0.1, 0.012, 1.25), (0, sx * 0.05, 0.72), mat="metal"))
    parts.append(L.cyl(0.075, 0.03, loc=(0, 0, 0.5), mat="neon_glow", n=14))
    parts.append(L.box((0.46, 0.1, 0.05), (0, -0.02, 1.33), mat="metal_dark", bev=0.01))
    # Lamp head: tapered box housing, glowing face, cage bars, yoke.
    head_c = Vector((0, -0.06, 1.44))
    rot = (-35, 0, 0)
    housing = L.box((0.3, 0.2, 0.18), (0, 0, 0), mat="metal_dark", bev=0.02, taper=(1.0, 1.0))
    face = L.box((0.25, 0.02, 0.13), (0, -0.105, 0), mat="warm_glow")
    bars = [L.box((0.012, 0.03, 0.15), (x, -0.125, 0), mat="metal") for x in (-0.08, 0.0, 0.08)]
    rim = L.box((0.29, 0.03, 0.17), (0, -0.1, 0), mat="metal", bev=0.006)
    # Make the rim a frame: cut its centre with a boolean.
    cut = L.box((0.25, 0.1, 0.13), (0, -0.1, 0), mat="metal")
    mod = rim.modifiers.new("Cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cut
    mod.solver = "EXACT"
    rim = L.apply_modifiers(rim)
    import bpy
    bpy.data.objects.remove(cut, do_unlink=True)
    fins = [L.box((0.012, 0.06, 0.16), (x, 0.12, 0), mat="metal") for x in (-0.1, -0.05, 0.0, 0.05, 0.1)]
    head = L.join([housing, face, rim] + bars + fins, "head")
    L.place(head, tuple(head_c), rot, scale=1.3)
    parts.append(head)
    # Yoke arms.
    for sx in (-1, 1):
        parts.append(L.box((0.02, 0.06, 0.2), (sx * 0.21, -0.04, 1.42), mat="metal", bev=0.004))
        parts.append(L.cyl(0.03, 0.03, loc=(sx * 0.215, -0.06, 1.44), rot=(0, 90, 0), mat="paint_yellow", n=10))
    # Conduit down the beam into the floor.
    parts.append(L.tube([(0.03, 0.08, 1.33), (0.04, 0.09, 0.9), (0.04, 0.09, 0.2), (0.1, 0.2, 0.015)], 0.016,
                        mat="rubber", res=1))
    body = L.join(parts, "Body")
    return [L.finish(body, smooth_angle=35)]


# ───────────────────────────── neon ─────────────────────────────

def neon():
    """A standing neon tube fixture (R03 / R04): a glowing tube in a glass sleeve between two
    finned caps, a yellow cage and a weighted foot. The game tints neon_glow per DecorDef.variant."""
    parts = [L.lathe([(0.0, 0.0), (0.19, 0.0), (0.19, 0.04), (0.15, 0.07), (0.0, 0.07)], mat="metal_dark", n=8)]
    for z, flip in ((0.07, False), (1.02, True)):
        cap = L.lathe([(0.0, 0.0), (0.11, 0.0), (0.12, 0.02), (0.12, 0.08), (0.09, 0.11), (0.0, 0.11)], mat="metal",
                      n=12)
        if flip:
            L.place(cap, (0, 0, 1.13), (180, 0, 0))
        else:
            L.place(cap, (0, 0, z))
        parts.append(cap)
        # Cooling fins.
        zz = z + 0.055 if not flip else 1.13 - 0.055
        for k in range(6):
            parts.append(L.box((0.05, 0.012, 0.07), (math.cos(k * math.pi / 3) * 0.13, math.sin(k * math.pi / 3) * 0.13, zz),
                               rot=(0, 0, k * 60), mat="metal_dark"))
    parts.append(L.cyl(0.075, 0.86, loc=(0, 0, 0.6), mat="neon_glow", n=14))
    # Cage: four bars and two rings.
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        parts.append(L.cyl(0.012, 0.86, loc=(math.cos(a) * 0.115, math.sin(a) * 0.115, 0.6), mat="paint_yellow", n=6))
    for z in (0.35, 0.85):
        parts.append(L.torus(0.115, 0.012, loc=(0, 0, z), mat="paint_yellow", n=16, m=4))
    # Top contact and a short cable to the floor.
    parts.append(L.cyl(0.02, 0.06, loc=(0, 0, 1.16), mat="brass", n=8))
    parts.append(L.tube([(0.12, 0.05, 0.05), (0.2, 0.1, 0.03), (0.3, 0.06, 0.012)], 0.012, mat="rubber", res=1))
    body = L.join(parts, "Body")
    return [L.finish(body, smooth_angle=35)]


# ───────────────────────────── cable ─────────────────────────────

def cable():
    """A cable spool (R03 prop library) standing on its rim with a loose run snaking off across
    the floor to a yellow plug."""
    rng = random.Random(9)
    parts = []
    R = 0.22
    W = 0.24
    sc = (-0.15, 0.05, R)
    for sx in (-1, 1):
        parts.append(L.lathe([(0.0, -0.02), (R, -0.02), (R, 0.02), (0.06, 0.02), (0.06, 0.03), (0.0, 0.03)],
                             loc=(sc[0] + sx * W / 2, sc[1], sc[2]), rot=(0, 90 * sx, 0), mat="graffiti", n=20))
        parts += [L.cyl(0.03, 0.03, loc=(sc[0] + sx * (W / 2 + 0.025), sc[1], sc[2]), rot=(0, 90, 0), mat="metal_dark", n=8)]
        for k in range(4):
            a = k * math.pi / 2 + 0.4
            parts.append(L.cyl(0.03, 0.03, loc=(sc[0] + sx * (W / 2 + 0.005), sc[1] + math.cos(a) * 0.13,
                                                sc[2] + math.sin(a) * 0.13), rot=(0, 90, 0), mat="mortar", n=8))
    parts.append(L.cyl(0.07, W, loc=sc, rot=(0, 90, 0), mat="metal_dark", n=12))
    # Wound coil: a helix of cable around the drum.
    turns = 6
    layers = [0.12, 0.155]
    for li, rad in enumerate(layers):
        pts = []
        steps = turns * 12
        for k in range(steps + 1):
            t = k / steps
            a = t * turns * 2 * math.pi
            x = sc[0] - W / 2 + 0.035 + t * (W - 0.07) if li == 0 else sc[0] + W / 2 - 0.035 - t * (W - 0.07)
            pts.append((x, sc[1] + math.cos(a) * rad, sc[2] + math.sin(a) * rad))
        parts.append(L.tube(pts, 0.022, mat="rubber", res=1, smooth=False))
    # Loose run off the bottom of the spool across the floor.
    run = [(sc[0] + 0.06, sc[1] - 0.15, 0.06), (sc[0] + 0.1, sc[1] - 0.24, 0.02), (0.05, -0.28, 0.018),
           (0.22, -0.12, 0.018), (0.2, 0.12, 0.018), (0.36, 0.22, 0.018), (0.42, 0.05, 0.018)]
    parts.append(L.tube(run, 0.022, mat="rubber", res=1, resolution_u=8))
    # Plug: yellow body with prongs.
    parts.append(L.box((0.09, 0.06, 0.05), (0.45, -0.04, 0.03), rot=(0, 0, -70), mat="paint_yellow", bev=0.01))
    for d in (-0.012, 0.012):
        parts.append(L.box((0.008, 0.04, 0.012), (0.47 + d, -0.1, 0.03), rot=(0, 0, -70), mat="brass"))
    body = L.join(parts, "Body")
    return [L.finish(body, smooth_angle=40)]


# ───────────────────────────── wave screen ─────────────────────────────

def wave_screen():
    """A waveform monitor on legs (R03 / R04): bolted frame with a sun hood, speaker pods either
    side and the "Screen" (0.86 x 0.5, clean 0-1 UVs) the game draws the music's waveform on."""
    W, H, D = 1.0, 0.66, 0.14
    zc = 0.78
    frame = L.box((W, D, H), (0, 0, zc), mat="metal", bev=0.03, seg=2)
    # Recess the front: inset the front face and push it in to make a bezel.
    import bpy
    bm = bmesh.new()
    bm.from_mesh(frame.data)
    front = [f for f in bm.faces if f.normal.y < -0.9 and f.calc_area() > 0.3]
    if front:
        bmesh.ops.inset_individual(bm, faces=front, thickness=0.06, depth=-0.035)
        for f in front:
            f.material_index = 0
    bm.to_mesh(frame.data)
    bm.free()
    parts = [frame]
    screen = L.screen_quad("Screen", 0.86, 0.5, loc=(0, -D / 2 + 0.03, zc), cols=4, rows=2)
    # Hood.
    parts.append(L.box((W + 0.04, 0.16, 0.03), (0, -0.07, zc + H / 2 + 0.01), rot=(-12, 0, 0), mat="metal_dark",
                       bev=0.008))
    # Speaker pods.
    for sx in (-1, 1):
        x = sx * (W / 2 + 0.09)
        parts.append(L.box((0.17, 0.16, 0.3), (x, 0, zc - 0.08), mat="metal_dark", bev=0.025, seg=2))
        cone = L.lathe([(0.0, 0.02), (0.025, 0.02), (0.06, -0.005), (0.065, -0.01), (0.065, -0.02), (0.0, -0.02)],
                       mat="mortar", n=16, loc=(x, -0.08, zc - 0.08), rot=(90, 0, 0))
        parts.append(cone)
        parts.append(L.torus(0.065, 0.01, loc=(x, -0.085, zc - 0.08), rot=(90, 0, 0), mat="paint_yellow", n=16, m=4))
    # Legs and feet.
    for sx in (-1, 1):
        parts.append(L.box((0.06, 0.06, zc - H / 2), (sx * 0.34, 0.02, (zc - H / 2) / 2), mat="metal_dark", bev=0.008))
        parts.append(L.box((0.12, 0.34, 0.04), (sx * 0.34, 0.02, 0.02), mat="metal_dark", bev=0.01))
    parts.append(L.box((0.62, 0.05, 0.05), (0, 0.02, 0.2), mat="metal", bev=0.008))
    # Bolts around the bezel and a status LED strip under it.
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.append(L.cyl(0.013, 0.012, loc=(sx * (W / 2 - 0.03), -D / 2 - 0.004, zc + sz * (H / 2 - 0.03)),
                               rot=(90, 0, 0), mat="metal_dark", n=6))
    for k in range(4):
        parts.append(L.box((0.05, 0.012, 0.014), (-0.36 + k * 0.07, -D / 2 - 0.004, zc - H / 2 + 0.018),
                           mat=("led_glow", "neon_glow", "screen_glow", "led_glow")[k]))
    # Power cable from the back to the floor.
    parts.append(L.tube([(0.2, D / 2, zc - 0.2), (0.25, 0.2, 0.3), (0.3, 0.3, 0.015)], 0.016, mat="rubber", res=1))
    body = L.join(parts, "Body")
    return [L.finish(body, smooth_angle=35), screen]
