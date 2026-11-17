"""Verify the exported trap .glb files from OUTSIDE Blender (plain Python, no bpy): reads each
file's glTF JSON + binary chunk and checks it against the "Traps" contract in docs/GODOT-PORT.md.

  python art/traps/check_traps.py [--verbose]

Per file: node names with their pivot (translation) and scale, materials, triangle count, bounds in
Godot axes. Checks: required objects present and nothing else, pivots and rest scales as documented,
no skins / animations / cameras / lights / textures, every emissive-role material ends in `_glow`,
triangle budget, tile footprints, the conveyor belt's UV convention, and the manifest entries.
Exit code 1 on any failure.
"""
from __future__ import annotations

import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.abspath(os.path.join(HERE, '..', '..', 'assets', 'models', 'kit'))
LOOKS = ['upper', 'lower']
TRI_BUDGET = 6000
PIPS = [f'Pip_{i:02d}' for i in range(1, 9)]
TICKS = [f'Tick_{i:02d}' for i in range(1, 9)]

# piece -> {object: (pivot xyz or None, scale xyz or None)} in Godot axes, as documented.
SPEC = {
    'trap_spikes': {'Base': ((0, 0, 0), None), 'Spikes': ((0, -0.02, 0), (1, 0.02, 1))},
    'trap_crusher': {'Housing': ((0, 0, 0), None), 'Head': ((0, 0, 0.53), None), 'Ram': ((0, 0, 0.05), (1, 1, 0.18))},
    'trap_crusher_lane': {'Lane': ((0, 0, 0), None)},
    'trap_crusher_stamper': {'Frame': ((0, 0, 0), None), 'Head': ((0, 1.3, 0), None), 'Ram': ((0, 2.1, 0), (1, 0.05, 1))},
    'trap_conveyor': {'Frame': ((0, 0, 0), None), 'Belt': ((0, 0, 0), None), 'Arrows': ((0, 0, 0), None),
                      'End_Back': ((0, 0, 0), None), 'End_Front': ((0, 0, 0), None),
                      'Roller_Back': ((0, 0.035, -0.435), None), 'Roller_Front': ((0, 0.035, 0.435), None)},
    'trap_flame': {'Body': ((0, 0, 0), None), 'Nozzle': ((0, 0.26, 0.66), None), 'Pilot': ((0, 0.142, 0.8), None),
                   'Jet': ((0, 0.26, 0.845), None)},
    'trap_flame_lane': {'Lane': ((0, 0, 0), None)},
    'trap_dart': dict({'Body': ((0, 0, 0), None), 'Muzzle': ((0, 0.3, 0.66), None), 'Shutter': ((0, 0.396, 0.7345), None),
                       'Flash': ((0, 0.3, 0.745), None)}, **{p: (None, None) for p in PIPS}),
    'trap_dart_lane': {'Lane': ((0, 0, 0), None)},
    'trap_dart_bolt': {'Dart': ((0, 0, 0), None)},
    'trap_bumper': {'Base': ((0, 0, 0), None), 'Pad': ((0, 0, 0), None), 'Spring': ((0, -0.02, 0), (1, 0.04, 1))},
    'trap_sensor': {'Post': ((0, 0, 0), None), 'Lens': ((0, 0.32, 0.068), None), 'Beam': ((0, 0.32, 0.08), None)},
    'trap_relay': dict({'Body': ((0, 0, 0), None), 'Lamp': ((0, 0.19, 0), None)}, **{t: (None, None) for t in TICKS}),
    'trap_magnet': {'Base': ((0, 0, 0), None), 'Coil': ((0, 0.05, 0), None), 'Ring': ((0, 0, 0), None)},
}
LOOKLESS = ['trap_dart_bolt']
# Floor overlays must stay inside their tile and close to the floor: (max |x|, max |z|, min y, max y).
OVERLAY = {'trap_spikes': (0.5, 0.5, -0.05, 0.05), 'trap_crusher_lane': (0.5, 0.5, -0.05, 0.05),
           'trap_flame_lane': (0.5, 0.5, -0.01, 0.03), 'trap_dart_lane': (0.5, 0.5, -0.01, 0.03),
           'trap_conveyor': (0.5, 0.5, -0.05, 0.12), 'trap_bumper': (0.5, 0.5, -0.05, 0.12)}
