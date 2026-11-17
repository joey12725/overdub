class_name ProjectileSystem
extends RefCounted
## Projectiles: world objects simulated in master time (prototype core/projectiles.ts; MISSILE-04,
## WEAPON-01..03, AI-06).
##
## EXTENSION POINTS (adding 'missile' | 'pierce' | 'phase' | 'arc' | 'burst' is purely additive)
##
##   ProjectileSystem.register_projectile_archetype(arch)
##     An archetype is a ProjectileArchetype (core/projectile_archetype.gd) keyed by its id; its
##     hooks (launch, step, on_hit_enemy, on_hit_self, on_hit_wall, on_expire) default to the
##     prototype's behaviour when the hook is absent.
##
##   Projectile flags consulted by fly_straight: passes_walls, hits_selves, hits_enemies, radius, range.
##   Per-projectile scratch lives in `p.data` (plain numbers) and `p.struck` (ids already hit).
##
## The player's five weapon archetypes live in core/weapons/ (one file each), registered lazily by
## Weapons.register_self_weapons() the first time the registry is read. The only archetype implemented
## here is the enemy 'bolt' (BoltArchetype, core/bolt_archetype.gd); the boss's 'shock' is
## ShockArchetype (core/enemies/shock_archetype.gd).
##
## Port addition: a self's straight-flying projectile strikes unbroken breakables it runs into and
## cores it touches with its momentum (Mechanisms.projectile_strike_breakable / _core; 'clang' when
## too weak). A wall-passing projectile ('phase') never meets a breakable, so it does not strike one.
##
## JS vs GDScript: the contact sort is a total order (t, order, index), so Godot's unstable sort could
## not reorder anything; it is an insertion sort here anyway (a handful of contacts, no allocation).

## Bolts fly until they hit something; this only bounds runaway bolts in open maps.
const BOLT_RANGE: float = 64.0
## Stagger a bolt inflicts on an enemy it strikes, master seconds.
const BOLT_ENEMY_STAGGER: float = 0.25

## Contact kinds, in tie order (selves first, then enemies, then cores; then lower index).
const _C_SELF: int = 0
const _C_ENEMY: int = 1
const _C_CORE: int = 2

static var _archetypes: Dictionary[StringName, ProjectileArchetype] = {}
static var _filled: bool = false

var list: Array[Projectile] = []
var _next_id: int = 1

# fly_straight scratch (per system, so sims on different threads never share it).
var _ray: ODGrid.RayHit = ODGrid.RayHit.new()
var _wall: ODGrid.RayHit = ODGrid.RayHit.new()
var _c_t: PackedFloat64Array = PackedFloat64Array()
var _c_kind: PackedInt32Array = PackedInt32Array()
var _c_index: PackedInt32Array = PackedInt32Array()
var _c_ref: Array[RefCounted] = []
var _c_order: PackedInt32Array = PackedInt32Array()

# ───────────────────────────── registry ─────────────────────────────


## Built-ins, registered once on first use: BOLT, the five self weapons, the boss's SHOCK, the dart
## launcher trap's DART (the prototype's traps/dart.ts registers itself on import).
static func _ensure_defaults() -> void:
	if _filled:
		return
	_filled = true
	_archetypes[RangedArchetype.BOLT] = BoltArchetype.new()
	Weapons.register_self_weapons()
	var shock: ProjectileArchetype = ShockArchetype.new()
	_archetypes[shock.id] = shock
	var dart: ProjectileArchetype = DartArchetype.new()
	_archetypes[dart.id] = dart


## Register (or replace) a projectile archetype.
static func register_projectile_archetype(a: ProjectileArchetype) -> void:
	_ensure_defaults()
	_archetypes[a.id] = a


## The archetype registered for `id`, or null.
static func get_projectile_archetype(id: StringName) -> ProjectileArchetype:
	_ensure_defaults()
	return _archetypes.get(id)

# ───────────────────────────── the system ─────────────────────────────


