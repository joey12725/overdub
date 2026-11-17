class_name Pathfinder
extends RefCounted
## Path-finding over walkable tiles: drives the recovery spark (DESYNC-02..04) and enemy navigation.
## Port of prototype/src/core/path.ts.
##
## A* on the 8-connected tile graph without corner cutting (a diagonal step needs both orthogonal
## neighbours walkable), honouring the grid's dynamic overlay so closed doors block and reopened ones
## are used on the next plan. Costs 1 / √2 with the octile heuristic (admissible and consistent, so
## results are optimal). Ties are broken by (f, h, tile index) so the chosen path never depends on
## heap internals.
##
## Buffers are allocated once per Pathfinder and reused; visited state is reset by bumping a
## generation stamp, so a plan allocates only its result. Port detail: walkability is read from a
## packed mask (ODGrid.fill_walk_mask) rebuilt whenever the grid revision changes — exactly
## grid.is_walkable, without a function call per neighbour.

## Math.SQRT2.
const SQRT2: float = 1.4142135623730951

# Neighbour order is fixed (E, W, S, N, SE, SW, NE, NW) for determinism.
const NDC: Array[int] = [1, -1, 0, 0, 1, -1, 1, -1]
const NDR: Array[int] = [0, 0, 1, -1, 1, 1, -1, -1]
static var _NDC: PackedInt32Array = PackedInt32Array(NDC)
static var _NDR: PackedInt32Array = PackedInt32Array(NDR)


class PathOpts:
	extends RefCounted
	## When the goal is unwalkable or unreachable, return a path to the reachable tile closest to it
	## (Euclidean, ties by lower cost) instead of null. The spark uses this to wait as close as it can
	## to a projection that is inside a wall or sealed off (DESYNC-03: no teleport).
	var allow_partial: bool = false
	## String-pull the tile path into straight runs (default true).
	var smooth: bool = true
	## Clearance radius used while smoothing, tiles. has_radius false = Tuning.BASE.spark_radius.
	var radius: float = 0.0
	var has_radius: bool = false

	static func make(p_allow_partial: bool = false, p_smooth: bool = true) -> PathOpts:
		var o := PathOpts.new()
		o.allow_partial = p_allow_partial
		o.smooth = p_smooth
		return o

	## Chainable: set the smoothing radius.
	func with_radius(r: float) -> PathOpts:
		radius = r
		has_radius = true
		return self


class PathResult:
	extends RefCounted
	## Waypoints to visit in order, excluding the start point. Ends at the goal point when it was reached.
	var points: Array[Vector2] = []
	## True if the goal tile itself was reached (false for a partial path).
	var complete: bool = false
	## Path cost in tiles along the tile graph (before smoothing).
	var cost: float = 0.0


var grid: ODGrid
var _n: int = 0
var _g: PackedFloat64Array
var _parent: PackedInt32Array
var _open_gen: PackedInt32Array
var _closed_gen: PackedInt32Array
var _gen: int = 0
# Binary min-heap with lazy deletion.
var _heap_node: PackedInt32Array
var _heap_f: PackedFloat64Array
var _heap_h: PackedFloat64Array
var _heap_size: int = 0
# Connected components of walkable tiles (4-connectivity equals 8-connectivity without corner
# cutting, since any legal diagonal step can be replaced by two orthogonal ones).
var _comp: PackedInt32Array
var _comp_revision: int = -1
var _flood_stack: PackedInt32Array
# Walkability mask with a one-tile border (see ODGrid.fill_walk_mask) and the revision it reflects.
var _walk: PackedByteArray
var _walk_revision: int = -1
var _walk_w: int = 0
## Nodes expanded by the most recent search (diagnostics, performance tests).
var last_expanded: int = 0

# Result of the last _search (the prototype returns a small object; kept as fields here).
var _res_tiles: PackedInt32Array
var _res_complete: bool = false
var _res_cost: float = 0.0
# 64-bit waypoint scratch for find_path (grown on demand, never shrunk).
var _px: PackedFloat64Array
var _py: PackedFloat64Array


func _init(p_grid: ODGrid) -> void:
	grid = p_grid
	var n := p_grid.cols * p_grid.rows
	_n = n
	_g.resize(n)
	_parent.resize(n)
	_open_gen.resize(n)
	_open_gen.fill(0)
	_closed_gen.resize(n)
	_closed_gen.fill(0)
	var cap := maxi(16, n * 2)
	_heap_node.resize(cap)
	_heap_f.resize(cap)
	_heap_h.resize(cap)
	_comp.resize(n)
	_flood_stack.resize(n)
	_walk_w = p_grid.cols + 2


