class_name RunLog
extends RefCounted
## Everything noteworthy that happened in a run, in order (prototype core/objective.ts RunLog).
## Plain data; ObjectiveTracker.build_outcome turns it into notes.

var deaths: Array[ObjectiveTracker.DeathRecord] = []
var desyncs: Array[ObjectiveTracker.DesyncRecord] = []
var resyncs: Array[ObjectiveTracker.ResyncRecord] = []
var weak_hits: Array[ObjectiveTracker.WeakHitRecord] = []
var kills: Array[ObjectiveTracker.KillRecord] = []


func death(tape: int, sub: int, cause: String) -> void:
	var r := ObjectiveTracker.DeathRecord.new()
	r.tape = tape
	r.sub = sub
	r.cause = cause
	deaths.append(r)


func desync(tape: int, sub: int, cause: String) -> void:
	var r := ObjectiveTracker.DesyncRecord.new()
	r.tape = tape
	r.sub = sub
	r.cause = cause
	desyncs.append(r)


func resync(tape: int, sub: int) -> void:
	var r := ObjectiveTracker.ResyncRecord.new()
	r.tape = tape
	r.sub = sub
	resyncs.append(r)


## `need` is the threshold that was needed, or NAN when there is none (the prototype's null).
func weak(tape: int, sub: int, kind: String, target: String, momentum: float, need: float, reason: String) -> void:
	var r := ObjectiveTracker.WeakHitRecord.new()
	r.tape = tape
	r.sub = sub
	r.kind = kind
	r.target = target
	r.momentum = momentum
	r.has_need = not is_nan(need)
	r.need = need if r.has_need else 0.0
	r.reason = reason
	weak_hits.append(r)


func kill(id: String, sub: int, by: String) -> void:
	var r := ObjectiveTracker.KillRecord.new()
	r.id = id
	r.sub = sub
	r.by = by
	kills.append(r)
