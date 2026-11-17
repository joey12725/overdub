extends ODTest
## Golden runner: every tests/goldens/*.json scenario, replayed through the port, must reproduce the
## prototype (tests/goldens/README.md "How to replay a golden" and "Comparison tolerance").
##
## For each scenario:
##   - the level, the resolved loadout and every take are rebuilt from the file;
##   - an `inputs` take is recorded live: the port's PlayerController runs one PlayerInput per local
##     tick through ODSim.step_local_tick, and the recording's events, sampled snapshots, provisional
##     outcome and recorded tape are compared with the golden's;
##   - later stages use the GOLDEN recorded tape (so a recording mismatch is reported once);
##   - the authoritative playback run is stepped to the horizon and its events, sampled snapshots
##     (sub 0, every 60 substeps, the horizon; plus threatBeats with beatSight, as the exporter adds
##     them to resolution snapshots only) and outcome compared;
##   - the resolution is also produced by ODResolve.resolve_encounter and must equal the stepped run
##     exactly (same events, same outcome, same sampled frames), so the public entry point is covered;
##   - when the golden names catalogue gear, LoadoutRules.resolve_loadout(gear) must equal the
##     resolved loadout; when it names bossMemoryFrom, BossMemoryLib.build_boss_memory must rebuild
##     every stage's memory.
##
## Tolerances (README): positions, event x/y/power, phase.tick, mech t / warn / reach, objective
## progress, beat and threatBeats within 1e-3; angles (facing, event dir, projectile dir, trap mech
## dir) within 1e-3 rad, wrapped; everything else exact. Recorded tapes: pose samples within 1e-3, event vx/vy within 1e-2.
##
## Tolerated exceptions go in TOLERATED (scenario -> [{path, reason}]); a divergence whose path
## starts with a listed prefix is reported as tolerated instead of failing. It is empty: every
## scenario matches the prototype.
##
## Diagnose one scenario: OD_GOLDEN=<name> bash tools/gd test test_goldens

const DIR := "res://tests/goldens"
const INDEX := DIR + "/index.json"
const SAMPLE_SUBS: int = 60

const POS_EPS: float = 1e-3
const ANGLE_EPS: float = 1e-3
const TAPE_VEL_EPS: float = 1e-2
const GEAR_EPS: float = 1e-9
const MEMORY_EPS: float = 1e-6
## At most this many divergences are listed per scenario (the first one is what matters).
const MAX_DIFFS: int = 8

## Keys compared within POS_EPS.
const NEAR_KEYS: Array[String] = ["x", "y", "z", "power", "tick", "t", "warn", "reach", "progress", "beat", "threatBeats"]
## Keys compared as wrapped angles within ANGLE_EPS (except phase.dir, an int).
const ANGLE_KEYS: Array[String] = ["facing", "dir"]
## Port snapshot keys the goldens leave out on purpose (README "Snapshot").
const OMITTED: Dictionary = {"actors": ["vx", "vy"], "enemies": ["facing", "stateT"]}
const BUTTONS: Array[String] = ["light", "heavy", "dodge", "ranged", "interact", "ability"]

## Scenario -> Array of {"path": String prefix, "reason": String}. Empty: no tolerated exceptions.
const TOLERATED: Dictionary = {}

var _catalogue: ContentData.GearCatalogue = null
## Values compared, and the largest in-tolerance differences seen (reported per run).
var _leaves: int = 0
var _worst_near: float = 0.0
var _worst_angle: float = 0.0


