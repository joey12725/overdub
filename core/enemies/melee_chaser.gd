class_name MeleeChaser
extends EnemyBehaviour
## The shared beat-grid melee chaser used by the stalker, the shielder and the brute (port of
## `meleeChaser` in prototype/src/core/enemies/stalker.ts). They differ in targeting, strike shape,
## timing and what hits do to them, not in how a walk-telegraph-strike cycle works.
##
## The walk -> telegraph -> strike -> recover cycle (AI-04 legibility, AI-07 grid):
##   - when an attack-grid instant is exactly one telegraph away and the quarry is within reach, it
##     plants, locks its facing and telegraphs; the strike lands ON the grid instant;
##   - otherwise it walks toward the quarry (A* around walls and closed doors).
## Being shoved or staggered cancels a telegraph (framework), so a strike never lands off-grid.
##
## Subclasses set `profile` (and `type`) in _init.

## mem key: re-pick the quarry once the current recovery ends (MeleeProfile.retarget_after_strike).
const MEM_REPICK_AFTER_RECOVER: String = "repickAfterRecover"

var profile: StalkerBehaviour.MeleeProfile = null


func on_beat(w: ODSim, e: EnemyState, beat: int) -> void:
	if e.state == EnemyStateName.TELEGRAPH or e.state == EnemyStateName.ATTACK:
		return
	if profile.retarget_on_beat.call(w, e, beat):
		_repick(w, e)


func step(w: ODSim, e: EnemyState) -> void:
	var s: int = w.s
	if e.state == EnemyStateName.TELEGRAPH:
		if s >= e.attack_sub:
			_strike_now(w, e)
		return
	if e.state == EnemyStateName.ATTACK:
		if s < e.state_end:
			return
		EnemyCommon.set_state(e, EnemyStateName.IDLE, s, s)
		if e.mem.get(MEM_REPICK_AFTER_RECOVER, false):
			e.mem[MEM_REPICK_AFTER_RECOVER] = false
			_repick(w, e)
	var target: SelfActor = EnemyCommon.self_by_index(w, e.target)
	if target == null or not EnemyCommon.targetable(target):
		_repick(w, e)
		target = EnemyCommon.self_by_index(w, e.target)
	if target == null:
		if e.state != EnemyStateName.IDLE:
			EnemyCommon.set_state(e, EnemyStateName.IDLE, s, s)
		return
	var dx: float = target.pose.x - e.x
	var dy: float = target.pose.y - e.y
	# Physical reach: raw distance (perceived distance is for target choice and aggro only).
	var d: float = ODGrid.hypot(dx, dy)
	var tel: int = EnemyCommon.telegraph_subs(w, e)
	if d <= e.stats.reach and EnemyCommon.is_grid_sub(w, e, s + tel):
		e.facing = atan2(dy, dx)
		e.attack_sub = s + tel
		EnemyCommon.set_state(e, EnemyStateName.TELEGRAPH, s, s + tel)
		w.emit(SimEvent.make(0, SimEventType.ENEMY_TELEGRAPH, e.x, e.y).with_id(e.id).with_tape(target.index).with_dir(e.facing).with_detail(profile.strike_name))
		if tel == 0:
			_strike_now(w, e)
		return
	var moved: bool = EnemyCommon.walk_toward(w, e, target.pose.x, target.pose.y, e.stats.reach * profile.stop_fraction)
	if not moved:
		e.facing = atan2(dy, dx)
	if moved and e.state != EnemyStateName.MOVE:
		EnemyCommon.set_state(e, EnemyStateName.MOVE, s, s)
	elif not moved and e.state != EnemyStateName.IDLE:
		EnemyCommon.set_state(e, EnemyStateName.IDLE, s, s)


## 'beatSight' forecast (port addition; see EnemyBehaviour.forecast_attack_subs), the grunt's rule
## with this chaser's own targeting and recovery.
##
## A telegraphing chaser lands exactly on e.attack_sub. Otherwise a grid instant g can be struck only
## if a telegraph can start at g - telegraph: not before `at`, not while it is staggered, sliding or
## recovering, and only if its quarry (the one it holds, else the one its profile would pick) can be
## within reach by then: it closes at most speed * (g - telegraph - at) / SUB_HZ tiles before it must
## plant (reach is physical: raw distance). With no possible quarry it forecasts nothing. Two
## forecast instants are never closer than telegraph + recovery.
func forecast_attack_subs(w: ODSim, e: EnemyState, at: int, end_sub: int, out: Array[int]) -> bool:
	var tel: int = EnemyCommon.telegraph_subs(w, e)
	var rec: int = floori(profile.recover_beats * w.spb + 0.5)
	var busy: int = maxi(e.stagger_until, at + e.knock_subs)
	var last: float = -INF
	if e.state == EnemyStateName.TELEGRAPH and e.attack_sub >= at:
		if e.attack_sub <= end_sub:
			out.append(e.attack_sub)
		last = e.attack_sub
		busy = maxi(busy, e.attack_sub + rec)
	elif e.state == EnemyStateName.ATTACK:
		busy = maxi(busy, e.state_end)
	var target: SelfActor = EnemyCommon.self_by_index(w, e.target)
	if target == null or not EnemyCommon.targetable(target):
		target = profile.pick.call(w, e)
	if target == null:
		return true
	var dx: float = target.pose.x - e.x
	var dy: float = target.pose.y - e.y
	var gap: float = maxf(0.0, ODGrid.hypot(dx, dy) - e.stats.reach)
	var g: float = EnemyCommon.next_grid_sub(w, e, at)
	while g <= end_sub and is_finite(g):
		var gi: int = int(g)
		var start: int = gi - tel
		if start >= at and start >= busy and gi - last >= tel + rec:
			# Walking time available before the telegraph has to start.
			if gap <= e.stats.speed * float(start - at) / OD.SUB_HZ + 1e-9:
				out.append(gi)
				last = gi
		g = EnemyCommon.next_grid_sub(w, e, g + 1.0)
	return true


func _repick(w: ODSim, e: EnemyState) -> void:
	var t: SelfActor = profile.pick.call(w, e)
	e.target = t.index if t != null else -1


func _strike_now(w: ODSim, e: EnemyState) -> void:
	StalkerBehaviour.melee_strike(w, e, e.stats.reach, profile.arc, profile.strike_name)
	e.attack_sub = -1
	# Math.round of a non-negative product: floor(x + 0.5) keeps JS rounding of halves.
	EnemyCommon.set_state(e, EnemyStateName.ATTACK, w.s, w.s + floori(profile.recover_beats * w.spb + 0.5))
	if profile.retarget_after_strike:
		e.mem[MEM_REPICK_AFTER_RECOVER] = true
