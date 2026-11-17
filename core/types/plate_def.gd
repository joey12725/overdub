class_name PlateDef
extends EntityDef
## A pressure plate (types.ts PlateDef). `id` is the signal id, true while an effective body (alive +
## synced self, or an enemy) stands on it.

var c: int = 0
var r: int = 0
## Requires the 'heavyStep' ability or a brute/boss body (absent in JSON = false).
var heavy: bool = false


func _init() -> void:
	kind = EntityKind.PLATE


func copy() -> EntityDef:
	var o := PlateDef.new()
	o.id = id
	o.c = c
	o.r = r
	o.heavy = heavy
	return o


static func from_dict(d: Dictionary) -> PlateDef:
	var o := PlateDef.new()
	o.id = ODJson.string(d, "id")
	o.c = ODJson.integer(d, "c")
	o.r = ODJson.integer(d, "r")
	o.heavy = ODJson.boolean(d, "heavy")
	return o


func to_dict() -> Dictionary:
	var out := {"kind": String(kind), "id": id, "c": c, "r": r}
	if heavy:
		out["heavy"] = true
	return out
