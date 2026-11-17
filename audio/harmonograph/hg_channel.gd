class_name HGChannel
extends RefCounted
## One Harmonograph voice (engine `channel(i)`). Field names are the engine's in snake_case; numbers
## the engine treats as JS numbers are floats, and the engine rounds them where it needs integers.
## Build a default with `Harmonograph.channel(i)` (i = 0..7 gives the engine's eight presets).
##
## Pitch pipeline per step n (Harmonograph.compile_channel):
##   at = n·speed + phase (retrograde: cycle − 1 − (at mod cycle)) → formula or Sum normal value
##   → blended with the phrase shape by `contour` → scale degree (absolute or step mode, fold,
##   leap recovery) → snapped to chord tones on strong steps by `gravity` / `palette` → cadence.
## The gate formula decides which steps sound; the velocity formula shapes ghost..accent.

const TYPE_MELODY := "Melody"
const TYPE_BASS := "Bass"
const TYPE_CHORD := "Chord"
const TYPE_DRUMS := "Drums"
const TYPES: Array[String] = [TYPE_MELODY, TYPE_BASS, TYPE_CHORD, TYPE_DRUMS]
const MODES: Array[String] = ["absolute", "step"]
const FOLDS: Array[String] = ["reflect", "wrap", "nearest", "drift"]
const SHAPES: Array[String] = ["arch", "ramp", "flat"]
const REPEATS: Array[String] = ["retrigger", "tie", "suppress"]
const DRUM_VELOCITIES: Array[String] = ["legacy", "formula", "fixed"]
const SUM_MODES: Array[String] = ["contour", "integer"]

var id: int = 0
var name: String = ""
var color: String = ""
## TYPE_MELODY, TYPE_BASS, TYPE_CHORD or TYPE_DRUMS.
var type: String = TYPE_MELODY
## Pitch-contour formula id and its parameters.
var formula: String = "fibonacci"
var params: Dictionary[String, float] = {}
var active: bool = true
## A pending active toggle at a beat (engine `queued: {active, beat}`), applied by compile_timeline.
var has_queued: bool = false
var queued_active: bool = false
var queued_beat: float = 0.0
var solo: bool = false
## Beats per step.
var rate: float = 0.25
## Period P for wave formulas and the retrograde reflection.
var cycle: float = 16.0
## Contour index offset in steps (`at = n·speed + phase`).
var phase: float = 0.0
## 0.5 straight .. 0.75: odd steps are delayed by (swing − 0.5)·2 steps.
var swing: float = 0.5
## Late offset in milliseconds at the state tempo.
var micro: float = 0.0
var gate: String = "euclid"
var gate_params: Dictionary[String, float] = {}
## Note length as a fraction of the step.
var gate_length: float = 0.72
var velocity: String = "accent"
var velocity_params: Dictionary[String, float] = {}
var accent: float = 100.0
var ghost: float = 45.0
## What overlapping repeats of a pitch do: REPEATS.
var repeated: String = "retrigger"
## MIDI range (before `octave`).
var low: float = 57.0
var high: float = 81.0
## 0..1: how many metric levels snap to chord tones (1 = every step).
var gravity: float = 0.4
## 0 chord tones only, 1 pentatonic, 2 scale, 3 scale + chromatic neighbours (with escape).
var palette: int = 2
## "absolute" (value → degree) or "step" (value → interval from the previous degree).
var mode: String = "absolute"
## How out-of-range degrees come back: FOLDS ("drift" also wanders ±3 degrees per phrase).
var fold: String = "reflect"
## Step mode: largest interval in degrees.
var leap: float = 2.0
## Step mode: after a leap larger than 2, step back one degree.
var recovery: bool = true
## Blend weight of the phrase `shape` over the formula contour.
var contour: float = 0.0
var shape: String = "arch"
## Phrase length in steps (state resets, cadence, variation).
var phrase: float = 16.0
## The last step of each phrase lands on the chord root.
var cadence: bool = true
## Phrase-variation amount added to `variation_param` (pattern 0, 1, 0, 2 per phrase).
var variation: float = 0.0
var variation_param: String = "m"
## Octave shift of the range.
var octave: float = 0.0
var glide: float = 0.0
var glide_method: String = "cc"
## Bass: gated notes play the lowest chord root.
var root_anchor: bool = true
## Bass: E(octave_pattern, 8) steps jump up an octave.
var octave_pattern: float = 0.0
var invert: bool = false
## Read the contour backwards inside each `cycle`.
var retrograde: bool = false
## Contour speed (augmentation < 1, diminution > 1).
var speed: float = 1.0
## Use the Sum of `terms` as the contour instead of `formula`.
var sum_enabled: bool = false
## Gate by Sum >= sum_threshold instead of the gate formula.
var sum_gate: bool = false
## Velocity from the Sum.
var sum_velocity: bool = false
var sum_threshold: float = 0.5
## "contour" (normalised terms, bipolar sum) or "integer" (integer terms mod sum_mod).
var sum_mode: String = "contour"
var sum_mod: float = 7.0
var ratio_snap: bool = true
## Always 8 terms.
var terms: Array[HGTerm] = []
## Chord: 0 triad .. 4 thirteenth (when voicing_formula is off).
var extension: int = 0
var inversion: int = 0
## Chord: voice-lead each chord to the previous one inside the range.
var minimal: bool = true
## Chord: odd voices raised by round(spread) octaves.
var spread: float = 0.0
## Chord: milliseconds between successive chord tones.
var strum: float = 0.0
## Chord: 1 strum upward in voicing order, -1 reversed.
var strum_direction: float = 1.0
## Chord: extension and inversion follow the contour value.
var voicing_formula: bool = true
## Chord: the voicing moves by octaves to follow the contour pitch.
var follow_contour: bool = false
## Drums: compile only this lane (-1 = every unmuted lane).
var drum_lane: int = -1
## Drums with a drum_lane: hits come from this channel's formula (value >= drum_threshold).
var drum_formula: bool = false
var drum_threshold: float = 0.5
var drum_velocity: String = "legacy"
## Host fields the engine carries but never reads while compiling (engine null = has_* false).
var pitch_root: float = 0.0
var has_pitch_root: bool = false
var octave_radius: float = 0.0
var has_octave_radius: bool = false
## Drums: always 8 lanes (kick, snare, closed hat, open hat, clap, perc, rim, crash).
var lanes: Array[HGLane] = []
var destination: String = ""
var cc_enabled: bool = false
var cc_number: float = 74.0
var cc_low: float = 0.0
var cc_high: float = 127.0
var cc_formula: String = "sine"


