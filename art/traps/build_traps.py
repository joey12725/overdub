"""Build the trap models, export .glb files, merge the kit manifest and render previews.

  blender --background --threads 8 --python art/traps/build_traps.py -- [options]

Options:
  --pieces a,b,...   only these pieces (default: all of traps.PIECES)
  --looks upper,lower
  --no-export        build (and preview) only
  --no-previews      skip the per-piece Workbench stills
  --sheet            render the contact sheet per look (from the exported .glb files)
  --diorama          render the trap room per look, in its safe and live states (from the .glb files)

Outputs: assets/models/kit/trap_<name>__<look>.glb (trap_dart_bolt.glb has no look),
assets/models/kit/manifest.json (merged: only trap_* keys are written), art/previews/traps/*.
"""
from __future__ import annotations

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import bpy  # noqa: E402

import traplib as T  # noqa: E402
import traps as TR  # noqa: E402
from traplib import C  # noqa: E402

ALL_THEMES = ['upper', 'mid', 'lower', 'core']


def parse_args(argv):
    args = {'pieces': None, 'looks': list(C.LOOKS), 'export': True, 'previews': True, 'sheet': False, 'diorama': False}
    it = iter(argv)
    for a in it:
        if a == '--pieces':
            args['pieces'] = next(it).split(',')
        elif a == '--looks':
            args['looks'] = next(it).split(',')
        elif a == '--no-export':
            args['export'] = False
        elif a == '--no-previews':
            args['previews'] = False
        elif a == '--sheet':
            args['sheet'] = True
        elif a == '--diorama':
            args['diorama'] = True
    return args


def build_all(args):
    pieces = args['pieces'] if args['pieces'] is not None else list(TR.PIECES)
    manifest = {}
    for piece in pieces:
        if piece not in TR.BUILDERS:
            raise SystemExit(f'unknown piece {piece}')
        lookless = piece in TR.LOOKLESS
        for look in (['upper'] if lookless else args['looks']):
            C.reset_scene()
            objs = TR.build(piece, look)
            key = piece if lookless else f'{piece}__{look}'
            print(f'[traps] built {key}: ' + ', '.join(f'{o.name}({len(o.data.polygons)}f)' for o in objs))
            if args['export']:
                C.export_glb(objs, os.path.join(C.KIT_DIR, key + '.glb'), animations=False)
                aabb = C.godot_aabb(objs)
                entry = {'file': key + '.glb', 'themes': ALL_THEMES if lookless else C.LOOK_THEMES[look], 'size': aabb['size'],
                         'aabb': {k: v for k, v in aabb.items() if k != 'size'}}
                entry.update(TR.manifest_extra(piece, look))
                manifest[key] = entry
                if not lookless:
                    # The same fallbacks as the rest of the kit: <name>, and the themes a look also serves.
                    if look == 'upper':
                        manifest[piece] = dict(entry)
                    for theme in C.LOOK_THEMES[look]:
                        if theme != look:
                            manifest[f'{piece}__{theme}'] = dict(entry)
            if args['previews']:
                out = os.path.join(T.PREVIEW_DIR, 'pieces')
                C.setup_render(look, 640, 640)
                C.render_view(objs, os.path.join(out, f'{key}_iso.png'), 'iso')
                # The same camera from the opposite corner: what the player sees when the trap faces away.
                C.render_view(objs, os.path.join(out, f'{key}_iso_behind.png'), rot=(90 - 35, 0, 225))
    if manifest:
        C.update_manifest(manifest)
        print(f'[traps] manifest: {len(manifest)} entries merged')


# ───────────────────────────── review scenes (from the exported files) ─────────────────────────────

def P(name, look, x, z, y=0.0, rot=0, setup=None):
    """Place an exported piece at Godot (x, y, z). rot: quarter turns; 0 acts toward +Z (s), 1 +X (e),
    2 -Z (n), 3 -X (w)."""
    import structure_scenes as SC
    return SC.place(name, look, x, -z, y, rot=rot, setup=setup)


def hide(o):
    o.hide_render = True
    o.hide_viewport = True


def s_spikes(t):
    def f(o):
        o['Spikes'].scale = (1, 1, max(TR.SPIKE_REST, t))
    return f


def s_crusher(cells, t):
    def f(o):
        hz = TR.HEAD_HOME_Z + t * (cells + 0.5 - TR.HEAD_END_GAP - TR.HEAD_HOME_Z)
        o['Head'].location.y = -hz
        o['Ram'].scale = (1, hz - TR.RAM_INTO_HEAD, 1)
    return f


