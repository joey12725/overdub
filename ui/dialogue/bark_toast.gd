class_name BarkToast
extends Control
## A non-blocking speech toast: a round portrait chip plus a short line in a speech bubble, about two
## seconds, near Moxie's deck (or over her head through a world anchor). It never takes input and
## never covers the `avoid` rects (the beat ruler). One bark at a time; a second one waits (at most one
## waiting, newer replaces older).
##
##   toast.show_bark(line, character, texture)
##   toast.anchor_rect = Rect2(...)    # local coordinates; has_anchor = false -> lower left corner
##   toast.avoid = [ruler_rect]

signal bark_started(line: DlgLine)
signal bark_finished(line: DlgLine)

const IN_TIME := 0.16
const OUT_TIME := 0.28

var anchor_rect: Rect2 = Rect2()
var has_anchor: bool = false
var avoid: Array[Rect2] = []
var unit: float = 14.0

var chip: DlgPortraitView = null
var _line: DlgLine = null
var _ch: DlgStoryData.Character = null
var _tex: Texture2D = null
var _next: Array = []
var _t: float = 0.0
var _hold: float = 0.0
var _bubble: Rect2 = Rect2()
var _side: String = "above"
var _wrapped: PackedStringArray = PackedStringArray()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	chip = DlgPortraitView.new()
	chip.name = "Chip"
	chip.round_chip = true
	chip.visible = false
	add_child(chip)


func is_showing() -> bool:
	return _line != null


func current_line() -> DlgLine:
	return _line


## Show now if idle, else wait behind the current bark.
func show_bark(line: DlgLine, ch: DlgStoryData.Character, tex: Texture2D) -> void:
	if _line != null:
		_next = [line, ch, tex]
		return
	_begin(line, ch, tex)


func clear() -> void:
	var was := _line
	_line = null
	_next = []
	chip.visible = false
	queue_redraw()
	if was != null:
		bark_finished.emit(was)


## Seconds a line stays fully visible.
static func hold_for(text: String) -> float:
	return clampf(1.5 + text.length() * 0.035, 1.8, 3.6)


## The bubble rect (local) of the bark on screen, for tests.
func bubble_rect() -> Rect2:
	return _bubble


func _begin(line: DlgLine, ch: DlgStoryData.Character, tex: Texture2D) -> void:
	_line = line
	_ch = ch
	_tex = tex
	_t = 0.0
	_hold = hold_for(line.line)
	chip.visible = true
	chip.show_portrait(ch.id + "." + line.expression, tex, ch.color, ch.name, false, ch.radio)
	_relayout()
	bark_started.emit(line)


func _process(delta: float) -> void:
	if _line == null:
		return
	_t += delta
	if _t >= IN_TIME + _hold + OUT_TIME:
		var done := _line
		_line = null
		chip.visible = false
		bark_finished.emit(done)
		if not _next.is_empty():
			var n := _next
			_next = []
			_begin(n[0], n[1], n[2])
		queue_redraw()
		return
	_relayout()
	queue_redraw()


func _alpha() -> float:
	if _t < IN_TIME:
		return _t / IN_TIME
	if _t > IN_TIME + _hold:
		return clampf(1.0 - (_t - IN_TIME - _hold) / OUT_TIME, 0.0, 1.0)
	return 1.0


func _relayout() -> void:
	var s := size
	if s.x < 2.0 or s.y < 2.0:
		s = get_viewport_rect().size
	unit = UiPalette.unit_for(s)
	var u := unit
	var f := UiPalette.font_ui()
	var fs := roundi(u * 1.15 * UiPalette.text_scale)
	var max_text := u * 20.0
	_wrapped = _wrap(f, _line.line if _line != null else "", fs, max_text)
	var tw := 0.0
	for w: String in _wrapped:
		tw = maxf(tw, f.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var line_h := f.get_height(fs) * 1.1
	var chip_d := u * 3.6
	var bw := chip_d + u * 0.9 + tw + u * 1.6
	var bh := maxf(chip_d + u * 0.6, line_h * _wrapped.size() + u * 1.3)
	var screen := Rect2(Vector2.ZERO, s)
	var a := anchor_rect if has_anchor else Rect2(Vector2(u * 2.0, s.y * 0.72), Vector2(u * 8.0, u * 2.0))
	var pl := CoachLayout.place(a, true, Vector2(bw, bh), screen, avoid, "above", u * 0.9, u)
	_bubble = pl.rect
	_side = pl.side
	# a small rise on entry
	var rise := (1.0 - minf(1.0, _t / IN_TIME)) * u * 0.8
	_bubble.position.y += rise
	chip.size = Vector2(chip_d, chip_d)
	chip.position = Vector2(_bubble.position.x + u * 0.35, _bubble.position.y + (bh - chip_d) * 0.5)
	chip.modulate = Color(1, 1, 1, _alpha())


static func _wrap(f: Font, text: String, fs: int, max_w: float) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	for w: String in text.split(" ", false):
		var tryl := w if cur == "" else cur + " " + w
		if cur != "" and f.get_string_size(tryl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
			out.append(cur)
			cur = w
		else:
			cur = tryl
	if cur != "":
		out.append(cur)
	return out


func _draw() -> void:
	if _line == null:
		return
	var u := unit
	var a := _alpha()
	var r := _bubble
	var col := _ch.color if _ch != null else UiPalette.MOXIE_YELLOW
	draw_rect(Rect2(r.position + Vector2(u * 0.25, u * 0.3), r.size), Color(UiPalette.INK, 0.85 * a))
	draw_rect(r, Color(UiPalette.PANEL_SOLID, 0.96 * a))
	draw_rect(r, Color(UiPalette.INK, a), false, maxf(2.0, roundf(u * 0.18)))
	draw_rect(Rect2(r.position, Vector2(maxf(3.0, u * 0.3), r.size.y)), Color(col, a))
	# tail toward the anchor
	var tail_x := clampf((anchor_rect.get_center().x if has_anchor else r.position.x + u * 4.0), r.position.x + u * 1.5, r.end.x - u * 1.5)
	var tri: PackedVector2Array
	if _side == "below":
		tri = PackedVector2Array([Vector2(tail_x - u * 0.6, r.position.y), Vector2(tail_x + u * 0.6, r.position.y), Vector2(tail_x, r.position.y - u * 0.8)])
	else:
		tri = PackedVector2Array([Vector2(tail_x - u * 0.6, r.end.y), Vector2(tail_x + u * 0.6, r.end.y), Vector2(tail_x, r.end.y + u * 0.8)])
	draw_colored_polygon(tri, Color(UiPalette.PANEL_SOLID, 0.96 * a))
	var f := UiPalette.font_ui()
	var fs := roundi(u * 1.15 * UiPalette.text_scale)
	var line_h := f.get_height(fs) * 1.1
	var tx := r.position.x + u * 3.6 + u * 0.9
	var block_h := line_h * _wrapped.size()
	var ty := r.position.y + (r.size.y - block_h) * 0.5 + f.get_ascent(fs)
	for i in _wrapped.size():
		draw_string(f, Vector2(tx, ty + line_h * i), _wrapped[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiPalette.PAPER, a))
