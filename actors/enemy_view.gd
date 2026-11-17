class_name EnemyView
extends Node3D
## One enemy on screen (prototype enemyView.ts). Readability contract (AI-04, UI-03): every enemy
## shows where it faces / aims, a TELEGRAPH decal of its real hit volume that fills with state_t
## before the attack lands, a stagger wobble, a hit flash, its current target (a dashed line and a
## pip in the targeted self's cassette colour), hit-point pips for multi-hit types, shield state,
## a death burst, and for the boss its phase (armour falls away) and a distinct treatment when it
## acts on memory (BOSS-02): the optic, telegraph, bar and a rewinding tape ribbon take the colour of
## the remembered cassette, and the strike zone is marked at the remembered place.
##
## The model comes from assets/models/enemies/<type>.glb (clips idle, move, telegraph, attack,
## stagger, death; `aim` bone on turret and drone; `Shield` / `Armor_1..3` objects), or a stand-in.

const MODEL_DIR: String = "res://assets/models/enemies/"
const MAX_PIPS: int = 8
const DEATH_SECONDS: float = 0.6
const FLASH_SECONDS: float = 0.14
const BLEND_SECONDS: float = 0.1
const WALK_STRIDE: float = 0.9
const SHIELD_COLOR: Color = Color("#58f0dc")
const BRASS: Color = Color("#d2a136")
const STONE: Color = Color("#a89d8b")


class Shared:
	extends RefCounted
	var mats: ActorMaterials = null
	var ink: Color = Color("#1f1412")
	var dust: ActorParticles = null
	var glow: ActorParticles = null
	var strip: ArrayMesh = null
	var pip: ArrayMesh = null
	var shadow: ArrayMesh = null
	var shock: ArrayMesh = null
	var ring: ArrayMesh = null
	var arrow: ArrayMesh = null
	var bar: ArrayMesh = null
	var dome: SphereMesh = null
	var disc: ArrayMesh = null
	## Telegraph sector per enemy type (cones and circles).
	var telegraph: Dictionary[StringName, ArrayMesh] = {}
	## Boss extras: sweep ring sector, memory ring.
	var sweep: ArrayMesh = null
	var recall: ArrayMesh = null
	## Base facing per enemy id (EnemyDef.facing): a turret's plinth stays put while it aims.
	var base_facing: Dictionary[String, float] = {}


class Env:
	extends RefCounted
	var dt: float = 0.0
	var time: float = 0.0
	var cam_basis: Basis = Basis.IDENTITY
	## Per tape: is the self on screen, where (sim), its cassette colour.
	var self_shown: Array[bool] = [false, false, false, false]
	var self_pos: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var tape_colors: PackedColorArray = PackedColorArray()
	## Enemy ids hit this frame (from 'hit' / 'projectileHit' events).
	var hits: Dictionary[String, bool] = {}
	## Boss telegraph mode by enemy id (from 'enemyTelegraph' event details).
	var boss_modes: Dictionary[String, StringName] = {}
	## Combat feel (null: the plain hit flash only) and the "reduce flashing" option.
	var feel: CombatFeel = null
	var reduce_flashing: bool = false


var type: StringName = &""
var id: String = ""
var spec: EnemySpecs.Spec
var rig: ActorRig
var _S: Shared
var _body: Node3D
var _sampler: ActorClipSampler
var _pose: ActorClipSampler.Pose
var _target: ActorClipSampler.Pose
var _from: ActorClipSampler.Pose
var _tmp: ActorClipSampler.Pose
var _aim_bone: int = -1
var _aim_axis_yaw: Vector3 = Vector3.UP
var _aim_axis_pitch: Vector3 = Vector3.RIGHT
var _shield_mesh: MeshInstance3D = null
var _armor: Array[MeshInstance3D] = []
var _reels: PackedInt32Array = PackedInt32Array()

var _tele: MeshInstance3D = null
var _aim: MeshInstance3D
var _volley: Array[MeshInstance3D] = []
var _sweep: MeshInstance3D = null
var _recall: MeshInstance3D = null
var _recall_line: MeshInstance3D = null
var _ribbon: MeshInstance3D = null
var _target_line: MeshInstance3D
var _arrow: MeshInstance3D
var _shadow: MeshInstance3D = null
var _marker: Node3D
var _target_pip: MeshInstance3D
var _pips: Array[MeshInstance3D] = []
var _bar_bg: MeshInstance3D = null
var _bar_fill: MeshInstance3D = null
var _shock: MeshInstance3D
var _dome: MeshInstance3D = null

