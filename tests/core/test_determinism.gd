extends ODTest
## Determinism and isolation of the simulation (ARCHITECTURE "One clock", "Authoritative result";
## docs/GODOT-PORT.md "Tests").
##
##  - The same config and inputs give identical events, snapshots (every field, including the ones the
##    goldens leave out), outcomes and recorded tapes, run after run.
##  - Nothing leaks between sims: sims created back to back, sims stepped interleaved substep by
##    substep, a recording sim followed by (or interleaved with) resolve_encounter, and resolves on
##    two worker threads at once all give exactly what a sim run alone gives. Module-level / static
##    scratch is the usual culprit; the only static state in core is the type registries and
##    read-only tuning, which test_static_state_is_registries_only pins down.
##  - resolve_encounter never mutates its config.
##
## The configs come from the golden fixtures (tests/goldens), which between them reach every enemy,
## weapon, ability, mechanism, trap and tape mode.

const DIR := "res://tests/goldens"

## Rich playback scenarios: boss memory, drones (flight planner in mem), missiles, mixed tape modes,
## desync detours, mechanisms, beatSight, traps (crusher solidity in the grid, relay schedules, belt
## carry state, telegraph scratch).
const PLAYBACK := [
	"boss-memory-exploited",
	"enemy-drone-fire",
	"missile-scenario-f-target-change",
	"tapemode-mixed-four",
	"desync-scenario-j",
	"mech-plate-holds-laser-off",
	"ability-beat-sight",
	"enemy-shielder-two-pairs-kill",
	"trap-gauntlet",
	"trap-relay-modes",
	"trap-crusher-stroke",
]
## Scenarios with live takes (recording through the player controller).
## The trap takes put belt carry and bumper launch (Traps.live_carry) through the controller.
const RECORDING := ["sandbox-bot-two-cassettes", "gear-abilities-catalogue", "record-busy-death", "ability-kill-refresh", "trap-gauntlet", "trap-bumper-live", "trap-conveyor-live-ride"]

## Static vars that may exist in core: registries filled once, and read-only tuning / constants.
const ALLOWED_STATICS := {
	"core/actors.gd": ["OBSTRUCTION_RADIUS"],
	"core/path.gd": ["_NDC", "_NDR"],
	"core/player.gd": ["_PHASE_OPTS"],
	"core/enemies/registry.gd": ["_registry", "_filled", "_overrides"],
	"core/projectiles.gd": ["_archetypes", "_filled"],
	"core/sim.gd": ["_ability_handlers", "_handlers_filled"],
	"core/tuning.gd": ["BASE", "ENEMY_STATS"],
	# Presentation only: the accessibility colour set. The simulation never reads a colour.
	"core/types.gd": ["_tape_palette"],
	"core/weapons/index.gd": ["_self_weapons"],
}


func before_each() -> void:
	ODCore.ensure_registered()


# ───────────────────────────── fixtures ─────────────────────────────


class Scenario:
	extends RefCounted
	var name: String = ""
	var level: LevelDef = null
	var loadout: ResolvedLoadout = null
	## Every take's tape as the golden has it (recorded takes use the golden's recorded tape).
	var tapes: Array[ODTape] = []
	var memory: BossMemory = null
	## The first live take: the tapes before it, its LiveTake, its inputs and its boss memory.
	var rec_tapes: Array[ODTape] = []
	var rec_live: LiveTake = null
	var rec_inputs: Array[PlayerInput] = []
	var rec_memory: BossMemory = null

	func config() -> SimConfig:
		return SimConfig.make(level, loadout, tapes.duplicate(), null, memory)

	func rec_config() -> SimConfig:
		return SimConfig.make(level, loadout, rec_tapes.duplicate(), rec_live, rec_memory)


func _scenario(name: String) -> Scenario:
	var g: Dictionary = load_json("%s/%s.json" % [DIR, name])
	var sc := Scenario.new()
	sc.name = name
	sc.level = LevelDef.from_dict(g.level)
	sc.loadout = ResolvedLoadout.from_dict(g.loadout.resolved)
	var recs: Dictionary = {}
	for r: Variant in g.expected.recordings:
		recs[int(r.take)] = r
	var takes: Array = g.takes
	for k: int in takes.size():
		var take: Dictionary = takes[k]
		if take.source == "tape":
			sc.tapes.append(ODTape.from_dict(take.tape))
			continue
		if sc.rec_live == null:
			sc.rec_tapes = sc.tapes.duplicate()
			sc.rec_live = LiveTake.make(int(take.index), float(take.speed), OD.end_mode_from_name(String(take.endMode)))
			var mem: Variant = recs[k].bossMemory
			sc.rec_memory = BossMemory.from_dict(mem) if mem is Dictionary else null
			for v: Variant in take.inputs:
				var i := PlayerInput.make(float(v[0]), float(v[1]), float(v[2]))
				for b: Variant in v[3]:
					i.set(String(b), true)
				sc.rec_inputs.append(i)
		sc.tapes.append(ODTape.from_dict(recs[k].tape))
	var m: Variant = g.expected.resolution.bossMemory
	sc.memory = BossMemory.from_dict(m) if m is Dictionary else null
	return sc


