class_name HudIcons
extends RefCounted
## Code-drawn icons for the HUD (port of prototype ui/hud/icons.ts and the ruler's lane glyphs).
## Every state the HUD shows carries an icon as well as a word and a colour, so no state is ever
## conveyed by colour alone (NEW-11). Drawn chunky so they survive small sizes and read as inked
## stickers. Icons are authored on a 24x24 grid like the prototype's SVGs.


## Use the generated glyph art for the states that have one (see draw_icon).
static var use_art: bool = true
## HudModel.ICON_* -> assets/ui/icons/tape/<name>.png
const ART_GLYPHS: Dictionary = {
	&"lock": "locked", &"rec": "rec", &"alive": "alive", &"ghost": "dead", &"death": "dead",
	&"desync": "desync", &"resync": "resync", &"stop": "stop", &"repeat": "repeat", &"reverse": "reverse",
}


## Draw icon `id` (HudModel.ICON_*) centred at `c`, `size` px across, in `color`. `ink` is the
## colour of details cut into filled shapes (ghost eyes).
static func draw_icon(ci: CanvasItem, id: StringName, c: Vector2, size: float, color: Color, ink: Color = UiPalette.INK) -> void:
	# The generated tape-state glyphs (assets/ui/icons/tape: white shape, ink outline) where one
	# exists for this state, tinted like the drawn icon; drawn shapes otherwise.
	if use_art and ART_GLYPHS.has(id):
		var name: String = ART_GLYPHS[id]
		var tint := Color.WHITE if name == "rec" else color
		if UiArt.draw_centered(ci, UiArt.tape_icon(name, size * 1.15), c, size * 1.15, tint):
			return
	var s := size / 24.0
	var o := c - Vector2(12, 12) * s
	match id:
		HudModel.ICON_LOCK:
			_rect(ci, o, s, Rect2(5, 10.5, 14, 10), color)
			ci.draw_arc(o + Vector2(12, 8) * s, 4.0 * s, PI, TAU, 14, color, 2.6 * s, true)
			_line(ci, o, s, Vector2(8, 8), Vector2(8, 10.8), color, 2.6)
			_line(ci, o, s, Vector2(16, 8), Vector2(16, 10.8), color, 2.6)
			ci.draw_circle(o + Vector2(12, 15) * s, 1.5 * s, ink, true, -1.0, true)
		HudModel.ICON_REC:
			ci.draw_circle(c, 7.0 * s, color, true, -1.0, true)
		HudModel.ICON_ARM:
			ci.draw_arc(c, 7.5 * s, 0, TAU, 28, color, 2.6 * s, true)
			ci.draw_circle(c, 3.0 * s, color, true, -1.0, true)
		HudModel.ICON_EMPTY:
			var r := Rect2(o + Vector2(4, 7) * s, Vector2(16, 10) * s)
			_dashed_rect(ci, r, color, 2.4 * s, 3.0 * s)
		HudModel.ICON_NONE:
			ci.draw_arc(c, 8.0 * s, 0, TAU, 28, color, 2.4 * s, true)
			_line(ci, o, s, Vector2(6.5, 17.5), Vector2(17.5, 6.5), color, 2.4)
		HudModel.ICON_TAKE:
			var pts := _pts(o, s, [Vector2(5, 4), Vector2(19, 4), Vector2(19, 20), Vector2(12, 16), Vector2(5, 20), Vector2(5, 4)])
			ci.draw_polyline(pts, color, 2.4 * s, true)
			_line(ci, o, s, Vector2(12, 8), Vector2(12, 12), color, 2.6)
			ci.draw_circle(o + Vector2(12, 14.3) * s, 1.3 * s, color, true, -1.0, true)
		HudModel.ICON_ALIVE:
			fill_poly(ci, _heart(o, s), color)
		HudModel.ICON_GHOST:
			fill_poly(ci, _ghost(o, s), color)
			for e: Vector2 in [Vector2(9.6, 11.2), Vector2(14.4, 11.2)]:
				_line(ci, o, s, e + Vector2(-1, -1), e + Vector2(1, 1), ink, 1.6)
				_line(ci, o, s, e + Vector2(1, -1), e + Vector2(-1, 1), ink, 1.6)
		HudModel.ICON_REC_GHOST:
			var g := _ghost(o, s)
			g.append(g[0])
			ci.draw_polyline(g, color, 2.2 * s, true)
			ci.draw_circle(o + Vector2(12, 11.5) * s, 2.6 * s, color, true, -1.0, true)
		HudModel.ICON_DESYNC:
			ci.draw_polyline(_pts(o, s, [Vector2(3, 13), Vector2(7, 8), Vector2(10, 15), Vector2(14, 6), Vector2(17, 12), Vector2(21, 9)]), color, 2.4 * s, true)
			ci.draw_circle(o + Vector2(20, 18) * s, 2.0 * s, color, true, -1.0, true)
		HudModel.ICON_RESYNC:
			ci.draw_arc(c, 8.0 * s, 0, TAU, 28, color, 2.4 * s, true)
			ci.draw_polyline(_pts(o, s, [Vector2(8, 12.3), Vector2(10.7, 15), Vector2(16.2, 9.4)]), color, 2.6 * s, true)
		HudModel.ICON_STOP:
			_rect(ci, o, s, Rect2(6, 6, 12, 12), color)
		HudModel.ICON_REPEAT:
			ci.draw_polyline(_pts(o, s, [Vector2(5, 11), Vector2(5, 9.5), Vector2(6, 7), Vector2(8.5, 6), Vector2(18, 6)]), color, 2.4 * s, true)
			ci.draw_polyline(_pts(o, s, [Vector2(15, 3), Vector2(18, 6), Vector2(15, 9)]), color, 2.4 * s, true)
			ci.draw_polyline(_pts(o, s, [Vector2(19, 13), Vector2(19, 14.5), Vector2(18, 17), Vector2(15.5, 18), Vector2(6, 18)]), color, 2.4 * s, true)
			ci.draw_polyline(_pts(o, s, [Vector2(9, 21), Vector2(6, 18), Vector2(9, 15)]), color, 2.4 * s, true)
		HudModel.ICON_REVERSE:
			_line(ci, o, s, Vector2(4, 8), Vector2(18, 8), color, 2.4)
			ci.draw_polyline(_pts(o, s, [Vector2(15, 4.5), Vector2(18.5, 8), Vector2(15, 11.5)]), color, 2.4 * s, true)
			_line(ci, o, s, Vector2(20, 16), Vector2(6, 16), color, 2.4)
			ci.draw_polyline(_pts(o, s, [Vector2(9, 19.5), Vector2(5.5, 16), Vector2(9, 12.5)]), color, 2.4 * s, true)
		HudModel.ICON_PLAY:
			fill_poly(ci, _pts(o, s, [Vector2(7, 5), Vector2(19, 12), Vector2(7, 19)]), color)
		HudModel.ICON_REWIND:
			fill_poly(ci, _pts(o, s, [Vector2(17, 5), Vector2(5, 12), Vector2(17, 19)]), color)
		HudModel.ICON_HOLD:
			_rect(ci, o, s, Rect2(6, 5, 4, 14), color)
			_rect(ci, o, s, Rect2(14, 5, 4, 14), color)
		HudModel.ICON_CUE:
			_line(ci, o, s, Vector2(6, 5), Vector2(6, 19), color, 2.6)
			var t := _pts(o, s, [Vector2(9, 6), Vector2(19, 12), Vector2(9, 18), Vector2(9, 6)])
			ci.draw_polyline(t, color, 2.2 * s, true)
		HudModel.ICON_DEATH:
			_line(ci, o, s, Vector2(6, 6), Vector2(18, 18), color, 3.2)
			_line(ci, o, s, Vector2(18, 6), Vector2(6, 18), color, 3.2)
		HudModel.ICON_SURVIVOR:
			ci.draw_circle(o + Vector2(12, 8) * s, 3.6 * s, color, true, -1.0, true)
			var body := PackedVector2Array()
			for k in 17:
				var a := PI + PI * k / 16.0
				body.append(o + (Vector2(12, 20) + Vector2(cos(a), sin(a)) * 7.0) * s)
			fill_poly(ci, body, color)
		HudModel.ICON_WORLD:
			ci.draw_arc(c, 8.0 * s, 0, TAU, 28, color, 2.2 * s, true)
			_line(ci, o, s, Vector2(4, 12), Vector2(20, 12), color, 1.8)
			var e := PackedVector2Array()
			for k in 25:
				var a := TAU * k / 24.0
				e.append(c + Vector2(cos(a) * 3.6, sin(a) * 8.0) * s)
			ci.draw_polyline(e, color, 1.8 * s, true)
		_:
			ci.draw_circle(c, 4.0 * s, color, true, -1.0, true)


