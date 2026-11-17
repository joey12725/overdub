extends ActorLayerBase
## The actor layer: everything alive on screen - the four selves (Moxie), enemies and projectiles,
## and the state visuals that must never be confused (recording ghost, playback ghost, desynced
## projection and recovery spark; UI-03). Port of prototype render/actors/index.ts.
##
## Per frame: interpolate frame.prev -> frame.snap by frame.alpha, update pooled views, step
## particles. Views are built at load_level (four selves, enemy / projectile pools prewarmed from the
## level) so the frame loop does not create nodes; a new enemy or projectile id only builds a view if
## its pool runs dry.

const ENEMY_TYPES: Array[StringName] = [EnemyType.GRUNT, EnemyType.STALKER, EnemyType.TURRET, EnemyType.SHIELDER, EnemyType.BRUTE, EnemyType.DRONE, EnemyType.BOSS]
const SHOT_KINDS: Array[StringName] = [RangedArchetype.MISSILE, RangedArchetype.PIERCE, RangedArchetype.PHASE, RangedArchetype.ARC, RangedArchetype.BURST, RangedArchetype.BOLT, RangedArchetype.SHOCK, RangedArchetype.DART]
## Default camera basis (orthographic isometric, yaw 45 deg, pitch 35 deg) when the view has none.
const DEFAULT_CAM_YAW: float = PI * 0.25
const DEFAULT_CAM_PITCH: float = -0.61086524

var mats: ActorMaterials = null
var selves: Array[SelfView] = []
var tape_colors: PackedColorArray = PackedColorArray()
var dust: ActorParticles = null
var glow: ActorParticles = null
var _root: Node3D = null
var _enemy_pools: Dictionary[StringName, ActorPool] = {}
var _shot_pools: Dictionary[StringName, ActorPool] = {}
var _enemy_pool_list: Array[ActorPool] = []
var _shot_pool_list: Array[ActorPool] = []
var _self_shared: SelfView.Shared = null
var _enemy_shared: EnemyView.Shared = null
var _shot_shared: ProjectileView.Shared = null
var _self_env: SelfView.Env = SelfView.Env.new()
var _enemy_env: EnemyView.Env = EnemyView.Env.new()
var _shot_env: ProjectileView.Env = ProjectileView.Env.new()
var _actor_interp: Array[ActorInterp.SelfFrame] = []
var _enemy_interp: ActorInterp.EnemyFrame = ActorInterp.EnemyFrame.new()
var _shot_interp: ActorInterp.ShotFrame = ActorInterp.ShotFrame.new()
var _keep_dying: Callable
var _pop_shot: Callable
var _time: float = 0.0
var _loaded: bool = false
## Combat feel (feel/, docs/COMBAT-FEEL.md): hit-hold, smears, impact frames, squash, knockback
## presentation. Fed the frame's sim events and snapshot once per frame, before bodies are posed.
var feel: CombatFeel = null
## What idle living selves do instead of idling: &"" (nothing), SelfView.FLAVOUR_COUNTIN (the
## count-in bounce: the game sets it while the session counts in) or SelfView.FLAVOUR_WIN (the win
## pose; also shown automatically once the objective is complete in the cinematic replay).
var flavour: StringName = &""


func _init() -> void:
	for i: int in OD.TAPE_COUNT:
		_actor_interp.append(ActorInterp.SelfFrame.new())
	_keep_dying = func(v: Node) -> bool:
		var ev := v as EnemyView
		ev.vanish(_enemy_env)
		return ev.dying()
	_pop_shot = func(v: Node) -> bool:
		(v as ProjectileView).pop()
		return false


