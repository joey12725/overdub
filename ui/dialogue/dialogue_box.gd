class_name DialogueBox
extends Control
## The dialogue box: an inked panel at the bottom of the screen with the speaker's portrait (Moxie on
## the left, everyone else on the right: INTEGRATION.md), a name tab in the character's colour,
## typewriter text, an advance cue, a fast-forward cue and a hold-to-skip control. It only draws; the
## DialoguePlayer owns the sequence and feeds it state. Sized in UI units (UiPalette.unit_for) so it
## lays out the same from 1280x720 to 4K. The panel is the generated inked panel
## (assets/ui/art/ui/panel.png, 9-slice margins from slices.json) when present, else a flat panel.
## The speaker tab stays drawn in code: it sits over the text column (not the portrait) and takes
## the character's colour, which the yellow-only dialogue_box.png / name_tab.png art cannot.
##
## Portrait geometry depends only on the box size and the side, never on the texture, so expression
## swaps never jump.

signal accept_clicked
signal skip_clicked

const ART_PANEL := "res://assets/ui/art/ui/panel.png"

var portrait: DlgPortraitView = null
var text_label: Label = null

var speaker_name: String = ""
var speaker_color: Color = UiPalette.MOXIE_YELLOW
var portrait_left: bool = true
var radio: bool = false
var radio_cut: bool = false
var waiting: bool = false
var fast: bool = false
var skip_progress: float = 0.0
var accept_label: String = "Enter"
var skip_label: String = "Esc"
var time: float = 0.0
var unit: float = 14.0
var _static_t: float = 0.0
var _art: Texture2D = null
var _skip_rect: Rect2 = Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	portrait = DlgPortraitView.new()
	portrait.name = "Portrait"
	add_child(portrait)
	text_label = Label.new()
	text_label.name = "Text"
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	text_label.visible_characters_behavior = TextServer.VC_CHARS_BEFORE_SHAPING
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_label.add_theme_font_override("font", UiPalette.font_ui())
	text_label.add_theme_color_override("font_color", UiPalette.PAPER)
	text_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	text_label.add_theme_constant_override("shadow_offset_x", 0)
	text_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(text_label)
	_art = UiArt.tex(ART_PANEL)
	resized.connect(_layout)
	_layout()


## Show a line: speaker, portrait texture (null = initial), full text (typed via set_visible_chars).
func show_line(line: DlgLine, ch: DlgStoryData.Character, tex: Texture2D) -> void:
	speaker_name = ch.name
	speaker_color = ch.color
	portrait_left = ch.left
	radio = ch.radio
	radio_cut = line.is_radio_cut()
	_static_t = 0.0
	text_label.text = line.line
	text_label.visible_characters = 0
	waiting = false
	portrait.show_portrait(ch.id + "." + line.expression, tex, ch.color, ch.name, ch.mirror, ch.radio)
	_layout()
	queue_redraw()


func set_visible_chars(n: int) -> void:
	if text_label.visible_characters != n:
		text_label.visible_characters = n


func set_waiting(w: bool) -> void:
	if w and not waiting and radio_cut:
		_static_t = 0.3
	waiting = w


func _process(delta: float) -> void:
	time += delta
	if _static_t > 0.0:
		_static_t = maxf(0.0, _static_t - delta)
	queue_redraw()


# ───────────────────────────── geometry ─────────────────────────────

## The area the box lays out in: its own size, or the viewport while it has not been sized yet.
## (Never assigned back to `size`: with full-rect anchors that would become a permanent offset.)
func area() -> Vector2:
	var s := size
	if (s.x < 2.0 or s.y < 2.0) and is_inside_tree():
		s = get_viewport_rect().size
	return s


func box_rect() -> Rect2:
	var s := area()
	var u := unit
	var margin := u * 1.6
	var w := minf(s.x - margin * 2.0, u * 64.0)
	var h := u * 7.6
	return Rect2(Vector2((s.x - w) * 0.5, s.y - margin * 1.2 - h), Vector2(w, h))


