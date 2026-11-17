class_name ODGrid
extends RefCounted
## Tile grid: static map solidity plus a dynamic overlay, and the geometric queries the kernel,
## player controller, path-finder and projectiles share. Port of prototype/src/core/grid.ts
## (class Grid is this class).
##
## Tile (c, r) covers world x ∈ [c, c+1), y ∈ [r, r+1) (see MapRows in LevelDef). Out-of-bounds
## tiles behave as walls for everything.
##
## Two kinds of solidity:
##   movement   — walls, void, low barriers ('='), dynamic solids. Bodies collide with these.
##   projectile — walls and dynamic solids only. Projectiles and line of sight pass over void and
##                low barriers.
## The dynamic overlay (closed doors, unbroken breakables) blocks both and is set by the kernel.
##
## All coordinates are float (64-bit) scalars; nothing here goes through Vector2 (32-bit) except the
## Vector2 convenience overloads (line_of_sight), so results match the prototype's doubles.

# ───────────────────────────── tiles ─────────────────────────────

const TILE_WALL: int = 0
const TILE_FLOOR: int = 1
const TILE_VOID: int = 2
const TILE_LOW: int = 3
const TILE_GRATE: int = 4
const TILE_OVERGROWN: int = 5
const TILE_RUNE: int = 6

const _CHAR_TO_TILE: Dictionary[String, int] = {
	"#": TILE_WALL,
	".": TILE_FLOOR,
	" ": TILE_VOID,
	"=": TILE_LOW,
	":": TILE_GRATE,
	",": TILE_OVERGROWN,
	"~": TILE_RUNE,
}

## Map character for each tile kind (index = kind).
const TILE_CHARS: Array[String] = ["#", ".", " ", "=", ":", ",", "~"]


## True for the tile kinds a body may stand on.
static func is_floor_kind(kind: int) -> bool:
	return kind == TILE_FLOOR or kind == TILE_GRATE or kind == TILE_OVERGROWN or kind == TILE_RUNE


class MoveOpts:
	extends RefCounted
	## Low barriers do not block (the 'phaseDodge' ability during a dodge).
	var ignore_low: bool = false

	static func make(p_ignore_low: bool) -> MoveOpts:
		var o := MoveOpts.new()
		o.ignore_low = p_ignore_low
		return o


class MoveResult:
	extends RefCounted
	var x: float = 0.0
	var y: float = 0.0
	## True if any collision changed the requested motion.
	var blocked: bool = false


class RayHit:
	extends RefCounted
	## True if a blocking tile was hit within the distance limit.
	var hit: bool = false
	## Distance along the ray to the hit (or to the limit when nothing was hit).
	var dist: float = 0.0
	## World point of the hit (or of the limit).
	var x: float = 0.0
	var y: float = 0.0
	## Tile that was hit (-1, -1 when nothing was hit).
	var c: int = -1
	var r: int = -1
	## Surface normal of the face that was entered (0, 0 when starting inside a solid or no hit).
	var nx: float = 0.0
	var ny: float = 0.0


## Details of a malformed map (grid.ts MapParseError) so the level validator can report the level and
## cell. Passed to parse() to be filled; `failed` tells whether it was.
class MapParseError:
	extends RefCounted
	var failed: bool = false
	var message: String = ""
	var c: int = 0
	var r: int = 0

## Static block flags.
const _BLOCK_NONE: int = 0
const _BLOCK_MOVE: int = 1
const _BLOCK_SHOT: int = 2
## Blocks movement only because it is a low barrier (ignorable with MoveOpts.ignore_low).
const _BLOCK_LOW: int = 4

## Largest sub-move move_circle takes before resolving; < 0.5 so no tile can be skipped.
const MOVE_STEP: float = 0.2

# ───────────────────────────── grid ─────────────────────────────

var cols: int = 0
var rows: int = 0
## Tile kind per tile, row-major (index = r * cols + c). Read-only after construction.
var tiles: PackedByteArray
## Static block flags per tile.
var _static_block: PackedByteArray
## 1 where the kernel has made the tile solid this substep.
var _dynamic: PackedByteArray
var _revision: int = 0
## resolve_circle's result (the prototype's module-level scratch; per instance here so two grids on
## two threads never share it).
var _res_x: float = 0.0
var _res_y: float = 0.0

