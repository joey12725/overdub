extends RefCounted
## Shared fixtures for the acceptance suites (tests/acceptance/test_acceptance_*.gd) and the replay
## suite (tests/replay/). Preload it: `const K = preload("res://tests/acceptance/acceptance_kit.gd")`.
## No class_name on purpose (nothing outside tests needs it).
##
## - ROWS: every acceptance id of docs/requirements.txt chapter 21 (TEST-01..34), Revision 1 (NEW-01..11)
##   and Revision 2 (APP-TEST-01..03) with its "Check" and "Expected result" text copied LITERALLY from
##   the document (wrapped lines joined with one space). test_acceptance_texts.gd proves each text
##   still occurs in docs/requirements.txt, so a reworded requirement breaks the suite instead of
##   silently drifting from it.
## - Scenario rooms shared by several suites (the Scenario C rescue room and its two tapes).
## - Golden fixtures: tests/goldens/*.json are scenarios authored and checked in the prototype. Here
##   they are only INPUTS (level, loadout, trajectory tapes, recorded inputs): `golden_run` records
##   the input takes through the shipped ODSim and resolves everything through the shipped ODResolve.
##   The acceptance assertions are then made against what the port produced, not against the
##   golden's expected numbers.
## - A GameSession driver (record / advance / speed) mirroring prototype tests/game/util.ts.

const S = preload("res://tests/helpers/script.gd")

