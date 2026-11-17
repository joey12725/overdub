"""The traps and automated machinery of docs/TRAPS.md as kit pieces (Blender 4.5).

Conventions (the full contract is the "Traps" subsection of docs/GODOT-PORT.md):
  * Coordinates in this file are GODOT coordinates (x right, y up, z forward); see traplib.py.
  * A directional trap acts along +Z at rest. Floor traps have their origin at the centre of their
    cell on the floor. Wall-mounted machines (crusher housing, flame jet, dart launcher) have their
    origin at the centre of THEIR tile (the wall tile named by the entity's c / r, or the tile behind
    cells[0] for a crusher) and hang off that tile's +Z face.
  * Every moving part is its own mesh object whose origin is its pivot, exported in the SAFE pose
    (spikes down, piston home, pad seated). The game sets one transform per part from the snapshot.
  * `*_glow` materials are the state lamps; `warn_glow` is the telegraph on every hazard.
  * No baked actions: every motion is one translation or one scale, driven by the snapshot.
"""
from __future__ import annotations

import math
import random

from mathutils import Matrix, Vector

import traplib as T
from traplib import C, F, S, as_part, chev_strip, face_stripes, floor_border, gbox, gcyl, gframe, gprism, grivet, gtube, gv, lathe, mount, sphere, sty

PIECES = ('trap_spikes', 'trap_crusher', 'trap_crusher_lane', 'trap_crusher_stamper', 'trap_conveyor', 'trap_flame',
          'trap_flame_lane', 'trap_dart', 'trap_dart_lane', 'trap_dart_bolt', 'trap_bumper', 'trap_sensor', 'trap_relay',
          'trap_magnet')
# Pieces whose shape and colours are the same in every theme: one file, no __look suffix.
LOOKLESS = ('trap_dart_bolt',)

FWD, UP = (0, 0, 1), (0, 1, 0)
CORNERS = ((-1, -1), (1, -1), (1, 1), (-1, 1))

# ── numbers the game needs (also written into the manifest and the contract) ──
SPIKE_TIP_Y = 0.62       # raised tips
SPIKE_BASE_Y = -0.02     # Spikes origin: the spike roots, inside the holes
SPIKE_REST = 0.02        # Spikes.scale.y: SPIKE_REST (down, tips below the rim) .. 1 (raised)
SPIKE_XZ = [(-0.3 + ix * 0.2, -0.3 + iz * 0.2) for iz in range(4) for ix in range(4)]

HEAD_HOME_Z = 0.53       # crusher Head.z retracted (its origin is the centre of its front face, on the floor)
HEAD_END_GAP = 0.02      # extended: Head.z = 0.5 + cells - HEAD_END_GAP
HEAD_DEPTH = 0.45
HEAD_TOP = 1.30
RAM_Z = 0.05             # crusher Ram origin (inside the housing); the mesh is 1 unit long along +Z
RAM_INTO_HEAD = 0.35     # Ram.scale.z = Head.z - RAM_INTO_HEAD

STAMP_HOME_Y = 1.30      # stamper Head.y withdrawn (origin = centre of its sole)
STAMP_DOWN_Y = 0.02      # stamper Head.y extended
STAMP_HEAD_H = 0.80
STAMP_ROD_Y = 2.10       # stamper Ram origin (under the gantry); the mesh is 1 unit long along -Y
STAMP_ROD_REST = 0.05    # Ram.scale.y = STAMP_HOME_Y + STAMP_ROD_REST - Head.y

BELT_Y = 0.05            # belt surface height
BELT_HALF_W = 0.392
ROLLER_Y, ROLLER_Z = 0.035, 0.435

NOZZLE_Y = 0.26          # flame axis height
NOZZLE_MOUNT_Z = 0.66
NOZZLE_MOUTH_Z = 0.845   # Jet origin; Jet.scale.z = reach - (NOZZLE_MOUTH_Z - 0.5)

DART_Y = 0.30            # dart lane height
MUZZLE_Z = 0.66
MUZZLE_RECOIL = 0.04
SHUTTER_TRAVEL = 0.095   # Shutter.y: +0 open .. -SHUTTER_TRAVEL closed
DART_FLASH_Z = 0.745
PIPS = 8

PAD_POP = 0.20           # bumper Pad.y = PAD_POP * t
SPRING_Y = -0.02         # Spring origin; Spring.scale.y = SPRING_REST + Pad.y
SPRING_REST = 0.04

SENSOR_Y = 0.32          # beam height
SENSOR_LENS_Z = 0.068
SENSOR_BEAM_Z = 0.08

RELAY_TOP = 0.19
TICKS = 8


def named(ob, name):
    ob.name = name
    ob.data.name = name
    return ob


def floor_chev(name, m, x, z, length, width, y=0.008, **kw):
    """A chevron strip painted on the floor at (x, z), pointing +Z."""
    return mount(chev_strip(name, m, length, width, **kw), gframe(FWD, UP, (x, y, z)))


# ───────────────────────────── 1. spikes ─────────────────────────────

