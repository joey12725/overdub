class_name AudioSfx
extends RefCounted
## Gameplay sounds as music (prototype src/audio/sfx.ts; MUSIC-05..07). Pure planning: which cue
## each SimEvent becomes, its pitches from the chord in force, when it sounds, and how repeats are
## merged. Turning cues into sample voices lives in AudioCues.
##
## Latency policy (MUSIC-07). Events are never moved in the simulation; only their audible accent
## is placed, and only LATE: to the next line of the sixteenth grid, never more than one sixteenth
## after the event. The grid is the master sixteenth subdivided by the same power of two the world
## is slowed by, so while recording at tape speed s (world rate 1/s) the grid is one sixteenth of
## the base tempo as the player hears it, and it always nests inside the master sixteenth grid.
## Impacts additionally get an immediate soft transient so feedback is never mushy.

# Cue kinds (sfx.ts SfxKind).
const STEP: StringName = &"step"
const SWING_LIGHT: StringName = &"swingLight"
const SWING_HEAVY: StringName = &"swingHeavy"
const HIT: StringName = &"hit"
const KILL: StringName = &"kill"
const BREAK: StringName = &"break"
const CLANG: StringName = &"clang"
const DODGE: StringName = &"dodge"
const FIRE: StringName = &"fire"
const PROJECTILE_HIT: StringName = &"projectileHit"
const INTERACT: StringName = &"interact"
const INTERACT_FAIL: StringName = &"interactFail"
const DOOR: StringName = &"door"
const PLATE: StringName = &"plate"
const LASER: StringName = &"laser"
const CORE: StringName = &"core"
const SELF_DEATH: StringName = &"selfDeath"
const DESYNC: StringName = &"desync"
const RESYNC: StringName = &"resync"
const TAPE_WRAP: StringName = &"tapeWrap"
const TAPE_TURN: StringName = &"tapeTurn"
const TAPE_END: StringName = &"tapeEnd"
const ENEMY_TELEGRAPH: StringName = &"enemyTelegraph"
const ENEMY_ATTACK: StringName = &"enemyAttack"
const ENEMY_SHOT: StringName = &"enemyShot"
const ENEMY_STAGGER: StringName = &"enemyStagger"
const BOSS_PHASE: StringName = &"bossPhase"
const BOSS_RECALL: StringName = &"bossRecall"
const OBJECTIVE: StringName = &"objective"
## Immediate soft attack played ahead of a quantised impact.
const TRANSIENT: StringName = &"transient"
# Trap cue kinds (SimEventType.TRAP, detail "<kind>:<what>"; docs/TRAPS.md "Events for audio and fx").
## Telegraph: a tick one beat before a beat-timed activation and a tock half a beat before it.
const TRAP_WARN: StringName = &"trapWarn"
const SPIKES_UP: StringName = &"spikesUp"
const SPIKES_DOWN: StringName = &"spikesDown"
const CRUSHER_SLAM: StringName = &"crusherSlam"
const CRUSHER_RETRACT: StringName = &"crusherRetract"
const CRUSHER_HOLD: StringName = &"crusherHold"
const CRUSHER_OPEN: StringName = &"crusherOpen"
const CONVEYOR: StringName = &"conveyor"
const FLAME_ON: StringName = &"flameOn"
const FLAME_OFF: StringName = &"flameOff"
const DART_FIRE: StringName = &"dartFire"
const DART_TOGGLE: StringName = &"dartToggle"
const BUMPER: StringName = &"bumper"
const SENSOR: StringName = &"sensor"
const RELAY_ARMED: StringName = &"relayArmed"
const RELAY: StringName = &"relay"
const MAGNET: StringName = &"magnet"

