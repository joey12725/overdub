"""Export skeleton + skinning.

The armature `Rig` uses Godot's SkeletonProfileHumanoid bone names, hierarchy and rest
orientations (rolls are taken from Godot's own reference pose, see gd_refpose.gd), in a clean
T-pose, plus secondary bones for pigtails, jacket flaps and hanging straps. Skin weights are
analytic (functions of the rest position, per garment), so they are smooth, symmetric and
reproducible, then all meshes are joined into one skinned mesh `Moxie`.
"""
import json
import math
import os

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector
from mathutils.kdtree import KDTree

import mc_hair
import mc_hand
import mc_kit
from mc_body import ELBOW, SHOULDER, WRIST
from mc_boots import FOOT_Y
from mc_head import NECK_R, neck_centre_y
from mc_jacket import BODY_YC
from mc_util import V, activate, get_co, norm, smoothstep as sm

HERE = os.path.dirname(os.path.abspath(__file__))

J = {
    "Hips": V(0, 0.014, 0.895), "Spine": V(0, 0.014, 0.975), "Chest": V(0, 0.014, 1.075),
    "UpperChest": V(0, 0.014, 1.175), "Neck": V(0, 0.016, 1.318), "Head": V(0, 0.006, 1.395),
    "HeadTop": V(0, 0.006, 1.600),
    "Shoulder": V(0.022, 0.014, 1.296), "UpperArm": SHOULDER, "LowerArm": ELBOW, "Hand": WRIST,
    "HandEnd": V(0.680, 0.008, 1.300),
    "UpperLeg": V(0.085, 0.012, 0.865), "LowerLeg": V(0.094, 0.004, 0.480), "Foot": V(0.100, 0.024, 0.090),
    "Toes": V(0.100, -0.090, 0.022), "ToesEnd": V(0.100, -0.160, 0.022),
}
FINGER_BONES = {"Thumb": ("Metacarpal", "Proximal", "Distal"),
                "Index": ("Proximal", "Intermediate", "Distal"),
                "Middle": ("Proximal", "Intermediate", "Distal"),
                "Ring": ("Proximal", "Intermediate", "Distal"),
                "Little": ("Proximal", "Intermediate", "Distal")}


def bone_table():
    """[(name, head, tail, parent)] in creation order."""
    T = []
    T.append(("Hips", J["Hips"], J["Spine"], None))
    T.append(("Spine", J["Spine"], J["Chest"], "Hips"))
    T.append(("Chest", J["Chest"], J["UpperChest"], "Spine"))
    T.append(("UpperChest", J["UpperChest"], J["Neck"], "Chest"))
    T.append(("Neck", J["Neck"], J["Head"], "UpperChest"))
    T.append(("Head", J["Head"], J["HeadTop"], "Neck"))
    fj = mc_hand.joints_left()
    for side, sx in (("Left", 1), ("Right", -1)):
        mir = V(sx, 1, 1)
        T.append((side + "Shoulder", J["Shoulder"] * mir, J["UpperArm"] * mir, "UpperChest"))
        T.append((side + "UpperArm", J["UpperArm"] * mir, J["LowerArm"] * mir, side + "Shoulder"))
        T.append((side + "LowerArm", J["LowerArm"] * mir, J["Hand"] * mir, side + "UpperArm"))
        T.append((side + "Hand", J["Hand"] * mir, J["HandEnd"] * mir, side + "LowerArm"))
        for fn, segs in FINGER_BONES.items():
            c = fj[fn] * mir
            parent = side + "Hand"
            for i, sg in enumerate(segs):
                nm = side + fn + sg
                T.append((nm, c[i], c[i + 1], parent))
                parent = nm
        T.append((side + "UpperLeg", J["UpperLeg"] * mir, J["LowerLeg"] * mir, "Hips"))
        T.append((side + "LowerLeg", J["LowerLeg"] * mir, J["Foot"] * mir, side + "UpperLeg"))
        T.append((side + "Foot", J["Foot"] * mir, J["Toes"] * mir, side + "LowerLeg"))
        T.append((side + "Toes", J["Toes"] * mir, J["ToesEnd"] * mir, side + "Foot"))
    # secondary (non-profile) bones
    for sfx, sx in (("L", 1), ("R", -1)):
        ch = mc_hair.pigtail_chain(sx)
        parent = "Head"
        for i in range(3):
            nm = "Pigtail%s%d" % (sfx, i + 1)
            T.append((nm, ch[i], ch[i + 1], parent))
            parent = nm
        T.append(("JacketFront" + sfx, V(sx * 0.170, -0.045, 1.215), V(sx * 0.150, -0.050, 0.960), "Chest"))
    T.append(("JacketBack", V(0, 0.125, 1.195), V(0, 0.122, 0.955), "Chest"))
    for i, nm in enumerate(("StrapA", "StrapB")):
        c = mc_kit.strap_chain(i)
        mid = 0.5 * (c[1] + c[2])
        T.append((nm + "1", c[0], mid, "Hips"))
        T.append((nm + "2", mid, c[3], nm + "1"))
    return T