var _last_state: StringName = &""
var _blend_t: float = 1.0
var _walk: float = 0.0
var _moving: float = 0.0
var _prev_x: float = 0.0
var _prev_y: float = 0.0
var _last_hp: int = 0
var _flash: float = 0.0
var _time: float = 0.0
var _death_t: float = -1.0
var _was_alive: bool = false
var _initialized: bool = false
var _last_shield: bool = false
var _shield_break_t: float = 1.0
var _recall_k: float = 0.0
var _last_phase: int = -1
var _seed: float = 0.0
var _x: float = 0.0
var _y: float = 0.0
var _base_yaw: float = 0.0
## Stagger clip position frozen while a hit is held.
var _held_t: float = 0.0
var _was_frozen: bool = false
var _ink_hull: Color = Color("#1f1412")


func setup(p_type: StringName, S: Shared) -> void:
	type = p_type
	_S = S
	spec = EnemySpecs.spec(type)
	name = "Enemy_" + String(type)
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	rig = ActorRig.new()
	rig.name = "Model"
	rig.setup(MODEL_DIR + String(type) + ".glb", EnemyStandin.instance.bind(type))
	_body.add_child(rig)
	_sampler = rig.sampler
	var n := _sampler.bone_count
	_pose = ActorClipSampler.Pose.new(n)
	_target = ActorClipSampler.Pose.new(n)
	_from = ActorClipSampler.Pose.new(n)
	_tmp = ActorClipSampler.Pose.new(n)
	_pose.copy_from(_sampler.rest)
	var accents: Array[StringName] = []
	for mi: MeshInstance3D in rig.meshes:
		if mi.mesh == null:
			continue
		for i: int in mi.mesh.get_surface_count():
			var mn := String(ActorRig.surface_material_name(mi, i))
			if mn.ends_with("_glow") and (mn.contains("eye") or mn.contains("optic") or mn.contains("lens")):
				accents.append(StringName(mn))
	var no_tints: Dictionary[StringName, Color] = {}
	rig.apply_materials(S.mats, no_tints, accents)
	_ink_hull = S.ink
	rig.set_param(&"outline_color", Color(S.ink, 1.0))
	rig.set_param(&"outline_width", clampf(0.012 + spec.radius * 0.012, 0.012, 0.024))
	rig.set_param(&"xray_color", Color(EnemySpecs.WARNING, 0.7))
	rig.set_param(&"rim_amt", 0.08)
	if rig.skeleton != null:
		_aim_bone = rig.skeleton.find_bone("aim")
		if _aim_bone >= 0:
			var parent := rig.skeleton.get_bone_parent(_aim_bone)
			var pb := rig.skeleton.get_bone_global_rest(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
			_aim_axis_yaw = (pb.inverse() * Vector3.UP).normalized()
			_aim_axis_pitch = (pb.inverse() * Vector3.RIGHT).normalized()
		for bn: String in ["reel.L", "reel.R"]:
			var bi := rig.skeleton.find_bone(bn)
			if bi >= 0:
				_reels.append(bi)
	_shield_mesh = rig.find_mesh("Shield")
	for i: int in 3:
		var am := rig.find_mesh("Armor_%d" % (i + 1))
		if am != null:
			_armor.append(am)
	_build_overlays(S)


func _flat(mesh: Mesh, mat: Material, parent: Node3D, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter(&"color", c)
	parent.add_child(mi)
	return mi


func _build_overlays(S: Shared) -> void:
	var m := S.mats
	var danger := EnemySpecs.DANGER
	# Telegraph decal (rotates with facing); aimed types use the world-space aim line instead.
	var tg: ArrayMesh = S.telegraph.get(type)
	if tg != null:
		_tele = _flat(tg, m.flat_mix, _body, Color(danger, 0.0))
		_tele.position.y = 0.022
		_tele.set_instance_shader_parameter(&"edge", 0.0 if spec.arc >= TAU - 0.01 else 1.2)
		_tele.set_instance_shader_parameter(&"back", 0.22)
		_tele.visible = false
	_aim = _flat(S.strip, m.flat_mix, self, Color(danger, 0.3))
	_aim.top_level = true
	_aim.set_instance_shader_parameter(&"edge", 0.6)
	_aim.visible = false
	_target_line = _flat(S.strip, m.flat_mix, self, Color(1, 1, 1, 0.35))
	_target_line.top_level = true
	_target_line.set_instance_shader_parameter(&"dash", 0.12)
	_target_line.visible = false
	# Facing arrow on the floor in front of the body.
	_arrow = _flat(S.arrow, m.flat_mix, _body, Color(danger, 0.55))
	_arrow.position = Vector3(0, 0.018, spec.radius + 0.1)
	if spec.hover > 0.0:
		_shadow = _flat(S.shadow, m.flat_mix, self, Color(0, 0, 0, 0.3))
		_shadow.position.y = 0.015
	# Billboarded marker above the head: target pip, hp pips, boss bar.
	_marker = Node3D.new()
	_marker.name = "Marker"
	_marker.position.y = spec.top + 0.14
	add_child(_marker)
	_target_pip = _flat(S.pip, m.flat_overlay, _marker, Color.WHITE)
	_target_pip.position.y = 0.14
	_target_pip.rotation.z = PI / 4.0
	_target_pip.scale = Vector3(1.5, 1.5, 1.0)
	for i: int in MAX_PIPS:
		var p := _flat(S.pip, m.flat_overlay, _marker, Color("#fff1d6"))
		p.visible = false
		_pips.append(p)
	if type == EnemyType.BOSS:
		_bar_bg = _flat(S.bar, m.flat_overlay, _marker, Color(Color("#1b1720"), 0.85))
		_bar_bg.scale = Vector3(1.6, 0.1, 1.0)
		_bar_fill = _flat(S.bar, m.flat_overlay, _marker, Color(danger, 1.0))
		_bar_fill.sorting_offset = 0.1
		for i: int in EnemySpecs.BOSS_VOLLEY_COUNT:
			var v := _flat(S.strip, m.flat_mix, self, Color(danger, 0.0))
			v.top_level = true
			v.set_instance_shader_parameter(&"edge", 0.6)
			v.visible = false
			_volley.append(v)
		_sweep = _flat(S.sweep, m.flat_mix, self, Color(danger, 0.0))
		_sweep.position.y = 0.024
		_sweep.set_instance_shader_parameter(&"back", 0.2)
		_sweep.visible = false
		_recall = _flat(S.recall, m.flat_mix, self, Color(danger, 0.0))
		_recall.top_level = true
		_recall.set_instance_shader_parameter(&"back", 0.25)
		_recall.visible = false
		_recall_line = _flat(S.strip, m.flat_overlay, self, Color(1, 1, 1, 0.0))
		_recall_line.top_level = true
		_recall_line.set_instance_shader_parameter(&"dash", 0.22)
		_recall_line.visible = false
		# Memory ribbon: a dashed loop of tape that rewinds around the boss while it recalls.
		_ribbon = _flat(S.ring, m.flat_add, self, Color(1, 1, 1, 0.0))
		_ribbon.set_instance_shader_parameter(&"dash", 0.35)
		_ribbon.set_instance_shader_parameter(&"len", TAU * 1.6)
		_ribbon.visible = false
	if type == EnemyType.SHIELDER:
		_dome = _flat(S.dome, m.flat_add, _body, Color(SHIELD_COLOR, 0.12))
		_dome.position = Vector3(0, 0.45, 0.12)
	_shock = _flat(S.shock, m.flat_add, self, Color(danger, 0.0))
	_shock.position.y = 0.03
	_shock.visible = false


## Reset per-instance state when (re)acquired from the pool for a new enemy id.
func reset(p_id: String) -> void:
	id = p_id
	_initialized = false
	_death_t = -1.0
	_flash = 0.0
	_walk = 0.0
	_moving = 0.0
	_seed = ActorMath.hash_string(p_id) * 100.0
	_last_phase = -1
	_recall_k = 0.0
	_last_state = &""
	_blend_t = 1.0
	_base_yaw = RenderCtx.heading_to_yaw(_S.base_facing.get(p_id, 0.0))
	visible = true
	_body.visible = true
	_marker.visible = true


## True while the death burst still plays after the enemy left the snapshot.
func dying() -> bool:
	return _death_t >= 0.0 and _death_t < DEATH_SECONDS


## The enemy is absent from the snapshot: play out the death if it was alive.
func vanish(env: Env) -> void:
	if _was_alive and _death_t < 0.0:
		_start_death()
	_was_alive = false
	if _death_t >= 0.0:
		_tick_death(env.dt)
	_hide_overlays()


func hide_view() -> void:
	visible = false
	_hide_overlays()


func _hide_overlays() -> void:
	_marker.visible = false
	_aim.visible = false
	_target_line.visible = false
	if _tele != null:
		_tele.visible = false
	for v: MeshInstance3D in _volley:
		v.visible = false
	if _sweep != null:
		_sweep.visible = false
		_recall.visible = false
		_recall_line.visible = false
		_ribbon.visible = false


func update_enemy(e: ActorInterp.EnemyFrame, env: Env) -> void:
	var dt := env.dt
	_time += dt
	_x = e.x
	_y = e.y
	# Combat feel: a struck enemy is drawn late (frozen on the contact frame, then catching up),
	# squashed along the hit, tilted and shuddering. Its floor telegraph and markers stay honest:
	# only the body is held.
	var fx: FeelSubject = env.feel.enemy_fx(e.id) if env.feel != null else null
	var off := fx.lag_offset() if fx != null else Vector2.ZERO
	position = Vector3(e.x, 0, e.y)
	rig.update_xray(global_position if is_inside_tree() else position)
	var yaw := RenderCtx.heading_to_yaw(e.facing)
	# A turret's plinth keeps its placed facing; its head turns on the aim bone.
	var body_xf := Transform3D(Basis(Vector3.UP, _base_yaw if type == EnemyType.TURRET else yaw), Vector3(off.x, 0, off.y))
	_body.transform = fx.apply(body_xf) if fx != null and fx.is_deformed() else body_xf
	visible = true
	_marker.visible = true
	if not _initialized or e.teleported:
		_prev_x = e.x
		_prev_y = e.y
		_last_hp = e.hp
		_last_shield = e.shield
		_was_alive = e.alive and e.state != EnemyStateName.DEAD
		_initialized = true
		if not _was_alive:
			# Seen for the first time already dead (a seek into a run): no burst, just gone.
			_death_t = DEATH_SECONDS
	var dead := not e.alive or e.state == EnemyStateName.DEAD
	if dead:
		if _was_alive and _death_t < 0.0:
			_start_death()
		_was_alive = false
		_tick_death(dt)
		_hide_overlays()
		return
	_was_alive = true
	_death_t = -1.0
	_body.visible = true
	_shock.visible = false
	rig.scale = Vector3.ONE

	# Hit flash: hp went down, or the sim reported a hit on this id.
	if e.hp < _last_hp or env.hits.has(e.id):
		_flash = FLASH_SECONDS
	_last_hp = e.hp
	_flash = maxf(0.0, _flash - dt)

	var dist := Vector2(e.x - _prev_x, e.y - _prev_y).length()
	_prev_x = e.x
	_prev_y = e.y
	var spd := dist / dt if dt > 0.0 else 0.0
	_moving += (ActorMath.clamp01(spd / 2.0) - _moving) * minf(1.0, dt * 10.0)
	_walk += dist / WALK_STRIDE

	_animate(e, dt, fx)
	_aim_at(e, env, yaw)
	if type == EnemyType.BOSS:
		_boss_phase(e)
	_update_eye(e, env)
	_update_telegraph(e, env)
	_update_target(e, env)
	_update_markers(e, env)
	if _dome != null:
		_update_shield(e, dt)
	if _shadow != null:
		var s := 1.0 - minf(0.5, spec.hover * 0.25)
		_shadow.scale = Vector3(s, 1.0, s)
	var asleep := e.state == EnemyStateName.ASLEEP
	# Impact frame. With the feel layer: white for one to three frames by momentum, the first one
	# inverted on heavy tiers (ink body, paper-white outline), nothing on a clang. Under "reduce
	# flashing" the body never flashes: the outline turns white for the plain flash time instead.
	var flash_a := 0.85 if _flash > 0.0 else 0.0
	var flash_c := Color.WHITE
	var hull := _ink_hull
	if env.feel != null:
		var ff := env.feel.flash_of(fx)
		flash_a = ff.x
		if ff.y > 0.5:
			flash_c = SelfView.NEGATIVE_BODY
			hull = Color(1.0, 0.98, 0.94)
	if env.reduce_flashing:
		flash_a = 0.0
		if _flash > 0.0:
			hull = Color(1.0, 0.98, 0.94)
	rig.set_param(&"flash_col", Color(flash_c, flash_a))
	rig.set_param(&"outline_color", Color(hull, 1.0))
	rig.set_param(&"desat", 0.5 if asleep else 0.0)


## Pose from state + state_t (telegraph / attack / stagger scrubbed by state_t; idle and move loop).
func _animate(e: ActorInterp.EnemyFrame, dt: float, fx: FeelSubject = null) -> void:
	var st := e.state
	# A held hit freezes the stagger clip where the hold began and releases it over the catch-up.
	var stagger_t := e.state_t
	if fx != null and fx.lag > 0.0 and st == EnemyStateName.STAGGER:
		if not _was_frozen:
			_held_t = 0.0 if st != _last_state else e.state_t
		var w := 1.0 if fx.frozen else clampf(fx.lag / maxf(fx.hold.hold, 1e-3), 0.0, 1.0)
		stagger_t = lerpf(e.state_t, _held_t, w)
		_was_frozen = true
	else:
		_was_frozen = false
	if st != _last_state:
		if _last_state != &"":
			_from.copy_from(_pose)
			_blend_t = 0.0
		_last_state = st
	match st:
		EnemyStateName.TELEGRAPH:
			_sampler.sample(&"telegraph", e.state_t, _target)
		EnemyStateName.ATTACK:
			_sampler.sample(&"attack", e.state_t, _target)
		EnemyStateName.STAGGER:
			_sampler.sample(&"stagger", stagger_t, _target)
		EnemyStateName.ASLEEP:
			_sampler.sample(&"idle", 0.0, _target)
		_:
			var idle_len := _sampler.clip_length(&"idle")
			_sampler.sample(&"idle", fmod(_time + _seed, idle_len) / idle_len, _target)
			if _moving > 0.02 and _sampler.has_clip(&"move"):
				_sampler.sample(&"move", fmod(_walk, 1.0), _tmp)
				ActorClipSampler.blend(_target, _tmp, ActorMath.smooth(0.0, 1.0, _moving), _target)
	_blend_t = minf(1.0, _blend_t + dt / BLEND_SECONDS)
	if _blend_t < 1.0:
		ActorClipSampler.blend(_from, _target, ActorMath.smooth(0.0, 1.0, _blend_t), _pose)
	else:
		_pose.copy_from(_target)
	# The boss's reels spin forward normally; on memory they spin hard in reverse (rewinding).
	if _reels.size() > 0:
		var spin := -9.0 if e.boss_recall else 1.2 + float(e.boss_phase) * 1.5
		for k: int in _reels.size():
			var bi := _reels[k]
			var q := _pose.get_rot(bi) * Quaternion(Vector3.RIGHT, _time * spin * (1.0 if k == 0 else -1.0))
			_pose.set_rot(bi, q)
	# Asleep: slumped.
	if st == EnemyStateName.ASLEEP:
		rig.position = Vector3(0, -0.04, 0)
		rig.rotation = Vector3(0.12, 0, 0)
	else:
		rig.position = Vector3.ZERO
		rig.rotation = Vector3.ZERO
	_sampler.apply(_pose)


## Turret: the head yaws to the aim; drone: the lens pitches down toward its target.
func _aim_at(e: ActorInterp.EnemyFrame, env: Env, yaw: float) -> void:
	if _aim_bone < 0:
		return
	var q := _pose.get_rot(_aim_bone)
	if type == EnemyType.TURRET:
		q = Quaternion(_aim_axis_yaw, ActorMath.wrap_angle(yaw - _base_yaw)) * q
	elif e.target >= 0 and e.target < 4 and env.self_shown[e.target]:
		var p := env.self_pos[e.target]
		var d := Vector2(p.x - e.x, p.y - e.y).length()
		var pitch := atan2(spec.hover * 0.9, maxf(0.3, d))
		q = Quaternion(_aim_axis_pitch, pitch) * q
	rig.skeleton.set_bone_pose_rotation(_aim_bone, q)


func _boss_phase(e: ActorInterp.EnemyFrame) -> void:
	var phase := maxi(1, e.boss_phase)
	if _last_phase >= 0 and phase != _last_phase:
		# Change of form: flash and shed debris so the transition itself is unmissable.
		_flash = 0.35
		_death_burst(0.5)
	_last_phase = phase
	# Armour plates fall away as phases advance: phase 2 drops Armor_1, phase 3 also Armor_2.
	for i: int in _armor.size():
		_armor[i].visible = i + 1 >= phase
	_recall_k += ((1.0 if e.boss_recall else 0.0) - _recall_k) * 0.12
	# Later phases run hotter: tinted toward the danger hue.
	var hot := 0.12 + 0.06 * sin(_time * 4.0) if phase >= 3 else (0.05 if phase == 2 else 0.0)
	rig.set_param(&"tint", Color(EnemySpecs.DANGER, hot))


func _tape_color(env: Env, tape: int) -> Color:
	return env.tape_colors[tape] if tape >= 0 and tape < env.tape_colors.size() else Color.WHITE


func _update_eye(e: ActorInterp.EnemyFrame, env: Env) -> void:
	var t := e.state_t
	var acc := EnemySpecs.EYE
	match e.state:
		EnemyStateName.ASLEEP:
			acc = EnemySpecs.EYE * 0.25
		EnemyStateName.TELEGRAPH:
			acc = EnemySpecs.EYE.lerp(Color.WHITE, t * 0.8) * (1.0 + t * 1.5 + sin(_time * 30.0) * 0.3 * t)
		EnemyStateName.ATTACK:
			acc = Color.WHITE * (2.2 - t)
		EnemyStateName.STAGGER:
			acc = EnemySpecs.EYE * (1.2 if sin(_time * 40.0) > 0.0 else 0.2)
		_:
			acc = EnemySpecs.EYE * 1.1
	if type == EnemyType.BOSS and e.boss_recall:
		# Acting on memory: the optic takes the colour of the remembered tape (BOSS-02).
		acc = acc.lerp(_tape_color(env, e.recall_tape) * 1.8, 0.85)
	acc.a = 1.0
	rig.set_param(&"accent", acc)
	rig.set_param(&"glow_mul", 0.6 if e.state == EnemyStateName.ASLEEP else 1.4)


func _target_dist(e: ActorInterp.EnemyFrame, env: Env) -> float:
	if e.target < 0 or e.target >= 4 or not env.self_shown[e.target]:
		return -1.0
	var p := env.self_pos[e.target]
	return Vector2(p.x - e.x, p.y - e.y).length()


func _update_telegraph(e: ActorInterp.EnemyFrame, env: Env) -> void:
	var tele := e.state == EnemyStateName.TELEGRAPH
	var atk := e.state == EnemyStateName.ATTACK
	var danger := EnemySpecs.DANGER
	var fill := ActorMath.clamp01(e.state_t) if tele else 1.0
	var op := 0.0
	var col := danger
	if tele:
		op = 0.55 + 0.25 * ActorMath.smooth(0.7, 1.0, e.state_t) * (0.5 + 0.5 * sin(_time * 40.0))
	elif atk:
		op = 0.9 * (1.0 - e.state_t)
		col = danger.lerp(Color.WHITE, 0.5 * (1.0 - e.state_t))
	var mode: StringName = &""
	if type == EnemyType.BOSS:
		mode = EnemySpecs.boss_mode(e, env.boss_modes.get(e.id, &""), _target_dist(e, env))
		if e.boss_recall:
			col = col.lerp(_tape_color(env, e.recall_tape), 0.65)
	# Cone / circle decal.
	if _tele != null:
		var show := (tele or atk) and (type != EnemyType.BOSS or mode == EnemySpecs.BOSS_CLEAVE)
		_tele.visible = show
		if show:
			_tele.set_instance_shader_parameter(&"fill", fill)
			_tele.set_instance_shader_parameter(&"color", Color(col, op))
	# Aim line: always shows where turrets / drones point; fills during the telegraph.
	var aim_type := spec.shape == EnemySpecs.SHAPE_LINE
	if aim_type:
		var length := spec.length
		var td := _target_dist(e, env)
		if td >= 0.0:
			length = minf(length, maxf(0.6, td))
		var fx := cos(e.facing)
		var fy := sin(e.facing)
		var h := spec.hover + 0.02 if spec.hover > 0.0 else 0.42
		var start := 0.35
		var width := 0.05 + 0.05 * e.state_t if tele else (0.12 * (1.0 - e.state_t) + 0.03 if atk else 0.025)
		ActorGeom.place_strip(_aim, e.x + fx * start, e.y + fy * start, e.x + fx * (start + length), e.y + fy * (start + length), width, h)
		_aim.visible = e.state != EnemyStateName.ASLEEP
		_aim.set_instance_shader_parameter(&"fill", fill if tele else 2.0)
		_aim.set_instance_shader_parameter(&"back", 0.25 if tele else 1.0)
		var ac := danger.lerp(Color.WHITE, 0.6 * (1.0 - e.state_t)) if atk else danger
		_aim.set_instance_shader_parameter(&"color", Color(ac, 0.9 if tele else (0.95 * (1.0 - e.state_t) + 0.1 if atk else 0.28)))
	else:
		_aim.visible = false
	if type == EnemyType.BOSS:
		_update_boss_modes(e, env, mode, tele, atk, fill, op, col)
	_arrow.visible = e.state != EnemyStateName.ASLEEP
	_arrow.set_instance_shader_parameter(&"color", Color(danger, 0.9 if tele else 0.55))


func _update_boss_modes(e: ActorInterp.EnemyFrame, env: Env, mode: StringName, tele: bool, atk: bool, fill: float, op: float, col: Color) -> void:
	var active := tele or atk
	# Volley: three bolts fanned at the attention.
	for i: int in _volley.size():
		var v := _volley[i]
		var show := active and mode == EnemySpecs.BOSS_VOLLEY
		v.visible = show
		if show:
			var a := e.facing + (float(i) - 1.0) * EnemySpecs.BOSS_VOLLEY_SPREAD
			var r0 := spec.radius + 0.2
			var length := minf(spec.length, maxf(1.0, _target_dist(e, env) + 0.5)) if _target_dist(e, env) >= 0.0 else spec.length * 0.6
			ActorGeom.place_strip(v, e.x + cos(a) * r0, e.y + sin(a) * r0, e.x + cos(a) * (r0 + length), e.y + sin(a) * (r0 + length), 0.09, 0.5)
			v.set_instance_shader_parameter(&"fill", fill)
			v.set_instance_shader_parameter(&"back", 0.25 if tele else 1.0)
			v.set_instance_shader_parameter(&"color", Color(col, op))
	# Sweep: a ring of shockwaves out to BOSS_SWEEP_RANGE.
	var sw := active and mode == EnemySpecs.BOSS_SWEEP
	_sweep.visible = sw
	if sw:
		_sweep.set_instance_shader_parameter(&"fill", fill)
		_sweep.set_instance_shader_parameter(&"color", Color(col, op * 0.8))
	# Memory strike: the zone at the remembered place, a dashed line from the boss to it and the
	# rewinding tape ribbon, all in the remembered cassette's colour.
	var rc := _tape_color(env, e.recall_tape)
	var rec := e.boss_recall and e.has_recall_at and active
	_recall.visible = rec
	_recall_line.visible = rec
	if rec:
		var r := EnemySpecs.BOSS_RECALL_RADIUS + EnemySpecs.ACTOR_RADIUS
		var pulse := 1.0 + 0.04 * sin(_time * 9.0)
		_recall.transform = Transform3D(Basis.from_scale(Vector3(r * pulse, 1.0, r * pulse)), Vector3(e.recall_x, 0.026, e.recall_y))
		_recall.set_instance_shader_parameter(&"fill", fill)
		_recall.set_instance_shader_parameter(&"color", Color(rc.lerp(EnemySpecs.DANGER, 0.25), maxf(op, 0.5)))
		var ln := ActorGeom.place_strip(_recall_line, e.x, e.y, e.recall_x, e.recall_y, 0.06, 0.05)
		_recall_line.set_instance_shader_parameter(&"len", ln)
		_recall_line.set_instance_shader_parameter(&"color", Color(rc, 0.8))
	_ribbon.visible = _recall_k > 0.05
	if _ribbon.visible:
		var rr := spec.radius + 0.45
		_ribbon.transform = Transform3D(Basis(Vector3.UP, -_time * 2.2) * Basis.from_scale(Vector3(rr, 1.0, rr)), Vector3(0, 1.0 + sin(_time * 3.0) * 0.08, 0))
		_ribbon.set_instance_shader_parameter(&"color", Color(rc, 0.85 * _recall_k))


func _update_target(e: ActorInterp.EnemyFrame, env: Env) -> void:
	var has := e.target >= 0 and e.target < 4 and e.state != EnemyStateName.ASLEEP and env.self_shown[e.target]
	_target_line.visible = has
	_target_pip.visible = has
	if not has:
		return
	var c := _tape_color(env, e.target)
	var p := env.self_pos[e.target]
	var ln := ActorGeom.place_strip(_target_line, e.x, e.y, p.x, p.y, 0.024, 0.035)
	_target_line.set_instance_shader_parameter(&"len", ln)
	_target_line.set_instance_shader_parameter(&"color", Color(c, 0.75 if e.state == EnemyStateName.TELEGRAPH else 0.38))
	_target_pip.set_instance_shader_parameter(&"color", Color(c, 0.95))


func _update_markers(e: ActorInterp.EnemyFrame, env: Env) -> void:
	_marker.basis = env.cam_basis
	var multi := e.max_hp > 1 and type != EnemyType.BOSS
	var n := mini(MAX_PIPS, maxi(0, e.max_hp)) if multi else 0
	var gap := 0.09
	for i: int in MAX_PIPS:
		var p := _pips[i]
		p.visible = i < n
		if not p.visible:
			continue
		p.position = Vector3((float(i) - float(n - 1) * 0.5) * gap, 0, 0)
		p.set_instance_shader_parameter(&"color", Color("#fff1d6") if i < e.hp else Color(Color("#2a2530"), 0.8))
	if _bar_fill != null:
		var f := ActorMath.clamp01(float(e.hp) / float(e.max_hp)) if e.max_hp > 0 else 0.0
		_bar_fill.scale = Vector3(maxf(0.001, 1.56 * f), 0.07, 1.0)
		_bar_fill.position.x = -0.78 * (1.0 - f)
		var bc := EnemySpecs.DANGER.lerp(Color.WHITE, 0.7 if _flash > 0.0 else 0.0)
		if e.boss_recall and e.recall_tape >= 0:
			bc = bc.lerp(_tape_color(env, e.recall_tape), 0.6)
		_bar_fill.set_instance_shader_parameter(&"color", bc)


func _update_shield(e: ActorInterp.EnemyFrame, dt: float) -> void:
	if _last_shield and not e.shield:
		_shield_break_t = 0.0
		# Shards of the shell scatter when it drops.
		for i: int in 16:
			var a := ActorMath.hash01(i + _seed) * TAU
			_S.glow.emit(e.x + cos(e.facing) * 0.3, 0.5 + ActorMath.hash01(i * 3 + _seed) * 0.4, e.y + sin(e.facing) * 0.3,
				cos(a) * 1.4, 0.8, sin(a) * 1.4, 0.45, 0.05, 0.0, Color("#8ffff0"), 1.0, 3.0, 3.0)
	_last_shield = e.shield
	if _shield_mesh != null:
		_shield_mesh.visible = e.shield
	_shield_break_t = minf(1.0, _shield_break_t + dt * 3.0)
	_dome.visible = e.shield or _shield_break_t < 1.0
	var k := 1.0 if e.shield else 1.0 - _shield_break_t
	var shimmer := 0.5 + 0.5 * sin(_time * 5.0)
	_dome.set_instance_shader_parameter(&"color", Color(SHIELD_COLOR, (0.08 + 0.06 * shimmer) * k + (0.0 if e.shield else 0.25 * k)))
	var s := 1.0 if e.shield else 1.0 + (1.0 - k) * 0.3
	_dome.scale = Vector3(s, 0.95 * s, 0.8 * s)


func _start_death() -> void:
	_death_t = 0.0
	_death_burst(1.0)


func _death_burst(scale_k: float) -> void:
	var n := roundi((60.0 if type == EnemyType.BOSS else (34.0 if type == EnemyType.BRUTE else 22.0)) * scale_k)
	var r := spec.radius
	for i: int in n:
		var a := ActorMath.hash01(i * 1.7 + _seed) * TAU
		var sp := 0.8 + ActorMath.hash01(i * 3.1 + _seed) * 2.2 * (r + 0.5)
		_S.dust.emit(_x, 0.2 + ActorMath.hash01(i + _seed) * spec.top * 0.7, _y, cos(a) * sp, 1.0 + ActorMath.hash01(i * 5.3) * 2.0, sin(a) * sp,
			0.9, 0.06 + ActorMath.hash01(i * 2.2) * 0.06, 0.6, BRASS if i % 4 == 0 else STONE, 1.0, 1.2, 6.0)
		if i % 2 == 0:
			_S.glow.emit(_x, 0.4 + ActorMath.hash01(i * 9 + _seed) * spec.top * 0.5, _y, cos(a + 0.5) * sp * 0.8, 0.5 + ActorMath.hash01(i * 7.7) * 1.5, sin(a + 0.5) * sp * 0.8,
				0.5, 0.05, 0.0, EnemySpecs.DANGER, 1.0, 2.0, 0.0)


## Collapse: flash, crumple downward (the death clip), a shock ring expands on the floor.
func _tick_death(dt: float) -> void:
	if _death_t < 0.0:
		return
	_death_t += dt
	var k := ActorMath.clamp01(_death_t / DEATH_SECONDS)
	if k >= 1.0:
		_body.visible = false
		_shock.visible = false
		if _shadow != null:
			_shadow.visible = false
		return
	_body.visible = true
	if _sampler.has_clip(&"death"):
		_sampler.sample(&"death", k, _pose)
		_sampler.apply(_pose)
	else:
		rig.scale = Vector3(1.0 + k * 0.2, 1.0 - ActorMath.ease_in_cubic(k) * 0.9, 1.0 + k * 0.2)
	rig.set_param(&"flash_col", Color(Color.WHITE if k < 0.2 else EnemySpecs.DANGER, 1.0 if k < 0.2 else 0.6 * (1.0 - k)))
	_shock.visible = true
	var rr := spec.radius * (1.0 + k * 2.5)
	_shock.scale = Vector3(rr, 1.0, rr)
	_shock.set_instance_shader_parameter(&"color", Color(EnemySpecs.DANGER, 0.8 * (1.0 - k)))
