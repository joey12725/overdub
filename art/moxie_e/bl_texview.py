"""Quick flat-colour check of the baked textures on work/mesh.blend:
blender -b --python bl_texview.py -- [out.png] [--grin]"""
import bpy, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bl_common import *
argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
out = os.path.abspath(argv[0]) if argv and not argv[0].startswith('--') else os.path.join(WORK, 'view_tex.png')
bpy.ops.wm.open_mainfile(filepath=os.path.join(WORK, 'mesh.blend'))
TEXDIR = os.path.join(ROOT, 'assets', 'models', 'candidates', 'e')


def set_tex(mat, path):
    mat.use_nodes = True; nt = mat.node_tree; nt.nodes.clear()
    o = nt.nodes.new('ShaderNodeOutputMaterial'); b = nt.nodes.new('ShaderNodeBsdfPrincipled'); t = nt.nodes.new('ShaderNodeTexImage')
    t.image = bpy.data.images.load(path, check_existing=False); nt.links.new(t.outputs['Color'], b.inputs['Base Color']); nt.links.new(b.outputs['BSDF'], o.inputs['Surface'])
    nt.nodes.active = t


set_tex(bpy.data.materials['body'], os.path.join(TEXDIR, 'moxie_body.png'))
set_tex(bpy.data.materials['head'], os.path.join(TEXDIR, 'moxie_head_grin.png' if '--grin' in argv else 'moxie_head.png'))
sc = bpy.context.scene
sc.display.shading.color_type = 'TEXTURE'; sc.display.shading.light = 'FLAT'
sc.display.shading.show_object_outline = False
sc.render.film_transparent = True; render.keep_light = True
R = os.path.join(WORK, '_r'); os.makedirs(R, exist_ok=True)
for i, (yaw, pitch) in enumerate(((0, 0), (45, 35), (90, 0), (180, 0), (-90, 0), (135, 20))):
    cam = ortho_cam(f'c{i}', yaw, pitch, target=(0, 0, 0.8), scale=1.75)
    render(os.path.join(R, f'b{i}.png'), cam, res=(700, 1100), transparent=True)
for i, (yaw, pitch) in enumerate(((0, 0), (35, 10), (90, 0), (180, 0), (-90, 0), (-35, 10))):
    cam = ortho_cam(f'h{i}', yaw, pitch, target=(0, 0, 1.44), scale=0.56)
    render(os.path.join(R, f'h{i}.png'), cam, res=(800, 800), transparent=True)
