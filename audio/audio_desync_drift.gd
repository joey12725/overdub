class_name AudioDesyncDrift
extends RefCounted
## Desync drift memory (sequencer.ts DesyncDrift; MUSIC-08, MUSIC-09, DESYNC).
##
## The drift grows while a self stays desynced and converges back after resync, so the track state
## alone is not enough. Drift is a deterministic function of the transitions seen on the master
## timeline, quantised per bar, so a bar's notes can be compiled ahead of time and recompiled
## identically.

## Drift added per bar while desynced (reaches full drift on the fourth bar).
const RISE_PER_BAR := 0.25
## Drift removed per bar after resync: the layer is exactly back on its baseline within two bars.
const FALL_PER_BAR := 0.5

# Per track: has_segment, desynced, since_bar, from (drift level in force at the transition).
var _has: Array[bool] = [false, false, false, false]
var _desynced: Array[bool] = [false, false, false, false]
var _since: Array[int] = [0, 0, 0, 0]
var _from: Array[float] = [0.0, 0.0, 0.0, 0.0]


func reset() -> void:
	_has = [false, false, false, false]
	_desynced = [false, false, false, false]
	_since = [0, 0, 0, 0]
	_from = [0.0, 0.0, 0.0, 0.0]


## Records the sync state of `track` at master `beat`. Returns true when it changed.
func update(track: int, desynced: bool, beat: float) -> bool:
	var cur := _desynced[track] if _has[track] else false
	if cur == desynced:
		return false
	var bar := maxi(0, int(floorf(beat / OD.BEATS_PER_BAR)))
	var level := at(track, bar)
	_has[track] = true
	_desynced[track] = desynced
	_since[track] = bar
	_from[track] = level
	return true


## Drift level of `track` during master bar `bar`, in quarter steps 0..1.
func at(track: int, bar: int) -> float:
	if not _has[track]:
		return 0.0
	var elapsed := maxi(0, bar - _since[track])
	var level: float
	if _desynced[track]:
		level = minf(1.0, _from[track] + RISE_PER_BAR * float(elapsed + 1))
	else:
		level = maxf(0.0, _from[track] - FALL_PER_BAR * float(elapsed))
	return HGMath.js_round(level * 4.0) / 4.0
