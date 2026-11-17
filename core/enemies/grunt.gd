class_name GruntBehaviour
extends EnemyBehaviour
## Grunt (prototype core/enemies/grunt.ts; AI-01, AI-07): walks at the NEAREST targetable self and
## strikes on its beat grid.
##
##   - Re-targets on every master beat (and immediately if its target stops being targetable), so a
##     closer self changes what it does at a legible moment (TEST-18, AI-02).
##   - When an attack-grid instant is exactly one telegraph away and its target is within reach, it
##     plants, locks its facing and telegraphs; the strike lands ON the grid beat (AI-07) and hits
##     every vulnerable self inside its reach + arc at that instant (one hit is lethal; HEALTH-01).
##     Locking the facing at telegraph start makes the strike dodgeable by moving or rolling.
##   - Otherwise it walks toward the target (path-finding around walls and closed doors).
##
## The prototype's GRUNT constant is the instance EnemyRegistry creates (GruntBehaviour.new()).

## Total strike arc, radians.
const GRUNT_ARC: float = 2.0 * PI / 3.0
## Recovery after a strike, master beats.
const GRUNT_RECOVER_BEATS: float = 0.25
## The grunt stops walking this fraction of its reach from its target's centre.
const STOP_FRACTION: float = 0.6


func _init() -> void:
	type = EnemyType.GRUNT


static func _retarget(w: ODSim, e: EnemyState) -> void:
	var t: SelfActor = EnemyCommon.nearest_target(w, e.x, e.y)
	e.target = t.index if t != null else -1


static func _strike(w: ODSim, e: EnemyState) -> void:
	var ar: float = Tuning.BASE.actor_radius
	var reach: float = e.stats.reach + ar
	for s: SelfActor in w.selves:
		if not s.vulnerable:
			continue
		var dx: float = s.pose.x - e.x
		var dy: float = s.pose.y - e.y
		var d: float = sqrt(dx * dx + dy * dy)
		if d > reach:
			continue
		if d > ar:
			var slack: float = asin(minf(1.0, ar / d))
			if absf(TapeLib.angle_delta(e.facing, atan2(dy, dx))) > GRUNT_ARC / 2.0 + slack:
				continue
		if w.grid.segment_blocked(e.x, e.y, s.pose.x, s.pose.y, true):
			continue
		w.combat.hit_self(SelfHit.make(s, "struck by grunt %s" % e.id, e.x, e.y, e.facing))
	w.emit(SimEvent.make(0, SimEventType.ENEMY_ATTACK, e.x, e.y).with_id(e.id).with_dir(e.facing).with_detail("strike"))


static func _recover_subs(w: ODSim) -> int:
	return EnemyCommon._js_round(GRUNT_RECOVER_BEATS * w.spb)


func on_beat(w: ODSim, e: EnemyState, _beat: int) -> void:
	if e.state == EnemyStateName.TELEGRAPH or e.state == EnemyStateName.ATTACK:
		return
	_retarget(w, e)


func step(w: ODSim, e: EnemyState) -> void:
	var s: int = w.s
	if e.state == EnemyStateName.TELEGRAPH:
		if s >= e.attack_sub:
			_strike(w, e)
			e.attack_sub = -1
			EnemyCommon.set_state(e, EnemyStateName.ATTACK, s, s + _recover_subs(w))
		return
	if e.state == EnemyStateName.ATTACK:
		if s < e.state_end:
			return
		EnemyCommon.set_state(e, EnemyStateName.IDLE, s, s)
	var target: SelfActor = EnemyCommon.self_by_index(w, e.target)
	if target == null or not target.vulnerable:
		_retarget(w, e)
		target = EnemyCommon.self_by_index(w, e.target)
	if target == null:
		if e.state != EnemyStateName.IDLE:
			EnemyCommon.set_state(e, EnemyStateName.IDLE, s, s)
		return
	var dx: float = target.pose.x - e.x
	var dy: float = target.pose.y - e.y
	var d: float = sqrt(dx * dx + dy * dy)
	var tel: int = EnemyCommon.telegraph_subs(w, e)
	if d <= e.stats.reach and EnemyCommon.is_grid_sub(w, e, s + tel):
		e.facing = atan2(dy, dx)
		e.attack_sub = s + tel
		EnemyCommon.set_state(e, EnemyStateName.TELEGRAPH, s, s + tel)
		w.emit(
			SimEvent.make(0, SimEventType.ENEMY_TELEGRAPH, e.x, e.y)
			.with_id(e.id)
			.with_tape(target.index)
			.with_dir(e.facing)
			.with_detail("strike")
		)
		if tel == 0:
			_strike(w, e)
			e.attack_sub = -1
			EnemyCommon.set_state(e, EnemyStateName.ATTACK, s, s + _recover_subs(w))
		return
	var moved: bool = EnemyCommon.walk_toward(w, e, target.pose.x, target.pose.y, e.stats.reach * STOP_FRACTION)
	if not moved:
		e.facing = atan2(dy, dx)
	if moved and e.state != EnemyStateName.MOVE:
		EnemyCommon.set_state(e, EnemyStateName.MOVE, s, s)
	elif not moved and e.state != EnemyStateName.IDLE:
		EnemyCommon.set_state(e, EnemyStateName.IDLE, s, s)


## 'beatSight' forecast (port addition; see EnemyBehaviour.forecast_attack_subs).
##
## A telegraphing grunt lands exactly on e.attack_sub. Otherwise a grid instant g can be struck only
## if a telegraph can start at g - telegraph: not before `at`, not while it is staggered, sliding or
## recovering, and only if its target (the one it holds, else the nearest it would pick) can be within
## reach by then: a grunt closes at most speed * (g - telegraph - now) / SUB_HZ tiles before it must
## plant. With no possible target it forecasts nothing. Later strikes need the recovery too: two
## forecast instants are never closer than telegraph + recovery.
func forecast_attack_subs(w: ODSim, e: EnemyState, at: int, end_sub: int, out: Array[int]) -> bool:
	var tel: int = EnemyCommon.telegraph_subs(w, e)
	var busy: int = maxi(e.stagger_until, at + e.knock_subs)
	var last: float = -INF
	if e.state == EnemyStateName.TELEGRAPH and e.attack_sub >= at:
		if e.attack_sub <= end_sub:
			out.append(e.attack_sub)
		last = e.attack_sub
		busy = maxi(busy, e.attack_sub + _recover_subs(w))
	elif e.state == EnemyStateName.ATTACK:
		busy = maxi(busy, e.state_end)
	var target: SelfActor = EnemyCommon.self_by_index(w, e.target)
	if target == null or not target.vulnerable:
		target = EnemyCommon.nearest_target(w, e.x, e.y)
	if target == null:
		return true
	var dx: float = target.pose.x - e.x
	var dy: float = target.pose.y - e.y
	var gap: float = maxf(0.0, sqrt(dx * dx + dy * dy) - e.stats.reach)
	var g: float = EnemyCommon.next_grid_sub(w, e, at)
	while g <= end_sub and is_finite(g):
		var gi: int = int(g)
		var start: int = gi - tel
		if start >= at and start >= busy and gi - last >= tel + _recover_subs(w):
			# Walking time available before the telegraph has to start.
			if gap <= e.stats.speed * float(start - at) / OD.SUB_HZ + 1e-9:
				out.append(gi)
				last = gi
		g = EnemyCommon.next_grid_sub(w, e, g + 1.0)
	return true
