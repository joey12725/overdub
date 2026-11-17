class_name MoxieModel
extends RefCounted
## What the actor layer needs to know about the Moxie model (docs/GODOT-PORT.md asset contract,
## "Moxie"), so that the self view relies only on the contract and works on the humanoid model, on a
## later replacement at the same path, and on the first-generation stand-in rig alike:
##
##  - bones by Godot's SkeletonProfileHumanoid names, with the stand-in's names as fallbacks;
##  - clips from res://assets/anim/moxie_anims.res (the contract library), plus the per-weapon
##    clips of the combat-feel library (light_<style>, heavy_<style>, ranged_<archetype>) baked onto
##    this skeleton with FeelRetarget, then whatever the .glb carries itself;
##  - the equipped ranged weapon worn on LeftLowerArm (replacing the model's own wrist device);
##  - the headphone glow: the model's own headphone `_glow` material when it has one, otherwise two
##    thin rings fitted to the outer faces of its ear cups, measured from the headphone materials.
## Everything is static; the baked library is cached for the process (all selves share one rig).

const CONTRACT_LIBRARY: String = "res://assets/anim/moxie_anims.res"
const WEAPON_DIR: String = "res://assets/models/weapons/"

const RIGHT_HAND: PackedStringArray = ["RightHand", "hand.R", "hand_R"]
const LEFT_HAND: PackedStringArray = ["LeftHand", "hand.L", "hand_L"]
const LEFT_FOREARM: PackedStringArray = ["LeftLowerArm", "forearm.L", "forearm_L"]
const CHEST: PackedStringArray = ["UpperChest", "Chest", "chest"]
const HEAD: PackedStringArray = ["Head", "head"]

## Material-name prefixes of the model's own wrist device, hidden while a ranged weapon (which brings
## its own bracer) is worn over it (asset contract addendum: Ranged).
const WRIST_DEVICE_PREFIXES: PackedStringArray = ["wrist_device", "device", "screen_glow"]
## Material-name prefixes of the headphones (same list as Wardrobe.HEADPHONE_PREFIXES).
const HEADPHONE_PREFIXES: PackedStringArray = ["headphones", "phones", "hp_"]
## Name of the glow material on the fitted rings (an accent: recoloured to the cassette colour).
const RING_GLOW: StringName = &"headphones_glow"
## Where along the forearm (elbow 0 .. wrist 1) the ranged weapon's Mount sits.
const MOUNT_ALONG: float = 0.6
## Height of the Mount above the forearm axis (the weapon frame has the axis at y = -0.036).
const MOUNT_LIFT: float = 0.036

static var _baked: AnimationLibrary = null
static var _baked_key: String = ""


## First bone of `names` that the skeleton has, or -1.
static func find_bone(sk: Skeleton3D, names: PackedStringArray) -> int:
	if sk == null:
		return -1
	for n: String in names:
		var i := sk.find_bone(n)
		if i >= 0:
			return i
	return -1


## Global (skeleton-space) rest transform of a bone.
static func global_rest(sk: Skeleton3D, bone: int) -> Transform3D:
	return sk.get_bone_global_rest(bone)


## A BoneAttachment3D on `bone` under the skeleton (null for bone -1).
static func attach(sk: Skeleton3D, bone: int, node_name: String) -> BoneAttachment3D:
	if sk == null or bone < 0:
		return null
	var ba := BoneAttachment3D.new()
	ba.name = node_name
	sk.add_child(ba)
	ba.bone_name = sk.get_bone_name(bone)
	return ba


## Bind the contract library over the model's own clips, then add the per-weapon combat-feel clips
## (only names the contract library does not have). Missing files are skipped: the sampler then
## keeps whatever the .glb (or stand-in) carries.
static func bind_clips(sampler: ActorClipSampler) -> void:
	if sampler == null or sampler.skeleton == null:
		return
	if ResourceLoader.exists(CONTRACT_LIBRARY):
		sampler.add_library(load(CONTRACT_LIBRARY) as AnimationLibrary, true)
	var feel := feel_library(sampler.skeleton)
	if feel != null:
		sampler.add_library(feel, true)


