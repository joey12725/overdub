class_name LabPuppet
extends Node3D
## A model driven by exact clip sampling, for the combat lab: load a rigged .glb, find its skeleton,
## (for a humanoid) fit the shipped animation library onto it with FeelRetarget, and pose it at any
## clip fraction. No AnimationPlayer playback: every pose is a pure function of (clip, fraction).

var skeleton: Skeleton3D = null
var model: Node3D = null
var clips: Dictionary[StringName, Animation] = {}
var body_scale: float = 1.0
var _bind: Dictionary[StringName, Array] = {}     # clip -> [tracks, kinds, bones]
var _weapons: Array[Node3D] = []


## Load `path` as a child. humanoid = true: use the shipped library (retargeted); false: use the
## animations inside the glb (enemies).
static func make(path: String, humanoid: bool) -> LabPuppet:
	var scene: PackedScene = load(path)
	if scene == null:
		return null
	var p := LabPuppet.new()
	p.model = scene.instantiate() as Node3D
	p.add_child(p.model)
	var skels := p.model.find_children("*", "Skeleton3D", true, false)
	p.skeleton = skels[0] as Skeleton3D if skels.size() > 0 else null
	if p.skeleton == null:
		return p
	if humanoid:
		var lib: AnimationLibrary = load(FeelRig.LIBRARY_PATH)
		var alias := FeelRetarget.alias_for(p.skeleton)
		var baked := FeelRetarget.bake_library(lib, p.skeleton, alias)
		for n: StringName in baked.get_animation_list():
			p.clips[n] = baked.get_animation(n)
		var hips := p.skeleton.find_bone(alias.get("Hips", "Hips"))
		if hips >= 0:
			p.body_scale = p._global_rest(hips).origin.y / FeelRig.REF_HIP_HEIGHT
	else:
		for pl: Node in p.model.find_children("*", "AnimationPlayer", true, false):
			var player := pl as AnimationPlayer
			for n: StringName in player.get_animation_list():
				var s := String(n)
				p.clips[StringName(s.substr(s.rfind("/") + 1))] = player.get_animation(n)
			player.active = false
	return p


func _global_rest(b: int) -> Transform3D:
	var t := Transform3D.IDENTITY
	while b >= 0:
		t = skeleton.get_bone_rest(b) * t
		b = skeleton.get_bone_parent(b)
	return t


func has_clip(clip: StringName) -> bool:
	return clips.has(clip)


## Pose the skeleton at `frac` (0..1) of `clip`. Loops wrap; one-shots clamp.
func pose(clip: StringName, frac: float) -> void:
	var anim: Animation = clips.get(clip)
	if anim == null or skeleton == null:
		return
	if not _bind.has(clip):
		var tr: PackedInt32Array = PackedInt32Array()
		var kd: PackedInt32Array = PackedInt32Array()
		var bn: PackedInt32Array = PackedInt32Array()
		for t: int in anim.get_track_count():
			var path := anim.track_get_path(t)
			if path.get_subname_count() == 0:
				continue
			var b := skeleton.find_bone(String(path.get_subname(0)))
			var ty := anim.track_get_type(t)
			if b < 0 or (ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_POSITION_3D and ty != Animation.TYPE_SCALE_3D):
				continue
			tr.append(t)
			kd.append(ty)
			bn.append(b)
		_bind[clip] = [tr, kd, bn]
	var f := fposmod(frac, 1.0) if anim.loop_mode != Animation.LOOP_NONE else clampf(frac, 0.0, 1.0)
	var time := f * anim.length
	var bind: Array = _bind[clip]
	var tracks: PackedInt32Array = bind[0]
	var kinds: PackedInt32Array = bind[1]
	var bones: PackedInt32Array = bind[2]
	skeleton.reset_bone_poses()
	for k: int in tracks.size():
		match kinds[k]:
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(bones[k], anim.rotation_track_interpolate(tracks[k], time))
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(bones[k], anim.position_track_interpolate(tracks[k], time))
			Animation.TYPE_SCALE_3D:
				skeleton.set_bone_pose_scale(bones[k], anim.scale_track_interpolate(tracks[k], time))


## Attach the melee weapon model of `item_id` to the right hand (and, for worn styles, the left
## gauntlet to the left hand), the way the actor layer should: BoneAttachment3D + FeelRig.weapon_attach_transform.
func equip(item_id: String) -> void:
	for w: Node3D in _weapons:
		w.queue_free()
	_weapons.clear()
	if skeleton == null:
		return
	var path := "res://assets/models/weapons/%s.glb" % item_id
	if not ResourceLoader.exists(path):
		return
	var worn := FeelRig.is_worn(FeelRig.style_for(item_id))
	var alias := FeelRetarget.alias_for(skeleton)
	for right: bool in ([true, false] if worn else [true]):
		var bone_name: String = "RightHand" if right else "LeftHand"
		var b := skeleton.find_bone(alias.get(bone_name, bone_name))
		if b < 0:
			continue
		var att := BoneAttachment3D.new()
		att.name = "Weapon" + ("R" if right else "L")
		skeleton.add_child(att)
		att.bone_idx = b
		var w := (load(path) as PackedScene).instantiate() as Node3D
		att.add_child(w)
		w.transform = FeelRig.weapon_attach_transform(skeleton, b, right, worn)
		if worn:
			# One file holds both gauntlets: show only this hand's.
			var other := w.find_child("Gauntlet_L" if right else "Gauntlet_R", true, false) as Node3D
			if other != null:
				other.visible = false
		ToonKit.apply_toon(w)
		_weapons.append(att)
