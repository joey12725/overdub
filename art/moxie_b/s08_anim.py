"""Stage 8: retarget off-the-shelf humanoid animation onto the Rig.

Source: Quaternius - Universal Animation Library (Standard), CC0 (see LICENSES.md), a Rigify-style
skeleton (DEF-hips, DEF-spine.001 ...). Retargeting is done in armature space:
    W_target(t) = W_source(t) * W_source(ref)^-1 * W_target(rest)
where the source reference pose is its T-pose clip with every bone direction-aligned to our rest
pose (so A/T-pose, leg-splay and toe-out differences cancel). Hips translation is scaled by hip height.
Loops keep their natural length; one-shots are re-timed to exactly 1.0 s, and the two melee clips are
time-warped so the wind-up fills 0-40 %, the strike lands in 40-60 % and the recovery fills 60-100 %.
Only profile bones are keyed (secondary bones are left to the game's secondary motion).
Outputs _stage/s08_anim.blend with actions idle, run, stopped, light, heavy, dodge, ranged, interact, death.
"""
import bpy, sys, os, json, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mb_util as U
from mathutils import Vector, Matrix, Quaternion

U.open_stage("s07_rig")
sc = bpy.context.scene
sc.render.fps = 30
rig = bpy.data.objects["Rig"]
SRC = os.path.join(U.HERE, "_dl", "ual", "AnimationLibrary_Godot_Standard.gltf")
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=SRC)
new = [o for o in bpy.data.objects if o not in before]
src = [o for o in new if o.type == 'ARMATURE'][0]
src.name = "UAL_Source"
for o in new:
    if o.type == 'MESH':
        o.hide_render = True
        o.hide_viewport = True
print("source bones", len(src.data.bones), "actions", len(bpy.data.actions))

BMAP = {"Hips": "DEF-hips", "Spine": "DEF-spine.001", "Chest": "DEF-spine.002", "UpperChest": "DEF-spine.003", "Neck": "DEF-neck", "Head": "DEF-head"}
for side, s in (("Left", "L"), ("Right", "R")):
    BMAP.update({side + "Shoulder": "DEF-shoulder." + s, side + "UpperArm": "DEF-upper_arm." + s, side + "LowerArm": "DEF-forearm." + s,
                 side + "Hand": "DEF-hand." + s, side + "UpperLeg": "DEF-thigh." + s, side + "LowerLeg": "DEF-shin." + s,
                 side + "Foot": "DEF-foot." + s, side + "Toes": "DEF-toe." + s,
                 side + "ThumbMetacarpal": "DEF-thumb.01." + s, side + "ThumbProximal": "DEF-thumb.02." + s, side + "ThumbDistal": "DEF-thumb.03." + s})
    for f, sf in (("Index", "f_index"), ("Middle", "f_middle"), ("Ring", "f_ring"), ("Little", "f_pinky")):
        for seg, k in (("Proximal", "01"), ("Intermediate", "02"), ("Distal", "03")):
            BMAP[side + f + seg] = "DEF-%s.%s.%s" % (sf, k, s)
missing = [v for v in BMAP.values() if v not in src.data.bones]
assert not missing, missing

# hierarchy order of our bones
order = [b.name for b in rig.data.bones]            # armature bones are stored parents-first
M = {b.name: b.matrix_local.to_3x3() for b in rig.data.bones}
PAR = {b.name: (b.parent.name if b.parent else None) for b in rig.data.bones}
HEAD = {b.name: b.head_local.copy() for b in rig.data.bones}


def set_action(obj, act):
    if obj.animation_data is None:
        obj.animation_data_create()
    obj.animation_data.action = act
    try:
        if act is not None and obj.animation_data.action_slot is None and len(act.slots):
            obj.animation_data.action_slot = act.slots[0]
    except Exception:
        pass


if src.animation_data:
    for tr in list(src.animation_data.nla_tracks):
        src.animation_data.nla_tracks.remove(tr)


def sample(act_name, frames):
    """Armature-space rotation + head position of every mapped source bone at the given frames."""
    act = bpy.data.actions[act_name]
    set_action(src, act)
    out = []
    for f in frames:
        sc.frame_set(int(math.floor(f)), subframe=f - math.floor(f))
        d = {}
        for tb, sb in BMAP.items():
            pm = src.pose.bones[sb].matrix
            d[tb] = (pm.to_3x3().normalized(), pm.translation.copy())
        out.append(d)
    return out, act


# ---- reference pose
ref = sample("A_TPose", [bpy.data.actions["A_TPose"].frame_range[0]])[0][0]
REF = {}
for tb in BMAP:
    Rs, ps = ref[tb]
    sdir = (Rs @ Vector((0, 1, 0))).normalized()
    tdir = (M[tb] @ Vector((0, 1, 0))).normalized()
    q = sdir.rotation_difference(tdir).to_matrix()
    REF[tb] = (q @ Rs)
    if tb in ("LeftUpperArm", "LeftUpperLeg", "LeftFoot", "LeftHand", "Spine"):
        print("ref check", tb, "src dir", tuple(round(c, 2) for c in sdir), "tgt dir", tuple(round(c, 2) for c in tdir))
hip_scale = HEAD["Hips"].z / ref["Hips"][1].z
print("hip scale", hip_scale, "src hips", tuple(ref["Hips"][1]))
SRC_HIP_REF = ref["Hips"][1].copy()



