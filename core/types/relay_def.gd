class_name RelayDef
extends TrapDef
## A relay (types.ts RelayDef; docs/TRAPS.md 8): signal logic with memory that turns a trigger into a
## beat-quantised pulse, latch or toggle. Signal `id` is its output; `<id>.armed` is true from the
## trigger until it fires.

const MODE_PULSE: StringName = &"pulse"
const MODE_LATCH: StringName = &"latch"
const MODE_TOGGLE: StringName = &"toggle"

## The relay arms each time this BECOMES true.
var trigger: SignalExpr = SignalExpr.of_const(false)
## MODE_*; &"" = default (pulse).
var mode: StringName = &""
## Master beats; NAN = defaults (TrapTuning.RELAY_QUANTIZE / RELAY_DELAY / RELAY_HOLD).
var quantize: float = NAN
var delay: float = NAN
var hold: float = NAN
## Where to draw its indicator lamp; NAN = not given (the sim uses 0).
var x: float = NAN
var y: float = NAN


func _init() -> void:
	kind = EntityKind.RELAY


## The effective mode (pulse when not given).
func mode_or_default() -> StringName:
	return MODE_PULSE if mode == &"" else mode


func copy() -> EntityDef:
	var o := RelayDef.new()
	o.id = id
	o.trigger = trigger.copy()
	o.mode = mode
	o.quantize = quantize
	o.delay = delay
	o.hold = hold
	o.x = x
	o.y = y
	return o


static func from_dict(d: Dictionary, errors: Array[String] = []) -> RelayDef:
	var o := RelayDef.new()
	o.id = ODJson.string(d, "id")
	o.trigger = _req_expr(d, "trigger", errors, "relay %s.trigger" % o.id)
	o.mode = ODJson.sname(d, "mode")
	o.quantize = _opt_num(d, "quantize")
	o.delay = _opt_num(d, "delay")
	o.hold = _opt_num(d, "hold")
	o.x = _opt_num(d, "x")
	o.y = _opt_num(d, "y")
	return o


func to_dict() -> Dictionary:
	var out := {"kind": String(kind), "id": id, "trigger": trigger.to_dict()}
	if mode != &"":
		out["mode"] = String(mode)
	_put_num(out, "quantize", quantize)
	_put_num(out, "delay", delay)
	_put_num(out, "hold", hold)
	_put_num(out, "x", x)
	_put_num(out, "y", y)
	return out