## Recipe table: SimEvent type -> [cue kind, min interval (s), impact, priority]. The pitches, gain
## and merge key of each live in _pitches / _gain / _key. "whiff" is deliberately silent: the swing
## already made its whoosh, and a second "miss" sound would be noise rather than information.
const RECIPES: Dictionary = {
	&"step": [&"step", 0.07, false, 0],
	&"swing": [&"swingLight", 0.05, false, 3],
	&"hit": [&"hit", 0.04, true, 6],
	&"kill": [&"kill", 0.06, true, 8],
	&"break": [&"break", 0.08, true, 8],
	&"clang": [&"clang", 0.06, true, 4],
	&"dodge": [&"dodge", 0.06, false, 2],
	&"fire": [&"fire", 0.05, false, 4],
	&"projectileHit": [&"projectileHit", 0.04, true, 5],
	&"interact": [&"interact", 0.05, false, 6],
	&"interactFail": [&"interactFail", 0.1, false, 1],
	&"door": [&"door", 0.1, false, 5],
	&"plate": [&"plate", 0.08, false, 4],
	&"laser": [&"laser", 0.08, false, 3],
	&"core": [&"core", 0.1, true, 8],
	&"selfDeath": [&"selfDeath", 0.1, true, 9],
	&"desync": [&"desync", 0.1, false, 7],
	&"resync": [&"resync", 0.1, false, 7],
	&"tapeWrap": [&"tapeWrap", 0.1, false, 2],
	&"tapeTurn": [&"tapeTurn", 0.1, false, 2],
	&"tapeEnd": [&"tapeEnd", 0.1, false, 3],
	&"enemyTelegraph": [&"enemyTelegraph", 0.06, false, 5],
	&"enemyAttack": [&"enemyAttack", 0.06, true, 5],
	&"enemyShot": [&"enemyShot", 0.05, false, 4],
	&"enemyStagger": [&"enemyStagger", 0.06, false, 3],
	&"bossPhase": [&"bossPhase", 0.3, true, 9],
	&"bossRecall": [&"bossRecall", 0.2, false, 7],
	&"objective": [&"objective", 0.3, false, 10],
}

## Trap events by detail -> [cue kind, min interval (s), impact, priority]. Every detail the trap
## system emits (core/traps/traps.gd) is audible.
const TRAP_RECIPES: Dictionary = {
	"spikes:warn": [&"trapWarn", 0.1, false, 6],
	"crusher:warn": [&"trapWarn", 0.1, false, 6],
	"flame:warn": [&"trapWarn", 0.1, false, 6],
	"spikes:up": [&"spikesUp", 0.05, true, 6],
	"spikes:down": [&"spikesDown", 0.05, false, 2],
	"crusher:slam": [&"crusherSlam", 0.05, true, 8],
	"crusher:retract": [&"crusherRetract", 0.1, false, 2],
	"crusher:hold": [&"crusherHold", 0.1, false, 1],
	"crusher:open": [&"crusherOpen", 0.1, false, 1],
	"conveyor:on": [&"conveyor", 0.1, false, 3],
	"conveyor:off": [&"conveyor", 0.1, false, 3],
	"conveyor:reverse": [&"conveyor", 0.1, false, 3],
	"conveyor:forward": [&"conveyor", 0.1, false, 3],
	"flame:on": [&"flameOn", 0.08, false, 5],
	"flame:off": [&"flameOff", 0.08, false, 2],
	"dart:fire": [&"dartFire", 0.04, false, 4],
	"dart:on": [&"dartToggle", 0.1, false, 1],
	"dart:off": [&"dartToggle", 0.1, false, 1],
	"bumper:fire": [&"bumper", 0.05, true, 5],
	"sensor:on": [&"sensor", 0.08, false, 4],
	"sensor:off": [&"sensor", 0.08, false, 2],
	"relay:armed": [&"relayArmed", 0.1, false, 3],
	"relay:on": [&"relay", 0.1, false, 2],
	"relay:off": [&"relay", 0.1, false, 2],
	"magnet:on": [&"magnet", 0.1, false, 2],
	"magnet:off": [&"magnet", 0.1, false, 2],
}

