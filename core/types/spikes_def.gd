class_name SpikesDef
extends TrapDef
## Spikes (types.ts SpikesDef; docs/TRAPS.md 1): floor tiles lethal while raised. Signal `id` is true
## while raised.

var cells: Array[Vector2i] = []
## Raised while this evaluates true.
var up_when: SignalExpr = SignalExpr.of_const(false)
## Damage per hit to enemies; NAN = default (TrapTuning.SPIKES_DAMAGE).
var damage: float = NAN


func _init() -> void:
	kind = EntityKind.SPIKES


func copy() -> EntityDef:
	var o := SpikesDef.new()
	o.id = id
	o.cells = cells.duplicate()
	o.up_when = up_when.copy()
	o.damage = damage
	return o


static func from_dict(d: Dictionary, errors: Array[String] = []) -> SpikesDef:
	var o := SpikesDef.new()
	o.id = ODJson.string(d, "id")
	o.cells = _cells_from(d)
	o.up_when = _req_expr(d, "upWhen", errors, "spikes %s.upWhen" % o.id)
	o.damage = _opt_num(d, "damage")
	return o


func to_dict() -> Dictionary:
	var out := {"kind": String(kind), "id": id, "cells": _cells_to(cells), "upWhen": up_when.to_dict()}
	_put_num(out, "damage", damage)
	return out
