"""Verify an exported enemy .glb from outside Blender (system Python, reads the glTF JSON + BIN).

    python art/enemies/common2_check.py assets/models/enemies/turret.glb [--expect-height 1.1]
           [--require-bones aim,...] [--require-meshes Armor_1,...]

Prints nodes, mesh objects, bones, materials (glow flagged), animations with lengths and channel
counts, triangle count and the rest-pose bounding box (Godot axes: Y up, model faces +Z), then
checks the docs/GODOT-PORT.md enemy contract. Exit code 1 on any contract failure.
"""
from __future__ import annotations

import json
import struct
import sys

COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
FMT = {5126: "f", 5125: "I", 5123: "H", 5121: "B", 5122: "h", 5120: "b"}
ACTIONS = {"idle": None, "move": None, "telegraph": 1.0, "attack": 1.0, "stagger": 1.0, "death": 1.0}
LOOPS = ("idle", "move")
# Bones that spin continuously; a loop may end them rotated by a symmetry step of the part.
SPIN_BONES = {"reel", "halo", "hammer"}


def load(path: str):
    data = open(path, "rb").read()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF" and version == 2, "not a glb v2"
    off = 12
    js, bin_ = None, b""
    while off < length:
        clen, ctype = struct.unpack_from("<I4s", data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == b"JSON":
            js = json.loads(chunk)
        elif ctype == b"BIN\0":
            bin_ = chunk
        off += 8 + clen
    return js, bin_


def read_accessor(js, bin_, i):
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    n = COMPONENTS[a["type"]]
    fmt = FMT[a["componentType"]]
    size = struct.calcsize(fmt)
    stride = bv.get("byteStride", size * n)
    base = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    out = []
    for k in range(a["count"]):
        out.append(struct.unpack_from("<" + fmt * n, bin_, base + k * stride))
    return out


def main() -> int:
    path = sys.argv[1]
    expect_h = None
    req_bones: list[str] = []
    req_meshes: list[str] = []
    args = sys.argv[2:]
    for i, a in enumerate(args):
        if a == "--expect-height":
            expect_h = float(args[i + 1])
        elif a == "--require-bones":
            req_bones = [b for b in args[i + 1].split(",") if b]
        elif a == "--require-meshes":
            req_meshes = [b for b in args[i + 1].split(",") if b]
    js, bin_ = load(path)
    fails: list[str] = []
    nodes = js["nodes"]
    names = [n.get("name", "?") for n in nodes]
    print(f"== {path}")
    print("nodes:", len(nodes))
    mesh_nodes = [n for n in nodes if "mesh" in n]
    print("mesh objects:", [n["name"] for n in mesh_nodes])
    skins = js.get("skins", [])
    bones = [nodes[j]["name"] for j in skins[0]["joints"]] if skins else []
    print(f"bones ({len(bones)}):", bones)
    rig = [n for n in nodes if n.get("name") == "Rig"]
    if not rig:
        fails.append("no node named Rig")
    for b in ["root", *req_bones]:
        if b not in bones:
            fails.append(f"missing bone {b}")
    for m in req_meshes:
        if m not in [n["name"] for n in mesh_nodes]:
            fails.append(f"missing mesh object {m}")
    for n in mesh_nodes:
        if "skin" not in n:
            fails.append(f"mesh {n['name']} is not skinned")
    mats = js.get("materials", [])
    print("materials:")
    for m in mats:
        em = m.get("emissiveFactor", [0, 0, 0])
        glow = any(c > 0 for c in em)
        bc = m.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])
        print(f"   {m['name']:<14} base {tuple(round(c, 3) for c in bc[:3])} {'EMISSIVE' if glow else ''}")
        if m["name"].endswith("_glow") != glow:
            fails.append(f"material {m['name']}: emissive={glow} does not match its name")
    tris = 0
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for mesh in js["meshes"]:
        for p in mesh["primitives"]:
            if "indices" in p:
                tris += js["accessors"][p["indices"]]["count"] // 3
            else:
                tris += js["accessors"][p["attributes"]["POSITION"]]["count"] // 3
            a = js["accessors"][p["attributes"]["POSITION"]]
            lo = [min(x, y) for x, y in zip(lo, a["min"])]
            hi = [max(x, y) for x, y in zip(hi, a["max"])]
    print(f"triangles: {tris}")
    print(f"bounds (Godot axes, bind pose): min {tuple(round(x, 3) for x in lo)} max {tuple(round(x, 3) for x in hi)}")
    print(f"   height {hi[1] - lo[1]:.3f}, width X {hi[0] - lo[0]:.3f}, depth Z {hi[2] - lo[2]:.3f}")
    if tris > 25000:
        fails.append(f"{tris} triangles > 25k budget")
    if abs(lo[1]) > 0.01:
        fails.append(f"origin not on the floor: min Y = {lo[1]:.3f}")
    if expect_h is not None and abs((hi[1] - lo[1]) - expect_h) > 0.12 * expect_h:
        fails.append(f"height {hi[1] - lo[1]:.3f} far from expected {expect_h}")
    # Facing: the eye material must sit on the +Z side.
    for mesh in js["meshes"]:
        for p in mesh["primitives"]:
            if mats and mats[p.get("material", 0)]["name"] == "eye_glow":
                a = js["accessors"][p["attributes"]["POSITION"]]
                cz = (a["min"][2] + a["max"][2]) / 2
                print(f"eye_glow centre Z = {cz:.3f} ({'front +Z ok' if cz > 0 else 'WRONG: behind'})")
                if cz <= 0:
                    fails.append("eye is not on the +Z (front) side")
    anims = js.get("animations", [])
    print("animations:")
    seen = {}
    for an in anims:
        tmax = 0.0
        tmin = 1e9
        targets = set()
        for ch in an["channels"]:
            s = an["samplers"][ch["sampler"]]
            acc = js["accessors"][s["input"]]
            tmax = max(tmax, acc["max"][0])
            tmin = min(tmin, acc["min"][0])
            targets.add(nodes[ch["target"]["node"]]["name"])
        seen[an["name"]] = (tmin, tmax, targets)
        print(f"   {an['name']:<10} {tmin:.3f}..{tmax:.3f} s  {len(an['channels'])} channels on {len(targets)} bones")
    for name, length in ACTIONS.items():
        if name not in seen:
            fails.append(f"missing animation {name}")
            continue
        tmin, tmax, targets = seen[name]
        if abs(tmin) > 1e-3:
            fails.append(f"{name} starts at {tmin}")
        if length is not None and abs(tmax - length) > 1e-3:
            fails.append(f"{name} is {tmax:.3f} s, expected {length}")
        if "aim" in targets:
            fails.append(f"{name} keys the game-driven aim bone")
    for name in LOOPS:
        if name in seen:
            an = next(a for a in anims if a["name"] == name)
            worst = 0.0
            for ch in an["channels"]:
                if nodes[ch["target"]["node"]]["name"].split(".")[0] in SPIN_BONES:
                    continue
                s = an["samplers"][ch["sampler"]]
                out = read_accessor(js, bin_, s["output"])
                if ch["target"]["path"] == "rotation":
                    a, b = out[0], out[-1]
                    dot = abs(sum(x * y for x, y in zip(a, b)))
                    worst = max(worst, 1 - dot)
                else:
                    worst = max(worst, max(abs(x - y) for x, y in zip(out[0], out[-1])))
            print(f"   {name}: largest first/last pose difference {worst:.5f} (spin bones excluded: they wrap by the part's symmetry)")
            if worst > 1e-3:
                fails.append(f"{name} does not loop (first/last pose differ by {worst:.4f})")
    extra = sorted(set(seen) - set(ACTIONS))
    if extra:
        print("   extra animations:", extra)
    if fails:
        print("CONTRACT FAILURES:")
        for f in fails:
            print("  -", f)
        return 1
    print("contract OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