def spikes(m, rng, look):
    st = sty(m, look)
    e = 0.46
    plate = gbox('plate', (-e, -0.04, -e), (e, 0.03, e), st['dark'], bevel=0.012)
    C.boolean(plate, [gcyl(f'h{i}', 0.058, 0.125, (x, 0.0375, z), m('void'), segments=10) for i, (x, z) in enumerate(SPIKE_XZ)])
    base = [plate]
    for i, (x, z) in enumerate(SPIKE_XZ):
        # Glow collar round every hole: brightness = warn, so the tile "heats up" before it bites.
        base.append(F.annulus(f'ring{i}', 0.06, 0.082, 0.029, 0.0345, m('warn_glow'), segs=12, center=(x, -z)))
    base += floor_border('hz', m, 0.388, 0.456, 0.385, 0.0325)
    for i, (sx, sz) in enumerate(CORNERS):
        base.append(gcyl(f'acc{i}', 0.022, 0.014, (sx * 0.422, 0.034, sz * 0.422), m('accent_glow'), segments=8))
    if st['up']:
        base.append(C.moss_pad('moss', rng, tuple(gv((-0.4, 0.03, 0.43))), 0.045, 0.02, m('moss')))
        base.append(gbox('rust', (0.05, 0.0295, -0.22), (0.16, 0.0325, -0.17), m('rust')))
    spk = []
    for i, (x, z) in enumerate(SPIKE_XZ):
        hgt = SPIKE_TIP_Y - SPIKE_BASE_Y
        spk.append(gcyl(f's{i}', 0.048, hgt, (x, SPIKE_BASE_Y + hgt / 2, z), m('steel'), segments=8, radius2=0.004))
    # Growing out of the holes by scale keeps every vertex above the floor slab at all times.
    sp = as_part(spk, 'Spikes', origin=(0, SPIKE_BASE_Y, 0))
    sp.scale = (1, 1, SPIKE_REST)  # Blender Z = Godot Y
    return [as_part(base, 'Base'), sp]


# ───────────────────────────── 2. crusher ─────────────────────────────

def crusher(m, rng, look):
    st = sty(m, look)
    up = st['up']
    h = []
    if up:
        h.append(gbox('plinth', (-0.5, -0.2, -0.5), (0.5, 0.3, 0.05), m('stone'), bevel=0.025,
                      chips=S.block_chips(rng, (1.0, 0.55, 0.5), 0.5), top_mat=m('stone_light')))
    else:
        h.append(gbox('plinth', (-0.5, -0.2, -0.5), (0.5, 0.3, 0.05), m('trim'), bevel=0.02))
    casing = gbox('casing', (-0.48, 0.3, -0.48), (0.48, 1.5, 0.05), st['casing'], bevel=0.02)
    if not up:
        T.side_runes(casing, m, rng, 1, 0.48, 0.215, 1.22, n=1)
        T.side_runes(casing, m, rng, 3, 0.48, -0.215, 1.22, n=1)
    h.append(casing)
    for sx in (-1, 1):
        x0, x1 = (0.45, 0.5) if sx > 0 else (-0.5, -0.45)
        h.append(gbox(f'jamb{sx}', (x0, -0.2, 0.05), (x1, 1.5, 0.5), st['frame'], bevel=0.012))
        for i, y in enumerate((0.3, 0.75, 1.2)):
            h.append(grivet(f'jr{sx}{i}', (sx * 0.475, y, 0.5), FWD, m('metal'), radius=0.016, height=0.01))
        # Chevrons on both flanks: the stroke direction reads even when the mouth faces away.
        h += mount(chev_strip(f'sc{sx}', m, 0.42, 0.18, period=0.14), gframe(FWD, (sx, 0, 0), (sx * 0.48, 0.82, -0.215)))
        # Twin hydraulic cylinders on the roof and a warning lamp at each front corner.
        h.append(gcyl(f'hyd{sx}', 0.085, 0.7, (sx * 0.33, 1.685, -0.1), st['light'], axis='Z', segments=12, bevel=0.012))
        for i, z in enumerate((-0.4, 0.2)):
            h.append(gcyl(f'hydr{sx}{i}', 0.097, 0.05, (sx * 0.33, 1.685, z), m('rust') if up else m('trim'), axis='Z', segments=12))
            h.append(gbox(f'saddle{sx}{i}', (sx * 0.33 - 0.11, 1.6, z - 0.05), (sx * 0.33 + 0.11, 1.65, z + 0.05), st['dark'], bevel=0.008))
        h.append(gcyl(f'bezel{sx}', 0.062, 0.024, (sx * 0.33, 1.61, 0.41), st['dark'], segments=10))
        h.append(gcyl(f'lamp{sx}', 0.046, 0.07, (sx * 0.33, 1.655, 0.41), m('warn_glow'), segments=10, bevel=0.012))
        if up:
            h.append(gbox(f'rust{sx}', (sx * 0.4805 - 0.004, 0.36, -0.42), (sx * 0.4805 + 0.004, 0.56, -0.3), m('rust')))
        else:
            h.append(gbox(f'neon{sx}', (sx * 0.484 - 0.008, 0.33, -0.45), (sx * 0.484 + 0.008, 0.36, 0.02), m('neon_cyan_glow')))
    h.append(gbox('sill', (-0.45, -0.2, 0.05), (0.45, 0.0, 0.5), st['dark']))
    h.append(gbox('liner', (-0.45, 0.0, 0.05), (0.45, 1.34, 0.075), m('void')))
    h.append(gbox('lintel', (-0.45, 1.34, 0.05), (0.45, 1.5, 0.5), st['casing'], bevel=0.012))
    h += face_stripes('lz', m, 0, 0.5, -0.43, 0.43, 1.36, 1.48, period=0.16, slant=0.1)
    h.append(gbox('cap', (-0.5, 1.5, -0.5), (0.5, 1.6, 0.5), st['frame'], bevel=0.02))
    h += mount(chev_strip('tc', m, 0.84, 0.3, period=0.21), gframe(FWD, UP, (0, 1.6, 0)))
    h.append(gbox('wire', (-0.06, 1.6, -0.47), (0.06, 1.625, -0.44), m('accent_glow')))
    if up:
        h.append(C.blade_tuft('tuft', rng, tuple(gv((-0.44, 1.6, -0.44))), m('grass'), height=0.12))

    # Head: the striking block. Built at home; its origin is the centre of its front face on the floor.
    z1 = HEAD_HOME_Z
    z0 = z1 - HEAD_DEPTH
    hd = [gbox('body', (-0.44, 0.02, z0), (0.44, HEAD_TOP, z1 - 0.03), st['light'], bevel=0.02),
          gbox('face', (-0.44, 0.02, z1 - 0.07), (0.44, HEAD_TOP, z1), st['frame'], bevel=0.012),
          gbox('anvil', (-0.3, 0.42, z1 - 0.01), (0.3, 0.9, z1 + 0.016), m('steel'), bevel=0.012)]
    hd += face_stripes('fz0', m, 0, z1, -0.4, 0.4, 0.06, 0.32, period=0.16, slant=0.1)
    hd += face_stripes('fz1', m, 0, z1, -0.4, 0.4, 1.0, 1.26, period=0.16, slant=0.1)
    for i, (x, y) in enumerate(((-0.36, 0.66), (0.36, 0.66), (-0.36, 0.42), (0.36, 0.42), (-0.36, 0.9), (0.36, 0.9))):
        hd.append(grivet(f'hr{i}', (x, y, z1), FWD, m('metal'), radius=0.022, height=0.014))
    hd += mount(chev_strip('ht', m, 0.36, 0.6, period=0.18), gframe(FWD, UP, (0, HEAD_TOP, z0 + 0.2)))
    for sx in (-1, 1):
        hd += mount(chev_strip(f'hs{sx}', m, 0.36, 0.3, period=0.18), gframe(FWD, (sx, 0, 0), (sx * 0.44, 0.72, z0 + 0.2)))
    head = as_part(hd, 'Head', origin=(0, 0, z1))

    # Ram: the body that fills the lane behind the head. One unit long, featureless along Z, so the
    # game stretches it with scale.z and nothing distorts.
    rm = [gbox('core', (-0.40, 0.06, RAM_Z), (0.40, 1.22, RAM_Z + 1.0), st['dark'])]
    for sx in (-1, 1):
        for i, y in enumerate((0.34, 0.9)):
            rm.append(gbox(f'rib{sx}{i}', (sx * 0.41 - 0.012, y - 0.06, RAM_Z), (sx * 0.41 + 0.012, y + 0.06, RAM_Z + 1.0), st['light']))
    rm.append(gbox('rail', (-0.12, 1.22, RAM_Z), (0.12, 1.24, RAM_Z + 1.0), m('paint_yellow')))
    ram = as_part(rm, 'Ram', origin=(0, 0, RAM_Z))
    ram.scale = (1, HEAD_HOME_Z - RAM_INTO_HEAD, 1)  # Blender Y = Godot Z
    return [as_part(h, 'Housing'), head, ram]


