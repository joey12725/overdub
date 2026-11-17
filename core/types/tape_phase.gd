class_name TapePhase
extends RefCounted
## Where a tape's playhead is on its recording at a given master substep (types.ts TapePhase).

## Fractional local tick in [0, ticks].
var tick: float = 0.0
## +1 forward, -1 during a reverse pass, 0 once a 'stop' tape has ended.
var dir: int = 1
## How many end-of-tape boundaries have been crossed so far (0 on the first traversal).
var traversal: int = 0
## True once a 'stop' tape has reached its end.
var ended: bool = false


static func make(p_tick: float, p_dir: int, p_traversal: int, p_ended: bool) -> TapePhase:
	var p := TapePhase.new()
	p.tick = p_tick
	p.dir = p_dir
	p.traversal = p_traversal
	p.ended = p_ended
	return p


func copy() -> TapePhase:
	return TapePhase.make(tick, dir, traversal, ended)


func copy_from(o: TapePhase) -> void:
	tick = o.tick
	dir = o.dir
	traversal = o.traversal
	ended = o.ended


func equals(o: TapePhase) -> bool:
	return tick == o.tick and dir == o.dir and traversal == o.traversal and ended == o.ended


static func from_dict(d: Dictionary) -> TapePhase:
	return TapePhase.make(ODJson.num(d, "tick"), ODJson.integer(d, "dir", 1), ODJson.integer(d, "traversal"), ODJson.boolean(d, "ended"))


func to_dict() -> Dictionary:
	return {"tick": tick, "dir": dir, "traversal": traversal, "ended": ended}
