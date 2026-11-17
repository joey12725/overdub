class_name AudioScore
extends RefCounted
## The composer's data for one piece (data/music/<level id>.json, data/music/menu.json; docs/MUSIC.md):
## the level's `music` block, the SFX pitch policy (MUSIC-05: `sfx.classes`, already merged with the
## level's palette), UI and count-in pitches (`sfx.ui`), the latency policy (`sfx.latency`, OPEN-23)
## and, for the menu, the bed (`bed.tracks`). Pure data; no nodes.
##
## Tone rule (`sfx.pitchRule`): a tone is {from, index, octave, perTape}. from "chord": index into the
## triad of the chord in force at the cue's grid line, stacked upward from the chord root in MIDI octave
## `octave` (C4 = 60; 0 root, 1 third, 2 fifth, 3 root an octave up ...). from "scale": 0-based degree
## of the level scale in `octave`. perTape adds the acting cassette index, so four selves acting together
## spell the chord. "off" replaces "tones" for off / close events, "heavy" for power >= 6.

const DIR := "res://data/music/"
const MENU_ID := "menu"
## Momentum at which a class's "heavy" tones replace its tones.
const HEAVY_POWER := 6.0
## OPEN-23 proposal, built here: impact classes use the 32nd grid when the heard sixteenth is longer
## than this (bpm below 116 at 1x), keeping the worst-case accent delay of a hit near 100 ms.
const IMPACT_GRID_THRESHOLD := 0.130

var id: String = ""
var bpm: float = 120.0
var palette: String = ""
var music: LevelMusicDef = null
## class name -> {tones, off?, heavy?, impact}
var classes: Dictionary = {}
## UI kind -> tone list; "countIn" -> {"5": tones, ...}.
var ui: Dictionary = {}
## Menu bed: TrackAudioState per cassette (empty for a level piece).
var bed: Array[TrackAudioState] = []
## Whether the 32nd-note impact grid applies (the latency data names it).
var impact_grid: bool = false

static var _cache: Dictionary = {}


## The piece for a level id ("01-soft-open"), or null when there is none. Cached. Read through the
## content layer's loader (CampaignData.music_file, which checks the schema and caches the file).
static func for_id(level_id: String) -> AudioScore:
	if level_id.is_empty():
		return null
	if _cache.has(level_id):
		return _cache[level_id]
	var s: AudioScore = null
	if FileAccess.file_exists(DIR + level_id + ".json"):
		var f := CampaignData.music_file(level_id)
		s = from_music_file(f) if f != null else _load(DIR + level_id + ".json")
	_cache[level_id] = s
	return s


static func from_music_file(f: ContentData.MusicFile) -> AudioScore:
	var d := {"id": f.id, "bpm": f.bpm, "sfx": f.sfx, "bed": f.bed}
	var s := from_dict(d)
	s.music = f.music.copy() if f.music != null else null
	return s


static func menu() -> AudioScore:
	return for_id(MENU_ID)


static func _load(path: String) -> AudioScore:
	if not FileAccess.file_exists(path):
		return null
	var errors: Array[String] = []
	var d: Variant = ODJson.read_file(path, errors)
	if not (d is Dictionary):
		push_warning("AudioScore: cannot read %s: %s" % [path, ", ".join(errors)])
		return null
	return from_dict(d)


static func from_dict(d: Dictionary) -> AudioScore:
	var s := AudioScore.new()
	s.id = ODJson.string(d, "id")
	s.bpm = ODJson.num(d, "bpm", 120.0)
	var m: Dictionary = ODJson.dict(d, "music")
	s.music = LevelMusicDef.from_dict(m) if not m.is_empty() else null
	var sfx: Dictionary = ODJson.dict(d, "sfx")
	s.palette = ODJson.string(sfx, "palette")
	s.classes = ODJson.dict(sfx, "classes")
	s.ui = ODJson.dict(sfx, "ui")
	var lat: Dictionary = ODJson.dict(sfx, "latency")
	s.impact_grid = ODJson.string(lat, "impactGrid") == "thirtysecond"
	var bed_d: Dictionary = ODJson.dict(d, "bed")
	for t: Variant in ODJson.array(bed_d, "tracks"):
		if t is Dictionary:
			var td: Dictionary = t
			s.bed.append(TrackAudioState.make(td.get("present", false) == true, float(td.get("speed", 1.0)), OD.LifeState.ALIVE, true, 1))
	return s


## A LevelDef carrying only what the director reads (bpm + music): for the menu bed.
func level_def() -> LevelDef:
	var l := LevelDef.new()
	l.id = id
	l.bpm = bpm
	l.music = music.copy() if music != null else LevelMusicDef.new()
	return l


func has_class(name: String) -> bool:
	return classes.has(name)


func is_impact(name: String) -> bool:
	var c: Variant = classes.get(name)
	return c is Dictionary and (c as Dictionary).get("impact", false) == true


## The tone list for a class: "off" for closing events, "heavy" for power >= HEAVY_POWER, else "tones".
func class_tones(name: String, off: bool, power: float) -> Array:
	var c: Variant = classes.get(name)
	if not (c is Dictionary):
		return []
	var cd: Dictionary = c
	if off and cd.get("off") is Array:
		return cd["off"]
	if power >= HEAVY_POWER and cd.get("heavy") is Array:
		return cd["heavy"]
	var t: Variant = cd.get("tones")
	return t if t is Array else []


## MIDI pitch of one tone under `chord` (from "chord") or the director's key (from "scale").
static func tone_pitch(tone: Dictionary, chord: AudioChordInfo, d: AudioDirector, tape: int) -> int:
	var index := int(tone.get("index", 0))
	if tone.get("perTape", false) == true:
		index += maxi(0, tape)
	var octave := int(tone.get("octave", 4))
	if str(tone.get("from", "chord")) == "scale":
		return d.scale_midi(index, octave)
	return AudioSfx.chord_tone(chord, index, octave)


## Pitches of a class for one event.
func pitches(name: String, off: bool, power: float, chord: AudioChordInfo, d: AudioDirector, tape: int) -> Array[int]:
	var out: Array[int] = []
	for t: Variant in class_tones(name, off, power):
		if t is Dictionary:
			out.append(tone_pitch(t, chord, d, tape))
	return out


## UI pitches for a kind (AudioBase.UI_*), or empty when the piece does not name it.
func ui_pitches(kind: StringName, d: AudioDirector) -> Array[int]:
	var out: Array[int] = []
	var tones: Variant = ui.get(String(kind))
	if not (tones is Array):
		return out
	var chord := d.chord_at(0.0)
	for t: Variant in tones:
		if t is Dictionary:
			out.append(tone_pitch(t, chord, d, -1))
	return out


## Count-in pitch for n = 5..8, or -1 when the piece does not name it.
func count_pitch(n: int, d: AudioDirector) -> int:
	var ci: Variant = ui.get("countIn")
	if not (ci is Dictionary):
		return -1
	var tones: Variant = (ci as Dictionary).get(str(n))
	if not (tones is Array) or (tones as Array).is_empty() or not ((tones as Array)[0] is Dictionary):
		return -1
	return tone_pitch((tones as Array)[0], d.chord_at(0.0), d, -1)
