class_name HGState
extends RefCounted
## The Harmonograph's global musical state (engine `initialState()`): key, scale, harmony source,
## tempo and the channels. Build one with `Harmonograph.initial_state()` (eight preset channels) or
## `Harmonograph.make_state()` (no channels), then configure.
##
## Not modelled (host features outside the game's needs): `sections` / `queuedSection` (section
## snapshots and recall).

const CHORD_SOURCES: Array[String] = ["pads", "progression", "formula"]
const QUALITIES: Array[String] = ["diatonic", "major", "minor", "dominant", "diminished"]
const BORROWED: Array[String] = ["", "♭II", "♭III", "♭VI", "♭VII", "iv", "V/V", "V/vi", "TT", "sus"]

var version: int = 1
## Beats per minute (micro / strum milliseconds convert to beats with it).
var tempo: float = 132.0
## Pitch class of the key (0 = C).
var root: int = 9
## Key of Harmonograph.SCALES ("Minor", "Dorian", ...). Unknown names behave as "Minor".
var scale: String = "Minor"
## Chord degree for chord_source "pads" (and for "formula" with plr).
var degree: int = 0
## Pads + escape: an explicit chromatic chord root (has_chord_root false = engine null).
var chord_root: int = 0
var has_chord_root: bool = false
## Borrowed chord name (BORROWED), used only with escape.
var borrowed: String = ""
## "diatonic" or a fixed chord quality (QUALITIES).
var quality: String = "diatonic"
## 0 triad, 1 seventh, 2 ninth, 3 eleventh, 4 thirteenth.
var extension: int = 0
var inversion: int = 0
var spread: float = 0.0
var chord_octave: int = 0
## Sus-style shift: third → fourth, seventh → flat seventh.
var shift: bool = false
var static_mode: bool = true
## Allow chromatic (out-of-scale) voices; off snaps everything into the scale.
var escape: bool = false
## "pads" (fixed degree), "progression" (progression list) or "formula" (chord_formula picks).
var chord_source: String = "progression"
## Scale degrees, one per chord_rate beats.
var progression: Array[int] = [0, 5, 2, 6]
var chord_formula: String = "circlechord"
var chord_params: Dictionary[String, float] = {}
## Beats per chord.
var chord_rate: float = 4.0
## Degrees a chord formula may pick from.
var allowed: Array[int] = [0, 1, 2, 3, 4, 5, 6]
## Launch quantisation for queued changes: "bar", "beat" or "phrase".
var quantize: String = "bar"
var phrase: float = 16.0
var selected: int = 0
var scene: String = "Stack"
var style: String = "3B1B"
var section: String = "Drop"
var build: HGBuild = HGBuild.new()
var channels: Array[HGChannel] = []


## Deep copy (engine `copy(s)`).
func copy() -> HGState:
	var s := HGState.new()
	s.version = version
	s.tempo = tempo
	s.root = root
	s.scale = scale
	s.degree = degree
	s.chord_root = chord_root
	s.has_chord_root = has_chord_root
	s.borrowed = borrowed
	s.quality = quality
	s.extension = extension
	s.inversion = inversion
	s.spread = spread
	s.chord_octave = chord_octave
	s.shift = shift
	s.static_mode = static_mode
	s.escape = escape
	s.chord_source = chord_source
	s.progression = progression.duplicate()
	s.chord_formula = chord_formula
	s.chord_params = chord_params.duplicate()
	s.chord_rate = chord_rate
	s.allowed = allowed.duplicate()
	s.quantize = quantize
	s.phrase = phrase
	s.selected = selected
	s.scene = scene
	s.style = style
	s.section = section
	s.build = build.copy()
	var cs: Array[HGChannel] = []
	for c: HGChannel in channels:
		cs.append(c.copy())
	s.channels = cs
	return s


## Shallow copy sharing the channels, with a different global extension (the engine's
## `{...s, extension}` used for chord voicing).
func with_extension(ext: int) -> HGState:
	var s := HGState.new()
	s.version = version
	s.tempo = tempo
	s.root = root
	s.scale = scale
	s.degree = degree
	s.chord_root = chord_root
	s.has_chord_root = has_chord_root
	s.borrowed = borrowed
	s.quality = quality
	s.extension = ext
	s.inversion = inversion
	s.spread = spread
	s.chord_octave = chord_octave
	s.shift = shift
	s.static_mode = static_mode
	s.escape = escape
	s.chord_source = chord_source
	s.progression = progression
	s.chord_formula = chord_formula
	s.chord_params = chord_params
	s.chord_rate = chord_rate
	s.allowed = allowed
	s.quantize = quantize
	s.phrase = phrase
	s.selected = selected
	s.scene = scene
	s.style = style
	s.section = section
	s.build = build
	s.channels = channels
	return s


