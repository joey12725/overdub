class_name ReplayRecord
extends RefCounted
## One kept winning performance (CINE-01, LEVEL-09; requirements chapter 20 "Replay integrity").
##
## A replay stores the INPUTS of the authoritative run, never its frames: the level identity (id plus
## a content hash), the loadout (catalogue ids and the exact resolved numbers the run used), the
## committed tapes in ODTape's own serialised form, the boss memory the run was given, and what the
## run produced (outcome, event count, horizon and an events checksum). Playing it re-resolves those
## inputs under playback rules and checks the result against the expectation, so a replay can only
## ever show the resolved outcome it recorded: no new boss learning step (the stored memory is used
## verbatim, never rebuilt), no live take, no randomness (the kernel has none). When the level, the
## rules or the gear changed since, the check fails and the replay is reported stale instead of being
## shown wrong (ReplayVerifier).
##
## JSON (version 1; keys camelCase like the rest of the game's data):
##   {
##     "format": "overdub-replay", "version": 1,
##     "levelId": "...", "levelName": "...", "levelHash": "<sha256 of the level's canonical JSON>",
##     "loadout": {helmet, top, pants, shoes, melee, ranged},       catalogue ids (Loadout.to_dict)
##     "resolvedLoadout": {...}, "loadoutHash": "<sha256>",        ResolvedLoadout.to_dict
##     "tapes": [SerializedTape, ...],                             ODTape.to_dict, cassette order
##     "bossMemory": BossMemory | null,                             BossMemory.to_dict
##     "inputBits": "<base64 float64>",                            exact copy of every number above
##     "expected": {"outcome": Outcome, "horizonSubs": n, "eventCount": n, "eventsChecksum": "<sha256>"},
##     "savedAt": unix seconds (0 = unknown)
##   }
##
## `inputBits` exists because GDScript's JSON parser does not round every decimal to the nearest
## double (core/README.md §5 "Engine facts"): tape event directions and velocities, boss-memory
## samples and gear numbers are arbitrary doubles. Every number inside "tapes", "bossMemory" and
## "resolvedLoadout" is also written, in
## walk order, as little-endian float64; loading restores them bit for bit, so the re-resolve sees
## exactly the tapes that won. A file without it (hand-edited) still loads, with JSON precision.

const FORMAT: String = "overdub-replay"
## Bump when the layout changes incompatibly; older files are migrated in from_dict, newer ones are
## refused (the game cannot know what they mean).
const VERSION: int = 1

var level_id: String = ""
var level_name: String = ""
var level_hash: String = ""
## Catalogue ids of the six slots (what the campaign screen shows and the loadout screen restores).
var loadout_ids: Loadout = Loadout.new()
## The numbers the winning run used (resolved through the catalogue of that time).
var resolved_loadout: ResolvedLoadout = ResolvedLoadout.new()
var loadout_hash: String = ""
## Every tape of the winning run, in cassette order (committed tapes + the final take).
var tapes: Array[ODTape] = []
## The boss memory the winning run was resolved with (built from the tapes committed before the final
## take); null when the level has no boss memory input.
var boss_memory: BossMemory = null
## What the run produced.
var expected_outcome: Outcome = Outcome.new()
var expected_horizon_subs: int = 0
var expected_event_count: int = 0
var expected_events_checksum: String = ""
## Wall-clock save time (unix seconds) supplied by the caller; 0 = unknown. Informational only.
var saved_at: int = 0


## Build the record of a win from exactly what the session resolved. `tapes` are the run's tapes in
## cassette order (GameSession: committed_tapes + [pending_tape]; a plain or typed Array); `boss_memory` is the memory the
## run was resolved with (GameSession.boss_memory at that moment); `resolution` is the authoritative
## run (GameSession.resolution). Returns null (with a reason in `errors`) when the inputs cannot be a
## winning replay: no resolution, a resolution that did not win, or no tapes.
static func from_win(
	level: LevelDef,
	loadout: ResolvedLoadout,
	p_tapes: Array,
	p_boss_memory: BossMemory,
	resolution: Resolution,
	errors: Array[String] = []
) -> ReplayRecord:
	if level == null or loadout == null or resolution == null:
		errors.append("ReplayRecord.from_win: level, loadout and resolution are required")
		return null
	if not resolution.outcome.win:
		errors.append("ReplayRecord.from_win: only a winning run is kept as a replay")
		return null
	if p_tapes.is_empty():
		errors.append("ReplayRecord.from_win: a replay needs at least one tape")
		return null
	var r := ReplayRecord.new()
	r.level_id = level.id
	r.level_name = level.name
	r.level_hash = ReplayVerifier.level_hash(level)
	r.loadout_ids = loadout.loadout.copy() if loadout.loadout != null else Loadout.new()
	r.resolved_loadout = loadout.copy()
	r.loadout_hash = ReplayVerifier.loadout_hash(loadout)
	for t: Variant in p_tapes:
		if not (t is ODTape):
			errors.append("ReplayRecord.from_win: tapes must be ODTape objects")
			return null
		r.tapes.append((t as ODTape).copy())
	r.boss_memory = p_boss_memory.copy() if p_boss_memory != null else null
	r.expected_outcome = resolution.outcome.copy()
	r.expected_horizon_subs = resolution.horizon_subs
	r.expected_event_count = resolution.events.size()
	r.expected_events_checksum = ReplayVerifier.events_checksum(resolution)
	return r


## The playback configuration of the stored run (never a live take). Shares this record's objects:
## hand a worker thread `config(level).deep_copy()`.
func config(level: LevelDef) -> SimConfig:
	return SimConfig.make(level, resolved_loadout, tapes.duplicate(), null, boss_memory)


