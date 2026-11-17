"""Verify assets/models/moxie.glb against the asset contract, from outside Blender.

Run with any Python 3 (standard library only):  python art/moxie/check_glb.py [path]
Reads the GLB's JSON chunk and binary buffer, prints nodes, bones, materials, animations with
their lengths, triangle count and the bounding box (Godot axes, Y up), checks the T-pose rest of
the joint nodes, looks for floating mesh islands, and exits non-zero when something in the
contract (docs/GODOT-PORT.md, "Moxie") does not hold.
"""
import json
import math
import struct
import sys
from collections import defaultdict

# Godot SkeletonProfileHumanoid names (the contract) - fingers: the mitten chain + thumb.
PROFILE_BONES = (["Root", "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head"]
                 + [s + b for s in ("Left", "Right") for b in ("Shoulder", "UpperArm", "LowerArm", "Hand",
                                                               "UpperLeg", "LowerLeg", "Foot", "Toes",
                                                               "ThumbProximal", "MiddleProximal",
                                                               "MiddleIntermediate")])
EXTRA_BONES = (["pigtail.%s.%03d" % (s, i) for s in "LR" for i in (1, 2, 3)]
               + ["jacket.L", "jacket.R", "jacket.B", "RightHandGrip"])
# The model's own material set (the contract only requires tint hooks top*/pants*/shoes* and _glow).
MATERIALS = ["skin", "hair", "hair_dark", "eye", "face_paint", "headphones", "headphones_glow", "headphones_dark",
             "top", "top_trim", "top_graphic", "jacket", "jacket_lining", "pants", "pants_graphic", "strap",
             "belt", "walkman", "pouch", "glove", "wrist_device", "wrist_device_glow", "shoes", "shoes_dark",
             "shoes_lace", "shoes_sole", "metal", "dark"]
CONTRACT_ANIMS = {"idle": 2.0, "run": 0.6, "stopped": 1.0, "light": 1.0, "heavy": 1.0, "dodge": 1.0,
                  "ranged": 1.0, "interact": 1.0, "death": 1.0}
TRI_BUDGET = 27500
COMP = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2), 5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load(path):
    data = open(path, "rb").read()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF" and version == 2, "not a glTF 2 binary"
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


# --- small vector math ----------------------------------------------------------------------

def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def qrot(q, v):
    x, y, z, w = q
    u = (x, y, z)
    t = cross(u, v)
    t = (2 * t[0], 2 * t[1], 2 * t[2])
    c = cross(u, t)
    return (v[0] + w * t[0] + c[0], v[1] + w * t[1] + c[1], v[2] + w * t[2] + c[2])


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz)


def point_tri_dist(p, a, b, c):
    """Distance from p to triangle abc (Ericson, Real-Time Collision Detection 5.1.5)."""
    ab, ac, ap = sub(b, a), sub(c, a), sub(p, a)
    d1, d2 = dot(ab, ap), dot(ac, ap)
    if d1 <= 0 and d2 <= 0:
        q = a
    else:
        bp = sub(p, b)
        d3, d4 = dot(ab, bp), dot(ac, bp)
        if d3 >= 0 and d4 <= d3:
            q = b
        else:
            vc = d1 * d4 - d3 * d2
            if vc <= 0 and d1 >= 0 and d3 <= 0:
                v = d1 / (d1 - d3)
                q = (a[0] + v * ab[0], a[1] + v * ab[1], a[2] + v * ab[2])
            else:
                cp = sub(p, c)
                d5, d6 = dot(ab, cp), dot(ac, cp)
                if d6 >= 0 and d5 <= d6:
                    q = c
                else:
                    vb = d5 * d2 - d1 * d6
                    if vb <= 0 and d2 >= 0 and d6 <= 0:
                        w = d2 / (d2 - d6)
                        q = (a[0] + w * ac[0], a[1] + w * ac[1], a[2] + w * ac[2])
                    else:
                        va = d3 * d6 - d5 * d4
                        if va <= 0 and (d4 - d3) >= 0 and (d5 - d6) >= 0:
                            w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
                            q = (b[0] + w * (c[0] - b[0]), b[1] + w * (c[1] - b[1]), b[2] + w * (c[2] - b[2]))
                        else:
                            den = 1.0 / (va + vb + vc)
                            v, w = vb * den, vc * den
                            q = (a[0] + ab[0] * v + ac[0] * w, a[1] + ab[1] * v + ac[1] * w,
                                 a[2] + ab[2] * v + ac[2] * w)
    d = sub(p, q)
    return math.sqrt(dot(d, d))