def s_stamper(t):
    def f(o):
        hy = TR.STAMP_HOME_Y + t * (TR.STAMP_DOWN_Y - TR.STAMP_HOME_Y)
        o['Head'].location.z = hy
        o['Ram'].scale = (1, 1, TR.STAMP_HOME_Y + TR.STAMP_ROD_REST - hy)
    return f


def s_conveyor(back, front):
    def f(o):
        if not back:
            hide(o['End_Back'])
            hide(o['Roller_Back'])
        if not front:
            hide(o['End_Front'])
            hide(o['Roller_Front'])
    return f


def s_flame(on, reach):
    def f(o):
        if on:
            o['Jet'].scale = (1, reach - (TR.NOZZLE_MOUTH_Z - 0.5), 1)
        else:
            hide(o['Jet'])
    return f


def s_dart(t, firing=False, enabled=True):
    def f(o):
        for i, n in enumerate(TR.PIP_NAMES):
            if not enabled or (i + 1) / TR.PIPS > t + 1e-6:
                hide(o[n])
        if firing:
            o['Muzzle'].location.y += TR.MUZZLE_RECOIL
        else:
            hide(o['Flash'])
        if not enabled:
            o['Shutter'].location.z -= TR.SHUTTER_TRAVEL
    return f


def s_bumper(t):
    def f(o):
        o['Pad'].location.z = TR.PAD_POP * t
        o['Spring'].scale = (1, 1, TR.SPRING_REST + TR.PAD_POP * t)
    return f


def s_sensor(reach):
    def f(o):
        if reach is None:
            hide(o['Beam'])
        else:
            o['Beam'].scale = (1, reach, 1)
    return f


def s_relay(lit, lamp=True):
    def f(o):
        for i, n in enumerate(TR.TICK_NAMES):
            if i >= lit:
                hide(o[n])
        if not lamp:
            hide(o['Lamp'])
    return f


def s_magnet(radius):
    def f(o):
        o['Ring'].scale = (radius, radius, 1)
    return f


def floor(look, x, z, n=0):
    P('floor_cracked' if n % 5 == 3 else 'floor_solid', look, x, z, rot=n % 4)


def set_glow(levels):
    """Emulate the game dimming / lighting state lamps: {material: emission strength}."""
    for mat in bpy.data.materials:
        base = mat.name.split('.')[0]
        if base in levels and mat.use_nodes:
            for n in mat.node_tree.nodes:
                if n.type == 'EMISSION':
                    n.inputs['Strength'].default_value = levels[base]


def belt_preview_material(look):
    """Preview only: draw the tread the game's shader scrolls, from the Belt's UVs (8 ribs per tile
    along V). Proves the UVs run along the travel axis."""
    for mat in bpy.data.materials:
        if mat.name.split('.')[0] != 'belt':
            continue
        nt = mat.node_tree
        nt.nodes.clear()
        out = nt.nodes.new('ShaderNodeOutputMaterial')
        em = nt.nodes.new('ShaderNodeEmission')
        uv = nt.nodes.new('ShaderNodeTexCoord')
        sep = nt.nodes.new('ShaderNodeSeparateXYZ')
        mul = nt.nodes.new('ShaderNodeMath')
        mul.operation = 'MULTIPLY'
        mul.inputs[1].default_value = 8.0
        fr = nt.nodes.new('ShaderNodeMath')
        fr.operation = 'FRACT'
        gt = nt.nodes.new('ShaderNodeMath')
        gt.operation = 'GREATER_THAN'
        gt.inputs[1].default_value = 0.72
        mix = nt.nodes.new('ShaderNodeMixRGB')
        mix.inputs['Color1'].default_value = (*C.hex_rgb(T.EXTRA[look]['belt']), 1)
        mix.inputs['Color2'].default_value = (*C.hex_rgb(0x6A5A58 if look == 'upper' else 0x4A3C5C), 1)
        nt.links.new(uv.outputs['UV'], sep.inputs[0])
        nt.links.new(sep.outputs['Y'], mul.inputs[0])
        nt.links.new(mul.outputs[0], fr.inputs[0])
        nt.links.new(fr.outputs[0], gt.inputs[0])
        nt.links.new(gt.outputs[0], mix.inputs['Fac'])
        nt.links.new(mix.outputs[0], em.inputs['Color'])
        nt.links.new(em.outputs[0], out.inputs[0])


