class_name FxWordRenderer
extends MultiMeshInstance3D
## World-space combat readouts: an FxTextPool drawn as one MultiMesh of camera-facing quads that
## sample the FxWordAtlas (fx/shaders/fx_word.gdshader). Readouts ignore depth so they stay legible
## over walls and props, and draw after every other effect.

const SHADER := preload("res://fx/shaders/fx_word.gdshader")

var atlas: FxWordAtlas
var _buf := PackedFloat32Array()
var _mm: MultiMesh
var _mat: ShaderMaterial
var drawn: int = 0


func setup(capacity: int, p_atlas: FxWordAtlas, ink: Color) -> void:
	name = "FxWords"
	atlas = p_atlas
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_mm.mesh = quad
	_mm.instance_count = capacity
	_mm.visible_instance_count = 0
	multimesh = _mm
	_buf.resize(capacity * FxTextPool.STRIDE)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.render_priority = 20
	_mat.set_shader_parameter("ink", ink)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-512.0, -64.0, -512.0), Vector3(1024.0, 128.0, 1024.0))
	top_level = true
	transform = Transform3D.IDENTITY
	if atlas.texture != null:
		_on_atlas(atlas.texture)
	else:
		atlas.ready_atlas.connect(_on_atlas)


func _on_atlas(tex: Texture2D) -> void:
	_mat.set_shader_parameter("atlas", tex)


func has_texture() -> bool:
	return atlas != null and atlas.texture != null


func sync(pool: FxTextPool) -> void:
	if _mm == null:
		return
	if not has_texture():
		visible = false
		drawn = 0
		return
	var n := pool.write_instances(_buf, atlas.rects, atlas.aspects)
	drawn = n
	if n > 0:
		_mm.buffer = _buf
	_mm.visible_instance_count = n
	visible = n > 0
