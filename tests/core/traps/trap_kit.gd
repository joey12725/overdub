extends RefCounted
## Shared fixtures for the trap suites (port of prototype/tests/core/traps/util.ts; docs/TRAPS.md).
## Use through preload: `const K = preload("res://tests/core/traps/trap_kit.gd")`.
##
## Every level here is the 12x10 open room at 120 bpm: 120 master substeps per beat, 30 local ticks
## per beat, and 4 substeps per local tick at 1x. A beat window `from: n` turns true in substep
## `n*120 - 1` (the substep that produces the instant `n*120`).
##
## Entities are written as the prototype's JSON literals (Dictionaries) and parsed through
## LevelDef.entity_from_dict, so the suites also exercise the trap defs' JSON shapes.

const S = preload("res://tests/helpers/script.gd")

const SPB: int = 120

const NEVER: Dictionary = {"const": false}
const ALWAYS: Dictionary = {"const": true}


## True on master beats [from, to) of every `every`.
static func beats(every: float, from: float, to: float) -> Dictionary:
	return {"beat": {"every": every, "from": from, "to": to}}


## A list of {c, r} cells.
static func cells(list: Array) -> Array:
	var out: Array = []
	for p: Variant in list:
		out.append({"c": (p as Array)[0], "r": (p as Array)[1]})
	return out


## `base` with `patch` merged over it (the prototype's `{...base, ...patch}`).
static func merged(base: Dictionary, patch: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k: Variant in patch:
		out[k] = patch[k]
	return out


## Parse entity literals (Dictionaries) or pass EntityDefs through.
static func entities(list: Array) -> Array[EntityDef]:
	var out: Array[EntityDef] = []
	for e: Variant in list:
		if e is EntityDef:
			out.append(e)
			continue
		var errors: Array[String] = []
		var ent := LevelDef.entity_from_dict(e, errors)
		if ent == null or not errors.is_empty():
			push_error("trap_kit: bad entity %s: %s" % [JSON.stringify(e), errors])
			continue
		out.append(ent)
	return out


## An open room with the given entities; 1x only, `bars` bars long (default 2 = 8 beats = 960 substeps).
static func room(list: Array, extra: Dictionary = {}) -> LevelDef:
	var p := {"speeds": [1.0], "bars": 2, "start": Vector2(1.5, 1.5), "entities": entities(list)}
	for k: Variant in extra:
		p[k] = extra[k]
	return TestLevels.make_level(p)


## An enemy that never wakes: a body for the machines to act on, with no behaviour of its own.
static func sleeper(id: String, type: String, x: float, y: float, extra: Dictionary = {}) -> Dictionary:
	return merged({"kind": "enemy", "id": id, "type": type, "x": x, "y": y, "wakeWhen": NEVER}, extra)


## A tape that stands at (x, y) for the whole take.
static func stand(index: int, x: float, y: float, ticks: int = 240) -> ODTape:
	return S.path_tape(index, 1.0, ticks, [[0, x, y]])


## The snapshot of one mechanism / trap in the frame at (or just after) a master substep.
static func mech_at(res: Resolution, sub: int, id: String) -> MechSnap:
	for m: MechSnap in S.frame_at(res, sub).mechs:
		if m.id == id:
			return m
	push_error("no mech %s" % id)
	return MechSnap.new()


## Trap events of one trap as [sub, detail] pairs.
static func trap_events(events: Array[SimEvent], id: String) -> Array:
	var out: Array = []
	for e: SimEvent in events:
		if e.type == SimEventType.TRAP and e.id == id:
			out.append([e.sub, e.detail])
	return out


## Trap events (any trap) with this detail.
static func trap_details(events: Array[SimEvent], detail: String) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e: SimEvent in events:
		if e.type == SimEventType.TRAP and e.detail == detail:
			out.append(e)
	return out


## The first trap event with this detail (null when none).
static func first_trap(events: Array[SimEvent], detail: String, id: String = "") -> SimEvent:
	for e: SimEvent in events:
		if e.type == SimEventType.TRAP and e.detail == detail and (id.is_empty() or e.id == id):
			return e
	return null


static func enemy_at(res: Resolution, sub: int, id: String) -> EnemySnap:
	for e: EnemySnap in S.frame_at(res, sub).enemies:
		if e.id == id:
			return e
	push_error("no enemy %s" % id)
	return EnemySnap.new()


static func last_frame(res: Resolution) -> FrameSnapshot:
	return res.frames[res.frames.size() - 1]


## The first frame at or after `sub` in a list of frames.
static func frame_from(frames: Array[FrameSnapshot], sub: int) -> FrameSnapshot:
	for f: FrameSnapshot in frames:
		if f.sub >= sub:
			return f
	return frames[frames.size() - 1]


## [tape, sub, detail] of every event of a type.
static func tsd(events: Array[SimEvent]) -> Array:
	var out: Array = []
	for e: SimEvent in events:
		out.append([e.tape, e.sub, e.detail])
	return out


## [id, sub, detail] of every event.
static func isd(events: Array[SimEvent]) -> Array:
	var out: Array = []
	for e: SimEvent in events:
		out.append([e.id, e.sub, e.detail])
	return out


## The subs of a list of events.
static func subs(events: Array[SimEvent]) -> Array:
	var out: Array = []
	for e: SimEvent in events:
		out.append(e.sub)
	return out


## The details of a list of events.
static func details(events: Array[SimEvent]) -> Array:
	var out: Array = []
	for e: SimEvent in events:
		out.append(e.detail)
	return out


## Trap events of one trap whose detail is not `skip`.
static func trap_events_except(events: Array[SimEvent], id: String, skip: String) -> Array:
	var out: Array = []
	for p: Variant in trap_events(events, id):
		if (p as Array)[1] != skip:
			out.append(p)
	return out


## True when some outcome note matches the regex.
static func has_note(res: Resolution, pattern: String) -> bool:
	var re := RegEx.create_from_string(pattern)
	for n: String in res.outcome.notes:
		if re.search(n) != null:
			return true
	return false