## The combat-feel library baked onto this skeleton (cached per bone layout), or null.
static func feel_library(sk: Skeleton3D) -> AnimationLibrary:
	if sk == null or not ResourceLoader.exists(FeelRig.LIBRARY_PATH):
		return null
	var key := "%d|%s|%s" % [sk.get_bone_count(), sk.get_bone_name(0), str(sk.get_bone_global_rest(0).origin)]
	if _baked != null and _baked_key == key:
		return _baked
	var src := load(FeelRig.LIBRARY_PATH) as AnimationLibrary
	if src == null:
		return null
	_baked = FeelRetarget.bake_library(src, sk, FeelRetarget.alias_for(sk))
	ground_feet(_baked, src, sk)
	measure_arcs(_baked, sk)
	_baked_key = key
	return _baked


## Rewrite the grip-arc metadata of every baked melee clip (od_grip / od_w / od_e, read by
## FeelRig.arc_at for the weapon smear) with the frame the weapon REALLY has in this model's right
## hand: the clips' authored arcs are for the 1.6-unit reference body, and a retargeted body with
## other proportions carries the weapon somewhere slightly different. Positions are stored in the
## reference body's scale (divide by this model's hips height / FeelRig.REF_HIP_HEIGHT), so callers
## keep scaling them exactly as COMBAT-FEEL.md says. Worn styles (gauntlets) keep the authored arc.
static func measure_arcs(lib: AnimationLibrary, sk: Skeleton3D) -> void:
	var rh := find_bone(sk, RIGHT_HAND)
	var hips := sk.find_bone("Hips")
	if lib == null or rh < 0 or hips < 0:
		return
	var k := sk.get_bone_global_rest(hips).origin.y / FeelRig.REF_HIP_HEIGHT
	if k <= 0.01:
		return
	var chain := _chain_of(sk, rh)
	var attach_held := FeelRig.weapon_attach_transform(sk, rh, true, false)
	var attach_worn := FeelRig.weapon_attach_transform(sk, rh, true, true)
	for clip: StringName in lib.get_animation_list():
		var a := lib.get_animation(clip)
		if a == null or not a.has_meta(&"od_grip"):
			continue
		if not a.has_meta(&"od_melee") and not String(clip).begins_with("light") and not String(clip).begins_with("heavy"):
			continue
		# Gauntlets are worn, not held: their arcs are in the fist frame.
		var attach := attach_worn if FeelRig.is_worn(String(a.get_meta(&"od_style", ""))) or String(clip).ends_with("_gauntlet") else attach_held
		var n := (a.get_meta(&"od_grip") as PackedVector3Array).size()
		if n < 2:
			continue
		var tracks := _chain_tracks(a, sk, chain)
		var grip := PackedVector3Array()
		var w := PackedVector3Array()
		var e := PackedVector3Array()
		for i: int in n:
			var wf := _chain_pose(a, sk, chain, tracks, a.length * float(i) / float(n - 1)) * attach
			grip.append(wf.origin / k)
			w.append(wf.basis.y.normalized())
			e.append(wf.basis.z.normalized())
		a.set_meta(&"od_grip", grip)
		a.set_meta(&"od_w", w)
		a.set_meta(&"od_e", e)


## Bone chain from `bone` up to the root.
static func _chain_of(sk: Skeleton3D, bone: int) -> PackedInt32Array:
	var chain := PackedInt32Array()
	var b := bone
	while b >= 0:
		chain.append(b)
		b = sk.get_bone_parent(b)
	return chain


## [rotation tracks, position tracks] of clip `a` for each bone of `chain` (-1: the bone rests).
static func _chain_tracks(a: Animation, sk: Skeleton3D, chain: PackedInt32Array) -> Array[PackedInt32Array]:
	var rot_t := PackedInt32Array()
	var pos_t := PackedInt32Array()
	rot_t.resize(chain.size())
	pos_t.resize(chain.size())
	rot_t.fill(-1)
	pos_t.fill(-1)
	for t: int in a.get_track_count():
		var path := a.track_get_path(t)
		if path.get_subname_count() == 0:
			continue
		var ci := chain.find(sk.find_bone(String(path.get_subname(0))))
		if ci < 0:
			continue
		if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			rot_t[ci] = t
		elif a.track_get_type(t) == Animation.TYPE_POSITION_3D:
			pos_t[ci] = t
	return [rot_t, pos_t]


