class_name Wardrobe
extends RefCounted
## The wardrobe: how equipped gear shows on Moxie (APPAREL-03). Reads data/wardrobe.json.
##
##   HEADGEAR  rigid models on the Head bone that sit with the yellow headphones:
##               Wardrobe.attach_headgear(skeleton, "prism_goggles", Wardrobe.head_fit(skeleton, meshes))
##   LOOKS     tops, pants and shoes recolour the base outfit by material name:
##               var tints := Wardrobe.tints_for(equipped_ids, Wardrobe.material_names(meshes))
##             plus an optional tiling pattern per material (Wardrobe.pattern_for) and optional
##             decals (Wardrobe.attach_decals).
##
## Everything is static and has no dependency on the actor layer, so it can be called from the
## actor rig, the loadout screen's preview and tools alike. docs/WARDROBE.md has the full contract.

const DATA_PATH: String = "res://data/wardrobe.json"
## Bone-name fallbacks: Godot's humanoid profile first, then the first-generation rig's names.
const HEAD_BONES: PackedStringArray = ["Head", "head"]
## Material-name prefixes that mark the headphones (overridable in head_fit.headphone_prefixes).
const HEADPHONE_PREFIXES: PackedStringArray = ["headphones", "phones", "hp_"]
## Material-name prefixes each slot is allowed to recolour. Nothing else is ever touched, which is
## what keeps the headphones, Walkman, hair, skin and belt constant in every loadout.
const REGIONS: Dictionary = {
	"top": ["top", "jacket"],
	"pants": ["pants"],
	"shoes": ["shoes"],
}

static var _data: Dictionary = {}
static var _loaded: bool = false
static var _textures: Dictionary = {}


# ───────────────────────────── data ─────────────────────────────

## The parsed data/wardrobe.json ({} when the file is missing or broken).
static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		var text := FileAccess.get_file_as_string(DATA_PATH)
		var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
		if parsed is Dictionary:
			_data = parsed as Dictionary
		else:
			push_warning("Wardrobe: %s is missing or not a JSON object" % DATA_PATH)
	return _data


## Drop the cache (tools and tests that rewrite the file).
static func reload() -> void:
	_loaded = false
	_data = {}
	_textures.clear()


## One item's entry, or {} for an id the wardrobe does not know (weapons, future gear).
static func item(item_id: String) -> Dictionary:
	var items: Variant = data().get("items", {})
	if items is Dictionary:
		var it: Variant = (items as Dictionary).get(item_id, {})
		if it is Dictionary:
			return it as Dictionary
	return {}


static func has_item(item_id: String) -> bool:
	return not item(item_id).is_empty()


## "helmet", "top", "pants", "shoes" or "".
static func slot_of(item_id: String) -> String:
	return str(item(item_id).get("slot", ""))


## The concept sheet for the loadout screen ("" when there is none).
static func concept_path(item_id: String) -> String:
	return str(item(item_id).get("concept", ""))


## Three swatches for UI: { base, trim, accent } as Colors ({} for an unknown item).
static func palette(item_id: String) -> Dictionary:
	var out: Dictionary = {}
	var pal: Variant = item(item_id).get("palette", {})
	if pal is Dictionary:
		for k: String in (pal as Dictionary):
			out[k] = Color.from_string(str((pal as Dictionary)[k]), Color.WHITE)
	return out


# ───────────────────────────── looks ─────────────────────────────

static func _look(item_id: String) -> Dictionary:
	var lk: Variant = item(item_id).get("look", {})
	return lk as Dictionary if lk is Dictionary else {}


## True when `mat_name` belongs to the outfit region that `slot` may recolour.
static func in_region(slot: String, mat_name: String) -> bool:
	if mat_name.ends_with("_glow"):
		return false
	var prefixes: Array = REGIONS.get(slot, [])
	for p: String in prefixes:
		if mat_name == p or mat_name.begins_with(p + "_"):
			return true
	return false


