class_name BossMemory
extends RefCounted
## Cross-recording memory for the outside-the-loop boss (types.ts BossMemory; BOSS-01/02).
## Built ONLY from committed tapes; discarded takes and the cinematic replay never update it.

## Per committed tape.
var observed: Array[BossObservation] = []


func copy() -> BossMemory:
	var o := BossMemory.new()
	for x: BossObservation in observed:
		o.observed.append(x.copy())
	return o


static func from_dict(d: Dictionary) -> BossMemory:
	var o := BossMemory.new()
	for v: Variant in ODJson.array(d, "observed"):
		if v is Dictionary:
			o.observed.append(BossObservation.from_dict(v))
	return o


func to_dict() -> Dictionary:
	var list: Array = []
	for x: BossObservation in observed:
		list.append(x.to_dict())
	return {"observed": list}