func spawn(w: ODSim, spec: SpawnSpec) -> Projectile:
	var p := Projectile.new()
	p.id = _next_id
	_next_id += 1
	p.owner_tape = spec.owner_tape
	p.owner_enemy = spec.owner_enemy if spec.owner_tape < 0 else ""
	p.archetype = spec.archetype
	p.x = spec.x
	p.y = spec.y
	p.z = spec.z
	p.dir = spec.dir
	p.speed = spec.speed
	p.radius = spec.radius
	p.range = spec.range
	p.travelled = 0.0
	p.alive = true
	p.momentum = spec.momentum
	p.passes_walls = spec.passes_walls
	p.hits_selves = spec.hits_selves if spec.has_hits_selves else spec.owner_tape < 0
	p.hits_enemies = spec.hits_enemies
	p.pierce_left = spec.pierce
	p.struck = {}
	p.target_id = spec.target_id
	p.spawn_sub = w.s
	p.pass_dir = spec.pass_dir
	p.data = spec.data.duplicate()
	p.arch = get_projectile_archetype(spec.archetype)
	list.append(p)
	return p


## ═══ RANGED DISPATCH HOOK ═══ - the single place a self's recorded 'ranged' event becomes world
## objects. Called by the sim at the event's launch tick, already gated on the self being able to
## act. With no archetype registered for the loadout's weapon this is a no-op that emits nothing.
func launch_from_self(w: ODSim, self_actor: SelfActor, ev: TapeEvent, pass_dir: int) -> void:
	var arch: ProjectileArchetype = get_projectile_archetype(w.loadout.ranged.archetype)
	if arch == null:
		return
	var n: int = arch.launch(w, self_actor, ev, pass_dir)
	if n > 0:
		# power = projectiles launched (a burst's pellet count).
		w.emit(
			SimEvent.make(0, SimEventType.FIRE, self_actor.pose.x, self_actor.pose.y)
			.with_tape(self_actor.index)
			.with_dir(ev.dir)
			.with_power(n)
			.with_detail(String(w.loadout.ranged.archetype))
		)


## Projectiles phase of a substep: every live projectile in spawn order (including ones spawned during
## this phase, like the prototype's loop over a growing array), then removal of the dead.
func step(w: ODSim) -> void:
	if list.is_empty():
		return
	var i: int = 0
	while i < list.size():
		var p: Projectile = list[i]
		i += 1
		if not p.alive:
			continue
		if p.arch != null:
			p.arch.step(w, p)
		else:
			fly_straight(w, p)
	var j: int = 0
	for k: int in list.size():
		if list[k].alive:
			list[j] = list[k]
			j += 1
	list.resize(j)


func snapshot() -> Array[ProjectileSnap]:
	var out: Array[ProjectileSnap] = []
	out.resize(list.size())
	for i: int in list.size():
		var p: Projectile = list[i]
		var snap := ProjectileSnap.new()
		snap.id = p.id
		snap.owner_tape = p.owner_tape
		snap.owner_enemy = p.owner_enemy
		snap.archetype = p.archetype
		snap.x = p.x
		snap.y = p.y
		snap.z = p.z
		snap.dir = p.dir
		snap.target_id = p.target_id
		out[i] = snap
	return out

# ───────────────────────────── default flight ─────────────────────────────


## Earliest t in [0, len] at which a point moving along (ux, uy) from (x0, y0) comes within R of
## (cx, cy); -1 for none.
static func _sweep_circle(x0: float, y0: float, ux: float, uy: float, max_t: float, cx: float, cy: float, rr: float) -> float:
	var fx: float = x0 - cx
	var fy: float = y0 - cy
	var c: float = fx * fx + fy * fy - rr * rr
	if c <= 0.0:
		return 0.0
	var b: float = fx * ux + fy * uy
	if b >= 0.0:
		return -1.0
	var disc: float = b * b - c
	if disc < 0.0:
		return -1.0
	var t: float = -b - sqrt(disc)
	return t if t >= 0.0 and t <= max_t else -1.0


func _add_contact(t: float, kind: int, index: int, ref: RefCounted) -> void:
	_c_t.append(t)
	_c_kind.append(kind)
	_c_index.append(index)
	_c_ref.append(ref)


## Contact a sorts after contact b (by t, then kind, then index).
func _contact_after(a: int, b: int) -> bool:
	if _c_t[a] != _c_t[b]:
		return _c_t[a] > _c_t[b]
	if _c_kind[a] != _c_kind[b]:
		return _c_kind[a] > _c_kind[b]
	return _c_index[a] > _c_index[b]


