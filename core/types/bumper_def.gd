class_name BumperDef
extends TrapDef
## A bumper (types.ts BumperDef; docs/TRAPS.md 6): a spring plate that launches what stands on it
## (grounded enemies, the live self; never a recorded self). Signal `id` is a short pulse after each
## firing.

var c: int = 0
var r: int = 0
## Dir4.* launch direction.
var dir: StringName = Dir4.E
## Launch distance in tiles for a body of mass 1; NAN = default (TrapTuning.BUMPER_POWER).
var power: float = NAN
## Fires once each time this BECOMES true.
var fire_when: SignalExpr = SignalExpr.of_const(false)


func _init() -> void:
	kind = EntityKind.BUMPER


func copy() -> EntityDef:
	var o := BumperDef.new()
	o.id = id
	o.c = c
	o.r = r
	o.dir = dir
	o.power = power
	o.fire_when = fire_when.copy()
	return o


static func from_dict(d: Dictionary, errors: Array[String] = []) -> BumperDef:
	var o := BumperDef.new()
	o.id = ODJson.string(d, "id")
	o.c = ODJson.integer(d, "c")
	o.r = ODJson.integer(d, "r")
	o.dir = ODJson.sname(d, "dir")
	o.power = _opt_num(d, "power")
	o.fire_when = _req_expr(d, "fireWhen", errors, "bumper %s.fireWhen" % o.id)
	return o


func to_dict() -> Dictionary:
	var out := {"kind": String(kind), "id": id, "c": c, "r": r, "dir": String(dir)}
	_put_num(out, "power", power)
	out["fireWhen"] = fire_when.to_dict()
	return out