def crusher_lane(m, rng, look):
    st = sty(m, look)
    p = []
    for sx in (-1, 1):
        p.append(gbox(f'rail{sx}', (sx * 0.445 - 0.025, -0.02, -0.5), (sx * 0.445 + 0.025, 0.024, 0.5), st['frame'], bevel=0.006))
        p.append(gbox(f'warn{sx}', (sx * 0.408 - 0.008, 0.0, -0.5), (sx * 0.408 + 0.008, 0.016, 0.5), m('warn_glow')))
        p += floor_chev(f'sc{sx}', m, sx * 0.355, 0, 1.0, 0.07, period=0.125)
    # Two big chevrons painted straight on the floor between the rails, and scuffs from the head.
    p += floor_chev('big', m, 0, 0, 1.0, 0.46, period=0.5, arm=0.075, bg=None)
    for i in range(6):
        x = rng.uniform(-0.28, 0.28)
        z = rng.uniform(-0.45, 0.2)
        p.append(gbox(f'scuff{i}', (x - 0.008, 0.002, z), (x + 0.008, 0.0095, z + rng.uniform(0.1, 0.25)), m('soot')))
    return [as_part(p, 'Lane')]


def crusher_stamper(m, rng, look):
    st = sty(m, look)
    up = st['up']
    top = STAMP_HOME_Y + STAMP_HEAD_H  # 2.1: underside of the gantry
    fr = []
    for i, (sx, sz) in enumerate(CORNERS):
        x, z = sx * 0.44, sz * 0.44
        fr.append(gbox(f'post{i}', (x - 0.045, 0.0, z - 0.045), (x + 0.045, top, z + 0.045), st['casing'], bevel=0.012))
        fr.append(gbox(f'foot{i}', (x - 0.06, 0.0, z - 0.06), (x + 0.06, 0.09, z + 0.06), st['dark'], bevel=0.012))
        fr.append(gbox(f'band{i}', (x - 0.048, 0.5, z - 0.048), (x + 0.048, 0.62, z + 0.048), m('hazard_dark')))
        fr.append(gbox(f'lamp{i}', (x - 0.04, top + 0.14, z - 0.04), (x + 0.04, top + 0.2, z + 0.04), m('warn_glow'), bevel=0.01))
    for k in range(4):
        fr += mount([gbox(f'beam{k}', (-0.485, top, 0.395), (0.485, top + 0.14, 0.485), st['frame'], bevel=0.012)],
                    Matrix.Rotation(k * math.pi / 2, 4, 'Z'))
        hz = F.hazard_stripes(f'tz{k}', -0.39, 0.39, -0.478, -0.402, top + 0.1415, m, period=0.1, slant=0.04, height=0.006)
        fr += mount(hz, Matrix.Rotation(k * math.pi / 2, 4, 'Z'))
    deck = gbox('deck', (-0.4, top + 0.02, -0.4), (0.4, top + 0.1, 0.4), st['dark'], bevel=0.01)
    if not up:
        T.top_runes(deck, m, rng, top + 0.1, [(-0.29, -0.29), (0.29, 0.29)])
    fr.append(deck)
    fr.append(gcyl('cyl', 0.2, 0.3, (0, top + 0.25, 0), st['casing'], segments=12, bevel=0.02))
    fr.append(gcyl('cylcap', 0.14, 0.07, (0, top + 0.43, 0), st['dark'], segments=12, bevel=0.012))
    fr.append(gcyl('cylband', 0.208, 0.05, (0, top + 0.2, 0), m('hazard_dark'), segments=12))
    fr.append(gbox('wire', (-0.06, top + 0.1, 0.3), (0.06, top + 0.125, 0.33), m('accent_glow')))
    # Floor target: hazard border, warn ring, scuffed centre.
    fr += floor_border('hz', m, 0.385, 0.465, 0.375, 0.012)
    fr.append(F.annulus('target', 0.2, 0.25, 0.002, 0.014, m('warn_glow'), segs=24))
    fr.append(gcyl('scuff', 0.17, 0.008, (0, 0.006, 0), m('soot'), segments=16))
    if up:
        fr.append(gbox('rust', (0.395, 1.1, 0.4855), (0.485, 1.3, 0.489), m('rust')))

    y0 = STAMP_HOME_Y
    hd = [gbox('body', (-0.38, y0 + 0.06, -0.38), (0.38, y0 + STAMP_HEAD_H, 0.38), st['light'], bevel=0.025),
          gbox('sole', (-0.41, y0, -0.41), (0.41, y0 + 0.12, 0.41), st['frame'], bevel=0.015)]
    for k in range(4):
        hz = F.hazard_stripes(f'hb{k}', -0.36, 0.36, 0.0, 0.16, 0.003, m, period=0.12, slant=0.06, height=0.008)
        hd += mount(hz, S.face_rot(k) @ Matrix.Translation((0, -0.38, y0 + 0.16)) @ S.FACE)
    # Down-pointing chevrons on every side: "this comes down".
    for i, n in enumerate(((0, 0, 1), (1, 0, 0), (0, 0, -1), (-1, 0, 0))):
        hd += mount(chev_strip(f'dc{i}', m, 0.32, 0.44, period=0.16),
                    gframe((0, -1, 0), n, (n[0] * 0.38, y0 + 0.56, n[2] * 0.38)))
    head = as_part(hd, 'Head', origin=(0, y0, 0))
    ram = as_part([gcyl('rod', 0.13, 1.0, (0, STAMP_ROD_Y - 0.5, 0), m('steel'), segments=12)], 'Ram', origin=(0, STAMP_ROD_Y, 0))
    ram.scale = (1, 1, STAMP_ROD_REST)  # Blender Z = Godot Y
    return [as_part(fr, 'Frame'), head, ram]