## Move a projectile straight along `p.dir` for one substep, resolving body contacts in the order
## they happen along the path and stopping at walls (unless passes_walls). Archetype hooks decide
## whether each contact stops it. `dist` defaults (NAN) to speed / SUB_HZ.
static func fly_straight(w: ODSim, p: Projectile, dist: float = NAN) -> void:
	w.projectiles._fly_straight(w, p, p.speed / OD.SUB_HZ if is_nan(dist) else dist)


func _fly_straight(w: ODSim, p: Projectile, dist: float) -> void:
	var arch: ProjectileArchetype = p.arch
	var remaining: float = p.range - p.travelled
	var step_len: float = minf(dist, maxf(0.0, remaining))
	var ux: float = cos(p.dir)
	var uy: float = sin(p.dir)
	var grid: ODGrid = w.grid

	var wall_t: float = INF
	var wall: ODGrid.RayHit = null
	if not p.passes_walls and step_len > 0.0:
		var hit: ODGrid.RayHit = grid.raycast(p.x, p.y, ux, uy, step_len, true, _ray)
		if hit.hit:
			wall_t = hit.dist
			wall = _copy_ray(hit, _wall)
	elif not p.passes_walls and grid.blocks_shot(int(floor(p.x)), int(floor(p.y))):
		wall_t = 0.0
		wall = _wall
		wall.hit = true
		wall.dist = 0.0
		wall.x = p.x
		wall.y = p.y
		wall.c = int(floor(p.x))
		wall.r = int(floor(p.y))
		wall.nx = 0.0
		wall.ny = 0.0

	_c_t.clear()
	_c_kind.clear()
	_c_index.clear()
	_c_ref.clear()
	var reach: float = minf(step_len, wall_t)
	if p.hits_selves:
		var sr: float = Tuning.BASE.actor_radius + p.radius
		for s: SelfActor in w.selves:
			if s.life == OD.LifeState.GHOST or (not p.struck.is_empty() and p.struck.has("self:%d" % s.index)):
				continue
			var t: float = _sweep_circle(p.x, p.y, ux, uy, reach, s.pose.x, s.pose.y, sr)
			if t >= 0.0:
				_add_contact(t, _C_SELF, s.index, s)
	if p.hits_enemies:
		var owner_enemy: String = p.owner_enemy if p.owner_tape < 0 else ""
		var enemies: Array[EnemyState] = w.enemies
		for i: int in enemies.size():
			var e: EnemyState = enemies[i]
			if not e.alive or (not owner_enemy.is_empty() and e.id == owner_enemy):
				continue
			if not p.struck.is_empty() and p.struck.has("enemy:%s" % e.id):
				continue
			var t: float = _sweep_circle(p.x, p.y, ux, uy, reach, e.x, e.y, e.stats.radius + p.radius)
			if t >= 0.0:
				_add_contact(t, _C_ENEMY, i, e)
	# Port addition: a self's projectile touching an inactive core strikes it.
	if p.owner_tape >= 0:
		var cores: Array[Mechanisms.CoreState] = w.mechs.cores
		for i: int in cores.size():
			var c: Mechanisms.CoreState = cores[i]
			if c.on or (not p.struck.is_empty() and p.struck.has("core:%s" % c.def.id)):
				continue
			var t: float = _sweep_circle(p.x, p.y, ux, uy, reach, c.def.x, c.def.y, Combat.CORE_RADIUS + p.radius)
			if t >= 0.0:
				_add_contact(t, _C_CORE, i, c)

	var n: int = _c_t.size()
	if n > 0:
		_c_order.resize(n)
		for i: int in n:
			_c_order[i] = i
		# Insertion sort by (t, kind, index): tiny, stable and allocation-free.
		for i: int in range(1, n):
			var x: int = _c_order[i]
			var j: int = i - 1
			while j >= 0 and _contact_after(_c_order[j], x):
				_c_order[j + 1] = _c_order[j]
				j -= 1
			_c_order[j + 1] = x
		for oi: int in n:
			var ci: int = _c_order[oi]
			var kind: int = _c_kind[ci]
			var verdict: StringName
			var hit_id: String = ""
			var hit_tape: int = -1
			if kind == _C_SELF:
				var hs: SelfActor = _c_ref[ci] as SelfActor
				hit_tape = hs.index
				verdict = arch.on_hit_self(w, p, hs) if arch != null else ProjectileArchetype.VERDICT_PASS
			elif kind == _C_ENEMY:
				var he: EnemyState = _c_ref[ci] as EnemyState
				hit_id = he.id
				verdict = arch.on_hit_enemy(w, p, he) if arch != null else default_hit_enemy(w, p, he)
			else:
				var hc: Mechanisms.CoreState = _c_ref[ci] as Mechanisms.CoreState
				hit_id = hc.def.id
				w.mechs.projectile_strike_core(w, p, hc)
				verdict = ProjectileArchetype.VERDICT_STOP
			if verdict == ProjectileArchetype.VERDICT_STOP:
				var ct: float = _c_t[ci]
				p.x += ux * ct
				p.y += uy * ct
				p.travelled += ct
				p.alive = false
				w.emit(
					SimEvent.make(0, SimEventType.PROJECTILE_HIT, p.x, p.y)
					.with_id(hit_id)
					.with_tape(hit_tape)
					.with_dir(p.dir)
					.with_detail(String(p.archetype))
				)
				return
	if wall != null and wall_t <= step_len:
		# Port addition: a self's projectile reaching an unbroken breakable strikes it first.
		w.mechs.projectile_strike_breakable(w, p, wall.c, wall.r)
		var wv: StringName = arch.on_hit_wall(w, p, wall) if arch != null else ProjectileArchetype.VERDICT_STOP
		if wv == ProjectileArchetype.VERDICT_STOP:
			p.x += ux * wall_t
			p.y += uy * wall_t
			p.travelled += wall_t
			p.alive = false
			w.emit(SimEvent.make(0, SimEventType.PROJECTILE_HIT, p.x, p.y).with_dir(p.dir).with_detail("%s:wall" % p.archetype))
			return
	p.x += ux * step_len
	p.y += uy * step_len
	p.travelled += step_len
	if p.travelled >= p.range - 1e-9:
		p.alive = false
		if arch != null:
			arch.on_expire(w, p)


