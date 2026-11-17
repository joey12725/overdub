"""Verify the exported structure / mechanism .glb files from OUTSIDE Blender (plain Python, no bpy):
reads each file's glTF JSON + binary chunk and checks it against the asset contract
(docs/GODOT-PORT.md) and the per-piece conventions in floors.py / structure.py / mechanisms.py.

  python art/kit/structure_check.py [--verbose] [piece ...]

Prints, per file: nodes (with parent and translation), materials, animations with their lengths,
triangle count and the Godot-space bounding box (glTF is already Y-up). Exit code 1 on any failure.
"""
from __future__ import annotations

import json
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.abspath(os.path.join(HERE, '..', '..', 'assets', 'models', 'kit'))

FLOORS = ['floor_solid', 'floor_cracked', 'floor_grate', 'floor_overgrown', 'floor_rune']
STRUCT = ['wall', 'wall_top_a', 'wall_top_b', 'wall_cut', 'barrier_low', 'cliff_skirt', 'edge_trim']
MECHS = ['door', 'switch', 'plate', 'breakable', 'breakable_chunks', 'laser_emitter', 'core', 'exit_pad']
LOOKS = ['upper', 'lower']

# Required mesh object names per mechanism (the game finds them by name).
OBJECTS = {
    'door': ['Frame', 'Panel'], 'switch': ['Base', 'Lever'], 'plate': ['Base', 'Pad'],
    'laser_emitter': ['Body', 'Lens'], 'core': ['Shell', 'Heart'],
}
ACTIONS = {'door': 'open', 'switch': 'toggle', 'plate': 'press'}
# Expected Godot-space bounds per piece: (axis, lo, hi) with a tolerance.
EXPECT = {
    'floor': [('x', -0.5, 0.5), ('z', -0.5, 0.5), ('ymax', None, 0.0)],
    'wall': [('x', -0.5, 0.5), ('z', -0.5, 0.5), ('ymin', -0.2, None), ('ymax', 1.6, None)],
    'wall_cut': [('x', -0.5, 0.5), ('z', -0.5, 0.5), ('ymin', -0.2, None), ('ymax', 0.45, None)],
}
TRI_BUDGET = 12000  # "kit pieces far less" than a 25k character


def read_glb(path):
    with open(path, 'rb') as f:
        data = f.read()
    magic, version, length = struct.unpack_from('<III', data, 0)
    assert magic == 0x46546C67, 'not a glb'
    off = 12
    js, binc = None, b''
    while off < length:
        clen, ctype = struct.unpack_from('<II', data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk.decode('utf-8'))
        elif ctype == 0x004E4942:
            binc = chunk
        off += 8 + clen
    return js, binc


def accessor_count(js, idx):
    return js['accessors'][idx]['count']


