extends ODTest
## Port of prototype/tests/core/foundation/path.test.ts: A*, re-planning, partial paths, smoothing and a
## performance bound.

const MAZE: Array[String] = [
	"###########",
	"#.....#...#",
	"#.###.#.#.#",
	"#.#...#.#.#",
	"#.#.###.#.#",
	"#.#.....#.#",
	"#.#######.#",
	"#.........#",
	"###########",
]


func _g(map: Array[String]) -> ODGrid:
	return ODGrid.parse(map)


func _no_smooth() -> Pathfinder.PathOpts:
	return Pathfinder.PathOpts.make(false, false)


func _tiles(pf: Pathfinder, path: Array[int]) -> Array:
	var cols := pf.grid.cols
	var out: Array = []
	for i: int in path:
		out.append([i % cols, i / cols])
	return out


## Check a tile path is legal: consecutive tiles adjacent, all walkable, no corner cutting.
func _expect_legal(grid: ODGrid, path: Array) -> void:
	for cr: Array in path:
		assert_true(grid.is_walkable(cr[0], cr[1]), "walkable %s" % [cr])
	for i in range(1, path.size()):
		var c0: int = path[i - 1][0]
		var r0: int = path[i - 1][1]
		var c1: int = path[i][0]
		var r1: int = path[i][1]
		assert_eq(maxi(absi(c1 - c0), absi(r1 - r0)), 1)
		if c1 != c0 and r1 != r0:
			assert_true(grid.is_walkable(c1, r0))
			assert_true(grid.is_walkable(c0, r1))


## Reference Dijkstra over the same graph for optimal cost comparison.
func _dijkstra_cost(grid: ODGrid, c0: int, r0: int, c1: int, r1: int) -> float:
	var n := grid.cols * grid.rows
	var dist := PackedFloat64Array()
	dist.resize(n)
	dist.fill(INF)
	var done := PackedByteArray()
	done.resize(n)
	done.fill(0)
	dist[r0 * grid.cols + c0] = 0.0
	while true:
		var u := -1
		for i in n:
			if done[i] == 0 and dist[i] < INF and (u < 0 or dist[i] < dist[u]):
				u = i
		if u < 0:
			return INF
		if u == r1 * grid.cols + c1:
			return dist[u]
		done[u] = 1
		var uc := u % grid.cols
		var ur := u / grid.cols
		for dr in range(-1, 2):
			for dc in range(-1, 2):
				if dc == 0 and dr == 0:
					continue
				var vc := uc + dc
				var vr := ur + dr
				if not grid.is_walkable(vc, vr):
					continue
				if dc != 0 and dr != 0 and (not grid.is_walkable(vc, ur) or not grid.is_walkable(uc, vr)):
					continue
				var v := vr * grid.cols + vc
				var w := Pathfinder.SQRT2 if dc != 0 and dr != 0 else 1.0
				if dist[u] + w < dist[v]:
					dist[v] = dist[u] + w
	return INF

# ── A* ──


func test_finds_the_optimal_legal_path_through_a_maze() -> void:
	var g := _g(MAZE)
	var pf := Pathfinder.new(g)
	var p := pf.find_tile_path(1, 1, 3, 3)
	if not assert_false(p.is_empty()):
		return
	var t := _tiles(pf, p)
	assert_eq(t[0], [1, 1])
	assert_eq(t[t.size() - 1], [3, 3])
	_expect_legal(g, t)
	var res := pf.find_path(1.5, 1.5, 3.5, 3.5, _no_smooth())
	assert_true(res.complete)
	assert_near(res.cost, _dijkstra_cost(g, 1, 1, 3, 3), 5e-10)
	assert_true(pf.last_expanded > 0)


