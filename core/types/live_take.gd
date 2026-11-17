class_name LiveTake
extends RefCounted
## The take being recorded (types.ts SimConfig.live: { index, speed, endMode }).

## TapeIndex.
var index: int = 0
## TapeSpeed.
var speed: float = 1.0
## OD.EndMode.
var end_mode: int = OD.EndMode.STOP


static func make(p_index: int, p_speed: float, p_end_mode: int) -> LiveTake:
	var l := LiveTake.new()
	l.index = p_index
	l.speed = p_speed
	l.end_mode = p_end_mode
	return l


func copy() -> LiveTake:
	return LiveTake.make(index, speed, end_mode)


static func from_dict(d: Dictionary) -> LiveTake:
	return LiveTake.make(ODJson.integer(d, "index"), ODJson.num(d, "speed", 1.0), maxi(0, OD.end_mode_from_name(ODJson.string(d, "endMode", "stop"))))


func to_dict() -> Dictionary:
	return {"index": index, "speed": speed, "endMode": OD.end_mode_name(end_mode)}
