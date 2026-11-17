"""Render helpers shared by the Moxie-A scripts (Blender 4.5)."""
import bpy, math, os
from mathutils import Vector, Matrix, Euler

def setup_scene(res=(900, 1200), bg=(0.86, 0.87, 0.9), engine='BLENDER_EEVEE_NEXT', samples=32):
    sc = bpy.context.scene
    sc.render.engine = engine
    try: sc.eevee.taa_render_samples = samples
    except Exception: pass
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    sc.render.image_settings.file_format = 'PNG'
    w = sc.world or bpy.data.worlds.new('W')
    sc.world = w
    w.use_nodes = True
    b = w.node_tree.nodes.get('Background')
    b.inputs[0].default_value = (*bg, 1)
    b.inputs[1].default_value = 1.0
    return sc

def ensure_lights(strength=3.0):
    for o in list(bpy.data.objects):
        if o.type == 'LIGHT' and o.name.startswith('MXL_'):
            bpy.data.objects.remove(o)
    def sun(name, rot, e, col=(1, 1, 1)):
        l = bpy.data.lights.new(name, 'SUN'); l.energy = e; l.color = col; l.angle = 0.2
        o = bpy.data.objects.new(name, l); bpy.context.scene.collection.objects.link(o)
        o.rotation_euler = Euler(rot)
        return o
    sun('MXL_key', (math.radians(55), 0, math.radians(35)), strength)
    sun('MXL_fill', (math.radians(70), 0, math.radians(-120)), strength * 0.25, (0.8, 0.85, 1))

def camera(name='MXCam'):
    cam = bpy.data.objects.get(name)
    if cam is None:
        cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
        bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam
    return cam

def aim(cam, target, yaw_deg, pitch_deg=0.0, dist=6.0, ortho=None, lens=85):
    """yaw 0 = looking at the character's front (character faces -Y in Blender)."""
    yaw = math.radians(yaw_deg); pitch = math.radians(pitch_deg)
    d = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
    cam.location = Vector(target) + d * dist
    cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    if ortho:
        cam.data.type = 'ORTHO'; cam.data.ortho_scale = ortho
    else:
        cam.data.type = 'PERSP'; cam.data.lens = lens
    cam.data.clip_start = 0.01; cam.data.clip_end = 100

def render(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)

def sheet(paths, out, cols=None, pad=6, bg=(40, 40, 46)):
    """Compose images into a contact sheet using Blender's image API (no PIL needed)."""
    import numpy as np
    imgs = []
    for p in paths:
        im = bpy.data.images.load(p, check_existing=False)
        w, h = im.size
        a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
        imgs.append(a); bpy.data.images.remove(im)
    cols = cols or len(imgs)
    rows = (len(imgs) + cols - 1) // cols
    h = max(a.shape[0] for a in imgs); w = max(a.shape[1] for a in imgs)
    S = np.zeros((rows * h + (rows + 1) * pad, cols * w + (cols + 1) * pad, 4), np.float32)
    S[..., :3] = [c / 255 for c in bg]; S[..., 3] = 1
    for i, a in enumerate(imgs):
        r = rows - 1 - i // cols; c = i % cols
        y = pad + r * (h + pad); x = pad + c * (w + pad)
        S[y:y + a.shape[0], x:x + a.shape[1]] = a
    o = bpy.data.images.new('sheet', S.shape[1], S.shape[0], alpha=True)
    o.pixels.foreach_set(S.ravel()); o.filepath_raw = out; o.file_format = 'PNG'; o.save()
    bpy.data.images.remove(o)


# ---------------------------------------------------------------- toon preview (mirrors actors/shaders)
def toonify(outline=0.012, ink=(0.012, 0.006, 0.005), lit=(1.0, 0.97, 0.92), shade=(0.55, 0.5, 0.68)):
    """Replace every material's surface with a two-step cel ramp of its flat base colour and add an
    inverted-hull ink outline (Solidify, flipped normals) - the same look the game's actor shaders
    give. Render-only: call in a throwaway session, never before saving the working file."""
    inkm = bpy.data.materials.new('MX_ink')
    inkm.use_nodes = True
    nt = inkm.node_tree; nt.nodes.clear()
    o = nt.nodes.new('ShaderNodeOutputMaterial'); e = nt.nodes.new('ShaderNodeEmission')
    e.inputs[0].default_value = (*ink, 1); nt.links.new(e.outputs[0], o.inputs[0])
    inkm.use_backface_culling = True
    try: inkm.use_backface_culling_shadow = True
    except Exception: pass
    for m in list(bpy.data.materials):
        if m is inkm or not m.use_nodes:
            continue
        bs = m.node_tree.nodes.get('Principled BSDF')
        if bs is None:
            continue
        col = tuple(bs.inputs['Base Color'].default_value)[:3]
        glow = m.name.endswith('_glow')
        nt = m.node_tree; nt.nodes.clear()
        out = nt.nodes.new('ShaderNodeOutputMaterial')
        em = nt.nodes.new('ShaderNodeEmission')
        if glow:
            em.inputs[0].default_value = (*col, 1); em.inputs[1].default_value = 1.6
        else:
            g = nt.nodes.new('ShaderNodeNewGeometry')
            dot = nt.nodes.new('ShaderNodeVectorMath'); dot.operation = 'DOT_PRODUCT'
            dot.inputs[1].default_value = Vector((-0.45, -0.55, 1.0)).normalized()
            h = nt.nodes.new('ShaderNodeMath'); h.operation = 'MULTIPLY_ADD'
            h.inputs[1].default_value = 0.5; h.inputs[2].default_value = 0.5
            ramp = nt.nodes.new('ShaderNodeValToRGB')
            ramp.color_ramp.interpolation = 'LINEAR'
            ramp.color_ramp.elements[0].position = 0.38
            ramp.color_ramp.elements[0].color = (*[c * s for c, s in zip(col, shade)], 1)
            ramp.color_ramp.elements[1].position = 0.46
            ramp.color_ramp.elements[1].color = (*[c * s for c, s in zip(col, lit)], 1)
            nt.links.new(g.outputs['Normal'], dot.inputs[0]); nt.links.new(dot.outputs['Value'], h.inputs[0])
            nt.links.new(h.outputs[0], ramp.inputs[0]); nt.links.new(ramp.outputs[0], em.inputs[0])
        nt.links.new(em.outputs[0], out.inputs[0])
    if outline > 0:
        for ob in bpy.data.objects:
            if ob.type != 'MESH' or ob.hide_render:
                continue
            ob.data.materials.append(inkm)
            md = ob.modifiers.new('MX_outline', 'SOLIDIFY')
            md.thickness = outline; md.offset = 1.0; md.use_flip_normals = True; md.use_rim = False
            md.material_offset = len(ob.data.materials) - 1
            md.use_quality_normals = True
    for o2 in list(bpy.data.objects):
        if o2.type == 'LIGHT':
            bpy.data.objects.remove(o2)
