class_name DroneBehaviour
extends EnemyBehaviour
## Drone (AI-01, AI-06, AI-07, HEALTH-02): a hovering gun that keeps its distance and fires on the
## off-beat. Port of prototype/src/core/enemies/drone.ts.
##
##   - Hovers: low barriers ('=') and void (' ') do not stop it; walls and closed doors do. It never
##     presses pressure plates (nothing touches the floor).
##   - Spacing: its target is the NEAREST targetable self (re-chosen every beat), and it keeps
##     DRONE_KEEP_DISTANCE tiles (+- DRONE_KEEP_BAND) away. Any self closer than the band pushes it
##     away (pushes from several selves add up, so between two of them it settles where they
##     balance instead of ping-ponging); otherwise, with its target too far or out of sight, it
##     closes in. With nothing pushing and its target in the band it holds position.
##   - Fire: its attack instants are its beat grid (ENEMY_STATS / EnemyDef.beat) shifted by half a
##     beat, so a drone always fires on an "and", never on the beat a grunt or turret uses. Exactly one
##     telegraph before an instant, if its target is within range with a clear line, it stops, locks
##     its aim and telegraphs; the bolt leaves ON the off-beat along the
##     locked aim (dodgeable by moving or rolling). Bolts are the turret's: walls stop them, low
##     barriers do not.
##   - 2 hit points: a standing 1x light chips it, a 2x light (or two selves) kills it.
##   - Knockback over ground it could not stand on would shove it to the nearest floor edge under
##     walking collision, which reads as a teleport; there it takes the damage and stagger only.
##
## Port addition (flight path-finding): out of sight of its target, the prototype followed a
## walking route only while over walkable ground and otherwise flew straight, so a drone over void
## behind an L-shaped wall stuck to the wall forever. Here, when no walking route serves (it is over
## void / a barrier, or the walking graph does not connect it to its target), it plans a FLIGHT
## route: A* over every tile that does not stop flight (anything but walls and closed doors), and
## follows it under hover collision. Where a walking route exists from walkable ground it keeps the
## prototype's walking behaviour exactly.

## Half-width of the comfortable distance band around DRONE_KEEP_DISTANCE, tiles.
const DRONE_KEEP_BAND: float = 0.5
## Recovery after a shot, master beats.
const DRONE_RECOVER_BEATS: float = 0.25
## Off-beat shift of the drone's attack grid, master beats.
const DRONE_OFFBEAT: float = 0.5
## With no line of sight it closes in until this near (it will have sight long before).
const NO_SIGHT_STOP: float = 1.0
## Largest single collision step while hovering, tiles.
const HOVER_STEP: float = 0.1

## mem key holding this drone's FlightPlanner (created on first use).
const MEM_FLIGHT: String = "flight"

const _SQRT2: float = 1.4142135623730951
# Neighbour order is fixed (E, W, S, N, SE, SW, NE, NW) for determinism, as path.ts.
const _NDC: Array[int] = [1, -1, 0, 0, 1, -1, 1, -1]
const _NDR: Array[int] = [0, 0, 1, -1, 1, 1, -1, -1]


func _init() -> void:
	type = EnemyType.DRONE
	hovering = true


## Does a hovering circle overlap anything that stops flight (walls, closed doors)?
static func hover_solid_at(grid: ODGrid, x: float, y: float, radius: float) -> bool:
	var c0: int = floori(x - radius)
	var c1: int = floori(x + radius)
	var r0: int = floori(y - radius)
	var r1: int = floori(y + radius)
	var r2: float = radius * radius
	for r: int in range(r0, r1 + 1):
		for c: int in range(c0, c1 + 1):
			if not grid.blocks_shot(c, r):
				continue
			var qx: float = float(c) if x < c else (float(c + 1) if x > c + 1 else x)
			var qy: float = float(r) if y < r else (float(r + 1) if y > r + 1 else y)
			var dx: float = x - qx
			var dy: float = y - qy
			if dx * dx + dy * dy < r2:
				return true
	return false


