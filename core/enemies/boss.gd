class_name BossBehaviour
extends EnemyBehaviour
## The outside-the-loop boss (BOSS-01..03, HEALTH-03, AI-04, AI-07). Port of
## prototype/src/core/enemies/boss.ts (its 'shock' projectile archetype is ShockArchetype,
## core/enemies/shock_archetype.gd, registered lazily by ProjectileSystem).
##
## A stationary, anchored colossus with a health bar (EnemyDef.hp, else ENEMY_STATS.boss.hp). It is
## built so that one self can never beat it and a coordinated group can, and so that what it
## remembers from committed takes is visible, telegraphed and exploitable.
##
## ATTENTION AND ARMOUR (BOSS-03). The boss always watches one self: its attention is the NEAREST
## targetable self, re-chosen on every beat while it is not committed to an attack (and at once when
## that self stops being targetable). It turns toward it at BOSS_TURN_RATE. Its front is armour:
##   a hit does damage only if it comes from a self that is NOT holding its attention, and lands on
##   its back (the push direction within BOSS_BACK_HALF_ARC of the way it faces).
## Everything else clangs ('clang', detail 'armour'). So one self can never hurt it - whoever is
## alone is always the one it watches - and the basic plan is "one self holds its eye up close,
## another strikes from behind". It is never shoved (anchored); only a hit of at least
## BOSS_STAGGER_MOMENTUM through the armour staggers it, which cancels whatever it is telegraphing.
##
## BASE PATTERN (the bar grid; AI-07). Attacks land on its beat grid (ENEMY_STATS boss: every bar),
## each announced by a telegraph of telegraphBeats:
##   - 'cleave' : a wide frontal arc (BOSS_CLEAVE_ARC) of radius + reach at its attention, facing
##                locked at telegraph start;
##   - 'volley' : instead of a cleave when its attention is out of cleave range, BOSS_VOLLEY_COUNT
##                bolts fanned at it (aim locked at telegraph start);
##   - 'sweep'  : from phase 2, every other attack is a ring of BOSS_SWEEP_SHOTS shockwave shots
##                (range BOSS_SWEEP_RANGE; walls stop them; i-frames pass through them).
## PHASES (HEALTH-03). Phase 2 at hp <= 2/3 max, phase 3 at hp <= 1/3 max. Each change emits
## 'bossPhase' (power = new phase) and interrupts the current telegraph. Phase 3 attacks twice as
## often (half the grid period; the telegraph shortens only as much as that requires).
##
## MEMORY (BOSS-01, BOSS-02). Given SimConfig.boss_memory - built only from committed tapes
## (boss_memory.gd) - it pre-empts remembered selves. Each remembered moment (a dwell or an attack;
## `BossMemoryLib.recall_candidates`) becomes a MEMORY STRIKE planned before the run starts:
##   - it lands on a whole master beat at the remembered place: for a dwell, on the dwell's second
##     beat (or the first beat a full telegraph allows), for an attack on the beat nearest to it;
##   - BOSS_RECALL_TELEGRAPH_BEATS before that it turns to the place, telegraphs and emits
##     'bossRecall' (tape = the remembered cassette, power = landing beat, detail = 'dwell' |
##     'attack'); EnemySnap.boss_recall / boss_recall_tape / boss_recall_at mark the whole commitment
##     so the renderer can draw it differently from ordinary reactivity;
##   - the strike hits every vulnerable self within BOSS_RECALL_RADIUS of the place (walls do not
##     shelter: it is a memory, not a projectile);
##   - while it is busy with a memory its attention IS the remembered cassette, so every other self
##     can strike its back (it is busy punishing tape A's old position while tape C hits it);
##   - it handles one memory at a time: moments whose telegraph would overlap an earlier planned one
##     (or its recovery) are skipped, ties going to the earlier beat, then the lower cassette, attacks
##     before dwells; base attacks never start if they would overlap a memory strike;
##   - a memory strike whose telegraph start finds the boss staggered is dropped, and a stagger or
##     phase change during its telegraph cancels it - protecting a committed tape is a tactic.
## With no memory (the first take) it uses only the base pattern. The plan is computed from the
## memory once per run and the memory itself is never written, so identical memory always gives an
## identical fight and a resolve or a replay cannot alter what the boss knows.

