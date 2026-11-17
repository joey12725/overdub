class_name DlgHintCard
extends Control
## The failure hint on the decision screen: a small paper card with a "TIP" sticker, placed under the
## HUD's decision panel (anchor "decision"; ONBOARDING.md "under the notes list") without covering it,
## the dock or the ruler. Never takes input.

var anchors: CoachAnchors = null
## Rects to keep clear (DialogueLayer passes CoachLayer.avoid_rects()); the ruler alone when empty.
var avoid: Array[Rect2] = []
var text: String = ""
var unit: float = 14.0
var _alpha: float = 0.0
var _lines: PackedStringArray = PackedStringArray()
var _rect: Rect2 = Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func show_hint(t: String) -> void:
	if t == text:
		return
	text = t
	_alpha = 0.0
	queue_redraw()


func clear() -> void:
	text = ""
	queue_redraw()


func is_showing() -> bool:
	return text != ""


func card_rect() -> Rect2:
	return _rect


func _process(delta: float) -> void:
	if text == "":
		return
	_alpha = minf(1.0, _alpha + delta / 0.25)
	_relayout()
	queue_redraw()


func _relayout() -> void:
	var s := size
	if s.x < 2.0 or s.y < 2.0:
		s = get_viewport_rect().size
	unit = UiPalette.unit_for(s)
	var u := unit
	var fs := roundi(u * 1.1 * UiPalette.text_scale)
	_lines = BarkToast._wrap(UiPalette.font_ui(), text, fs, u * 22.0)
	var w := 0.0
	for l: String in _lines:
		w = maxf(w, UiPalette.font_ui().get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var h := UiPalette.font_ui().get_height(fs) * 1.08 * _lines.size() + u * 3.2
	var sz := Vector2(maxf(w, u * 8.0) + u * 2.4, h)
	var anchor := Rect2()
	var ok := false
	var keep_clear: Array[Rect2] = avoid.duplicate()
	if anchors != null:
		var d := anchors.resolve("decision", self)
		ok = d.ok
		anchor = d.rect
		if keep_clear.is_empty():
			var r := anchors.resolve("ruler", self)
			if r.ok:
				keep_clear.append(r.rect)
	if not ok:
		anchor = Rect2(Vector2(s.x * 0.5 - u * 10.0, s.y * 0.35), Vector2(u * 20.0, u * 10.0))
	_rect = CoachLayout.place(anchor, true, sz, Rect2(Vector2.ZERO, s), keep_clear, "below", u, u).rect


func _draw() -> void:
	if text == "":
		return
	var u := unit
	var a := _alpha
	var r := _rect
	draw_rect(Rect2(r.position + Vector2(u * 0.3, u * 0.35), r.size), Color(UiPalette.INK, 0.9 * a))
	draw_rect(r, Color(UiPalette.PAPER, a))
	draw_rect(r, Color(UiPalette.INK, a), false, maxf(2.0, roundf(u * 0.2)))
	var fd := UiPalette.font_display()
	var fst := roundi(u * 0.95)
	var tag := "TIP"
	var tw := fd.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fst).x + u * 1.2
	var tr := Rect2(r.position + Vector2(u * 0.9, -u * 0.7), Vector2(tw, u * 1.6))
	draw_rect(tr, Color(UiPalette.MOXIE_YELLOW, a))
	draw_rect(tr, Color(UiPalette.INK, a), false, maxf(2.0, roundf(u * 0.15)))
	draw_string(fd, Vector2(tr.position.x + u * 0.6, tr.position.y + (tr.size.y + fd.get_ascent(fst) - fd.get_descent(fst)) * 0.5), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, fst, Color(UiPalette.INK, a))
	var fu := UiPalette.font_ui()
	var fs := roundi(u * 1.1 * UiPalette.text_scale)
	var y := r.position.y + u * 1.5
	for l: String in _lines:
		draw_string(fu, Vector2(r.position.x + u * 1.2, y + fu.get_ascent(fs)), l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiPalette.INK, a))
		y += fu.get_height(fs) * 1.08
