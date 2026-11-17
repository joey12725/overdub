"""Armature `Rig`, skinning and the pose-authoring helpers for Moxie.

Bones (contract): root, hips, spine, chest, neck, head, shoulder.L/R, upper_arm.L/R, forearm.L/R,
hand.L/R, thigh.L/R, shin.L/R, foot.L/R, toe.L/R, pigtail.L/R.001-003, jacket.L/R.
Helpers: fingers.L/R.001-002 (a mitten chain for the four fingers), thumb.L/R, jacket.B (back
flap), grip.R (weapon socket: head at the centre of the right fist, +Y along the blade direction
out of the thumb side, +Z toward the back of the hand).

Skinning is computed, not painted: each mesh part is tagged (`wspec`) with the body region it
belongs to, and a weighter per region assigns smooth, normalised weights along the bone chain
that region follows (joint blend widths tuned per region: tight for skin, wide for the bunched
sleeves and baggy pants so cloth bends without collapsing), rigid weights for hard gear
(headphones, Walkman, boots, wrist devices), and blended secondary bones for the jacket flaps,
pigtails and hanging straps.
"""
import math

import bpy
from mathutils import Matrix, Quaternion, Vector

import mx_skel as S
from mx_body import hand_frame
from mx_geo import V, smoothstep
from mx_hair import pigtail_layout as _pigtail_layout


def pigtail_layout():
    tie, chain = _pigtail_layout()
    return S.head_xform(tie), [S.head_xform(p) for p in chain]

BONES = []   # (name, head, tail, parent, deform)


def _hand_points():
    fr = hand_frame()
    tb = fr @ V(-0.004, 0.010, 0.026)
    tt = fr @ V(-0.018, 0.072, 0.050)
    fmid = S.KNUCKLE + S.HAND_DIR * (S.FINGER_LEN * 0.5)
    fist = fr @ V(-0.016, 0.062, 0.004)
    thumb_side = (fr.to_3x3() @ V(0, 0, 1)).normalized()
    dorsal = (fr.to_3x3() @ V(1, 0, 0)).normalized()
    return tb, tt, fmid, fist, thumb_side, dorsal


def bone_table():
    tie, chain = pigtail_layout()
    tb, tt, fmid, fist, thumb_side, dorsal = _hand_points()
    L = [
        ("root", V(0, 0, 0), V(0, 0.18, 0), None),
        ("hips", S.HIPS, S.SPINE, "root"),
        ("spine", S.SPINE, S.CHEST, "hips"),
        ("chest", S.CHEST, S.NECK, "spine"),
        ("neck", S.NECK, S.HEAD, "chest"),
        ("head", S.HEAD, S.head_xform(S.HEAD_TOP), "neck"),
        ("jacket.B", V(0, 0.115, 1.12), V(0, 0.135, 0.88), "chest"),
    ]
    sides = []
    for s in ("L", "R"):
        m = (lambda p: p.copy()) if s == "L" else S.mirror
        sides += [
            ("shoulder." + s, m(S.SHOULDER_IN), m(S.SHOULDER_JOINT), "chest"),
            ("upper_arm." + s, m(S.SHOULDER_JOINT), m(S.ELBOW), "shoulder." + s),
            ("forearm." + s, m(S.ELBOW), m(S.WRIST), "upper_arm." + s),
            ("hand." + s, m(S.WRIST), m(S.KNUCKLE), "forearm." + s),
            ("fingers.%s.001" % s, m(S.KNUCKLE), m(fmid), "hand." + s),
            ("fingers.%s.002" % s, m(fmid), m(S.FINGER_TIP), "fingers.%s.001" % s),
            ("thumb." + s, m(tb), m(tt), "hand." + s),
            ("thigh." + s, m(S.HIP_JOINT), m(S.KNEE), "hips"),
            ("shin." + s, m(S.KNEE), m(S.ANKLE), "thigh." + s),
            ("foot." + s, m(S.ANKLE), m(S.BALL), "shin." + s),
            ("toe." + s, m(S.BALL), m(S.TOE_TIP), "foot." + s),
            ("pigtail.%s.001" % s, m(chain[0]), m(chain[1]), "head"),
            ("pigtail.%s.002" % s, m(chain[1]), m(chain[3]), "pigtail.%s.001" % s),
            ("pigtail.%s.003" % s, m(chain[3]), m(chain[4]), "pigtail.%s.002" % s),
            ("jacket." + s, m(V(0.205, 0.050, 1.120)), m(V(0.215, 0.070, 0.880)), "chest"),
        ]
    grip_head = S.mirror(fist)
    grip_tail = grip_head + S.mirror(thumb_side) * 0.10
    sides.append(("grip.R", grip_head, grip_tail, "hand.R"))
    return L + sides


