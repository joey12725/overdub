class_name WorldDecor
extends RefCounted
## Decor entities (DecorDef; port of prototype render/env/decor.ts). Each type loads its kit model
## (assets/models/kit/<name>.glb, theme variants first) and falls back to a procedural stand-in in
## the house style of the R03 / R04 prop libraries. Decor never collides (types.ts DecorDef), so
## models stay low and compact unless the piece is a set-piece (arch, time machine).
##
## Graffiti is not a model: it is a Decal with a painted tag from assets/textures/graffiti/ when one
## matches the variant, else a procedural spray-paint texture (WorldGraffiti),
## projected onto the nearest camera-visible wall face or the floor, lit like the surface it is on.
##
## Orientation: `rot` quarter turns rotate the piece about +Y; rot 0 faces +Z, rot 1 faces +X.

## DecorType -> kit piece name (asset contract spelling).
const KIT_NAMES := {
	&"vines": "vines", &"bush": "bush", &"crate": "crate", &"barrel": "barrel", &"pipe": "pipe",
	&"console": "console", &"generator": "generator", &"vent": "vent", &"arch": "arch",
	&"rubble": "rubble", &"chest": "chest", &"neon": "neon", &"runePanel": "rune_panel",
	&"waveScreen": "wave_screen", &"cable": "cable", &"lamp": "lamp", &"timeMachine": "time_machine",
}

## Wall-top height the kit vines model is authored for (manifest placement note).
const VINES_WALL_TOP := 1.5

## Named neon colours a DecorDef.variant may use.
const NEON_NAMES := ["cyan", "pink", "magenta", "violet", "purple", "orange", "amber", "yellow"]

var b: WorldBuilder
var pal: WorldPalette
var layout: WorldLayout
var kit: WorldKit


func _init(builder: WorldBuilder) -> void:
	b = builder
	pal = builder.pal
	layout = builder.layout
	kit = builder.kit


func build(def: DecorDef) -> Node3D:
	var node: Node3D = null
	if def.type == DecorType.GRAFFITI:
		node = _graffiti(def)
	else:
		node = _from_kit(def)
		if node == null:
			b._note_piece(KIT_NAMES.get(def.type, String(def.type)), false)
			node = _standin(def)
		else:
			b._note_piece(KIT_NAMES.get(def.type, String(def.type)), true)
	if node == null:
		return null
	node.name = ("decor_%s" % def.type).validate_node_name()
	# Readable sibling names (decor_waveScreen, decor_waveScreen2, ...): the default for a name clash
	# is "@Node3D@<n>", which hides every piece after the first from lookups by decor name.
	b.add_node(node, true)
	return node


static func place_xform(def: DecorDef) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, def.rot * PI * 0.5), Vector3(def.x, 0.0, def.y))


func neon_color(variant: String, rng: WorldRng) -> Color:
	var v := variant.strip_edges().to_lower()
	match v:
		"cyan":
			return pal.neon_a
		"pink", "magenta":
			return pal.neon_b
		"violet", "purple":
			return pal.neon_c
		"orange":
			return pal.warm
		"amber":
			return pal.accent
		"yellow":
			return pal.hazard
	if v.length() >= 6 and Color.html_is_valid(v):
		return Color.html(v)
	return rng.pick_color([pal.neon_a, pal.neon_b, pal.neon_c])


# ───────────────────────────── wall faces ─────────────────────────────

## The camera-visible wall face nearest a point, for decals and hanging vines: {c, r, face, height}
## or {} when there is none (prototype findWallFace). With `allow_cut`, a point with no tall wall
## behind it falls back to the outer (camera-facing) face of an adjacent camera-side cut wall, so
## vines spill over the parapet toward the camera instead of standing loose on the floor.
func find_wall_face(x: float, y: float, prefer: int = 0, allow_cut: bool = false) -> Dictionary:
	var c := int(floor(x))
	var r := int(floor(y))
	if layout.is_wall(c, r):
		var faces: Array[int] = [WorldScatter.FACE_E, WorldScatter.FACE_S]
		if prefer == WorldScatter.FACE_S:
			faces = [WorldScatter.FACE_S, WorldScatter.FACE_E]
		for f: int in faces:
			var nc := c + 1 if f == WorldScatter.FACE_E else c
			var nr := r + 1 if f == WorldScatter.FACE_S else r
			if not layout.is_wall(nc, nr):
				return {"c": c, "r": r, "face": f, "height": layout.wall_height(c, r)}
		return {}
	var options: Array[Dictionary] = []
	if layout.is_wall(c - 1, r) and layout.wall_height(c - 1, r) > WorldLayout.WALL_CUT_HEIGHT + 0.01:
		options.append({"c": c - 1, "r": r, "face": WorldScatter.FACE_E})
	if layout.is_wall(c, r - 1) and layout.wall_height(c, r - 1) > WorldLayout.WALL_CUT_HEIGHT + 0.01:
		options.append({"c": c, "r": r - 1, "face": WorldScatter.FACE_S})
	if options.is_empty() and allow_cut:
		if layout.is_wall(c + 1, r) and not layout.is_wall(c + 2, r):
			options.append({"c": c + 1, "r": r, "face": WorldScatter.FACE_E})
		if layout.is_wall(c, r + 1) and not layout.is_wall(c, r + 2):
			options.append({"c": c, "r": r + 1, "face": WorldScatter.FACE_S})
	if options.is_empty():
		return {}
	var pick: Dictionary = options[0]
	for o: Dictionary in options:
		if o["face"] == prefer:
			pick = o
	pick["height"] = layout.wall_height(pick["c"], pick["r"])
	return pick


