class_name GameTestFixtures
extends RefCounted
## Helpers for driving a GameSession headlessly (port of prototype/tests/game/util.ts and the plan
## builders the game suites share).

const STEP: float = 1.0 / 60.0
const S = preload("res://tests/helpers/script.gd")


static func new_session(level: LevelDef, loadout: ResolvedLoadout = null, skip_briefing: bool = true) -> GameSession:
	var errors: Array[String] = []
	var s := GameSession.create(level, loadout if loadout != null else TestLoadout.base_loadout(), skip_briefing, false, errors)
	if s == null:
		push_error("new_session: %s" % ", ".join(errors))
	return s


## Advance wall time in 1/60 s frames until the phase changes (bounded). False when it never did.
static func advance_until_phase_changes(s: GameSession, max_seconds: float = 120.0) -> bool:
	var start := s.phase
	var t := 0.0
	while t < max_seconds and s.phase == start:
		s.advance(STEP)
		t += STEP
	return s.phase != start


## record → count-in → feed the input tick by tick until the take ends. `input` is a
## TestScript.InputScript or a Callable(tick) -> PlayerInput. False when recording never started.
static func record_with(s: GameSession, input: Variant) -> bool:
	if not s.act(SessionAction.RECORD):
		push_error("record not offered in %s" % s.phase)
		return false
	advance_until_phase_changes(s, 10.0)
	if s.phase != SessionPhase.RECORDING:
		push_error("expected recording, got %s" % s.phase)
		return false
	var tick := 0
	while s.phase == SessionPhase.RECORDING:
		s.tick_local(_input_at(input, tick))
		tick += 1
	return true


static func _input_at(input: Variant, tick: int) -> PlayerInput:
	if input is Callable:
		return (input as Callable).call(tick)
	return (input as TestScript.InputScript).input(tick)


static func set_speed(s: GameSession, speed: float) -> bool:
	var i := 0
	while i < 8 and s.speed != speed:
		s.act(SessionAction.SPEED_UP if s.speed < speed else SessionAction.SPEED_DOWN)
		i += 1
	return s.speed == speed


static func no_input(_tick: int = 0) -> PlayerInput:
	return PlayerInput.make(0.0, 0.0, 0.0)


static func all_buttons(_tick: int = 0) -> PlayerInput:
	var p := PlayerInput.make(1.0, 1.0, 1.0)
	p.light = true
	p.heavy = true
	p.dodge = true
	p.ranged = true
	p.interact = true
	p.ability = true
	return p


## The rescue room from the kernel ghost tests (Scenario C): a turret shoots anyone at the start; a
## sleeping grunt is the objective; a lever opens a door.
static func rescue_room(max_tapes: int = 4) -> LevelDef:
	var ents: Array[EntityDef] = [
		S.enemy("t1", EnemyType.TURRET, 1.5, 4.5),
		S.enemy("g1", EnemyType.GRUNT, 3.0, 2.55, {"wake": SignalExpr.of_const(false)}),
		S.switch_def("lever", 2.5, 1.5),
		S.door("gate", [Vector2i(6, 3)], SignalExpr.of_sig("lever")),
	]
	var map: Array[String] = ["############", "#.....#....#", "#.....#....#", "#..........#", "#.....#....#", "############"]
	var targets: Array[String] = ["g1"]
	return TestLevels.make_level({
		"id": "rescue",
		"speeds": [1.0, 2.0],
		"bars": 4,
		"max_tapes": max_tapes,
		"map": map,
		"start": Vector2(3.0, 3.5),
		"entities": ents,
		"objective": S.objective(ObjectiveType.ELIMINATE, "Destroy the grunt", targets),
	})


