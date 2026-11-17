"""
Measures the head of a Moxie glb from outside Blender, relative to the Head bone's joint, in
character axes (+Y up, +Z front): the numbers the headgear is fitted to (hlib.py HEAD_* / CUP_* /
BAND_TOP and data/wardrobe.json head_fit).

    python -I art/wardrobe/measure_head.py [model.glb ...]      default: assets/models/moxie.glb
"""
import json
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load(path):
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + n])
    off = 20 + n
    bn = struct.unpack("<I", b[off:off + 4])[0]
    return j, b[off + 8:off + 8 + bn]


def accessor(j, blob, i):
    a = j["accessors"][i]
    bv = j["bufferViews"][a["bufferView"]]
    dt = np.dtype(CT[a["componentType"]])
    nc = NC[a["type"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 0)
    if stride and stride != dt.itemsize * nc:
        raw = np.frombuffer(blob, np.uint8, count=stride * (a["count"] - 1) + dt.itemsize * nc, offset=start)
        idx = (np.arange(a["count"])[:, None] * stride + np.arange(dt.itemsize * nc)[None, :]).ravel()
        arr = np.frombuffer(raw[idx].tobytes(), dt)
    else:
        arr = np.frombuffer(blob, dt, count=a["count"] * nc, offset=start)
    return arr.reshape(a["count"], nc).astype(np.float64)


def node_matrix(nd):
    if "matrix" in nd:
        return np.array(nd["matrix"], dtype=np.float64).reshape(4, 4).T
    m = np.eye(4)
    t = nd.get("translation", [0, 0, 0])
    q = nd.get("rotation", [0, 0, 0, 1])
    s = nd.get("scale", [1, 1, 1])
    x, y, z, w = q
    r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m[:3, :3] = r * np.array(s)[None, :]
    m[:3, 3] = t
    return m


def measure(path):
    j, blob = load(path)
    nodes = j["nodes"]
    parent = {}
    for i, nd in enumerate(nodes):
        for c in nd.get("children", []):
            parent[c] = i

    def world(i):
        m = node_matrix(nodes[i])
        while i in parent:
            i = parent[i]
            m = node_matrix(nodes[i]) @ m
        return m
    head = next(i for i, nd in enumerate(nodes) if nd.get("name") in ("Head", "head"))
    hpos = world(head)[:3, 3]
    mats = [m.get("name", "") for m in j.get("materials", [])]
    per = {}
    for i, nd in enumerate(nodes):
        if "mesh" not in nd:
            continue
        # skinned meshes: glTF ignores the node transform; vertices are in skeleton-root space
        w = np.eye(4) if "skin" in nd else world(i)
        for pr in j["meshes"][nd["mesh"]]["primitives"]:
            v = accessor(j, blob, pr["attributes"]["POSITION"])
            v = v @ w[:3, :3].T + w[:3, 3] - hpos
            per.setdefault(mats[pr["material"]] if "material" in pr else "", []).append(v)
    per = {k: np.concatenate(v) for k, v in per.items()}
    print("==", os.path.relpath(path, ROOT), " head joint", np.round(hpos, 3))

    def grp(prefixes, ylo=-0.02, yhi=0.6, xmax=0.4):
        vs = [v for k, v in per.items() if any(k.startswith(p) for p in prefixes) and not k.endswith("_glow")]
        if not vs:
            return None
        v = np.concatenate(vs)
        return v[(v[:, 1] > ylo) & (v[:, 1] < yhi) & (np.abs(v[:, 0]) < xmax)]
    out = {}
    hp = grp(["headphones", "phones", "hp_"])
    if hp is not None and len(hp):
        out["headphones_min"] = hp.min(0)
        out["headphones_max"] = hp.max(0)
        cup = hp[(hp[:, 0] > hp[:, 0].max() * 0.72) & (hp[:, 1] < hp[:, 1].min() + (hp[:, 1].max() - hp[:, 1].min()) * 0.6)]
        out["cup_centre"] = (cup.min(0) + cup.max(0)) / 2
        out["cup_radius_yz"] = (cup.max(0) - cup.min(0))[1:] / 2
        out["cup_outer_x"] = cup[:, 0].max()
        out["band_top"] = hp[:, 1].max()
    sk = grp(["skin", "face", "head"], ylo=0.0, xmax=0.2)
    if sk is not None and len(sk):
        out["skin_min"] = sk.min(0)
        out["skin_max"] = sk.max(0)
        brow = sk[(sk[:, 1] > 0.12) & (np.abs(sk[:, 0]) < 0.03)]
        if len(brow):
            out["skin_front_above_0.12"] = brow[:, 2].max()
    hair = grp(["hair"], ylo=0.0)
    if hair is not None and len(hair):
        mid = hair[np.abs(hair[:, 0]) < 0.09]
        out["hair_top_mid"] = mid[:, 1].max()
        out["hair_front_mid"] = mid[:, 2].max()
        out["hair_back_mid"] = mid[:, 2].min()
        for y0 in (0.10, 0.14, 0.18, 0.22):
            s = mid[(mid[:, 1] > y0) & (mid[:, 1] < y0 + 0.04)]
            if len(s):
                out["hair_front_y%.2f" % y0] = s[:, 2].max()
        near = hair[(np.abs(hair[:, 2]) < 0.05) & (hair[:, 1] > 0.08) & (hair[:, 1] < 0.2) & (np.abs(hair[:, 0]) < 0.16)]
        if len(near):
            out["hair_side_x_at_ear"] = np.abs(near[:, 0]).max()
    for k, v in out.items():
        print("  %-24s %s" % (k, np.round(v, 3)))
    return out


if __name__ == "__main__":
    paths = sys.argv[1:] or [os.path.join(ROOT, "assets", "models", "moxie.glb")]
    for p in paths:
        measure(p)
