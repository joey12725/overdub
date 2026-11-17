class_name FxAmbient
extends Node3D
## Music-linked environment (MUSIC-12, chapter 18 "Musical architecture"; port of
## prototype/src/render/fx/music/ambient.ts).
##
## Harmonograph-inspired visuals that live in the architecture and react to RenderFrame.music:
##   - Lissajous / rose floor sigils under the start, every core and the exit, morphing with the chord;
##   - a "Stack" contour strip (four layers' recent pitches against a shared playhead) on every
##     wave-screen prop and on an edge display mounted along the diorama's far edge (on a rail at the
##     level bounds, never floating in empty space);
##   - an "Epicycles" hologram (sixteen strongest Fourier harmonics of the combined contour as nested
##     rotating circles) above a projector at the end of that rail;
##   - rune strokes on inscribed floor tiles and glyph columns on rune panels, pulsing with the beat
##     and each cassette's level - only where the world has not registered its own rune surfaces in
##     ctx.music_reactive (those are pulsed by FxMusicDrive instead, so nothing is drawn twice).
## Visual only: nothing here is a collider or feeds back into gameplay.

## Pitch-history samples per beat and length (16 beats = four bars of contour).
const SAMPLES_PER_BEAT := 8
const HISTORY := 128
const DFT_N := 64
const EPI_COUNT := 16
const TRACE_PTS := 72
const SIGIL_PTS := 160
const SCREEN_PTS := 48
const MAX_RUNE_TILES := 160
const MAX_PANELS := 12
const MAX_SIGILS := 6
## Edge display layout (scene units). The strip sits above the rail on the far edge.
const STRIP_LIFT := 0.35
const STRIP_H := 0.95
const EPI_R := 1.05
## Edge length reserved for the epicycles and their trace at the strip's right end.
const EPI_SPAN := 4.2
## Fallback wave-screen face (when the kit manifest does not give the prop's size).
const SCREEN_CY := 1.5
const SCREEN_HW := 0.56
const SCREEN_AMP := 0.5

const SHADER_RUNE := preload("res://fx/shaders/fx_rune.gdshader")
const SHADER_CONTOUR := preload("res://fx/shaders/fx_contour.gdshader")
const SHADER_SIGIL := preload("res://fx/shaders/fx_sigil.gdshader")
const SHADER_RING := preload("res://fx/shaders/fx_ring.gdshader")
const SHADER_LINE := preload("res://fx/shaders/fx_line.gdshader")
const KIT_MANIFEST := "res://assets/models/kit/manifest.json"


class Sigil:
	extends RefCounted
	var node: MeshInstance3D
	var x: float
	var z: float
	var radius: float
	var variant: int
	var color: Color
	var from := PackedVector2Array()
	var to := PackedVector2Array()
	var morph: float = 1.0


class Screen:
	extends RefCounted
	var x: float
	var z: float
	var node: MeshInstance3D
	var cy: float = SCREEN_CY
	var hw: float = SCREEN_HW
	var amp: float = SCREEN_AMP


var level: LevelDef
var palette: ThemePalette
## Diagnostics / tests: what was built.
var sigil_count: int = 0
var rune_stroke_count: int = 0
var panel_count: int = 0
var screen_count: int = 0
var edge_built: bool = false
## False when the world's music visualisers own the sigils / screens / edge display (build()).
var structural: bool = true
## Scene-space anchor of the edge display: rail start, along-edge unit vector, inward normal, length,
## rail height.
var edge_origin := Vector3.ZERO
var edge_along := Vector3.RIGHT
var edge_inward := Vector3.BACK
var edge_len: float = 1.0
var rail_y: float = 1.2

var _W: int = 1
var _H: int = 1
var _bounds := AABB()
var _quality: StringName = &"high"

# Pitch / level history per tape (ring buffers) and its data texture for the contour shader.
var _h_pitch := PackedFloat32Array()
var _h_level := PackedFloat32Array()
var _h_head: int = 0
var _h_count: int = 0
var _last_sample: int = -2147483648
var _hist_image: Image
var _hist_tex: ImageTexture
var _hist_dirty: bool = false

var _sigils: Array[Sigil] = []
var _screens: Array[Screen] = []
var _sigil_params := FxCurves.SigilParams.new()
var _last_chord: int = -2147483648

var _rune_node: MeshInstance3D = null
var _rune_mat: ShaderMaterial = null
var _panel_hosts: Array[Vector2] = []
var _panel_node: MeshInstance3D = null
var _contour_mat: ShaderMaterial = null
var _strip_node: MeshInstance3D = null
var _ring_mat: ShaderMaterial = null
var _rings: Array[MeshInstance3D] = []
var _dyn: MeshInstance3D = null
var _dyn_mesh: ImmediateMesh = null
var _sigil_mat: ShaderMaterial = null

