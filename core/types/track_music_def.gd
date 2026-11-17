class_name TrackMusicDef
extends RefCounted
## One cassette's musical layer for a level (types.ts TrackMusicDef; MUSIC-02). Interpreted by audio/.

## MusicRole.*
var role: StringName = MusicRole.MELODY
## Harmonograph formula id.
var formula: String = ""
## Formula parameters (name -> number), in authored order. Empty = absent.
var params: Dictionary[String, float] = {}
## Drum genre starting point when role is drums; "" = absent.
var genre: String = ""


func copy() -> TrackMusicDef:
	var o := TrackMusicDef.new()
	o.role = role
	o.formula = formula
	o.params = params.duplicate()
	o.genre = genre
	return o


static func from_dict(d: Dictionary) -> TrackMusicDef:
	var o := TrackMusicDef.new()
	o.role = ODJson.sname(d, "role", MusicRole.MELODY)
	o.formula = ODJson.string(d, "formula")
	var p := ODJson.dict(d, "params")
	for k: Variant in p:
		if ODJson.is_number(p[k]):
			o.params[str(k)] = float(p[k])
	o.genre = ODJson.string(d, "genre")
	return o


func to_dict() -> Dictionary:
	var out := {"role": String(role), "formula": formula}
	if not params.is_empty():
		var p := {}
		for k: String in params:
			p[k] = params[k]
		out["params"] = p
	if not genre.is_empty():
		out["genre"] = genre
	return out
