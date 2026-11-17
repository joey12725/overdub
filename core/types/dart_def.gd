class_name DartDef
extends TrapDef
## A dart launcher (types.ts DartDef; docs/TRAPS.md 5): an indestructible shooter firing straight
## darts on a beat grid, never targeting. Signal `id` is true while enabled.

## The launcher tile (normally a wall tile).
var c: int = 0
var r: int = 0
## Dir4.* lane direction.
var dir: StringName = Dir4.E
## Fires on master beats offset + k*every; NAN = defaults (TrapTuning.DART_EVERY / DART_OFFSET).
var every: float = NAN
var offset: float = NAN
## Fires only while true; null = always.
var enabled_when: SignalExpr = null
## Dart speed, tiles per master second; NAN = default (TrapTuning.DART_SPEED).
var speed: float = NAN


func _init() -> void:
	kind = EntityKind.DART


func copy() -> EntityDef:
	var o := DartDef.new()
	o.id = id
	o.c = c
	o.r = r
	o.dir = dir
	o.every = every
	o.offset = offset
	o.enabled_when = _copy_expr(enabled_when)
	o.speed = speed
	return o


static func from_dict(d: Dictionary, errors: Array[String] = []) -> DartDef:
	var o := DartDef.new()
	o.id = ODJson.string(d, "id")
	o.c = ODJson.integer(d, "c")
	o.r = ODJson.integer(d, "r")
	o.dir = ODJson.sname(d, "dir")
	o.every = _opt_num(d, "every")
	o.offset = _opt_num(d, "offset")
	o.enabled_when = _opt_expr(d, "enabledWhen", errors, "dart %s.enabledWhen" % o.id)
	o.speed = _opt_num(d, "speed")
	return o


func to_dict() -> Dictionary:
	var out := {"kind": String(kind), "id": id, "c": c, "r": r, "dir": String(dir)}
	_put_num(out, "every", every)
	_put_num(out, "offset", offset)
	_put_expr(out, "enabledWhen", enabled_when)
	_put_num(out, "speed", speed)
	return out
