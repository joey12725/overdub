class_name FeelBursts
extends Node3D
## Pooled one-quad effects of the feel layer: camera-facing impact bursts (shaders/impact.gdshader)
## and flat world marks (shaders/decal.gdshader). All state is per-instance shader parameters on two
## shared materials, so a burst costs one draw and no allocation.

const KIND_HIT: int = 0
const KIND_CLANG: int = 1
const KIND_DUST: int = 2
const KIND_NEAR_MISS: int = 3
const KIND_KILL: int = 4
const DECAL_CRACK: int = 0
const DECAL_SKID: int = 1

const BURSTS: int = 28
const DECALS: int = 14

var _burst: Array[MeshInstance3D] = []
var _burst_t: PackedFloat32Array = PackedFloat32Array()
var _burst_life: PackedFloat32Array = PackedFloat32Array()
var _decal: Array[MeshInstance3D] = []
var _decal_t: PackedFloat32Array = PackedFloat32Array()
var _decal_life: PackedFloat32Array = PackedFloat32Array()
var _next_burst: int = 0
var _next_decal: int = 0
var _seed: float = 0.0
## Largest burst diameter (tiles) and tier allowed. CombatFeel lowers both under "reduce flashing"
## (docs/ACCESSIBILITY.md 6.2): a crush burst is otherwise a bright flash over a tenth of the screen.
var max_size: float = INF
var max_tier: int = 4


func _init() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var bm := ShaderMaterial.new()
	bm.shader = load("res://feel/shaders/impact.gdshader")
	bm.render_priority = 20
	var dm := ShaderMaterial.new()
	dm.shader = load("res://feel/shaders/decal.gdshader")
	dm.render_priority = 2
	for i: int in BURSTS:
		var mi := _make(quad, bm, "Burst%d" % i)
		# The shader places the quad in view space; keep its flat AABB from being frustum-culled.
		mi.extra_cull_margin = 4.0
		_burst.append(mi)
	for i: int in DECALS:
		_decal.append(_make(quad, dm, "Decal%d" % i))
	_burst_t.resize(BURSTS)
	_burst_life.resize(BURSTS)
	_decal_t.resize(DECALS)
	_decal_life.resize(DECALS)


func _make(mesh: Mesh, mat: Material, n: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


## Spawn a burst at scene position `at`. `screen_angle` is the hit direction on screen (radians).
func burst(kind: int, at: Vector3, size: float, life: float, tier: int, screen_angle: float, tint: Color, lines: int = 8) -> void:
	var i := _next_burst
	_next_burst = (_next_burst + 1) % BURSTS
	_seed = fmod(_seed + 0.6180339, 1.0)
	var mi := _burst[i]
	mi.transform = Transform3D(Basis.from_scale(Vector3.ONE * minf(size, max_size)), at)
	mi.set_instance_shader_parameter(&"progress", 0.0)
	mi.set_instance_shader_parameter(&"kind", float(kind))
	mi.set_instance_shader_parameter(&"tier", float(mini(tier, max_tier)))
	mi.set_instance_shader_parameter(&"angle", screen_angle)
	mi.set_instance_shader_parameter(&"seed", _seed * 10.0)
	mi.set_instance_shader_parameter(&"tint", tint)
	mi.set_instance_shader_parameter(&"lines", float(lines))
	mi.visible = true
	_burst_t[i] = 0.0
	_burst_life[i] = maxf(life, 0.02)


## Spawn a flat mark: `xform` places a unit quad (its local XY plane is the mark; +X is "along").
func decal(kind: int, xform: Transform3D, life: float, power: float = 1.0) -> void:
	var i := _next_decal
	_next_decal = (_next_decal + 1) % DECALS
	_seed = fmod(_seed + 0.6180339, 1.0)
	var mi := _decal[i]
	mi.transform = xform
	mi.set_instance_shader_parameter(&"progress", 0.0)
	mi.set_instance_shader_parameter(&"kind", float(kind))
	mi.set_instance_shader_parameter(&"seed", _seed * 10.0)
	mi.set_instance_shader_parameter(&"power", power)
	mi.visible = true
	_decal_t[i] = 0.0
	_decal_life[i] = maxf(life, 0.02)


func advance(dt: float) -> void:
	for i: int in BURSTS:
		if not _burst[i].visible:
			continue
		_burst_t[i] += dt
		var p := _burst_t[i] / _burst_life[i]
		if p >= 1.0:
			_burst[i].visible = false
		else:
			_burst[i].set_instance_shader_parameter(&"progress", p)
	for i: int in DECALS:
		if not _decal[i].visible:
			continue
		_decal_t[i] += dt
		var p := _decal_t[i] / _decal_life[i]
		if p >= 1.0:
			_decal[i].visible = false
		else:
			_decal[i].set_instance_shader_parameter(&"progress", p)


func clear() -> void:
	for mi: MeshInstance3D in _burst:
		mi.visible = false
	for mi: MeshInstance3D in _decal:
		mi.visible = false


func active_bursts() -> int:
	var n := 0
	for mi: MeshInstance3D in _burst:
		if mi.visible:
			n += 1
	return n
