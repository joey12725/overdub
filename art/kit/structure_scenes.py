"""Review scenes built from the EXPORTED .glb files (so they also prove the exports load):
  * contact_sheet(look): every structure/mechanism piece of one look laid out in a grid.
  * diorama(look): a small room assembled by script from the kit (floors, walls with caps, camera-side
    cutaways, a door, a switch, a plate, a breakable, an exit pad, a ledge with edge trim and a
    barrier, cliff skirt underneath) plus decor props when their .glb files exist.

Rendered with EEVEE in an approximation of the game's look: stepped toon lighting, inverted-hull ink
outlines, glow materials emissive, orthographic camera at yaw 45 / pitch 35.
"""
from __future__ import annotations

import math
import os

import bpy
from mathutils import Vector

import common as C

SHEET_ORDER = ['floor_solid', 'floor_cracked', 'floor_grate', 'floor_overgrown', 'floor_rune',
               'wall', 'wall_top_a', 'wall_top_b', 'wall_cut', 'barrier_low', 'cliff_skirt', 'edge_trim',
               'door', 'switch', 'plate', 'breakable', 'breakable_chunks', 'laser_emitter', 'core', 'exit_pad']

DECOR = ['crate', 'barrel', 'lamp', 'console', 'generator', 'vines', 'bush', 'rubble', 'pipe', 'vent', 'neon', 'cable',
         'rune_panel', 'chest']

_cache: dict[str, list] = {}


def kit_path(name, look):
    for key in (f'{name}__{look}', name):
        p = os.path.join(C.KIT_DIR, key + '.glb')
        if os.path.exists(p):
            return p
    return None


def import_piece(name, look):
    """Import a piece once into a hidden template collection; return its top-level objects."""
    key = f'{name}:{look}'
    if key in _cache:
        return _cache[key]
    path = kit_path(name, look)
    if path is None:
        _cache[key] = []
        return []
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    tmpl = bpy.data.collections.get('templates') or bpy.data.collections.new('templates')
    if tmpl.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(tmpl)
    for o in new:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        tmpl.objects.link(o)
        if o.animation_data:
            o.animation_data.action = None
    tmpl.hide_render = True
    tmpl.hide_viewport = True
    tops = [o for o in new if o.parent is None]
    _cache[key] = tops
    return tops


def place(name, look, x, y, z=0.0, rot=0, setup=None):
    """Instance a piece at Blender (x, y, z) with `rot` quarter turns. Returns {object name: copy}."""
    tops = import_piece(name, look)
    if not tops:
        return {}
    out = {}

    def dup(o, parent):
        c = o.copy()
        bpy.context.scene.collection.objects.link(c)
        c.parent = parent
        if c.animation_data:
            c.animation_data.action = None
        out[o.name.split('.')[0]] = c
        for ch in o.children:
            dup(ch, c)
        return c

    root = bpy.data.objects.new(f'{name}_inst', None)
    bpy.context.scene.collection.objects.link(root)
    root.location = (x, y, z)
    root.rotation_euler = (0, 0, rot * math.pi / 2)
    for o in tops:
        dup(o, root)
    if setup:
        setup(out)
    return out


# ───────────────────────────── toon look ─────────────────────────────