def build_armature():
    ref = json.load(open(os.path.join(HERE, "godot_humanoid_ref.json")))
    arm = bpy.data.armatures.new("Rig")
    rig = bpy.data.objects.new("Rig", arm)
    bpy.context.scene.collection.objects.link(rig)
    activate(rig)
    bpy.ops.object.mode_set(mode='EDIT')
    for (name, head, tail, parent) in bone_table():
        b = arm.edit_bones.new(name)
        b.head = Vector(head)
        b.tail = Vector(tail)
        if parent:
            b.parent = arm.edit_bones[parent]
            b.use_connect = (Vector(head) - b.parent.tail).length < 1e-5
        if name in ref:
            gz = ref[name]["z"]
            b.align_roll(Vector((gz[0], -gz[2], gz[1])))       # Godot (x,y,z) -> Blender (x,-z,y)
        else:
            b.align_roll(Vector((0, -1, 0)) if abs(b.vector.normalized().y) < 0.9 else Vector((0, 0, 1)))
    bpy.ops.object.mode_set(mode='OBJECT')
    arm.display_type = 'OCTAHEDRAL'
    rig.show_in_front = True
    return rig


# --------------------------------------------------------------------------- weights

def _chain(P, neck=True):
    z = P[:, 2]
    s0 = sm(0.930, 1.020, z)
    s1 = sm(1.030, 1.120, z)
    s2 = sm(1.130, 1.220, z)
    w = {"Hips": 1 - s0, "Spine": s0 - s1, "Chest": s1 - s2}
    if neck:
        r = np.hypot(P[:, 0], P[:, 1] - neck_centre_y(1.34))
        near = sm(0.080, 0.050, r)
        s3 = sm(1.300, 1.345, z) * near
        s4 = sm(1.372, 1.412, z) * near
        s4 = np.where(z > 1.40, np.maximum(s4, sm(1.40, 1.43, z)), s4)
        s3 = np.maximum(s3, s4)
        w["UpperChest"] = s2 - s3
        w["Neck"] = s3 - s4
        w["Head"] = s4
    else:
        w["UpperChest"] = s2
    return w


def _scale(w, f):
    return {k: v * f for k, v in w.items()}


def _add(a, b):
    out = dict(a)
    for k, v in b.items():
        out[k] = out.get(k, 0) + v
    return out


def _sided(name_fn, wL_total, P):
    """Split a per-side weight by the sign of x."""
    left = P[:, 0] >= 0
    return {name_fn("Left"): np.where(left, wL_total, 0.0), name_fn("Right"): np.where(~left, wL_total, 0.0)}


def w_body(P):
    """Torso chain + shoulders + arms (skin, top, chest strap)."""
    ax = np.abs(P[:, 0])
    z = P[:, 2]
    # the arm takes over across the deltoid; lower on the armpit side so the pit folds cleanly
    arm = sm(0.100, 0.186, ax + 0.25 * np.clip(1.30 - z, -0.04, 0.05))
    arm = np.where(z < 1.20, 0.0, arm)
    lower = sm(0.340, 0.410, ax)
    hand = sm(0.590, 0.618, ax)
    w = _scale(_chain(P), 1 - arm)
    sh = sm(0.030, 0.105, ax) * sm(1.215, 1.275, z) * 0.55
    uc = w["UpperChest"]
    w["UpperChest"] = uc * (1 - sh)
    w = _add(w, _sided(lambda s: s + "Shoulder", uc * sh, P))
    w = _add(w, _sided(lambda s: s + "UpperArm", arm * (1 - lower), P))
    w = _add(w, _sided(lambda s: s + "LowerArm", arm * lower * (1 - hand), P))
    w = _add(w, _sided(lambda s: s + "Hand", arm * lower * hand, P))
    return w