# ───────────────────────────── 3. conveyor ─────────────────────────────

def conveyor(m, rng, look):
    st = sty(m, look)
    fr = [gbox('bed', (-0.40, -0.04, -0.5), (0.40, 0.034, 0.5), m('void'))]
    for sx in (-1, 1):
        fr.append(gbox(f'rail{sx}', (sx * 0.44 - 0.04, -0.04, -0.5), (sx * 0.44 + 0.04, 0.075, 0.5), st['casing'], bevel=0.01))
        fr += mount(chev_strip(f'rc{sx}', m, 1.0, 0.066, period=0.125), gframe(FWD, UP, (sx * 0.44, 0.075, 0)))
        fr.append(gbox(f'run{sx}', (sx * 0.396 - 0.006, 0.05, -0.5), (sx * 0.396 + 0.006, 0.064, 0.5), m('run_glow')))
        if st['up']:
            fr.append(gbox(f'rust{sx}', (sx * 0.4805 - 0.003, -0.01, -0.3 * sx), (sx * 0.4805 + 0.003, 0.05, -0.3 * sx + 0.14), m('rust')))
    frame = as_part(fr, 'Frame')

    belt = as_part([gbox('belt', (-BELT_HALF_W, 0.02, -0.5), (BELT_HALF_W, BELT_Y, 0.5), m('belt'))], 'Belt', uv=False)
    T.travel_uv(belt, -BELT_HALF_W, BELT_HALF_W)
    arrows = as_part(mount(chev_strip('ar', m, 1.0, 0.44, period=1 / 3, arm=0.075, bg=None, fg='belt_arrow'),
                           gframe(FWD, UP, (0, BELT_Y, 0))), 'Arrows', uv=False)
    T.travel_uv(arrows, -BELT_HALF_W, BELT_HALF_W)

    out = [frame, belt, arrows]
    for tag, sz in (('Back', -1), ('Front', 1)):
        z = sz * ROLLER_Z
        lip = [gbox('lip', (-0.40, -0.04, sz * 0.5 - (0.028 if sz > 0 else 0.0)), (0.40, 0.088, sz * 0.5 + (0.028 if sz < 0 else 0.0)),
                    st['frame'], bevel=0.008)]
        out.append(as_part(lip, 'End_' + tag))
        r = 0.062
        drum = [gcyl('drum', r, 0.78, (0, ROLLER_Y, z), m('steel'), axis='X', segments=12)]
        for i, (dy, dz) in enumerate(((1, 0), (-1, 0), (0, 1), (0, -1))):
            ty, tz = (0.008, 0.014) if dy else (0.014, 0.008)
            rl = r - 0.005  # lagging bars: proud of the drum by 3 mm, so a spinning roller stays inside its tile
            drum.append(gbox(f'lag{i}', (-0.385, ROLLER_Y + dy * rl - ty, z + dz * rl - tz), (0.385, ROLLER_Y + dy * rl + ty, z + dz * rl + tz),
                             m('hazard_dark')))
        out.append(as_part(drum, 'Roller_' + tag, origin=(0, ROLLER_Y, z)))
    return out


# ───────────────────────────── 4. flame jet ─────────────────────────────

