class_name ToonKit
extends RefCounted
## Builders for the shared OVERDUB materials (shaders/README.md documents every uniform) and the
## re-materialing pass for imported .glb scenes (asset contract: base colours only, `*_glow`
## materials become emissive, Godot applies the toon shader and the ink outline).
##
## Used by world/, actors/ and fx/. Nothing here touches the scene tree except apply_toon(), which
## only edits the nodes it is given.

const TOON_SHADER := preload("res://shaders/toon.gdshader")
const TOON_CUTOUT_SHADER := preload("res://shaders/toon_cutout.gdshader")
const OUTLINE_SHADER := preload("res://shaders/outline.gdshader")
const XRAY_SHADER := preload("res://shaders/xray.gdshader")
const GLOW_SHADER := preload("res://shaders/glow.gdshader")
const GLOW_ADD_SHADER := preload("res://shaders/glow_add.gdshader")
const SURFACE_SHADER := preload("res://shaders/world_surface.gdshader")
const BLOB_SHADER := preload("res://shaders/blob_shadow.gdshader")

## Default ink (prototype 'upper' palette ink).
const INK := Color("#1f1412")
## Default outline width in viewport pixels.
const OUTLINE_PX := 2.0
## Energy given to `*_glow` materials by apply_toon().
const GLOW_ENERGY := 2.6

## Theme lighting that new toon materials pick up (the world view sets these on level load from the
## level's palette, before the layers build anything).
static var theme_shadow_tint: Color = Color(0.30, 0.27, 0.34, 1.0)
static var theme_ink: Color = INK

static var _ramp: GradientTexture1D = null


## Options for apply_toon().
class Options:
	extends RefCounted
	## Ink colour of the outline pass.
	var outline_color: Color = ToonKit.theme_ink
	## Outline width in pixels; <= 0 disables the outline pass.
	var outline_px: float = ToonKit.OUTLINE_PX
	## Emission energy for `*_glow` materials.
	var glow_energy: float = ToonKit.GLOW_ENERGY
	## Material name -> colour override (e.g. tint a self's "headphones_glow" in cassette colour).
	var color_by_name: Dictionary[String, Color] = {}
	## Material names (or name suffixes, see glow_suffix) treated as emissive.
	var glow_suffix: String = "_glow"
	## Add the x-ray silhouette pass (actors that must stay visible behind walls).
	var xray: bool = false
	var xray_color: Color = Color(0.95, 0.95, 1.0, 0.55)
	## Bake smoothed normals into CUSTOM0 for the outline (static meshes only; skinned meshes keep
	## their normals automatically).
	var bake_smooth_normals: bool = true
	## Cast shadows from the re-materialed meshes.
	var cast_shadows: bool = true
	## Render layers to put the meshes on (0 = leave as imported).
	var layers: int = 0


## The stepped irradiance ramp (deep shadow, half, lit, highlight) as a 1D texture. Shared.
static func ramp() -> Texture2D:
	if _ramp == null:
		var g := Gradient.new()
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		g.offsets = PackedFloat32Array([0.0, 0.06, 0.38, 0.82])
		g.colors = PackedColorArray([Color(0, 0, 0), Color(0.55, 0.55, 0.55), Color(0.86, 0.86, 0.86), Color(1, 1, 1)])
		_ramp = GradientTexture1D.new()
		_ramp.gradient = g
		_ramp.width = 64
	return _ramp


## A new lit cel material of colour `color` (sRGB), with the ink outline as next_pass unless
## outline_px <= 0.
static func toon(color: Color, outline_px: float = OUTLINE_PX, outline_color: Color = theme_ink) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON_SHADER
	_set_lighting(m)
	m.set_shader_parameter(&"albedo", color)
	if outline_px > 0.0:
		m.next_pass = outline(outline_color, outline_px)
	return m


## Two-sided alpha-scissor variant (foliage cards, vines, tags on quads). No outline by default.
static func toon_cutout(color: Color, texture: Texture2D = null, cut: float = 0.4) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON_CUTOUT_SHADER
	_set_lighting(m)
	m.set_shader_parameter(&"albedo", color)
	m.set_shader_parameter(&"alpha_cut", cut)
	if texture != null:
		m.set_shader_parameter(&"albedo_texture", texture)
		m.set_shader_parameter(&"use_albedo_texture", true)
	return m


## Lit cel material that also glows (emission colour * energy on top of the cel albedo).
static func toon_emissive(color: Color, emission: Color, energy: float, outline_px: float = OUTLINE_PX) -> ShaderMaterial:
	var m := toon(color, outline_px)
	m.set_shader_parameter(&"emission", emission)
	m.set_shader_parameter(&"emission_energy", energy)
	return m


## The world's procedural surface material (patterns: see world_surface.gdshader).
static func surface(top_pattern: int, side_pattern: int, top_color: Color, side_color: Color, line_color: Color, outline_px: float = OUTLINE_PX, outline_color: Color = theme_ink) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	_set_lighting(m)
	m.set_shader_parameter(&"top_pattern", top_pattern)
	m.set_shader_parameter(&"side_pattern", side_pattern)
	m.set_shader_parameter(&"top_color", top_color)
	m.set_shader_parameter(&"side_color", side_color)
	m.set_shader_parameter(&"line_color", line_color)
	if outline_px > 0.0:
		m.next_pass = outline(outline_color, outline_px)
	return m


