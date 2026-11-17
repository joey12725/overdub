class_name CrusherDef
extends TrapDef
## A crusher (types.ts CrusherDef; docs/TRAPS.md 2): a piston lethal on the stroke and solid (like a
## closed door) while extended. Signal `id` is true while solid (from the stroke until the retract
## completes).

## Floor tiles occupied when extended, ordered from the housing outward.
var cells: Array[Vector2i] = []
## Extended while this evaluates true.
var extend_when: SignalExpr = SignalExpr.of_const(false)
## Presentation only: Dir4.* travel direction; &"" = inferred from the first two cells.
var dir: StringName = &""
## Stroke damage to enemies; NAN = default (TrapTuning.CRUSHER_DAMAGE).
var damage: float = NAN


func _init() -> void:
	kind = EntityKind.CRUSHER


func copy() -> EntityDef:
	var o := CrusherDef.new()
	o.id = id
	o.cells = cells.duplicate()
	o.extend_when = extend_when.copy()
	o.dir = dir
	o.damage = damage
	return o


static func from_dict(d: Dictionary, errors: Array[String] = []) -> CrusherDef:
	var o := CrusherDef.new()
	o.id = ODJson.string(d, "id")
	o.cells = _cells_from(d)
	o.extend_when = _req_expr(d, "extendWhen", errors, "crusher %s.extendWhen" % o.id)
	o.dir = ODJson.sname(d, "dir")
	o.damage = _opt_num(d, "damage")
	return o


func to_dict() -> Dictionary:
	var out := {"kind": String(kind), "id": id, "cells": _cells_to(cells), "extendWhen": extend_when.to_dict()}
	if dir != &"":
		out["dir"] = String(dir)
	_put_num(out, "damage", damage)
	return out
