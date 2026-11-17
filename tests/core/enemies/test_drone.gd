extends ODTest
## Drone (AI-01, AI-06, AI-07, HEALTH-02): hovers over void and low barriers, keeps its distance from
## the nearest self, fires bolts on the off-beat, takes two hits.
## Port of prototype/tests/core/enemies/drone.test.ts, plus the port's flight path-finding.

const K = preload("res://tests/core/enemies/test_enemy_kit.gd")
const SPB: int = 120
const BAND: float = DroneBehaviour.DRONE_KEEP_BAND
const KEEP: float = Tuning.DRONE_KEEP_DISTANCE


## A grid far beyond the horizon: the drone never fires, so spacing can be watched on its own.
func _drone(x: float, y: float, o: Dictionary = {}) -> EnemyDef:
	return K.enemy("d1", EnemyType.DRONE, x, y, o)


const HOLD_FIRE: Dictionary = {"beat": [1000, 999]}


func test_AI01_backs_off_from_a_self_that_is_too_close() -> void:
	var lvl := K.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(2, 5), "entities": [_drone(4, 5, HOLD_FIRE)]})
	var res := K.resolve(lvl, [K.still(0, 2, 5)])
	var end := K.last_frame(res).enemies[0]
	assert_true(K.dist(end, 2, 5) >= KEEP - BAND - 1e-6, "out of the band's near edge")
	assert_true(K.dist(end, 2, 5) <= KEEP + BAND, "inside the band")


func test_AI01_closes_in_on_a_self_that_is_too_far_and_then_holds_position() -> void:
	var lvl := K.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(1.5, 5), "entities": [_drone(10.5, 5, HOLD_FIRE)]})
	var res := K.resolve(lvl, [K.still(0, 1.5, 5)])
	var mid := K.frame_at(res, 8 * SPB).enemies[0]
	var end := K.last_frame(res).enemies[0]
	assert_true(K.dist(end, 1.5, 5) <= KEEP + BAND + 1e-6)
	assert_true(K.dist(end, 1.5, 5) >= KEEP - BAND)
	assert_eq(end.x, mid.x, "holds position")


func test_AI01_targets_the_nearest_self_and_between_two_settles_where_their_pushes_balance() -> void:
	var lvl := K.make_level({"speeds": [1.0], "bars": 2, "start": Vector2(1.5, 5), "entities": [_drone(6, 5, HOLD_FIRE)]})
	var near := K.path_tape(1, 1.0, 240, [[0, 8, 5]])
	var res := K.resolve(lvl, [K.still(0, 1.5, 5, 240), near])
	assert_eq(K.frame_at(res, SPB / 2).enemies[0].target, 1)
	# Pushed by both (A 4.5 west, B 2 east): the balance point is x = 4.75, and it stays there.
	var settled := K.frame_at(res, 4 * SPB).enemies[0]
	assert_near(settled.x, 4.75, 5e-7)
	assert_eq(K.last_frame(res).enemies[0].x, settled.x)


# A void trench (columns 6..8) and a low barrier column (4) between the self and the drone.
const TRENCH: Array[String] = [
	"##############",
	"#...=.   ....#",
	"#...=.   ....#",
	"#...=.   ....#",
	"#...=.   ....#",
	"#...=.   ....#",
	"#...=.   ....#",
	"##############",
]


func _trench(type: StringName) -> LevelDef:
	return K.make_level({"map": TRENCH, "speeds": [1.0], "bars": 4, "start": Vector2(1.5, 3.5), "entities": [K.enemy("d1", type, 12.5, 3.5, HOLD_FIRE)]})


func test_hovering_flies_over_void_and_low_barriers_that_stop_walkers() -> void:
	var self_tape := K.still(0, 1.5, 3.5)
	var drone := K.last_frame(K.resolve(_trench(EnemyType.DRONE), [self_tape])).enemies[0]
	# 5 tiles from the self is x = 6.5: over the trench.
	assert_true(drone.x < 9.0)
	assert_eq(TRENCH[floori(drone.y)][floori(drone.x)], " ", "over the void")
	assert_true(K.dist(drone, 1.5, 3.5) <= KEEP + BAND + 1e-6)
	# A grunt with the same goal is stopped at the trench's edge.
	var grunt := K.last_frame(K.resolve(_trench(EnemyType.GRUNT), [self_tape])).enemies[0]
	assert_true(grunt.x > 9.0)


