extends ODTest
## Port of prototype/tests/core/foundation/player.test.ts: locomotion, collision, actions and
## determinism of the PlayerController.

const ALIVE := OD.LifeState.ALIVE
const REC_GHOST := OD.LifeState.REC_GHOST

var big_room: ODGrid
var B := Tuning.BASE


func before_each() -> void:
	var rows: Array[String] = ["##############################"]
	for i in 12:
		rows.append("#............................#")
	rows.append("##############################")
	big_room = ODGrid.parse(rows)


func _f32(v: float) -> float:
	return PackedFloat32Array([v])[0]


## idle_input() with fields from `p` (prototype keys: moveX, moveY, aim, light, heavy, dodge, ranged,
## interact, ability).
func _input(p: Dictionary = {}) -> PlayerInput:
	var i := PlayerController.idle_input()
	for k: String in p:
		i.set(k.to_snake_case(), p[k])
	return i


func _ctl(x: float, y: float, facing: float = 0.0) -> PlayerController:
	return PlayerController.new(PlayerController.PlayerStart.make(x, y, facing))


## Steps `n` ticks; `inputs` maps the controller's current tick to an input Dictionary.
func _run(ctl: PlayerController, inputs: Callable, n: int, grid: ODGrid = null, loadout: ResolvedLoadout = null) -> Array[PlayerController.PlayerStepResult]:
	var g := grid if grid != null else big_room
	var lo := loadout if loadout != null else TestLoadout.base_loadout()
	var out: Array[PlayerController.PlayerStepResult] = []
	for i in n:
		out.append(ctl.step(_input(inputs.call(ctl.tick)), g, lo, ALIVE))
	return out


func _all_events(steps: Array[PlayerController.PlayerStepResult]) -> Array[TapeEvent]:
	var out: Array[TapeEvent] = []
	for s: PlayerController.PlayerStepResult in steps:
		out.append_array(s.events)
	return out


func _kinds_ticks(evs: Array[TapeEvent]) -> Array:
	var out: Array = []
	for e: TapeEvent in evs:
		out.append([e.kind, e.tick])
	return out


func _ticks(evs: Array[TapeEvent]) -> Array:
	var out: Array = []
	for e: TapeEvent in evs:
		out.append(e.tick)
	return out


func _speed(s: PlayerController.PlayerStepResult) -> float:
	return ODGrid.hypot(s.vx, s.vy)

# ── locomotion ──


func test_accelerates_to_run_speed_quickly_and_holds_it() -> void:
	var ctl := _ctl(3, 6)
	var steps := _run(ctl, func(_t: int) -> Dictionary: return {"moveX": 1}, 60)
	var reach_tick := -1
	for i in steps.size():
		if steps[i].vx >= B.run_speed - 1e-9:
			reach_tick = i
			break
	assert_true(reach_tick > 0)
	assert_true(reach_tick <= 8, "~0.13 s, got %d" % reach_tick)
	assert_near(steps[59].vx, B.run_speed, 5e-10)
	assert_near(steps[59].x - steps[58].x, B.run_speed / 60, 5e-6)
	assert_eq(steps[59].anim, AnimState.RUN)
	# One local second of running covers close to runSpeed tiles.
	assert_true(steps[59].x - 3 > B.run_speed - 0.5)


func test_brakes_to_a_full_stop_with_no_input() -> void:
	var ctl := _ctl(3, 6)
	_run(ctl, func(_t: int) -> Dictionary: return {"moveX": 1}, 30)
	var steps := _run(ctl, func(_t: int) -> Dictionary: return {}, 30)
	var stop_tick := -1
	for i in steps.size():
		if steps[i].vx == 0 and steps[i].vy == 0:
			stop_tick = i
			break
	assert_true(stop_tick >= 0)
	assert_true(stop_tick <= 10)
	assert_eq(steps[29].anim, AnimState.IDLE)


func test_clamps_diagonal_input_to_unit_length() -> void:
	var ctl := _ctl(3, 3)
	var s := _run(ctl, func(_t: int) -> Dictionary: return {"moveX": 1, "moveY": 1}, 60)[59]
	assert_near(_speed(s), B.run_speed, 5e-7)


func _turn(ret: float) -> float:
	var ctl := _ctl(3, 3)
	var lo := TestLoadout.base_loadout({"mods": {"momentumRetention": ret}})
	_run(ctl, func(_t: int) -> Dictionary: return {"moveX": 1}, 30, big_room, lo)
	return _run(ctl, func(_t: int) -> Dictionary: return {"moveY": 1}, 4, big_room, lo)[3].vx


