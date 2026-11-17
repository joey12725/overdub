class_name SwitchDef
extends EntityDef
## A switch (types.ts SwitchDef). `id` is the signal id, true while the switch is on. An 'interact'
## attempt in range toggles it.

var x: float = 0.0
var y: float = 0.0
## Starts on (absent in JSON = false).
var initial: bool = false


func _init() -> void:
	kind = EntityKind.SWITCH


func copy() -> EntityDef:
	var o := SwitchDef.new()
	o.id = id
	o.x = x
	o.y = y
	o.initial = initial
	return o


static func from_dict(d: Dictionary) -> SwitchDef:
	var o := SwitchDef.new()
	o.id = ODJson.string(d, "id")
	o.x = ODJson.num(d, "x")
	o.y = ODJson.num(d, "y")
	o.initial = ODJson.boolean(d, "initial")
	return o


func to_dict() -> Dictionary:
	var out := {"kind": String(kind), "id": id, "x": x, "y": y}
	if initial:
		out["initial"] = true
	return out
