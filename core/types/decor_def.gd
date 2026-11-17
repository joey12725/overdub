class_name DecorDef
extends EntityDef
## Non-colliding set dressing, purely visual (types.ts DecorDef). Has no id.

## DecorType.*
var type: StringName = DecorType.CRATE
var x: float = 0.0
var y: float = 0.0
## Rotation in quarter turns 0..3 (absent in JSON = 0).
var rot: int = 0
## Free-form variant (graffiti text, neon colour...); "" = absent.
var variant: String = ""


func _init() -> void:
	kind = EntityKind.DECOR


func copy() -> EntityDef:
	var o := DecorDef.new()
	o.type = type
	o.x = x
	o.y = y
	o.rot = rot
	o.variant = variant
	return o


static func from_dict(d: Dictionary) -> DecorDef:
	var o := DecorDef.new()
	o.type = ODJson.sname(d, "type", DecorType.CRATE)
	o.x = ODJson.num(d, "x")
	o.y = ODJson.num(d, "y")
	o.rot = ODJson.integer(d, "rot")
	o.variant = ODJson.string(d, "variant")
	return o


func to_dict() -> Dictionary:
	var out := {"kind": String(kind), "type": String(type), "x": x, "y": y}
	if rot != 0:
		out["rot"] = rot
	if not variant.is_empty():
		out["variant"] = variant
	return out