## Turn rate toward its attention, radians per master second.
const BOSS_TURN_RATE: float = 2.4
## Half-width of the back arc that armour does not cover, radians (90 deg = the whole rear half).
const BOSS_BACK_HALF_ARC: float = PI / 2.0
## Total cleave arc, radians.
const BOSS_CLEAVE_ARC: float = (5.0 * PI) / 6.0
## Bolts in a volley and the angle between neighbours, radians.
const BOSS_VOLLEY_COUNT: int = 3
const BOSS_VOLLEY_SPREAD: float = PI / 12.0
## Sweep ring: shots, range (tiles) and shot radius (tiles; dense enough to leave no gaps in range).
const BOSS_SWEEP_SHOTS: int = 24
const BOSS_SWEEP_RANGE: float = 6.0
const BOSS_SWEEP_RADIUS: float = 0.35
## Recovery after a base attack, master beats.
const BOSS_RECOVER_BEATS: float = 0.5
## Memory strikes: telegraph (whole beats, so landings stay on the beat), radius, recovery.
const BOSS_RECALL_TELEGRAPH_BEATS: float = 2.0
const BOSS_RECALL_RADIUS: float = 1.25
const BOSS_RECALL_RECOVER_BEATS: float = 1.0
## A hit through the armour needs this much momentum to stagger the boss (a 2x standing heavy).
const BOSS_STAGGER_MOMENTUM: float = 4.0

## What it is committed to (boss.ts BossMode; "" = nothing).
const MODE_NONE: StringName = &""
const MODE_CLEAVE: StringName = &"cleave"
const MODE_VOLLEY: StringName = &"volley"
const MODE_SWEEP: StringName = &"sweep"
const MODE_RECALL: StringName = &"recall"

## mem keys (scalars), plus the per-run plan under MEM_RUNTIME.
const MEM_PHASE: String = "phase"
const MEM_MODE: String = "mode"
const MEM_RECALL_TAPE: String = "recallTape"
const MEM_RECALL_X: String = "recallX"
const MEM_RECALL_Y: String = "recallY"
## Holds this run's BossRuntime. The prototype kept it in a WeakMap keyed by the state; here it rides
## on the per-run EnemyState so the shared behaviour object never holds run data.
const MEM_RUNTIME: String = "runtime"


## One planned memory strike.
class RecallPlan:
	extends RefCounted
	## TapeIndex.
	var tape: int = 0
	## BossMemoryLib.REASON_DWELL | REASON_ATTACK.
	var reason: StringName = &""
	var start_sub: int = 0
	var land_sub: int = 0
	var x: float = 0.0
	var y: float = 0.0


## Per-run plan derived from the memory.
class BossRuntime:
	extends RefCounted
	var recalls: Array[RecallPlan] = []
	## Index of the next memory strike that has not started (or been dropped).
	var next: int = 0


func _init() -> void:
	type = EnemyType.BOSS
	heavy_body = true


static func _runtime(e: EnemyState) -> BossRuntime:
	var v: Variant = e.mem.get(MEM_RUNTIME)
	if v is BossRuntime:
		return v
	var rt := BossRuntime.new()
	e.mem[MEM_RUNTIME] = rt
	return rt


## Boss phase for a hit-point total: 1, 2 at <= 2/3 of max, 3 at <= 1/3 of max.
static func boss_phase_for(hp: float, max_hp: float) -> int:
	if hp * 3 <= max_hp:
		return 3
	if hp * 3 <= max_hp * 2:
		return 2
	return 1


static func _phase(e: EnemyState) -> int:
	return int(e.mem.get(MEM_PHASE, 1))


## What it is committed to. Only a telegraph or its recovery is a commitment (a stagger ends it).
static func _mode(e: EnemyState) -> StringName:
	if e.state != EnemyStateName.TELEGRAPH and e.state != EnemyStateName.ATTACK:
		return MODE_NONE
	return StringName(e.mem.get(MEM_MODE, MODE_NONE))


static func _cleave_reach(e: EnemyState) -> float:
	return e.stats.radius + e.stats.reach


# Math.round of non-negative values below: floor(x + 0.5) keeps JS rounding of halves.
static func _round(x: float) -> int:
	return floori(x + 0.5)


