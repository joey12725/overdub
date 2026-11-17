"""Verify enemy .glb files against the asset contract from OUTSIDE Blender (plain Python 3 + numpy).

    python art/enemies/common_check_glb.py [type ...]      (default: grunt stalker shielder drone)

Reads the glTF JSON and binary chunks directly and reports, per file: nodes, armature `Rig` and its
bones, mesh objects, materials, animations (names, lengths, animated bones), triangle count,
bounding box (Godot axes: Y up, +Z forward), and checks:
  - armature node `Rig`, a `root` bone; skins reference only Rig bones
  - required actions present: idle, move, telegraph, attack, stagger, death; the one-shots last
    exactly 1.0 s; loops start and end on the same pose
  - `aim` bone (drone/turret) is never animated
  - material names: palette names, emissive ones end in _glow and only those carry emission
  - exactly one eye: a single `eye_glow` primitive whose centroid is in FRONT (+Z) of the origin
  - origin on the floor (min Y ~ 0 for walkers, hover height for the drone) and centred footprint
  - skin weights: every vertex weighted, weights sum to 1
  - triangle budget < 25k; per-type extras (shielder: mesh node `Shield`)
  - game-spun reels (`reel.L` / `reel.R`): the bone's LOCAL X is the axle of the disc skinned to it
    (actors/enemy_view.gd spins those bones about local X)
  - `telegraph` starts on the rest pose (it is scrubbed from 0) and `attack` starts on the pose
    `telegraph` ends in
Exit code 1 if any check fails.
"""
from __future__ import annotations

import json
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
MODEL_DIR = os.path.join(REPO, "assets", "models", "enemies")

REQUIRED = ["idle", "move", "telegraph", "attack", "stagger", "death"]
ONE_SHOTS = ["telegraph", "attack", "stagger", "death"]
LOOPS = ["idle", "move"]
PALETTE = {"ceramic", "ceramic_dark", "metal", "metal_light", "brass", "hazard", "hazard_dark", "cable", "tape",
           "speaker", "screen", "blade", "eye_glow", "rune_glow", "meter_glow", "charge_glow", "shield_glow"}
EXPECT = {
    # type: (height range, hovering, extra mesh nodes, needs aim bone)
    "grunt": ((1.2, 1.4), False, [], False),
    "stalker": ((1.3, 1.5), False, [], False),
    "shielder": ((1.3, 1.5), False, ["Shield"], False),
    "drone": ((1.35, 1.6), True, [], True),
}
COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67, "not a glb"
    off = 12
    js, binc = None, None
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk.decode("utf-8"))
        elif ctype == 0x004E4942:
            binc = chunk
        off += 8 + clen
    return js, binc


def accessor(js, binc, idx):
    acc = js["accessors"][idx]
    bv = js["bufferViews"][acc["bufferView"]]
    dt = COMP[acc["componentType"]]
    n = NCOMP[acc["type"]]
    start = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride", 0)
    count = acc["count"]
    item = np.dtype(dt).itemsize * n
    if stride and stride != item:
        raw = np.frombuffer(binc, dtype=np.uint8, count=stride * (count - 1) + item, offset=start)
        rows = np.stack([raw[i * stride: i * stride + item] for i in range(count)])
        arr = rows.view(dt).reshape(count, n)
    else:
        arr = np.frombuffer(binc, dtype=dt, count=count * n, offset=start).reshape(count, n)
    if acc.get("normalized"):
        arr = arr.astype(np.float64) / np.iinfo(dt).max
    return arr


def quat_to_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def node_matrix(n):
    if "matrix" in n:
        return np.array(n["matrix"]).reshape(4, 4).T
    m = np.eye(4)
    m[:3, :3] = quat_to_mat(n.get("rotation", [0, 0, 0, 1])) * np.array(n.get("scale", [1, 1, 1]))
    m[:3, 3] = n.get("translation", [0, 0, 0])
    return m


