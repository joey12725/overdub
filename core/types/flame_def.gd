class_name FlameDef
extends TrapDef
## A flame jet (types.ts FlameDef; docs/TRAPS.md 4): a directional hazard from a nozzle tile, cut at
## the first tile that blocks shots. Signal `id` is true while burning.

## The nozzle tile (normally a wall tile); the jet starts on the next tile along `dir`.
var c: int = 0
var r: int = 0
## Dir4.*
var dir: StringName = Dir4.E
## Whole tiles covered when nothing blocks the jet.
var range: float = 0.0
## Burning while this evaluates true.
var on_when: SignalExpr = SignalExpr.of_const(false)
## Damage per hit to enemies; NAN = default (TrapTuning.FLAME_DAMAGE).
var damage: float = NAN


func _init() -> void:
	kind = EntityKind.FLAME


func copy() -> EntityDef:
	var o := FlameDef.new()
	o.id = id
	o.c = c
	o.r = r
	o.dir = dir
	o.range = range
	o.on_when = on_when.copy()
	o.damage = damage
	return o


static func from_dict(d: Dictionary, errors: Array[String] = []) -> FlameDef:
	var o := FlameDef.new()
	o.id = ODJson.string(d, "id")
	o.c = ODJson.integer(d, "c")
	o.r = ODJson.integer(d, "r")
	o.dir = ODJson.sname(d, "dir")
	o.range = ODJson.num(d, "range")
	o.on_when = _req_expr(d, "onWhen", errors, "flame %s.onWhen" % o.id)
	o.damage = _opt_num(d, "damage")
	return o


func to_dict() -> Dictionary:
	var out := {"kind": String(kind), "id": id, "c": c, "r": r, "dir": String(dir), "range": range, "onWhen": on_when.to_dict()}
	_put_num(out, "damage", damage)
	return out