def bake(name, src_clip, times, hold=False, loop=False):
    """times: source frames to sample, one per output frame (30 fps)."""
    samples, sact = sample(src_clip, times)
    act = bpy.data.actions.new(name)
    set_action(rig, act)
    for pb in rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    prevq = {}
    for fi, smp in enumerate(samples):
        W = {}
        for b in order:
            p = PAR[b]
            if b in BMAP:
                Rs, ps = smp[b]
                W[b] = (Rs @ REF[b].inverted()) @ M[b]
            else:
                W[b] = (W[p] @ (M[p].inverted() @ M[b])) if p else M[b]
        for b in BMAP:
            p = PAR[b]
            rel = M[p].inverted() @ M[b]
            Q = (rel.inverted() @ W[p].inverted() @ W[b]).to_quaternion()
            if b in prevq and prevq[b].dot(Q) < 0:
                Q.negate()
            prevq[b] = Q.copy()
            pb = rig.pose.bones[b]
            pb.rotation_quaternion = Q
            pb.keyframe_insert("rotation_quaternion", frame=fi)
            if b == "Hips":
                d = (smp[b][1] - SRC_HIP_REF) * hip_scale
                if not loop:
                    pass
                pb.location = M[b].inverted() @ d
                pb.keyframe_insert("location", frame=fi)
    act.use_fake_user = True
    act["source_clip"] = src_clip
    act["loop"] = loop
    for fc in act.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = 'LINEAR'
    return act


def frange(act_name):
    a, b = bpy.data.actions[act_name].frame_range
    return float(a), float(b)


def hand_speed(clip, bone):
    a, b = frange(clip)
    fr = np.arange(a, b + 0.001, 1.0)
    smp, _ = sample(clip, fr)
    pos = np.array([s[bone][1][:] for s in smp])
    hip = np.array([s["Hips"][1][:] for s in smp])
    rel = pos - hip
    v = np.linalg.norm(np.diff(rel, axis=0), axis=1)
    return fr, v


def strike_phases(clip):
    """Returns (hand, frames a, windup end, strike end, b) from the faster hand's speed profile."""
    best = None
    for hand in ("RightHand", "LeftHand"):
        fr, v = hand_speed(clip, hand)
        if best is None or v.max() > best[2].max():
            best = (hand, fr, v)
    hand, fr, v = best
    k = int(np.argmax(v))
    thr = 0.45 * v[k]
    i0 = k
    while i0 > 0 and v[i0 - 1] > thr:
        i0 -= 1
    i1 = k
    while i1 < len(v) - 1 and v[i1 + 1] > thr:
        i1 += 1
    return hand, fr[0], fr[i0], fr[min(i1 + 2, len(fr) - 1)], fr[-1]


def warp_times(a, w, s, b, n=30):
    """n+1 source frames: [a,w] -> 0..40 %, [w,s] -> 40..60 %, [s,b] -> 60..100 %."""
    out = []
    for i in range(n + 1):
        u = i / n
        if u <= 0.4:
            out.append(a + (w - a) * (u / 0.4))
        elif u <= 0.6:
            out.append(w + (s - w) * ((u - 0.4) / 0.2))
        else:
            out.append(s + (b - s) * ((u - 0.6) / 0.4))
    return out


report = {}
# loops at natural speed
for name, clip in (("idle", "Idle_Loop"), ("run", "Jog_Fwd_Loop")):
    a, b = frange(clip)
    times = list(np.arange(a, b + 0.001, 1.0))
    bake(name, clip, times, loop=True)
    report[name] = {"source": clip, "frames": len(times), "seconds": (len(times) - 1) / 30.0}
# stopped: a held ready pose (first frame of the sword-ready idle), 1.0 s
a, b = frange("Sword_Idle")
bake("stopped", "Sword_Idle", [a] * 31, loop=True)
report["stopped"] = {"source": "Sword_Idle (frame 0 held)", "frames": 31, "seconds": 1.0}
# melee: time-warped
for name, clip in (("light", "Punch_Cross"), ("heavy", "Sword_Attack")):
    hand, a, w, s, b = strike_phases(clip)
    bake(name, clip, warp_times(a, w, s, b))
    report[name] = {"source": clip, "hand": hand, "src_frames": [a, w, s, b], "seconds": 1.0}
# other one-shots: uniform re-time to 1.0 s
for name, clip in (("dodge", "Roll"), ("ranged", "Spell_Simple_Shoot"), ("interact", "Interact"), ("death", "Death01")):
    a, b = frange(clip)
    bake(name, clip, [a + (b - a) * i / 30 for i in range(31)])
    report[name] = {"source": clip, "src_frames": [a, b], "seconds": 1.0}
print("REPORT", json.dumps(report))
with open(os.path.join(U.STAGE, "anim_report.json"), "w") as fh:
    json.dump(report, fh, indent=1)

# clean up the source
set_action(rig, None)
for pb in rig.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)
for o in new:
    bpy.data.objects.remove(o)
keep = set(report.keys())
for a_ in list(bpy.data.actions):
    if a_.name not in keep:
        bpy.data.actions.remove(a_)
for blk in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.images):
    for d in list(blk):
        if d.users == 0:
            blk.remove(d)
U.save_stage("s08_anim")
