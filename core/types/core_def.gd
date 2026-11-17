class_name CoreDef
extends EntityDef
## A core: an objective target that must be struck (momentum >= threshold) to activate (types.ts
## CoreDef). `id` is the signal id, true once activated.

var x: float = 0.0
var y: float = 0.0
## Momentum needed. Valid only when has_threshold; otherwise the sim's default
## (combat.ts coreThreshold / tuning.ts DEFAULT_CORE_THRESHOLD).
var threshold: float = 0.0
var has_threshold: bool = false


func _init() -> void:
	kind = EntityKind.CORE


func copy() -> EntityDef:
	var o := CoreDef.new()
	o.id = id
	o.x = x
	o.y = y
	o.threshold = threshold
	o.has_threshold = has_threshold
	return o


static func from_dict(d: Dictionary) -> CoreDef:
	var o := CoreDef.new()
	o.id = ODJson.string(d, "id")
	o.x = ODJson.num(d, "x")
	o.y = ODJson.num(d, "y")
	o.has_threshold = ODJson.is_number(d.get("threshold"))
	o.threshold = ODJson.num(d, "threshold")
	return o


func to_dict() -> Dictionary:
	var out := {"kind": String(kind), "id": id, "x": x, "y": y}
	if has_threshold:
		out["threshold"] = threshold
	return out