## Fly by (dx, dy) under hover collision, sliding along walls axis by axis. Steps are short so it
## cannot tunnel. Returns true if it moved.
static func hover_move(w: ODSim, e: EnemyState, dx: float, dy: float) -> bool:
	var r: float = e.stats.radius
	var n: int = maxi(1, ceili(ODGrid.hypot(dx, dy) / HOVER_STEP))
	var sx: float = dx / n
	var sy: float = dy / n
	var x: float = e.x
	var y: float = e.y
	for i: int in range(n):
		if not hover_solid_at(w.grid, x + sx, y + sy, r):
			x += sx
			y += sy
		elif sx != 0.0 and not hover_solid_at(w.grid, x + sx, y, r):
			x += sx
		elif sy != 0.0 and not hover_solid_at(w.grid, x, y + sy, r):
			y += sy
		else:
			break
	var moved: bool = x != e.x or y != e.y
	e.x = x
	e.y = y
	return moved


## Is `sub` one of this drone's (off-beat) firing instants?
static func is_drone_fire_sub(w: ODSim, e: EnemyState, sub: int) -> bool:
	return EnemyCommon.is_grid_sub(w, e, sub - _offbeat_subs(w))


static func _offbeat_subs(w: ODSim) -> int:
	# Math.round of a non-negative value: floor(x + 0.5) keeps JS rounding of halves.
	return floori(DRONE_OFFBEAT * w.spb + 0.5)


static func _has_shot(w: ODSim, e: EnemyState, tx: float, ty: float) -> bool:
	var dx: float = tx - e.x
	var dy: float = ty - e.y
	# Firing range is an aggro rule: perceived distance.
	if EnemyCommon.perceived_distance(w, ODGrid.hypot(dx, dy)) > e.stats.reach:
		return false
	return not w.grid.segment_blocked(e.x, e.y, tx, ty, true)


static func _fire(w: ODSim, e: EnemyState) -> void:
	var s: int = w.s
	e.attack_sub = -1
	ProjectileSystem.spawn_bolt(w, e, e.facing)
	w.emit(SimEvent.make(0, SimEventType.ENEMY_SHOT, e.x, e.y).with_id(e.id).with_tape(e.target).with_dir(e.facing).with_detail("bolt"))
	EnemyCommon.set_state(e, EnemyStateName.ATTACK, s, s + floori(DRONE_RECOVER_BEATS * w.spb + 0.5))


static func _retarget(w: ODSim, e: EnemyState) -> void:
	var t: SelfActor = EnemyCommon.nearest_target(w, e.x, e.y)
	e.target = t.index if t != null else -1


func on_beat(w: ODSim, e: EnemyState, _beat: int) -> void:
	if e.state == EnemyStateName.TELEGRAPH or e.state == EnemyStateName.ATTACK:
		return
	_retarget(w, e)


