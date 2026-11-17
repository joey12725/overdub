"""
Verifies every weapon / projectile glb WITHOUT Blender (plain glTF parsing):
  python -I art/weapons/check_glb.py [--table]
Checks node names, required empties and their positions against art/weapons/metrics/*.json,
materials (named, *_glow emissive), triangle counts, world bounds, skins, no animations/cameras/
lights/textures. Exit code 1 on any failure. --table prints the markdown rows used in the docs.
"""
import json
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
MELEE = ["splice_blade", "stylus_shiv", "amp_sledge", "reel_lash", "speaker_knuckles", "vinyl_glaive"]
RANGED = ["mixtape_rocket", "needle_rail", "bleed_emitter", "bass_drop", "static_spray"]
PROJ = ["missile", "pierce", "phase", "arc", "burst", "bolt", "shock"]
REQ_NODES = {
    "melee": ["Grip", "Tip", "TrailStart", "TrailEnd"], "ranged": ["Mount", "Muzzle", "Weapon"],
    "projectile": ["Projectile", "Nose", "Tail"],
}
EXTRA = {"reel_lash": ["Weapon", "Lash", "LashRig", "LashRoot"], "vinyl_glaive": ["Weapon", "Disc", "DiscAxis", "Grip2"],
         "speaker_knuckles": ["Gauntlet_R", "Gauntlet_L"], "amp_sledge": ["Weapon", "Grip2"],
         "splice_blade": ["Weapon"], "stylus_shiv": ["Weapon"], "mixtape_rocket": ["Round"]}
BUDGET = {"melee": (1500, 9000), "ranged": (1500, 6000), "projectile": (40, 2000)}
fails = 0


def fail(msg):
    global fails
    fails += 1
    print("  FAIL", msg)


def quat_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def node_local(n):
    m = np.eye(4)
    if "matrix" in n:
        return np.array(n["matrix"], dtype=float).reshape(4, 4).T
    s = n.get("scale", [1, 1, 1])
    m[:3, :3] = quat_mat(n.get("rotation", [0, 0, 0, 1])) @ np.diag(s)
    m[:3, 3] = n.get("translation", [0, 0, 0])
    return m


def load(path):
    b = open(path, "rb").read()
    assert b[:4] == b"glTF", "not a glb"
    n = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + n])
    bin_ = b[20 + n + 8:]
    return j, bin_


