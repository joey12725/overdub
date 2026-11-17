class_name EnemyStandin
extends RefCounted
## Clearly-temporary primitive stand-ins for assets/models/enemies/<type>.glb, used only while those
## files are missing. Shaped like the asset contract: armature "Rig"-style Skeleton3D, clips `idle`
## (loop), `move` (loop), `telegraph`, `attack`, `stagger`, `death` (1.0 s each), an `aim` bone on
## the turret and drone, the shielder's `Shield` mesh object and the boss's `Armor_1..3` objects.
## Silhouettes follow the prototype's ruin-security machines (render/actors/enemyModels.ts).

const SAMPLE_FPS: float = 30.0
const CLIPS: Array[StringName] = [&"idle", &"move", &"telegraph", &"attack", &"stagger", &"death"]

const COLORS: Dictionary[StringName, Color] = {
	&"stone": Color("#a89d8b"),
	&"stone_dark": Color("#7b7163"),
	&"stone_light": Color("#c4b8a3"),
	&"brass": Color("#d2a136"),
	&"brass_dark": Color("#9c7424"),
	&"metal": Color("#3b3e46"),
	&"metal_light": Color("#5e626c"),
	&"rune_glow": Color("#58f0dc"),
	&"eye_glow": Color("#ff6a1a"),
}

static var _templates: Dictionary[StringName, PackedScene] = {}


static func instance(type: StringName) -> Node3D:
	if not _templates.has(type):
		var root := _build(type)
		var scene := PackedScene.new()
		scene.pack(root)
		root.free()
		_templates[type] = scene
	return _templates[type].instantiate() as Node3D


