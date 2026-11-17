class_name ObjectiveSnap
extends RefCounted
## Objective state at one instant (types.ts ObjectiveSnap).

## Latched: the objective has been satisfied in this run.
var complete: bool = false
## 0..1 progress (enemies killed / total, cores lit / total, boss damage).
var progress: float = 0.0
## Count of selves that are currently alive (not ghost).
var survivors: int = 0


func copy() -> ObjectiveSnap:
	var o := ObjectiveSnap.new()
	o.copy_from(self)
	return o


func copy_from(o: ObjectiveSnap) -> void:
	complete = o.complete
	progress = o.progress
	survivors = o.survivors


static func from_dict(d: Dictionary) -> ObjectiveSnap:
	var o := ObjectiveSnap.new()
	o.complete = ODJson.boolean(d, "complete")
	o.progress = ODJson.num(d, "progress")
	o.survivors = ODJson.integer(d, "survivors")
	return o


func to_dict() -> Dictionary:
	return {"complete": complete, "progress": progress, "survivors": survivors}
