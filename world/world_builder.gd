class_name WorldBuilder
extends RefCounted
## Builds a level's environment from LevelDef.map (port of prototype render/env/build.ts): floor
## tiles per kind and variant, walls (cut low on the camera side; chapter 16), barriers, the
## floating-diorama cliff skirt, edge trim and hazard bands, decor entities (WorldDecor), seeded
## ambient dressing (WorldScatter), contact shadows, practical lights and ambient motes.
##
## Pieces come from the Blender kit through WorldKit when a model exists; otherwise from the
## procedural stand-ins here (world_surface.gdshader patterns on WorldGeom blocks).
##
## Draw calls: every repeated element is one MultiMeshInstance3D per mesh + material, so a level
## costs a few dozen draw calls regardless of size. Nothing allocates per frame after build().

## Render layer (bit value) of all environment geometry; graffiti decals project onto it only, so
## selves and enemies walking past a tag never get painted.
const ENV_LAYER := 2
## Maximum number of practical point lights on 'high' (brightest first).
const MAX_PRACTICALS := 6

const FLOOR_PIECES := {
	&"solid": "floor_solid", &"alt": "floor_solid", &"cracked": "floor_cracked",
	&"grate": "floor_grate", &"overgrown": "floor_overgrown", &"rune": "floor_rune",
}


## A point light source a prop asks for (lamp, neon tube, generator window, time machine).
class Practical:
	extends RefCounted
	var pos: Vector3
	var color: Color
	var energy: float
	var light_range: float


## Instances of one mesh + material, emitted as one MultiMeshInstance3D.
class Batch:
	extends RefCounted
	var name: String
	var mesh: Mesh
	var material: Material
	var shadows: bool = true
	var xforms: Array[Transform3D] = []
	var colors: PackedColorArray = PackedColorArray()

	func add(xf: Transform3D, c: Color = Color.WHITE) -> void:
		xforms.append(xf)
		colors.append(c)


var level: LevelDef
var layout: WorldLayout
var pal: WorldPalette
var kit: WorldKit
## Parent of everything built (owned by the world view; freed on level change).
var root: Node3D
var reactive: Array[MusicReactive] = []
var practicals: Array[Practical] = []
## Per-frame ambient animation: func(time: float, dt: float) -> void.
var animators: Array[Callable] = []
## Instance counts per element family, for diagnostics and tests.
var stats: Dictionary = {}
## Names of kit pieces that came from models (vs stand-ins), for diagnostics and tests.
var used_models: Dictionary = {}
var used_standins: Dictionary = {}
## Wall tiles (Vector2i -> true) whose piece another element replaces (a crusher housing; WorldTraps).
var skip_walls: Dictionary = {}

var _batches: Dictionary = {}
var _batch_order: Array[String] = []
var _mats: Dictionary = {}
var _meshes: Dictionary = {}
var _seed: int = 0


func _init(p_level: LevelDef, p_layout: WorldLayout, p_pal: WorldPalette, p_kit: WorldKit, p_root: Node3D) -> void:
	level = p_level
	layout = p_layout
	pal = p_pal
	kit = p_kit
	root = p_root
	_seed = layout.level_seed


func build() -> void:
	_floors()
	_walls()
	_cliffs()
	_edges()
	_barriers()
	var decor := WorldDecor.new(self)
	for e: EntityDef in level.entities:
		if e is DecorDef:
			decor.build(e as DecorDef)
	_scatter()
	_emit_batches()
	_motes()


# ───────────────────────────── helpers ─────────────────────────────

static func xform(x: float, y: float, z: float, ry: float = 0.0, s: Vector3 = Vector3.ONE) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, ry).scaled(s), Vector3(x, y, z))


func batch(key: String, mesh: Mesh, material: Material, shadows: bool = true) -> Batch:
	if _batches.has(key):
		return _batches[key]
	var b := Batch.new()
	b.name = key
	b.mesh = mesh
	b.material = material
	b.shadows = shadows
	_batches[key] = b
	_batch_order.append(key)
	return b


## A mesh built once per builder and cached by key.
func mesh(key: String, make: Callable) -> Mesh:
	if not _meshes.has(key):
		_meshes[key] = make.call()
	return _meshes[key]


## A material created once per builder and cached by key.
func mat(key: String, make: Callable) -> Material:
	if not _mats.has(key):
		_mats[key] = make.call()
	return _mats[key]


func toon(c: Color, outline_px: float = ToonKit.OUTLINE_PX) -> ShaderMaterial:
	return mat("toon:%s:%s" % [c.to_html(), outline_px], func() -> Material: return ToonKit.toon(c, outline_px, pal.ink)) as ShaderMaterial


