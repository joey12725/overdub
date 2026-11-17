"""Deformation test sheet: blender --background <blend> --python render_deform.py -- out.png [poses]"""
import bpy, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mxa_render as R, mxa_util as U, mxa_pose as P
args = sys.argv[sys.argv.index('--') + 1:]
out = args[0]
poses = args[1].split(',') if len(args) > 1 else ['relaxed', 'crouch', 'arms_up', 'arms_fwd', 'stride', 'twist', 'fist', 'attitude']
rig = bpy.data.objects['Rig']
for pb in rig.pose.bones:
    for c in pb.constraints:
        c.mute = True
rig.animation_data_clear()
R.setup_scene((620, 820)); R.ensure_lights(2.0)
R.toonify(outline=0.006)
cam = R.camera()
ps = []
for name in poses:
    P.pose(rig, name)
    zc = 0.62 if name == 'crouch' else 0.86
    for k, yaw in enumerate((25, 205) if name != 'fist' else (25, 70)):
        if name == 'fist' and k == 1:
            R.aim(cam, (0.2, -0.1, 1.25), 30, 10, 8, ortho=0.6)
        else:
            R.aim(cam, (0, 0, zc), yaw, 8, 8, ortho=2.05)
        p = out[:-4] + '_%s_%d.png' % (name, k); R.render(p); ps.append(p)
R.sheet(ps, out, cols=4)
for p in ps:
    os.remove(p)
