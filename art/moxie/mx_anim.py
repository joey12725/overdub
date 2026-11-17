"""Moxie's actions, authored as key poses on the rig (see mx_rig.expand_pose for the pose format).

Pose ops are rotations in armature axes applied in order, relative to the parent's posed frame:
  ('x', deg)  pitch: + tips an upward bone (spine, neck, head) forward, swings a downward bone
              (thigh, upper arm) BACK; - swings a downward limb forward.
  ('y', deg)  roll about the front-back axis: + lowers her left arm / raises her right arm,
              + tilts the head/spine toward her left... (mirrored for '.S' keys)
  ('z', deg)  yaw: + turns toward her left (counter-clockwise seen from above).
  ('twist', deg) about the bone's own axis; ('bend', deg) flexes elbows/knees/fingers.
Keys ending in '.S' are written for her left side and mirrored to the right.
'hips_loc': armature-space offset of the hips (metres).

Timing: 30 fps. Loops: idle 2.0 s, run 0.6 s, stopped 1.0 s (last key == first key).
One-shots are exactly 1.0 s; light/heavy: wind-up 0-0.4, hit 0.4-0.6, recovery 0.6-1.0.
"""
import math

import bpy

import mx_rig

FPS = 30
LOOPS = {"idle", "run", "stopped"}
ACTION_ORDER = ["idle", "run", "stopped", "light", "heavy", "dodge", "ranged", "interact", "death"]
LENGTHS = {"idle": 2.0, "run": 0.6, "stopped": 1.0}
CONTACT_YAW = {"run": 80, "dodge": 80, "heavy": 60, "death": 70}


TEST_POSES = {
    "crouch": {
        'hips_loc': (0, 0.04, -0.33),
        'hips': [('x', 10)],
        'spine': [('x', 22)],
        'chest': [('x', 8)],
        'head': [('x', -22)],
        'thigh.S': [('x', -105), ('y', 12)],
        'shin.S': [('bend', 128)],
        'foot.S': [('x', -22)],
        'upper_arm.S': [('y', -15), ('x', -40)],
        'forearm.S': [('bend', 60)],
    },
    "raise_arm": {
        'upper_arm.L': [('y', -150)],
        'forearm.L': [('bend', 25)],
        'upper_arm.R': [('y', 30), ('x', -60)],
        'forearm.R': [('bend', 95)],
    },
    "stride": {
        'hips_loc': (0, 0, -0.07),
        'thigh.L': [('x', -48)],
        'shin.L': [('bend', 30)],
        'foot.L': [('x', 15)],
        'thigh.R': [('x', 38)],
        'shin.R': [('bend', 35)],
        'foot.R': [('x', -10)],
        'upper_arm.S': [('y', 25)],
    },
}

ACTIONS = {}   # filled by mx_moves (name -> list of (t, pose))


def _keys(name):
    import mx_moves
    return mx_moves.ACTIONS[name]


def _lowest(body):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    me = ev.to_mesh()
    z = min(v.co.z for v in me.vertices)
    ev.to_mesh_clear()
    return z


def ground(rig, body, pose, info):
    """Shift the hips vertically so the pose's lowest mesh point sits at pose['_lift'] (default 0).

    Keys are authored by eye; this keeps every grounded key exactly on the floor (no sinking feet,
    no hovering) and airborne keys at their stated clearance."""
    lift = pose.get('_lift', 0.0)
    quats, loc = mx_rig.pose_quats(rig, pose, info)
    for pb in rig.pose.bones:
        pb.rotation_quaternion = quats[pb.name]
        pb.location = (0, 0, 0)
    rig.pose.bones['hips'].location = loc
    bpy.context.view_layer.update()
    dz = lift - _lowest(body)
    out = dict(pose)
    hl = pose.get('hips_loc', (0.0, 0.0, 0.0))
    out['hips_loc'] = (hl[0], hl[1], hl[2] + dz)
    return out


# Normalised time ranges in which the character has floor contact: the lowest mesh point is held
# exactly on the floor there. Outside them it may rise (run flight, dive, the fall) but never sink.
GROUND_LOCK = {
    "idle": [(0.0, 1.0)],
    "stopped": [(0.0, 1.0)],
    "light": [(0.0, 1.0)],
    "heavy": [(0.0, 1.0)],
    "ranged": [(0.0, 1.0)],
    "interact": [(0.0, 1.0)],
    "run": [],
    "dodge": [(0.0, 0.16), (0.30, 1.0)],
    "death": [(0.0, 1.0)],
}


