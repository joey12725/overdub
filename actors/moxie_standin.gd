class_name MoxieStandin
extends RefCounted
## Clearly-temporary primitive stand-in for assets/models/moxie.glb, used only while that file is
## missing. It follows the asset contract exactly (armature bones, material names, clip names and
## lengths, +Z facing, origin on the floor) so the real model drops in with no code change. The
## clips are synthesised from MoxiePose (the prototype's procedural poses).

## Stand-in scale: the prototype figure was about 1.08 tall; the contract asks for about 1.6.
const S: float = 1.45
const SAMPLE_FPS: float = 30.0

const BONES: Array[StringName] = [
	&"root", &"hips", &"spine", &"chest", &"neck", &"head",
	&"shoulder.L", &"upper_arm.L", &"forearm.L", &"hand.L",
	&"shoulder.R", &"upper_arm.R", &"forearm.R", &"hand.R",
	&"thigh.L", &"shin.L", &"foot.L", &"toe.L",
	&"thigh.R", &"shin.R", &"foot.R", &"toe.R",
	&"pigtail.L.001", &"pigtail.L.002", &"pigtail.L.003",
	&"pigtail.R.001", &"pigtail.R.002", &"pigtail.R.003",
	&"jacket.L", &"jacket.R",
]

## Moxie's palette (prototype moxie.ts MOXIE_COLORS), by contract material name.
const COLORS: Dictionary[StringName, Color] = {
	&"skin": Color("#c98559"),
	&"hair": Color("#3b2219"),
	&"eye": Color("#2a140c"),
	&"face_paint": Color("#e8406a"),
	&"headphones": Color("#ffc414"),
	&"headphones_glow": Color("#ffffff"),
	&"top": Color("#ece5d6"),
	&"top_trim": Color("#262125"),
	&"jacket": Color("#2c2427"),
	&"jacket_lining": Color("#f4b51b"),
	&"pants": Color("#6d6a3b"),
	&"pants_graphic": Color("#f6c12b"),
	&"strap": Color("#c8285a"),
	&"belt": Color("#2a2626"),
	&"walkman": Color("#ffc81e"),
	&"pouch": Color("#3d3b3e"),
	&"glove": Color("#221f24"),
	&"wrist_device": Color("#26262c"),
	&"wrist_device_glow": Color("#4ff2ff"),
	&"shoes": Color("#2f2a2c"),
	&"shoes_lace": Color("#ffc81e"),
	&"shoes_sole": Color("#ebe1d0"),
}

static var _template: PackedScene = null


## A fresh instance of the stand-in (shares meshes and clips with every other instance).
static func instance() -> Node3D:
	if _template == null:
		var root := _build()
		_template = PackedScene.new()
		_template.pack(root)
		root.free()
	return _template.instantiate() as Node3D