def toon_materials(look):
    """Rewrite every material as stepped toon shading (or emission for *_glow) and add an ink
    material; returns the ink material."""
    ink = bpy.data.materials.get('ink_outline') or bpy.data.materials.new('ink_outline')
    ink.use_nodes = True
    nt = ink.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    em = nt.nodes.new('ShaderNodeEmission')
    em.inputs['Color'].default_value = (*C.hex_rgb(0x140C0A if look == 'upper' else 0x07040C), 1)
    nt.links.new(em.outputs[0], out.inputs[0])
    ink.use_backface_culling = True
    for mat in bpy.data.materials:
        if mat == ink or not mat.use_nodes:
            continue
        bsdf = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if bsdf is None:
            continue
        col = tuple(bsdf.inputs['Base Color'].default_value)
        nt = mat.node_tree
        nt.nodes.clear()
        out = nt.nodes.new('ShaderNodeOutputMaterial')
        if mat.name.split('.')[0].endswith('_glow'):
            em = nt.nodes.new('ShaderNodeEmission')
            em.inputs['Color'].default_value = col
            em.inputs['Strength'].default_value = 2.2
            nt.links.new(em.outputs[0], out.inputs[0])
            continue
        diff = nt.nodes.new('ShaderNodeBsdfDiffuse')
        diff.inputs['Color'].default_value = (1, 1, 1, 1)
        s2r = nt.nodes.new('ShaderNodeShaderToRGB')
        ramp = nt.nodes.new('ShaderNodeValToRGB')
        ramp.color_ramp.interpolation = 'CONSTANT'
        els = ramp.color_ramp.elements
        els[0].position = 0.0
        els[0].color = (0.5, 0.5, 0.56, 1) if look == 'upper' else (0.46, 0.42, 0.56, 1)
        els[1].position = 0.2
        els[1].color = (0.78, 0.76, 0.76, 1)
        e3 = els.new(0.62)
        e3.color = (1.0, 1.0, 1.0, 1)
        mul = nt.nodes.new('ShaderNodeMixRGB')
        mul.blend_type = 'MULTIPLY'
        mul.inputs['Fac'].default_value = 1.0
        mul.inputs['Color2'].default_value = col
        em = nt.nodes.new('ShaderNodeEmission')
        nt.links.new(diff.outputs[0], s2r.inputs[0])
        nt.links.new(s2r.outputs['Color'], ramp.inputs['Fac'])
        nt.links.new(ramp.outputs['Color'], mul.inputs['Color1'])
        nt.links.new(mul.outputs[0], em.inputs['Color'])
        nt.links.new(em.outputs[0], out.inputs[0])
    return ink


def add_outlines(ink, thickness=0.012):
    for o in bpy.context.scene.objects:
        if o.type != 'MESH' or not o.visible_get():
            continue
        if ink.name not in [m.name for m in o.data.materials if m]:
            o.data.materials.append(ink)
        mod = o.modifiers.new('ink', 'SOLIDIFY')
        mod.thickness = thickness
        mod.offset = 1.0
        mod.use_flip_normals = True
        mod.use_rim = False
        mod.material_offset = len(o.data.materials) - 1
        mod.material_offset_rim = len(o.data.materials) - 1


def setup_eevee(look, width, height):
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE_NEXT'
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = 'Standard'
    scene.render.film_transparent = False
    if scene.world is None:
        scene.world = bpy.data.worlds.new('World')
    w = scene.world
    w.use_nodes = True
    bg = w.node_tree.nodes.get('Background')
    bg.inputs['Color'].default_value = (*C.hex_rgb(C.BG[look]), 1)
    bg.inputs['Strength'].default_value = 1.0
    try:
        scene.eevee.taa_render_samples = 32
        scene.eevee.use_shadows = True
    except AttributeError:
        pass
    sun = bpy.data.lights.new('sun', 'SUN')
    sun.energy = 1.0
    sun.color = C.hex_rgb(0xFFF0D6) if look == 'upper' else C.hex_rgb(0xCDC2F0)
    sun.angle = math.radians(2)
    so = bpy.data.objects.new('sun', sun)
    scene.collection.objects.link(so)
    # Key from the camera's upper left so both visible faces of a block get different steps.
    so.rotation_euler = Vector((0.3, 0.55, -0.78)).to_track_quat('-Z', 'Y').to_euler()


def render_iso(objs_bounds, path, margin=1.08):
    C.render_view(objs_bounds, path, 'iso', margin=margin)


# ───────────────────────────── contact sheet ─────────────────────────────

def _door_open(objs):
    if 'Panel' in objs:
        objs['Panel'].location.z -= 1.58  # mechanisms.PANEL_DROP


def _lever_on(objs):
    if 'Lever' in objs:
        objs['Lever'].rotation_euler = (0, 0.65, 0)  # mechanisms.LEVER_ANGLE, the 'on' end of `toggle`


def _lever_off(objs):
    if 'Lever' in objs:
        objs['Lever'].rotation_euler = (0, -0.65, 0)


def _pad_down(objs):
    if 'Pad' in objs:
        objs['Pad'].location.z -= 0.045  # mechanisms.PAD_TRAVEL


