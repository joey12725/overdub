class_name ODTape
extends RefCounted
## One cassette's performance: a fixed trajectory plus action events (types.ts Tape; PLAY-01).
## `ticks` local ticks were recorded, so pose arrays hold `ticks + 1` samples (sample 0 = start pose).
##
## Named ODTape (not Tape) per docs/GODOT-PORT.md. The tape *functions* of prototype/src/core/tape.ts
## live in TapeLib (core/tape.gd); TapeLib.serialize_tape / deserialize_tape / clone_tape delegate to
## to_dict / from_dict / copy here.
##
## pos/facing are PackedFloat32Array, which gives the prototype's Float32Array rounding: a value
## written into them is rounded to float32 exactly like Math.fround.

## TapeIndex 0..3.
var index: int = 0
## TapeSpeed (one of OD.ALL_SPEEDS).
var speed: float = 1.0
## OD.EndMode.
var end_mode: int = OD.EndMode.STOP
## Number of local ticks recorded (level.bars worth).
var ticks: int = 0
## Interleaved x, y per sample. Size (ticks + 1) * 2.
var pos: PackedFloat32Array = PackedFloat32Array()
## Facing in radians per sample. Size ticks + 1.
var facing: PackedFloat32Array = PackedFloat32Array()
## AnimState index (into OD.ANIM_STATES) per sample. Size ticks + 1.
var anim: PackedByteArray = PackedByteArray()
var events: Array[TapeEvent] = []

## SerializedTape format version (tape.ts SerializedTape.v).
const SERIAL_VERSION: int = 1


## A tape with zeroed pose arrays sized for `p_ticks` recorded ticks.
static func create(p_index: int, p_speed: float, p_end_mode: int, p_ticks: int) -> ODTape:
	var t := ODTape.new()
	t.index = p_index
	t.speed = p_speed
	t.end_mode = p_end_mode
	t.ticks = p_ticks
	t.pos.resize((p_ticks + 1) * 2)
	t.facing.resize(p_ticks + 1)
	t.anim.resize(p_ticks + 1)
	return t


## Deep copy (tape.ts cloneTape).
func copy() -> ODTape:
	var t := ODTape.new()
	t.index = index
	t.speed = speed
	t.end_mode = end_mode
	t.ticks = ticks
	t.pos = pos.duplicate()
	t.facing = facing.duplicate()
	t.anim = anim.duplicate()
	for e: TapeEvent in events:
		t.events.append(e.copy())
	return t


## SerializedTape: {v: 1, index, speed, endMode, ticks, pos, facing, anim, events} with the pose arrays
## as little-endian bytes in standard padded base64 and events as [tick, kindIndex, dir, x, y, vx, vy]
## tuples. Byte-compatible with the prototype's serializeTape.
func to_dict() -> Dictionary:
	var ev: Array = []
	for e: TapeEvent in events:
		ev.append(e.to_tuple())
	return {
		"v": SERIAL_VERSION,
		"index": index,
		"speed": speed,
		"endMode": OD.end_mode_name(end_mode),
		"ticks": ticks,
		"pos": Marshalls.raw_to_base64(pos.to_byte_array()),
		"facing": Marshalls.raw_to_base64(facing.to_byte_array()),
		"anim": Marshalls.raw_to_base64(anim),
		"events": ev,
	}


## Inverse of to_dict (tape.ts deserializeTape). Returns null and appends a message to `errors` on
## malformed input (wrong version, lengths, kinds, speed, end mode or base64).
static func from_dict(d: Variant, errors: Array[String] = []) -> ODTape:
	if not (d is Dictionary) or ODJson.integer(d, "v", -1) != SERIAL_VERSION:
		errors.append("deserializeTape: unsupported version")
		return null
	var dd: Dictionary = d
	var raw_ticks: Variant = dd.get("ticks")
	if not ODJson.is_number(raw_ticks) or float(raw_ticks) != floorf(float(raw_ticks)) or float(raw_ticks) < 0.0:
		errors.append("deserializeTape: bad ticks")
		return null
	var t := ODTape.new()
	t.ticks = int(raw_ticks)
	t.index = ODJson.integer(dd, "index")
	if t.index < 0 or t.index >= OD.TAPE_COUNT:
		errors.append("deserializeTape: bad index %d" % t.index)
		return null
	t.speed = ODJson.num(dd, "speed", 1.0)
	if not OD.is_speed(t.speed):
		errors.append("deserializeTape: bad speed %s" % t.speed)
		return null
	t.end_mode = OD.end_mode_from_name(ODJson.string(dd, "endMode"))
	if t.end_mode < 0:
		errors.append("deserializeTape: bad endMode")
		return null
	var pos_bytes: Variant = _decode_base64(ODJson.string(dd, "pos"), errors)
	var facing_bytes: Variant = _decode_base64(ODJson.string(dd, "facing"), errors)
	var anim_bytes: Variant = _decode_base64(ODJson.string(dd, "anim"), errors)
	if pos_bytes == null or facing_bytes == null or anim_bytes == null:
		return null
	var pb: PackedByteArray = pos_bytes
	var fb: PackedByteArray = facing_bytes
	if pb.size() % 4 != 0 or fb.size() % 4 != 0:
		errors.append("deserializeTape: float array byte length not a multiple of 4")
		return null
	t.pos = pb.to_float32_array()
	t.facing = fb.to_float32_array()
	t.anim = anim_bytes
	if t.pos.size() != (t.ticks + 1) * 2 or t.facing.size() != t.ticks + 1 or t.anim.size() != t.ticks + 1:
		errors.append("deserializeTape: array lengths do not match ticks")
		return null
	for tuple: Variant in ODJson.array(dd, "events"):
		var e := TapeEvent.from_tuple(tuple, errors)
		if e == null:
			return null
		t.events.append(e)
	return t


const _B64_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"


## Strict standard padded base64 -> bytes; null (plus an error) when malformed.
static func _decode_base64(s: String, errors: Array[String]) -> Variant:
	if s.length() % 4 != 0:
		errors.append("base64: length not a multiple of 4")
		return null
	var n := s.length()
	for i in n:
		var ch := s[i]
		if ch == "=":
			if i < n - 2 or (i == n - 2 and s[n - 1] != "="):
				errors.append("base64: bad character at %d" % i)
				return null
		elif not _B64_CHARS.contains(ch):
			errors.append("base64: bad character at %d" % i)
			return null
	if n == 0:
		return PackedByteArray()
	return Marshalls.base64_to_raw(s)