## Skeleton-space transform of the first bone of `chain` in clip `a` at `time` (forward kinematics
## straight from the tracks: no Skeleton3D state is touched).
static func _chain_pose(a: Animation, sk: Skeleton3D, chain: PackedInt32Array, tracks: Array[PackedInt32Array], time: float) -> Transform3D:
	var g := Transform3D.IDENTITY
	for ci: int in chain.size():
		var rest := sk.get_bone_rest(chain[ci])
		var q := a.rotation_track_interpolate(tracks[0][ci], time).normalized() if tracks[0][ci] >= 0 else rest.basis.get_rotation_quaternion()
		var o := a.position_track_interpolate(tracks[1][ci], time) if tracks[1][ci] >= 0 else rest.origin
		g = Transform3D(Basis(q), o) * g
	return g


## Plant the feet: FeelRetarget carries rotations over and scales the travel of the hips by hip
## height, so on a body whose leg proportions differ from the profile the feet end a centimetre or
## three under (or over) the floor whenever the knees bend. For every key of the baked hips track,
## lift the hips so that the lower ankle of this body sits exactly as far above its own rest height
## as the lower ankle of the source clip sits above the source floor (scaled by hip height): a
## planted foot stays planted, a jump keeps its height. Pure translation of the root; rotations are
## untouched.
static func ground_feet(baked: AnimationLibrary, src: AnimationLibrary, sk: Skeleton3D) -> void:
	var hips := sk.find_bone("Hips")
	var lf := sk.find_bone("LeftFoot")
	var rf := sk.find_bone("RightFoot")
	if baked == null or src == null or hips < 0 or lf < 0 or rf < 0 or sk.get_bone_parent(hips) >= 0:
		return
	var profile := SkeletonProfileHumanoid.new()
	var p_hips := profile.find_bone(&"Hips")
	var hip_scale := sk.get_bone_global_rest(hips).origin.y / FeelRetarget.PROFILE_HIP_HEIGHT
	var rest_y := minf(sk.get_bone_global_rest(lf).origin.y, sk.get_bone_global_rest(rf).origin.y)
	var chains: Array[PackedInt32Array] = [_chain_of(sk, lf), _chain_of(sk, rf)]
	# Source legs in profile space: [foot, lower leg, upper leg, hips] profile bone indices.
	var src_chains: Array[PackedInt32Array] = []
	for side: String in ["Left", "Right"]:
		src_chains.append(PackedInt32Array([profile.find_bone(StringName(side + "Foot")), profile.find_bone(StringName(side + "LowerLeg")),
			profile.find_bone(StringName(side + "UpperLeg")), p_hips]))
	# Pass 1 measures, pass 2 applies: the source floor is the lowest its ankles ever go in the
	# whole library (its standing height), not the profile T-pose.
	var src_floor := INF
	var jobs: Array[Array] = []
	for clip: StringName in baked.get_animation_list():
		var a := baked.get_animation(clip)
		var sa := src.get_animation(clip)
		if a == null or sa == null:
			continue
		var tr0 := _chain_tracks(a, sk, chains[0])
		var tr1 := _chain_tracks(a, sk, chains[1])
		var hips_pos: int = tr0[1][chains[0].size() - 1]
		if hips_pos < 0:
			continue
		# Source tracks by profile bone index.
		var s_rot: Dictionary[int, int] = {}
		var s_pos := -1
		for t: int in sa.get_track_count():
			var path := sa.track_get_path(t)
			if path.get_subname_count() == 0:
				continue
			var pi := profile.find_bone(path.get_subname(0))
			if pi < 0:
				continue
			if sa.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				s_rot[pi] = t
			elif sa.track_get_type(t) == Animation.TYPE_POSITION_3D and pi == p_hips:
				s_pos = t
		if s_pos < 0:
			continue
		for k: int in a.track_get_key_count(hips_pos):
			var time := a.track_get_key_time(hips_pos, k)
			var low := minf(_chain_pose(a, sk, chains[0], tr0, time).origin.y, _chain_pose(a, sk, chains[1], tr1, time).origin.y)
			var src_low := INF
			for sc: PackedInt32Array in src_chains:
				var g := Transform3D.IDENTITY
				for pi: int in sc:
					var ref := profile.get_reference_pose(pi)
					var q := sa.rotation_track_interpolate(s_rot[pi], time).normalized() if s_rot.has(pi) else ref.basis.get_rotation_quaternion()
					var o := sa.position_track_interpolate(s_pos, time) if pi == p_hips else ref.origin
					g = Transform3D(Basis(q), o) * g
				src_low = minf(src_low, g.origin.y)
			src_floor = minf(src_floor, src_low)
			jobs.append([a, hips_pos, k, low, src_low])
	for j: Array in jobs:
		var a: Animation = j[0]
		var want := rest_y + (float(j[4]) - src_floor) * hip_scale
		var v: Vector3 = a.track_get_key_value(j[1], j[2])
		a.track_set_key_value(j[1], j[2], v + Vector3(0, want - float(j[3]), 0))