def build_armature():
    arm_data = bpy.data.armatures.new("Rig")
    rig = bpy.data.objects.new("Rig", arm_data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm_data.edit_bones
    _, _, _, _, thumb_side, dorsal = _hand_points()
    for name, h, t, parent in bone_table():
        b = eb.new(name)
        # bones go through the same proportion stage as the meshes (mx_skel.warp); the hand chain
        # is rigid, like the hand meshes
        anchor = S.RIGID_ANCHOR["hand"] if name.startswith(("hand", "fingers", "thumb", "grip")) else None
        b.head, b.tail = S.warp_point(h, anchor), S.warp_point(t, anchor)
        if parent:
            b.parent = eb[parent]
            b.use_connect = False
        # consistent rolls: arm bones' local +Z points to the back of the hand
        if name.startswith(("upper_arm", "forearm", "hand", "fingers", "thumb")):
            b.align_roll(dorsal if ".L" in name else S.mirror(dorsal))
        elif name.startswith(("thigh", "shin", "foot", "toe")):
            b.align_roll(V(0, -1, 0) if not name.startswith(("foot", "toe")) else V(0, 0, 1))
        elif name == "grip.R":
            b.align_roll(S.mirror(dorsal))
        else:
            b.align_roll(V(0, -1, 0) if abs((t - h).normalized().z) > 0.5 else V(0, 0, 1))
        b.use_deform = name not in ("root", "grip.R")
    bpy.ops.object.mode_set(mode='OBJECT')
    rig.data.display_type = 'STICK'
    for pb in rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    return rig


# --------------------------------------------------------------------------------------------
# weighting
# --------------------------------------------------------------------------------------------

def chain(u, joints, widths, bones):
    """Smooth partition of unity along a 1-D coordinate. len(bones) == len(joints) + 1."""
    ts = [smoothstep(j - w, j + w, u) for j, w in zip(joints, widths)]
    out = {}
    prev = 1.0
    for i, b in enumerate(bones):
        t = ts[i] if i < len(ts) else 0.0
        w = prev - t
        if w > 1e-4:
            out[b] = out.get(b, 0.0) + w
        prev = t
    return out


def arm_coord(v, s):
    p = v if s == "L" else S.mirror(v)
    d1 = (p - S.SHOULDER_JOINT).dot(S.ARM_DIR)
    if d1 <= S.UPPER_ARM_LEN:
        return d1, p
    return S.UPPER_ARM_LEN + (p - S.ELBOW).dot(S.FOREARM_DIR), p


def w_arm(v, s, elbow_w=0.030, shoulder_w=0.035):
    d, _ = arm_coord(v, s)
    lw = S.UPPER_ARM_LEN + S.FOREARM_LEN
    w = chain(d, [-0.012, S.UPPER_ARM_LEN, lw - 0.002], [shoulder_w, elbow_w, 0.016],
              ["shoulder." + s, "upper_arm." + s, "forearm." + s, "hand." + s])
    # deep inside the torso the arm root follows the chest a little
    if d < -0.03:
        k = smoothstep(-0.03, -0.06, d) * 0.5
        w = {b: x * (1 - k) for b, x in w.items()}
        w["chest"] = w.get("chest", 0.0) + k
    return w


def w_torso(v):
    w = chain(v.z, [0.905, 1.030, 1.262], [0.045, 0.050, 0.020], ["hips", "spine", "chest", "neck"])
    # shoulder region follows the shoulder bones
    ax = abs(v.x)
    k = smoothstep(0.080, 0.145, ax) * smoothstep(1.150, 1.215, v.z)
    if k > 0:
        s = "L" if v.x > 0 else "R"
        w = {b: x * (1 - k) for b, x in w.items()}
        ka = smoothstep(0.135, 0.180, ax)
        w["shoulder." + s] = w.get("shoulder." + s, 0.0) + k * (1 - ka * 0.6)
        w["upper_arm." + s] = w.get("upper_arm." + s, 0.0) + k * ka * 0.6
    return w


def w_neck(v):
    return chain(v.z, [1.262, 1.36], [0.020, 0.030], ["chest", "neck", "head"])


def w_leg(v, s):
    w = chain(-v.z, [-0.80, -S.KNEE.z, -S.ANKLE.z - 0.02], [0.05, 0.055, 0.03],
              ["hips", "thigh." + s, "shin." + s, "foot." + s])
    return w


def w_pants(v):
    """The one-piece pants: each half follows its leg chain; toward the crotch seam the thigh share
    is split between both thighs so the seam stays put when the legs spread."""
    s = "L" if v.x >= 0 else "R"
    o = "R" if s == "L" else "L"
    w = w_leg(v, s)
    k = 0.5 + 0.5 * smoothstep(0.0, 0.07, abs(v.x))
    th = w.get("thigh." + s, 0.0)
    if th > 0 and k < 1.0:
        w["thigh." + s] = th * k
        w["thigh." + o] = th * (1 - k)
    return w


def w_pelvis(v):
    k = smoothstep(0.81, 0.73, v.z) * smoothstep(0.0, 0.07, abs(v.x))
    w = {"hips": 1.0 - k}
    if k > 0:
        s = "L" if v.x > 0 else "R"
        w["thigh." + s] = k
    return w


def w_foot(v, s):
    p = v if s == "L" else S.mirror(v)
    t = smoothstep(S.BALL.y + 0.025, S.BALL.y - 0.015, p.y) * smoothstep(0.10, 0.07, p.z)
    up = smoothstep(0.135, 0.20, p.z)
    w = {"foot." + s: (1 - t) * (1 - up), "toe." + s: t * (1 - up), "shin." + s: up}
    return w


def w_hand(v, s, obj_name):
    p = v if s == "L" else S.mirror(v)
    fr = hand_frame().inverted()
    loc = fr @ p
    if obj_name.startswith("thumb"):
        k = smoothstep(0.012, 0.030, loc.y)
        return {"hand." + s: 1 - k, "thumb." + s: k}
    if obj_name.startswith("finger"):
        return chain(loc.y, [0.082, 0.082 + S.FINGER_LEN * 0.5], [0.010, 0.010],
                     ["hand." + s, "fingers.%s.001" % s, "fingers.%s.002" % s])
    # palm / glove cuff: wrist blend into the forearm
    return chain(loc.y, [0.000], [0.014], ["forearm." + s, "hand." + s])


def w_pigtail(v, s):
    tie, ch = pigtail_layout()
    p = v if s == "L" else S.mirror(v)
    # project onto the bone chain polyline
    pts = [ch[0], ch[1], ch[3], ch[4]]
    best, bu = 1e9, 0.0
    acc = 0.0
    joints = []
    for a, b in zip(pts, pts[1:]):
        seg = b - a
        ln = seg.length
        t = max(0.0, min(1.0, (p - a).dot(seg) / (ln * ln)))
        d = (a + seg * t - p).length
        if d < best:
            best, bu = d, acc + t * ln
        acc += ln
        joints.append(acc)
    return chain(bu, [0.008, joints[0], joints[1]], [0.010, 0.020, 0.025],
                 ["head", "pigtail.%s.001" % s, "pigtail.%s.002" % s, "pigtail.%s.003" % s])


def w_jacket(v):
    h = smoothstep(1.13, 0.88, v.z)
    ax = abs(v.x)
    s = "L" if v.x > 0 else "R"
    arm = smoothstep(0.16, 0.24, ax) * smoothstep(1.02, 1.14, v.z) * 0.55
    back = smoothstep(0.02, 0.10, v.y) * smoothstep(0.17, 0.05, ax)
    sec = h * 0.75
    w = {}
    w["jacket.B"] = sec * back
    w["jacket." + s] = sec * (1 - back)
    if arm > 0:
        w["upper_arm." + s] = arm
    rest = max(0.0, 1.0 - sum(w.values()))
    w["chest"] = rest * smoothstep(0.92, 1.02, v.z) + 0.0
    w["spine"] = rest * (1 - smoothstep(0.92, 1.02, v.z))
    return w


def w_cable(v):
    if v.z > 1.30 and v.y > -0.05:
        k = smoothstep(1.32, 1.39, v.z)
        return {"neck": 1 - k, "head": k}
    return chain(v.z, [0.94, 1.04, 1.25, 1.33], [0.03, 0.05, 0.03, 0.03], ["hips", "spine", "chest", "neck", "head"])


def w_hangstrap(v):
    """Loose webbing at her right hip: rides the hips at the clip, the thigh down the leg, and
    below the knee shares the shin so the tail swings with the lower leg."""
    k = smoothstep(0.84, 0.70, v.z)
    sh = smoothstep(0.50, 0.40, v.z) * 0.45
    return {"hips": 1 - k, "thigh.R": k * (1 - sh), "shin.R": k * sh}


def weights_for(obj, v):
    spec = obj.get("wspec", "")
    side = spec[-1] if spec.endswith((".L", ".R")) else None
    base = spec[:-2] if side else spec
    if base == "torso":
        return w_torso(v)
    if base == "neck":
        return w_neck(v)
    if base in ("head", "pigroot"):
        return {"head": 1.0}
    if base == "arm":
        return w_arm(v, side)
    if base == "sleeve":
        return w_arm(v, side, elbow_w=0.060, shoulder_w=0.05)
    if base == "forearm":
        return {"forearm." + side: 1.0}
    if base == "hand":
        return w_hand(v, side, obj.name)
    if base == "leg":
        return w_leg(v, side)
    if base == "pelvis":
        return w_pelvis(v)
    if base == "pants":
        return w_pants(v)
    if base == "foot":
        return w_foot(v, side)
    if base == "pigtail":
        return w_pigtail(v, side)
    if base == "jacket":
        return w_jacket(v)
    if base == "cable":
        return w_cable(v)
    if base == "hangstrap":
        return w_hangstrap(v)
    raise ValueError("no weighter for %s (%s)" % (obj.name, spec))


def skin_parts(parts, max_influences=4):
    for obj in parts:
        groups = {}
        for v in obj.data.vertices:
            w = weights_for(obj, v.co)
            items = sorted(((x, b) for b, x in w.items() if x > 1e-3), reverse=True)[:max_influences]
            tot = sum(x for x, _ in items)
            for x, b in items:
                g = groups.get(b)
                if g is None:
                    g = obj.vertex_groups.get(b) or obj.vertex_groups.new(name=b)
                    groups[b] = g
                g.add([v.index], x / tot, 'REPLACE')


def bind(mesh_obj, rig):
    mesh_obj.parent = rig
    mod = mesh_obj.modifiers.new("Armature", 'ARMATURE')
    mod.object = rig
    mod.use_vertex_groups = True


# --------------------------------------------------------------------------------------------
# posing
# --------------------------------------------------------------------------------------------

BEND_FWD = {"forearm": V(0, -1, 0), "shin": V(0, 1, 0), "thumb": None}


def rest_info(rig):
    info = {}
    for b in rig.data.bones:
        m = b.matrix_local.to_3x3()
        d = (b.tail_local - b.head_local).normalized()
        info[b.name] = (m, d)
    return info


def _axis_rot(axis, deg):
    return Quaternion(Vector(axis).normalized(), math.radians(deg))


def op_quat(name, op, info):
    kind, deg = op
    m, d = info[name]
    if kind == 'x':
        return _axis_rot((1, 0, 0), deg)
    if kind == 'y':
        return _axis_rot((0, 1, 0), deg)
    if kind == 'z':
        return _axis_rot((0, 0, 1), deg)
    if kind == 'twist':
        return _axis_rot(d, deg)
    if kind == 'bend':
        base = name.split(".")[0]
        if base in ("forearm",):
            f = V(0, -1, 0)
        elif base in ("shin",):
            f = V(0, 1, 0)
        elif base in ("fingers", "thumb", "hand"):
            f = -(m @ V(0, 0, 1)) if ".L" in name else -(m @ V(0, 0, 1))
        else:
            f = V(0, -1, 0)
        ax = d.cross(f)
        if ax.length < 1e-6:
            ax = V(1, 0, 0)
        return _axis_rot(ax, deg)
    raise ValueError(kind)


def mirror_ops(ops):
    out = []
    for k, a in ops:
        if k in ('y', 'z', 'twist'):
            out.append((k, -a))
        else:
            out.append((k, a))
    return out


def expand_pose(pose):
    """Pose dict: bone -> list of ops; keys ending in '.S' mean 'L and mirrored R'.

    Keys 'X.L' / 'X.R' are taken as given. Special key 'hips_loc' -> armature-space offset.
    """
    out = {}
    for k, v in pose.items():
        if k.startswith('_'):
            continue
        if k == 'hips_loc':
            out[k] = v
        elif k.endswith(".S"):
            base = k[:-2]
            out.setdefault(base + ".L", []).extend(v)
            out.setdefault(base + ".R", []).extend(mirror_ops(v))
        elif ".S." in k:
            out.setdefault(k.replace(".S.", ".L."), []).extend(v)
            out.setdefault(k.replace(".S.", ".R."), []).extend(mirror_ops(v))
        else:
            out.setdefault(k, []).extend(v)
    return out


def pose_quats(rig, pose, info=None):
    """Return {bone: local quaternion} and the hips location (local) for a pose dict."""
    info = info or rest_info(rig)
    p = expand_pose(pose)
    quats = {}
    for name in info:
        ops = p.get(name, [])
        D = Quaternion()
        for op in ops:
            D = op_quat(name, op, info) @ D
        m = info[name][0]
        R = m.to_quaternion()
        quats[name] = R.inverted() @ D @ R
    loc = V(0, 0, 0)
    if 'hips_loc' in p:
        m = info['hips'][0]
        loc = m.inverted() @ Vector(p['hips_loc'])
    return quats, loc


def apply_pose(rig, pose):
    quats, loc = pose_quats(rig, pose)
    for pb in rig.pose.bones:
        pb.rotation_quaternion = quats[pb.name]
        pb.location = (0, 0, 0)
    rig.pose.bones['hips'].location = loc
    bpy.context.view_layer.update()
