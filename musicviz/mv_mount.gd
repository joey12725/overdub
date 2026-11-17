class_name MVMount
extends RefCounted
## Puts visualiser textures into the 3D world: on a prop's screen surface, as a wall frieze, as a
## floor inscription, as a hologram. Plain MeshInstance3D quads with unshaded musicviz shaders — no
## physics bodies, no colliders, nothing the simulation can see (MUSIC-12, chapter 18).
## Coordinates are scene units (1 tile = 1 unit, Y up, floor top at Y = 0; RenderCtx.to_scene).

const SURFACE_SHADER := preload("res://musicviz/shaders/mv_surface.gdshader")
const HOLOGRAM_SHADER := preload("res://musicviz/shaders/mv_hologram.gdshader")
## Height of floor inscriptions above the floor top (clears floor_rune tiles at +0.01).
const FLOOR_LIFT := 0.014
## Offset of wall friezes off the wall face.
const WALL_LIFT := 0.012
## Wave-screen glass colour behind the waveform.
const SCREEN_GLASS := Color(0.02, 0.025, 0.04, 1.0)
## Warm-theme limits (see apply_theme).
const WARM_SURFACE_ENERGY := 1.05
const WARM_HOLOGRAM_ENERGY := 1.2
const WARM_HOLOGRAM_ADDITIVE := 0.0


## Surface material showing `tex` (an MVCanvas texture). uv_rect picks an atlas cell.
static func surface_material(tex: Texture2D, energy: float = 1.8, backdrop: Color = Color(0, 0, 0, 0), uv_rect: Rect2 = Rect2(0, 0, 1, 1), disc: bool = false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	m.set_shader_parameter(&"tex", tex)
	m.set_shader_parameter(&"energy", energy)
	m.set_shader_parameter(&"backdrop", backdrop)
	m.set_shader_parameter(&"uv_rect", Vector4(uv_rect.position.x, uv_rect.position.y, uv_rect.size.x, uv_rect.size.y))
	m.set_shader_parameter(&"disc_mask", 1.0 if disc else 0.0)
	return m


static func hologram_material(tex: Texture2D, energy: float = 2.2, tint: Color = Color.WHITE, additive: float = 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = HOLOGRAM_SHADER
	m.set_shader_parameter(&"tex", tex)
	m.set_shader_parameter(&"energy", energy)
	m.set_shader_parameter(&"tint", tint)
	m.set_shader_parameter(&"additive", additive)
	return m


## Theme treatment of a mounted material: in the dark depths the visualisers are light (bright
## cores, additive holograms) at `energy`; in the warm ruins they are inked inscriptions that must
## hold up on pale stone, so the bloom boost is capped and holograms are drawn mostly over the scene.
static func apply_theme(m: ShaderMaterial, style: MVStyle, energy: float, is_hologram: bool) -> void:
	var warm := style.kind == MVStyle.WARM
	if is_hologram:
		m.set_shader_parameter(&"energy", minf(energy, WARM_HOLOGRAM_ENERGY) if warm else energy)
		m.set_shader_parameter(&"additive", WARM_HOLOGRAM_ADDITIVE if warm else 1.0)
	else:
		m.set_shader_parameter(&"energy", minf(energy, WARM_SURFACE_ENERGY) if warm else energy)


## The mesh named "Screen" under a prop model (the wave_screen asset contract), or null.
static func find_screen(root: Node) -> MeshInstance3D:
	if root == null:
		return null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null and String(n.name).to_lower().begins_with("screen"):
			return mi
		for ch: Node in n.get_children():
			stack.append(ch)
	return null


## Applies `mat` to every surface of the prop's "Screen" mesh. Returns that mesh (null if the model
## has none — callers then fall back to a quad of their own).
static func on_screen(model_root: Node, mat: Material) -> MeshInstance3D:
	var mi := find_screen(model_root)
	if mi == null:
		return null
	for s: int in mi.mesh.get_surface_count():
		mi.set_surface_override_material(s, mat)
	return mi


static func _quiet(mi: MeshInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


## A vertical quad from `a` to `b` (floor points; their y is ignored), spanning y0..y0+height,
## facing `facing` (the side the camera sees), with the texture reading left to right for a viewer
## on that side.
static func wall_quad(parent: Node3D, a: Vector3, b: Vector3, y0: float, height: float, facing: Vector3, mat: Material) -> MeshInstance3D:
	var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length := along.length()
	var x := along / maxf(1e-6, length)
	var z := x.cross(Vector3.UP)
	var f := Vector3(facing.x, 0.0, facing.z)
	if z.dot(f) < 0.0:
		x = -x
		z = -z
	var q := QuadMesh.new()
	q.size = Vector2(length, height)
	var mi := MeshInstance3D.new()
	mi.name = "MVWallQuad"
	mi.mesh = q
	mi.material_override = mat
	_quiet(mi)
	var mid := (a + b) * 0.5
	mi.transform = Transform3D(Basis(x, Vector3.UP, z), Vector3(mid.x, y0 + height * 0.5, mid.z) + z * WALL_LIFT)
	parent.add_child(mi)
	return mi


## A flat disc decal of `radius` centred on floor point `centre` (y = floor top there).
static func floor_disc(parent: Node3D, centre: Vector3, radius: float, mat: Material, yaw: float = 0.0) -> MeshInstance3D:
	var p := PlaneMesh.new()
	p.size = Vector2(radius * 2.0, radius * 2.0)
	var mi := MeshInstance3D.new()
	mi.name = "MVFloorDisc"
	mi.mesh = p
	mi.material_override = mat
	_quiet(mi)
	mi.transform = Transform3D(Basis(Vector3.UP, yaw), centre + Vector3(0.0, FLOOR_LIFT, 0.0))
	parent.add_child(mi)
	return mi


## A flat strip lying on the floor from floor point `a` to `b`, `width` across, with the texture
## reading left to right for the isometric camera (which looks from the +X / +Z side, so screen right
## is +X / -Z on the floor) and its top edge away from the camera.
static func floor_strip(parent: Node3D, a: Vector3, b: Vector3, width: float, mat: Material) -> MeshInstance3D:
	var along := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length := along.length()
	var x := along / maxf(1e-6, length)
	if x.dot(Vector3(1.0, 0.0, -1.0)) < 0.0:
		x = -x
	var z := x.cross(Vector3.UP)
	var p := PlaneMesh.new()
	p.size = Vector2(length, width)
	var mi := MeshInstance3D.new()
	mi.name = "MVFloorStrip"
	mi.mesh = p
	mi.material_override = mat
	_quiet(mi)
	var mid := (a + b) * 0.5
	mi.transform = Transform3D(Basis(x, Vector3.UP, z), Vector3(mid.x, a.y + FLOOR_LIFT, mid.z))
	parent.add_child(mi)
	return mi


## A camera-facing hologram of `width` x `height` standing on floor point `base` (+ `lift`).
static func hologram(parent: Node3D, base: Vector3, width: float, height: float, mat: Material, lift: float = 0.1) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(width, height)
	var mi := MeshInstance3D.new()
	mi.name = "MVHologram"
	mi.mesh = q
	mi.material_override = mat
	_quiet(mi)
	mi.position = base + Vector3(0.0, lift + height * 0.5, 0.0)
	parent.add_child(mi)
	return mi