func _ensure_walk() -> void:
	if _walk_revision == grid.revision and _walk_revision >= 0:
		return
	grid.fill_walk_mask(_walk)
	_walk_revision = grid.revision

# ───────────────────────────── reachability ─────────────────────────────


## Component id of a tile (-1 if unwalkable). Recomputed lazily when the grid revision changes.
func component_of(c: int, r: int) -> int:
	if not grid.in_bounds(c, r):
		return -1
	_ensure_components()
	return _comp[r * grid.cols + c]


## Is there any route between two tiles right now? O(1) after a per-revision flood fill.
func has_route(c0: int, r0: int, c1: int, r1: int) -> bool:
	var a := component_of(c0, r0)
	return a >= 0 and a == component_of(c1, r1)


## has_route between the tiles under two world points.
func has_route_between(a: Vector2, b: Vector2) -> bool:
	return has_route(floori(a.x), floori(a.y), floori(b.x), floori(b.y))


func _ensure_components() -> void:
	if _comp_revision == grid.revision and _comp_revision >= 0:
		return
	_ensure_walk()
	var cols := grid.cols
	var w := _walk_w
	var walk := _walk
	_comp.fill(-1)
	var next := 0
	for i in _n:
		if _comp[i] != -1:
			continue
		var c := i % cols
		var r := (i - c) / cols
		if walk[(r + 1) * w + c + 1] == 0:
			continue
		var sp := 0
		_flood_stack[sp] = i
		sp += 1
		_comp[i] = next
		while sp > 0:
			sp -= 1
			var j := _flood_stack[sp]
			var jc := j % cols
			var jr := (j - jc) / cols
			for d in 4:
				var nc := jc + NDC[d]
				var nr := jr + NDR[d]
				if walk[(nr + 1) * w + nc + 1] == 0:
					continue
				var k := nr * cols + nc
				if _comp[k] != -1:
					continue
				_comp[k] = next
				_flood_stack[sp] = k
				sp += 1
		next += 1
	_comp_revision = grid.revision

# ───────────────────────────── A* ─────────────────────────────


## Tile path from (c0, r0) to (c1, r1) as tile indices, start and goal inclusive. Empty when there is
## no path (the prototype's null; a found path always holds at least the start tile).
## With allow_partial the path ends at the reachable tile nearest the goal.
func find_tile_path(c0: int, r0: int, c1: int, r1: int, allow_partial: bool = false) -> Array[int]:
	var out: Array[int] = []
	if not _search(c0, r0, c1, r1, allow_partial):
		return out
	for t: int in _res_tiles:
		out.append(t)
	return out