func test_every_golden_matches_the_port() -> void:
	ODCore.ensure_registered()
	var gear_errors: Array[String] = []
	_catalogue = ContentData.load_gear(gear_errors)
	assert_eq(gear_errors, [], "gear catalogue loads")
	var index: Variant = load_json(INDEX)
	if not assert_true(index is Dictionary, "index.json loads"):
		return
	var only := OS.get_environment("OD_GOLDEN")
	var scenarios: Array = (index as Dictionary).get("scenarios", [])
	var ran := 0
	var matched := 0
	var tolerated_total := 0
	var failed: Array[String] = []
	var t0 := Time.get_ticks_msec()
	_leaves = 0
	_worst_near = 0.0
	_worst_angle = 0.0
	for e: Variant in scenarios:
		var entry: Dictionary = e
		var name: String = entry.get("name", "?")
		if not only.is_empty() and name != only:
			continue
		var g: Variant = load_json(DIR + "/" + String(entry.get("file", "")))
		if not assert_true(g is Dictionary, name + ": golden loads"):
			continue
		ran += 1
		var diffs: Array[String] = []
		_run_golden(g, diffs)
		var tolerated := _apply_tolerances(name, diffs)
		tolerated_total += tolerated.size()
		for t: String in tolerated:
			print("    [golden] %s: tolerated %s" % [name, t])
		if diffs.is_empty():
			matched += 1
		else:
			failed.append(name)
			print("    [golden] %s DIVERGES:" % name)
			for d: String in diffs.slice(0, MAX_DIFFS):
				print("        " + d)
		assert_eq(diffs.size(), 0, "%s matches the prototype%s" % [name, "" if diffs.is_empty() else ": " + diffs[0]])
	if only.is_empty():
		assert_eq(ran, scenarios.size(), "every listed scenario ran")
		assert_true(ran >= 163, "all 163 goldens present (140 + 22 trap scenarios + the dead-signal scenario)")
	else:
		assert_eq(ran, 1, "OD_GOLDEN names a scenario")
	print("    [golden] %d scenario(s): %d match, %d diverge, %d tolerated difference(s); %d values compared; worst |d| %s (positions etc.), %s rad (angles); %d ms" % [ran, matched, failed.size(), tolerated_total, _leaves, String.num_scientific(_worst_near), String.num_scientific(_worst_angle), Time.get_ticks_msec() - t0])
	assert_true(_leaves > 100000, "the runner compares the goldens' values (%d)" % _leaves)
	if not failed.is_empty():
		print("    [golden] diverging: " + ", ".join(failed))


## Every tolerated exception names a scenario that exists and gives a reason.
func test_tolerated_exceptions_are_documented() -> void:
	var index: Variant = load_json(INDEX)
	var names := {}
	for e: Variant in (index as Dictionary).get("scenarios", []):
		names[(e as Dictionary).get("name", "")] = true
	assert_true(true, "tolerance table checked")
	for name: String in TOLERATED:
		assert_true(names.has(name), "tolerated scenario %s exists" % name)
		for t: Variant in TOLERATED[name]:
			assert_true(String((t as Dictionary).get("reason", "")).length() > 20, "%s: tolerance has a reason" % name)


## The runner is not vacuous: a golden edited beyond tolerance in each kind of field fails, and one
## edited within tolerance still passes.
func test_runner_detects_divergences() -> void:
	ODCore.ensure_registered()
	var base: Variant = load_json(DIR + "/enemy-grunt-target-switch.json")
	if not assert_true(base is Dictionary, "golden loads"):
		return
	var clean: Array[String] = []
	_run_golden(base, clean)
	assert_eq(clean, [], "unedited golden matches")
	var edits: Array[Callable] = [
		func(r: Dictionary) -> String:
			r.events[0].x = float(r.events[0].x) + 0.01
			return "event x",
		func(r: Dictionary) -> String:
			r.events[0].sub = int(r.events[0].sub) + 1
			return "event sub",
		func(r: Dictionary) -> String:
			r.events.pop_back()
			return "event count",
		func(r: Dictionary) -> String:
			r.snapshots[3].actors[0].y = float(r.snapshots[3].actors[0].y) - 0.002
			return "actor y",
		func(r: Dictionary) -> String:
			r.snapshots[3].actors[0].facing = float(r.snapshots[3].actors[0].facing) + 0.01
			return "actor facing",
		func(r: Dictionary) -> String:
			r.snapshots[2].enemies[0].hp = int(r.snapshots[2].enemies[0].hp) + 1
			return "enemy hp",
		func(r: Dictionary) -> String:
			r.snapshots[2].enemies[0].erase("target")
			return "optional key",
		func(r: Dictionary) -> String:
			r.outcome.win = not bool(r.outcome.win)
			return "outcome win",
	]
	for edit: Callable in edits:
		var g: Dictionary = (base as Dictionary).duplicate(true)
		var what: String = edit.call(g.expected.resolution)
		var diffs: Array[String] = []
		_run_golden(g, diffs)
		assert_true(diffs.size() > 0, "an edited %s is caught" % what)
	var within: Dictionary = (base as Dictionary).duplicate(true)
	var snap: Dictionary = within.expected.resolution.snapshots[3]
	snap.actors[0].x = float(snap.actors[0].x) + 5e-4
	snap.actors[0].facing = float(snap.actors[0].facing) + 2.0 * PI - 5e-4
	var ok: Array[String] = []
	_run_golden(within, ok)
	assert_eq(ok, [], "edits within tolerance (and a full turn of facing) pass")