## id -> [check, expected result]. Texts are verbatim from docs/requirements.txt.
const ROWS: Dictionary = {
	"TEST-01": ["Record the same-duration level at slow, middle and fast settings.", "Actual recording allowance remains equal; world pace changes relative to the controlled character."],
	"TEST-02": ["Compare a recording’s platform landing with true-speed replay.", "The master-beat relationship is preserved; no duration stretching changes the landing."],
	"TEST-03": ["Begin cassette two after finishing cassette one.", "The encounter starts at beat zero; cassette one plays from its start."],
	"TEST-04": ["Record a later tape.", "Prior tapes are visible/simulated; unrecorded future tapes do not appear."],
	"TEST-05": ["Retry the currently active cassette before advancing.", "Earlier committed takes remain; the current take can be replaced."],
	"TEST-06": ["Change any older tape after advancing.", "Every cassette in the attempt is reset, including those before the edited tape."],
	"TEST-07": ["Die while actively recording.", "Recording continues with a major ghost visual distinction."],
	"TEST-08": ["Approach a locked door while actively recording after death.", "Normal movement collision still applies; the recording ghost cannot simply phase through."],
	"TEST-09": ["Attack and flip a switch as the active recording ghost.", "They affect that provisional recording run."],
	"TEST-10": ["Replay the same tape and let it die before those events.", "Later attack/switch effects do not occur; its non-interactive ghost continues the path."],
	"TEST-11": ["Prevent the tape’s old fatal hit.", "Later recorded actions can be effective, subject to current world and sync state."],
	"TEST-12": ["Kill a previously surviving earlier tape at a new time.", "From that moment, it becomes a non-interactive playback ghost."],
	"TEST-13": ["Close a door across a living earlier tape’s recorded path.", "Its projection stays on the recording; desynchronization and reachable recovery apply."],
	"TEST-14": ["Leave an unobstructed detour for the recovery spark.", "Finite-speed recovery can navigate toward the moving projection; no instant overlap-only recovery."],
	"TEST-15": ["Open a blocked route while a spark is catching up.", "The new traversable route can enable recovery."],
	"TEST-16": ["Attack or receive fire while desynchronized.", "No dealt or received damage under the working invulnerable/harmless rule."],
	"TEST-17": ["Use the wall-and-turret teaching case.", "Desync can protect the crossing, but the actor must resync before damaging the turret."],
	"TEST-18": ["Add a closer self to an enemy’s target rule.", "Enemy response can change without the old tape changing its aim or path."],
	"TEST-19": ["Knock an enemy into/out of another attack.", "Its new physical position changes later hit outcomes."],
	"TEST-20": ["Compare movement/tape-speed combinations on the same attack.", "Effective momentum meaningfully influences damage, stagger and knockback."],
	"TEST-21": ["Dodge a qualifying hit.", "The selected i-frame interval can prevent death; exact timing is tunable."],
	"TEST-22": ["Fire a recorded missile after changing enemy positions.", "Nearest target is acquired once at launch; the missile does not continuously retarget."],
	"TEST-23": ["Kill three selves and complete the objective with one survivor.", "The survival rule permits success."],
	"TEST-24": ["Complete an objective with no survivors.", "The survival requirement is not met."],
	"TEST-25": ["Trigger repeat on a short tape.", "It cuts to its starting position and repeats without resetting the entire encounter."],
	"TEST-26": ["Trigger reverse.", "Recorded actions run backward without globally restoring world history; specific event inverses require policy."],
	"TEST-27": ["Produce a mechanically valid but unusual rhythm.", "The solution is not rejected or steered away solely for musical reasons."],
	"TEST-28": ["Produce ordinary movement/combat sounds.", "They use the agreed fine rhythmic integration policy; no unapproved gameplay-time adjustment."],
	"TEST-29": ["Kill/desync a cassette.", "Its own generated musical channel changes state; shared coherence remains a design goal."],
	"TEST-30": ["Let enemies attack.", "Their timing can be beat-based, but they do not directly rewrite player wave functions."],
	"TEST-31": ["Finish a failed final encounter.", "Playback may finish for observation; the player can reset/end early."],
	"TEST-32": ["Watch a successful cinematic.", "Controls do not alter the result; all tapes use correct master timing and extra music-linked visuals."],
	"TEST-33": ["Change gear between levels.", "Available equipment can be recombined without skill-point reallocation."],
	"TEST-34": ["Review art handoff.", "Selected character details, isometric perspective, warm upper lighting and neon metal lower direction are preserved."],
	"NEW-01": ["Weapon behavior", "Equip at least two melee weapons with visibly different effective reach, attack timing, knockback or other meaningful properties; both remain viable."],
	"NEW-02": ["Weapon behavior", "Equip at least two ranged weapon archetypes with different weaknesses; guided missile is slower than at least one alternative projectile."],
	"NEW-03": ["Weapon behavior", "A missile acquires nearest enemy once on launch, does not retarget, and may choose a different enemy on a subsequent tape playback if battlefield state differs."],
	"NEW-04": ["Weapon behavior", "A fast piercing projectile may strike successive targets in its line when that weapon property applies; a normal projectile does not inherit piercing automatically."],
	"NEW-05": ["Weapon behavior", "A wall-piercing or vertical-trajectory weapon follows only its own documented collision/trajectory rules; never grant every ranged attack these abilities."],
	"NEW-06": ["Weapon behavior", "Different cassette speeds and local velocity influence melee momentum and its damage/stagger/knockback consequences, with weapon-specific characteristics."],
	"NEW-07": ["Cassette HUD and planning", "Four separately identifiable on-screen cassette elements are present during level play; their colors correspond to the four player recordings."],
	"NEW-08": ["Cassette HUD and planning", "Each cassette visibly states its tape speed and status, including which tape is currently recording and which are committed."],
	"NEW-09": ["Cassette HUD and planning", "Continuous-time master timeline with beat markers remains visible during recording, not only during the final cinematic replay."],
	"NEW-10": ["Cassette HUD and planning", "Switching tape speed changes readout and any corresponding reel/transport feedback without losing master-beat alignment."],
	"NEW-11": ["Cassette HUD and planning", "A player can distinguish a cassette that is unrecorded, committed, stopped, looping, reversing, dead or desynchronized without relying exclusively on audio."],
	"APP-TEST-01": ["Acceptance criteria", "Equip and swap a helmet, shirt, pants, and shoes; each category can demonstrably change a gameplay outcome."],
	"APP-TEST-02": ["Acceptance criteria", "Changing a clothing slot updates its displayed effect and preserves the distinction between equipment categories."],
	"APP-TEST-03": ["Acceptance criteria", "A valid compulsory level can be completed using at least the intended baseline loadout available before entering it."],
}