# ───────────────────────────── graffiti ─────────────────────────────

func _graffiti(def: DecorDef) -> Node3D:
	var seed_v := WorldRng.hash_string("%s,%s,%s" % [def.x, def.y, def.variant]) ^ b._seed
	var rng := WorldRng.new(seed_v)
	var paint := pal.graffiti if rng.chance(0.5) else pal.graffiti_alt
	var tex: Texture2D = WorldGraffiti.painted(def.variant, seed_v)
	var painted := tex != null
	if not painted:
		tex = WorldGraffiti.texture(def.variant, paint, seed_v)
	var d := Decal.new()
	d.texture_albedo = tex
	d.albedo_mix = 1.0
	d.cull_mask = WorldBuilder.ENV_LAYER
	d.normal_fade = 0.35
	d.upper_fade = 0.05
	d.lower_fade = 0.05
	var prefer := 0
	if def.rot == 1 or def.rot == 3:
		prefer = WorldScatter.FACE_E
	elif def.rot == 0 or def.rot == 2:
		prefer = WorldScatter.FACE_S
	var face := find_wall_face(def.x, def.y, prefer)
	if not face.is_empty() and float(face["height"]) > 0.6:
		var fc: int = face["c"]
		var fr: int = face["r"]
		var f: int = face["face"]
		var h: float = face["height"]
		# Tags sprawl across neighbouring blocks when the wall continues; a lone block keeps them small.
		var n := 0
		if f == WorldScatter.FACE_E:
			n = int(_tall(fc, fr - 1, h)) + int(_tall(fc, fr + 1, h))
		else:
			n = int(_tall(fc - 1, fr, h)) + int(_tall(fc + 1, fr, h))
		var size := minf(h * 0.95, 1.75 if n == 2 else (1.35 if n == 1 else 1.05))
		var along := 0.0
		if not (fc == int(floor(def.x)) and fr == int(floor(def.y))):
			along = -(def.y - (fr + 0.5)) if f == WorldScatter.FACE_E else def.x - (fc + 0.5)
		along = clampf(along, -0.2, 0.2)
		var mount := WorldScatter.mount_on_face(fc, fr, f, minf(h * 0.55, 0.95), along, 0.0)
		# Decal projects along its local -Y: local +Y = the face normal, local +Z = down.
		var normal := mount.basis.z
		var down := Vector3.DOWN
		var x_axis := normal.cross(down)
		d.transform = Transform3D(Basis(x_axis, normal, down), mount.origin)
		d.size = Vector3(size, 0.4, size)
	else:
		var basis := Basis(Vector3.UP, def.rot * PI * 0.5)
		d.transform = Transform3D(basis, Vector3(def.x, 0.0, def.y))
		d.size = Vector3(0.95, 0.3, 0.95)
	var holder := Node3D.new()
	holder.add_child(d)
	# Painted tags count as authored art in build_stats; procedural ones as generated stand-ins.
	b._note_piece("graffiti", painted)
	return holder


func _tall(c: int, r: int, h: float) -> bool:
	return layout.is_wall(c, r) and layout.wall_height(c, r) >= h * 0.8


# ───────────────────────────── kit models ─────────────────────────────

func _from_kit(def: DecorDef) -> Node3D:
	var piece_name: String = KIT_NAMES.get(def.type, String(def.type))
	if kit == null or not kit.has_model(piece_name):
		return null
	var opts := ToonKit.Options.new()
	opts.outline_color = pal.ink
	var n := kit.instance(piece_name, int(floor(def.x)), int(floor(def.y)), opts)
	if n == null:
		return null
	var at := Vector2(def.x, def.y)
	_register_glows(n, at, def)
	var xf := place_xform(def)
	if def.type == DecorType.VINES:
		# Kit vines (manifest placement): origin at the foot of the wall face, hanging in +Z from a
		# wall top at y = 1.5; scale Y by wall_height / 1.5 to fit the wall they drape over.
		var face := find_wall_face(def.x, def.y, WorldScatter.FACE_E if def.rot == 1 else 0, true)
		if not face.is_empty():
			var h: float = face["height"]
			var along := 0.0
			if int(face["face"]) == WorldScatter.FACE_E:
				along = clampf(-(def.y - (int(face["r"]) + 0.5)), -0.25, 0.25)
			else:
				along = clampf(def.x - (int(face["c"]) + 0.5), -0.25, 0.25)
			xf = WorldScatter.mount_on_face(face["c"], face["r"], face["face"], 0.0, along, 0.0)
			xf = xf.scaled_local(Vector3(1.0, maxf(0.25, h / VINES_WALL_TOP), 1.0))
	n.transform = xf
	_dress(def, at)
	return n