def flame(m, rng, look):
    st = sty(m, look)
    up = st['up']
    b = [gbox('plate', (-0.3, 0.0, 0.5), (0.3, 0.44, 0.535), st['frame'], bevel=0.01),
         gbox('foot', (-0.32, 0.0, 0.5), (0.32, 0.05, 0.6), st['dark'], bevel=0.012)]
    housing = gbox('housing', (-0.13, 0.08, 0.52), (0.13, 0.4, 0.66), st['casing'], bevel=0.02)
    b.append(housing)
    for sx in (-1, 1):
        b.append(gcyl(f'tank{sx}', 0.062, 0.3, (sx * 0.22, 0.2, 0.61), m('rust') if up else m('metal'), segments=10, bevel=0.012))
        b.append(gcyl(f'tankband{sx}', 0.066, 0.04, (sx * 0.22, 0.2, 0.61), m('hazard_dark'), segments=10))
        b.append(gcyl(f'tankcap{sx}', 0.03, 0.05, (sx * 0.22, 0.365, 0.61), st['dark'], segments=8))
        b.append(gtube(f'hose{sx}', [(sx * 0.22, 0.385, 0.61), (sx * 0.22, 0.42, 0.61), (sx * 0.12, 0.42, 0.6)], 0.014, st['dark'], sides=6, elbow=0.02))
        b += mount(chev_strip(f'sc{sx}', m, 0.12, 0.12, period=0.06), gframe(FWD, (sx, 0, 0), (sx * 0.13, 0.3, 0.59)))
    # Hood: its top carries the direction chevrons, so the lane reads from behind and above.
    b.append(gbox('hood', (-0.2, 0.4, 0.5), (0.2, 0.45, 0.76), m('hazard_dark'), bevel=0.01))
    b += mount(chev_strip('tc', m, 0.24, 0.3, period=0.12, arm=0.05, bg=None), gframe(FWD, UP, (0, 0.45, 0.63)))
    b.append(gbox('wire', (-0.28, 0.36, 0.535), (-0.2, 0.39, 0.545), m('accent_glow')))
    b.append(gtube('pilotfeed', [(0, 0.1, 0.66), (0, 0.1, 0.8), (0, 0.125, 0.8)], 0.011, st['dark'], sides=6, elbow=0.015))
    if not up:
        b.append(gbox('neon', (-0.3, 0.052, 0.6), (0.3, 0.075, 0.607), m('neon_cyan_glow')))
    body = as_part(b, 'Body')

    y = NOZZLE_Y
    nz = [gcyl('collar', 0.088, 0.04, (0, y, 0.68), st['dark'], axis='Z', segments=12),
          gcyl('barrel', 0.06, 0.1, (0, y, 0.73), st['light'], axis='Z', segments=12),
          gcyl('flare', 0.06, 0.065, (0, y, 0.8075), st['dark'], axis='Z', segments=12, radius2=0.1),
          gcyl('throat', 0.082, 0.006, (0, y, 0.842), m('heat_glow'), axis='Z', segments=12)]
    nozzle = as_part(nz, 'Nozzle', origin=(0, y, NOZZLE_MOUNT_Z))
    pilot = as_part([sphere('pilot', 0.03, (0, 0.142, 0.8), m('pilot_glow'), squash=(0.8, 1.2, 0.8))], 'Pilot', origin=(0, 0.142, 0.8))

    # Jet: an optional stand-in for the fire, one unit long from the mouth. Hot core, then the body.
    o = (0, y, NOZZLE_MOUTH_Z)
    jet = as_part([lathe('core', [(0.0, 0.045), (0.16, 0.105), (0.34, 0.12)], m('flame_core_glow'), segs=8, origin=o),
                   lathe('fire', [(0.2, 0.085), (0.5, 0.155), (0.78, 0.145), (0.93, 0.085), (1.0, 0.0)], m('flame_glow'), segs=8, origin=o,
                         phase=math.pi / 8)], 'Jet', origin=o)
    return [body, nozzle, pilot, jet]


def flame_lane(m, rng, look):
    p = [gbox('streak', (-0.07, 0.001, -0.5), (0.07, 0.008, 0.5), m('soot'))]
    for i in range(4):
        cx, cz = rng.uniform(-0.08, 0.08), -0.36 + i * 0.24 + rng.uniform(-0.04, 0.04)
        rx, rz = rng.uniform(0.13, 0.22), rng.uniform(0.14, 0.2)
        pts = []
        for k in range(9):
            a = -k * math.tau / 9
            j = rng.uniform(0.72, 1.12)
            # Clamped to the tile so neighbouring lane tiles never overlap (z-fighting).
            pts.append((cx + math.cos(a) * rx * j, max(-0.5, min(0.5, cz + math.sin(a) * rz * j))))
        p.append(gprism(f'scorch{i}', pts, 0.001, 0.009, m('soot')))
    for sx in (-1, 1):
        p += floor_chev(f'sc{sx}', m, sx * 0.455, 0, 1.0, 0.06, period=0.125)
        p.append(gbox(f'warn{sx}', (sx * 0.412 - 0.007, 0.0, -0.5), (sx * 0.412 + 0.007, 0.015, 0.5), m('warn_glow')))
    return [as_part(p, 'Lane')]


# ───────────────────────────── 5. dart launcher ─────────────────────────────