static func expected(id: String) -> String:
	return ROWS[id][1]


## "<id> expects: <text>" for assertion messages.
static func say(id: String, detail: String = "") -> String:
	return "%s expects \"%s\"%s" % [id, expected(id), (" - " + detail) if not detail.is_empty() else ""]


## Collapse every whitespace run to one space (the PDF text wraps rows over several lines).
static func norm(s: String) -> String:
	var re := RegEx.create_from_string("\\s+")
	return re.sub(s, " ", true).strip_edges()


# ───────────────────────────── rooms ─────────────────────────────


## The Scenario C rescue room (prototype tests/game/util.ts rescueRoom):
##          012345678901
##     r0   ############
##     r1   #.L...#....#     L lever (2.5, 1.5)
##     r2   #..g..#....#     g grunt g1, asleep (3.0, 2.55) - the objective
##     r3   #..@..D....#     @ start (3.0, 3.5); D door "gate" (6, 3), opened by the lever
##     r4   #T....#....#     T turret t1 (1.5, 4.5) - shoots anyone standing at the start
##     r5   ############
static func rescue_room(max_tapes: int = 4, gate_open_when: SignalExpr = null) -> LevelDef:
	var ents: Array[EntityDef] = [
		S.enemy("t1", EnemyType.TURRET, 1.5, 4.5),
		S.enemy("g1", EnemyType.GRUNT, 3.0, 2.55, {"wake": SignalExpr.of_const(false)}),
		S.switch_def("lever", 2.5, 1.5),
		S.door("gate", [Vector2i(6, 3)], gate_open_when if gate_open_when != null else SignalExpr.of_sig("lever")),
	]
	var map: Array[String] = ["############", "#.....#....#", "#.....#....#", "#..........#", "#.....#....#", "############"]
	var targets: Array[String] = ["g1"]
	var lv := TestLevels.make_level(
		{
			"id": "rescue",
			"speeds": [1.0, 2.0],
			"bars": 4,
			"max_tapes": max_tapes,
			"map": map,
			"start": Vector2(3.0, 3.5),
			"entities": ents,
			"objective": S.objective(ObjectiveType.ELIMINATE, "Destroy the grunt", targets),
		}
	)
	return lv


## Tape A (1x): stands at the start (the turret kills it early), then - as a recording ghost -
## strikes the grunt, flips the lever and walks through the door.
static func tape_a_script() -> TestScript.InputScript:
	return (
		S.input_script()
		.aim(0, 480, -PI / 2)
		.press(100, ActionKind.LIGHT, -PI / 2)
		.run(130, 150, -0.3, -1)
		.press(160, ActionKind.INTERACT)
		.run(175, 200, 0.55, 1)
		.run(200, 300, 1, 0)
	)


## Tape B (2x): runs at the turret and destroys it before its first shot, which saves tape A.
static func tape_b_script() -> TestScript.InputScript:
	return S.input_script().run(0, 9, -1.5, 1).press(9, ActionKind.LIGHT, atan2(1, -1.5)).run(30, 60, 1, -1)


## The two-cassette rescue win, recorded through the shipped sim: [tape A, tape B].
static func rescue_win_tapes(level: LevelDef) -> Array[ODTape]:
	var a := S.record_take(level, 0, 1.0, tape_a_script())
	var b := S.record_take(level, 1, 2.0, tape_b_script(), [a.tape])
	var out: Array[ODTape] = [a.tape, b.tape]
	return out


# ───────────────────────────── goldens as fixtures ─────────────────────────────


