class_name TapeRecorder
extends RefCounted
## Accumulates one take (port of class TapeRecorder in prototype/src/core/tape.ts).
##
## Packed arrays are allocated up front for `ticks + 1` samples. Call `push` once per local tick (after
## the controller step) and `add_event` for each event that tick produced. Positions are stored as
## float32: callers wanting live == playback exactness should feed already float32-rounded values
## (the PlayerController does).
##
## The prototype throws on misuse; here push / add_event return false and append the prototype's
## message to `errors` instead, and create() returns null for a bad tick count.

var index: int = 0
var speed: float = 1.0
## OD.EndMode.
var end_mode: int = OD.EndMode.STOP
var ticks: int = 0
var _pos: PackedFloat32Array
var _facing: PackedFloat32Array
var _anim: PackedByteArray
var _events: Array[TapeEvent] = []
## Samples written so far (≥ 1: the start pose).
var _samples: int = 1

## Local ticks recorded so far (samples − 1).
var recorded_ticks: int:
	get:
		return _samples - 1

## True once every sample of the allowance has been pushed.
var complete: bool:
	get:
		return _samples == ticks + 1


## Use create() for validated construction; an invalid tick count here is reported with push_error
## and treated as 0.
func _init(init: TapeLib.TapeRecorderInit) -> void:
	var n := init.ticks
	if n < 0:
		push_error("TapeRecorder: bad tick count %d" % n)
		n = 0
	index = init.index
	speed = init.speed
	end_mode = init.end_mode
	ticks = n
	_pos.resize((n + 1) * 2)
	_pos.fill(0.0)
	_facing.resize(n + 1)
	_facing.fill(0.0)
	_anim.resize(n + 1)
	_anim.fill(0)
	_pos[0] = init.start_x
	_pos[1] = init.start_y
	_facing[0] = init.start_facing
	_anim[0] = maxi(0, TapeLib.anim_index(init.start_anim))


## Validated constructor: null (and the prototype's message in `errors`) when the tick count is bad.
static func create(init: TapeLib.TapeRecorderInit, errors: Array[String] = []) -> TapeRecorder:
	if not (init.ticks >= 0):
		errors.append("TapeRecorder: bad tick count %d" % init.ticks)
		return null
	return TapeRecorder.new(init)


## Append the pose at the end of the next local tick. Fails once the allowance is used up.
func push(x: float, y: float, facing: float, anim: StringName, errors: Array[String] = []) -> bool:
	if _samples > ticks:
		errors.append("TapeRecorder: tape is full")
		return false
	var i := _samples
	_samples += 1
	_pos[i * 2] = x
	_pos[i * 2 + 1] = y
	_facing[i] = facing
	_anim[i] = maxi(0, TapeLib.anim_index(anim))
	return true


## Record an event. Its tick must be a recorded or the currently-recording tick
## (≤ recorded_ticks, since the event of tick i is added alongside sample i + 1) and events must
## arrive in non-decreasing tick order. The event is copied.
func add_event(ev: TapeEvent, errors: Array[String] = []) -> bool:
	if not (ev.tick >= 0 and ev.tick <= ticks and ev.tick <= recorded_ticks):
		errors.append("TapeRecorder: event tick %d out of range" % ev.tick)
		return false
	if not _events.is_empty() and ev.tick < _events[_events.size() - 1].tick:
		errors.append("TapeRecorder: events must be added in tick order")
		return false
	_events.append(ev.copy())
	return true


## The take so far as a tape whose `ticks` is the number recorded (a prefix of the final tape).
## Arrays are copies; the recorder can keep recording.
func snapshot() -> ODTape:
	var n := _samples
	var t := ODTape.new()
	t.index = index
	t.speed = speed
	t.end_mode = end_mode
	t.ticks = n - 1
	t.pos = _pos.slice(0, n * 2)
	t.facing = _facing.slice(0, n)
	t.anim = _anim.slice(0, n)
	for e: TapeEvent in _events:
		t.events.append(e.copy())
	return t


## The finished tape with the full allowance. If fewer ticks were recorded (an aborted take), the
## remaining samples hold the last recorded pose so the tape stays well-formed.
func finish() -> ODTape:
	var last := _samples - 1
	for i in range(_samples, ticks + 1):
		_pos[i * 2] = _pos[last * 2]
		_pos[i * 2 + 1] = _pos[last * 2 + 1]
		_facing[i] = _facing[last]
		_anim[i] = _anim[last]
	var t := ODTape.new()
	t.index = index
	t.speed = speed
	t.end_mode = end_mode
	t.ticks = ticks
	t.pos = _pos.duplicate()
	t.facing = _facing.duplicate()
	t.anim = _anim.duplicate()
	for e: TapeEvent in _events:
		t.events.append(e.copy())
	return t
