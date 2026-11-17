class_name WidgetBossModel
extends RefCounted
## State behind the boss bar (HEALTH-03, BOSS-01..03, chapter 10 "Fairness"). Pure: fed snapshots,
## events and elapsed wall time; read by WidgetBossBar for drawing and by tests directly.
##
##   health      hp / max_hp from the EnemySnap, plus a damage-lag "ghost" fraction that holds for
##               GHOST_HOLD seconds after a hit and then drains at GHOST_DRAIN per second, so every
##               chunk of damage stays visible long enough to be read.
##   phases      pips at the hp fractions where BossBehaviour.boss_phase_for changes phase (computed
##               by calling it, not re-derived), and the current phase from EnemySnap.boss_phase.
##   armour      plates left (3, one hidden per phase as the model's Armor_1..3 are), whether it is
##               staggered (the one moment its guard is down), and whose eye it holds: EnemySnap.target
##               is its attention, the self that can never hurt it (BOSS-03).
##   memory      lit while EnemySnap.boss_recall: WHICH committed cassette it is punishing
##               (boss_recall_tape -> colour and letter), the remembered place and, from the
##               'bossRecall' event, the master beat the memory strike lands on. That is the tell the
##               player exploits: while it punishes tape A's old position, every other tape is free
##               to hit its back. With set_memory() it also lists which tapes it remembers at all.

const GHOST_HOLD: float = 0.55
const GHOST_DRAIN: float = 0.6
const FLASH_TIME: float = 0.35
## Armour plates on the boss model (Armor_1..3).
const PLATES: int = 3

const ARMOUR_GUARDED: StringName = &"guarded"
const ARMOUR_OPEN: StringName = &"open"
const ARMOUR_BROKEN: StringName = &"broken"

var present: bool = false
var id: String = ""
var hp: int = 0
var max_hp: int = 0
var alive: bool = true
## Current fill, 0..1.
var frac: float = 1.0
## Damage-lag fill, >= frac.
var ghost: float = 1.0
var _ghost_hold: float = 0.0
## Phase 1..3 and the fractions (descending) where the next phases begin.
var phase: int = 1
var phase_marks: Array[float] = []
## ARMOUR_*.
var armour: StringName = ARMOUR_GUARDED
var plates: int = PLATES
## Tape it is watching (its front faces it); -1 = none.
var attention: int = -1
var staggered: bool = false
## Memory.
var recalling: bool = false
var recall_tape: int = -1
var recall_at: Vector2 = Vector2.ZERO
var has_recall_at: bool = false
## Master beat the current memory strike lands on; -1 = unknown.
var recall_land_beat: float = -1.0
## BossMemoryLib.REASON_DWELL / REASON_ATTACK from the 'bossRecall' event; "" = unknown.
var recall_reason: StringName = &""
## Beats until it lands (from the last update's beat); -1 = unknown.
var recall_beats_left: float = -1.0
## Tapes the boss remembers (from set_memory) and how many remembered moments each has.
var remembered: Array[int] = []
var remembered_moments: Dictionary[int, int] = {}
## Hit / clang flashes, seconds left.
var hit_flash: float = 0.0
var clang_flash: float = 0.0
var clang_tape: int = -1
var phase_flash: float = 0.0
var _last_hp: int = -1


## Remembered tapes from the boss's memory (null = none). Uses BossMemoryLib.recall_candidates so the
## moment count matches what the boss can act on.
func set_memory(memory: BossMemory) -> void:
	remembered.clear()
	remembered_moments.clear()
	if memory == null:
		return
	for ob: BossObservation in memory.observed:
		if not remembered.has(ob.tape):
			remembered.append(ob.tape)
			remembered_moments[ob.tape] = 0
	for c: BossMemoryLib.RecallCandidate in BossMemoryLib.recall_candidates(memory):
		remembered_moments[c.tape] = int(remembered_moments.get(c.tape, 0)) + 1
	remembered.sort()


## The first boss in a snapshot, or null.
static func find_boss(snap: FrameSnapshot) -> EnemySnap:
	if snap == null:
		return null
	for e: EnemySnap in snap.enemies:
		if e.type == EnemyType.BOSS:
			return e
	return null


## Phase-change fractions for a boss with `max_hp`, found by asking BossBehaviour.boss_phase_for
## at every hit-point value (descending).
static func phase_marks_for(p_max_hp: int) -> Array[float]:
	var out: Array[float] = []
	if p_max_hp <= 0:
		return out
	var prev := BossBehaviour.boss_phase_for(p_max_hp, p_max_hp)
	for h: int in range(p_max_hp - 1, 0, -1):
		var ph := BossBehaviour.boss_phase_for(h, p_max_hp)
		if ph != prev:
			# The phase starts once hp drops to h: mark the boundary at h's fraction.
			out.append(float(h) / float(p_max_hp))
			prev = ph
	return out