## The key of a look's colour table that names `mat_name`, or "". In order:
##   1. the exact name                                   "jacket_lining"
##   2. an alias from data/wardrobe.json "aliases"        "laces" -> "shoes_lace"
##   3. region + the role of its last word ("suffix_roles")  "jacket_rib" -> "jacket_trim"
##   4. the longest key that is a "_"-separated prefix    "top_trim_inner" -> "top_trim"
static func match_key(table: Dictionary, mat_name: String) -> String:
	if table.has(mat_name):
		return mat_name
	var cut := mat_name.rfind("_")
	if cut > 0:
		var roles: Variant = data().get("suffix_roles", {})
		if roles is Dictionary:
			var role := str((roles as Dictionary).get(mat_name.substr(cut + 1), ""))
			var head := mat_name.substr(0, mat_name.find("_"))
			if not role.is_empty() and table.has(head + "_" + role):
				return head + "_" + role
	var best := ""
	for k: String in table:
		if mat_name.begins_with(k + "_") and k.length() > best.length():
			best = k
	return best


## The contract name of a model's material: itself, or what data/wardrobe.json "aliases" maps it to
## (for models whose outfit materials do not start with top / jacket / pants / shoes).
static func canonical(mat_name: String) -> String:
	var al: Variant = data().get("aliases", {})
	if al is Dictionary and (al as Dictionary).has(mat_name):
		return str((al as Dictionary)[mat_name])
	return mat_name


## Base colours for the equipped looks: material name -> Color, for exactly those of
## `material_names` that an equipped top / pants / shoes item recolours. Feed it straight to
## ActorRig.apply_materials(mats, tints, accents).
static func tints_for(item_ids: Array, material_names: Array) -> Dictionary[StringName, Color]:
	var out: Dictionary[StringName, Color] = {}
	for id: Variant in item_ids:
		var it := item(str(id))
		var slot := str(it.get("slot", ""))
		var colors: Variant = _look(str(id)).get("colors", {})
		if not (colors is Dictionary) or not REGIONS.has(slot):
			continue
		for mn: Variant in material_names:
			var mat_name := canonical(str(mn))
			if not in_region(slot, mat_name):
				continue
			var key := match_key(colors as Dictionary, mat_name)
			if not key.is_empty():
				out[StringName(str(mn))] = Color.from_string(str((colors as Dictionary)[key]), Color.WHITE)
	return out


## The pattern an equipped look paints over `mat_name`, or {}:
##   { texture: Texture2D, color: Color, strength: float, scale: float (repeats per metre), id: String }
## The texture is a seamless grey mask: final = mix(base, color, mask * strength).
static func pattern_for(item_ids: Array, mat_name: String) -> Dictionary:
	mat_name = canonical(mat_name)
	for id: Variant in item_ids:
		var it := item(str(id))
		var pat: Variant = _look(str(id)).get("pattern", {})
		if not (pat is Dictionary) or (pat as Dictionary).is_empty():
			continue
		var p := pat as Dictionary
		var region := str(p.get("region", ""))
		if not in_region(str(it.get("slot", "")), mat_name):
			continue
		# a pattern belongs to its region's main material and that material's unnamed sub-parts,
		# never to another keyed material such as jacket_lining
		var colors: Variant = _look(str(id)).get("colors", {})
		var key := match_key(colors as Dictionary, mat_name) if colors is Dictionary else mat_name
		if key != region:
			continue
		var tex := _texture(str(p.get("texture", "")))
		if tex == null:
			continue
		return {
			"id": str(p.get("id", "")),
			"texture": tex,
			"color": Color.from_string(str(p.get("color", "#000000")), Color.BLACK),
			"strength": float(p.get("strength", 1.0)),
			"scale": float(p.get("scale", 4.0)),
		}
	return {}


