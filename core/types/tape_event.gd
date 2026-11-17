class_name TapeEvent
extends RefCounted
## A recorded attempt (types.ts TapeEvent). Tapes preserve attempts, never results (PLAY-02).

## Local tick on which the action started.
var tick: int = 0
## ActionKind.*
var kind: StringName = ActionKind.LIGHT
## Facing/aim in radians when the action started. Playback never re-aims (PLAY-01).
var dir: float = 0.0
## Actor position when the action started.
var x: float = 0.0
var y: float = 0.0
## Local-space velocity (tiles per local second) when the action started; feeds momentum.
var vx: float = 0.0
var vy: float = 0.0


static func make(p_tick: int, p_kind: StringName, p_dir: float, p_x: float, p_y: float, p_vx: float = 0.0, p_vy: float = 0.0) -> TapeEvent:
	var e := TapeEvent.new()
	e.tick = p_tick
	e.kind = p_kind
	e.dir = p_dir
	e.x = p_x
	e.y = p_y
	e.vx = p_vx
	e.vy = p_vy
	return e


func copy() -> TapeEvent:
	return TapeEvent.make(tick, kind, dir, x, y, vx, vy)


func equals(o: TapeEvent) -> bool:
	return tick == o.tick and kind == o.kind and dir == o.dir and x == o.x and y == o.y and vx == o.vx and vy == o.vy


## Object form {tick, kind, dir, x, y, vx, vy} (as JSON.stringify of the prototype's TapeEvent).
static func from_dict(d: Dictionary) -> TapeEvent:
	return TapeEvent.make(
		ODJson.integer(d, "tick"), ODJson.sname(d, "kind", ActionKind.LIGHT), ODJson.num(d, "dir"),
		ODJson.num(d, "x"), ODJson.num(d, "y"), ODJson.num(d, "vx"), ODJson.num(d, "vy"))


func to_dict() -> Dictionary:
	return {"tick": tick, "kind": String(kind), "dir": dir, "x": x, "y": y, "vx": vx, "vy": vy}


## SerializedTape tuple form [tick, kindIndex, dir, x, y, vx, vy] (kindIndex into ActionKind.ALL).
func to_tuple() -> Array:
	return [tick, ActionKind.ALL.find(kind), dir, x, y, vx, vy]


## Inverse of to_tuple(). Returns null and appends to `errors` when malformed.
static func from_tuple(t: Variant, errors: Array[String] = []) -> TapeEvent:
	if not (t is Array) or (t as Array).size() != 7:
		errors.append("tape event: expected a 7-element tuple")
		return null
	var a: Array = t
	for v: Variant in a:
		if not ODJson.is_number(v):
			errors.append("tape event: tuple holds a non-number")
			return null
	var k := roundi(float(a[1]))
	if k < 0 or k >= ActionKind.ALL.size():
		errors.append("deserializeTape: bad action kind %d" % k)
		return null
	return TapeEvent.make(roundi(float(a[0])), ActionKind.ALL[k], float(a[2]), float(a[3]), float(a[4]), float(a[5]), float(a[6]))