func glow(c: Color, energy: float, kind: StringName = MusicReactive.KIND_NEON, at: Vector2 = Vector2.INF) -> ShaderMaterial:
	var key := "glow:%s:%s" % [c.to_html(), energy]
	var fresh := not _mats.has(key)
	var m := mat(key, func() -> Material: return ToonKit.glow(c, energy)) as ShaderMaterial
	if fresh:
		register_reactive(kind, m, &"energy", energy, at)
	return m


## Register an emissive material for the fx layer to pulse (MusicReactive). `param` is the shader
## parameter scaled by the level; `base` its authored value. One entry per material.
func register_reactive(kind: StringName, m: ShaderMaterial, param: StringName, base: float, at: Vector2 = Vector2.INF) -> void:
	for r: MusicReactive in reactive:
		if r.material == m:
			return
	var entry := MusicReactive.make(kind, m, func(level_v: float) -> void: m.set_shader_parameter(param, base * maxf(0.0, level_v)))
	if at != Vector2.INF:
		entry.at = at
		entry.has_at = true
	reactive.append(entry)


func practical(pos: Vector3, c: Color, energy: float, light_range: float) -> void:
	var p := Practical.new()
	p.pos = pos
	p.color = c
	p.energy = energy
	p.light_range = light_range
	practicals.append(p)


func add_node(n: Node3D, readable_name: bool = false) -> void:
	_set_layers(n)
	root.add_child(n, readable_name)


func _set_layers(n: Node) -> void:
	if n is VisualInstance3D and not (n is Decal) and not (n is Light3D):
		(n as VisualInstance3D).layers = ENV_LAYER
	for c: Node in n.get_children():
		_set_layers(c)


func _grey(f: float) -> Color:
	return Color(f, f, f, 1.0)


func _note_piece(name: String, from_model: bool) -> void:
	if from_model:
		used_models[name] = true
	else:
		used_standins[name] = true


## Kit piece as a MultiMesh batch source; null when the stand-in must be used.
func _kit_piece(name: String, c: int = 0, r: int = 0) -> WorldKit.Piece:
	var p := kit.piece(name, c, r) if kit != null else null
	_note_piece(name, p != null)
	return p


func _metal_finish() -> bool:
	return pal.floor_finish == WorldPalette.FINISH_METAL


# ───────────────────────────── materials for stand-ins ─────────────────────────────

func _surface(key: String, top_pattern: int, side_pattern: int, top_c: Color, side_c: Color, line_c: Color, outline_px: float = ToonKit.OUTLINE_PX) -> ShaderMaterial:
	return mat("surf:" + key, func() -> Material:
		var m := ToonKit.surface(top_pattern, side_pattern, top_c, side_c, line_c, outline_px, pal.ink)
		m.set_shader_parameter(&"accent_color", pal.foliage if pal.floor_finish != WorldPalette.FINISH_METAL else pal.rust)
		m.set_shader_parameter(&"seed", float(_seed % 997))
		m.set_shader_parameter(&"wear", 0.35)
		m.set_shader_parameter(&"blotch", 0.12 if pal.floor_finish == WorldPalette.FINISH_STONE else 0.08)
		return m) as ShaderMaterial


func _floor_material(kind: StringName) -> ShaderMaterial:
	var side := WorldPalette.scale_color(pal.metal if _metal_finish() else pal.stone, 0.8)
	var stone_top := pal.floor_finish == WorldPalette.FINISH_STONE or (pal.floor_finish == WorldPalette.FINISH_MIXED and kind != &"alt")
	var top_p := 1 if stone_top else 2
	var top_c := pal.floor_alt if kind == &"alt" else pal.floor_color
	match kind:
		&"grate":
			return _surface("floor:grate", 3, 2, WorldPalette.scale_color(pal.metal, 1.15), side, pal.grout, 1.0)
		&"overgrown":
			var m := _surface("floor:overgrown", 6, top_p, pal.floor_alt, side, pal.grout, 1.0)
			m.set_shader_parameter(&"accent_color", pal.foliage)
			return m
		&"rune":
			var fresh := not _mats.has("surf:floor:rune")
			var m := _surface("floor:rune", 4, 2, WorldPalette.scale_color(pal.metal, 1.2) if not _metal_finish() else pal.floor_color, side, pal.grout, 1.0)
			if fresh:
				m.set_shader_parameter(&"glow_color", pal.rune)
				m.set_shader_parameter(&"glow_energy", 1.9)
				register_reactive(MusicReactive.KIND_RUNE, m, &"glow_energy", 1.9)
			return m
		&"cracked":
			var m := _surface("floor:cracked", top_p, top_p, top_c, side, pal.grout, 1.0)
			m.set_shader_parameter(&"wear", 0.75)
			m.set_shader_parameter(&"blotch", 0.25)
			return m
	return _surface("floor:" + String(kind), top_p, top_p, top_c, side, pal.grout, 1.0)