## Trap pitch policy, in the composer's tone format (AudioScore): chord tones under the chord at the
## accent, so machines play along with the music. A piece's own class of the same name wins.
const TRAP_TONES: Dictionary = {
	"trapWarn": {"tones": [{"from": "chord", "index": 0, "octave": 5}, {"from": "chord", "index": 2, "octave": 5}]},
	"spikesUp": {"tones": [{"from": "chord", "index": 2, "octave": 4}]},
	"spikesDown": {"tones": [{"from": "chord", "index": 0, "octave": 4}]},
	"crusherSlam": {"tones": [{"from": "chord", "index": 0, "octave": 2}, {"from": "chord", "index": 0, "octave": 3}]},
	"crusherRetract": {"tones": [{"from": "chord", "index": 2, "octave": 3}]},
	"crusherHold": {"tones": [{"from": "chord", "index": 0, "octave": 3}]},
	"crusherOpen": {"tones": [{"from": "chord", "index": 0, "octave": 3}]},
	"conveyor": {"tones": [{"from": "chord", "index": 0, "octave": 3}], "off": [{"from": "chord", "index": 0, "octave": 2}]},
	"flameOn": {"tones": [{"from": "chord", "index": 0, "octave": 3}]},
	"flameOff": {"tones": [{"from": "chord", "index": 0, "octave": 3}]},
	"dartFire": {"tones": [{"from": "chord", "index": 1, "octave": 5}]},
	"dartToggle": {"tones": [{"from": "chord", "index": 0, "octave": 5}]},
	"bumper": {"tones": [{"from": "chord", "index": 0, "octave": 4}, {"from": "chord", "index": 2, "octave": 4}]},
	"sensor": {"tones": [{"from": "chord", "index": 1, "octave": 5}], "off": [{"from": "chord", "index": 0, "octave": 5}]},
	"relayArmed": {"tones": [{"from": "chord", "index": 2, "octave": 5}]},
	"relay": {"tones": [{"from": "chord", "index": 0, "octave": 5}], "off": [{"from": "chord", "index": 2, "octave": 4}]},
	"magnet": {"tones": [{"from": "chord", "index": 0, "octave": 3}], "off": [{"from": "chord", "index": 0, "octave": 2}]},
}

const TAPE_PAN: Array[float] = [-0.28, -0.09, 0.09, 0.28]
## Most cues one sixteenth slot may hold; lower-priority cues beyond it are dropped.
const MAX_CUES_PER_SLOT := 8
## Below this delay the accent is effectively immediate, so no separate transient is needed.
const TRANSIENT_MIN_DELAY := 0.012


## The transport as the SFX planner sees it (sfx.ts SfxClock).
class Clock:
	extends RefCounted
	## Listening-clock time now.
	var now: float = 0.0
	## Master beat of the transport now.
	var beat: float = 0.0
	## Master seconds per wall second (0 when paused).
	var rate: float = 0.0
	var playing: bool = false
	var bpm: float = 120.0

	static func make(p_now: float, p_beat: float, p_rate: float, p_playing: bool, p_bpm: float) -> Clock:
		var c := Clock.new()
		c.now = p_now
		c.beat = p_beat
		c.rate = p_rate
		c.playing = p_playing
		c.bpm = p_bpm
		return c


## Where an event's accent lands (sfx.ts Quantised).
class Quantised:
	extends RefCounted
	## Master beat the accent lands on.
	var beat: float = 0.0
	## Seconds from now until it sounds (>= 0).
	var delay: float = 0.0
	## Seconds the accent lands after the event itself (>= 0, <= one sixteenth).
	var lateness: float = 0.0


## One planned gameplay sound (sfx.ts SfxCue).
class Cue:
	extends RefCounted
	var kind: StringName = &""
	## Start time on the listening clock (seconds).
	var time: float = 0.0
	## MIDI pitches, in the order the recipe plays them.
	var pitches: Array[int] = []
	## 0..1.
	var gain: float = 0.0
	## -1..1.
	var pan: float = 0.0
	## "on" | "off" | archetype | "light" | "heavy" ... passed through from the event.
	var detail: String = ""
	## Self involved, -1 = none.
	var tape: int = -1
	## Seconds per master sixteenth at the current transport, for recipes with internal rhythm.
	var sixteenth: float = 0.125
	## How many events were merged into this cue.
	var count: int = 1
	## Event momentum (SimEvent.power; 0 when absent): picks the impact weight.
	var power: float = 0.0


# ───────────────────────────── quantisation ─────────────────────────────

## Sixteenth-grid spacing in master beats at a world rate (see the latency policy above).
static func sfx_grid(rate: float) -> float:
	var sixteenth := OD.BEATS_PER_BAR / 16.0
	if not (rate > 0.0) or rate >= 1.0:
		return sixteenth
	var k := int(ceilf(log(1.0 / rate) / log(2.0) - 1e-9))
	return sixteenth / pow(2.0, maxi(0, k))


