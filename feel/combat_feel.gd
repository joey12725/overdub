class_name CombatFeel
extends Node3D
## OVERDUB combat feel: everything that makes a hit LAND, as presentation only.
##
## It is fed the simulation's events and snapshots and the bodies the actor layer draws; it never
## changes gameplay timing. "Hit-stop" is a visual hold: a struck enemy and the attacker are DRAWN
## late for a few frames (FeelHold), while the sim and the music run on untouched.
##
## Use (docs/COMBAT-FEEL.md has the full integration steps):
##
##     var feel := CombatFeel.new()                 # add under RenderCtx.root (or any Node3D)
##     feel.setup(ctx.camera)
##     feel.shake_callable = ctx.shake              # optional: screen shake goes through the view
##     feel.solid_at = func(x, y): return grid.is_solid(x, y)   # optional: enables wall slams
##     feel.track_self(tape, self_node, cassette_colour, tape_speed, FeelRig.style_for(item_id), weapon_len)
##     feel.track_enemy(id, enemy_node, radius, height)
##     # every rendered frame, BEFORE posing bodies:
##     feel.update(frame.events, frame.snap, frame.dt)
##     # then, when posing:
##     var fx := feel.enemy_fx(id)          # FeelSubject: lag, pos, apply(base), flash
##     feel.update_swing(tape, clip_animation, shown_fraction, play_dir, heavy, base_transform)
##
## Scene convention (RenderCtx): sim (x, y) -> scene (X = x, Z = y), Y up; a sim direction `a`
## (radians) is the scene vector (cos a, 0, sin a).

## A hit was presented: momentum tier, scene position, scene direction (for audio / fx hooks).
signal impact(tier: int, at: Vector3, dir: Vector3)
## An enemy attack passed through a dodge's i-frames.
signal near_miss(tape: int, at: Vector3)
## A knocked-back enemy hit something solid.
signal wall_slam(id: String, at: Vector3, tier: int)

## Callable(magnitude: float): screen shake (RenderCtx.shake). Unset: only the signal-free default.
var shake_callable: Callable = Callable()
## Callable(x: float, y: float) -> bool in sim coordinates: true where geometry is solid.
var solid_at: Callable = Callable()
## Callable(x: float, y: float) -> float: floor height at a sim position (RenderCtx.surface_height).
var height_at: Callable = Callable()
## Drive the camera's h_offset / v_offset with the directional punch (never its transform).
var drive_camera: bool = true
## Put the flash overlay on struck bodies' meshes (GeometryInstance3D.material_overlay).
var auto_flash: bool = true
## Master switches (accessibility / quality).
var enable_shake: bool = true
var enable_ghosts: bool = true
## Spawn afterimages while a self dodges. The actor layer draws its own dodge afterimages (cheap
## skinned copies) and turns this off; near-miss and fast-tape ghosts are unaffected.
var dodge_ghosts: bool = true
## "Reduce flashing" (docs/ACCESSIBILITY.md 6.2): no inverted impact frame, no white body flash, no
## camera punch, bursts capped at a small solid-tier size, no white near-miss ghost. Holds, squash,
## smears, dust and decals stay: they carry the hit without a luminance flash.
var reduce_flashing: bool = false:
	set(v):
		reduce_flashing = v
		bursts.max_size = REDUCED_BURST_SIZE if v else INF
		bursts.max_tier = FeelTune.TIER_SOLID if v else FeelTune.TIER_CRUSH
const REDUCED_BURST_SIZE: float = 1.0

var camera: Camera3D = null
var bursts: FeelBursts = null
var ghosts: FeelGhosts = null

var _selves: Dictionary[int, FeelSubject] = {}
var _enemies: Dictionary[String, FeelSubject] = {}
var _smears: Dictionary[int, FeelSmear] = {}
var _punch: Vector3 = Vector3.ZERO
var _punch_v: Vector3 = Vector3.ZERO
var _flash_shader: Shader = null
## Shake requested this frame (the largest), for callers that poll instead of using shake_callable.
var frame_shake: float = 0.0