static func _recover_subs(w: ODSim) -> int:
	return _round(BOSS_RECOVER_BEATS * w.spb)


static func _recall_recover_subs(w: ODSim) -> int:
	return _round(BOSS_RECALL_RECOVER_BEATS * w.spb)


## Base attack grid period in substeps for the current phase (phase 3 halves it).
static func _base_period(w: ODSim, e: EnemyState) -> int:
	var p: int = _round(e.every * w.spb)
	return maxi(1, _round(p / 2.0)) if _phase(e) >= 3 else p


static func _base_telegraph(w: ODSim, e: EnemyState) -> int:
	return maxi(0, mini(EnemyCommon.telegraph_subs(w, e), _base_period(w, e) - _recover_subs(w)))


## Index of the base attack landing on `sub`, or -1 when `sub` is not on the grid.
static func _base_attack_index(w: ODSim, e: EnemyState, sub: int) -> int:
	var p: int = _base_period(w, e)
	if not (p > 0):
		return -1
	var off: int = _round(e.offset * w.spb)
	# JS % keeps the dividend's sign like GDScript's; ((x % p) + p) % p is the true modulo in both.
	var r: int = (((sub - off) % p) + p) % p
	# Math.floor of a float quotient: floori(float / int) (GDScript int / int truncates toward 0).
	return floori(float(sub - off) / p) if r == 0 else -1


## Who holds the boss's attention right now (the remembered cassette during a memory strike);
## -1 = nobody.
static func boss_attention(w: ODSim, e: EnemyState) -> int:
	if _mode(e) == MODE_RECALL:
		return int(e.mem.get(MEM_RECALL_TAPE, -1))
	var t: SelfActor = EnemyCommon.self_by_index(w, e.target)
	return t.index if t != null and EnemyCommon.targetable(t) else -1


static func _retarget(w: ODSim, e: EnemyState) -> void:
	var t: SelfActor = EnemyCommon.nearest_target(w, e.x, e.y)
	e.target = t.index if t != null else -1


## Plan the run's memory strikes from the (read-only) memory.
static func _plan_recalls(w: ODSim) -> Array[RecallPlan]:
	var out: Array[RecallPlan] = []
	var tel_beats: int = ceili(BOSS_RECALL_TELEGRAPH_BEATS)
	var tel: int = tel_beats * w.spb
	var rec: int = _recall_recover_subs(w)
	var busy_until: float = -INF
	for c: BossMemoryLib.RecallCandidate in BossMemoryLib.recall_candidates(w.boss_memory):
		var land_beat: int = maxi(c.beat + 1, tel_beats) if c.reason == BossMemoryLib.REASON_DWELL else c.beat
		if land_beat > c.last_beat and c.reason == BossMemoryLib.REASON_DWELL:
			continue
		var land_sub: int = land_beat * w.spb
		var start_sub: int = land_sub - tel
		if start_sub < 0 or land_sub >= w.horizon_subs:
			continue
		if start_sub < busy_until:
			continue
		var r := RecallPlan.new()
		r.tape = c.tape
		r.reason = c.reason
		r.start_sub = start_sub
		r.land_sub = land_sub
		r.x = c.x
		r.y = c.y
		out.append(r)
		busy_until = land_sub + rec
	return out


## Would an attack occupying substeps [a, b) collide with a memory strike still to come?
static func _clashes_with_recall(rt: BossRuntime, a: int, b: int, rec: int) -> bool:
	for i: int in range(rt.next, rt.recalls.size()):
		var r: RecallPlan = rt.recalls[i]
		if r.start_sub >= b:
			break
		if r.land_sub + rec > a:
			return true
	return false


static func _cancel_telegraph(w: ODSim, e: EnemyState) -> void:
	if e.state != EnemyStateName.TELEGRAPH:
		return
	e.attack_sub = -1
	e.mem[MEM_MODE] = MODE_NONE
	EnemyCommon.set_state(e, EnemyStateName.IDLE, w.s, w.s)