## Incremented whenever the dynamic overlay actually changes. Path caches and spark re-planning
## key off it (DESYNC-04: a reopened route must be noticed).
var revision: int:
	get:
		return _revision


## Use create() / parse() for validated construction. `p_tiles` must hold cols * rows kinds.
func _init(p_cols: int = 1, p_rows: int = 1, p_tiles: PackedByteArray = PackedByteArray([TILE_WALL])) -> void:
	if not (p_cols > 0 and p_rows > 0) or p_tiles.size() != p_cols * p_rows:
		push_error("Grid: bad dimensions %dx%d for %d tiles" % [p_cols, p_rows, p_tiles.size()])
		p_cols = 1
		p_rows = 1
		p_tiles = PackedByteArray([TILE_WALL])
	cols = p_cols
	rows = p_rows
	tiles = p_tiles
	var n := p_tiles.size()
	_static_block.resize(n)
	_dynamic.resize(n)
	_dynamic.fill(0)
	for i in n:
		var t := tiles[i]
		var b := _BLOCK_NONE
		if t == TILE_WALL:
			b = _BLOCK_MOVE | _BLOCK_SHOT
		elif t == TILE_VOID:
			b = _BLOCK_MOVE
		elif t == TILE_LOW:
			b = _BLOCK_MOVE | _BLOCK_LOW
		_static_block[i] = b


## Validated constructor (the prototype's `new Grid(...)`, which throws). Returns null and appends the
## prototype's message to `errors` on bad dimensions.
static func create(p_cols: int, p_rows: int, p_tiles: PackedByteArray, errors: Array[String] = []) -> ODGrid:
	if not (p_cols > 0 and p_rows > 0) or p_tiles.size() != p_cols * p_rows:
		errors.append("Grid: bad dimensions %dx%d for %d tiles" % [p_cols, p_rows, p_tiles.size()])
		return null
	return ODGrid.new(p_cols, p_rows, p_tiles)


## Parse MapRows. Short rows are padded with void. On an unknown character (or an empty map) returns
## null, appends the MapParseError message to `errors` and, when given, fills `parse_error`.
static func parse(map: Array[String], errors: Array[String] = [], parse_error: MapParseError = null) -> ODGrid:
	var n_rows := map.size()
	var n_cols := 0
	for row: String in map:
		n_cols = maxi(n_cols, row.length())
	if n_rows == 0 or n_cols == 0:
		return _parse_fail("Map is empty", 0, 0, errors, parse_error)
	var t := PackedByteArray()
	t.resize(n_cols * n_rows)
	t.fill(TILE_VOID)
	for r in n_rows:
		var row := map[r]
		for c in row.length():
			var ch := row[c]
			var kind: int = _CHAR_TO_TILE.get(ch, -1)
			if kind < 0:
				return _parse_fail("Unknown map character %s at column %d, row %d" % [JSON.stringify(ch), c, r], c, r, errors, parse_error)
			t[r * n_cols + c] = kind
	return ODGrid.new(n_cols, n_rows, t)


static func _parse_fail(message: String, c: int, r: int, errors: Array[String], parse_error: MapParseError) -> ODGrid:
	errors.append(message)
	if parse_error != null:
		parse_error.failed = true
		parse_error.message = message
		parse_error.c = c
		parse_error.r = r
	return null


## Parse a level's map (Grid.fromLevel).
static func from_level(level: LevelDef, errors: Array[String] = [], parse_error: MapParseError = null) -> ODGrid:
	return parse(level.map, errors, parse_error)


## Parse a level's map (grid.ts parseGrid).
static func parse_grid(map: Array[String], errors: Array[String] = [], parse_error: MapParseError = null) -> ODGrid:
	return parse(map, errors, parse_error)


func in_bounds(c: int, r: int) -> bool:
	return c >= 0 and r >= 0 and c < cols and r < rows


func index(c: int, r: int) -> int:
	return r * cols + c


