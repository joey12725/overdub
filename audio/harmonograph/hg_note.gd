class_name HGNote
extends RefCounted
## One compiled note event (engine compileChannel event).

## Index of the channel in the state it was compiled from.
var channel: int = 0
## MIDI pitch 0..127 (drums: the lane's note).
var pitch: int = 60
## 1..127.
var velocity: int = 100
## Onset on the state's beat clock, including swing / micro / strum offsets.
var beat: float = 0.0
## Length in beats (>= 0.01).
var duration: float = 0.25
## Step index n the note came from (Zeno roll hits: the hit index).
var step: int = 0
## Drum lane index, or -1 for pitched notes.
var lane: int = -1
## Drum lane name ("Kick", "Snare", ...); "" for pitched notes.
var sound: String = ""
## Drum-formula lanes: the channel's formula value that triggered the hit.
var formula_value: float = 0.0
var has_formula_value: bool = false
## Part of a build's Zeno snare roll.
var roll: bool = false


func copy() -> HGNote:
	var n := HGNote.new()
	n.channel = channel
	n.pitch = pitch
	n.velocity = velocity
	n.beat = beat
	n.duration = duration
	n.step = step
	n.lane = lane
	n.sound = sound
	n.formula_value = formula_value
	n.has_formula_value = has_formula_value
	n.roll = roll
	return n


## Engine event shape: {pitch, velocity, beat, duration, step, lane?, formulaValue?, roll?}.
func to_dict() -> Dictionary:
	var d: Dictionary = {"pitch": pitch, "velocity": velocity, "beat": beat, "duration": duration, "step": step}
	if lane >= 0:
		d["lane"] = lane
	if has_formula_value:
		d["formulaValue"] = formula_value
	if roll:
		d["roll"] = true
	return d
