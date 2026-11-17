class_name HudDraw
extends RefCounted
## Shared inked drawing primitives for the HUD widgets: sticker panels with hard ink shadows,
## outlined display text, keycaps / face buttons, state badges (icon + word + tone), hatches and the
## colour-blind cassette patterns. Everything draws onto the CanvasItem passed in, from _draw().

static var _boxes: Dictionary = {}


## A rounded panel with a chunky border and an optional hard ink shadow (sticker look).
static func panel(ci: CanvasItem, r: Rect2, bg: Color, border: Color, border_w: float, radius: float, shadow: float = 0.0, shadow_color: Color = UiPalette.INK) -> void:
	if r.size.x <= 0.5 or r.size.y <= 0.5:
		return
	var key := "%s|%s|%d|%d|%d|%s" % [bg.to_html(), border.to_html(), roundi(border_w), roundi(radius), roundi(shadow), shadow_color.to_html()]
	var sb: StyleBoxFlat = _boxes.get(key)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = border
		sb.set_border_width_all(roundi(border_w))
		sb.set_corner_radius_all(roundi(radius))
		sb.anti_aliasing = true
		sb.corner_detail = 6
		if shadow > 0.0:
			sb.shadow_color = shadow_color
			sb.shadow_size = 0
			sb.shadow_offset = Vector2(shadow, shadow)
		if _boxes.size() > 512:
			_boxes.clear()
		_boxes[key] = sb
	sb.draw(ci.get_canvas_item(), r)


## Baseline y that vertically centres `size`-px text of `font` in a band starting at `top` of height `h`.
static func baseline_in(font: Font, size: int, top: float, h: float) -> float:
	var asc := font.get_ascent(size)
	var desc := font.get_descent(size)
	return top + (h - (asc + desc)) * 0.5 + asc


static func text_width(font: Font, text: String, size: int) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Largest font size <= `size` (and >= `min_size`) at which `text` fits in `max_w`.
static func fit_size(font: Font, text: String, size: int, max_w: float, min_size: int = 6) -> int:
	var s := size
	while s > min_size and text_width(font, text, s) > max_w:
		s -= 1
	return s


## `text` cut with an ellipsis so it fits `max_w`.
static func ellipsize(font: Font, text: String, size: int, max_w: float) -> String:
	if text_width(font, text, size) <= max_w:
		return text
	var t := text
	while t.length() > 1 and text_width(font, t + "…", size) > max_w:
		t = t.substr(0, t.length() - 1)
	return t.strip_edges() + "…"


## Text with an optional ink outline. `pos` is the left baseline point.
static func text(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, color: Color, outline: float = 0.0, outline_color: Color = UiPalette.INK) -> void:
	if outline > 0.0:
		ci.draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, roundi(outline), outline_color)
	ci.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Text centred (both axes) in `r`.
static func text_center(ci: CanvasItem, font: Font, r: Rect2, s: String, size: int, color: Color, outline: float = 0.0, outline_color: Color = UiPalette.INK) -> void:
	var w := text_width(font, s, size)
	var base := baseline_in(font, size, r.position.y, r.size.y)
	text(ci, font, Vector2(r.position.x + (r.size.x - w) * 0.5, base), s, size, color, outline, outline_color)


## Text rotated by `angle` around its centre `c` (sticker words).
static func text_rotated(ci: CanvasItem, font: Font, c: Vector2, s: String, size: int, color: Color, angle: float, outline: float = 0.0, scale: float = 1.0) -> void:
	var w := text_width(font, s, size)
	var asc := font.get_ascent(size)
	var desc := font.get_descent(size)
	ci.draw_set_transform(c, angle, Vector2(scale, scale))
	text(ci, font, Vector2(-w * 0.5, (asc - desc) * 0.5), s, size, color, outline)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


# ───────────────────────────── prompts ─────────────────────────────

static func keycap_width(p: ButtonPrompt, h: float) -> float:
	if p == null:
		return 0.0
	if _is_face(p.style):
		return h
	var size := roundi(h * 0.5)
	return maxf(h * 1.05, text_width(UiPalette.font_mono(), p.key, size) + h * 0.62)


