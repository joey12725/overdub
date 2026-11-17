class_name ActorGear
extends RefCounted
## Equipped gear on Moxie (APPAREL-03, WEAPON-04): the melee weapon model from
## assets/models/weapons/<item id>.glb (origin at the grip, business end along +Y), attached to bone
## hand.R, and headgear built per helmet look variant, attached to the head bone. Headgear always sits
## between the ear cups and under the headband: a helmet never hides the headphones (CHAR-05).
## While a weapon file is missing a clearly-temporary primitive stand-in of the right style is used.

const WEAPON_DIR: String = "res://assets/models/weapons/"
## Stand-in Moxie head proportions (MoxieStandin.S) - headgear is authored in those units and scaled
## to the actual model's height.
const STANDIN_TOP: float = 1.57


## Merges primitives into one static ArrayMesh, one surface per material name.
class MeshBuilder:
	extends RefCounted
	var _parts: Array = []
	var _colors: Dictionary[StringName, Color] = {}

	func add(mesh: PrimitiveMesh, mat: StringName, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> void:
		_parts.append([mesh.get_mesh_arrays(), mat, Transform3D(Basis.from_euler(rot, EULER_ORDER_XYZ) * Basis.from_scale(scl), pos)])
		_colors[mat] = color

	func build(node_name: String) -> MeshInstance3D:
		var mesh := ArrayMesh.new()
		for mat: StringName in _colors:
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var uvs := PackedVector2Array()
			var idx := PackedInt32Array()
			for p: Array in _parts:
				if p[1] != mat:
					continue
				var arrays: Array = p[0]
				var xf: Transform3D = p[2]
				var nb := xf.basis.inverse().transposed()
				var pv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var pn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var pi: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var base := verts.size()
				for v: int in pv.size():
					verts.append(xf * pv[v])
					norms.append((nb * pn[v]).normalized())
					uvs.append(Vector2.ZERO)
				for k: int in pi.size():
					idx.append(base + pi[k])
			var arr: Array = []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_NORMAL] = norms
			arr[Mesh.ARRAY_TEX_UV] = uvs
			arr[Mesh.ARRAY_INDEX] = idx
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var si := mesh.get_surface_count() - 1
			var m := StandardMaterial3D.new()
			m.resource_name = String(mat)
			m.albedo_color = _colors[mat]
			mesh.surface_set_material(si, m)
			mesh.surface_set_name(si, String(mat))
		var mi := MeshInstance3D.new()
		mi.name = node_name
		mi.mesh = mesh
		return mi