func step(w: ODSim, e: EnemyState) -> void:
	var s: int = w.s
	if e.state == EnemyStateName.TELEGRAPH:
		if s >= e.attack_sub:
			_fire(w, e)
		return
	if e.state == EnemyStateName.ATTACK:
		if s < e.state_end:
			return
		EnemyCommon.set_state(e, EnemyStateName.IDLE, s, s)
	var target: SelfActor = EnemyCommon.self_by_index(w, e.target)
	if target == null or not EnemyCommon.targetable(target):
		_retarget(w, e)
		target = EnemyCommon.self_by_index(w, e.target)
	if target == null:
		if e.state != EnemyStateName.IDLE:
			EnemyCommon.set_state(e, EnemyStateName.IDLE, s, s)
		return
	var tx: float = target.pose.x
	var ty: float = target.pose.y
	var dx: float = tx - e.x
	var dy: float = ty - e.y
	var d: float = ODGrid.hypot(dx, dy)
	var tel: int = EnemyCommon.telegraph_subs(w, e)
	var clear: bool = _has_shot(w, e, tx, ty)
	if clear and is_drone_fire_sub(w, e, s + tel):
		e.facing = atan2(dy, dx)
		e.attack_sub = s + tel
		EnemyCommon.set_state(e, EnemyStateName.TELEGRAPH, s, s + tel)
		w.emit(SimEvent.make(0, SimEventType.ENEMY_TELEGRAPH, e.x, e.y).with_id(e.id).with_tape(target.index).with_dir(e.facing).with_detail("bolt"))
		if tel == 0:
			_fire(w, e)
		return
	var step_len: float = e.stats.speed / OD.SUB_HZ
	var moved: bool = false
	var sight: bool = not w.grid.segment_blocked(e.x, e.y, tx, ty, true)
	# Backing off weighs every self inside the comfort distance, not just the target: backing
	# straight away from the nearest would carry it into the next one and it would ping-pong
	# between them. Summed, it settles where the pushes balance. (Spacing is physical: raw distance.)
	var rx: float = 0.0
	var ry: float = 0.0
	var crowd: int = 0
	var keep: float = Tuning.DRONE_KEEP_DISTANCE
	for o: SelfActor in w.selves:
		if not EnemyCommon.targetable(o):
			continue
		var ox: float = e.x - o.pose.x
		var oy: float = e.y - o.pose.y
		var od: float = ODGrid.hypot(ox, oy)
		if not (od > 0.0) or od >= keep - DRONE_KEEP_BAND:
			continue
		rx += (ox / od) * (keep - od)
		ry += (oy / od) * (keep - od)
		crowd += 1
	var push: float = ODGrid.hypot(rx, ry)
	if crowd > 0:
		# Never overshoot the balance point: each unit of travel changes the summed push by about
		# one unit per self pushing.
		if push > 1e-3:
			var back: float = minf(step_len, push / crowd)
			moved = hover_move(w, e, (rx / push) * back, (ry / push) * back)
	elif not sight and d > NO_SIGHT_STOP:
		# Regaining line of sight. From walkable ground with a walking route to its target it follows
		# that route (the prototype's rule); otherwise it plans a flight route over void and barriers.
		if not w.grid.is_solid_at(e.x, e.y, e.stats.radius) and w.paths.has_route(floori(e.x), floori(e.y), floori(tx), floori(ty)):
			moved = EnemyCommon.walk_toward(w, e, tx, ty, NO_SIGHT_STOP)
		else:
			moved = fly_toward(w, e, tx, ty, NO_SIGHT_STOP)
	elif sight and d > keep + DRONE_KEEP_BAND:
		var fwd: float = minf(step_len, d - keep)
		moved = hover_move(w, e, (dx / d) * fwd, (dy / d) * fwd)
	e.facing = atan2(dy, dx)
	if moved and e.state != EnemyStateName.MOVE:
		EnemyCommon.set_state(e, EnemyStateName.MOVE, s, s)
	elif not moved and e.state != EnemyStateName.IDLE:
		EnemyCommon.set_state(e, EnemyStateName.IDLE, s, s)


