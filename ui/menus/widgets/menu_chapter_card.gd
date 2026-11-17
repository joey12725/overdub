class_name MenuChapterCard
extends Control
## Full-screen chapter card between levels (assets/ui/art/cards: wordless art, titles set in engine
## upper-left). Fades in, holds, fades out, then emits `finished`. Accept / cancel / a click cut it
## short. Mounted by UiRoot.show_chapter_card(theme); the game decides when a new chapter starts
## (first level of a LevelTheme on the descent).

signal finished

const FADE := 0.45

var theme_id: StringName = LevelTheme.UPPER
var hold: float = 2.6
var subtitle: String = ""
var _t: float = 0.0
var _tex: Texture2D = null
var _done: bool = false


func _init(p_theme: StringName = LevelTheme.UPPER, p_subtitle: String = "", p_hold: float = 2.6) -> void:
	theme_id = p_theme
	subtitle = p_subtitle
	hold = p_hold
	name = "ChapterCard"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_tex = UiArt.chapter_card(p_theme)


func duration() -> float:
	return FADE * 2.0 + hold


func seek(t: float) -> void:
	_t = t
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t >= duration():
		_finish()


func skip() -> void:
	if _t < FADE + hold:
		_t = FADE + hold


func _gui_input(e: InputEvent) -> void:
	var mb := e as InputEventMouseButton
	if mb != null and mb.pressed:
		accept_event()
		skip()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_accept") or e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		skip()


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
	queue_free()


func _draw() -> void:
	var a := clampf(minf(_t / FADE, (duration() - _t) / FADE), 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, a))
	if _tex != null:
		var ts := _tex.get_size()
		var zoom := 1.0 + clampf(_t / duration(), 0.0, 1.0) * 0.03
		var s := maxf(size.x / ts.x, size.y / ts.y) * zoom
		var d := ts * s
		draw_texture_rect(_tex, Rect2((size - d) * 0.5, d), false, Color(1, 1, 1, a))
	# Ink corner for the words.
	var w := size.x * 0.55
	var h := size.y * 0.42
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(0, h)]),
		PackedColorArray([Color(0, 0, 0, 0.75 * a), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]))
	var u := UiPalette.unit_for(size)
	var words := UiArt.chapter_title(theme_id)
	var slide := (1.0 - clampf((_t - FADE * 0.5) / FADE, 0.0, 1.0)) * u * 2.0
	var x := u * 3.0 - slide
	var mono := UiPalette.font_mono()
	var disp := MenuStyle.display_font()
	var accent := MenuStyle.theme_accent(theme_id)
	draw_string(mono, Vector2(x, u * 4.6), words[0], HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(u * 1.1), Color(accent, a))
	var fs := roundi(u * 3.4)
	draw_string(disp, Vector2(x + 4, u * 8.2 + 4), words[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(MenuStyle.PINK, a))
	draw_string(disp, Vector2(x, u * 8.2), words[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(MenuStyle.PAPER, a))
	if subtitle != "":
		# Ink outline: the art behind this corner can be pale stone or bright sky.
		draw_string_outline(MenuStyle.ui_italic_font(), Vector2(x, u * 10.2), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(u * 1.25), maxi(4, roundi(u * 0.35)), Color(MenuStyle.INK, a * 0.85))
		draw_string(MenuStyle.ui_italic_font(), Vector2(x, u * 10.2), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(u * 1.25), Color(MenuStyle.PAPER, a))
