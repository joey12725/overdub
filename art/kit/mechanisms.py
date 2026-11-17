"""Mechanisms: door, switch, plate, breakable, breakable_chunks, laser_emitter, core, exit_pad.

Moving parts are separate named mesh objects (docs/GODOT-PORT.md asset contract). Each object's
origin is its pivot, so the game only has to set one transform:
  door      Frame (static), Panel (origin at its bottom centre; open = slide down by PANEL_DROP).
  switch    Base, Lever (origin at the pivot; rotate about Godot Z: off +0.65 rad, on -0.65 rad).
  plate     Base, Pad (pressed = Pad down by PAD_TRAVEL).
  breakable a single mesh; breakable_chunks: Chunk_01..Chunk_10 at their assembled positions, each
            with its origin at its own centre (spin in place).
  laser_emitter  Body, Lens (lens faces Godot +Z at y = BEAM_Y).
  core      Shell, Heart (origin at the heart's centre; spin / bob it).
  exit_pad  a single mesh.
Each moving glb also carries a 1.0 s action (`open`, `toggle`, `press`) the game may scrub instead.
Materials named `accent_glow` are meant to be tinted with the wire's accent colour at runtime.
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

import common as C
import floors as F
import structure as S

PIECES = ('door', 'switch', 'plate', 'breakable', 'breakable_chunks', 'laser_emitter', 'core', 'exit_pad')

DOOR_TOP = 1.8
PANEL_H = 1.6
PANEL_DROP = 1.58
LEVER_PIVOT = 0.42
LEVER_ANGLE = 0.65
PAD_TRAVEL = 0.045
BEAM_Y = 0.45
HEART_Y = 0.95
BREAK_TOP = 1.2


def named(ob, name):
    ob.name = name
    ob.data.name = name
    return ob


def as_part(parts, name, origin=(0, 0, 0)):
    """Join parts into the named exported object and put its origin at `origin` (pivot)."""
    ob = C.join(parts, name)
    C.finish(ob)
    o = Vector(origin)
    if o.length > 0:
        ob.data.transform(Matrix.Translation(-o))
        ob.location = o
    return named(ob, name)


def chevrons(name, x0, x1, z0, z1, m, period=0.16, plane_y=-0.06, k_rot=0.0):
    """Hazard stripes stood up on a face plane (outward -Y) at y = plane_y."""
    hz = F.hazard_stripes(name, x0, x1, z0, z1, 0.003, m, period=period, slant=0.1, height=0.006)
    mtx = Matrix.Rotation(k_rot, 4, 'Z') @ Matrix.Translation((0, plane_y, 0)) @ S.FACE
    for s in hz:
        s.matrix_world = mtx @ s.matrix_world
    return hz


def animate(ob, action_name, data_path, index, keys):
    """Keyframe a 1.0 s action (frames 0..24 at 24 fps) with linear interpolation."""
    scene = bpy.context.scene
    scene.render.fps = 24
    ob.animation_data_create()
    act = bpy.data.actions.new(action_name)
    ob.animation_data.action = act
    for t, v in keys:
        prop = getattr(ob, data_path)
        prop[index] = v
        ob.keyframe_insert(data_path=data_path, index=index, frame=t * 24)
    for fc in _fcurves(act):
        for kp in fc.keyframe_points:
            kp.interpolation = 'LINEAR'
    # Rest pose at the first key.
    getattr(ob, data_path)[index] = keys[0][1]
    act.use_fake_user = True
    return act


def _fcurves(act):
    if hasattr(act, 'fcurves') and len(act.fcurves):
        return list(act.fcurves)
    out = []
    for layer in getattr(act, 'layers', []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                out += list(bag.fcurves)
    return out


# ───────────────────────────── door ─────────────────────────────

def door(m, rng, look):
    up = look == 'upper'
    frame = []
    for side in (-1, 1):
        x0, x1 = (-0.5, -0.36) if side < 0 else (0.36, 0.5)
        if up:
            # Stacked stone pillar, joints staggered.
            z = -0.2
            i = 0
            while z < DOOR_TOP - 0.2:
                h = min(rng.uniform(0.3, 0.42), DOOR_TOP - 0.18 - z)
                frame.append(C.box_mm(f'p{side}{i}', (x0 - (0.02 if i % 2 else 0) * side * -1, -0.3, z + 0.01), (x1, 0.3, z + h - 0.01),
                                      S.stone_mat(m, rng), bevel=0.022, chips=S.block_chips(rng, (x1 - x0, 0.6, h), 0.35)))
                z += h
                i += 1
            frame.append(C.box_mm(f'guide{side}', (x1 - 0.04 if side < 0 else x0 - 0.0, -0.1, 0.0), (x1 + 0.0 if side < 0 else x0 + 0.04, 0.1, DOOR_TOP - 0.18),
                                  m('metal_dark'), bevel=0.008))
        else:
            post = C.box_mm(f'post{side}', (x0, -0.32, -0.2), (x1, 0.32, DOOR_TOP - 0.16), m('plate'), bevel=0.02)
            frame.append(post)
            frame.append(C.box_mm(f'postcap{side}', (x0 - 0.01, -0.34, -0.2), (x1 + 0.01, 0.34, 0.12), m('trim'), bevel=0.018))
            # Rune column on the post's front and a vertical accent strip on the inner jamb.
            glyphs = []
            cx = (x0 + x1) / 2
            for g in range(3):
                for s_, pl in enumerate(F.glyph_strokes(rng, 0.06, 0.13)):
                    pts = [(cx + q[0], 0.45 + g * 0.32 + q[1]) for q in pl]
                    glyphs.append(F.ribbon(f'g{side}{g}{s_}', pts, 0.02, -0.014, 0.05, m('rune_glow')))
            cut = C.join(glyphs, f'rc{side}')
            cut.matrix_world = Matrix.Translation((0, -0.32, 0)) @ S.FACE
            C.boolean(post, [cut])
            jx = x1 if side < 0 else x0
            frame.append(C.box_mm(f'strip{side}', (jx - 0.012, -0.2, 0.15), (jx + 0.012, -0.14, DOOR_TOP - 0.3), m('accent_glow')))
            frame.append(C.box_mm(f'strip_b{side}', (jx - 0.012, 0.14, 0.15), (jx + 0.012, 0.2, DOOR_TOP - 0.3), m('accent_glow')))
            frame.append(C.box_mm(f'guide{side}', (jx - 0.03, -0.1, 0.0), (jx + 0.03, 0.1, DOOR_TOP - 0.16), m('trim'), bevel=0.008))
    # Lintel: a painted steel beam with hazard stripes front and back.
    lin_mat = m('paint_yellow') if up else m('trim')
    frame.append(C.box_mm('lintel', (-0.52, -0.32, DOOR_TOP - 0.2), (0.52, 0.32, DOOR_TOP), lin_mat, bevel=0.02))
    for k_rot, py in ((0.0, -0.32), (math.pi, -0.32)):
        frame += chevrons(f'lz{k_rot:.1f}', -0.44, 0.44, DOOR_TOP - 0.17, DOOR_TOP - 0.03, m, period=0.16, plane_y=py, k_rot=k_rot)
    for sy in (-1, 1):
        frame.append(C.box_mm(f'status{sy}', (-0.08, sy * 0.33 - 0.012, DOOR_TOP - 0.3), (0.08, sy * 0.33 + 0.012, DOOR_TOP - 0.22), m('status_glow'),
                              bevel=0.006))
        frame.append(C.box_mm(f'status_h{sy}', (-0.1, sy * 0.31 - 0.02, DOOR_TOP - 0.32), (0.1, sy * 0.31 + 0.02, DOOR_TOP - 0.2), m('metal_dark'),
                              bevel=0.006))
    # Threshold: the slot the panel sinks into, lit along both lips.
    frame.append(C.box_mm('slot', (-0.36, -0.08, -0.06), (0.36, 0.08, 0.004), m('void')))
    for sy in (-1, 1):
        frame.append(C.box_mm(f'lip{sy}', (-0.36, sy * 0.1 - 0.02, -0.02), (0.36, sy * 0.1 + 0.02, 0.012), m('metal_dark'), bevel=0.006))
        frame.append(C.box_mm(f'lipglow{sy}', (-0.33, sy * 0.13 - 0.012, -0.01), (0.33, sy * 0.13 + 0.012, 0.008), m('accent_glow')))
    if up:
        frame.append(C.moss_pad('moss', rng, (-0.43, -0.3, 0.5), 0.07, 0.03, m('moss'), up=(0, -1, 0)))
        frame.append(C.blade_tuft('tuft', rng, (0.44, 0.0, DOOR_TOP), m('grass'), height=0.14))
        frame += C.vine('vine', rng, [(0.44, -0.322, DOOR_TOP - 0.05), (0.46, -0.33, 1.3), (0.42, -0.33, 0.9)], (0, -1, 0), m('leaf_dark'), m('grass'))

    panel = []
    pw = 0.37
    pm = m('paint_yellow') if up else m('plate')
    body = C.box_mm('panel', (-pw, -0.06, 0.0), (pw, 0.06, PANEL_H), pm, bevel=0.02)
    panel.append(body)
    for sy in (-1, 1):
        # Horizontal stiffener ribs on both faces.
        for i, z in enumerate((0.42, 0.85, 1.28)):
            panel.append(C.box_mm(f'rib{sy}{i}', (-pw + 0.03, sy * 0.06 - 0.02, z - 0.04), (pw - 0.03, sy * 0.06 + 0.02, z + 0.04),
                                  m('metal') if up else m('trim'), bevel=0.012))
        # Accent window strip near the top.
        panel.append(C.box_mm(f'win{sy}', (-0.24, sy * 0.06 - 0.012, 1.42), (0.24, sy * 0.06 + 0.012, 1.5), m('accent_glow')))
        panel += chevrons(f'pz{sy}', -pw + 0.02, pw - 0.02, 0.04, 0.32, m, period=0.14, plane_y=-0.06, k_rot=0.0 if sy < 0 else math.pi)
        for i, x in enumerate((-0.3, 0.3)):
            for z in (0.6, 1.07):
                panel.append(C.rivet(f'pr{sy}{i}{z}', (x, sy * 0.06, z), (0, sy, 0), m('metal_dark'), radius=0.02, height=0.012))
    if up:
        panel.append(C.box_mm('rust', (0.18, -0.068, 0.32), (0.34, -0.055, 0.48), m('rust'), bevel=0.004))
        panel.append(C.box_mm('rust2', (-0.36, 0.055, 1.1), (-0.25, 0.068, 1.2), m('rust'), bevel=0.004))
    else:
        cut = F.rune_circle(m, 0.17, 0.0, ticks=False)
        cut.matrix_world = Matrix.Translation((0, -0.06, 1.07 - 0.21)) @ S.FACE @ Matrix.Translation((0, 0.21, 0))
        C.boolean(body, [cut])
    fr = as_part(frame, 'Frame')
    pa = as_part(panel, 'Panel')
    animate(pa, 'open', 'location', 2, [(0.0, 0.0), (1.0, -PANEL_DROP)])
    return [fr, pa]


# ───────────────────────────── switch ─────────────────────────────

def switch(m, rng, look):
    up = look == 'upper'
    base = []
    if up:
        base.append(C.box_mm('plinth', (-0.3, -0.26, -0.02), (0.3, 0.26, 0.12), m('stone'), bevel=0.025,
                             chips=S.block_chips(rng, (0.6, 0.52, 0.14), 0.5), top_mat=m('stone_light')))
        housing = m('paint_yellow')
    else:
        base.append(C.box_mm('plinth', (-0.3, -0.26, -0.02), (0.3, 0.26, 0.12), m('trim'), bevel=0.02))
        housing = m('plate')
    base.append(C.box_mm('housing', (-0.23, -0.19, 0.12), (0.23, 0.19, 0.38), housing, bevel=0.03))
    base.append(C.box_mm('lid', (-0.2, -0.16, 0.37), (0.2, 0.16, 0.4), m('metal_dark'), bevel=0.012))
    # Arc guide on the lid: the lever's two stops are visible end caps.
    base.append(C.box_mm('slot', (-0.17, -0.03, 0.385), (0.17, 0.03, 0.405), m('void')))
    for sx, mat in ((-1, m('status_glow')), (1, m('accent_glow'))):
        base.append(C.box_mm(f'stop{sx}', (sx * 0.17 - 0.025, -0.05, 0.39), (sx * 0.17 + 0.025, 0.05, 0.43), m('metal'), bevel=0.008))
        # Indicator lamps on the front: red = off side, accent = on side.
        base.append(C.cylinder(f'lamp{sx}', 0.035, 0.02, (sx * 0.12, -0.195, 0.3), mat, segments=10, axis='Y'))
        base.append(C.cylinder(f'bezel{sx}', 0.048, 0.014, (sx * 0.12, -0.188, 0.3), m('metal_dark'), segments=10, axis='Y'))
    base += chevrons('hz', -0.2, 0.2, 0.15, 0.24, m, period=0.1, plane_y=-0.19)
    if not up:
        base.append(C.box_mm('neon', (-0.3, -0.27, 0.02), (0.3, -0.255, 0.05), m('neon_cyan_glow')))
    # Pivot cheeks.
    for sy in (-1, 1):
        base.append(C.box_mm(f'cheek{sy}', (-0.05, sy * 0.06 - 0.015, 0.39), (0.05, sy * 0.06 + 0.015, 0.47), m('metal'), bevel=0.01))
    lever = []
    lever.append(C.cylinder('hub', 0.045, 0.09, (0, 0, LEVER_PIVOT + 0.02), m('metal_dark'), segments=12, axis='Y', bevel=0.008))
    lever.append(C.tube('arm', [(0, 0, LEVER_PIVOT + 0.02), (0, 0, LEVER_PIVOT + 0.36)], 0.026, m('metal'), sides=10))
    lever.append(C.tube('grip', [(0, 0, LEVER_PIVOT + 0.24), (0, 0, LEVER_PIVOT + 0.36)], 0.036, m('hazard_dark'), sides=10))
    knob = bmesh.new()
    bmesh.ops.create_icosphere(knob, subdivisions=2, radius=0.065)
    bmesh.ops.translate(knob, vec=Vector((0, 0, LEVER_PIVOT + 0.4)), verts=knob.verts)
    lever.append(C.obj_from_bm('knob', knob, [m('accent_glow')]))
    b = as_part(base, 'Base')
    lv = as_part(lever, 'Lever', origin=(0, 0, LEVER_PIVOT + 0.02))
    # Blender Y rotation of -a tips the arm to -X (Godot rotation +a about Z): off -> on.
    animate(lv, 'toggle', 'rotation_euler', 1, [(0.0, -LEVER_ANGLE), (1.0, LEVER_ANGLE)])
    lv.rotation_euler = (0, 0, 0)
    return [b, lv]


# ───────────────────────────── plate ─────────────────────────────

def plate(m, rng, look):
    up = look == 'upper'
    base = []
    e = 0.44
    fr = m('stone_light') if up else m('plate')
    for i, (lo, hi) in enumerate((((-e, -e), (e, -e + 0.09)), ((-e, e - 0.09), (e, e)), ((-e, -e + 0.09), (-e + 0.09, e - 0.09)),
                                  ((e - 0.09, -e + 0.09), (e, e - 0.09)))):
        base.append(C.box_mm(f'fr{i}', (lo[0], lo[1], -0.05), (hi[0], hi[1], 0.035), fr, bevel=0.012))
    base.append(C.box_mm('well', (-e + 0.09, -e + 0.09, -0.06), (e - 0.09, e - 0.09, -0.01), m('void')))
    # Hazard corner stripes and accent edge bars.
    for k in range(4):
        hz = F.hazard_stripes(f'hz{k}', -0.3, 0.3, -e + 0.015, -e + 0.075, 0.0365, m, period=0.1, slant=0.04)
        for s in hz:
            s.matrix_world = Matrix.Rotation(k * math.pi / 2, 4, 'Z') @ s.matrix_world
        base += hz
    for i, (x, y) in enumerate(((-e + 0.045, -e + 0.045), (e - 0.045, -e + 0.045), (-e + 0.045, e - 0.045), (e - 0.045, e - 0.045))):
        base.append(C.rivet(f'rv{i}', (x, y, 0.035), (0, 0, 1), m('metal_dark'), radius=0.02, height=0.012))
    pad = []
    p = 0.33
    pad.append(C.box_mm('pad', (-p, -p, -0.04), (p, p, 0.07), m('metal') if up else m('plate_light'), bevel=0.02))
    pad.append(C.box_mm('pad_in', (-p + 0.07, -p + 0.07, 0.06), (p - 0.07, p - 0.07, 0.075), m('metal_dark') if up else m('plate'), bevel=0.01))
    for k in range(4):
        bar = C.box_mm(f'bar{k}', (-0.16, -p + 0.025, 0.06), (0.16, -p + 0.05, 0.078), m('accent_glow'))
        bar.matrix_world = Matrix.Rotation(k * math.pi / 2, 4, 'Z') @ bar.matrix_world
        pad.append(bar)
    # Footprint chevron pointing "press here".
    pad.append(C.prism('chev', [(-0.1, -0.06), (0.0, 0.04), (0.1, -0.06), (0.1, 0.0), (0.0, 0.1), (-0.1, 0.0)], 0.07, 0.082, m('accent_glow')))
    b = as_part(base, 'Base')
    pd = as_part(pad, 'Pad')
    animate(pd, 'press', 'location', 2, [(0.0, 0.0), (1.0, -PAD_TRAVEL)])
    return [b, pd]


# ───────────────────────────── breakable ─────────────────────────────

def breakable(m, rng, look):
    """Weak wall: loose, shifted blocks with a glowing fracture core showing through every gap, big
    through-cracks and a hazard tape band. Lower than a wall (1.2) and lit from inside, so it never
    reads as the indestructible wall."""
    up = look == 'upper'
    parts = [C.box_mm('core', (-0.4, -0.4, -0.2), (0.4, 0.4, BREAK_TOP - 0.1), m('crack_glow'))]
    courses = 4
    z = -0.2
    hs = [0.36, 0.34, 0.36, 0.34]
    for i in range(courses):
        h = hs[i]
        widths = rng.choice(([0.5, 0.5], [0.4, 0.6], [0.62, 0.38]))
        a = -0.48
        along_x = i % 2 == 0
        for j, wd in enumerate(widths):
            wd = wd * 0.96
            b = a + wd
            gap = 0.045
            if along_x:
                lo, hi = (a + gap / 2, -0.47, z + gap / 2), (b - gap / 2, 0.47, z + h - gap / 2)
            else:
                lo, hi = (-0.47, a + gap / 2, z + gap / 2), (0.47, b - gap / 2, z + h - gap / 2)
            size = [hi[k] - lo[k] for k in range(3)]
            centre = Vector([(hi[k] + lo[k]) / 2 for k in range(3)])
            if i == courses - 1 and j == 1:
                # Top course broken off: a rough stump instead of a block.
                parts.append(C.rock(f'stump{j}', rng, (size[0], size[1], size[2] * 0.6), centre - Vector((0, 0, size[2] * 0.2)),
                                    m('stone_dark') if up else m('plate_dark'), flat_bottom=True, rot_z=0.0))
                a = b
                continue
            mat = (m('stone_dark') if rng.random() < 0.5 else m('stone')) if up else (m('plate') if rng.random() < 0.6 else m('plate_dark'))
            ob = C.box(f'b{i}{j}', size, centre, mat, bevel=0.03 if up else 0.02,
                       chips=S.block_chips(rng, size, 0.7 if up else 0.3, (0.04, 0.1)))
            # Loose: each block shoved and twisted off true.
            ob.rotation_euler = (rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03), rng.uniform(-0.06, 0.06))
            ob.location = (rng.uniform(-0.02, 0.02), rng.uniform(-0.02, 0.02), 0)
            C.apply_modifiers(ob)
            parts.append(ob)
            a = b
        z += h
    # Through-cracks on the two camera faces, floored with the glow.
    blocks = [p for p in parts if p.name.startswith('b')]
    bpy.context.view_layer.update()
    for k in (0, 1, 2, 3):
        cut = F.crack(f'tc{k}', rng, (rng.uniform(-0.3, -0.1), 1.0), (rng.uniform(0.0, 0.3), -0.1), m('crack_glow'),
                      width=0.035, depth=0.08, steps=7, amp=0.07)
        cut.matrix_world = S.face_cutter_matrix(k, -0.47) @ cut.matrix_world
        for ob in blocks:
            lo, hi = C.bounds([ob])
            if True:
                c2 = cut.copy()
                c2.data = cut.data.copy()
                C.link(c2)
                C.boolean(ob, [c2])
        C.delete([cut])
    # Hazard tape band wrapped round at about chest height: the "breakable" tag.
    for k in range(4):
        hz = F.hazard_stripes(f'tape{k}', -0.46, 0.46, 0.0, 0.09, 0.003, m, period=0.12, slant=0.06, height=0.008)
        mtx = S.face_rot(k) @ Matrix.Translation((0, -0.49, 0.78)) @ S.FACE
        for s in hz:
            s.matrix_world = mtx @ s.matrix_world
        parts += hz
        # A bolted tag plate on the tape with an accent_glow lamp: the game tints it with the
        # breakable's accent colour, tying it to the HUD/wire language like the other mechanisms.
        tag = [C.box_mm(f'tagp{k}', (-0.11, -0.515, 0.74), (0.11, -0.49, 0.9), m('metal_dark'), bevel=0.01),
               C.box_mm(f'tagl{k}', (-0.07, -0.522, 0.8), (0.07, -0.51, 0.84), m('accent_glow')),
               C.rivet(f'tagr{k}a', (-0.085, -0.515, 0.82), (0, -1, 0), m('metal'), radius=0.012, height=0.008),
               C.rivet(f'tagr{k}b', (0.085, -0.515, 0.82), (0, -1, 0), m('metal'), radius=0.012, height=0.008)]
        for t in tag:
            t.matrix_world = S.face_rot(k) @ t.matrix_world
        parts += tag
    for i in range(5):
        parts.append(C.rock(f'deb{i}', rng, (0.1, 0.08, 0.06), (rng.uniform(-0.42, 0.42), rng.choice((-0.5, 0.5)) * rng.uniform(0.86, 0.96), 0.02),
                            m('stone') if up else m('plate_dark'), flat_bottom=True))
    if up:
        parts.append(C.moss_pad('moss', rng, (-0.2, 0.0, BREAK_TOP - 0.17), 0.12, 0.04, m('moss')))
    ob = C.join(parts, 'breakable')
    C.finish(ob)
    return [ob]


def breakable_chunks(m, rng, look):
    """Ten chunks filling the breakable's volume (2 x 2 columns in plan, stacked), each its own object
    with its origin at its centre."""
    up = look == 'upper'
    out = []
    cells = []
    for lvl, (z0, z1) in enumerate(((-0.2, 0.25), (0.25, 0.7), (0.7, 1.1))):
        for ix in (-1, 1):
            for iy in (-1, 1):
                cells.append((ix, iy, z0, z1, lvl))
    cells = cells[:10]
    for n, (ix, iy, z0, z1, lvl) in enumerate(cells):
        c = Vector((ix * 0.24, iy * 0.24, (z0 + z1) / 2))
        size = (0.46, 0.46, z1 - z0)
        mat = (m('stone') if n % 3 else m('stone_dark')) if up else (m('plate') if n % 3 else m('plate_dark'))
        ob = C.rock(f'ch{n}', rng, size, (0, 0, 0), mat, jitter=0.18, top_mat=m('crack_glow') if n % 2 else None)
        name = f'Chunk_{n + 1:02d}'
        named(ob, name)
        C.finish(ob)
        ob.location = c
        out.append(ob)
    return out


# ───────────────────────────── laser emitter ─────────────────────────────

def laser_emitter(m, rng, look):
    up = look == 'upper'
    body = []
    if up:
        body.append(C.box_mm('foot', (-0.24, -0.24, -0.02), (0.24, 0.24, 0.12), m('stone'), bevel=0.025,
                             chips=S.block_chips(rng, (0.48, 0.48, 0.14), 0.5), top_mat=m('stone_light')))
        shell = m('paint_yellow')
    else:
        body.append(C.box_mm('foot', (-0.24, -0.24, -0.02), (0.24, 0.24, 0.12), m('trim'), bevel=0.02))
        shell = m('plate')
    body.append(C.box_mm('column', (-0.15, -0.15, 0.12), (0.15, 0.15, 0.6), shell, bevel=0.025))
    body.append(C.box_mm('head', (-0.19, -0.2, 0.33), (0.19, 0.17, 0.6), m('metal') if up else m('plate_dark'), bevel=0.03))
    body.append(C.box_mm('ring', (-0.2, -0.21, 0.6), (0.2, 0.18, 0.65), m('accent_glow')))
    body.append(C.box_mm('cap', (-0.17, -0.18, 0.65), (0.17, 0.15, 0.72), m('metal_dark'), bevel=0.02))
    # Heat fins on the back.
    for i in range(4):
        x = -0.12 + i * 0.08
        body.append(C.box_mm(f'fin{i}', (x - 0.012, 0.15, 0.36), (x + 0.012, 0.23, 0.58), m('metal_dark'), bevel=0.005))
    # Lens barrel pointing front (-Y = Godot +Z).
    body.append(C.cylinder('barrel', 0.1, 0.1, (0, -0.24, BEAM_Y), m('metal_dark'), segments=14, axis='Y', bevel=0.01))
    body.append(C.cylinder('hood', 0.115, 0.03, (0, -0.29, BEAM_Y), m('hazard_dark'), segments=14, axis='Y', bevel=0.006))
    body += chevrons('hz', -0.14, 0.14, 0.16, 0.28, m, period=0.09, plane_y=-0.15)
    if not up:
        cut = C.join([F.ribbon(f'r{k}', [(q[0], 0.0 + q[1]) for q in pl], 0.018, -0.012, 0.05, m('rune_glow'))
                      for k, pl in enumerate(F.glyph_strokes(rng, 0.08, 0.14))], 'rc')
        cut.matrix_world = Matrix.Rotation(math.pi / 2, 4, 'Z') @ Matrix.Translation((0, -0.15, 0.25)) @ S.FACE
        col = [b for b in body if b.name == 'column'][0]
        C.boolean(col, [cut])
    lens = [C.cylinder('lens', 0.075, 0.03, (0, -0.305, BEAM_Y), m('lens_glow'), segments=14, axis='Y', bevel=0.008)]
    return [as_part(body, 'Body'), as_part(lens, 'Lens', origin=(0, -0.305, BEAM_Y))]


# ───────────────────────────── core ─────────────────────────────

def core(m, rng, look):
    up = look == 'upper'
    shell = []
    if up:
        shell.append(C.cylinder('plinth', 0.46, 0.18, (0, 0, 0.07), m('stone'), segments=8, bevel=0.03, cap_mat=m('stone_light')))
        rim = m('paint_yellow')
    else:
        shell.append(C.cylinder('plinth', 0.46, 0.18, (0, 0, 0.07), m('trim'), segments=8, bevel=0.03, cap_mat=m('plate')))
        rim = m('plate')
    shell.append(C.cylinder('drum', 0.3, 0.3, (0, 0, 0.31), rim, segments=8, bevel=0.025, radius2=0.24))
    shell.append(C.cylinder('collar', 0.26, 0.06, (0, 0, 0.49), m('metal_dark'), segments=12, bevel=0.012))
    shell.append(C.cylinder('ring', 0.27, 0.025, (0, 0, 0.43), m('accent_glow'), segments=16))
    # Four claws curling up around the heart: tapered tubes.
    for i in range(4):
        a = i * math.pi / 2 + math.pi / 4
        d = Vector((math.cos(a), math.sin(a), 0))
        pts = [d * 0.22 + Vector((0, 0, 0.45)), d * 0.36 + Vector((0, 0, 0.7)), d * 0.32 + Vector((0, 0, 1.05)), d * 0.18 + Vector((0, 0, 1.28))]
        shell.append(C.tube(f'claw{i}', pts, 0.045, m('metal') if up else m('plate_light'), sides=8, elbow=0.12))
        shell.append(C.box(f'clawtip{i}', (0.07, 0.07, 0.1), d * 0.17 + Vector((0, 0, 1.3)), m('metal_dark'), bevel=0.012, rot_z=a))
    # Floor sockets with cable stubs.
    for i in range(3):
        a = i * math.tau / 3
        p0 = Vector((math.cos(a) * 0.4, math.sin(a) * 0.4, 0.02))
        p1 = Vector((math.cos(a) * 0.6, math.sin(a) * 0.6, 0.02))
        shell.append(C.tube(f'cable{i}', [p0 + Vector((0, 0, 0.08)), p0, p1], 0.03, m('hazard_dark') if up else m('seam'), sides=8, elbow=0.06))
    if not up:
        cut = F.rune_circle(m, 0.36, 0.16, ticks=True)
        plinth = shell[0]
        C.boolean(plinth, [cut])
    hearts = [heart_crystal(m)]
    # Clamp hardware: a banded girdle and two end caps, so the heart reads as a built device (a
    # power cell held in the claws), not a loose gem. Dark metal against the core_glow facets keeps
    # it legible both dormant (the game dims core_glow) and struck (bright).
    hearts.append(C.cylinder('girdle', 0.205, 0.06, (0, 0, HEART_Y), m('metal_dark'), segments=6, bevel=0.01))
    hearts.append(C.cylinder('girdle_lip', 0.215, 0.018, (0, 0, HEART_Y), m('accent_glow'), segments=6))
    for sz, z in ((1, HEART_Y + 0.25), (-1, HEART_Y - 0.21)):
        hearts.append(C.cylinder(f'endcap{sz}', 0.07, 0.07, (0, 0, z), m('metal_dark'), segments=6, bevel=0.012,
                                 radius2=0.045 if sz > 0 else 0.09))
    return [as_part(shell, 'Shell'), as_part(hearts, 'Heart', origin=(0, 0, HEART_Y))]


def heart_crystal(m):
    """Hexagonal crystal: apexes top and bottom, two staggered rings, convex hull with the coplanar
    facets merged, so the toon shader gets a few large clean facets."""
    pts = [Vector((0, 0, HEART_Y + 0.33)), Vector((0, 0, HEART_Y - 0.27))]
    for i in range(6):
        a = i * math.tau / 6
        pts.append(Vector((math.cos(a) * 0.19, math.sin(a) * 0.19, HEART_Y + 0.09)))
        b = a + math.tau / 12
        pts.append(Vector((math.cos(b) * 0.17, math.sin(b) * 0.17, HEART_Y - 0.08)))
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in pts]
    bmesh.ops.convex_hull(bm, input=vs, use_existing_faces=False)
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(2), verts=bm.verts, edges=bm.edges)
    return C.obj_from_bm('crystal', bm, [m('core_glow')])


# ───────────────────────────── exit pad ─────────────────────────────

def exit_pad(m, rng, look):
    up = look == 'upper'
    parts = []
    e = 0.46
    fr = m('metal') if up else m('plate')
    for i, (lo, hi) in enumerate((((-e, -e), (e, -e + 0.06)), ((-e, e - 0.06), (e, e)), ((-e, -e + 0.06), (-e + 0.06, e - 0.06)),
                                  ((e - 0.06, -e + 0.06), (e, e - 0.06)))):
        parts.append(C.box_mm(f'fr{i}', (lo[0], lo[1], -0.02), (hi[0], hi[1], 0.03), fr, bevel=0.01))
    parts.append(C.box_mm('deck', (-e + 0.06, -e + 0.06, -0.02), (e - 0.06, e - 0.06, 0.012), m('metal_dark') if up else m('seam')))
    parts.append(F.annulus('ring', 0.24, 0.3, 0.012, 0.026, m('exit_glow'), segs=32))
    parts.append(C.cylinder('disc', 0.16, 0.02, (0, 0, 0.02), m('exit_glow'), segments=24))
    # Chevrons pointing outward on all four sides ("out of here").
    for k in range(4):
        ch = C.prism(f'chev{k}', [(-0.09, 0.32), (0.0, 0.39), (0.09, 0.32), (0.09, 0.355), (0.0, 0.425), (-0.09, 0.355)], 0.012, 0.026,
                     m('exit_glow'))
        ch.matrix_world = Matrix.Rotation(k * math.pi / 2, 4, 'Z')
        parts.append(ch)
    for i, (sx, sy) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1))):
        x, y = sx * (e - 0.07), sy * (e - 0.07)
        parts.append(C.box_mm(f'py{i}', (x - 0.05, y - 0.05, 0.0), (x + 0.05, y + 0.05, 0.36), m('paint_yellow') if up else m('trim'), bevel=0.015))
        parts.append(C.box_mm(f'tip{i}', (x - 0.045, y - 0.045, 0.36), (x + 0.045, y + 0.045, 0.42), m('exit_glow'), bevel=0.01))
    ob = C.join(parts, 'exit_pad')
    C.finish(ob)
    return [ob]


BUILDERS = {'door': door, 'switch': switch, 'plate': plate, 'breakable': breakable, 'breakable_chunks': breakable_chunks,
            'laser_emitter': laser_emitter, 'core': core, 'exit_pad': exit_pad}

ANIMATED = {'door', 'switch', 'plate'}


def has_animation(piece):
    return piece in ANIMATED


NOTES = {
    'door': {'objects': ['Frame', 'Panel'], 'open': {'object': 'Panel', 'translate_y': -PANEL_DROP}, 'actions': ['open'],
             'placement': 'spans X across the tile (rotate 90 deg when the wall line runs along Z)'},
    'switch': {'objects': ['Base', 'Lever'], 'lever_rotation_z': {'off': LEVER_ANGLE, 'on': -LEVER_ANGLE}, 'actions': ['toggle']},
    'plate': {'objects': ['Base', 'Pad'], 'pressed': {'object': 'Pad', 'translate_y': -PAD_TRAVEL}, 'actions': ['press']},
    'breakable': {'objects': ['breakable'], 'height': BREAK_TOP},
    'breakable_chunks': {'objects': [f'Chunk_{i:02d}' for i in range(1, 11)]},
    'laser_emitter': {'objects': ['Body', 'Lens'], 'beam_y': BEAM_Y, 'facing': '+Z'},
    'core': {'objects': ['Shell', 'Heart'], 'heart_y': HEART_Y},
    'exit_pad': {'objects': ['exit_pad']},
}


def manifest_extra(piece, look):
    return dict(NOTES[piece])


def build(piece: str, look: str) -> list:
    m = C.Mats(look)
    rng = random.Random(f'{piece}:{look}')
    return BUILDERS[piece](m, rng, look)


def extra_previews(piece, look, objs):
    """Open/closed and off/on states rendered side by side for review."""
    import os
    by = {o.name: o for o in objs}
    out = os.path.join(C.PREVIEW_DIR, 'pieces')
    C.setup_render(look, 640, 640)
    # Actions drive the moving part; detach while posing stills, then restore for export.
    saved = {o.name: (o.animation_data.action if o.animation_data else None) for o in objs}
    for o in objs:
        if o.animation_data:
            o.animation_data.action = None
    if piece == 'door':
        p = by['Panel']
        p.location.z = -PANEL_DROP
        C.render_view([by['Frame']], os.path.join(out, f'{piece}__{look}_open_iso.png'), 'iso')
        p.location.z = 0
        C.render_view([by['Frame']], os.path.join(out, f'{piece}__{look}_closed_iso.png'), 'iso')
    elif piece == 'switch':
        lv = by['Lever']
        for state, ang in (('off', -LEVER_ANGLE), ('on', LEVER_ANGLE)):
            lv.rotation_euler = (0, ang, 0)
            C.render_view(objs, os.path.join(out, f'{piece}__{look}_{state}_iso.png'), 'iso')
            C.render_view(objs, os.path.join(out, f'{piece}__{look}_{state}_front.png'), 'front')
        lv.rotation_euler = (0, -LEVER_ANGLE, 0)
    elif piece == 'plate':
        pd = by['Pad']
        pd.location.z = -PAD_TRAVEL
        C.render_view(objs, os.path.join(out, f'{piece}__{look}_pressed_iso.png'), 'iso')
        pd.location.z = 0
    for o in objs:
        if saved.get(o.name) is not None:
            o.animation_data.action = saved[o.name]
