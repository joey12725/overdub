"""Preview-only cel shading that mimics the game's toon shader (shaders/toon_lighting.gdshaderinc):
four flat light bands with a tinted shadow floor, plus an inverted-hull ink outline.
Nothing here is exported; it only makes the review renders look like the game."""
import bpy, math
from mathutils import Vector

BANDS = [(0.0, 0.0), (0.06, 0.55), (0.38, 0.86), (0.82, 1.0)]
SHADOW = (0.50, 0.45, 0.56)      # shadow_tint * shadow_floor + ambient, roughly what the game shows
INK = (0.008, 0.005, 0.005)


def toon_material(src):
    """Return a toon copy of material `src` (same base colour / texture)."""
    name = "TOON_" + src.name
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emi = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(emi.outputs[0], out.inputs[0])
    # base colour
    tex = None
    col = (0.8, 0.8, 0.8, 1)
    emit = 0.0
    if src.use_nodes:
        bsdf = src.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            col = tuple(bsdf.inputs["Base Color"].default_value)
            emit = bsdf.inputs["Emission Strength"].default_value
            if bsdf.inputs["Base Color"].links:
                n = bsdf.inputs["Base Color"].links[0].from_node
                if n.type == 'TEX_IMAGE':
                    tex = n.image
    if tex is not None:
        base = nt.nodes.new("ShaderNodeTexImage")
        base.image = tex
        base_out = base.outputs["Color"]
    else:
        base = nt.nodes.new("ShaderNodeRGB")
        base.outputs[0].default_value = col
        base_out = base.outputs[0]
    if src.name.endswith("_glow") or emit > 0:
        nt.links.new(base_out, emi.inputs["Color"])
        emi.inputs["Strength"].default_value = 1.6
        return m
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    dif.inputs["Color"].default_value = (1, 1, 1, 1)
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    nt.links.new(dif.outputs[0], s2r.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.interpolation = 'CONSTANT'
    while len(cr.elements) > 1:
        cr.elements.remove(cr.elements[-1])
    cr.elements[0].position = 0.0
    cr.elements[0].color = (0, 0, 0, 1)
    for pos, val in BANDS[1:]:
        e = cr.elements.new(pos)
        e.color = (val, val, val, 1)
    nt.links.new(s2r.outputs["Color"], ramp.inputs["Fac"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = 'RGBA'
    mix.inputs["A"].default_value = (*SHADOW, 1)
    mix.inputs["B"].default_value = (1, 1, 1, 1)
    nt.links.new(ramp.outputs["Color"], mix.inputs["Factor"])
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = 'RGBA'
    mul.blend_type = 'MULTIPLY'
    mul.inputs["Factor"].default_value = 1.0
    nt.links.new(base_out, mul.inputs["A"])
    nt.links.new(mix.outputs["Result"], mul.inputs["B"])
    nt.links.new(mul.outputs["Result"], emi.inputs["Color"])
    return m


def ink_material():
    m = bpy.data.materials.get("TOON_ink")
    if m:
        return m
    m = bpy.data.materials.new("TOON_ink")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emi = nt.nodes.new("ShaderNodeEmission")
    emi.inputs["Color"].default_value = (*INK, 1)
    nt.links.new(emi.outputs[0], out.inputs[0])
    m.use_backface_culling = True
    try:
        m.use_backface_culling_shadow = True
    except Exception:
        pass
    return m


def toonify(objs, outline=0.0035, skip_outline=()):
    """Swap every material for its toon twin and add an inverted hull. Call on a throw-away scene state."""
    ink = ink_material()
    for o in objs:
        if o.type != 'MESH':
            continue
        n = len(o.data.materials)
        for i in range(n):
            if o.data.materials[i] is not None and not o.data.materials[i].name.startswith("TOON_"):
                o.data.materials[i] = toon_material(o.data.materials[i])
        if outline > 0 and o.name not in skip_outline and "TOON_ink" not in [m.name for m in o.data.materials if m]:
            o.data.materials.append(ink)
            md = o.modifiers.new("TOON_hull", 'SOLIDIFY')
            md.thickness = outline
            md.offset = 1.0
            md.use_flip_normals = True
            md.use_rim = False
            md.material_offset = n       # every hull face lands on the ink slot (clamped)
            md.use_quality_normals = True


def setup_eevee(bg=(0.80, 0.80, 0.82), sun_dir=(-0.45, -0.75, 0.9), transparent=False):
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE_NEXT'
    sc.eevee.taa_render_samples = 32
    sc.render.film_transparent = transparent
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    if sc.world is None:
        sc.world = bpy.data.worlds.new("W")
    sc.world.use_nodes = True
    sc.world.node_tree.nodes["Background"].inputs[0].default_value = (*bg, 1)
    sc.world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    sun = bpy.data.objects.get("ToonSun")
    if sun is None:
        sd = bpy.data.lights.new("ToonSun", 'SUN')
        sun = bpy.data.objects.new("ToonSun", sd)
        sc.collection.objects.link(sun)
    sun.data.energy = math.pi
    sun.data.angle = 0.01
    d = Vector(sun_dir).normalized()
    sun.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    return sun
