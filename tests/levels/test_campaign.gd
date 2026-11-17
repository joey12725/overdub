extends ODTest
## The shipped campaign is proven in the shipped game (port of prototype/tests/levels/campaign.test.ts).
##
## For every level in data/levels/index.json, in path order:
##   - it loads through ContentData / CampaignData (every entity kind, traps included) and the
##     validator accepts it, both as the typed model and as raw JSON;
##   - its solution (data/levels/solutions/<id>.json) wears the baseline loadout, and its stored
##     inputs, replayed open-loop through the real GameSession by the shipped bot (GameBot), win with
##     the takes, outcome notes, survivors and tapes the TypeScript prototype stored (APP-TEST-03);
##   - its stored tapes, resolved by ODResolve.resolve_encounter under playback rules, give the same
##     outcome and the same event timeline.
## Plus the campaign-wide rules: exactly the twelve NN-*.json files, indices 1..12, sandbox off the
## path; loot names real gear, each non-starting item is found exactly once; and each level carries
## the composer's music block (tests/content/test_music_files.gd checks the extras).
##
## When a level fails here but passes `cd prototype && npx vitest run tests/levels`, the two engines
## disagree: find the rule difference in core/ (and add a golden), or re-author the solution with
## margin (`npx vite-node scripts/level.ts mutate <NN>`).

const LEVEL_DIR := "res://data/levels"
const SOLUTION_DIR := "res://data/levels/solutions"
## Event types the stored timeline keeps (prototype scripts/lib/run.ts TIMELINE_TYPES).
const TIMELINE_TYPES: Array[String] = [
	"swing", "hit", "kill", "break", "clang", "dodge", "fire", "interact", "interactFail", "door", "plate",
	"laser", "core", "selfDeath", "desync", "resync", "tapeWrap", "tapeTurn", "tapeEnd", "enemyAttack",
	"enemyShot", "bossPhase", "objective",
]

## Bot runs, one per level id, shared by the tests of this suite (a run is the expensive part).
var _runs: Dictionary = {}


func _campaign() -> Array[LevelDef]:
	var errors: Array[String] = []
	var levels := ContentData.load_campaign(errors)
	assert_eq(errors, [] as Array[String], "the campaign loads without errors")
	return levels


func _solution(id: String) -> Dictionary:
	var path := SOLUTION_DIR.path_join(id + ".json")
	var errors: Array[String] = []
	var d: Variant = ODJson.read_file(path, errors) if FileAccess.file_exists(path) else null
	assert_true(d is Dictionary, "%s: every campaign level needs its designer's solution (%s)" % [id, "; ".join(errors)])
	return d if d is Dictionary else {}


func _bot_run(id: String) -> GameBot.BotRun:
	if _runs.has(id):
		return _runs[id]
	var errors: Array[String] = []
	var run := GameBot.run_plan_file(SOLUTION_DIR.path_join(id + ".json"), errors)
	assert_true(run != null, "%s: the bot could not play the solution: %s" % [id, "; ".join(errors)])
	_runs[id] = run
	return run


func _timeline(level: LevelDef, events: Array[SimEvent]) -> Array:
	var spb := ODTime.subs_per_beat(level)
	var out: Array = []
	for e: SimEvent in events:
		if not TIMELINE_TYPES.has(String(e.type)):
			continue
		var beat := roundf(e.sub / spb * 1000.0) / 1000.0
		out.append([beat, String(e.type), OD.TAPE_NAMES[e.tape] if e.tape >= 0 else "", e.id, e.detail])
	return out


func _outcome_dict(o: Outcome) -> Dictionary:
	return {"win": o.win, "objectiveComplete": o.objective_complete, "survivors": o.survivors, "notes": o.notes}


func _stored_outcome(gen: Dictionary) -> Dictionary:
	var o: Dictionary = ODJson.dict(gen, "outcome")
	return {"win": o.get("win"), "objectiveComplete": o.get("objectiveComplete"), "survivors": o.get("survivors"), "notes": o.get("notes")}


# ───────────────────────────── the campaign as a whole ─────────────────────────────


