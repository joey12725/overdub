class_name WidgetDraw
extends RefCounted
## Drawing helpers shared by the widgets: inked text, sticker panels, pips, cassette letter badges,
## state icons, chevrons. Kept in this directory (not borrowed from ui/hud) so the widgets never break
## when the HUD's internals change; colours and fonts come from the shared UiPalette.
##
## Every state carries an icon and a word as well as a colour, never colour alone (NEW-11).

const ICON_ALIVE: StringName = &"alive"
const ICON_GHOST: StringName = &"ghost"
const ICON_REC_GHOST: StringName = &"recGhost"
const ICON_DESYNC: StringName = &"desync"
const ICON_SPARK: StringName = &"spark"
const ICON_THREAT: StringName = &"threat"
const ICON_SHIELD: StringName = &"shield"
const ICON_BREAKABLE: StringName = &"breakable"
const ICON_CORE: StringName = &"core"
const ICON_EYE: StringName = &"eye"
const ICON_REELS: StringName = &"reels"
const ICON_SKULL: StringName = &"skull"
const ICON_CHECK: StringName = &"check"
const ICON_CROSS: StringName = &"cross"


## The fluid UI unit for widgets drawn by `ci`, from the VIEWPORT size (not the node's own rect), so
## a widget mounted in a small container is sized like the rest of the HUD.
static func unit(ci: CanvasItem) -> float:
	if ci == null or not ci.is_inside_tree():
		return 14.0
	return UiPalette.unit_for(ci.get_viewport_rect().size)


static func text(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, color: Color, outline: float = 0.0, outline_color: Color = UiPalette.INK) -> void:
	if outline > 0.0:
		ci.draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, int(outline), outline_color)
	ci.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