static func _box(x: float, y: float, z: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(x, y, z)
	return m


static func _cyl(top: float, bottom: float, h: float, segs: int = 10) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return m


static func _sphere(r: float, segs: int = 10) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = segs
	m.rings = maxi(4, segs / 2)
	return m


static func _cone(r: float, h: float, segs: int = 6) -> CylinderMesh:
	return _cyl(0.0, r, h, segs)


## The melee weapon for an item id: its .glb if present, else a stand-in by style / variant.
## Returns [node, is_standin].
static func weapon(item_id: String, melee: MeleeWeaponDef, look: GearLook) -> Array:
	var path := WEAPON_DIR + item_id + ".glb"
	if not item_id.is_empty() and ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene != null:
			var n := scene.instantiate() as Node3D
			if n != null:
				n.name = "Weapon"
				return [n, false]
	return [weapon_standin(String(melee.style), look.variant if look != null else "", look.color_or(Color("#e8e6df")) if look != null else Color("#e8e6df"), melee.reach), true]


## Clearly-temporary weapon stand-in: grip at the origin, business end along +Y.
static func weapon_standin(style: String, variant: String, color: Color, reach: float) -> Node3D:
	var b := MeshBuilder.new()
	var grip := Color("#2a2328")
	var metal := Color("#9aa0a6")
	match style:
		"blunt":
			b.add(_cyl(0.022, 0.022, 0.5), &"weapon_grip", grip, Vector3(0, 0.2, 0))
			b.add(_box(0.2, 0.14, 0.14), &"weapon", color, Vector3(0, 0.48, 0))
			b.add(_box(0.05, 0.12, 0.12), &"weapon_glow", Color("#ff4fa3"), Vector3(0.1, 0.48, 0))
		"whip":
			b.add(_cyl(0.022, 0.022, 0.16), &"weapon_grip", grip, Vector3(0, 0.05, 0))
			var y := 0.13
			for i: int in 6:
				b.add(_cyl(0.012, 0.012, 0.12), &"weapon", color, Vector3(0.0, y + 0.06, -0.015 * float(i * i)), Vector3(-0.08 * float(i), 0, 0))
				y += 0.115
			b.add(_sphere(0.025), &"weapon_glow", Color("#ffd23f"), Vector3(0, y + 0.03, -0.55))
		"gauntlet":
			b.add(_box(0.11, 0.1, 0.12), &"weapon", color, Vector3(0, -0.02, 0.01))
			b.add(_cyl(0.035, 0.035, 0.03, 12), &"weapon_glow", Color("#ffd23f"), Vector3(0, -0.02, 0.075), Vector3(PI * 0.5, 0, 0))
			b.add(_box(0.12, 0.03, 0.13), &"weapon_grip", grip, Vector3(0, 0.04, 0.01))
		_:
			if variant == "glaive":
				b.add(_cyl(0.018, 0.018, 1.1), &"weapon_grip", grip, Vector3(0, 0.2, 0))
				b.add(_box(0.08, 0.32, 0.015), &"weapon", color, Vector3(0, 0.88, 0))
				b.add(_box(0.06, 0.2, 0.012), &"weapon", color, Vector3(0, -0.45, 0))
				b.add(_box(0.012, 0.3, 0.018), &"weapon_glow", Color("#b14cff"), Vector3(0.03, 0.88, 0))
			else:
				var blade := clampf(reach * 0.42, 0.25, 0.7) if variant != "shiv" else 0.22
				b.add(_cyl(0.02, 0.02, 0.13), &"weapon_grip", grip, Vector3(0, 0.0, 0))
				b.add(_box(0.12, 0.025, 0.04), &"weapon_guard", metal, Vector3(0, 0.08, 0))
				b.add(_box(0.05, blade, 0.012), &"weapon", color, Vector3(0, 0.09 + blade * 0.5, 0))
				b.add(_box(0.01, blade * 0.9, 0.016), &"weapon_glow", Color("#7fe7ff"), Vector3(0.018, 0.09 + blade * 0.5, 0))
	var mi := b.build("WeaponStandin")
	var root := Node3D.new()
	root.name = "Weapon"
	root.add_child(mi)
	return root


## Headgear for a helmet look (variant: cap, hood, crown, visor, goggles, antenna, beanie, mask).
## Built in stand-in head units relative to the head bone, scaled by `scale`. Null for no headgear.
static func headgear(look: GearLook, scale: float) -> Node3D:
	if look == null:
		return null
	var c := look.color_or(Color("#3c4250"))
	var v := look.variant
	if v.is_empty() and look.color.is_empty():
		return null
	var s := MoxieStandin.S * scale
	var b := MeshBuilder.new()
	match v:
		"cap":
			# Flat crown cap under the headband, brim forward.
			b.add(_sphere(0.13 * s, 14), &"helmet", c, Vector3(0, 0.2, -0.01) * s, Vector3.ZERO, Vector3(0.9, 0.5, 1.0))
			b.add(_box(0.13 * s, 0.012 * s, 0.1 * s), &"helmet", c, Vector3(0, 0.215, 0.14) * s, Vector3(0.12, 0, 0))
			b.add(_box(0.04 * s, 0.02 * s, 0.01 * s), &"helmet_trim", Color("#f6c12b"), Vector3(0, 0.235, 0.115) * s)
		"hood":
			# A drape behind the head and below the band, narrower than the ear-cup gap.
			b.add(_sphere(0.14 * s, 14), &"helmet", c, Vector3(0, 0.1, -0.07) * s, Vector3.ZERO, Vector3(0.78, 1.05, 0.8))
			b.add(_box(0.16 * s, 0.1 * s, 0.05 * s), &"helmet", c, Vector3(0, -0.02, -0.12) * s)
		"crown":
			for i: int in 7:
				var a := TAU * float(i) / 7.0
				b.add(_cone(0.022 * s, 0.07 * s), &"helmet", c, Vector3(sin(a) * 0.075, 0.29, cos(a) * 0.075) * s)
			b.add(_cyl(0.085 * s, 0.085 * s, 0.025 * s, 14), &"helmet_glow", c, Vector3(0, 0.26, 0) * s)
		"visor":
			b.add(_box(0.2 * s, 0.035 * s, 0.03 * s), &"helmet", c, Vector3(0, 0.13, 0.12) * s)
			b.add(_box(0.17 * s, 0.022 * s, 0.01 * s), &"helmet_glow", Color("#58f0ff"), Vector3(0, 0.13, 0.137) * s)
		"goggles":
			b.add(_box(0.2 * s, 0.018 * s, 0.02 * s), &"helmet", c.darkened(0.4), Vector3(0, 0.2, 0.1) * s, Vector3(-0.5, 0, 0))
			for side: float in [1.0, -1.0]:
				b.add(_cyl(0.03 * s, 0.03 * s, 0.03 * s, 12), &"helmet", c, Vector3(side * 0.045, 0.215, 0.11) * s, Vector3(PI * 0.5 - 0.6, 0, 0))
				b.add(_cyl(0.022 * s, 0.022 * s, 0.006 * s, 12), &"helmet_glow", Color("#7ff3ff"), Vector3(side * 0.045, 0.227, 0.123) * s, Vector3(PI * 0.5 - 0.6, 0, 0))
		"antenna":
			for side: float in [1.0, -1.0]:
				b.add(_cyl(0.008 * s, 0.01 * s, 0.17 * s, 6), &"helmet", c, Vector3(side * 0.05, 0.33, -0.02) * s, Vector3(-0.15, 0, -side * 0.25))
				b.add(_sphere(0.018 * s, 8), &"helmet_glow", Color("#ff5577"), Vector3(side * 0.072, 0.415, -0.035) * s)
		"beanie":
			b.add(_sphere(0.13 * s, 14), &"helmet", c, Vector3(0, 0.21, -0.01) * s, Vector3.ZERO, Vector3(0.86, 0.7, 1.0))
		"mask":
			b.add(_sphere(0.07 * s, 10), &"helmet", c, Vector3(0, 0.035, 0.08) * s, Vector3.ZERO, Vector3(1.3, 0.75, 0.75))
			b.add(_box(0.05 * s, 0.006 * s, 0.01 * s), &"helmet_glow", Color("#58f0ff"), Vector3(0, 0.035, 0.135) * s)
		_:
			# A coloured helmet with an unknown variant still shows: goggles never hide the phones.
			b.add(_box(0.2 * s, 0.018 * s, 0.02 * s), &"helmet", c, Vector3(0, 0.2, 0.1) * s, Vector3(-0.5, 0, 0))
	var mi := b.build("Headgear")
	var root := Node3D.new()
	root.name = "Headgear"
	root.add_child(mi)
	return root