static func _is_face(style: StringName) -> bool:
	return style == ButtonPrompt.STYLE_FACE_A or style == ButtonPrompt.STYLE_FACE_B or style == ButtonPrompt.STYLE_FACE_X or style == ButtonPrompt.STYLE_FACE_Y


## A keycap / gamepad button glyph with its left edge at `pos.x`, vertically centred on `pos.y`.
## Returns its width.
static func keycap(ci: CanvasItem, pos: Vector2, p: ButtonPrompt, h: float, dim: bool = false) -> float:
	if p == null:
		return 0.0
	var w := keycap_width(p, h)
	var r := Rect2(pos.x, pos.y - h * 0.5, w, h)
	var ink := UiPalette.INK
	var bw := maxf(1.5, h * 0.09)
	var a := 0.45 if dim else 1.0
	var font := UiPalette.font_mono()
	if _is_face(p.style):
		var col := UiPalette.FACE_A
		match p.style:
			ButtonPrompt.STYLE_FACE_B:
				col = UiPalette.FACE_B
			ButtonPrompt.STYLE_FACE_X:
				col = UiPalette.FACE_X
			ButtonPrompt.STYLE_FACE_Y:
				col = UiPalette.FACE_Y
		var c := r.get_center()
		ci.draw_circle(c + Vector2(0, h * 0.07), h * 0.5, UiPalette.alpha(ink, a), true, -1.0, true)
		ci.draw_circle(c, h * 0.5 - bw * 0.5, UiPalette.alpha(col, a), true, -1.0, true)
		ci.draw_arc(c, h * 0.5 - bw * 0.5, 0, TAU, 24, UiPalette.alpha(ink, a), bw, true)
		text_center(ci, UiPalette.font_display(), r, p.key, roundi(h * 0.52), UiPalette.alpha(ink, a))
		return w
	var bg := UiPalette.PAPER
	var radius := h * 0.22
	if p.style == ButtonPrompt.STYLE_SHOULDER or p.style == ButtonPrompt.STYLE_MENU:
		bg = UiPalette.FACE_NEUTRAL
		radius = h * 0.45
	# Key body with a thicker bottom lip.
	panel(ci, Rect2(r.position + Vector2(0, h * 0.1), r.size), UiPalette.alpha(ink, a), UiPalette.alpha(ink, a), 0, radius)
	panel(ci, Rect2(r.position, r.size - Vector2(0, h * 0.08)), UiPalette.alpha(bg, a), UiPalette.alpha(ink, a), bw, radius)
	text_center(ci, font, Rect2(r.position, r.size - Vector2(0, h * 0.1)), p.key, roundi(h * 0.5), UiPalette.alpha(ink, a))
	return w


## "[key] LABEL" prompt: keycap then the label in the display font. Returns total width.
static func prompt(ci: CanvasItem, pos: Vector2, pr: HudModel.Prompt, h: float, color: Color, label_size: int, dim: bool = false, show_label: bool = true) -> float:
	var w := keycap(ci, pos, pr.binding, h, dim)
	if not show_label:
		return w
	var font := UiPalette.font_display()
	var x := pos.x + w + h * 0.3
	var base := baseline_in(font, label_size, pos.y - h * 0.5, h)
	text(ci, font, Vector2(x, base), pr.label, label_size, UiPalette.alpha(color, 0.45 if dim else 1.0))
	return w + h * 0.3 + text_width(font, pr.label, label_size)


static func prompt_width(pr: HudModel.Prompt, h: float, label_size: int, show_label: bool = true) -> float:
	var w := keycap_width(pr.binding, h)
	if not show_label:
		return w
	return w + h * 0.3 + text_width(UiPalette.font_display(), pr.label, label_size)


# ───────────────────────────── badges ─────────────────────────────