func test_hovering_never_presses_a_pressure_plate_it_hovers_over() -> void:
	var self_tape := K.still(0, 2, 2, 120)
	for type: StringName in [EnemyType.DRONE, EnemyType.GRUNT]:
		var lvl := K.make_level({
			"speeds": [1.0],
			"bars": 1,
			"start": Vector2(2, 2),
			"entities": [K.enemy("d1", type, 6.5, 5.5, {"asleep": true}), K.plate("p1", 6, 5)],
		})
		var on: bool = K.resolve(lvl, [self_tape]).frames[2].mech("p1").on
		assert_eq(on, type == EnemyType.GRUNT, "%s on the plate" % type)


func test_AI07_fires_bolts_only_on_the_off_beat_after_a_telegraph_along_its_locked_aim() -> void:
	var lvl := K.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(1.5, 5), "entities": [_drone(6.5, 5)]})
	# Three selves spaced out so it keeps finding targets after each kill.
	var a := K.still(0, 1.5, 2)
	var b := K.path_tape(1, 1.0, 480, [[0, 1.5, 8]])
	var c := K.path_tape(2, 1.0, 480, [[0, 10.5, 8]])
	var res := K.resolve(lvl, [a, b, c])
	var shots := K.events_of(res.events, SimEventType.ENEMY_SHOT, -1, "d1")
	assert_true(shots.size() >= 2, "at least two shots")
	var half: int = int(DroneBehaviour.DRONE_OFFBEAT * SPB)
	var st := Tuning.enemy_stats(EnemyType.DRONE)
	for s: SimEvent in shots:
		assert_eq(s.sub % SPB, half, "on the 'and'")
		# Its grid (every 2, offset 1) shifted by half a beat: beats 1.5, 3.5, 5.5 ...
		assert_eq((s.sub - half - int(st.offset * SPB)) % int(st.every * SPB), 0)
	var tels := K.events_of(res.events, SimEventType.ENEMY_TELEGRAPH, -1, "d1")
	assert_eq(float(tels[0].sub), shots[0].sub - st.telegraph_beats * SPB)
	assert_eq(shots[0].dir, tels[0].dir, "locked aim")
	var shot_death := false
	for d: SimEvent in K.events_of(res.events, SimEventType.SELF_DEATH):
		if d.detail == "shot by drone d1":
			shot_death = true
	assert_true(shot_death, "its bolts kill")


func _sees(grid: ODGrid, res: Resolution, tels: Array[SimEvent], tx: float, ty: float) -> bool:
	for t: SimEvent in tels:
		var f: FrameSnapshot = null
		for fr: FrameSnapshot in res.frames:
			if fr.sub == t.sub + 1:
				f = fr
				break
		if f == null:
			f = K.frame_at(res, t.sub + 1)
		var d := f.enemies[0]
		if grid.segment_blocked(d.x, d.y, tx, ty, true):
			return false
	return true


func test_AI06_only_telegraphs_at_a_self_it_can_see_behind_a_pillar_it_comes_around_first() -> void:
	var walled := K.make_level({
		"map": ["############", "#..........#", "#..........#", "#....#.....#", "#....#.....#", "#....#.....#", "#..........#", "#..........#", "############"],
		"speeds": [1.0],
		"bars": 2,
		"start": Vector2(2, 4),
		"entities": [_drone(8.5, 4.5)],
	})
	var grid := ODGrid.from_level(walled)
	var res := K.resolve(walled, [K.still(0, 2.5, 4.5, 240)])
	var tels := K.events_of(res.events, SimEventType.ENEMY_TELEGRAPH, -1, "d1")
	assert_true(tels.size() > 0, "it telegraphs")
	# At the start the pillar hides the self entirely.
	assert_true(grid.segment_blocked(8.5, 4.5, 2.5, 4.5, true))
	assert_true(_sees(grid, res, tels, 2.5, 4.5), "every telegraph has a clear line")


