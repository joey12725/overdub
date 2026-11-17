class_name TurretBehaviour
extends EnemyBehaviour
## Turret (prototype core/enemies/turret.ts; AI-06, AI-07): stationary, immovable (mass/poise INF),
## destroyed by melee.
##
##   - One telegraph before each attack-grid instant it picks the nearest targetable self that is in
##     range, in line of sight (projectile solidity: walls and closed doors block, low barriers do
##     not) and inside its optional aim arc (EnemyDef.arc, total width in radians centred on facing).
##   - It tracks that target while telegraphing and fires one straight bolt ON the grid beat at the
##     target's position at that instant. If the target became invalid it re-picks; if nothing is
##     valid when the beat arrives, the shot is withheld (a turret does not fire at nothing).
##   - Dead ghosts and desynced selves are never targeted (Scenario J: desync crosses the lane).

## Recovery after a shot, master beats.
const TURRET_RECOVER_BEATS: float = 0.25


func _init() -> void:
	type = EnemyType.TURRET


static func _aim_base(e: EnemyState) -> float:
	return e.def.facing


## Can the turret shoot at this self right now?
static func _can_shoot(w: ODSim, e: EnemyState, s: SelfActor) -> bool:
	if not s.vulnerable:
		return false
	var dx: float = s.pose.x - e.x
	var dy: float = s.pose.y - e.y
	if EnemyCommon.perceived_distance(w, sqrt(dx * dx + dy * dy)) > e.stats.reach:
		return false
	if e.def.has_arc and e.def.arc < PI * 2.0:
		if absf(TapeLib.angle_delta(_aim_base(e), atan2(dy, dx))) > e.def.arc / 2.0:
			return false
	return not w.grid.segment_blocked(e.x, e.y, s.pose.x, s.pose.y, true)


## Nearest shootable self (EnemyCommon.nearest_target filtered by _can_shoot; same order and ties).
static func _pick(w: ODSim, e: EnemyState) -> SelfActor:
	var best: SelfActor = null
	var best_d: float = INF
	var k: float = w.perceive_k
	for s: SelfActor in w.selves:
		if not s.vulnerable:
			continue
		var dx: float = s.pose.x - e.x
		var dy: float = s.pose.y - e.y
		var d: float = sqrt(dx * dx + dy * dy) * k
		if not _can_shoot(w, e, s):
			continue
		if d < best_d:
			best_d = d
			best = s
	return best


static func _fire(w: ODSim, e: EnemyState) -> void:
	var t: SelfActor = EnemyCommon.self_by_index(w, e.target)
	if t == null or not _can_shoot(w, e, t):
		t = _pick(w, e)
	e.attack_sub = -1
	var s: int = w.s
	if t == null:
		e.target = -1
		EnemyCommon.set_state(e, EnemyStateName.IDLE, s, s)
		return
	e.target = t.index
	e.facing = atan2(t.pose.y - e.y, t.pose.x - e.x)
	ProjectileSystem.spawn_bolt(w, e, e.facing)
	w.emit(
		SimEvent.make(0, SimEventType.ENEMY_SHOT, e.x, e.y).with_id(e.id).with_tape(t.index).with_dir(e.facing).with_detail("bolt")
	)
	EnemyCommon.set_state(e, EnemyStateName.ATTACK, s, s + EnemyCommon._js_round(TURRET_RECOVER_BEATS * w.spb))


func init(_w: ODSim, e: EnemyState) -> void:
	e.facing = _aim_base(e)


func step(w: ODSim, e: EnemyState) -> void:
	var s: int = w.s
	if e.state == EnemyStateName.TELEGRAPH:
		var tt: SelfActor = EnemyCommon.self_by_index(w, e.target)
		if tt != null and _can_shoot(w, e, tt):
			e.facing = atan2(tt.pose.y - e.y, tt.pose.x - e.x)
		if s >= e.attack_sub:
			_fire(w, e)
		return
	if e.state == EnemyStateName.ATTACK:
		if s < e.state_end:
			return
		EnemyCommon.set_state(e, EnemyStateName.IDLE, s, s)
	var tel: int = EnemyCommon.telegraph_subs(w, e)
	if not EnemyCommon.is_grid_sub(w, e, s + tel):
		return
	var t: SelfActor = _pick(w, e)
	if t == null:
		e.target = -1
		return
	e.target = t.index
	e.facing = atan2(t.pose.y - e.y, t.pose.x - e.x)
	e.attack_sub = s + tel
	EnemyCommon.set_state(e, EnemyStateName.TELEGRAPH, s, s + tel)
	w.emit(
		SimEvent.make(0, SimEventType.ENEMY_TELEGRAPH, e.x, e.y).with_id(e.id).with_tape(t.index).with_dir(e.facing).with_detail("bolt")
	)
	if tel == 0:
		_fire(w, e)


## 'beatSight' forecast (port addition; see EnemyBehaviour.forecast_attack_subs).
##
## A telegraphing turret fires on e.attack_sub (if it still has something to shoot at; the forecast
## keeps the committed instant). A turret never moves, so beyond that it fires on a grid instant g
## exactly when some self is shootable when the telegraph for g starts: the forecast lists the grid
## instants whose telegraph can still start (not before `at`, not while staggered or recovering) as
## long as some self is shootable now (in range, line of sight, aim arc). Nothing shootable: nothing.
func forecast_attack_subs(w: ODSim, e: EnemyState, at: int, end_sub: int, out: Array[int]) -> bool:
	var tel: int = EnemyCommon.telegraph_subs(w, e)
	var busy: int = maxi(e.stagger_until, at + e.knock_subs)
	var committed: int = -1
	if e.state == EnemyStateName.TELEGRAPH and e.attack_sub >= at:
		committed = e.attack_sub
		if committed <= end_sub:
			out.append(committed)
		busy = maxi(busy, committed + EnemyCommon._js_round(TURRET_RECOVER_BEATS * w.spb))
	elif e.state == EnemyStateName.ATTACK:
		busy = maxi(busy, e.state_end)
	if _pick(w, e) == null:
		return true
	var g: float = EnemyCommon.next_grid_sub(w, e, at)
	while g <= end_sub and is_finite(g):
		var gi: int = int(g)
		if gi != committed and gi - tel >= at and gi - tel >= busy:
			out.append(gi)
		g = EnemyCommon.next_grid_sub(w, e, g + 1.0)
	return true
