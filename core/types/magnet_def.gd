class_name MagnetDef
extends TrapDef
## A magnet (types.ts MagnetDef; docs/TRAPS.md 9): pulls living enemies within a radius toward a
## point while on. Signal `id` is true while pulling.

## Position (world units); it has no collision.
var x: float = 0.0
var y: float = 0.0
## Tiles; bodies farther than this are unaffected.
var radius: float = 0.0
## Tiles per master second for a body of mass 1; NAN = default (TrapTuning.MAGNET_PULL).
var pull: float = NAN
## Pulling while this evaluates true.
var on_when: SignalExpr = SignalExpr.of_const(false)


func _init() -> void:
	kind = EntityKind.MAGNET


func copy() -> EntityDef:
	var o := MagnetDef.new()
	o.id = id
	o.x = x
	o.y = y
	o.radius = radius
	o.pull = pull
	o.on_when = on_when.copy()
	return o


static func from_dict(d: Dictionary, errors: Array[String] = []) -> MagnetDef:
	var o := MagnetDef.new()
	o.id = ODJson.string(d, "id")
	o.x = ODJson.num(d, "x")
	o.y = ODJson.num(d, "y")
	o.radius = ODJson.num(d, "radius")
	o.pull = _opt_num(d, "pull")
	o.on_when = _req_expr(d, "onWhen", errors, "magnet %s.onWhen" % o.id)
	return o


func to_dict() -> Dictionary:
	var out := {"kind": String(kind), "id": id, "x": x, "y": y, "radius": radius}
	_put_num(out, "pull", pull)
	out["onWhen"] = on_when.to_dict()
	return out