## Everything a run produced, as plain data (full snapshots, not just the golden fields).
class Trace:
	extends RefCounted
	var events: Array = []
	var frames: Array = []
	var outcome: Dictionary = {}
	var tape: Dictionary = {}


## A playback sim, stepped by the caller through step().
class Runner:
	extends RefCounted
	var sim: ODSim
	var trace := Trace.new()
	var _inputs: Array[PlayerInput] = []
	var _k := 0

	func _init(config: SimConfig, inputs: Array[PlayerInput] = []) -> void:
		var errors: Array[String] = []
		sim = ODSim.create_sim(config, errors)
		assert(sim != null, str(errors))
		_inputs = inputs
		trace.frames.append(sim.snapshot().to_dict())

	func finished() -> bool:
		return _k >= _inputs.size() if sim.config.live != null else sim.sub >= sim.horizon_subs

	## One substep (playback) or one local tick (recording).
	func step() -> void:
		if sim.config.live != null:
			sim.step_local_tick(_inputs[_k])
			_k += 1
		else:
			sim.step_sub()
		for e: SimEvent in sim.drain_events():
			trace.events.append(e.to_dict())
		trace.frames.append(sim.snapshot().to_dict())
		if finished():
			trace.outcome = sim.outcome().to_dict()
			if sim.config.live != null:
				trace.tape = sim.live_tape().to_dict()

	func run() -> Trace:
		while not finished():
			step()
		return trace


func _play(sc: Scenario) -> Trace:
	return Runner.new(sc.config()).run()


func _record(sc: Scenario) -> Trace:
	return Runner.new(sc.rec_config(), sc.rec_inputs).run()


func _resolve(config: SimConfig) -> Trace:
	var r := ODResolve.resolve_encounter(config)
	var t := Trace.new()
	for e: SimEvent in r.events:
		t.events.append(e.to_dict())
	for f: FrameSnapshot in r.frames:
		t.frames.append(f.to_dict())
	t.outcome = r.outcome.to_dict()
	return t


## Exact equality of two traces; names the first difference.
func _same(a: Trace, b: Trace, label: String) -> bool:
	if not assert_eq(a.events.size(), b.events.size(), label + ": event count"):
		return false
	for i: int in a.events.size():
		if not ODJson.deep_equal(a.events[i], b.events[i]):
			return assert_json_eq(a.events[i], b.events[i], 0.0, "%s: event %d" % [label, i])
	if not assert_eq(a.frames.size(), b.frames.size(), label + ": frame count"):
		return false
	for i: int in a.frames.size():
		if not ODJson.deep_equal(a.frames[i], b.frames[i]):
			return assert_json_eq(a.frames[i], b.frames[i], 0.0, "%s: frame %d (sub %s)" % [label, i, a.frames[i].sub])
	return assert_json_eq(a.outcome, b.outcome, 0.0, label + ": outcome") and assert_json_eq(a.tape, b.tape, 0.0, label + ": recorded tape")


# ───────────────────────────── tests ─────────────────────────────


func test_same_config_twice_gives_identical_runs() -> void:
	for name: String in PLAYBACK:
		var sc := _scenario(name)
		var a := _play(sc)
		var b := _play(sc)
		assert_true(a.events.size() > 0, name + ": the run has events")
		_same(a, b, name + " (stepped twice)")
		_same(_resolve(sc.config()), _resolve(sc.config()), name + " (resolve_encounter twice)")


func test_same_inputs_twice_record_identical_takes() -> void:
	for name: String in RECORDING:
		var sc := _scenario(name)
		assert_true(sc.rec_inputs.size() > 0, name + ": has a live take")
		var a := _record(sc)
		var b := _record(sc)
		assert_true(not a.tape.is_empty(), name + ": a tape was recorded")
		_same(a, b, name + " (recorded twice)")


func test_sims_created_back_to_back_do_not_leak_state() -> void:
	var names: Array = PLAYBACK.duplicate()
	var first: Dictionary = {}
	for name: String in names:
		first[name] = _play(_scenario(name))
	# The same scenarios again in the reverse order: each sim now follows a different predecessor.
	names.reverse()
	for name: String in names:
		_same(first[name], _play(_scenario(name)), name + " (after other sims)")