## Inverted-hull ink material (use as next_pass).
static func outline(color: Color = theme_ink, thickness_px: float = OUTLINE_PX) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = OUTLINE_SHADER
	m.set_shader_parameter(&"outline_color", color)
	m.set_shader_parameter(&"thickness_px", thickness_px)
	return m


## X-ray silhouette material (append with with_xray()).
static func xray(color: Color = Color(0.95, 0.95, 1.0, 0.55), margin: float = 0.35) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = XRAY_SHADER
	m.set_shader_parameter(&"xray_color", color)
	m.set_shader_parameter(&"occlusion_margin", margin)
	m.render_priority = 10
	return m


## Opaque unlit emissive (HDR colour * energy; blooms above ~1.2).
static func glow(color: Color, energy: float = 2.2) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter(&"color", color)
	m.set_shader_parameter(&"energy", energy)
	return m


## Additive, depth-write-free glow (halos, beams, light pools). `radial` fades to the UV edge.
static func glow_add(color: Color, energy: float = 1.0, opacity: float = 1.0, radial: float = 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GLOW_ADD_SHADER
	m.set_shader_parameter(&"color", color)
	m.set_shader_parameter(&"energy", energy)
	m.set_shader_parameter(&"opacity", opacity)
	m.set_shader_parameter(&"radial", radial)
	return m


## Soft round contact shadow for a horizontal quad (PlaneMesh) a few mm above the floor.
static func blob(color: Color = Color(0.12, 0.08, 0.08), opacity: float = 0.42, softness: float = 0.75) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BLOB_SHADER
	m.set_shader_parameter(&"color", color)
	m.set_shader_parameter(&"opacity", opacity)
	m.set_shader_parameter(&"softness", softness)
	return m


## Attach (or replace) the outline pass of a material chain's first material.
static func with_outline(m: ShaderMaterial, color: Color = theme_ink, thickness_px: float = OUTLINE_PX) -> ShaderMaterial:
	var xr: Material = null
	if m.next_pass != null and m.next_pass is ShaderMaterial and (m.next_pass as ShaderMaterial).shader == OUTLINE_SHADER:
		xr = m.next_pass.next_pass
	elif m.next_pass != null and m.next_pass is ShaderMaterial and (m.next_pass as ShaderMaterial).shader == XRAY_SHADER:
		xr = m.next_pass
	var o := outline(color, thickness_px)
	o.next_pass = xr
	m.next_pass = o
	return m


## Append an x-ray pass at the end of the material's pass chain (after the outline).
static func with_xray(m: Material, color: Color = Color(0.95, 0.95, 1.0, 0.55)) -> Material:
	var last: Material = m
	while last.next_pass != null:
		if last.next_pass is ShaderMaterial and (last.next_pass as ShaderMaterial).shader == XRAY_SHADER:
			return m
		last = last.next_pass
	last.next_pass = xray(color)
	return m


## True when the material (or its chain) is one of ours.
static func is_toon(m: Material) -> bool:
	return m is ShaderMaterial and ((m as ShaderMaterial).shader == TOON_SHADER or (m as ShaderMaterial).shader == TOON_CUTOUT_SHADER or (m as ShaderMaterial).shader == SURFACE_SHADER)


## Base colour of an imported material (BaseMaterial3D albedo, or our own albedo parameter).
static func base_color_of(m: Material) -> Color:
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).albedo_color
	if m is ShaderMaterial:
		var v: Variant = (m as ShaderMaterial).get_shader_parameter(&"albedo")
		if v is Color:
			return v
		v = (m as ShaderMaterial).get_shader_parameter(&"color")
		if v is Color:
			return v
	return Color(0.8, 0.8, 0.8)


## Material name used for styling: resource_name as exported from Blender (".001" suffixes dropped).
static func material_name(m: Material) -> String:
	if m == null:
		return ""
	var n := m.resource_name
	var dot := n.rfind(".")
	if dot > 0 and n.substr(dot + 1).is_valid_int():
		n = n.substr(0, dot)
	return n