func load_level(ctx: RenderCtx) -> void:
	dispose()
	_root = Node3D.new()
	_root.name = "Actors"
	add_child(_root)
	if mats == null:
		mats = ActorMaterials.new()
	mats.set_palette(ctx.palette, ctx.toon_ramp)
	var low := ctx.quality == WorldViewBase.QUALITY_LOW
	dust = ActorParticles.new()
	dust.name = "Dust"
	dust.setup(384 if low else 768, mats.particle_mix)
	_root.add_child(dust)
	glow = ActorParticles.new()
	glow.name = "Glow"
	glow.setup(384 if low else 768, mats.particle_add)
	_root.add_child(glow)
	# Cassette colours: the measured accessibility set in use (docs/ACCESSIBILITY.md section 2).
	tape_colors = ActorOptions.tape_colors()
	_enemy_env.tape_colors = tape_colors
	var loadout: ResolvedLoadout = ctx.loadout if ctx.loadout != null else ResolvedLoadout.new()
	var ink := ctx.palette.ink if ctx.palette != null else Color("#1f1412")
	var strip := ActorGeom.strip()

	# ── selves ──
	var ss := SelfView.Shared.new()
	ss.mats = mats
	ss.melee = loadout.melee
	ss.ranged = loadout.ranged
	ss.melee_id = loadout.loadout.get_slot(GearSlot.MELEE)
	ss.ranged_id = loadout.loadout.get_slot(GearSlot.RANGED)
	ss.helmet_id = loadout.loadout.get_slot(GearSlot.HELMET)
	for id: String in loadout.loadout.ids():
		if not id.is_empty():
			ss.item_ids.append(id)
	ss.looks = loadout.looks
	ss.ink = ink
	ss.dust = dust
	ss.glow = glow
	ss.ring = ActorGeom.ring(0.42, 0.5, 48)
	ss.ring_outer = ActorGeom.ring(0.4, 0.54, 48)
	ss.disc = ActorGeom.disc(0.42, 40)
	ss.badge = ActorGeom.disc(0.15, 20)
	ss.chevron = ActorGeom.chevron(0.22, 0.16, 0.06)
	ss.halo = ActorGeom.broken_ring(0.17, 0.016, 4)
	ss.bar = ActorGeom.quad(0.035, 0.12)
	ss.strip = strip
	ss.merge_ring = ActorGeom.ring(0.85, 1.0, 40)
	var flash := SphereMesh.new()
	flash.radius = 0.06
	flash.height = 0.12
	flash.radial_segments = 8
	flash.rings = 4
	ss.flash = flash
	# Floor rings in each cassette's own shape, with a wider ink backing (ACCESSIBILITY A1).
	for i: int in OD.TAPE_COUNT:
		ss.shape_rings.append(AccessKit.ring_mesh(i, 0.5, 0.085))
		ss.shape_rings_ink.append(AccessKit.ring_mesh(i, 0.535, 0.155))
	feel = CombatFeel.new()
	_root.add_child(feel)
	feel.setup(ctx.camera)
	# The actor layer draws flashes through its own body shader (clamped for accessibility) and its
	# own cheap dodge afterimages.
	feel.auto_flash = false
	feel.dodge_ghosts = false
	feel.drive_camera = ctx.camera != null
	feel.reduce_flashing = _reduce_flashing(ctx)
	if ctx.view != null:
		feel.shake_callable = ctx.shake
		feel.height_at = ctx.surface_height
		feel.solid_at = func(x: float, y: float) -> bool: return ctx.surface_height(x, y) > 0.45
	ss.feel = feel
	_self_shared = ss
	selves.clear()
	for i: int in OD.TAPE_COUNT:
		var v := SelfView.new()
		_root.add_child(v)
		v.setup(i, tape_colors[i], ss)
		_root.add_child(v.world)
		selves.append(v)

	# ── enemies ──
	var es := EnemyView.Shared.new()
	es.mats = mats
	es.ink = ink
	es.dust = dust
	es.glow = glow
	es.strip = strip
	es.pip = ActorGeom.quad(0.065, 0.065)
	es.shadow = ActorGeom.disc(0.32, 24)
	es.shock = ActorGeom.ring(0.85, 1.0, 40)
	es.ring = ActorGeom.ring(0.94, 1.0, 64)
	es.arrow = ActorGeom.arrow(0.2, 0.15)
	es.bar = ActorGeom.quad(1.0, 1.0)
	es.disc = ActorGeom.disc(1.0, 40)
	var dome := SphereMesh.new()
	dome.radius = 0.62
	dome.height = 1.24
	dome.radial_segments = 10
	dome.rings = 6
	es.dome = dome
	for t: StringName in ENEMY_TYPES:
		var sp := EnemySpecs.spec(t)
		if sp.shape == EnemySpecs.SHAPE_CONE:
			var inner := sp.radius * 0.6 if t == EnemyType.BOSS else 0.15
			es.telegraph[t] = ActorGeom.sector(inner, sp.reach, sp.arc, maxi(16, roundi(sp.arc * 12.0)), true)
	var boss := EnemySpecs.spec(EnemyType.BOSS)
	es.sweep = ActorGeom.sector(boss.radius, EnemySpecs.BOSS_SWEEP_RANGE, TAU, 72, true)
	es.recall = ActorGeom.disc(1.0, 40)
	var counts: Dictionary[StringName, int] = {}
	if ctx.level != null:
		for ent: EntityDef in ctx.level.entities:
			if ent is EnemyDef:
				var ed := ent as EnemyDef
				counts[ed.type] = counts.get(ed.type, 0) + 1
				es.base_facing[ed.id] = ed.facing
	_enemy_shared = es
	_enemy_pools.clear()
	_enemy_pool_list.clear()
	for t: StringName in ENEMY_TYPES:
		var pool := ActorPool.new(_make_enemy.bind(t), _release_view)
		pool.prewarm(counts.get(t, 0))
		_enemy_pools[t] = pool
		_enemy_pool_list.append(pool)

	# ── projectiles ──
	var ps := ProjectileView.Shared.new()
	ps.mats = mats
	ps.dust = dust
	ps.glow = glow
	ps.strip = strip
	var orb := SphereMesh.new()
	orb.radius = 1.0
	orb.height = 2.0
	orb.radial_segments = 10
	orb.rings = 6
	ps.orb = orb
	var body := CapsuleMesh.new()
	body.radius = 0.045
	body.height = 0.29
	body.radial_segments = 8
	body.rings = 2
	ps.missile_body = body
	var fin := BoxMesh.new()
	fin.size = Vector3(0.01, 0.07, 0.07)
	ps.fin = fin
	ps.ring = ActorGeom.ring(0.8, 1.0, 32)
	ps.disc = ActorGeom.disc(0.14, 16)
	var pellet := SphereMesh.new()
	pellet.radius = 1.0
	pellet.height = 2.0
	pellet.radial_segments = 5
	pellet.rings = 3
	ps.pellet = pellet
	var spike := BoxMesh.new()
	spike.size = Vector3.ONE
	ps.spike = spike
	_shot_shared = ps
	_shot_pools.clear()
	_shot_pool_list.clear()
	var any_enemy := not counts.is_empty()
	var has_dart := false
	for e: EntityDef in ctx.level.entities:
		if e.kind == EntityKind.DART:
			has_dart = true
	for k: StringName in SHOT_KINDS:
		var pool := ActorPool.new(_make_shot.bind(k), _release_view)
		var warm := 0
		if k == loadout.ranged.archetype:
			warm = maxi(4, loadout.ranged.count * 2)
		elif (k == RangedArchetype.BOLT or k == RangedArchetype.SHOCK) and any_enemy:
			warm = 4
		elif k == RangedArchetype.DART and has_dart:
			warm = 4
		pool.prewarm(warm)
		_shot_pools[k] = pool
		_shot_pool_list.append(pool)
	_loaded = true