## Sets the contour formula and resets its parameters to the formula defaults (engine `set formula`).
func set_formula(id_: String, p: Dictionary[String, float] = {}) -> void:
	formula = id_
	params = HGFormulas.clean_params(id_, p) if not p.is_empty() else HGFormulas.defaults(id_)


## Sets the gate formula and its parameters (defaults when p is empty).
func set_gate(id_: String, p: Dictionary[String, float] = {}) -> void:
	gate = id_
	gate_params = HGFormulas.clean_params(id_, p) if not p.is_empty() else HGFormulas.defaults(id_)


## Sets the velocity formula and its parameters (defaults when p is empty).
func set_velocity(id_: String, p: Dictionary[String, float] = {}) -> void:
	velocity = id_
	velocity_params = HGFormulas.clean_params(id_, p) if not p.is_empty() else HGFormulas.defaults(id_)


func copy() -> HGChannel:
	var c := HGChannel.new()
	c.id = id
	c.name = name
	c.color = color
	c.type = type
	c.formula = formula
	c.params = params.duplicate()
	c.active = active
	c.has_queued = has_queued
	c.queued_active = queued_active
	c.queued_beat = queued_beat
	c.solo = solo
	c.rate = rate
	c.cycle = cycle
	c.phase = phase
	c.swing = swing
	c.micro = micro
	c.gate = gate
	c.gate_params = gate_params.duplicate()
	c.gate_length = gate_length
	c.velocity = velocity
	c.velocity_params = velocity_params.duplicate()
	c.accent = accent
	c.ghost = ghost
	c.repeated = repeated
	c.low = low
	c.high = high
	c.gravity = gravity
	c.palette = palette
	c.mode = mode
	c.fold = fold
	c.leap = leap
	c.recovery = recovery
	c.contour = contour
	c.shape = shape
	c.phrase = phrase
	c.cadence = cadence
	c.variation = variation
	c.variation_param = variation_param
	c.octave = octave
	c.glide = glide
	c.glide_method = glide_method
	c.root_anchor = root_anchor
	c.octave_pattern = octave_pattern
	c.invert = invert
	c.retrograde = retrograde
	c.speed = speed
	c.sum_enabled = sum_enabled
	c.sum_gate = sum_gate
	c.sum_velocity = sum_velocity
	c.sum_threshold = sum_threshold
	c.sum_mode = sum_mode
	c.sum_mod = sum_mod
	c.ratio_snap = ratio_snap
	var ts: Array[HGTerm] = []
	for t: HGTerm in terms:
		ts.append(t.copy())
	c.terms = ts
	c.extension = extension
	c.inversion = inversion
	c.minimal = minimal
	c.spread = spread
	c.strum = strum
	c.strum_direction = strum_direction
	c.voicing_formula = voicing_formula
	c.follow_contour = follow_contour
	c.drum_lane = drum_lane
	c.drum_formula = drum_formula
	c.drum_threshold = drum_threshold
	c.drum_velocity = drum_velocity
	c.pitch_root = pitch_root
	c.has_pitch_root = has_pitch_root
	c.octave_radius = octave_radius
	c.has_octave_radius = has_octave_radius
	var ls: Array[HGLane] = []
	for l: HGLane in lanes:
		ls.append(l.copy())
	c.lanes = ls
	c.destination = destination
	c.cc_enabled = cc_enabled
	c.cc_number = cc_number
	c.cc_low = cc_low
	c.cc_high = cc_high
	c.cc_formula = cc_formula
	return c