# Materials that are allowed to exist; anything else is a typo. Glow roles must end in _glow.
GLOW = {'warn_glow', 'heat_glow', 'pilot_glow', 'flame_glow', 'flame_core_glow', 'pip_glow', 'muzzle_glow', 'dart_glow',
        'sensor_glow', 'beam_glow', 'relay_glow', 'magnet_glow', 'magnet_ring_glow', 'run_glow', 'accent_glow',
        'neon_cyan_glow', 'rune_glow'}
PLAIN = {'stone', 'stone_light', 'stone_dark', 'metal', 'metal_dark', 'paint_yellow', 'hazard_dark', 'rust', 'moss', 'grass',
         'void', 'plate', 'plate_light', 'plate_dark', 'trim', 'steel', 'soot', 'belt', 'belt_arrow', 'magnet_body'}


def read_glb(path):
    with open(path, 'rb') as f:
        data = f.read()
    magic, _version, length = struct.unpack_from('<III', data, 0)
    assert magic == 0x46546C67, 'not a glb'
    off, js, binc = 12, None, b''
    while off < length:
        clen, ctype = struct.unpack_from('<II', data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk.decode('utf-8'))
        elif ctype == 0x004E4942:
            binc = chunk
        off += 8 + clen
    return js, binc


def accessor(js, binc, idx):
    acc = js['accessors'][idx]
    bv = js['bufferViews'][acc['bufferView']]
    n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[acc['type']]
    fmt = {5126: 'f', 5123: 'H', 5125: 'I', 5121: 'B'}[acc['componentType']]
    size = struct.calcsize(fmt) * n
    stride = bv.get('byteStride', size)
    base = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
    return [struct.unpack_from('<' + fmt * n, binc, base + i * stride) for i in range(acc['count'])]


def close(a, b, eps=2e-3):
    return all(abs(x - y) <= eps for x, y in zip(a, b))


def check_file(name, piece, verbose):
    path = os.path.join(KIT, name + '.glb')
    fails = []
    if not os.path.exists(path):
        return [f'{name}: file missing'], None
    js, binc = read_glb(path)
    for key in ('skins', 'animations', 'cameras', 'images', 'textures'):
        if js.get(key):
            fails.append(f'{name}: unexpected {key}')
    if 'KHR_lights_punctual' in js.get('extensionsUsed', []):
        fails.append(f'{name}: lights exported')
    nodes = {n['name']: n for n in js['nodes']}
    spec = SPEC[piece]
    if sorted(nodes) != sorted(spec):
        fails.append(f'{name}: objects {sorted(nodes)} != {sorted(spec)}')
    if any('children' in n for n in js['nodes']):
        fails.append(f'{name}: hierarchy is not flat')
    mats = [m['name'] for m in js.get('materials', [])]
    for mn in mats:
        if mn not in GLOW and mn not in PLAIN:
            fails.append(f'{name}: unknown material {mn}')
    for m in js.get('materials', []):
        if m.get('emissiveFactor') or m.get('pbrMetallicRoughness', {}).get('baseColorTexture'):
            fails.append(f'{name}: material {m["name"]} is not base-colour only')
    tris = 0
    lo, hi = [1e9] * 3, [-1e9] * 3
    rows = []
    for nm, node in sorted(nodes.items()):
        t = node.get('translation', [0, 0, 0])
        s = node.get('scale', [1, 1, 1])
        if node.get('rotation', [0, 0, 0, 1]) not in ([0, 0, 0, 1], [0.0, 0.0, 0.0, 1.0]):
            fails.append(f'{name}/{nm}: has a rest rotation {node["rotation"]}')
        want = spec.get(nm)
        if want:
            if want[0] is not None and not close(t, want[0]):
                fails.append(f'{name}/{nm}: pivot {t} != {want[0]}')
            if not close(s, want[1] or (1, 1, 1)):
                fails.append(f'{name}/{nm}: scale {s} != {want[1] or (1, 1, 1)}')
        mesh = js['meshes'][node['mesh']]
        ntri = 0
        nmat = set()
        nlo, nhi = [1e9] * 3, [-1e9] * 3
        for prim in mesh['primitives']:
            ntri += js['accessors'][prim['indices']]['count'] // 3
            nmat.add(js['materials'][prim['material']]['name'])
            acc = js['accessors'][prim['attributes']['POSITION']]
            for i in range(3):
                nlo[i] = min(nlo[i], acc['min'][i] * s[i] + t[i])
                nhi[i] = max(nhi[i], acc['max'][i] * s[i] + t[i])
            if 'TEXCOORD_0' not in prim['attributes'] or 'NORMAL' not in prim['attributes']:
                fails.append(f'{name}/{nm}: primitive without UVs or normals')
        tris += ntri
        for i in range(3):
            lo[i], hi[i] = min(lo[i], nlo[i]), max(hi[i], nhi[i])
        rows.append((nm, t, s, ntri, sorted(nmat), nlo, nhi))
    if tris > TRI_BUDGET:
        fails.append(f'{name}: {tris} triangles > {TRI_BUDGET}')
    if piece in OVERLAY:
        mx, mz, y0, y1 = OVERLAY[piece]
        # Parts in the rest pose only; the ring / jet style helpers are not overlays.
        if max(-lo[0], hi[0]) > mx + 1e-3 or max(-lo[2], hi[2]) > mz + 1e-3 or lo[1] < y0 - 1e-3 or hi[1] > y1 + 1e-3:
            fails.append(f'{name}: overlay leaves its tile: {lo} .. {hi}')
    if piece == 'trap_conveyor':
        fails += check_belt(name, js, binc, nodes)
    r3 = lambda v: [round(x, 3) for x in v]
    print(f'{name}.glb  {tris} tris  bounds {r3(lo)} .. {r3(hi)}  {len(mats)} materials')
    if verbose:
        for nm, t, s, ntri, nmat, nlo, nhi in rows:
            print(f'    {nm:13s} pivot {r3(t)} scale {r3(s)}  {ntri:5d} tris  {r3(nlo)} .. {r3(nhi)}  {", ".join(nmat)}')
    return fails, {'tris': tris, 'lo': lo, 'hi': hi}


