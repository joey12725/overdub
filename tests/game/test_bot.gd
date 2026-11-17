extends ODTest
## The headless bot proves levels solvable through the real session (APP-TEST-03). Port of
## prototype/tests/game/bot.test.ts, plus the plan files in data/levels/solutions/.

const F = preload("res://tests/game/game_fixtures.gd")


func _base() -> ResolvedLoadout:
	return LoadoutRules.resolve_loadout(CampaignData.base_loadout())


func _idle(speed: float) -> GameBot.BotTake:
	return GameBot.constant_take(speed, OD.EndMode.STOP)


func test_solves_the_sandbox_with_the_baseline_loadout_in_one_take() -> void:
	var opts := GameBot.BotOptions.new()
	opts.loadout = _base()
	var errors: Array[String] = []
	var takes: Array[GameBot.BotTake] = [F.solo_sweep()]
	var run := GameBot.run_bot_detailed(CampaignData.sandbox(), takes, opts, errors)
	if not assert_true(run != null, ", ".join(errors)):
		return
	assert_true(run.outcome.win, GameBot.describe_run(run))
	assert_eq(run.takes_recorded, 1)
	assert_eq(run.session.phase, SessionPhase.RESULTS)
	assert_eq(run.outcome.survivors, [0])


func test_solves_the_sandbox_with_a_two_cassette_plan_a_opens_the_door_and_holds_the_plate_b_fights() -> void:
	var a_steps: Array[GameBot.PlanStep] = [
		GameBot.PlanStep.goto_point(3.5, 2.3),
		GameBot.PlanStep.interact(),
		GameBot.PlanStep.goto_point(2.5, 6.5),
		GameBot.PlanStep.goto_point(1.5, 8.5),
		GameBot.PlanStep.hold(1.5, 8.5),
	]
	var b_steps: Array[GameBot.PlanStep] = [
		GameBot.PlanStep.goto_point(4.5, 3.5),
		GameBot.PlanStep.goto_point(7.0, 3.5),
		GameBot.PlanStep.goto_point(11.5, 3.4),
		GameBot.PlanStep.hold(11.5, 3.4),
	]
	var takes: Array[GameBot.BotTake] = [
		GameBot.plan_take(1.0, OD.EndMode.STOP, a_steps, GameBot.Reflex.make(0.0)),
		GameBot.plan_take(2.0, OD.EndMode.STOP, b_steps, GameBot.Reflex.make(1.45, 1.2)),
	]
	var errors: Array[String] = []
	var run := GameBot.run_bot_detailed(CampaignData.sandbox(), takes, null, errors)
	if not assert_true(run != null, ", ".join(errors)):
		return
	assert_true(run.outcome.win, GameBot.describe_run(run))
	assert_eq(run.takes_recorded, 2)
	assert_eq(run.session.committed_tapes.size(), 1)
	assert_eq(run.session.pending_tape.speed, 2.0)
	var plate_on := false
	for e: SimEvent in run.session.resolution.events:
		if e.type == SimEventType.PLATE and e.detail == "on":
			plate_on = true
	assert_true(plate_on)


func test_reports_a_failing_plan_as_the_final_resolved_outcome() -> void:
	var takes: Array[GameBot.BotTake] = [_idle(1.0), _idle(1.0)]
	var out := GameBot.run_bot(CampaignData.sandbox(), takes)
	if not assert_true(out != null):
		return
	assert_false(out.win)
	assert_eq(out.reason, FailReason.OBJECTIVE)


func test_rejects_plans_the_level_cannot_accept() -> void:
	var sb := CampaignData.sandbox()
	var errors: Array[String] = []
	var none: Array[GameBot.BotTake] = []
	assert_true(GameBot.run_bot(sb, none, null, errors) == null)
	assert_true(errors.size() > 0 and errors[0].contains("no takes"), str(errors))
	errors.clear()
	var five: Array[GameBot.BotTake] = [_idle(1.0), _idle(1.0), _idle(1.0), _idle(1.0), _idle(1.0)]
	assert_true(GameBot.run_bot(sb, five, null, errors) == null)
	assert_true(errors.size() > 0 and errors[0].contains("offers 4"), str(errors))
	errors.clear()
	var narrow := sb.copy()
	narrow.speeds = [1.0, 2.0]
	var fast: Array[GameBot.BotTake] = [_idle(4.0)]
	assert_true(GameBot.run_bot(narrow, fast, null, errors) == null)
	assert_true(errors.size() > 0 and errors[0].contains("speed 4x"), str(errors))


