class_name BossMemoryAction
extends RefCounted
## One remembered attack attempt of a committed tape (types.ts BossMemoryAction).

## Master beat (fractional) at which the attempt fired.
var beat: float = 0.0
## Recorded position of the self at that instant.
var x: float = 0.0
var y: float = 0.0
## ActionKind.*
var kind: StringName = ActionKind.LIGHT


static func make(p_beat: float, p_x: float, p_y: float, p_kind: StringName) -> BossMemoryAction:
	var a := BossMemoryAction.new()
	a.beat = p_beat
	a.x = p_x
	a.y = p_y
	a.kind = p_kind
	return a


func copy() -> BossMemoryAction:
	return BossMemoryAction.make(beat, x, y, kind)


static func from_dict(d: Dictionary) -> BossMemoryAction:
	return BossMemoryAction.make(ODJson.num(d, "beat"), ODJson.num(d, "x"), ODJson.num(d, "y"), ODJson.sname(d, "kind", ActionKind.LIGHT))


func to_dict() -> Dictionary:
	return {"beat": beat, "x": x, "y": y, "kind": String(kind)}
