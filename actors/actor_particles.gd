class_name ActorParticles
extends MultiMeshInstance3D
## Pooled soft particles for the actor layer (prototype particles.ts): dust, smoke, glows, bursts.
## A fixed-capacity ring of particles in packed arrays drawn by one MultiMesh of camera-facing
## quads; emitting overwrites the oldest slot. Presentation only (it uses wall time, never the sim).
## Nothing is allocated after construction.

var capacity: int = 0
var _pos: PackedVector3Array = PackedVector3Array()
var _vel: PackedVector3Array = PackedVector3Array()
var _col: PackedColorArray = PackedColorArray()
## life, age, size, grow, drag, gravity per particle.
var _life: PackedFloat32Array = PackedFloat32Array()
var _age: PackedFloat32Array = PackedFloat32Array()
var _size: PackedFloat32Array = PackedFloat32Array()
var _grow: PackedFloat32Array = PackedFloat32Array()
var _drag: PackedFloat32Array = PackedFloat32Array()
var _grav: PackedFloat32Array = PackedFloat32Array()
var _next: int = 0
var _alive: int = 0
var _hidden: Transform3D = Transform3D(Basis.from_scale(Vector3(1e-5, 1e-5, 1e-5)), Vector3(0, -100, 0))


func setup(p_capacity: int, mat: ShaderMaterial) -> void:
	capacity = p_capacity
	# Packed arrays are values: resize each member itself.
	_pos.resize(capacity)
	_vel.resize(capacity)
	_col.resize(capacity)
	_life.resize(capacity)
	_age.resize(capacity)
	_size.resize(capacity)
	_grow.resize(capacity)
	_drag.resize(capacity)
	_grav.resize(capacity)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = capacity
	for i: int in capacity:
		_age[i] = 1.0
		_life[i] = 0.0
		mm.set_instance_transform(i, _hidden)
		mm.set_instance_color(i, Color(0, 0, 0, 0))
	multimesh = mm
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Particles roam the whole level; never cull the batch by its (tiny) quad bounds.
	custom_aabb = AABB(Vector3(-1000, -50, -1000), Vector3(2000, 100, 2000))


## Emit one particle (scene coordinates). size in scene units; grow = size gain per second
## (relative); drag = velocity decay rate; gravity = downward acceleration.
func emit(x: float, y: float, z: float, vx: float, vy: float, vz: float, life: float, size: float,
		grow: float, color: Color, alpha: float, drag: float, gravity: float) -> void:
	if capacity == 0:
		return
	var i := _next
	_next = (_next + 1) % capacity
	if _age[i] >= _life[i]:
		_alive += 1
	_pos[i] = Vector3(x, y, z)
	_vel[i] = Vector3(vx, vy, vz)
	_col[i] = Color(color.r, color.g, color.b, alpha)
	_life[i] = maxf(0.01, life)
	_age[i] = 0.0
	_size[i] = size
	_grow[i] = grow
	_drag[i] = drag
	_grav[i] = gravity


func update_particles(dt: float) -> void:
	if _alive <= 0 or multimesh == null:
		return
	var mm := multimesh
	var alive := 0
	for i: int in capacity:
		if _age[i] >= _life[i]:
			continue
		_age[i] += dt
		if _age[i] >= _life[i]:
			mm.set_instance_transform(i, _hidden)
			mm.set_instance_color(i, Color(0, 0, 0, 0))
			continue
		alive += 1
		var v := _vel[i]
		v.y -= _grav[i] * dt
		v *= exp(-_drag[i] * dt)
		_vel[i] = v
		var p := _pos[i] + v * dt
		_pos[i] = p
		var k := _age[i] / _life[i]
		var s := _size[i] * (1.0 + _grow[i] * _age[i])
		var c := _col[i]
		var fade := 1.0 - k * k
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, s)), p))
		mm.set_instance_color(i, Color(c.r, c.g, c.b, c.a * fade))
	_alive = alive


func clear_particles() -> void:
	if multimesh == null:
		return
	for i: int in capacity:
		_age[i] = 1.0
		_life[i] = 0.0
		multimesh.set_instance_transform(i, _hidden)
		multimesh.set_instance_color(i, Color(0, 0, 0, 0))
	_alive = 0
