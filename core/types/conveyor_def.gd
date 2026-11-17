class_name ConveyorDef
extends TrapDef
## A conveyor belt (types.ts ConveyorDef; docs/TRAPS.md 3): carries grounded enemies, floor-height
## projectiles and the LIVE self. Signal `id` is true while running; `<id>.rev` while reversed.

var cells: Array[Vector2i] = []
## Dir4.* travel direction when not reversed.
var dir: StringName = Dir4.E
## Tiles per master second; NAN = default (TrapTuning.CONVEYOR_SPEED).
var speed: float = NAN
## Runs while true; null = always.
var run_when: SignalExpr = null
## Runs the opposite way while true; null = never.
var reverse_when: SignalExpr = null


func _init() -> void:
	kind = EntityKind.CONVEYOR


func copy() -> EntityDef:
	var o := ConveyorDef.new()
	o.id = id
	o.cells = cells.duplicate()
	o.dir = dir
	o.speed = speed
	o.run_when = _copy_expr(run_when)
	o.reverse_when = _copy_expr(reverse_when)
	return o


static func from_dict(d: Dictionary, errors: Array[String] = []) -> ConveyorDef:
	var o := ConveyorDef.new()
	o.id = ODJson.string(d, "id")
	o.cells = _cells_from(d)
	o.dir = ODJson.sname(d, "dir")
	o.speed = _opt_num(d, "speed")
	o.run_when = _opt_expr(d, "runWhen", errors, "conveyor %s.runWhen" % o.id)
	o.reverse_when = _opt_expr(d, "reverseWhen", errors, "conveyor %s.reverseWhen" % o.id)
	return o


func to_dict() -> Dictionary:
	var out := {"kind": String(kind), "id": id, "cells": _cells_to(cells), "dir": String(dir)}
	_put_num(out, "speed", speed)
	_put_expr(out, "runWhen", run_when)
	_put_expr(out, "reverseWhen", reverse_when)
	return out
