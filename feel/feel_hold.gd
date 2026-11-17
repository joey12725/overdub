class_name FeelHold
extends RefCounted
## The visual hit-hold ("hit-stop") of one actor, as a PRESENTATION LAG.
##
## The simulation is deterministic and the music is locked to it, so nothing here may pause, slow or
## otherwise touch game time. Instead, a held actor is DRAWN late: for `hold` seconds its pose and
## position stay frozen at the contact frame (the lag grows as fast as time passes), then over
## `catch_up` seconds the drawing catches back up with the simulation (a time-smear). The lag is
## always >= 0 (the presentation never runs ahead of the sim), never exceeds the hold, and is back to
## exactly 0 after hold + catch_up. Callers sample their pose / position at (now - lag).
##
## Pure: advance() takes the frame's wall dt; there is no clock in here.

var hold: float = 0.0
var catch_up: float = 0.0
var elapsed: float = 0.0
var active: bool = false


## Lag (seconds behind the sim) `t` seconds after contact. Continuous; 0 outside [0, hold + catch_up].
static func lag_at(t: float, p_hold: float, p_catch_up: float) -> float:
	if t <= 0.0 or p_hold <= 0.0:
		return 0.0
	if t <= p_hold:
		return t
	if p_catch_up <= 0.0 or t >= p_hold + p_catch_up:
		return 0.0
	var u := (t - p_hold) / p_catch_up
	if u >= 1.0:
		return 0.0
	# Catch up fast at first, then settle (ease-out cubic): the release snaps.
	var k := 1.0 - u
	return p_hold * k * k * k


## Start (or extend) a hold. A new hit during a hold never shortens what remains.
func start(p_hold: float, p_catch_up: float) -> void:
	if active and lag() > p_hold:
		return
	var carry := lag() if active else 0.0
	hold = maxf(p_hold, carry)
	catch_up = p_catch_up
	# Resume from the lag already accumulated, so a re-hit does not jump the drawing backwards.
	elapsed = carry
	active = true


func advance(dt: float) -> void:
	if not active:
		return
	elapsed += maxf(0.0, dt)
	if elapsed >= hold + catch_up:
		active = false
		elapsed = 0.0


## Seconds the drawing is behind the simulation right now.
func lag() -> float:
	return lag_at(elapsed, hold, catch_up) if active else 0.0


## True while the pose is fully frozen (the hold proper, before the catch-up).
func frozen() -> bool:
	return active and elapsed < hold


## The same lag in local tape ticks, for scrubbing a clip: `ticks_per_second` is how fast the tape's
## local tick advances in wall time right now (60 while recording; 60 x speed x world rate in review).
static func lag_ticks(lag_seconds: float, ticks_per_second: float) -> float:
	return maxf(0.0, lag_seconds) * maxf(0.0, ticks_per_second)
