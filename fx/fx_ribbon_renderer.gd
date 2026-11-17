class_name FxRibbonRenderer
extends MeshInstance3D
## Per-tape colour ribbons trailing each self in the cinematic, so the four performances read as four
## voices (draws FxDirector.Ribbons). Rebuilt every frame as one ImmediateMesh surface: at most
## 4 x RIBBON_POINTS points, and nothing at all outside the cinematic (the director empties them).

const SHADER_LINE := preload("res://fx/shaders/fx_line.gdshader")

var _im := ImmediateMesh.new()
var _pts := PackedVector3Array()
var _cols := PackedColorArray()
var _widths := PackedFloat32Array()
var _time: float = 0.0
## Ribbons drawn last frame (diagnostics / tests).
var drawn: int = 0


func _init() -> void:
	name = "FxRibbons"
	mesh = _im
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_LINE
	# Additive: lifted so the voices still read on the pale upper-theme floors.
	mat.set_shader_parameter("gain", 1.6)
	mat.render_priority = 3
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true


func sync(rb: FxDirector.Ribbons, dt: float) -> void:
	_time += dt
	_im.clear_surfaces()
	drawn = 0
	var begun := false
	for t: int in 4:
		var n := rb.count[t]
		var alpha := rb.alpha[t]
		if n < 2 or alpha < 0.01:
			continue
		# Desynced selves' ribbons stutter; ghosts' are faint and greyed toward white.
		var flicker := (1.0 if sin(_time * 38.0 + t) > -0.2 else 0.25) if rb.state[t] == 2 else 1.0
		var base := OD.tape_color(t)
		if rb.state[t] == 1:
			base = Color(0.5 + base.r * 0.5, 0.5 + base.g * 0.5, 0.5 + base.b * 0.5)
		_pts.resize(n)
		_cols.resize(n)
		_widths.resize(n)
		for k: int in n:
			var p := rb.pts[rb.point_index(t, k)]
			_pts[k] = Vector3(p.x, p.y + t * 0.002, p.z)
			var f := float(k) / float(n - 1)
			# Widest a little behind the self, tapering both to the tail and into the self's feet so the
			# ring under her stays clean.
			var body := minf(1.0, (1.0 - f) * 8.0)
			_widths[k] = (0.05 + 0.26 * f) * (0.35 + 0.65 * body)
			_cols[k] = Color(base.r, base.g, base.b, 0.95 * pow(f, 1.3) * alpha * flicker)
		if not begun:
			_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			begun = true
		FxLineGeo.draw_immediate(_im, _pts, Vector3.UP, 0.1, base, false, _cols, _widths)
		drawn += 1
	if begun:
		_im.surface_end()
	visible = drawn > 0
