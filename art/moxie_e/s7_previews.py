"""Step 7 (Blender): final previews + pixel-aligned head renders for the face check.
  work/ver_front.png, work/ver_left.png   orthographic renders of the head in exactly the head sheets' pixel frame
  art/previews/moxie_e/_parts/turn_*.png, face_*.png, iso.png
Then run s7_measure.py (venv python) to overlay / measure and to tile the previews."""
import bpy, sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bl_common import *
bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, 'moxie.blend'))
setup_materials(grin='--grin' in sys.argv); flat_tex_shading()
sc = bpy.context.scene; sc.render.film_transparent = True
for o in bpy.data.objects:
    if o.type == 'ARMATURE': o.hide_render = True
rig = bpy.data.objects['Rig']
if rig.animation_data: rig.animation_data.action = None
for tr in rig.animation_data.nla_tracks: tr.mute = True
V = json.load(open(os.path.join(WORK, 'views_final.json')))
W, H = 1536, 1024
if '--grin' in sys.argv:
    render(os.path.join(PREV, '_parts', 'grin.png'), ortho_cam('g', 20, 5, target=(0, 0, 1.43), scale=0.5), res=(800, 800), transparent=True)
    sys.exit(0)
u0, v0, mpp = V['head_front'][:3]
cam = ortho_cam('vf', 0, 0, target=((W / 2 - u0) * mpp, 0, (v0 - H / 2) * mpp), scale=W * mpp)
render(os.path.join(WORK, 'ver_front.png'), cam, res=(W, H), transparent=True)
u0, v0, mpp = V['head_left'][:3]
cam = ortho_cam('vl', 90, 0, target=(0, (W / 2 - u0) * mpp, (v0 - H / 2) * mpp), scale=W * mpp)
render(os.path.join(WORK, 'ver_left.png'), cam, res=(W, H), transparent=True)
P = os.path.join(PREV, '_parts'); os.makedirs(P, exist_ok=True)
sc.display.shading.show_object_outline = True; sc.display.shading.object_outline_color = (0.05, 0.03, 0.03)
for i in range(8):
    render(os.path.join(P, f'turn_{i}.png'), ortho_cam(f't{i}', i * 45, 0, target=(0, 0, 0.8), scale=1.72), res=(760 if i % 4 == 0 else 520, 1000), transparent=True)
for i, (yaw, pitch) in enumerate(((0, 0), (35, 8), (-35, 8), (90, 0), (-90, 0), (180, 0))):
    render(os.path.join(P, f'face_{i}.png'), ortho_cam(f'f{i}', yaw, pitch, target=(0, 0, 1.43), scale=0.5), res=(900, 900), transparent=True)
render(os.path.join(P, 'iso.png'), ortho_cam('iso', 45, 35, target=(0, 0, 0.8), scale=2.1), res=(900, 1000), transparent=True)
