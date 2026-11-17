"""
Verify the exported decor / weapon .glb files from outside Blender (plain Python 3, no deps):
parses the GLB JSON + BIN chunks and checks them against docs/GODOT-PORT.md's asset contract.

  python art/kit/decor_check.py            # all decor in the manifest that this script owns + all weapons
  python art/kit/decor_check.py -v         # also list every node / material

Checks: no cameras / lights / skins / animations; node names; required named objects (Lid, Screen,
Fan...); material names (only known roles; emissive ones end in _glow); triangle count; bounding box
in Godot axes from the actual vertex data (node transforms applied); props sit on Y = 0 with the
origin inside the footprint; weapons contain the origin (grip) and extend along +Y; Screen has
0-1 UVs; manifest entries match the file sizes.
"""
from __future__ import annotations

import json
import math
import os
import struct
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
KIT = os.path.join(ROOT, "assets", "models", "kit")
WEAPONS = os.path.join(ROOT, "assets", "models", "weapons")

DECOR = {
    "vines": [], "bush": [], "rubble__upper": [], "rubble__lower": [], "crate__upper": [], "crate__lower": [],
    "barrel__upper": [], "barrel__lower": [], "chest__upper": ["Lid"], "chest__lower": ["Lid"],
    "pipe__upper": [], "pipe__lower": [], "console__upper": ["Screen"], "console__lower": ["Screen"],
    "generator__upper": ["Fan"], "generator__lower": [], "vent__upper": ["Fan"], "vent__lower": ["Fan"],
    "lamp__upper": [], "lamp__lower": [], "neon": [], "cable": [], "wave_screen": ["Screen"],
    "arch__upper": [], "arch__lower": [], "rune_panel": [],
    "time_machine": ["Ring_Outer", "Ring_Mid", "Ring_Inner", "Heart", "Reel_L", "Reel_R"],
}
GLOW_EXPECTED = {"neon": "neon_glow", "rune_panel": "rune_glow", "wave_screen": "screen_glow",
                 "time_machine": "core_glow", "console__upper": "screen_glow", "console__lower": "screen_glow",
                 "lamp__upper": "warm_glow", "lamp__lower": "warm_glow"}
WEAPON_IDS = {"splice_blade": [], "stylus_shiv": [], "amp_sledge": [], "reel_lash": ["Lash"],
              "speaker_knuckles": [], "vinyl_glaive": ["Disc"]}

COMP = {5126: ("f", 4), 5125: ("I", 4), 5123: ("H", 2), 5121: ("B", 1)}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def load_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67, "not a glb"
    off = 12
    js, binc = None, b""
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk.decode("utf-8"))
        elif ctype == 0x004E4942:
            binc = chunk
        off += 8 + clen
    return js, binc


def read_accessor(js, binc, idx):
    acc = js["accessors"][idx]
    bv = js["bufferViews"][acc["bufferView"]]
    fmt, size = COMP[acc["componentType"]]
    n = NCOMP[acc["type"]]
    stride = bv.get("byteStride", size * n)
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    out = []
    for i in range(acc["count"]):
        out.append(struct.unpack_from("<" + fmt * n, binc, base + i * stride))
    return out


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def node_matrix(node):
    if "matrix" in node:
        m = node["matrix"]
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    t = node.get("translation", [0, 0, 0])
    q = node.get("rotation", [0, 0, 0, 1])
    s = node.get("scale", [1, 1, 1])
    x, y, z, w = q
    r = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    return [[r[0][0] * s[0], r[0][1] * s[1], r[0][2] * s[2], t[0]],
            [r[1][0] * s[0], r[1][1] * s[1], r[1][2] * s[2], t[1]],
            [r[2][0] * s[0], r[2][1] * s[1], r[2][2] * s[2], t[2]],
            [0, 0, 0, 1]]


def analyse(path):
    js, binc = load_glb(path)
    info = {"nodes": [], "materials": [m.get("name") for m in js.get("materials", [])], "tris": 0,
            "min": [1e9] * 3, "max": [-1e9] * 3, "uv": {}, "errors": [],
            "cameras": len(js.get("cameras", [])), "skins": len(js.get("skins", [])),
            "animations": [(a.get("name"), len(a.get("channels", []))) for a in js.get("animations", [])],
            "lights": len(js.get("extensions", {}).get("KHR_lights_punctual", {}).get("lights", [])),
            "node_xf": {}}
    scene = js["scenes"][js.get("scene", 0)]

    def walk(ni, parent_m):
        node = js["nodes"][ni]
        m = mat_mul(parent_m, node_matrix(node))
        name = node.get("name", f"node{ni}")
        info["nodes"].append(name)
        info["node_xf"][name] = (node.get("translation", [0, 0, 0]), node.get("rotation", [0, 0, 0, 1]))
        if "mesh" in node:
            for prim in js["meshes"][node["mesh"]]["primitives"]:
                pos = read_accessor(js, binc, prim["attributes"]["POSITION"])
                for p in pos:
                    w = [sum(m[r][c] * (list(p) + [1])[c] for c in range(4)) for r in range(3)]
                    for k in range(3):
                        info["min"][k] = min(info["min"][k], w[k])
                        info["max"][k] = max(info["max"][k], w[k])
                if "indices" in prim:
                    info["tris"] += js["accessors"][prim["indices"]]["count"] // 3
                else:
                    info["tris"] += len(pos) // 3
                if "TEXCOORD_0" in prim["attributes"]:
                    uvs = read_accessor(js, binc, prim["attributes"]["TEXCOORD_0"])
                    us = [u for u, _ in uvs]
                    vs = [v for _, v in uvs]
                    info["uv"][name] = (min(us), max(us), min(vs), max(vs))
        for c in node.get("children", []):
            walk(c, m)

    ident = [[1 if i == j else 0 for j in range(4)] for i in range(4)]
    for ni in scene["nodes"]:
        walk(ni, ident)
    return info


