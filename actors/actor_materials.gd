class_name ActorMaterials
extends RefCounted
## The actor layer's shaders and shared materials (prototype render/actors/materials.ts).
##
## Bodies: one ShaderMaterial pair per contract material (opaque `solid` + translucent `fx`), shared
## by every self / enemy that uses that material; per-instance state (cassette colour, opacity,
## hologram, phase, flash...) lives in instance uniforms set on each MeshInstance3D, so four selves
## share one set of materials. Pass chains:
##   solid: body -> outline -> x-ray
##   solid, identity (selves): body -> ink line -> cassette-coloured outline -> x-ray
##   fx:    body_fx -> outline_fx -> echo (red) -> echo (cyan) -> x-ray
## Flat markers, particles and trails use one material per blend mode with instance uniforms.

const SHADER_DIR: String = "res://actors/shaders/"

## Render priorities: hull after body, x-ray and overlays last.
const PRI_BODY: int = 0
const PRI_HULL: int = 1
const PRI_ECHO: int = 2
const PRI_DECAL: int = 3
const PRI_TRAIL: int = 6
const PRI_PARTICLE: int = 8
const PRI_XRAY: int = 20
const PRI_OVERLAY: int = 30

var flat_mix: ShaderMaterial
var flat_add: ShaderMaterial
var flat_overlay: ShaderMaterial
var flat_overlay_add: ShaderMaterial
var particle_mix: ShaderMaterial
var particle_add: ShaderMaterial
var particle_overlay: ShaderMaterial
var trail: ShaderMaterial
var outline: ShaderMaterial
var outline_fx: ShaderMaterial
var echo_a: ShaderMaterial
var echo_b: ShaderMaterial
var xray: ShaderMaterial
## Two-tier outline of a self: thin ink line, then the wider cassette-coloured hull behind it.
var ink: ShaderMaterial
var outline_id: ShaderMaterial
## Single-colour afterimage body (dodge echoes): flat translucent cassette colour.
var afterimage: ShaderMaterial
## A surface that is not drawn (ActorRig.apply_materials hidden_names).
var hidden: ShaderMaterial

var _body_shader: Shader
var _body_fx_shader: Shader
var _body_ds_shader: Shader
var _body_fx_ds_shader: Shader
var _bodies: Dictionary[String, Array] = {}
## How far the lit / shade tints close in on white for textured materials (painted cel shading).
const TEXTURED_CEL_SOFT: float = 0.62


## Outfit zones of a single-texture body (shader: actor_body.gdshaderinc `zone_*`).
class Zones:
	extends RefCounted
	## Material the zones apply to.
	var material: StringName = &"body"
	var tex_a: Texture2D = null
	var tex_b: Texture2D = null
	## Six linear tints, alpha = strength (0 leaves the painted zone alone).
	var tints: PackedColorArray = PackedColorArray()
	var lums: PackedFloat32Array = PackedFloat32Array()

	func key() -> String:
		var k := ""
		for c: Color in tints:
			k += c.to_html(true)
		return k

	func active() -> bool:
		if tex_a == null or tex_b == null:
			return false
		for c: Color in tints:
			if c.a > 0.001:
				return true
		return false
var _light_dir: Vector3 = Vector3(-0.45, 1.0, 0.55).normalized()
var _lit: Color = Color(1.0, 0.97, 0.92)
var _shade: Color = Color(0.55, 0.5, 0.68)
var _ramp: Texture2D = null


static func _shader(file: String) -> Shader:
	return load(SHADER_DIR + file) as Shader