# ───────────────────────────── outfit zones (looks on the single-texture body) ─────────────────────────────

const ZONE_NAMES: Array[StringName] = [&"top", &"jacket", &"jacket_lining", &"pants", &"pants_graphic", &"shoes"]
const ZONE_JSON: String = "res://assets/models/moxie_regions.json"
const ZONE_TEX_A: String = "res://assets/models/moxie_regions_a.png"
const ZONE_TEX_B: String = "res://assets/models/moxie_regions_b.png"
const GEAR_JSON: String = "res://data/gear.json"

static var _zone_lums: PackedFloat32Array = PackedFloat32Array()
static var _base_ids: Array[String] = []
static var _base_read: bool = false


## Item ids of the catalogue's base loadout: the painted model IS that outfit, so those items never
## recolour it.
static func base_item_ids() -> Array[String]:
	if not _base_read:
		_base_read = true
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(GEAR_JSON))
		if v is Dictionary and (v as Dictionary).get("baseLoadout") is Dictionary:
			for id: Variant in ((v as Dictionary)["baseLoadout"] as Dictionary).values():
				_base_ids.append(str(id))
	return _base_ids


## Outfit zone tints for the equipped top / pants / shoes on the single-texture body (null when
## the masks are missing or nothing is recoloured). See tools/moxie_regions.py and docs/WARDROBE.md.
static func outfit_zones(item_ids: Array[String]) -> ActorMaterials.Zones:
	if not ResourceLoader.exists(ZONE_TEX_A) or not ResourceLoader.exists(ZONE_TEX_B):
		return null
	if _zone_lums.is_empty():
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(ZONE_JSON))
		var zones: Dictionary = (v as Dictionary).get("zones", {}) if v is Dictionary else {}
		for zn: StringName in ZONE_NAMES:
			var zd: Variant = zones.get(String(zn), {})
			_zone_lums.append(float((zd as Dictionary).get("lum", 0.2)) if zd is Dictionary else 0.2)
	var ids: Array = []
	var base := base_item_ids()
	for id: String in item_ids:
		if not base.has(id):
			ids.append(id)
	var z := ActorMaterials.Zones.new()
	z.lums = _zone_lums
	var tints: Dictionary[StringName, Color] = {}
	if not ids.is_empty():
		tints = Wardrobe.tints_for(ids, ZONE_NAMES)
	for zn: StringName in ZONE_NAMES:
		var c := Color(1, 1, 1, 0)
		if tints.has(zn):
			var lin: Color = (tints[zn] as Color).srgb_to_linear()
			c = Color(lin.r, lin.g, lin.b, 1.0)
		z.tints.append(c)
	z.tex_a = load(ZONE_TEX_A) as Texture2D
	z.tex_b = load(ZONE_TEX_B) as Texture2D
	return z if z.active() else null


## Clip names for the equipped melee style: [light, heavy] (per-weapon clips when the sampler has
## them, else the contract's `light` / `heavy`).
static func melee_clips(sampler: ActorClipSampler, style: String) -> Array[StringName]:
	var has := sampler.has_clip
	return [FeelRig.melee_clip(false, style, has), FeelRig.melee_clip(true, style, has)]


static func ranged_clip(sampler: ActorClipSampler, archetype: String) -> StringName:
	return FeelRig.ranged_clip(archetype, sampler.has_clip)