func test_momentum_retention_gear_carries_more_sideways_velocity_through_a_turn() -> void:
	assert_true(_turn(2) > _turn(1))
	assert_true(_turn(1) > 0)


func test_move_speed_gear_raises_top_speed() -> void:
	var ctl := _ctl(3, 6)
	var s := _run(ctl, func(_t: int) -> Dictionary: return {"moveX": 1}, 60, big_room, TestLoadout.base_loadout({"mods": {"moveSpeed": 1.5}}))[59]
	assert_near(s.vx, B.run_speed * 1.5, 5e-10)


func test_turns_to_face_the_movement_direction() -> void:
	var ctl := _ctl(3, 6, 0)
	var s := _run(ctl, func(_t: int) -> Dictionary: return {"moveY": -1}, 10)
	assert_near(s[9].facing, -PI / 2, 5e-7)
	assert_true(absf(s[0].facing) < PI / 2, "turned, not snapped")


func test_stores_float32_exact_positions_so_live_state_equals_the_tape() -> void:
	var ctl := _ctl(3.1, 6.3)
	var bad := 0
	for s: PlayerController.PlayerStepResult in _run(ctl, func(t: int) -> Dictionary: return {"moveX": sin(t / 7.0), "moveY": cos(t / 5.0)}, 120):
		if _f32(s.x) != s.x or _f32(s.y) != s.y or _f32(s.facing) != s.facing:
			bad += 1
	assert_eq(bad, 0)

# ── collision ──


func test_stops_at_walls_and_slides_along_them() -> void:
	var g := ODGrid.parse(TestLevels.OPEN_ROOM)
	var ctl := _ctl(6, 5)
	var s := _run(ctl, func(_t: int) -> Dictionary: return {"moveX": 1, "moveY": -0.3}, 120, g)
	var last := s[s.size() - 1]
	assert_near(last.x, 11 - B.actor_radius, 0.005)
	assert_true(last.x < 11 - B.actor_radius)
	assert_true(last.y < 5)
	# Pushing into the wall kills the normal velocity only.
	assert_near(last.vx, 0, 5e-7)
	assert_false(g.is_solid_at(last.x, last.y, B.actor_radius))


func test_runs_down_a_1_tile_corridor_without_snagging() -> void:
	var g := ODGrid.parse(["##########", "#........#", "####.#####", "####.#####", "####.#####", "####.#####", "#........#", "##########"])
	var ctl := _ctl(4.5, 1.5)
	var s := _run(ctl, func(_t: int) -> Dictionary: return {"moveY": 1}, 80, g)
	assert_true(s[s.size() - 1].y > 6.4)
	for p: PlayerController.PlayerStepResult in s:
		if not assert_false(g.is_solid_at(p.x, p.y, B.actor_radius)):
			return


func test_enters_a_corridor_from_an_angle_by_sliding_off_the_corner() -> void:
	var g := ODGrid.parse(["##########", "#........#", "####.#####", "####.#####", "#........#", "##########"])
	var ctl := _ctl(4.3, 1.5)
	var s := _run(ctl, func(_t: int) -> Dictionary: return {"moveY": 1}, 80, g)
	assert_true(s[s.size() - 1].y > 4.4)


func test_ghost_02_test_08_recording_ghosts_are_still_blocked_by_walls() -> void:
	var g := ODGrid.parse(["#####", "#...#", "#####"])
	g.set_dynamic_solid(2, 1, true) # closed door
	var ctl := _ctl(1.5, 1.5)
	var s: PlayerController.PlayerStepResult = null
	for i in 60:
		s = ctl.step(_input({"moveX": 1}), g, TestLoadout.base_loadout(), REC_GHOST)
	assert_true(s.x < 2 - B.actor_radius + 1e-6)

# ── actions ──