func _make_enemy(t: StringName) -> Node:
	var v := EnemyView.new()
	_root.add_child(v)
	v.setup(t, _enemy_shared)
	v.hide_view()
	return v


func _make_shot(k: StringName) -> Node:
	var v := ProjectileView.new()
	_root.add_child(v)
	v.setup(k, _shot_shared)
	v.hide_view()
	return v


func _release_view(v: Node) -> void:
	if v is EnemyView:
		if feel != null:
			feel.untrack_enemy((v as EnemyView).id)
		(v as EnemyView).hide_view()
	elif v is ProjectileView:
		(v as ProjectileView).hide_view()


func update(frame: RenderFrame, ctx: RenderCtx) -> void:
	if not _loaded or frame == null or frame.snap == null:
		return
	var dt := clampf(frame.dt, 0.0, 0.1)
	_time += dt
	var snap := frame.snap
	var prev: FrameSnapshot = frame.prev if frame.prev != null else snap

	# Camera-derived helpers for billboards, the chroma split and the letter badge.
	var cam_basis := Basis.from_euler(Vector3(DEFAULT_CAM_PITCH, DEFAULT_CAM_YAW, 0.0), EULER_ORDER_YXZ)
	if ctx != null and ctx.camera != null:
		cam_basis = ctx.camera.global_transform.basis.orthonormalized()
	var fwd := -cam_basis.z
	var h := Vector2(fwd.x, fwd.z)
	h = h.normalized() if h.length() > 1e-5 else Vector2(0, -1)

	# Combat feel first: it decides how late each held body is drawn this frame.
	var reduce := _reduce_flashing(ctx)
	if feel != null:
		feel.reduce_flashing = reduce
		for i: int in mini(OD.TAPE_COUNT, selves.size()):
			var sv := selves[i]
			feel.track_self(i, sv.rig, sv.color, sv.tape_speed, sv.style, sv.weapon_len, sv.body_scale)
		feel.update(frame.events, snap, dt)
	_enemy_env.feel = feel
	_enemy_env.reduce_flashing = reduce
	_enemy_env.hits.clear()
	for ev: SimEvent in frame.events:
		if (ev.type == SimEventType.HIT or ev.type == SimEventType.PROJECTILE_HIT) and not ev.id.is_empty():
			_enemy_env.hits[ev.id] = true
		elif ev.type == SimEventType.ENEMY_TELEGRAPH and not ev.id.is_empty() and not ev.detail.is_empty():
			_enemy_env.boss_modes[ev.id] = StringName(ev.detail)

	# ── selves ──
	var se := _self_env
	se.dt = dt
	se.time = _time
	se.beat_pulse = frame.music.beat_pulse if frame.music != null else 0.0
	se.cam_basis = cam_basis
	se.cam_right = cam_basis.x.normalized()
	se.cam_fwd = h
	se.flourish = 1.0 if frame.mode == ViewMode.CINEMATIC else 0.0
	se.world_rate = frame.world_rate
	se.reduce_flashing = reduce
	se.high_contrast = ActorOptions.high_contrast
	se.flavour = flavour
	if flavour == &"" and frame.mode == ViewMode.CINEMATIC and snap.objective != null and snap.objective.complete:
		se.flavour = SelfView.FLAVOUR_WIN
	for i: int in OD.TAPE_COUNT:
		var view := selves[i]
		var cur := ActorInterp.find_actor(snap.actors, i, i)
		if cur == null:
			if view.shown:
				view.set_shown(false)
			_enemy_env.self_shown[i] = false
			continue
		var p := ActorInterp.find_actor(prev.actors, i, i)
		var a := ActorInterp.interp_actor(p, cur, frame.alpha, _actor_interp[i])
		se.is_live = cur.live or frame.active == i
		view.update_self(a, se)
		_enemy_env.self_shown[i] = true
		_enemy_env.self_pos[i] = view.pos

	# ── enemies ──
	var ee := _enemy_env
	ee.dt = dt
	ee.time = _time
	ee.cam_basis = cam_basis
	_shot_env.enemy_pos.clear()
	for pool: ActorPool in _enemy_pool_list:
		pool.begin()
	for i: int in snap.enemies.size():
		var cur := snap.enemies[i]
		var pool: ActorPool = _enemy_pools.get(cur.type)
		if pool == null:
			continue
		var view := pool.touch(cur.id) as EnemyView
		if pool.last_new:
			view.reset(cur.id)
		if feel != null and feel.enemy_fx(cur.id) == null:
			feel.track_enemy(cur.id, view.rig, view.spec.radius, view.spec.top)
		var p := ActorInterp.find_enemy(prev.enemies, cur.id, i)
		view.update_enemy(ActorInterp.interp_enemy(p, cur, frame.alpha, _enemy_interp), ee)
		if cur.alive:
			_shot_env.enemy_pos[cur.id] = Vector2(_enemy_interp.x, _enemy_interp.y)
		if cur.state != EnemyStateName.TELEGRAPH and cur.state != EnemyStateName.ATTACK:
			ee.boss_modes.erase(cur.id)
	for pool: ActorPool in _enemy_pool_list:
		pool.sweep(_keep_dying)

	# ── projectiles ──
	var pe := _shot_env
	pe.dt = dt
	pe.time = _time
	for pool: ActorPool in _shot_pool_list:
		pool.begin()
	for i: int in snap.projectiles.size():
		var cur := snap.projectiles[i]
		var pool: ActorPool = _shot_pools.get(cur.archetype)
		if pool == null:
			continue
		var view := pool.touch(cur.id) as ProjectileView
		if pool.last_new:
			view.reset(cur.id, owner_color(cur))
		var p := ActorInterp.find_projectile(prev.projectiles, cur.id, i)
		view.update_shot(ActorInterp.interp_projectile(p, cur, frame.alpha, _shot_interp), cur.target_id, pe)
	for pool: ActorPool in _shot_pool_list:
		pool.sweep(_pop_shot)

	dust.update_particles(dt)
	glow.update_particles(dt)


