"""Verifies the control rig: blender --background art/moxie_c/moxie.blend --python art/moxie_c/mc_ctrl_test.py
Checks that switching the export skeleton onto the Rigify rig keeps the rest pose, then poses a few
IK controls and renders art/previews/moxie_c/control_rig.png to prove the mesh follows."""
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mc_render as R  # noqa: E402

rig = bpy.data.objects["Rig"]
ctrl = bpy.data.objects["MoxieControl"]
exec(bpy.data.texts["moxie_tools.py"].as_string())
if rig.animation_data:
    rig.animation_data.action = None
for pb in rig.pose.bones:
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.location = (0, 0, 0)
control_rig(True)  # noqa: F821
bpy.context.view_layer.update()
worst, wname = 0.0, ""
for pb in rig.pose.bones:
    if not any(c.name == "FollowControl" for c in pb.constraints):
        continue
    d = (pb.matrix.translation - pb.bone.matrix_local.translation).length
    ang = pb.matrix.to_quaternion().rotation_difference(pb.bone.matrix_local.to_quaternion()).angle
    ang = min(ang, 6.283185307 - ang)
    m = max(d, ang)
    if m > worst:
        worst, wname = m, pb.name
print("REST DEVIATION with control rig on: %.5f (%s)" % (worst, wname))
names = [b.name for b in ctrl.pose.bones]
print("controls present:", [n for n in ("torso", "hips", "chest", "head", "hand_ik.L", "hand_ik.R", "foot_ik.L",
                                         "foot_ik.R", "upper_arm_fk.L", "thigh_fk.L", "f_index.01_master.L") if n in names])
pb = ctrl.pose.bones


def move(name, v):
    b = pb[name]
    b.location = b.bone.matrix_local.to_3x3().inverted() @ Vector(v)


for s in ("L", "R"):
    for limb in ("upper_arm", "thigh"):
        par = pb.get("%s_parent.%s" % (limb, s))
        if par is not None and "IK_FK" in par:
            par["IK_FK"] = 0.0
move("torso", (0, 0, -0.14))
move("hand_ik.L", (-0.20, -0.22, 0.10))
move("hand_ik.R", (0.14, -0.14, -0.30))
move("foot_ik.R", (0.0, -0.22, 0.10))
bpy.context.view_layer.update()
hand = rig.pose.bones["LeftHand"].matrix.translation
print("LeftHand moved to", [round(v, 3) for v in hand], "from", [round(v, 3) for v in rig.data.bones["LeftHand"].head_local])
R.setup('soft')
R.floor(True)
out = os.path.abspath(os.path.join(HERE, "..", "previews", "moxie_c", "control_rig.png"))
R.render(out, (0, 0, 0.8), 30, 8, 2.0, (800, 900))
print("CTRL TEST DONE")