# Epicycle state.
var _signal := PackedFloat32Array()
var _re := PackedFloat32Array()
var _im := PackedFloat32Array()
var _sm_re := PackedFloat32Array()
var _sm_im := PackedFloat32Array()
var _hf := PackedFloat32Array()
var _ha := PackedFloat32Array()
var _hp := PackedFloat32Array()
var _trace_y := PackedFloat32Array()
var _trace_timer: float = 0.0
## Latest epicycle reconstruction (for tests): harmonics in use and the chain tip.
var epi_count: int = 0
var epi_tip := Vector2.ZERO

# Camera-yaw basis for camera-facing panel holograms and screens (flattened right and toward-camera).
var _b_right := Vector3.RIGHT
var _b_normal := Vector3.BACK
var _basis_set: bool = false

var _scratch := PackedVector2Array()
var _pts3 := PackedVector3Array()
var _cols := PackedColorArray()


## Build every ambient element for a level. `reactive` is ctx.music_reactive (decides whether the
## procedural runes are needed); `camera` gives the view direction for the edge and the facing.
func build(ctx: RenderCtx) -> void:
	level = ctx.level if ctx.level != null else LevelDef.new()
	palette = ctx.palette if ctx.palette != null else ThemePalette.new()
	_quality = ctx.quality
	_H = maxi(1, level.map.size())
	var w := 1
	for row: String in level.map:
		w = maxi(w, row.length())
	_W = w
	_bounds = ctx.bounds
	if _bounds.size.x <= 0.0 or _bounds.size.z <= 0.0:
		_bounds = AABB(Vector3.ZERO, Vector3(_W, 1.2, _H))
	_h_pitch.resize(4 * HISTORY)
	_h_level.resize(4 * HISTORY)
	_h_pitch.fill(0.5)
	_h_level.fill(0.0)
	_hist_image = Image.create(HISTORY, 4, false, Image.FORMAT_RGF)
	_hist_image.fill(Color(0.5, 0.0, 0.0))
	_hist_tex = ImageTexture.create_from_image(_hist_image)
	_signal.resize(DFT_N)
	_re.resize(DFT_N)
	_im.resize(DFT_N)
	_sm_re.resize(DFT_N)
	_sm_im.resize(DFT_N)
	_sm_re.fill(0.0)
	_sm_im.fill(0.0)
	_hf.resize(EPI_COUNT)
	_ha.resize(EPI_COUNT)
	_hp.resize(EPI_COUNT)
	_trace_y.resize(TRACE_PTS)
	_trace_y.fill(0.0)

	_update_basis(ctx.camera, true)
	var world_runes := _world_rune_spots(ctx.music_reactive)
	# When the world mounted the music visualisers (musicviz/: screens, frieze, sigils, rune strips,
	# holograms) those are the structural view of the music; this layer then draws only the rune
	# pulses on inscribed floor, so nothing is drawn twice and no two systems drive one surface.
	structural = not ctx.musicviz_mounted
	_build_runes(world_runes)
	if structural:
		_build_sigils()
		_build_panels(world_runes)
		_build_contours()
		_build_edge(ctx)
	_dyn_mesh = ImmediateMesh.new()
	_dyn = MeshInstance3D.new()
	_dyn.name = "AmbientLines"
	_dyn.mesh = _dyn_mesh
	_dyn.material_override = _line_material(1.0)
	_dyn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dyn)


# ───────────────────────────── build ─────────────────────────────

## Positions of rune surfaces the world registered (`at` known), plus whether any rune surface exists.
func _world_rune_spots(reactive: Array[MusicReactive]) -> Array:
	var spots: Array[Vector2] = []
	var any := false
	for m: MusicReactive in reactive:
		if m == null or m.kind != MusicReactive.KIND_RUNE:
			continue
		any = true
		if m.has_at:
			spots.append(m.at)
	return [any, spots]