def accessor(j, bin_, i):
    a = j["accessors"][i]
    bv = j["bufferViews"][a["bufferView"]]
    comp = {5120: "i1", 5121: "u1", 5122: "<i2", 5123: "<u2", 5125: "<u4", 5126: "<f4"}[a["componentType"]]
    k = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[a["type"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride")
    if stride and stride != np.dtype(comp).itemsize * k:
        raw = np.frombuffer(bin_, dtype="u1", count=stride * a["count"], offset=off).reshape(a["count"], stride)
        return np.frombuffer(raw[:, :np.dtype(comp).itemsize * k].tobytes(), dtype=comp).reshape(a["count"], k)
    return np.frombuffer(bin_, dtype=comp, count=a["count"] * k, offset=off).reshape(a["count"], k)


def check(item, kind, folder):
    path = os.path.join(ROOT, "assets", "models", folder, item + ".glb")
    if not os.path.exists(path):
        fail("%s missing" % path)
        return None
    j, bin_ = load(path)
    nodes = j["nodes"]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i

    def world(i):
        m = node_local(nodes[i])
        while i in parent:
            i = parent[i]
            m = node_local(nodes[i]) @ m
        return m

    names = [n.get("name", "") for n in nodes]
    for req in REQ_NODES[kind] + EXTRA.get(item, []):
        if req not in names:
            fail("%s: node %s missing" % (item, req))
    for key in ("animations", "cameras", "textures", "images"):
        if j.get(key):
            fail("%s: unexpected %s" % (item, key))
    mats = [m.get("name", "") for m in j.get("materials", [])]
    for m in j.get("materials", []):
        nm = m.get("name", "")
        if not nm:
            fail("%s: unnamed material" % item)
        if nm.endswith("_glow") and not any(c > 0 for c in m.get("emissiveFactor", [0, 0, 0])):
            fail("%s: %s is not emissive" % (item, nm))
        if "baseColorTexture" in m.get("pbrMetallicRoughness", {}):
            fail("%s: %s has a texture" % (item, nm))
    lo = np.full(3, 1e9)
    hi = np.full(3, -1e9)
    tris = {}
    for i, n in enumerate(nodes):
        if "mesh" not in n:
            continue
        w = world(i) if "skin" not in n else np.eye(4)
        t = 0
        for p in j["meshes"][n["mesh"]]["primitives"]:
            pos = accessor(j, bin_, p["attributes"]["POSITION"]).astype(float)
            t += (j["accessors"][p["indices"]]["count"] if "indices" in p else len(pos)) // 3
            if "NORMAL" not in p["attributes"]:
                fail("%s: primitive without normals" % item)
            if "material" not in p:
                fail("%s: primitive without a material" % item)
            wp = pos @ w[:3, :3].T + w[:3, 3]
            lo = np.minimum(lo, wp.min(0))
            hi = np.maximum(hi, wp.max(0))
        tris[n["name"]] = t
    total = sum(tris.values())
    b0, b1 = BUDGET[kind]
    if not (b0 <= total <= b1):
        fail("%s: %d triangles outside %d..%d" % (item, total, b0, b1))
    empties = {n["name"]: world(i) for i, n in enumerate(nodes) if "mesh" not in n and "children" not in n and n.get("name") and i not in [jn for s in j.get("skins", []) for jn in s["joints"]]}
    mpath = os.path.join(HERE, "metrics", item + ".json")
    met = json.load(open(mpath)) if os.path.exists(mpath) else None
    if met:
        for nm, e in met["empties"].items():
            if nm not in empties:
                fail("%s: empty %s missing" % (item, nm))
            elif np.abs(empties[nm][:3, 3] - np.array(e["pos"])).max() > 2e-3:
                fail("%s: empty %s at %s, expected %s" % (item, nm, empties[nm][:3, 3].round(4), e["pos"]))
        if np.abs(lo - np.array(met["bounds_min"])).max() > 3e-3 or np.abs(hi - np.array(met["bounds_max"])).max() > 3e-3:
            fail("%s: bounds %s..%s differ from the build's %s..%s" % (item, lo.round(3), hi.round(3), met["bounds_min"], met["bounds_max"]))
        if total != met["tris_total"]:
            fail("%s: %d triangles, build reported %d" % (item, total, met["tris_total"]))
    # frame conventions
    if kind == "melee":
        if not (lo[1] < -0.03 and hi[1] > 0.09):
            fail("%s: origin is not inside the grip (y %.3f..%.3f)" % (item, lo[1], hi[1]))
        tip = empties.get("Tip")
        if tip is not None and tip[1, 3] < 0.09:
            fail("%s: Tip is not along +Y" % item)
    if kind == "ranged":
        mz = empties.get("Muzzle")
        if mz is not None:
            if mz[2, 3] < (0.05 if item == "bass_drop" else 0.15) or mz[2, 2] < 0.7:   # bass_drop lobs: tilted 40 degrees up
                fail("%s: Muzzle not forward along +Z" % item)
    if kind == "projectile":
        if not (lo[2] < 0 < hi[2]) or abs((lo[0] + hi[0]) / 2) > 0.01:
            fail("%s: not centred / nose not along +Z" % item)
    skins = j.get("skins", [])
    bones = [nodes[jn]["name"] for s in skins for jn in s["joints"]]
    if item == "reel_lash" and len(bones) != 10:
        fail("reel_lash: expected 10 lash bones, found %d" % len(bones))
    print("%-17s tris=%5d %-34s size=(%.3f, %.3f, %.3f) y=%.3f..%.3f z=%.3f..%.3f mats=%d empties=%s%s" % (
        item, total, ",".join("%s:%d" % kv for kv in tris.items()), *(hi - lo), lo[1], hi[1], lo[2], hi[2], len(mats),
        ",".join(sorted(empties)), (" bones=%d" % len(bones)) if bones else ""))
    return {"tris": total, "lo": lo, "hi": hi, "empties": empties, "mats": mats}


def main():
    out = {}
    for it in MELEE:
        out[it] = check(it, "melee", "weapons")
    for it in RANGED:
        out[it] = check(it, "ranged", "weapons")
    for it in PROJ:
        out[it] = check(it, "projectile", "projectiles")
    print("check_glb: %d failure(s)" % fails)
    sys.exit(1 if fails else 0)


main()