## Engine-shaped channel → HGChannel: starts from the preset `Harmonograph.channel(index % 8)` and
## overwrites every key present (as the engine's importState does, without its validation).
static func from_dict(d: Dictionary, index: int = 0) -> HGChannel:
	var c := Harmonograph.channel(index % 8)
	c.id = index
	c.apply_dict(d)
	return c


## Overwrites the fields present in `d` (engine JSON keys). Terms and lanes merge by position.
func apply_dict(d: Dictionary) -> void:
	id = ODJson.integer(d, "id", id)
	name = ODJson.string(d, "name", name)
	color = ODJson.string(d, "color", color)
	type = ODJson.string(d, "type", type)
	formula = ODJson.string(d, "formula", formula)
	if d.get("params") is Dictionary:
		params = HGMath.params_from(d["params"])
	active = ODJson.boolean(d, "active", active)
	if d.has("queued"):
		var q: Variant = d["queued"]
		has_queued = q is Dictionary
		if has_queued:
			queued_active = ODJson.boolean(q, "active", false)
			queued_beat = ODJson.num(q, "beat", 0.0)
	solo = ODJson.boolean(d, "solo", solo)
	rate = ODJson.num(d, "rate", rate)
	cycle = ODJson.num(d, "cycle", cycle)
	phase = ODJson.num(d, "phase", phase)
	swing = ODJson.num(d, "swing", swing)
	micro = ODJson.num(d, "micro", micro)
	gate = ODJson.string(d, "gate", gate)
	if d.get("gateParams") is Dictionary:
		gate_params = HGMath.params_from(d["gateParams"])
	gate_length = ODJson.num(d, "gateLength", gate_length)
	velocity = ODJson.string(d, "velocity", velocity)
	if d.get("velocityParams") is Dictionary:
		velocity_params = HGMath.params_from(d["velocityParams"])
	accent = ODJson.num(d, "accent", accent)
	ghost = ODJson.num(d, "ghost", ghost)
	repeated = ODJson.string(d, "repeated", repeated)
	low = ODJson.num(d, "low", low)
	high = ODJson.num(d, "high", high)
	gravity = ODJson.num(d, "gravity", gravity)
	palette = ODJson.integer(d, "palette", palette)
	mode = ODJson.string(d, "mode", mode)
	fold = ODJson.string(d, "fold", fold)
	leap = ODJson.num(d, "leap", leap)
	recovery = ODJson.boolean(d, "recovery", recovery)
	contour = ODJson.num(d, "contour", contour)
	shape = ODJson.string(d, "shape", shape)
	phrase = ODJson.num(d, "phrase", phrase)
	cadence = ODJson.boolean(d, "cadence", cadence)
	variation = ODJson.num(d, "variation", variation)
	variation_param = ODJson.string(d, "variationParam", variation_param)
	octave = ODJson.num(d, "octave", octave)
	glide = ODJson.num(d, "glide", glide)
	glide_method = ODJson.string(d, "glideMethod", glide_method)
	root_anchor = ODJson.boolean(d, "rootAnchor", root_anchor)
	octave_pattern = ODJson.num(d, "octavePattern", octave_pattern)
	invert = ODJson.boolean(d, "invert", invert)
	retrograde = ODJson.boolean(d, "retrograde", retrograde)
	speed = ODJson.num(d, "speed", speed)
	sum_enabled = ODJson.boolean(d, "sumEnabled", sum_enabled)
	sum_gate = ODJson.boolean(d, "sumGate", sum_gate)
	sum_velocity = ODJson.boolean(d, "sumVelocity", sum_velocity)
	sum_threshold = ODJson.num(d, "sumThreshold", sum_threshold)
	sum_mode = ODJson.string(d, "sumMode", sum_mode)
	sum_mod = ODJson.num(d, "sumMod", sum_mod)
	ratio_snap = ODJson.boolean(d, "ratioSnap", ratio_snap)
	if d.get("terms") is Array:
		var src: Array = d["terms"]
		var ts: Array[HGTerm] = []
		for j: int in src.size():
			var t: HGTerm = terms[j].copy() if j < terms.size() else HGTerm.new()
			if src[j] is Dictionary:
				t.apply_dict(src[j])
			ts.append(t)
		terms = ts
	extension = ODJson.integer(d, "extension", extension)
	inversion = ODJson.integer(d, "inversion", inversion)
	minimal = ODJson.boolean(d, "minimal", minimal)
	spread = ODJson.num(d, "spread", spread)
	strum = ODJson.num(d, "strum", strum)
	strum_direction = ODJson.num(d, "strumDirection", strum_direction)
	voicing_formula = ODJson.boolean(d, "voicingFormula", voicing_formula)
	follow_contour = ODJson.boolean(d, "followContour", follow_contour)
	if d.has("drumLane"):
		drum_lane = ODJson.integer(d, "drumLane", -1) if ODJson.is_number(d["drumLane"]) else -1
	drum_formula = ODJson.boolean(d, "drumFormula", drum_formula)
	drum_threshold = ODJson.num(d, "drumThreshold", drum_threshold)
	drum_velocity = ODJson.string(d, "drumVelocity", drum_velocity)
	if d.has("pitchRoot"):
		has_pitch_root = ODJson.is_number(d["pitchRoot"])
		pitch_root = float(d["pitchRoot"]) if has_pitch_root else 0.0
	if d.has("octaveRadius"):
		has_octave_radius = ODJson.is_number(d["octaveRadius"])
		octave_radius = float(d["octaveRadius"]) if has_octave_radius else 0.0
	if d.get("lanes") is Array:
		var src: Array = d["lanes"]
		var ls: Array[HGLane] = []
		for j: int in src.size():
			var l: HGLane = lanes[j].copy() if j < lanes.size() else HGLane.new()
			if src[j] is Dictionary:
				l.apply_dict(src[j])
			ls.append(l)
		lanes = ls
	destination = ODJson.string(d, "destination", destination)
	cc_enabled = ODJson.boolean(d, "ccEnabled", cc_enabled)
	cc_number = ODJson.num(d, "ccNumber", cc_number)
	cc_low = ODJson.num(d, "ccLow", cc_low)
	cc_high = ODJson.num(d, "ccHigh", cc_high)
	cc_formula = ODJson.string(d, "ccFormula", cc_formula)