## Lane glyph for an action kind (ActionKind.*): distinct silhouettes so kinds read without colour.
static func draw_glyph(ci: CanvasItem, kind: StringName, x: float, cy: float, size: float, color: Color) -> void:
	var s := size / 2.0
	match kind:
		ActionKind.LIGHT:
			ci.draw_line(Vector2(x - s * 0.45, cy + s), Vector2(x + s * 0.45, cy - s), color, maxf(1.4, s * 0.42), true)
		ActionKind.HEAVY:
			fill_poly(ci, PackedVector2Array([Vector2(x, cy - s * 1.15), Vector2(x + s * 0.85, cy), Vector2(x, cy + s * 1.15), Vector2(x - s * 0.85, cy)]), color)
		ActionKind.DODGE:
			var w := maxf(1.2, s * 0.32)
			ci.draw_polyline(PackedVector2Array([Vector2(x - s * 0.9, cy - s * 0.7), Vector2(x - s * 0.2, cy), Vector2(x - s * 0.9, cy + s * 0.7)]), color, w, true)
			ci.draw_polyline(PackedVector2Array([Vector2(x + s * 0.1, cy - s * 0.7), Vector2(x + s * 0.8, cy), Vector2(x + s * 0.1, cy + s * 0.7)]), color, w, true)
		ActionKind.RANGED:
			fill_poly(ci, PackedVector2Array([
				Vector2(x - s, cy - s * 0.35), Vector2(x, cy - s * 0.35), Vector2(x, cy - s * 0.9), Vector2(x + s, cy),
				Vector2(x, cy + s * 0.9), Vector2(x, cy + s * 0.35), Vector2(x - s, cy + s * 0.35)]), color)
		ActionKind.INTERACT:
			ci.draw_rect(Rect2(x - s * 0.7, cy - s * 0.7, s * 1.4, s * 1.4), color, false, maxf(1.2, s * 0.34), true)
		ActionKind.ABILITY:
			var pts := PackedVector2Array()
			for k in 8:
				var r := s * 1.05 if k % 2 == 0 else s * 0.32
				var a := k * PI / 4.0 - PI / 2.0
				pts.append(Vector2(x + cos(a) * r, cy + sin(a) * r))
			fill_poly(ci, pts, color)
		_:
			ci.draw_circle(Vector2(x, cy), s * 0.5, color, true, -1.0, true)