## Tile kind; out of bounds reads as wall.
func tile_at(c: int, r: int) -> int:
	return tiles[r * cols + c] if (c >= 0 and r >= 0 and c < cols and r < rows) else TILE_WALL


## Tile kind under a world point.
func tile_at_point(x: float, y: float) -> int:
	return tile_at(floori(x), floori(y))

# ── dynamic overlay ──


func set_dynamic_solid(c: int, r: int, solid: bool) -> void:
	if not in_bounds(c, r):
		return
	var i := r * cols + c
	var v := 1 if solid else 0
	if _dynamic[i] != v:
		_dynamic[i] = v
		_revision += 1


func is_dynamic_solid(c: int, r: int) -> bool:
	return in_bounds(c, r) and _dynamic[r * cols + c] == 1


func clear_dynamic() -> void:
	var changed := false
	for i in _dynamic.size():
		if _dynamic[i] != 0:
			_dynamic[i] = 0
			changed = true
	if changed:
		_revision += 1

# ── per-tile solidity ──


## Does tile (c, r) block bodies?
func blocks_move(c: int, r: int, ignore_low: bool = false) -> bool:
	if c < 0 or r < 0 or c >= cols or r >= rows:
		return true
	var i := r * cols + c
	if _dynamic[i] == 1:
		return true
	var b := _static_block[i]
	if b & _BLOCK_MOVE:
		return not (ignore_low and (b & _BLOCK_LOW) != 0)
	return false


## Does tile (c, r) block projectiles and line of sight?
func blocks_shot(c: int, r: int) -> bool:
	if c < 0 or r < 0 or c >= cols or r >= rows:
		return true
	var i := r * cols + c
	return _dynamic[i] == 1 or (_static_block[i] & _BLOCK_SHOT) != 0


## Can a body stand on tile (c, r) right now? (floor and not dynamically solid)
func is_walkable(c: int, r: int) -> bool:
	return not blocks_move(c, r, false)


## Is the tile statically walkable, ignoring the dynamic overlay? (door cells are)
func is_static_walkable(c: int, r: int) -> bool:
	return in_bounds(c, r) and (_static_block[r * cols + c] & _BLOCK_MOVE) == 0


## A packed walkability mask for fast inner loops (used by Pathfinder): byte (r + 1) * (cols + 2) +
## (c + 1) is 1 when is_walkable(c, r); the one-tile border is 0 (out of bounds = wall). Rebuilt by
## the caller whenever `revision` changes.
func fill_walk_mask(out: PackedByteArray) -> void:
	var w := cols + 2
	out.resize(w * (rows + 2))
	out.fill(0)
	for r in rows:
		var row_in := r * cols
		var row_out := (r + 1) * w + 1
		for c in cols:
			var i := row_in + c
			if _dynamic[i] == 0 and (_static_block[i] & _BLOCK_MOVE) == 0:
				out[row_out + c] = 1

# ── circle queries ──


## Does a circle overlap any movement-blocking tile? Touching exactly is not overlapping.
## A radius ≤ 0 tests the point's tile.
func is_solid_at(x: float, y: float, radius: float, opts: MoveOpts = null) -> bool:
	var ignore_low := opts != null and opts.ignore_low
	if not (radius > 0.0):
		return blocks_move(floori(x), floori(y), ignore_low)
	var r2 := radius * radius
	var c0 := floori(x - radius)
	var c1 := floori(x + radius)
	var r0 := floori(y - radius)
	var r1 := floori(y + radius)
	for r in range(r0, r1 + 1):
		for c in range(c0, c1 + 1):
			if not blocks_move(c, r, ignore_low):
				continue
			var qx: float = float(c) if x < c else (float(c + 1) if x > c + 1 else x)
			var qy: float = float(r) if y < r else (float(r + 1) if y > r + 1 else y)
			var dx := x - qx
			var dy := y - qy
			if dx * dx + dy * dy < r2:
				return true
	return false


