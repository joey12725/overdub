class_name BreakableDef
extends EntityDef
## A breakable wall tile (types.ts BreakableDef). `id` is the signal id, true once broken.

var c: int = 0
var r: int = 0
## A single melee hit needs at least this much momentum to break it (Scenario K).
var threshold: float = 1.0


func _init() -> void:
	kind = EntityKind.BREAKABLE


func copy() -> EntityDef:
	var o := BreakableDef.new()
	o.id = id
	o.c = c
	o.r = r
	o.threshold = threshold
	return o


static func from_dict(d: Dictionary) -> BreakableDef:
	var o := BreakableDef.new()
	o.id = ODJson.string(d, "id")
	o.c = ODJson.integer(d, "c")
	o.r = ODJson.integer(d, "r")
	o.threshold = ODJson.num(d, "threshold", 1.0)
	return o


func to_dict() -> Dictionary:
	return {"kind": String(kind), "id": id, "c": c, "r": r, "threshold": threshold}
