"""Preview rendering (EEVEE). Two looks:
  'soft'  - lit Principled materials, soft studio light: judges form, folds, topology smoothness
  'toon'  - stepped cel shading + inverted-hull ink outline: what the game's shader will show

Views: yaw 0 looks at her face (camera on -Y), yaw 90 at her left side, 180 at her back.
The game camera is orthographic, yaw 45, pitch 35.
"""
import math
import os

import bpy
import numpy as np
from mathutils import Vector

BG = (0.80, 0.81, 0.84)


def _cam():
    sc = bpy.context.scene
    cam = bpy.data.objects.get("PreviewCam")
    if cam is None:
        cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
        sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def setup(mode='soft'):
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE_NEXT'
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGB'
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    sc.eevee.taa_render_samples = 32
    try:
        sc.eevee.use_shadows = True
        sc.eevee.use_gtao = True
    except Exception:
        pass
    w = sc.world or bpy.data.worlds.new("W")
    sc.world = w
    w.use_nodes = True
    bgn = w.node_tree.nodes["Background"]
    bgn.inputs[0].default_value = (*[c ** 2.2 for c in BG], 1)
    bgn.inputs[1].default_value = 1.0 if mode == 'toon' else 0.55
    for name, rot, energy, col in (("KeyL", (50, 0, -35), 3.2, (1, 0.97, 0.93)),
                                   ("FillL", (60, 0, 110), 0.9, (0.85, 0.9, 1.0)),
                                   ("RimL", (120, 0, 200), 1.4, (1, 1, 1))):
        ob = bpy.data.objects.get(name)
        if ob is None:
            ld = bpy.data.lights.new(name, 'SUN')
            ob = bpy.data.objects.new(name, ld)
            sc.collection.objects.link(ob)
        ob.data.energy = energy if mode == 'soft' else (3.0 if name == "KeyL" else 0.0)
        ob.data.color = col
        ob.data.angle = math.radians(8)
        ob.rotation_euler = [math.radians(a) for a in rot]
        ob.hide_render = False
    return _cam()


def place(cam, target, yaw, pitch, ortho_scale, dist=8.0):
    y, p = math.radians(yaw), math.radians(pitch)
    d = Vector((math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p)))
    cam.location = Vector(target) + d * dist
    cam.rotation_mode = 'QUATERNION'
    cam.rotation_quaternion = (Vector(target) - cam.location).to_track_quat('-Z', 'Y')
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = ortho_scale
    cam.data.clip_start = 0.01
    cam.data.clip_end = 50
    # key light follows the camera a little so every view is readable
    key = bpy.data.objects.get("KeyL")
    if key:
        key.rotation_euler = (math.radians(52), 0, math.radians(yaw - 32))
    fill = bpy.data.objects.get("FillL")
    if fill:
        fill.rotation_euler = (math.radians(62), 0, math.radians(yaw + 70))
    rim = bpy.data.objects.get("RimL")
    if rim:
        rim.rotation_euler = (math.radians(115), 0, math.radians(yaw + 160))


def render(path, target, yaw, pitch, ortho_scale, res=(700, 1000)):
    sc = bpy.context.scene
    cam = _cam()
    place(cam, target, yaw, pitch, ortho_scale)
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


# --------------------------------------------------------------------------- toon look

def _toon_material(src):
    name = "TOON_" + src.name
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(emit.outputs[0], out.inputs[0])
    b = src.node_tree.nodes.get("Principled BSDF") if src.use_nodes else None
    col = tuple(src.diffuse_color)
    tex = None
    glow = src.name.endswith("_glow")
    if b:
        col = tuple(b.inputs["Base Color"].default_value)
        for l in src.node_tree.links:
            if l.to_node == b and l.to_socket.name == "Base Color":
                tex = l.from_node.image
                col = (1, 1, 1, 1)
    flat = glow or src.name in ("eye", "teeth")
    if tex:
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = tex
        base = tn.outputs["Color"]
    else:
        rgb = nt.nodes.new("ShaderNodeRGB")
        rgb.outputs[0].default_value = col
        base = rgb.outputs[0]
    if flat:
        nt.links.new(base, emit.inputs[0])
        emit.inputs[1].default_value = 1.6 if glow else 1.0
        return mat
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    nt.links.new(dif.outputs[0], s2r.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = 'CONSTANT'
    e = ramp.color_ramp.elements
    e[0].position = 0.0
    e[0].color = (0.50, 0.42, 0.50, 1)
    e[1].position = 0.30
    e[1].color = (1, 1, 1, 1)
    mid = e.new(0.10)
    mid.color = (0.72, 0.66, 0.72, 1)
    nt.links.new(s2r.outputs[0], ramp.inputs[0])
    mix = nt.nodes.new("ShaderNodeMixRGB")
    mix.blend_type = 'MULTIPLY'
    mix.inputs[0].default_value = 1.0
    nt.links.new(base, mix.inputs[1])
    nt.links.new(ramp.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], emit.inputs[0])
    return mat


def _ink():
    m = bpy.data.materials.get("INK")
    if m:
        return m
    m = bpy.data.materials.new("INK")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = (0.045, 0.03, 0.05, 1)
    nt.links.new(em.outputs[0], out.inputs[0])
    m.use_backface_culling = True
    return m


def apply_toon(outline=0.0035, skip_outline=("Eyes", "Teeth")):
    """Swap every material for its toon twin and add an inverted hull. Not saved to the .blend."""
    ink = _ink()
    for ob in bpy.data.objects:
        if ob.type != 'MESH' or ob.name.startswith("Preview"):
            continue
        me = ob.data
        for i, m in enumerate(me.materials):
            if m and not m.name.startswith("TOON_") and m.name != "INK":
                me.materials[i] = _toon_material(m)
        if outline > 0 and not any(ob.name.startswith(s) for s in skip_outline):
            if "INK" not in [m.name for m in me.materials if m]:
                me.materials.append(ink)
            mod = ob.modifiers.new("ink", 'SOLIDIFY')
            mod.thickness = outline
            mod.offset = 1.0
            mod.use_flip_normals = True
            mod.use_rim = False
            mod.material_offset = len(me.materials) - 1
            mod.use_quality_normals = True


def floor(show=True, r=0.75):
    ob = bpy.data.objects.get("PreviewFloor")
    if ob is None and show:
        import bmesh
        bm = bmesh.new()
        bmesh.ops.create_circle(bm, cap_ends=True, radius=r, segments=64)
        me = bpy.data.meshes.new("PreviewFloor")
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new("PreviewFloor", me)
        bpy.context.scene.collection.objects.link(ob)
        mat = bpy.data.materials.new("preview_floor")
        mat.diffuse_color = (0.55, 0.56, 0.6, 1.0)
        mat.use_nodes = True
        mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.5, 0.51, 0.55, 1)
        me.materials.append(mat)
    if ob:
        ob.hide_render = not show
    return ob