func _init() -> void:
	name = "CombatFeel"
	bursts = FeelBursts.new()
	bursts.name = "Bursts"
	add_child(bursts)
	ghosts = FeelGhosts.new()
	ghosts.name = "Ghosts"
	add_child(ghosts)
	_flash_shader = load("res://feel/shaders/flash.gdshader")


func setup(p_camera: Camera3D) -> void:
	camera = p_camera


# ───────────────────────────── tracking ─────────────────────────────

## Register (or update) a self. `node`: the Node3D the actor layer draws for it (its meshes are used
## for flashes and afterimages). `weapon_len`: grip-to-tip length of the equipped weapon in scene
## units (use the melee reach for the whip: its lash reaches that far at the crack).
func track_self(tape: int, node: Node3D, tint: Color, speed: float, style: String = "blade", weapon_len: float = 0.8, body_scale: float = 1.0) -> FeelSubject:
	var s: FeelSubject = _selves.get(tape)
	if s == null:
		s = FeelSubject.new()
		_selves[tape] = s
		var sm := FeelSmear.new()
		sm.name = "Smear%d" % tape
		add_child(sm)
		_smears[tape] = sm
	if s.node != node:
		_drop_flash(s)
	s.node = node
	s.tint = tint
	s.speed = speed
	s.style = style
	s.weapon_len = weapon_len
	s.body_scale = body_scale
	s.height = 1.6 * body_scale
	return s


func track_enemy(id: String, node: Node3D, radius: float = 0.4, height: float = 1.2) -> FeelSubject:
	var s: FeelSubject = _enemies.get(id)
	if s == null:
		s = FeelSubject.new()
		_enemies[id] = s
	if s.node != node:
		_drop_flash(s)
	s.node = node
	s.radius = radius
	s.height = height
	return s


func untrack_enemy(id: String) -> void:
	var s: FeelSubject = _enemies.get(id)
	if s != null:
		_drop_flash(s)
		_enemies.erase(id)


## Forget every body and effect (level change).
func clear() -> void:
	for s: FeelSubject in _selves.values():
		_drop_flash(s)
	for s: FeelSubject in _enemies.values():
		_drop_flash(s)
	for sm: FeelSmear in _smears.values():
		sm.queue_free()
	_selves.clear()
	_enemies.clear()
	_smears.clear()
	bursts.clear()
	ghosts.clear()
	_punch = Vector3.ZERO
	_punch_v = Vector3.ZERO
	if camera != null and drive_camera:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


## Flash a caller that draws its own flash (auto_flash off) should show for a body: x = amount 0..1,
## y = 1 on the inverted "negative" frame. Zero under reduce_flashing.
func flash_of(s: FeelSubject) -> Vector2:
	if s == null or reduce_flashing:
		return Vector2.ZERO
	return Vector2(s.flash, 1.0 if s.invert else 0.0)


## The presentation state of a self / an enemy (null when not tracked).
func self_fx(tape: int) -> FeelSubject:
	return _selves.get(tape)


func enemy_fx(id: String) -> FeelSubject:
	return _enemies.get(id)


# ───────────────────────────── per frame ─────────────────────────────

