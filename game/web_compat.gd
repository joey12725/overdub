class_name WebCompat
## Adjustments for the web (Compatibility renderer) build, applied once at start-up before any level
## is built. Desktop builds are untouched.
##
## The Compatibility renderer keeps instance uniforms in one buffer of 4,096 slots and reserves 16 per
## instance, so at most 256 objects in a scene may use them; a level has far more (tiles, props,
## actor hulls, afterimages, impacts), and past the limit objects lose their material. On the web
## every instance uniform therefore becomes an ordinary material uniform with the same default, and
## code that sets a per-object value goes through set_param(), which gives that object its own copy
## of its materials and sets the value there. Desktop builds keep real instance uniforms.

## Every shader with instance uniforms (directly or through an include below).
const WORLD_SHADERS: Array[String] = [
	"res://shaders/world_surface.gdshader",
	"res://shaders/outline.gdshader",
	"res://shaders/glow.gdshader",
	"res://shaders/glow_add.gdshader",
	"res://shaders/blob_shadow.gdshader",
	"res://shaders/xray.gdshader",
	"res://shaders/toon.gdshader",
	"res://shaders/toon_cutout.gdshader",
	"res://actors/shaders/actor_echo.gdshader",
	"res://actors/shaders/actor_ink.gdshader",
	"res://actors/shaders/actor_outline.gdshader",
	"res://actors/shaders/actor_outline_fx.gdshader",
	"res://actors/shaders/actor_trail.gdshader",
	"res://actors/shaders/actor_xray.gdshader",
	"res://actors/shaders/actor_body.gdshader",
	"res://actors/shaders/actor_body_ds.gdshader",
	"res://actors/shaders/actor_body_fx.gdshader",
	"res://actors/shaders/actor_body_fx_ds.gdshader",
	"res://actors/shaders/actor_flat_add.gdshader",
	"res://actors/shaders/actor_flat_mix.gdshader",
	"res://actors/shaders/actor_flat_overlay.gdshader",
	"res://actors/shaders/actor_flat_overlay_add.gdshader",
	"res://feel/shaders/decal.gdshader",
	"res://feel/shaders/ghost.gdshader",
	"res://feel/shaders/impact.gdshader",
	"res://fx/shaders/fx_contour.gdshader",
	"res://fx/shaders/fx_ring.gdshader",
	"res://fx/shaders/fx_sigil.gdshader",
]

## Includes whose instance uniforms are demoted too: their text is inlined into the shaders above.
const WORLD_INCLUDES: Array[String] = [
	"res://shaders/toon_body.gdshaderinc",
	"res://actors/shaders/actor_body.gdshaderinc",
	"res://actors/shaders/actor_flat.gdshaderinc",
]

const _META := &"_webcompat"

static var _applied: bool = false
## The rewritten shaders. Held so the resource cache keeps these copies: a shader nothing references
## is freed, and the next load() would read the original back from disk.
static var _keep: Array[Shader] = []


## True in the web build. OVERDUB_WEBCOMPAT=1 forces it on desktop (run with
## --rendering-method gl_compatibility) to reproduce the web renderer locally.
static func is_web() -> bool:
	return OS.has_feature("web") or OS.get_environment("OVERDUB_WEBCOMPAT") == "1"


## Call before the first world is built. Safe to call more than once.
static func apply() -> void:
	if _applied or not is_web():
		return
	_applied = true
	for path: String in WORLD_SHADERS:
		var sh := load(path) as Shader
		if sh != null:
			sh.code = demote_instance_uniforms(inline_includes(sh.code))
			_keep.append(sh)
	print("webcompat: instance uniforms demoted in %d shaders" % WORLD_SHADERS.size())


## Replace each `#include` of a WORLD_INCLUDES file with that file's text.
static func inline_includes(code: String) -> String:
	var out := code
	for inc: String in WORLD_INCLUDES:
		var line := "#include \"%s\"" % inc
		if not out.contains(line):
			continue
		var si := load(inc) as ShaderInclude
		if si == null:
			continue
		out = out.replace(line, si.code)
	return out


## `instance uniform T name : hints, instance_index(N) = v;` -> `uniform T name : hints = v;`
static func demote_instance_uniforms(code: String) -> String:
	var out := code.replace("instance uniform ", "uniform ")
	var idx := RegEx.create_from_string(r"\s*,?\s*instance_index\(\d+\)")
	out = idx.sub(out, "", true)
	# A hint list emptied by the removal leaves "name : = v": drop the dangling colon.
	var dangling := RegEx.create_from_string(r"(uniform\s+\w+\s+\w+)\s*:\s*(=|;)")
	return dangling.sub(out, "$1 $2", true)


## Per-object shader value: set_instance_shader_parameter on desktop; on the web, the same value on
## this object's own copies of its materials (made on first use, remade if its materials change).
static func set_param(gi: GeometryInstance3D, param: StringName, value: Variant) -> void:
	if gi == null:
		return
	if not is_web():
		gi.set_instance_shader_parameter(param, value)
		return
	var st: Dictionary = gi.get_meta(_META, {})
	var values: Dictionary = st.get("values", {})
	values[param] = value
	if st.is_empty() or st.get("key", []) != _material_key(gi):
		st = {"values": values, "mats": _make_unique(gi)}
		st["key"] = _material_key(gi)
		gi.set_meta(_META, st)
		for k: StringName in values:
			for m: ShaderMaterial in st["mats"]:
				m.set_shader_parameter(k, values[k])
		return
	st["values"] = values
	for m: ShaderMaterial in st["mats"]:
		m.set_shader_parameter(param, value)


static func _material_key(gi: GeometryInstance3D) -> Array:
	var key: Array = [gi.material_override, gi.material_overlay]
	var mi := gi as MeshInstance3D
	if mi != null:
		key.append(mi.mesh)
		if mi.mesh != null:
			for i: int in range(mi.mesh.get_surface_count()):
				key.append(mi.get_surface_override_material(i))
	return key


## Give `gi` private copies of every material it draws with; returns the ShaderMaterials among them
## (next passes included).
static func _make_unique(gi: GeometryInstance3D) -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	if gi.material_override != null:
		gi.material_override = _dup_chain(gi.material_override, out)
	if gi.material_overlay != null:
		gi.material_overlay = _dup_chain(gi.material_overlay, out)
	var mi := gi as MeshInstance3D
	if mi != null and mi.mesh != null and gi.material_override == null:
		for i: int in range(mi.mesh.get_surface_count()):
			var m := mi.get_surface_override_material(i)
			if m == null:
				m = mi.mesh.surface_get_material(i)
			if m != null:
				mi.set_surface_override_material(i, _dup_chain(m, out))
	var mmi := gi as MultiMeshInstance3D
	if mmi != null and gi.material_override == null and mmi.multimesh != null and mmi.multimesh.mesh != null:
		var mesh := mmi.multimesh.mesh
		if mesh.get_surface_count() > 0 and mesh.surface_get_material(0) != null:
			gi.material_override = _dup_chain(mesh.surface_get_material(0), out)
	return out


static func _dup_chain(m: Material, out: Array[ShaderMaterial]) -> Material:
	var d := m.duplicate() as Material
	if d is ShaderMaterial:
		out.append(d as ShaderMaterial)
	if d.next_pass != null:
		d.next_pass = _dup_chain(d.next_pass, out)
	return d
