"""Stage 7: the export skeleton and skinning.

- builds armature 'Rig' with Godot SkeletonProfileHumanoid bone names (Root, Hips ... fingers, toes)
  from the MakeHuman joint positions, plus secondary bones (pigtails, jacket flaps, straps)
- skin weights: the MakeHuman 'default' rig weights are merged onto the humanoid bones for every
  mesh that kept the body topology (Body, Pants, Sleeves); fitted garments get barycentric weight
  transfer from the full body / from the garment they sit on; hard-surface gear is bound rigidly
- re-poses everything from the modelling A-pose to a clean T-pose and makes that the rest pose
- sets consistent bone rolls, grounds the soles at z = 0
Outputs _stage/s07_rig.blend.
"""
import bpy, bmesh, sys, os, json, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mb_util as U
import mb_pose as P
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
from mathutils.interpolate import poly_3d_calc

U.open_stage("s06_gear")
mh = bpy.data.objects["MH_Rig"]
body = bpy.data.objects["Body"]
with bpy.data.libraries.load(os.path.join(U.STAGE, "s04_hair.blend")) as (src, dst):
    dst.objects = ["Body"]
body_src = dst.objects[0]
body_src.name = "BodySrc"
bpy.context.scene.collection.objects.link(body_src)


def J(name, tail=False):
    b = mh.data.bones[name]
    return Vector(b.tail_local if tail else b.head_local)


def mx(v):
    return Vector((-v.x, v.y, v.z))


def c0(v):
    return Vector((0.0, v.y, v.z))


# ---------------------------------------------------------------- bone table
B = {}          # name -> (head, tail, parent)
B["Root"] = (Vector((0, 0, 0)), Vector((0, 0, 0.12)), None)
B["Hips"] = (c0(J("spine05")), c0(J("spine04")), "Root")
B["Spine"] = (c0(J("spine04")), c0(J("spine02")), "Hips")
B["Chest"] = (c0(J("spine02")), c0(J("spine01")), "Spine")
B["UpperChest"] = (c0(J("spine01")), c0(J("neck01")), "Chest")
B["Neck"] = (c0(J("neck01")), c0(J("head")), "UpperChest")
B["Head"] = (c0(J("head")), c0(J("head")) + Vector((0, 0, 0.19)), "Neck")
FMAP = {"Thumb": ("finger1", ("Metacarpal", "Proximal", "Distal")), "Index": ("finger2", ("Proximal", "Intermediate", "Distal")),
        "Middle": ("finger3", ("Proximal", "Intermediate", "Distal")), "Ring": ("finger4", ("Proximal", "Intermediate", "Distal")),
        "Little": ("finger5", ("Proximal", "Intermediate", "Distal"))}
toe_h = sum((J("toe%d-1.L" % i) for i in range(1, 6)), Vector()) / 5
for side, f in (("Left", lambda v: v), ("Right", mx)):
    B[side + "Shoulder"] = (f(J("clavicle.L")), f(J("upperarm01.L")), "UpperChest")
    B[side + "UpperArm"] = (f(J("upperarm01.L")), f(J("lowerarm01.L")), side + "Shoulder")
    B[side + "LowerArm"] = (f(J("lowerarm01.L")), f(J("wrist.L")), side + "UpperArm")
    B[side + "Hand"] = (f(J("wrist.L")), f(J("finger3-1.L")), side + "LowerArm")
    for fn, (mhf, segs) in FMAP.items():
        for i, seg in enumerate(segs):
            h = J("%s-%d.L" % (mhf, i + 1))
            t = J("%s-%d.L" % (mhf, i + 2)) if i < 2 else J("%s-3.L" % mhf, tail=True)
            B[side + fn + seg] = (f(h), f(t), (side + fn + segs[i - 1]) if i else side + "Hand")
    B[side + "UpperLeg"] = (f(J("upperleg01.L")), f(J("lowerleg01.L")), "Hips")
    B[side + "LowerLeg"] = (f(J("lowerleg01.L")), f(J("foot.L")), side + "UpperLeg")
    B[side + "Foot"] = (f(J("foot.L")), f(toe_h), side + "LowerLeg")
    B[side + "Toes"] = (f(toe_h), f(toe_h + Vector((0, -0.075, -0.004))), side + "Foot")

