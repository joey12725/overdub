class_name Resolution
extends RefCounted
## Result of resolving the whole combined encounter under playback rules (types.ts Resolution;
## REC-06, OPEN-07).

var outcome: Outcome = Outcome.new()
## One snapshot every OD.FRAME_SUBS substeps, starting at substep 0; replayed verbatim by the cinematic.
var frames: Array[FrameSnapshot] = []
var events: Array[SimEvent] = []
var horizon_subs: int = 0


## The frame at or just before master substep `sub` (clamped to the stored range), or null when empty.
func frame_at_sub(sub: int) -> FrameSnapshot:
	if frames.is_empty():
		return null
	return frames[clampi(floori(float(sub) / OD.FRAME_SUBS), 0, frames.size() - 1)]


func copy() -> Resolution:
	var o := Resolution.new()
	o.outcome = outcome.copy()
	for f: FrameSnapshot in frames:
		o.frames.append(f.copy())
	for e: SimEvent in events:
		o.events.append(e.copy())
	o.horizon_subs = horizon_subs
	return o


static func from_dict(d: Dictionary) -> Resolution:
	var o := Resolution.new()
	o.outcome = Outcome.from_dict(ODJson.dict(d, "outcome"))
	for v: Variant in ODJson.array(d, "frames"):
		if v is Dictionary:
			o.frames.append(FrameSnapshot.from_dict(v))
	for v: Variant in ODJson.array(d, "events"):
		if v is Dictionary:
			o.events.append(SimEvent.from_dict(v))
	o.horizon_subs = ODJson.integer(d, "horizonSubs")
	return o


func to_dict() -> Dictionary:
	var f: Array = []
	for x: FrameSnapshot in frames:
		f.append(x.to_dict())
	var e: Array = []
	for x: SimEvent in events:
		e.append(x.to_dict())
	return {"outcome": outcome.to_dict(), "frames": f, "events": e, "horizonSubs": horizon_subs}