func _line_material(gain: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER_LINE
	m.set_shader_parameter("gain", gain)
	m.render_priority = 2
	return m


func _set_tape_uniforms(m: ShaderMaterial) -> void:
	m.set_shader_parameter("tape_a", OD.tape_color(0))
	m.set_shader_parameter("tape_b", OD.tape_color(1))
	m.set_shader_parameter("tape_c", OD.tape_color(2))
	m.set_shader_parameter("tape_d", OD.tape_color(3))


func _build_sigils() -> void:
	# Floor sigils: under the shared start position, every core and the exit.
	var spots: Array = [[level.start.x, level.start.y, 1.15, palette.neon_a]]
	for e: EntityDef in level.entities:
		if spots.size() >= MAX_SIGILS:
			break
		if e is CoreDef:
			var c := e as CoreDef
			spots.append([c.x, c.y, 0.95, palette.neon_c])
		elif e is ExitDef:
			var x := e as ExitDef
			spots.append([x.c + x.w / 2.0, x.r + x.h / 2.0, maxf(0.8, minf(x.w, x.h) * 0.45), palette.hazard])
	_sigil_mat = ShaderMaterial.new()
	_sigil_mat.shader = SHADER_SIGIL
	_sigil_mat.render_priority = 1
	for s: int in spots.size():
		var sp: Array = spots[s]
		var g := Sigil.new()
		g.x = sp[0]
		g.z = sp[1]
		g.radius = sp[2]
		g.color = sp[3]
		g.variant = s
		g.node = MeshInstance3D.new()
		g.node.name = "Sigil%d" % s
		g.node.material_override = _sigil_mat
		g.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.node.position = Vector3(g.x, 0.016, g.z)
		add_child(g.node)
		_sigils.append(g)
	sigil_count = _sigils.size()


func _sigil_mesh(g: Sigil) -> void:
	var a := PackedVector3Array()
	var b := PackedVector3Array()
	a.resize(SIGIL_PTS)
	b.resize(SIGIL_PTS)
	for i: int in SIGIL_PTS:
		a[i] = Vector3(g.from[i].x * g.radius, 0.0, g.from[i].y * g.radius)
		b[i] = Vector3(g.to[i].x * g.radius, 0.0, g.to[i].y * g.radius)
	var bld := FxLineGeo.Builder.new()
	bld.add(a, Vector3.UP, 0.045, true, Color.WHITE, Vector4.ZERO, b)
	g.node.mesh = bld.commit()


func _build_runes(world_runes: Array) -> void:
	if world_runes[0]:
		return
	var bld := FxLineGeo.Builder.new()
	var tiles := 0
	var cap := MAX_RUNE_TILES >> 1 if _quality == WorldViewBase.QUALITY_LOW else MAX_RUNE_TILES
	for r: int in level.map.size():
		var row := level.map[r]
		for c: int in row.length():
			if tiles >= cap:
				break
			if row[c] != "~":
				continue
			tiles += 1
			var rseed := FxRng.hash4(c, r, level.index, 7)
			var strokes := FxCurves.rune_glyph(rseed)
			var tape := (c * 7 + r * 3) % 4
			var rot := float((rseed >> 8) % 4) * (PI / 2.0)
			var cr := cos(rot)
			var sr := sin(rot)
			for st: PackedVector2Array in strokes:
				var pts := PackedVector3Array()
				for p: Vector2 in st:
					var u := p.x * 0.3
					var v := p.y * 0.3
					pts.append(Vector3(c + 0.5 + u * cr - v * sr, 0.014, r + 0.5 + u * sr + v * cr))
				bld.add(pts, Vector3.UP, 0.05, false, Color.WHITE, Vector4(tape, (c + r) * 0.6, 0.0, 0.0))
				rune_stroke_count += 1
	if bld.is_empty():
		return
	_rune_mat = _make_rune_material()
	_rune_node = MeshInstance3D.new()
	_rune_node.name = "Runes"
	_rune_node.mesh = bld.commit()
	_rune_node.material_override = _rune_mat
	_rune_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rune_node)


func _make_rune_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER_RUNE
	m.render_priority = 1
	m.set_shader_parameter("rune_color", palette.neon_c)
	_set_tape_uniforms(m)
	return m


func _build_panels(world_runes: Array) -> void:
	var spots: Array[Vector2] = world_runes[1]
	_panel_hosts.clear()
	for e: EntityDef in level.entities:
		if not (e is DecorDef) or _panel_hosts.size() >= MAX_PANELS:
			continue
		var d := e as DecorDef
		if d.type != DecorType.RUNE_PANEL:
			continue
		var covered := false
		for s: Vector2 in spots:
			if s.distance_to(Vector2(d.x, d.y)) < 0.8:
				covered = true
		if not covered:
			_panel_hosts.append(Vector2(d.x, d.y))
	panel_count = _panel_hosts.size()
	_rebuild_panels()


func _rebuild_panels() -> void:
	if _panel_hosts.is_empty():
		return
	if _panel_node == null:
		_panel_node = MeshInstance3D.new()
		_panel_node.name = "RunePanels"
		_panel_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _rune_mat == null:
			_rune_mat = _make_rune_material()
		_panel_node.material_override = _rune_mat
		add_child(_panel_node)
	var bld := FxLineGeo.Builder.new()
	var rx := _b_right
	var nx := _b_normal
	for pi: int in _panel_hosts.size():
		var host := _panel_hosts[pi]
		for gi: int in 3:
			var strokes := FxCurves.rune_glyph(FxRng.hash4(roundi(host.x * 10.0), roundi(host.y * 10.0), gi, 11))
			for st: PackedVector2Array in strokes:
				var pts := PackedVector3Array()
				for p: Vector2 in st:
					var u := p.x * 0.16
					var v := 0.55 + gi * 0.42 + p.y * 0.16
					pts.append(Vector3(host.x, 0.0, host.y) + rx * u + nx * 0.35 + Vector3(0.0, v, 0.0))
				bld.add(pts, nx, 0.04, false, Color.WHITE, Vector4(pi % 4, 0.0, 1.0, gi))
	_panel_node.mesh = bld.commit()