static func _copy_ray(src: ODGrid.RayHit, dst: ODGrid.RayHit) -> ODGrid.RayHit:
	dst.hit = src.hit
	dst.dist = src.dist
	dst.x = src.x
	dst.y = src.y
	dst.c = src.c
	dst.r = src.r
	dst.nx = src.nx
	dst.ny = src.ny
	return dst


## Default enemy contact: deliver the projectile's momentum and stop unless it can pierce.
static func default_hit_enemy(w: ODSim, p: Projectile, e: EnemyState) -> StringName:
	p.struck["enemy:%s" % e.id] = true
	var src: StrikeSource = StrikeSource.of_tape(p.owner_tape) if p.owner_tape >= 0 else StrikeSource.of_enemy(p.owner_enemy)
	w.combat.strike_enemy(e, EnemyStrike.make(src, String(p.archetype), p.momentum, p.dir, e.x, e.y))
	if p.pierce_left > 0:
		p.pierce_left -= 1
		return ProjectileArchetype.VERDICT_PASS
	return ProjectileArchetype.VERDICT_STOP

# ───────────────────────────── enemy bolt ─────────────────────────────


## Fire a bolt from an enemy's rim along `dir` at the enemy's shot speed.
static func spawn_bolt(w: ODSim, e: EnemyState, dir: float) -> Projectile:
	var off: float = e.stats.radius + Tuning.ENEMY_SHOT_RADIUS + 0.01
	var spec := SpawnSpec.make(
		-1, e.id, RangedArchetype.BOLT, e.x + cos(dir) * off, e.y + sin(dir) * off, dir, e.stats.shot_speed, Tuning.ENEMY_SHOT_RADIUS, BOLT_RANGE
	)
	spec.momentum = 1.0
	spec.set_hits_selves(true)
	spec.hits_enemies = true
	return w.projectiles.spawn(w, spec)