## Background, text colour and inner-ring colour for a badge tone (HudModel.TONE_*).
static func tone_colors(tone: StringName, tape_color: Color) -> Array[Color]:
	match tone:
		HudModel.TONE_MUTED:
			return [UiPalette.MUTED, UiPalette.MUTED_TEXT, Color(0, 0, 0, 0)]
		HudModel.TONE_IDLE:
			return [UiPalette.MUTED, UiPalette.PAPER, Color(0, 0, 0, 0)]
		HudModel.TONE_ARMED:
			return [UiPalette.INK, tape_color, tape_color]
		HudModel.TONE_REC:
			return [UiPalette.REC_RED, Color.WHITE, Color(0, 0, 0, 0)]
		HudModel.TONE_PENDING:
			return [UiPalette.STATE_WARN, UiPalette.INK, Color(0, 0, 0, 0)]
		HudModel.TONE_LOCKED:
			return [UiPalette.PAPER, UiPalette.INK, Color(0, 0, 0, 0)]
		HudModel.TONE_GOOD:
			return [Color("#183a1c"), UiPalette.STATE_GOOD, Color(0, 0, 0, 0)]
		HudModel.TONE_DEAD:
			return [UiPalette.STATE_DEAD, UiPalette.INK, Color(0, 0, 0, 0)]
		HudModel.TONE_DESYNC:
			return [UiPalette.STATE_DESYNC, UiPalette.INK, Color(0, 0, 0, 0)]
		HudModel.TONE_WARN:
			return [UiPalette.STATE_WARN, UiPalette.INK, Color(0, 0, 0, 0)]
	return [UiPalette.MUTED, UiPalette.PAPER, Color(0, 0, 0, 0)]


static func badge_width(b: HudModel.Badge, h: float, compact: bool) -> float:
	var size := roundi(h * 0.58)
	return h * 0.32 + h * 0.78 + h * 0.22 + text_width(UiPalette.font_display(), b.short if compact else b.label, size) + h * 0.38


## A state badge: inked pill with icon + word in its tone. Left edge at r.position, at most
## r.size.x wide (the word is ellipsised to fit). Returns the width drawn.
static func badge(ci: CanvasItem, r: Rect2, b: HudModel.Badge, compact: bool, tape_color: Color, lamp_on: bool = true) -> float:
	if b == null:
		return 0.0
	var h := r.size.y
	var font := UiPalette.font_display()
	var size := roundi(h * 0.58)
	var words := b.short if compact else b.label
	var icon_s := h * 0.78
	var pad_l := h * 0.3
	var gap := h * 0.2
	var pad_r := h * 0.38
	var avail := r.size.x - pad_l - icon_s - gap - pad_r
	if avail < h * 0.8:
		# Too narrow for a word: icon only (never colour alone - the icon carries the meaning).
		var w0 := minf(r.size.x, h * 1.3)
		var cols0 := tone_colors(b.tone, tape_color)
		panel(ci, Rect2(r.position, Vector2(w0, h)), cols0[0], UiPalette.INK, maxf(1.5, h * 0.1), h * 0.28)
		HudIcons.draw_icon(ci, b.icon, r.position + Vector2(w0, h) * 0.5, icon_s, cols0[1], cols0[0])
		return w0
	if text_width(font, words, size) > avail:
		size = fit_size(font, words, size, avail, maxi(8, roundi(h * 0.46)))
		words = ellipsize(font, words, size, avail)
	var w := pad_l + icon_s + gap + text_width(font, words, size) + pad_r
	var rr := Rect2(r.position, Vector2(w, h))
	var cols := tone_colors(b.tone, tape_color)
	panel(ci, rr, cols[0], UiPalette.INK, maxf(1.5, h * 0.1), h * 0.28)
	if b.tone == HudModel.TONE_PENDING:
		hatch(ci, rr.grow(-maxf(1.5, h * 0.1)), Color("#ffcf87"), h * 0.42, h * 0.2)
	if cols[2].a > 0.0:
		ci.draw_rect(rr.grow(-h * 0.16), cols[2], false, maxf(1.0, h * 0.08), true)
	var ic := Vector2(rr.position.x + pad_l + icon_s * 0.5, rr.position.y + h * 0.5)
	if b.icon == HudModel.ICON_REC:
		# The REC lamp pulses (lamp_on false = the dim half of the blink).
		ci.draw_circle(ic, icon_s * 0.36, UiPalette.INK, true, -1.0, true)
		ci.draw_circle(ic, icon_s * 0.29, Color.WHITE if lamp_on else Color(1, 1, 1, 0.3), true, -1.0, true)
	else:
		HudIcons.draw_icon(ci, b.icon, ic, icon_s, cols[1], cols[0])
	text(ci, font, Vector2(ic.x + icon_s * 0.5 + gap, baseline_in(font, size, rr.position.y, h)), words, size, cols[1])
	return w


