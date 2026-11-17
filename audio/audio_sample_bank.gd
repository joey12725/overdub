class_name AudioSampleBank
extends RefCounted
## The generated sample library (assets/audio/manifest.json, built by art/audio/make_samples.py):
## families of multi-sampled instruments, drums, blips and SFX. Picks the nearest sample for a
## pitch, rotates round-robin variants, and owns the loaded AudioStreamWAVs (with their loop points).
##
## Every file starts with `pad` seconds of digital silence; AudioVoiceEngine seeks into that pad so
## a voice starting on a mix boundary still places its attack at the intended time.

const MANIFEST_PATH := "res://assets/audio/manifest.json"
const ROOT_DIR := "res://assets/audio/"
## Largest pitch shift (semitones) before the target is moved by octaves into a family's range.
const MAX_SHIFT := 3.0

var pad: float = 0.1
var sample_rate: int = 44100
var families: Dictionary = {}
var errors: Array[String] = []


class Sample:
	extends RefCounted
	var file: String = ""
	## MIDI root, -1 for unpitched samples.
	var root: int = -1
	var frames: int = 0
	var loop_begin: int = -1
	var loop_end: int = -1
	var stream: AudioStreamWAV


class Family:
	extends RefCounted
	var name: StringName = &""
	var pitched: bool = false
	var loop: bool = false
	## Default release fade (seconds).
	var release: float = 0.05
	## Sorted by root for pitched families.
	var samples: Array[Sample] = []
	var lo: int = 0
	var hi: int = 0
	var _rr: int = 0


## The sample to play for a trigger and its pitch_scale.
class Pick:
	extends RefCounted
	var sample: Sample
	var pitch_scale: float = 1.0
	## Semitones of shift actually applied (for tests).
	var shift: float = 0.0


## Loads the manifest; with `load_streams` also loads every sample (main thread, once).
func load_manifest(load_streams: bool) -> bool:
	errors.clear()
	families.clear()
	if not FileAccess.file_exists(MANIFEST_PATH):
		errors.append("missing " + MANIFEST_PATH)
		return false
	var parse_errors: Array[String] = []
	var d: Variant = ODJson.read_file(MANIFEST_PATH, parse_errors)
	if not (d is Dictionary):
		errors.append("bad manifest: %s" % ", ".join(parse_errors))
		return false
	pad = ODJson.num(d, "pad", 0.1)
	sample_rate = ODJson.integer(d, "sampleRate", 44100)
	var fams := ODJson.dict(d, "families")
	var names: Array = fams.keys()
	names.sort()
	for n: Variant in names:
		var fd: Dictionary = fams[n]
		var fam := Family.new()
		fam.name = StringName(str(n))
		fam.pitched = ODJson.boolean(fd, "pitched")
		fam.loop = ODJson.boolean(fd, "loop")
		fam.release = ODJson.num(fd, "release", 0.05)
		for sd: Variant in ODJson.array(fd, "samples"):
			if not (sd is Dictionary):
				continue
			var s := Sample.new()
			s.file = ODJson.string(sd, "file")
			s.root = ODJson.integer(sd, "root", -1)
			s.frames = ODJson.integer(sd, "frames")
			s.loop_begin = ODJson.integer(sd, "loopBegin", -1)
			s.loop_end = ODJson.integer(sd, "loopEnd", -1)
			fam.samples.append(s)
		if fam.samples.is_empty():
			errors.append("family %s has no samples" % fam.name)
			continue
		if fam.pitched:
			fam.samples.sort_custom(func(a: Sample, b: Sample) -> bool: return a.root < b.root)
			fam.lo = fam.samples[0].root
			fam.hi = fam.samples[fam.samples.size() - 1].root
		families[fam.name] = fam
	if load_streams:
		for k: StringName in families:
			for s: Sample in (families[k] as Family).samples:
				_load_stream(s)
	return errors.is_empty()


func _load_stream(s: Sample) -> void:
	var path := ROOT_DIR + s.file
	if not ResourceLoader.exists(path):
		errors.append("missing sample " + path)
		return
	var st := load(path) as AudioStreamWAV
	if st == null:
		errors.append("not a WAV stream: " + path)
		return
	if s.loop_begin >= 0 and s.loop_end > s.loop_begin:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = s.loop_begin
		st.loop_end = s.loop_end
	else:
		st.loop_mode = AudioStreamWAV.LOOP_DISABLED
	s.stream = st


func has_family(name: StringName) -> bool:
	return families.has(name)


func family(name: StringName) -> Family:
	return families.get(name)


## Nearest sample for `pitch` (MIDI; < 0 or unpitched family: round-robin variant at 1.0). A target
## more than MAX_SHIFT semitones outside a family's roots moves by octaves into range, keeping its
## pitch class, so a sample is never stretched far.
func pick(name: StringName, pitch: float) -> Pick:
	var fam: Family = families.get(name)
	if fam == null:
		return null
	var out := Pick.new()
	if not fam.pitched or pitch < 0.0:
		out.sample = fam.samples[fam._rr % fam.samples.size()]
		fam._rr += 1
		return out
	var p := pitch
	while p > fam.hi + MAX_SHIFT:
		p -= 12.0
	while p < fam.lo - MAX_SHIFT:
		p += 12.0
	var best: Sample = fam.samples[0]
	for s: Sample in fam.samples:
		if absf(p - s.root) < absf(p - best.root):
			best = s
	out.sample = best
	out.shift = p - best.root
	out.pitch_scale = pow(2.0, out.shift / 12.0)
	return out