# ───────────────────────────── floors ─────────────────────────────

func _floors() -> void:
	var slab := mesh("floorSlab", func() -> Mesh: return WorldGeom.chamfer_box(Vector3(0.985, WorldLayout.TILE_THICK, 0.985), 0.03, -WorldLayout.TILE_THICK))
	var count := 0
	var cells: Array[Vector2i] = []
	var kinds: Array[StringName] = []
	for f: WorldLayout.Floor in layout.floors:
		cells.append(Vector2i(f.c, f.r))
		kinds.append(f.kind)
	# Walls stand on a floor slab too when they come from the kit (the kit wall starts at the slab).
	var kit_walls := kit != null and kit.has_model("wall")
	for i: int in range(layout.floors.size()):
		var f := layout.floors[i]
		var shade := (0.95 + 0.08 * WorldRng.tile_noise(_seed ^ 0x77, f.c, f.r)) * (1.0 - 0.3 * f.ao)
		var piece_name: String = FLOOR_PIECES.get(f.kind, "floor_solid")
		var p := _kit_piece(piece_name, f.c, f.r)
		var xf := xform(f.c + 0.5, 0.0, f.r + 0.5, f.rot * PI * 0.5)
		if p != null:
			var tint := shade * (0.92 if f.kind == &"alt" else 1.0)
			batch("floor:" + p.path, p.mesh, null, false).add(xf, _grey(tint))
		else:
			batch("floor:" + String(f.kind), slab, _floor_material(f.kind), false).add(xf, _grey(shade))
		count += 1
	if kit_walls:
		for w: WorldLayout.Wall in layout.walls:
			var p := _kit_piece("floor_solid", w.c, w.r)
			if p != null:
				batch("floor:" + p.path, p.mesh, null, false).add(xform(w.c + 0.5, 0.0, w.r + 0.5), _grey(0.8))
	stats["floor"] = count


# ───────────────────────────── walls ─────────────────────────────

func _wall_material(inscribed: bool, cut: bool) -> ShaderMaterial:
	var key := "wall:%d:%d" % [int(inscribed), int(cut)]
	var fresh := not _mats.has("surf:" + key)
	var side_p := 8 if (_metal_finish() or (inscribed and pal.floor_finish == WorldPalette.FINISH_MIXED)) else 1
	var top_p := (5 if _metal_finish() else 1) if cut else (2 if _metal_finish() else 0)
	var top_c := WorldPalette.scale_color(pal.wall_top, 0.95) if cut else pal.wall_top
	var m := _surface(key, top_p, side_p, top_c, pal.wall, pal.grout)
	if fresh:
		m.set_shader_parameter(&"accent_color", pal.hazard if cut and _metal_finish() else (pal.foliage if not _metal_finish() else pal.rust))
		if side_p == 8:
			m.set_shader_parameter(&"glow_color", pal.rune)
			m.set_shader_parameter(&"glow_energy", 1.6 if inscribed else 0.0)
			m.set_shader_parameter(&"glow_share", 0.45)
			if inscribed:
				register_reactive(MusicReactive.KIND_RUNE, m, &"glow_energy", 1.6)
	return m


func _walls() -> void:
	var inscribed_share := 0.3 if pal.floor_finish == WorldPalette.FINISH_STONE else 0.4
	var count := 0
	var replaced := 0
	for w: WorldLayout.Wall in layout.walls:
		if skip_walls.has(Vector2i(w.c, w.r)):
			replaced += 1
			continue
		var rot := floorf(w.shade * 4.0) * PI * 0.5
		var tint := _grey(0.9 + 0.14 * w.shade)
		var piece_name := "wall_cut" if w.cut else "wall"
		var p := _kit_piece(piece_name, w.c, w.r)
		if p != null:
			var base := p.aabb.position.y
			var top := p.aabb.end.y
			var k := (w.height - base) / maxf(0.01, top - base)
			var xf := Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(1.0, k, 1.0)), Vector3(w.c + 0.5, base - base * k, w.r + 0.5))
			batch("wall:" + p.path, p.mesh, null).add(xf, tint)
			if not w.cut:
				var cap_name := "wall_top_a" if WorldRng.tile_noise(_seed ^ 0x7c, w.c, w.r) < 0.6 else "wall_top_b"
				var cap := _kit_piece(cap_name, w.c, w.r)
				if cap != null:
					batch("wallTop:" + cap.path, cap.mesh, null).add(xform(w.c + 0.5, w.height, w.r + 0.5, rot), tint)
		else:
			var inscribed := WorldRng.tile_noise(_seed ^ 0x1d5, w.c, w.r) < inscribed_share
			var h := w.height + WorldLayout.TILE_THICK
			var key := "%.2f" % w.height
			var geo := mesh("wall:" + key, func() -> Mesh: return WorldGeom.chamfer_box(Vector3(1.0, h, 1.0), 0.05 if w.cut else 0.06, -WorldLayout.TILE_THICK))
			batch("wall:%s:%d:%d" % [key, int(inscribed), int(w.cut)], geo, _wall_material(inscribed, w.cut)).add(xform(w.c + 0.5, 0.0, w.r + 0.5, rot), tint)
		count += 1
	stats["wall"] = count
	stats["wall_replaced"] = replaced