def w_legs(P, boots=False):
    """Hips/spine + legs (pants, boots)."""
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    ax = np.abs(x)
    # the outside of the hip stays with the pelvis a little lower than the inner thigh
    leg = sm(0.905, 0.770, z + 0.10 * np.clip(ax - 0.09, -0.05, 0.07))
    if boots:
        leg = np.ones(len(P))
    knee = sm(0.535, 0.425, z)
    foot = sm(0.150, 0.095, z)
    toes = foot * sm(-0.088, -0.128, y - FOOT_Y) * sm(0.11, 0.07, z)
    # left/right only blend across the crotch; below it each leg is strictly its own side
    wd = 0.0005 + 0.022 * sm(0.735, 0.790, z)
    sl = np.clip((x + wd) / (2 * wd), 0.0, 1.0)
    sl = sl * sl * (3 - 2 * sl)
    w = _scale(_chain(P, neck=False), 1 - leg)
    for side, f in (("Left", sl), ("Right", 1 - sl)):
        w[side + "UpperLeg"] = leg * f * (1 - knee)
        w[side + "LowerLeg"] = leg * f * knee * (1 - foot)
        w[side + "Foot"] = leg * f * knee * (foot - toes)
        w[side + "Toes"] = leg * f * knee * toes
    return w


def w_head_mesh(P):
    z = P[:, 2]
    r = np.hypot(P[:, 0], P[:, 1] - neck_centre_y(1.37))
    neck_zone = sm(NECK_R + 0.014, NECK_R + 0.004, r)
    wn = sm(1.410, 1.368, z) * neck_zone
    return {"Neck": wn, "Head": 1 - wn}


def _along_chain(P, pts):
    """Arc-length coordinate of each point along a polyline (nearest segment)."""
    best_d = np.full(len(P), 1e9)
    best_u = np.zeros(len(P))
    acc = 0.0
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        L = np.linalg.norm(b - a)
        t = ((P - a) @ (b - a)) / (L * L)
        tc = np.clip(t, 0, 1)
        d = np.linalg.norm(P - (a + tc[:, None] * (b - a)), axis=1)
        # allow extrapolation before the first / after the last segment
        tt = np.where(i == 0, np.minimum(t, 1), tc)
        tt = np.where(i == len(pts) - 2, np.maximum(t, 0) if i else t, tt)
        better = d < best_d
        best_u = np.where(better, acc + tt * L, best_u)
        best_d = np.where(better, d, best_d)
        acc += L
    return best_u


def _chain_weights(u, lens, names, d=0.006, d0=0.010, root=None):
    """Blend along a bone chain by arc length u. root: bone that owns u < 0."""
    cuts = np.cumsum(lens)[:-1]
    b0 = sm(-d0, d0, u)
    w = {}
    prev = b0
    for i, nm in enumerate(names):
        nxt = sm(cuts[i] - d, cuts[i] + d, u) * b0 if i < len(cuts) else 0.0
        w[nm] = prev - nxt
        prev = nxt
    if root:
        w[root] = 1 - b0
    return w


def w_hand(ob, side):
    P = get_co(ob)
    sx = 1 if side == "Left" else -1
    Pl = P * V(sx, 1, 1)
    fj = mc_hand.joints_left()
    w = {}
    total = np.zeros(len(P))
    for fn, segs in FINGER_BONES.items():
        g = ob.vertex_groups["tag_" + fn]
        tag = np.zeros(len(P))
        for v in ob.data.vertices:
            for ge in v.groups:
                if ge.group == g.index:
                    tag[v.index] = ge.weight
        c = fj[fn]
        u = _along_chain(Pl, c)
        lens = [np.linalg.norm(c[i + 1] - c[i]) for i in range(3)]
        if fn == "Thumb":
            cw = _chain_weights(u - lens[0] * 0.55, [lens[0] * 0.45, lens[1], lens[2]],
                                [side + fn + s for s in segs], d=0.006, d0=0.012)
        else:
            cw = _chain_weights(u, lens, [side + fn + s for s in segs])
        for k, v in cw.items():
            w[k] = v * tag
            total += v * tag
    w[side + "Hand"] = 1 - total
    return w