## Register every `*_glow` surface of a model as music-reactive, tinting neon by variant.
func _register_glows(n: Node, at: Vector2, def: DecorDef) -> void:
	var stack: Array[Node] = [n]
	var seen := {}
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		for ch: Node in x.get_children():
			stack.append(ch)
		var mi := x as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s: int in range(mi.mesh.get_surface_count()):
			var m := mi.get_surface_override_material(s) as ShaderMaterial
			if m == null or m.shader != ToonKit.GLOW_SHADER or seen.has(m):
				continue
			seen[m] = true
			var mname := m.resource_name
			if not def.variant.is_empty() and (def.type == DecorType.NEON or def.type == DecorType.LAMP) and mname.begins_with("neon"):
				m.set_shader_parameter(&"color", neon_color(def.variant, WorldRng.new(1)))
			var kind := MusicReactive.KIND_NEON
			if mname.contains("rune"):
				kind = MusicReactive.KIND_RUNE
			elif mname.contains("screen") or mname.contains("wave"):
				kind = MusicReactive.KIND_SCREEN
			elif mname.contains("core") or def.type == DecorType.TIME_MACHINE and mname.contains("chrono"):
				kind = MusicReactive.KIND_CORE
			b.register_reactive(kind, m, &"energy", float(m.get_shader_parameter(&"energy")), at)


## Contact shadow and practical light for a decor piece (shared by model and stand-in).
func _dress(def: DecorDef, at: Vector2) -> void:
	match def.type:
		DecorType.BUSH, DecorType.CONSOLE, DecorType.VENT, DecorType.CHEST, DecorType.CABLE:
			b.blob(at.x, at.y, 0.45)
		DecorType.CRATE, DecorType.RUBBLE:
			b.blob(at.x, at.y, 0.5, 0.7)
		DecorType.BARREL:
			b.blob(at.x, at.y, 0.36)
		DecorType.GENERATOR:
			b.blob(at.x, at.y, 0.6)
			b.practical(Vector3(at.x, 0.7, at.y), pal.warm if pal.floor_finish == WorldPalette.FINISH_STONE else pal.neon_b, 1.4, 3.0)
		DecorType.NEON:
			b.blob(at.x, at.y, 0.3)
			b.practical(Vector3(at.x, 0.6, at.y), neon_color(def.variant, WorldRng.new(WorldRng.hash_string("n%s,%s" % [def.x, def.y]) ^ b._seed)), 1.8, 3.2)
		DecorType.LAMP:
			b.blob(at.x, at.y, 0.3)
			var lc := neon_color(def.variant, WorldRng.new(1)) if not def.variant.is_empty() else pal.warm
			# Pale stone saturates fast under a close practical; keep the pool warm, not blown out.
			var stone_wall := pal.floor_finish != WorldPalette.FINISH_METAL
			b.practical(Vector3(at.x, 1.1, at.y), lc, 1.1 if stone_wall else 2.2, 3.4 if stone_wall else 4.0)
		DecorType.RUNE_PANEL:
			b.blob(at.x, at.y, 0.4)
		DecorType.WAVE_SCREEN:
			b.blob(at.x, at.y, 0.5)
		DecorType.ARCH:
			var a := def.rot * PI * 0.5
			var off := Vector2(cos(a), -sin(a)) * 0.6
			b.blob(at.x - off.x, at.y - off.y, 0.35)
			b.blob(at.x + off.x, at.y + off.y, 0.35)
		DecorType.TIME_MACHINE:
			b.blob(at.x, at.y, 1.8, 0.7)
			b.practical(Vector3(at.x, 1.6, at.y), pal.accent, 4.0, 6.0)
	if def.type == DecorType.CHEST and def.variant == "open":
		b.practical(Vector3(at.x, 0.6, at.y), pal.accent, 1.0, 2.4)


# ───────────────────────────── stand-ins ─────────────────────────────

