class_name BossObservation
extends RefCounted
## What the boss remembers of one committed tape (types.ts BossMemory.observed[] element).

## TapeIndex.
var tape: int = 0
## TapeSpeed.
var speed: float = 1.0
## Sampled positions in master beats the boss will pre-empt.
var samples: Array[BossSample] = []
## Every attack attempt (light, heavy, ranged) the tape makes within the horizon, end behaviour
## applied, in master beats. Valid only when has_actions (absent = positions only).
var actions: Array[BossMemoryAction] = []
var has_actions: bool = false


func copy() -> BossObservation:
	var o := BossObservation.new()
	o.tape = tape
	o.speed = speed
	for s: BossSample in samples:
		o.samples.append(s.copy())
	for a: BossMemoryAction in actions:
		o.actions.append(a.copy())
	o.has_actions = has_actions
	return o


static func from_dict(d: Dictionary) -> BossObservation:
	var o := BossObservation.new()
	o.tape = ODJson.integer(d, "tape")
	o.speed = ODJson.num(d, "speed", 1.0)
	for v: Variant in ODJson.array(d, "samples"):
		if v is Dictionary:
			o.samples.append(BossSample.from_dict(v))
	o.has_actions = d.get("actions") is Array
	for v: Variant in ODJson.array(d, "actions"):
		if v is Dictionary:
			o.actions.append(BossMemoryAction.from_dict(v))
	return o


func to_dict() -> Dictionary:
	var s: Array = []
	for x: BossSample in samples:
		s.append(x.to_dict())
	var out := {"tape": tape, "speed": speed, "samples": s}
	if has_actions:
		var a: Array = []
		for x: BossMemoryAction in actions:
			a.append(x.to_dict())
		out["actions"] = a
	return out