## Re-material every MeshInstance3D under `root` (root included): each surface gets a toon material
## with its imported base colour (and albedo texture) preserved, `*_glow` surfaces become unlit
## emissive, every non-glow surface gets the ink outline. Returns the materials it created by
## material name (several surfaces with one name share one material), so callers can tint or pulse
## them later (e.g. "headphones_glow" in a self's cassette colour).
static func apply_toon(root: Node, opts: Options = null) -> Dictionary[String, ShaderMaterial]:
	if opts == null:
		opts = Options.new()
	var made: Dictionary[String, ShaderMaterial] = {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if opts.bake_smooth_normals and opts.outline_px > 0.0 and not is_skinned(mi):
			mi.mesh = bake_smooth_normals(mi.mesh)
		for s: int in range(mi.mesh.get_surface_count()):
			var src: Material = mi.get_surface_override_material(s)
			if src == null:
				src = mi.mesh.surface_get_material(s)
			var mname := material_name(src)
			var mat: ShaderMaterial = made.get(mname, null) if not mname.is_empty() else null
			if mat == null:
				mat = _toon_for(src, mname, opts)
				if not mname.is_empty():
					made[mname] = mat
			mi.set_surface_override_material(s, mat)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if opts.cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if opts.layers != 0:
			mi.layers = opts.layers
	return made


static func _toon_for(src: Material, mname: String, opts: Options) -> ShaderMaterial:
	var col := base_color_of(src)
	if opts.color_by_name.has(mname):
		col = opts.color_by_name[mname]
	if mname.ends_with(opts.glow_suffix):
		var g := glow(col, opts.glow_energy)
		g.resource_name = mname
		return g
	var m := toon(col, opts.outline_px, opts.outline_color)
	m.resource_name = mname
	if src is BaseMaterial3D:
		var b := src as BaseMaterial3D
		if b.albedo_texture != null:
			m.set_shader_parameter(&"albedo_texture", b.albedo_texture)
			m.set_shader_parameter(&"use_albedo_texture", true)
		if b.emission_enabled:
			m.set_shader_parameter(&"emission", b.emission)
			m.set_shader_parameter(&"emission_energy", b.emission_energy_multiplier)
		if b.vertex_color_use_as_albedo:
			m.set_shader_parameter(&"vertex_color_mix", 1.0)
		else:
			m.set_shader_parameter(&"vertex_color_mix", 0.0)
	if opts.xray:
		with_xray(m, opts.xray_color)
	return m


## True when the mesh instance is skinned (a Skin resource, or bone weights in any surface).
## MeshInstance3D.skeleton defaults to "..", so the node path alone says nothing.
static func is_skinned(mi: MeshInstance3D) -> bool:
	if mi.skin != null:
		return true
	if mi.mesh == null:
		return false
	for s: int in range(mi.mesh.get_surface_count()):
		var arrays := mi.mesh.surface_get_arrays(s)
		if arrays.size() > Mesh.ARRAY_BONES and arrays[Mesh.ARRAY_BONES] != null:
			return true
	return false


## A copy of `mesh` whose surfaces carry a smoothed normal (average of every face normal meeting at
## a position) in CUSTOM0, so the inverted-hull outline stays closed on hard-edged meshes. Surface
## materials and names are kept. Meshes that already have CUSTOM0 are returned unchanged.
static func bake_smooth_normals(mesh: Mesh) -> Mesh:
	if mesh == null or mesh.get_surface_count() == 0:
		return mesh
	if mesh.has_meta(&"od_smooth_normals"):
		return mesh
	var out := ArrayMesh.new()
	out.resource_name = mesh.resource_name
	var shape_count := (mesh as ArrayMesh).get_blend_shape_count() if mesh is ArrayMesh else 0
	for bi: int in range(shape_count):
		out.add_blend_shape((mesh as ArrayMesh).get_blend_shape_name(bi))
	if shape_count > 0:
		out.blend_shape_mode = (mesh as ArrayMesh).blend_shape_mode
	for s: int in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(s)
		var prim := Mesh.PRIMITIVE_TRIANGLES
		if mesh is ArrayMesh:
			prim = (mesh as ArrayMesh).surface_get_primitive_type(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
		var flags := 0
		if prim == Mesh.PRIMITIVE_TRIANGLES and normals is PackedVector3Array and arrays[Mesh.ARRAY_CUSTOM0] == null:
			var nrm: PackedVector3Array = normals
			var sums: Dictionary[Vector3i, Vector3] = {}
			for i: int in range(verts.size()):
				var key := Vector3i((verts[i] * 1000.0).round())
				sums[key] = sums.get(key, Vector3.ZERO) + nrm[i]
			var custom := PackedFloat32Array()
			custom.resize(verts.size() * 4)
			for i: int in range(verts.size()):
				var sn: Vector3 = sums[Vector3i((verts[i] * 1000.0).round())]
				sn = sn.normalized() if sn.length_squared() > 1e-8 else nrm[i]
				custom[i * 4] = sn.x
				custom[i * 4 + 1] = sn.y
				custom[i * 4 + 2] = sn.z
				custom[i * 4 + 3] = 1.0
			arrays[Mesh.ARRAY_CUSTOM0] = custom
			flags = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		var blend: Array = []
		if shape_count > 0:
			blend = mesh.surface_get_blend_shape_arrays(s)
		out.add_surface_from_arrays(prim, arrays, blend, {}, flags)
		out.surface_set_material(s, mesh.surface_get_material(s))
		if mesh is ArrayMesh:
			out.surface_set_name(s, (mesh as ArrayMesh).surface_get_name(s))
	out.set_meta(&"od_smooth_normals", true)
	return out


static func _set_lighting(m: ShaderMaterial) -> void:
	m.set_shader_parameter(&"toon_ramp", ramp())
	m.set_shader_parameter(&"shadow_tint", theme_shadow_tint)
