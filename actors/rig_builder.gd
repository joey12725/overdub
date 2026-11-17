class_name ActorRigBuilder
extends RefCounted
## Builds clearly-temporary stand-in characters from primitives, shaped exactly like an imported
## Blender .glb: a Skeleton3D with named bones, skinned MeshInstance3D objects whose surface
## materials carry the asset-contract material names (resource_name), and an AnimationPlayer whose
## clips use the contract's animation names with bone tracks "Skeleton3D:<bone>". Everything that
## drives the real model (ActorRig, ActorClipSampler, material swaps by name) therefore runs
## unchanged on a stand-in. Used only while assets/models/** files are missing.

class Part:
	extends RefCounted
	var bone: int = 0
	var arrays: Array = []
	var xform: Transform3D = Transform3D.IDENTITY
	var material: StringName = &""
	var object: StringName = &"Body"


var _names: Array[StringName] = []
var _parents: PackedInt32Array = PackedInt32Array()
var _rest: Array[Transform3D] = []
var _parts: Array[Part] = []
var _colors: Dictionary[StringName, Color] = {}


## Add a bone at `pos` relative to its parent (rest rotation identity). Returns its index.
func bone(bone_name: StringName, parent: StringName, pos: Vector3) -> int:
	_names.append(bone_name)
	_parents.append(_names.find(parent) if parent != &"" else -1)
	_rest.append(Transform3D(Basis.IDENTITY, pos))
	return _names.size() - 1


## Declare the base colour of a material name.
func material(mat: StringName, color: Color) -> void:
	_colors[mat] = color


## Attach a primitive to a bone (transform relative to the bone) in a material, inside mesh object
## `object` (separate MeshInstance3D nodes, e.g. the shielder's "Shield").
func part(bone_name: StringName, mesh: PrimitiveMesh, mat: StringName, pos: Vector3 = Vector3.ZERO,
		rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, object: StringName = &"Body") -> void:
	var p := Part.new()
	p.bone = _names.find(bone_name)
	if p.bone < 0:
		push_error("ActorRigBuilder: unknown bone %s" % bone_name)
		return
	p.arrays = mesh.get_mesh_arrays()
	p.xform = Transform3D(Basis.from_euler(rot, EULER_ORDER_XYZ) * Basis.from_scale(scl), pos)
	p.material = mat
	p.object = object
	_parts.append(p)


func bone_count() -> int:
	return _names.size()


func bone_names() -> Array[StringName]:
	return _names.duplicate()


func global_rest(i: int) -> Transform3D:
	var t := _rest[i]
	var p := _parents[i]
	while p >= 0:
		t = _rest[p] * t
		p = _parents[p]
	return t


