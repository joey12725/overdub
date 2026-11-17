class_name ReplayVerifier
extends RefCounted
## Re-resolves a kept replay and proves it still shows what was won (requirements chapter 20
## "Replay integrity": a replay must reproduce the actual resolved outcome, never a fresh adaptive
## run; CINE-04).
##
## Checks, cheapest first:
##   1. the record's level hash equals the current level's       -> else STATUS_STALE, REASON_LEVEL_CHANGED
##   2. (optional) the record's loadout hash equals the loadout the current catalogue resolves the
##      same item ids to                                          -> else STATUS_STALE, REASON_GEAR_CHANGED
##   3. re-resolve the stored tapes with the stored resolved loadout and the stored boss memory under
##      playback rules (ODResolve, no live take), then compare horizon, outcome (win, objective,
##      survivors, reason), event count and the events checksum   -> else STATUS_STALE, REASON_RULES_CHANGED
## Only an STATUS_OK check carries a Resolution; the cinematic plays exactly that.
##
## The events checksum is a SHA-256 over every event's (sub, type, tape, id, detail) in order: the
## exact substep of every kill, death, desync, door, plate, swing and shot. It deliberately leaves out
## float payloads (positions, directions, power) and the outcome's notes text, so a cosmetic change
## (a reworded note) does not stale a replay, while any change to what happened when does.

const STATUS_OK: StringName = &"ok"
## The inputs no longer reproduce the recorded result: do not show it as that result.
const STATUS_STALE: StringName = &"stale"
## The file is unreadable, foreign or from a newer version.
const STATUS_INVALID: StringName = &"invalid"
## No replay is kept for this level.
const STATUS_MISSING: StringName = &"missing"

const REASON_NONE: StringName = &""
const REASON_LEVEL_CHANGED: StringName = &"levelChanged"
const REASON_GEAR_CHANGED: StringName = &"gearChanged"
const REASON_RULES_CHANGED: StringName = &"rulesChanged"
const REASON_NOT_A_WIN: StringName = &"notAWin"
const REASON_UNREADABLE: StringName = &"unreadable"
const REASON_RESOLVE_FAILED: StringName = &"resolveFailed"


## The verdict on one replay.
class Check:
	extends RefCounted
	var status: StringName = STATUS_MISSING
	var reason: StringName = REASON_NONE
	## Human explanation for logs and the campaign screen tooltip ("" when STATUS_OK).
	var message: String = ""
	var record: ReplayRecord = null
	## The re-resolved run: set only when status == STATUS_OK (and after a full verify).
	var resolution: Resolution = null

	func ok() -> bool:
		return status == STATUS_OK

	func is_stale() -> bool:
		return status == STATUS_STALE

	static func make(p_status: StringName, p_reason: StringName, p_message: String, p_record: ReplayRecord) -> Check:
		var c := Check.new()
		c.status = p_status
		c.reason = p_reason
		c.message = p_message
		c.record = p_record
		return c


## SHA-256 of the level's canonical JSON (LevelDef.to_dict through ODJson.stringify), so whitespace
## or key order in the file does not matter but any change to the map, entities, objective, timing or
## music does.
static func level_hash(level: LevelDef) -> String:
	return ODJson.stringify(level.to_dict()).sha256_text()


## SHA-256 of a resolved loadout's canonical JSON.
static func loadout_hash(loadout: ResolvedLoadout) -> String:
	return ODJson.stringify(loadout.to_dict()).sha256_text()


## SHA-256 over every event's (sub, type, tape, id, detail), in order.
static func events_checksum(resolution: Resolution) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for e: SimEvent in resolution.events:
		ctx.update(("%d|%s|%d|%s|%s\n" % [e.sub, e.type, e.tape, e.id, e.detail]).to_utf8_buffer())
	return ctx.finish().hex_encode()


## The outcome facts a replay must reproduce (notes are presentation and excluded).
static func outcome_key(o: Outcome) -> String:
	var surv: Array[String] = []
	for s: int in o.survivors:
		surv.append(str(s))
	return "win=%s objective=%s survivors=[%s] reason=%s" % [o.win, o.objective_complete, ",".join(surv), o.reason]


## Checks 1-2 only (no resolve): cheap enough for every entry of the campaign screen. STATUS_OK here means
## "worth offering"; play() still runs the full verify. `current_loadout` (optional) is the loadout
## the current catalogue resolves the record's item ids to.
static func quick_check(record: ReplayRecord, level: LevelDef, current_loadout: ResolvedLoadout = null) -> Check:
	if record == null:
		return Check.make(STATUS_MISSING, REASON_NONE, "no replay kept for this level", null)
	if level == null:
		return Check.make(STATUS_STALE, REASON_LEVEL_CHANGED, "level '%s' no longer exists" % record.level_id, record)
	if not record.expected_outcome.win:
		return Check.make(STATUS_INVALID, REASON_NOT_A_WIN, "the stored run is not a win", record)
	if record.level_id != level.id or record.level_hash != level_hash(level):
		return Check.make(STATUS_STALE, REASON_LEVEL_CHANGED, "level '%s' changed since this replay was recorded" % record.level_id, record)
	if current_loadout != null and loadout_hash(current_loadout) != record.loadout_hash:
		return Check.make(STATUS_STALE, REASON_GEAR_CHANGED, "the equipment used in this replay changed since it was recorded", record)
	return Check.make(STATUS_OK, REASON_NONE, "", record)


## Compare an already-resolved run of the record (e.g. from a worker thread) with its expectation.
static func check_resolution(record: ReplayRecord, level: LevelDef, res: Resolution, current_loadout: ResolvedLoadout = null) -> Check:
	var c := quick_check(record, level, current_loadout)
	if not c.ok():
		return c
	if res == null:
		return Check.make(STATUS_STALE, REASON_RESOLVE_FAILED, "the stored tapes no longer resolve on this level", record)
	var diffs: Array[String] = []
	if res.horizon_subs != record.expected_horizon_subs:
		diffs.append("horizon %d substeps, recorded %d" % [res.horizon_subs, record.expected_horizon_subs])
	if outcome_key(res.outcome) != outcome_key(record.expected_outcome):
		diffs.append("outcome '%s', recorded '%s'" % [outcome_key(res.outcome), outcome_key(record.expected_outcome)])
	if res.events.size() != record.expected_event_count:
		diffs.append("%d events, recorded %d" % [res.events.size(), record.expected_event_count])
	if events_checksum(res) != record.expected_events_checksum:
		diffs.append("event checksum differs")
	if not diffs.is_empty():
		return Check.make(STATUS_STALE, REASON_RULES_CHANGED, "the rules changed since this replay was recorded: " + "; ".join(diffs), record)
	var ok := Check.make(STATUS_OK, REASON_NONE, "", record)
	ok.resolution = res
	return ok


## Full verify: quick checks, then re-resolve the stored inputs (synchronously, on this thread) and
## compare. `progress` / `cancel` are passed to ODResolve.resolve_encounter.
static func verify(
	record: ReplayRecord,
	level: LevelDef,
	current_loadout: ResolvedLoadout = null,
	progress: Callable = Callable(),
	cancel: ODResolve.CancelToken = null
) -> Check:
	var c := quick_check(record, level, current_loadout)
	if not c.ok():
		return c
	var errors: Array[String] = []
	var res := ODResolve.resolve_encounter(record.config(level), progress, cancel, errors)
	if res == null:
		return Check.make(STATUS_STALE, REASON_RESOLVE_FAILED, "the stored tapes no longer resolve: %s" % ", ".join(errors), record)
	return check_resolution(record, level, res, current_loadout)
