"""Preview stills in the game's cel look (flat colours, two-step shading, inverted-hull ink):
    blender --background moxie.blend --python render_previews.py -- <art/previews/moxie_a>
Writes turnaround.png, face.png, toon_iso.png, thumb.png, tpose.png."""
import bpy, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mxa_render as R, mxa_pose as P
out = sys.argv[sys.argv.index('--') + 1]
os.makedirs(out, exist_ok=True)
rig = bpy.data.objects['Rig']
for o in bpy.data.objects:
    if o.type == 'ARMATURE':
        o.hide_render = True
for pb in rig.pose.bones:
    for c in pb.constraints:
        c.mute = True
if rig.animation_data:
    rig.animation_data.action = None
sc = R.setup_scene((760, 1280))
R.toonify(outline=0.007)
cam = R.camera()


def shots(name, views, res, cols=None):
    sc.render.resolution_x, sc.render.resolution_y = res
    ps = []
    for i, (target, yaw, pitch, ortho) in enumerate(views):
        R.aim(cam, target, yaw, pitch, 8, ortho=ortho)
        p = os.path.join(out, '_%s_%d.png' % (name, i)); R.render(p); ps.append(p)
    R.sheet(ps, os.path.join(out, name + '.png'), cols=cols or len(ps))
    for p in ps:
        os.remove(p)


P.pose(rig, 'relaxed')
shots('turnaround', [((0, 0, 0.88), y, 3, 1.95) for y in (0, 40, 90, 180)], (760, 1280))
shots('face', [((0, -0.02, 1.49), 0, 0, 0.42), ((0, -0.02, 1.49), 38, 6, 0.42), ((0, 0, 1.49), 90, 0, 0.42)], (900, 900))
P.pose(rig, 'tpose')
shots('tpose', [((0, 0, 0.88), 0, 0, 1.95), ((0, 0, 0.88), 180, 0, 1.95)], (1280, 1280))
P.pose(rig, 'attitude')
shots('toon_iso', [((0, 0, 0.88), 45, 35, 2.1), ((0, 0, 0.88), -45, 35, 2.1)], (900, 1200))
# thumbnail: 160 px tall at the isometric angle, outline at the in-game width
for m in [m for o in bpy.data.objects if o.type == 'MESH' for m in o.modifiers if m.name == 'MX_outline']:
    m.thickness = 0.012
sc.render.resolution_x, sc.render.resolution_y = 120, 160
R.aim(cam, (0, 0, 0.90), 45, 35, 8, ortho=2.0)
R.render(os.path.join(out, 'thumb.png'))