static func _box(x: float, y: float, z: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(x, y, z)
	return m


static func _sphere(r: float, segs: int = 12) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = segs
	m.rings = maxi(4, segs / 2)
	return m


static func _cyl(top: float, bottom: float, h: float, segs: int = 10) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return m


static func _torus(r: float, tube: float, segs: int = 24) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = r - tube
	m.outer_radius = r + tube
	m.rings = segs
	m.ring_segments = 5
	return m


static func _cone(r: float, h: float, segs: int = 6) -> CylinderMesh:
	return _cyl(0.0, r, h, segs)


static func _build(type: StringName) -> Node3D:
	var b := ActorRigBuilder.new()
	for mat: StringName in COLORS:
		b.material(mat, COLORS[mat])
	b.bone(&"root", &"", Vector3.ZERO)
	match type:
		EnemyType.STALKER:
			_stalker(b)
		EnemyType.TURRET:
			_turret(b)
		EnemyType.SHIELDER:
			_shielder(b)
		EnemyType.BRUTE:
			_brute(b)
		EnemyType.DRONE:
			_drone(b)
		EnemyType.BOSS:
			_boss(b)
		_:
			_grunt(b)
	var root := b.build("EnemyStandin_" + String(type))
	var player := root.get_node("AnimationPlayer") as AnimationPlayer
	var lib := player.get_animation_library(&"")
	for clip: StringName in CLIPS:
		lib.add_animation(clip, _bake(b, type, clip))
	ActorRigBuilder.own(root, root)
	return root


# ───────────────────────────── silhouettes ─────────────────────────────

static func _grunt(b: ActorRigBuilder) -> void:
	# Squat sentinel: a carved stone block torso with brass collar and rune seams.
	b.bone(&"body", &"root", Vector3(0, 0.18, 0))
	b.bone(&"head", &"body", Vector3(0, 0.39, 0.02))
	b.bone(&"arm.R", &"body", Vector3(-0.27, 0.3, 0))
	b.bone(&"arm.L", &"body", Vector3(0.26, 0.3, 0))
	b.bone(&"leg.R", &"body", Vector3(-0.12, 0.02, 0))
	b.bone(&"leg.L", &"body", Vector3(0.12, 0.02, 0))
	b.part(&"body", _box(0.42, 0.34, 0.32), &"stone", Vector3(0, 0.2, 0))
	b.part(&"body", _box(0.44, 0.06, 0.34), &"brass", Vector3(0, 0.36, 0))
	b.part(&"body", _box(0.3, 0.025, 0.01), &"rune_glow", Vector3(0, 0.2, 0.162))
	b.part(&"body", _box(0.025, 0.2, 0.01), &"rune_glow", Vector3(0, 0.2, 0.163))
	b.part(&"body", _box(0.2, 0.12, 0.08), &"metal", Vector3(0, 0.18, -0.19))
	b.part(&"head", _sphere(0.15, 10), &"stone_dark", Vector3(0, 0.06, 0), Vector3.ZERO, Vector3(1.1, 0.8, 1))
	b.part(&"head", _box(0.2, 0.05, 0.06), &"metal", Vector3(0, 0.06, 0.12))
	b.part(&"head", _box(0.13, 0.03, 0.02), &"eye_glow", Vector3(0, 0.06, 0.155))
	b.part(&"head", _cone(0.03, 0.1, 4), &"brass", Vector3(0.1, 0.15, -0.02), Vector3(0, 0, -0.5))
	b.part(&"head", _cone(0.03, 0.1, 4), &"brass", Vector3(-0.1, 0.15, -0.02), Vector3(0, 0, 0.5))
	# The club: a ruin column fragment bolted to a piston forearm.
	b.part(&"arm.R", _sphere(0.07, 8), &"metal")
	b.part(&"arm.R", _cyl(0.05, 0.05, 0.18, 8), &"metal_light", Vector3(0, -0.1, 0))
	b.part(&"arm.R", _cyl(0.1, 0.09, 0.24, 8), &"stone_light", Vector3(0, -0.3, 0.02))
	b.part(&"arm.R", _torus(0.095, 0.018, 12), &"brass", Vector3(0, -0.22, 0.02))
	b.part(&"arm.L", _sphere(0.06, 8), &"metal")
	b.part(&"arm.L", _cyl(0.045, 0.04, 0.22, 8), &"metal_light", Vector3(0, -0.12, 0))
	b.part(&"arm.L", _box(0.09, 0.08, 0.09), &"brass", Vector3(0, -0.25, 0))
	for leg: StringName in [&"leg.R", &"leg.L"]:
		b.part(leg, _cyl(0.065, 0.055, 0.16, 8), &"metal", Vector3(0, -0.08, 0))
		b.part(leg, _box(0.13, 0.05, 0.17), &"stone_dark", Vector3(0, -0.16, 0.02))


static func _stalker(b: ActorRigBuilder) -> void:
	# Lean hunter: horizontal body, raised hindquarters, ridge of brass vanes, blade arms, tail.
	b.bone(&"body", &"root", Vector3(0, 0.38, 0))
	b.bone(&"head", &"body", Vector3(0, 0.08, 0.24))
	b.bone(&"arm.R", &"body", Vector3(-0.11, 0.02, 0.14))
	b.bone(&"arm.L", &"body", Vector3(0.11, 0.02, 0.14))
	b.bone(&"leg.R", &"body", Vector3(-0.09, -0.02, -0.08))
	b.bone(&"leg.L", &"body", Vector3(0.09, -0.02, -0.08))
	b.bone(&"tail", &"body", Vector3(0, 0.06, -0.22))
	var caps := CapsuleMesh.new()
	caps.radius = 0.1
	caps.height = 0.52
	b.part(&"body", caps, &"metal", Vector3(0, 0.05, 0), Vector3(PI * 0.5 - 0.25, 0, 0))
	var caps2 := CapsuleMesh.new()
	caps2.radius = 0.085
	caps2.height = 0.4
	b.part(&"body", caps2, &"stone", Vector3(0, 0.12, -0.02), Vector3(PI * 0.5 - 0.25, 0, 0))
	for i: int in 4:
		b.part(&"body", _cone(0.03, 0.12, 4), &"brass", Vector3(0, 0.22 - i * 0.02, 0.1 - i * 0.09), Vector3(-0.6, 0, 0))
	b.part(&"body", _box(0.012, 0.012, 0.3), &"rune_glow", Vector3(0.09, 0.08, 0))
	b.part(&"body", _box(0.012, 0.012, 0.3), &"rune_glow", Vector3(-0.09, 0.08, 0))
	b.part(&"head", _box(0.12, 0.08, 0.2), &"stone_light", Vector3(0, 0, 0.05))
	b.part(&"head", _box(0.11, 0.018, 0.02), &"eye_glow", Vector3(0, 0.035, 0.155))
	for arm: StringName in [&"arm.R", &"arm.L"]:
		b.part(arm, _sphere(0.045, 6), &"metal")
		b.part(arm, _cyl(0.025, 0.02, 0.16, 6), &"metal_light", Vector3(0, -0.08, 0))
		b.part(arm, _box(0.035, 0.3, 0.012), &"stone_light", Vector3(0, -0.28, 0.06), Vector3(0.4, 0, 0))
	for leg: StringName in [&"leg.R", &"leg.L"]:
		b.part(leg, _cyl(0.04, 0.03, 0.2, 6), &"metal", Vector3(0, -0.08, -0.05), Vector3(-0.5, 0, 0))
		b.part(leg, _cyl(0.025, 0.02, 0.2, 6), &"metal_light", Vector3(0, -0.24, -0.03), Vector3(0.5, 0, 0))
		b.part(leg, _box(0.06, 0.03, 0.1), &"stone_dark", Vector3(0, -0.33, 0.02))
	b.part(&"tail", _cyl(0.025, 0.025, 0.36, 6), &"metal", Vector3(0, 0.15, -0.15), Vector3(-0.8, 0, 0))
	b.part(&"tail", _sphere(0.04, 6), &"eye_glow", Vector3(0, 0.3, -0.3))


static func _turret(b: ActorRigBuilder) -> void:
	# A temple plinth with a rune ring, crowned by a retrofitted gun head on the `aim` bone.
	b.bone(&"base", &"root", Vector3.ZERO)
	b.bone(&"aim", &"root", Vector3(0, 0.3, 0))
	b.bone(&"barrels", &"aim", Vector3(0, 0.12, 0.08))
	b.part(&"base", _cyl(0.3, 0.36, 0.22, 8), &"stone", Vector3(0, 0.11, 0))
	b.part(&"base", _cyl(0.26, 0.3, 0.08, 8), &"stone_dark", Vector3(0, 0.26, 0))
	b.part(&"base", _torus(0.335, 0.012, 24), &"rune_glow", Vector3(0, 0.14, 0))
	for i: int in 4:
		var a := TAU * float(i) / 4.0 + PI / 4.0
		b.part(&"base", _box(0.08, 0.1, 0.05), &"brass", Vector3(sin(a) * 0.32, 0.12, cos(a) * 0.32), Vector3(0, a, 0))
	b.part(&"aim", _cyl(0.18, 0.2, 0.08, 10), &"metal", Vector3(0, 0.03, 0))
	b.part(&"aim", _box(0.3, 0.18, 0.28), &"brass", Vector3(0, 0.15, -0.02))
	b.part(&"aim", _box(0.32, 0.04, 0.3), &"brass_dark", Vector3(0, 0.25, -0.02))
	b.part(&"aim", _box(0.12, 0.05, 0.02), &"eye_glow", Vector3(0, 0.17, 0.125))
	for s: float in [1.0, -1.0]:
		b.part(&"barrels", _cyl(0.035, 0.04, 0.34, 8), &"metal_light", Vector3(s * 0.075, 0, 0.17), Vector3(PI * 0.5, 0, 0))
		b.part(&"barrels", _cyl(0.045, 0.045, 0.04, 8), &"metal", Vector3(s * 0.075, 0, 0.33), Vector3(PI * 0.5, 0, 0))


static func _shielder(b: ActorRigBuilder) -> void:
	b.bone(&"body", &"root", Vector3(0, 0.2, 0))
	b.bone(&"head", &"body", Vector3(0, 0.4, 0))
	b.bone(&"shield", &"body", Vector3(0.05, 0.2, 0.3))
	b.bone(&"arm.R", &"body", Vector3(-0.25, 0.3, 0))
	b.bone(&"leg.R", &"body", Vector3(-0.1, 0.02, 0))
	b.bone(&"leg.L", &"body", Vector3(0.1, 0.02, 0))
	b.part(&"body", _cyl(0.16, 0.22, 0.38, 10), &"stone", Vector3(0, 0.19, 0))
	b.part(&"body", _torus(0.225, 0.02, 16), &"brass", Vector3(0, 0.16, 0))
	b.part(&"body", _box(0.012, 0.25, 0.012), &"rune_glow", Vector3(0, 0.18, 0.235))
	b.part(&"head", _sphere(0.12, 10), &"metal", Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1, 0.85, 1))
	b.part(&"head", _sphere(0.035, 8), &"eye_glow", Vector3(0, 0.05, 0.105))
	# The tower shield: a hexagonal temple-door slab with a brass rim and a rune emitter.
	var hex := CylinderMesh.new()
	hex.top_radius = 0.3
	hex.bottom_radius = 0.3
	hex.height = 0.05
	hex.radial_segments = 6
	hex.rings = 1
	b.part(&"shield", hex, &"stone_light", Vector3.ZERO, Vector3(PI * 0.5, 0, PI / 6.0), Vector3(1, 1, 1.15), &"Shield")
	var hex2 := hex.duplicate() as CylinderMesh
	hex2.top_radius = 0.24
	hex2.bottom_radius = 0.24
	hex2.height = 0.06
	b.part(&"shield", hex2, &"brass", Vector3(0, 0, 0.005), Vector3(PI * 0.5, 0, PI / 6.0), Vector3(1, 1, 1.15), &"Shield")
	b.part(&"shield", _sphere(0.05, 6), &"eye_glow", Vector3(0, 0, 0.04), Vector3.ZERO, Vector3.ONE, &"Shield")
	b.part(&"arm.R", _sphere(0.055, 8), &"metal")
	b.part(&"arm.R", _cyl(0.04, 0.035, 0.22, 6), &"metal_light", Vector3(0, -0.11, 0))
	b.part(&"arm.R", _box(0.08, 0.08, 0.08), &"brass", Vector3(0, -0.24, 0))
	for leg: StringName in [&"leg.R", &"leg.L"]:
		b.part(leg, _cyl(0.06, 0.05, 0.16, 8), &"metal", Vector3(0, -0.08, 0))
		b.part(leg, _box(0.12, 0.05, 0.16), &"stone_dark", Vector3(0, -0.17, 0.02))