static func _mat(file: String, priority: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader(file)
	m.render_priority = priority
	return m


func _init() -> void:
	_body_shader = _shader("actor_body.gdshader")
	_body_fx_shader = _shader("actor_body_fx.gdshader")
	_body_ds_shader = _shader("actor_body_ds.gdshader")
	_body_fx_ds_shader = _shader("actor_body_fx_ds.gdshader")
	flat_mix = _mat("actor_flat_mix.gdshader", PRI_DECAL)
	flat_add = _mat("actor_flat_add.gdshader", PRI_DECAL)
	flat_overlay = _mat("actor_flat_overlay.gdshader", PRI_OVERLAY)
	flat_overlay_add = _mat("actor_flat_overlay_add.gdshader", PRI_OVERLAY)
	particle_mix = _mat("actor_particle_mix.gdshader", PRI_PARTICLE)
	particle_add = _mat("actor_particle_add.gdshader", PRI_PARTICLE)
	particle_overlay = _mat("actor_particle_overlay.gdshader", PRI_OVERLAY + 5)
	trail = _mat("actor_trail.gdshader", PRI_TRAIL)
	outline = _mat("actor_outline.gdshader", PRI_HULL)
	outline_fx = _mat("actor_outline_fx.gdshader", PRI_HULL)
	echo_a = _mat("actor_echo.gdshader", PRI_ECHO)
	echo_a.set_shader_parameter(&"echo_tint", Color(1.0, 0.22, 0.32))
	echo_a.set_shader_parameter(&"echo_sign", 1.0)
	echo_b = _mat("actor_echo.gdshader", PRI_ECHO)
	echo_b.set_shader_parameter(&"echo_tint", Color(0.2, 0.95, 1.0))
	echo_b.set_shader_parameter(&"echo_sign", -1.0)
	xray = _mat("actor_xray.gdshader", PRI_XRAY)
	outline.next_pass = xray
	outline_id = _mat("actor_outline.gdshader", PRI_HULL)
	outline_id.set_shader_parameter(&"depth_push", 0.06)
	outline_id.next_pass = xray
	ink = _mat("actor_ink.gdshader", PRI_HULL)
	ink.next_pass = outline_id
	outline_fx.next_pass = echo_a
	echo_a.next_pass = echo_b
	echo_b.next_pass = xray
	afterimage = _mat("actor_flat_add.gdshader", PRI_ECHO)
	hidden = _mat("actor_hidden.gdshader", PRI_BODY)


## Derive lit / shade tints from the theme palette so actors sit in the room's light, clamped toward
## neutral so characters stay readable whatever the room does (materials.ts applyPaletteLight).
func set_palette(pal: ThemePalette, ramp: Texture2D) -> void:
	var k := clampf(0.55 + pal.key_intensity * 0.35, 0.85, 1.25)
	_lit = Color(1, 1, 1).lerp(pal.key_light, 0.25) * k
	var a := clampf(0.35 + pal.ambient_intensity * 0.3, 0.5, 0.75)
	_shade = Color(0.62, 0.58, 0.78).lerp(pal.ambient, 0.3) * (a / 0.62)
	_lit.a = 1.0
	_shade.a = 1.0
	_ramp = ramp
	ink.set_shader_parameter(&"ink_color", pal.ink)
	for key: String in _bodies:
		for m: ShaderMaterial in _bodies[key]:
			_apply_light(m)


func _apply_light(m: ShaderMaterial) -> void:
	m.set_shader_parameter(&"light_dir", _light_dir)
	m.set_shader_parameter(&"lit_col", _lit)
	m.set_shader_parameter(&"shade_col", _shade)
	m.set_shader_parameter(&"has_ramp", 1.0 if _ramp != null else 0.0)
	if _ramp != null:
		m.set_shader_parameter(&"ramp", _ramp)


## [solid, fx] body materials for a base colour (and optional albedo texture); cached by colour,
## texture and flags. `double_sided` for materials imported as double-sided (open sheets).
## `identity`: the two-tier outline of a self (ink line + cassette-coloured hull). `zones`: outfit
## zone tints for a single-texture body.
func body_pair(albedo: Color, is_glow: bool, is_accent: bool, tex: Texture2D = null, double_sided: bool = false,
		identity: bool = false, zones: Zones = null) -> Array:
	var zoned := zones != null and tex != null and zones.active()
	var key := "%s|%d|%d|%d|%s|%d|%s" % [albedo.to_html(false), int(is_glow), int(is_accent), int(double_sided),
		str(tex.get_rid()) if tex != null else "", int(identity), zones.key() if zoned else ""]
	if _bodies.has(key):
		return _bodies[key]
	var solid := ShaderMaterial.new()
	solid.shader = _body_ds_shader if double_sided else _body_shader
	solid.render_priority = PRI_BODY
	var fx := ShaderMaterial.new()
	fx.shader = _body_fx_ds_shader if double_sided else _body_fx_shader
	fx.render_priority = PRI_BODY
	for m: ShaderMaterial in [solid, fx]:
		m.set_shader_parameter(&"albedo", albedo)
		m.set_shader_parameter(&"is_glow", 1.0 if is_glow else 0.0)
		m.set_shader_parameter(&"is_accent", 1.0 if is_accent else 0.0)
		m.set_shader_parameter(&"has_tex", 1.0 if tex != null else 0.0)
		if tex != null:
			m.set_shader_parameter(&"albedo_tex", tex)
			m.set_shader_parameter(&"cel_soft", TEXTURED_CEL_SOFT)
		if zoned:
			m.set_shader_parameter(&"has_zones", 1.0)
			m.set_shader_parameter(&"zone_a", zones.tex_a)
			m.set_shader_parameter(&"zone_b", zones.tex_b)
			m.set_shader_parameter(&"zone_tint", zones.tints)
			m.set_shader_parameter(&"zone_lum", zones.lums)
		_apply_light(m)
	solid.next_pass = ink if identity else outline
	fx.next_pass = outline_fx
	var pair: Array = [solid, fx]
	_bodies[key] = pair
	return pair