def check_belt(name, js, binc, nodes):
    """Belt and Arrows: glTF V must equal z + 0.5 (0 upstream, 1 downstream), U = across, 0..1."""
    fails = []
    for nm in ('Belt', 'Arrows'):
        node = nodes.get(nm)
        if node is None:
            continue
        for prim in js['meshes'][node['mesh']]['primitives']:
            pos = accessor(js, binc, prim['attributes']['POSITION'])
            uv = accessor(js, binc, prim['attributes']['TEXCOORD_0'])
            bad = [(p, t) for p, t in zip(pos, uv) if abs(t[1] - (p[2] + 0.5)) > 1e-4 or abs(t[0] - (p[0] + 0.392) / 0.784) > 1e-4]
            if bad:
                fails.append(f'{name}/{nm}: {len(bad)} vertices off the travel UV convention, e.g. pos {bad[0][0]} uv {bad[0][1]}')
            vs = [t[1] for t in uv]
            if nm == 'Belt' and (abs(min(vs)) > 1e-4 or abs(max(vs) - 1) > 1e-4 or min(t[0] for t in uv) < -1e-4 or max(t[0] for t in uv) > 1 + 1e-4):
                fails.append(f'{name}/Belt: UV range is not 0..1')
    return fails


def main():
    verbose = '--verbose' in sys.argv
    fails = []
    files = []
    for piece in SPEC:
        files += [(piece, piece)] if piece in LOOKLESS else [(f'{piece}__{look}', piece) for look in LOOKS]
    total = 0
    for name, piece in files:
        f, info = check_file(name, piece, verbose)
        fails += f
        total += info['tris'] if info else 0
    with open(os.path.join(KIT, 'manifest.json'), 'r', encoding='utf-8') as f:
        pieces = json.load(f)['pieces']
    for name, piece in files:
        keys = [name] if piece in LOOKLESS else [name]
        if piece not in LOOKLESS:
            keys += [piece, f'{piece}__mid', f'{piece}__core']
        for k in keys:
            e = pieces.get(k)
            if e is None:
                fails.append(f'manifest: missing {k}')
            elif not os.path.exists(os.path.join(KIT, e['file'])):
                fails.append(f'manifest: {k} -> missing file {e["file"]}')
            elif sorted(e.get('objects', [])) != sorted(SPEC[piece]):
                fails.append(f'manifest: {k} objects do not match the file')
    others = [k for k in pieces if not k.startswith('trap_')]
    stray = [f for f in os.listdir(KIT) if f.startswith('trap_') and f.endswith('.glb') and f[:-4] not in [n for n, _ in files]]
    if stray:
        fails.append(f'stray trap files: {stray}')
    print(f'{len(files)} files, {total} triangles in all; manifest: {sum(1 for k in pieces if k.startswith("trap_"))} trap keys, '
          f'{len(others)} other keys untouched')
    for f in fails:
        print('FAIL', f)
    print('RESULT', 'FAIL' if fails else 'OK')
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