# ───────────────────────────── cliff skirt ─────────────────────────────

func _cliffs() -> void:
	var cliff_mat := _surface("cliff", 0, 7, pal.cliff, pal.cliff, WorldPalette.scale_color(pal.cliff_deep, 1.2), 1.5)
	cliff_mat.set_shader_parameter(&"cliff_deep", pal.cliff_deep)
	cliff_mat.set_shader_parameter(&"cliff_depth", absf(layout.min_y) + 0.2)
	cliff_mat.set_shader_parameter(&"blotch", 0.0)
	for cl: WorldLayout.Cliff in layout.cliffs:
		var rot := floorf(WorldRng.tile_noise(_seed ^ 0xc1, cl.c, cl.r) * 4.0) * PI * 0.5
		var tint := _grey(0.92 + 0.12 * cl.shade)
		var p := _kit_piece("cliff_skirt", cl.c, cl.r)
		if p != null:
			var top := p.aabb.end.y
			var span := maxf(0.05, top - p.aabb.position.y)
			var k := (cl.depth + 0.25) / span
			batch("cliff:" + p.path, p.mesh, null, false).add(Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(1.0, k, 1.0)), Vector3(cl.c + 0.5, top - top * k, cl.r + 0.5)), tint)
		else:
			var shape := int(floor(cl.shade * 3.0)) % 3
			var key := "%.2f:%d" % [cl.depth, shape]
			var depth := cl.depth
			var seed_v := _seed + shape * 131 + int(round(depth * 100.0))
			var geo := mesh("cliff:" + key, func() -> Mesh: return WorldGeom.cliff_column(seed_v, depth, -WorldLayout.TILE_THICK))
			batch("cliff:" + key, geo, cliff_mat, false).add(xform(cl.c + 0.5, 0.0, cl.r + 0.5, rot), tint)
	stats["cliff"] = layout.cliffs.size()


# ───────────────────────────── edge trim and hazard bands ─────────────────────────────

func _edges() -> void:
	var lip_c := WorldPalette.scale_color(pal.wall_top, 0.92) if pal.floor_finish == WorldPalette.FINISH_STONE else pal.metal
	var lip_mesh := mesh("lip", func() -> Mesh: return WorldGeom.chamfer_box(Vector3(1.0, 0.08, 0.08), 0.015, -0.04))
	var haz_mesh := mesh("hazBand", func() -> Mesh:
		var bld := WorldGeom.Builder.new()
		bld.quad(Vector3(-0.5, -0.15, 0.0), Vector3(0.5, -0.15, 0.0), Vector3(0.5, 0.15, 0.0), Vector3(-0.5, 0.15, 0.0), Vector3(0, 0, -1))
		return bld.build())
	var haz_mat := _surface("hazard", 5, 5, pal.hazard, pal.hazard, WorldPalette.scale_color(pal.trim, 0.6), 0.0)
	haz_mat.set_shader_parameter(&"accent_color", pal.hazard)
	haz_mat.set_shader_parameter(&"blotch", 0.0)
	var hazard_share := 0.4 if pal.floor_finish == WorldPalette.FINISH_STONE else 0.6
	var trims := 0
	for e: WorldLayout.Edge in layout.edges:
		var c := e.c
		var r := e.r
		var side := e.side
		var yaw := [PI, PI * 0.5, 0.0, -PI * 0.5][side] as float
		if not e.wall:
			var p := _kit_piece("edge_trim", c, r)
			if p != null:
				batch("edge:" + p.path, p.mesh, null, false).add(xform(c + 0.5, 0.0, r + 0.5, yaw))
			else:
				var off := [Vector3(0.5, 0, 0.0), Vector3(1.0, 0, 0.5), Vector3(0.5, 0, 1.0), Vector3(0.0, 0, 0.5)][side] as Vector3
				batch("edge:lip", lip_mesh, toon(lip_c, 1.0), false).add(xform(c + off.x, 0.0, r + off.z, yaw))
			trims += 1
		# Hazard paint comes in runs of three tiles so it reads as deliberate striping, not noise.
		if side == WorldLayout.SIDE_E or side == WorldLayout.SIDE_S:
			var run := (int(floor(r / 3.0)) * 31 + c) if side == WorldLayout.SIDE_E else (int(floor(c / 3.0)) * 17 + r * 3)
			if WorldRng.tile_noise(_seed ^ 0x4a7, run, 1 if side == WorldLayout.SIDE_E else 2) < hazard_share:
				if side == WorldLayout.SIDE_E:
					batch("edge:hazard", haz_mesh, haz_mat, false).add(xform(c + 1.006, -0.38, r + 0.5, PI * 0.5))
				else:
					batch("edge:hazard", haz_mesh, haz_mat, false).add(xform(c + 0.5, -0.38, r + 1.006))
	stats["edge"] = trims


