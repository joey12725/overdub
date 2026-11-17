class_name MVAudioNotes
extends RefCounted
## Routes the visualisers' note queries to the audio module's own music director (AudioDirector,
## audio/audio_director.gd), so the notes drawn are exactly the notes heard and the bar compilation
## (several milliseconds per layer per bar in GDScript) is paid once, by the audio, instead of
## twice. Install with MusicVizHub.use_audio_director(audio.director()) after both modules loaded
## the level (the director is replaced on every audio load_level, so call it again then).
##
## Loosely coupled on purpose: the director is duck-typed (any object with
## bar_notes(track, variant, bar) returning notes with track/beat/duration/pitch/velocity/drum/
## norm/step) and its variant class is loaded by path, so a half-edited audio file can never stop
## musicviz from parsing. Converted bars are cached here, keyed like the director's own cache.

const VARIANT_SCRIPT := "res://audio/audio_layer_variant.gd"
const CACHE_LIMIT := 768

var director: Object = null
var _variant_script: Script = null
var _cache: Dictionary = {}


## An adapter for `p_director`, or null when it does not offer bar_notes / its variant class is
## missing (then MVMusic keeps compiling its own notes).
static func make(p_director: Object) -> MVAudioNotes:
	if p_director == null or not p_director.has_method(&"bar_notes"):
		return null
	if not ResourceLoader.exists(VARIANT_SCRIPT):
		return null
	var s := load(VARIANT_SCRIPT) as Script
	if s == null or not s.can_instantiate():
		return null
	var a := MVAudioNotes.new()
	a.director = p_director
	a._variant_script = s
	return a


## Installs the adapter as `music`'s note source. Returns false (and leaves music alone) if the
## director cannot be used.
static func install(music: MVMusic, p_director: Object) -> bool:
	var a := make(p_director)
	if a == null or music == null:
		return false
	music.note_source = a.bar_notes
	music.note_source_owner = a
	return true


## MVMusic.note_source signature: the notes of layer `track` in master bar `bar` under `v`.
func bar_notes(track: int, v: MVVariant, bar: int) -> Array[MVNote]:
	var out: Array[MVNote] = []
	if bar < 0 or not is_instance_valid(director):
		return out
	var key := "%d|%s|%d" % [track, v.key(), bar]
	if _cache.has(key):
		return _cache[key]
	var av: Object = _variant_script.new()
	av.set(&"speed", v.speed)
	av.set(&"dead", v.dead)
	av.set(&"transport", v.transport)
	av.set(&"drift", v.drift)
	var src: Array = director.call(&"bar_notes", track, av, bar)
	for e: Object in src:
		var n := MVNote.new()
		n.track = e.get(&"track")
		n.beat = e.get(&"beat")
		n.duration = e.get(&"duration")
		n.pitch = e.get(&"pitch")
		n.velocity = e.get(&"velocity")
		n.drum = e.get(&"drum")
		n.norm = e.get(&"norm")
		n.step = e.get(&"step")
		out.append(n)
	if _cache.size() > CACHE_LIMIT:
		_cache.clear()
	_cache[key] = out
	return out