func test_the_campaign_is_exactly_the_twelve_numbered_level_files_in_index_order() -> void:
	var files: Array[String] = []
	for f: String in DirAccess.get_files_at(LEVEL_DIR):
		if f.ends_with(".json") and f.length() > 3 and f.substr(0, 2).is_valid_int() and f[2] == "-":
			files.append(f.get_basename())
	files.sort()
	var ids := ContentData.list_level_ids()
	assert_eq(ids, files, "data/levels/index.json lists every NN-<slug>.json, in file order")
	assert_eq(ids.size(), 12, "twelve campaign levels")
	var levels := _campaign()
	var got: Array[String] = []
	for i in levels.size():
		got.append(levels[i].id)
		assert_eq(levels[i].index, i + 1, "%s: campaign levels are numbered 1..12 like their files" % levels[i].id)
	assert_eq(got, files, "ContentData.load_campaign returns them in index order")
	var cached: Array[String] = []
	for l: LevelDef in CampaignData.levels():
		cached.append(l.id)
	assert_eq(cached, files, "CampaignData.levels() is the same path")
	assert_false(cached.has("sandbox"), "the sandbox is kept off the path")
	assert_true(ContentData.list_level_ids(true).has("sandbox"), "the sandbox is an extra level")
	assert_true(CampaignData.sandbox() != null and CampaignData.sandbox().index == 0, "the sandbox still loads for development")
	var problems: Array[String] = []
	for m: String in LevelValidator.validate_campaign(levels):
		if LevelValidator.is_problem(m):
			problems.append(m)
	assert_eq(problems, [] as Array[String], "the campaign validates as a whole")


func test_every_level_validates_and_loads_every_entity_kind_including_traps() -> void:
	var kinds: Dictionary = {}
	for lv: LevelDef in _campaign():
		var problems: Array[String] = []
		for m: String in LevelValidator.validate_level(lv):
			if LevelValidator.is_problem(m):
				problems.append(m)
		assert_eq(problems, [] as Array[String], "%s is a valid level" % lv.id)
		var raw: Variant = ODJson.read_file(LEVEL_DIR.path_join(lv.id + ".json"))
		var raw_problems: Array[String] = []
		for m: String in LevelValidator.validate_json(raw):
			if LevelValidator.is_problem(m):
				raw_problems.append(m)
		assert_eq(raw_problems, [] as Array[String], "%s is valid as raw JSON" % lv.id)
		# Every entity round-trips: the typed model carries all of it.
		var entities: Array = ODJson.array(raw, "entities")
		assert_eq(lv.entities.size(), entities.size(), "%s: every entity loads" % lv.id)
		for i in mini(entities.size(), lv.entities.size()):
			var e: EntityDef = lv.entities[i]
			kinds[String(e.kind)] = true
			# Every field the designer wrote is carried by the typed model (to_dict may add defaults).
			var typed := e.to_dict()
			var authored: Dictionary = entities[i]
			for key: String in authored:
				# to_dict omits a field at its default (an enemy's facing 0); that carries it too.
				if not typed.has(key) and (authored[key] is float or authored[key] is int) and float(authored[key]) == 0.0:
					continue
				var diff := ODJson.first_difference(typed.get(key), authored[key])
				assert_true(typed.has(key) and diff.is_empty(), "%s: entity #%d (%s) carries %s as authored (%s)" % [lv.id, i, e.kind, key, diff])
			if EntityKind.is_trap(e.kind):
				assert_true(e is TrapDef, "%s: %s loads as a TrapDef" % [lv.id, e.kind])
	for k: String in ["spikes", "crusher", "conveyor", "flame", "dart", "relay", "sensor"]:
		assert_true(kinds.has(k), "some campaign level uses %s" % k)


