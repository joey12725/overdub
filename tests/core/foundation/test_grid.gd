extends ODTest
## Port of prototype/tests/core/foundation/grid.test.ts: parsing, solidity, move_circle, sweeps and rays.

const R := 0.3
const SKIN := Tuning.COLLISION_SKIN


func _g(map: Array[String]) -> ODGrid:
	return ODGrid.parse(map)


## The prototype's 32-bit LCG: seed = (seed * 1664525 + 1013904223) >>> 0, returning seed / 2^32.
## GDScript ints are 64-bit, so mask to 32 bits after the multiply-add (exact: < 2^63).
class Lcg:
	var seed: int = 0

	func _init(s: int) -> void:
		seed = s

	func next() -> float:
		seed = (seed * 1664525 + 1013904223) & 0xffffffff
		return seed / 4294967296.0

# ── parsing ──


func test_reads_every_documented_tile_character_and_pads_short_rows_with_void() -> void:
	var g := _g(["#.= :,~", "#."])
	assert_eq(g.cols, 7)
	assert_eq(g.rows, 2)
	assert_eq(g.tile_at(0, 0), ODGrid.TILE_WALL)
	assert_eq(g.tile_at(1, 0), ODGrid.TILE_FLOOR)
	assert_eq(g.tile_at(2, 0), ODGrid.TILE_LOW)
	assert_eq(g.tile_at(3, 0), ODGrid.TILE_VOID)
	assert_eq(g.tile_at(4, 0), ODGrid.TILE_GRATE)
	assert_eq(g.tile_at(5, 1), ODGrid.TILE_VOID)
	assert_eq(g.tile_at(-1, 0), ODGrid.TILE_WALL)
	assert_eq(g.tile_at(5, 0), ODGrid.TILE_OVERGROWN)
	assert_eq(g.tile_at(6, 0), ODGrid.TILE_RUNE)
	assert_eq(g.to_string(), "#.= :,~\n#.     ")
	assert_true(ODGrid.is_floor_kind(ODGrid.TILE_RUNE))
	assert_false(ODGrid.is_floor_kind(ODGrid.TILE_LOW))


func test_rejects_unknown_characters_with_their_position() -> void:
	var errors: Array[String] = []
	var pe := ODGrid.MapParseError.new()
	assert_eq(ODGrid.parse(["##", "#D"], errors, pe), null)
	assert_true(pe.failed)
	assert_eq(pe.c, 1)
	assert_eq(pe.r, 1)
	assert_eq(errors, ["Unknown map character \"D\" at column 1, row 1"])
	var empty: Array[String] = []
	var pe2 := ODGrid.MapParseError.new()
	assert_eq(ODGrid.parse(empty, errors, pe2), null)
	assert_true(pe2.failed)
	assert_eq(errors[1], "Map is empty")
	var bad: Array[String] = []
	assert_eq(ODGrid.create(2, 2, PackedByteArray([1, 1, 1]), bad), null)
	assert_eq(bad, ["Grid: bad dimensions 2x2 for 3 tiles"])
	assert_true(ODGrid.from_level(TestLevels.make_level()) != null)

# ── solidity ──


func test_separates_movement_solidity_from_projectile_solidity() -> void:
	var g := _g(["#####", "#.= #", "#####"])
	assert_true(g.is_walkable(1, 1))
	assert_false(g.is_walkable(2, 1), "low barrier blocks movement")
	assert_false(g.blocks_shot(2, 1), "...not projectiles")
	assert_false(g.is_walkable(3, 1), "void is impassable")
	assert_false(g.blocks_shot(3, 1), "...but does not block shots")
	assert_true(g.blocks_shot(0, 0))
	assert_false(g.blocks_move(2, 1, true), "phaseDodge ignores low barriers")
	assert_true(g.blocks_move(3, 1, true), "but never void")
	assert_true(g.blocks_move(99, 99))
	assert_true(g.blocks_shot(-1, 1))


