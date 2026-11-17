class_name MenuVector
extends RefCounted
## Tiny SVG-path subset for the menu artwork (prototype ui/menus/art.ts kept its art as SVG markup;
## here the same path data is flattened to polylines and drawn on a CanvasItem). Supports
## M/m L/l H/h V/v C/c Q/q Z/z. Parsed paths are cached. Never instantiated.


class Sub:
	extends RefCounted
	var points: PackedVector2Array = PackedVector2Array()
	var closed: bool = false


const CURVE_STEPS := 12

static var _cache: Dictionary[String, Array] = {}


static func parse(d: String) -> Array:
	if _cache.has(d):
		return _cache[d]
	var subs: Array = []
	var tokens := _tokenize(d)
	var i := 0
	var cmd := ""
	var pos := Vector2.ZERO
	var start := Vector2.ZERO
	var cur: Sub = null
	while i < tokens.size():
		var t: String = tokens[i]
		if t.length() == 1 and "MmLlHhVvCcQqZz".contains(t):
			cmd = t
			i += 1
			if cmd == "Z" or cmd == "z":
				if cur != null:
					cur.closed = true
				pos = start
				cur = null
			continue
		var rel := cmd == cmd.to_lower()
		match cmd.to_upper():
			"M":
				var p := _pt(tokens, i)
				i += 2
				pos = pos + p if rel else p
				start = pos
				cur = Sub.new()
				cur.points.append(pos)
				subs.append(cur)
				# Subsequent pairs after a moveto are implicit linetos.
				cmd = "l" if rel else "L"
			"L":
				var p := _pt(tokens, i)
				i += 2
				pos = pos + p if rel else p
				cur = _ensure(cur, subs, pos)
				cur.points.append(pos)
			"H":
				var x := float(tokens[i])
				i += 1
				pos = Vector2(pos.x + x if rel else x, pos.y)
				cur = _ensure(cur, subs, pos)
				cur.points.append(pos)
			"V":
				var y := float(tokens[i])
				i += 1
				pos = Vector2(pos.x, pos.y + y if rel else y)
				cur = _ensure(cur, subs, pos)
				cur.points.append(pos)
			"C":
				var c1 := _pt(tokens, i)
				var c2 := _pt(tokens, i + 2)
				var e := _pt(tokens, i + 4)
				i += 6
				if rel:
					c1 += pos
					c2 += pos
					e += pos
				cur = _ensure(cur, subs, pos)
				for s in range(1, CURVE_STEPS + 1):
					cur.points.append(pos.bezier_interpolate(c1, c2, e, float(s) / CURVE_STEPS))
				pos = e
			"Q":
				var q := _pt(tokens, i)
				var e2 := _pt(tokens, i + 2)
				i += 4
				if rel:
					q += pos
					e2 += pos
				cur = _ensure(cur, subs, pos)
				for s in range(1, CURVE_STEPS + 1):
					var tt := float(s) / CURVE_STEPS
					cur.points.append(pos.lerp(q, tt).lerp(q.lerp(e2, tt), tt))
				pos = e2
			_:
				# Unsupported command or stray number: skip it.
				i += 1
	_cache[d] = subs
	return subs


static func _ensure(cur: Sub, subs: Array, pos: Vector2) -> Sub:
	if cur != null:
		return cur
	var s := Sub.new()
	s.points.append(pos)
	subs.append(s)
	return s


static func _pt(tokens: PackedStringArray, i: int) -> Vector2:
	if i + 1 >= tokens.size():
		return Vector2.ZERO
	return Vector2(float(tokens[i]), float(tokens[i + 1]))


static func _tokenize(d: String) -> PackedStringArray:
	var out := PackedStringArray()
	var num := ""
	for ch in d:
		if "MmLlHhVvCcQqZz".contains(ch):
			if not num.is_empty():
				out.append(num)
				num = ""
			out.append(ch)
		elif ch == "-":
			if not num.is_empty() and not num.ends_with("e"):
				out.append(num)
				num = ""
			num += ch
		elif ch == "." and num.contains("."):
			out.append(num)
			num = "."
		elif "0123456789.e".contains(ch):
			num += ch
		else:
			if not num.is_empty():
				out.append(num)
				num = ""
	if not num.is_empty():
		out.append(num)
	return out