## Move a circle by (dx, dy) with wall sliding. The motion is cut into steps of at most
## MOVE_STEP tiles and penetration is resolved after each, so a fast body cannot tunnel through a
## 1-tile wall (a step never carries the centre past a tile's middle). Resolved circles rest
## COLLISION_SKIN outside walls. When nothing blocks, the result is exactly (x + dx, y + dy).
func move_circle(x: float, y: float, dx: float, dy: float, radius: float, opts: MoveOpts = null, out: MoveResult = null) -> MoveResult:
	var res := out if out != null else MoveResult.new()
	var ignore_low := opts != null and opts.ignore_low
	var rad := radius if radius > 0.0 else 1e-4
	var dist := hypot(dx, dy)
	var n := ceili(dist / MOVE_STEP) if dist > 0.0 else 0
	var px := x
	var py := y
	var blocked := false
	if _resolve_circle(px, py, rad, ignore_low):
		px = _res_x
		py = _res_y
		blocked = true
	var sx := dx / n if n > 0 else 0.0
	var sy := dy / n if n > 0 else 0.0
	for i in n:
		px += sx
		py += sy
		if _resolve_circle(px, py, rad, ignore_low):
			px = _res_x
			py = _res_y
			blocked = true
	if blocked:
		res.x = px
		res.y = py
	else:
		res.x = x + dx
		res.y = y + dy
	res.blocked = blocked
	return res


## Push a circle out of blocking tiles, deepest penetration first so internal seams between
## adjacent wall tiles never produce sideways bumps. Returns true if it moved; result in _res_x/_res_y.
func _resolve_circle(x: float, y: float, radius: float, ignore_low: bool) -> bool:
	var moved := false
	var r2 := radius * radius
	var skin := Tuning.COLLISION_SKIN
	for iter in 8:
		var best := -1
		var best_pen := 0.0
		var best_px := 0.0
		var best_py := 0.0
		var c0 := floori(x - radius)
		var c1 := floori(x + radius)
		var r0 := floori(y - radius)
		var r1 := floori(y + radius)
		for r in range(r0, r1 + 1):
			for c in range(c0, c1 + 1):
				if not blocks_move(c, r, ignore_low):
					continue
				var qx: float = float(c) if x < c else (float(c + 1) if x > c + 1 else x)
				var qy: float = float(r) if y < r else (float(r + 1) if y > r + 1 else y)
				var ddx := x - qx
				var ddy := y - qy
				var d2 := ddx * ddx + ddy * ddy
				if d2 >= r2:
					continue
				var pen: float
				var pxv: float
				var pyv: float
				if d2 > 1e-18:
					var d := sqrt(d2)
					pen = radius - d
					var k := (radius + skin - d) / d
					pxv = ddx * k
					pyv = ddy * k
				else:
					# Centre inside (or on the edge of) the tile: leave through the nearest face whose
					# neighbour is open, so a body is never shoved deeper into a wall mass.
					var left := x - c
					var right := c + 1 - x
					var top := y - r
					var bottom := r + 1 - y
					var face := -1
					var face_dist := INF
					# consider(face, dist, neighbour, requireOpen) in the prototype's order: W, E, N, S.
					if not blocks_move(c - 1, r, ignore_low) and left < face_dist:
						face_dist = left
						face = 0
					if not blocks_move(c + 1, r, ignore_low) and right < face_dist:
						face_dist = right
						face = 1
					if not blocks_move(c, r - 1, ignore_low) and top < face_dist:
						face_dist = top
						face = 2
					if not blocks_move(c, r + 1, ignore_low) and bottom < face_dist:
						face_dist = bottom
						face = 3
					if face < 0:
						if left < face_dist:
							face_dist = left
							face = 0
						if right < face_dist:
							face_dist = right
							face = 1
						if top < face_dist:
							face_dist = top
							face = 2
						if bottom < face_dist:
							face_dist = bottom
							face = 3
					pen = radius + face_dist
					var push := face_dist + radius + skin
					pxv = -push if face == 0 else (push if face == 1 else 0.0)
					pyv = -push if face == 2 else (push if face == 3 else 0.0)
				if pen > best_pen:
					best_pen = pen
					best = r * cols + c
					best_px = pxv
					best_py = pyv
		if best < 0:
			break
		x += best_px
		y += best_py
		moved = true
	_res_x = x
	_res_y = y
	return moved