## Places an event's accent on the next sixteenth line at or after the event. The event happened at
## master `event_beat`; the transport is at `clock.beat` now. Never early, never more than one grid
## step (<= one sixteenth of the heard tempo) after the event.
static func quantize_late(event_beat: float, clock: Clock, grid: float = 0.0) -> Quantised:
	var q := Quantised.new()
	var bps := clock.rate * (clock.bpm / 60.0)
	if not clock.playing or not (bps > 0.0) or is_nan(event_beat) or is_inf(event_beat):
		q.beat = clock.beat
		return q
	var g := grid if grid > 0.0 else sfx_grid(clock.rate)
	var target := ceilf(event_beat / g - 1e-9) * g
	# How long ago (>= 0) the event happened, as far as the transport is concerned.
	var since := maxf(0.0, (clock.beat - event_beat) / bps)
	var lateness_wanted := (target - event_beat) / bps
	q.delay = maxf(0.0, lateness_wanted - since)
	q.beat = maxf(target, clock.beat)
	q.lateness = since + q.delay
	return q


static func sub_to_master_beat(sub: int, bpm: float) -> float:
	return (float(sub) / OD.SUB_HZ) * (bpm / 60.0)


# ───────────────────────────── pitch ─────────────────────────────

## Chord tone `i` (0 = root, 1 = third, ... wrapping up octaves) at or above the chord root in
## MIDI octave `octave`.
static func chord_tone(chord: AudioChordInfo, i: int, octave: int) -> int:
	var pcs: Array[int] = chord.pcs
	if pcs.is_empty():
		pcs = [chord.root]
	var base := 12 * (octave + 1) + chord.root
	var stack: Array[int] = []
	for pc: int in pcs:
		stack.append(base + posmod(pc - chord.root, 12))
	stack.sort()
	var idx := posmod(i, stack.size())
	return stack[idx] + 12 * floori(float(i) / float(stack.size()))


## SimEvent types that produce sound (every type except "whiff"; "trap" by its detail).
static func audible_events() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in RECIPES:
		out.append(k)
	out.append(SimEventType.TRAP)
	return out


## The recipe for an event: RECIPES by type, TRAP_RECIPES by detail for trap events; [] if silent.
static func recipe_of(e: SimEvent) -> Array:
	if e.type == SimEventType.TRAP:
		return TRAP_RECIPES.get(e.detail, [])
	return RECIPES.get(e.type, [])


## The composer's class name for an event (docs/MUSIC.md SFX pitch policy).
static func class_of(e: SimEvent, kind: StringName) -> String:
	if e.type == SimEventType.SWING:
		return "swingHeavy" if e.detail == "heavy" else "swingLight"
	return String(kind)


static func _trap_off(e: SimEvent) -> bool:
	return e.detail.ends_with(":off") or e.detail.ends_with(":down")


static func _trap_pitches(kind: StringName, c: AudioChordInfo, e: SimEvent, d: AudioDirector) -> Array[int]:
	var spec: Dictionary = TRAP_TONES.get(String(kind), {})
	var list: Variant = spec.get("off") if _trap_off(e) and spec.has("off") else spec.get("tones", [])
	var out: Array[int] = []
	for t: Variant in list:
		out.append(AudioScore.tone_pitch(t, c, d, -1))
	if out.is_empty():
		out.append(chord_tone(c, 0, 4))
	return out


static func _trap_gain(kind: StringName, e: SimEvent) -> float:
	match kind:
		TRAP_WARN:
			return 0.34
		SPIKES_UP:
			return 0.42
		SPIKES_DOWN:
			return 0.16
		CRUSHER_SLAM:
			# power = bodies struck: an empty stroke is still a big machine.
			return minf(0.9, 0.62 + 0.08 * maxf(0.0, e.power if e.has_power else 0.0))
		CRUSHER_RETRACT:
			return 0.2
		CRUSHER_HOLD, DART_TOGGLE:
			return 0.12
		CRUSHER_OPEN:
			return 0.16
		CONVEYOR:
			return 0.22
		FLAME_ON:
			return 0.4
		FLAME_OFF:
			return 0.2
		DART_FIRE:
			return 0.3
		BUMPER:
			return 0.36 if e.has_power and e.power <= 0.0 else 0.44
		SENSOR:
			return 0.26 if e.detail.ends_with(":on") else 0.16
		RELAY_ARMED:
			return 0.2
		RELAY:
			return 0.16
		MAGNET:
			return 0.2
	return 0.2