static func _brute(b: ActorRigBuilder) -> void:
	# Hunched golem: massive shoulders, tiny head, brass bands strapping cracked stone.
	b.bone(&"body", &"root", Vector3(0, 0.3, 0))
	b.bone(&"head", &"body", Vector3(0, 0.6, 0.2))
	b.bone(&"arm.R", &"body", Vector3(-0.5, 0.42, 0.05))
	b.bone(&"arm.L", &"body", Vector3(0.5, 0.42, 0.05))
	b.bone(&"leg.R", &"body", Vector3(-0.17, -0.06, 0))
	b.bone(&"leg.L", &"body", Vector3(0.17, -0.06, 0))
	b.part(&"body", _sphere(0.36, 8), &"stone", Vector3(0, 0.3, 0), Vector3.ZERO, Vector3(1.35, 0.95, 1.0))
	b.part(&"body", _box(0.7, 0.08, 0.42), &"brass", Vector3(0, 0.36, 0))
	b.part(&"body", _box(0.36, 0.3, 0.3), &"stone_dark", Vector3(0, 0.02, -0.02))
	b.part(&"body", _box(0.02, 0.32, 0.02), &"rune_glow", Vector3(0.08, 0.3, 0.33), Vector3(0.25, 0, 0.3))
	b.part(&"body", _box(0.24, 0.16, 0.12), &"metal", Vector3(0, 0.4, -0.3))
	b.part(&"head", _box(0.2, 0.14, 0.18), &"stone_light", Vector3(0, 0.05, 0))
	b.part(&"head", _box(0.14, 0.03, 0.02), &"eye_glow", Vector3(0, 0.05, 0.095))
	b.part(&"head", _box(0.24, 0.04, 0.2), &"brass", Vector3(0, 0.13, 0))
	for arm: StringName in [&"arm.R", &"arm.L"]:
		b.part(arm, _sphere(0.15, 8), &"stone_dark", Vector3.ZERO, Vector3.ZERO, Vector3(1.1, 1, 1))
		b.part(arm, _box(0.18, 0.12, 0.16), &"brass", Vector3(0, 0.06, 0))
		b.part(arm, _cyl(0.09, 0.08, 0.3, 8), &"metal", Vector3(0, -0.2, 0.02))
		b.part(arm, _sphere(0.17, 7), &"stone", Vector3(0, -0.43, 0.04), Vector3.ZERO, Vector3(1, 0.9, 1.1))
		b.part(arm, _box(0.2, 0.05, 0.2), &"brass", Vector3(0, -0.32, 0.04))
	for leg: StringName in [&"leg.R", &"leg.L"]:
		b.part(leg, _cyl(0.11, 0.1, 0.22, 8), &"metal", Vector3(0, -0.1, 0))
		b.part(leg, _box(0.22, 0.08, 0.26), &"stone_dark", Vector3(0, -0.22, 0.03))