# MakeHuman weight group -> humanoid bone
MAP = {"root": "Hips", "spine05": "Hips", "pelvis.L": "Hips", "pelvis.R": "Hips", "spine04": "Spine", "spine03": "Spine",
       "spine02": "Chest", "breast.L": "Chest", "breast.R": "Chest", "spine01": "UpperChest",
       "neck01": "Neck", "neck02": "Neck", "neck03": "Neck"}
for b_ in mh.data.bones["head"].children_recursive:
    MAP[b_.name] = "Head"
MAP["head"] = "Head"
for side, s in (("Left", "L"), ("Right", "R")):
    MAP.update({"clavicle." + s: side + "Shoulder", "shoulder01." + s: side + "Shoulder",
                "upperarm01." + s: side + "UpperArm", "upperarm02." + s: side + "UpperArm",
                "lowerarm01." + s: side + "LowerArm", "lowerarm02." + s: side + "LowerArm", "wrist." + s: side + "Hand",
                "upperleg01." + s: side + "UpperLeg", "upperleg02." + s: side + "UpperLeg",
                "lowerleg01." + s: side + "LowerLeg", "lowerleg02." + s: side + "LowerLeg", "foot." + s: side + "Foot"})
    for i in range(1, 5):
        MAP["metacarpal%d.%s" % (i, s)] = side + "Hand"
    for fn, (mhf, segs) in FMAP.items():
        for i, seg in enumerate(segs):
            MAP["%s-%d.%s" % (mhf, i + 1, s)] = side + fn + seg
    for t in range(1, 6):
        for k in range(1, 4):
            MAP["toe%d-%d.%s" % (t, k, s)] = side + "Toes"

# ---------------------------------------------------------------- secondary bones
hair = bpy.data.objects["Hair"]
tie_l = Vector(hair["tie_l"])
ax_l = Vector(hair["tie_axis_l"])
drop = (ax_l + Vector((0, 0, -0.9))).normalized()
for side, f in (("L", lambda v: v), ("R", mx)):
    B["Pigtail%s1" % side] = (f(tie_l), f(tie_l + ax_l * 0.085), "Head")
    B["Pigtail%s2" % side] = (f(tie_l + ax_l * 0.085), f(tie_l + ax_l * 0.085 + drop * 0.10), "Pigtail%s1" % side)
    B["Jacket%s" % side] = (f(Vector((0.135, -0.105, 1.135))), f(Vector((0.150, -0.125, 0.965))), "Chest")
B["JacketBack"] = (Vector((0, 0.115, 1.09)), Vector((0, 0.13, 0.96)), "Chest")
straps = json.loads(bpy.data.objects["Straps"]["strap_roots"])
for k, (a, b_) in enumerate(straps):
    a, b_ = Vector(a), Vector(b_)
    mid = a.lerp(b_, 0.45)
    B["Strap%da" % (k + 1)] = (a, mid, "Hips")
    B["Strap%db" % (k + 1)] = (mid, b_, "Strap%da" % (k + 1))

arm = bpy.data.armatures.new("Rig")
rig = bpy.data.objects.new("Rig", arm)
bpy.context.scene.collection.objects.link(rig)
U.activate(rig)
bpy.ops.object.mode_set(mode='EDIT')
for name, (h, t, par) in B.items():
    eb = arm.edit_bones.new(name)
    eb.head, eb.tail = h, t
for name, (h, t, par) in B.items():
    if par:
        arm.edit_bones[name].parent = arm.edit_bones[par]
bpy.ops.object.mode_set(mode='OBJECT')
BONES = list(B.keys())
BI = {n: i for i, n in enumerate(BONES)}
NBONE = len(BONES)