def seg_tri_hit(p, q, a, b, c):
    """Segment pq crosses triangle abc (Moller-Trumbore on the segment)."""
    e1, e2 = sub(b, a), sub(c, a)
    d = sub(q, p)
    h = cross(d, e2)
    det = dot(e1, h)
    if abs(det) < 1e-12:
        return False
    f = 1.0 / det
    s = sub(p, a)
    u = f * dot(s, h)
    if u < 0 or u > 1:
        return False
    qq = cross(s, e1)
    v = f * dot(d, qq)
    if v < 0 or u + v > 1:
        return False
    t = f * dot(e2, qq)
    return 0.0 <= t <= 1.0


def floating_islands(verts, tris, tol=0.002, cell=0.02):
    """Connected mesh islands (vertices welded by position) that do not touch - intersect or come
    within `tol` of - the island set attached to the largest island. Returns [(size, centre)]."""
    key = {}
    vid = []
    for p in verts:
        k = (round(p[0] / 1e-5), round(p[1] / 1e-5), round(p[2] / 1e-5))
        vid.append(key.setdefault(k, len(key)))
    parent = list(range(len(key)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for a, b, c in tris:
        ra, rb, rc = find(vid[a]), find(vid[b]), find(vid[c])
        parent[rb] = ra
        parent[find(rc)] = ra
    isl_of_tri = [find(vid[t[0]]) for t in tris]
    isl_ids = sorted(set(isl_of_tri))
    index = {r: i for i, r in enumerate(isl_ids)}
    tri_isl = [index[r] for r in isl_of_tri]
    n = len(isl_ids)
    sizes = [0] * n
    for i in tri_isl:
        sizes[i] += 1
    grid = defaultdict(list)
    for ti, (a, b, c) in enumerate(tris):
        pa, pb, pc = verts[a], verts[b], verts[c]
        lo = [min(pa[k], pb[k], pc[k]) - tol for k in range(3)]
        hi = [max(pa[k], pb[k], pc[k]) + tol for k in range(3)]
        for x in range(int(math.floor(lo[0] / cell)), int(math.floor(hi[0] / cell)) + 1):
            for y in range(int(math.floor(lo[1] / cell)), int(math.floor(hi[1] / cell)) + 1):
                for z in range(int(math.floor(lo[2] / cell)), int(math.floor(hi[2] / cell)) + 1):
                    grid[(x, y, z)].append(ti)
    adj = [set() for _ in range(n)]
    vert_isl = {}
    for ti, (a, b, c) in enumerate(tris):
        for v in (a, b, c):
            vert_isl[v] = tri_isl[ti]
    # vertex proximity
    for v, isl in vert_isl.items():
        p = verts[v]
        cellk = (int(math.floor(p[0] / cell)), int(math.floor(p[1] / cell)), int(math.floor(p[2] / cell)))
        for ti in grid.get(cellk, ()):
            other = tri_isl[ti]
            if other == isl or other in adj[isl]:
                continue
            a, b, c = tris[ti]
            if point_tri_dist(p, verts[a], verts[b], verts[c]) <= tol:
                adj[isl].add(other)
                adj[other].add(isl)
    # edge-triangle crossings
    for ti, (a, b, c) in enumerate(tris):
        isl = tri_isl[ti]
        for e0, e1 in ((a, b), (b, c), (c, a)):
            p, q = verts[e0], verts[e1]
            mid = ((p[0] + q[0]) * 0.5, (p[1] + q[1]) * 0.5, (p[2] + q[2]) * 0.5)
            cellk = (int(math.floor(mid[0] / cell)), int(math.floor(mid[1] / cell)), int(math.floor(mid[2] / cell)))
            for tj in grid.get(cellk, ()):
                other = tri_isl[tj]
                if other == isl or other in adj[isl]:
                    continue
                x, y, z = tris[tj]
                if seg_tri_hit(p, q, verts[x], verts[y], verts[z]):
                    adj[isl].add(other)
                    adj[other].add(isl)
    root = max(range(n), key=lambda i: sizes[i])
    seen = {root}
    stack = [root]
    while stack:
        k = stack.pop()
        for m in adj[k]:
            if m not in seen:
                seen.add(m)
                stack.append(m)
    out = []
    for i in range(n):
        if i in seen:
            continue
        pts = [verts[v] for t, isl in zip(tris, tri_isl) if isl == i for v in t]
        cen = tuple(sum(p[k] for p in pts) / len(pts) for k in range(3))
        out.append((sizes[i], cen))
    return n, out


def global_rest(nodes, joints):
    """Rest translation/rotation of every joint in model space (from the node TRS chain)."""
    parent = {}
    for i, nd in enumerate(nodes):
        for c in nd.get("children", []):
            parent[c] = i
    cache = {}

    def g(i):
        if i in cache:
            return cache[i]
        nd = nodes[i]
        t = tuple(nd.get("translation", (0, 0, 0)))
        r = tuple(nd.get("rotation", (0, 0, 0, 1)))
        if i in parent:
            pt, pr = g(parent[i])
            rt = qrot(pr, t)
            res = ((pt[0] + rt[0], pt[1] + rt[1], pt[2] + rt[2]), qmul(pr, r))
        else:
            res = (t, r)
        cache[i] = res
        return res
    return {nodes[j]["name"]: g(j) for j in joints}


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "assets/models/moxie.glb"
    js, binc = load(path)
    problems = []
    nodes = js["nodes"]
    print("NODES (%d):" % len(nodes))
    for i, n in enumerate(nodes):
        if "camera" in n or "KHR_lights_punctual" in n.get("extensions", {}):
            problems.append("camera/light node %s" % n.get("name"))
        if "mesh" in n:
            print("  %-12s mesh%s" % (n.get("name"), " (skinned)" if "skin" in n else ""))
    skins = js.get("skins", [])
    if len(skins) != 1:
        problems.append("expected one skin, found %d" % len(skins))
    joints = skins[0]["joints"] if skins else []
    bones = [nodes[j]["name"] for j in joints]
    print("BONES (%d): %s" % (len(bones), ", ".join(bones)))
    for b in PROFILE_BONES + EXTRA_BONES:
        if b not in bones:
            problems.append("missing bone " + b)
    if not any(n.get("name") == "Rig" for n in nodes):
        problems.append("no node named Rig")
    # T-pose rest: the arm chains run straight along +-X (Godot axes), legs straight down
    rest = global_rest(nodes, joints) if joints else {}
    for side, sx in (("Left", 1), ("Right", -1)):
        chain = [side + "UpperArm", side + "LowerArm", side + "Hand", side + "MiddleProximal"]
        for a, b in zip(chain, chain[1:]):
            if a in rest and b in rest:
                d = sub(rest[b][0], rest[a][0])
                ln = math.sqrt(dot(d, d))
                ang = math.degrees(math.acos(max(-1.0, min(1.0, d[0] * sx / ln))))
                print("REST %-22s -> %-22s %5.1f deg off the T-pose line" % (a, b, ang))
                if ang > 3.0:
                    problems.append("rest pose is not a T-pose (%s %.1f deg)" % (a, ang))
    if "LeftUpperLeg" in rest and "LeftFoot" in rest:
        d = sub(rest["LeftFoot"][0], rest["LeftUpperLeg"][0])
        print("REST LeftUpperLeg -> LeftFoot drop %.3f, sideways %.3f" % (-d[1], d[0]))
    mats = [m["name"] for m in js.get("materials", [])]
    print("MATERIALS (%d): %s" % (len(mats), ", ".join(mats)))
    for m in MATERIALS:
        if m not in mats:
            problems.append("missing material " + m)
    for hook in ("top", "pants", "shoes"):
        if not any(m.startswith(hook) for m in mats):
            problems.append("no tint-hook material starting with " + hook)
    for m in js.get("materials", []):
        if m["name"].endswith("_glow") and not m.get("emissiveFactor"):
            problems.append("glow material without emission: " + m["name"])
        tex = m.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if tex:
            print("  textured: %s (image %s)" % (m["name"], js["textures"][tex["index"]]["source"]))
    # geometry
    tris = 0
    lo = [1e9] * 3
    hi = [-1e9] * 3
    all_v, all_t = [], []
    for mesh in js["meshes"]:
        for prim in mesh["primitives"]:
            pos = read_accessor(js, binc, prim["attributes"]["POSITION"])
            base = len(all_v)
            all_v += pos
            if "indices" in prim:
                idx = [i[0] for i in read_accessor(js, binc, prim["indices"])]
                tris += len(idx) // 3
                all_t += [(base + idx[k], base + idx[k + 1], base + idx[k + 2]) for k in range(0, len(idx), 3)]
            acc = js["accessors"][prim["attributes"]["POSITION"]]
            for k in range(3):
                lo[k] = min(lo[k], acc["min"][k])
                hi[k] = max(hi[k], acc["max"][k])
            for attr in ("JOINTS_0", "WEIGHTS_0"):
                if attr not in prim["attributes"]:
                    problems.append("primitive without %s in mesh %s" % (attr, mesh.get("name")))
    print("TRIANGLES %d" % tris)
    print("BBOX (bind pose, Godot axes) min (%.3f %.3f %.3f) max (%.3f %.3f %.3f)" % (*lo, *hi))
    print("  height %.3f, width %.3f, depth %.3f" % (hi[1] - lo[1], hi[0] - lo[0], hi[2] - lo[2]))
    if tris > TRI_BUDGET:
        problems.append("triangle budget exceeded: %d > %d" % (tris, TRI_BUDGET))
    if not (1.55 <= hi[1] <= 1.75):
        problems.append("height %.3f outside ~1.6" % hi[1])
    if abs(lo[1]) > 0.01:
        problems.append("origin not on the floor (min y %.3f)" % lo[1])
    n_isl, floating = floating_islands(all_v, all_t)
    print("ISLANDS %d, floating %d" % (n_isl, len(floating)))
    for size, cen in floating:
        print("  floating island: %d tris near (%.3f %.3f %.3f)" % (size, *cen))
        problems.append("floating mesh island near (%.3f %.3f %.3f)" % cen)
    # facing: the painted face (material face_paint) must sit on the +Z side in Godot
    fi = mats.index("face_paint") if "face_paint" in mats else -1
    for mesh in js["meshes"]:
        for prim in mesh["primitives"]:
            if prim.get("material") == fi:
                pos = read_accessor(js, binc, prim["attributes"]["POSITION"])
                zc = sum(p[2] for p in pos) / len(pos)
                yc = sum(p[1] for p in pos) / len(pos)
                print("FACE centre z %+.3f (front is +Z), height %.3f" % (zc, yc))
                if zc < 0.03:
                    problems.append("face is not on the +Z side (z %.3f)" % zc)
    # animations
    anims = {a["name"]: a for a in js.get("animations", [])}
    print("ANIMATIONS (%d):" % len(anims))
    for name, a in anims.items():
        t1 = max(js["accessors"][s["input"]]["max"][0] for s in a["samplers"])
        t0 = min(js["accessors"][s["input"]]["min"][0] for s in a["samplers"])
        targets = sorted({nodes[c["target"]["node"]]["name"] for c in a["channels"]})
        print("  %-9s %.3f s (from %.3f), %d channels, %d bones" % (name, t1 - t0, t0, len(a["channels"]),
                                                                    len(targets)))
        stray = [t for t in targets if t not in bones and t != "Rig"]
        if stray:
            problems.append("animation %s targets non-joint nodes %s" % (name, stray))
    for name, length in CONTRACT_ANIMS.items():
        if name not in anims:
            problems.append("missing animation " + name)
            continue
        a = anims[name]
        t1 = max(js["accessors"][s["input"]]["max"][0] for s in a["samplers"])
        t0 = min(js["accessors"][s["input"]]["min"][0] for s in a["samplers"])
        if abs((t1 - t0) - length) > 1e-3 or abs(t0) > 1e-4:
            problems.append("animation %s spans %.3f..%.3f, expected 0..%.1f" % (name, t0, t1, length))
    # skin weights: every primitive normalised
    bad = total = 0
    for mesh in js["meshes"]:
        for prim in mesh["primitives"]:
            w = read_accessor(js, binc, prim["attributes"]["WEIGHTS_0"])
            total += len(w)
            bad += sum(1 for row in w if abs(sum(row) - 1.0) > 0.01)
    print("WEIGHTS %d verts, %d not normalised" % (total, bad))
    if bad:
        problems.append("%d unnormalised weights" % bad)
    if js.get("cameras") or js.get("extensions", {}).get("KHR_lights_punctual"):
        problems.append("cameras or lights exported")
    print()
    if problems:
        print("PROBLEMS:")
        for p in problems:
            print("  - " + p)
        sys.exit(1)
    print("OK: moxie.glb matches the asset contract")


if __name__ == "__main__":
    main()