static func _drone(b: ActorRigBuilder) -> void:
	# Floating ward-orb: stone shell split by a brass equator, one big lens on the `aim` bone.
	b.bone(&"body", &"root", Vector3(0, 1.0, 0))
	b.bone(&"aim", &"body", Vector3(0, 0, 0))
	b.bone(&"rotor.A", &"body", Vector3(0, 0.03, 0))
	b.bone(&"rotor.B", &"body", Vector3(0, -0.03, 0))
	b.part(&"body", _sphere(0.17, 12), &"stone")
	b.part(&"body", _torus(0.17, 0.025, 20), &"brass")
	b.part(&"body", _cone(0.05, 0.12, 6), &"metal", Vector3(0, -0.19, 0), Vector3(PI, 0, 0))
	b.part(&"body", _sphere(0.025, 6), &"rune_glow", Vector3(0, -0.26, 0))
	b.part(&"aim", _cyl(0.08, 0.09, 0.06, 12), &"metal", Vector3(0, 0, 0.15), Vector3(PI * 0.5, 0, 0))
	b.part(&"aim", _cyl(0.06, 0.06, 0.02, 12), &"eye_glow", Vector3(0, 0, 0.185), Vector3(PI * 0.5, 0, 0))
	for rotor: StringName in [&"rotor.A", &"rotor.B"]:
		b.part(rotor, _torus(0.27, 0.014, 24), &"metal_light")
		for i: int in 3:
			var a := TAU * float(i) / 3.0
			b.part(rotor, _box(0.12, 0.012, 0.03), &"brass", Vector3(cos(a) * 0.21, 0, sin(a) * 0.21), Vector3(0, -a, 0))


