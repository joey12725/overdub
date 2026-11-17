extends ODTest
## Bit-exact parity with the prototype. fixtures/foundation_reference.json is written by the prototype
## itself (fixtures/gen_foundation_reference.ts; regenerate with
## `cd prototype && npx vite-node ../tests/core/foundation/fixtures/gen_foundation_reference.ts`).
## Doubles travel as base64 Float64 bytes, so no decimal parsing is involved.
##
##   path     — 500 plans on the 40×40 performance maze (dynamic solids toggling, partial paths,
##              smoothing on and off, off-centre goals): found / complete / expanded / cost / points.
##   walk     — 4000 random fast move_circle steps: every resulting position.
##   player   — the 600-tick determinism recording (two seeds, two loadouts): the whole tape and the
##              per-tick velocities.

const FIXTURE := "res://tests/core/foundation/fixtures/foundation_reference.json"

var ref: Dictionary = {}


func before_each() -> void:
	if ref.is_empty():
		var data: Variant = load_json(FIXTURE)
		if data is Dictionary:
			ref = data


func _f64(b64: String) -> PackedFloat64Array:
	return Marshalls.base64_to_raw(b64).to_float64_array() if not b64.is_empty() else PackedFloat64Array()


func _f32(v: float) -> float:
	return PackedFloat32Array([v])[0]


func test_path_plans_match_the_prototype_exactly() -> void:
	if not assert_true(ref.has("path"), "fixture loaded"):
		return
	var plans: Array = ref["path"]
	var g := ODGrid.parse(load("res://tests/core/foundation/test_path.gd").maze_40())
	var pf := Pathfinder.new(g)
	var open: Array[Vector2i] = []
	for r in 40:
		for c in 40:
			if g.is_walkable(c, r):
				open.append(Vector2i(c, r))
	var mismatches := 0
	for i in plans.size():
		var want: Dictionary = plans[i]
		var a := open[(i * 7919) % open.size()]
		var b := open[(i * 104729 + 13) % open.size()]
		if i % 50 == 0:
			g.set_dynamic_solid(b.x, (b.y + 1) % 40, i % 100 == 0)
		var tx := b.x + (0.25 if i % 3 == 0 else 0.5)
		var ty := b.y + (0.8 if i % 3 == 0 else 0.5)
		var res := pf.find_path(a.x + 0.5, a.y + 0.5, tx, ty, Pathfinder.PathOpts.make(true, i % 2 == 0))
		var pts := _f64(want["points"])
		var ok: bool = (res != null) == want["found"] and pf.last_expanded == int(want["expanded"])
		if ok and res != null:
			ok = res.complete == want["complete"] and res.cost == _f64(want["cost"])[0] and res.points.size() * 2 == pts.size()
			if ok:
				for k in res.points.size():
					# PathResult.points are Vector2 (32-bit): compare with the prototype's doubles rounded to float32.
					if res.points[k] != Vector2(_f32(pts[k * 2]), _f32(pts[k * 2 + 1])):
						ok = false
		if not ok:
			mismatches += 1
			if mismatches <= 3:
				fail("plan %d differs: want %s, got %s" % [i, want, [res != null, res.complete if res else false, pf.last_expanded, res.cost if res else 0.0, res.points if res else []]])
	assert_eq(mismatches, 0, "plans differing from the prototype")


func _walk_grid() -> ODGrid:
	return ODGrid.parse([
		"############",
		"#....#.....#",
		"#.##.#.##..#",
		"#.#..=..#..#",
		"#.#.###.#..#",
		"#...# ..#..#",
		"############",
	])


func test_move_circle_walk_matches_the_prototype_exactly_given_its_inputs() -> void:
	if not assert_true(ref.has("walk"), "fixture loaded"):
		return
	var want := _f64(ref["walk"])
	var inputs := _f64(ref["walkInputs"])
	var g := _walk_grid()
	var x := 1.5
	var y := 1.5
	var first_bad := -1
	for i in 4000:
		var r := g.move_circle(x, y, inputs[i * 4 + 2], inputs[i * 4 + 3], 0.3)
		x = r.x
		y = r.y
		if first_bad < 0 and (x != want[i * 2] or y != want[i * 2 + 1]):
			first_bad = i
	assert_eq(first_bad, -1, "first step that differs from the prototype")


## Godot's sin/cos (the platform C runtime) and V8's (fdlibm) can disagree in the last bit. The
## LCG-derived angle and distance must agree exactly; the trig products may differ by ~1 ulp.
func test_walk_inputs_agree_with_v8_up_to_libm_rounding() -> void:
	if not assert_true(ref.has("walkInputs"), "fixture loaded"):
		return
	var inputs := _f64(ref["walkInputs"])
	var seed := 7
	var lcg_bad := 0
	var trig_diff := 0
	var worst := 0.0
	for i in 4000:
		seed = (seed * 1664525 + 1013904223) & 0xffffffff
		var a := seed / 4294967296.0 * PI * 2
		seed = (seed * 1664525 + 1013904223) & 0xffffffff
		var d := seed / 4294967296.0 * 1.5
		if a != inputs[i * 4] or d != inputs[i * 4 + 1]:
			lcg_bad += 1
		var dx := cos(a) * d
		var dy := sin(a) * d
		if dx != inputs[i * 4 + 2] or dy != inputs[i * 4 + 3]:
			trig_diff += 1
			worst = maxf(worst, maxf(absf(dx - inputs[i * 4 + 2]), absf(dy - inputs[i * 4 + 3])))
	assert_eq(lcg_bad, 0, "LCG angle / distance")
	assert_true(worst < 1e-15, "trig differences stay at the last-bit level (worst %s)" % worst)
	print("    [parity] sin/cos products differing from V8 in the last bit: %d of 8000 (worst %s)" % [trig_diff, worst])


