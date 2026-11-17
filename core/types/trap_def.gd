class_name TrapDef
extends EntityDef
## Base of the nine trap entities (types.ts TrapDef union; docs/TRAPS.md "Vocabulary"): SpikesDef,
## CrusherDef, ConveyorDef, FlameDef, DartDef, BumperDef, SensorDef, RelayDef, MagnetDef. Simulated by
## Traps (core/traps/traps.gd).
##
## Optional prototype fields: an absent number is NAN (test with is_nan / has_num), an absent
## direction / mode is &"", an absent expression is null. The defaults the simulation applies live in
## TrapTuning; to_dict() writes back only the fields that were given, so a level round-trips.


## True when an optional number was given (not NAN).
static func has_num(v: float) -> bool:
	return not is_nan(v)


## `v` when given, else `def` (the prototype's `v ?? def`).
static func num_or(v: float, def: float) -> float:
	return def if is_nan(v) else v


static func _opt_num(d: Dictionary, key: String) -> float:
	var v: Variant = d.get(key)
	return float(v) if ODJson.is_number(v) else NAN


static func _cells_from(d: Dictionary, key: String = "cells") -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Variant in ODJson.array(d, key):
		out.append(ODJson.cell(c))
	return out


static func _cells_to(cells: Array[Vector2i]) -> Array:
	var list: Array = []
	for c: Vector2i in cells:
		list.append(ODJson.cell_to_dict(c))
	return list


## A required expression: parse errors are reported and a constant false stands in.
static func _req_expr(d: Dictionary, key: String, errors: Array[String], where: String) -> SignalExpr:
	var e := SignalExpr.from_dict(d.get(key), errors, where)
	return e if e != null else SignalExpr.of_const(false)


## An optional expression: null when absent.
static func _opt_expr(d: Dictionary, key: String, errors: Array[String], where: String) -> SignalExpr:
	if not d.has(key) or d.get(key) == null:
		return null
	return SignalExpr.from_dict(d.get(key), errors, where)


static func _copy_expr(e: SignalExpr) -> SignalExpr:
	return e.copy() if e != null else null


## Add `key: v` to `out` when the optional number was given.
static func _put_num(out: Dictionary, key: String, v: float) -> void:
	if not is_nan(v):
		out[key] = v


## Add `key: e` to `out` when the optional expression was given.
static func _put_expr(out: Dictionary, key: String, e: SignalExpr) -> void:
	if e != null:
		out[key] = e.to_dict()