static func _box(x: float, y: float, z: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(x, y, z) * S
	return m


static func _sphere(r: float, segs: int = 14) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r * S
	m.height = r * 2.0 * S
	m.radial_segments = segs
	m.rings = maxi(4, segs / 2)
	return m


static func _cyl(top: float, bottom: float, h: float, segs: int = 10) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top * S
	m.bottom_radius = bottom * S
	m.height = h * S
	m.radial_segments = segs
	m.rings = 1
	return m


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r * S
	m.height = maxf(h, r * 2.0) * S
	m.radial_segments = 10
	m.rings = 4
	return m


static func _torus(r: float, tube: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = (r - tube) * S
	m.outer_radius = (r + tube) * S
	m.rings = 18
	m.ring_segments = 6
	return m


static func _v(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z) * S


static func _build() -> Node3D:
	var b := ActorRigBuilder.new()
	for mat: StringName in COLORS:
		b.material(mat, COLORS[mat])
	b.bone(&"root", &"", Vector3.ZERO)
	b.bone(&"hips", &"root", _v(0, 0.46, 0))
	b.bone(&"spine", &"hips", _v(0, 0.06, 0))
	b.bone(&"chest", &"spine", _v(0, 0.08, 0))
	b.bone(&"neck", &"chest", _v(0, 0.1, 0))
	b.bone(&"head", &"neck", _v(0, 0.035, 0))
	for s: int in [1, -1]:
		var side := "L" if s == 1 else "R"
		b.bone(StringName("shoulder." + side), &"chest", _v(s * 0.05, 0.065, 0))
		b.bone(StringName("upper_arm." + side), StringName("shoulder." + side), _v(s * 0.065, 0, 0))
		b.bone(StringName("forearm." + side), StringName("upper_arm." + side), _v(0, -0.14, 0))
		b.bone(StringName("hand." + side), StringName("forearm." + side), _v(0, -0.13, 0))
	for s: int in [1, -1]:
		var side := "L" if s == 1 else "R"
		b.bone(StringName("thigh." + side), &"hips", _v(s * 0.068, -0.02, 0))
		b.bone(StringName("shin." + side), StringName("thigh." + side), _v(0, -0.19, 0))
		b.bone(StringName("foot." + side), StringName("shin." + side), _v(0, -0.18, 0))
		b.bone(StringName("toe." + side), StringName("foot." + side), _v(0, -0.05, 0.06))
	for s: int in [1, -1]:
		var side := "L" if s == 1 else "R"
		b.bone(StringName("pigtail." + side + ".001"), &"head", _v(s * 0.11, 0.21, -0.04))
		b.bone(StringName("pigtail." + side + ".002"), StringName("pigtail." + side + ".001"), _v(0, -0.08, 0))
		b.bone(StringName("pigtail." + side + ".003"), StringName("pigtail." + side + ".002"), _v(0, -0.075, 0))
	b.bone(&"jacket.L", &"spine", _v(0.06, 0.0, -0.05))
	b.bone(&"jacket.R", &"spine", _v(-0.06, 0.0, -0.05))

	# Pelvis: low-rise olive cargos, belt, Walkman on the hip, pouch.
	b.part(&"hips", _box(0.2, 0.1, 0.13), &"pants", _v(0, -0.015, 0))
	b.part(&"hips", _box(0.215, 0.025, 0.14), &"belt", _v(0, 0.035, 0))
	b.part(&"hips", _box(0.06, 0.075, 0.03), &"walkman", _v(0.085, 0.0, 0.07))
	b.part(&"hips", _box(0.05, 0.06, 0.035), &"pouch", _v(-0.09, -0.005, 0.055))
	b.part(&"hips", _box(0.012, 0.16, 0.012), &"strap", _v(0.1, -0.08, 0.02), Vector3(0, 0, 0.15))
	# Midriff + crop top.
	b.part(&"spine", _cyl(0.07, 0.085, 0.08), &"skin", _v(0, 0.02, 0))
	b.part(&"chest", _box(0.19, 0.1, 0.12), &"top", _v(0, 0.035, 0.0))
	b.part(&"chest", _box(0.195, 0.018, 0.125), &"top_trim", _v(0, -0.015, 0.0))
	b.part(&"chest", _box(0.02, 0.17, 0.01), &"strap", _v(0.0, 0.035, 0.064), Vector3(0, 0, 0.6))
	# Jacket worn off the shoulders: side panels with yellow lining, sleeves on the upper arms.
	for s: int in [1, -1]:
		var side := "L" if s == 1 else "R"
		b.part(&"chest", _box(0.04, 0.12, 0.13), &"jacket", _v(s * 0.1, 0.02, -0.01))
		b.part(&"chest", _box(0.005, 0.11, 0.12), &"jacket_lining", _v(s * 0.078, 0.02, -0.01))
		b.part(StringName("jacket." + side), _box(0.07, 0.11, 0.025), &"jacket", _v(0, -0.04, 0))
		b.part(StringName("jacket." + side), _box(0.065, 0.1, 0.004), &"jacket_lining", _v(0, -0.04, 0.014))
		b.part(StringName("upper_arm." + side), _cyl(0.04, 0.036, 0.14), &"jacket", _v(0, -0.07, 0))
		b.part(StringName("forearm." + side), _cyl(0.028, 0.024, 0.12), &"skin", _v(0, -0.06, 0))
		b.part(StringName("hand." + side), _sphere(0.032, 8), &"glove", _v(0, -0.02, 0))
		# Legs: baggy cargos, chunky high-tops.
		b.part(StringName("thigh." + side), _cyl(0.058, 0.052, 0.2), &"pants", _v(0, -0.095, 0))
		b.part(StringName("thigh." + side), _box(0.03, 0.05, 0.004), &"pants_graphic", _v(s * 0.0, -0.1, 0.056))
		b.part(StringName("shin." + side), _cyl(0.05, 0.056, 0.18), &"pants", _v(0, -0.09, 0))
		b.part(StringName("foot." + side), _box(0.085, 0.07, 0.15), &"shoes", _v(0, -0.02, 0.025))
		b.part(StringName("foot." + side), _box(0.09, 0.02, 0.16), &"shoes_sole", _v(0, -0.06, 0.03))
		b.part(StringName("foot." + side), _box(0.05, 0.008, 0.06), &"shoes_lace", _v(0, 0.017, 0.05))
		# Pigtails.
		b.part(StringName("pigtail." + side + ".001"), _capsule(0.032, 0.1), &"hair", _v(0, -0.04, 0))
		b.part(StringName("pigtail." + side + ".002"), _capsule(0.028, 0.09), &"hair", _v(0, -0.04, 0))
		b.part(StringName("pigtail." + side + ".003"), _capsule(0.02, 0.07), &"hair", _v(0, -0.03, 0))
	# Wrist device on the left forearm.
	b.part(&"forearm.L", _box(0.05, 0.04, 0.05), &"wrist_device", _v(0, -0.09, 0.0))
	b.part(&"forearm.L", _box(0.035, 0.025, 0.004), &"wrist_device_glow", _v(0, -0.09, 0.026))
	# Neck, head (big anime head), hair cap, eyes, face paint.
	b.part(&"neck", _cyl(0.032, 0.036, 0.06), &"skin", _v(0, 0.0, 0))
	b.part(&"head", _sphere(0.135, 16), &"skin", _v(0, 0.11, 0.0), Vector3.ZERO, Vector3(0.95, 1.0, 0.98))
	b.part(&"head", _sphere(0.144, 16), &"hair", _v(0, 0.135, -0.018), Vector3.ZERO, Vector3(1.0, 0.95, 1.0))
	b.part(&"head", _box(0.2, 0.05, 0.05), &"hair", _v(0, 0.19, 0.095), Vector3(0.35, 0, 0))
	for s: int in [1, -1]:
		b.part(&"head", _sphere(0.03, 8), &"eye", _v(s * 0.05, 0.1, 0.115), Vector3.ZERO, Vector3(1.0, 1.15, 0.35))
	b.part(&"head", _box(0.04, 0.009, 0.006), &"face_paint", _v(0.06, 0.068, 0.118), Vector3(0, 0.45, 0.25))
	# The signature: big yellow over-ear headphones; the outer rings glow in the cassette colour.
	for s: int in [1, -1]:
		b.part(&"head", _cyl(0.08, 0.08, 0.055, 16), &"headphones", _v(s * 0.142, 0.105, -0.005), Vector3(0, 0, PI * 0.5))
		b.part(&"head", _cyl(0.062, 0.062, 0.012, 16), &"headphones_glow", _v(s * 0.172, 0.105, -0.005), Vector3(0, 0, PI * 0.5))
		b.part(&"head", _box(0.02, 0.07, 0.03), &"headphones", _v(s * 0.137, 0.18, -0.005))
	# Headband arching over the crown (a ring in the XY plane; its lower half hides inside the head).
	b.part(&"head", _torus(0.152, 0.018), &"headphones", _v(0, 0.185, -0.005), Vector3(PI * 0.5, 0, 0))

	var root := b.build("MoxieStandin")
	var player := root.get_node("AnimationPlayer") as AnimationPlayer
	var lib := player.get_animation_library(&"")
	var bones := b.bone_names()
	lib.add_animation(MoxieAnim.CLIP_IDLE, _bake(b, bones, MoxiePose.S_IDLE, MoxieAnim.IDLE_SECONDS, true))
	lib.add_animation(MoxieAnim.CLIP_RUN, _bake(b, bones, MoxiePose.S_RUN, MoxieAnim.RUN_SECONDS, true))
	lib.add_animation(MoxieAnim.CLIP_STOPPED, _bake(b, bones, MoxiePose.S_STOPPED, 1.0, true))
	lib.add_animation(MoxieAnim.CLIP_LIGHT, _bake_melee(b, bones, false))
	lib.add_animation(MoxieAnim.CLIP_HEAVY, _bake_melee(b, bones, true))
	lib.add_animation(MoxieAnim.CLIP_DODGE, _bake(b, bones, MoxiePose.S_DODGE, 1.0, false))
	lib.add_animation(MoxieAnim.CLIP_RANGED, _bake(b, bones, MoxiePose.S_RANGED, 1.0, false))
	lib.add_animation(MoxieAnim.CLIP_INTERACT, _bake(b, bones, MoxiePose.S_INTERACT, 1.0, false))
	lib.add_animation(MoxieAnim.CLIP_DEATH, _bake(b, bones, MoxiePose.S_DEATH, 1.0, false))
	ActorRigBuilder.own(root, root)
	return root


static func _bake(b: ActorRigBuilder, bones: Array[StringName], state: int, length: float, loop: bool) -> Animation:
	var clip := ActorRigBuilder.ClipBake.new(length, loop, b, [&"root"] as Array[StringName])
	var pose := MoxiePose.create()
	var scratch := MoxiePose.create()
	var p := MoxiePose.Params.new()
	var n := maxi(2, roundi(length * SAMPLE_FPS))
	for i: int in n + 1:
		var t := length * float(i) / float(n)
		var u := t / length
		p.time = t
		p.stride = u * TAU
		p.speed = 1.0
		MoxiePose.compute(state, u, p, pose, scratch)
		_key_pose(clip, bones, t, pose)
	return clip.anim


## light / heavy: one 1.0 s clip, wind-up 0-0.4, hit 0.4-0.6, recovery 0.6-1.0 (asset contract).
static func _bake_melee(b: ActorRigBuilder, bones: Array[StringName], heavy: bool) -> Animation:
	var clip := ActorRigBuilder.ClipBake.new(1.0, false, b, [&"root"] as Array[StringName])
	var pose := MoxiePose.create()
	var scratch := MoxiePose.create()
	var p := MoxiePose.Params.new()
	var n := roundi(SAMPLE_FPS)
	for i: int in n + 1:
		var t := float(i) / float(n)
		var state: int
		var u: float
		if t < MoxieAnim.WINDUP_END:
			state = MoxiePose.S_HEAVY_WINDUP if heavy else MoxiePose.S_LIGHT_WINDUP
			u = t / MoxieAnim.WINDUP_END
		elif t < MoxieAnim.ACTIVE_END:
			state = MoxiePose.S_HEAVY_ACTIVE if heavy else MoxiePose.S_LIGHT_ACTIVE
			u = (t - MoxieAnim.WINDUP_END) / (MoxieAnim.ACTIVE_END - MoxieAnim.WINDUP_END)
		else:
			state = MoxiePose.S_HEAVY_RECOVER if heavy else MoxiePose.S_LIGHT_RECOVER
			u = (t - MoxieAnim.ACTIVE_END) / (1.0 - MoxieAnim.ACTIVE_END)
		MoxiePose.compute(state, u, p, pose, scratch)
		# 30 samples per second put keys exactly on the 0.4 / 0.6 phase boundaries.
		_key_pose(clip, bones, t, pose)
	return clip.anim


## Pose -> bone keys (prototype moxie.ts applyPose, mapped onto the contract armature).
static func _key_pose(c: ActorRigBuilder.ClipBake, bones: Array[StringName], t: float, o: PackedFloat32Array) -> void:
	var st := o[MoxiePose.K_STRETCH]
	c.key(bones.find(&"root"), t, Vector3.ZERO, _v(0, o[MoxiePose.K_ROOT_Y], o[MoxiePose.K_ROOT_FWD]),
		Vector3(1.0 - st * 0.25, 1.0 - st * 0.35, 1.0 + st))
	c.key(bones.find(&"hips"), t, Vector3(o[MoxiePose.K_HIPS_PITCH], o[MoxiePose.K_HIPS_YAW], o[MoxiePose.K_HIPS_ROLL]))
	c.key(bones.find(&"spine"), t, Vector3(o[MoxiePose.K_SPINE_PITCH], o[MoxiePose.K_SPINE_YAW], o[MoxiePose.K_SPINE_ROLL]))
	c.key(bones.find(&"chest"), t, Vector3.ZERO)
	c.key(bones.find(&"neck"), t, Vector3.ZERO)
	c.key(bones.find(&"head"), t, Vector3(o[MoxiePose.K_HEAD_PITCH], o[MoxiePose.K_HEAD_YAW], o[MoxiePose.K_HEAD_ROLL]))
	c.key(bones.find(&"shoulder.L"), t, Vector3.ZERO)
	c.key(bones.find(&"shoulder.R"), t, Vector3.ZERO)
	c.key(bones.find(&"upper_arm.L"), t, Vector3(-o[MoxiePose.K_ARM_L_RAISE], o[MoxiePose.K_ARM_L_TWIST], o[MoxiePose.K_ARM_L_OUT]))
	c.key(bones.find(&"forearm.L"), t, Vector3(-o[MoxiePose.K_ELBOW_L], 0, 0))
	c.key(bones.find(&"hand.L"), t, Vector3.ZERO)
	c.key(bones.find(&"upper_arm.R"), t, Vector3(-o[MoxiePose.K_ARM_R_RAISE], -o[MoxiePose.K_ARM_R_TWIST], -o[MoxiePose.K_ARM_R_OUT]))
	c.key(bones.find(&"forearm.R"), t, Vector3(-o[MoxiePose.K_ELBOW_R], 0, 0))
	c.key(bones.find(&"hand.R"), t, Vector3.ZERO)
	c.key(bones.find(&"thigh.L"), t, Vector3(-o[MoxiePose.K_LEG_L_RAISE], 0, o[MoxiePose.K_LEG_L_OUT]))
	c.key(bones.find(&"shin.L"), t, Vector3(o[MoxiePose.K_KNEE_L], 0, 0))
	c.key(bones.find(&"foot.L"), t, Vector3(o[MoxiePose.K_FOOT_L] + o[MoxiePose.K_LEG_L_RAISE] - o[MoxiePose.K_KNEE_L], 0, 0))
	c.key(bones.find(&"toe.L"), t, Vector3.ZERO)
	c.key(bones.find(&"thigh.R"), t, Vector3(-o[MoxiePose.K_LEG_R_RAISE], 0, -o[MoxiePose.K_LEG_R_OUT]))
	c.key(bones.find(&"shin.R"), t, Vector3(o[MoxiePose.K_KNEE_R], 0, 0))
	c.key(bones.find(&"foot.R"), t, Vector3(o[MoxiePose.K_FOOT_R] + o[MoxiePose.K_LEG_R_RAISE] - o[MoxiePose.K_KNEE_R], 0, 0))
	c.key(bones.find(&"toe.R"), t, Vector3.ZERO)
	var pl := o[MoxiePose.K_PIG_L_TIP]
	var pr := o[MoxiePose.K_PIG_R_TIP]
	c.key(bones.find(&"pigtail.L.001"), t, Vector3(0.45 + o[MoxiePose.K_PIG_L_SWING], 0, 0.35 + o[MoxiePose.K_PIG_L_OUT] * 0.7))
	c.key(bones.find(&"pigtail.L.002"), t, Vector3(pl * 0.8, 0, -0.25 - pl * 0.4))
	c.key(bones.find(&"pigtail.L.003"), t, Vector3(pl * 0.4, 0, -0.12 - pl * 0.2))
	c.key(bones.find(&"pigtail.R.001"), t, Vector3(0.45 + o[MoxiePose.K_PIG_R_SWING], 0, -0.35 - o[MoxiePose.K_PIG_R_OUT] * 0.7))
	c.key(bones.find(&"pigtail.R.002"), t, Vector3(pr * 0.8, 0, 0.25 + pr * 0.4))
	c.key(bones.find(&"pigtail.R.003"), t, Vector3(pr * 0.4, 0, 0.12 + pr * 0.2))
	var jf := 0.12 + o[MoxiePose.K_JACKET_FLARE] * 0.7
	c.key(bones.find(&"jacket.L"), t, Vector3(jf, 0, 0.1))
	c.key(bones.find(&"jacket.R"), t, Vector3(jf, 0, -0.1))
