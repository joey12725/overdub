class_name CoachLayout
extends RefCounted
## Places a callout bubble next to an anchor rect. Node-free.
##
## place() tries the preferred side, then above / below / right / left, and takes the first position
## that stays on screen and overlaps none of the `avoid` rects (the beat ruler, the count-in...); if
## none fits it takes the candidate with the least overlap, clamped to the screen. The pointer tip
## sits on the anchor edge facing the bubble. Without an anchor the bubble goes top-centre.

class Placement:
	extends RefCounted
	var rect: Rect2 = Rect2()
	## "above" | "below" | "left" | "right" | "none" (no anchor: no pointer).
	var side: String = "none"
	## Where the pointer touches the anchor, and where it leaves the bubble.
	var tip: Vector2 = Vector2.ZERO
	var base: Vector2 = Vector2.ZERO


const ORDER: Array[String] = ["above", "below", "right", "left"]


static func place(anchor: Rect2, has_anchor: bool, bubble: Vector2, screen: Rect2, avoid: Array[Rect2], prefer: String = "auto", gap: float = 14.0, margin: float = 12.0) -> Placement:
	var p := Placement.new()
	var safe := screen.grow(-margin)
	if not has_anchor:
		p.rect = Rect2(Vector2(safe.get_center().x - bubble.x * 0.5, safe.position.y + safe.size.y * 0.12), bubble)
		p.rect = _clamp(p.rect, safe)
		p.side = "none"
		return p
	var order: Array[String] = []
	if ORDER.has(prefer):
		order.append(prefer)
	for s: String in ORDER:
		if not order.has(s):
			order.append(s)
	var best_r := Rect2()
	var best_side := ""
	var best_cost := INF
	for s: String in order:
		var r := _nudge(_candidate(anchor, bubble, s, gap), s, avoid, gap * 0.5)
		# Clamped onto the screen; a clamp that slides the bubble over its own anchor costs double.
		r = _clamp(r, safe)
		var cost := _overlap(r, avoid) + _overlap_one(r, anchor) * 2.0
		if cost <= 0.0:
			best_r = r
			best_side = s
			best_cost = 0.0
			break
		if cost < best_cost:
			best_cost = cost
			best_r = r
			best_side = s
	p.rect = best_r
	p.side = best_side
	_pointer(p, anchor)
	return p


static func _candidate(a: Rect2, b: Vector2, side: String, gap: float) -> Rect2:
	var c := a.get_center()
	match side:
		"above":
			return Rect2(Vector2(c.x - b.x * 0.5, a.position.y - gap - b.y), b)
		"below":
			return Rect2(Vector2(c.x - b.x * 0.5, a.end.y + gap), b)
		"right":
			return Rect2(Vector2(a.end.x + gap, c.y - b.y * 0.5), b)
	return Rect2(Vector2(a.position.x - gap - b.x, c.y - b.y * 0.5), b)


## Slide a candidate further out along its side until it clears every avoid rect it overlaps (the
## anchor may sit inside an avoided band, e.g. a lane of the ruler).
static func _nudge(r: Rect2, side: String, avoid: Array[Rect2], pad: float) -> Rect2:
	for _pass in 3:
		var moved := false
		for o: Rect2 in avoid:
			if not r.intersects(o):
				continue
			match side:
				"above":
					r.position.y = o.position.y - pad - r.size.y
				"below":
					r.position.y = o.end.y + pad
				"right":
					r.position.x = o.end.x + pad
				_:
					r.position.x = o.position.x - pad - r.size.x
			moved = true
		if not moved:
			break
	return r


static func _clamp(r: Rect2, safe: Rect2) -> Rect2:
	var pos := r.position
	pos.x = clampf(pos.x, safe.position.x, maxf(safe.position.x, safe.end.x - r.size.x))
	pos.y = clampf(pos.y, safe.position.y, maxf(safe.position.y, safe.end.y - r.size.y))
	return Rect2(pos, r.size)


static func _overlap_one(r: Rect2, o: Rect2) -> float:
	var i := r.intersection(o)
	return i.get_area() if i.has_area() else 0.0


static func _overlap(r: Rect2, avoid: Array[Rect2]) -> float:
	var t := 0.0
	for o: Rect2 in avoid:
		t += _overlap_one(r, o)
	return t


static func _pointer(p: Placement, a: Rect2) -> void:
	var r := p.rect
	match p.side:
		"above":
			var x := clampf(a.get_center().x, r.position.x + 18.0, r.end.x - 18.0)
			p.base = Vector2(x, r.end.y)
			p.tip = Vector2(clampf(a.get_center().x, a.position.x, a.end.x), a.position.y)
		"below":
			var x := clampf(a.get_center().x, r.position.x + 18.0, r.end.x - 18.0)
			p.base = Vector2(x, r.position.y)
			p.tip = Vector2(clampf(a.get_center().x, a.position.x, a.end.x), a.end.y)
		"right":
			var y := clampf(a.get_center().y, r.position.y + 14.0, r.end.y - 14.0)
			p.base = Vector2(r.position.x, y)
			p.tip = Vector2(a.end.x, clampf(a.get_center().y, a.position.y, a.end.y))
		"left":
			var y := clampf(a.get_center().y, r.position.y + 14.0, r.end.y - 14.0)
			p.base = Vector2(r.end.x, y)
			p.tip = Vector2(a.position.x, clampf(a.get_center().y, a.position.y, a.end.y))