## Runs A*. Returns false for the prototype's null; otherwise _res_tiles / _res_complete / _res_cost.
func _search(c0: int, r0: int, c1: int, r1: int, allow_partial: bool) -> bool:
	var cols := grid.cols
	last_expanded = 0
	_ensure_walk()
	var walk := _walk
	var w := _walk_w
	if not grid.in_bounds(c0, r0) or walk[(r0 + 1) * w + c0 + 1] == 0:
		return false
	var start := r0 * cols + c0
	var goal_walkable := grid.in_bounds(c1, r1) and walk[(r1 + 1) * w + c1 + 1] == 1
	if not allow_partial:
		if not goal_walkable or not has_route(c0, r0, c1, r1):
			return false
	var goal := r1 * cols + c1 if goal_walkable else -1
	if start == goal:
		_res_tiles.resize(1)
		_res_tiles[0] = start
		_res_complete = true
		_res_cost = 0.0
		return true

	var gen := _next_gen()
	# Local references to the buffers: GDScript packed arrays assigned to a variable share storage, so
	# writes through these land in the members (and are cheaper than member access).
	var g := _g
	var parent := _parent
	var open_gen := _open_gen
	var closed_gen := _closed_gen
	var hn := _heap_node
	var hf := _heap_f
	var hh := _heap_h
	var size := 0

	g[start] = 0.0
	parent[start] = -1
	open_gen[start] = gen
	var h0 := _octile(c0, r0, c1, r1)
	hn[0] = start
	hf[0] = h0
	hh[0] = h0
	size = 1

	var best := start
	var best_d := _euclid2(c0, r0, c1, r1)
	var best_g := 0.0
	var found := false
	var expanded := 0
	var ndc := _NDC
	var ndr := _NDR
	# Neighbour offsets in the padded walk mask and in tile indices, in NDC/NDR order.
	var woff := PackedInt32Array()
	var toff := PackedInt32Array()
	woff.resize(8)
	toff.resize(8)
	for k in 8:
		woff[k] = ndr[k] * w + ndc[k]
		toff[k] = ndr[k] * cols + ndc[k]

	while size > 0:
		# ── pop (the prototype's pop(); sift-down with the last entry held aside) ──
		var node := hn[0]
		size -= 1
		if size > 0:
			var xn := hn[size]
			var xf := hf[size]
			var xh := hh[size]
			var i := 0
			while true:
				var l := 2 * i + 1
				if l >= size:
					break
				var r := l + 1
				var m := l
				if r < size:
					# less(r, l)
					var fr := hf[r]
					var fl := hf[l]
					if fr != fl:
						if fr < fl:
							m = r
					else:
						var hr := hh[r]
						var hl := hh[l]
						if (hr < hl) if hr != hl else (hn[r] < hn[l]):
							m = r
				# !less(m, x): stop when child m is not smaller than the held entry.
				var mf := hf[m]
				var m_less: bool
				if mf != xf:
					m_less = mf < xf
				else:
					var mh := hh[m]
					m_less = (mh < xh) if mh != xh else (hn[m] < xn)
				if not m_less:
					break
				hn[i] = hn[m]
				hf[i] = mf
				hh[i] = hh[m]
				i = m
			hn[i] = xn
			hf[i] = xf
			hh[i] = xh
		if closed_gen[node] == gen:
			continue
		closed_gen[node] = gen
		expanded += 1
		if node == goal:
			found = true
			break
		var nc0 := node % cols
		var nr0 := (node - nc0) / cols
		var gn := g[node]
		if allow_partial:
			var ex := c1 - nc0
			var ey := r1 - nr0
			var d := float(ex * ex + ey * ey)
			if d < best_d or (d == best_d and gn < best_g):
				best_d = d
				best_g = gn
				best = node
		var wrow := (nr0 + 1) * w + nc0 + 1
		for k in 8:
			if walk[wrow + woff[k]] == 0:
				continue
			var step := 1.0
			if k >= 4:
				# No corner cutting: both orthogonal neighbours of a diagonal step must be open.
				if walk[wrow + ndc[k]] == 0 or walk[wrow + ndr[k] * w] == 0:
					continue
				step = SQRT2
			var ni := node + toff[k]
			if closed_gen[ni] == gen:
				continue
			var ng := gn + step
			if open_gen[ni] == gen and ng >= g[ni]:
				continue
			open_gen[ni] = gen
			g[ni] = ng
			parent[ni] = node
			# _octile(nc, nr, c1, r1), inlined (same arithmetic).
			var hx := absi(c1 - (nc0 + ndc[k]))
			var hy := absi(r1 - (nr0 + ndr[k]))
			var h: float = hx - hy + SQRT2 * hy if hx > hy else hy - hx + SQRT2 * hx
			var f := ng + h
			# ── push (the prototype's push(); sift-up with the new entry held aside) ──
			if size == hn.size():
				_grow()
				hn = _heap_node
				hf = _heap_f
				hh = _heap_h
			var j := size
			size += 1
			while j > 0:
				var p := (j - 1) >> 1
				var fp := hf[p]
				var less: bool
				if f != fp:
					less = f < fp
				else:
					var hp := hh[p]
					less = (h < hp) if h != hp else (ni < hn[p])
				if not less:
					break
				hn[j] = hn[p]
				hf[j] = fp
				hh[j] = hh[p]
				j = p
			hn[j] = ni
			hf[j] = f
			hh[j] = h
	_heap_size = size
	last_expanded = expanded

	var end := goal if found else (best if allow_partial else -1)
	if end < 0:
		return false
	var count := 0
	var i := end
	while i != -1:
		count += 1
		i = _parent[i]
	_res_tiles.resize(count)
	i = end
	var j := count - 1
	while i != -1:
		_res_tiles[j] = i
		j -= 1
		i = _parent[i]
	_res_complete = found
	_res_cost = _g[end]
	return true


