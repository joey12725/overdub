class_name WidgetOffscreen
extends RefCounted
## Pure maths for edge-of-screen indicators (chapter 16: "supplements off-screen activity with an
## interface indicator"; OPEN-20). No nodes: callers project world points to screen first.
##
## The safe rect is the part of the screen indicators may use (the viewport minus the HUD dock at
## the bottom and the boss bar at the top), shrunk by a margin so chevrons never touch the edge.
## A point outside it is pinned to where the ray from the rect's centre toward the point crosses the
## rect's border. Pinned points are ordered by their position along the perimeter (clockwise from the
## top-left corner) and neighbours closer than `cluster_px` along the perimeter merge into one
## cluster, so four selves bunched in the next room read as one stack rather than four overlapping
## chevrons. The perimeter is a loop, so clusters may wrap round a corner and round the start.

const KIND_SELF: StringName = &"self"
const KIND_SPARK: StringName = &"spark"
const KIND_THREAT: StringName = &"threat"

const STATE_ALIVE: StringName = &"alive"
const STATE_GHOST: StringName = &"ghost"
const STATE_REC_GHOST: StringName = &"recGhost"
const STATE_DESYNC: StringName = &"desync"

const EDGE_TOP := 0
const EDGE_RIGHT := 1
const EDGE_BOTTOM := 2
const EDGE_LEFT := 3


## One thing that may need an indicator.
class Item:
	extends RefCounted
	## KIND_*.
	var kind: StringName = &"self"
	## Cassette 0..3 (selves and sparks); -1 for enemies.
	var tape: int = -1
	## STATE_* for selves; "" otherwise.
	var state: StringName = &""
	## Enemy id for threats.
	var id: String = ""
	## Projected screen position (may be far outside the viewport).
	var screen: Vector2 = Vector2.ZERO
	## The point is behind the camera (perspective cameras only): the projection is mirrored.
	var behind: bool = false
	## 0..1 pulse (the self just acted / the threat is about to land).
	var pulse: float = 0.0

	static func make(p_kind: StringName, p_tape: int, p_state: StringName, p_screen: Vector2) -> Item:
		var it := Item.new()
		it.kind = p_kind
		it.tape = p_tape
		it.state = p_state
		it.screen = p_screen
		return it


## One indicator on the edge: one or more items.
class Cluster:
	extends RefCounted
	var items: Array[Item] = []
	## Where the chevron sits (on the safe rect's border).
	var pos: Vector2 = Vector2.ZERO
	## Direction it points, radians (screen space, 0 = right, +y down).
	var angle: float = 0.0
	## EDGE_* of `pos`.
	var edge: int = 0
	## Perimeter coordinate of `pos`, px clockwise from the top-left corner.
	var t: float = 0.0


## Is `p` inside `rect` (borders included)?
static func is_inside(p: Vector2, rect: Rect2) -> bool:
	return p.x >= rect.position.x and p.x <= rect.end.x and p.y >= rect.position.y and p.y <= rect.end.y


## The safe rect: `viewport` minus `top`/`bottom` insets, shrunk by `margin` on every side.
static func safe_rect(viewport: Rect2, top: float, bottom: float, margin: float) -> Rect2:
	var r := Rect2(viewport.position.x + margin, viewport.position.y + top + margin, viewport.size.x - 2.0 * margin, viewport.size.y - top - bottom - 2.0 * margin)
	r.size.x = maxf(r.size.x, 2.0)
	r.size.y = maxf(r.size.y, 2.0)
	return r


## The screen point to use for an item: mirrored through the centre when behind the camera.
static func effective_point(it: Item, rect: Rect2) -> Vector2:
	if not it.behind:
		return it.screen
	var c := rect.get_center()
	var d := c - it.screen
	if d.length_squared() < 1e-6:
		d = Vector2(0, 1)
	# Push it well outside so it pins to the edge.
	return c + d.normalized() * (rect.size.length() + d.length())


## Where the ray from the rect's centre toward `p` leaves the rect. `p` inside -> `p` itself.
static func edge_point(p: Vector2, rect: Rect2) -> Vector2:
	if is_inside(p, rect):
		return p
	var c := rect.get_center()
	var d := p - c
	var hx := rect.size.x * 0.5
	var hy := rect.size.y * 0.5
	var sx := INF if absf(d.x) < 1e-9 else hx / absf(d.x)
	var sy := INF if absf(d.y) < 1e-9 else hy / absf(d.y)
	var s := minf(sx, sy)
	var q := c + d * s
	return Vector2(clampf(q.x, rect.position.x, rect.end.x), clampf(q.y, rect.position.y, rect.end.y))