func test_loot_names_real_gear_and_every_found_item_is_found_exactly_once() -> void:
	var cat := CampaignData.gear()
	var base := cat.base_inventory()
	var found: Dictionary = {}
	for lv: LevelDef in _campaign():
		for id: String in lv.loot:
			assert_true(cat.has_item(id), "%s: loot '%s' is a gear id" % [lv.id, id])
			assert_false(base.has(id), "%s: loot '%s' is not starting gear" % [lv.id, id])
			assert_false(found.has(id), "%s: loot '%s' is also found in %s" % [lv.id, id, found.get(id, "")])
			found[id] = lv.id
	for it: GearItem in cat.items:
		if not base.has(it.id):
			assert_true(found.has(it.id), "gear '%s' is found somewhere on the path" % it.id)


func test_every_level_plays_the_composers_music_at_its_own_tempo() -> void:
	for lv: LevelDef in _campaign():
		var f := ContentData.load_music_file(lv.id)
		if not assert_true(f != null, "data/music/%s.json loads" % lv.id):
			continue
		assert_eq(f.bpm, lv.bpm, "%s: the piece is composed at the level's bpm" % lv.id)
		assert_eq(lv.music.to_dict(), f.music.to_dict(), "%s: the level's music block is the composer's (python -I art/music/merge.py --write)" % lv.id)


# ───────────────────────────── each level proven ─────────────────────────────


func test_every_solution_wears_the_baseline_loadout() -> void:
	var cat := CampaignData.gear()
	for lv: LevelDef in _campaign():
		var sol := _solution(lv.id)
		if sol.is_empty():
			continue
		var gen := ODJson.dict(sol, "generated")
		assert_false(gen.is_empty(), "%s: the solution is compiled (generated block)" % lv.id)
		assert_true(Loadout.from_dict(ODJson.dict(gen, "loadout")).equals(cat.base_loadout), "%s: recorded with the baseline loadout" % lv.id)
		var plan := GameBot.load_plan(SOLUTION_DIR.path_join(lv.id + ".json"))
		assert_true(plan != null and (plan.loadout == null or plan.loadout.equals(cat.base_loadout)), "%s: the bot wears the baseline loadout" % lv.id)
		assert_true(plan != null and not plan.draft, "%s: not a draft" % lv.id)


func test_every_solution_wins_through_the_real_session_with_the_prototypes_outcome() -> void:
	for lv: LevelDef in _campaign():
		var sol := _solution(lv.id)
		var gen := ODJson.dict(sol, "generated")
		var run := _bot_run(lv.id)
		if run == null or gen.is_empty():
			continue
		var what := "%s: %s" % [lv.id, GameBot.describe_run(run)]
		assert_true(run.outcome.win, what)
		assert_eq(run.takes_recorded, ODJson.integer(gen, "takesRecorded", -1), what)
		assert_eq(_outcome_dict(run.outcome), _stored_outcome(gen), "%s: same outcome as the prototype" % lv.id)


## How far a Godot-recorded tape may drift from the prototype's recording of the same inputs. The two
## engines share every rule (tests/core/test_goldens.gd), but transcendental functions (atan2, sin,
## cos, hypot) may differ in the last bit between V8 and Godot, so float32 samples can differ by an
## ulp or so (measured on the shipped campaign: at most 2e-6 tiles and 3e-7 rad). Anything near
## these bounds is a real rule difference.
const TAPE_POS_TOL := 1e-4
const TAPE_FACING_TOL := 1e-4


