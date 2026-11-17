class_name SensorDef
extends TrapDef
## A beam sensor (types.ts SensorDef; docs/TRAPS.md 7): a harmless tripwire whose signal `id` is true
## while a detected body breaks the beam (or forever once tripped, with `latch`).
##
## The ends are kept as 64-bit floats (from_x...), not Vector2, so beam geometry matches the
## prototype's doubles exactly.

const DETECTS_ANY: StringName = &"any"
const DETECTS_SELVES: StringName = &"selves"
const DETECTS_ENEMIES: StringName = &"enemies"

## World-space ends of the beam (tile units); the emitter is at `from`.
var from_x: float = 0.0
var from_y: float = 0.0
var to_x: float = 0.0
var to_y: float = 0.0
## DETECTS_*; &"" = default (any).
var detects: StringName = &""
var latch: bool = false


func _init() -> void:
	kind = EntityKind.SENSOR


## The beam's emitter end as a Vector2 (presentation).
func from_point() -> Vector2:
	return Vector2(from_x, from_y)


## The beam's far end as a Vector2 (presentation).
func to_point() -> Vector2:
	return Vector2(to_x, to_y)


func copy() -> EntityDef:
	var o := SensorDef.new()
	o.id = id
	o.from_x = from_x
	o.from_y = from_y
	o.to_x = to_x
	o.to_y = to_y
	o.detects = detects
	o.latch = latch
	return o


static func from_dict(d: Dictionary, _errors: Array[String] = []) -> SensorDef:
	var o := SensorDef.new()
	o.id = ODJson.string(d, "id")
	var f := ODJson.dict(d, "from")
	var t := ODJson.dict(d, "to")
	o.from_x = ODJson.num(f, "x")
	o.from_y = ODJson.num(f, "y")
	o.to_x = ODJson.num(t, "x")
	o.to_y = ODJson.num(t, "y")
	o.detects = ODJson.sname(d, "detects")
	o.latch = ODJson.boolean(d, "latch")
	return o


func to_dict() -> Dictionary:
	var out := {"kind": String(kind), "id": id, "from": {"x": from_x, "y": from_y}, "to": {"x": to_x, "y": to_y}}
	if detects != &"":
		out["detects"] = String(detects)
	if latch:
		out["latch"] = true
	return out