def _no_penetration(rig, body, act, name, nframes, info):
    """Bake the hips height on every frame so contact frames sit exactly on the floor and no
    frame sinks below it (between-key sag of interpolated legs)."""
    m = info['hips'][0]
    up_local = m.inverted() @ mx_rig.V(0, 0, 1)
    sc = bpy.context.scene
    lock = GROUND_LOCK.get(name, [])
    loop = name in LOOPS
    for _ in range(3):
        corr = []
        worst = 0.0
        for f in range(nframes + 1):
            sc.frame_set(f)
            low = _lowest(body)
            t = f / nframes
            locked = any(t0 - 1e-6 <= t <= t1 + 1e-6 for t0, t1 in lock)
            dz = -low if locked else max(0.0, -low)
            worst = max(worst, abs(dz))
            corr.append((f, dz, mx_rig.V(*rig.pose.bones['hips'].location)))
        if worst < 0.0015:
            return
        if loop:
            corr[-1] = (nframes, corr[0][1], corr[0][2])
        hb = rig.pose.bones['hips']
        for f, dz, loc in corr:
            hb.location = loc + up_local * dz
            hb.keyframe_insert("location", frame=f, group='hips')


def build_actions(rig, body=None):
    import importlib
    import mx_moves
    importlib.reload(mx_moves)
    info = mx_rig.rest_info(rig)
    grounded = {}
    if rig.animation_data is None:
        rig.animation_data_create()
    for name in ACTION_ORDER:
        keys = mx_moves.ACTIONS[name]
        length = LENGTHS.get(name, 1.0)
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        rig.animation_data.action = act
        prev = {}
        frames = []
        for t, pose in keys:
            if body is not None:
                if id(pose) not in grounded:
                    grounded[id(pose)] = (pose, ground(rig, body, pose, info))
                pose = grounded[id(pose)][1]
            f = round(t * length * FPS)   # whole frames: no un-baked keys between samples
            frames.append(f)
            quats, loc = mx_rig.pose_quats(rig, pose, info)
            for pb in rig.pose.bones:
                q = quats[pb.name]
                if pb.name in prev and prev[pb.name].dot(q) < 0:
                    q = -q
                prev[pb.name] = q
                pb.rotation_quaternion = q
                pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
            hb = rig.pose.bones['hips']
            hb.location = loc
            hb.keyframe_insert("location", frame=f, group='hips')
        act.use_frame_range = True
        act.frame_start = 0
        act.frame_end = length * FPS
        if body is not None:
            _no_penetration(rig, body, act, name, int(round(length * FPS)), info)
        act.use_cyclic = name in LOOPS
        if name in LOOPS:
            for fc in act.fcurves:
                m = fc.modifiers.new('CYCLES')
                m.mode_before = 'REPEAT'
                m.mode_after = 'REPEAT'
        ACTIONS[name] = act
    rig.animation_data.action = None


def floor_report(rig, body):
    """Lowest mesh point per sampled frame of every action (feet should sit at ~0, never below)."""
    dg = bpy.context.evaluated_depsgraph_get()
    for name in ACTION_ORDER:
        lows = []
        for i in range(9):
            show_action(rig, name, i / 8)
            ev = body.evaluated_get(dg)
            me = ev.to_mesh()
            lows.append(min(v.co.z for v in me.vertices))
            ev.to_mesh_clear()
        print("FLOOR %-9s %s" % (name, " ".join("%+.3f" % z for z in lows)))


def show_action(rig, name, t):
    act = bpy.data.actions[name]
    rig.animation_data.action = act
    try:
        if act.slots and rig.animation_data.action_slot is None:
            rig.animation_data.action_slot = act.slots[0]
    except AttributeError:
        pass
    length = LENGTHS.get(name, 1.0)
    f = t * length * FPS
    sc = bpy.context.scene
    sc.frame_set(int(math.floor(f)), subframe=f - math.floor(f))


def clear_pose(rig):
    if rig is None:
        return
    if rig.animation_data:
        rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    bpy.context.view_layer.update()