func test_matches_dijkstra_on_every_reachable_pair_of_a_maze() -> void:
	var g := _g(MAZE)
	var pf := Pathfinder.new(g)
	var open: Array[Vector2i] = []
	for r in g.rows:
		for c in g.cols:
			if g.is_walkable(c, r):
				open.append(Vector2i(c, r))
	var checked := 0
	var i := 0
	while i < open.size():
		var j := 1
		while j < open.size():
			var a := open[i]
			var b := open[j]
			var res := pf.find_path(a.x + 0.5, a.y + 0.5, b.x + 0.5, b.y + 0.5, _no_smooth())
			var ref := _dijkstra_cost(g, a.x, a.y, b.x, b.y)
			if is_inf(ref):
				assert_eq(res, null)
			elif assert_true(res != null, "%s -> %s" % [a, b]):
				assert_near(res.cost, ref, 5e-10, "%s -> %s" % [a, b])
			checked += 1
			j += 5
		i += 3
	assert_true(checked > 50)


func test_never_cuts_corners() -> void:
	var g := _g(["#####", "#..##", "##..#", "#####"])
	var pf := Pathfinder.new(g)
	# (2,1) → (2,2) is direct; (1,1) → (3,2) must not squeeze diagonally between walls.
	var t := _tiles(pf, pf.find_tile_path(1, 1, 3, 2))
	_expect_legal(g, t)
	assert_eq(t, [[1, 1], [2, 1], [2, 2], [3, 2]])
	var sealed := _g(["####", "#.##", "##.#", "####"])
	assert_true(Pathfinder.new(sealed).find_tile_path(1, 1, 2, 2).is_empty())


func test_desync_04_re_plans_when_a_door_closes_and_when_it_opens_again() -> void:
	var g := _g([
		"###########",
		"#....#....#",
		"#.........#",
		"#....#....#",
		"#.####....#",
		"#.........#",
		"###########",
	])
	var pf := Pathfinder.new(g)
	var direct := pf.find_path(2.5, 2.5, 8.5, 2.5)
	assert_near(direct.cost, 6, 5e-10)
	# Close the door at (5, 2): the only route is the long detour through the bottom corridor.
	g.set_dynamic_solid(5, 2, true)
	var detour := pf.find_path(2.5, 2.5, 8.5, 2.5)
	assert_true(detour.cost > 9)
	var through_door := false
	for cr: Array in _tiles(pf, pf.find_tile_path(2, 2, 8, 2)):
		if cr[0] == 5 and cr[1] == 2:
			through_door = true
	assert_false(through_door)
	# Seal the detour too: no route.
	g.set_dynamic_solid(1, 4, true)
	assert_false(pf.has_route(2, 2, 8, 2))
	assert_eq(pf.find_path(2.5, 2.5, 8.5, 2.5), null)
	# Reopen the door: direct again.
	g.set_dynamic_solid(5, 2, false)
	assert_true(pf.has_route(2, 2, 8, 2))
	assert_true(pf.has_route_between(Vector2(2.5, 2.5), Vector2(8.5, 2.5)))
	assert_near(pf.find_path(2.5, 2.5, 8.5, 2.5).cost, 6, 5e-10)


func test_partial_paths_head_for_the_reachable_tile_nearest_an_unreachable_goal() -> void:
	var g := _g(["#######", "#..#..#", "#..#..#", "#######"])
	var pf := Pathfinder.new(g)
	assert_eq(pf.find_path(1.5, 1.5, 4.5, 1.5), null)
	var part := pf.find_path(1.5, 1.5, 4.5, 1.5, Pathfinder.PathOpts.make(true))
	assert_false(part.complete)
	assert_eq(part.points[part.points.size() - 1], Vector2(2.5, 1.5))
	# Goal inside a wall (a projection that desynced into it).
	var in_wall := pf.find_path(1.5, 2.5, 3.4, 2.5, Pathfinder.PathOpts.make(true))
	assert_eq(in_wall.points[in_wall.points.size() - 1], Vector2(2.5, 2.5))


func test_starts_from_the_nearest_walkable_tile_when_the_start_is_inside_a_solid() -> void:
	var g := _g(["#####", "#...#", "#####"])
	g.set_dynamic_solid(1, 1, true)
	var res := Pathfinder.new(g).find_path(1.5, 1.5, 3.5, 1.5)
	if not assert_true(res != null):
		return
	assert_eq(res.points[res.points.size() - 1], Vector2(3.5, 1.5))