func test_every_solution_plan_file_loads_and_meets_its_expectation() -> void:
	var paths := GameBot.plan_paths()
	assert_true(paths.has(GameBot.PLAN_DIR.path_join("sandbox.json")), str(paths))
	for p: String in paths:
		var errors: Array[String] = []
		var plan := GameBot.load_plan(p, errors)
		if not assert_true(plan != null, "%s: %s" % [p, ", ".join(errors)]):
			continue
		assert_true(CampaignData.level(plan.level_id) != null, "%s names a real level" % p)
		if plan.draft:
			# A designer's plan the level tools have not compiled yet (load_plan already refused a
			# draft that claims an expect block): nothing to replay.
			assert_true(plan.takes.is_empty(), p)
			continue
		var run := GameBot.run_plan_file(p, errors)
		if not assert_true(run != null, "%s: %s" % [p, ", ".join(errors)]):
			continue
		var want := plan.expect_win if plan.has_expect_win else true
		assert_eq(run.outcome.win, want, "%s: %s" % [p, GameBot.describe_run(run)])
		if plan.expect_takes >= 0:
			assert_eq(run.takes_recorded, plan.expect_takes, p)


func test_open_loop_inputs_by_tick_parse_and_drive_the_session() -> void:
	var d := {
		"speed": 1,
		"endMode": "stop",
		"inputs": [
			{"from": 0, "to": 30, "move": [1, 0]},
			{"from": 10, "to": 20, "aim": 1.5},
			{"tick": 12, "press": "light", "aim": -1.0},
		],
	}
	var errors: Array[String] = []
	var take := GameBot.take_from_dict(d, "inline", errors)
	if not assert_true(take != null, ", ".join(errors)):
		return
	var i0: PlayerInput = take.inputs.call(0, null)
	assert_eq([i0.move_x, i0.move_y, i0.aim], [1.0, 0.0, 0.0])
	var i11: PlayerInput = take.inputs.call(11, null)
	assert_near(i11.aim, 1.5, 1e-12)
	var i12: PlayerInput = take.inputs.call(12, null)
	assert_true(i12.light)
	assert_near(i12.aim, -1.0, 1e-12)
	var i40: PlayerInput = take.inputs.call(40, null)
	assert_eq([i40.move_x, i40.move_y], [0.0, 0.0])
	# The bot accepts it on a level.
	var takes: Array[GameBot.BotTake] = [take]
	assert_true(GameBot.run_bot(F.rescue_room(1), takes, null, errors) != null, ", ".join(errors))


func test_malformed_plans_are_reported_not_run() -> void:
	var errors: Array[String] = []
	assert_true(GameBot.take_from_dict({"endMode": "sideways", "steps": [{"fly": 1}]}, "bad", errors) == null)
	assert_true(errors.size() >= 3, str(errors))
	errors.clear()
	assert_true(GameBot.take_from_dict({"speed": 1}, "empty", errors) == null)
	assert_true(errors.size() == 1 and errors[0].contains("steps or inputs"), str(errors))
	errors.clear()
	assert_true(GameBot.load_plan("res://data/levels/solutions/no_such_plan.json", errors) == null)
	assert_true(errors.size() > 0)


func _write_tmp(name: String, d: Dictionary) -> String:
	var path := "user://test_bot_%s.json" % name
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(ODJson.stringify(d, ""))
	f.close()
	return path


func test_an_uncompiled_designer_draft_is_recognised_and_not_run() -> void:
	var take := {"speed": 1, "endMode": "stop", "note": "n", "plan": [{"goto": [3.5, 2.5]}]}
	var path := _write_tmp("draft", {"version": 1, "level": "sandbox", "takes": [take]})
	var errors: Array[String] = []
	var plan := GameBot.load_plan(path, errors)
	if assert_true(plan != null, ", ".join(errors)):
		assert_true(plan.draft)
		assert_true(plan.takes.is_empty())
	assert_true(GameBot.run_plan_file(path, errors) == null)
	assert_true(errors.size() == 1 and errors[0].contains("draft"), str(errors))
	# A draft that claims an expectation is a stale file, not a draft.
	errors.clear()
	var stale := _write_tmp("stale", {"version": 1, "level": "sandbox", "expect": {"win": true, "takes": 1}, "takes": [take]})
	assert_true(GameBot.load_plan(stale, errors) == null)
	assert_true(errors.size() == 1 and errors[0].contains("stale"), str(errors))
	# A compiled take keeps its plan alongside the inputs and is not a draft.
	errors.clear()
	var compiled := take.duplicate()
	compiled["inputs"] = [{"from": 0, "to": 10, "move": [1, 0], "aim": 0}]
	var ok := GameBot.load_plan(_write_tmp("compiled", {"version": 1, "level": "sandbox", "takes": [compiled]}), errors)
	if assert_true(ok != null, ", ".join(errors)):
		assert_false(ok.draft)
		assert_eq(ok.takes.size(), 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(stale))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_bot_compiled.json"))