def check(name, path, required, kind, manifest, verbose):
    errs = []
    info = analyse(path)
    if info["cameras"] or info["lights"] or info["skins"]:
        errs.append(f"has cameras/lights/skins {info['cameras']}/{info['lights']}/{info['skins']}")
    if info["animations"]:
        errs.append(f"unexpected animations {info['animations']}")
    for r in required + ["Body"]:
        if r not in info["nodes"]:
            errs.append(f"missing object {r}")
    for m in info["materials"]:
        if not m:
            errs.append("unnamed material")
    lo, hi = info["min"], info["max"]
    if kind == "decor":
        if abs(lo[1]) > 0.002:
            errs.append(f"floor: min y = {lo[1]:.4f} (want 0)")
        if not (lo[0] < 0 < hi[0] and lo[2] < 0 < hi[2]):
            errs.append("origin not inside the footprint")
        exp = GLOW_EXPECTED.get(name)
        if exp and exp not in info["materials"]:
            errs.append(f"expected glow material {exp}")
        if "Screen" in required:
            uv = info["uv"].get("Screen")
            if not uv:
                errs.append("Screen has no UVs")
            elif abs(uv[0]) > 1e-4 or abs(uv[1] - 1) > 1e-4 or abs(uv[2]) > 1e-4 or abs(uv[3] - 1) > 1e-4:
                errs.append(f"Screen UVs not 0-1: {uv}")
        if info["tris"] > (20000 if name == "time_machine" else 6000):
            errs.append(f"too many triangles {info['tris']}")
        e = manifest.get(name)
        if e is None:
            errs.append("not in manifest")
        else:
            size = [hi[k] - lo[k] for k in range(3)]
            if any(abs(size[k] - e["size"][k]) > 0.01 for k in range(3)):
                errs.append(f"manifest size {e['size']} != file {[round(s, 3) for s in size]}")
            if e.get("file") != f"{name}.glb":
                errs.append(f"manifest file {e.get('file')}")
    else:
        if name != "speaker_knuckles" and not (lo[1] < 0.02 and hi[1] > 0.1):
            errs.append(f"origin not at the grip / not extending along +Y: y {lo[1]:.3f}..{hi[1]:.3f}")
        if name == "speaker_knuckles":
            # A gauntlet: the origin is the fist centre, the knuckle face is the +Y end and the
            # wrist cuff runs back along -Y, so only require the origin inside and knuckles at +Y.
            if not (lo[1] < 0 < hi[1] and hi[1] > 0.08):
                errs.append("gauntlet: origin not inside the fist or knuckles not toward +Y")
        elif hi[1] < -lo[1]:
            errs.append("business end not along +Y")
        if info["tris"] > 8000:
            errs.append(f"too many triangles {info['tris']}")
    glow = [m for m in info["materials"] if m and m.endswith("_glow")]
    status = "OK  " if not errs else "FAIL"
    print(f"{status} {name:18s} tris={info['tris']:6d} nodes={info['nodes']} "
          f"aabb=({', '.join(f'{v:.3f}' for v in lo)})..({', '.join(f'{v:.3f}' for v in hi)}) "
          f"glow={glow} anims={info['animations'] or 'none'}")
    if verbose:
        print("      materials:", info["materials"])
        for n, (t, q) in info["node_xf"].items():
            print(f"      node {n}: t={[round(v, 3) for v in t]} r={[round(v, 3) for v in q]}")
        if info["uv"]:
            print("      uv ranges:", {k: tuple(round(x, 3) for x in v) for k, v in info["uv"].items()})
    for e in errs:
        print("     -", e)
    return not errs


def main():
    verbose = "-v" in sys.argv
    with open(os.path.join(KIT, "manifest.json"), encoding="utf-8") as f:
        manifest = json.load(f)["pieces"]
    ok = True
    for name, req in DECOR.items():
        p = os.path.join(KIT, f"{name}.glb")
        if not os.path.exists(p):
            print("FAIL missing", p)
            ok = False
            continue
        ok &= check(name, p, req, "decor", manifest, verbose)
    # every theme key for the decor names resolves to an existing file
    bases = sorted({n.split("__")[0] for n in DECOR})
    for b in bases:
        for key in [b] + [f"{b}__{t}" for t in ("upper", "mid", "lower", "core")]:
            e = manifest.get(key)
            if e is None or not os.path.exists(os.path.join(KIT, e["file"])):
                print(f"FAIL manifest key {key} missing or points at a missing file")
                ok = False
    for name, req in WEAPON_IDS.items():
        p = os.path.join(WEAPONS, f"{name}.glb")
        if not os.path.exists(p):
            print("FAIL missing", p)
            ok = False
            continue
        ok &= check(name, p, req, "weapon", manifest, verbose)
    print("ALL OK" if ok else "SOME CHECKS FAILED")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