## Take the boss's snapshot at master beat `beat`; `dt` is wall seconds since the last update.
func update(e: EnemySnap, beat: float, dt: float) -> void:
	if e == null:
		present = false
		return
	if not present or e.id != id:
		_reset_for(e)
	present = true
	hp = e.hp
	max_hp = maxi(1, e.max_hp)
	alive = e.alive
	frac = clampf(float(hp) / float(max_hp), 0.0, 1.0)
	if _last_hp >= 0 and hp < _last_hp:
		_ghost_hold = GHOST_HOLD
		hit_flash = FLASH_TIME
	_last_hp = hp
	if phase_marks.is_empty() or e.max_hp != _marks_for:
		phase_marks = phase_marks_for(e.max_hp)
		_marks_for = e.max_hp
	var new_phase := e.boss_phase if e.boss_phase >= 1 else BossBehaviour.boss_phase_for(hp, max_hp)
	if new_phase > phase:
		phase_flash = FLASH_TIME * 2.0
	phase = new_phase
	plates = clampi(PLATES - (phase - 1), 0, PLATES) if alive else 0
	staggered = e.state == EnemyStateName.STAGGER
	attention = e.target
	if not alive:
		armour = ARMOUR_BROKEN
	elif staggered:
		armour = ARMOUR_OPEN
	else:
		armour = ARMOUR_GUARDED
	var was := recalling
	recalling = e.alive and e.boss_recall
	recall_tape = e.boss_recall_tape if recalling else -1
	has_recall_at = recalling and e.has_boss_recall_at
	recall_at = e.boss_recall_at if has_recall_at else Vector2.ZERO
	if not recalling:
		recall_land_beat = -1.0
		recall_reason = &""
	elif not was and recall_land_beat < beat:
		# Entered a memory strike without having seen its event: the landing beat is unknown until
		# on_events() reports it; estimate it from the telegraph's progress (state_t over the
		# BOSS_RECALL_TELEGRAPH_BEATS-long telegraph).
		var left := BossBehaviour.BOSS_RECALL_TELEGRAPH_BEATS
		if e.state == EnemyStateName.TELEGRAPH:
			left *= clampf(1.0 - e.state_t, 0.0, 1.0)
		recall_land_beat = beat + left
	recall_beats_left = maxf(0.0, recall_land_beat - beat) if recalling and recall_land_beat >= 0.0 else -1.0
	advance(dt)


var _marks_for: int = -1


func _reset_for(e: EnemySnap) -> void:
	id = e.id
	_last_hp = -1
	max_hp = maxi(1, e.max_hp)
	frac = clampf(float(e.hp) / float(max_hp), 0.0, 1.0)
	ghost = frac
	_ghost_hold = 0.0
	phase = maxi(1, e.boss_phase)
	recall_land_beat = -1.0
	hit_flash = 0.0
	clang_flash = 0.0
	phase_flash = 0.0


## Animate the ghost bar and flashes by `dt` wall seconds.
func advance(dt: float) -> void:
	if dt <= 0.0:
		ghost = maxf(ghost, frac)
		return
	if ghost < frac:
		ghost = frac
	if _ghost_hold > 0.0:
		_ghost_hold = maxf(0.0, _ghost_hold - dt)
	elif ghost > frac:
		ghost = maxf(frac, ghost - GHOST_DRAIN * dt)
	hit_flash = maxf(0.0, hit_flash - dt)
	clang_flash = maxf(0.0, clang_flash - dt)
	phase_flash = maxf(0.0, phase_flash - dt)


## Read this frame's sim events: the memory strike's landing beat ('bossRecall' power), armour
## clangs, phase changes. Only events about this boss (by id) count.
func on_events(events: Array[SimEvent]) -> void:
	for ev: SimEvent in events:
		if id != "" and ev.id != "" and ev.id != id:
			continue
		if ev.type == SimEventType.BOSS_RECALL:
			if ev.has_power:
				recall_land_beat = ev.power
			recalling = true
			recall_tape = ev.tape
			recall_reason = StringName(ev.detail)
		elif ev.type == SimEventType.CLANG and ev.detail == "armour":
			clang_flash = FLASH_TIME
			clang_tape = ev.tape
		elif ev.type == SimEventType.BOSS_PHASE:
			phase_flash = FLASH_TIME * 2.0