# ───────────────────────────── one scenario ─────────────────────────────


func _run_golden(g: Dictionary, diffs: Array[String]) -> void:
	var errors: Array[String] = []
	var level := LevelDef.from_dict(g.get("level", {}), errors)
	if level == null or not errors.is_empty():
		diffs.append("level does not load: %s" % [errors])
		return
	var lo: Dictionary = g.get("loadout", {})
	var resolved: Dictionary = lo.get("resolved", {})
	var loadout := ResolvedLoadout.from_dict(resolved)
	var gear: Variant = lo.get("gear")
	if gear is Dictionary:
		var rl := LoadoutRules.resolve_loadout(Loadout.from_dict(gear), _catalogue)
		var mine := rl.to_dict()
		# `looks` (per-slot GearLook for the 3D model) is a port addition the prototype has no field for.
		mine.erase("looks")
		var d := ODJson.first_difference(mine, resolved, GEAR_EPS)
		if d != "":
			diffs.append("loadout.gear resolves differently: " + d)
	var memory_from: Variant = g.get("bossMemoryFrom")
	var takes: Array = g.get("takes", [])
	var expected: Dictionary = g.get("expected", {})
	var recordings: Array = expected.get("recordings", [])
	var tapes: Array[ODTape] = []
	for k: int in takes.size():
		var take: Dictionary = takes[k]
		if take.get("source") == "tape":
			var t := ODTape.from_dict(take.get("tape"), errors)
			if t == null:
				diffs.append("take %d: tape does not load: %s" % [k, errors])
				return
			tapes.append(t)
			continue
		var rec: Dictionary = {}
		for r: Variant in recordings:
			if int((r as Dictionary).get("take", -1)) == k:
				rec = r
		if rec.is_empty():
			diffs.append("take %d: no recording in the golden" % k)
			return
		var stage := "rec%d" % k
		var memory := _stage_memory(stage, level, tapes, memory_from, rec.get("bossMemory"), diffs)
		_run_recording(stage, level, loadout, tapes, take, rec, memory, diffs)
		var golden_tape := ODTape.from_dict(rec.get("tape"), errors)
		if golden_tape == null:
			diffs.append("%s: golden tape does not load: %s" % [stage, errors])
			return
		tapes.append(golden_tape)
	var res: Dictionary = expected.get("resolution", {})
	var mem := _stage_memory("resolution", level, tapes, memory_from, res.get("bossMemory"), diffs)
	_run_resolution(level, loadout, tapes, res, mem, diffs)


## The stage's BossMemory from the golden, checked against BossMemoryLib.build_boss_memory when the
## golden names the committed cassettes.
func _stage_memory(stage: String, level: LevelDef, tapes: Array[ODTape], memory_from: Variant, golden: Variant, diffs: Array[String]) -> BossMemory:
	var memory: BossMemory = BossMemory.from_dict(golden) if golden is Dictionary else null
	if memory_from is Array:
		var committed: Array[ODTape] = []
		for t: ODTape in tapes:
			if (memory_from as Array).has(float(t.index)) or (memory_from as Array).has(t.index):
				committed.append(t)
		var built := BossMemoryLib.build_boss_memory(level, committed)
		if golden is Dictionary:
			var d := ODJson.first_difference(built.to_dict(), golden, MEMORY_EPS)
			if d != "":
				diffs.append("%s.bossMemory rebuilt differently: %s" % [stage, d])
		elif built != null and not built.observed.is_empty():
			diffs.append("%s.bossMemory: golden has none, port builds %d observation(s)" % [stage, built.observed.size()])
	return memory


