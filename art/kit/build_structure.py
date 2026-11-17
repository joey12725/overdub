"""Build the structural environment kit and the mechanisms, export .glb files, update the manifest
and render previews.

  blender --background --python art/kit/build_structure.py -- [options]

Options:
  --pieces a,b,...   only these pieces (default: all floors, structure and mechanisms)
  --looks upper,lower
  --no-export        build and render only
  --views iso,front  per-piece preview views (default: iso,front,side,back,three_quarter + thumb)
  --no-previews      skip per-piece previews
  --sheet            render the contact sheet per look (from the exported .glb files)
  --diorama          render the assembled test dioramas (from the exported .glb files)

Outputs: assets/models/kit/<piece>__<look>.glb, assets/models/kit/manifest.json (merged: only our
keys are touched), art/previews/kit/<piece>__<look>_<view>.png, contact sheets and dioramas.
"""
from __future__ import annotations

import importlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import common as C  # noqa: E402

MODULES = ('floors', 'structure', 'mechanisms')


def load_modules():
    mods = {}
    for name in MODULES:
        try:
            mod = importlib.import_module(name)
        except ModuleNotFoundError as e:
            if e.name == name:
                continue
            raise
        mods[name] = mod
    return mods


def piece_table(mods):
    table = {}
    for mod in mods.values():
        for p in mod.PIECES if hasattr(mod, 'PIECES') else mod.FLOOR_PIECES:
            table[p] = mod
    return table


def parse_args(argv):
    args = {'pieces': None, 'looks': list(C.LOOKS), 'export': True, 'views': ['iso', 'front', 'side', 'back', 'three_quarter'],
            'previews': True, 'sheet': False, 'diorama': False}
    it = iter(argv)
    for a in it:
        if a == '--pieces':
            args['pieces'] = next(it).split(',')
        elif a == '--looks':
            args['looks'] = next(it).split(',')
        elif a == '--no-export':
            args['export'] = False
        elif a == '--views':
            args['views'] = next(it).split(',')
        elif a == '--no-previews':
            args['previews'] = False
        elif a == '--sheet':
            args['sheet'] = True
        elif a == '--diorama':
            args['diorama'] = True
    return args


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    args = parse_args(argv)
    mods = load_modules()
    table = piece_table(mods)
    pieces = args['pieces'] or list(table)
    manifest = {}
    for piece in pieces:
        if piece not in table:
            if piece in ('sheet', 'diorama'):
                continue
            raise SystemExit(f'unknown piece {piece}')
        mod = table[piece]
        for look in args['looks']:
            C.reset_scene()
            objs = mod.build(piece, look)
            key = f'{piece}__{look}'
            print(f'[kit] built {key}: ' + ', '.join(f'{o.name}({len(o.data.polygons)}f)' for o in objs))
            if args['export']:
                path = os.path.join(C.KIT_DIR, key + '.glb')
                anim = getattr(mod, 'has_animation', lambda p: False)(piece)
                C.export_glb(objs, path, animations=anim)
                entry = {
                    'file': key + '.glb',
                    'themes': C.LOOK_THEMES[look],
                    'size': C.godot_aabb(objs)['size'],
                    'aabb': {k: v for k, v in C.godot_aabb(objs).items() if k != 'size'},
                }
                extra = getattr(mod, 'manifest_extra', lambda p, l: {})(piece, look)
                entry.update(extra)
                manifest[key] = entry
                # Fallbacks the game looks up by name: <name> and the themes this look also serves.
                if look == 'upper':
                    manifest[piece] = dict(entry)
                for theme in C.LOOK_THEMES[look]:
                    if theme != look:
                        manifest[f'{piece}__{theme}'] = dict(entry)
            if args['previews']:
                C.setup_render(look, 640, 640)
                for view in args['views']:
                    C.render_view(objs, os.path.join(C.PREVIEW_DIR, 'pieces', f'{key}_{view}.png'), view)
                C.setup_render(look, 160, 160)
                C.render_view(objs, os.path.join(C.PREVIEW_DIR, 'pieces', f'{key}_thumb160.png'), 'iso', margin=1.02)
                extra_previews = getattr(mod, 'extra_previews', None)
                if extra_previews:
                    extra_previews(piece, look, objs)
    if manifest:
        C.update_manifest(manifest)
        print(f'[kit] manifest: {len(manifest)} entries merged')
    if args['sheet'] or args['diorama']:
        import structure_scenes as scenes
        importlib.reload(scenes)
        for look in args['looks']:
            if args['sheet']:
                scenes.contact_sheet(look, [p for p in pieces if p in table] or None)
            if args['diorama']:
                scenes.diorama(look)


if __name__ == '__main__':
    main()
