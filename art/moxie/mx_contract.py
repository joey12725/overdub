"""Bring the authored rig to the asset contract in docs/GODOT-PORT.md before export.

The model, weights and actions are authored on an A-pose rig with short descriptive bone names
(mx_rig / mx_moves). The contract asks for Godot's SkeletonProfileHumanoid bone names and a clean
T-pose rest. This module:

1. splits the chest bone into `Chest` + `UpperChest` (the profile has both): the shoulders, neck
   and jacket bones re-parent to UpperChest, and the chest weights are shared between the two by
   height. UpperChest carries no keys, so it rigidly follows Chest and every action is unchanged;
2. renames every bone (and its vertex group and the F-curves of every action) to the profile
   names - the mitten finger chain maps to the middle finger, the thumb to the thumb's proximal
   bone; secondary bones keep descriptive names (pigtail.*, jacket.*) and the weapon socket
   becomes RightHandGrip;
3. poses the rig into a T-pose (arms, hands and fingers straight out along +-X, palms down) for
   export with `export_rest_position_armature=False`: the glTF joint nodes - Godot's Skeleton3D
   rests - get the T-pose, while the skin's inverse bind matrices keep the A-pose the mesh was
   bound in. Skinning and every animation stay exact (animation channels are absolute local
   transforms, independent of which rest the nodes carry), and a humanoid clip retargeted in
   Godot sees a clean T-pose rest.
"""
import bpy
from mathutils import Matrix, Vector

from mx_geo import smoothstep

PROFILE = {
    "root": "Root", "hips": "Hips", "spine": "Spine", "chest": "Chest", "neck": "Neck", "head": "Head",
    "grip.R": "RightHandGrip",
}
for _s, _side in (("L", "Left"), ("R", "Right")):
    PROFILE.update({
        "shoulder." + _s: _side + "Shoulder",
        "upper_arm." + _s: _side + "UpperArm",
        "forearm." + _s: _side + "LowerArm",
        "hand." + _s: _side + "Hand",
        "fingers.%s.001" % _s: _side + "MiddleProximal",
        "fingers.%s.002" % _s: _side + "MiddleIntermediate",
        "thumb." + _s: _side + "ThumbProximal",
        "thigh." + _s: _side + "UpperLeg",
        "shin." + _s: _side + "LowerLeg",
        "foot." + _s: _side + "Foot",
        "toe." + _s: _side + "Toes",
    })

# Bones the T-pose straightens along the arm line, parents first.
ARM_CHAIN = ["UpperArm", "LowerArm", "Hand", "MiddleProximal", "MiddleIntermediate"]


def _edit_mode(rig):
    bpy.context.view_layer.objects.active = rig
    for ob in bpy.context.view_layer.objects:
        ob.select_set(ob == rig)
    bpy.ops.object.mode_set(mode='EDIT')


def split_upper_chest(rig, body):
    _edit_mode(rig)
    eb = rig.data.edit_bones
    chest = eb["chest"]
    head, tail = chest.head.copy(), chest.tail.copy()
    mid = head.lerp(tail, 0.5)
    roll = chest.roll
    chest.tail = mid
    up = eb.new("UpperChest")
    up.head, up.tail = mid, tail
    up.roll = roll
    up.parent = chest
    up.use_deform = True
    for b in eb:
        if b.parent == chest and b != up:
            b.parent = up
    bpy.ops.object.mode_set(mode='OBJECT')
    # share the chest weights by height around the new joint
    g_chest = body.vertex_groups.get("chest")
    g_up = body.vertex_groups.new(name="UpperChest")
    if g_chest is not None:
        gi = g_chest.index
        for v in body.data.vertices:
            for g in v.groups:
                if g.group == gi and g.weight > 0:
                    k = smoothstep(mid.z - 0.05, mid.z + 0.05, v.co.z)
                    if k > 0:
                        g_up.add([v.index], g.weight * k, 'REPLACE')
                        g_chest.add([v.index], g.weight * (1 - k), 'REPLACE')
    for pb in rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    return mid


def rename(rig, body):
    for old, new in PROFILE.items():
        b = rig.data.bones.get(old)
        if b is None:
            raise KeyError("bone %s missing" % old)
        b.name = new   # renames the pose bone; vertex groups and F-curves are fixed below
        g = body.vertex_groups.get(old)
        if g is not None:
            g.name = new
    for act in bpy.data.actions:
        for fc in act.fcurves:
            dp = fc.data_path
            if dp.startswith('pose.bones["'):
                name = dp[len('pose.bones["'):dp.index('"]')]
                if name in PROFILE:
                    fc.data_path = dp.replace('pose.bones["%s"]' % name, 'pose.bones["%s"]' % PROFILE[name])
        for grp in act.groups:
            if grp.name in PROFILE:
                grp.name = PROFILE[grp.name]


def t_pose(rig):
    """Pose bones so the arms (and the mitten fingers) lie straight along +-X, palms down."""
    if rig.animation_data:
        rig.animation_data.action = None
    for pb in rig.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    bpy.context.view_layer.update()
    for side, sx in (("Left", 1.0), ("Right", -1.0)):
        target = Vector((sx, 0.0, 0.0))
        for part in ARM_CHAIN:
            pb = rig.pose.bones[side + part]
            m = pb.matrix.copy()
            head = m.translation.copy()
            cur = (m.to_3x3() @ Vector((0, 1, 0))).normalized()
            q = cur.rotation_difference(target)
            pb.matrix = Matrix.Translation(head) @ q.to_matrix().to_4x4() @ Matrix.Translation(-head) @ m
            bpy.context.view_layer.update()


def apply_contract(rig, body):
    split_upper_chest(rig, body)
    rename(rig, body)
    for pb in rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'
