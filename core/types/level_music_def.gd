class_name LevelMusicDef
extends RefCounted
## A level's music (types.ts LevelMusicDef; MUSIC-01..02).

## Root pitch class 0..11.
var root: int = 0
## Harmonograph scale name.
var scale: String = ""
## Roman-numeral style progression as scale degrees (0-based), one chord per `chord_bars` bars.
var progression: Array[int] = []
## Bars per chord; 0 = absent (audio applies its default).
var chord_bars: int = 0
## Exactly four entries: the layer owned by cassette 1..4.
var tracks: Array[TrackMusicDef] = []


func copy() -> LevelMusicDef:
	var o := LevelMusicDef.new()
	o.root = root
	o.scale = scale
	o.progression = progression.duplicate()
	o.chord_bars = chord_bars
	for t: TrackMusicDef in tracks:
		o.tracks.append(t.copy())
	return o


static func from_dict(d: Dictionary) -> LevelMusicDef:
	var o := LevelMusicDef.new()
	o.root = ODJson.integer(d, "root")
	o.scale = ODJson.string(d, "scale")
	o.progression = ODJson.ints(d.get("progression"))
	o.chord_bars = ODJson.integer(d, "chordBars")
	for t: Variant in ODJson.array(d, "tracks"):
		if t is Dictionary:
			o.tracks.append(TrackMusicDef.from_dict(t))
	return o


func to_dict() -> Dictionary:
	var tr: Array = []
	for t: TrackMusicDef in tracks:
		tr.append(t.to_dict())
	var out := {"root": root, "scale": scale, "progression": progression.duplicate()}
	if chord_bars > 0:
		out["chordBars"] = chord_bars
	out["tracks"] = tr
	return out
