class_name ProjectileView
extends Node3D
## Projectiles, one look per archetype (WEAPON-01..03; prototype projectileView.ts), coloured by
## owner: a self's shots carry its cassette colour, enemy shots the hot danger orange.
##   missile - slow, chunky, smoke trail, dashed lock line + reticle on its one locked target (WEAPON-02)
##   pierce  - fast bright lance with a long streak
##   phase   - ghostly orb drawn over walls (it passes through them, so it must stay visible)
##   arc     - lobbed shell at height z, ground shadow and a predicted landing marker
##   burst   - small pellets with short streaks
##   bolt    - enemy energy bolt
##   shock   - enemy crackling orb

const SMOKE: Color = Color("#b9b4ad")
## Projectile models (asset contract addendum: one mesh node `Projectile`, nose +Z, +Y up). While a
## file is missing the primitive core is drawn instead.
const MODEL_DIR: String = "res://assets/models/projectiles/"
## The dart launcher's bolt ships with the trap kit (docs/GODOT-PORT.md "Dart launcher").
const DART_MODEL: String = "res://assets/models/kit/trap_dart_bolt.glb"
## Height a dart flies at (the launcher's muzzle), and its pale `dart_glow` colour: no cassette owns it.
const DART_HEIGHT: float = 0.30
const DART_COLOR: Color = Color("#f4eeff")
const CRACKLE: int = 6


class Shared:
	extends RefCounted
	var mats: ActorMaterials = null
	var dust: ActorParticles = null
	var glow: ActorParticles = null
	var strip: ArrayMesh = null
	var orb: SphereMesh = null
	var missile_body: CapsuleMesh = null
	var fin: BoxMesh = null
	var ring: ArrayMesh = null
	var disc: ArrayMesh = null
	var pellet: SphereMesh = null
	var spike: BoxMesh = null


class Env:
	extends RefCounted
	var dt: float = 0.0
	var time: float = 0.0
	## Live enemy positions by id (missile lock lines).
	var enemy_pos: Dictionary[String, Vector2] = {}


var kind: StringName = &""
var color: Color = Color.WHITE
var _S: Shared
var _body: Node3D
var _cores: Array[MeshInstance3D] = []
var _halos: Array[MeshInstance3D] = []
var _streak: MeshInstance3D = null
var _lock: MeshInstance3D = null
var _reticle: MeshInstance3D = null
var _shadow: MeshInstance3D = null
var _landing: MeshInstance3D = null
var _crackle: Array[MeshInstance3D] = []
var _emit_acc: float = 0.0
var _time: float = 0.0
var _last: Vector3 = Vector3.ZERO
var _vel: Vector3 = Vector3.ZERO
var _g: float = 0.0
var _samples: int = 0
var _seed: float = 0.0
var _halo_alpha: float = 0.55
## The archetype's model (null while its file is missing) and its meshes (owner colour on the glow).
var _model: Node3D = null
var _model_meshes: Array[MeshInstance3D] = []