## Which edge a border point lies on (corners resolve to top/bottom first).
static func edge_of(p: Vector2, rect: Rect2) -> int:
	var dt := absf(p.y - rect.position.y)
	var db := absf(p.y - rect.end.y)
	var dl := absf(p.x - rect.position.x)
	var dr := absf(p.x - rect.end.x)
	var m := minf(minf(dt, db), minf(dl, dr))
	if m == dt:
		return EDGE_TOP
	if m == db:
		return EDGE_BOTTOM
	if m == dr:
		return EDGE_RIGHT
	return EDGE_LEFT


## Perimeter length.
static func perimeter(rect: Rect2) -> float:
	return 2.0 * (rect.size.x + rect.size.y)


## Perimeter coordinate of a border point, clockwise from the top-left corner.
static func perimeter_t(p: Vector2, rect: Rect2) -> float:
	var w := rect.size.x
	var h := rect.size.y
	match edge_of(p, rect):
		EDGE_TOP:
			return clampf(p.x - rect.position.x, 0.0, w)
		EDGE_RIGHT:
			return w + clampf(p.y - rect.position.y, 0.0, h)
		EDGE_BOTTOM:
			return w + h + clampf(rect.end.x - p.x, 0.0, w)
	return 2.0 * w + h + clampf(rect.end.y - p.y, 0.0, h)


## Border point at perimeter coordinate `t` (wraps).
static func point_at(t: float, rect: Rect2) -> Vector2:
	var w := rect.size.x
	var h := rect.size.y
	var per := perimeter(rect)
	var u := fposmod(t, per)
	if u <= w:
		return Vector2(rect.position.x + u, rect.position.y)
	u -= w
	if u <= h:
		return Vector2(rect.end.x, rect.position.y + u)
	u -= h
	if u <= w:
		return Vector2(rect.end.x - u, rect.end.y)
	u -= w
	return Vector2(rect.position.x, rect.end.y - u)


## Pin every off-screen item to the border and cluster neighbours. On-screen items are dropped.
## Deterministic: ties keep input order.
static func layout(items: Array[Item], rect: Rect2, cluster_px: float) -> Array[Cluster]:
	var pinned: Array = [] # [t, Item, effective point]
	for it: Item in items:
		var p := effective_point(it, rect)
		if is_inside(p, rect):
			continue
		var e := edge_point(p, rect)
		pinned.append([perimeter_t(e, rect), it, p])
	var out: Array[Cluster] = []
	if pinned.is_empty():
		return out
	# Stable sort by t (insertion index breaks ties).
	for i: int in pinned.size():
		pinned[i].append(i)
	pinned.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[3] < b[3]))
	var per := perimeter(rect)
	# Start the sweep after the widest gap so a cluster never straddles the sweep's seam.
	var start := 0
	var widest := -1.0
	for i: int in pinned.size():
		var nxt: float = pinned[(i + 1) % pinned.size()][0]
		var gap: float = fposmod(nxt - float(pinned[i][0]), per)
		if pinned.size() == 1:
			gap = per
		if gap > widest:
			widest = gap
			start = (i + 1) % pinned.size()
	var groups: Array = []
	var cur: Array = []
	var prev_t := 0.0
	for k: int in pinned.size():
		var row: Array = pinned[(start + k) % pinned.size()]
		var t: float = row[0]
		# Unwrap so t increases monotonically through the sweep.
		if k > 0:
			while t < prev_t:
				t += per
		if k > 0 and t - prev_t > cluster_px:
			groups.append(cur)
			cur = []
		cur.append([t, row[1], row[2]])
		prev_t = t
	groups.append(cur)
	var c0 := rect.get_center()
	for g: Array in groups:
		var cl := Cluster.new()
		var sum_t := 0.0
		var sum_p := Vector2.ZERO
		for row: Array in g:
			sum_t += float(row[0])
			sum_p += (row[2] as Vector2) - c0
			cl.items.append(row[1])
		cl.t = fposmod(sum_t / g.size(), per)
		cl.pos = point_at(cl.t, rect)
		cl.edge = edge_of(cl.pos, rect)
		var d := sum_p if sum_p.length_squared() > 1e-6 else (cl.pos - c0)
		cl.angle = atan2(d.y, d.x)
		out.append(cl)
	out.sort_custom(func(a: Cluster, b: Cluster) -> bool: return a.t < b.t)
	return out


## Self state for an indicator from a snapshot.
static func self_state(a: ActorSnap) -> StringName:
	if a.life == OD.LifeState.GHOST:
		return STATE_GHOST
	if a.life == OD.LifeState.REC_GHOST:
		return STATE_REC_GHOST
	if not a.synced:
		return STATE_DESYNC
	return STATE_ALIVE