func test_light_attack_event_phases_facing_lock_and_slowdown_follow_action_timing() -> void:
	var lo := TestLoadout.base_loadout()
	var tm := PlayerController.action_timing(ActionKind.LIGHT, lo)
	assert_eq([tm.active_start, tm.active_end, tm.commit], [6, 10, 20])
	var ctl := _ctl(5, 6)
	_run(ctl, func(_t: int) -> Dictionary: return {"moveX": 1}, 30)
	var t0 := ctl.tick
	var steps := _run(ctl, func(t: int) -> Dictionary: return {"moveY": 1, "light": t == t0, "aim": 0.7}, 30, big_room, lo)
	var evs := _all_events(steps)
	if not assert_eq(evs.size(), 1):
		return
	assert_eq([evs[0].tick, evs[0].kind], [t0, ActionKind.LIGHT])
	assert_near(evs[0].dir, 0.7, 5e-13)
	assert_near(evs[0].vx, B.run_speed, 5e-10, "velocity when the swing started (momentum input)")
	for i in 30:
		var want := AnimState.LIGHT_WINDUP if i < 6 else (AnimState.LIGHT_ACTIVE if i < 10 else (AnimState.LIGHT_RECOVER if i < 20 else AnimState.RUN))
		if i <= 20:
			assert_eq(steps[i].anim, want, "anim at %d" % i)
	for i in 10:
		assert_near(steps[i].facing, 0.7, 5e-7)
	assert_true(PlayerController.melee_hit_window(evs[0], lo).equals(PlayerController.TickWindow.make(t0 + 6, t0 + 10)))
	assert_eq(PlayerController.effect_tick(evs[0], lo), t0 + 6)
	# Speed is pulled toward moveMul × run speed while committed.
	assert_true(_speed(steps[19]) < B.run_speed * 0.5 + 0.05)


func test_heavy_attack_uses_the_heavy_swing_timing() -> void:
	var lo := TestLoadout.base_loadout()
	var ctl := _ctl(5, 6)
	var steps := _run(ctl, func(t: int) -> Dictionary: return {"heavy": t == 0}, 45, big_room, lo)
	var counts := {}
	for s: PlayerController.PlayerStepResult in steps:
		counts[s.anim] = counts.get(s.anim, 0) + 1
	assert_eq(counts.get(AnimState.HEAVY_WINDUP, 0), 16)
	assert_eq(counts.get(AnimState.HEAVY_ACTIVE, 0), 5)
	assert_eq(counts.get(AnimState.HEAVY_RECOVER, 0), 18)
	assert_true(PlayerController.melee_hit_window(_all_events(steps)[0], lo).equals(PlayerController.TickWindow.make(16, 21)))


func test_buffers_a_press_during_recovery_for_a_few_ticks_but_not_forever() -> void:
	var lo := TestLoadout.base_loadout()
	var ctl := _ctl(5, 6)
	# Light at 0 (free again at 20); heavy pressed at 14 is buffered and starts at 20.
	var s1 := _run(ctl, func(t: int) -> Dictionary: return {"light": t == 0, "heavy": t == 14}, 40, big_room, lo)
	assert_eq(_kinds_ticks(_all_events(s1)), [[ActionKind.LIGHT, 0], [ActionKind.HEAVY, 20]])
	# Pressed at 11: 9 ticks before free, longer than the buffer: dropped.
	var ctl2 := _ctl(5, 6)
	var s2 := _run(ctl2, func(t: int) -> Dictionary: return {"light": t == 0 or t == 11}, 40, big_room, lo)
	assert_eq(_ticks(_all_events(s2)), [0])


func test_dodge_dash_distance_i_frames_and_cooldown() -> void:
	var lo := TestLoadout.base_loadout()
	var tm := PlayerController.action_timing(ActionKind.DODGE, lo)
	var ctl := _ctl(5, 6)
	var steps := _run(ctl, func(t: int) -> Dictionary: return {"moveX": 1.0 if t < 14 else 0.0, "dodge": t == 0 or t == 20 or t == 30}, 80, big_room, lo)
	var evs := _all_events(steps)
	# The press at 20 expires in the buffer before the cooldown ends; the one at 30 waits for it.
	assert_eq(_ticks(evs), [0, tm.cooldown])
	assert_eq(tm.cooldown, B.dodge_ticks + B.dodge_cooldown)
	# The dash covers the dodge distance.
	assert_near(steps[B.dodge_ticks - 1].x - 5, B.dodge_distance, 5e-5)
	var win := PlayerController.dodge_iframe_window(evs[0], lo)
	assert_true(win.equals(PlayerController.TickWindow.make(1, 1 + int(B.dodge_iframes))))
	for i in 20:
		assert_eq(steps[i].iframes, i >= win.start and i < win.end, "iframes at %d" % i)
	for i in B.dodge_ticks:
		assert_eq(steps[i].anim, AnimState.DODGE)