func test_dynamic_overlay_blocks_both_and_bumps_the_revision_only_on_change() -> void:
	var d := _g(["....."])
	var r0 := d.revision
	d.set_dynamic_solid(2, 0, true)
	assert_eq(d.revision, r0 + 1)
	d.set_dynamic_solid(2, 0, true)
	assert_eq(d.revision, r0 + 1)
	assert_false(d.is_walkable(2, 0))
	assert_true(d.blocks_shot(2, 0))
	assert_true(d.is_static_walkable(2, 0))
	assert_true(d.is_dynamic_solid(2, 0))
	assert_false(d.line_of_sight(Vector2(0.5, 0.5), Vector2(4.5, 0.5)))
	d.set_dynamic_solid(2, 0, false)
	assert_true(d.line_of_sight(Vector2(0.5, 0.5), Vector2(4.5, 0.5)))
	assert_true(d.line_of_sight_xy(0.5, 0.5, 4.5, 0.5))
	d.set_dynamic_solid(9, 9, true) # out of bounds: ignored
	assert_eq(d.revision, r0 + 2)
	d.set_dynamic_solid(1, 0, true)
	d.clear_dynamic()
	assert_true(d.is_walkable(1, 0))
	assert_eq(d.revision, r0 + 4)
	d.clear_dynamic()
	assert_eq(d.revision, r0 + 4, "clearing an empty overlay is not a change")


func test_is_solid_at_tests_circle_overlap_touching_is_not_overlap() -> void:
	var g := _g(["#####", "#.= #", "#####"])
	assert_false(g.is_solid_at(1.5, 1.5, R))
	assert_true(g.is_solid_at(1.25, 1.5, R), "into the wall at x = 1")
	assert_false(g.is_solid_at(1.3, 1.5, R), "exactly touching")
	assert_true(g.is_solid_at(1.5, 1.5, 0.6))
	assert_false(g.is_solid_at(1.5, 1.5, 0))
	assert_true(g.is_solid_at(1.75, 1.5, R), "low barrier at x = 2")
	assert_false(g.is_solid_at(1.75, 1.5, R, ODGrid.MoveOpts.make(true)))

# ── move_circle ──

const ROOM: Array[String] = ["##########", "#........#", "#........#", "#........#", "#........#", "##########"]


func test_move_circle_is_exact_when_nothing_blocks() -> void:
	var r := _g(ROOM).move_circle(3, 3, 0.37, -0.11, R)
	assert_eq([r.x, r.y, r.blocked], [3 + 0.37, 3 - 0.11, false])
	assert_eq(r.x, 3.37)
	assert_eq(r.y, 2.89)


func test_stops_at_a_wall_with_the_collision_skin() -> void:
	var r := _g(ROOM).move_circle(8, 3, 2, 0, R)
	assert_true(r.blocked)
	assert_near(r.x, 9 - R - SKIN, 5e-10)
	assert_eq(r.y, 3)


func test_slides_along_a_wall_made_of_several_tiles_without_seam_bumps() -> void:
	# Hug the top wall (y = 1) and push diagonally into it across many tile seams.
	var room := _g(ROOM)
	var x := 1.5
	var y := 1 + R + SKIN
	var out := ODGrid.MoveResult.new()
	for i in 60:
		var r := room.move_circle(x, y, 0.1, -0.05, R, null, out)
		if not assert_near(r.y, 1 + R + SKIN, 5e-10, "step %d y" % i):
			return
		if not assert_near(r.x, x + 0.1, 5e-10, "step %d x" % i):
			return
		x = r.x
		y = r.y
		if x > 8:
			break


func test_slides_out_of_an_inside_corner_without_sticking_or_penetrating() -> void:
	var room := _g(ROOM)
	var x := 7.0
	var y := 3.0
	for i in 40:
		var r := room.move_circle(x, y, 0.2, -0.2, R)
		x = r.x
		y = r.y
		if not assert_false(room.is_solid_at(x, y, R), "step %d" % i):
			return
	assert_near(x, 9 - R - SKIN, 5e-7)
	assert_near(y, 1 + R + SKIN, 5e-7)