## 'beatSight' forecast (port addition; see EnemyBehaviour.forecast_attack_subs).
##
## A drone fires on its grid shifted by DRONE_OFFBEAT (the "and" between beats). A telegraphing drone
## fires exactly on e.attack_sub. Otherwise an off-beat instant g is possible only if its telegraph
## can start at g - telegraph: not before `at`, not while it is staggered, sliding or recovering, and
## only if its quarry (the one it holds, else the nearest) can be in range by then - it closes at most
## speed * (g - telegraph - at) / SUB_HZ tiles, and range is perceived distance. Out of sight it needs
## at least a beat to come around, so off-beats whose telegraph would start sooner are left out. Two
## forecast instants are never closer than telegraph + recovery. No possible quarry: nothing.
func forecast_attack_subs(w: ODSim, e: EnemyState, at: int, end_sub: int, out: Array[int]) -> bool:
	var tel: int = EnemyCommon.telegraph_subs(w, e)
	var rec: int = floori(DRONE_RECOVER_BEATS * w.spb + 0.5)
	var shift: int = _offbeat_subs(w)
	var busy: int = maxi(e.stagger_until, at + e.knock_subs)
	var last: float = -INF
	if e.state == EnemyStateName.TELEGRAPH and e.attack_sub >= at:
		if e.attack_sub <= end_sub:
			out.append(e.attack_sub)
		last = e.attack_sub
		busy = maxi(busy, e.attack_sub + rec)
	elif e.state == EnemyStateName.ATTACK:
		busy = maxi(busy, e.state_end)
	var target: SelfActor = EnemyCommon.self_by_index(w, e.target)
	if target == null or not EnemyCommon.targetable(target):
		target = EnemyCommon.nearest_target(w, e.x, e.y)
	if target == null:
		return true
	var dx: float = target.pose.x - e.x
	var dy: float = target.pose.y - e.y
	var raw: float = ODGrid.hypot(dx, dy)
	# Tiles it must close so that the perceived distance is within range (perceived = raw * k).
	var k: float = EnemyCommon.perceived_distance(w, 1.0)
	var gap: float = maxf(0.0, raw - e.stats.reach / k) if k > 0.0 else 0.0
	var sight: bool = not w.grid.segment_blocked(e.x, e.y, target.pose.x, target.pose.y, true)
	var earliest: int = at if sight else at + w.spb
	var g: float = EnemyCommon.next_grid_sub(w, e, at - shift)
	while g + shift <= end_sub and is_finite(g):
		var gi: int = int(g) + shift
		var start: int = gi - tel
		if start >= earliest and start >= busy and gi - last >= tel + rec:
			if gap <= e.stats.speed * float(start - at) / OD.SUB_HZ + 1e-9:
				out.append(gi)
				last = gi
		g = EnemyCommon.next_grid_sub(w, e, g + 1.0)
	return true


func on_hit(w: ODSim, e: EnemyState, strike: EnemyStrike) -> HitResponse:
	if w.grid.is_solid_at(e.x, e.y, e.stats.radius):
		var st: EnemyStrike = strike.copy()
		st.knockback = 0.0
		st.has_knockback = true
		return HitResponse.replace(st)
	return HitResponse.apply()


# ───────────────────────────── flight path-finding ─────────────────────────────

## Fly toward (tx, ty) for one substep under hover collision, stopping `stop` tiles short. Heads
## straight when the hovering body has a clear sweep, otherwise follows a flight route (A* over
## tiles that do not stop flight) re-planned on door changes, every EnemyCommon.ENEMY_REPLAN_SUBS,
## when the goal moved more than a tile, or after the drone did something else for a substep.
## Returns true if it moved.
static func fly_toward(w: ODSim, e: EnemyState, tx: float, ty: float, stop: float) -> bool:
	var ddx: float = tx - e.x
	var ddy: float = ty - e.y
	var dist: float = ODGrid.hypot(ddx, ddy)
	if dist <= stop:
		return false
	var budget: float = minf(e.stats.speed / OD.SUB_HZ, dist - stop)
	if not (budget > 0.0):
		return false
	var r: float = e.stats.radius
	var gx: float = tx
	var gy: float = ty
	var fp: FlightPlanner = _planner(w, e)
	var s: int = w.s
	if hover_sweep_blocked(w.grid, e.x, e.y, tx, ty, r * 0.95):
		var stale: bool = (
			fp.plan_rev != w.grid.revision
			or s - fp.plan_sub >= EnemyCommon.ENEMY_REPLAN_SUBS
			or fp.last_used_sub != s - 1
			or fp.idx >= fp.count
			or _dist(tx, ty, fp.plan_tx, fp.plan_ty) > 1.0
		)
		if stale:
			fp.plan(w.grid, e.x, e.y, tx, ty, r)
			fp.plan_rev = w.grid.revision
			fp.plan_sub = s
			fp.plan_tx = tx
			fp.plan_ty = ty
		fp.last_used_sub = s
		# Skip waypoints already reached.
		while fp.idx < fp.count and _dist(fp.px[fp.idx], fp.py[fp.idx], e.x, e.y) < 1e-6:
			fp.idx += 1
		if fp.idx >= fp.count:
			return false
		gx = fp.px[fp.idx]
		gy = fp.py[fp.idx]
		var dg: float = _dist(gx, gy, e.x, e.y)
		if dg <= budget:
			budget = dg
			fp.idx += 1
	var dx: float = gx - e.x
	var dy: float = gy - e.y
	var d: float = ODGrid.hypot(dx, dy)
	if not (d > 0.0):
		return false
	return hover_move(w, e, (dx / d) * budget, (dy / d) * budget)