func test_HEALTH02_a_standing_light_chips_it_a_2x_light_kills_it() -> void:
	var lvl := K.make_level({"speeds": [1.0, 2.0], "bars": 1, "start": Vector2(5.5, 5), "entities": [_drone(6.5, 5, {"asleep": true})]})
	var one := K.resolve(lvl, [K.path_tape(0, 1.0, 120, [[0, 5.5, 5]], [[10, ActionKind.LIGHT, 0.0]])])
	assert_eq(K.events_of(one.events, SimEventType.KILL).size(), 0)
	assert_eq(K.last_frame(one).enemies[0].hp, 1)
	assert_true(K.last_frame(one).enemies[0].alive)
	var two := K.resolve(lvl, [K.path_tape(0, 2.0, 120, [[0, 5.5, 5]], [[10, ActionKind.LIGHT, 0.0]])])
	assert_eq(K.events_of(two.events, SimEventType.KILL, -1, "d1").size(), 1)


# ───────────────────────────── port addition: flight path-finding ─────────────────────────────

# Void (columns 8..12) with an L-shaped wall (column 10, rows 3..6, plus row 6 to column 12). The
# drone hovers in the L's corner over void; its quarry stands west of the L. Straight west is the
# wall, there is no walking route from void, and the prototype's straight flight stuck to the wall.
const L_POCKET: Array[String] = [
	"################",
	"#.......     ..#",
	"#.......     ..#",
	"#.......  #  ..#",
	"#.......  #  ..#",
	"#.......  #  ..#",
	"#.......  ###..#",
	"#.......     ..#",
	"################",
]


func test_AI06_flight_pathfinding_a_drone_over_void_comes_around_an_L_shaped_wall() -> void:
	var lvl := K.make_level({"map": L_POCKET, "speeds": [1.0], "bars": 2, "start": Vector2(3.5, 4.5), "entities": [_drone(11.5, 4.5)]})
	var grid := ODGrid.from_level(lvl)
	assert_true(grid.segment_blocked(11.5, 4.5, 3.5, 4.5, true), "the wall hides the self at first")
	var res := K.resolve(lvl, [K.still(0, 3.5, 4.5, 240)])
	var tels := K.events_of(res.events, SimEventType.ENEMY_TELEGRAPH, -1, "d1")
	assert_true(tels.size() > 0, "it regains sight and telegraphs")
	assert_true(_sees(grid, res, tels, 3.5, 4.5), "only with a clear line")
	assert_true(K.events_of(res.events, SimEventType.ENEMY_SHOT, -1, "d1").size() > 0, "and fires")
	# It got there on a flight plan (the prototype's straight flight stops dead at the wall).
	var sim: ODSim = ODSim.create_sim(SimConfig.make(lvl, K.base_loadout(), [K.still(0, 3.5, 4.5, 240)]))
	for i: int in range(60):
		sim.step_sub()
	var de: EnemyState = sim.enemy_by_id("d1")
	assert_true(de.mem.has(DroneBehaviour.MEM_FLIGHT), "a flight plan was made")
	assert_true(de.y < 4.0, "heading round the top of the L (y %.3f)" % de.y)
	# It never entered a wall on the way.
	for f: FrameSnapshot in res.frames:
		var d := f.enemies[0]
		assert_false(DroneBehaviour.hover_solid_at(grid, d.x, d.y, Tuning.enemy_stats(EnemyType.DRONE).radius), "hover-clear at sub %d" % f.sub)
		if DroneBehaviour.hover_solid_at(grid, d.x, d.y, Tuning.enemy_stats(EnemyType.DRONE).radius):
			break


