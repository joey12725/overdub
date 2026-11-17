class_name WorldKit
extends RefCounted
## The environment kit from Blender (docs/GODOT-PORT.md "Asset contract"): assets/models/kit/<name>.glb
## listed in assets/models/kit/manifest.json as
##   { "pieces": { "<name>": { "file": "...", "themes": ["upper", ...], "size": [x, y, z] } } }
##
## Lookup order for a piece on a theme: `<name>__upper` / `<name>__lower` (the look that matches the
## theme; 'mid' picks per tile between the two, as the transition), then the unsuffixed `<name>`,
## then nothing - the caller builds its procedural stand-in (WorldBuilder / WorldDecor / mechs).
## Models are loaded at runtime by these names, so a piece that arrives later is picked up with no
## code change. Every model is re-materialed with ToonKit (base colours kept, `*_glow` emissive,
## ink outline).

const KIT_DIR := "res://assets/models/kit/"
const MANIFEST_PATH := "res://assets/models/kit/manifest.json"
## Share of 'mid' floor tiles that use the lower (metal) look.
const MID_METAL_SHARE := 0.3


## A kit piece as one mesh (all its mesh nodes merged, transforms baked), for MultiMesh use.
class Piece:
	extends RefCounted
	## Resolved manifest name (e.g. "wall__upper").
	var name: String = ""
	var path: String = ""
	var mesh: Mesh = null
	## Size from the manifest, else the merged mesh AABB size.
	var size: Vector3 = Vector3.ONE
	var aabb: AABB = AABB()
	## Emissive (`*_glow`) materials, for MusicReactive registration.
	var glow_materials: Array[ShaderMaterial] = []
	var glow_names: Array[String] = []


var theme: StringName = LevelTheme.UPPER
var ink: Color = ToonKit.INK
## Glow material name -> colour override applied to every kit piece (the core depth recolours the
## lower kit's magenta inscriptions and wall neon to its chronal amber / cyan; see glow_overrides()).
var glow_colors: Dictionary[String, Color] = {}
## name -> { file, themes, size } from the manifest (may be empty).
var manifest: Dictionary = {}
var _piece_cache: Dictionary = {}
var _scene_cache: Dictionary = {}
var _missing: Dictionary = {}


func _init(p_theme: StringName = LevelTheme.UPPER, p_ink: Color = ToonKit.INK, p_glow_colors: Dictionary[String, Color] = {}) -> void:
	theme = p_theme
	ink = p_ink
	glow_colors = p_glow_colors
	manifest = load_manifest()


## The manifest's piece table, or {} when the kit has not arrived yet.
static func load_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var errors: Array[String] = []
	var d: Variant = ODJson.read_file(MANIFEST_PATH, errors)
	if not (d is Dictionary):
		push_warning("WorldKit: unreadable manifest %s %s" % [MANIFEST_PATH, errors])
		return {}
	var pieces: Variant = (d as Dictionary).get("pieces", {})
	return pieces if pieces is Dictionary else {}


## Candidate names for a piece, best first: the theme variant whose manifest `themes` lists this
## theme, then the variant the theme maps to by default (upper/mid -> __upper, lower/core ->
## __lower, as the kit's LOOK_THEMES), then the unsuffixed name. On 'mid', when the manifest
## offers both looks for 'mid', `c`, `r` pick per tile so the transition mixes them.
func candidates(piece: String, c: int = 0, r: int = 0) -> Array[String]:
	var out: Array[String] = []
	var listed: Array[String] = []
	for look: String in ["__upper", "__lower"]:
		var entry: Variant = manifest.get(piece + look, null)
		if entry is Dictionary:
			var themes: Variant = (entry as Dictionary).get("themes", [])
			if themes is Array and (themes as Array).has(String(theme)):
				listed.append(piece + look)
	if listed.size() == 2 and WorldRng.tile_noise(0x6d1d, c, r) >= 0.5:
		listed.reverse()
	# 'mid' is the transition: the kit only lists the masonry look for it, so a seeded share of
	# floor tiles takes the lower look's metal plates (stone giving way to the machine below).
	if theme == LevelTheme.MID and piece.begins_with("floor_") and manifest.has(piece + "__lower") \
			and not listed.has(piece + "__lower") and WorldRng.tile_noise(0x3a71, c, r) < MID_METAL_SHARE:
		out.append(piece + "__lower")
	out.append_array(listed)
	var default_look := "__lower" if theme == LevelTheme.LOWER or theme == LevelTheme.CORE else "__upper"
	if not out.has(piece + default_look):
		out.append(piece + default_look)
	out.append(piece)
	return out


## Resource path of a candidate name, or "" when it does not exist.
func path_of(name: String) -> String:
	var file := name + ".glb"
	var entry: Variant = manifest.get(name, null)
	if entry is Dictionary and (entry as Dictionary).has("file"):
		file = str((entry as Dictionary)["file"])
	var path := file if file.begins_with("res://") else KIT_DIR + file
	return path if ResourceLoader.exists(path) else ""


