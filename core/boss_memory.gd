class_name BossMemoryLib
extends RefCounted
## Cross-recording memory of the outside-the-loop boss (BOSS-01, BOSS-02). Port of
## prototype/src/core/bossMemory.ts.
##
## Policy (the requirements leave it open; this is the resolved reading):
##   - Memory is built ONLY from committed tapes. A discarded take, a whole-attempt reset (which
##     discards the tapes) and the cinematic never feed it, so the replay of a resolved run can never
##     re-teach the boss (CINE-04).
##   - It records choreography, not outcomes: where each committed tape is at every whole master beat
##     of the horizon and every attack attempt it makes, with end behaviour (stop / repeat / reverse)
##     applied. What happened to the tape in some run (death, desync) is not memory: the boss
##     remembers what you rehearsed, which is exactly what the player can see on the cassette lane.
##   - It is read-only data. The simulation copies what it needs at the start of a run and never
##     writes to it, so the same memory always produces the same fight.
##
## `recall_candidates` is the single interpretation of that memory: the moments a remembered self
## "stood somewhere for a while" (a dwell) or "attacked". The boss (enemies/boss.gd) turns those
## candidates into telegraphed memory strikes.

## Recorded attempts the boss remembers as attacks. Dodges and interactions are not threats.
const REMEMBERED_ACTIONS: Array[StringName] = [ActionKind.LIGHT, ActionKind.HEAVY, ActionKind.RANGED]

## A remembered self "stood somewhere" while it stayed within this many tiles of where it stopped.
const BOSS_DWELL_RADIUS: float = 0.75
## ...for at least this many whole master beats (so two consecutive samples are not yet a dwell).
const BOSS_DWELL_BEATS: int = 2

## Why the boss remembers a moment (bossMemory.ts RecallReason).
const REASON_DWELL: StringName = &"dwell"
const REASON_ATTACK: StringName = &"attack"


## One remembered moment the boss may pre-empt: a place and the earliest whole beat it applies to.
class RecallCandidate:
	extends RefCounted
	## TapeIndex.
	var tape: int = 0
	## BossMemoryLib.REASON_DWELL | REASON_ATTACK.
	var reason: StringName = &"dwell"
	## First whole master beat at which the remembered self is expected at (x, y).
	var beat: int = 0
	## Last whole master beat of the moment (equal to `beat` for an attack).
	var last_beat: int = 0
	var x: float = 0.0
	var y: float = 0.0

	static func make(p_tape: int, p_reason: StringName, p_beat: int, p_last: int, p_x: float, p_y: float) -> RecallCandidate:
		var c := RecallCandidate.new()
		c.tape = p_tape
		c.reason = p_reason
		c.beat = p_beat
		c.last_beat = p_last
		c.x = p_x
		c.y = p_y
		return c


## Build the boss memory from the committed tapes. Each tape contributes its position at every whole
## master beat 0..floor(horizon / beat) and every light / heavy / ranged attempt it makes inside the
## horizon (end behaviour applied: a repeating tape attacks again every traversal, a reversing one
## on its backward passes too). Tapes are listed in cassette order.
static func build_boss_memory(level: LevelDef, committed: Array[ODTape]) -> BossMemory:
	var spb: float = ODTime.subs_per_beat(level)
	var h: float = ODTime.horizon_subs(level)
	# float division then floor, as the prototype's Math.floor(H / spb).
	var beats: int = floori(h / spb)
	var mem := BossMemory.new()
	var pose := TapeLib.PoseSample.new()
	# [...committed].sort((a, b) => a.index - b.index) is a stable sort; Godot's sort_custom is not,
	# so a stable insertion sort keeps equal indices in the given order.
	var sorted: Array[ODTape] = committed.duplicate()
	for i: int in range(1, sorted.size()):
		var t: ODTape = sorted[i]
		var j: int = i - 1
		while j >= 0 and sorted[j].index > t.index:
			sorted[j + 1] = sorted[j]
			j -= 1
		sorted[j + 1] = t
	var crossings: Array[ODTime.EventCrossing] = []
	for t: ODTape in sorted:
		var o := BossObservation.new()
		o.tape = t.index
		o.speed = t.speed
		for b: int in range(beats + 1):
			TapeLib.sample_pose_at_sub(t, b * spb, pose)
			o.samples.append(BossSample.make(b, pose.x, pose.y))
		crossings.clear()
		ODTime.collect_event_crossings(t, 0, h, crossings)
		for c: ODTime.EventCrossing in crossings:
			if not REMEMBERED_ACTIONS.has(c.event.kind):
				continue
			TapeLib.sample_pose_at_sub(t, c.sub, pose)
			# float division (c.sub may be an integer substep).
			o.actions.append(BossMemoryAction.make(float(c.sub) / spb, pose.x, pose.y, c.event.kind))
		o.has_actions = true
		mem.observed.append(o)
	return mem


## Every moment the memory describes, ordered by beat, then cassette, then reason (attack first).
##
##   dwell  - a run of whole-beat samples that all stay within BOSS_DWELL_RADIUS of the run's first
##            sample for at least BOSS_DWELL_BEATS beats. The place is the run's first sample.
##            Scanning restarts after the run, so a long wait is one dwell, not many.
##   attack - each remembered attempt, at the whole beat nearest to it (enemy attacks keep to the
##            beat grid; AI-07) and the position the self had when it fired.
##
## Pure: reads the memory, never writes it. `memory` may be null (no memory: no moments).
static func recall_candidates(memory: BossMemory) -> Array[RecallCandidate]:
	var out: Array[RecallCandidate] = []
	if memory == null:
		return out
	for o: BossObservation in memory.observed:
		var s: Array[BossSample] = o.samples
		var i: int = 0
		while i < s.size():
			var j: int = i
			while j + 1 < s.size():
				var dx: float = s[j + 1].x - s[i].x
				var dy: float = s[j + 1].y - s[i].y
				if ODGrid.hypot(dx, dy) > BOSS_DWELL_RADIUS:
					break
				j += 1
			if s[j].beat - s[i].beat >= BOSS_DWELL_BEATS:
				out.append(RecallCandidate.make(o.tape, REASON_DWELL, int(s[i].beat), int(s[j].beat), s[i].x, s[i].y))
			i = j + 1
		for a: BossMemoryAction in o.actions:
			# Math.round rounds halves toward +Infinity; GDScript round() rounds them away from zero.
			var b: int = floori(a.beat + 0.5)
			out.append(RecallCandidate.make(o.tape, REASON_ATTACK, b, b, a.x, a.y))
	# Array.prototype.sort is stable; Godot's sort_custom is not, so equal moments keep their
	# insertion order through a stable insertion sort.
	for k: int in range(1, out.size()):
		var c: RecallCandidate = out[k]
		var m: int = k - 1
		while m >= 0 and _candidate_after(out[m], c):
			out[m + 1] = out[m]
			m -= 1
		out[m + 1] = c
	return out


## Strictly after in (beat, cassette, attack-before-dwell) order.
static func _candidate_after(a: RecallCandidate, b: RecallCandidate) -> bool:
	if a.beat != b.beat:
		return a.beat > b.beat
	if a.tape != b.tape:
		return a.tape > b.tape
	if a.reason == b.reason:
		return false
	return a.reason != REASON_ATTACK