static func text_width(font: Font, s: String, size: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Text centred on `c` (vertical centre on the cap height).
static func text_centered(ci: CanvasItem, font: Font, c: Vector2, s: String, size: int, color: Color, outline: float = 0.0, outline_color: Color = UiPalette.INK) -> void:
	var w := text_width(font, s, size)
	var asc := font.get_ascent(size)
	var desc := font.get_descent(size)
	var base := c.y + (asc - desc) * 0.5 - size * 0.06
	text(ci, font, Vector2(c.x - w * 0.5, base), s, size, color, outline, outline_color)


## Rounded sticker panel with an ink border and a hard drop shadow.
static func panel(ci: CanvasItem, r: Rect2, bg: Color, border: Color, border_w: float, radius: float, shadow: float = 0.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(roundf(border_w)))
	sb.set_corner_radius_all(int(roundf(radius)))
	sb.anti_aliasing = true
	if shadow > 0.0:
		sb.shadow_color = UiPalette.alpha(UiPalette.INK, 0.85)
		sb.shadow_size = 0
		sb.shadow_offset = Vector2(shadow, shadow)
	ci.draw_style_box(sb, r)


## A row of `slots` pips centred on `c`, `filled` (fractional allowed) of them filled with `fill`.
## Returns the row's width.
static func pips(ci: CanvasItem, c: Vector2, slots: int, filled: float, size: float, fill: Color, empty: Color, gap: float = -1.0) -> float:
	if slots <= 0:
		return 0.0
	var g := size * 0.35 if gap < 0.0 else gap
	var w := slots * size + (slots - 1) * g
	var x := c.x - w * 0.5
	for i: int in slots:
		var r := Rect2(x + i * (size + g), c.y - size * 0.5, size, size)
		var diamond := _diamond(r)
		ci.draw_colored_polygon(diamond, UiPalette.INK)
		var inner := _diamond(r.grow(-maxf(1.0, size * 0.16)))
		ci.draw_colored_polygon(inner, empty)
		var f := clampf(filled - i, 0.0, 1.0)
		if f >= 0.999:
			ci.draw_colored_polygon(inner, fill)
		elif f > 0.0:
			# Partial pip: the left part of the diamond.
			var rr := r.grow(-maxf(1.0, size * 0.16))
			var cut := rr.position.x + rr.size.x * f
			if cut - rr.position.x < 0.5:
				continue
			var pts := PackedVector2Array()
			for p: Vector2 in inner:
				pts.append(Vector2(minf(p.x, cut), p.y))
			ci.draw_colored_polygon(pts, fill)
	return w


static func _diamond(r: Rect2) -> PackedVector2Array:
	var c := r.get_center()
	return PackedVector2Array([Vector2(c.x, r.position.y), Vector2(r.end.x, c.y), Vector2(c.x, r.end.y), Vector2(r.position.x, c.y)])


## Cassette badge: a rounded square in the tape's colour with its letter (A..D).
static func tape_badge(ci: CanvasItem, c: Vector2, size: float, tape: int, lit: bool = true) -> void:
	var col := UiPalette.tape(tape) if lit else UiPalette.tape_night(tape)
	var r := Rect2(c - Vector2(size, size) * 0.5, Vector2(size, size))
	panel(ci, r, col, UiPalette.INK, maxf(1.5, size * 0.1), size * 0.22)
	var letter := OD.tape_letter(tape) if tape >= 0 and tape < OD.TAPE_COUNT else "?"
	text_centered(ci, UiPalette.font_display(), c, letter, int(size * 0.68), UiPalette.INK if lit else UiPalette.tape(tape))


## Arrowhead chevron centred at `c` pointing along `angle`.
static func chevron(ci: CanvasItem, c: Vector2, angle: float, size: float, fill: Color, ink_w: float = 2.0) -> void:
	var d := Vector2.from_angle(angle)
	var n := Vector2(-d.y, d.x)
	var tip := c + d * size * 0.6
	var back := c - d * size * 0.4
	var pts := PackedVector2Array([tip, back + n * size * 0.55, c - d * size * 0.12, back - n * size * 0.55])
	var rim := pts.duplicate()
	rim.append(pts[0])
	ci.draw_colored_polygon(pts, fill)
	ci.draw_polyline(rim, UiPalette.INK, ink_w, true)


## Code-drawn icon `id` centred at `c`, `size` px across.
static func icon(ci: CanvasItem, id: StringName, c: Vector2, size: float, color: Color, ink: Color = UiPalette.INK) -> void:
	var s := size / 24.0
	var o := c - Vector2(12, 12) * s
	match id:
		ICON_ALIVE:
			ci.draw_colored_polygon(_heart(o, s), color)
		ICON_GHOST, ICON_REC_GHOST:
			var g := _ghost(o, s)
			if id == ICON_GHOST:
				ci.draw_colored_polygon(g, color)
				for e: Vector2 in [Vector2(9.6, 11.2), Vector2(14.4, 11.2)]:
					ci.draw_line(o + (e + Vector2(-1.2, -1.2)) * s, o + (e + Vector2(1.2, 1.2)) * s, ink, 1.7 * s)
					ci.draw_line(o + (e + Vector2(1.2, -1.2)) * s, o + (e + Vector2(-1.2, 1.2)) * s, ink, 1.7 * s)
			else:
				var rim := g.duplicate()
				rim.append(g[0])
				ci.draw_polyline(rim, color, 2.2 * s, true)
				ci.draw_circle(o + Vector2(12, 11.5) * s, 2.6 * s, color)
		ICON_DESYNC:
			ci.draw_polyline(_pts(o, s, [Vector2(3, 13), Vector2(7, 8), Vector2(10, 15), Vector2(14, 6), Vector2(17, 12), Vector2(21, 9)]), color, 2.6 * s, true)
			ci.draw_circle(o + Vector2(20, 18) * s, 2.2 * s, color)
		ICON_SPARK:
			var star := PackedVector2Array()
			for k: int in 8:
				var a := k * PI / 4.0 - PI / 2.0
				var rad := 10.0 if k % 2 == 0 else 3.6
				star.append(c + Vector2.from_angle(a) * rad * s)
			ci.draw_colored_polygon(star, color)
		ICON_THREAT:
			var tri := _pts(o, s, [Vector2(12, 2.5), Vector2(22, 20.5), Vector2(2, 20.5)])
			ci.draw_colored_polygon(tri, color)
			ci.draw_line(o + Vector2(12, 8.5) * s, o + Vector2(12, 14) * s, ink, 2.6 * s)
			ci.draw_circle(o + Vector2(12, 17.2) * s, 1.5 * s, ink)
		ICON_SHIELD:
			var sh := _pts(o, s, [Vector2(12, 2), Vector2(20.5, 5), Vector2(19.5, 13), Vector2(12, 22), Vector2(4.5, 13), Vector2(3.5, 5)])
			ci.draw_colored_polygon(sh, color)
			ci.draw_line(o + Vector2(12, 5) * s, o + Vector2(12, 18.5) * s, ink, 1.6 * s)
		ICON_BREAKABLE:
			for b: Rect2 in [Rect2(3, 4, 8, 5), Rect2(13, 4, 8, 5), Rect2(3, 11, 4, 5), Rect2(9, 11, 6, 5), Rect2(17, 11, 4, 5), Rect2(3, 18, 8, 3.5), Rect2(13, 18, 8, 3.5)]:
				ci.draw_rect(Rect2(o + b.position * s, b.size * s), color)
			ci.draw_polyline(_pts(o, s, [Vector2(11, 2), Vector2(13.5, 9), Vector2(10, 13), Vector2(13, 22)]), ink, 1.8 * s, true)
		ICON_CORE:
			ci.draw_arc(c, 9.0 * s, 0, TAU, 28, color, 2.4 * s, true)
			ci.draw_circle(c, 5.0 * s, color)
			ci.draw_circle(c, 2.0 * s, ink)
		ICON_EYE:
			var lens := PackedVector2Array()
			for k: int in 24:
				var a := TAU * k / 24.0
				lens.append(c + Vector2(cos(a) * 11.0, sin(a) * 6.5) * s)
			ci.draw_colored_polygon(lens, color)
			ci.draw_circle(c, 3.6 * s, ink)
			ci.draw_circle(c + Vector2(-1.0, -1.0) * s, 1.1 * s, color)
		ICON_REELS:
			for cx: float in [7.0, 17.0]:
				var rc := o + Vector2(cx, 12) * s
				ci.draw_arc(rc, 4.8 * s, 0, TAU, 20, color, 2.2 * s, true)
				ci.draw_circle(rc, 1.6 * s, color)
			ci.draw_line(o + Vector2(7, 16.8) * s, o + Vector2(17, 16.8) * s, color, 1.8 * s)
		ICON_SKULL:
			ci.draw_circle(o + Vector2(12, 10) * s, 8.0 * s, color)
			ci.draw_rect(Rect2(o + Vector2(7.5, 14) * s, Vector2(9, 6) * s), color)
			ci.draw_circle(o + Vector2(9, 10.5) * s, 2.2 * s, ink)
			ci.draw_circle(o + Vector2(15, 10.5) * s, 2.2 * s, ink)
			ci.draw_line(o + Vector2(12, 16) * s, o + Vector2(12, 20) * s, ink, 1.4 * s)
		ICON_CHECK:
			ci.draw_polyline(_pts(o, s, [Vector2(4, 12.5), Vector2(9.5, 18), Vector2(20, 6)]), color, 3.6 * s, true)
		ICON_CROSS:
			ci.draw_line(o + Vector2(5, 5) * s, o + Vector2(19, 19) * s, color, 3.6 * s, true)
			ci.draw_line(o + Vector2(19, 5) * s, o + Vector2(5, 19) * s, color, 3.6 * s, true)
		_:
			ci.draw_circle(c, 6.0 * s, color)


static func _pts(o: Vector2, s: float, src: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in src:
		out.append(o + p * s)
	return out


static func _heart(o: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k: int in 32:
		var t := TAU * k / 32.0
		var x := 16.0 * pow(sin(t), 3.0)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		out.append(o + Vector2(12.0 + x * 0.58, 11.5 - y * 0.58) * s)
	return out


static func _ghost(o: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k: int in 13:
		var a := PI + PI * k / 12.0
		out.append(o + (Vector2(12, 10) + Vector2(cos(a), sin(a)) * 7.5) * s)
	out.append(o + Vector2(19.5, 20.5) * s)
	out.append(o + Vector2(17, 18) * s)
	out.append(o + Vector2(14.5, 20.5) * s)
	out.append(o + Vector2(12, 18) * s)
	out.append(o + Vector2(9.5, 20.5) * s)
	out.append(o + Vector2(7, 18) * s)
	out.append(o + Vector2(4.5, 20.5) * s)
	return out


## Icon for a self state (WidgetOffscreen.STATE_*).
static func state_icon(state: StringName) -> StringName:
	match state:
		WidgetOffscreen.STATE_GHOST:
			return ICON_GHOST
		WidgetOffscreen.STATE_REC_GHOST:
			return ICON_REC_GHOST
		WidgetOffscreen.STATE_DESYNC:
			return ICON_DESYNC
	return ICON_ALIVE


## Colour for a self state's icon.
static func state_color(state: StringName) -> Color:
	match state:
		WidgetOffscreen.STATE_GHOST, WidgetOffscreen.STATE_REC_GHOST:
			return UiPalette.STATE_DEAD
		WidgetOffscreen.STATE_DESYNC:
			return UiPalette.STATE_DESYNC
	return UiPalette.STATE_GOOD


## Arc polyline from angle a0 to a1 (radians) as a thick band, filled.
static func arc_band(ci: CanvasItem, c: Vector2, r_in: float, r_out: float, a0: float, a1: float, color: Color) -> void:
	# Thinner than half a pixel at the rim: nothing to see, and the polygon would not triangulate.
	if absf(a1 - a0) * maxf(r_out, 1.0) < 0.5 or r_out - r_in < 0.01:
		return
	var n := maxi(3, ceili(absf(a1 - a0) / 0.06))
	var pts := PackedVector2Array()
	for k: int in n + 1:
		pts.append(c + Vector2.from_angle(lerpf(a0, a1, float(k) / n)) * r_out)
	for k: int in range(n, -1, -1):
		pts.append(c + Vector2.from_angle(lerpf(a0, a1, float(k) / n)) * r_in)
	ci.draw_colored_polygon(pts, color)
