class_name WorldPost
extends CanvasLayer
## Light screen pass over the 3D view (shaders/post.gdshader): per-theme grade, saturation,
## vignette, chromatic split and flash. Sits on canvas layer -1, so it draws over the 3D world and
## under the UI (which the game adds on a CanvasLayer >= 0).
##
## Fed every frame from RenderCtx.post (PostControls): `chromatic` and `flash` are kicks this class
## decays toward 0 (the PostControls contract), `saturation` and `vignette` are held values the fx
## layer owns. 'low' quality hides the pass entirely.

const SHADER := preload("res://shaders/post.gdshader")

var controls: PostControls = PostControls.new()
var enabled: bool = true
var _rect: ColorRect = null
var _mat: ShaderMaterial = null
var _base_vignette: float = 0.3
var _base_saturation: float = 1.0


func _init() -> void:
	layer = -1
	name = "Post"
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect = ColorRect.new()
	_rect.name = "Grade"
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


## Theme grade from the palette.
func set_palette(pal: WorldPalette) -> void:
	_mat.set_shader_parameter(&"grade_gain", pal.grade_gain)
	_mat.set_shader_parameter(&"grade_lift", pal.grade_lift)
	_mat.set_shader_parameter(&"contrast", pal.contrast)
	_mat.set_shader_parameter(&"vignette_color", pal.background.darkened(0.4))
	_base_vignette = pal.vignette_base
	_base_saturation = pal.saturation


func reset_controls() -> void:
	controls.chromatic = 0.0
	controls.flash = 0.0
	controls.flash_color = Color.WHITE
	controls.saturation = 1.0
	controls.vignette = 1.0


func set_enabled(on: bool) -> void:
	enabled = on
	_rect.visible = on


## Decay kicks and push the controls into the shader. Call once per rendered frame.
func update(dt: float) -> void:
	var c := controls
	c.chromatic = 0.0 if c.chromatic < 1e-3 else c.chromatic * exp(-dt * 6.0)
	c.flash = 0.0 if c.flash < 1e-3 else c.flash * exp(-dt * 8.0)
	if not enabled:
		return
	_mat.set_shader_parameter(&"vignette", _base_vignette * c.vignette)
	_mat.set_shader_parameter(&"saturation", _base_saturation * c.saturation)
	_mat.set_shader_parameter(&"chromatic", c.chromatic)
	_mat.set_shader_parameter(&"flash", c.flash)
	_mat.set_shader_parameter(&"flash_color", c.flash_color)