# ───────────────────────────── hatches and patterns ─────────────────────────────

## Diagonal hatch lines clipped to `r`. `dir` 1 = "/" lines, -1 = "\" lines.
static func hatch(ci: CanvasItem, r: Rect2, color: Color, spacing: float, width: float, dir: int = 1) -> void:
	if r.size.x <= 0.0 or r.size.y <= 0.0 or spacing <= 0.5:
		return
	var span := r.size.x + r.size.y
	var n := ceili(span / spacing)
	if n > 600:
		n = 600
	for k in n + 1:
		var t := k * spacing
		# Line x + dir*y = const through the rect; parametrise along x.
		var a: Vector2
		var b: Vector2
		if dir > 0:
			a = Vector2(r.position.x + t, r.position.y)
			b = Vector2(r.position.x + t - r.size.y, r.end.y)
		else:
			a = Vector2(r.position.x + t - r.size.y, r.position.y)
			b = Vector2(r.position.x + t, r.end.y)
		var seg := _clip_x(a, b, r.position.x, r.end.x)
		if seg.size() == 2:
			ci.draw_line(seg[0], seg[1], color, width, true)


static func _clip_x(a: Vector2, b: Vector2, x0: float, x1: float) -> PackedVector2Array:
	var lo := minf(a.x, b.x)
	var hi := maxf(a.x, b.x)
	if hi < x0 or lo > x1:
		return PackedVector2Array()
	var dx := b.x - a.x
	var pa := a
	var pb := b
	if absf(dx) > 1e-6:
		if pa.x < x0:
			pa = a.lerp(b, (x0 - a.x) / dx)
		elif pa.x > x1:
			pa = a.lerp(b, (x1 - a.x) / dx)
		if pb.x < x0:
			pb = a.lerp(b, (x0 - a.x) / dx)
		elif pb.x > x1:
			pb = a.lerp(b, (x1 - a.x) / dx)
	return PackedVector2Array([pa, pb])


## Colour-blind cassette pattern for tape `i` over `r` (SaveSettings.patterns): A diagonal stripes,
## B dots, C horizontal bars, D cross-hatch. Shapes, not colours, tell the cassettes apart.
static func tape_pattern(ci: CanvasItem, r: Rect2, i: int, color: Color, scale: float) -> void:
	# One pattern set everywhere (docs/ACCESSIBILITY.md H1): A stripes, B dots, C chevrons, D grid,
	# from the shared seamless tiles (data/accessibility/patterns.json via AccessKit).
	if UiArt.draw_pattern(ci, r, i, color, maxf(10.0, scale * 2.6)):
		return
	var s := maxf(4.0, scale)
	match i:
		0:
			hatch(ci, r, color, s * 0.9, s * 0.28, 1)
		1:
			var y := r.position.y + s * 0.5
			var row := 0
			while y < r.end.y:
				var x := r.position.x + s * (0.5 if row % 2 == 0 else 0.95)
				while x < r.end.x:
					ci.draw_circle(Vector2(x, y), s * 0.17, color, true, -1.0, true)
					x += s * 0.9
				y += s * 0.55
				row += 1
		2:
			var y2 := r.position.y + s * 0.35
			while y2 < r.end.y:
				ci.draw_line(Vector2(r.position.x, y2), Vector2(r.end.x, y2), color, s * 0.2, true)
				y2 += s * 0.6
		3:
			hatch(ci, r, color, s * 1.1, s * 0.16, 1)
			hatch(ci, r, color, s * 1.1, s * 0.16, -1)


## Name of the pattern for tape `i` (for legends / accessibility text).
static func pattern_name(i: int) -> String:
	if AccessKit.pattern_id(i) != "":
		return AccessKit.pattern_id(i)
	match i:
		0:
			return "stripes"
		1:
			return "dots"
		2:
			return "bars"
		3:
			return "cross-hatch"
	return ""