## The resolved model path for a piece on this theme ("" = no model: use the stand-in).
func resolve(piece: String, c: int = 0, r: int = 0) -> String:
	for n: String in candidates(piece, c, r):
		var p := path_of(n)
		if not p.is_empty():
			return p
	return ""


func has_model(piece: String) -> bool:
	return not resolve(piece).is_empty()


## The piece merged into one re-materialed mesh, or null when no model exists (stand-in time).
func piece(piece_name: String, c: int = 0, r: int = 0) -> Piece:
	var path := resolve(piece_name, c, r)
	if path.is_empty():
		return null
	if _piece_cache.has(path):
		return _piece_cache[path]
	var scene := _load_scene(path)
	if scene == null:
		return null
	var p := _merge(scene, path)
	_piece_cache[path] = p
	return p


## A re-materialed instance of the piece's scene (named parts kept: Frame/Panel, Base/Lever...),
## or null when no model exists. The caller owns the node.
func instance(piece_name: String, c: int = 0, r: int = 0, opts: ToonKit.Options = null) -> Node3D:
	var path := resolve(piece_name, c, r)
	if path.is_empty():
		return null
	var scene := _load_scene(path)
	if scene == null:
		return null
	var n := scene.instantiate() as Node3D
	if n == null:
		return null
	if opts == null:
		opts = ToonKit.Options.new()
		opts.outline_color = ink
	opts.layers = WorldBuilder.ENV_LAYER
	_recolor(ToonKit.apply_toon(n, opts))
	return n


## Size from the manifest entry of the resolved piece (or Vector3.ZERO when unknown).
func manifest_size(name: String) -> Vector3:
	var entry: Variant = manifest.get(name, null)
	if entry is Dictionary:
		var s: Variant = (entry as Dictionary).get("size", null)
		if s is Array and (s as Array).size() == 3:
			return Vector3(float(s[0]), float(s[1]), float(s[2]))
	return Vector3.ZERO


## Kit glow recolours for a theme's palette ({} = keep the authored colours).
static func glow_overrides(pal: WorldPalette) -> Dictionary[String, Color]:
	var out: Dictionary[String, Color] = {}
	if pal.theme == LevelTheme.CORE:
		out["rune_glow"] = pal.rune
		out["neon_pink_glow"] = pal.neon_a
		out["neon_violet_glow"] = pal.neon_c
	return out


func _recolor(made: Dictionary[String, ShaderMaterial]) -> void:
	if glow_colors.is_empty():
		return
	for k: String in made:
		var m := made[k]
		if glow_colors.has(k) and m.shader == ToonKit.GLOW_SHADER:
			m.set_shader_parameter(&"color", glow_colors[k])


func _load_scene(path: String) -> PackedScene:
	if _scene_cache.has(path):
		return _scene_cache[path]
	var res: Resource = load(path)
	var scene := res as PackedScene
	if scene == null:
		if not _missing.has(path):
			push_warning("WorldKit: %s is not a scene" % path)
			_missing[path] = true
		return null
	_scene_cache[path] = scene
	return scene


func _merge(scene: PackedScene, path: String) -> Piece:
	var root := scene.instantiate()
	var tools: Dictionary = {}
	var materials: Dictionary = {}
	var order: Array[String] = []
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var n: Node = item[0]
		var xf: Transform3D = item[1]
		for ch: Node in n.get_children():
			var cx := xf
			if ch is Node3D:
				cx = xf * (ch as Node3D).transform
			stack.append([ch, cx])
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		for s: int in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.get_surface_override_material(s)
			if mat == null:
				mat = mi.mesh.surface_get_material(s)
			var key := ToonKit.material_name(mat)
			if not tools.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = st
				materials[key] = mat
				order.append(key)
			(tools[key] as SurfaceTool).append_from(mi.mesh, s, xf)
	root.free()
	var merged := ArrayMesh.new()
	for key: String in order:
		(tools[key] as SurfaceTool).commit(merged)
		merged.surface_set_material(merged.get_surface_count() - 1, materials[key])
	# Re-material through a throwaway MeshInstance3D so the same pass as instance() applies.
	var holder := MeshInstance3D.new()
	holder.mesh = merged
	var opts := ToonKit.Options.new()
	opts.outline_color = ink
	var made := ToonKit.apply_toon(holder, opts)
	_recolor(made)
	var final_mesh: Mesh = holder.mesh
	for s: int in range(final_mesh.get_surface_count()):
		var sm := holder.get_surface_override_material(s) as ShaderMaterial
		# Without vertex colours, COLOR carries only the MultiMesh instance tint (shade / AO): use it.
		if sm != null and ToonKit.is_toon(sm) and (final_mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_COLOR) == 0:
			sm.set_shader_parameter(&"vertex_color_mix", 1.0)
		final_mesh.surface_set_material(s, sm)
	holder.free()
	var p := Piece.new()
	p.path = path
	p.name = path.get_file().get_basename()
	p.mesh = final_mesh
	p.aabb = final_mesh.get_aabb()
	var ms := manifest_size(p.name)
	p.size = ms if ms != Vector3.ZERO else p.aabb.size
	for k: String in made:
		if k.ends_with("_glow"):
			p.glow_materials.append(made[k])
			p.glow_names.append(k)
	return p