func test_dodge_goes_along_facing_when_idle_and_scales_with_gear() -> void:
	var lo := TestLoadout.base_loadout({"mods": {"dodgeDistance": 1.5, "dodgeIframes": 2, "dodgeCooldown": 0.5}})
	var ctl := _ctl(10, 6, PI)
	var steps := _run(ctl, func(t: int) -> Dictionary: return {"dodge": t == 0}, 20, big_room, lo)
	assert_near(10 - steps[B.dodge_ticks - 1].x, B.dodge_distance * 1.5, 5e-6)
	assert_near(_all_events(steps)[0].dir, PI, 5e-7)
	var tm := PlayerController.action_timing(ActionKind.DODGE, lo)
	assert_eq(tm.iframe_end - tm.iframe_start, B.dodge_iframes * 2)
	assert_eq(tm.cooldown, B.dodge_ticks + roundi(B.dodge_cooldown * 0.5))


func test_a_buffered_dodge_cancels_melee_recovery_but_not_windup() -> void:
	var ctl := _ctl(5, 6)
	var steps := _run(ctl, func(t: int) -> Dictionary: return {"light": t == 0, "dodge": t == 3 or t == 12}, 30)
	# Dodge at 3 is buffered (windup) until 10, when recovery begins and it may cancel.
	assert_eq(_kinds_ticks(_all_events(steps)), [[ActionKind.LIGHT, 0], [ActionKind.DODGE, 10]])


func test_phase_dodge_crosses_low_barriers_a_normal_dodge_does_not() -> void:
	var g := ODGrid.parse(["#######", "#..=..#", "#######"])
	var plain := _ctl(1.5, 1.5)
	var a := _run(plain, func(t: int) -> Dictionary: return {"moveX": 1, "dodge": t == 0}, 20, g)
	assert_true(a[19].x < 3)
	var phase := _ctl(1.5, 1.5)
	var b := _run(phase, func(t: int) -> Dictionary: return {"moveX": 1, "dodge": t == 0}, 20, g, TestLoadout.base_loadout({"abilities": [AbilityId.PHASE_DODGE]}))
	assert_true(b[19].x > 4)


func test_ranged_launch_tick_commit_and_cooldown() -> void:
	var lo := TestLoadout.base_loadout()
	var tm := PlayerController.action_timing(ActionKind.RANGED, lo)
	assert_eq(tm.effect, B.ranged_launch_delay)
	assert_eq(tm.cooldown, 45)
	var ctl := _ctl(5, 6)
	var steps := _run(ctl, func(t: int) -> Dictionary: return {"ranged": t == 0 or t == 40, "aim": -1}, 60, big_room, lo)
	var evs := _all_events(steps)
	assert_eq(_ticks(evs), [0, 45])
	assert_eq(PlayerController.ranged_launch_tick(evs[0], lo), B.ranged_launch_delay)
	for i in 12:
		assert_eq(steps[i].anim, AnimState.RANGED)
	assert_near(steps[0].facing, -1, 5e-7)
	assert_eq(PlayerController.melee_hit_window(evs[0], lo), null)
	assert_eq(PlayerController.dodge_iframe_window(evs[0], lo), null)
	assert_eq(PlayerController.ranged_launch_tick(TapeEvent.make(3, ActionKind.LIGHT, 0, 0, 0), lo), -1)
	assert_eq(PlayerController.action_timing(ActionKind.RANGED, TestLoadout.base_loadout({"mods": {"rangedCooldown": 0.5}})).cooldown, 23)


func test_interact_and_ability() -> void:
	var ctl := _ctl(5, 6)
	var steps := _run(ctl, func(t: int) -> Dictionary: return {"interact": t == 2, "ability": t == 3}, 20)
	var kinds: Array = []
	for e: TapeEvent in _all_events(steps):
		kinds.append(e.kind)
	assert_eq(kinds, [ActionKind.INTERACT], "no active ability equipped")
	assert_eq(steps[2].anim, AnimState.INTERACT)
	var ctl2 := _ctl(5, 6)
	var s2 := _run(ctl2, func(t: int) -> Dictionary: return {"ability": t == 3, "light": t == 3}, 20, big_room, TestLoadout.base_loadout({"abilities": [AbilityId.MANUAL_DESYNC]}))
	assert_eq(_kinds_ticks(_all_events(s2)), [[ActionKind.ABILITY, 3], [ActionKind.LIGHT, 3]])