# ───────────────────────────── ranged weapon ─────────────────────────────

## The ranged weapon model for an item id (null when the file is missing).
static func ranged_weapon(item_id: String) -> Node3D:
	var path := WEAPON_DIR + item_id + ".glb"
	if item_id.is_empty() or not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var n := scene.instantiate() as Node3D
	if n != null:
		n.name = "RangedWeapon"
	return n


## Local transform (relative to the forearm bone) of a ranged weapon worn on the left forearm:
## +Z along the bone toward the hand (direction of fire), +Y up in the rest pose (the back of the
## forearm in a palms-down T-pose), Mount MOUNT_ALONG of the way to the wrist and MOUNT_LIFT above
## the bone axis. Derived from the global rest, so the bone's own axes do not matter.
static func ranged_attach_transform(sk: Skeleton3D, forearm: int, hand: int) -> Transform3D:
	var g := global_rest(sk, forearm)
	var to_hand := Vector3.ZERO
	if hand >= 0:
		to_hand = global_rest(sk, hand).origin - g.origin
	if to_hand.length() < 1e-4:
		to_hand = g.basis.y.normalized() * 0.22
	var z := to_hand.normalized()
	var up := Vector3.UP - z * Vector3.UP.dot(z)
	if up.length() < 1e-3:
		up = Vector3.FORWARD
	var y := up.normalized()
	var x := y.cross(z).normalized()
	var origin := g.origin + to_hand * MOUNT_ALONG + y * MOUNT_LIFT
	return g.affine_inverse() * Transform3D(Basis(x, y, z), origin)


## Material names on `meshes` that belong to the model's own wrist device.
static func wrist_device_names(meshes: Array[MeshInstance3D]) -> Array[StringName]:
	var out: Array[StringName] = []
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		for i: int in mi.mesh.get_surface_count():
			var n := ActorRig.surface_material_name(mi, i)
			if out.has(n):
				continue
			for pre: String in WRIST_DEVICE_PREFIXES:
				if String(n).begins_with(pre):
					out.append(n)
					break
	return out


# ───────────────────────────── headgear ─────────────────────────────

## Brow gear (cap, crown, visor, goggles) is authored level on the reference head. From the
## gameplay camera (35 degrees above) a level brim covers the whole face of this model, whose face
## sits further under its fringe, so on a single-texture head brow gear is tipped back and lifted a
## little: pitch (radians, negative raises the front) about a pivot inside the skull, and a lift,
## both in skeleton space relative to the Head joint.
const BROW_GEAR_PITCH: float = -0.5
const BROW_GEAR_LIFT: Vector3 = Vector3(0.0, 0.022, -0.012)
const BROW_GEAR_PIVOT: Vector3 = Vector3(0.0, 0.13, 0.0)


## Seat a headgear attachment made by Wardrobe.attach_headgear on this model's head (see above).
## Only models without named headphone materials (the single-texture head) are adjusted: where the
## wardrobe could measure the headphones its own fit already stands.
static func seat_headgear(sk: Skeleton3D, head: int, attachment: Node3D, item_id: String) -> void:
	var model := attachment.get_node_or_null("Headgear") as Node3D
	var at: Variant = Wardrobe.item(item_id).get("attach", {})
	if model == null or head < 0 or not (at is Dictionary) or str((at as Dictionary).get("anchor", "")) != "brow":
		return
	if sk.find_bone("Hips") < 0:
		return
	for c: Node in sk.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for i: int in mi.mesh.get_surface_count():
			if _is_phones(String(ActorRig.surface_material_name(mi, i))):
				return
	var rest := sk.get_bone_global_rest(head)
	var pivot := rest.origin + BROW_GEAR_PIVOT
	var x := rest * model.transform
	var tip := Transform3D(Basis(Vector3.RIGHT, BROW_GEAR_PITCH), Vector3.ZERO)
	x = Transform3D(Basis.IDENTITY, pivot + BROW_GEAR_LIFT) * tip * Transform3D(Basis.IDENTITY, -pivot) * x
	model.transform = rest.affine_inverse() * x


# ───────────────────────────── headphone glow ─────────────────────────────