## A golden scenario run through the shipped core.
class GoldenRun:
	extends RefCounted
	var name: String = ""
	var level: LevelDef = null
	var loadout: ResolvedLoadout = null
	## Tapes in take order: trajectory tapes as given, input takes as recorded by the port.
	var tapes: Array[ODTape] = []
	## One per input take, in take order (the live record-mode runs).
	var recordings: Array[TestScript.TakeResult] = []
	## The authoritative playback run of all tapes (null if the level could not be resolved).
	var resolution: Resolution = null
	var errors: Array[String] = []

	func tape(index: int) -> ODTape:
		for t: ODTape in tapes:
			if t.index == index:
				return t
		return null


static func golden_json(name: String) -> Dictionary:
	var errors: Array[String] = []
	var d: Variant = ODJson.read_file("res://tests/goldens/%s.json" % name, errors)
	return d if d is Dictionary else {}


static func _input_from_tuple(t: Array) -> PlayerInput:
	var inp := PlayerInput.make(float(t[0]), float(t[1]), float(t[2]))
	for b: Variant in (t[3] as Array):
		inp.set(String(b), true)
	return inp


## Load a golden's level / loadout / takes, record its input takes through ODSim (against the tapes
## available so far, with the golden's boss memory input if any) and resolve the lot with ODResolve.
## `only_takes` (>= 0) stops after that many takes.
static func golden_run(name: String, only_takes: int = -1) -> GoldenRun:
	var g := golden_json(name)
	var r := GoldenRun.new()
	r.name = name
	if g.is_empty():
		r.errors.append("golden %s not found" % name)
		return r
	r.level = LevelDef.from_dict(ODJson.dict(g, "level"), r.errors)
	r.loadout = ResolvedLoadout.from_dict(ODJson.dict(ODJson.dict(g, "loadout"), "resolved"))
	var recs: Array = ODJson.array(ODJson.dict(g, "expected"), "recordings")
	var takes: Array = ODJson.array(g, "takes")
	for k: int in takes.size():
		if only_takes >= 0 and k >= only_takes:
			break
		var take: Dictionary = takes[k]
		if ODJson.string(take, "source") == "tape":
			var t := ODTape.from_dict(take.get("tape"), r.errors)
			if t != null:
				r.tapes.append(t)
			continue
		var mem: BossMemory = null
		for rec: Variant in recs:
			if rec is Dictionary and ODJson.integer(rec, "take", -1) == k and rec.get("bossMemory") is Dictionary:
				mem = BossMemory.from_dict(rec["bossMemory"])
		var prior: Array[ODTape] = r.tapes.duplicate()
		var cfg := SimConfig.make(
			r.level, r.loadout, prior, LiveTake.make(ODJson.integer(take, "index"), ODJson.num(take, "speed", 1.0), OD.end_mode_from_name(ODJson.string(take, "endMode", "stop"))), mem
		)
		var sim := ODSim.create_sim(cfg, r.errors)
		if sim == null:
			return r
		var tr := TestScript.TakeResult.new()
		tr.sim = sim
		for inp: Variant in ODJson.array(take, "inputs"):
			sim.step_local_tick(_input_from_tuple(inp))
			tr.frames.append(sim.snapshot())
			tr.events.append_array(sim.drain_events())
		tr.tape = sim.live_tape()
		tr.outcome = sim.outcome()
		r.recordings.append(tr)
		r.tapes.append(tr.tape)
	var res_mem: BossMemory = null
	var res_d := ODJson.dict(ODJson.dict(g, "expected"), "resolution")
	if res_d.get("bossMemory") is Dictionary:
		res_mem = BossMemory.from_dict(res_d["bossMemory"])
	r.resolution = ODResolve.resolve_encounter(SimConfig.make(r.level, r.loadout, r.tapes, null, res_mem), Callable(), null, r.errors)
	return r