## World-space path from (sx, sy) to (tx, ty). A start inside an unwalkable tile begins from the
## nearest walkable tile. Returns null when no route exists (unless allow_partial).
func find_path(sx: float, sy: float, tx: float, ty: float, opts: PathOpts = null) -> PathResult:
	var cols := grid.cols
	var c0 := floori(sx)
	var r0 := floori(sy)
	if not grid.is_walkable(c0, r0):
		var near := grid.nearest_walkable(c0, r0)
		if near < 0:
			return null
		c0 = near % cols
		r0 = (near - c0) / cols
	var c1 := floori(tx)
	var r1 := floori(ty)
	if not _search(c0, r0, c1, r1, opts != null and opts.allow_partial):
		return null
	# Waypoints stay 64-bit (scratch buffers) until the result is built: the exact goal point feeds the
	# smoothing sweeps, and rounding it to a 32-bit Vector2 first changes which waypoints survive.
	var nt := _res_tiles.size()
	if _px.size() < nt + 1:
		_px.resize(nt + 1)
		_py.resize(nt + 1)
	var px := _px
	var py := _py
	var np := 0
	for i in range(1, nt):
		var t := _res_tiles[i]
		var c := t % cols
		px[np] = c + 0.5
		py[np] = (t - c) / cols + 0.5
		np += 1
	if _res_complete:
		# Finish on the exact goal point, replacing the goal tile's centre.
		if np == 0:
			np = 1
		px[np - 1] = tx
		py[np - 1] = ty
	elif np == 0 and (c0 + 0.5 != sx or r0 + 0.5 != sy):
		# Partial path that never left the start tile: still head for its centre (stable waiting spot).
		px[0] = c0 + 0.5
		py[0] = r0 + 0.5
		np = 1
	var res := PathResult.new()
	if opts != null and not opts.smooth:
		for k in np:
			res.points.append(Vector2(px[k], py[k]))
	else:
		var radius := opts.radius if opts != null and opts.has_radius else Tuning.BASE.spark_radius
		_smooth_xy(sx, sy, px, py, np, radius, res.points)
	res.complete = _res_complete
	res.cost = _res_cost
	return res


## String pulling by line of walk: from each kept point, skip ahead to the last consecutive
## waypoint a circle of `radius` can sweep to without touching movement-blocking tiles.
## The next waypoint is always kept even if the sweep to it is tight, so progress is guaranteed.
func smooth(sx: float, sy: float, points: Array[Vector2], radius: float) -> Array[Vector2]:
	var n := points.size()
	var px := PackedFloat64Array()
	var py := PackedFloat64Array()
	px.resize(n)
	py.resize(n)
	for k in n:
		px[k] = points[k].x
		py[k] = points[k].y
	var out: Array[Vector2] = []
	_smooth_xy(sx, sy, px, py, n, radius, out)
	return out


## smooth() over 64-bit waypoints (the first `n` entries of px / py); appends the kept ones to `out`.
func _smooth_xy(sx: float, sy: float, px: PackedFloat64Array, py: PackedFloat64Array, n: int, radius: float, out: Array[Vector2]) -> void:
	if n <= 1:
		for k in n:
			out.append(Vector2(px[k], py[k]))
		return
	var ax := sx
	var ay := sy
	var i := 0
	while i < n:
		var j := i
		while j + 1 < n and not grid.sweep_circle_blocked(ax, ay, px[j + 1], py[j + 1], radius):
			j += 1
		out.append(Vector2(px[j], py[j]))
		ax = px[j]
		ay = py[j]
		i = j + 1

# ───────────────────────────── heap ─────────────────────────────


func _next_gen() -> int:
	_gen += 1
	# The prototype stores generations in a Uint32Array and wraps at 0xffffffff; PackedInt32Array is
	# signed, so wrap at 0x7fffffff instead (same reset, just earlier; unreachable in practice).
	if _gen >= 0x7fffffff:
		_gen = 1
		_open_gen.fill(0)
		_closed_gen.fill(0)
	return _gen


## The binary min-heap (lazy deletion) is inlined in _search. Its order is the prototype's less(a, b):
## f, then h, then tile index; push / pop sift with the moving entry held aside, which makes the same
## comparisons and leaves the same layout as the prototype's swap-based sifting.


func _grow() -> void:
	var cap := _heap_node.size() * 2
	_heap_node.resize(cap)
	_heap_f.resize(cap)
	_heap_h.resize(cap)


static func _octile(c0: int, r0: int, c1: int, r1: int) -> float:
	var dx := absi(c1 - c0)
	var dy := absi(r1 - r0)
	return dx - dy + SQRT2 * dy if dx > dy else dy - dx + SQRT2 * dx


static func _euclid2(c0: int, r0: int, c1: int, r1: int) -> float:
	var dx := c1 - c0
	var dy := r1 - r0
	return float(dx * dx + dy * dy)


## Total length of a polyline starting at (sx, sy).
static func path_length(sx: float, sy: float, points: Array[Vector2]) -> float:
	var len := 0.0
	var x := sx
	var y := sy
	for p: Vector2 in points:
		len += ODGrid.hypot(p.x - x, p.y - y)
		x = p.x
		y = p.y
	return len
