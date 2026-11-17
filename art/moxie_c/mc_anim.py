"""Retargets clips from Quaternius' Universal Animation Library (CC0) onto Moxie's humanoid rig
and bakes them as actions named per the game contract.

    blender --background art/moxie_c/moxie_model.blend --python art/moxie_c/mc_anim.py -- <UAL1_Standard.glb>

Retargeting is done in world space: for every mapped bone the source bone's rotation relative to
the source T-pose is applied to Moxie's T-pose rest orientation; the hips translation is scaled by
the leg-length ratio. Both skeletons rest in a T-pose facing -Y, so no manual offsets are needed.
One-shots are resampled to exactly 1.0 s; `light` / `heavy` are re-timed so the wind-up fills
0-40 %, the strike 40-60 % and the recovery 60-100 % (strike = the fast part of the weapon hand).
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

FPS = 30

MAP = {"pelvis": "Hips", "spine_01": "Spine", "spine_02": "Chest", "spine_03": "UpperChest",
       "neck_01": "Neck", "Head": "Head"}
for s, S in (("l", "Left"), ("r", "Right")):
    MAP.update({"clavicle_" + s: S + "Shoulder", "upperarm_" + s: S + "UpperArm",
                "lowerarm_" + s: S + "LowerArm", "hand_" + s: S + "Hand", "thigh_" + s: S + "UpperLeg",
                "calf_" + s: S + "LowerLeg", "foot_" + s: S + "Foot", "ball_" + s: S + "Toes"})
    for f, F in (("index", "Index"), ("middle", "Middle"), ("ring", "Ring"), ("pinky", "Little")):
        for i, seg in enumerate(("Proximal", "Intermediate", "Distal")):
            MAP["%s_0%d_%s" % (f, i + 1, s)] = S + F + seg
    for i, seg in enumerate(("Metacarpal", "Proximal", "Distal")):
        MAP["thumb_0%d_%s" % (i + 1, s)] = S + "Thumb" + seg

# name -> (source action, kind, seconds, options)
CLIPS = [
    ("idle", "Idle_Loop", "loop", 2.0, {}),
    ("run", "Jog_Fwd_Loop", "loop", 0.6, {}),
    ("stopped", "Sword_Idle", "hold", 1.0, {"frame": 0.0}),
    ("light", "Sword_Attack", "strike", 1.0, {}),
    ("heavy", "Sword_Attack", "strike", 1.0, {"heavy": True}),
    ("dodge", "Roll", "oneshot", 1.0, {}),
    ("ranged", "Pistol_Shoot", "oneshot", 1.0, {"lead_in": "Pistol_Idle_Loop"}),
    ("interact", "Interact", "oneshot", 1.0, {}),
    ("death", "Death01", "oneshot", 1.0, {}),
]


def _set_action(ob, act):
    if ob.animation_data is None:
        ob.animation_data_create()
    ob.animation_data.action = act
    try:
        if act is not None and getattr(act, "slots", None) and len(act.slots):
            ob.animation_data.action_slot = act.slots[0]
    except Exception:
        pass


class Source:
    def __init__(self, path):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        self.new = [o for o in bpy.data.objects if o not in before]
        self.arm = [o for o in self.new if o.type == 'ARMATURE'][0]
        self.acts = {a.name: a for a in bpy.data.actions}
        self.W = self.arm.matrix_world.to_3x3()
        self.rest = {b.name: (self.W @ b.matrix_local.to_3x3()) for b in self.arm.data.bones}
        self.rest_hip = self.arm.matrix_world @ self.arm.data.bones["pelvis"].head_local
        self.leg = (self.arm.data.bones["thigh_l"].head_local - self.arm.data.bones["foot_l"].head_local).length

    def sample(self, action, frame):
        """World rotations (3x3) of mapped bones and pelvis position at a (fractional) frame."""
        _set_action(self.arm, self.acts[action])
        sc = bpy.context.scene
        f0 = math.floor(frame)
        sc.frame_set(int(f0), subframe=float(frame - f0))
        bpy.context.view_layer.update()
        out = {}
        for sname in MAP:
            pb = self.arm.pose.bones[sname]
            out[sname] = self.W @ pb.matrix.to_3x3()
        hip = self.arm.matrix_world @ self.arm.pose.bones["pelvis"].matrix.translation
        hand = self.arm.matrix_world @ self.arm.pose.bones["hand_r"].matrix.translation
        return out, hip, hand

    def length(self, action):
        return self.acts[action].frame_range[1]

    def remove(self):
        for o in self.new:
            bpy.data.objects.remove(o, do_unlink=True)
        for a in list(self.acts.values()):
            bpy.data.actions.remove(a)


def strike_window(src, action):
    """(windup_end, strike_end) source frames from the weapon-hand speed profile."""
    L = src.length(action)
    fs = np.linspace(0, L, 80)
    pos = np.array([src.sample(action, f)[2][:] for f in fs])
    sp = np.linalg.norm(np.diff(pos, axis=0), axis=1)
    sp = np.convolve(sp, np.ones(3) / 3, mode="same")
    pk = int(np.argmax(sp))
    thr = sp[pk] * 0.45
    a = pk
    while a > 0 and sp[a - 1] > thr:
        a -= 1
    b = pk
    while b < len(sp) - 1 and sp[b + 1] > thr:
        b += 1
    return float(fs[a]), float(fs[min(b + 1, len(fs) - 1)])


def time_map(src, name, action, kind, seconds, opt):
    """List of source frames, one per target frame (0..N)."""
    n = int(round(seconds * FPS))
    L = src.length(action)
    u = np.linspace(0, 1, n + 1)
    if kind == "hold":
        return [opt.get("frame", 0.0)] * (n + 1)
    if kind == "strike":
        w, s = strike_window(src, action)
        print("  strike window of %s: wind-up ends %.1f, strike ends %.1f of %.1f" % (action, w, s, L))
        return list(np.interp(u, [0, 0.4, 0.6, 1.0], [0, w, s, L]))
    return list(u * L)


def retarget(rig, src, name, action, kind, seconds, opt):
    frames = time_map(src, name, action, kind, seconds, opt)
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    _set_action(rig, act)
    arm = rig.data
    order = [b.name for b in arm.bones if b.name in MAP.values()]
    inv = {v: k for k, v in MAP.items()}
    rest = {b.name: b.matrix_local.to_3x3() for b in arm.bones}
    my_leg = (arm.bones["LeftUpperLeg"].head_local - arm.bones["LeftFoot"].head_local).length
    scale = my_leg / src.leg
    hip_rest = arm.bones["Hips"].head_local.copy()
    prev_q = {}
    heavy = opt.get("heavy", False)
    for k, sf in enumerate(frames):
        rots, hip, _ = src.sample(action, sf)
        posed = {}
        u = k / (len(frames) - 1)
        for bname in order:
            sname = inv[bname]
            D = rots[sname] @ src.rest[sname].inverted()
            M = D @ rest[bname]
            if heavy:
                M = _heavy_layer(bname, u) @ M
            posed[bname] = M
            b = arm.bones[bname]
            if b.parent and b.parent.name in posed:
                base = posed[b.parent.name] @ rest[b.parent.name].inverted() @ rest[bname]
            else:
                base = rest[bname]
            q = (base.inverted() @ M).to_quaternion()
            if bname in prev_q and prev_q[bname].dot(q) < 0:
                q.negate()
            prev_q[bname] = q.copy()
            pb = rig.pose.bones[bname]
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=k)
        d = (hip - src.rest_hip) * scale
        if heavy:
            d = d + _heavy_hips(u)
        pb = rig.pose.bones["Hips"]
        pb.location = rest["Hips"].inverted() @ d
        pb.keyframe_insert("location", frame=k)
    try:
        for fc in act.fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = 'LINEAR'
    except Exception:
        pass
    act.frame_range = (0, len(frames) - 1)
    act["loop"] = kind in ("loop", "hold")
    return act


def _bump(u, a, b, c, d):
    """0 before a, rises to 1 at b, holds to c, falls to 0 at d (smooth)."""
    def s(x):
        x = min(1.0, max(0.0, x))
        return x * x * (3 - 2 * x)
    if u < b:
        return s((u - a) / max(b - a, 1e-6))
    if u < c:
        return 1.0
    return 1.0 - s((u - c) / max(d - c, 1e-6))


def _heavy_layer(bone, u):
    """Extra world-space rotation layered on the sword swing to turn it into a committed heavy
    blow: a deeper coil and lift in the wind-up, a lunge with a forward lean through the strike."""
    wind = _bump(u, 0.02, 0.30, 0.38, 0.47)
    hit = _bump(u, 0.40, 0.52, 0.66, 0.95)
    rz = rx = 0.0
    if bone in ("Spine", "Chest", "UpperChest"):
        rz = -11.0 * wind + 7.0 * hit          # coil toward the weapon side, then through
        rx = 5.0 * wind - 9.0 * hit            # lean back, then drive forward
    elif bone == "RightUpperArm":
        rx = 16.0 * wind
    elif bone == "Hips":
        rz = -6.0 * wind + 4.0 * hit
    if rz == 0.0 and rx == 0.0:
        return Matrix.Identity(3)
    return (Matrix.Rotation(math.radians(rz), 3, 'Z') @ Matrix.Rotation(math.radians(rx), 3, 'X'))


def _heavy_hips(u):
    wind = _bump(u, 0.02, 0.30, 0.38, 0.47)
    hit = _bump(u, 0.40, 0.52, 0.66, 0.95)
    return Vector((0.0, 0.035 * wind - 0.075 * hit, 0.012 * wind - 0.060 * hit))


def main():
    path = sys.argv[sys.argv.index("--") + 1]
    sc = bpy.context.scene
    sc.render.fps = FPS
    rig = bpy.data.objects["Rig"]
    import mc_rig
    mc_rig.reset_pose(rig)
    src = Source(path)
    sc.render.fps = FPS
    # the library was authored at 24 fps; sample it on its own timeline
    made = []
    for (name, action, kind, seconds, opt) in CLIPS:
        act = retarget(rig, src, name, action, kind, seconds, opt)
        made.append(act)
        print("clip %-9s <- %-14s %2d frames (%.2fs)" % (name, action, int(act.frame_range[1]) + 1,
                                                        act.frame_range[1] / FPS))
    src.remove()
    _set_action(rig, bpy.data.actions["idle"])
    sc.frame_set(0)
    for a in list(bpy.data.actions):
        if a not in made:
            bpy.data.actions.remove(a)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "moxie_anim.blend"))
    print("ANIM DONE")


if __name__ == "__main__":
    main()