def render_scene(look, path, width, height, glow, margin=1.06, small=None):
    import structure_scenes as SC
    ink = SC.toon_materials(look)
    belt_preview_material(look)
    set_glow(glow)
    SC.add_outlines(ink, 0.02)
    SC.setup_eevee(look, width, height)
    vis = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.visible_get() and not o.hide_render]
    SC.render_iso(vis, path, margin=margin)
    if small:
        bpy.context.scene.render.resolution_x, bpy.context.scene.render.resolution_y = small[1], small[2]
        SC.render_iso(vis, small[0], margin=margin)


def wall_unit(look, piece, x, z, lane, n_lane, setup):
    """A wall tile at (x, z - 1) carrying a wall-mounted machine, and its lane running toward +Z."""
    P('wall', look, x, z - 1)
    P(piece, look, x, z - 1, setup=setup)
    for k in range(n_lane):
        floor(look, x, z + k)
        P(lane, look, x, z + k)


def e_spikes(t):
    def f(look, x, z):
        floor(look, x, z)
        P('trap_spikes', look, x, z, setup=s_spikes(t))
    return f


def e_crusher(t):
    def f(look, x, z):
        P('trap_crusher', look, x, z - 1, setup=s_crusher(2, t))
        for k in range(2):
            floor(look, x, z + k)
            P('trap_crusher_lane', look, x, z + k)
    return f


def e_stamper(t):
    def f(look, x, z):
        floor(look, x, z)
        P('trap_crusher_stamper', look, x, z, setup=s_stamper(t))
    return f


def e_conveyor(look, x, z):
    for k in (-1, 0, 1):
        floor(look, x, z + k)
        P('trap_conveyor', look, x, z + k, setup=s_conveyor(k == -1, k == 1))


def e_flame(on):
    def f(look, x, z):
        wall_unit(look, 'trap_flame', x, z, 'trap_flame_lane', 2, s_flame(on, 2))
    return f


def e_dart(t, firing=False, enabled=True):
    def f(look, x, z):
        wall_unit(look, 'trap_dart', x, z, 'trap_dart_lane', 2, s_dart(t, firing, enabled))
        if firing:
            P('trap_dart_bolt', look, x, z + 0.7, y=TR.DART_Y)
    return f


def e_bumper(t):
    def f(look, x, z):
        floor(look, x, z)
        P('trap_bumper', look, x, z, setup=s_bumper(t))
    return f


def e_sensor(look, x, z):
    for k in (-1, 0, 1):
        floor(look, x, z + k)
    P('trap_sensor', look, x, z - 1.2, setup=s_sensor(2.4))
    P('trap_sensor', look, x, z + 1.2, rot=2, setup=s_sensor(None))


def e_relay(look, x, z):
    floor(look, x, z)
    P('trap_relay', look, x, z, setup=s_relay(5))


def e_magnet(look, x, z):
    for dx in (-1, 0, 1):
        for dz in (-1, 0, 1):
            floor(look, x + dx, z + dz)
    P('trap_magnet', look, x, z, setup=s_magnet(1.3))


SHEET = [('spikes (down)', e_spikes(0)), ('spikes (warn 1)', e_spikes(0.12)), ('spikes (raised)', e_spikes(1)),
         ('crusher (home)', e_crusher(0)), ('crusher (extended, 2 cells)', e_crusher(1)), ('stamper (home)', e_stamper(0)),
         ('stamper (down)', e_stamper(1)), ('conveyor (3 cells)', e_conveyor), ('flame (off)', e_flame(False)),
         ('flame (on, reach 2)', e_flame(True)), ('dart (t = 0.5)', e_dart(0.5)), ('dart (firing)', e_dart(0.0, firing=True)),
         ('dart (disabled)', e_dart(0.0, enabled=False)), ('bumper (seated)', e_bumper(0)), ('bumper (fired)', e_bumper(1)),
         ('sensor (pair)', e_sensor), ('relay (armed, t = 0.6)', e_relay), ('magnet (radius 1.3)', e_magnet)]

LIT = {'warn_glow': 2.2, 'heat_glow': 2.4, 'relay_glow': 2.2, 'magnet_glow': 2.2, 'magnet_ring_glow': 1.6}
DIM = {'warn_glow': 0.1, 'heat_glow': 0.1, 'relay_glow': 2.2, 'magnet_glow': 0.12, 'magnet_ring_glow': 0.35}