## Discrepancies between a recorded tape and a stored one: everything discrete exactly, samples
## within the tolerances above. Also returns the measured maxima in `stats`.
func _tape_diffs(got: ODTape, want: ODTape, stats: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if got.index != want.index or got.speed != want.speed or got.end_mode != want.end_mode or got.ticks != want.ticks:
		out.append("header %s/%s/%s/%d vs %s/%s/%s/%d" % [got.index, got.speed, got.end_mode, got.ticks, want.index, want.speed, want.end_mode, want.ticks])
		return out
	if got.anim != want.anim:
		out.append("animation states differ")
	var dp := 0.0
	for k in mini(got.pos.size(), want.pos.size()):
		dp = maxf(dp, absf(got.pos[k] - want.pos[k]))
	var df := 0.0
	for k in mini(got.facing.size(), want.facing.size()):
		df = maxf(df, absf(TapeLib.angle_delta(got.facing[k], want.facing[k])))
	if got.pos.size() != want.pos.size() or got.facing.size() != want.facing.size():
		out.append("sample counts differ")
	stats["pos"] = maxf(float(stats.get("pos", 0.0)), dp)
	stats["facing"] = maxf(float(stats.get("facing", 0.0)), df)
	if dp > TAPE_POS_TOL:
		out.append("positions differ by up to %s tiles" % dp)
	if df > TAPE_FACING_TOL:
		out.append("facings differ by up to %s rad" % df)
	if got.events.size() != want.events.size():
		out.append("%d events vs %d" % [got.events.size(), want.events.size()])
	else:
		for k in got.events.size():
			var a := got.events[k]
			var b := want.events[k]
			if a.tick != b.tick or a.kind != b.kind:
				out.append("event %d: %s@%d vs %s@%d" % [k, a.kind, a.tick, b.kind, b.tick])
			elif absf(TapeLib.angle_delta(a.dir, b.dir)) > TAPE_FACING_TOL or absf(a.x - b.x) > TAPE_POS_TOL or absf(a.y - b.y) > TAPE_POS_TOL:
				out.append("event %d (%s@%d) aimed or placed differently" % [k, a.kind, a.tick])
	return out


func test_every_solution_records_the_prototypes_tapes() -> void:
	var exact := 0
	var total := 0
	var stats: Dictionary = {}
	for lv: LevelDef in _campaign():
		var gen := ODJson.dict(_solution(lv.id), "generated")
		var run := _bot_run(lv.id)
		if run == null or gen.is_empty():
			continue
		var tapes: Array[ODTape] = run.session.committed_tapes.duplicate()
		if run.session.pending_tape != null:
			tapes.append(run.session.pending_tape)
		var stored: Array = ODJson.array(gen, "tapes")
		if not assert_eq(tapes.size(), stored.size(), "%s: tapes recorded" % lv.id):
			continue
		for i in tapes.size():
			total += 1
			var want := ODTape.from_dict(stored[i])
			if not assert_true(want != null, "%s: stored tape %d deserializes" % [lv.id, i]):
				continue
			if ODJson.first_difference(tapes[i].to_dict(), stored[i]).is_empty():
				exact += 1
			var diffs := _tape_diffs(tapes[i], want, stats)
			assert_eq(diffs, [] as Array[String], "%s: tape %s matches the prototype's recording" % [lv.id, OD.TAPE_NAMES[i]])
	print("[campaign] tapes recorded identically to the prototype: %d of %d bit for bit; largest drift %s tiles, %s rad" % [exact, total, stats.get("pos", 0.0), stats.get("facing", 0.0)])


func test_every_levels_stored_tapes_resolve_to_the_same_outcome_and_timeline() -> void:
	var lo := LoadoutRules.resolve_loadout(CampaignData.base_loadout())
	for lv: LevelDef in _campaign():
		var gen := ODJson.dict(_solution(lv.id), "generated")
		if gen.is_empty():
			continue
		var tapes: Array[ODTape] = []
		var errors: Array[String] = []
		for t: Variant in ODJson.array(gen, "tapes"):
			var tape := ODTape.from_dict(t, errors)
			if tape != null:
				tapes.append(tape)
		if not assert_eq(errors, [] as Array[String], "%s: stored tapes deserialize" % lv.id):
			continue
		# The boss remembers committed tapes only: every tape but the one just recorded.
		var memory := BossMemoryLib.build_boss_memory(lv, tapes.slice(0, tapes.size() - 1))
		var res := ODResolve.resolve_encounter(SimConfig.make(lv, lo, tapes, null, memory), Callable(), null, errors)
		if not assert_true(res != null, "%s: resolves (%s)" % [lv.id, "; ".join(errors)]):
			continue
		assert_true(res.outcome.win, "%s: %s" % [lv.id, " ".join(res.outcome.notes)])
		assert_eq(_outcome_dict(res.outcome), _stored_outcome(gen), "%s: same outcome as the prototype" % lv.id)
		assert_eq(_timeline(lv, res.events), ODJson.array(gen, "timeline"), "%s: same event timeline as the prototype" % lv.id)