func setup(p_kind: StringName, S: Shared) -> void:
	kind = p_kind
	_S = S
	name = "Shot_" + String(kind)
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var m := S.mats
	var overlay := kind == RangedArchetype.PHASE
	var core_mat: Material = m.flat_overlay if overlay else m.flat_mix
	var halo_mat: Material = m.flat_overlay_add if overlay else m.flat_add
	match kind:
		RangedArchetype.MISSILE:
			_part(S.missile_body, m.flat_mix, Vector3(1, 1, 1), Vector3.ZERO, Vector3(PI * 0.5, 0, 0), false, Color("#2d2a30"))
			for i: int in 4:
				var a := PI * 0.5 * i + PI * 0.25
				_part(S.fin, core_mat, Vector3(1, 1, 1), Vector3(sin(a) * 0.05, cos(a) * 0.05, -0.1), Vector3(0, 0, -a), true)
			var ex := _part(S.orb, halo_mat, Vector3(0.09, 0.09, 0.14), Vector3(0, 0, -0.18), Vector3.ZERO, false)
			_halos.append(ex)
			_lock = _world(S.strip, m.flat_mix)
			_lock.set_instance_shader_parameter(&"dash", 0.14)
			_reticle = _world(S.ring, m.flat_overlay_add)
		RangedArchetype.PIERCE:
			_part(S.orb, core_mat, Vector3(0.05, 0.05, 0.3), Vector3.ZERO, Vector3.ZERO, true)
			_halos.append(_part(S.orb, halo_mat, Vector3(0.1, 0.1, 0.42), Vector3.ZERO, Vector3.ZERO, false))
			_streak = _world(S.strip, m.flat_add)
		RangedArchetype.PHASE:
			_part(S.orb, core_mat, Vector3(0.09, 0.09, 0.09), Vector3.ZERO, Vector3.ZERO, true)
			_halos.append(_part(S.orb, halo_mat, Vector3(0.2, 0.2, 0.2), Vector3.ZERO, Vector3.ZERO, false))
			var r := _part(S.ring, halo_mat, Vector3(0.24, 0.24, 0.24), Vector3.ZERO, Vector3.ZERO, false)
			_halos.append(r)
		RangedArchetype.ARC:
			_part(S.orb, core_mat, Vector3(0.1, 0.1, 0.1), Vector3.ZERO, Vector3.ZERO, true)
			_halos.append(_part(S.orb, halo_mat, Vector3(0.17, 0.17, 0.17), Vector3.ZERO, Vector3.ZERO, false))
			_shadow = _world(S.disc, m.flat_mix)
			_landing = _world(S.ring, m.flat_add)
		RangedArchetype.BURST:
			_part(S.pellet, core_mat, Vector3(0.045, 0.045, 0.045), Vector3.ZERO, Vector3.ZERO, true)
			_halos.append(_part(S.orb, halo_mat, Vector3(0.08, 0.08, 0.08), Vector3.ZERO, Vector3.ZERO, false))
			_streak = _world(S.strip, m.flat_add)
		RangedArchetype.SHOCK:
			_part(S.orb, core_mat, Vector3(0.08, 0.08, 0.08), Vector3.ZERO, Vector3.ZERO, true)
			_halos.append(_part(S.orb, halo_mat, Vector3(0.18, 0.18, 0.18), Vector3.ZERO, Vector3.ZERO, false))
			for i: int in CRACKLE:
				var c := MeshInstance3D.new()
				c.mesh = S.spike
				c.material_override = m.flat_add
				c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_body.add_child(c)
				_crackle.append(c)
		RangedArchetype.DART:
			# A thin pale needle with a long streak: small, fast and still readable on any floor.
			_part(S.orb, core_mat, Vector3(0.035, 0.035, 0.16), Vector3.ZERO, Vector3.ZERO, true)
			_halos.append(_part(S.orb, halo_mat, Vector3(0.09, 0.09, 0.26), Vector3.ZERO, Vector3.ZERO, false))
			_streak = _world(S.strip, m.flat_add)
		_:
			# bolt (enemy) and any unknown archetype.
			_part(S.orb, core_mat, Vector3(0.06, 0.06, 0.18), Vector3.ZERO, Vector3.ZERO, true)
			_halos.append(_part(S.orb, halo_mat, Vector3(0.13, 0.13, 0.24), Vector3.ZERO, Vector3.ZERO, false))
			_streak = _world(S.strip, m.flat_add)
	_load_model(S)
	if _streak != null:
		_streak.set_instance_shader_parameter(&"fade", 1.0)
		_streak.set_instance_shader_parameter(&"edge", -0.8)
	if _shadow != null:
		_shadow.set_instance_shader_parameter(&"color", Color(0, 0, 0, 0.35))


## Swap the primitive core for the archetype's model when its file exists. The model is cel-shaded
## with the actor materials; its `_glow` parts take the owner colour (accent). The additive halos,
## streaks and markers stay: they carry the owner colour and the readability cues. The phase shot
## keeps its over-the-walls core too (it passes through walls, so it must stay visible).
func _load_model(S: Shared) -> void:
	var path := DART_MODEL if kind == RangedArchetype.DART else MODEL_DIR + String(kind) + ".glb"
	if not ResourceLoader.exists(path):
		return
	var scene := load(path) as PackedScene
	if scene == null:
		return
	_model = scene.instantiate() as Node3D
	if _model == null:
		return
	_model.name = "Model"
	_body.add_child(_model)
	for n: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		_model_meshes.append(mi)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i: int in mi.mesh.get_surface_count():
			var mat_name := String(ActorRig.surface_material_name(mi, i))
			var m := mi.get_active_material(i)
			var col := (m as BaseMaterial3D).albedo_color if m is BaseMaterial3D else Color(0.8, 0.8, 0.8)
			var glow := mat_name.ends_with("_glow")
			mi.set_surface_override_material(i, S.mats.body_pair(col, glow, glow)[0])
		mi.set_instance_shader_parameter(&"outline_width", 0.008)
		mi.set_instance_shader_parameter(&"glow_mul", 2.2)
	if kind != RangedArchetype.PHASE:
		for c: MeshInstance3D in _cores:
			c.visible = false
		_cores.clear()