## Would a circle swept from (x0, y0) to (x1, y1) overlap any movement-blocking tile?
## Exact (segment-to-box distance), not sampled. Used for the desync "straight step is blocked"
## test and for path string-pulling. A radius ≤ 0 falls back to the tile walk of segment_blocked.
func sweep_circle_blocked(x0: float, y0: float, x1: float, y1: float, radius: float, opts: MoveOpts = null) -> bool:
	var ignore_low := opts != null and opts.ignore_low
	if not (radius > 0.0):
		return _traverse(x0, y0, x1 - x0, y1 - y0, 1.0, false, ignore_low, null)
	var len := hypot(x1 - x0, y1 - y0)
	# Chunk long sweeps so each chunk's candidate box stays small.
	var chunks := maxi(1, ceili(len / 2.0))
	var r2 := radius * radius
	for k in chunks:
		var ax := x0 + ((x1 - x0) * k) / chunks
		var ay := y0 + ((y1 - y0) * k) / chunks
		var bx := x1 if k == chunks - 1 else x0 + ((x1 - x0) * (k + 1)) / chunks
		var by := y1 if k == chunks - 1 else y0 + ((y1 - y0) * (k + 1)) / chunks
		var c0 := floori(minf(ax, bx) - radius)
		var c1 := floori(maxf(ax, bx) + radius)
		var r0 := floori(minf(ay, by) - radius)
		var r1 := floori(maxf(ay, by) + radius)
		for r in range(r0, r1 + 1):
			for c in range(c0, c1 + 1):
				if not blocks_move(c, r, ignore_low):
					continue
				if segment_box_dist2(ax, ay, bx, by, c, r, c + 1, r + 1) < r2:
					return true
	return false

# ── rays ──


## Does the segment pass through a blocking tile? `for_projectile` selects projectile/sight
## solidity (walls, dynamic) instead of movement solidity (also void and low barriers).
## Includes the start and end tiles. Passing exactly through a corner between two tiles is blocked
## only if both of them block (a sealed diagonal), not by grazing one.
func segment_blocked(x0: float, y0: float, x1: float, y1: float, for_projectile: bool) -> bool:
	return _traverse(x0, y0, x1 - x0, y1 - y0, 1.0, for_projectile, false, null)


## Clear line of sight between two points (projectile solidity). Vector2 is 32-bit: callers holding
## 64-bit positions should prefer line_of_sight_xy.
func line_of_sight(a: Vector2, b: Vector2) -> bool:
	return not _traverse(a.x, a.y, b.x - a.x, b.y - a.y, 1.0, true, false, null)


## line_of_sight on scalar (64-bit) coordinates.
func line_of_sight_xy(ax: float, ay: float, bx: float, by: float) -> bool:
	return not _traverse(ax, ay, bx - ax, by - ay, 1.0, true, false, null)


## Cast a ray from (x0, y0) along (dir_x, dir_y) (need not be normalised) up to max_dist tiles.
## Returns the first blocking tile and the distance to its entry face.
func raycast(x0: float, y0: float, dir_x: float, dir_y: float, max_dist: float, for_projectile: bool, out: RayHit = null) -> RayHit:
	var res := out if out != null else RayHit.new()
	var len := hypot(dir_x, dir_y)
	if not (len > 0.0):
		var c := floori(x0)
		var r := floori(y0)
		var hit := blocks_shot(c, r) if for_projectile else blocks_move(c, r)
		res.hit = hit
		res.dist = 0.0
		res.x = x0
		res.y = y0
		res.c = c if hit else -1
		res.r = r if hit else -1
		res.nx = 0.0
		res.ny = 0.0
		return res
	var ux := dir_x / len
	var uy := dir_y / len
	res.hit = _traverse(x0, y0, ux, uy, max_dist, for_projectile, false, res)
	if not res.hit:
		res.dist = max_dist
		res.c = -1
		res.r = -1
		res.nx = 0.0
		res.ny = 0.0
	res.x = x0 + ux * res.dist
	res.y = y0 + uy * res.dist
	return res


