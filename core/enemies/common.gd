class_name EnemyCommon
extends RefCounted
## Shared enemy machinery (prototype core/enemies/common.ts): state creation, the per-substep driver,
## beat-grid helpers, targeting, navigation, knockback and stagger. Behaviours (grunt.gd,
## turret.gd, ...) build on these.
##
## Knockback (MOM-05) is a real slide over KNOCKBACK_SECONDS with wall collision; the enemy keeps
## whatever position it ends at and resumes from there. Hitting a wall mid-slide turns the
## remaining distance into extra stagger. Neither ever applies to selves (MOM-06).
##
## JS vs GDScript: Math.hypot(a, b) is written sqrt(a*a + b*b) (identical up to the last bit; never
## Vector2, which is float32 in Godot). Math.round is JS round-half-up: _js_round below.

## Substeps between navigation re-plans while chasing (re-planning also happens on any door change).
const ENEMY_REPLAN_SUBS: int = 60


## JS Math.round (halves round toward +infinity; GDScript round() rounds them away from zero).
static func _js_round(v: float) -> int:
	return int(floor(v + 0.5))


static func create_enemy_state(def: EnemyDef) -> EnemyState:
	var stats: Tuning.EnemyStats = Tuning.enemy_stats(def.type)
	var e := EnemyState.new()
	var hp: int = def.hp if def.has_hp else int(stats.hp)
	e.id = def.id
	e.type = def.type
	e.def = def
	e.stats = stats
	e.beh = EnemyRegistry.get_enemy_behaviour(def.type)
	e.every = float(def.beat_every) if def.has_beat else float(stats.every)
	e.offset = def.beat_offset if def.has_beat else float(stats.offset)
	e.x = def.x
	e.y = def.y
	e.facing = def.facing
	e.hp = hp
	e.max_hp = hp
	e.alive = true
	e.awake = def.wake_when == null
	e.state = EnemyStateName.IDLE if def.wake_when == null else EnemyStateName.ASLEEP
	e.state_start = 0
	e.state_end = 0
	e.target = -1
	e.attack_sub = -1
	e.stagger_until = 0
	e.knock_dx = 0.0
	e.knock_dy = 0.0
	e.knock_subs = 0
	e.path = []
	e.path_idx = 0
	e.plan_sub = -INF
	e.plan_rev = -1
	e.plan_tx = 0.0
	e.plan_ty = 0.0
	e.death_sub = -1
	e.killed_by = ""
	e.mem = {}
	return e


static func set_state(e: EnemyState, state: StringName, start: int, end: int) -> void:
	e.state = state
	e.state_start = start
	e.state_end = end


## Enemies phase of a substep. Fixed order: entity order. For each living enemy: integrate any
## knockback slide; if awake and neither staggered nor sliding, run on_beat on beat boundaries and
## then step.
static func step_enemies(w: ODSim) -> void:
	var s: int = w.s
	var spb: int = w.spb
	for e: EnemyState in w.enemies:
		if not e.alive:
			continue
		if e.knock_subs > 0:
			_integrate_knockback(w, e)
		if not e.awake:
			continue
		if s < e.stagger_until:
			e.state = EnemyStateName.STAGGER
			continue
		if e.state == EnemyStateName.STAGGER:
			set_state(e, EnemyStateName.IDLE, s, s)
		if e.knock_subs > 0:
			continue
		var beh: EnemyBehaviour = e.beh
		if s % spb == 0:
			@warning_ignore("integer_division")
			beh.on_beat(w, e, s / spb)
		beh.step(w, e)

# ───────────────────────────── beat grid (AI-07) ─────────────────────────────


static func _grid_period(w: ODSim, e: EnemyState) -> int:
	return _js_round(e.every * w.spb)


static func _grid_offset(w: ODSim, e: EnemyState) -> int:
	return _js_round(e.offset * w.spb)


## Is `sub` on this enemy's attack grid (offset + k * every beats)?
static func is_grid_sub(w: ODSim, e: EnemyState, sub: int) -> bool:
	var p: int = _grid_period(w, e)
	if p <= 0:
		return false
	# int % keeps the dividend's sign, like JS %.
	var r: int = (sub - _grid_offset(w, e)) % p
	return (r + p if r < 0 else r) == 0


## First grid substep at or after `from`; INF when the enemy has no grid (prototype: Infinity).
static func next_grid_sub(w: ODSim, e: EnemyState, from: float) -> float:
	var p: int = _grid_period(w, e)
	var off: int = _grid_offset(w, e)
	if p <= 0:
		return INF
	var k: float = ceil((from - off) / float(p))
	return off + k * p


## Telegraph length in substeps (AI-04 legibility).
static func telegraph_subs(w: ODSim, e: EnemyState) -> int:
	return maxi(0, _js_round(e.stats.telegraph_beats * w.spb))

# ───────────────────────────── targeting ─────────────────────────────


