class_name MechSnap
extends RefCounted
## One mechanism or trap at one instant (types.ts MechSnap). Traps (docs/TRAPS.md "Snapshot fields")
## add the optional warn / dir / reach / firing fields; each is present only when its has_* flag is.

var id: String = ""
## MechKind.*
var kind: StringName = MechKind.DOOR
## Door: open. Switch/plate/core/exit: on. Breakable: broken. Laser: firing. Traps: see TRAPS.md
## (spikes raised, crusher solid, conveyor running, flame burning, dart enabled, bumper pulse,
## sensor tripped, relay output, magnet pulling).
var on: bool = false
## Doors: 0..1 open/close progress. Spikes 1/0, crusher extension, dart shot progress, bumper
## spring return, relay armed progress. Valid only when has_t.
var t: float = 0.0
var has_t: bool = false
## Traps: telegraph 0..1 rising over the beat before a beat-timed activation (relay: 1 while armed).
var warn: float = 0.0
var has_warn: bool = false
## Traps: direction in radians (crusher piston travel, belt travel, flame / dart lane, bumper launch).
var dir: float = 0.0
var has_dir: bool = false
## Traps: tiles covered right now (flame jet) or live beam length (sensor).
var reach: float = 0.0
var has_reach: bool = false
## Traps: dart muzzle flash / bumper firing.
var firing: bool = false
var has_firing: bool = false


func with_t(v: float) -> MechSnap:
	t = v
	has_t = true
	return self


func with_warn(v: float) -> MechSnap:
	warn = v
	has_warn = true
	return self


func with_dir(v: float) -> MechSnap:
	dir = v
	has_dir = true
	return self


func with_reach(v: float) -> MechSnap:
	reach = v
	has_reach = true
	return self


func with_firing(v: bool) -> MechSnap:
	firing = v
	has_firing = true
	return self


func copy() -> MechSnap:
	var o := MechSnap.new()
	o.id = id
	o.kind = kind
	o.on = on
	o.t = t
	o.has_t = has_t
	o.warn = warn
	o.has_warn = has_warn
	o.dir = dir
	o.has_dir = has_dir
	o.reach = reach
	o.has_reach = has_reach
	o.firing = firing
	o.has_firing = has_firing
	return o


static func from_dict(d: Dictionary) -> MechSnap:
	var o := MechSnap.new()
	o.id = ODJson.string(d, "id")
	o.kind = ODJson.sname(d, "kind", MechKind.DOOR)
	o.on = ODJson.boolean(d, "on")
	o.has_t = ODJson.is_number(d.get("t"))
	o.t = ODJson.num(d, "t")
	o.has_warn = ODJson.is_number(d.get("warn"))
	o.warn = ODJson.num(d, "warn")
	o.has_dir = ODJson.is_number(d.get("dir"))
	o.dir = ODJson.num(d, "dir")
	o.has_reach = ODJson.is_number(d.get("reach"))
	o.reach = ODJson.num(d, "reach")
	o.has_firing = d.get("firing") is bool
	o.firing = ODJson.boolean(d, "firing")
	return o


## Prototype key order: id, kind, on, t, warn, dir, reach, firing (each optional one only when set).
func to_dict() -> Dictionary:
	var out := {"id": id, "kind": String(kind), "on": on}
	if has_t:
		out["t"] = t
	if has_warn:
		out["warn"] = warn
	if has_dir:
		out["dir"] = dir
	if has_reach:
		out["reach"] = reach
	if has_firing:
		out["firing"] = firing
	return out