## Kit-manifest size of a piece (Vector3.ZERO when unknown).
static func kit_size(piece: String) -> Vector3:
	if not FileAccess.file_exists(KIT_MANIFEST):
		return Vector3.ZERO
	var errors: Array[String] = []
	var data: Variant = ODJson.read_file(KIT_MANIFEST, errors)
	if not (data is Dictionary):
		return Vector3.ZERO
	var pieces: Dictionary = ODJson.dict(data, "pieces")
	var p: Dictionary = ODJson.dict(pieces, piece)
	var sz: Array = ODJson.array(p, "size")
	if sz.size() < 3 or not (ODJson.is_number(sz[0]) and ODJson.is_number(sz[1]) and ODJson.is_number(sz[2])):
		return Vector3.ZERO
	return Vector3(float(sz[0]), float(sz[1]), float(sz[2]))


func _contour_mesh(samples: int) -> ArrayMesh:
	# Four lines of `samples` points; VERTEX carries (i, side, tape) for the contour shader.
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for t: int in 4:
		var base := verts.size()
		for i: int in samples:
			verts.append(Vector3(i, 1.0, t))
			verts.append(Vector3(i, -1.0, t))
			uvs.append(Vector2(1.0, 0.0))
			uvs.append(Vector2(-1.0, 0.0))
		for i: int in samples - 1:
			var v := base + i * 2
			idx.append_array(PackedInt32Array([v, v + 1, v + 2, v + 1, v + 3, v + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _contour_node(samples: int, nm: String) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.name = nm
	n.mesh = _contour_mesh(samples)
	n.material_override = _contour_mat
	n.top_level = true
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The vertex data are indices, not positions: give culling the whole diorama.
	n.custom_aabb = _bounds.grow(6.0)
	n.set_instance_shader_parameter("samples", float(samples))
	add_child(n)
	n.transform = Transform3D.IDENTITY
	return n


func _build_contours() -> void:
	_contour_mat = ShaderMaterial.new()
	_contour_mat.shader = SHADER_CONTOUR
	_contour_mat.render_priority = 2
	_contour_mat.set_shader_parameter("history", _hist_tex)
	_contour_mat.set_shader_parameter("history_len", HISTORY)
	_set_tape_uniforms(_contour_mat)
	var size := kit_size("wave_screen")
	for e: EntityDef in level.entities:
		if not (e is DecorDef) or _screens.size() >= MAX_PANELS:
			continue
		var d := e as DecorDef
		if d.type != DecorType.WAVE_SCREEN:
			continue
		var s := Screen.new()
		s.x = d.x
		s.z = d.y
		if size.y > 0.2 and size.x > 0.2:
			# Screen face roughly in the upper part of the prop (the asset contract fixes the origin
			# on the floor at the footprint centre).
			s.cy = size.y * 0.72
			s.hw = minf(SCREEN_HW, size.x * 0.42)
			s.amp = minf(SCREEN_AMP, size.y * 0.26)
		s.node = _contour_node(SCREEN_PTS, "WaveScreen%d" % _screens.size())
		s.node.set_instance_shader_parameter("mode", 1.0)
		s.node.set_instance_shader_parameter("width", 0.035)
		s.node.set_instance_shader_parameter("lay", Vector4(s.hw, s.cy, s.amp, 0.0))
		_screens.append(s)
	screen_count = _screens.size()
	_place_screens()


func _place_screens() -> void:
	for s: Screen in _screens:
		s.node.set_instance_shader_parameter("origin", Vector3(s.x, 0.0, s.z) + _b_normal * 0.3)
		s.node.set_instance_shader_parameter("along", _b_right)
		s.node.set_instance_shader_parameter("up", Vector3.UP)


## Choose the far edge (outward normal most aligned with the view direction), mount a rail and a
## dark display panel on it, and put the strip and the epicycle projector there.
func _build_edge(ctx: RenderCtx) -> void:
	var fwd := Vector3(-1.0, 0.0, -1.0).normalized()
	var right := Vector3(1.0, 0.0, -1.0).normalized()
	if ctx.camera != null:
		var cb := ctx.camera.global_transform.basis if ctx.camera.is_inside_tree() else ctx.camera.transform.basis
		fwd = -cb.z
		right = cb.x
	var x0 := _bounds.position.x
	var x1 := _bounds.end.x
	var z0 := _bounds.position.z
	var z1 := _bounds.end.z
	var cands := [
		[Vector3(0, 0, -1), x1 - x0],
		[Vector3(0, 0, 1), x1 - x0],
		[Vector3(-1, 0, 0), z1 - z0],
		[Vector3(1, 0, 0), z1 - z0],
	]
	var best: Array = cands[0]
	var best_score := -INF
	for c: Array in cands:
		var n: Vector3 = c[0]
		var score: float = n.x * fwd.x + n.z * fwd.z + float(c[1]) * 1e-3
		if score > best_score:
			best_score = score
			best = c
	var nrm: Vector3 = best[0]
	var elen: float = best[1]
	# Along-edge direction that reads left -> right on screen.
	var along := Vector3(-nrm.z, 0.0, nrm.x)
	if along.dot(Vector3(right.x, 0.0, right.z)) < 0.0:
		along = -along
	edge_along = along
	edge_inward = -nrm
	edge_len = maxf(EPI_SPAN + 4.0, elen - 0.4)
	var mid := Vector3(
		(x0 + x1) * 0.5 if nrm.x == 0.0 else (x0 if nrm.x < 0.0 else x1),
		0.0,
		(z0 + z1) * 0.5 if nrm.z == 0.0 else (z0 if nrm.z < 0.0 else z1))
	# The rail runs along the top of the edge, just inside the bounds (it sits on the boundary walls).
	var top := _bounds.end.y
	if ctx.view != null:
		top = maxf(top, ctx.surface_height(mid.x - nrm.x * 0.5, mid.z - nrm.z * 0.5))
	rail_y = clampf(top if top > 0.3 else 1.2, 0.6, 3.0)
	edge_origin = mid - along * (edge_len * 0.5) - nrm * 0.25
	edge_origin.y = 0.0
	_build_mount()

	_strip_node = _contour_node(HISTORY, "EdgeStrip")
	_strip_node.set_instance_shader_parameter("mode", 0.0)
	_strip_node.set_instance_shader_parameter("width", 0.06)
	_strip_node.set_instance_shader_parameter("origin", edge_origin)
	_strip_node.set_instance_shader_parameter("along", edge_along)
	_strip_node.set_instance_shader_parameter("up", Vector3.UP)
	var s0 := 0.4
	var play := s0 + (edge_len - EPI_SPAN - s0) * 0.8
	_strip_node.set_instance_shader_parameter("lay", Vector4(s0, play, rail_y + STRIP_LIFT, STRIP_H))

	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = SHADER_RING
	_ring_mat.render_priority = 2
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	for i: int in EPI_COUNT:
		var r := MeshInstance3D.new()
		r.name = "Epicycle%d" % i
		r.mesh = quad
		r.material_override = _ring_mat
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		r.visible = false
		add_child(r)
		_rings.append(r)
	edge_built = true


## A rail with end posts, a dark glass backing and a projector disc: the physical display the edge
## visuals are drawn on.
func _build_mount() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = palette.metal.darkened(0.25)
	metal.roughness = 0.6
	metal.metallic = 0.4
	var trim := StandardMaterial3D.new()
	trim.albedo_color = palette.trim
	trim.roughness = 0.7
	var yaw := atan2(edge_along.x, edge_along.z) - PI * 0.5
	var rail_basis := Basis(Vector3.UP, yaw)
	# Rail.
	var rail := MeshInstance3D.new()
	rail.name = "EdgeRail"
	var bm := BoxMesh.new()
	bm.size = Vector3(edge_len, 0.09, 0.14)
	rail.mesh = bm
	rail.material_override = metal
	rail.transform = Transform3D(rail_basis, edge_origin + edge_along * (edge_len * 0.5) + Vector3(0.0, rail_y + 0.045, 0.0))
	add_child(rail)
	# Posts down to the floor at both ends and the middle.
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.1, rail_y, 0.1)
	for f: float in [0.02, 0.5, 0.98]:
		var p := MeshInstance3D.new()
		p.name = "EdgePost"
		p.mesh = post_mesh
		p.material_override = trim
		p.position = edge_origin + edge_along * (edge_len * f) + Vector3(0.0, rail_y * 0.5, 0.0)
		add_child(p)
	# Dark translucent backing panel behind the strip so the contour reads as an installed display.
	var glass := StandardMaterial3D.new()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(palette.ink.r, palette.ink.g, palette.ink.b, 0.55)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var back := MeshInstance3D.new()
	back.name = "EdgeDisplay"
	var qm := QuadMesh.new()
	qm.size = Vector2(edge_len - EPI_SPAN + 0.2, STRIP_H + 0.55)
	back.mesh = qm
	back.material_override = glass
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var panel_basis := Basis(edge_along, Vector3.UP, edge_along.cross(Vector3.UP))
	back.transform = Transform3D(panel_basis, edge_origin + edge_along * ((edge_len - EPI_SPAN + 0.2) * 0.5) + Vector3(0.0, rail_y + STRIP_LIFT + STRIP_H * 0.5, 0.0) - edge_inward * 0.04)
	add_child(back)
	# Projector disc under the epicycle hologram.
	var proj := MeshInstance3D.new()
	proj.name = "EpicycleProjector"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.28
	cyl.bottom_radius = 0.36
	cyl.height = 0.16
	proj.mesh = cyl
	proj.material_override = metal
	proj.position = _epi_center_world() + Vector3(0.0, -(STRIP_H * 0.5 + STRIP_LIFT) + 0.17, 0.0)
	add_child(proj)
	var lens := MeshInstance3D.new()
	lens.name = "EpicycleLens"
	var lm := CylinderMesh.new()
	lm.top_radius = 0.18
	lm.bottom_radius = 0.18
	lm.height = 0.03
	lens.mesh = lm
	var lens_mat := StandardMaterial3D.new()
	lens_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lens_mat.albedo_color = palette.neon_a
	lens_mat.emission_enabled = true
	lens_mat.emission = palette.neon_a
	lens.material_override = lens_mat
	lens.position = proj.position + Vector3(0.0, 0.095, 0.0)
	add_child(lens)


func _epi_center_u() -> float:
	return edge_len - EPI_R - 0.3


func _epi_center_world() -> Vector3:
	return edge_origin + edge_along * _epi_center_u() + Vector3(0.0, rail_y + STRIP_LIFT + STRIP_H * 0.5, 0.0)


func _strip_point(u: float, v: float) -> Vector3:
	return edge_origin + edge_along * u + Vector3(0.0, v, 0.0)


# ───────────────────────────── per frame ─────────────────────────────

func update(music: MusicPulse, brightness: float, dt: float, camera: Camera3D) -> void:
	if music == null:
		music = MusicPulse.new()
	if _update_basis(camera, false):
		_rebuild_panels()
		_place_screens()
	_sample_history(music)
	_update_sigils(music, brightness, dt)
	var avg := 0.0
	for t: int in 4:
		avg += _lvl(music, t)
	if _rune_mat != null:
		_rune_mat.set_shader_parameter("levels", Vector4(_lvl(music, 0), _lvl(music, 1), _lvl(music, 2), _lvl(music, 3)))
		_rune_mat.set_shader_parameter("beat", music.beat)
		_rune_mat.set_shader_parameter("beat_pulse", music.beat_pulse)
		_rune_mat.set_shader_parameter("bar_pulse", music.bar_pulse)
		_rune_mat.set_shader_parameter("brightness", brightness)
	if _contour_mat != null:
		if _hist_dirty:
			_hist_tex.update(_hist_image)
			_hist_dirty = false
		_contour_mat.set_shader_parameter("head", _h_head)
		_contour_mat.set_shader_parameter("count", _h_count)
		_contour_mat.set_shader_parameter("frac", music.beat * SAMPLES_PER_BEAT - floorf(music.beat * SAMPLES_PER_BEAT))
		_contour_mat.set_shader_parameter("brightness", brightness)
	_dyn_mesh.clear_surfaces()
	if _screens.is_empty() and not edge_built:
		# Nothing dynamic to draw (e.g. musicviz owns the screens and the edge display).
		return
	_dyn_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_draw_screens(music, brightness)
	if edge_built:
		_draw_strip_marks(music, brightness)
		_update_epicycles(music, brightness, dt)
	_dyn_mesh.surface_end()


static func _lvl(m: MusicPulse, t: int) -> float:
	var v := m.levels[t] if t < m.levels.size() else 0.0
	return clampf(v, 0.0, 1.0) if is_finite(v) else 0.0


## Refresh the camera-facing basis; true when it changed.
func _update_basis(camera: Camera3D, force: bool) -> bool:
	if camera == null:
		_basis_set = true
		return false
	var cb := camera.global_transform.basis if camera.is_inside_tree() else camera.transform.basis
	var r := Vector3(cb.x.x, 0.0, cb.x.z)
	if r.length() < 1e-5:
		return false
	r = r.normalized()
	if _basis_set and not force and (r - _b_right).length() < 1e-3:
		return false
	_b_right = r
	var n := Vector3(cb.z.x, 0.0, cb.z.z)
	_b_normal = n.normalized() if n.length() > 1e-5 else Vector3.BACK
	_basis_set = true
	return true


func _sample_history(m: MusicPulse) -> void:
	var idx := int(floorf(m.beat * SAMPLES_PER_BEAT))
	var last := _last_sample
	if last == -2147483648 or idx < last or idx - last > HISTORY:
		# First frame or the transport jumped (new run / seek): restart the contour.
		_h_head = 0
		_h_count = 0
		_last_sample = idx
		_push_sample(m)
		return
	for _s: int in range(last, idx):
		_push_sample(m)
	_last_sample = idx


func _push_sample(m: MusicPulse) -> void:
	var h := _h_head
	for t: int in 4:
		var p := m.pitches[t] if t < m.pitches.size() else 0.5
		var l := m.levels[t] if t < m.levels.size() else 0.0
		p = clampf(p, 0.0, 1.0) if is_finite(p) else 0.5
		l = clampf(l, 0.0, 1.0) if is_finite(l) else 0.0
		_h_pitch[t * HISTORY + h] = p
		_h_level[t * HISTORY + h] = l
		_hist_image.set_pixel(h, t, Color(p, l, 0.0))
	_hist_dirty = true
	_h_head = (h + 1) % HISTORY
	if _h_count < HISTORY:
		_h_count += 1
	_refresh_spectrum()


## Index into the ring for the k-th sample counting back from newest (k = 0 newest).
func _back(k: int) -> int:
	return (_h_head - 1 - k + HISTORY * 2) % HISTORY


func _refresh_spectrum() -> void:
	# Combined contour of the last DFT_N samples, weighted by how loud each layer is.
	for s: int in DFT_N:
		var h := _back(DFT_N - 1 - s)
		var num := 0.0
		var den := 0.0
		for t: int in 4:
			var l := _h_level[t * HISTORY + h]
			num += l * _h_pitch[t * HISTORY + h]
			den += l
		_signal[s] = (num / den) * 2.0 - 1.0 if den > 0.02 else 0.0
	FxCurves.dft(_signal, DFT_N, _re, _im)


func _update_sigils(m: MusicPulse, br: float, dt: float) -> void:
	var chord := m.chord
	var changed := chord != _last_chord
	var first := _last_chord == -2147483648
	_last_chord = chord
	var avg := 0.0
	for t: int in 4:
		avg += _lvl(m, t)
	avg *= 0.25
	var a := (0.16 + 0.24 * m.bar_pulse + 0.1 * m.beat_pulse + 0.2 * avg) * br
	var ang := m.beat * PI / 32.0
	for s: int in _sigils.size():
		var g := _sigils[s]
		if changed:
			FxCurves.sigil_points(_scratch, SIGIL_PTS, FxCurves.sigil_params_for_chord(chord, g.variant, _sigil_params))
			if first or g.from.size() != SIGIL_PTS:
				g.from = _scratch.duplicate()
				g.to = _scratch.duplicate()
				g.morph = 1.0
			else:
				# Start from what is on screen right now, so a quick chord change never pops.
				var e := g.morph * g.morph * (3.0 - 2.0 * g.morph)
				var cur := PackedVector2Array()
				cur.resize(SIGIL_PTS)
				for i: int in SIGIL_PTS:
					cur[i] = g.from[i].lerp(g.to[i], e)
				g.from = cur
				g.to = _scratch.duplicate()
				g.morph = 0.0
			_sigil_mesh(g)
		elif g.morph < 1.0:
			g.morph = minf(1.0, g.morph + dt / 1.2)
		# Alternate sigils counter-rotate so a room never turns as one block.
		var dir := 1.0 if s % 2 == 0 else -1.0
		g.node.rotation = Vector3(0.0, -ang * dir, 0.0)
		g.node.set_instance_shader_parameter("morph", g.morph)
		g.node.set_instance_shader_parameter("tint", Color(g.color.r, g.color.g, g.color.b, a))


func _draw_screens(m: MusicPulse, br: float) -> void:
	var rx := _b_right
	var nx := _b_normal
	var col := palette.neon_b
	for s: Screen in _screens:
		var c := Vector3(s.x, 0.0, s.z) + nx * 0.3
		var y0 := s.cy - s.amp * 0.64
		var y1 := s.cy + s.amp * 0.64
		var hw := s.hw + 0.06
		_pts3.resize(5)
		_pts3[0] = c - rx * hw + Vector3(0.0, y0, 0.0)
		_pts3[1] = c + rx * hw + Vector3(0.0, y0, 0.0)
		_pts3[2] = c + rx * hw + Vector3(0.0, y1, 0.0)
		_pts3[3] = c - rx * hw + Vector3(0.0, y1, 0.0)
		_pts3[4] = _pts3[0]
		FxLineGeo.draw_immediate(_dyn_mesh, _pts3, nx, 0.025, Color(col.r, col.g, col.b, (0.18 + 0.12 * m.bar_pulse) * br), true)
		_pts3.resize(2)
		_pts3[0] = c + rx * s.hw + Vector3(0.0, y0 + 0.02, 0.0)
		_pts3[1] = c + rx * s.hw + Vector3(0.0, y1 - 0.02, 0.0)
		FxLineGeo.draw_immediate(_dyn_mesh, _pts3, nx, 0.03, Color(1.0, 1.0, 1.0, (0.25 + 0.5 * m.beat_pulse) * br))


func _draw_strip_marks(m: MusicPulse, br: float) -> void:
	var L := edge_len
	var s0 := 0.4
	var play := s0 + (L - EPI_SPAN - s0) * 0.8
	var y0 := rail_y + STRIP_LIFT
	var nrm := edge_inward
	var col := palette.neon_b
	_pts3.resize(2)
	# Baseline.
	_pts3[0] = _strip_point(s0, y0 - 0.08)
	_pts3[1] = _strip_point(L - EPI_SPAN, y0 - 0.08)
	FxLineGeo.draw_immediate(_dyn_mesh, _pts3, nrm, 0.03, Color(col.r, col.g, col.b, (0.2 + 0.2 * m.bar_pulse) * br))
	# Playhead.
	_pts3[0] = _strip_point(play, y0 - 0.15)
	_pts3[1] = _strip_point(play, y0 + STRIP_H + 0.2)
	FxLineGeo.draw_immediate(_dyn_mesh, _pts3, nrm, 0.05, Color(1.0, 1.0, 1.0, (0.35 + 0.5 * m.beat_pulse) * br))
	# Upcoming beat ticks to the right of the playhead; the bar line stands taller.
	var unit := (play - s0) / (float(HISTORY) / SAMPLES_PER_BEAT)
	var next_beat := ceilf(m.beat)
	for k: int in 4:
		var bt := next_beat + k
		var u := play + (bt - m.beat) * unit
		var bar := (int(bt) % 4 + 4) % 4 == 0
		_pts3[0] = _strip_point(u, y0 - 0.12)
		_pts3[1] = _strip_point(u, y0 + (0.5 if bar else 0.18))
		FxLineGeo.draw_immediate(_dyn_mesh, _pts3, nrm, 0.03, Color(col.r, col.g, col.b, (0.5 if bar else 0.28) * br))


func _update_epicycles(m: MusicPulse, br: float, dt: float) -> void:
	# Smooth the spectrum so harmonics swell rather than pop when the contour changes.
	var k := 1.0 - exp(-dt * 3.0)
	for i: int in DFT_N:
		_sm_re[i] += (_re[i] - _sm_re[i]) * k
		_sm_im[i] += (_im[i] - _sm_im[i]) * k
	var count := FxCurves.strongest_harmonics(_sm_re, _sm_im, DFT_N, EPI_COUNT, _hf, _ha, _hp)
	epi_count = count
	var sum := 0.0
	for i: int in count:
		sum += _ha[i]
	# Normalise so the hologram keeps its size; a nearly flat contour is magnified at most ~8x.
	var scale := EPI_R / maxf(sum, 0.12) if sum > 1e-6 else 0.0
	# One revolution per DFT window (DFT_N samples), locked to the master beat.
	var window_beats := float(DFT_N) / SAMPLES_PER_BEAT
	var theta := fposmod(m.beat / window_beats, 1.0) * TAU
	var cu := _epi_center_u()
	var cv := rail_y + STRIP_LIFT + STRIP_H * 0.5
	var x := 0.0
	var y := 0.0
	var plane := Basis(edge_along, Vector3.UP, edge_along.cross(Vector3.UP))
	var rune := palette.neon_c
	_pts3.resize(EPI_COUNT + 1)
	_pts3[0] = _strip_point(cu, cv)
	var used := 1
	for i: int in EPI_COUNT:
		var ring := _rings[i]
		if i >= count:
			ring.visible = false
			continue
		var r := _ha[i] * scale
		# Circle centred on the running tip.
		ring.visible = r > 0.004
		ring.transform = Transform3D(plane * Basis.from_scale(Vector3(r, r, 1.0)), _strip_point(cu + x, cv + y) - edge_inward * 0.01)
		ring.set_instance_shader_parameter("radius", r)
		ring.set_instance_shader_parameter("tint", Color(rune.r, rune.g, rune.b, (0.12 + 0.18 * (1.0 - float(i) / EPI_COUNT)) * br))
		# x = sum a sin, y = sum a cos: the vertical coordinate of the tip is the reconstructed contour.
		var ang := _hf[i] * theta + _hp[i]
		x += r * sin(ang)
		y += r * cos(ang)
		_pts3[used] = _strip_point(cu + x, cv + y)
		used += 1
	epi_tip = Vector2(x, y)
	_pts3.resize(used)
	if used >= 2:
		FxLineGeo.draw_immediate(_dyn_mesh, _pts3, edge_inward, 0.03, Color(1.0, 1.0, 1.0, (0.3 + 0.3 * m.beat_pulse) * br))
	# Trace: the tip's height over recent time, flowing left toward the strip.
	_trace_timer += dt
	if _trace_timer >= 1.0 / 30.0:
		_trace_timer = 0.0
		for i: int in range(TRACE_PTS - 1, 0, -1):
			_trace_y[i] = _trace_y[i - 1]
		_trace_y[0] = y
	var tc := palette.neon_a
	var t0 := cu - EPI_R - 0.25
	var span := 1.4
	_pts3.resize(TRACE_PTS)
	_cols.resize(TRACE_PTS)
	for i: int in TRACE_PTS:
		var u := t0 - (span * i) / (TRACE_PTS - 1)
		_pts3[i] = _strip_point(u, cv + _trace_y[i])
		_cols[i] = Color(tc.r, tc.g, tc.b, (0.55 * (1.0 - float(i) / TRACE_PTS)) * br)
	FxLineGeo.draw_immediate(_dyn_mesh, _pts3, edge_inward, 0.05, tc, false, _cols)