func _part(parent: Node3D, m: Mesh, material: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _box(size: Vector3, bevel: float = 0.03, y0: float = 0.0) -> Mesh:
	return b.mesh("box:%s:%s:%s" % [size, bevel, y0], func() -> Mesh: return WorldGeom.chamfer_box(size, bevel, y0))


func _cyl(r0: float, r1: float, h: float, sides: int = 10, axis: int = 1) -> Mesh:
	return b.mesh("cyl:%s:%s:%s:%d:%d" % [r0, r1, h, sides, axis], func() -> Mesh:
		var bld := WorldGeom.Builder.new()
		WorldGeom.cylinder_into(bld, Vector3.ZERO, r0, r1, h, sides, axis)
		return bld.build())


func _ring(big_r: float, r: float, segs: int = 24) -> Mesh:
	return b.mesh("ring:%s:%s:%d" % [big_r, r, segs], func() -> Mesh:
		var bld := WorldGeom.Builder.new()
		WorldGeom.ring_into(bld, Vector3.ZERO, big_r, r, segs, 6)
		return bld.build())


func _utility_color() -> Color:
	if pal.floor_finish == WorldPalette.FINISH_STONE:
		return pal.hazard
	if pal.floor_finish == WorldPalette.FINISH_MIXED:
		return WorldPalette.mix_color(pal.hazard, pal.metal, 0.35)
	return pal.metal


func _standin(def: DecorDef) -> Node3D:
	var g := Node3D.new()
	var at := Vector2(def.x, def.y)
	var stone := pal.floor_finish == WorldPalette.FINISH_STONE
	var rng := WorldRng.new(WorldRng.hash_string("%s%s,%s" % [def.type, def.x, def.y]) ^ b._seed)
	match def.type:
		DecorType.VINES:
			return _vines_standin(def)
		DecorType.BUSH:
			for i: int in range(rng.range_i(3, 5)):
				var k := rng.range_i(0, 3)
				var a := float(i) * TAU / 4.0
				var d := 0.0 if i == 0 else rng.range_f(0.12, 0.24)
				var leaf := b.mesh("leaf%d" % k, func() -> Mesh: return WorldGeom.leaf_clump(k, 0.5))
				var p := _part(g, leaf, b.toon(WorldPalette.scale_color(pal.foliage, rng.range_f(0.8, 1.15))), Vector3(cos(a) * d, 0, sin(a) * d))
				p.scale = Vector3.ONE * (1.2 if i == 0 else rng.range_f(0.7, 1.0))
		DecorType.CRATE:
			var base := _utility_color() if rng.chance(0.6) else (pal.metal if stone else WorldPalette.mix_color(pal.metal, pal.trim, 0.3))
			_part(g, _box(Vector3(0.62, 0.48, 0.62), 0.05), b.toon(base))
			_part(g, _box(Vector3(0.66, 0.06, 0.66), 0.01, 0.4), b.toon(WorldPalette.scale_color(base, 0.7)))
			if def.variant == "stack" or (def.variant.is_empty() and rng.chance(0.4)):
				var top := _part(g, _box(Vector3(0.42, 0.34, 0.42), 0.04), b.toon(WorldPalette.scale_color(base, 1.08)), Vector3(rng.range_f(-0.06, 0.06), 0.48, rng.range_f(-0.06, 0.06)))
				top.rotation.y = rng.range_f(-0.4, 0.4)
		DecorType.BARREL:
			var colors := {"red": Color("#c8323a"), "yellow": pal.hazard, "pink": pal.graffiti, "rust": pal.rust, "metal": pal.metal}
			var col: Color = colors.get(def.variant, rng.pick_color([Color("#c8323a"), pal.hazard, pal.rust, pal.graffiti if stone else pal.metal]))
			_part(g, _cyl(0.23, 0.23, 0.62, 12), b.toon(col), Vector3(0, 0.31, 0))
			for y: float in [0.14, 0.48]:
				_part(g, _cyl(0.245, 0.245, 0.05, 12), b.toon(WorldPalette.scale_color(col, 0.6)), Vector3(0, y, 0))
		DecorType.PIPE:
			var col := pal.metal if pal.floor_finish == WorldPalette.FINISH_METAL else pal.hazard
			var m := b.toon(col)
			_part(g, _cyl(0.11, 0.11, 0.56, 10), m, Vector3(-0.49, 0.28, 0))
			_part(g, _cyl(0.11, 0.11, 0.56, 10), m, Vector3(0.49, 0.28, 0))
			_part(g, _cyl(0.11, 0.11, 1.1, 10, 0), m, Vector3(0, 0.56, 0))
			for x: float in [-0.49, 0.49]:
				_part(g, _cyl(0.155, 0.155, 0.05, 10), b.toon(WorldPalette.scale_color(col, 0.65)), Vector3(x, 0.03, 0))
			if not stone:
				_part(g, _cyl(0.145, 0.145, 0.06, 10, 0), b.glow(pal.neon_b, 2.4), Vector3(0, 0.56, 0), Vector3.ZERO, false)
		DecorType.CONSOLE:
			var body := pal.metal if stone else WorldPalette.mix_color(pal.metal, pal.trim, 0.2)
			_part(g, _box(Vector3(0.62, 0.52, 0.42), 0.04), b.toon(body))
			var head := _part(g, _box(Vector3(0.62, 0.08, 0.36), 0.02, -0.04), b.toon(WorldPalette.scale_color(body, 0.8)), Vector3(0, 0.6, 0.02), Vector3(0.5, 0, 0))
			head.name = "Head"
			var screen := _screen_material(pal.neon_a, rng.range_i(0, 999), false, at)
			_part(g, _box(Vector3(0.48, 0.01, 0.24), 0.0, 0.0), screen, Vector3(0, 0.645, 0.04), Vector3(0.5, 0, 0), false)
			var bcols: Array[Color] = [pal.hazard, pal.neon_b, Color("#7dff9a")]
			for i: int in range(3):
				_part(g, _box(Vector3(0.06, 0.03, 0.05), 0.0), b.glow(bcols[i], 1.4), Vector3(-0.18 + i * 0.12, 0.43, 0.215), Vector3.ZERO, false)
		DecorType.GENERATOR:
			var col := _utility_color()
			_part(g, _box(Vector3(0.86, 0.12, 0.62), 0.03), b.toon(pal.trim))
			_part(g, _cyl(0.26, 0.26, 0.74, 14, 0), b.toon(col), Vector3(0, 0.42, 0))
			for x: float in [-0.36, 0.36]:
				_part(g, _cyl(0.29, 0.29, 0.06, 14, 0), b.toon(WorldPalette.scale_color(col, 0.65)), Vector3(x, 0.42, 0))
			_part(g, _box(Vector3(0.3, 0.28, 0.22), 0.03), b.toon(pal.metal), Vector3(0.12, 0.62, 0))
			_part(g, _cyl(0.05, 0.05, 0.4, 8), b.toon(pal.metal), Vector3(-0.25, 0.85, -0.1))
			var glow_c := pal.warm if stone else pal.neon_b
			_part(g, _box(Vector3(0.4, 0.06, 0.02), 0.0, -0.03), b.glow(glow_c, 2.6, MusicReactive.KIND_NEON, at), Vector3(0, 0.45, 0.262), Vector3.ZERO, false)
			var fan := _part(g, _box(Vector3(0.03, 0.34, 0.06), 0.0, -0.17), b.toon(pal.trim), Vector3(0.39, 0.42, 0))
			b.animators.append(func(t: float, _dt: float) -> void: fan.rotation.x = t * 9.0)
		DecorType.VENT:
			var casing := Color("#e8e0d0") if stone else pal.metal
			_part(g, _box(Vector3(0.64, 0.6, 0.42), 0.05), b.toon(casing))
			_part(g, _cyl(0.22, 0.22, 0.02, 20, 2), b.toon(WorldPalette.scale_color(pal.grout, 0.6), 0.0), Vector3(0, 0.3, 0.212), Vector3.ZERO, false)
			_part(g, _ring(0.22, 0.025, 20), b.toon(WorldPalette.scale_color(casing, 0.7), 1.0), Vector3(0, 0.3, 0.215), Vector3(PI * 0.5, 0, 0), false)
			var blades := Node3D.new()
			blades.position = Vector3(0, 0.3, 0.222)
			g.add_child(blades)
			for i: int in range(3):
				_part(blades, _box(Vector3(0.06, 0.38, 0.01), 0.0, -0.19), b.toon(WorldPalette.scale_color(casing, 0.7), 0.0), Vector3.ZERO, Vector3(0, 0, i * PI / 3.0), false)
			b.animators.append(func(t: float, _dt: float) -> void: blades.rotation.z = t * 5.0)
		DecorType.ARCH:
			var sm := b.toon(pal.metal if pal.floor_finish == WorldPalette.FINISH_METAL else pal.stone)
			var cap := b.toon(pal.wall_top if pal.floor_finish == WorldPalette.FINISH_METAL else WorldPalette.scale_color(pal.stone, 1.12))
			for x: float in [-0.62, 0.62]:
				_part(g, _box(Vector3(0.3, 1.3, 0.38), 0.04), sm, Vector3(x, 0, 0))
			for i: int in range(7):
				var a := PI - float(i) / 6.0 * PI
				_part(g, _box(Vector3(0.3, 0.26, 0.38), 0.03, -0.13), cap if i == 3 else sm, Vector3(cos(a) * 0.62, 1.3 + sin(a) * 0.5, 0), Vector3(0, 0, a - PI * 0.5))
			if not stone:
				for x: float in [-0.47, 0.47]:
					_part(g, _box(Vector3(0.05, 0.8, 0.04), 0.0), b.glow(pal.neon_b, 2.6), Vector3(x, 0.2, 0.2), Vector3.ZERO, false)
			else:
				for p: Vector2 in [Vector2(-0.55, 1.25), Vector2(0.3, 1.65)]:
					_part(g, b.mesh("leaf1", func() -> Mesh: return WorldGeom.leaf_clump(1, 0.5)), b.toon(pal.foliage), Vector3(p.x, p.y, 0.05))
		DecorType.RUBBLE:
			for i: int in range(rng.range_i(4, 7)):
				var k := rng.range_i(0, 5)
				var rk := _part(g, b.mesh("rubble%d" % k, func() -> Mesh: return WorldGeom.rock(k * 977 + 3, 0.17)), b.toon(WorldPalette.scale_color(pal.stone, rng.range_f(0.82, 1.1))), Vector3(rng.range_f(-0.35, 0.35), 0, rng.range_f(-0.35, 0.35)))
				rk.rotation.y = rng.range_f(0.0, TAU)
				rk.scale = Vector3.ONE * (1.5 if i == 0 else rng.range_f(0.6, 1.1))
		DecorType.CHEST:
			var body := Color("#8a5a3a") if stone else pal.trim
			_part(g, _box(Vector3(0.62, 0.3, 0.42), 0.03), b.toon(body))
			for x: float in [-0.24, 0.24]:
				_part(g, _box(Vector3(0.06, 0.31, 0.44), 0.0), b.toon(pal.hazard), Vector3(x, 0, 0), Vector3.ZERO, false)
			var lid := Node3D.new()
			lid.position = Vector3(0, 0.3, -0.21)
			lid.rotation.x = -1.9 if def.variant == "open" else 0.0
			g.add_child(lid)
			_part(lid, _cyl(0.21, 0.21, 0.62, 10, 0), b.toon(body), Vector3(0, 0, 0.21)).scale = Vector3(1, 0.5, 1)
			_part(g, _box(Vector3(0.08, 0.1, 0.03), 0.0), b.toon(pal.hazard), Vector3(0, 0.21, 0.22), Vector3.ZERO, false)
			if def.variant == "open":
				_part(g, _box(Vector3(0.5, 0.02, 0.3), 0.0), b.glow(pal.accent, 2.2, MusicReactive.KIND_NEON, at), Vector3(0, 0.28, 0), Vector3.ZERO, false)
		DecorType.NEON:
			var col := neon_color(def.variant, WorldRng.new(WorldRng.hash_string("n%s,%s" % [def.x, def.y]) ^ b._seed))
			_part(g, _cyl(0.055, 0.055, 0.8, 10), b.glow(col, 3.0, MusicReactive.KIND_NEON, at), Vector3(0, 0.55, 0), Vector3.ZERO, false)
			var glass := b.mat("neonGlass:" + col.to_html(), func() -> Material: return ToonKit.glow_add(col, 0.5, 0.6, 0.0))
			_part(g, _cyl(0.1, 0.1, 0.82, 12), glass, Vector3(0, 0.55, 0), Vector3.ZERO, false)
			for y: float in [0.1, 1.0]:
				_part(g, _cyl(0.12, 0.13, 0.12, 10), b.toon(pal.metal), Vector3(0, y, 0))
			_part(g, _box(Vector3(0.32, 0.06, 0.32), 0.02), b.toon(pal.trim))
		DecorType.RUNE_PANEL:
			_part(g, _box(Vector3(0.62, 1.35, 0.2), 0.04), b.toon(pal.stone if stone else pal.metal))
			_part(g, _box(Vector3(0.7, 0.1, 0.26), 0.03, 1.35), b.toon(pal.wall_top))
			var col := neon_color(def.variant, WorldRng.new(1)) if not def.variant.is_empty() else pal.rune
			var face := b.mat("runeFace:" + col.to_html(), func() -> Material:
				var m := ToonKit.surface(8, 8, pal.metal, WorldPalette.scale_color(pal.metal, 0.8), pal.grout, 0.0, pal.ink)
				m.set_shader_parameter(&"glow_color", col)
				m.set_shader_parameter(&"glow_energy", 2.4)
				m.set_shader_parameter(&"glow_share", 1.0)
				m.set_shader_parameter(&"blotch", 0.0)
				return m) as ShaderMaterial
			b.register_reactive(MusicReactive.KIND_RUNE, face, &"glow_energy", 2.4, at)
			_part(g, _box(Vector3(0.42, 1.18, 0.02), 0.0), face, Vector3(0, 0.09, 0.104), Vector3.ZERO, false)
		DecorType.WAVE_SCREEN:
			var frame_m := b.toon(pal.metal if stone else pal.trim)
			_part(g, _box(Vector3(1.0, 0.66, 0.12), 0.03, 0.42), frame_m)
			for x: float in [-0.35, 0.35]:
				_part(g, _box(Vector3(0.06, 0.44, 0.06), 0.0), frame_m, Vector3(x, 0, 0))
			var col := neon_color(def.variant, WorldRng.new(1)) if not def.variant.is_empty() else pal.neon_a
			_part(g, _box(Vector3(0.86, 0.52, 0.01), 0.0, 0.49), _screen_material(col, rng.range_i(0, 999), true, at), Vector3(0, 0, 0.062), Vector3.ZERO, false)
		DecorType.CABLE:
			var spool := b.toon(pal.graffiti if stone else pal.trim)
			for z: float in [-0.14, 0.14]:
				_part(g, _cyl(0.28, 0.28, 0.04, 16, 2), spool, Vector3(0, 0.28, z))
			_part(g, _cyl(0.2, 0.2, 0.24, 14, 2), b.toon(Color("#3a3a3a") if stone else Color("#1e1a24")), Vector3(0, 0.28, 0))
		DecorType.LAMP:
			var metal := b.toon(Color("#3c342e") if stone else pal.trim)
			_part(g, _box(Vector3(0.26, 0.08, 0.26), 0.02), metal)
			_part(g, _cyl(0.035, 0.045, 0.95, 8), metal, Vector3(0, 0.5, 0))
			_part(g, _cyl(0.16, 0.0, 0.1, 6), metal, Vector3(0, 1.25, 0))
			var col := neon_color(def.variant, WorldRng.new(1)) if not def.variant.is_empty() else pal.warm
			_part(g, _cyl(0.08, 0.08, 0.18, 8), b.glow(col, 3.0, MusicReactive.KIND_NEON, at), Vector3(0, 1.08, 0), Vector3.ZERO, false)
			for i: int in range(4):
				var a := float(i) * TAU / 4.0
				_part(g, _box(Vector3(0.02, 0.24, 0.02), 0.0, -0.12), metal, Vector3(cos(a) * 0.12, 1.08, sin(a) * 0.12), Vector3.ZERO, false)
		DecorType.TIME_MACHINE:
			_time_machine(g, at)
		_:
			_part(g, _box(Vector3(0.5, 0.5, 0.5), 0.04), b.toon(pal.metal))
	g.transform = place_xform(def)
	_dress(def, at)
	return g


func _vines_standin(def: DecorDef) -> Node3D:
	var g := Node3D.new()
	var face := find_wall_face(def.x, def.y, WorldScatter.FACE_E if def.rot == 1 else 0, true)
	var leaf := b.toon(pal.foliage, 1.5)
	var dark := b.toon(WorldPalette.scale_color(pal.foliage, 0.72), 1.5)
	var seed_v := WorldRng.hash_string("v%s,%s" % [def.x, def.y]) ^ b._seed
	var rng := WorldRng.new(seed_v)
	if not face.is_empty():
		var h: float = face["height"]
		for strand: int in range(2):
			var drop := h * (0.6 + 0.35 * rng.next())
			var n := 4 + rng.range_i(0, 2)
			for i: int in range(n):
				var t := float(i) / float(n - 1)
				var k := (i + strand) % 2
				var m := b.mesh("ivy%d" % k, func() -> Mesh: return WorldGeom.leaf_clump(k + 5, 0.32))
				var xf := WorldScatter.mount_on_face(face["c"], face["r"], face["face"], h - 0.05 - t * drop, (strand - 0.5) * 0.4 + sin(t * 4.0 + strand) * 0.08, 0.03)
				var mi := _part(g, m, dark if k == 1 else leaf, Vector3.ZERO)
				mi.transform = xf.scaled_local(Vector3(1.0, 0.8, 0.45) * (1.0 - 0.3 * t))
		var top := _part(g, b.mesh("leaf2", func() -> Mesh: return WorldGeom.leaf_clump(2, 0.55)), leaf)
		top.transform = WorldScatter.mount_on_face(face["c"], face["r"], face["face"], h - 0.02, 0.0, -0.15)
		return g
	# No wall: a creeping mound.
	for i: int in range(3):
		var m := b.mesh("leaf%d" % i, func() -> Mesh: return WorldGeom.leaf_clump(i, 0.5))
		var mi := _part(g, m, b.toon(WorldPalette.scale_color(pal.foliage, 0.85 + i * 0.1)), Vector3(def.x + (i - 1) * 0.2, 0, def.y + ((i * 37) % 5) * 0.05 - 0.1))
		mi.scale = Vector3(1, 0.6, 1)
	return g


## Glow material with a scrolling waveform / console texture.
func _screen_material(col: Color, seed_v: int, wave: bool, at: Vector2) -> ShaderMaterial:
	var m := ToonKit.glow(Color.WHITE, 1.7)
	m.set_shader_parameter(&"tex", _screen_texture(col, seed_v, wave))
	m.set_shader_parameter(&"use_texture", true)
	m.set_shader_parameter(&"uv_scroll", Vector2(0.25 if wave else 0.12, 0.0))
	b.register_reactive(MusicReactive.KIND_SCREEN, m, &"energy", 1.7, at)
	return m


static func _screen_texture(col: Color, seed_v: int, wave: bool) -> ImageTexture:
	var w := 128
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var bg := Color(col.r * 0.08, col.g * 0.1, col.b * 0.12)
	img.fill(bg)
	var rng := WorldRng.new(seed_v)
	var grid := Color(col.r * 0.25, col.g * 0.25, col.b * 0.25)
	for x: int in range(0, w, 16):
		for y: int in range(h):
			img.set_pixel(x, y, grid)
	for y: int in range(0, h, 16):
		for x: int in range(w):
			img.set_pixel(x, y, grid)
	if wave:
		# A harmonograph-like waveform (two summed sines), tileable horizontally.
		var f1 := float(rng.range_i(1, 3))
		var f2 := float(rng.range_i(3, 6))
		var prev := -1
		for x: int in range(w):
			var t := float(x) / float(w) * TAU
			var y := int(h * 0.5 + (sin(t * f1) * 0.55 + sin(t * f2 + 1.3) * 0.3) * h * 0.38)
			var y0 := y if prev < 0 else prev
			for yy: int in range(mini(y0, y), maxi(y0, y) + 1):
				for d: int in range(-1, 2):
					if yy + d >= 0 and yy + d < h:
						img.set_pixel(x, yy + d, col.lerp(Color.WHITE, 0.3 if d == 0 else 0.0))
			prev = y
	else:
		# Console: rows of status bars.
		for row: int in range(5):
			var y := 6 + row * 11
			var bar_len := rng.range_i(30, 110)
			for x: int in range(8, mini(w - 4, 8 + bar_len)):
				for d: int in range(3):
					img.set_pixel(x, y + d, col if (x / 6) % 4 != 3 else col.lerp(Color.WHITE, 0.4))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## WORLD-05: the bottom loot is a time machine. Gyroscopic ring gate on a rune dais, cassette-reel
## housings (tying it to the Walkman / tape mechanics) and a chronal core.
func _time_machine(g: Node3D, at: Vector2) -> void:
	var metal := b.toon(pal.metal)
	var dark := b.toon(pal.trim)
	var brass := b.toon(Color("#c89a3a"))
	_part(g, _cyl(1.6, 1.7, 0.22, 8), dark, Vector3(0, 0.11, 0))
	_part(g, _cyl(1.2, 1.3, 0.2, 8), metal, Vector3(0, 0.32, 0))
	_part(g, _ring(1.45, 0.03, 48), b.glow(pal.accent, 2.6, MusicReactive.KIND_RUNE, at), Vector3(0, 0.225, 0), Vector3.ZERO, false)
	var strip := b.glow(pal.neon_a, 2.6, MusicReactive.KIND_NEON, at)
	for i: int in range(4):
		var a := float(i) / 4.0 * TAU + PI / 4.0
		_part(g, _box(Vector3(0.26, 1.7, 0.26), 0.04, 0.2), metal, Vector3(cos(a) * 1.45, 0, sin(a) * 1.45))
		_part(g, _box(Vector3(0.06, 1.2, 0.06), 0.0), strip, Vector3(cos(a) * 1.32, 0.4, sin(a) * 1.32), Vector3.ZERO, false)
	var reels: Array[MeshInstance3D] = []
	for x: float in [-0.9, 0.9]:
		_part(g, _box(Vector3(0.6, 0.7, 0.3), 0.05, 0.07), dark, Vector3(x, 0, 0.55))
		reels.append(_part(g, _cyl(0.34, 0.34, 0.1, 6, 2), b.toon(pal.hazard), Vector3(x, 0.78, 0.72)))
		_part(g, _cyl(0.12, 0.12, 0.14, 6, 2), metal, Vector3(x, 0.78, 0.74))
	var gimbal := Node3D.new()
	gimbal.position = Vector3(0, 1.55, 0)
	g.add_child(gimbal)
	var outer := _part(gimbal, _ring(1.0, 0.09, 40), brass, Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
	var mid := _part(outer, _ring(0.78, 0.07, 36), metal)
	var inner := _part(mid, _ring(0.58, 0.05, 32), brass)
	_part(g, _cyl(0.1, 0.16, 0.6, 8), metal, Vector3(0, 0.6, 0))
	var core_m := mat_core(at)
	var core := _part(g, b.mesh("tmCore", func() -> Mesh: return WorldGeom.rock(17, 0.28, 1.0)), core_m, Vector3(0, 1.3, 0), Vector3.ZERO, false)
	var halo := _part(g, b.mesh("tmHalo", func() -> Mesh:
		var sm := SphereMesh.new()
		sm.radius = 0.42
		sm.height = 0.84
		sm.radial_segments = 16
		sm.rings = 8
		return sm), ToonKit.glow_add(pal.accent, 0.9, 0.5, 0.0), Vector3(0, 1.55, 0), Vector3.ZERO, false)
	(halo.material_override as ShaderMaterial).set_shader_parameter(&"fresnel_fade", 1.0)
	b.animators.append(func(t: float, _dt: float) -> void:
		gimbal.rotation.y = t * 0.35
		outer.rotation.z = sin(t * 0.4) * 0.5
		mid.rotation.y = t * 0.9
		inner.rotation.x = t * 1.4
		core.rotation = Vector3(t * 0.7, t * 1.1, 0.0)
		var bob := sin(t * 1.6) * 0.06
		core.position.y = 1.3 + bob
		halo.position.y = 1.55 + bob
		halo.scale = Vector3.ONE * (1.0 + sin(t * 3.2) * 0.06)
		for r: MeshInstance3D in reels:
			r.rotation.z = t * 2.0)


func mat_core(at: Vector2) -> ShaderMaterial:
	var m := b.mat("tmCoreMat", func() -> Material: return ToonKit.toon_emissive(pal.accent, pal.accent, 2.2, 1.5)) as ShaderMaterial
	b.register_reactive(MusicReactive.KIND_CORE, m, &"emission_energy", 2.2, at)
	return m
