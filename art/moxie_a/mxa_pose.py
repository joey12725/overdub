"""FK posing helpers in armature space (independent of each bone's rest orientation)."""
import bpy, math
from mathutils import Matrix, Vector


def reset(rig):
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()


def rot(rig, bone, axis, deg):
    """Rotate a pose bone about a world/armature-space axis through its head."""
    pb = rig.pose.bones[bone]
    bpy.context.view_layer.update()
    M = pb.matrix.copy()
    h = M.translation.copy()
    R = Matrix.Rotation(math.radians(deg), 4, Vector(axis))
    pb.matrix = Matrix.Translation(h) @ R @ Matrix.Translation(-h) @ M
    bpy.context.view_layer.update()


def move(rig, bone, d):
    pb = rig.pose.bones[bone]
    bpy.context.view_layer.update()
    M = pb.matrix.copy(); M.translation += Vector(d)
    pb.matrix = M
    bpy.context.view_layer.update()


X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)


def fingers(rig, curl, sides=('Left', 'Right')):
    for S in sides:
        s = 1 if S == 'Left' else -1
        for f in ('Index', 'Middle', 'Ring', 'Little'):
            for seg in ('Proximal', 'Intermediate', 'Distal'):
                rot(rig, S + f + seg, Y, curl * s)
        rot(rig, S + 'ThumbMetacarpal', Y, curl * 0.35 * s)
        rot(rig, S + 'ThumbProximal', Z, curl * 0.5 * s)
        rot(rig, S + 'ThumbDistal', Z, curl * 0.6 * s)


def pose(rig, name):
    reset(rig)
    r = lambda b, a, d: rot(rig, b, a, d)
    if name == 'tpose':
        return
    if name == 'relaxed':
        r('LeftUpperArm', Y, 68); r('RightUpperArm', Y, -68)
        r('LeftLowerArm', Z, -18); r('RightLowerArm', Z, 18)
        fingers(rig, 22)
    elif name == 'crouch':
        move(rig, 'Hips', (0, 0.12, -0.45))
        r('Hips', X, 20)
        for S in ('Left', 'Right'):
            s = 1 if S == 'Left' else -1
            r(S + 'UpperLeg', X, -112); r(S + 'UpperLeg', Z, 14 * s)
            r(S + 'LowerLeg', X, 138)
            r(S + 'Foot', X, -8)
        r('Spine', X, 14); r('Chest', X, 10)
        r('LeftUpperArm', Y, 60); r('RightUpperArm', Y, -60)
        r('LeftUpperArm', X, -45); r('RightUpperArm', X, -45)
    elif name == 'arms_up':
        r('LeftShoulder', Y, -22); r('RightShoulder', Y, 22)
        r('LeftUpperArm', Y, -62); r('RightUpperArm', Y, 62)
        r('LeftLowerArm', Y, -12); r('RightLowerArm', Y, 12)
    elif name == 'arms_fwd':
        r('LeftUpperArm', Z, -88); r('RightUpperArm', Z, 88)
        r('LeftLowerArm', Z, -30); r('RightLowerArm', Z, 30)
    elif name == 'stride':
        r('LeftUpperLeg', X, -52); r('LeftLowerLeg', X, 30)
        r('RightUpperLeg', X, 34); r('RightLowerLeg', X, 42)
        r('LeftUpperArm', Y, 70); r('RightUpperArm', Y, -70)
        r('LeftUpperArm', X, 40); r('RightUpperArm', X, -40)
        r('LeftLowerArm', X, -50); r('RightLowerArm', X, -70)
        r('Spine', Z, -10); r('Chest', Z, -8)
    elif name == 'twist':
        for b in ('Spine', 'Chest', 'UpperChest'):
            r(b, Z, 20)
        r('Neck', Z, -30); r('Head', Z, -32); r('Head', X, 8)
        r('LeftUpperArm', Y, 68); r('RightUpperArm', Y, -68)
    elif name == 'fist':
        r('LeftUpperArm', Y, 30); r('RightUpperArm', Y, -30)
        r('LeftLowerArm', Z, -100); r('RightLowerArm', Z, 100)
        fingers(rig, 78)
    elif name == 'attitude':   # R01: hand behind head, hand on hip, weight on one leg
        r('Hips', Y, 6); r('Spine', Y, -5); r('Chest', Y, -4)
        r('LeftUpperArm', Y, -40); r('LeftUpperArm', Z, 25)
        r('LeftLowerArm', Y, -118)
        r('RightUpperArm', Y, -52); r('RightUpperArm', Z, -20)
        r('RightLowerArm', Y, -78); r('RightHand', Y, -10)
        r('LeftUpperLeg', Y, -10); r('RightUpperLeg', Y, 14); r('RightUpperLeg', Z, -18)
        r('Head', Y, -8); r('Head', Z, -12)
        fingers(rig, 30)
    bpy.context.view_layer.update()