static func _boss(b: ActorRigBuilder) -> void:
	# The Archivist: a stone plinth, a central column with one great optic, cassette-reel wheels on
	# its flanks and three armour plates that fall away as its phases advance.
	b.bone(&"base", &"root", Vector3.ZERO)
	b.bone(&"body", &"root", Vector3(0, 0.5, 0))
	b.bone(&"eye", &"body", Vector3(0, 0.7, 0.5))
	b.bone(&"reel.L", &"body", Vector3(0.62, 0.65, 0))
	b.bone(&"reel.R", &"body", Vector3(-0.62, 0.65, 0))
	for i: int in 3:
		b.bone(StringName("armor.%d" % (i + 1)), &"body", Vector3(0, 0.6, 0))
	b.part(&"base", _cyl(1.05, 1.2, 0.35, 12), &"stone_dark", Vector3(0, 0.17, 0))
	b.part(&"base", _cyl(0.9, 1.0, 0.2, 12), &"stone", Vector3(0, 0.45, 0))
	b.part(&"base", _torus(1.1, 0.03, 36), &"rune_glow", Vector3(0, 0.3, 0))
	for i: int in 8:
		var a := TAU * float(i) / 8.0
		b.part(&"base", _box(0.2, 0.3, 0.12), &"brass", Vector3(sin(a) * 1.08, 0.2, cos(a) * 1.08), Vector3(0, a, 0))
	b.part(&"body", _cyl(0.48, 0.55, 1.1, 10), &"metal", Vector3(0, 0.55, 0))
	b.part(&"body", _cyl(0.5, 0.5, 0.08, 10), &"brass", Vector3(0, 0.2, 0))
	b.part(&"body", _cyl(0.5, 0.5, 0.08, 10), &"brass", Vector3(0, 0.95, 0))
	for i: int in 6:
		var a := TAU * float(i) / 6.0
		b.part(&"body", _box(0.03, 0.7, 0.03), &"rune_glow", Vector3(sin(a) * 0.5, 0.6, cos(a) * 0.5))
	b.part(&"body", _cone(0.42, 0.5, 10), &"stone_light", Vector3(0, 1.35, 0))
	b.part(&"eye", _cyl(0.3, 0.34, 0.16, 16), &"brass", Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
	b.part(&"eye", _cyl(0.24, 0.24, 0.18, 16), &"metal", Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
	b.part(&"eye", _cyl(0.17, 0.17, 0.2, 16), &"eye_glow", Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
	for reel: StringName in [&"reel.L", &"reel.R"]:
		b.part(reel, _cyl(0.38, 0.38, 0.1, 18), &"brass", Vector3.ZERO, Vector3(0, 0, PI * 0.5))
		b.part(reel, _cyl(0.12, 0.12, 0.14, 6), &"metal", Vector3.ZERO, Vector3(0, 0, PI * 0.5))
		for i: int in 6:
			var a := TAU * float(i) / 6.0
			b.part(reel, _box(0.12, 0.05, 0.05), &"metal", Vector3(0, sin(a) * 0.22, cos(a) * 0.22), Vector3(a, 0, 0))
		b.part(reel, _torus(0.36, 0.02, 24), &"rune_glow", Vector3.ZERO, Vector3(0, 0, PI * 0.5))
	for i: int in 3:
		var bone := StringName("armor.%d" % (i + 1))
		var obj := StringName("Armor_%d" % (i + 1))
		var a := TAU * float(i) / 3.0
		var p := Vector3(sin(a) * 0.62, 0.0, cos(a) * 0.62)
		b.part(bone, _box(0.6, 0.95, 0.12), &"stone", p, Vector3(0, a, 0), Vector3.ONE, obj)
		b.part(bone, _box(0.62, 0.08, 0.14), &"brass", p + Vector3(0, 0.34, 0), Vector3(0, a, 0), Vector3.ONE, obj)
		b.part(bone, _box(0.62, 0.08, 0.14), &"brass", p - Vector3(0, 0.34, 0), Vector3(0, a, 0), Vector3.ONE, obj)
		b.part(bone, _box(0.08, 0.3, 0.02), &"rune_glow", p + Vector3(sin(a), 0, cos(a)) * 0.07, Vector3(0, a, 0), Vector3.ONE, obj)


# ───────────────────────────── clips ─────────────────────────────

static func _bake(b: ActorRigBuilder, type: StringName, clip: StringName) -> Animation:
	var loop := clip == &"idle" or clip == &"move"
	var bake := ActorRigBuilder.ClipBake.new(1.0 if clip != &"idle" else 2.0, loop, b, b.bone_names())
	var names := b.bone_names()
	var length := bake.anim.length
	var n := roundi(length * SAMPLE_FPS)
	for i: int in n + 1:
		var tt := length * float(i) / float(n)
		var u := tt / length
		var pose: Dictionary[StringName, Array] = {}
		for nm: StringName in names:
			pose[nm] = [Vector3.ZERO, Vector3.ZERO, Vector3.ONE]
		_pose(type, clip, u, tt, pose)
		for k: int in names.size():
			var e: Array = pose[names[k]]
			bake.key(k, tt, e[0], e[1], e[2])
	return bake.anim


static func _rot(pose: Dictionary[StringName, Array], bone: StringName, r: Vector3) -> void:
	if pose.has(bone):
		pose[bone][0] = r


static func _off(pose: Dictionary[StringName, Array], bone: StringName, o: Vector3) -> void:
	if pose.has(bone):
		pose[bone][1] = o


## One sample of an enemy clip (prototype enemyView.ts animate(), baked). u = 0..1 through the clip.
static func _pose(type: StringName, clip: StringName, u: float, tt: float, pose: Dictionary[StringName, Array]) -> void:
	var moving := 1.0 if clip == &"move" else 0.0
	var walk := u * TAU
	var sw := sin(walk) * moving
	var breathe := sin(u * TAU) * 0.008
	var tele := ActorMath.ease_out_cubic(u) if clip == &"telegraph" else 0.0
	var atk := u if clip == &"attack" else -1.0
	var bob := absf(cos(walk)) * moving
	match type:
		EnemyType.GRUNT:
			_off(pose, &"body", Vector3(0, bob * 0.03 + breathe, 0))
			_rot(pose, &"leg.L", Vector3(sw * 0.6, 0, 0))
			_rot(pose, &"leg.R", Vector3(-sw * 0.6, 0, 0))
			_rot(pose, &"arm.L", Vector3(-sw * 0.4, 0, 0))
			if tele > 0.0:
				_rot(pose, &"arm.R", Vector3(-2.6 * tele, 0, 0))
				_rot(pose, &"body", Vector3(-0.15 * tele, 0, 0))
			elif atk >= 0.0:
				var k := ActorMath.ease_out_cubic(minf(1.0, atk * 3.0))
				_rot(pose, &"arm.R", Vector3(lerpf(-2.6, -0.8, k), 0, 0))
				_rot(pose, &"body", Vector3(0.3 * k * (1.0 - atk * 0.6), 0, 0))
			else:
				_rot(pose, &"arm.R", Vector3(sw * 0.4, 0, 0))
		EnemyType.STALKER:
			_off(pose, &"body", Vector3(0, bob * 0.04 + breathe, 0))
			_rot(pose, &"body", Vector3(0.1 * moving, 0, 0))
			_rot(pose, &"leg.L", Vector3(sw * 0.8, 0, 0))
			_rot(pose, &"leg.R", Vector3(-sw * 0.8, 0, 0))
			_rot(pose, &"tail", Vector3(sin(u * TAU * 2.0) * 0.15, sin(u * TAU * 3.0) * 0.4, 0))
			_rot(pose, &"arm.L", Vector3(-0.3 - sw * 0.3, 0, 0))
			_rot(pose, &"arm.R", Vector3(-0.3 + sw * 0.3, 0, 0))
			if tele > 0.0:
				_off(pose, &"body", Vector3(0, -0.1 * tele, 0))
				_rot(pose, &"body", Vector3(-0.35 * tele, 0, 0))
				_rot(pose, &"arm.L", Vector3(-2.1 * tele, 0, 0.5 * tele))
				_rot(pose, &"arm.R", Vector3(-2.1 * tele, 0, -0.5 * tele))
			elif atk >= 0.0:
				var k := ActorMath.ease_out_cubic(minf(1.0, atk * 2.5))
				_off(pose, &"body", Vector3(0, 0, 0.25 * k * (1.0 - atk)))
				_rot(pose, &"body", Vector3(0.4 * k * (1.0 - atk * 0.7), 0, 0))
				_rot(pose, &"arm.L", Vector3(lerpf(-2.1, -1.2, k), 0, lerpf(0.5, -0.6, k)))
				_rot(pose, &"arm.R", Vector3(lerpf(-2.1, -1.2, k), 0, lerpf(-0.5, 0.6, k)))
		EnemyType.TURRET:
			_off(pose, &"aim", Vector3(0, breathe * 0.5, 0))
			if tele > 0.0:
				_rot(pose, &"barrels", Vector3(0, 0, u * TAU * 2.0 * tele))
			if atk >= 0.0:
				_off(pose, &"barrels", Vector3(0, 0, -0.08 * (1.0 - ActorMath.ease_out_cubic(atk))))
		EnemyType.SHIELDER:
			_off(pose, &"body", Vector3(0, bob * 0.025 + breathe, 0))
			_rot(pose, &"leg.L", Vector3(sw * 0.5, 0, 0))
			_rot(pose, &"leg.R", Vector3(-sw * 0.5, 0, 0))
			if tele > 0.0:
				_off(pose, &"shield", Vector3(0, 0, -0.12 * tele))
			if atk >= 0.0:
				_off(pose, &"shield", Vector3(0, 0, 0.22 * ActorMath.ease_out_cubic(minf(1.0, atk * 3.0)) * (1.0 - atk * 0.5)))
			_rot(pose, &"arm.R", Vector3(-sw * 0.4 - tele * 1.2, 0, 0))
		EnemyType.BRUTE:
			_off(pose, &"body", Vector3(0, bob * 0.04 + breathe * 2.0, 0))
			_rot(pose, &"body", Vector3(0.15, 0, 0))
			_rot(pose, &"leg.L", Vector3(sw * 0.45, 0, 0))
			_rot(pose, &"leg.R", Vector3(-sw * 0.45, 0, 0))
			_rot(pose, &"arm.L", Vector3(-sw * 0.35, 0, 0))
			_rot(pose, &"arm.R", Vector3(sw * 0.35, 0, 0))
			if tele > 0.0:
				_rot(pose, &"arm.L", Vector3(-2.9 * tele, 0, 0))
				_rot(pose, &"arm.R", Vector3(-2.9 * tele, 0, 0))
				_rot(pose, &"body", Vector3(0.15 - 0.35 * tele, 0, 0))
				_off(pose, &"body", Vector3(0, 0.08 * tele, 0))
			elif atk >= 0.0:
				var k := ActorMath.ease_in_cubic(minf(1.0, atk * 4.0))
				var rise := ActorMath.smooth(0.5, 1.0, atk)
				_rot(pose, &"arm.L", Vector3(lerpf(lerpf(-2.9, -0.5, k), 0.0, rise), 0, 0))
				_rot(pose, &"arm.R", Vector3(lerpf(lerpf(-2.9, -0.5, k), 0.0, rise), 0, 0))
				_rot(pose, &"body", Vector3(lerpf(lerpf(-0.2, 0.5, k), 0.15, rise), 0, 0))
				_off(pose, &"body", Vector3(0, -0.1 * k * (1.0 - rise), 0))
		EnemyType.DRONE:
			_off(pose, &"body", Vector3(0, sin(u * TAU) * 0.06, 0))
			_rot(pose, &"body", Vector3(0.15 * moving + (-0.1 * tele if tele > 0.0 else 0.0), 0, sin(u * TAU) * 0.06))
			_rot(pose, &"rotor.A", Vector3(0.1, u * TAU * 3.0, 0))
			_rot(pose, &"rotor.B", Vector3(0, -u * TAU * 4.0, 0))
			if atk >= 0.0:
				_off(pose, &"body", Vector3(0, 0, -0.08 * (1.0 - atk)))
		EnemyType.BOSS:
			_off(pose, &"body", Vector3(0, sin(u * TAU) * 0.04, 0))
			_rot(pose, &"reel.L", Vector3(u * TAU, 0, 0))
			_rot(pose, &"reel.R", Vector3(-u * TAU, 0, 0))
			if tele > 0.0:
				_off(pose, &"body", Vector3(0, 0.15 * tele, 0))
				_rot(pose, &"body", Vector3(-0.1 * tele, 0, 0))
				_rot(pose, &"eye", Vector3(0, 0, 0))
			elif atk >= 0.0:
				var k := ActorMath.ease_out_cubic(minf(1.0, atk * 3.0))
				_off(pose, &"body", Vector3(0, 0.15 * (1.0 - k) - 0.08 * k * (1.0 - atk), 0))
				_rot(pose, &"body", Vector3(0.08 * k * (1.0 - atk), 0, 0))
			for i: int in 3:
				# Plates breathe slightly against the column.
				_off(pose, StringName("armor.%d" % (i + 1)), Vector3(0, sin(u * TAU + i) * 0.01, 0))
	# Stagger wobble and the death collapse act on the root (any type).
	if clip == &"stagger":
		var amp := (1.0 - u) * 0.35
		_rot(pose, &"root", Vector3(sin(tt * 23.0 + 1.0) * amp * 0.6, 0, sin(tt * 32.0) * amp))
		_off(pose, &"root", Vector3(0, absf(sin(tt * 16.0)) * 0.04 * (1.0 - u), 0))
	elif clip == &"death":
		var s := 1.0 - ActorMath.ease_in_cubic(u) * 0.9
		pose[&"root"] = [Vector3(0.2 * u, 0, 0.1 * u), Vector3(0, -u * 0.15, 0), Vector3(1.0 + u * 0.2, s, 1.0 + u * 0.2)]
