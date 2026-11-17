extends ODTest
## The golden fixtures (tests/goldens/README.md) are well-formed and load into the port's types.
##
## This suite checks the FILES, not the simulation: every scenario parses, its level, loadout, boss
## memory, tapes and events load through the types' from_dict() and round-trip, its inputs are
## well-formed, and its expected snapshots follow the sampling rule. The simulation comparison
## (replaying each scenario through ODSim / ODResolve) belongs to the core port's golden runner.
##
## Run with `bash tools/gd test goldens`.

const DIR := "res://tests/goldens"
const INDEX := DIR + "/index.json"
const BUTTONS := ["light", "heavy", "dodge", "ranged", "interact", "ability"]

var _index: Dictionary = {}
var _cache: Dictionary = {}


func _scenarios() -> Array:
	if _index.is_empty():
		var data: Variant = load_json(INDEX)
		if data is Dictionary:
			_index = data
	return _index.get("scenarios", [])


func _golden(entry: Dictionary) -> Dictionary:
	var file: String = entry.get("file", "")
	if not _cache.has(file):
		var data: Variant = load_json(DIR + "/" + file)
		_cache[file] = data if data is Dictionary else {}
	return _cache[file]


## Master substeps per beat and the horizon, from the level (time.ts subsPerBeat / horizonSubs).
func _horizon_subs(level: Dictionary) -> int:
	var spb := 240.0 * 60.0 / float(level.get("bpm", 120))
	return int(round(float(level.get("horizonBars", 0)) * 4.0 * spb))


func test_index_lists_every_file() -> void:
	var listed := {}
	if not assert_true(_scenarios().size() >= 40, "at least 40 scenarios"):
		return
	assert_eq(_index.get("format"), 1, "index format")
	assert_eq(_index.get("sampleSubs"), 60, "sample spacing")
	for e: Variant in _scenarios():
		var entry: Dictionary = e
		listed[entry.get("file", "")] = true
		assert_eq(entry.get("file"), String(entry.get("name", "")) + ".json", "file is <name>.json")
	var dir := DirAccess.open(DIR)
	if not assert_true(dir != null, "goldens directory opens"):
		return
	for f: String in dir.get_files():
		if f.ends_with(".json") and f != "index.json":
			assert_true(listed.has(f), "%s is listed in index.json" % f)
	assert_eq(listed.size(), _scenarios().size(), "no duplicate files")


func test_levels_and_loadouts_load() -> void:
	var gear_errors: Array[String] = []
	var catalogue := ContentData.load_gear(gear_errors)
	assert_eq(gear_errors, [], "gear catalogue loads")
	for e: Variant in _scenarios():
		var g := _golden(e)
		var label: String = g.get("name", "?")
		assert_eq(g.get("format"), 1, label + ": format")
		var errors: Array[String] = []
		var level := LevelDef.from_dict(g.get("level", {}), errors)
		if not assert_eq(errors, [], label + ": level loads"):
			continue
		assert_true(level != null and level.map.size() > 0 and level.bpm > 0, label + ": level has a map and tempo")
		var lo: Dictionary = g.get("loadout", {})
		var resolved: Dictionary = lo.get("resolved", {})
		var rl := ResolvedLoadout.from_dict(resolved)
		assert_json_eq(rl.to_dict(), resolved, 0.0, label + ": resolved loadout round-trips")
		var gear: Variant = lo.get("gear")
		if gear is Dictionary:
			for slot: StringName in GearSlot.ALL:
				var id: String = (gear as Dictionary).get(String(slot), "")
				assert_true(catalogue != null and catalogue.has_item(id), "%s: gear %s=%s is in data/gear.json" % [label, slot, id])
				assert_eq(id, resolved.get("loadout", {}).get(String(slot)), label + ": gear ids match the resolved loadout")
		else:
			assert_eq(gear, null, label + ": gear is null or a Loadout")


func test_takes_load() -> void:
	for e: Variant in _scenarios():
		var g := _golden(e)
		var label: String = g.get("name", "?")
		var used := {}
		for t: Variant in g.get("takes", []):
			var take: Dictionary = t
			var src: String = take.get("source", "")
			if src == "tape":
				var errors: Array[String] = []
				var tape := ODTape.from_dict(take.get("tape"), errors)
				if not assert_eq(errors, [], label + ": tape loads"):
					continue
				assert_json_eq(tape.to_dict(), take.get("tape"), 0.0, label + ": tape round-trips byte for byte")
				assert_false(used.has(tape.index), label + ": cassette indices are unique")
				used[tape.index] = true
			elif assert_eq(src, "inputs", label + ": take source"):
				var index := int(take.get("index", -1))
				assert_true(index >= 0 and index < OD.TAPE_COUNT, label + ": cassette index")
				assert_false(used.has(index), label + ": cassette indices are unique")
				used[index] = true
				assert_true(OD.is_speed(float(take.get("speed", 0))), label + ": speed")
				assert_true(OD.end_mode_from_name(String(take.get("endMode", ""))) >= 0, label + ": end mode")
				var inputs: Array = take.get("inputs", [])
				assert_true(inputs.size() > 0, label + ": inputs present")
				var bad := 0
				for i: Variant in inputs:
					if not (i is Array and (i as Array).size() == 4 and ODJson.is_number(i[0]) and ODJson.is_number(i[1]) and ODJson.is_number(i[2]) and i[3] is Array):
						bad += 1
						continue
					for b: Variant in i[3]:
						if not BUTTONS.has(b):
							bad += 1
				assert_eq(bad, 0, label + ": every input is [moveX, moveY, aim, [buttons]]")