static func _start_recall(w: ODSim, e: EnemyState, r: RecallPlan) -> void:
	e.mem[MEM_MODE] = MODE_RECALL
	e.mem[MEM_RECALL_TAPE] = r.tape
	e.mem[MEM_RECALL_X] = r.x
	e.mem[MEM_RECALL_Y] = r.y
	e.facing = atan2(r.y - e.y, r.x - e.x)
	e.attack_sub = r.land_sub
	EnemyCommon.set_state(e, EnemyStateName.TELEGRAPH, w.s, r.land_sub)
	# Float division, as the prototype's landSub / spb.
	var land_beat: float = float(r.land_sub) / w.spb
	w.emit(SimEvent.make(0, SimEventType.BOSS_RECALL, r.x, r.y).with_id(e.id).with_tape(r.tape).with_dir(e.facing).with_power(land_beat).with_detail(String(r.reason)))
	w.emit(SimEvent.make(0, SimEventType.ENEMY_TELEGRAPH, r.x, r.y).with_id(e.id).with_tape(r.tape).with_dir(e.facing).with_detail("recall"))


static func _land(w: ODSim, e: EnemyState) -> void:
	var m: StringName = _mode(e)
	var s: int = w.s
	e.attack_sub = -1
	if m == MODE_RECALL:
		var x: float = float(e.mem.get(MEM_RECALL_X, 0.0))
		var y: float = float(e.mem.get(MEM_RECALL_Y, 0.0))
		var tape: int = int(e.mem.get(MEM_RECALL_TAPE, -1))
		var reach: float = BOSS_RECALL_RADIUS + Tuning.BASE.actor_radius
		var cause: String = "struck by boss %s (remembering Tape %s)" % [e.id, OD.TAPE_NAMES[tape]]
		for sa: SelfActor in w.selves:
			if not EnemyCommon.targetable(sa):
				continue
			var dx: float = sa.pose.x - x
			var dy: float = sa.pose.y - y
			if ODGrid.hypot(dx, dy) > reach:
				continue
			w.combat.hit_self(SelfHit.make(sa, cause, x, y, e.facing))
		w.emit(SimEvent.make(0, SimEventType.ENEMY_ATTACK, x, y).with_id(e.id).with_tape(tape).with_dir(e.facing).with_detail("recall"))
		EnemyCommon.set_state(e, EnemyStateName.ATTACK, s, s + _recall_recover_subs(w))
		return
	if m == MODE_CLEAVE:
		StalkerBehaviour.melee_strike(w, e, _cleave_reach(e), BOSS_CLEAVE_ARC, "cleave")
	elif m == MODE_VOLLEY:
		var half: float = (BOSS_VOLLEY_COUNT - 1) / 2.0
		for i: int in range(BOSS_VOLLEY_COUNT):
			ProjectileSystem.spawn_bolt(w, e, TapeLib.wrap_angle(e.facing + (i - half) * BOSS_VOLLEY_SPREAD))
		w.emit(SimEvent.make(0, SimEventType.ENEMY_SHOT, e.x, e.y).with_id(e.id).with_tape(e.target).with_dir(e.facing).with_detail("volley"))
	elif m == MODE_SWEEP:
		_spawn_sweep(w, e)
		w.emit(SimEvent.make(0, SimEventType.ENEMY_ATTACK, e.x, e.y).with_id(e.id).with_dir(e.facing).with_detail("sweep"))
	EnemyCommon.set_state(e, EnemyStateName.ATTACK, s, s + _recover_subs(w))


# ───────────────────────────── sweep shockwave ─────────────────────────────

static func _spawn_sweep(w: ODSim, e: EnemyState) -> void:
	var off: float = e.stats.radius + BOSS_SWEEP_RADIUS + 0.01
	for i: int in range(BOSS_SWEEP_SHOTS):
		var dir: float = TapeLib.wrap_angle(e.facing + (i * 2.0 * PI) / BOSS_SWEEP_SHOTS)
		var spec := SpawnSpec.make(-1, e.id, RangedArchetype.SHOCK, e.x + cos(dir) * off, e.y + sin(dir) * off, dir, e.stats.shot_speed, BOSS_SWEEP_RADIUS, BOSS_SWEEP_RANGE - off)
		spec.set_hits_selves(true)
		spec.hits_enemies = false
		w.projectiles.spawn(w, spec)


# ───────────────────────────── behaviour ─────────────────────────────