## Laser hall for the final-tape edge case: a permanent laser across the room between the start and
## a sleeping grunt. Walking through it kills; only a recording ghost can then reach the grunt.
static func laser_hall(max_tapes: int = 2) -> LevelDef:
	var ents: Array[EntityDef] = [
		S.laser("beam", Vector2(5.5, 1.5), Vector2(5.5, 8.5), SignalExpr.of_const(true)),
		S.enemy("g1", EnemyType.GRUNT, 8.5, 5.5, {"wake": SignalExpr.of_const(false)}),
	]
	var targets: Array[String] = ["g1"]
	var modes: Array[int] = [OD.EndMode.STOP]
	return TestLevels.make_level({
		"id": "laser-hall",
		"speeds": [1.0],
		"end_modes": modes,
		"bars": 2,
		"max_tapes": max_tapes,
		"start": Vector2(2.5, 5.5),
		"entities": ents,
		"objective": S.objective(ObjectiveType.ELIMINATE, "Destroy the grunt", targets),
	})


## Scenario C tape A: the turret kills it early; as a recording ghost it strikes, flips the lever and
## leaves.
static func tape_a() -> TestScript.InputScript:
	return (TestScript.input_script()
		.aim(0, 480, -PI / 2.0)
		.press(100, ActionKind.LIGHT, -PI / 2.0)
		.run(130, 150, -0.3, -1)
		.press(160, ActionKind.INTERACT)
		.run(175, 200, 0.55, 1)
		.run(200, 300, 1, 0))


## TEST-11 tape B (2x): destroys the turret before its first shot, which saves tape A.
static func tape_b() -> TestScript.InputScript:
	return TestScript.input_script().run(0, 9, -1.5, 1).press(9, ActionKind.LIGHT, atan2(1.0, -1.5)).run(30, 60, 1, -1)


## The sandbox solo sweep (prototype bot.test.ts soloSweep): lever, door, both grunts, then the
## turret from above, dodging its bolt.
static func solo_sweep() -> GameBot.BotTake:
	var steps: Array[GameBot.PlanStep] = [
		GameBot.PlanStep.goto_point(3.5, 2.3),
		GameBot.PlanStep.interact(),
		GameBot.PlanStep.goto_point(4.5, 3.5),
		GameBot.PlanStep.goto_point(7.0, 3.5),
		GameBot.PlanStep.goto_point(11.5, 3.4),
		GameBot.PlanStep.hold(11.5, 3.4),
	]
	return GameBot.plan_take(1.0, OD.EndMode.STOP, steps, GameBot.Reflex.make(1.45, 1.2))


## Feed a closed-loop plan take through the session's own snapshots (Callable(tick) -> PlayerInput).
static func plan_inputs(s: GameSession, take: GameBot.BotTake) -> Callable:
	var ctx := GameBot.BotContext.new()
	return func(tick: int) -> PlayerInput:
		var snap := s.current_frame().snap
		ctx.tick = tick
		ctx.index = s.active_index
		ctx.snap = snap
		for a: ActorSnap in snap.actors:
			if a.live:
				ctx.self_actor = a
		return take.inputs.call(tick, ctx)


static func phases_of(cues: Array[GameSession.Cue]) -> Array[StringName]:
	var out: Array[StringName] = []
	for c: GameSession.Cue in cues:
		if c.kind == GameSession.CUE_PHASE:
			out.append(c.phase)
	return out


static func statuses(v: SessionView) -> Array[StringName]:
	var out: Array[StringName] = []
	for d: DeckView in v.decks:
		out.append(d.status)
	return out


static func actor_tapes(snap: FrameSnapshot) -> Array[int]:
	var out: Array[int] = []
	for a: ActorSnap in snap.actors:
		out.append(a.tape)
	return out


static func dicts(list: Array) -> Array:
	var out: Array = []
	for o: Variant in list:
		if o is DeckMark:
			out.append({"tick": (o as DeckMark).tick, "kind": String((o as DeckMark).kind)})
		elif o is DeckStateMark:
			out.append({"beat": (o as DeckStateMark).beat, "kind": String((o as DeckStateMark).kind)})
		else:
			out.append((o as Object).call("to_dict"))
	return out