# ───────────────────────────── barriers ─────────────────────────────

func _barriers() -> void:
	if layout.barriers.is_empty():
		return
	var rail_c := WorldPalette.scale_color(pal.hazard, 0.9) if _metal_finish() else pal.hazard
	for b: WorldLayout.Barrier in layout.barriers:
		var x := b.c + 0.5
		var z := b.r + 0.5
		var any := b.n or b.e or b.s or b.w
		var along_x := b.e or b.w or not any
		var along_z := b.n or b.s
		var p := _kit_piece("barrier_low", b.c, b.r)
		if p != null:
			if along_x:
				batch("barrier:" + p.path, p.mesh, null).add(xform(x, 0.0, z))
			if along_z:
				batch("barrier:" + p.path, p.mesh, null).add(xform(x, 0.0, z, PI * 0.5))
			continue
		var base_h := 0.34
		var side_mat := _surface("barrierBase", 0, 5, pal.wall_top if not _metal_finish() else pal.metal, pal.hazard, WorldPalette.scale_color(pal.trim, 0.6))
		side_mat.set_shader_parameter(&"accent_color", pal.hazard)
		var base := mesh("barrierBase", func() -> Mesh: return WorldGeom.chamfer_box(Vector3(0.8, base_h, 0.8), 0.05))
		batch("barrier:base", base, side_mat).add(xform(x, 0.0, z))
		var post := mesh("barrierPost", func() -> Mesh:
			var bld := WorldGeom.Builder.new()
			WorldGeom.cylinder_into(bld, Vector3(0, base_h + (WorldLayout.BARRIER_HEIGHT - base_h) * 0.5, 0), 0.045, 0.045, WorldLayout.BARRIER_HEIGHT - base_h + 0.04, 8)
			return bld.build())
		batch("barrier:post", post, toon(rail_c)).add(xform(x, 0.0, z))
		var rail := mesh("barrierRail", func() -> Mesh:
			var bld := WorldGeom.Builder.new()
			WorldGeom.cylinder_into(bld, Vector3(0, WorldLayout.BARRIER_HEIGHT, 0), 0.035, 0.035, 0.5, 8, 0)
			return bld.build())
		var rb := batch("barrier:rail", rail, toon(rail_c))
		if b.e or not any:
			rb.add(xform(x + 0.25, 0.0, z))
		if b.w or not any:
			rb.add(xform(x - 0.25, 0.0, z))
		if b.s:
			rb.add(xform(x, 0.0, z + 0.25, PI * 0.5))
		if b.n:
			rb.add(xform(x, 0.0, z - 0.25, PI * 0.5))
	stats["barrier"] = layout.barriers.size()


# ───────────────────────────── contact shadows ─────────────────────────────

func blob(x: float, y: float, radius: float, strength: float = 1.0) -> void:
	var quad := mesh("blobQuad", func() -> Mesh:
		var pm := PlaneMesh.new()
		pm.size = Vector2(1, 1)
		return pm)
	var m := mat("blob", func() -> Material:
		var sm := ShaderMaterial.new()
		sm.shader = ToonKit.BLOB_SHADER
		sm.set_shader_parameter(&"color", pal.ink)
		sm.set_shader_parameter(&"opacity", 0.45)
		return sm)
	var s := radius * 2.0 * (0.8 + 0.2 * strength)
	batch("blob", quad, m, false).add(xform(x, 0.008, y, 0.0, Vector3(s, 1.0, s)), Color(1, 1, 1, clampf(strength, 0.0, 1.0)))


# ───────────────────────────── ambient scatter ─────────────────────────────