# Sheet entries: (piece, label, setup). Mechanism states are shown side by side.
SHEET = [('floor_solid', None, None), ('floor_cracked', None, None), ('floor_grate', None, None),
         ('floor_overgrown', None, None), ('floor_rune', None, None), ('exit_pad', None, None),
         ('wall', None, None), ('wall_top_a', 'wall + wall_top_a', None), ('wall_top_b', 'wall + wall_top_b', None),
         ('wall_cut', None, None), ('barrier_low', None, None), ('edge_trim', 'floor + edge_trim', None),
         ('door', 'door (closed)', None), ('door', 'door (open)', _door_open), ('switch', 'switch (off)', _lever_off),
         ('switch', 'switch (on)', _lever_on), ('plate', 'plate (up)', None), ('plate', 'plate (pressed)', _pad_down),
         ('breakable', None, None), ('breakable_chunks', None, None), ('laser_emitter', None, None),
         ('core', None, None), ('cliff_skirt', 'floor + cliff_skirt', None)]


def contact_sheet(look, pieces=None):
    C.reset_scene()
    _cache.clear()
    entries = [e for e in SHEET if pieces is None or e[0] in pieces]
    cols = 6
    # Grid along the iso camera's screen axes: right = (+X, +Y)/sqrt2, toward the camera = (+X, -Y)/sqrt2.
    col_step, row_step = 2.3, 7.2
    lab_mat = C.Mats(look)('stone_light' if look == 'upper' else 'plate_light')
    r2 = 0.7071
    for i, (name, text, setup) in enumerate(entries):
        col, row = i % cols, i // cols
        x = (col * col_step + row * row_step) * r2
        y = (col * col_step - row * row_step) * r2
        z = 0.0
        if name.startswith('wall_top'):
            place('wall', look, x, y)
            z = 1.6
        elif name in ('edge_trim', 'cliff_skirt'):
            place('floor_solid', look, x, y)
        place(name, look, x, y, z, setup=setup)
        # Label on the ground in front of the piece (toward the camera), below any hanging part.
        C.label(text or name, (x + 1.25 * r2, y - 1.25 * r2, -1.0), size=0.24, mat=lab_mat)
    ink = toon_materials(look)
    add_outlines(ink, 0.02)
    setup_eevee(look, 2400, 1800)
    vis = [o for o in bpy.context.scene.objects if o.type in ('MESH',) and o.visible_get()]
    render_iso(vis, os.path.join(C.PREVIEW_DIR, f'contact_sheet__{look}.png'), margin=1.12)


# ───────────────────────────── diorama ─────────────────────────────

# Map in the game's tile convention: (c, r) -> Godot (x = c + 0.5, z = r + 0.5) -> Blender (c + 0.5, -(r + 0.5)).
# '#' wall, 'D' door, 'B' breakable, '.' floor, ':' grate, ',' overgrown, '~' rune, '=' barrier, ' ' void.
ROOM = [
    '###D###',
    '#.....#',
    '#.:..~#',
    'B..,..#',
    '#.....#',
    '##...##',
    ' ..=.. ',
]


def tile_xy(c, r):
    return c + 0.5, -(r + 0.5)