## Only alive, synced selves are ever targeted: dead ghosts, the recording ghost (GHOST-04) and
## desynced projections (DESYNC-07) are ignored by enemy decisions (ARCHITECTURE, AI-07 policy).
static func targetable(self_actor: SelfActor) -> bool:
	return self_actor.vulnerable


## Distance as enemy decision logic perceives it. Loadout abilities: 'lowProfile' selves read as
## farther, 'loudmouth' selves as nearer (factors and rule in Abilities.effective_distance, the single
## source; the sim caches its factor once per run as ODSim.perceive_k = effective_distance(abilities,
## 1), and effective_distance is d * k, so the product is the same number). The loadout is shared by
## every cassette, so these change ranges (who is in reach / in aggro), not which self is nearest.
static func perceived_distance(w: ODSim, d: float) -> float:
	return d * w.perceive_k


## Nearest targetable self from (x, y) by perceived straight-line distance, optionally filtered by
## `accept(self_actor: SelfActor, dist: float) -> bool`. Ties go to the lowest tape index (selves are
## kept sorted by index; strict comparison).
static func nearest_target(w: ODSim, x: float, y: float, accept: Callable = Callable()) -> SelfActor:
	var best: SelfActor = null
	var best_d: float = INF
	var k: float = w.perceive_k
	var filtered: bool = accept.is_valid()
	for s: SelfActor in w.selves:
		if not s.vulnerable:
			continue
		var dx: float = s.pose.x - x
		var dy: float = s.pose.y - y
		var d: float = sqrt(dx * dx + dy * dy) * k
		if filtered and not accept.call(s, d):
			continue
		if d < best_d:
			best_d = d
			best = s
	return best


## The self with tape index `index`, or null (also for -1).
static func self_by_index(w: ODSim, index: int) -> SelfActor:
	if index < 0:
		return null
	for s: SelfActor in w.selves:
		if s.index == index:
			return s
	return null

# ───────────────────────────── navigation ─────────────────────────────


## Walk toward (tx, ty) for one substep, stopping `stop` tiles short. Heads straight when the swept
## body has a clear line, otherwise follows an A* route re-planned on door changes, periodically,
## and when the goal has moved more than a tile. Movement collides with walls (no tunnelling).
## Returns true if the enemy moved.
static func walk_toward(w: ODSim, e: EnemyState, tx: float, ty: float, stop: float) -> bool:
	var ddx: float = tx - e.x
	var ddy: float = ty - e.y
	var dist: float = sqrt(ddx * ddx + ddy * ddy)
	if dist <= stop:
		return false
	var budget: float = minf(e.stats.speed / OD.SUB_HZ, dist - stop)
	if not (budget > 0.0):
		return false
	var r: float = e.stats.radius
	var gx: float = tx
	var gy: float = ty
	var grid: ODGrid = w.grid
	if grid.sweep_circle_blocked(e.x, e.y, tx, ty, r * 0.95):
		var mdx: float = tx - e.plan_tx
		var mdy: float = ty - e.plan_ty
		var stale: bool = (
			e.plan_rev != grid.revision
			or w.s - e.plan_sub >= ENEMY_REPLAN_SUBS
			or e.path_idx >= e.path.size()
			or sqrt(mdx * mdx + mdy * mdy) > 1.0
		)
		if stale:
			var opts: Pathfinder.PathOpts = Pathfinder.PathOpts.make(true).with_radius(r)
			var res: Pathfinder.PathResult = w.paths.find_path(e.x, e.y, tx, ty, opts)
			if res != null:
				e.path = res.points
			else:
				e.path = []
			e.path_idx = 0
			e.plan_rev = grid.revision
			e.plan_sub = w.s
			e.plan_tx = tx
			e.plan_ty = ty
		# Skip waypoints already reached.
		while e.path_idx < e.path.size():
			var wp: Vector2 = e.path[e.path_idx]
			var wx: float = wp.x - e.x
			var wy: float = wp.y - e.y
			if sqrt(wx * wx + wy * wy) < 1e-6:
				e.path_idx += 1
			else:
				break
		if e.path_idx >= e.path.size():
			return false
		var g: Vector2 = e.path[e.path_idx]
		gx = g.x
		gy = g.y
		var gdx: float = gx - e.x
		var gdy: float = gy - e.y
		var dg: float = sqrt(gdx * gdx + gdy * gdy)
		if dg <= budget:
			budget = dg
			e.path_idx += 1
	var dx: float = gx - e.x
	var dy: float = gy - e.y
	var d: float = sqrt(dx * dx + dy * dy)
	if not (d > 0.0):
		return false
	var mv: ODGrid.MoveResult = grid.move_circle(e.x, e.y, (dx / d) * budget, (dy / d) * budget, r, null, w.move_scratch)
	var moved: bool = mv.x != e.x or mv.y != e.y
	e.x = mv.x
	e.y = mv.y
	e.facing = atan2(dy, dx)
	return moved

# ───────────────────────────── knockback, stagger, death ─────────────────────────────


