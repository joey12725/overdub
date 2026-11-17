"""Proves the control rig drives the export skeleton: blender --background moxie.blend --python test_control.py -- out.png
Checks that switching the constraints on leaves the rest pose untouched, then poses with the
Rigify IK controls only (torso down = IK crouch, IK hands) and renders the result."""
import bpy, sys, os
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mxa_render as R
out = sys.argv[sys.argv.index('--') + 1]
rig = bpy.data.objects['Rig']; ctrl = bpy.data.objects['MoxieControl']
if rig.animation_data:
    rig.animation_data.action = None
for pb in rig.pose.bones:
    pb.matrix_basis.identity()
    for c in pb.constraints:
        c.mute = False
bpy.context.view_layer.update()
worst = 0.0
for pb in rig.pose.bones:
    d = (pb.matrix - pb.bone.matrix_local)
    worst = max(worst, max(abs(x) for row in d for x in row))
print('CONTROL rest deviation with constraints on: %.6f' % worst)
pb = ctrl.pose.bones
pb['torso'].location = pb['torso'].bone.matrix_local.to_3x3().inverted() @ Vector((0, -0.03, -0.33))
for s, sx in (('L', 1), ('R', -1)):
    try:
        ctrl.pose.bones['upper_arm_parent.' + s]['IK_FK'] = 0.0   # IK arms
    except Exception as e:
        print('CONTROL no IK_FK prop', e)
    h = pb['hand_ik.' + s]
    h.location = h.bone.matrix_local.to_3x3().inverted() @ Vector((-0.30 * sx, -0.32, 0.02 if s == 'L' else -0.45))
bpy.context.view_layer.update()
print('CONTROL hips z %.3f (rest %.3f), left hand %s' % (rig.pose.bones['Hips'].matrix.translation.z,
      rig.data.bones['Hips'].head_local.z, [round(v, 3) for v in rig.pose.bones['LeftHand'].matrix.translation]))
print('CONTROL feet z', round(rig.pose.bones['LeftFoot'].matrix.translation.z, 3), 'rest', round(rig.data.bones['LeftFoot'].head_local.z, 3))
ctrl.hide_set(False)
R.setup_scene((700, 900)); R.toonify(outline=0.006)
cam = R.camera()
ps = []
for i, yaw in enumerate((25, 100)):
    R.aim(cam, (0, 0, 0.75), yaw, 8, 8, ortho=1.9)
    p = out[:-4] + '_%d.png' % i; R.render(p); ps.append(p)
R.sheet(ps, out, cols=2)
for p in ps:
    os.remove(p)
