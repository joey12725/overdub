class_name AudioSequencer
extends RefCounted
## Which variant each cassette layer is in, bar by bar, and the merged note stream the scheduler
## pulls from (prototype src/audio/sequencer.ts). Pure; no nodes.

var director: AudioDirector
var drift := AudioDesyncDrift.new()
var _tracks: Array[TrackAudioState] = []


func _init(p_director: AudioDirector) -> void:
	director = p_director
	for i: int in OD.TAPE_COUNT:
		_tracks.append(silent_track())


## A cassette that is not present (its layer is silent).
static func silent_track() -> TrackAudioState:
	return TrackAudioState.make(false, 1.0, OD.LifeState.ALIVE, true, 1)


static func _same_composition(a: TrackAudioState, b: TrackAudioState) -> bool:
	return a.present == b.present and a.speed == b.speed and a.life == b.life and a.synced == b.synced and a.transport == b.transport


## Current per-track states (copies).
func states() -> Array[TrackAudioState]:
	var out: Array[TrackAudioState] = []
	for t: TrackAudioState in _tracks:
		out.append(t.copy())
	return out


## Applies new track states at master `beat`. Returns true when the generated notes from now on
## differ, so already-planned notes must be re-planned.
func set_tracks(tracks: Array[TrackAudioState], beat: float) -> bool:
	var changed := false
	for i: int in OD.TAPE_COUNT:
		var t: TrackAudioState = tracks[i] if i < tracks.size() and tracks[i] != null else silent_track()
		var desynced := t.present and t.life == OD.LifeState.ALIVE and not t.synced
		if drift.update(i, desynced, beat):
			changed = true
		if not _same_composition(t, _tracks[i]):
			changed = true
			_tracks[i] = t.copy()
	return changed


## Every take restarts at beat 0 with fresh selves: forget the old run's drift history.
func restart() -> void:
	drift.reset()


## The variant of `track` during master bar `bar`, or null when the cassette is not present.
func variant_at(track: int, bar: int) -> AudioLayerVariant:
	var t: TrackAudioState = _tracks[track]
	if not t.present:
		return null
	var dead := t.life != OD.LifeState.ALIVE
	# Death and desync are distinct semantics: a ghost never drifts back to life (MUSIC-08).
	var transport := clampi(t.transport, -1, 1)
	return AudioLayerVariant.make(t.speed if OD.is_speed(t.speed) else 1.0, dead, transport, 0.0 if dead else drift.at(track, bar))


## All present layers' notes with onsets in [from, to), sorted by beat, then track, then pitch.
func collect(from: float, to: float) -> Array[AudioLayerNote]:
	var out: Array[AudioLayerNote] = []
	if to <= from:
		return out
	var first_bar := maxi(0, int(floorf(from / OD.BEATS_PER_BAR)))
	for track: int in OD.TAPE_COUNT:
		var bar := first_bar
		while float(bar * OD.BEATS_PER_BAR) < to:
			var v := variant_at(track, bar)
			if v == null:
				break
			for n: AudioLayerNote in director.bar_notes(track, v, bar):
				if n.beat >= from - 1e-9 and n.beat < to - 1e-9:
					out.append(n)
			bar += 1
	out.sort_custom(_collect_less)
	return out


static func _collect_less(a: AudioLayerNote, b: AudioLayerNote) -> bool:
	if a.beat != b.beat:
		return a.beat < b.beat
	if a.track != b.track:
		return a.track < b.track
	if a.pitch != b.pitch:
		return a.pitch < b.pitch
	return String(a.drum) < String(b.drum)