func test_flight_planner_routes_over_void_around_walls_and_never_through_them() -> void:
	var errors: Array[String] = []
	var grid := ODGrid.parse(L_POCKET, errors)
	assert_eq(errors.size(), 0)
	var fp := DroneBehaviour.FlightPlanner.new(grid.cols, grid.rows)
	fp.plan(grid, 11.5, 4.5, 3.5, 4.5, 0.3)
	assert_true(fp.count >= 2, "a bend is needed")
	assert_near(fp.px[fp.count - 1], 3.5, 1e-9, "ends on the goal")
	assert_near(fp.py[fp.count - 1], 4.5, 1e-9)
	var ax: float = 11.5
	var ay: float = 4.5
	var went_north := false
	for i: int in range(fp.count):
		assert_false(DroneBehaviour.hover_sweep_blocked(grid, ax, ay, fp.px[i], fp.py[i], 0.3), "leg %d flyable" % i)
		assert_false(grid.blocks_shot(floori(fp.px[i]), floori(fp.py[i])), "waypoint %d flyable" % i)
		if fp.py[i] < 3.0:
			went_north = true
		ax = fp.px[i]
		ay = fp.py[i]
	assert_true(went_north, "around the top of the L")
	# Sealed off: a partial route to the reachable tile nearest the goal.
	var sealed := ODGrid.parse(["#######", "#  #..#", "#  #..#", "#######"], errors)
	var fp2 := DroneBehaviour.FlightPlanner.new(sealed.cols, sealed.rows)
	fp2.plan(sealed, 1.5, 1.5, 5.5, 1.5, 0.3)
	assert_true(fp2.count >= 1)
	assert_near(fp2.px[fp2.count - 1], 2.5, 1e-9, "waits at the wall nearest the goal")


func test_flight_keeps_the_walking_route_where_one_serves() -> void:
	# On walkable ground with a walking route (the pillar case above), fly_toward is not used: the
	# drone follows EnemyCommon.walk_toward exactly as the prototype, so no flight plan is created.
	var walled := K.make_level({
		"map": ["############", "#..........#", "#..........#", "#....#.....#", "#....#.....#", "#....#.....#", "#..........#", "#..........#", "############"],
		"speeds": [1.0],
		"bars": 1,
		"start": Vector2(2, 4),
		"entities": [_drone(8.5, 4.5, HOLD_FIRE)],
	})
	var sim: ODSim = ODSim.create_sim(SimConfig.make(walled, K.base_loadout(), [K.still(0, 2.5, 4.5, 120)]))
	for i: int in range(120):
		sim.step_sub()
	assert_false(sim.enemy_by_id("d1").mem.has(DroneBehaviour.MEM_FLIGHT), "walked, not flown")
	assert_true(sim.enemy_by_id("d1").x < 8.5 or sim.enemy_by_id("d1").y != 4.5, "it moved")


# ───────────────────────────── port addition: beatSight forecast ─────────────────────────────

func test_beatSight_drone_forecast_is_on_the_off_beat() -> void:
	var lvl := K.make_level({"speeds": [1.0], "bars": 2, "start": Vector2(1.5, 5), "entities": [_drone(6.5, 5)]})
	var sim: ODSim = ODSim.create_sim(SimConfig.make(lvl, K.base_loadout(), [K.still(0, 1.5, 5, 240)]))
	var e: EnemyState = sim.enemy_by_id("d1")
	var out: Array[int] = []
	assert_true(e.beh.forecast_attack_subs(sim, e, 0, 8 * SPB, out), "drone forecasts itself")
	assert_true(out.size() > 0)
	for s: int in out:
		assert_eq(s % SPB, SPB / 2, "off-beat instant %d" % s)
	# The first one is the off-beat it really fires on.
	var res := K.resolve(lvl, [K.still(0, 1.5, 5, 240)])
	var shots := K.events_of(res.events, SimEventType.ENEMY_SHOT, -1, "d1")
	assert_true(shots.size() > 0)
	if shots.size() > 0 and out.size() > 0:
		assert_eq(out[0], shots[0].sub)
