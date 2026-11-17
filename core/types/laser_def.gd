class_name LaserDef
extends EntityDef
## A laser (types.ts LaserDef). The beam runs between two tile centres; it kills living, synced
## selves that touch it while on.

## Prototype keys "from" / "to" (sim axes).
var from: Vector2 = Vector2.ZERO
var to: Vector2 = Vector2.ZERO
## Laser is on while this evaluates true.
var on_when: SignalExpr = SignalExpr.of_const(true)


func _init() -> void:
	kind = EntityKind.LASER


func copy() -> EntityDef:
	var o := LaserDef.new()
	o.id = id
	o.from = from
	o.to = to
	o.on_when = on_when.copy()
	return o


static func from_dict(d: Dictionary, errors: Array[String] = []) -> LaserDef:
	var o := LaserDef.new()
	o.id = ODJson.string(d, "id")
	o.from = ODJson.vec2(d.get("from"))
	o.to = ODJson.vec2(d.get("to"))
	var e := SignalExpr.from_dict(d.get("onWhen"), errors, "laser %s.onWhen" % o.id)
	if e != null:
		o.on_when = e
	return o


func to_dict() -> Dictionary:
	return {
		"kind": String(kind),
		"id": id,
		"from": ODJson.vec2_to_dict(from),
		"to": ODJson.vec2_to_dict(to),
		"onWhen": on_when.to_dict(),
	}
