class_name FeelGhosts
extends Node3D
## Afterimages: frozen cut-outs of the current pose of a body (dodge i-frames, fast-tape swings).
## A ghost is the meshes of the body baked at their current skeleton pose, drawn with
## shaders/ghost.gdshader in the cassette colour, living FeelTune.GHOST_LIFE seconds.

const MAX_MESHES: int = 48

var _mat: ShaderMaterial = null
var _pool: Array[MeshInstance3D] = []
var _t: PackedFloat32Array = PackedFloat32Array()
var _life: PackedFloat32Array = PackedFloat32Array()
var _next: int = 0


func _init() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://feel/shaders/ghost.gdshader")
	_mat.render_priority = 1
	_t.resize(MAX_MESHES)
	_life.resize(MAX_MESHES)
	for i: int in MAX_MESHES:
		var mi := MeshInstance3D.new()
		mi.name = "Ghost%d" % i
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_pool.append(mi)


## Freeze a copy of every visible mesh under `body`. Returns how many meshes were ghosted.
func spawn(body: Node3D, tint: Color, life: float = FeelTune.GHOST_LIFE, opacity: float = 0.6) -> int:
	if body == null or not is_inside_tree():
		return 0
	var n := 0
	for c: Node in body.find_children("*", "MeshInstance3D", true, false):
		var src := c as MeshInstance3D
		if src == null or not src.is_visible_in_tree() or src.mesh == null:
			continue
		var mesh := bake_pose(src)
		if mesh == null:
			continue
		var i := _next
		_next = (_next + 1) % MAX_MESHES
		var g := _pool[i]
		g.mesh = mesh
		g.global_transform = src.global_transform
		g.set_instance_shader_parameter(&"tint", tint)
		g.set_instance_shader_parameter(&"life", 0.0)
		g.set_instance_shader_parameter(&"opacity", opacity)
		g.visible = true
		_t[i] = 0.0
		_life[i] = maxf(0.03, life)
		n += 1
	return n


## `src`'s mesh frozen at its current skeleton pose (vertices in `src`'s own space). The engine
## bakes it when the skin is registered with a renderer skeleton. It is not under the headless
## renderer (no skeleton RIDs: MeshInstance3D.bake_mesh_from_current_skeleton_pose() then raises
## "skin registered with a valid skeleton") nor while the skeleton path is unresolved; the pose is
## then skinned here from the Skeleton3D itself, so the ghost is the same cut-out either way.
## Falls back to the rest-pose mesh when there is nothing to skin with.
static func bake_pose(src: MeshInstance3D) -> Mesh:
	if src == null or src.mesh == null:
		return null
	if src.skin == null or not (src.mesh is ArrayMesh):
		return src.mesh
	var ref := src.get_skin_reference() if src.is_inside_tree() else null
	if ref != null and ref.get_skeleton().is_valid():
		var baked: Mesh = src.bake_mesh_from_current_skeleton_pose()
		if baked != null:
			return baked
	var skel := skeleton_of(src)
	if skel == null:
		return src.mesh
	var posed := skin_on_cpu(src.mesh as ArrayMesh, src.skin, skel)
	return posed if posed != null else src.mesh


## The Skeleton3D that deforms `src`: its skeleton path, else the nearest Skeleton3D ancestor (a
## mesh copied or re-parented under the rig keeps working when its path no longer resolves).
static func skeleton_of(src: MeshInstance3D) -> Skeleton3D:
	if src.is_inside_tree() and not src.skeleton.is_empty():
		var by_path := src.get_node_or_null(src.skeleton) as Skeleton3D
		if by_path != null:
			return by_path
	var n: Node = src.get_parent()
	while n != null:
		if n is Skeleton3D:
			return n as Skeleton3D
		n = n.get_parent()
	return null


## Linear-blend skinning of `mesh` by `skel`'s current pose through `skin` (positions and normals;
## the ghost shader needs nothing else). Null when no surface carries bone weights.
static func skin_on_cpu(mesh: ArrayMesh, skin: Skin, skel: Skeleton3D) -> ArrayMesh:
	var mats: Array[Transform3D] = []
	for i: int in skin.get_bind_count():
		var bone := skin.get_bind_bone(i)
		var bind_name := skin.get_bind_name(i)
		if bind_name != &"":
			bone = skel.find_bone(bind_name)
		if bone < 0 or bone >= skel.get_bone_count():
			mats.append(Transform3D.IDENTITY)
		else:
			mats.append(skel.get_bone_global_pose(bone) * skin.get_bind_pose(i))
	if mats.is_empty():
		return null
	var out := ArrayMesh.new()
	for s: int in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(s)
		if arrays.size() <= Mesh.ARRAY_WEIGHTS or arrays[Mesh.ARRAY_VERTEX] == null or arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights := PackedFloat32Array(arrays[Mesh.ARRAY_WEIGHTS])
		var n := verts.size()
		if n == 0 or bones.size() % n != 0 or weights.size() != bones.size():
			continue
		var per := bones.size() / n
		var has_normals: bool = arrays[Mesh.ARRAY_NORMAL] != null
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if has_normals else PackedVector3Array()
		var count := mats.size()
		for v: int in n:
			var p := Vector3.ZERO
			var nm := Vector3.ZERO
			var total := 0.0
			var src_p := verts[v]
			var o := v * per
			for k: int in per:
				var w := weights[o + k]
				if w <= 0.0:
					continue
				var b := bones[o + k]
				if b < 0 or b >= count:
					continue
				var m := mats[b]
				p += (m * src_p) * w
				if has_normals:
					nm += (m.basis * normals[v]) * w
				total += w
			if total > 0.0:
				verts[v] = p / total
				if has_normals:
					normals[v] = nm.normalized()
		var made: Array = []
		made.resize(Mesh.ARRAY_MAX)
		made[Mesh.ARRAY_VERTEX] = verts
		if has_normals:
			made[Mesh.ARRAY_NORMAL] = normals
		made[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, made)
	return out if out.get_surface_count() > 0 else null


func advance(dt: float) -> void:
	for i: int in MAX_MESHES:
		var g := _pool[i]
		if not g.visible:
			continue
		_t[i] += dt
		var p := _t[i] / _life[i]
		if p >= 1.0:
			g.visible = false
			g.mesh = null
		else:
			g.set_instance_shader_parameter(&"life", p)


func clear() -> void:
	for g: MeshInstance3D in _pool:
		g.visible = false
		g.mesh = null


func active() -> int:
	var n := 0
	for g: MeshInstance3D in _pool:
		if g.visible:
			n += 1
	return n