## Engine-shaped state → HGState. Keys absent from `d` keep the initial_state() defaults; channels
## start from the engine presets (`channel(i % 8)`), as importState does, without its validation.
static func from_dict(d: Dictionary) -> HGState:
	var s := Harmonograph.initial_state()
	s.version = ODJson.integer(d, "version", s.version)
	s.tempo = ODJson.num(d, "tempo", s.tempo)
	s.root = ODJson.integer(d, "root", s.root)
	s.scale = ODJson.string(d, "scale", s.scale)
	s.degree = ODJson.integer(d, "degree", s.degree)
	if d.has("chordRoot"):
		s.has_chord_root = ODJson.is_number(d["chordRoot"])
		s.chord_root = ODJson.integer(d, "chordRoot", 0) if s.has_chord_root else 0
	s.borrowed = ODJson.string(d, "borrowed", s.borrowed)
	s.quality = ODJson.string(d, "quality", s.quality)
	s.extension = ODJson.integer(d, "extension", s.extension)
	s.inversion = ODJson.integer(d, "inversion", s.inversion)
	s.spread = ODJson.num(d, "spread", s.spread)
	s.chord_octave = ODJson.integer(d, "chordOctave", s.chord_octave)
	s.shift = ODJson.boolean(d, "shift", s.shift)
	s.static_mode = ODJson.boolean(d, "staticMode", s.static_mode)
	s.escape = ODJson.boolean(d, "escape", s.escape)
	s.chord_source = ODJson.string(d, "chordSource", s.chord_source)
	if d.get("progression") is Array:
		s.progression = ODJson.ints(d["progression"])
	s.chord_formula = ODJson.string(d, "chordFormula", s.chord_formula)
	if d.get("chordParams") is Dictionary:
		s.chord_params = HGMath.params_from(d["chordParams"])
	s.chord_rate = ODJson.num(d, "chordRate", s.chord_rate)
	if d.get("allowed") is Array:
		s.allowed = ODJson.ints(d["allowed"])
	s.quantize = ODJson.string(d, "quantize", s.quantize)
	s.phrase = ODJson.num(d, "phrase", s.phrase)
	s.selected = ODJson.integer(d, "selected", s.selected)
	s.scene = ODJson.string(d, "scene", s.scene)
	s.style = ODJson.string(d, "style", s.style)
	s.section = ODJson.string(d, "section", s.section)
	if d.get("build") is Dictionary:
		s.build.apply_dict(d["build"])
	if d.get("channels") is Array:
		var src: Array = d["channels"]
		var cs: Array[HGChannel] = []
		for i: int in src.size():
			var cd: Dictionary = src[i] if src[i] is Dictionary else {}
			cs.append(HGChannel.from_dict(cd, i))
		s.channels = cs
	return s


## Engine JSON shape (without sections).
func to_dict() -> Dictionary:
	var cs: Array = []
	for c: HGChannel in channels:
		cs.append(c.to_dict())
	var prog: Array = []
	for v: int in progression:
		prog.append(v)
	var al: Array = []
	for v: int in allowed:
		al.append(v)
	return {
		"version": version, "tempo": tempo, "root": root, "scale": scale, "degree": degree,
		"chordRoot": chord_root if has_chord_root else null, "borrowed": borrowed,
		"quality": quality, "extension": extension, "inversion": inversion, "spread": spread,
		"chordOctave": chord_octave, "shift": shift, "staticMode": static_mode, "escape": escape,
		"chordSource": chord_source, "progression": prog, "chordFormula": chord_formula,
		"chordParams": HGMath.params_to_dict(chord_params), "chordRate": chord_rate,
		"allowed": al, "quantize": quantize, "phrase": phrase, "selected": selected,
		"scene": scene, "style": style, "section": section, "build": build.to_dict(),
		"channels": cs,
	}