func test_cannot_tunnel_through_a_1_tile_wall_at_any_speed() -> void:
	var g := _g(["#######", "#..#..#", "#..#..#", "#######"])
	for dist: float in [1.25, 2.0, 3.5, 10.0, 100.0]:
		var r := g.move_circle(1.5, 1.5, dist, 0, R)
		assert_true(r.x < 3, "dist %s" % dist)
		assert_near(r.x, 3 - R - SKIN, 5e-10)
		var back := g.move_circle(5.5, 2.5, -dist, 0.3, R)
		assert_true(back.x > 4, "back dist %s" % dist)


func test_never_leaves_the_walkable_region_under_random_fast_motion() -> void:
	var g := _g([
		"############",
		"#....#.....#",
		"#.##.#.##..#",
		"#.#..=..#..#",
		"#.#.###.#..#",
		"#...# ..#..#",
		"############",
	])
	var rnd := Lcg.new(7)
	var x := 1.5
	var y := 1.5
	var out := ODGrid.MoveResult.new()
	var bad := 0
	for i in 4000:
		var a := rnd.next() * PI * 2
		var d := rnd.next() * 1.5
		var r := g.move_circle(x, y, cos(a) * d, sin(a) * d, R, null, out)
		# Never overlapping a solid and never on a non-walkable tile.
		if g.is_solid_at(r.x, r.y, R) or not g.is_walkable(floori(r.x), floori(r.y)):
			bad += 1
		# Moves never cross a solid tile (no tunnelling): the straight segment stays clear for a point.
		if g.segment_blocked(x, y, r.x, r.y, false) and ODGrid.hypot(r.x - x, r.y - y) > 1.2:
			bad += 1
		x = r.x
		y = r.y
	assert_eq(bad, 0)


func test_pushes_a_circle_that_starts_overlapping_back_into_open_space() -> void:
	# A door closed on it.
	var g := _g(["#####", "#...#", "#####"])
	g.set_dynamic_solid(2, 1, true)
	var r := g.move_circle(2.4, 1.5, 0, 0, R)
	assert_true(r.blocked)
	assert_false(g.is_solid_at(r.x, r.y, R))


func test_phase_dodge_crosses_low_barriers_only() -> void:
	var g := _g(["#####", "#.=.#", "#####"])
	assert_true(g.move_circle(1.5, 1.5, 2, 0, R).x < 2)
	assert_near(g.move_circle(1.5, 1.5, 2, 0, R, ODGrid.MoveOpts.make(true)).x, 3.5, 5e-10)

# ── sweeps and rays ──

const PILLAR: Array[String] = ["#######", "#.....#", "#..#..#", "#.....#", "#######"]


func test_sweep_circle_blocked_is_exact_against_tile_boxes() -> void:
	var g := _g(PILLAR)
	assert_false(g.sweep_circle_blocked(1.5, 1.5, 5.5, 1.5, R))
	assert_true(g.sweep_circle_blocked(1.5, 2.5, 5.5, 2.5, R))
	# Passing the pillar corner with clearance just above/below the radius.
	assert_false(g.sweep_circle_blocked(1.5, 1.69, 5.5, 1.69, R))
	assert_true(g.sweep_circle_blocked(1.5, 1.71, 5.5, 1.71, R))
	assert_true(g.sweep_circle_blocked(1.5, 1.5, 5.5, 3.5, 0))


func test_segment_blocked_walks_every_tile_on_the_segment() -> void:
	var g := _g(PILLAR)
	assert_false(g.segment_blocked(1.5, 1.5, 5.5, 1.5, true))
	assert_true(g.segment_blocked(1.5, 2.5, 5.5, 2.5, true))
	assert_true(g.segment_blocked(2.9, 1.5, 4.1, 3.5, true))
	assert_true(g.segment_blocked(3.5, 2.5, 3.5, 2.5, true), "starts inside")