## Advance the feel layer by one rendered frame: `events` are the sim events of this frame, `snap`
## the snapshot being drawn, `dt` the frame's WALL time. Call once per frame, before posing bodies.
func update(events: Array[SimEvent], snap: FrameSnapshot, dt: float) -> void:
	frame_shake = 0.0
	# 1. Positions into the subjects' histories (and hold / spring / flash advance).
	var seen_enemy: Dictionary[String, EnemySnap] = {}
	if snap != null:
		for e: EnemySnap in snap.enemies:
			seen_enemy[e.id] = e
		for a: ActorSnap in snap.actors:
			var s: FeelSubject = _selves.get(a.tape)
			if s != null:
				s.advance(dt, Vector2(a.x, a.y), true)
				_dodge_ghosts(s, a, dt)
	for id: String in _enemies:
		var s: FeelSubject = _enemies[id]
		var es: EnemySnap = seen_enemy.get(id)
		if es != null:
			s.advance(dt, Vector2(es.x, es.y), true)
			_slide(id, s, dt)
		else:
			s.advance(dt, Vector2.ZERO, false)
	if snap == null:
		for s: FeelSubject in _selves.values():
			s.advance(dt, Vector2.ZERO, false)
	# 2. Events.
	_events(events, snap)
	# 3. Flash overlays, pooled effects, camera punch.
	for s: FeelSubject in _selves.values():
		_apply_flash(s)
	for s: FeelSubject in _enemies.values():
		_apply_flash(s)
	bursts.advance(dt)
	ghosts.advance(dt)
	_camera(dt)
	if frame_shake > 0.0 and enable_shake and shake_callable.is_valid():
		shake_callable.call(frame_shake)


## Draw the weapon smear of a self for this frame. `anim` is the library clip being shown, `frac` the
## clip fraction actually DRAWN (after subtracting the hold lag), `play_dir` +1 / -1 (reversed tape),
## `base` the scene transform of the body (feet at the origin, +Z = facing). Call every frame the self
## is in a melee state; call hide_swing() otherwise.
func update_swing(tape: int, anim: Animation, frac: float, play_dir: int, heavy: bool, base: Transform3D) -> void:
	var s: FeelSubject = _selves.get(tape)
	var sm: FeelSmear = _smears.get(tape)
	if s == null or sm == null:
		return
	sm.build(anim, frac, play_dir, heavy, s.style, s.speed, base, s.body_scale, s.weapon_len, s.tint)
	# Fast tapes: whole-body afterimages spaced through the hit window (multi-ghosting).
	var n: int = FeelTune.SPEED_BODY_GHOSTS[FeelTune.speed_index(s.speed)]
	if n > 0 and enable_ghosts and s.last_frac >= 0.0 and s.node != null:
		for k: int in n:
			var mark := 0.38 + 0.22 * (float(k) + 0.5) / float(n)
			if (s.last_frac < mark and frac >= mark) or (s.last_frac > mark and frac <= mark):
				ghosts.spawn(s.node, s.tint, FeelTune.GHOST_LIFE * 0.7, 0.45)
	s.last_frac = frac


func hide_swing(tape: int) -> void:
	var sm: FeelSmear = _smears.get(tape)
	if sm != null:
		sm.hide_smear()
	var s: FeelSubject = _selves.get(tape)
	if s != null:
		s.last_frac = -1.0


## Current camera punch offset in scene space (for views that prefer to add it themselves).
func camera_offset() -> Vector3:
	return _punch


# ───────────────────────────── events ─────────────────────────────