def dart(m, rng, look):
    st = sty(m, look)
    up = st['up']
    b = [gbox('plate', (-0.24, 0.0, 0.5), (0.24, 0.52, 0.53), st['frame'], bevel=0.01),
         gbox('foot', (-0.26, 0.0, 0.5), (0.26, 0.05, 0.6), st['dark'], bevel=0.012)]
    b.append(gbox('block', (-0.19, 0.0, 0.52), (0.19, 0.5, 0.68), st['casing'], bevel=0.02))
    b += face_stripes('fz', m, 0, 0.68, -0.17, 0.17, 0.06, 0.16, period=0.1, slant=0.05)
    for sx in (-1, 1):
        b.append(gbox(f'guide{sx}', (sx * 0.147 - 0.012, 0.24, 0.68), (sx * 0.147 + 0.012, 0.46, 0.745), st['dark'], bevel=0.005))
        b += mount(chev_strip(f'sc{sx}', m, 0.14, 0.16, period=0.07), gframe(FWD, (sx, 0, 0), (sx * 0.19, 0.32, 0.6)))
    # Hood: direction chevrons and the row of pip sockets on top, visible from every facing.
    b.append(gbox('hood', (-0.22, 0.5, 0.49), (0.22, 0.55, 0.73), m('hazard_dark'), bevel=0.01))
    b += mount(chev_strip('tc', m, 0.13, 0.26, period=0.065, arm=0.03, bg=None), gframe(FWD, UP, (0, 0.55, 0.655)))
    b.append(gbox('pipbar', (-0.205, 0.55, 0.505), (0.205, 0.556, 0.56), st['frame']))
    b.append(gbox('wire', (0.15, 0.4, 0.53), (0.23, 0.43, 0.54), m('accent_glow')))
    if up:
        b.append(gbox('rust', (0.05, 0.36, 0.6795), (0.17, 0.46, 0.683), m('rust')))
    else:
        b.append(gbox('neon', (-0.24, 0.052, 0.6), (0.24, 0.075, 0.607), m('neon_cyan_glow')))
    out = [as_part(b, 'Body')]

    mz = [gbox('sleeve', (-0.13, 0.255, 0.62), (0.13, 0.345, 0.725), st['dark'], bevel=0.012),
          gbox('slot', (-0.1, 0.283, 0.72), (0.1, 0.317, 0.7265), m('void'))]
    out.append(as_part(mz, 'Muzzle', origin=(0, DART_Y, MUZZLE_Z)))

    sh = [gbox('shutter', (-0.125, 0.352, 0.728), (0.125, 0.44, 0.741), m('paint_yellow'), bevel=0.004)]
    for i in range(3):
        x = -0.085 + i * 0.085
        sh.append(C.prism(f'bar{i}', [(x - 0.035, 0), (x - 0.005, 0), (x + 0.035, 0.088), (x + 0.005, 0.088)], 0.0, 0.003, m('hazard_dark')))
        mount(sh[-1:], Matrix.Translation(gv((0, 0.352, 0.7415))) @ S.FACE)
    out.append(as_part(sh, 'Shutter', origin=(0, 0.396, 0.7345)))

    for i in range(PIPS):
        x = -0.175 + i * 0.05
        pip = as_part([gbox('pip', (x - 0.017, 0.556, 0.515), (x + 0.017, 0.566, 0.55), m('pip_glow'))], f'Pip_{i + 1:02d}',
                      origin=(x, 0.556, 0.5325))
        out.append(pip)

    o = (0, DART_Y, DART_FLASH_Z)
    fl = [lathe('star', [(0.0, 0.0), (0.02, 0.1), (0.05, 0.035), (0.17, 0.0)], m('muzzle_glow'), segs=4, origin=o),
          lathe('star2', [(0.0, 0.0), (0.015, 0.065), (0.04, 0.03), (0.11, 0.0)], m('muzzle_glow'), segs=4, origin=o, phase=math.pi / 4)]
    out.append(as_part(fl, 'Flash', origin=o))
    return out


def dart_lane(m, rng, look):
    p = [gbox('score', (-0.012, 0.001, -0.5), (0.012, 0.011, 0.5), m('hazard_dark'))]
    p += floor_chev('tick', m, 0, 0, 1.0, 0.17, period=0.25, arm=0.032, bg=None)
    for sx in (-1, 1):
        for i in range(4):
            z = -0.4375 + i * 0.25
            p.append(gbox(f'dash{sx}{i}', (sx * 0.12 - 0.006, 0.001, z - 0.04), (sx * 0.12 + 0.006, 0.009, z + 0.04), m('hazard_dark')))
    return [as_part(p, 'Lane')]


def dart_bolt(m, rng, look):
    p = [gcyl('shaft', 0.014, 0.2, (0, 0, -0.03), m('steel'), axis='Z', segments=6),
         lathe('head', [(0.05, 0.0), (0.06, 0.034), (0.15, 0.0)], m('dart_glow'), segs=6),
         gbox('fin_h', (-0.04, -0.004, -0.15), (0.04, 0.004, -0.07), m('dart_glow')),
         gbox('fin_v', (-0.004, -0.04, -0.15), (0.004, 0.04, -0.07), m('dart_glow'))]
    return [as_part(p, 'Dart')]


# ───────────────────────────── 6. bumper ─────────────────────────────

def bumper(m, rng, look):
    st = sty(m, look)
    e = 0.46
    plate = gbox('plate', (-e, -0.04, -e), (e, 0.03, e), st['dark'], bevel=0.012)
    C.boolean(plate, [gcyl('well', 0.37, 0.12, (0, 0.04, 0), m('void'), segments=24)])
    base = [plate]
    for sx in (-1, 1):
        base += mount(chev_strip(f'sc{sx}', m, 0.84, 0.062, period=0.12), gframe(FWD, UP, (sx * 0.424, 0.03, 0)))
    for i, sz in enumerate((-1, 1)):
        base.append(gbox(f'wire{i}', (-0.14, 0.03, sz * 0.425 - 0.012), (0.14, 0.037, sz * 0.425 + 0.012), m('accent_glow')))
    if st['up']:
        base.append(C.moss_pad('moss', rng, tuple(gv((0.39, 0.03, -0.42))), 0.04, 0.018, m('moss')))

    pad = [gcyl('disc', 0.34, 0.06, (0, 0.045, 0), st['casing'], segments=20, bevel=0.012),
           gcyl('inset', 0.285, 0.008, (0, 0.079, 0), m('hazard_dark'), segments=20),
           # The launch arrow.
           gprism('arrow', [(-0.055, -0.2), (0.055, -0.2), (0.055, 0.02), (0.18, 0.02), (0.0, 0.24), (-0.18, 0.02), (-0.055, 0.02)],
                  0.082, 0.09, m('paint_yellow'))]
    for i in range(6):
        a = i * math.tau / 6 + math.pi / 6
        pad.append(grivet(f'pr{i}', (math.cos(a) * 0.314, 0.075, math.sin(a) * 0.314), UP, m('metal'), radius=0.016, height=0.01))
    pad = as_part(pad, 'Pad')

    n = 36
    pts = [(math.cos(i / n * 3 * math.tau) * 0.2, math.sin(i / n * 3 * math.tau) * 0.2, i / n) for i in range(n + 1)]
    spring = as_part([C.tube('coil', pts, 0.022, m('steel'), sides=6)], 'Spring', origin=(0, 0, 0))
    spring.location = gv((0, SPRING_Y, 0))
    spring.scale = (1, 1, SPRING_REST)
    return [as_part(base, 'Base'), pad, spring]