func test_boss_memory_loads() -> void:
	var with_memory := 0
	for e: Variant in _scenarios():
		var g := _golden(e)
		var label: String = g.get("name", "?")
		var stages: Array = (g.get("expected", {}).get("recordings", []) as Array).duplicate()
		stages.append(g.get("expected", {}).get("resolution", {}))
		for s: Variant in stages:
			var mem: Variant = (s as Dictionary).get("bossMemory")
			if mem == null:
				continue
			with_memory += 1
			assert_true(g.get("bossMemoryFrom") is Array, label + ": memory only with bossMemoryFrom")
			var bm := BossMemory.from_dict(mem)
			assert_true(bm.observed.size() > 0, label + ": memory observes a tape")
			assert_json_eq(bm.to_dict(), mem, 0.0, label + ": boss memory round-trips")
	assert_true(with_memory >= 5, "several stages use boss memory")


func _check_stage(label: String, stage: Dictionary, final_sub: int) -> void:
	var events: Array = stage.get("events", [])
	var last := -1
	var sorted := true
	var trips := true
	for ev: Variant in events:
		var d: Dictionary = ev
		if int(d.get("sub", -1)) < last:
			sorted = false
		last = int(d.get("sub", -1))
		if not SimEventType.has(StringName(String(d.get("type", "")))):
			trips = false
		elif not ODJson.deep_equal(SimEvent.from_dict(d).to_dict(), d):
			trips = false
	assert_true(sorted, label + ": events in substep order")
	assert_true(trips, label + ": every event is a known SimEvent type and round-trips")
	var snaps: Array = stage.get("snapshots", [])
	if not assert_true(snaps.size() >= 2, label + ": snapshots present"):
		return
	assert_eq(snaps[0].get("sub"), 0, label + ": first snapshot at sub 0")
	assert_eq(snaps[snaps.size() - 1].get("sub"), final_sub, label + ": last snapshot at the final substep")
	var rule := true
	for i in range(1, snaps.size() - 1):
		if int(snaps[i].get("sub")) % 60 != 0 or int(snaps[i].get("sub")) <= int(snaps[i - 1].get("sub")):
			rule = false
	assert_true(rule, label + ": snapshots every 60 substeps")
	var o: Dictionary = stage.get("outcome", {})
	assert_true(o.has("win") and o.has("objectiveComplete") and o.get("survivors") is Array, label + ": outcome fields")
	if o.has("reason"):
		assert_true(FailReason.has(StringName(String(o.get("reason")))), label + ": reason")


func test_expected_results_are_consistent() -> void:
	for e: Variant in _scenarios():
		var g := _golden(e)
		var label: String = g.get("name", "?")
		var level: Dictionary = g.get("level", {})
		var takes: Array = g.get("takes", [])
		var expected: Dictionary = g.get("expected", {})
		var res: Dictionary = expected.get("resolution", {})
		var horizon := _horizon_subs(level)
		assert_eq(res.get("horizonSubs"), horizon, label + ": horizon from the level")
		_check_stage(label, res, horizon)
		var input_takes := 0
		for t: Variant in takes:
			if (t as Dictionary).get("source") == "inputs":
				input_takes += 1
		var recs: Array = expected.get("recordings", [])
		assert_eq(recs.size(), input_takes, label + ": one recording per inputs take")
		for r: Variant in recs:
			var rec: Dictionary = r
			var k := int(rec.get("take", -1))
			if not assert_true(k >= 0 and k < takes.size() and takes[k].get("source") == "inputs", label + ": recording refers to an inputs take"):
				continue
			var take: Dictionary = takes[k]
			var errors: Array[String] = []
			var tape := ODTape.from_dict(rec.get("tape"), errors)
			if not assert_eq(errors, [], label + ": recorded tape loads"):
				continue
			var n: int = (take.get("inputs", []) as Array).size()
			assert_eq(tape.ticks, n, label + ": recorded tape has one tick per input")
			assert_eq(tape.index, int(take.get("index", -1)), label + ": recorded tape cassette")
			assert_eq(tape.speed, float(take.get("speed", 0)), label + ": recorded tape speed")
			_check_stage(label + " (recording)", rec, n * OD.subs_per_local_tick(tape.speed))