static func _tape_of(e: SimEvent) -> int:
	return e.tape if e.tape >= 0 else 0


## Momentum -> 0..1 loudness; logarithmic so a 4x heavy is louder than a 0.5x light without clipping.
static func _power_gain(e: SimEvent, lo: float, hi: float) -> float:
	var p := maxf(0.0, e.power if e.has_power else 1.0)
	return minf(hi, lo + (hi - lo) * minf(1.0, (log(1.0 + p) / log(2.0)) / 4.0))


static func _is_off(e: SimEvent) -> bool:
	return e.detail == "off" or e.detail == "close" or e.detail == "closed"


## Selves sound on different chord tones (A root, B third, C fifth, D seventh/octave), so four
## selves acting together spell the chord instead of piling onto one pitch.
static func _pitches(type: StringName, c: AudioChordInfo, e: SimEvent) -> Array[int]:
	var t := _tape_of(e)
	match type:
		&"step":
			return [chord_tone(c, t, 3)]
		&"swing":
			var heavy := e.detail == "heavy"
			return [chord_tone(c, t + (0 if heavy else 2), 3 if heavy else 4)]
		&"hit":
			var lift := 2 if (e.power if e.has_power else 0.0) >= 6.0 else 0
			return [chord_tone(c, t + lift, 4), chord_tone(c, t + lift + 2, 5)]
		&"kill":
			return [chord_tone(c, 0, 5), chord_tone(c, 1, 5), chord_tone(c, 2, 5)]
		&"break":
			return [chord_tone(c, 0, 2), chord_tone(c, 0, 3)]
		&"clang", &"dodge", &"projectileHit":
			return [chord_tone(c, t + 1, 5)]
		&"fire":
			return [chord_tone(c, t, 4), chord_tone(c, t + 2, 5)]
		&"interact":
			if _is_off(e):
				return [chord_tone(c, 2, 5), chord_tone(c, 1, 5)]
			return [chord_tone(c, 1, 5), chord_tone(c, 2, 5)]
		&"interactFail":
			return [chord_tone(c, 0, 3)]
		&"door":
			if _is_off(e):
				return [chord_tone(c, 2, 2), chord_tone(c, 0, 2)]
			return [chord_tone(c, 0, 2), chord_tone(c, 2, 2)]
		&"plate":
			return [chord_tone(c, 0 if _is_off(e) else 2, 4)]
		&"laser":
			return [chord_tone(c, 0, 3)]
		&"core":
			return [chord_tone(c, 0, 5), chord_tone(c, 1, 5), chord_tone(c, 2, 5), chord_tone(c, 3, 5)]
		&"selfDeath":
			return [chord_tone(c, 2, 4), chord_tone(c, 1, 4), chord_tone(c, 0, 4)]
		&"desync":
			return [chord_tone(c, t, 4)]
		&"resync":
			return [chord_tone(c, t, 4), chord_tone(c, t + 3, 4)]
		&"tapeWrap":
			return [chord_tone(c, 0, 5)]
		&"tapeTurn":
			return [chord_tone(c, 2, 4)]
		&"tapeEnd":
			return [chord_tone(c, 0, 3)]
		&"enemyTelegraph":
			return [chord_tone(c, 0, 3), chord_tone(c, 1, 3)]
		&"enemyAttack":
			return [chord_tone(c, 0, 2)]
		&"enemyShot":
			return [chord_tone(c, 2, 4)]
		&"enemyStagger":
			return [chord_tone(c, 1, 3)]
		&"bossPhase":
			return [chord_tone(c, 0, 1), chord_tone(c, 0, 2), chord_tone(c, 2, 2)]
		&"bossRecall":
			return [chord_tone(c, 0, 4), chord_tone(c, 2, 4), chord_tone(c, 3, 4)]
		&"objective":
			return [chord_tone(c, 0, 5), chord_tone(c, 1, 5), chord_tone(c, 2, 5), chord_tone(c, 0, 6)]
	return [chord_tone(c, 0, 4)]


