class_name FxSpriteRenderer
extends MultiMeshInstance3D
## GPU side of an FxSpritePool: one MultiMesh of unit quads whose shader draws every procedural
## shape (fx/shaders/fx_sprite.gdshaderinc). The buffer is allocated once at full pool capacity and
## refilled in place every frame; only the live prefix is drawn (visible_instance_count).

const SHADER_GLOW := preload("res://fx/shaders/fx_sprite_glow.gdshader")
const SHADER_INK := preload("res://fx/shaders/fx_sprite_ink.gdshader")

var _buf := PackedFloat32Array()
var _mm: MultiMesh
## Instances drawn last frame (diagnostics / tests).
var drawn: int = 0


func setup(capacity: int, additive: bool, priority: int) -> void:
	name = "FxGlow" if additive else "FxInk"
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = false
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_mm.mesh = quad
	_mm.instance_count = capacity
	_mm.visible_instance_count = 0
	multimesh = _mm
	_buf.resize(capacity * FxSpritePool.STRIDE)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_GLOW if additive else SHADER_INK
	# Ink draws under the glow; both under the readouts.
	mat.render_priority = priority
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Instance transforms carry packed data, not real placements: culling sees the whole world.
	custom_aabb = AABB(Vector3(-512.0, -64.0, -512.0), Vector3(1024.0, 128.0, 1024.0))
	# The shader reads MODEL_MATRIX as raw data, so this node must sit at the identity.
	top_level = true
	transform = Transform3D.IDENTITY


func sync(pool: FxSpritePool) -> void:
	if _mm == null:
		return
	var n := pool.write_instances(_buf)
	drawn = n
	if n > 0:
		_mm.buffer = _buf
	_mm.visible_instance_count = n
	visible = n > 0