static func _dist(ax: float, ay: float, bx: float, by: float) -> float:
	var dx: float = ax - bx
	var dy: float = ay - by
	return ODGrid.hypot(dx, dy)


static func _planner(w: ODSim, e: EnemyState) -> FlightPlanner:
	var v: Variant = e.mem.get(MEM_FLIGHT)
	if v is FlightPlanner:
		return v
	var fp := FlightPlanner.new(w.grid.cols, w.grid.rows)
	e.mem[MEM_FLIGHT] = fp
	return fp


## Does tile (c, r) stop flight? (walls and closed doors: projectile solidity; out of bounds too)
static func blocks_flight(grid: ODGrid, c: int, r: int) -> bool:
	return grid.blocks_shot(c, r)


## Would a hovering circle swept from (x0, y0) to (x1, y1) overlap anything that stops flight?
## Exact segment-to-box distance, chunked like ODGrid.sweep_circle_blocked.
static func hover_sweep_blocked(grid: ODGrid, x0: float, y0: float, x1: float, y1: float, radius: float) -> bool:
	var len: float = _dist(x0, y0, x1, y1)
	var chunks: int = maxi(1, ceili(len / 2.0))
	var r2: float = radius * radius
	for k: int in range(chunks):
		var ax: float = x0 + ((x1 - x0) * k) / chunks
		var ay: float = y0 + ((y1 - y0) * k) / chunks
		var bx: float = x1 if k == chunks - 1 else x0 + ((x1 - x0) * (k + 1)) / chunks
		var by: float = y1 if k == chunks - 1 else y0 + ((y1 - y0) * (k + 1)) / chunks
		var c0: int = floori(minf(ax, bx) - radius)
		var c1: int = floori(maxf(ax, bx) + radius)
		var r0: int = floori(minf(ay, by) - radius)
		var r1: int = floori(maxf(ay, by) + radius)
		for r: int in range(r0, r1 + 1):
			for c: int in range(c0, c1 + 1):
				if not grid.blocks_shot(c, r):
					continue
				if ODGrid.segment_box_dist2(ax, ay, bx, by, c, r, c + 1, r + 1) < r2:
					return true
	return false