func copy() -> ReplayRecord:
	var errors: Array[String] = []
	return ReplayRecord.from_dict(to_dict(), errors)


# ───────────────────────────── JSON ─────────────────────────────


func to_dict() -> Dictionary:
	var tape_list: Array = []
	for t: ODTape in tapes:
		tape_list.append(t.to_dict())
	var mem: Variant = boss_memory.to_dict() if boss_memory != null else null
	var lo := resolved_loadout.to_dict()
	var bits := PackedFloat64Array()
	_collect_numbers(tape_list, bits)
	_collect_numbers(mem, bits)
	_collect_numbers(lo, bits)
	return {
		"format": FORMAT,
		"version": VERSION,
		"levelId": level_id,
		"levelName": level_name,
		"levelHash": level_hash,
		"loadout": loadout_ids.to_dict(),
		"resolvedLoadout": lo,
		"loadoutHash": loadout_hash,
		"tapes": tape_list,
		"bossMemory": mem,
		"inputBits": Marshalls.raw_to_base64(bits.to_byte_array()),
		"expected": {
			"outcome": expected_outcome.to_dict(),
			"horizonSubs": expected_horizon_subs,
			"eventCount": expected_event_count,
			"eventsChecksum": expected_events_checksum,
		},
		"savedAt": saved_at,
	}


## Parse a record. Returns null and appends the reason to `errors` when the data is not a replay,
## comes from a newer game version, or holds an invalid tape.
static func from_dict(d: Variant, errors: Array[String] = []) -> ReplayRecord:
	if not (d is Dictionary):
		errors.append("replay: not a JSON object")
		return null
	var dd: Dictionary = (d as Dictionary).duplicate(true)
	if ODJson.string(dd, "format") != FORMAT:
		errors.append("replay: not an OVERDUB replay file")
		return null
	var version := ODJson.integer(dd, "version", -1)
	if version > VERSION:
		errors.append("replay: format version %d is newer than this game understands (%d)" % [version, VERSION])
		return null
	if version < 1:
		errors.append("replay: unknown format version %d" % version)
		return null
	# (Migrations from older versions go here, rewriting `dd` into the current layout.)
	var tape_list: Array = ODJson.array(dd, "tapes")
	var mem: Variant = dd.get("bossMemory")
	var lo: Dictionary = ODJson.dict(dd, "resolvedLoadout")
	var bits_text := ODJson.string(dd, "inputBits")
	if not bits_text.is_empty():
		var raw := Marshalls.base64_to_raw(bits_text)
		var bits := raw.to_float64_array() if raw.size() % 8 == 0 else PackedFloat64Array()
		var count := PackedFloat64Array()
		_collect_numbers(tape_list, count)
		_collect_numbers(mem, count)
		_collect_numbers(lo, count)
		if bits.size() == count.size():
			var at := [0]
			tape_list = _restore_numbers(tape_list, bits, at)
			mem = _restore_numbers(mem, bits, at)
			lo = _restore_numbers(lo, bits, at)
		else:
			errors.append("replay: inputBits does not match the stored inputs (%d vs %d numbers); using JSON precision" % [bits.size(), count.size()])
	var r := ReplayRecord.new()
	r.level_id = ODJson.string(dd, "levelId")
	r.level_name = ODJson.string(dd, "levelName")
	r.level_hash = ODJson.string(dd, "levelHash")
	r.loadout_ids = Loadout.from_dict(ODJson.dict(dd, "loadout"))
	r.resolved_loadout = ResolvedLoadout.from_dict(lo)
	r.loadout_hash = ODJson.string(dd, "loadoutHash")
	if r.level_id.is_empty():
		errors.append("replay: no level id")
		return null
	for v: Variant in tape_list:
		var tape_errors: Array[String] = []
		var t := ODTape.from_dict(v, tape_errors)
		if t == null:
			errors.append("replay: bad tape: %s" % ", ".join(tape_errors))
			return null
		r.tapes.append(t)
	if r.tapes.is_empty():
		errors.append("replay: no tapes")
		return null
	r.boss_memory = BossMemory.from_dict(mem) if mem is Dictionary else null
	var ex := ODJson.dict(dd, "expected")
	r.expected_outcome = Outcome.from_dict(ODJson.dict(ex, "outcome"))
	r.expected_horizon_subs = ODJson.integer(ex, "horizonSubs")
	r.expected_event_count = ODJson.integer(ex, "eventCount")
	r.expected_events_checksum = ODJson.string(ex, "eventsChecksum")
	r.saved_at = ODJson.integer(dd, "savedAt")
	return r


## Every number (int or float) in a JSON value, in a fixed walk order (dictionary insertion order,
## array order). Strings, booleans and nulls are skipped.
static func _collect_numbers(v: Variant, out: PackedFloat64Array) -> void:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT:
			out.append(float(v))
		TYPE_DICTIONARY:
			var d: Dictionary = v
			for k: Variant in d:
				_collect_numbers(d[k], out)
		TYPE_ARRAY:
			for x: Variant in (v as Array):
				_collect_numbers(x, out)


## A copy of `v` whose numbers are replaced, in _collect_numbers order, by `bits[at[0]...]`.
## Integral values become ints (JSON readers accept either).
static func _restore_numbers(v: Variant, bits: PackedFloat64Array, at: Array) -> Variant:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT:
			var f: float = bits[at[0]]
			at[0] = int(at[0]) + 1
			return f
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var o := {}
			for k: Variant in d:
				o[k] = _restore_numbers(d[k], bits, at)
			return o
		TYPE_ARRAY:
			var o2: Array = []
			for x: Variant in (v as Array):
				o2.append(_restore_numbers(x, bits, at))
			return o2
	return v
