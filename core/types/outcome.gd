class_name Outcome
extends RefCounted
## Result of a run (types.ts Outcome).

## REC-07: objective complete AND at least one self alive at the end of the horizon.
var win: bool = false
var objective_complete: bool = false
## Tape indices of the survivors.
var survivors: Array[int] = []
## FailReason.*; &"" = none (a win).
var reason: StringName = &""
## Human explanations in the game's own terms ("Tape 1 died at beat 9", "Spark never caught up").
var notes: Array[String] = []


func copy() -> Outcome:
	var o := Outcome.new()
	o.win = win
	o.objective_complete = objective_complete
	o.survivors = survivors.duplicate()
	o.reason = reason
	o.notes = notes.duplicate()
	return o


static func from_dict(d: Dictionary) -> Outcome:
	var o := Outcome.new()
	o.win = ODJson.boolean(d, "win")
	o.objective_complete = ODJson.boolean(d, "objectiveComplete")
	o.survivors = ODJson.ints(d.get("survivors"))
	o.reason = ODJson.sname(d, "reason")
	o.notes = ODJson.strings(d.get("notes"))
	return o


func to_dict() -> Dictionary:
	var out := {"win": win, "objectiveComplete": objective_complete, "survivors": survivors.duplicate()}
	if reason != &"":
		out["reason"] = String(reason)
	out["notes"] = ODJson.strings_to_array(notes)
	return out