func _events(events: Array[SimEvent], snap: FrameSnapshot) -> void:
	if events.is_empty():
		return
	# What else happened to each enemy in this batch decides how its hit is drawn.
	var clanged: Dictionary[String, bool] = {}
	var killed: Dictionary[String, bool] = {}
	var hit_ids: Dictionary[String, bool] = {}
	for ev: SimEvent in events:
		if ev.type == SimEventType.CLANG:
			clanged[ev.id] = true
		elif ev.type == SimEventType.KILL:
			killed[ev.id] = true
		elif ev.type == SimEventType.HIT:
			hit_ids[ev.id] = true
	for ev: SimEvent in events:
		match ev.type:
			SimEventType.HIT:
				_hit(ev, clanged.has(ev.id), killed.has(ev.id))
			SimEventType.CLANG:
				if not hit_ids.has(ev.id):
					_hit(ev, true, false)      # blocked outright (shield up, breakable too tough)
			SimEventType.KILL:
				if not hit_ids.has(ev.id):
					_burst_at(FeelBursts.KIND_KILL, ev.x, ev.y, 0.6, FeelTune.TIER_SOLID, _dir3(ev), Color("#ffd23f"))
					_shake(FeelTune.TIER_SOLID, 1.0)
			SimEventType.BREAK:
				_burst_at(FeelBursts.KIND_KILL, ev.x, ev.y, 0.6, FeelTune.TIER_HEAVY, _dir3(ev), Color("#f1e3c8"))
				_shake(FeelTune.TIER_HEAVY, 1.0)
			SimEventType.PROJECTILE_HIT:
				var t := FeelTune.tier_of(ev.power if ev.has_power else 1.0)
				var es: FeelSubject = _enemies.get(ev.id)
				if es != null:
					es.struck(t, _dir3(ev), 1.0)
				_burst_at(FeelBursts.KIND_HIT, ev.x, ev.y, 0.6, t, _dir3(ev), Color("#ffd23f"))
				_shake(maxi(0, t - 1), 1.0)
			SimEventType.SELF_DEATH:
				var ss: FeelSubject = _selves.get(ev.tape)
				if ss != null:
					ss.struck(FeelTune.TIER_HEAVY, _dir3(ev), 1.0)
					_burst_at(FeelBursts.KIND_HIT, ev.x, ev.y, 0.9, FeelTune.TIER_HEAVY, _dir3(ev), ss.tint)
				_shake(FeelTune.TIER_HEAVY, 1.0)
			SimEventType.ENEMY_ATTACK:
				_near_miss(ev, snap)


func _hit(ev: SimEvent, clang: bool, kill: bool) -> void:
	var attacker: FeelSubject = _selves.get(ev.tape)
	var speed := attacker.speed if attacker != null else 1.0
	var tier := FeelTune.hit_tier(ev.power if ev.has_power else 1.0, clang)
	var dir := _dir3(ev)
	var victim: FeelSubject = _enemies.get(ev.id)
	var tint := attacker.tint if attacker != null else Color("#ffd23f")
	var h := 0.6
	if victim != null:
		# A clang does not flash white: the body barely registers it.
		victim.struck(tier, dir, speed, not clang)
		victim.slide_left = 0.9
		victim.slide_dist = 0.0
		victim.slide_dust = 0.0
		victim.slide_from = Vector2(ev.x, ev.y)
		h = victim.height * 0.55
	if attacker != null:
		attacker.connected(tier, speed)
	var kind := FeelBursts.KIND_CLANG if clang else (FeelBursts.KIND_KILL if kill else FeelBursts.KIND_HIT)
	var size_tier := mini(4, tier + 1) if kill else tier
	_burst_at(kind, ev.x, ev.y, h, size_tier, dir, tint)
	_shake(tier, speed)
	var p := 0.0 if reduce_flashing else FeelTune.punch(tier, speed)
	_punch_v += dir * p * 38.0
	impact.emit(tier, _scene(ev.x, ev.y, h), dir)


func _near_miss(ev: SimEvent, snap: FrameSnapshot) -> void:
	if snap == null:
		return
	for a: ActorSnap in snap.actors:
		if not a.iframes:
			continue
		var d := Vector2(a.x - ev.x, a.y - ev.y)
		if d.length() > FeelTune.NEAR_MISS_RADIUS:
			continue
		var s: FeelSubject = _selves.get(a.tape)
		var tint := s.tint if s != null else Color("#7de3ff")
		var along := Vector3(a.vx, 0.0, a.vy)
		if along.length_squared() < 1e-4:
			along = Vector3(cos(a.facing), 0.0, sin(a.facing))
		var at := _scene(a.x, a.y, 0.85)
		bursts.burst(FeelBursts.KIND_NEAR_MISS, at, 2.2, 0.28, 2, _screen_angle(along), tint, 6)
		if s != null:
			# A two-frame held pose on the dodger: the "it missed" beat.
			s.hold.start(0.035, 0.07)
			if enable_ghosts and s.node != null:
				ghosts.spawn(s.node, tint if reduce_flashing else Color.WHITE, 0.2, 0.35 if reduce_flashing else 0.7)
		near_miss.emit(a.tape, at)