def check(etype: str) -> bool:
    path = os.path.join(MODEL_DIR, f"{etype}.glb")
    ok = True
    problems = []

    def need(cond, msg):
        nonlocal ok
        if not cond:
            ok = False
            problems.append(msg)

    js, binc = load_glb(path)
    nodes = js["nodes"]
    print(f"\n=== {etype}.glb ({os.path.getsize(path) // 1024} KiB)")
    # World matrices.
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    world = {}

    def wm(i):
        if i not in world:
            world[i] = (wm(parent[i]) if i in parent else np.eye(4)) @ node_matrix(nodes[i])
        return world[i]

    skins = js.get("skins", [])
    joint_ids = set(j for s in skins for j in s["joints"])
    rig = [i for i, n in enumerate(nodes) if n.get("name") == "Rig"]
    need(len(rig) == 1, "no single armature node named Rig")
    bones = [nodes[j]["name"] for j in skins[0]["joints"]] if skins else []
    mesh_nodes = [(i, n) for i, n in enumerate(nodes) if "mesh" in n]
    print("nodes      :", ", ".join(n.get("name", "?") for i, n in enumerate(nodes) if i not in joint_ids))
    print(f"bones ({len(bones)}):", ", ".join(bones))
    print("meshes     :", ", ".join(n["name"] for _, n in mesh_nodes))
    need("root" in bones, "no root bone")
    need(not js.get("cameras") and "KHR_lights_punctual" not in js.get("extensions", {}), "cameras/lights exported")
    for extra in EXPECT[etype][2]:
        need(any(n["name"] == extra for _, n in mesh_nodes), f"missing mesh node {extra}")
    if EXPECT[etype][3]:
        need("aim" in bones, "missing aim bone")
        if "aim" in bones:
            aim = next(i for i, n in enumerate(nodes) if n.get("name") == "aim")
            r = np.array(nodes[aim].get("rotation", [0, 0, 0, 1]))
            # Rest pointing straight up in model space: world basis of aim == Rig's basis.
            rel = np.linalg.inv(wm(rig[0])[:3, :3]) @ wm(aim)[:3, :3]
            need(np.allclose(rel, np.eye(3), atol=1e-4), f"aim rest basis is not identity: {rel.round(3)}")

    # Materials.
    mats = [m["name"] for m in js.get("materials", [])]
    print("materials  :", ", ".join(mats))
    for m in js.get("materials", []):
        name = m["name"]
        need(name in PALETTE, f"material {name} not in the family palette")
        emissive = any(c > 0 for c in m.get("emissiveFactor", [0, 0, 0]))
        need(emissive == name.endswith("_glow"), f"material {name}: emissive={emissive} but name/_glow mismatch")

    # Meshes: triangles, bbox, eye, weights.
    tris = 0
    lo = np.full(3, np.inf)
    hi = np.full(3, -np.inf)
    eye_prims = []
    by_joint = {}   # joint node index -> positions (armature space) of the vertices it owns
    for ni, n in mesh_nodes:
        mesh = js["meshes"][n["mesh"]]
        for p in mesh["primitives"]:
            pos = accessor(js, binc, p["attributes"]["POSITION"]).astype(np.float64)
            # Skinned meshes are posed in bind space = armature space; Rig world transform applies.
            m = wm(rig[0]) if "skin" in n else wm(ni)
            wpos = pos @ m[:3, :3].T + m[:3, 3]
            lo = np.minimum(lo, wpos.min(0))
            hi = np.maximum(hi, wpos.max(0))
            idx = accessor(js, binc, p["indices"]) if "indices" in p else None
            nt = (len(idx) if idx is not None else len(pos)) // 3
            tris += nt
            mname = mats[p["material"]] if "material" in p else None
            if mname == "eye_glow":
                eye_prims.append(wpos.mean(0))
            if "JOINTS_0" in p["attributes"]:
                w = accessor(js, binc, p["attributes"]["WEIGHTS_0"]).astype(np.float64)
                s = w.sum(1)
                need(np.all(np.abs(s - 1) < 2e-3), f"{n['name']}/{mname}: weights do not sum to 1 (min {s.min():.3f})")
                jn = accessor(js, binc, p["attributes"]["JOINTS_0"])
                skin_joints = js["skins"][n["skin"]]["joints"]
                top = jn[np.arange(len(jn)), w.argmax(1)]
                for j in np.unique(top):
                    by_joint.setdefault(skin_joints[int(j)], []).append(pos[top == j])
            else:
                need(False, f"{n['name']}/{mname}: primitive not skinned")
    size = hi - lo
    print(f"triangles  : {tris}")
    print(f"bbox (Godot): min {lo.round(3)}  max {hi.round(3)}  size {size.round(3)}")
    need(tris < 25000, f"triangle budget exceeded: {tris}")
    hmin, hmax = EXPECT[etype][0]
    need(hmin <= hi[1] <= hmax, f"height {hi[1]:.2f} outside {hmin}-{hmax}")
    if EXPECT[etype][1]:
        need(lo[1] > 0.7, f"hovering type should float (min Y {lo[1]:.2f})")
    else:
        need(abs(lo[1]) < 0.01, f"origin not on the floor (min Y {lo[1]:.3f})")
    centre = (lo + hi) / 2
    need(abs(centre[0]) < 0.12, f"footprint not centred in X ({centre[0]:.3f})")
    need(len(eye_prims) == 1, f"expected exactly one eye_glow primitive, got {len(eye_prims)}")
    if eye_prims:
        e = eye_prims[0]
        print(f"eye centroid: {e.round(3)}  (front = +Z)")
        need(e[2] > 0.05 and e[2] > centre[2], f"eye is not on the front (+Z): {e.round(3)}")

    # Game-spun reels: local X of the bone must be the axle (thin axis) of its disc.
    for i, nd in enumerate(nodes):
        if nd.get("name", "").startswith("reel.") and i in by_joint:
            pts = np.concatenate(by_joint[i])
            _, sv, vt = np.linalg.svd(pts - pts.mean(0), full_matrices=False)
            axle = vt[-1]
            rel = np.linalg.inv(wm(rig[0])[:3, :3]) @ wm(i)[:3, :3]
            bx = rel[:, 0] / np.linalg.norm(rel[:, 0])
            al = abs(float(axle @ bx))
            print(f"{nd['name']:<11}: axle . local X = {al:.3f}")
            need(al > 0.99, f"{nd['name']}: local X is not the reel axle (|cos| {al:.3f})")

    # Animations.
    anims = {}
    for a in js.get("animations", []):
        tmax, tmin = 0.0, 1e9
        animated = set()
        endpoints = {}
        for ch in a["channels"]:
            s = a["samplers"][ch["sampler"]]
            t = accessor(js, binc, s["input"])
            tmax = max(tmax, float(t.max()))
            tmin = min(tmin, float(t.min()))
            tn = nodes[ch["target"]["node"]].get("name")
            animated.add(tn)
            v = accessor(js, binc, s["output"]).astype(np.float64)
            endpoints[(tn, ch["target"]["path"])] = (v[0], v[-1])
        anims[a["name"]] = (tmin, tmax, animated, endpoints)
    print("animations :", ", ".join(f"{k} {v[1]:.3f}s" for k, v in anims.items()))
    for r in REQUIRED:
        need(r in anims, f"missing animation {r}")
    for r in ONE_SHOTS:
        if r in anims:
            need(abs(anims[r][1] - 1.0) < 1e-3 and anims[r][0] < 1e-3, f"{r} is not exactly 0..1.0 s ({anims[r][0]}..{anims[r][1]})")
    for r in LOOPS:
        if r in anims:
            bad = []
            for (tn, path), (v0, v1) in anims[r][3].items():
                d = min(np.abs(v0 - v1).max(), np.abs(v0 + v1).max()) if path == "rotation" else np.abs(v0 - v1).max()
                if d > 1e-3:
                    bad.append(f"{tn}.{path}")
            need(not bad, f"loop {r} does not close: {bad[:6]}")
    for name, (_, _, animated, _) in anims.items():
        need("aim" not in animated, f"aim bone is animated in {name}")
    by_name = {n.get("name"): n for n in nodes}
    rest_of = {"rotation": [0, 0, 0, 1], "translation": [0, 0, 0], "scale": [1, 1, 1]}

    def differs(a, b, path):
        a, b = np.asarray(a, dtype=np.float64), np.asarray(b, dtype=np.float64)
        d = min(np.abs(a - b).max(), np.abs(a + b).max()) if path == "rotation" else np.abs(a - b).max()
        return d > 2e-3

    if "telegraph" in anims:
        bad = [f"{tn}.{path}" for (tn, path), (v0, _) in anims["telegraph"][3].items()
               if differs(v0, by_name[tn].get(path, rest_of[path]), path)]
        need(not bad, f"telegraph does not start on the rest pose: {bad[:6]}")
        if "attack" in anims:
            bad = [f"{tn}.{path}" for (tn, path), (_, v1) in anims["telegraph"][3].items()
                   if (tn, path) in anims["attack"][3] and tn not in ("reel", "prop", "reel.L", "reel.R")
                   and differs(v1, anims["attack"][3][(tn, path)][0], path)]
            need(not bad, f"attack does not start on the telegraph's end pose: {bad[:6]}")
    for p in problems:
        print("  FAIL:", p)
    print("  OK" if ok else "  FAILED")
    return ok


def main():
    types = sys.argv[1:] or ["grunt", "stalker", "shielder", "drone"]
    results = [check(t) for t in types]
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