## Build the node tree: <root_name> (Node3D) / Skeleton3D / <object> (MeshInstance3D) ...,
## plus an AnimationPlayer child of the root (empty library "" for the caller to fill).
func build(root_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = root_name
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	root.add_child(skel)
	for i: int in _names.size():
		skel.add_bone(String(_names[i]))
	for i: int in _names.size():
		if _parents[i] >= 0:
			skel.set_bone_parent(i, _parents[i])
		skel.set_bone_rest(i, _rest[i])
		skel.set_bone_pose_position(i, _rest[i].origin)
		skel.set_bone_pose_rotation(i, Quaternion.IDENTITY)
		skel.set_bone_pose_scale(i, Vector3.ONE)
	var globals: Array[Transform3D] = []
	for i: int in _names.size():
		globals.append(global_rest(i))
	var skin := Skin.new()
	for i: int in _names.size():
		skin.add_named_bind(String(_names[i]), globals[i].affine_inverse())
	# Group parts by object, then material.
	var objects: Array[StringName] = []
	for p: Part in _parts:
		if not objects.has(p.object):
			objects.append(p.object)
	for obj: StringName in objects:
		var mats: Array[StringName] = []
		for p: Part in _parts:
			if p.object == obj and not mats.has(p.material):
				mats.append(p.material)
		var mesh := ArrayMesh.new()
		for mat: StringName in mats:
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var uvs := PackedVector2Array()
			var bones := PackedInt32Array()
			var weights := PackedFloat32Array()
			var idx := PackedInt32Array()
			for p: Part in _parts:
				if p.object != obj or p.material != mat:
					continue
				var xf := globals[p.bone] * p.xform
				var nb := xf.basis.inverse().transposed()
				var pv: PackedVector3Array = p.arrays[Mesh.ARRAY_VERTEX]
				var pn: PackedVector3Array = p.arrays[Mesh.ARRAY_NORMAL]
				var pu: Variant = p.arrays[Mesh.ARRAY_TEX_UV]
				var pi: PackedInt32Array = p.arrays[Mesh.ARRAY_INDEX]
				var base := verts.size()
				for v: int in pv.size():
					verts.append(xf * pv[v])
					norms.append((nb * pn[v]).normalized())
					uvs.append((pu as PackedVector2Array)[v] if pu is PackedVector2Array else Vector2.ZERO)
					bones.append_array([p.bone, 0, 0, 0])
					weights.append_array([1.0, 0.0, 0.0, 0.0])
				for k: int in pi.size():
					idx.append(base + pi[k])
			var arr: Array = []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_NORMAL] = norms
			arr[Mesh.ARRAY_TEX_UV] = uvs
			arr[Mesh.ARRAY_BONES] = bones
			arr[Mesh.ARRAY_WEIGHTS] = weights
			arr[Mesh.ARRAY_INDEX] = idx
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var si := mesh.get_surface_count() - 1
			mesh.surface_set_name(si, String(mat))
			var m := StandardMaterial3D.new()
			m.resource_name = String(mat)
			m.albedo_color = _colors.get(mat, Color(0.8, 0.8, 0.8))
			mesh.surface_set_material(si, m)
		var mi := MeshInstance3D.new()
		mi.name = String(obj)
		mi.mesh = mesh
		mi.skin = skin
		skel.add_child(mi)
		mi.skeleton = NodePath("..")
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	player.add_animation_library(&"", AnimationLibrary.new())
	return root


## Recursively set the owner of every descendant (so the tree can be packed / duplicated whole).
static func own(root: Node, node: Node) -> void:
	for c: Node in node.get_children():
		c.owner = root
		own(root, c)


## A clip under construction: one rotation track per bone, plus position/scale tracks for the bones
## listed in `moving` (rest + offset is keyed, as the glTF importer does).
class ClipBake:
	extends RefCounted
	var anim: Animation = Animation.new()
	var _rot: Dictionary[int, int] = {}
	var _pos: Dictionary[int, int] = {}
	var _scl: Dictionary[int, int] = {}
	var _rest: Array[Transform3D] = []

	func _init(length: float, loop: bool, builder: ActorRigBuilder, moving: Array[StringName]) -> void:
		anim.length = length
		anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		var names := builder.bone_names()
		for i: int in names.size():
			_rest.append(builder._rest[i])
			var tr := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(tr, NodePath("Skeleton3D:" + String(names[i])))
			_rot[i] = tr
			if moving.has(names[i]):
				var tp := anim.add_track(Animation.TYPE_POSITION_3D)
				anim.track_set_path(tp, NodePath("Skeleton3D:" + String(names[i])))
				_pos[i] = tp
				var ts := anim.add_track(Animation.TYPE_SCALE_3D)
				anim.track_set_path(ts, NodePath("Skeleton3D:" + String(names[i])))
				_scl[i] = ts

	## Key bone `i` at time t: euler rotation (XYZ order), position offset from rest, scale.
	func key(i: int, t: float, euler: Vector3, offset: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> void:
		anim.rotation_track_insert_key(_rot[i], t, Basis.from_euler(euler, EULER_ORDER_XYZ).get_rotation_quaternion())
		if _pos.has(i):
			anim.position_track_insert_key(_pos[i], t, _rest[i].origin + offset)
			anim.scale_track_insert_key(_scl[i], t, scl)
