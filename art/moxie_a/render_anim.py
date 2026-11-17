"""Animation contact sheets: blender --background <blend> --python render_anim.py -- outdir [clips] [n]
One PNG per clip (n frames across the clip, three-quarter view, toon look)."""
import bpy, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mxa_render as R, mxa_util as U
args = sys.argv[sys.argv.index('--') + 1:]
outdir = args[0]
clips = args[1].split(',') if len(args) > 1 and args[1] != 'all' else [a.name for a in bpy.data.actions if a.get('source')]
n = int(args[2]) if len(args) > 2 else 8
rig = bpy.data.objects['Rig']
for pb in rig.pose.bones:
    for c in pb.constraints:
        c.mute = True
R.setup_scene((360, 480)); R.ensure_lights(2.0)
R.toonify(outline=0.007)
cam = R.camera()
sc = bpy.context.scene
for o in bpy.data.objects:
    if o.type == 'ARMATURE':
        o.hide_render = True
for name in clips:
    act = bpy.data.actions[name]
    rig.animation_data_create(); rig.animation_data.action = act
    try:
        if act.slots:
            rig.animation_data.action_slot = act.slots[0]
    except Exception:
        pass
    f0, f1 = act.frame_range
    ps = []
    for i in range(n):
        f = f0 + (f1 - f0) * i / (n - 1 if not act.get('loop') else n)
        sc.frame_set(int(f), subframe=f - int(f))
        R.aim(cam, (0, 0, 0.82), 30, 12, 8, ortho=2.3)
        p = os.path.join(outdir, '_%s_%02d.png' % (name, i)); R.render(p); ps.append(p)
    R.sheet(ps, os.path.join(outdir, 'anim_%s.png' % name.replace('src_', 'src_')), cols=n)
    for p in ps:
        os.remove(p)