func _run_recording(stage: String, level: LevelDef, loadout: ResolvedLoadout, tapes: Array[ODTape], take: Dictionary, rec: Dictionary, memory: BossMemory, diffs: Array[String]) -> void:
	var live := LiveTake.make(int(take.get("index", 0)), float(take.get("speed", 1.0)), OD.end_mode_from_name(String(take.get("endMode", "stop"))))
	var errors: Array[String] = []
	var sim := ODSim.create_sim(SimConfig.make(level, loadout, tapes.duplicate(), live, memory), errors)
	if sim == null:
		diffs.append("%s: create_sim failed: %s" % [stage, errors])
		return
	var snaps: Array = [_snap(sim, false)]
	var events: Array = []
	var input := PlayerInput.new()
	for v: Variant in take.get("inputs", []):
		_fill_input(input, v)
		sim.step_local_tick(input)
		for ev: SimEvent in sim.drain_events():
			events.append(ev.to_dict())
		if sim.sub % SAMPLE_SUBS == 0:
			snaps.append(_snap(sim, false))
	if sim.sub % SAMPLE_SUBS != 0:
		snaps.append(_snap(sim, false))
	_cmp_events(stage + ".events", rec.get("events", []), events, diffs)
	_cmp_snapshots(stage + ".snapshots", rec.get("snapshots", []), snaps, diffs)
	_cmp_outcome(stage + ".outcome", rec.get("outcome", {}), sim.outcome(), diffs)
	var golden_tape := ODTape.from_dict(rec.get("tape"), errors)
	if golden_tape != null:
		_cmp_tape(stage + ".tape", golden_tape, sim.live_tape(), diffs)


func _run_resolution(level: LevelDef, loadout: ResolvedLoadout, tapes: Array[ODTape], res: Dictionary, memory: BossMemory, diffs: Array[String]) -> void:
	var errors: Array[String] = []
	var config := SimConfig.make(level, loadout, tapes.duplicate(), null, memory)
	var sim := ODSim.create_sim(config, errors)
	if sim == null:
		diffs.append("resolution: create_sim failed: %s" % [errors])
		return
	var h := int(res.get("horizonSubs", -1))
	if sim.horizon_subs != h:
		diffs.append("resolution.horizonSubs: expected %d, port %d" % [h, sim.horizon_subs])
		return
	var snaps: Array = [_snap(sim, true)]
	var events: Array = []
	var raw_events: Array[SimEvent] = []
	while sim.sub < h:
		sim.step_sub()
		for ev: SimEvent in sim.drain_events():
			raw_events.append(ev)
			events.append(ev.to_dict())
		if sim.sub % SAMPLE_SUBS == 0 or sim.sub == h:
			snaps.append(_snap(sim, true))
	_cmp_events("resolution.events", res.get("events", []), events, diffs)
	_cmp_snapshots("resolution.snapshots", res.get("snapshots", []), snaps, diffs)
	var outcome := sim.outcome()
	_cmp_outcome("resolution.outcome", res.get("outcome", {}), outcome, diffs)
	# The public entry point gives exactly the stepped run.
	var r := ODResolve.resolve_encounter(config, Callable(), null, errors)
	if r == null:
		diffs.append("resolve_encounter failed: %s" % [errors])
		return
	if r.events.size() != raw_events.size():
		diffs.append("resolve_encounter: %d events, stepped run %d" % [r.events.size(), raw_events.size()])
	else:
		for i: int in raw_events.size():
			if not ODJson.deep_equal(r.events[i].to_dict(), raw_events[i].to_dict()):
				diffs.append("resolve_encounter: event %d differs from the stepped run" % i)
				break
	if not ODJson.deep_equal(r.outcome.to_dict(), outcome.to_dict()):
		diffs.append("resolve_encounter: outcome differs from the stepped run")
	var k := 0
	for f: FrameSnapshot in r.frames:
		if f.sub % SAMPLE_SUBS != 0 and f.sub != h:
			continue
		var mine: Dictionary = snaps[k] if k < snaps.size() else {}
		var theirs := f.to_dict()
		mine = mine.duplicate()
		mine.erase("threatBeats")
		if not ODJson.deep_equal(theirs, mine):
			diffs.append("resolve_encounter: frame at sub %d differs from the stepped run" % f.sub)
			break
		k += 1
	if k != snaps.size():
		diffs.append("resolve_encounter: %d sampled frames, stepped run %d" % [k, snaps.size()])