func test_exact_diagonal_corner_crossings_block_only_when_both_side_tiles_block() -> void:
	var d := _g(["....", ".#..", "..#.", "...."])
	# Through the shared corner (2, 2) of the two diagonal walls: sealed.
	assert_true(d.segment_blocked(1.5, 2.5, 2.5, 1.5, true))
	var e := _g(["....", ".#..", "....", "...."])
	# Grazing the corner of a single wall tile: open.
	assert_false(e.segment_blocked(1.5, 2.5, 2.5, 1.5, true))


func test_void_and_low_barriers_do_not_block_sight_walls_do() -> void:
	var v := _g(["#####", "#. .#", "#.=.#", "#####"])
	assert_true(v.line_of_sight(Vector2(1.5, 1.5), Vector2(3.5, 1.5)))
	assert_true(v.line_of_sight(Vector2(1.5, 2.5), Vector2(3.5, 2.5)))
	assert_true(v.segment_blocked(1.5, 1.5, 3.5, 1.5, false), "but not walkable")
	assert_false(v.line_of_sight(Vector2(1.5, 1.5), Vector2(5.5, 1.5)), "out of bounds past the wall")


func test_raycast_reports_distance_tile_and_normal() -> void:
	var g := _g(PILLAR)
	var hit := g.raycast(1.5, 2.5, 1, 0, 10, true)
	assert_true(hit.hit)
	assert_eq(hit.c, 3)
	assert_eq(hit.r, 2)
	assert_near(hit.dist, 1.5, 5e-13)
	assert_near(hit.x, 3, 5e-13)
	assert_eq([hit.nx, hit.ny], [-1, 0])
	var up := g.raycast(4.5, 3.5, 0, -2, 10, true)
	assert_near(up.dist, 2.5, 5e-13)
	assert_eq([up.c, up.r, up.nx, up.ny], [4, 0, 0, 1])
	var miss := g.raycast(1.5, 1.5, 1, 0, 2, true)
	assert_false(miss.hit)
	assert_eq(miss.dist, 2)
	assert_near(miss.x, 3.5, 5e-13)
	assert_eq([miss.c, miss.r], [-1, -1])
	var diag := g.raycast(1.5, 1.5, 1, 1, 10, true)
	assert_true(diag.hit)
	assert_near(diag.dist, sqrt(2.0) * 2.5, 5e-10)
	var inside := g.raycast(3.5, 2.5, 0, 0, 10, true)
	assert_eq([inside.hit, inside.dist, inside.c, inside.r], [true, 0, 3, 2])


func test_nearest_walkable_finds_the_closest_open_tile_deterministically() -> void:
	var g := _g(PILLAR)
	var n := g.nearest_walkable(3, 2)
	assert_eq([n % g.cols, n / g.cols], [3, 1])
	assert_eq(g.nearest_walkable(2, 2), g.index(2, 2))
	var solid := _g(["###", "###", "###"])
	assert_eq(solid.nearest_walkable(1, 1, 3), -1)


func test_hypot_matches_v8_math_hypot() -> void:
	# Values printed by Node 24 (V8): Math.hypot(0.1, 0.2) = 0.223606797749979; Math.hypot(1e200, 1e200)
	# = 1.414213562373095e+200 = sqrt(2) * 1e200 (written as an expression: GDScript's float-literal
	# parser is not correctly rounded for that 16-digit literal).
	assert_eq(ODGrid.hypot(3, 4), 5)
	assert_eq(ODGrid.hypot(-3, 0), 3)
	assert_eq(ODGrid.hypot(0, 0), 0)
	assert_eq(ODGrid.hypot(0.1, 0.2), 0.223606797749979)
	assert_eq(ODGrid.hypot(1e200, 1e200), sqrt(2.0) * 1e200)
	assert_eq(ODGrid.hypot(INF, NAN), INF)
	assert_true(is_nan(ODGrid.hypot(1, NAN)))
	assert_eq(ODGrid.segment_box_dist2(0, 0, 0, 3, 1, 1, 2, 2), 1)
	assert_eq(ODGrid.segment_box_dist2(0, 0, 3, 3, 1, 1, 2, 2), 0)