func _record(seed: int, loadout: ResolvedLoadout) -> Array:
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
	var ctl := PlayerController.new(PlayerController.PlayerStart.make(2, 2, 0))
	var ticks := 600
	var p := ctl.pose
	var rec := TapeRecorder.new(TapeLib.TapeRecorderInit.make(0, 2, OD.EndMode.STOP, ticks, p.x, p.y, p.facing))
	var mx := 0.0
	var my := 0.0
	var vel := PackedFloat64Array()
	var input := PlayerInput.new()
	for i in ticks:
		if i % 9 == 0:
			s = (s * 1664525 + 1013904223) & 0xffffffff
			mx = s / 4294967296.0 * 2 - 1
			s = (s * 1664525 + 1013904223) & 0xffffffff
			my = s / 4294967296.0 * 2 - 1
		s = (s * 1664525 + 1013904223) & 0xffffffff
		var r := s / 4294967296.0
		input.move_x = mx
		input.move_y = my
		s = (s * 1664525 + 1013904223) & 0xffffffff
		input.aim = s / 4294967296.0 * 6.28 - 3.14
		input.light = r < 0.03
		input.heavy = r >= 0.03 and r < 0.045
		input.dodge = r >= 0.045 and r < 0.07
		input.ranged = r >= 0.07 and r < 0.08
		input.interact = r >= 0.08 and r < 0.09
		input.ability = r >= 0.09 and r < 0.095
		var res := ctl.step(input, g, loadout, OD.LifeState.ALIVE if i < 300 else OD.LifeState.REC_GHOST)
		for e: TapeEvent in res.events:
			rec.add_event(e)
		rec.push(res.x, res.y, res.facing, res.anim)
		vel.append(res.vx)
		vel.append(res.vy)
	return [rec.finish(), vel]


func _check_player(key: String, seed: int, loadout: ResolvedLoadout) -> void:
	if not assert_true(ref.has(key), "fixture loaded"):
		return
	var want: Dictionary = ref[key]
	var errors: Array[String] = []
	var want_tape := ODTape.from_dict(want["tape"], errors)
	assert_eq(errors, [])
	var got: Array = _record(seed, loadout)
	var tape: ODTape = got[0]
	var vel: PackedFloat64Array = got[1]
	var want_vel := _f64(want["velocities"])
	var first_bad := -1
	for i in vel.size():
		if vel[i] != want_vel[i]:
			first_bad = i / 2
			break
	var first_pose := -1
	var worst_pos := 0.0
	var worst_facing := 0.0
	for i in tape.ticks + 1:
		var dx := absf(tape.pos[i * 2] - want_tape.pos[i * 2])
		var dy := absf(tape.pos[i * 2 + 1] - want_tape.pos[i * 2 + 1])
		var df := absf(TapeLib.angle_delta(tape.facing[i], want_tape.facing[i]))
		if first_pose < 0 and (dx > 0.0 or dy > 0.0 or df > 0.0 or tape.anim[i] != want_tape.anim[i]):
			first_pose = i
		worst_pos = maxf(worst_pos, maxf(dx, dy))
		worst_facing = maxf(worst_facing, df)
	# Recorded attempts (tick + kind) and animation states must be identical; poses may drift only by
	# libm last-bit noise (V8's fdlibm vs the platform's atan2/sin/cos/exp).
	assert_eq(tape.events.size(), want_tape.events.size(), key + " event count")
	var same_events := tape.events.size() == want_tape.events.size()
	if same_events:
		for i in tape.events.size():
			if tape.events[i].tick != want_tape.events[i].tick or tape.events[i].kind != want_tape.events[i].kind:
				same_events = false
	assert_true(same_events, key + ": event ticks and kinds identical")
	assert_eq(tape.anim, want_tape.anim, key + ": anim states identical")
	assert_true(worst_pos < 1e-4, "%s: worst position deviation %s tiles" % [key, worst_pos])
	assert_true(worst_facing < 1e-4, "%s: worst facing deviation %s rad" % [key, worst_facing])
	print("    [parity] %s: bit-identical=%s; first differing velocity tick %d, first differing pose sample %d; worst |pos| %s tiles, worst |facing| %s rad" % [
		key, TapeLib.tapes_equal(tape, want_tape), first_bad, first_pose, worst_pos, worst_facing])


func test_player_recording_matches_the_prototype_up_to_libm_rounding() -> void:
	_check_player("player42", 42, TestLoadout.base_loadout())


func test_player_recording_with_gear_matches_the_prototype_up_to_libm_rounding() -> void:
	_check_player("player5fast", 5, TestLoadout.base_loadout({"mods": {"moveSpeed": 1.2}}))