## Resolve a level with explicit tapes (and optional loadout / boss memory) through ODResolve.
static func resolve(level: LevelDef, tapes: Array[ODTape], loadout: ResolvedLoadout = null, mem: BossMemory = null) -> Resolution:
	var errors: Array[String] = []
	var lo := loadout if loadout != null else TestLoadout.base_loadout()
	var res := ODResolve.resolve_encounter(SimConfig.make(level, lo, tapes, null, mem), Callable(), null, errors)
	if res == null:
		push_error("acceptance resolve: %s" % ", ".join(errors))
	return res


# ───────────────────────────── event helpers ─────────────────────────────


static func events_of(events: Array[SimEvent], type: StringName, tape: int = -1, id: String = "") -> Array[SimEvent]:
	return S.events_of(events, type, tape, id)


static func first_event(events: Array[SimEvent], type: StringName, tape: int = -1, id: String = "") -> SimEvent:
	var l := S.events_of(events, type, tape, id)
	return l[0] if not l.is_empty() else null


## (sub, type, tape, id, detail) rows of a list of events, for exact comparison.
static func event_rows(events: Array[SimEvent]) -> Array:
	var out: Array = []
	for e: SimEvent in events:
		out.append("%d|%s|%d|%s|%s" % [e.sub, e.type, e.tape, e.id, e.detail])
	return out


static func frames_json(frames: Array[FrameSnapshot]) -> Array:
	var out: Array = []
	for f: FrameSnapshot in frames:
		out.append(f.to_dict())
	return out


# ───────────────────────────── GameSession driver ─────────────────────────────

const STEP: float = 1.0 / 60.0


static func new_session(level: LevelDef, loadout: ResolvedLoadout = null, skip_briefing: bool = true) -> GameSession:
	var errors: Array[String] = []
	var s := GameSession.create(level, loadout if loadout != null else TestLoadout.base_loadout(), skip_briefing, false, errors)
	if s == null:
		push_error("GameSession.create failed: %s" % ", ".join(errors))
	return s


## Advance wall time in 1/60 s frames until the phase changes (bounded). False if it never did.
static func advance_until_phase_changes(s: GameSession, max_seconds: float = 120.0) -> bool:
	var start := s.phase
	var t := 0.0
	while t < max_seconds and s.phase == start:
		s.advance(STEP)
		t += STEP
	return s.phase != start


static func no_input() -> PlayerInput:
	return PlayerInput.make(0.0, 0.0, 0.0)


static func all_buttons() -> PlayerInput:
	var p := PlayerInput.make(1.0, 1.0, 1.0)
	for b: String in ["light", "heavy", "dodge", "ranged", "interact", "ability"]:
		p.set(b, true)
	return p


## record -> count-in -> feed the script tick by tick until the take ends. Returns the live events.
static func record_with(s: GameSession, sc: TestScript.InputScript = null) -> Array[SimEvent]:
	var events: Array[SimEvent] = []
	if not s.act(SessionAction.RECORD):
		push_error("record not offered in %s" % s.phase)
		return events
	advance_until_phase_changes(s, 10.0)
	if s.phase != SessionPhase.RECORDING:
		push_error("expected recording, got %s" % s.phase)
		return events
	var tick := 0
	while s.phase == SessionPhase.RECORDING:
		s.tick_local(sc.input(tick) if sc != null else no_input())
		events.append_array(s.drain_events())
		tick += 1
		if tick > 100000:
			push_error("recording never ended")
			break
	return events


static func set_speed(s: GameSession, speed: float) -> bool:
	var i := 0
	while i < 8 and s.speed != speed:
		s.act(SessionAction.SPEED_UP if s.speed < speed else SessionAction.SPEED_DOWN)
		i += 1
	return s.speed == speed


## Record tape A on the rescue room and play its review through to the decision.
static func take_a_to_decision(s: GameSession) -> bool:
	record_with(s, tape_a_script())
	if s.phase != SessionPhase.REVIEW:
		return false
	advance_until_phase_changes(s)
	return s.phase == SessionPhase.DECISION
