class_name AudioLayerNote
extends RefCounted
## One note of a cassette layer (director.ts LayerNote).

## Tape index 0..3 whose layer plays it.
var track: int = 0
## Master beat of the onset.
var beat: float = 0.0
## Master beats. Never crosses a chord change, so a held note cannot clash with the next chord.
var duration: float = 0.0
## MIDI pitch (drums: a GM-style note number, see AudioDirector.DRUM_NOTE).
var pitch: int = 60
## 1..127.
var velocity: int = 100
## Drum kind (AudioDirector.DRUM_*), &"" for pitched notes.
var drum: StringName = &""
## Pitch normalised into the layer range 0..1 (for MusicPulse.pitches).
var norm: float = 0.5
var step: int = 0


static func make(p_track: int, p_beat: float, p_duration: float, p_pitch: int, p_velocity: int, p_norm: float, p_step: int, p_drum: StringName = &"") -> AudioLayerNote:
	var n := AudioLayerNote.new()
	n.track = p_track
	n.beat = p_beat
	n.duration = p_duration
	n.pitch = p_pitch
	n.velocity = p_velocity
	n.norm = p_norm
	n.step = p_step
	n.drum = p_drum
	return n


func copy() -> AudioLayerNote:
	return AudioLayerNote.make(track, beat, duration, pitch, velocity, norm, step, drum)


## Identity used by the scheduler so a re-planned window never plays a note twice.
func key() -> String:
	return "%d|%.6f|%d|%s" % [track, beat, pitch, drum]


## Comparable summary for tests: [track, beat(6dp), pitch, velocity, duration(6dp), drum].
func strip() -> Array:
	return [track, snappedf(beat, 0.000001), pitch, velocity, snappedf(duration, 0.000001), String(drum)]