func _dodge_ghosts(s: FeelSubject, a: ActorSnap, dt: float) -> void:
	if a.anim != AnimState.DODGE or not enable_ghosts or not dodge_ghosts or s.node == null:
		s.ghost_timer = 0.0
		return
	s.ghost_timer -= dt
	if s.ghost_timer <= 0.0:
		s.ghost_timer = FeelTune.DODGE_GHOST_EVERY
		ghosts.spawn(s.node, s.tint)


## Knockback presentation of an enemy: dust while it slides, then a landing or a wall slam.
func _slide(id: String, s: FeelSubject, dt: float) -> void:
	var p := s.pos
	if not s.has_prev:
		s.prev_pos = p
		s.has_prev = true
		return
	var step := p - s.prev_pos
	s.prev_pos = p
	if s.slide_left <= 0.0 or dt <= 0.0:
		return
	s.slide_left -= dt
	var v := step.length() / dt
	var dir2 := Vector2(s.hit_dir.x, s.hit_dir.z)
	if v > FeelTune.SLIDE_DUST_SPEED and step.dot(dir2) > 0.0:
		s.slide_dist += step.length()
		s.slide_dust += step.length() * FeelTune.DUST_PER_TILE[s.tier]
		while s.slide_dust >= 1.0:
			s.slide_dust -= 1.0
			var back := p - dir2 * s.radius * 0.6
			bursts.burst(FeelBursts.KIND_DUST, _scene(back.x, back.y, 0.12), 0.5 + 0.12 * float(s.tier), 0.42, s.tier, 0.0, Color("#d9cdb8"))
		s.slide_speed = v
		return
	if s.frozen or s.lag > 0.0:
		return        # still held at the contact frame: the slide has not been drawn yet
	if s.slide_dist > 0.25:
		# The slide just ended. Fast into something solid = slam; otherwise a skidding stop.
		var ahead := p + dir2 * (s.radius + 0.35)
		var slam := s.slide_speed > FeelTune.SLAM_SPEED and solid_at.is_valid() and bool(solid_at.call(ahead.x, ahead.y))
		var mid := (s.slide_from + p) * 0.5
		var along := Vector3(dir2.x, 0.0, dir2.y)
		var skid := Transform3D(Basis(along * maxf(0.3, s.slide_dist), along.cross(Vector3.UP).normalized() * (s.radius * 1.4) * -1.0, Vector3.UP), _scene(mid.x, mid.y, 0.025))
		bursts.decal(FeelBursts.DECAL_SKID, skid, 1.6)
		if slam:
			# Find the wall face: march out from the body until the probe turns solid, then sit the
			# crack just in front of it (inside the wall it would be hidden).
			var reach_d := s.radius + 0.35
			var d := 0.0
			while d < reach_d:
				var probe := p + dir2 * d
				if bool(solid_at.call(probe.x, probe.y)):
					break
				d += 0.04
			var wall := p + dir2 * maxf(0.0, d - 0.05)
			var at := _scene(wall.x, wall.y, s.height * 0.55)
			# The crack lies on the wall face: a vertical plane across the hit direction.
			var sz := 0.9 + 0.3 * float(s.tier)
			var crack := Transform3D(Basis(along.cross(Vector3.UP).normalized() * sz, Vector3.UP * sz, -along), at)
			bursts.decal(FeelBursts.DECAL_CRACK, crack, 2.6, float(s.tier))
			bursts.burst(FeelBursts.KIND_HIT, at, FeelTune.BURST_SIZE[s.tier] * 0.8, 0.2, s.tier, _screen_angle(-along), Color("#f1e3c8"), 9)
			for k: int in 3:
				bursts.burst(FeelBursts.KIND_DUST, at + Vector3(0, -0.2 + 0.25 * k, 0) - along * 0.1, 0.55, 0.5, s.tier, 0.0, Color("#d9cdb8"))
			s.struck(maxi(1, s.tier - 1), along, s.speed, false)
			_shake(mini(4, s.tier + 1), 1.0)
			if not reduce_flashing:
				_punch_v += along * FeelTune.PUNCH[s.tier] * 30.0
			wall_slam.emit(id, at, s.tier)
		else:
			s.landed(0.10 + 0.05 * float(s.tier))
			bursts.burst(FeelBursts.KIND_DUST, _scene(p.x + dir2.x * s.radius, p.y + dir2.y * s.radius, 0.1), 0.6, 0.4, s.tier, 0.0, Color("#d9cdb8"))
	s.slide_left = 0.0
	s.slide_dist = 0.0


