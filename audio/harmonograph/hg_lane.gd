class_name HGLane
extends RefCounted
## One drum lane of a Drums channel (engine `lane(...)`): a gate formula decides hits, a velocity
## formula shapes them between `ghost` and `accent`, optionally combined with another lane by
## Boolean `logic`.

const LOGIC: Array[String] = ["none", "AND", "OR", "XOR", "NOT"]

var name: String = ""
## MIDI note of the drum sound.
var note: int = 36
var mute: bool = false
## Gate formula id (a hit where its value > 0).
var gate: String = "euclid"
var params: Dictionary[String, float] = {}
var velocity: String = "accent"
var velocity_params: Dictionary[String, float] = {}
var accent: float = 100.0
var ghost: float = 35.0
## Late offset in milliseconds at the state tempo.
var micro: float = 0.0
## "none", "AND", "OR", "XOR" or "NOT" against lane `other`.
var logic: String = "none"
var other: int = 0
## Also hit where the gate fires one step later.
var approach: bool = false
## Read the gate two steps ahead.
var anticipation: bool = false


## Engine `lane(name, note, k, n, rot)`: a Euclidean lane with the accent velocity mask.
static func make(p_name: String, p_note: int, k: float, n: float = 16.0, rot: float = 0.0) -> HGLane:
	var l := HGLane.new()
	l.name = p_name
	l.note = p_note
	l.params = {"k": k, "n": n, "rot": rot}
	return l


func copy() -> HGLane:
	var l := HGLane.new()
	l.name = name
	l.note = note
	l.mute = mute
	l.gate = gate
	l.params = params.duplicate()
	l.velocity = velocity
	l.velocity_params = velocity_params.duplicate()
	l.accent = accent
	l.ghost = ghost
	l.micro = micro
	l.logic = logic
	l.other = other
	l.approach = approach
	l.anticipation = anticipation
	return l


## Overwrites the fields present in `d` (engine JSON keys).
func apply_dict(d: Dictionary) -> void:
	name = ODJson.string(d, "name", name)
	note = ODJson.integer(d, "note", note)
	mute = ODJson.boolean(d, "mute", mute)
	gate = ODJson.string(d, "gate", gate)
	if d.get("params") is Dictionary:
		params = HGMath.params_from(d["params"])
	velocity = ODJson.string(d, "velocity", velocity)
	if d.get("velocityParams") is Dictionary:
		velocity_params = HGMath.params_from(d["velocityParams"])
	accent = ODJson.num(d, "accent", accent)
	ghost = ODJson.num(d, "ghost", ghost)
	micro = ODJson.num(d, "micro", micro)
	logic = ODJson.string(d, "logic", logic)
	other = ODJson.integer(d, "other", other)
	approach = ODJson.boolean(d, "approach", approach)
	anticipation = ODJson.boolean(d, "anticipation", anticipation)


func to_dict() -> Dictionary:
	return {
		"name": name, "note": note, "mute": mute, "gate": gate, "params": HGMath.params_to_dict(params),
		"velocity": velocity, "velocityParams": HGMath.params_to_dict(velocity_params), "accent": accent,
		"ghost": ghost, "micro": micro, "logic": logic, "other": other, "approach": approach,
		"anticipation": anticipation,
	}