def diorama(look):
    C.reset_scene()
    _cache.clear()
    rows = len(ROOM)
    cols = max(len(r) for r in ROOM)

    def at(c, r):
        if r < 0 or r >= rows or c < 0 or c >= len(ROOM[r]):
            return ' '
        return ROOM[r][c]

    ground = lambda c, r: at(c, r) != ' '
    open_ = lambda c, r: at(c, r) in '.:,~='
    floor_kind = {'.': 'floor_solid', ':': 'floor_grate', ',': 'floor_overgrown', '~': 'floor_rune', '=': 'floor_solid'}
    for r in range(rows):
        for c in range(cols):
            ch = at(c, r)
            if ch == ' ':
                continue
            x, y = tile_xy(c, r)
            h = (c * 7 + r * 13) % 5
            if ch in floor_kind:
                kind = floor_kind[ch]
                if ch == '.' and h == 3:
                    kind = 'floor_cracked'
                place(kind, look, x, y, rot=(c * 3 + r) % 4)
                if ch == '=':
                    place('barrier_low', look, x, y)
            elif ch == '#':
                # Cutaway rule (chapter 16): a wall with open floor behind it (camera's view) is cut.
                cut = open_(c - 1, r) or open_(c, r - 1) or open_(c - 1, r - 1)
                if cut:
                    place('wall_cut', look, x, y, rot=h % 4)
                else:
                    place('wall', look, x, y, rot=h % 4)
                    cap = ('wall_top_a', 'wall_top_b', None)[(c + r) % 3]
                    if cap:
                        # Caps face the room: their detailed side toward the camera (front = -Y).
                        place(cap, look, x, y, 1.6, rot=0 if r == 0 else 3)
            elif ch == 'D':
                place('floor_solid', look, x, y)
                place('door', look, x, y)
            elif ch == 'B':
                place('floor_solid', look, x, y)
                place('breakable', look, x, y, rot=1)
            # Diorama underside and edges.
            exposed = [(dc, dr) for dc, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)) if not ground(c + dc, r + dr)]
            if exposed:
                place('cliff_skirt', look, x, y, rot=(c + 2 * r) % 4)
            if ch in floor_kind:
                for dc, dr in exposed:
                    # edge_trim faces -Y (Godot +Z, row + 1); quarter turns: +X = 1, +Y = 2, -X = 3.
                    rot = {(0, 1): 0, (1, 0): 1, (0, -1): 2, (-1, 0): 3}[(dc, dr)]
                    place('edge_trim', look, x, y, rot=rot)

    # Mechanisms: the switch thrown on; in the lower room the door it drives stands open (the upper
    # room shows it shut), so both door states are reviewed in context.
    place('switch', look, *tile_xy(5, 1), setup=_lever_on)
    if look == 'lower':
        door_inst = [o for o in bpy.context.scene.objects if o.name.startswith('Panel') and o.parent and o.parent.name.startswith('door_inst')]
        for o in door_inst:
            o.location.z -= 1.58
    place('plate', look, *tile_xy(2, 4))
    place('exit_pad', look, *tile_xy(4, 6))
    place('laser_emitter', look, *tile_xy(1, 1), rot=1)
    place('core', look, *tile_xy(4, 3))
    # Decor props from the decor engineer's kit, when exported. (piece, col, row, quarter turns,
    # offset): props face Godot +Z (Blender -Y) at rot 0; rot 1 faces +X, rot 3 faces -X.
    props = [('console', 2, 1, 0, (0, 0.12)), ('lamp', 4, 1, 0, (0.18, 0.2)), ('crate', 1, 2, 1, (0, 0)),
             ('chest', 5, 3, 3, (0.15, 0)), ('barrel', 5, 4, 0, (0.1, -0.05)), ('rubble', 1, 3, 0, (-0.05, 0)),
             ('generator', 1, 6, 0, (0, 0)), ('bush', 5, 6, 0, (0, 0))]
    if look == 'lower':
        props[1] = ('neon', 4, 1, 0, (0.25, 0.25))
        props.append(('cable', 3, 2, 0, (0, 0)))
    for name, c, r, rot, (dx, dy) in props:
        if kit_path(name, look):
            x, y = tile_xy(c, r)
            place(name, look, x + dx, y + dy, rot=rot)
    # Wall-mounted growth: origin at the foot of a wall face, hanging toward the room.
    for c, r, rot, x, y in ((5, 0, 0, 5.5, -1.0), (0, 2, 1, 1.0, -2.5)):
        if kit_path('vines', look) and (look == 'upper' or c == 0):
            place('vines', look, x, y, rot=rot)
    ink = toon_materials(look)
    add_outlines(ink, 0.022)
    setup_eevee(look, 1600, 1200)
    vis = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.visible_get()]
    render_iso(vis, os.path.join(C.PREVIEW_DIR, f'diorama__{look}.png'), margin=1.05)
    # Game-size check: the same view at the in-game scale (~64 px per tile).
    bpy.context.scene.render.resolution_x = 640
    bpy.context.scene.render.resolution_y = 480
    render_iso(vis, os.path.join(C.PREVIEW_DIR, f'diorama__{look}_small.png'), margin=1.05)
