class_name ActorRig
extends Node3D
## One animated character instance (Moxie or an enemy): the model scene from assets/models/** (or
## its clearly-temporary stand-in while the file is missing), its Skeleton3D, an exact clip sampler
## over its AnimationPlayer, and the actor materials swapped in by contract material name.
##
## Material styling (docs/GODOT-PORT.md asset contract): each surface's imported material name picks
## its shared ActorMaterials pair; names ending in "_glow" are emissive; `accent_names` are recoloured
## per instance (cassette colour on the headphone glow, state colour on an enemy optic); `tints`
## replace the base colour of named materials (gear looks: top, pants, shoes).

var model: Node3D = null
var skeleton: Skeleton3D = null
var player: AnimationPlayer = null
var sampler: ActorClipSampler = null
var meshes: Array[MeshInstance3D] = []
## True when the stand-in is shown because the model file does not exist (yet).
var is_standin: bool = false
## Height of the model's bounds (for markers above the head).
var top: float = 1.0
## Model bounds in rig space (rest pose).
var bounds: AABB = AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 1, 1))
var translucent: bool = false

var _xray_volume: Vector4 = Vector4(0, 0, 0.45, 1.3)
var _solid: Array[Array] = []
var _fx: Array[Array] = []


static func model_exists(path: String) -> bool:
	return ResourceLoader.exists(path)


## Instance the model at `path`, or `standin` (a Callable returning a Node3D) when it is missing.
func setup(path: String, standin: Callable) -> void:
	var scene: PackedScene = null
	if model_exists(path):
		scene = load(path) as PackedScene
	if scene != null:
		model = scene.instantiate() as Node3D
	if model == null:
		model = standin.call() as Node3D
		is_standin = true
	add_child(model)
	var skels := model.find_children("*", "Skeleton3D", true, false)
	skeleton = skels[0] as Skeleton3D if skels.size() > 0 else null
	var players := model.find_children("*", "AnimationPlayer", true, false)
	player = players[0] as AnimationPlayer if players.size() > 0 else null
	if player != null:
		# The clips are sampled, never played: keep the player inert.
		player.stop()
		player.active = false
	sampler = ActorClipSampler.new(skeleton, player)
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		meshes.append(n as MeshInstance3D)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		var b := mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	top = maxf(0.3, box.end.y) if not first else 1.0
	if not first:
		bounds = box


## Radius of the vertical cylinder that bounds this model for the x-ray test (actor_xray.gdshader):
## its own layers (pigtails behind the face, an arm across the chest) lie inside it and never trigger
## the silhouette, while a wall in front of it does. The rest pose's width is not used directly (a
## T-pose's arms would inflate it): at most twice the depth.
func xray_radius() -> float:
	return clampf(maxf(bounds.size.z * 0.5, minf(bounds.size.x, bounds.size.z * 2.0) * 0.5) + 0.08, 0.3, 1.2)


## Move the x-ray volume to the actor's floor position (world space); call once per frame.
func update_xray(world_pos: Vector3) -> void:
	_xray_volume.x = world_pos.x
	_xray_volume.y = world_pos.z
	_xray_volume.w = world_pos.y + top + 0.3
	set_param(&"xray_volume", _xray_volume)


## Include the meshes under `node` (an attached weapon or headgear) in this rig's styling: call
## before apply_materials().
func adopt(node: Node) -> void:
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for n: Node in node.find_children("*", "MeshInstance3D", true, false):
		meshes.append(n as MeshInstance3D)


## Name of a surface's material (the asset contract's styling hook).
static func surface_material_name(mi: MeshInstance3D, i: int) -> StringName:
	var m := mi.get_active_material(i)
	if m != null and not m.resource_name.is_empty():
		return StringName(m.resource_name)
	if mi.mesh != null:
		return StringName(mi.mesh.surface_get_name(i))
	return &""


static func _base_texture(mi: MeshInstance3D, i: int) -> Texture2D:
	var m := mi.get_active_material(i)
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).albedo_texture
	return null


## True when the imported material is double-sided (an open sheet: a face plane, hair cards).
static func _double_sided(mi: MeshInstance3D, i: int) -> bool:
	var m := mi.get_active_material(i)
	return m is BaseMaterial3D and (m as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED


static func _base_color(mi: MeshInstance3D, i: int) -> Color:
	var m := mi.get_active_material(i)
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).albedo_color
	return Color(0.8, 0.8, 0.8)


## Swap every surface to the shared actor materials. Surfaces whose material is in `hidden_names`
## are not drawn (the model's own wrist device under a worn ranged weapon).
## `identity`: selves get the two-tier outline (ink line + cassette-coloured hull). `zones`: outfit
## zone tints for the single-texture body material they name.
func apply_materials(mats: ActorMaterials, tints: Dictionary[StringName, Color], accent_names: Array[StringName], hidden_names: Array[StringName] = [],
		identity: bool = false, zones: ActorMaterials.Zones = null) -> void:
	_solid.clear()
	_fx.clear()
	for mi: MeshInstance3D in meshes:
		var solid: Array[Material] = []
		var fx: Array[Material] = []
		if mi.mesh != null:
			for i: int in mi.mesh.get_surface_count():
				var mat_name := surface_material_name(mi, i)
				if hidden_names.has(mat_name):
					solid.append(mats.hidden)
					fx.append(mats.hidden)
					continue
				var col: Color = tints.get(mat_name, _base_color(mi, i))
				var glow := String(mat_name).ends_with("_glow")
				# A gear tint replaces the colour outright; otherwise keep the imported texture too.
				var tex: Texture2D = null if tints.has(mat_name) else _base_texture(mi, i)
				var z: ActorMaterials.Zones = zones if zones != null and zones.material == mat_name else null
				var pair := mats.body_pair(col, glow, accent_names.has(mat_name), tex, _double_sided(mi, i), identity, z)
				solid.append(pair[0])
				fx.append(pair[1])
		_solid.append(solid)
		_fx.append(fx)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_xray_volume.z = xray_radius()
		mi.set_instance_shader_parameter(&"xray_volume", _xray_volume)
	translucent = true
	set_translucent(false)


## Swap between the opaque and translucent material twins (only when the state changes).
func set_translucent(on: bool) -> void:
	if on == translucent:
		return
	translucent = on
	for k: int in meshes.size():
		var mi := meshes[k]
		var list: Array[Material] = []
		list.assign(_fx[k] if on else _solid[k])
		for i: int in list.size():
			mi.set_surface_override_material(i, list[i])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Set an instance uniform on every mesh of the rig.
func set_param(param: StringName, value: Variant) -> void:
	for mi: MeshInstance3D in meshes:
		mi.set_instance_shader_parameter(param, value)


## Mesh object by node name (e.g. the shielder's "Shield", the boss's "Armor_1"), or null.
func find_mesh(object_name: String) -> MeshInstance3D:
	for mi: MeshInstance3D in meshes:
		if mi.name == object_name:
			return mi
	return null
