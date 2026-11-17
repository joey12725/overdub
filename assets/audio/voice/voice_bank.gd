class_name VoiceBank
extends RefCounted
## Moxie's voice one-shots: the count-in words, non-verbal efforts and (when recorded) bark lines.
## Reads res://assets/audio/voice/manifest.json (written by art/voice/build_voice.py) and hands out
## streams by id. Presentation only: it uses its own RNG and never touches the simulation.
##
##   var voice := VoiceBank.new()
##   voice.load_manifest()
##   voice.begin_count(VoiceBank.STYLE_NORMAL)            # once per count-in: picks one take for all four words
##   var id := voice.count_id(5, tonic_midi)              # tonic_midi >= 0 -> the word intoned on that pitch class
##   player.stream = voice.stream(id)                     # player on the "Ui" bus
##   player.volume_db = voice.gain_db(id)
##   # start the player voice.onset_sec(id) BEFORE the beat so the vowel lands on it
##
## See docs/VOICE.md.

const MANIFEST := "res://assets/audio/voice/manifest.json"
const STYLE_NORMAL := &"normal"
const STYLE_WHISPER := &"whisper"
const STYLE_SHOUT := &"shout"
const STYLE_PITCHED := &"pitched"
const EFFORT_ATTACK_LIGHT := &"attack_light"
const EFFORT_ATTACK_HEAVY := &"attack_heavy"
const EFFORT_DODGE := &"dodge"
const EFFORT_HIT := &"hit"
const EFFORT_DEATH := &"death"
const EFFORT_LAUGH := &"laugh"
const EFFORT_HM := &"hm"
const EFFORT_SIGH := &"sigh"

var _entries: Dictionary = {}
var _count: Dictionary = {}
var _efforts: Dictionary = {}
var _barks: Dictionary = {}
var _gain: Dictionary = {}
var _streams: Dictionary = {}
var _last_effort: Dictionary = {}
var _count_style: StringName = STYLE_NORMAL
var _count_take: int = 0
var _rng := RandomNumberGenerator.new()


## False (and an empty bank: every lookup returns "" / null) if the manifest is missing or invalid.
func load_manifest(path: String = MANIFEST) -> bool:
	_entries = {}
	_count = {}
	_efforts = {}
	_barks = {}
	_gain = {}
	_streams = {}
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return false
	var d: Dictionary = parsed
	_entries = d.get("entries", {})
	_count = d.get("count", {})
	_efforts = d.get("efforts", {})
	_barks = d.get("barks", {})
	_gain = d.get("suggested_gain_db", {})
	_rng.randomize()
	return not _entries.is_empty()


func has(id: String) -> bool:
	return _entries.has(id)


## All ids of one kind ("count" | "effort"), for preloading.
func ids(kind: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in _entries:
		var e: Dictionary = _entries[id]
		if String(e.get("kind", "")) == kind:
			out.append(id)
	return out


## The stream for an id (cached), or null if the id is unknown or its file is missing.
func stream(id: String) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	var s: AudioStream = null
	if _entries.has(id):
		var e: Dictionary = _entries[id]
		var f: String = String(e.get("file", ""))
		if f != "" and ResourceLoader.exists(f):
			s = load(f) as AudioStream
	_streams[id] = s
	return s


## Seconds from the start of the file to the word's vowel onset (its perceptual beat). Start the
## player this much EARLY so the count sits on the beat. 0 for efforts and unknown ids.
func onset_sec(id: String) -> float:
	if not _entries.has(id):
		return 0.0
	var e: Dictionary = _entries[id]
	return float(e.get("onset_ms", 0.0)) / 1000.0


func duration_sec(id: String) -> float:
	if not _entries.has(id):
		return 0.0
	var e: Dictionary = _entries[id]
	return float(e.get("duration_ms", 0.0)) / 1000.0


## Every file is normalised to the same loudness; this is the suggested per-style trim in dB.
func gain_db(id: String) -> float:
	if not _entries.has(id):
		return 0.0
	var e: Dictionary = _entries[id]
	var key: String = String(e.get("style", ""))
	if String(e.get("kind", "")) == "effort":
		key = "effort"
	return float(_gain.get(key, 0.0))


## The fundamental the take was voiced at (Hz); 0 for whispers and efforts.
func f0_hz(id: String) -> float:
	if not _entries.has(id):
		return 0.0
	var e: Dictionary = _entries[id]
	var v: Variant = e.get("f0_hz", null)
	return float(v) if v != null else 0.0


## Call once at the start of a count-in: fixes the style and picks one take, so "five six seven
## eight" all come from the same performance.
func begin_count(style: StringName = STYLE_NORMAL) -> void:
	_count_style = style
	var by_n: Dictionary = _count.get(String(style), {})
	var takes: Variant = by_n.get("5", [])
	var n: int = (takes as Array).size() if takes is Array else 0
	_count_take = _rng.randi_range(0, n - 1) if n > 1 else 0


## The id for count word n (5..8). With tonic_midi >= 0 (and the style set to STYLE_NORMAL or
## STYLE_PITCHED) the intoned take on that pitch class is used; otherwise the spoken take chosen
## by begin_count(). "" if n is out of range or the bank is empty.
func count_id(n: int, tonic_midi: int = -1) -> String:
	var key := str(n)
	if tonic_midi >= 0 and (_count_style == STYLE_NORMAL or _count_style == STYLE_PITCHED):
		var by_n: Dictionary = _count.get("pitched", {})
		var by_pc: Dictionary = by_n.get(key, {})
		var id: String = String(by_pc.get(str(posmod(tonic_midi, 12)), ""))
		if id != "":
			return id
	var spoken: Dictionary = _count.get(String(_count_style), {})
	var takes: Variant = spoken.get(key, [])
	if not (takes is Array) or (takes as Array).is_empty():
		return ""
	var arr: Array = takes
	return String(arr[mini(_count_take, arr.size() - 1)])


## A random take of an effort kind (EFFORT_*), never the same one twice running. "" if none.
func effort_id(kind: StringName) -> String:
	var takes: Variant = _efforts.get(String(kind), [])
	if not (takes is Array) or (takes as Array).is_empty():
		return ""
	var arr: Array = takes
	var i := _rng.randi_range(0, arr.size() - 1)
	if arr.size() > 1 and int(_last_effort.get(kind, -1)) == i:
		i = (i + 1) % arr.size()
	_last_effort[kind] = i
	return String(arr[i])


## "bark.<group>.<index>" as listed in the manifest (index = position in story.json barks[group]).
static func bark_id(group: String, index: int) -> String:
	return "bark.%s.%02d" % [group, index]


## The recorded line for a bark, or null: no bark audio exists yet (text-only barks), and a line
## whose text changed since it was recorded is treated as unrecorded.
func bark_stream(group: String, index: int, text: String = "") -> AudioStream:
	var id := bark_id(group, index)
	if not _barks.has(id):
		return null
	var b: Dictionary = _barks[id]
	var f: Variant = b.get("file", null)
	if f == null or String(f) == "":
		return null
	if text != "" and String(b.get("text", "")) != text:
		return null
	if not ResourceLoader.exists(String(f)):
		return null
	return load(String(f)) as AudioStream
