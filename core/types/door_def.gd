class_name DoorDef
extends EntityDef
## A door (types.ts DoorDef).

## Tiles the door occupies when closed (Vector2i(c, r): x = column, y = row).
var cells: Array[Vector2i] = []
## Door is open while this evaluates true.
var open_when: SignalExpr = SignalExpr.of_const(false)


func _init() -> void:
	kind = EntityKind.DOOR


func copy() -> EntityDef:
	var o := DoorDef.new()
	o.id = id
	o.cells = cells.duplicate()
	o.open_when = open_when.copy()
	return o


static func from_dict(d: Dictionary, errors: Array[String] = []) -> DoorDef:
	var o := DoorDef.new()
	o.id = ODJson.string(d, "id")
	for c: Variant in ODJson.array(d, "cells"):
		o.cells.append(ODJson.cell(c))
	var e := SignalExpr.from_dict(d.get("openWhen"), errors, "door %s.openWhen" % o.id)
	if e != null:
		o.open_when = e
	return o


func to_dict() -> Dictionary:
	var list: Array = []
	for c: Vector2i in cells:
		list.append(ODJson.cell_to_dict(c))
	return {"kind": String(kind), "id": id, "cells": list, "openWhen": open_when.to_dict()}