# ───────────────────────────── 7. beam sensor ─────────────────────────────

def sensor(m, rng, look):
    st = sty(m, look)
    p = [gbox('foot', (-0.08, 0.0, -0.08), (0.08, 0.035, 0.08), st['dark'], bevel=0.01),
         gbox('column', (-0.04, 0.03, -0.04), (0.04, 0.4, 0.04), st['casing'], bevel=0.008),
         gbox('band', (-0.044, 0.08, -0.044), (0.044, 0.13, 0.044), m('hazard_dark')),
         gbox('head', (-0.06, 0.25, -0.06), (0.06, 0.385, 0.06), st['frame'], bevel=0.012),
         gbox('visor', (-0.05, 0.36, 0.055), (0.05, 0.376, 0.1), st['dark'], bevel=0.004),
         gbox('wire', (-0.02, 0.27, -0.066), (0.02, 0.36, -0.058), m('accent_glow'))]
    post = as_part(p, 'Post')
    lens = as_part([gcyl('lens', 0.032, 0.02, (0, SENSOR_Y, SENSOR_LENS_Z), m('sensor_glow'), axis='Z', segments=10),
                    gbox('cap', (-0.034, 0.4, -0.034), (0.034, 0.432, 0.034), m('sensor_glow'), bevel=0.008)],
                   'Lens', origin=(0, SENSOR_Y, SENSOR_LENS_Z))
    # Beam: an optional stand-in. One unit long from the lens, dashed (a sensor is never a solid
    # red laser line), so scale.z = reach.
    dashes = [gbox(f'd{i}', (-0.007, SENSOR_Y - 0.007, SENSOR_BEAM_Z + i / 8 + 0.02), (0.007, SENSOR_Y + 0.007, SENSOR_BEAM_Z + i / 8 + 0.09),
                   m('beam_glow')) for i in range(8)]
    beam = as_part(dashes, 'Beam', origin=(0, SENSOR_Y, SENSOR_BEAM_Z))
    return [post, lens, beam]


# ───────────────────────────── 8. relay ─────────────────────────────

def relay(m, rng, look):
    st = sty(m, look)
    b = [gbox('box', (-0.13, 0.0, -0.13), (0.13, 0.16, 0.13), st['casing'], bevel=0.02),
         gbox('lid', (-0.145, 0.16, -0.145), (0.145, RELAY_TOP, 0.145), st['frame'], bevel=0.01),
         F.annulus('socket', 0.08, 0.13, RELAY_TOP - 0.004, RELAY_TOP + 0.002, m('hazard_dark'), segs=24),
         gcyl('bezel', 0.075, 0.016, (0, RELAY_TOP + 0.006, 0), st['dark'], segments=12),
         gcyl('conduit', 0.026, 0.1, (-0.17, 0.06, 0), st['light'], axis='X', segments=8),
         gbox('wire', (-0.05, 0.11, 0.13), (0.05, 0.135, 0.137), m('accent_glow'))]
    for k in range(4):
        hz = F.hazard_stripes(f'hz{k}', -0.1, 0.1, 0.0, 0.06, 0.003, m, period=0.07, slant=0.04, height=0.006)
        b += mount(hz, S.face_rot(k) @ Matrix.Translation((0, -0.13, 0.025)) @ S.FACE)
    out = [as_part(b, 'Body'),
           as_part([sphere('dome', 0.062, (0, RELAY_TOP + 0.012, 0), m('relay_glow'))], 'Lamp', origin=(0, RELAY_TOP, 0))]
    # Progress ring: Tick_01 starts at the back (-Z) and they run clockwise seen from above.
    for i in range(TICKS):
        a0 = i * math.tau / TICKS + 0.07
        a1 = (i + 1) * math.tau / TICKS - 0.07
        am = (a0 + a1) / 2
        pt = lambda r, a: (r * math.sin(a), -r * math.cos(a))
        poly = [pt(0.087, a0), pt(0.087, am), pt(0.087, a1), pt(0.124, a1), pt(0.124, am), pt(0.124, a0)]
        mid = pt(0.105, am)
        out.append(as_part([gprism('tick', poly, RELAY_TOP + 0.002, RELAY_TOP + 0.01, m('relay_glow'))], f'Tick_{i + 1:02d}',
                           origin=(mid[0], RELAY_TOP, mid[1])))
    return out


# ───────────────────────────── 9. magnet ─────────────────────────────

def magnet(m, rng, look):
    st = sty(m, look)
    disc = gcyl('disc', 0.36, 0.05, (0, 0.025, 0), st['frame'], segments=24, bevel=0.012)
    b = [disc, gcyl('hub', 0.19, 0.06, (0, 0.08, 0), st['casing'], segments=16, bevel=0.01)]
    # Inward chevrons on the rim: "this pulls".
    for i in range(4):
        a = i * math.pi / 2 + math.pi / 4
        d = (math.cos(a), 0, math.sin(a))
        b += mount(chev_strip(f'in{i}', m, 0.085, 0.13, period=0.0425),
                   gframe((-d[0], 0, -d[2]), UP, (d[0] * 0.305, 0.05, d[2] * 0.305)))
    # Horseshoe emblem on the hub.
    ro, ri, c, zt = 0.125, 0.065, -0.02, 0.085
    outer = [(ro * math.cos(a), c - ro * math.sin(a)) for a in [k * math.pi / 10 for k in range(11)]]
    inner = [(ri * math.cos(a), c - ri * math.sin(a)) for a in [k * math.pi / 10 for k in range(10, -1, -1)]]
    b.append(gprism('shoe', outer + [(-ro, zt), (-ri, zt)] + inner + [(ri, zt), (ro, zt)], 0.11, 0.14, m('magnet_body')))
    for sx in (-1, 1):
        b.append(gbox(f'pole{sx}', (sx * 0.095 - 0.032, 0.11, zt), (sx * 0.095 + 0.032, 0.142, zt + 0.04), m('steel')))
    b.append(gbox('wire', (-0.05, 0.05, -0.35), (0.05, 0.058, -0.325), m('accent_glow')))
    coil = [F.annulus('coil', 0.2, 0.25, 0.05, 0.088, m('magnet_glow'), segs=24)]
    ring = [F.annulus('ring', 0.982, 1.0, 0.003, 0.013, m('magnet_ring_glow'), segs=48)]
    return [as_part(b, 'Base'), as_part(coil, 'Coil', origin=(0, 0.05, 0)), as_part(ring, 'Ring')]


