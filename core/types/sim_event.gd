class_name SimEvent
extends RefCounted
## Something that happened in the world (types.ts SimEvent). Emitted by the sim, consumed by audio,
## render, HUD and the goldens.
##
## Optional fields: tape/target ints use -1 for absent, strings use "", and the two optional floats
## carry has_dir / has_power flags (0 is a meaningful value for both). Build with make() and the
## chainable with_*() setters:
##     w.emit(SimEvent.make(0, SimEventType.HIT, x, y).with_tape(i).with_id(e.id).with_power(m))

## Master substep.
var sub: int = 0
## SimEventType.*
var type: StringName = &""
var x: float = 0.0
var y: float = 0.0
## Self involved; -1 = none.
var tape: int = -1
## Enemy / mechanism involved; "" = none.
var id: String = ""
## Direction in radians, where meaningful. Valid only when has_dir.
var dir: float = 0.0
var has_dir: bool = false
## Momentum / intensity, where meaningful. Valid only when has_power.
var power: float = 0.0
var has_power: bool = false
## Extra discriminator: "light" | "heavy" | archetype | "on" | "off" ...; "" = none.
var detail: String = ""


static func make(p_sub: int, p_type: StringName, p_x: float, p_y: float) -> SimEvent:
	var e := SimEvent.new()
	e.sub = p_sub
	e.type = p_type
	e.x = p_x
	e.y = p_y
	return e


func with_tape(p_tape: int) -> SimEvent:
	tape = p_tape
	return self


func with_id(p_id: String) -> SimEvent:
	id = p_id
	return self


func with_dir(p_dir: float) -> SimEvent:
	dir = p_dir
	has_dir = true
	return self


func with_power(p_power: float) -> SimEvent:
	power = p_power
	has_power = true
	return self


func with_detail(p_detail: String) -> SimEvent:
	detail = p_detail
	return self


func copy() -> SimEvent:
	var o := SimEvent.make(sub, type, x, y)
	o.tape = tape
	o.id = id
	o.dir = dir
	o.has_dir = has_dir
	o.power = power
	o.has_power = has_power
	o.detail = detail
	return o


static func from_dict(d: Dictionary) -> SimEvent:
	var o := SimEvent.make(ODJson.integer(d, "sub"), ODJson.sname(d, "type"), ODJson.num(d, "x"), ODJson.num(d, "y"))
	o.tape = ODJson.integer(d, "tape", -1)
	o.id = ODJson.string(d, "id")
	o.has_dir = ODJson.is_number(d.get("dir"))
	o.dir = ODJson.num(d, "dir")
	o.has_power = ODJson.is_number(d.get("power"))
	o.power = ODJson.num(d, "power")
	o.detail = ODJson.string(d, "detail")
	return o


func to_dict() -> Dictionary:
	var out := {"sub": sub, "type": String(type), "x": x, "y": y}
	if tape >= 0:
		out["tape"] = tape
	if not id.is_empty():
		out["id"] = id
	if has_dir:
		out["dir"] = dir
	if has_power:
		out["power"] = power
	if not detail.is_empty():
		out["detail"] = detail
	return out