## A* over flyable tiles for one drone, with buffers allocated once and reused (a generation stamp
## resets visited state), mirroring path.ts: 8-connected without corner cutting, costs 1 / sqrt(2),
## octile heuristic, ties broken by (f, h, tile index), allowPartial (nearest reachable tile to the
## goal, ties by lower cost), then string-pulled with the hover sweep. The route is kept in packed
## float64 arrays (px, py; `count` waypoints, `idx` the next one).
class FlightPlanner:
	extends RefCounted
	var cols: int = 0
	var rows: int = 0
	var g: PackedFloat64Array = PackedFloat64Array()
	var parent: PackedInt32Array = PackedInt32Array()
	var open_gen: PackedInt32Array = PackedInt32Array()
	var closed_gen: PackedInt32Array = PackedInt32Array()
	var gen: int = 0
	var heap_node: PackedInt32Array = PackedInt32Array()
	var heap_f: PackedFloat64Array = PackedFloat64Array()
	var heap_h: PackedFloat64Array = PackedFloat64Array()
	var heap_size: int = 0
	var tiles: PackedInt32Array = PackedInt32Array()
	## Raw (unsmoothed) waypoints, then the smoothed route.
	var raw_x: PackedFloat64Array = PackedFloat64Array()
	var raw_y: PackedFloat64Array = PackedFloat64Array()
	var px: PackedFloat64Array = PackedFloat64Array()
	var py: PackedFloat64Array = PackedFloat64Array()
	var count: int = 0
	var idx: int = 0
	var plan_rev: int = -1
	var plan_sub: int = -1000000000
	var plan_tx: float = 0.0
	var plan_ty: float = 0.0
	var last_used_sub: int = -1000000000

	func _init(p_cols: int, p_rows: int) -> void:
		cols = p_cols
		rows = p_rows
		var n: int = cols * rows
		g.resize(n)
		parent.resize(n)
		open_gen.resize(n)
		closed_gen.resize(n)
		var cap: int = maxi(16, n * 2)
		heap_node.resize(cap)
		heap_f.resize(cap)
		heap_h.resize(cap)
		raw_x.resize(n + 1)
		raw_y.resize(n + 1)
		px.resize(n + 1)
		py.resize(n + 1)

	## Plan from (sx, sy) to (tx, ty); fills px/py/count and resets idx. An empty route (count 0)
	## means no flyable start tile.
	func plan(grid: ODGrid, sx: float, sy: float, tx: float, ty: float, radius: float) -> void:
		count = 0
		idx = 0
		var c0: int = floori(sx)
		var r0: int = floori(sy)
		if DroneBehaviour.blocks_flight(grid, c0, r0):
			return
		var c1: int = floori(tx)
		var r1: int = floori(ty)
		var goal_ok: bool = not DroneBehaviour.blocks_flight(grid, c1, r1)
		var start: int = r0 * cols + c0
		var goal: int = r1 * cols + c1 if goal_ok else -1
		var found: bool = false
		var end_node: int = start
		if start == goal:
			found = true
		else:
			gen += 1
			heap_size = 0
			g[start] = 0.0
			parent[start] = -1
			open_gen[start] = gen
			var h0: float = DroneBehaviour._octile(c0, r0, c1, r1)
			_push(start, h0, h0)
			var best: int = start
			var best_d: float = DroneBehaviour._euclid2(c0, r0, c1, r1)
			var best_g: float = 0.0
			while heap_size > 0:
				var node: int = _pop()
				if closed_gen[node] == gen:
					continue
				closed_gen[node] = gen
				if node == goal:
					found = true
					break
				var nc0: int = node % cols
				@warning_ignore("integer_division")
				var nr0: int = node / cols
				var gn: float = g[node]
				var dd: float = DroneBehaviour._euclid2(nc0, nr0, c1, r1)
				if dd < best_d or (dd == best_d and gn < best_g):
					best_d = dd
					best_g = gn
					best = node
				for k: int in range(8):
					var nc: int = nc0 + DroneBehaviour._NDC[k]
					var nr: int = nr0 + DroneBehaviour._NDR[k]
					if DroneBehaviour.blocks_flight(grid, nc, nr):
						continue
					var stp: float = 1.0
					if k >= 4:
						# No corner cutting: both orthogonal neighbours of a diagonal step must be open.
						if DroneBehaviour.blocks_flight(grid, nc, nr0) or DroneBehaviour.blocks_flight(grid, nc0, nr):
							continue
						stp = DroneBehaviour._SQRT2
					var ni: int = nr * cols + nc
					if closed_gen[ni] == gen:
						continue
					var ng: float = gn + stp
					if open_gen[ni] == gen and ng >= g[ni]:
						continue
					open_gen[ni] = gen
					g[ni] = ng
					parent[ni] = node
					var h: float = DroneBehaviour._octile(nc, nr, c1, r1)
					_push(ni, ng + h, h)
			end_node = goal if found else best
		# Tile chain end -> start, then waypoints start -> end excluding the start tile.
		tiles.clear()
		if start == end_node:
			tiles.append(start)
		else:
			var i: int = end_node
			while i != -1:
				tiles.append(i)
				i = parent[i]
		var nraw: int = 0
		for j: int in range(tiles.size() - 2, -1, -1):
			var t: int = tiles[j]
			var tc: int = t % cols
			@warning_ignore("integer_division")
			var tr: int = t / cols
			raw_x[nraw] = tc + 0.5
			raw_y[nraw] = tr + 0.5
			nraw += 1
		if found:
			# Finish on the exact goal point, replacing the goal tile's centre.
			if nraw > 0:
				raw_x[nraw - 1] = tx
				raw_y[nraw - 1] = ty
			else:
				raw_x[0] = tx
				raw_y[0] = ty
				nraw = 1
		elif nraw == 0 and (c0 + 0.5 != sx or r0 + 0.5 != sy):
			# Partial route that never left the start tile: head for its centre (stable waiting spot).
			raw_x[0] = c0 + 0.5
			raw_y[0] = r0 + 0.5
			nraw = 1
		# String pulling by the hover sweep, as Pathfinder.smooth.
		if nraw <= 1:
			for j: int in range(nraw):
				px[j] = raw_x[j]
				py[j] = raw_y[j]
			count = nraw
			return
		var ax: float = sx
		var ay: float = sy
		var a: int = 0
		while a < nraw:
			var b: int = a
			while b + 1 < nraw and not DroneBehaviour.hover_sweep_blocked(grid, ax, ay, raw_x[b + 1], raw_y[b + 1], radius):
				b += 1
			px[count] = raw_x[b]
			py[count] = raw_y[b]
			count += 1
			ax = raw_x[b]
			ay = raw_y[b]
			a = b + 1

	func _less(a: int, b: int) -> bool:
		var fa: float = heap_f[a]
		var fb: float = heap_f[b]
		if fa != fb:
			return fa < fb
		var ha: float = heap_h[a]
		var hb: float = heap_h[b]
		if ha != hb:
			return ha < hb
		return heap_node[a] < heap_node[b]

	func _swap(a: int, b: int) -> void:
		var n: int = heap_node[a]
		heap_node[a] = heap_node[b]
		heap_node[b] = n
		var f: float = heap_f[a]
		heap_f[a] = heap_f[b]
		heap_f[b] = f
		var h: float = heap_h[a]
		heap_h[a] = heap_h[b]
		heap_h[b] = h

	func _push(node: int, f: float, h: float) -> void:
		if heap_size == heap_node.size():
			var cap: int = heap_node.size() * 2
			heap_node.resize(cap)
			heap_f.resize(cap)
			heap_h.resize(cap)
		var i: int = heap_size
		heap_size += 1
		heap_node[i] = node
		heap_f[i] = f
		heap_h[i] = h
		while i > 0:
			var p: int = (i - 1) >> 1
			if not _less(i, p):
				break
			_swap(i, p)
			i = p

	func _pop() -> int:
		var top: int = heap_node[0]
		heap_size -= 1
		var last: int = heap_size
		if last > 0:
			heap_node[0] = heap_node[last]
			heap_f[0] = heap_f[last]
			heap_h[0] = heap_h[last]
			var i: int = 0
			while true:
				var l: int = 2 * i + 1
				if l >= last:
					break
				var r: int = l + 1
				var m: int = r if r < last and _less(r, l) else l
				if not _less(m, i):
					break
				_swap(i, m)
				i = m
		return top


static func _octile(c0: int, r0: int, c1: int, r1: int) -> float:
	var dx: int = absi(c1 - c0)
	var dy: int = absi(r1 - r0)
	return dx - dy + _SQRT2 * dy if dx > dy else dy - dx + _SQRT2 * dx


static func _euclid2(c0: int, r0: int, c1: int, r1: int) -> float:
	var dx: int = c1 - c0
	var dy: int = r1 - r0
	return float(dx * dx + dy * dy)
