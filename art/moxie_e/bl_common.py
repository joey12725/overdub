"""Shared Blender helpers for candidate E (render set-ups, paths)."""
import bpy, os, math
from mathutils import Vector, Euler

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
WORK = os.path.join(HERE, 'work')
PREV = os.path.join(ROOT, 'art', 'previews', 'moxie_e')
GEN = os.path.join(ROOT, 'docs', 'reference', 'generated')
os.makedirs(PREV, exist_ok=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def ortho_cam(name, yaw_deg, pitch_deg, target=(0, 0, 0.8), scale=2.0, dist=6.0):
    """Orthographic camera looking at target. yaw 0 = from the front (-Y), positive yaw goes toward her left (+X)."""
    cam = bpy.data.cameras.new(name); cam.type = 'ORTHO'; cam.ortho_scale = scale
    ob = bpy.data.objects.new(name, cam); bpy.context.scene.collection.objects.link(ob)
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    d = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
    ob.location = Vector(target) + d * dist
    ob.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    cam.clip_start = 0.1; cam.clip_end = 50
    return ob


def render(path, cam, res=(800, 1000), engine='BLENDER_WORKBENCH', transparent=False, samples=16):
    sc = bpy.context.scene
    sc.camera = cam
    sc.render.engine = engine
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = transparent
    sc.render.image_settings.file_format = 'PNG'
    sc.render.filepath = path
    sc.view_settings.view_transform = 'Standard'
    if engine == 'BLENDER_WORKBENCH':
        if not getattr(render, 'keep_light', False): sc.display.shading.light = 'STUDIO'
        sc.display.render_aa = '8'
    else:
        try: sc.eevee.taa_render_samples = samples
        except Exception: pass
    bpy.ops.render.render(write_still=True)


def contact_sheet(paths, out, cols=None, pad=0):
    """Tile PNGs with Blender's image API only (no PIL in Blender)."""
    import numpy as np
    imgs = []
    for p in paths:
        im = bpy.data.images.load(p); w, h = im.size
        a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
        imgs.append(a); bpy.data.images.remove(im)
    cols = cols or len(imgs)
    rows = (len(imgs) + cols - 1) // cols
    h = max(i.shape[0] for i in imgs); w = max(i.shape[1] for i in imgs)
    sheet = np.zeros((rows * h, cols * w, 4), np.float32); sheet[:, :, 3] = 1; sheet[:, :, :3] = 0.5
    for k, a in enumerate(imgs):
        r, c = divmod(k, cols)
        y0 = (rows - 1 - r) * h
        sheet[y0:y0 + a.shape[0], c * w:c * w + a.shape[1]] = a
    im = bpy.data.images.new('sheet', sheet.shape[1], sheet.shape[0], alpha=True)
    im.pixels.foreach_set(sheet.ravel()); im.filepath_raw = out; im.file_format = 'PNG'; im.save()
    bpy.data.images.remove(im)


TEXDIR = os.path.join(ROOT, 'assets', 'models', 'candidates', 'e')


def setup_materials(grin=False):
    """Principled materials 'body' / 'head' with the baked albedo (what the glb exports)."""
    for name, f in (('body', 'moxie_body.png'), ('head', 'moxie_head_grin.png' if grin else 'moxie_head.png')):
        mat = bpy.data.materials[name]; mat.use_nodes = True; nt = mat.node_tree; nt.nodes.clear()
        o = nt.nodes.new('ShaderNodeOutputMaterial'); b = nt.nodes.new('ShaderNodeBsdfPrincipled'); t = nt.nodes.new('ShaderNodeTexImage')
        t.image = bpy.data.images.load(os.path.join(TEXDIR, f), check_existing=True)
        t.image.name = name          # glb image name -> Godot extracts it as moxie_<name>.png, i.e. onto the same file
        nt.links.new(t.outputs['Color'], b.inputs['Base Color']); nt.links.new(b.outputs['BSDF'], o.inputs['Surface'])
        b.inputs['Roughness'].default_value = 1.0; b.inputs['Metallic'].default_value = 0.0
        try: b.inputs['Specular IOR Level'].default_value = 0.0
        except Exception: pass
        nt.nodes.active = t


def flat_tex_shading():
    sc = bpy.context.scene
    sc.display.shading.color_type = 'TEXTURE'; sc.display.shading.light = 'FLAT'; sc.display.shading.show_object_outline = False
    render.keep_light = True


def rot(rig, bone, axis, deg):
    """rotate a pose bone about a WORLD axis through its head (call parents before children)"""
    import math
    from mathutils import Matrix
    pb = rig.pose.bones[bone]; h = pb.matrix.translation.copy()
    pb.matrix = Matrix.Translation(h) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-h) @ pb.matrix
    bpy.context.view_layer.update()


def move(rig, bone, vec):
    from mathutils import Matrix
    pb = rig.pose.bones[bone]
    pb.matrix = Matrix.Translation(vec) @ pb.matrix
    bpy.context.view_layer.update()


def reset_pose(rig):
    for pb in rig.pose.bones:
        pb.location = (0, 0, 0); pb.rotation_mode = 'QUATERNION'; pb.rotation_quaternion = (1, 0, 0, 0); pb.scale = (1, 1, 1)
    bpy.context.view_layer.update()