func _scatter() -> void:
	var items := WorldScatter.plan(level, layout, pal)
	var rng := WorldRng.new(_seed ^ 0xab5)
	var stone_finish := pal.floor_finish == WorldPalette.FINISH_STONE
	var tuft_mat := mat("tuft", func() -> Material: return ToonKit.toon_cutout(pal.foliage)) as ShaderMaterial
	var pebble_mat := toon(pal.stone if not _metal_finish() else pal.metal, 1.0)
	var leaf_mat := toon(pal.foliage, 1.5)
	var leaf_dark := toon(WorldPalette.scale_color(pal.foliage, 0.72), 1.5)
	var rubble_mat := toon(WorldPalette.scale_color(pal.wall_top, 0.95) if stone_finish else pal.metal, 1.5)
	var cliff_rock_mat := toon(WorldPalette.mix_color(pal.cliff, pal.stone, 0.4), 1.5)
	var pipe_c := pal.hazard if stone_finish else (pal.rust if pal.floor_finish == WorldPalette.FINISH_MIXED else pal.metal)
	var stain_mat := mat("stain", func() -> Material:
		var sm := ShaderMaterial.new()
		sm.shader = ToonKit.BLOB_SHADER
		sm.set_shader_parameter(&"color", pal.grout if stone_finish else pal.rust)
		sm.set_shader_parameter(&"opacity", 0.24)
		sm.set_shader_parameter(&"softness", 0.55)
		sm.set_shader_parameter(&"ragged", 0.9)
		return sm)
	var quad := mesh("blobQuad", func() -> Mesh:
		var pm := PlaneMesh.new()
		pm.size = Vector2(1, 1)
		return pm)
	var paint_mat := _surface("floorPaint", 5, 5, pal.hazard, pal.hazard, WorldPalette.scale_color(pal.trim, 0.5), 0.0)
	paint_mat.set_shader_parameter(&"accent_color", pal.hazard)
	paint_mat.set_shader_parameter(&"wear", 0.9)
	var paint_mesh := mesh("paintPlane", func() -> Mesh:
		var bld := WorldGeom.Builder.new()
		bld.quad(Vector3(-0.48, 0, -0.12), Vector3(0.48, 0, -0.12), Vector3(0.48, 0, 0.12), Vector3(-0.48, 0, 0.12), Vector3(0, -1, 0))
		return bld.build())
	var neon_cols: Array[Color] = [pal.neon_a, pal.neon_b, pal.neon_c]
	var counts := {}
	for it: WorldScatter.Item in items:
		counts[it.kind] = int(counts.get(it.kind, 0)) + 1
		var c := int(floor(it.x))
		var r := int(floor(it.y))
		var h := layout.wall_height(c, r)
		match it.kind:
			WorldScatter.TUFT:
				var i := int(floor(it.v * 3.0)) % 3
				var g := mesh("tuft%d" % i, func() -> Mesh: return WorldGeom.tuft(i, 0.32))
				batch("tuft%d" % i, g, tuft_mat, false).add(xform(it.x, 0.0, it.y, it.v * 6.0, Vector3.ONE * it.s), _grey(0.85 + it.v * 0.3))
			WorldScatter.PEBBLES:
				for i: int in range(3):
					var a := it.v * 10.0 + i * 2.1
					var k := i & 1
					var g := mesh("pebble%d" % k, func() -> Mesh: return WorldGeom.rock(k * 53 + 1, 0.07, 0.6))
					batch("pebble%d" % k, g, pebble_mat, false).add(xform(it.x + cos(a) * 0.12, 0.0, it.y + sin(a) * 0.12, a, Vector3.ONE * it.s), _grey(0.85 + 0.1 * i))
			WorldScatter.STAIN:
				batch("stain", quad, stain_mat, false).add(xform(it.x, 0.005, it.y, it.v * 3.0, Vector3(0.5 + it.s * 0.5, 1.0, 0.4 + it.s * 0.4)), Color(it.v, 1, 1, 1))
			WorldScatter.FLOOR_PAINT:
				var off := (it.v - 0.5) * 0.5
				var along_x := it.v < 0.5
				batch("floorPaint", paint_mesh, paint_mat, false).add(xform(it.x + (0.0 if along_x else off), 0.004, it.y + (off if along_x else 0.0), 0.0 if along_x else PI * 0.5, Vector3(1, 1, it.s)))
			WorldScatter.WALL_VINE:
				# Ivy: a chain of small leaf clumps hanging from the wall top down the face.
				var drop := maxf(0.5, h * (0.45 + 0.5 * it.s))
				var n := 3 + int(it.s * 3.0)
				for i: int in range(n):
					var t := float(i) / float(n - 1)
					var k := i % 2
					var g := mesh("ivy%d" % k, func() -> Mesh: return WorldGeom.leaf_clump(k + 5, 0.32))
					var xf := WorldScatter.mount_on_face(c, r, it.face, h - 0.05 - t * drop, (it.v - 0.5) * 0.5 + sin(t * 5.0 + it.v * 9.0) * 0.08, 0.03)
					xf = xf.scaled_local(Vector3(1.0, 0.8, 0.45) * (1.0 - 0.35 * t))
					batch("ivy%d" % k, g, leaf_dark if k == 1 else leaf_mat).add(xf)
			WorldScatter.WALL_PIPE:
				var y := 0.25 + it.v * maxf(0.1, h - 0.6)
				var pg := mesh("wallPipe", func() -> Mesh:
					var bld := WorldGeom.Builder.new()
					WorldGeom.cylinder_into(bld, Vector3.ZERO, 0.06, 0.06, 1.0, 8, 0)
					return bld.build())
				batch("wallPipe", pg, toon(pipe_c, 1.5)).add(WorldScatter.mount_on_face(c, r, it.face, y, 0.0, 0.07))
				var bg := mesh("wallBracket", func() -> Mesh: return WorldGeom.chamfer_box(Vector3(0.08, 0.16, 0.12), 0.01, -0.08))
				batch("wallBracket", bg, toon(pal.trim, 1.0)).add(WorldScatter.mount_on_face(c, r, it.face, y, 0.0, 0.04))
			WorldScatter.WALL_NEON:
				var y := minf(h - 0.4, 0.5 + it.s * 0.3)
				var col := neon_cols[int(floor(it.v * 3.0)) % 3]
				var ng := mesh("wallNeon", func() -> Mesh: return WorldGeom.chamfer_box(Vector3(0.07, 0.62, 0.05), 0.01, -0.31))
				batch("wallNeon:" + col.to_html(), ng, glow(col, 3.0)).add(WorldScatter.mount_on_face(c, r, it.face, y, (it.v - 0.5) * 0.4, 0.04), Color.WHITE)
				var cg := mesh("wallNeonCap", func() -> Mesh: return WorldGeom.chamfer_box(Vector3(0.12, 0.07, 0.08), 0.01, -0.035))
				for dy: float in [-0.33, 0.33]:
					batch("wallNeonCap", cg, toon(pal.metal, 1.0)).add(WorldScatter.mount_on_face(c, r, it.face, y + dy, (it.v - 0.5) * 0.4, 0.04))
				if it.v < 0.3:
					practical(WorldScatter.mount_on_face(c, r, it.face, y, 0.0, 0.4).origin, col, 1.2, 2.2)
			WorldScatter.WALL_VENT:
				var y := minf(h - 0.3, 0.55 + it.v * 0.3)
				var vg := mesh("wallVent", func() -> Mesh: return WorldGeom.chamfer_box(Vector3(0.46, 0.32, 0.06), 0.015, -0.16))
				batch("wallVent", vg, toon(WorldPalette.scale_color(pal.metal, 0.95), 1.5)).add(WorldScatter.mount_on_face(c, r, it.face, y, (it.v - 0.5) * 0.3, 0.01).scaled_local(Vector3(it.s, it.s, 1.0)))
				var sg := mesh("wallVentSlat", func() -> Mesh: return WorldGeom.chamfer_box(Vector3(0.38, 0.03, 0.02), 0.0, -0.015))
				for i: int in range(4):
					batch("wallVentSlat", sg, toon(WorldPalette.scale_color(pal.grout, 0.7), 0.0), false).add(WorldScatter.mount_on_face(c, r, it.face, y - 0.1 + i * 0.065, (it.v - 0.5) * 0.3, 0.045).scaled_local(Vector3(it.s, 1, 1)))
			WorldScatter.WALL_CABLE:
				var y := maxf(0.5, h - 0.25)
				var cbg := mesh("wallCable", func() -> Mesh: return _cable_mesh())
				batch("wallCable", cbg, toon(Color("#2e2a28") if stone_finish else Color("#18141e"), 1.0), false).add(WorldScatter.mount_on_face(c, r, it.face, y, 0.0, 0.04).scaled_local(Vector3(1, 0.4 + it.s * 0.6, 1)))
			WorldScatter.TOP_GRASS:
				var k := int(floor(it.v * 2.0)) % 2
				var g := mesh("topLeaf%d" % k, func() -> Mesh: return WorldGeom.leaf_clump(k + 3, 0.5))
				batch("topLeaf%d" % k, g, leaf_mat).add(xform(it.x + (it.v - 0.5) * 0.4, h, it.y + (it.s - 0.8) * 0.4, it.v * 6.0, Vector3(it.s, it.s * 0.7, it.s)))
			WorldScatter.TOP_RUBBLE:
				var k := int(floor(it.v * 3.0)) % 3
				var g := mesh("rock%d" % k, func() -> Mesh: return WorldGeom.rock(k * 977 + 3, 0.17))
				batch("topRubble%d" % k, g, rubble_mat).add(xform(it.x + (it.v - 0.5) * 0.4, h, it.y - (it.v - 0.5) * 0.3, it.v * 6.0, Vector3(it.s * 1.2, it.s, it.s * 1.2)), _grey(0.9 + 0.15 * it.s))
			WorldScatter.CLIFF_ROOT:
				var drop := 0.5 + it.s * 0.9
				var rg := mesh("root", func() -> Mesh: return _root_mesh())
				var xf := WorldScatter.mount_on_face(c, r, it.face, -WorldLayout.TILE_THICK, (it.v - 0.5) * 0.6, 0.0)
				batch("cliffRoot", rg, toon(WorldPalette.scale_color(pal.foliage, 0.65), 1.0), false).add(xf.scaled_local(Vector3(1.0, drop, 1.0)))
			WorldScatter.CLIFF_ROCK:
				var k := rng.range_i(0, 2)
				var g := mesh("rock%d" % k, func() -> Mesh: return WorldGeom.rock(k * 977 + 3, 0.17))
				var xf := WorldScatter.mount_on_face(c, r, it.face, -0.55 - it.v * 0.5, (it.v - 0.5) * 0.6, 0.02)
				xf = Transform3D(xf.basis.rotated(Vector3.UP, it.v * 5.0).scaled(Vector3.ONE * (0.8 + it.s * 0.6)), xf.origin)
				batch("cliffRock%d" % k, g, cliff_rock_mat, false).add(xf)
	for k: StringName in counts:
		stats[String(k)] = counts[k]