def w_pigtails(P):
    w = {}
    for sfx, sx in (("L", 1), ("R", -1)):
        sel = (P[:, 0] * sx) > 0
        ch = mc_hair.pigtail_chain(sx)
        u = _along_chain(P, ch)
        lens = [np.linalg.norm(ch[i + 1] - ch[i]) for i in range(3)]
        cw = _chain_weights(u - 0.012, lens, ["Pigtail%s%d" % (sfx, i + 1) for i in range(3)], d=0.022,
                            d0=0.014, root="Head")
        for k, v in cw.items():
            w[k] = w.get(k, 0) + np.where(sel, v, 0.0)
    return w


def w_sleeve(P):
    ax = np.abs(P[:, 0])
    lower = sm(0.335, 0.415, ax)
    w = _sided(lambda s: s + "UpperArm", 1 - lower, P)
    return _add(w, _sided(lambda s: s + "LowerArm", lower, P))


def w_jacket_body(P):
    z = P[:, 2]
    a = np.degrees(np.abs(np.arctan2(P[:, 0], P[:, 1] - BODY_YC)))      # 0 back .. 180 front
    back = sm(1.210, 1.020, z) * sm(105, 60, a) * 0.85
    front = sm(1.230, 1.030, z) * sm(92, 128, a) * 0.90
    w = _scale(_chain(P, neck=False), 1 - back - front)
    w["JacketBack"] = back
    return _add(w, {"JacketFrontL": np.where(P[:, 0] > 0, front, 0), "JacketFrontR": np.where(P[:, 0] <= 0, front, 0)})


def w_straps(P):
    w = {}
    d_best = np.full(len(P), 1e9)
    which = np.zeros(len(P), dtype=int)
    us = []
    for i in range(2):
        c = mc_kit.strap_chain(i)
        mid = 0.5 * (c[1] + c[2])
        pts = np.array([c[0], mid, c[3]])
        us.append((_along_chain(P, pts), [np.linalg.norm(mid - c[0]), np.linalg.norm(c[3] - mid)]))
        dd = np.min(np.linalg.norm(P[:, None, :] - np.array([c[0], c[1], c[2], c[3]])[None, :, :], axis=2), axis=1)
        which = np.where(dd < d_best, i, which)
        d_best = np.minimum(dd, d_best)
    for i, nm in enumerate(("StrapA", "StrapB")):
        u, lens = us[i]
        cw = _chain_weights(u - 0.02, lens, [nm + "1", nm + "2"], d=0.03, d0=0.02, root="Hips")
        for k, v in cw.items():
            w[k] = w.get(k, 0) + np.where(which == i, v, 0.0)
    return w


def _one(name, n):
    return {name: np.ones(n)}


def weights_for(ob):
    P = get_co(ob)
    n = len(P)
    nm = ob.name
    if nm == "Head":
        return w_head_mesh(P)
    if nm in ("Eyes", "Lashes", "Teeth", "Hair", "Headphones"):
        return _one("Head", n)
    if nm == "Pigtails":
        return w_pigtails(P)
    if nm in ("Body", "Top", "TopTrim", "ChestStrap", "Choker", "Cable"):
        return w_body(P)
    if nm in ("HandL", "HandR"):
        return w_hand(ob, "Left" if nm.endswith("L") else "Right")
    if nm in ("Pants", "PantsTrim"):
        return w_legs(P)
    if nm in ("Boots", "Shins"):
        return w_legs(P, boots=True)
    if nm == "Jacket":
        g = ob.vertex_groups["tag_sleeve"]
        tag = np.zeros(n)
        for v in ob.data.vertices:
            for ge in v.groups:
                if ge.group == g.index:
                    tag[v.index] = ge.weight
        ws, wb = w_sleeve(P), w_jacket_body(P)
        return _add(_scale(ws, (tag > 0.5).astype(float)), _scale(wb, (tag <= 0.5).astype(float)))
    if nm == "JacketTrimSleeve":
        return w_sleeve(P)
    if nm == "JacketTrimBody":
        return w_jacket_body(P)
    if nm == "WristDevices":
        return _sided(lambda s: s + "LowerArm", np.ones(n), P)
    if nm == "BeltKit":
        return _one("Hips", n)
    if nm == "Straps":
        return w_straps(P)
    raise KeyError(nm)


