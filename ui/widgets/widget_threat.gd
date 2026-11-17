class_name WidgetThreat
extends RefCounted
## Pure maths for the 'beatSight' overlay (WidgetThreatTicks): where each upcoming enemy attack beat
## sits on the master ruler and how imminent it is. The beats come from SessionView.threat_beats
## (ODSim.threat_beats -> Abilities.upcoming_attack_beats); nothing here forecasts anything.

## Within this many master beats an attack counts as imminent (full pulse).
const IMMINENT_BEATS: float = 1.0
## Ticks fade in over this many beats at the far end of the look-ahead window.
const FADE_IN_BEATS: float = 2.0
## Beats that land within this many px of each other on the ruler merge into one tick (with a count).
const MERGE_PX: float = 3.0


class Tick:
	extends RefCounted
	var beat: float = 0.0
	## x on the ruler, px.
	var x: float = 0.0
	## Master beats until it lands (>= 0).
	var beats_left: float = 0.0
	## 0..1: 1 at the moment it lands, 0 at IMMINENT_BEATS or more away.
	var imminence: float = 0.0
	## 0..1 opacity (fades in at the far end of the window).
	var alpha: float = 1.0
	## How many forecast beats this tick stands for.
	var count: int = 1
	## Whole beats until it lands, for a countdown label (ceil; 0 = this beat).
	var countdown: int = 0


## Ruler x for master beat `beat` on a track [track_x, track_x + track_w] spanning `horizon` beats
## (the same mapping as the HUD ruler: track_x + beat / horizon * track_w).
static func beat_x(beat: float, horizon: float, track_x: float, track_w: float) -> float:
	return track_x + (beat / maxf(1e-6, horizon)) * track_w


## Ticks for `beats` seen at master beat `now`, looking `look_ahead` beats ahead. Beats in the past or
## beyond the horizon are dropped; neighbours closer than MERGE_PX merge (the earliest beat wins).
static func ticks(beats: Array[float], now: float, horizon: float, track_x: float, track_w: float, look_ahead: float = Abilities.BEAT_SIGHT_LOOKAHEAD_BEATS) -> Array[Tick]:
	var sorted: Array[float] = beats.duplicate()
	sorted.sort()
	var out: Array[Tick] = []
	for b: float in sorted:
		if b < now - 1e-6 or b > horizon + 1e-6:
			continue
		var x := beat_x(b, horizon, track_x, track_w)
		if not out.is_empty() and absf(x - out[out.size() - 1].x) < MERGE_PX:
			out[out.size() - 1].count += 1
			continue
		var t := Tick.new()
		t.beat = b
		t.x = x
		t.beats_left = maxf(0.0, b - now)
		t.imminence = clampf(1.0 - t.beats_left / IMMINENT_BEATS, 0.0, 1.0)
		var far := look_ahead - t.beats_left
		t.alpha = clampf(far / FADE_IN_BEATS, 0.25, 1.0) if look_ahead > 0.0 else 1.0
		t.countdown = maxi(0, ceili(t.beats_left - 1e-6))
		out.append(t)
	return out


## The soonest upcoming tick, or null.
static func next_tick(list: Array[Tick]) -> Tick:
	return list[0] if not list.is_empty() else null
