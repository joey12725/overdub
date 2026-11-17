class_name FxOverlay
extends CanvasLayer
## Screen treatments drawn over the 3D world and under every UI layer: one full-screen ColorRect
## with fx/shaders/fx_overlay.gdshader, driven from FxDirector.ScreenState (letterbox easing in, the
## world-speed tint and speed lines, the bar-synced sweep, flashes, radial impact speed lines and the
## glitch tear). Hidden whenever nothing is active, so it costs nothing in plain play.

const SHADER := preload("res://fx/shaders/fx_overlay.gdshader")
## Below the game's UI CanvasLayer (which uses the default layer 1 or above).
const LAYER := -5

var rect: ColorRect
var _mat: ShaderMaterial
## True when the overlay drew anything last frame (diagnostics / tests).
var active: bool = false


func _init() -> void:
	name = "FxOverlay"
	layer = LAYER
	rect = ColorRect.new()
	rect.name = "Screen"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color.WHITE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	rect.material = _mat
	add_child(rect)
	rect.visible = false


func set_ink(c: Color) -> void:
	_mat.set_shader_parameter("ink", Vector3(c.r, c.g, c.b))


func sync(sc: FxDirector.ScreenState, camera: Camera3D) -> void:
	var vp_size := Vector2(1600.0, 900.0)
	if rect.is_inside_tree():
		vp_size = rect.get_viewport_rect().size
	var asp := vp_size.x / vp_size.y if vp_size.y > 0.0 else 16.0 / 9.0
	_mat.set_shader_parameter("aspect", asp)
	_mat.set_shader_parameter("time", sc.time)
	_mat.set_shader_parameter("letterbox", sc.letterbox)
	_mat.set_shader_parameter("flash", Vector4(sc.flash.r, sc.flash.g, sc.flash.b, sc.flash_a))
	_mat.set_shader_parameter("tint", Vector4(sc.tint.r, sc.tint.g, sc.tint.b, sc.tint_a))
	_mat.set_shader_parameter("speed", Vector2(sc.speed, sc.speed_sign))
	_mat.set_shader_parameter("sweep", Vector2(sc.sweep_pos, sc.sweep_a))
	var b := Vector3.ZERO
	if sc.burst_amt > 0.0 and camera != null and camera.is_inside_tree() and not camera.is_position_behind(sc.burst):
		var px := camera.unproject_position(sc.burst)
		b = Vector3(px.x / vp_size.x * 2.0 - 1.0, 1.0 - px.y / vp_size.y * 2.0, sc.burst_amt)
	_mat.set_shader_parameter("burst", b)
	_mat.set_shader_parameter("glitch", Vector4(sc.glitch_color.r, sc.glitch_color.g, sc.glitch_color.b, sc.glitch))
	active = sc.letterbox > 0.0005 or sc.flash_a > 0.002 or sc.tint_a > 0.001 or sc.speed > 0.001 or sc.sweep_a > 0.002 or b.z > 0.01 or sc.glitch > 0.01
	rect.visible = active