BUILDERS = {'trap_spikes': spikes, 'trap_crusher': crusher, 'trap_crusher_lane': crusher_lane, 'trap_crusher_stamper': crusher_stamper,
            'trap_conveyor': conveyor, 'trap_flame': flame, 'trap_flame_lane': flame_lane, 'trap_dart': dart, 'trap_dart_lane': dart_lane,
            'trap_dart_bolt': dart_bolt, 'trap_bumper': bumper, 'trap_sensor': sensor, 'trap_relay': relay, 'trap_magnet': magnet}

PIP_NAMES = [f'Pip_{i:02d}' for i in range(1, PIPS + 1)]
TICK_NAMES = [f'Tick_{i:02d}' for i in range(1, TICKS + 1)]

# Manifest notes: the object names and the numbers the game needs, per piece (Godot axes).
NOTES = {
    'trap_spikes': {'kind': 'spikes', 'objects': ['Base', 'Spikes'], 'placement': 'one per cell, any yaw',
                    'spikes_scale_y': {'down': SPIKE_REST, 'raised': 1.0}, 'tip_y': SPIKE_TIP_Y},
    'trap_crusher': {'kind': 'crusher', 'objects': ['Housing', 'Head', 'Ram'],
                     'placement': 'origin = centre of the tile behind cells[0]; +Z = piston travel; replaces the wall piece on that tile',
                     'head_z': {'home': HEAD_HOME_Z, 'extended': 'cells + 0.5 - %.2f' % HEAD_END_GAP},
                     'ram_scale_z': 'Head.z - %.2f' % RAM_INTO_HEAD, 'head_top': HEAD_TOP},
    'trap_crusher_lane': {'kind': 'crusher', 'objects': ['Lane'], 'placement': 'one per crusher cell, +Z = piston travel'},
    'trap_crusher_stamper': {'kind': 'crusher', 'objects': ['Frame', 'Head', 'Ram'], 'placement': 'one-cell crusher with no dir; any yaw',
                             'head_y': {'home': STAMP_HOME_Y, 'extended': STAMP_DOWN_Y},
                             'ram_scale_y': '%.2f - Head.y' % (STAMP_HOME_Y + STAMP_ROD_REST)},
    'trap_conveyor': {'kind': 'conveyor', 'objects': ['Frame', 'Belt', 'Arrows', 'End_Back', 'Roller_Back', 'End_Front', 'Roller_Front'],
                      'placement': 'one per cell, +Z = current travel direction', 'belt_y': BELT_Y,
                      'belt_uv': 'U 0..1 across (-X to +X), V = z + 0.5 (0 upstream edge, 1 downstream edge); 1 V = 1 tile',
                      'roller_radius': 0.062},
    'trap_flame': {'kind': 'flame', 'objects': ['Body', 'Nozzle', 'Pilot', 'Jet'],
                   'placement': 'origin = centre of the nozzle tile; unit hangs on its +Z face; +Z = jet direction',
                   'nozzle_y': NOZZLE_Y, 'jet_origin_z': NOZZLE_MOUTH_Z, 'jet_scale_z': 'reach - %.3f' % (NOZZLE_MOUTH_Z - 0.5)},
    'trap_flame_lane': {'kind': 'flame', 'objects': ['Lane'], 'placement': 'one per tile of reach, +Z = jet direction'},
    'trap_dart': {'kind': 'dart', 'objects': ['Body', 'Muzzle', 'Shutter', 'Flash'] + PIP_NAMES,
                  'placement': 'origin = centre of the launcher tile; unit hangs on its +Z face; +Z = lane direction',
                  'dart_y': DART_Y, 'muzzle_recoil_z': -MUZZLE_RECOIL, 'shutter_y': {'open': 0.0, 'closed': -SHUTTER_TRAVEL}},
    'trap_dart_lane': {'kind': 'dart', 'objects': ['Lane'], 'placement': 'one per lane tile, +Z = lane direction'},
    'trap_dart_bolt': {'kind': 'dart', 'objects': ['Dart'], 'placement': 'projectile; origin at its centre, point along +Z, fly at y = %.2f' % DART_Y},
    'trap_bumper': {'kind': 'bumper', 'objects': ['Base', 'Pad', 'Spring'], 'placement': 'one cell, +Z = launch direction',
                    'pad_y': 'PAD_POP * t', 'pad_pop': PAD_POP, 'spring_scale_y': '%.2f + Pad.y' % SPRING_REST},
    'trap_sensor': {'kind': 'sensor', 'objects': ['Post', 'Lens', 'Beam'],
                    'placement': 'one at `from` facing `to` (+Z along the beam), one at `to` facing back with Beam hidden',
                    'beam_y': SENSOR_Y, 'beam_scale_z': 'reach'},
    'trap_relay': {'kind': 'relay', 'objects': ['Body', 'Lamp'] + TICK_NAMES, 'placement': 'origin on the surface under it (floor or wall top) at x, y',
                   'ticks': 'Tick_01 at the back (-Z), clockwise seen from above'},
    'trap_magnet': {'kind': 'magnet', 'objects': ['Base', 'Coil', 'Ring'], 'placement': 'origin on the floor at x, y',
                    'ring_scale_xz': 'radius'},
}


def manifest_extra(piece, look):
    return dict(NOTES[piece])


def build(piece: str, look: str) -> list:
    m = T.TrapMats(look)
    rng = random.Random(f'{piece}:{look}')
    return BUILDERS[piece](m, rng, look)