func init(w: ODSim, e: EnemyState) -> void:
	e.mem[MEM_PHASE] = 1
	e.mem[MEM_MODE] = MODE_NONE
	e.mem[MEM_RECALL_TAPE] = -1
	var rt := BossRuntime.new()
	rt.recalls = _plan_recalls(w)
	e.mem[MEM_RUNTIME] = rt


func on_beat(w: ODSim, e: EnemyState, _beat: int) -> void:
	if e.state == EnemyStateName.TELEGRAPH or e.state == EnemyStateName.ATTACK:
		return
	_retarget(w, e)


func step(w: ODSim, e: EnemyState) -> void:
	var s: int = w.s
	var rt: BossRuntime = _runtime(e)
	# A stagger ends a telegraph from outside (framework): forget what it was going to do.
	if e.state != EnemyStateName.TELEGRAPH and e.state != EnemyStateName.ATTACK:
		e.mem[MEM_MODE] = MODE_NONE

	if e.state == EnemyStateName.TELEGRAPH:
		if s >= e.attack_sub:
			_land(w, e)
		return
	if e.state == EnemyStateName.ATTACK:
		if s < e.state_end:
			return
		e.mem[MEM_MODE] = MODE_NONE
		EnemyCommon.set_state(e, EnemyStateName.IDLE, s, s)

	# Memory strikes whose start passed while it was staggered or busy are dropped, not delayed:
	# a late memory strike would land off its remembered beat.
	while rt.next < rt.recalls.size() and rt.recalls[rt.next].start_sub < s:
		rt.next += 1
	if rt.next < rt.recalls.size() and rt.recalls[rt.next].start_sub == s:
		_start_recall(w, e, rt.recalls[rt.next])
		rt.next += 1
		return

	var target: SelfActor = EnemyCommon.self_by_index(w, e.target)
	if target == null or not EnemyCommon.targetable(target):
		_retarget(w, e)
		target = EnemyCommon.self_by_index(w, e.target)
	if target != null:
		var want: float = atan2(target.pose.y - e.y, target.pose.x - e.x)
		var d: float = TapeLib.angle_delta(e.facing, want)
		var max_turn: float = BOSS_TURN_RATE / OD.SUB_HZ
		e.facing = TapeLib.wrap_angle(e.facing + (d if absf(d) <= max_turn else signf(d) * max_turn))

	var tel: int = _base_telegraph(w, e)
	var k: int = _base_attack_index(w, e, s + tel)
	if k < 0 or s + tel <= 0:
		return
	if _clashes_with_recall(rt, s, s + tel + _recover_subs(w), _recall_recover_subs(w)):
		return
	var next_mode: StringName
	var target_d: float = 0.0
	if target != null:
		var tdx: float = target.pose.x - e.x
		var tdy: float = target.pose.y - e.y
		# Physical reach: raw distance.
		target_d = ODGrid.hypot(tdx, tdy)
	if _phase(e) >= 2 and (k & 1) == 1:
		next_mode = MODE_SWEEP
	elif target != null and target_d > _cleave_reach(e) + Tuning.BASE.actor_radius:
		next_mode = MODE_VOLLEY
	else:
		next_mode = MODE_CLEAVE
	if target != null and next_mode != MODE_SWEEP:
		e.facing = atan2(target.pose.y - e.y, target.pose.x - e.x)
	e.mem[MEM_MODE] = next_mode
	e.attack_sub = s + tel
	EnemyCommon.set_state(e, EnemyStateName.TELEGRAPH, s, s + tel)
	w.emit(SimEvent.make(0, SimEventType.ENEMY_TELEGRAPH, e.x, e.y).with_id(e.id).with_tape(target.index if target != null else -1).with_dir(e.facing).with_detail(String(next_mode)))
	if tel == 0:
		_land(w, e)


