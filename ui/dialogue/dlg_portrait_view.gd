class_name DlgPortraitView
extends Control
## A portrait in a fixed frame: the texture is aspect-fitted to this Control's square, bottom-aligned,
## so swapping expressions (or speakers) never moves the frame. A missing texture draws a coloured
## initial instead. A swap plays a short pop (scale about the bottom centre, no cross-fade:
## INTEGRATION.md). `radio` overlays scanlines for voices in Moxie's headphones.

const POP_TIME := 0.14
## Head crop for round bark chips, in 1024 px portrait space (assets/portraits/README.md).
const CHIP_REGION := Rect2(162, 20, 700, 700)
const CHIP_REGION_BASE := 1024.0
## Radio treatment: cyan scanlines over the silhouette only (alpha-masked), drifting slowly.
const RADIO_SHADER := """
shader_type canvas_item;
uniform float strength = 0.16;
uniform float spacing = 3.0;
uniform float offset = 0.0;
void fragment() {
	float line = step(0.5, fract((FRAGCOORD.y + offset) / spacing));
	COLOR.rgb = mix(COLOR.rgb, vec3(0.31, 0.95, 1.0), strength * line);
}
"""

static var _radio_shader: Shader = null
var _radio_mat: ShaderMaterial = null

var texture: Texture2D = null
var color: Color = UiPalette.PAPER
var initial: String = "?"
## Mirror horizontally (Character.mirror; off by default, the art already faces the text).
var flip: bool = false
var radio: bool = false
## Draw the inked frame plate behind the bust (dialogue box) or a round chip (barks).
var round_chip: bool = false
var time: float = 0.0
var _pop: float = 0.0
var _key: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Set the speaker / expression. Returns true when the picture changed (and pops).
func show_portrait(key: String, tex: Texture2D, col: Color, name_text: String, p_flip: bool, p_radio: bool) -> bool:
	var changed := key != _key
	_key = key
	texture = tex
	color = col
	initial = name_text.substr(0, 1).to_upper() if name_text != "" else "?"
	flip = p_flip
	radio = p_radio
	_apply_radio()
	if changed:
		_pop = POP_TIME
	queue_redraw()
	return changed


func is_fallback() -> bool:
	return texture == null


func _apply_radio() -> void:
	if not radio:
		material = null
		return
	if _radio_shader == null:
		_radio_shader = Shader.new()
		_radio_shader.code = RADIO_SHADER
	if _radio_mat == null:
		_radio_mat = ShaderMaterial.new()
		_radio_mat.shader = _radio_shader
	material = _radio_mat


func _process(delta: float) -> void:
	time += delta
	if _radio_mat != null and radio:
		_radio_mat.set_shader_parameter("spacing", maxf(3.0, size.y / 60.0))
		_radio_mat.set_shader_parameter("offset", fmod(time * 18.0, 1000.0))
	if _pop > 0.0:
		_pop = maxf(0.0, _pop - delta)
		queue_redraw()


func _draw() -> void:
	var s := size
	if s.x < 2.0 or s.y < 2.0:
		return
	var k := 1.0
	if _pop > 0.0:
		var p := 1.0 - _pop / POP_TIME
		k = 1.0 + 0.06 * sin(p * PI)
	var pivot := Vector2(s.x * 0.5, s.y)
	draw_set_transform(pivot - pivot * k, 0.0, Vector2(k, k))
	if round_chip:
		var c := s * 0.5
		var r := minf(s.x, s.y) * 0.5
		draw_circle(c, r, UiPalette.INK)
		draw_circle(c, r - maxf(2.0, r * 0.08), color.darkened(0.55))
	if texture != null:
		var ts := texture.get_size()
		# Chips show the head only (README crop); the box shows the whole bust.
		var src := Rect2(Vector2.ZERO, ts)
		if round_chip and absf(ts.x - ts.y) < 1.0:
			var k2 := ts.x / CHIP_REGION_BASE
			src = Rect2(CHIP_REGION.position * k2, CHIP_REGION.size * k2)
		var fit := minf(s.x / src.size.x, s.y / src.size.y)
		if round_chip:
			fit *= 0.94
		var ds := src.size * fit
		var pos := Vector2((s.x - ds.x) * 0.5, s.y - ds.y)
		if round_chip:
			pos.y = (s.y - ds.y) * 0.5
		var rect := Rect2(pos, ds)
		if flip:
			rect = Rect2(Vector2(pos.x + ds.x, pos.y), Vector2(-ds.x, ds.y))
		draw_texture_rect_region(texture, rect, src)
	else:
		_draw_initial(s)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_initial(s: Vector2) -> void:
	var d := minf(s.x, s.y)
	var c := Vector2(s.x * 0.5, s.y - d * 0.5)
	var r := d * 0.42
	draw_circle(c + Vector2(d * 0.03, d * 0.04), r, UiPalette.INK)
	draw_circle(c, r, color)
	draw_arc(c, r, 0.0, TAU, 48, UiPalette.INK, maxf(2.0, d * 0.03), true)
	var f := UiPalette.font_display()
	var fs := roundi(r * 1.15)
	var ts := f.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var base := Vector2(c.x - ts.x * 0.5, c.y + f.get_ascent(fs) * 0.5 - f.get_descent(fs) * 0.25)
	draw_string(f, base, initial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiPalette.INK)