## State-mark glyph (StateMarkKind.*): death cross, desync zigzag, resync ring. Inked outline first.
static func draw_state_glyph(ci: CanvasItem, kind: StringName, x: float, cy: float, size: float) -> void:
	var s := size / 2.0
	var ink := UiPalette.INK
	if kind == StateMarkKind.DEATH:
		for pass_i in 2:
			var w := maxf(3.0, s * 0.62) if pass_i == 0 else maxf(1.6, s * 0.3)
			var col := ink if pass_i == 0 else UiPalette.PAPER
			ci.draw_line(Vector2(x - s * 0.7, cy - s * 0.7), Vector2(x + s * 0.7, cy + s * 0.7), col, w, true)
			ci.draw_line(Vector2(x + s * 0.7, cy - s * 0.7), Vector2(x - s * 0.7, cy + s * 0.7), col, w, true)
	elif kind == StateMarkKind.DESYNC:
		var pts := PackedVector2Array([Vector2(x - s * 0.8, cy + s * 0.2), Vector2(x - s * 0.35, cy - s * 0.6),
			Vector2(x + s * 0.05, cy + s * 0.6), Vector2(x + s * 0.45, cy - s * 0.6), Vector2(x + s * 0.8, cy)])
		ci.draw_polyline(pts, ink, maxf(3.0, s * 0.52), true)
		ci.draw_polyline(pts, UiPalette.STATE_DESYNC, maxf(1.5, s * 0.25), true)
	else:
		ci.draw_arc(Vector2(x, cy), s * 0.65, 0, TAU, 20, ink, maxf(3.0, s * 0.5), true)
		ci.draw_arc(Vector2(x, cy), s * 0.65, 0, TAU, 20, UiPalette.STATE_GOOD, maxf(1.5, s * 0.24), true)


## Filled polygon with an antialiased rim (Godot does not antialias polygon fills).
static func fill_poly(ci: CanvasItem, pts: PackedVector2Array, color: Color) -> void:
	if pts.size() < 3:
		return
	ci.draw_colored_polygon(pts, color)
	var rim := pts.duplicate()
	rim.append(pts[0])
	ci.draw_polyline(rim, color, 1.0, true)


static func _pts(o: Vector2, s: float, src: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in src:
		out.append(o + p * s)
	return out


static func _line(ci: CanvasItem, o: Vector2, s: float, a: Vector2, b: Vector2, color: Color, w: float) -> void:
	ci.draw_line(o + a * s, o + b * s, color, w * s, true)


static func _rect(ci: CanvasItem, o: Vector2, s: float, r: Rect2, color: Color) -> void:
	ci.draw_rect(Rect2(o + r.position * s, r.size * s), color, true)


static func _dashed_rect(ci: CanvasItem, r: Rect2, color: Color, w: float, dash: float) -> void:
	var a := r.position
	var b := Vector2(r.end.x, r.position.y)
	var c := r.end
	var d := Vector2(r.position.x, r.end.y)
	ci.draw_dashed_line(a, b, color, w, dash, true, true)
	ci.draw_dashed_line(b, c, color, w, dash, true, true)
	ci.draw_dashed_line(c, d, color, w, dash, true, true)
	ci.draw_dashed_line(d, a, color, w, dash, true, true)


static func _heart(o: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in 32:
		var t := TAU * k / 32.0
		var x := 16.0 * pow(sin(t), 3)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		out.append(o + (Vector2(12, 12.6) + Vector2(x, -y) * 0.48) * s)
	return out


static func _ghost(o: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in 13:
		var a := PI + PI * k / 12.0
		out.append(o + (Vector2(12, 11) + Vector2(cos(a), sin(a)) * 7.0) * s)
	for p: Vector2 in [Vector2(19, 20), Vector2(16.6, 18), Vector2(14.3, 20), Vector2(12, 18), Vector2(9.7, 20), Vector2(7.4, 18), Vector2(5, 20)]:
		out.append(o + p * s)
	return out