static func _gain(type: StringName, e: SimEvent) -> float:
	match type:
		&"step":
			return 0.1
		&"swing":
			return 0.3 if e.detail == "heavy" else 0.2
		&"hit":
			return _power_gain(e, 0.35, 0.9)
		&"kill":
			return 0.55
		&"break":
			return _power_gain(e, 0.6, 0.85)
		&"clang":
			return _power_gain(e, 0.25, 0.45)
		&"dodge":
			return 0.2
		&"fire":
			return 0.32
		&"projectileHit":
			return _power_gain(e, 0.25, 0.6)
		&"interact":
			return 0.34
		&"interactFail":
			return 0.14
		&"door":
			return 0.38
		&"plate":
			return 0.28
		&"laser":
			return 0.22
		&"core":
			return 0.5
		&"selfDeath":
			return 0.6
		&"desync", &"resync":
			return 0.34
		&"tapeWrap":
			return 0.14
		&"tapeTurn":
			return 0.18
		&"tapeEnd":
			return 0.24
		&"enemyTelegraph":
			return 0.22
		&"enemyAttack":
			return 0.36
		&"enemyShot":
			return 0.22
		&"enemyStagger":
			return 0.26
		&"bossPhase":
			return 0.75
		&"bossRecall":
			return 0.42
		&"objective":
			return 0.6
	return 0.2


## Merge key: events with the same key on the same grid line become one cue.
static func _key(type: StringName, e: SimEvent) -> String:
	match type:
		&"swing", &"hit", &"dodge", &"fire", &"interact", &"selfDeath", &"desync", &"resync", &"tapeWrap", &"tapeTurn", &"tapeEnd":
			return "%s:%d" % [type, _tape_of(e)]
		&"door", &"plate", &"laser":
			return "%s:%s" % [type, e.id]
		&"trap":
			return "trap:%s:%s" % [e.detail, e.id]
	return String(type)