func test_interleaved_sims_do_not_share_state() -> void:
	var a := _scenario("enemy-drone-fire")
	var b := _scenario("boss-memory-exploited")
	var c := _scenario("missile-scenario-f-target-change")
	var solo := [_play(a), _play(b), _play(c)]
	var runners := [Runner.new(a.config()), Runner.new(b.config()), Runner.new(c.config())]
	var busy := true
	while busy:
		busy = false
		for r: Runner in runners:
			if not r.finished():
				r.step()
				busy = true
	for i: int in 3:
		_same(solo[i], runners[i].trace, "%s (interleaved with two other sims)" % [[a, b, c][i].name])


func test_recording_and_resolve_do_not_leak_into_each_other() -> void:
	for name: String in RECORDING:
		var sc := _scenario(name)
		var resolve_fresh := _resolve(sc.config())
		var rec_fresh := _record(sc)
		# A resolve right after a recording sim, and a recording right after a resolve.
		_same(resolve_fresh, _resolve(sc.config()), name + ": resolve after a recording")
		_same(rec_fresh, _record(sc), name + ": recording after a resolve")
		# The recording sim and a playback sim of the full encounter, stepped in lockstep.
		var rec := Runner.new(sc.rec_config(), sc.rec_inputs)
		var play := Runner.new(sc.config())
		while not rec.finished() or not play.finished():
			if not rec.finished():
				rec.step()
			for k: int in 4:
				if not play.finished():
					play.step()
		_same(rec_fresh, rec.trace, name + ": recording interleaved with playback")
		var play_solo := _play(sc)
		_same(play_solo, play.trace, name + ": playback interleaved with recording")
		# resolve_encounter (frames every 4 substeps) agrees with the stepped run.
		var k := 0
		for f: Variant in resolve_fresh.frames:
			while k < play_solo.frames.size() and int(play_solo.frames[k].sub) != int(f.sub):
				k += 1
			if not assert_true(k < play_solo.frames.size(), name + ": resolve frame %s exists in the stepped run" % f.sub):
				break
			if not assert_json_eq(f, play_solo.frames[k], 0.0, name + ": resolve frame at sub %s" % f.sub):
				break
		assert_json_eq(resolve_fresh.events, play_solo.events, 0.0, name + ": resolve events equal the stepped run's")


func test_resolve_does_not_mutate_its_config() -> void:
	for name: String in ["boss-memory-exploited", "tapemode-mixed-four", "sandbox-bot-two-cassettes"]:
		var sc := _scenario(name)
		var config := sc.config()
		var before := config.to_dict()
		ODResolve.resolve_encounter(config)
		assert_json_eq(config.to_dict(), before, 0.0, name + ": config unchanged by resolve_encounter")
		var rc := sc.rec_config() if sc.rec_live != null else null
		if rc != null:
			var rb := rc.to_dict()
			_record(sc)
			assert_json_eq(rc.to_dict(), rb, 0.0, name + ": recording config unchanged by recording")


func test_concurrent_resolves_on_worker_threads_match() -> void:
	var a := _scenario("boss-memory-exploited")
	var b := _scenario("enemy-drone-fire")
	var ra := _resolve(a.config())
	var rb := _resolve(b.config())
	var ta := Thread.new()
	var tb := Thread.new()
	ta.start(ODResolve.resolve_encounter.bind(a.config().deep_copy()))
	tb.start(ODResolve.resolve_encounter.bind(b.config().deep_copy()))
	var resolutions := [ta.wait_to_finish(), tb.wait_to_finish()]
	var expected := [ra, rb]
	for i: int in 2:
		var r: Resolution = resolutions[i]
		if not assert_true(r != null, "thread %d resolved" % i):
			continue
		var t := Trace.new()
		for e: SimEvent in r.events:
			t.events.append(e.to_dict())
		for f: FrameSnapshot in r.frames:
			t.frames.append(f.to_dict())
		t.outcome = r.outcome.to_dict()
		_same(expected[i], t, "worker thread %d" % i)


func test_static_state_is_registries_only() -> void:
	var found := {}
	var files: Array[String] = []
	_collect("res://core", files)
	var re := RegEx.create_from_string("(?m)^\\s*static\\s+var\\s+(\\w+)")
	for path: String in files:
		var text := FileAccess.get_file_as_string(path)
		var rel := path.trim_prefix("res://")
		for m: RegExMatch in re.search_all(text):
			var allowed: Array = ALLOWED_STATICS.get(rel, [])
			assert_true(allowed.has(m.get_string(1)), "%s: static var %s is a known registry or constant (per-run state must live in the sim)" % [rel, m.get_string(1)])
			found["%s:%s" % [rel, m.get_string(1)]] = true
	var listed := 0
	for k: String in ALLOWED_STATICS:
		listed += (ALLOWED_STATICS[k] as Array).size()
	assert_eq(found.size(), listed, "every allowed static var still exists")


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for d: String in dir.get_directories():
		_collect(dir_path + "/" + d, out)
	for f: String in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path + "/" + f)