func portrait_rect() -> Rect2:
	var b := box_rect()
	var p := unit * 12.5
	var inset := unit * 0.8
	var x := b.position.x + inset if portrait_left else b.end.x - inset - p
	return Rect2(Vector2(x, b.end.y - p - unit * 0.35), Vector2(p, p))


func text_rect() -> Rect2:
	var b := box_rect()
	var p := unit * 12.5
	var pad := unit * 1.5
	var x := b.position.x + p + pad * 1.4 if portrait_left else b.position.x + pad * 1.4
	var w := b.size.x - p - pad * 2.8
	return Rect2(Vector2(x, b.position.y + unit * 1.55), Vector2(w, b.size.y - unit * 2.6))


func tab_rect() -> Rect2:
	var t := text_rect()
	var f := UiPalette.font_display()
	var fs := roundi(unit * 1.2)
	var w := f.get_string_size(speaker_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + unit * 2.0
	var h := unit * 2.2
	var b := box_rect()
	return Rect2(Vector2(t.position.x - unit * 0.4, b.position.y - h * 0.62), Vector2(w, h))


func skip_rect() -> Rect2:
	return _skip_rect


func _layout() -> void:
	if not is_node_ready():
		return
	var s := area()
	unit = UiPalette.unit_for(s)
	var pr := portrait_rect()
	portrait.position = pr.position
	portrait.size = pr.size
	var tr := text_rect()
	text_label.position = tr.position
	text_label.size = tr.size
	text_label.add_theme_font_size_override("font_size", roundi(unit * 1.5 * UiPalette.text_scale))
	text_label.add_theme_constant_override("line_spacing", roundi(unit * 0.15))
	var b := box_rect()
	var sw := unit * 9.0
	_skip_rect = Rect2(Vector2(b.end.x - sw - unit * 0.6, b.end.y + unit * 0.25), Vector2(sw, unit * 1.6))
	if _skip_rect.end.y > s.y:
		_skip_rect.position.y = b.position.y - unit * 1.9
	queue_redraw()


# ───────────────────────────── drawing ─────────────────────────────

func _draw() -> void:
	var u := unit
	var b := box_rect()
	var bw := maxf(2.0, roundf(u * 0.22))
	# hard offset shadow + panel
	draw_rect(Rect2(b.position + Vector2(u * 0.35, u * 0.4), b.size), Color(UiPalette.INK, 0.9))
	if _art != null:
		draw_style_box(_art_box(), b)
		draw_rect(b.grow(-u * 0.9), UiPalette.alpha(speaker_color, 0.3), false, maxf(1.0, bw * 0.5))
	else:
		draw_rect(b, UiPalette.PANEL_SOLID)
		draw_rect(b, UiPalette.INK, false, bw)
		draw_rect(b.grow(-bw * 1.5), UiPalette.alpha(speaker_color, 0.35), false, maxf(1.0, bw * 0.5))
	if radio:
		_draw_wave(b, u)
	_draw_tab(u)
	if _static_t > 0.0:
		_draw_static(text_rect(), u)
	if waiting:
		var a := 0.55 + 0.45 * sin(time * 6.0)
		var c := Vector2(b.end.x - u * 1.7, b.end.y - u * 1.2 + sin(time * 6.0) * u * 0.12)
		var tri := PackedVector2Array([c + Vector2(-u * 0.5, -u * 0.3), c + Vector2(u * 0.5, -u * 0.3), c + Vector2(0, u * 0.35)])
		draw_colored_polygon(tri, UiPalette.alpha(speaker_color, a))
	if fast:
		var f := UiPalette.font_mono()
		draw_string(f, Vector2(b.end.x - u * 4.2, b.position.y + u * 1.4), ">>", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(u * 1.0), UiPalette.alpha(UiPalette.PAPER, 0.7))
	_draw_skip(u)


func _art_box() -> StyleBoxTexture:
	var m := UiArt.margins("ui/panel.png")
	var sb := StyleBoxTexture.new()
	sb.texture = _art
	sb.texture_margin_left = m[0] if m[0] > 0.0 else 32.0
	sb.texture_margin_top = m[1] if m[1] > 0.0 else 32.0
	sb.texture_margin_right = m[2] if m[2] > 0.0 else 32.0
	sb.texture_margin_bottom = m[3] if m[3] > 0.0 else 32.0
	return sb


func _draw_tab(u: float) -> void:
	if speaker_name == "":
		return
	var r := tab_rect()
	draw_rect(Rect2(r.position + Vector2(u * 0.22, u * 0.25), r.size), UiPalette.INK)
	draw_rect(r, speaker_color)
	draw_rect(r, UiPalette.INK, false, maxf(2.0, roundf(u * 0.18)))
	var f := UiPalette.font_display()
	var fs := roundi(u * 1.2)
	var txt := speaker_name.to_upper()
	var ty := r.position.y + (r.size.y + f.get_ascent(fs) - f.get_descent(fs)) * 0.5
	var ink := UiPalette.INK if speaker_color.get_luminance() > 0.45 else UiPalette.PAPER
	draw_string(f, Vector2(r.position.x + u, ty), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


func _draw_wave(b: Rect2, u: float) -> void:
	var pts := PackedVector2Array()
	var n := 64
	for i in n + 1:
		var x := b.position.x + b.size.x * float(i) / n
		var y := b.position.y + sin(float(i) * 0.9 + time * 9.0) * u * 0.18 * (0.5 + 0.5 * sin(float(i) * 0.21 + time * 2.0))
		pts.append(Vector2(x, y))
	draw_polyline(pts, UiPalette.alpha(speaker_color, 0.8), maxf(1.5, u * 0.12), true)


func _draw_static(r: Rect2, u: float) -> void:
	var k := _static_t / 0.3
	var seed_i := int(time * 60.0)
	for i in 14:
		var h := (sin(float(seed_i * 31 + i * 17)) * 0.5 + 0.5)
		var y := r.position.y + h * r.size.y
		var w := r.size.x * (0.3 + 0.7 * fmod(h * 7.3, 1.0))
		draw_rect(Rect2(Vector2(r.position.x + (r.size.x - w) * fmod(h * 3.1, 1.0), y), Vector2(w, maxf(1.0, u * 0.12))), Color(UiPalette.PAPER, 0.35 * k))


func _draw_skip(u: float) -> void:
	var r := _skip_rect
	var f := UiPalette.font_ui()
	var fs := roundi(u * 0.95)
	var key := skip_label
	var kf := UiPalette.font_mono()
	var kw := kf.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + u * 0.9
	var label := "hold to skip"
	var lw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var total := kw + u * 0.5 + lw + u * 1.9
	var x := r.end.x - total
	var cy := r.get_center().y
	var key_r := Rect2(Vector2(x, cy - u * 0.65), Vector2(kw, u * 1.3))
	draw_rect(key_r, UiPalette.PAPER)
	draw_rect(key_r, UiPalette.INK, false, maxf(1.0, u * 0.1))
	draw_string(kf, Vector2(x + u * 0.45, cy + kf.get_ascent(fs) * 0.38), key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiPalette.INK)
	draw_string(f, Vector2(x + kw + u * 0.5, cy + f.get_ascent(fs) * 0.38), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiPalette.alpha(UiPalette.PAPER, 0.8))
	var rc := Vector2(r.end.x - u * 0.7, cy)
	var rr := u * 0.55
	draw_arc(rc, rr, 0.0, TAU, 32, Color(UiPalette.PAPER, 0.25), maxf(2.0, u * 0.16), true)
	if skip_progress > 0.0:
		draw_arc(rc, rr, -PI * 0.5, -PI * 0.5 + TAU * skip_progress, 32, UiPalette.MOXIE_YELLOW, maxf(2.0, u * 0.16), true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _skip_rect.grow(unit * 0.4).has_point(mb.position):
				skip_clicked.emit()
			else:
				accept_clicked.emit()
			accept_event()