# ---------------------------------------------------------------- weight plumbing
def read_mh_weights(obj):
    """Dense (nverts x NBONE) matrix from MakeHuman groups merged onto humanoid bones."""
    gmap = {}
    for g in obj.vertex_groups:
        if g.name in MAP:
            gmap[g.index] = BI[MAP[g.name]]
    Wm = np.zeros((len(obj.data.vertices), NBONE), dtype=np.float32)
    for v in obj.data.vertices:
        for g in v.groups:
            j = gmap.get(g.group)
            if j is not None:
                Wm[v.index, j] += g.weight
    return Wm


def write_weights(obj, Wm, limit=4):
    Wm = np.maximum(Wm, 0)
    # keep the strongest `limit` influences
    if Wm.shape[1] > limit:
        idx = np.argsort(-Wm, axis=1)[:, limit:]
        np.put_along_axis(Wm, idx, 0.0, axis=1)
    s = Wm.sum(1, keepdims=True)
    bad = s[:, 0] < 1e-6
    Wm[bad, BI["Hips"]] = 1.0
    s[bad] = 1.0
    Wm = Wm / s
    obj.vertex_groups.clear()
    groups = [obj.vertex_groups.new(name=n) for n in BONES]
    nz = np.argwhere(Wm > 0.002)
    for i, j in nz:
        groups[j].add([int(i)], float(Wm[i, j]), 'REPLACE')
    for g in list(obj.vertex_groups):      # drop empty groups to keep files small
        pass
    return Wm