def apply_weights(ob, w, max_inf=4):
    names = list(w.keys())
    M = np.stack([np.broadcast_to(np.asarray(w[k], dtype=np.float64), (len(ob.data.vertices),)) for k in names], axis=1)
    M = np.clip(M, 0, None)
    M[M < 0.004] = 0
    if M.shape[1] > max_inf:
        idx = np.argsort(-M, axis=1)[:, max_inf:]
        np.put_along_axis(M, idx, 0.0, axis=1)
    s = M.sum(axis=1, keepdims=True)
    bad = (s[:, 0] < 1e-6)
    if bad.any():
        raise RuntimeError("%s: %d verts without weights" % (ob.name, int(bad.sum())))
    M = M / s
    for g in list(ob.vertex_groups):
        ob.vertex_groups.remove(g)
    for j, k in enumerate(names):
        col = M[:, j]
        nz = np.nonzero(col)[0]
        if len(nz) == 0:
            continue
        g = ob.vertex_groups.new(name=k)
        for i in nz:
            g.add([int(i)], float(col[i]), 'REPLACE')


def transfer_weights(src, dst):
    """Copy weights from the nearest vertex of src (gloves follow the hand they were made from)."""
    sco = get_co(src)
    kd = KDTree(len(sco))
    for i, p in enumerate(sco):
        kd.insert(Vector(p), i)
    kd.balance()
    names = {g.index: g.name for g in src.vertex_groups}
    for g in list(dst.vertex_groups):
        dst.vertex_groups.remove(g)
    groups = {}
    for v in dst.data.vertices:
        _, i, _ = kd.find(v.co)
        for ge in src.data.vertices[i].groups:
            nm = names[ge.group]
            if nm not in groups:
                groups[nm] = dst.vertex_groups.new(name=nm)
            groups[nm].add([v.index], ge.weight, 'REPLACE')


def skin(obs, rig):
    """Weight every part, join into one mesh `Moxie`, bind to the rig."""
    meshes = []
    for nm, ob in obs.items():
        if nm.startswith("Glove"):
            continue
        apply_weights(ob, weights_for(ob))
        meshes.append(ob)
    for nm in ("GloveL", "GloveR"):
        if nm in obs:
            transfer_weights(obs["Hand" + nm[-1]], obs[nm])
            meshes.append(obs[nm])
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs.get("Body", meshes[0])
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = "Moxie"
    body.data.name = "Moxie"
    body.parent = rig
    md = body.modifiers.new("Armature", 'ARMATURE')
    md.object = rig
    return body


# --------------------------------------------------------------------------- posing helpers

def reset_pose(rig):
    for pb in rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)


def set_pose(rig, spec):
    """spec: {bone: [(axis, degrees), ...]} with axes in ARMATURE REST space ('x','y','z'), applied
    in order. A rotation is expressed as if the parent were still in its rest pose, so the same
    spec reads naturally whatever the parents do. 'loc' entries move a bone: {bone: {'loc': (x,y,z)}}"""
    reset_pose(rig)
    ax = {"x": Vector((1, 0, 0)), "y": Vector((0, 1, 0)), "z": Vector((0, 0, 1))}
    for name, rots in spec.items():
        pb = rig.pose.bones[name]
        R = pb.bone.matrix_local.to_quaternion()
        q = Quaternion()
        loc = None
        for item in rots:
            if item[0] == "loc":
                loc = Vector(item[1])
                continue
            a, deg = item
            q = Quaternion(ax[a], math.radians(deg)) @ q
        pb.rotation_quaternion = R.inverted() @ q @ R
        if loc is not None:
            pb.location = R.inverted() @ loc
    bpy.context.view_layer.update()