def node_world(js):
    """World matrices (translation/rotation/scale only, as exported) -> per-node world transform fn."""
    parent = {}
    for i, n in enumerate(js.get('nodes', [])):
        for c in n.get('children', []):
            parent[c] = i

    def local(n):
        t = n.get('translation', [0, 0, 0])
        r = n.get('rotation', [0, 0, 0, 1])
        s = n.get('scale', [1, 1, 1])
        x, y, z, w = r
        R = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
             [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
             [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
        return lambda p: [sum(R[i][k] * p[k] * s[k] for k in range(3)) + t[i] for i in range(3)]

    def world(i):
        fns = []
        j = i
        while j is not None:
            fns.append(local(js['nodes'][j]))
            j = parent.get(j)

        def f(p):
            for fn in fns:
                p = fn(p)
            return p
        return f
    return world, parent


def inspect(path):
    js, binc = read_glb(path)
    world, parent = node_world(js)
    info = {'nodes': [], 'materials': [m.get('name', '?') for m in js.get('materials', [])], 'anims': [],
            'tris': 0, 'lo': [1e9] * 3, 'hi': [-1e9] * 3, 'skins': len(js.get('skins', [])),
            'cameras': len(js.get('cameras', [])),
            'lights': len(js.get('extensions', {}).get('KHR_lights_punctual', {}).get('lights', []))}
    for i, n in enumerate(js.get('nodes', [])):
        info['nodes'].append({'name': n.get('name'), 'parent': js['nodes'][parent[i]]['name'] if i in parent else None,
                              'mesh': 'mesh' in n, 't': [round(v, 3) for v in n.get('translation', [0, 0, 0])]})
        if 'mesh' not in n:
            continue
        f = world(i)
        mesh = js['meshes'][n['mesh']]
        for prim in mesh['primitives']:
            if 'indices' in prim:
                info['tris'] += accessor_count(js, prim['indices']) // 3
            pa = js['accessors'][prim['attributes']['POSITION']]
            lo, hi = pa['min'], pa['max']
            # Transform the 8 corners of the local AABB (exact for translation-only nodes).
            for cx in (lo[0], hi[0]):
                for cy in (lo[1], hi[1]):
                    for cz in (lo[2], hi[2]):
                        p = f([cx, cy, cz])
                        for k in range(3):
                            info['lo'][k] = min(info['lo'][k], p[k])
                            info['hi'][k] = max(info['hi'][k], p[k])
    for a in js.get('animations', []):
        t_max = 0.0
        for s in a['samplers']:
            acc = js['accessors'][s['input']]
            t_max = max(t_max, acc.get('max', [0])[0])
        targets = sorted({(js['nodes'][c['target']['node']]['name'], c['target']['path']) for c in a['channels']})
        info['anims'].append({'name': a.get('name'), 'length': round(t_max, 4), 'targets': targets})
    return info


def check(piece, look, verbose):
    key = f'{piece}__{look}'
    path = os.path.join(KIT, key + '.glb')
    errs = []
    if not os.path.exists(path):
        return [f'{key}: missing file'], None
    info = inspect(path)
    lo, hi = info['lo'], info['hi']
    names = [n['name'] for n in info['nodes']]
    mesh_names = [n['name'] for n in info['nodes'] if n['mesh']]
    if info['cameras'] or info['lights']:
        errs.append(f'{key}: has cameras/lights')
    if info['skins']:
        errs.append(f'{key}: unexpected skin (kit pieces are static)')
    if info['tris'] > TRI_BUDGET:
        errs.append(f'{key}: {info["tris"]} triangles > budget {TRI_BUDGET}')
    if any(m in ('Material', '?') or m.startswith('Material.') for m in info['materials']):
        errs.append(f'{key}: unnamed default material')
    # Slabs/blocks must stay inside the tile; creeper leaves on a wall face may overhang a little
    # (on a face that meets a neighbouring wall they are simply buried in it).
    tol = 0.06 if piece == 'wall' else 0.035
    kind = 'floor' if piece.startswith('floor_') else piece
    for axis, a, b in EXPECT.get(kind, []):
        if axis == 'x' and (lo[0] < a - tol or hi[0] > b + tol):
            errs.append(f'{key}: x extent {lo[0]:.3f}..{hi[0]:.3f} outside the tile')
        if axis == 'z' and (lo[2] < a - tol or hi[2] > b + tol):
            errs.append(f'{key}: z extent {lo[2]:.3f}..{hi[2]:.3f} outside the tile')
        if axis == 'ymax' and b is not None and abs(hi[1] - b) > 0.03 and kind == 'floor':
            # Grass / plants may rise above the walkable top; only slab tops must sit at 0.
            if hi[1] < -0.01:
                errs.append(f'{key}: top {hi[1]:.3f} below the walkable plane')
        if axis == 'ymax' and a is not None and abs(hi[1] - a) > 0.25:
            errs.append(f'{key}: top {hi[1]:.3f}, expected about {a}')
        if axis == 'ymin' and a is not None and abs(lo[1] - a) > 0.02:
            errs.append(f'{key}: bottom {lo[1]:.3f}, expected {a}')
    if kind == 'floor' and abs(lo[1] + 0.2) > 0.02:
        errs.append(f'{key}: floor body bottom {lo[1]:.3f}, expected -0.2')
    for req in OBJECTS.get(piece, []):
        if req not in mesh_names:
            errs.append(f'{key}: missing mesh object {req!r} (has {mesh_names})')
    if piece == 'breakable_chunks':
        chunks = [n for n in mesh_names if n.startswith('Chunk_')]
        if not 8 <= len(chunks) <= 12:
            errs.append(f'{key}: {len(chunks)} chunks (want 8-12)')
    if piece in ACTIONS:
        want = ACTIONS[piece]
        got = {a['name']: a for a in info['anims']}
        if want not in got:
            errs.append(f'{key}: missing action {want!r} (has {list(got)})')
        elif abs(got[want]['length'] - 1.0) > 1e-3:
            errs.append(f'{key}: action {want} is {got[want]["length"]} s, want 1.0')
    glow = [m for m in info['materials'] if m.endswith('_glow')]
    if piece in ('floor_rune', 'door', 'laser_emitter', 'core', 'exit_pad') and not glow:
        errs.append(f'{key}: no *_glow material')
    line = (f'{key:28s} tris={info["tris"]:5d}  y {lo[1]:+.3f}..{hi[1]:+.3f}  x {lo[0]:+.3f}..{hi[0]:+.3f}  '
            f'z {lo[2]:+.3f}..{hi[2]:+.3f}  objects={mesh_names}')
    if info['anims']:
        line += '  actions=' + ', '.join(f'{a["name"]}({a["length"]}s -> {a["targets"]})' for a in info['anims'])
    if verbose:
        line += '\n    materials=' + ', '.join(info['materials'])
        line += '\n    nodes=' + ', '.join(f'{n["name"]}<{n["parent"]}>@{n["t"]}' for n in info['nodes'])
    return errs, line


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    verbose = '--verbose' in sys.argv
    pieces = args or FLOORS + STRUCT + MECHS
    errs_all = []
    for p in pieces:
        for look in LOOKS:
            errs, line = check(p, look, verbose)
            if line:
                print(line)
            for e in errs:
                print('  FAIL ' + e)
            errs_all += errs
    # Manifest: every piece and look present, sizes plausible, decor entries untouched by us.
    with open(os.path.join(KIT, 'manifest.json'), encoding='utf-8') as f:
        man = json.load(f)['pieces']
    for p in pieces:
        for key in (p, f'{p}__upper', f'{p}__lower', f'{p}__mid', f'{p}__core'):
            if key not in man:
                errs_all.append(f'manifest: missing {key}')
                print(f'  FAIL manifest: missing {key}')
            elif not os.path.exists(os.path.join(KIT, man[key]['file'])):
                errs_all.append(f'manifest: {key} -> missing file {man[key]["file"]}')
                print(f'  FAIL manifest: {key} -> missing file')
    print(f'{len(pieces) * len(LOOKS)} files checked, {len(errs_all)} problem(s)')
    sys.exit(1 if errs_all else 0)


if __name__ == '__main__':
    main()
