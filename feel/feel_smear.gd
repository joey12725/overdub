class_name FeelSmear
extends MeshInstance3D
## The weapon smear of one self: a ribbon swept along the REAL arc of the weapon, read from the
## grip metadata of the clip (FeelRig.arc_at), so it is exact at any tape speed, frame rate or scrub
## direction. Rebuilt each frame from [tail, head] clip fractions; drawn by shaders/smear.gdshader.

const SEGMENTS: int = 22

var _imesh: ImmediateMesh = ImmediateMesh.new()
var _mat: ShaderMaterial = ShaderMaterial.new()


func _init() -> void:
	mesh = _imesh
	_mat.shader = load("res://feel/shaders/smear.gdshader")
	_mat.render_priority = 8
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	visible = false


## Rebuild for clip `anim` shown at fraction `frac`, playing in `dir` (+1 / -1). `base` is the scene
## transform of the body (feet, facing), `body_scale` its size against the reference body,
## `weapon_len` the length of the weapon from the grip (scene units), `style` its FeelRig style.
func build(anim: Animation, frac: float, dir: int, heavy: bool, style: String, speed: float, base: Transform3D,
		body_scale: float, weapon_len: float, tint: Color) -> void:
	var env := FeelTune.smear_envelope(frac)
	if anim == null or env <= 0.0 or not anim.has_meta(&"od_grip"):
		visible = false
		return
	var span := FeelTune.smear_span(style, heavy, speed)
	var rng := FeelTune.smear_range(frac, span, dir)
	if absf(rng.y - rng.x) < 0.004:
		visible = false
		return
	var si := FeelTune.speed_index(speed)
	var inner: float = FeelTune.STYLE_SMEAR_INNER.get(style, 0.2)
	var look: int = FeelTune.STYLE_SMEAR_LOOK.get(style, 0)
	var k := body_scale
	_imesh.clear_surfaces()
	_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i: int in SEGMENTS + 1:
		var u := float(i) / float(SEGMENTS)
		var f := lerpf(rng.y, rng.x, u)             # u = 0 at the weapon, 1 at the tail
		var a := FeelRig.arc_at(anim, f)
		var grip := a[0] * k
		var w := a[1]
		var p_in := grip + w * (weapon_len * inner)
		var p_out := grip + w * weapon_len
		if look == 3:
			# Fist: a cone trailing behind the knuckles along the punch (edge) direction.
			var e := a[2]
			var side := w * 0.11 * k
			p_in = grip + e * 0.08 * k - side
			p_out = grip + e * 0.08 * k + side
		_imesh.surface_set_uv(Vector2(u, 0.0))
		_imesh.surface_add_vertex(base * p_in)
		_imesh.surface_set_uv(Vector2(u, 1.0))
		_imesh.surface_add_vertex(base * p_out)
	_imesh.surface_end()
	global_transform = Transform3D.IDENTITY
	_mat.set_shader_parameter(&"tint", tint)
	_mat.set_shader_parameter(&"strength", env)
	_mat.set_shader_parameter(&"weight", FeelTune.SPEED_SMEAR_WEIGHT[si] * (1.15 if heavy else 1.0))
	_mat.set_shader_parameter(&"echoes", float(FeelTune.SPEED_ECHOES[si]))
	_mat.set_shader_parameter(&"look", float(look))
	visible = true


func hide_smear() -> void:
	visible = false