func _cable_mesh() -> Mesh:
	var bld := WorldGeom.Builder.new()
	var pts: Array[Vector3] = []
	for i: int in range(9):
		var t := float(i) / 8.0
		pts.append(Vector3(-0.5 + t, -0.5 * (1.0 - pow(2.0 * t - 1.0, 2.0)), 0.0))
	for i: int in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var mid := (a + b) * 0.5
		var dir := (b - a)
		var basis := Basis(Vector3.UP, 0.0)
		var ang := atan2(dir.y, dir.x)
		basis = Basis(Vector3(0, 0, 1), ang)
		var sub := WorldGeom.Builder.new()
		WorldGeom.cylinder_into(sub, Vector3.ZERO, 0.025, 0.025, dir.length() + 0.01, 5, 0)
		bld.append_mesh(sub, Transform3D(basis, mid))
	return bld.build()


func _root_mesh() -> Mesh:
	# Three tapered strands hanging from y = 0 to y = -1 (scaled by length).
	var bld := WorldGeom.Builder.new()
	for k: int in range(3):
		var x := (k - 1) * 0.12
		var sway := (k - 1) * 0.06
		var prev := Vector3(x, 0, 0.02)
		for i: int in range(1, 6):
			var t := float(i) / 5.0
			var p := Vector3(x + sin(t * 3.0 + k) * 0.05 + sway * t, -t * (0.8 + 0.1 * k), 0.02 + t * 0.03)
			var w := 0.03 * (1.0 - t * 0.7)
			bld.quad(prev + Vector3(-w, 0, 0), prev + Vector3(w, 0, 0), p + Vector3(w * 0.8, 0, 0), p + Vector3(-w * 0.8, 0, 0), prev + Vector3(0, 0, -1))
			prev = p
	return bld.build()