## Plans one frame's events into cues; holds the cross-frame rate limiter (sfx.ts SfxPlanner).
class Planner:
	extends RefCounted
	var _last_by_key: Dictionary = {}
	## The level's composed SFX policy (data/music); null = the built-in warm table.
	var policy: AudioScore = null

	func reset() -> void:
		_last_by_key.clear()

	## Pitches of one cue: the piece's class when it has one, else the built-in table.
	func pitches_for(e: SimEvent, kind: StringName, chord: AudioChordInfo, harmony: AudioDirector) -> Array[int]:
		var power := e.power if e.has_power else 0.0
		if e.type == SimEventType.TRAP:
			if policy != null and policy.has_class(String(kind)):
				var tp := policy.pitches(String(kind), AudioSfx._trap_off(e), power, chord, harmony, -1)
				if not tp.is_empty():
					return tp
			return AudioSfx._trap_pitches(kind, chord, e, harmony)
		var cls := AudioSfx.class_of(e, kind)
		if policy != null and policy.has_class(cls):
			var p := policy.pitches(cls, AudioSfx._is_off(e), power, chord, harmony, AudioSfx._tape_of(e))
			if not p.is_empty():
				return p
		return AudioSfx._pitches(e.type, chord, e)

	## The grid an event's accent lands on: the sixteenth, or the 32nd for impacts when the piece asks
	## for it and the heard sixteenth is long (OPEN-23).
	func grid_for(impact: bool, clock: Clock) -> float:
		var g := AudioSfx.sfx_grid(clock.rate)
		if policy == null or not policy.impact_grid or not impact:
			return g
		var bps := clock.rate * (clock.bpm / 60.0)
		if not (bps > 0.0):
			return g
		return g * 0.5 if g / bps > AudioScore.IMPACT_GRID_THRESHOLD else g

	## Deterministic given the same events and clock. `harmony` gives the chord at a master beat.
	func plan(events: Array[SimEvent], clock: Clock, harmony: AudioDirector) -> Array[Cue]:
		var bps := clock.rate * (clock.bpm / 60.0)
		var sixteenth := (OD.BEATS_PER_BAR / 16.0) / bps if bps > 0.0 else 60.0 / clock.bpm / 4.0
		var merged: Dictionary = {}
		var transients: Dictionary = {}
		for e: SimEvent in events:
			if e == null:
				continue
			var r: Array = AudioSfx.recipe_of(e)
			if r.is_empty():
				continue
			var ev_beat := AudioSfx.sub_to_master_beat(e.sub, clock.bpm)
			var grid := grid_for(bool(r[2]), clock)
			var q := AudioSfx.quantize_late(ev_beat, clock, grid)
			if r[0] == AudioSfx.TRAP_WARN and e.has_power and bps > 0.0 and clock.playing:
				# The telegraph lands on the activation's own rhythm: one beat before it, on the grid.
				var target := ceilf((ev_beat + e.power - 1.0) / grid - 1e-9) * grid
				if target > clock.beat:
					q.beat = target
					q.delay = (target - clock.beat) / bps
			var time := clock.now + q.delay
			var key := AudioSfx._key(e.type, e)
			var slot := int(roundf(q.beat / grid))
			var merge_key := "%s@%d" % [key, slot]
			if merged.has(merge_key):
				var existing: Cue = merged[merge_key][0]
				existing.count += 1
				# Merged repeats get a touch louder, never louder than one strong hit.
				existing.gain = minf(1.0, maxf(existing.gain, AudioSfx._gain(e.type, e)) * 1.08)
				if e.has_power:
					existing.power = maxf(existing.power, e.power)
				continue
			if _last_by_key.has(key):
				var last: float = _last_by_key[key]
				if time - last < float(r[1]) and time >= last:
					continue
			var kind: StringName = AudioSfx.SWING_HEAVY if (e.type == SimEventType.SWING and e.detail == "heavy") else r[0]
			var chord := harmony.chord_at(q.beat)
			var cue := Cue.new()
			cue.kind = kind
			cue.time = time
			cue.pitches = pitches_for(e, kind, chord, harmony)
			cue.gain = AudioSfx._trap_gain(kind, e) if e.type == SimEventType.TRAP else AudioSfx._gain(e.type, e)
			cue.pan = AudioSfx.TAPE_PAN[e.tape] if e.tape >= 0 and e.tape < OD.TAPE_COUNT else 0.0
			cue.detail = e.detail
			cue.tape = e.tape
			cue.sixteenth = sixteenth
			cue.count = 1
			cue.power = e.power if e.has_power else 0.0
			merged[merge_key] = [cue, int(r[3]), key, slot]
			if bool(r[2]) and q.delay > AudioSfx.TRANSIENT_MIN_DELAY and not transients.has(key):
				var tr := Cue.new()
				tr.kind = AudioSfx.TRANSIENT
				tr.time = clock.now
				var first: Array[int] = [cue.pitches[0]]
				tr.pitches = first
				tr.gain = cue.gain * 0.3
				tr.pan = cue.pan
				tr.detail = String(e.type)
				tr.tape = e.tape
				tr.sixteenth = sixteenth
				transients[key] = tr

		var by_slot: Dictionary = {}
		var slot_order: Array[int] = []
		for mk: String in merged:
			var m: Array = merged[mk]
			var s: int = m[3]
			if not by_slot.has(s):
				by_slot[s] = []
				slot_order.append(s)
			by_slot[s].append(m)
		var out: Array[Cue] = []
		for s: int in slot_order:
			var list: Array = by_slot[s]
			# Stable priority sort (insertion order breaks ties, as JS Array.sort does).
			var idx: Array = range(list.size())
			idx.sort_custom(func(a: int, b: int) -> bool:
				var pa: int = list[a][1]
				var pb: int = list[b][1]
				return pa > pb or (pa == pb and a < b))
			for j: int in mini(idx.size(), AudioSfx.MAX_CUES_PER_SLOT):
				var m: Array = list[idx[j]]
				var cue: Cue = m[0]
				out.append(cue)
				_last_by_key[m[2]] = cue.time
		for k: String in transients:
			out.append(transients[k])
		# Stable time sort.
		var order: Array = range(out.size())
		order.sort_custom(func(a: int, b: int) -> bool:
			return out[a].time < out[b].time or (out[a].time == out[b].time and a < b))
		var sorted: Array[Cue] = []
		for i: int in order:
			sorted.append(out[i])
		if _last_by_key.size() > 256:
			var cutoff := clock.now - 2.0
			for k: String in _last_by_key.keys():
				if float(_last_by_key[k]) < cutoff:
					_last_by_key.erase(k)
		return sorted