# ───────────────────────────── helpers ─────────────────────────────

func _dir3(ev: SimEvent) -> Vector3:
	if ev.has_dir:
		return Vector3(cos(ev.dir), 0.0, sin(ev.dir))
	return Vector3(0, 0, 1)


func _scene(x: float, y: float, up: float) -> Vector3:
	var floor_y := float(height_at.call(x, y)) if height_at.is_valid() else 0.0
	return Vector3(x, floor_y + up, y)


## Direction of a scene vector on screen, radians (0 = screen right, counter-clockwise).
func _screen_angle(dir: Vector3) -> float:
	if camera == null:
		return atan2(-dir.z, dir.x)
	var v := camera.global_transform.basis.inverse() * dir
	return atan2(v.y, v.x)


func _burst_at(kind: int, x: float, y: float, up: float, tier: int, dir: Vector3, tint: Color) -> void:
	bursts.burst(kind, _scene(x, y, up), FeelTune.BURST_SIZE[tier], FeelTune.BURST_LIFE[tier], tier, _screen_angle(dir), tint, FeelTune.BURST_LINES[tier])


func _shake(tier: int, speed: float) -> void:
	frame_shake = maxf(frame_shake, FeelTune.shake(tier, speed))


func _camera(dt: float) -> void:
	# A critically-damped-ish spring: the camera lurches along the hit and returns.
	var left := minf(dt, 0.1)
	while left > 0.0:
		var h := minf(left, 1.0 / 240.0)
		_punch_v += (-_punch * 420.0 - _punch_v * 30.0) * h
		_punch += _punch_v * h
		left -= h
	if camera != null and drive_camera:
		var b := camera.global_transform.basis
		camera.h_offset = _punch.dot(b.x)
		camera.v_offset = _punch.dot(b.y)


func _apply_flash(s: FeelSubject) -> void:
	if not auto_flash or s.node == null or not is_instance_valid(s.node):
		return
	if s.flash > 0.0 and not reduce_flashing:
		if s.flash_material == null:
			s.flash_material = ShaderMaterial.new()
			s.flash_material.shader = _flash_shader
		if not s.flash_on:
			s.flash_meshes.clear()
			for c: Node in s.node.find_children("*", "MeshInstance3D", true, false):
				var mi := c as MeshInstance3D
				if mi != null and mi.material_overlay == null:
					mi.material_overlay = s.flash_material
					s.flash_meshes.append(mi)
			s.flash_on = true
		s.flash_material.set_shader_parameter(&"amount", s.flash)
		s.flash_material.set_shader_parameter(&"invert", 1.0 if s.invert else 0.0)
	elif s.flash_on:
		_drop_flash(s)


func _drop_flash(s: FeelSubject) -> void:
	for mi: MeshInstance3D in s.flash_meshes:
		if is_instance_valid(mi) and mi.material_overlay == s.flash_material:
			mi.material_overlay = null
	s.flash_meshes.clear()
	s.flash_on = false