func test_records_the_pre_step_position_and_velocity_on_events() -> void:
	var ctl := _ctl(5, 6)
	_run(ctl, func(_t: int) -> Dictionary: return {"moveX": 1}, 20)
	var before := ctl.pose
	var s := ctl.step(_input({"moveX": 1, "light": true}), big_room, TestLoadout.base_loadout(), ALIVE)
	var e := s.events[0]
	assert_eq([e.tick, e.x, e.y, e.vx, e.vy], [20, before.x, before.y, before.vx, before.vy])
	assert_eq(ctl.action_kind, ActionKind.LIGHT)


func test_kill_refresh_refresh_dodge_clears_the_cooldown() -> void:
	var ctl := _ctl(5, 6)
	_run(ctl, func(t: int) -> Dictionary: return {"dodge": t == 0}, 16)
	assert_true(ctl.dodge_cooldown > 0)
	ctl.refresh_dodge()
	assert_eq(ctl.dodge_cooldown, 0)
	var s := ctl.step(_input({"dodge": true}), big_room, TestLoadout.base_loadout(), ALIVE)
	assert_eq(s.events[0].kind, ActionKind.DODGE)


func test_sanitises_non_finite_input() -> void:
	var ctl := _ctl(5, 6, 0.25)
	var s := ctl.step(_input({"moveX": NAN, "moveY": INF, "aim": NAN, "ranged": true}), big_room, TestLoadout.base_loadout(), ALIVE)
	assert_eq([s.x, s.y, s.vx, s.vy], [5, 6, 0, 0])
	assert_near(s.events[0].dir, 0.25, 1e-7, "a NaN aim keeps the current facing")

# ── determinism ──


func _record(seed: int, loadout: ResolvedLoadout = null) -> ODTape:
	var lo := loadout if loadout != null else TestLoadout.base_loadout()
	var s := seed
	var g := ODGrid.parse([
		"################",
		"#......#.......#",
		"#..==..#..##...#",
		"#......=.......#",
		"#..#.......#...#",
		"#..#..###..#...#",
		"#..............#",
		"################",
	])
	var ctl := _ctl(2, 2, 0)
	var ticks := 600
	var p := ctl.pose
	var rec := TapeRecorder.new(TapeLib.TapeRecorderInit.make(0, 2, OD.EndMode.STOP, ticks, p.x, p.y, p.facing))
	var mx := 0.0
	var my := 0.0
	var input := PlayerInput.new()
	var solid := 0
	for i in ticks:
		# The prototype's LCG: s = (s * 1664525 + 1013904223) >>> 0; value s / 2^32.
		if i % 9 == 0:
			s = (s * 1664525 + 1013904223) & 0xffffffff
			mx = s / 4294967296.0 * 2 - 1
			s = (s * 1664525 + 1013904223) & 0xffffffff
			my = s / 4294967296.0 * 2 - 1
		input.move_x = mx
		input.move_y = my
		s = (s * 1664525 + 1013904223) & 0xffffffff
		input.aim = s / 4294967296.0 * 6.28 - 3.14
		s = (s * 1664525 + 1013904223) & 0xffffffff
		var r := s / 4294967296.0
		input.light = r < 0.03
		input.heavy = r >= 0.03 and r < 0.045
		input.dodge = r >= 0.045 and r < 0.07
		input.ranged = r >= 0.07 and r < 0.08
		input.interact = r >= 0.08 and r < 0.09
		input.ability = r >= 0.09 and r < 0.095
		var res := ctl.step(input, g, lo, ALIVE if i < 300 else REC_GHOST)
		for e: TapeEvent in res.events:
			rec.add_event(e)
		rec.push(res.x, res.y, res.facing, res.anim)
		if g.is_solid_at(res.x, res.y, B.actor_radius):
			solid += 1
	assert_eq(solid, 0, "never inside a wall")
	return rec.finish()


func test_same_inputs_produce_bit_identical_tapes() -> void:
	var a := _record(42)
	var b := _record(42)
	assert_true(TapeLib.tapes_equal(a, b))
	assert_true(a.events.size() > 10)
	assert_false(TapeLib.tapes_equal(a, _record(43)))


func test_gear_changes_the_tape_loadout_is_an_input() -> void:
	assert_false(TapeLib.tapes_equal(_record(5), _record(5, TestLoadout.base_loadout({"mods": {"moveSpeed": 1.2}}))))