# ───────────────────────────── emit ─────────────────────────────

func _emit_batches() -> void:
	for key: String in _batch_order:
		var b: Batch = _batches[key]
		if b.xforms.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = b.mesh
		mm.instance_count = b.xforms.size()
		for i: int in range(b.xforms.size()):
			mm.set_instance_transform(i, b.xforms[i])
			mm.set_instance_color(i, b.colors[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = key.validate_node_name()
		mmi.multimesh = mm
		if b.material != null:
			mmi.material_override = b.material
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if b.shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_node(mmi)
	_batches.clear()
	_batch_order.clear()


# ───────────────────────────── ambient motes ─────────────────────────────

func _motes() -> void:
	var area := (layout.max_x - layout.min_x) * (layout.max_z - layout.min_z)
	var amount := mini(260, int(round(area * 0.45 * pal.mote_density)))
	if amount <= 0:
		return
	var p := GPUParticles3D.new()
	p.name = "Motes"
	p.amount = amount
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.fixed_fps = 30
	p.local_coords = false
	var centre := Vector3((layout.min_x + layout.max_x) * 0.5, 1.6, (layout.min_z + layout.max_z) * 0.5)
	p.position = centre
	p.visibility_aabb = AABB(Vector3(-(layout.max_x - layout.min_x), -2.0, -(layout.max_z - layout.min_z)), Vector3(layout.max_x - layout.min_x, 4.0, layout.max_z - layout.min_z) * 2.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3((layout.max_x - layout.min_x) * 0.5, 1.4, (layout.max_z - layout.min_z) * 0.5)
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.2
	pm.gravity = Vector3(0, 0.01, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = Color(pal.mote.r * 1.4, pal.mote.g * 1.4, pal.mote.b * 1.4, 0.55)
	sm.albedo_texture = _mote_texture()
	sm.disable_receive_shadows = true
	quad.material = sm
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_node(p)


static func _mote_texture() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	return t