## Fill every closed-able subpath of `d`. Polygons that cannot be triangulated are outlined instead
## so a bad path never raises an engine error.
static func fill(ci: CanvasItem, d: String, col: Color) -> void:
	for s: Sub in parse(d):
		if s.points.size() < 3:
			continue
		var pts := s.points
		if pts[0].is_equal_approx(pts[pts.size() - 1]):
			pts = pts.slice(0, pts.size() - 1)
		if Geometry2D.triangulate_polygon(pts).is_empty():
			ci.draw_polyline(pts, col, 1.5, true)
		else:
			ci.draw_colored_polygon(pts, col)


static func stroke(ci: CanvasItem, d: String, col: Color, width: float, round_caps: bool = false) -> void:
	for s: Sub in parse(d):
		var pts := s.points
		if pts.size() < 2:
			continue
		if s.closed:
			pts = pts.duplicate()
			pts.append(pts[0])
		ci.draw_polyline(pts, col, width, true)
		if round_caps and not s.closed:
			ci.draw_circle(pts[0], width * 0.5, col)
			ci.draw_circle(pts[pts.size() - 1], width * 0.5, col)


## Fill then outline.
static func shape(ci: CanvasItem, d: String, fill_col: Color, stroke_col: Color = Color.TRANSPARENT, width: float = 0.0) -> void:
	fill(ci, d, fill_col)
	if width > 0.0 and stroke_col.a > 0.0:
		stroke(ci, d, stroke_col, width)


## Polygon for a rounded rectangle (for clipping and filled shapes).
static func rounded_rect(r: Rect2, radius: float, steps: int = 6) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var rad := minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var corners := [
		[r.position + Vector2(r.size.x - rad, rad), -PI / 2],
		[r.position + Vector2(r.size.x - rad, r.size.y - rad), 0.0],
		[r.position + Vector2(rad, r.size.y - rad), PI / 2],
		[r.position + Vector2(rad, rad), PI],
	]
	for c: Array in corners:
		var centre: Vector2 = c[0]
		var a0: float = c[1]
		for s in steps + 1:
			var a := a0 + (PI / 2) * float(s) / steps
			pts.append(centre + Vector2(cos(a), sin(a)) * rad)
	return pts


## Rect rotated about its own pivot (SVG transform="rotate(deg cx cy)").
static func rotated_rect(r: Rect2, deg: float, pivot: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var t := Transform2D(deg_to_rad(deg), Vector2.ZERO)
	for i in pts.size():
		pts[i] = pivot + t.basis_xform(pts[i] - pivot)
	return pts


static func ellipse(centre: Vector2, rx: float, ry: float, steps: int = 32) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for s in steps:
		var a := TAU * float(s) / steps
		pts.append(centre + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## Draw `poly` filled with `col`, clipped to `clip` (both convex or simple polygons).
static func fill_clipped(ci: CanvasItem, poly: PackedVector2Array, clip: PackedVector2Array, col: Color) -> void:
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(poly, clip):
		if piece.size() >= 3 and not Geometry2D.triangulate_polygon(piece).is_empty():
			ci.draw_colored_polygon(piece, col)


## A dashed circle outline.
static func dashed_circle(ci: CanvasItem, centre: Vector2, r: float, col: Color, width: float, dash: float, gap: float, phase: float = 0.0) -> void:
	var circ := TAU * r
	var n := maxi(1, int(circ / (dash + gap)))
	var step := TAU / n
	var dash_a := step * dash / (dash + gap)
	for i in n:
		var a := phase + i * step
		ci.draw_arc(centre, r, a, a + dash_a, 6, col, width, true)
