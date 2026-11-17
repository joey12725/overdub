class_name BossSample
extends RefCounted
## One remembered position of a committed tape (types.ts BossMemory.observed[].samples[]).

## Master beat.
var beat: float = 0.0
var x: float = 0.0
var y: float = 0.0


static func make(p_beat: float, p_x: float, p_y: float) -> BossSample:
	var s := BossSample.new()
	s.beat = p_beat
	s.x = p_x
	s.y = p_y
	return s


func copy() -> BossSample:
	return BossSample.make(beat, x, y)


static func from_dict(d: Dictionary) -> BossSample:
	return BossSample.make(ODJson.num(d, "beat"), ODJson.num(d, "x"), ODJson.num(d, "y"))


func to_dict() -> Dictionary:
	return {"beat": beat, "x": x, "y": y}