func on_hit(w: ODSim, e: EnemyState, strike: EnemyStrike) -> HitResponse:
	if not strike.source.is_tape():
		return HitResponse.block("armour")
	if strike.source.tape == boss_attention(w, e):
		return HitResponse.block("armour")
	if absf(TapeLib.angle_delta(e.facing, strike.dir)) > BOSS_BACK_HALF_ARC:
		return HitResponse.block("armour")
	var mel: MeleeWeaponDef = w.loadout.melee
	var mods: StatMods = w.loadout.mods
	var damage: float = strike.damage if strike.has_damage else float(Tuning.strike_damage(strike.momentum, mel.damage_eff, mods.damage))
	var stagger: float = 0.0
	if strike.momentum >= BOSS_STAGGER_MOMENTUM:
		stagger = strike.stagger if strike.has_stagger else Tuning.strike_stagger(strike.momentum, mel.stagger_eff, mods.stagger, e.stats.poise)
	var after: float = e.hp - damage
	if after > 0:
		var phase: int = boss_phase_for(after, e.max_hp)
		var was: int = _phase(e)
		if phase > was:
			for p: int in range(was + 1, phase + 1):
				w.emit(SimEvent.make(0, SimEventType.BOSS_PHASE, e.x, e.y).with_id(e.id).with_tape(strike.source.tape).with_power(p).with_detail("phase %d" % p))
			e.mem[MEM_PHASE] = phase
			_cancel_telegraph(w, e)
	var st: EnemyStrike = strike.copy()
	st.damage = damage
	st.has_damage = true
	st.knockback = 0.0
	st.has_knockback = true
	st.stagger = stagger
	st.has_stagger = true
	return HitResponse.replace(st)


## 'beatSight' forecast (port addition; see EnemyBehaviour.forecast_attack_subs).
##
## The boss attacks whether or not anyone is near (a cleave at empty air still lands on its grid), so
## the forecast is its plan for the window, from the current state:
##   - a committed telegraph (base attack or memory strike) lands exactly on e.attack_sub;
##   - every memory strike still to come whose telegraph start is not ruled out (not before `at`,
##     not while staggered, sliding or still busy) lands on its planned beat;
##   - every base-grid instant of the CURRENT phase (phase 3 halves the period) whose telegraph can
##     start (same rules) and that would not overlap a memory strike still to come at that moment.
## A phase change during the window is not foreseen (it depends on hits not yet landed).
func forecast_attack_subs(w: ODSim, e: EnemyState, at: int, end_sub: int, out: Array[int]) -> bool:
	var rt: BossRuntime = _runtime(e)
	var rec: int = _recover_subs(w)
	var recall_rec: int = _recall_recover_subs(w)
	var busy: int = maxi(e.stagger_until, at + e.knock_subs)
	if e.state == EnemyStateName.TELEGRAPH and e.attack_sub >= at:
		if e.attack_sub <= end_sub:
			out.append(e.attack_sub)
		busy = maxi(busy, e.attack_sub + (recall_rec if _mode(e) == MODE_RECALL else rec))
	elif e.state == EnemyStateName.ATTACK:
		busy = maxi(busy, e.state_end)
	# Memory strikes still to come, in order; a dropped one frees nothing (the plan never overlaps).
	for i: int in range(rt.next, rt.recalls.size()):
		var r: RecallPlan = rt.recalls[i]
		if r.land_sub > end_sub:
			break
		if r.start_sub >= at and r.start_sub >= busy:
			out.append(r.land_sub)
	var tel: int = _base_telegraph(w, e)
	var p: int = _base_period(w, e)
	if not (p > 0):
		return true
	var off: int = _round(e.offset * w.spb)
	# First grid instant >= at (true modulo, as _base_attack_index).
	var g: int = at + ((((off - at) % p) + p) % p)
	while g <= end_sub:
		var start: int = g - tel
		# A memory strike that runs into [start, g + recovery) - started earlier and still going, or
		# starting inside it - keeps the base attack from starting, exactly as in step.
		if g > 0 and start >= at and start >= busy and not _clashes_with_recall(rt, start, start + tel + rec, recall_rec):
			out.append(g)
		g += p
	return true


func on_death(_w: ODSim, e: EnemyState) -> void:
	e.mem[MEM_MODE] = MODE_NONE


func snapshot(_w: ODSim, e: EnemyState, snap: EnemySnap) -> void:
	snap.boss_phase = _phase(e)
	var recalling: bool = e.alive and _mode(e) == MODE_RECALL
	snap.boss_recall = recalling
	if recalling:
		snap.boss_recall_tape = int(e.mem.get(MEM_RECALL_TAPE, -1))
		snap.boss_recall_at = Vector2(float(e.mem.get(MEM_RECALL_X, 0.0)), float(e.mem.get(MEM_RECALL_Y, 0.0)))
		snap.has_boss_recall_at = true