## Decal descriptions of the equipped looks (see attach_decals for what the fields mean).
static func decals_for(item_ids: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: Variant in item_ids:
		var ds: Variant = _look(str(id)).get("decals", [])
		if ds is Array:
			for d: Variant in (ds as Array):
				if d is Dictionary:
					out.append(d as Dictionary)
	return out


static func _texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _textures.has(path):
		return _textures[path] as Texture2D
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_textures[path] = tex
	return tex


# ───────────────────────────── model helpers ─────────────────────────────

## A surface's material name (the asset contract's styling hook; same rule as ActorRig).
static func surface_material_name(mi: MeshInstance3D, surface: int) -> String:
	var m := mi.get_active_material(surface)
	if m != null and not m.resource_name.is_empty():
		return m.resource_name
	if mi.mesh != null:
		return mi.mesh.surface_get_name(surface)
	return ""


## Every distinct material name on the given meshes.
static func material_names(meshes: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for m: Variant in meshes:
		var mi := m as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i: int in mi.mesh.get_surface_count():
			var n := StringName(surface_material_name(mi, i))
			if not out.has(n):
				out.append(n)
	return out


## First bone of `names` that the skeleton has, or -1.
static func find_bone(skeleton: Skeleton3D, names: PackedStringArray) -> int:
	if skeleton == null:
		return -1
	for n: String in names:
		var i := skeleton.find_bone(n)
		if i >= 0:
			return i
	return -1


static func _to_ancestor(node: Node3D, ancestor: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


static func _common_root(a: Node, b: Node) -> Node:
	var chain: Array[Node] = []
	var n: Node = a
	while n != null:
		chain.append(n)
		n = n.get_parent()
	n = b
	while n != null:
		if chain.has(n):
			return n
		n = n.get_parent()
	return null


# ───────────────────────────── headgear ─────────────────────────────

## Where headgear sits on this particular Moxie model:
## { offset: Vector3, scale: float, brow_push: float, source: String }.
## Headgear is authored relative to the Head bone of the reference head (docs/WARDROBE.md "Head
## fit"). In order of preference:
##   1. an explicit entry for `model_path` under head_fit.models in data/wardrobe.json;
##   2. measured: the model's own headphones (materials named headphones* / phones* / hp_*) are
##      compared with the reference headphones, so the gear follows them wherever a modeller put them;
##   3. measured from the head's skin (materials named skin*) when it has no named headphones;
##   4. the reference fit unchanged.
static func head_fit(skeleton: Skeleton3D, meshes: Array = [], model_path: String = "") -> Dictionary:
	var hf: Variant = data().get("head_fit", {})
	var cfg: Dictionary = hf as Dictionary if hf is Dictionary else {}
	var models: Variant = cfg.get("models", {})
	if models is Dictionary and (models as Dictionary).has(model_path):
		var m: Dictionary = (models as Dictionary)[model_path]
		return {"offset": _vec3(m.get("offset", [0, 0, 0])), "scale": float(m.get("scale", 1.0)),
			"brow_push": float(m.get("brow_push", 0.0)), "source": "data"}
	var fallback := {"offset": Vector3.ZERO, "scale": 1.0, "brow_push": 0.0, "source": "reference"}
	if not bool(cfg.get("auto", true)):
		return fallback
	var head := find_bone(skeleton, HEAD_BONES)
	var ref: Variant = cfg.get("reference_headphones", {})
	if head < 0 or not (ref is Dictionary):
		return fallback
	var box := headphones_box(skeleton, meshes)
	if box.size.x <= 0.0:
		# No named headphones on this model: size the gear from the skin of the head instead.
		var rs: Variant = cfg.get("reference_skin", {})
		var skin_pre := PackedStringArray(cfg.get("skin_prefixes", ["skin"]) as Array)
		var sbox := prefix_box(skeleton, meshes, skin_pre, 0.0, 0.5, 0.2)
		if not (rs is Dictionary) or sbox.size.x <= 0.0:
			return fallback
		var s2 := clampf(sbox.size.x / maxf(float((rs as Dictionary).get("width", 0.18)), 0.001), 0.6, 1.8)
		var off2 := Vector3(sbox.get_center().x, sbox.end.y - float((rs as Dictionary).get("top", 0.205)) * s2, 0.0)
		return {"offset": off2, "scale": s2, "brow_push": _brow_push(skeleton, meshes, cfg, s2, off2), "source": "skin"}
	var rmin := _vec3((ref as Dictionary).get("min", [-0.129, 0.035, -0.052]))
	var rmax := _vec3((ref as Dictionary).get("max", [0.129, 0.227, 0.043]))
	# Width (cup to cup) is the most reliable measure of how big the head is.
	var s := clampf(box.size.x / maxf(rmax.x - rmin.x, 0.001), 0.6, 1.8)
	var ref_c := (rmin + rmax) * 0.5
	var c := box.get_center()
	var off := Vector3(c.x, box.end.y - rmax.y * s, c.z - ref_c.z * s)
	return {"offset": off, "scale": s, "brow_push": _brow_push(skeleton, meshes, cfg, s, off), "source": "headphones"}


# Brow gear (cap, crown, visor, goggles) rides on the fringe: if this model's hair stands further
# forward than the fitted reference hair would, that gear is pushed out by the difference.
static func _brow_push(skeleton: Skeleton3D, meshes: Array, cfg: Dictionary, s: float, off: Vector3) -> float:
	var front := hair_front(skeleton, meshes)
	if front == -INF:
		return 0.0
	return clampf(front - (float(cfg.get("reference_hair_front", 0.12)) * s + off.z), 0.0, 0.1)


## How far forward (+Z of the Head bone joint, skeleton space) the fringe reaches above the brow:
## the largest z of hair* vertices near the middle of the forehead. -INF when there is no hair.
static func hair_front(skeleton: Skeleton3D, meshes: Array) -> float:
	var head := find_bone(skeleton, HEAD_BONES)
	if head < 0:
		return -INF
	var head_pos := skeleton.get_bone_global_rest(head).origin
	var best := -INF
	for m: Variant in meshes:
		var mi := m as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var root := _common_root(mi, skeleton)
		if root == null:
			continue
		var xf := _to_ancestor(skeleton, root).affine_inverse() * _to_ancestor(mi, root)
		for i: int in mi.mesh.get_surface_count():
			if not surface_material_name(mi, i).begins_with("hair"):
				continue
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
			for v: Vector3 in verts:
				var p := xf * v - head_pos
				if absf(p.x) < 0.09 and p.y > 0.14 and p.y < 0.32:
					best = maxf(best, p.z)
	return best


## Bounds of the model's headphones around the head, relative to the Head bone's rest position, in
## skeleton space. A zero-size box when the model has no headphone materials or no head bone.
static func headphones_box(skeleton: Skeleton3D, meshes: Array) -> AABB:
	var prefixes: PackedStringArray = HEADPHONE_PREFIXES
	var hf: Variant = data().get("head_fit", {})
	if hf is Dictionary and (hf as Dictionary).has("headphone_prefixes"):
		prefixes = PackedStringArray((hf as Dictionary)["headphone_prefixes"] as Array)
	# the y / x limits ignore the cable that runs down to the Walkman
	return prefix_box(skeleton, meshes, prefixes, -0.02, 0.5, 0.32)


## Bounds, relative to the Head bone's rest position in skeleton space, of every vertex whose
## material name starts with one of `prefixes` (never *_glow) and that lies between y_lo and y_hi
## above the joint and within x_max of the centre line. A zero-size box when nothing matches.
static func prefix_box(skeleton: Skeleton3D, meshes: Array, prefixes: PackedStringArray, y_lo: float, y_hi: float, x_max: float) -> AABB:
	var head := find_bone(skeleton, HEAD_BONES)
	if head < 0:
		return AABB()
	var head_pos := skeleton.get_bone_global_rest(head).origin
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var found := false
	for m: Variant in meshes:
		var mi := m as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var root := _common_root(mi, skeleton)
		if root == null:
			continue
		var xf := _to_ancestor(skeleton, root).affine_inverse() * _to_ancestor(mi, root)
		for i: int in mi.mesh.get_surface_count():
			var sn := surface_material_name(mi, i)
			var hit := false
			for pre: String in prefixes:
				if sn.begins_with(pre):
					hit = true
					break
			if not hit or sn.ends_with("_glow"):
				continue
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
			for v: Vector3 in verts:
				var p := xf * v - head_pos
				if p.y < y_lo or p.y > y_hi or absf(p.x) > x_max:
					continue
				lo = lo.min(p)
				hi = hi.max(p)
				found = true
	if not found:
		return AABB()
	return AABB(lo, hi - lo)


## Instantiate an item's headgear model, or null (not a helmet, or the model is missing).
static func headgear_scene(item_id: String) -> Node3D:
	var at: Variant = item(item_id).get("attach", {})
	if not (at is Dictionary):
		return null
	var path := str((at as Dictionary).get("model", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	return ps.instantiate() as Node3D if ps != null else null


## Attach an item's headgear to the skeleton's Head bone. Returns the BoneAttachment3D (its child
## "Headgear" is the model; hand its MeshInstance3Ds to the toon materials), or null when the item
## has no headgear or the skeleton has no head bone.
## `fit` comes from head_fit(); {} = the reference fit.
static func attach_headgear(skeleton: Skeleton3D, item_id: String, fit: Dictionary = {}) -> BoneAttachment3D:
	var at: Variant = item(item_id).get("attach", {})
	if skeleton == null or not (at is Dictionary) or (at as Dictionary).is_empty():
		return null
	var a := at as Dictionary
	var names := PackedStringArray([str(a.get("bone", "Head"))])
	names.append_array(HEAD_BONES)
	var bone := find_bone(skeleton, names)
	if bone < 0:
		return null
	var model := headgear_scene(item_id)
	if model == null:
		return null
	var ba := BoneAttachment3D.new()
	ba.name = "Headgear_" + item_id
	skeleton.add_child(ba)
	ba.bone_idx = bone
	model.name = "Headgear"
	ba.add_child(model)
	var s := float(fit.get("scale", 1.0)) * float(a.get("scale", 1.0))
	var fit_off: Vector3 = fit.get("offset", Vector3.ZERO)
	var off := fit_off + _vec3(a.get("offset", [0, 0, 0])) * s
	if str(a.get("anchor", "")) == "brow":
		off.z += float(fit.get("brow_push", 0.0))
	# The model is authored in character axes (+Y up, +Z front) around the bone's joint; undo the
	# bone's own rest orientation so it stays upright whatever the rig's bone roll is.
	var rest := skeleton.get_bone_global_rest(bone)
	model.transform = rest.affine_inverse() * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), rest.origin + off)
	return ba


## Remove every headgear previously attached to this skeleton by attach_headgear.
static func clear_headgear(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	for c: Node in skeleton.get_children():
		if c is BoneAttachment3D and String(c.name).begins_with("Headgear_"):
			skeleton.remove_child(c)
			c.queue_free()


# ───────────────────────────── decals ─────────────────────────────

## Where a decal place sits on this model, in skeleton space (rest pose), or null when it cannot
## be measured. "jacket_back": the middle of the rearmost surface of the jacket* materials.
static func measure_place(place: String, skeleton: Skeleton3D, meshes: Array) -> Variant:
	if place != "jacket_back" or skeleton == null or meshes.is_empty():
		return null
	var pts: PackedVector3Array = []
	for m: Variant in meshes:
		var mi := m as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var root := _common_root(mi, skeleton)
		if root == null:
			continue
		var xf := _to_ancestor(skeleton, root).affine_inverse() * _to_ancestor(mi, root)
		for i: int in mi.mesh.get_surface_count():
			var sn := canonical(surface_material_name(mi, i))
			if not (sn == "jacket" or sn.begins_with("jacket_")) or sn.ends_with("_glow"):
				continue
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
			for v: Vector3 in verts:
				var p := xf * v
				if absf(p.x) < 0.07:      # the centre strip of the garment
					pts.append(p)
	if pts.is_empty():
		return null
	var back := INF
	for p: Vector3 in pts:
		back = minf(back, p.z)
	# the back panel = the centre-strip vertices within 4 cm of the rearmost one
	var y_lo := INF
	var y_hi := -INF
	for p: Vector3 in pts:
		if p.z < back + 0.04:
			y_lo = minf(y_lo, p.y)
			y_hi = maxf(y_hi, p.y)
	return Vector3(0.0, (y_lo + y_hi) * 0.5, back - 0.012)


## Attach the equipped looks' decals as small alpha-cut cards riding a torso bone. Returns the
## created BoneAttachment3Ds (named "Decal_<id>").
##   make_material  optional Callable (texture: Texture2D, color: Color, opacity: float) -> Material
##                  to use the game's toon material; by default an unshaded alpha-scissor
##                  StandardMaterial3D is used.
##   meshes         the model's MeshInstance3Ds: when given, the card is placed on the measured back
##                  of the jacket (measure_place); otherwise at the per-bone offset in
##                  data/wardrobe.json "decal_places".
static func attach_decals(skeleton: Skeleton3D, item_ids: Array, make_material: Callable = Callable(), meshes: Array = []) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if skeleton == null:
		return out
	var places: Variant = data().get("decal_places", {})
	for d: Dictionary in decals_for(item_ids):
		var place: Variant = (places as Dictionary).get(str(d.get("place", "")), {}) if places is Dictionary else {}
		if not (place is Dictionary) or (place as Dictionary).is_empty():
			continue
		var p := place as Dictionary
		var tex := _texture(str(d.get("texture", "")))
		if tex == null:
			continue
		var bone := -1
		var off := Vector3.ZERO
		var bones: Variant = p.get("bones", {})
		if bones is Dictionary:
			for bn: String in (bones as Dictionary):
				bone = skeleton.find_bone(bn)
				if bone >= 0:
					off = _vec3((bones as Dictionary)[bn])
					break
		if bone < 0:
			continue
		var measured: Variant = measure_place(str(d.get("place", "")), skeleton, meshes)
		if measured is Vector3:
			off = (measured as Vector3) - skeleton.get_bone_global_rest(bone).origin
		var color := Color.from_string(str(d.get("color", "#ffffff")), Color.WHITE)
		var opacity := float(d.get("opacity", 1.0))
		var mat: Material = null
		if make_material.is_valid():
			mat = make_material.call(tex, color, opacity) as Material
		if mat == null:
			var sm := StandardMaterial3D.new()
			sm.albedo_texture = tex
			sm.albedo_color = Color(color, opacity)
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			sm.alpha_scissor_threshold = 0.5
			sm.cull_mode = BaseMaterial3D.CULL_BACK
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat = sm
		var quad := QuadMesh.new()
		var size := float(d.get("size", p.get("size", 0.24)))
		quad.size = Vector2(size, size)
		var mi := MeshInstance3D.new()
		mi.name = "Card"
		mi.mesh = quad
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ba := BoneAttachment3D.new()
		ba.name = "Decal_" + str(d.get("id", "decal"))
		skeleton.add_child(ba)
		ba.bone_idx = bone
		ba.add_child(mi)
		var normal := _vec3(p.get("normal", [0, 0, -1])).normalized()
		var basis := Basis.looking_at(-normal, Vector3.UP)  # the card's +Z (its face) along `normal`
		var rest := skeleton.get_bone_global_rest(bone)
		mi.transform = rest.affine_inverse() * Transform3D(basis, rest.origin + off)
		out.append(ba)
	return out


static func clear_decals(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	for c: Node in skeleton.get_children():
		if c is BoneAttachment3D and String(c.name).begins_with("Decal_"):
			skeleton.remove_child(c)
			c.queue_free()


static func _vec3(v: Variant) -> Vector3:
	if v is Vector3:
		return v as Vector3
	if v is Array and (v as Array).size() >= 3:
		var a := v as Array
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