def tri_bvh(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.faces.ensure_lookup_table()
    tris = [[v.index for v in f.verts] for f in bm.faces]
    cos = [v.co.copy() for v in bm.verts]
    return BVHTree.FromBMesh(bm), tris, cos, bm


def transfer(dst, src_obj, Wsrc, cache={}):
    """Barycentric nearest-surface weight transfer."""
    if src_obj.name not in cache:
        cache[src_obj.name] = tri_bvh(src_obj)
    bvh, tris, cos, _ = cache[src_obj.name]
    out = np.zeros((len(dst.data.vertices), NBONE), dtype=np.float32)
    for v in dst.data.vertices:
        loc, nrm, fi, dist = bvh.find_nearest(v.co)
        t = tris[fi]
        w = poly_3d_calc([cos[t[0]], cos[t[1]], cos[t[2]]], loc)
        out[v.index] = Wsrc[t[0]] * w[0] + Wsrc[t[1]] * w[1] + Wsrc[t[2]] * w[2]
    return out


def islands(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    lab = [-1] * len(bm.verts)
    n = 0
    for v in bm.verts:
        if lab[v.index] >= 0:
            continue
        st = [v]
        lab[v.index] = n
        while st:
            c = st.pop()
            for e in c.link_edges:
                o = e.other_vert(c)
                if lab[o.index] < 0:
                    lab[o.index] = n
                    st.append(o)
        n += 1
    bm.free()
    return np.array(lab), n


def rigid_hint(obj):
    """Per-vertex bone name from the builder's face attribute."""
    names = list(obj.get("rigid_bones", [""]))
    att = obj.data.attributes.get("rigid_bone")
    out = [""] * len(obj.data.vertices)
    if att is None:
        return out
    for p in obj.data.polygons:
        nm = names[att.data[p.index].value]
        for vi in p.vertices:
            out[vi] = nm
    return out


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def co_of(obj):
    a = np.zeros(len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get("co", a)
    return a.reshape(-1, 3)


Wsrc_body = read_mh_weights(body_src)
Wall = {}
for name in ("Body", "Pants", "SleeveL", "SleeveR"):
    o = bpy.data.objects[name]
    Wall[name] = write_weights(o, read_mh_weights(o))
ARMS = [BI[s + n] for s in ("Left", "Right") for n in ("Shoulder", "UpperArm", "LowerArm", "Hand")]
LEGS = [BI[s + n] for s in ("Left", "Right") for n in ("UpperLeg", "LowerLeg", "Foot", "Toes")]

for o in [x for x in bpy.data.objects if x.type == 'MESH']:
    n = o.name
    if n in Wall or n == "BodySrc":
        continue
    co = co_of(o)
    nv = len(co)
    hint = rigid_hint(o)
    if n in ("PantsTrim", "PantsPockets"):
        Wm = transfer(o, bpy.data.objects["Pants"], Wall["Pants"])
        if n == "PantsPockets":
            lab, k = islands(o)
            for i in range(k):
                Wm[lab == i] = Wm[lab == i].mean(0)
    elif n.startswith("SleeveTrim"):
        Wm = transfer(o, bpy.data.objects["Sleeve" + n[-1]], Wall["Sleeve" + n[-1]])
    elif n == "Hair":
        Wm = np.zeros((nv, NBONE), dtype=np.float32)
        Wm[:, BI["Head"]] = 1.0
        lab, k = islands(o)
        for side, f in (("L", 1.0), ("R", -1.0)):
            tie = np.array([tie_l.x * f, tie_l.y, tie_l.z])
            d = np.linalg.norm(co - tie, axis=1)
            for i in range(k):
                m = lab == i
                if d[np.where(m)[0].min()] < 0.03 and m.sum() < 200:        # a plume clump rooted at this tie
                    dd = d[m]
                    w2 = sstep(0.085, 0.17, dd)
                    w1 = sstep(0.012, 0.07, dd) * (1 - w2)
                    Wm[m] = 0
                    Wm[np.where(m)[0], BI["Pigtail%s1" % side]] = w1
                    Wm[np.where(m)[0], BI["Pigtail%s2" % side]] = w2
                    Wm[np.where(m)[0], BI["Head"]] = 1 - w1 - w2
    elif n == "HairTies":
        Wm = np.zeros((nv, NBONE), dtype=np.float32)
        Wm[:, BI["Head"]] = 1.0
    elif n == "Straps":
        Wm = np.zeros((nv, NBONE), dtype=np.float32)
        for k, (a, b_) in enumerate(straps):
            m = np.array([h == "Strap%d" % (k + 1) for h in hint])
            t = (a[2] - co[:, 2]) / max(a[2] - b_[2], 1e-6)
            wb = sstep(0.35, 0.6, t)
            wa = sstep(0.04, 0.2, t) * (1 - wb)
            Wm[m, BI["Strap%da" % (k + 1)]] = wa[m]
            Wm[m, BI["Strap%db" % (k + 1)]] = wb[m]
            Wm[m, BI["Hips"]] = (1 - wa - wb)[m]
    elif any(hint):
        Wm = np.zeros((nv, NBONE), dtype=np.float32)
        for i, h in enumerate(hint):
            Wm[i, BI[h if h in BI else "Hips"]] = 1.0
        if n.startswith("Boot"):
            side = "Left" if n.endswith("L") else "Right"
            ty = B[side + "Toes"][0].y
            wt = sstep(ty + 0.012, ty - 0.022, co[:, 1]) * sstep(0.10, 0.07, co[:, 2])
            Wm[:, BI[side + "Toes"]] = wt
            Wm[:, BI[side + "Foot"]] = 1 - wt
    else:
        Wm = transfer(o, body_src, Wsrc_body)
        if n == "JacketBody":
            Wm[:, ARMS] = 0
            s = Wm.sum(1, keepdims=True)
            Wm = Wm / np.maximum(s, 1e-6)
            zt, zb = co[:, 2].max(), co[:, 2].min()
            h = np.clip((1.12 - co[:, 2]) / (1.12 - zb), 0, 1)
            wf = 0.85 * h ** 1.3
            frontness = sstep(0.0, -0.08, co[:, 1])
            wl = wf * frontness * sstep(-0.02, 0.05, co[:, 0])
            wr = wf * frontness * sstep(0.02, -0.05, co[:, 0])
            wb = wf * sstep(-0.02, 0.06, co[:, 1])
            Wm *= (1 - wl - wr - wb)[:, None]
            Wm[:, BI["JacketL"]] += wl
            Wm[:, BI["JacketR"]] += wr
            Wm[:, BI["JacketBack"]] += wb
        if n in ("Top", "TopGraphic", "ChestStrap"):
            Wm[:, [BI[s + nm] for s in ("Left", "Right") for nm in ("UpperArm", "LowerArm", "Hand")]] = 0
        if n == "Cable":
            Wm[:, ARMS + LEGS] = 0
    Wall[n] = write_weights(o, Wm)

bpy.data.objects.remove(body_src)
bpy.data.objects.remove(mh)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
for o in meshes:
    o.parent = rig
    md = o.modifiers.new("Armature", 'ARMATURE')
    md.object = rig

# ---------------------------------------------------------------- A-pose -> T-pose, applied as the rest pose
U.activate(rig)
bpy.ops.object.mode_set(mode='POSE')
pb = rig.pose.bones
P._update()
foot_m = {s: pb[s + "Foot"].matrix.copy() for s in ("Left", "Right")}
for side, sx in P.SIDES:
    P.aim(pb[side + "Shoulder"], (sx, 0, 0.12))
    P.aim(pb[side + "UpperArm"], (sx, 0, 0))
    P.aim(pb[side + "LowerArm"], (sx, 0, 0))
    # palm down: roll the forearm/hand so the knuckle line is horizontal, then level the hand
    P.aim(pb[side + "Hand"], (sx, 0, 0))
    P._update()
    a = pb[side + "IndexProximal"].head
    b_ = pb[side + "LittleProximal"].head
    across = (b_ - a)
    ang = math.degrees(math.atan2(across.z, -across.y))     # want across along +Y (back) i.e. z = 0
    P.turn(pb[side + "Hand"], (sx, 0, 0), -ang * sx)
    P._update()
    a = pb[side + "IndexProximal"].head
    b_ = pb[side + "LittleProximal"].head
    if abs((b_ - a).z) > 0.004:                             # wrong way round: undo and turn the other way
        P.turn(pb[side + "Hand"], (sx, 0, 0), 2 * ang * sx)
    leg_dir = Vector((sx * 0.040, 0, -1))
    P.aim(pb[side + "UpperLeg"], leg_dir)
    P.aim(pb[side + "LowerLeg"], leg_dir)
    P._update()
    m = foot_m[side].copy()
    m.translation = pb[side + "Foot"].head
    pb[side + "Foot"].matrix = m
    P._update()
bpy.ops.object.mode_set(mode='OBJECT')
for o in meshes:
    U.activate(o)
    bpy.ops.object.modifier_apply(modifier="Armature")
U.activate(rig)
bpy.ops.object.mode_set(mode='POSE')
bpy.ops.pose.armature_apply(selected=False)
bpy.ops.object.mode_set(mode='OBJECT')

# ground the soles and set bone rolls
zmin = min((o.matrix_world @ v.co).z for o in meshes if o.name.startswith("Boot") for v in o.data.vertices)
print("sole offset", zmin)
for o in meshes:
    o.data.transform(Matrix.Translation((0, 0, -zmin)))
U.activate(rig)
bpy.ops.object.mode_set(mode='EDIT')
UPZ = Vector((0, 0, 1))
FWD = Vector((0, -1, 0))
for eb in arm.edit_bones:
    if eb.name != "Root":
        eb.head.z -= zmin
        eb.tail.z -= zmin
    n = eb.name
    if n == "Root":
        eb.head, eb.tail = Vector((0, 0, 0)), Vector((0, 0, 0.12))
        eb.align_roll(FWD)
    elif "Arm" in n or "Hand" in n or "Shoulder" in n or any(f in n for f in ("Thumb", "Index", "Middle", "Ring", "Little")):
        eb.align_roll(UPZ)
    elif "Foot" in n or "Toes" in n:
        eb.align_roll(UPZ)
    else:
        eb.align_roll(FWD)
    eb.use_connect = False
bpy.ops.object.mode_set(mode='OBJECT')
for o in meshes:
    md = o.modifiers.new("Armature", 'ARMATURE')
    md.object = rig
    for p in o.data.polygons:
        pass
rig["humanoid"] = True
print("rig bones", len(arm.bones), "object matrix identity:", rig.matrix_world == Matrix.Identity(4))
U.save_stage("s07_rig")
