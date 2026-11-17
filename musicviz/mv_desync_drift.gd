class_name MVDesyncDrift
extends RefCounted
## Desync drift memory (port of prototype/src/audio/sequencer.ts DesyncDrift; MUSIC-08/09, DESYNC):
## the drift grows while a self stays desynced and converges back after resync, quantised per bar,
## so the notes the visualisers mark are the notes the audio plays.

const DRIFT_RISE_PER_BAR := 0.25
const DRIFT_FALL_PER_BAR := 0.5

var _desynced: Array[bool] = [false, false, false, false]
var _has: Array[bool] = [false, false, false, false]
var _since_bar: Array[int] = [0, 0, 0, 0]
var _from: Array[float] = [0.0, 0.0, 0.0, 0.0]


func reset() -> void:
	_desynced = [false, false, false, false]
	_has = [false, false, false, false]
	_since_bar = [0, 0, 0, 0]
	_from = [0.0, 0.0, 0.0, 0.0]


## Records the sync state of `track` at master `beat`; true when it changed.
func update(track: int, desynced: bool, beat: float) -> bool:
	var cur := _desynced[track] if _has[track] else false
	if cur == desynced:
		return false
	var bar := maxi(0, floori(beat / OD.BEATS_PER_BAR))
	var from := at(track, bar)
	_has[track] = true
	_desynced[track] = desynced
	_since_bar[track] = bar
	_from[track] = from
	return true


## Drift level of `track` during master bar `bar`, in quarter steps 0..1.
func at(track: int, bar: int) -> float:
	if not _has[track]:
		return 0.0
	var elapsed := maxi(0, bar - _since_bar[track])
	var level: float
	if _desynced[track]:
		level = minf(1.0, _from[track] + DRIFT_RISE_PER_BAR * (elapsed + 1))
	else:
		level = maxf(0.0, _from[track] - DRIFT_FALL_PER_BAR * elapsed)
	return HGMath.js_round(level * 4.0) / 4.0