func _part(mesh: Mesh, mat: Material, scl: Vector3, pos: Vector3, rot: Vector3, is_core: bool, fixed: Color = Color(0, 0, 0, 0)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(Basis.from_euler(rot) * Basis.from_scale(scl), pos)
	_body.add_child(mi)
	if fixed.a > 0.0:
		mi.set_instance_shader_parameter(&"color", fixed)
	elif is_core:
		_cores.append(mi)
	return mi


func _world(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	return mi


func reset(id: int, owner_color: Color) -> void:
	_seed = ActorMath.hash01(id * 0.37 + 1.0) * 100.0
	_samples = 0
	_time = 0.0
	_emit_acc = 0.0
	_g = 0.0
	_vel = Vector3.ZERO
	color = owner_color
	# Enemy shots keep more of their orange so they never read as a self's pale shot.
	var pale := 0.0 if kind == RangedArchetype.MISSILE else (0.2 if kind == RangedArchetype.BOLT or kind == RangedArchetype.SHOCK else 0.55)
	var core := Color(owner_color.lerp(Color.WHITE, pale), 1.0)
	for c: MeshInstance3D in _cores:
		c.set_instance_shader_parameter(&"color", core)
	_halo_alpha = 0.55
	for h: MeshInstance3D in _halos:
		h.set_instance_shader_parameter(&"color", Color(owner_color, _halo_alpha))
	for c: MeshInstance3D in _crackle:
		c.set_instance_shader_parameter(&"color", Color(owner_color.lerp(Color.WHITE, 0.4), 0.9))
	for mi: MeshInstance3D in _model_meshes:
		mi.set_instance_shader_parameter(&"accent", Color(owner_color.lerp(Color.WHITE, pale * 0.5), 1.0))
		mi.set_instance_shader_parameter(&"outline_color", Color(owner_color.darkened(0.7), 1.0))
		# The phase shot's model shows through walls as a flat owner-coloured silhouette.
		mi.set_instance_shader_parameter(&"xray_color", Color(owner_color, 0.7 if kind == RangedArchetype.PHASE else 0.0))
	if _streak != null:
		_streak.set_instance_shader_parameter(&"color", Color(owner_color, 0.8))
	if _lock != null:
		_lock.set_instance_shader_parameter(&"color", Color(owner_color, 0.55))
		_reticle.set_instance_shader_parameter(&"color", Color(owner_color, 0.85))
	if _landing != null:
		_landing.set_instance_shader_parameter(&"color", Color(owner_color, 0.0))
	visible = true


func update_shot(p: ActorInterp.ShotFrame, target_id: String, env: Env) -> void:
	var dt := env.dt
	_time += dt
	var h := 0.15 + p.z if kind == RangedArchetype.ARC else (0.45 + p.z if kind == RangedArchetype.MISSILE else 0.5 + p.z)
	if kind == RangedArchetype.DART:
		h = DART_HEIGHT + p.z
	position = Vector3(p.x, h, p.y)
	_body.rotation = Vector3(0, RenderCtx.heading_to_yaw(p.dir), 0)
	# Velocity estimate (landing prediction, trails).
	var cur := Vector3(p.x, p.z, p.y)
	if _samples > 0 and dt > 1e-5:
		var k := minf(1.0, dt * 12.0)
		var nv := (cur - _last) / dt
		if _samples > 1:
			var ng := -(nv.y - _vel.y) / dt
			if not is_nan(ng) and not is_inf(ng):
				_g += (ng - _g) * minf(1.0, dt * 4.0)
		_vel = _vel.lerp(nv, k)
	var moved := Vector2(p.x - _last.x, p.y - _last.z).length() if _samples > 0 else 0.0
	_last = cur
	_samples += 1
	if p.fresh:
		_muzzle(p)
	var fx := cos(p.dir)
	var fy := sin(p.dir)
	match kind:
		RangedArchetype.MISSILE:
			# Slow and smoky: the long flight is the weapon's drawback (WEAPON-02), so make it visible.
			_emit_acc += moved * 22.0 + dt * 8.0
			var k := 0
			while _emit_acc >= 1.0:
				_emit_acc -= 1.0
				k += 1
				var r := ActorMath.hash01(_time * 50.0 + _seed + k * 4.1) - 0.5
				_S.dust.emit(p.x - fx * 0.2 + r * 0.04, h + r * 0.04, p.y - fy * 0.2, 0, 0.15, 0, 1.2, 0.07, 3.0, SMOKE, 0.55, 2.0, 0.0)
			var has_t := not target_id.is_empty() and env.enemy_pos.has(target_id)
			_lock.visible = has_t
			_reticle.visible = has_t
			if has_t:
				var tp: Vector2 = env.enemy_pos[target_id]
				var ln := ActorGeom.place_strip(_lock, p.x, p.y, tp.x, tp.y, 0.03, 0.06)
				_lock.set_instance_shader_parameter(&"len", ln)
				var s := 0.45 + sin(_time * 8.0) * 0.04
				_reticle.transform = Transform3D(Basis(Vector3.UP, _time * 3.0) * Basis.from_scale(Vector3(s, 1.0, s)), Vector3(tp.x, 0.06, tp.y))
		RangedArchetype.PIERCE, RangedArchetype.BURST, RangedArchetype.BOLT, RangedArchetype.DART:
			if _streak != null:
				var length := 1.1 if kind == RangedArchetype.PIERCE else (0.5 if kind == RangedArchetype.BOLT else 0.28)
				var w := 0.07 if kind == RangedArchetype.PIERCE else (0.08 if kind == RangedArchetype.BOLT else 0.04)
				if kind == RangedArchetype.DART:
					length = 0.8
					w = 0.06
				ActorGeom.place_strip(_streak, p.x - fx * length, p.y - fy * length, p.x, p.y, w, h)
		RangedArchetype.PHASE:
			var s := 1.0 + sin(_time * 9.0 + _seed) * 0.15
			_body.scale = Vector3(s, s, s)
			for hm: MeshInstance3D in _halos:
				hm.set_instance_shader_parameter(&"color", Color(color, 0.35 + 0.15 * sin(_time * 13.0)))
			_emit_acc += dt * 18.0
			while _emit_acc >= 1.0:
				_emit_acc -= 1.0
				_S.glow.emit(p.x, h, p.y, 0, 0.1, 0, 0.35, 0.06, 0.3, color, 0.6, 0.0, 0.0)
		RangedArchetype.ARC:
			# The canister tumbles about its X axis as it flies.
			if _model != null:
				_model.rotation = Vector3(_time * 9.0 + _seed, 0, 0)
			_shadow.transform = Transform3D(Basis.from_scale(Vector3.ONE * maxf(0.4, 1.0 - p.z * 0.2)), Vector3(p.x, 0.016, p.y))
			# Predict touchdown from the observed parabola (falls back to a straight-down drop).
			var g := _g if _g > 0.5 else 9.8
			var disc := _vel.y * _vel.y + 2.0 * g * maxf(0.0, p.z)
			var tl := maxf(0.0, (_vel.y + sqrt(disc)) / g)
			var lx := p.x + _vel.x * tl
			var ly := p.y + _vel.z * tl
			var s := 0.35 + 0.08 * sin(_time * 10.0)
			_landing.transform = Transform3D(Basis(Vector3.UP, _time * 2.0) * Basis.from_scale(Vector3(s, 1.0, s)), Vector3(lx, 0.02, ly))
			_landing.set_instance_shader_parameter(&"color", Color(color, 0.8 if _samples > 2 else 0.0))
		RangedArchetype.SHOCK:
			var step := floorf(_time * 24.0)
			for i: int in CRACKLE:
				var a := ActorMath.hash01(step * 13.0 + i * 7.0 + _seed) * TAU
				var b := ActorMath.hash01(step * 17.0 + i * 3.0 + _seed) * PI - PI * 0.5
				var length := 0.14 + ActorMath.hash01(step + i) * 0.14
				var dirv := Vector3(cos(a) * cos(b), sin(b), sin(a) * cos(b))
				var bz := Basis.looking_at(dirv, Vector3.UP if absf(dirv.y) < 0.95 else Vector3.RIGHT)
				_crackle[i].transform = Transform3D(bz * Basis.from_scale(Vector3(0.012, 0.012, length)), dirv * (0.05 + length * 0.5))
			for hm: MeshInstance3D in _halos:
				hm.set_instance_shader_parameter(&"color", Color(color, 0.4 + 0.3 * ActorMath.hash01(floorf(_time * 30.0) + _seed)))


func _muzzle(p: ActorInterp.ShotFrame) -> void:
	for i: int in 8:
		var a := p.dir + (ActorMath.hash01(i + _seed) - 0.5) * 1.6
		var sp := 0.8 + ActorMath.hash01(i * 3 + _seed) * 1.4
		_S.glow.emit(p.x, 0.5 + p.z, p.y, cos(a) * sp, 0.2, sin(a) * sp, 0.22, 0.05, 0.0, color.lerp(Color.WHITE, 0.3), 1.0, 6.0, 0.0)


## The projectile ended between snapshots: a small pop at its last position.
func pop() -> void:
	for i: int in 10:
		var a := TAU * float(i) / 10.0
		_S.glow.emit(_last.x, 0.5 + _last.y, _last.z, cos(a) * 1.2, 0.4, sin(a) * 1.2, 0.25, 0.05, 0.0, color, 0.9, 5.0, 0.0)
	hide_view()


func hide_view() -> void:
	visible = false