func _blocks(c: int, r: int, for_projectile: bool, ignore_low: bool) -> bool:
	return blocks_shot(c, r) if for_projectile else blocks_move(c, r, ignore_low)


## Amanatides–Woo grid walk along p(t) = (x0, y0) + t·(dx, dy), t ∈ [0, t_max]. Returns true on
## the first blocking tile; if `hit` is given, fills dist (= t), tile and entry normal.
func _traverse(x0: float, y0: float, dx: float, dy: float, t_max: float, for_projectile: bool, ignore_low: bool, hit: RayHit) -> bool:
	var c := floori(x0)
	var r := floori(y0)
	if _blocks(c, r, for_projectile, ignore_low):
		if hit != null:
			_set_hit(hit, 0.0, c, r, 0.0, 0.0)
		return true
	var step_x := 1 if dx > 0.0 else (-1 if dx < 0.0 else 0)
	var step_y := 1 if dy > 0.0 else (-1 if dy < 0.0 else 0)
	var t_delta_x := 1.0 / absf(dx) if step_x != 0 else INF
	var t_delta_y := 1.0 / absf(dy) if step_y != 0 else INF
	var t_max_x: float = (c + 1 - x0) / dx if step_x > 0 else ((x0 - c) / -dx if step_x < 0 else INF)
	var t_max_y: float = (r + 1 - y0) / dy if step_y > 0 else ((y0 - r) / -dy if step_y < 0 else INF)
	# Bounded by the number of tile boundaries the segment can cross.
	var limit := 4 + ceili(absf(dx) * t_max) + ceili(absf(dy) * t_max) + 2
	for n in limit:
		var diff := t_max_x - t_max_y
		var tie := absf(diff) <= 1e-12 * maxf(1.0, absf(t_max_x)) and t_max_x != INF
		if tie:
			var t := t_max_x
			if t > t_max:
				return false
			var a_blocks := _blocks(c + step_x, r, for_projectile, ignore_low)
			var b_blocks := _blocks(c, r + step_y, for_projectile, ignore_low)
			if a_blocks and b_blocks:
				if hit != null:
					_set_hit(hit, t, c + step_x, r, -step_x, 0.0)
				return true
			c += step_x
			r += step_y
			t_max_x += t_delta_x
			t_max_y += t_delta_y
			if _blocks(c, r, for_projectile, ignore_low):
				if hit != null:
					_set_hit(hit, t, c, r, -step_x, -step_y)
				return true
		elif diff < 0.0:
			var t := t_max_x
			if t > t_max:
				return false
			c += step_x
			t_max_x += t_delta_x
			if _blocks(c, r, for_projectile, ignore_low):
				if hit != null:
					_set_hit(hit, t, c, r, -step_x, 0.0)
				return true
		else:
			var t := t_max_y
			if t > t_max:
				return false
			r += step_y
			t_max_y += t_delta_y
			if _blocks(c, r, for_projectile, ignore_low):
				if hit != null:
					_set_hit(hit, t, c, r, 0.0, -step_y)
				return true
	return false


## Nearest walkable tile to (c, r) by Chebyshev rings, scanning each ring in a fixed order
## (deterministic). Returns the tile index or -1 if none within max_ring.
func nearest_walkable(c: int, r: int, max_ring: int = 8) -> int:
	if is_walkable(c, r):
		return index(c, r)
	var best := -1
	var best_d := INF
	for ring in range(1, max_ring + 1):
		for rr in range(r - ring, r + ring + 1):
			for cc in range(c - ring, c + ring + 1):
				if maxi(absi(cc - c), absi(rr - r)) != ring:
					continue
				if not is_walkable(cc, rr):
					continue
				var d := (cc - c) * (cc - c) + (rr - r) * (rr - r)
				if d < best_d:
					best_d = d
					best = index(cc, rr)
		if best >= 0:
			return best
	return -1