## Snapshot as a golden dict; `threat` adds threatBeats (the exporter does so for the resolution only,
## with beatSight).
func _snap(sim: ODSim, threat: bool) -> Dictionary:
	var d := sim.snapshot().to_dict()
	if threat and sim.loadout.has_ability(AbilityId.BEAT_SIGHT):
		var tb: Array = []
		for b: float in sim.threat_beats():
			tb.append(b)
		d["threatBeats"] = tb
	return d


func _fill_input(input: PlayerInput, v: Variant) -> void:
	var a: Array = v
	input.clear(float(a[2]))
	input.move_x = float(a[0])
	input.move_y = float(a[1])
	for b: Variant in a[3]:
		match String(b):
			"light":
				input.light = true
			"heavy":
				input.heavy = true
			"dodge":
				input.dodge = true
			"ranged":
				input.ranged = true
			"interact":
				input.interact = true
			"ability":
				input.ability = true

# ───────────────────────────── comparison ─────────────────────────────


func _cmp_events(path: String, expected: Array, actual: Array, diffs: Array[String]) -> void:
	var n := mini(expected.size(), actual.size())
	for i: int in n:
		var before := diffs.size()
		_cmp("%s[%d]" % [path, i], "events", "", expected[i], actual[i], diffs)
		if diffs.size() > before:
			diffs.insert(before, "%s: first divergence at event %d: golden %s | port %s" % [path, i, JSON.stringify(expected[i]), JSON.stringify(actual[i])])
			return
	if expected.size() != actual.size():
		var extra: Variant = actual[n] if actual.size() > n else expected[n]
		diffs.append("%s: golden has %d events, port %d (first unmatched: %s %s)" % [path, expected.size(), actual.size(), "port" if actual.size() > n else "golden", JSON.stringify(extra)])


func _cmp_snapshots(path: String, expected: Array, actual: Array, diffs: Array[String]) -> void:
	if expected.size() != actual.size():
		diffs.append("%s: golden has %d snapshots, port %d" % [path, expected.size(), actual.size()])
	for i: int in mini(expected.size(), actual.size()):
		var before := diffs.size()
		_cmp("%s[sub %s]" % [path, str(int((expected[i] as Dictionary).get("sub", -1)))], "snapshot", "", expected[i], actual[i], diffs)
		if diffs.size() > before:
			return  # the first diverging snapshot is the useful one


func _cmp_outcome(path: String, expected: Dictionary, actual: Outcome, diffs: Array[String]) -> void:
	_cmp(path, "outcome", "", expected, actual.to_dict(), diffs)


func _cmp_tape(path: String, g: ODTape, p: ODTape, diffs: Array[String]) -> void:
	if p == null:
		diffs.append(path + ": port has no live tape")
		return
	if g.index != p.index or g.speed != p.speed or g.end_mode != p.end_mode or g.ticks != p.ticks:
		diffs.append("%s: header golden {%d, %s, %d, %d} port {%d, %s, %d, %d}" % [path, g.index, g.speed, g.end_mode, g.ticks, p.index, p.speed, p.end_mode, p.ticks])
		return
	if g.anim != p.anim:
		for i: int in g.anim.size():
			if g.anim[i] != p.anim[i]:
				diffs.append("%s.anim[%d]: golden %d, port %d" % [path, i, g.anim[i], p.anim[i]])
				break
	for i: int in g.pos.size():
		if absf(g.pos[i] - p.pos[i]) > POS_EPS:
			diffs.append("%s.pos[tick %d].%s: golden %s, port %s" % [path, i / 2, "x" if i % 2 == 0 else "y", g.pos[i], p.pos[i]])
			break
	for i: int in g.facing.size():
		if absf(TapeLib.angle_delta(g.facing[i], p.facing[i])) > ANGLE_EPS:
			diffs.append("%s.facing[%d]: golden %s, port %s" % [path, i, g.facing[i], p.facing[i]])
			break
	if g.events.size() != p.events.size():
		diffs.append("%s.events: golden %d, port %d" % [path, g.events.size(), p.events.size()])
		return
	for i: int in g.events.size():
		var a: TapeEvent = g.events[i]
		var b: TapeEvent = p.events[i]
		var ok := a.tick == b.tick and a.kind == b.kind
		ok = ok and absf(TapeLib.angle_delta(a.dir, b.dir)) <= ANGLE_EPS
		ok = ok and absf(a.x - b.x) <= POS_EPS and absf(a.y - b.y) <= POS_EPS
		ok = ok and absf(a.vx - b.vx) <= TAPE_VEL_EPS and absf(a.vy - b.vy) <= TAPE_VEL_EPS
		if not ok:
			diffs.append("%s.events[%d]: golden %s, port %s" % [path, i, a.to_tuple(), b.to_tuple()])
			return