def contact_sheet(look):
    import structure_scenes as SC
    C.reset_scene()
    SC._cache.clear()
    cols = 6
    col_step, row_step = 3.2, 7.8
    lab = T.TrapMats(look)('stone_light' if look == 'upper' else 'plate_light')
    r2 = 0.7071
    for i, (text, fn) in enumerate(SHEET):
        col, row = i % cols, i // cols
        # Grid along the iso camera's screen axes (Godot): right = (+x, -z), toward the camera = (+x, +z).
        x = round((col * col_step + row * row_step) * r2)
        z = round((-col * col_step + row * row_step) * r2)
        fn(look, x + 0.5, z + 0.5)
        C.label(text, (x + 0.5 + 1.5, -(z + 0.5 + 1.5), 0.0), size=0.25, mat=lab)
    render_scene(look, os.path.join(T.PREVIEW_DIR, f'contact_sheet__{look}.png'), 2600, 1700, LIT, margin=1.05)


def diorama(look, state):
    """A 9 x 7 room with every trap in place: `safe` (all machines at rest, lamps dim) or `live`
    (every machine at the instant it acts)."""
    import structure_scenes as SC
    live = state == 'live'
    C.reset_scene()
    SC._cache.clear()
    w, h = 9, 7
    for r in range(h):
        for c in range(w):
            x, z = c + 0.5, r + 0.5
            n = c * 7 + r * 13
            if r == 0 or c == 0:
                if (c, r) != (2, 0):
                    P('wall', look, x, z, rot=n % 4)
                    if (c + r) % 3 == 1 and (c, r) not in ((7, 0), (0, 4), (5, 0)):
                        P('wall_top_a' if n % 2 else 'wall_top_b', look, x, z, y=1.6, rot=0 if r == 0 else 3)
            else:
                floor(look, x, z, n)
            if r == h - 1 or c == w - 1 or r == 0 or c == 0:
                P('cliff_skirt', look, x, z, rot=(c + 2 * r) % 4)
    t = 1.0 if live else 0.0
    # Crusher out of the back wall (dir s, two cells) and an overhead stamper in the corner.
    P('trap_crusher', look, 2.5, 0.5, setup=s_crusher(2, t))
    for r in (1, 2):
        P('trap_crusher_lane', look, 2.5, r + 0.5)
    P('trap_crusher_stamper', look, 1.5, 3.5, setup=s_stamper(t))
    # Flame jet from the back wall (dir s, range 3).
    P('trap_flame', look, 5.5, 0.5, setup=s_flame(live, 3))
    for r in (1, 2, 3):
        P('trap_flame_lane', look, 5.5, r + 0.5)
    # A 2 x 2 spike bed.
    for c, r in ((7, 1), (8, 1), (7, 2), (8, 2)):
        P('trap_spikes', look, c + 0.5, r + 0.5, setup=s_spikes(t))
    # Dart launcher in the left wall (dir e), its lane across the room.
    P('trap_dart', look, 0.5, 4.5, rot=1, setup=s_dart(0.0 if live else 0.5, firing=live))
    for c in range(1, 6):
        P('trap_dart_lane', look, c + 0.5, 4.5, rot=1)
    if live:
        P('trap_dart_bolt', look, 1.75, 4.5, y=TR.DART_Y, rot=1)
        P('trap_dart_bolt', look, 5.2, 4.5, y=TR.DART_Y, rot=1)
    # Bumper aimed at the spikes (dir n).
    P('trap_bumper', look, 7.5, 4.5, rot=2, setup=s_bumper(t))
    # Magnet.
    P('trap_magnet', look, 3.5, 2.5, setup=s_magnet(0.9))
    # Conveyor along the front (dir e, four cells).
    for c in range(1, 5):
        P('trap_conveyor', look, c + 0.5, 6.5, rot=1, setup=s_conveyor(c == 1, c == 4))
    # Beam sensor across the front right, and the relay it feeds on the wall top.
    P('trap_sensor', look, 5.7, 6.5, rot=1, setup=s_sensor(3.1))
    P('trap_sensor', look, 8.9, 6.5, rot=3, setup=s_sensor(None))
    P('trap_relay', look, 7.5, 0.5, y=1.6, setup=s_relay(8 if live else 4))
    name = f'diorama__{look}_{state}'
    render_scene(look, os.path.join(T.PREVIEW_DIR, name + '.png'), 1600, 1200, LIT if live else DIM,
                 small=(os.path.join(T.PREVIEW_DIR, name + '_small.png'), 640, 480))


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    args = parse_args(argv)
    if args['pieces'] != ['none']:
        build_all(args)
    for look in args['looks']:
        if args['sheet']:
            contact_sheet(look)
        if args['diorama']:
            diorama(look, 'safe')
            diorama(look, 'live')


if __name__ == '__main__':
    main()