## ASCII dump (static tiles; dynamic solids shown as 'D'). For debugging and test failure messages.
func _to_string() -> String:
	var lines := PackedStringArray()
	for r in rows:
		var s := ""
		for c in cols:
			var i := r * cols + c
			s += "D" if _dynamic[i] != 0 else TILE_CHARS[tiles[i]]
		lines.append(s)
	return "\n".join(lines)


static func _set_hit(h: RayHit, t: float, c: int, r: int, nx: float, ny: float) -> void:
	h.dist = t
	h.c = c
	h.r = r
	h.nx = nx
	h.ny = ny

# ───────────────────────────── geometry helpers ─────────────────────────────


## Math.hypot exactly as V8 computes it (scale by the max, Kahan-compensated sum, sqrt × max), so
## distances are bit-identical to the prototype. A naive sqrt(x*x + y*y) differs in the last bit
## for ~40% of inputs. Use this wherever the prototype calls Math.hypot.
static func hypot(x: float, y: float) -> float:
	var ax := absf(x)
	var ay := absf(y)
	if is_inf(ax) or is_inf(ay):
		return INF
	if is_nan(ax) or is_nan(ay):
		return NAN
	var mx := ax if ax > ay else ay
	if mx == 0.0:
		return 0.0
	var n := ax / mx
	var summand := n * n
	var sum := summand
	var comp := (sum - 0.0) - summand
	n = ay / mx
	summand = n * n - comp
	var prelim := sum + summand
	return sqrt(prelim) * mx


static func _point_box_dist2(px: float, py: float, bx0: float, by0: float, bx1: float, by1: float) -> float:
	var qx := bx0 if px < bx0 else (bx1 if px > bx1 else px)
	var qy := by0 if py < by0 else (by1 if py > by1 else py)
	var dx := px - qx
	var dy := py - qy
	return dx * dx + dy * dy


static func _point_seg_dist2(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
	var vx := bx - ax
	var vy := by - ay
	var l2 := vx * vx + vy * vy
	var t := ((px - ax) * vx + (py - ay) * vy) / l2 if l2 > 0.0 else 0.0
	t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
	var dx := ax + vx * t - px
	var dy := ay + vy * t - py
	return dx * dx + dy * dy


## Liang–Barsky: does segment a→b intersect the closed box?
static func _segment_hits_box(ax: float, ay: float, bx: float, by: float, x0: float, y0: float, x1: float, y1: float) -> bool:
	var dx := bx - ax
	var dy := by - ay
	var t0 := 0.0
	var t1 := 1.0
	# Each slab clips [t0, t1]; p·t <= q must hold for the point to be inside that half-plane.
	# The prototype's clip() closure, applied in its order: -x, +x, -y, +y.
	for s in 4:
		var p: float
		var q: float
		if s == 0:
			p = -dx
			q = ax - x0
		elif s == 1:
			p = dx
			q = x1 - ax
		elif s == 2:
			p = -dy
			q = ay - y0
		else:
			p = dy
			q = y1 - ay
		if p == 0.0:
			if not (q >= 0.0):
				return false
			continue
		var t := q / p
		if p < 0.0:
			if t > t1:
				return false
			if t > t0:
				t0 = t
		else:
			if t < t0:
				return false
			if t < t1:
				t1 = t
	return true


## Squared distance between segment a→b and an axis-aligned box. For disjoint convex shapes the
## minimum is attained at a segment endpoint or a box corner, so those cases cover it exactly.
static func segment_box_dist2(ax: float, ay: float, bx: float, by: float, x0: float, y0: float, x1: float, y1: float) -> float:
	if _segment_hits_box(ax, ay, bx, by, x0, y0, x1, y1):
		return 0.0
	var d := _point_box_dist2(ax, ay, x0, y0, x1, y1)
	d = minf(d, _point_box_dist2(bx, by, x0, y0, x1, y1))
	d = minf(d, _point_seg_dist2(x0, y0, ax, ay, bx, by))
	d = minf(d, _point_seg_dist2(x1, y0, ax, ay, bx, by))
	d = minf(d, _point_seg_dist2(x0, y1, ax, ay, bx, by))
	d = minf(d, _point_seg_dist2(x1, y1, ax, ay, bx, by))
	return d