## Compare golden value `e` with port value `a`; `key` is the field name (an array passes its own
## key to its elements), `parent` the enclosing field name.
func _cmp(path: String, key: String, parent: String, e: Variant, a: Variant, diffs: Array[String]) -> void:
	if e is Dictionary:
		if not a is Dictionary:
			diffs.append("%s: golden object, port %s" % [path, type_string(typeof(a))])
			return
		var ed: Dictionary = e
		var ad: Dictionary = a
		var omitted: Array = OMITTED.get(key, [])
		for k: Variant in ed:
			if not ad.has(k):
				diffs.append("%s.%s: missing in port (golden %s)" % [path, k, JSON.stringify(ed[k])])
			else:
				_cmp("%s.%s" % [path, k], String(k), key, ed[k], ad[k], diffs)
		for k: Variant in ad:
			if not ed.has(k) and not omitted.has(k):
				diffs.append("%s.%s: port has %s, golden has no such key" % [path, k, JSON.stringify(ad[k])])
		return
	if e is Array:
		if not a is Array:
			diffs.append("%s: golden array, port %s" % [path, type_string(typeof(a))])
			return
		var ea: Array = e
		var aa: Array = a
		if ea.size() != aa.size():
			diffs.append("%s: golden %d item(s) %s, port %d %s" % [path, ea.size(), _short(ea), aa.size(), _short(aa)])
			return
		for i: int in ea.size():
			_cmp("%s[%d]" % [path, i], key, parent, ea[i], aa[i], diffs)
		return
	if ODJson.is_number(e):
		if not ODJson.is_number(a):
			diffs.append("%s: golden %s, port %s" % [path, JSON.stringify(e), JSON.stringify(a)])
			return
		var ef := float(e)
		var af := float(a)
		_leaves += 1
		if ANGLE_KEYS.has(key) and parent != "phase":
			var da := absf(TapeLib.angle_delta(ef, af))
			_worst_angle = maxf(_worst_angle, da) if da <= ANGLE_EPS else _worst_angle
			if da > ANGLE_EPS:
				diffs.append("%s: golden %s, port %s (angle)" % [path, ef, af])
		elif NEAR_KEYS.has(key):
			_worst_near = maxf(_worst_near, absf(ef - af)) if absf(ef - af) <= POS_EPS else _worst_near
			if absf(ef - af) > POS_EPS:
				diffs.append("%s: golden %s, port %s (|d| %s)" % [path, ef, af, absf(ef - af)])
		elif ef != af:
			diffs.append("%s: golden %s, port %s" % [path, ef, af])
		return
	_leaves += 1
	if typeof(e) != typeof(a) or e != a:
		diffs.append("%s: golden %s, port %s" % [path, JSON.stringify(e), JSON.stringify(a)])


func _short(v: Array) -> String:
	var s := JSON.stringify(v)
	return s if s.length() <= 160 else s.substr(0, 157) + "..."


## Move tolerated divergences out of `diffs`; returns them.
func _apply_tolerances(name: String, diffs: Array[String]) -> Array[String]:
	var out: Array[String] = []
	if not TOLERATED.has(name):
		return out
	var keep: Array[String] = []
	for d: String in diffs:
		var hit := ""
		for t: Variant in TOLERATED[name]:
			if d.begins_with(String((t as Dictionary).get("path", "\u0000"))):
				hit = String((t as Dictionary).get("reason", ""))
		if hit.is_empty():
			keep.append(d)
		else:
			out.append("%s (%s)" % [d, hit])
	diffs.assign(keep)
	return out
