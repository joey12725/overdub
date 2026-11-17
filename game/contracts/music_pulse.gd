class_name MusicPulse
extends RefCounted
## Cheap per-frame musical state shared with visuals (contracts.ts MusicPulse). All values are safe
## defaults when audio is off. Produced by AudioBase.pulse(), read by the world, fx and HUD.

## Master beat position (float).
var beat: float = 0.0
## 0..1 saw that hits 1 on each beat and decays.
var beat_pulse: float = 0.0
## 0..1 saw that hits 1 on each bar.
var bar_pulse: float = 0.0
## Per-cassette layer level 0..1 (recent note energy), index = tape. Size OD.TAPE_COUNT.
var levels: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## Per-cassette most recent normalised pitch 0..1 (for contour drawing). Size OD.TAPE_COUNT.
var pitches: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## Current chord degree index within the level progression.
var chord: int = 0


func copy() -> MusicPulse:
	var o := MusicPulse.new()
	o.beat = beat
	o.beat_pulse = beat_pulse
	o.bar_pulse = bar_pulse
	o.levels = levels.duplicate()
	o.pitches = pitches.duplicate()
	o.chord = chord
	return o