func test_is_deterministic_identical_inputs_give_identical_paths() -> void:
	var g := _g(["############", "#..........#", "#..........#", "#..........#", "############"])
	var a := Pathfinder.new(g).find_tile_path(1, 1, 10, 3)
	var b := Pathfinder.new(g).find_tile_path(1, 1, 10, 3)
	var pf := Pathfinder.new(g)
	pf.find_tile_path(3, 3, 1, 1)
	assert_eq(pf.find_tile_path(1, 1, 10, 3), a)
	assert_eq(b, a)
	assert_true(a.size() >= 10)

# ── smoothing ──


func test_string_pulls_open_room_paths_to_a_straight_line() -> void:
	var g := _g(["##########", "#........#", "#........#", "#........#", "#........#", "##########"])
	var res := Pathfinder.new(g).find_path(1.5, 1.5, 8.5, 3.7)
	assert_eq(res.points, [Vector2(8.5, 3.7)])


func test_keeps_corners_around_obstacles_and_every_leg_is_walkable_with_clearance() -> void:
	var g := _g(MAZE)
	var pf := Pathfinder.new(g)
	var raw := pf.find_path(1.5, 1.5, 3.5, 3.5, _no_smooth())
	var sm := pf.find_path(1.5, 1.5, 3.5, 3.5, Pathfinder.PathOpts.make().with_radius(0.2))
	assert_true(sm.points.size() < raw.points.size())
	var x := 1.5
	var y := 1.5
	for p: Vector2 in sm.points:
		assert_false(g.sweep_circle_blocked(x, y, p.x, p.y, 0.2))
		x = p.x
		y = p.y
	assert_true(Pathfinder.path_length(1.5, 1.5, sm.points) <= Pathfinder.path_length(1.5, 1.5, raw.points) + 1e-9)

# ── performance ──


func test_re_plans_on_a_40x40_maze_many_times_per_second() -> void:
	# Deterministic maze: walls on a lattice with gaps from an LCG (see tools/bench_foundation.gd).
	var g := ODGrid.parse(maze_40())
	var pf := Pathfinder.new(g)
	var open: Array[Vector2i] = []
	for r in 40:
		for c in 40:
			if g.is_walkable(c, r):
				open.append(Vector2i(c, r))
	var t0 := Time.get_ticks_usec()
	var found := 0
	var n := 2000
	var opts := Pathfinder.PathOpts.make(true)
	for i in n:
		var a := open[(i * 7919) % open.size()]
		var b := open[(i * 104729 + 13) % open.size()]
		if i % 50 == 0:
			g.set_dynamic_solid(b.x, (b.y + 1) % 40, i % 100 == 0)
		if pf.find_path(a.x + 0.5, a.y + 0.5, b.x + 0.5, b.y + 0.5, opts) != null:
			found += 1
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	assert_eq(found, n)
	# The prototype's bound is 2 ms per plan in JS; GDScript is slower, so allow 4 ms (typical runs are
	# well below; tools/bench_foundation.gd reports the number).
	assert_true(ms / n < 4.0, "%.3f ms per plan" % (ms / n))


## The prototype's performance-test maze (shared with tools/bench_foundation.gd).
static func maze_40() -> Array[String]:
	var seed := 99
	var rows: Array[String] = []
	for r in 40:
		var s := ""
		for c in 40:
			var border := r == 0 or c == 0 or r == 39 or c == 39
			# `||` short-circuits, so the LCG only advances when the earlier tests are false.
			var wall := border
			if not wall and r % 4 == 0:
				seed = (seed * 1664525 + 1013904223) & 0xffffffff
				wall = seed / 4294967296.0 < 0.8
			if not wall and c % 6 == 0:
				seed = (seed * 1664525 + 1013904223) & 0xffffffff
				wall = seed / 4294967296.0 < 0.5
			s += "#" if wall else "."
		rows.append(s)
	return rows
