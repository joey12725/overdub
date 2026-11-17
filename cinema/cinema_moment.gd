class_name CinemaMoment
extends RefCounted
## A candidate story beat found in the resolved events: one link of the solution's causal chain
## (cause, then effect), with its importance. The planner turns moments into shots.

## CinemaGrammar.KIND_*
var kind: StringName = CinemaGrammar.KIND_KILL
var score: float = 0.0
## Master beat the cause starts (wind-up, switch thrown, plate stepped on).
var cause_beat: float = 0.0
## Master beat of the effect (impact, door passed, resync). key_beat >= cause_beat.
var key_beat: float = 0.0
## Floor points (sim axes).
var cause_point: Vector2 = Vector2.ZERO
var effect_point: Vector2 = Vector2.ZERO
var cause_tape: int = -1
var effect_tape: int = -1
## Every self involved, cause first.
var tapes: Array[int] = []
## Enemies / mechanisms involved.
var ids: Array[String] = []
var reason: String = ""
## Indices into Resolution.events this moment explains.
var source_events: Array[int] = []
var callouts: Array[CinemaTypes.Callout] = []
## Cause and effect happen together in different rooms: the point is the simultaneity (split).
var simultaneous_far: bool = false
## Moments folded into this one (their reasons are already in `reason`).
var absorbed: Array[StringName] = []
## Set by the planner: index of the shot that shows it, -1 = not shown.
var shot: int = -1


func add_tape(t: int) -> void:
	if t >= 0 and not tapes.has(t):
		tapes.append(t)


func add_id(i: String) -> void:
	if not i.is_empty() and not ids.has(i):
		ids.append(i)


func add_callout(c: CinemaTypes.Callout) -> void:
	for o: CinemaTypes.Callout in callouts:
		if o.key() == c.key():
			return
	callouts.append(c)


func first_event() -> int:
	return source_events[0] if not source_events.is_empty() else 1 << 30


## Fold `other` into this moment (same story beat seen twice, e.g. a kill that is also the climax).
func absorb(other: CinemaMoment) -> void:
	for t: int in other.tapes:
		add_tape(t)
	for i: String in other.ids:
		add_id(i)
	for e: int in other.source_events:
		if not source_events.has(e):
			source_events.append(e)
	source_events.sort()
	for c: CinemaTypes.Callout in other.callouts:
		add_callout(c)
	absorbed.append(other.kind)
	for k: StringName in other.absorbed:
		absorbed.append(k)
	cause_beat = minf(cause_beat, other.cause_beat)


## Deterministic priority order: higher score first, then earlier key beat, kind, first event.
static func before(a: CinemaMoment, b: CinemaMoment) -> bool:
	if not is_equal_approx(a.score, b.score):
		return a.score > b.score
	if not is_equal_approx(a.key_beat, b.key_beat):
		return a.key_beat < b.key_beat
	var ra := CinemaGrammar.kind_rank(a.kind)
	var rb := CinemaGrammar.kind_rank(b.kind)
	if ra != rb:
		return ra < rb
	return a.first_event() < b.first_event()


func to_dict() -> Dictionary:
	return {
		"kind": String(kind),
		"score": snappedf(score, 0.01),
		"cause": snappedf(cause_beat, 0.001),
		"key": snappedf(key_beat, 0.001),
		"tapes": tapes.duplicate(),
		"ids": ids.duplicate(),
		"events": source_events.duplicate(),
		"reason": reason,
		"shot": shot,
	}