static func _is_phones(n: String) -> bool:
	for pre: String in HEADPHONE_PREFIXES:
		if n.begins_with(pre):
			return true
	return false


## Accent materials of the model: headphone materials ending in `_glow` (empty when there are none).
static func headphone_glow_names(meshes: Array[MeshInstance3D]) -> Array[StringName]:
	var out: Array[StringName] = []
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		for i: int in mi.mesh.get_surface_count():
			var n := ActorRig.surface_material_name(mi, i)
			if String(n).ends_with("_glow") and _is_phones(String(n)) and not out.has(n):
				out.append(n)
	return out


## The two ear cups measured from the headphone materials, in skeleton space:
## [left AABB, right AABB] (+X is her left), empty when the model has no headphone materials.
static func ear_cups(sk: Skeleton3D, meshes: Array[MeshInstance3D]) -> Array[AABB]:
	var out: Array[AABB] = []
	var head := find_bone(sk, HEAD)
	if head < 0:
		return out
	var hp := global_rest(sk, head).origin
	var pts := PackedVector3Array()
	var max_x := 0.0
	# Pass 0: the headphone materials. Pass 1 (a single-texture head with no named headphones): the
	# `head` material's vertices in the band beside the skull where ear cups sit - outside the skull
	# width, around ear height, not as far back as the pigtails.
	for pass_i: int in 2:
		for mi: MeshInstance3D in meshes:
			if mi.mesh == null:
				continue
			var xf := mi.transform if mi.get_parent() == sk else Transform3D.IDENTITY
			for i: int in mi.mesh.get_surface_count():
				var n := String(ActorRig.surface_material_name(mi, i))
				if pass_i == 0 and (not _is_phones(n) or n.ends_with("_glow")):
					continue
				if pass_i == 1 and n != "head":
					continue
				var verts: PackedVector3Array = mi.mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
				for v: Vector3 in verts:
					var p := xf * v
					var r := p - hp
					if pass_i == 0:
						# The cups and band only: not the cable that runs down to the Walkman.
						if r.y < -0.05 or r.y > 0.5 or absf(r.x) > 0.35:
							continue
					elif r.y < 0.045 or r.y > 0.175 or absf(r.x) < 0.118 or absf(r.x) > 0.2 or r.z < -0.045 or r.z > 0.065:
						continue
					pts.append(p)
					max_x = maxf(max_x, absf(r.x))
		if not pts.is_empty():
			break
	if pts.is_empty() or max_x < 0.03:
		return out
	for side: float in [1.0, -1.0]:
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		var found := false
		for p: Vector3 in pts:
			if (p.x - hp.x) * side > max_x * 0.72:
				lo = lo.min(p)
				hi = hi.max(p)
				found = true
		if not found:
			out.clear()
			return out
		out.append(AABB(lo, hi - lo))
	return out


## Two glow rings on the outer faces of the cups, parented to a BoneAttachment3D on the head (null
## when the cups cannot be measured). Their material is named RING_GLOW, so ActorRig styles them as
## an emissive accent (the cassette colour).
static func build_headphone_rings(sk: Skeleton3D, meshes: Array[MeshInstance3D]) -> BoneAttachment3D:
	var cups := ear_cups(sk, meshes)
	var head := find_bone(sk, HEAD)
	if cups.size() != 2 or head < 0:
		return null
	var b := ActorGear.MeshBuilder.new()
	for k: int in 2:
		var box := cups[k]
		var side := 1.0 if k == 0 else -1.0
		var r := clampf(minf(box.size.y, box.size.z) * 0.36, 0.025, 0.09)
		var t := TorusMesh.new()
		t.inner_radius = r * 0.72
		t.outer_radius = r
		t.rings = 24
		t.ring_segments = 6
		var c := box.get_center()
		var x := box.end.x if side > 0.0 else box.position.x
		# Torus axis is Y: turn it onto X so the ring faces out of the cup.
		b.add(t, RING_GLOW, Color.WHITE, Vector3(x + side * 0.004, c.y, c.z), Vector3(0, 0, PI * 0.5))
	var mi := b.build("HeadphoneGlow")
	var ba := attach(sk, head, "At_HeadphoneGlow")
	ba.add_child(mi)
	mi.transform = global_rest(sk, head).affine_inverse()
	return ba