## Substeps a knockback slide lasts: max(1, round(KNOCKBACK_SECONDS * SUB_HZ)).
static func knock_subs_total() -> int:
	return maxi(1, _js_round(Tuning.KNOCKBACK_SECONDS * OD.SUB_HZ))


## Start (or add to) a knockback slide of `dist` tiles in direction `dir` (MOM-05).
static func apply_knockback(w: ODSim, e: EnemyState, dir: float, dist: float) -> void:
	if not (dist > 0.0):
		return
	var n: int = knock_subs_total()
	var rem_x: float = e.knock_dx * e.knock_subs
	var rem_y: float = e.knock_dy * e.knock_subs
	var tx: float = rem_x + cos(dir) * dist
	var ty: float = rem_y + sin(dir) * dist
	e.knock_dx = tx / n
	e.knock_dy = ty / n
	e.knock_subs = n
	# A shove breaks a telegraph: the attack would otherwise land off the beat grid (AI-07).
	if e.state == EnemyStateName.TELEGRAPH:
		e.attack_sub = -1
		set_state(e, EnemyStateName.IDLE, w.s, w.s)
	e.path = []
	e.path_idx = 0


static func _integrate_knockback(w: ODSim, e: EnemyState) -> void:
	var want: float = sqrt(e.knock_dx * e.knock_dx + e.knock_dy * e.knock_dy)
	var res: ODGrid.MoveResult = w.grid.move_circle(e.x, e.y, e.knock_dx, e.knock_dy, e.stats.radius, null, w.move_scratch)
	var gx: float = res.x - e.x
	var gy: float = res.y - e.y
	var got: float = sqrt(gx * gx + gy * gy)
	var blocked: bool = res.blocked
	e.x = res.x
	e.y = res.y
	e.knock_subs -= 1
	if blocked and want - got > want * 0.5:
		# Slammed into a wall: the rest of the slide becomes stagger.
		var remaining: float = want - got + want * e.knock_subs
		e.knock_subs = 0
		apply_stagger(w, e, _js_round(remaining * Tuning.WALL_SLAM_STAGGER_PER_TILE * OD.SUB_HZ))
	if e.knock_subs <= 0:
		e.knock_subs = 0
		e.knock_dx = 0.0
		e.knock_dy = 0.0


## Stagger for `subs` master substeps: cancels any telegraph, emits 'enemyStagger'.
static func apply_stagger(w: ODSim, e: EnemyState, subs: int) -> void:
	if not (subs > 0) or not e.alive:
		return
	var until: int = w.s + subs
	if until <= e.stagger_until:
		return
	e.stagger_until = until
	e.attack_sub = -1
	set_state(e, EnemyStateName.STAGGER, w.s, until)
	w.emit(SimEvent.make(0, SimEventType.ENEMY_STAGGER, e.x, e.y).with_id(e.id).with_power(float(subs) / OD.SUB_HZ))


## Player-readable name of a strike source ("Tape A", "turret t1", "laser beam").
static func describe_source(w: ODSim, src: StrikeSource) -> String:
	if src.tape >= 0:
		return "Tape %s" % OD.TAPE_NAMES[src.tape]
	if not src.enemy.is_empty():
		var e: EnemyState = w.enemy_by_id(src.enemy)
		return "%s %s" % [e.type, e.id] if e != null else src.enemy
	return src.env


static func kill_enemy(w: ODSim, e: EnemyState, strike: EnemyStrike) -> void:
	e.alive = false
	e.hp = 0
	e.death_sub = w.s
	e.killed_by = describe_source(w, strike.source)
	e.knock_subs = 0
	e.attack_sub = -1
	set_state(e, EnemyStateName.DEAD, w.s, w.s)
	w.emit(
		SimEvent.make(0, SimEventType.KILL, e.x, e.y)
		.with_id(e.id)
		.with_tape(strike.source.tape)
		.with_power(strike.momentum)
		.with_dir(strike.dir)
		.with_detail(strike.kind)
	)
	w.log.kill(e.id, w.s, e.killed_by)
	e.beh.on_death(w, e)


## Plain-data snapshot of an enemy at master instant `at`.
static func enemy_snapshot(w: ODSim, e: EnemyState, at: int) -> EnemySnap:
	var span: int = e.state_end - e.state_start
	var progress: float = float(at - e.state_start) / span if span > 0 else 0.0
	progress = 0.0 if progress < 0.0 else (1.0 if progress > 1.0 else progress)
	var snap := EnemySnap.new()
	snap.id = e.id
	snap.type = e.type
	snap.x = e.x
	snap.y = e.y
	snap.facing = e.facing
	snap.hp = e.hp
	snap.max_hp = e.max_hp
	snap.alive = e.alive
	snap.state = e.state
	snap.state_t = progress
	# Only report a target that can still be targeted: a self that died or desynced is let go.
	var t: SelfActor = self_by_index(w, e.target)
	if e.alive and t != null and t.vulnerable:
		snap.target = t.index
	e.beh.snapshot(w, e, snap)
	return snap