## Engine JSON shape (camelCase keys, null for absent optionals).
func to_dict() -> Dictionary:
	var ts: Array = []
	for t: HGTerm in terms:
		ts.append(t.to_dict())
	var ls: Array = []
	for l: HGLane in lanes:
		ls.append(l.to_dict())
	return {
		"id": id, "name": name, "color": color, "type": type, "formula": formula,
		"params": HGMath.params_to_dict(params), "active": active,
		"queued": {"active": queued_active, "beat": queued_beat} if has_queued else null,
		"solo": solo, "rate": rate, "cycle": cycle, "phase": phase, "swing": swing, "micro": micro,
		"gate": gate, "gateParams": HGMath.params_to_dict(gate_params), "gateLength": gate_length,
		"velocity": velocity, "velocityParams": HGMath.params_to_dict(velocity_params),
		"accent": accent, "ghost": ghost, "repeated": repeated, "low": low, "high": high,
		"gravity": gravity, "palette": palette, "mode": mode, "fold": fold, "leap": leap,
		"recovery": recovery, "contour": contour, "shape": shape, "phrase": phrase,
		"cadence": cadence, "variation": variation, "variationParam": variation_param,
		"octave": octave, "glide": glide, "glideMethod": glide_method, "rootAnchor": root_anchor,
		"octavePattern": octave_pattern, "invert": invert, "retrograde": retrograde, "speed": speed,
		"sumEnabled": sum_enabled, "sumGate": sum_gate, "sumVelocity": sum_velocity,
		"sumThreshold": sum_threshold, "sumMode": sum_mode, "sumMod": sum_mod,
		"ratioSnap": ratio_snap, "terms": ts, "extension": extension, "inversion": inversion,
		"minimal": minimal, "spread": spread, "strum": strum, "strumDirection": strum_direction,
		"voicingFormula": voicing_formula, "followContour": follow_contour,
		"drumLane": drum_lane if drum_lane >= 0 else null, "drumFormula": drum_formula,
		"drumThreshold": drum_threshold, "drumVelocity": drum_velocity,
		"pitchRoot": pitch_root if has_pitch_root else null,
		"octaveRadius": octave_radius if has_octave_radius else null, "lanes": ls,
		"destination": destination, "ccEnabled": cc_enabled, "ccNumber": cc_number,
		"ccLow": cc_low, "ccHigh": cc_high, "ccFormula": cc_formula,
	}