## A self's shots carry its cassette colour; enemy shots the danger orange.
func owner_color(p: ProjectileSnap) -> Color:
	if p.owner_tape >= 0 and p.owner_tape < tape_colors.size():
		return tape_colors[p.owner_tape]
	if p.archetype == RangedArchetype.DART:
		return ProjectileView.DART_COLOR
	return EnemySpecs.DANGER


func self_anchor(tape: int, frame: RenderFrame) -> Vector3:
	if tape >= 0 and tape < selves.size() and selves[tape].shown:
		return selves[tape].anchor()
	return super.self_anchor(tape, frame)


## "Reduce flashing" is on when either the render context says so (RenderCtx.reduce_flashing, set by
## the world view from the player's settings) or ActorOptions does.
func _reduce_flashing(ctx: RenderCtx) -> bool:
	return ActorOptions.reduce_flashing or (ctx != null and ctx.get(&"reduce_flashing") == true)


## Set what idle living selves do instead of idling (see `flavour`).
func set_flavour(f: StringName) -> void:
	flavour = f


## Views currently live in the pools (for tests / the screenshot tool).
func enemy_view(id: String) -> EnemyView:
	for pool: ActorPool in _enemy_pool_list:
		var v := pool.get_view(id)
		if v != null:
			return v as EnemyView
	return null


func pool_stats() -> Dictionary:
	var created := 0
	for pool: ActorPool in _enemy_pool_list:
		created += pool.created
	for pool: ActorPool in _shot_pool_list:
		created += pool.created
	return {"created": created}


func dispose() -> void:
	_loaded = false
	selves.clear()
	_enemy_pools.clear()
	_shot_pools.clear()
	_enemy_pool_list.clear()
	_shot_pool_list.clear()
	_enemy_env.boss_modes.clear()
	_enemy_env.feel = null
	if feel != null:
		feel.clear()
		feel = null
	if _self_shared != null:
		_self_shared.feel = null
	if _root != null:
		remove_child(_root)
		_root.queue_free()
		_root = null
	dust = null
	glow = null
