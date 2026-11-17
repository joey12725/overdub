extends ODTest
## The world view end to end (headless): building the sandbox in every theme, the RenderCtx it hands
## the layers, mechanism visuals driven by MechSnap, wire accents, scatter readability rules and
## the facade's projections. Run with `bash tools/gd test world/`.

var _view: WorldViewBase = null


func _level(theme: StringName = LevelTheme.UPPER) -> LevelDef:
	var l := ContentData.load_level("sandbox", [])
	l.theme = theme
	return l


func before_each() -> void:
	_view = Facades.instance_world_view()
	tree().root.add_child(_view)


func after_each() -> void:
	if _view != null:
		_view.dispose()
		_view.queue_free()
		_view = null


func _frame(mechs: Dictionary, dt: float = 1.0 / 60.0) -> RenderFrame:
	var snap := FrameSnapshot.new()
	for id: String in mechs:
		var m := MechSnap.new()
		m.id = id
		m.on = mechs[id]
		snap.mechs.append(m)
	var f := RenderFrame.new()
	f.snap = snap
	f.prev = snap
	f.dt = dt
	f.mode = ViewMode.RECORD
	return f


func test_world_view_scene_is_provided() -> void:
	assert_true(Facades.is_provided(Facades.WORLD_VIEW_SCENE))
	assert_true(_view is WorldViewBase, "scene root extends WorldViewBase")
	assert_true(_view.has_method("set_bottom_inset"))


func test_loads_every_theme_and_fills_ctx() -> void:
	for theme: StringName in LevelTheme.ALL:
		var loaded := [false]
		var cb := func(_l: LevelDef) -> void: loaded[0] = true
		_view.level_loaded.connect(cb)
		_view.load_level(_level(theme), ResolvedLoadout.new())
		_view.level_loaded.disconnect(cb)
		assert_true(loaded[0], "%s: level_loaded emitted" % theme)
		var c := _view.ctx
		assert_true(c != null, "%s: ctx" % theme)
		assert_true(c.camera is Camera3D, "%s: camera" % theme)
		assert_eq(c.palette.theme, theme)
		assert_true(c.toon_material is ShaderMaterial and c.toon_material.next_pass != null, "%s: toon template with outline" % theme)
		assert_true(c.toon_ramp != null)
		assert_true(c.root != null and c.root.is_inside_tree(), "%s: layer root" % theme)
		assert_near(c.bounds.end.x, 14.0, 1e-6)
		assert_near(c.bounds.end.z, 10.0, 1e-6)
		assert_true(c.post != null)
		# Rune floor ('~') and the rune panel register as music-reactive.
		var kinds := {}
		for r: MusicReactive in c.music_reactive:
			kinds[r.kind] = true
			assert_true(r.material != null and r.apply_level.is_valid(), "reactive entry complete")
		assert_true(kinds.has(MusicReactive.KIND_RUNE), "%s: rune reactive" % theme)
		assert_true(kinds.has(MusicReactive.KIND_SCREEN), "%s: console screen reactive" % theme)
		assert_near(c.surface_height(9.5, 4.5), WorldLayout.BARRIER_HEIGHT, 1e-6)
		var stats: Dictionary = _view.call("build_stats")
		var walls := 0
		for row: String in c.level.map:
			walls += row.count("#")
		assert_eq(int(stats["counts"]["wall"]), walls, "%s: one wall piece per '#' tile" % theme)
		assert_true(int(stats["counts"]["cliff"]) > 0)


func test_music_reactive_set_level_scales_emission() -> void:
	_view.load_level(_level(LevelTheme.LOWER), ResolvedLoadout.new())
	for r: MusicReactive in _view.ctx.music_reactive:
		var m := r.material as ShaderMaterial
		var param := &"glow_energy" if m.get_shader_parameter(&"glow_energy") != null else (&"energy" if m.get_shader_parameter(&"energy") != null else &"emission_energy")
		var base: float = m.get_shader_parameter(param)
		r.set_level(2.0)
		var hi: float = m.get_shader_parameter(param)
		r.set_level(0.0)
		var lo: float = m.get_shader_parameter(param)
		r.set_level(1.0)
		assert_true(hi > base and lo == 0.0, "%s %s pulses (%s -> %s / %s)" % [r.kind, param, base, hi, lo])


func test_door_and_lever_share_accent() -> void:
	var lv := _level()
	var map := WorldMechAccent.build_map(lv)
	var door: DoorDef = null
	for e: EntityDef in lv.entities:
		if e is DoorDef:
			door = e
	assert_eq(WorldMechAccent.expr_accent(door.open_when, map), map["lever"], "door wears its lever's colour")
	# Distinct signals get distinct accents while the palette lasts; none is a cassette colour.
	assert_ne(map["lever"], map["plate"])
	for c: Color in map.values():
		for t: Color in OD.TAPE_COLORS_RGB:
			assert_true(c != t, "accent %s is not a cassette colour" % c)
	# The laser's accent follows its first signal (plate), the beam itself is always hazard red.
	var laser: LaserDef = null
	for e: EntityDef in lv.entities:
		if e is LaserDef:
			laser = e
	assert_eq(WorldMechAccent.expr_accent(laser.on_when, map), map["plate"])
	assert_eq(WorldMechAccent.expr_accent(SignalExpr.of_beat(4, 0, 2), map), WorldMechAccent.BEAT_ACCENT)


func test_door_opens_from_snapshot_only() -> void:
	_view.load_level(_level(), ResolvedLoadout.new())
	var door := _view.find_child("mech_gate", true, false) as Node3D
	assert_true(door != null, "door visual exists")
	var panel := door.find_child("Panel", true, false) as Node3D
	assert_true(panel != null, "door has a Panel part")
	var closed_y := panel.position.y
	var closed_s := panel.scale.y
	for i: int in range(90):
		_view.render(_frame({"gate": true}))
	var moved := panel.position.y < closed_y - 0.5 or panel.scale.y < closed_s * 0.2
	assert_true(moved, "panel slid / sank when the snapshot says open")
	for i: int in range(90):
		_view.render(_frame({"gate": false}))
	assert_near(panel.position.y, closed_y, 0.02, "closed again")
	assert_near(panel.scale.y, closed_s, 0.02, "closed again (scale)")


func test_switch_plate_laser_breakable_follow_snapshots() -> void:
	_view.load_level(_level(), ResolvedLoadout.new())
	var lever := _view.find_child("mech_lever", true, false).find_child("Lever", true, false) as Node3D
	var r_off := lever.rotation.z
	for i: int in range(60):
		_view.render(_frame({"lever": true, "plate": true, "beam": true, "cracked": false}))
	assert_true(lever.rotation.z < r_off - 1.0, "lever thrown")
	var pad := _view.find_child("mech_plate", true, false).find_child("Pad", true, false) as Node3D
	assert_true(pad.position.y < -0.03, "plate pad pressed")
	var laser := _view.find_child("mech_beam", true, false) as Node3D
	var beam_visible := false
	for n: Node in laser.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).visible and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).get_parent() != laser:
			beam_visible = true
	assert_true(beam_visible, "beam visible while firing")
	# Break the wall: the block hides and chunks fly, then settle on the floor.
	var brk := _view.find_child("mech_cracked", true, false) as Node3D
	var f := _frame({"cracked": true})
	f.events.append(SimEvent.make(0, SimEventType.BREAK, 5.5, 7.5).with_id("cracked").with_dir(0.0))
	_view.render(f)
	var shown := 0
	for n: Node in brk.find_children("*", "Node3D", true, false):
		if (n as Node3D).visible and (n.name.begins_with("Chunk") or n.get_parent() == brk):
			shown += 1
	assert_true(shown >= 8, "chunks visible after break (%d)" % shown)
	for i: int in range(200):
		_view.render(_frame({"cracked": true}))
	for n: Node in brk.get_children():
		if n is MeshInstance3D and (n as MeshInstance3D).visible:
			assert_true((n as Node3D).position.y >= -0.001 and (n as Node3D).position.y < 0.6, "chunk settled on the floor")


func test_graffiti_is_a_decal_on_env_layer() -> void:
	_view.load_level(_level(), ResolvedLoadout.new())
	var decals := _view.find_children("*", "Decal", true, false)
	assert_true(decals.size() >= 1, "graffiti decal built")
	for d: Node in decals:
		assert_eq((d as Decal).cull_mask, WorldBuilder.ENV_LAYER, "decal paints the environment only")
		assert_true((d as Decal).texture_albedo != null)


func test_scatter_never_blocks_the_floor() -> void:
	var lv := _level(LevelTheme.UPPER)
	var L := WorldLayout.compute(lv)
	var items := WorldScatter.plan(lv, L, WorldPalette.for_theme(LevelTheme.UPPER))
	assert_true(items.size() > 10, "dressing exists")
	var busy := WorldScatter.occupied_tiles(lv)
	for it: WorldScatter.Item in items:
		if WorldScatter.FLOOR_KINDS.has(it.kind):
			var cell := Vector2i(int(floor(it.x)), int(floor(it.y)))
			assert_false(busy.has(cell), "%s not on an entity tile %s" % [it.kind, cell])
			assert_true(WorldLayout.is_floor_char(L.at(cell.x, cell.y)), "%s on a floor tile" % it.kind)
		else:
			# Bulky items hang on walls / cliffs (their owning tile is a wall or the outline).
			var ch := L.at(int(floor(it.x)), int(floor(it.y)))
			assert_true(ch == "#" or it.kind == WorldScatter.CLIFF_ROCK or it.kind == WorldScatter.CLIFF_ROOT, "%s off the walkable floor" % it.kind)
	# Deterministic: same plan twice.
	var again := WorldScatter.plan(lv, L, WorldPalette.for_theme(LevelTheme.UPPER))
	assert_eq(again.size(), items.size())
	for i: int in range(items.size()):
		assert_near(again[i].x, items[i].x, 0.0)


func test_view_projection_and_shake() -> void:
	_view.load_level(_level(), ResolvedLoadout.new())
	_view.call("set_bottom_inset", 150.0)
	for i: int in range(240):
		_view.render(_frame({}))
	var up := _view.screen_up_in_world()
	assert_near(up.length(), 1.0, 1e-6)
	var size := _view.get_viewport().get_visible_rect().size
	var p := Vector2(size.x * 0.4, size.y * 0.3)
	var w := _view.screen_to_world(p)
	var cam: Camera3D = _view.ctx.camera
	var o := cam.project_ray_origin(p)
	var n := cam.project_ray_normal(p)
	var hit := o + n * (-o.y / n.y)
	assert_vec_near(w, Vector2(hit.x, hit.z), 1e-2, "screen_to_world agrees with the live Camera3D")
	_view.set_screen_shake(false)
	_view.ctx.shake(1.0)
	assert_near((_view.call("camera_rig") as WorldIsoCamera).trauma, 0.0, 1e-9, "shake ignored when disabled")
	_view.set_screen_shake(true)
	_view.ctx.shake(0.5)
	assert_near((_view.call("camera_rig") as WorldIsoCamera).trauma, 0.5, 1e-9)


func test_quality_switch() -> void:
	_view.load_level(_level(LevelTheme.LOWER), ResolvedLoadout.new())
	_view.set_quality(WorldViewBase.QUALITY_LOW)
	assert_eq(_view.ctx.quality, WorldViewBase.QUALITY_LOW)
	assert_false((_view.get("key_light") as DirectionalLight3D).shadow_enabled)
	_view.set_quality(WorldViewBase.QUALITY_HIGH)
	assert_true((_view.get("key_light") as DirectionalLight3D).shadow_enabled)


func test_toonkit_rematerials_a_scene() -> void:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var stone := StandardMaterial3D.new()
	stone.resource_name = "stone"
	stone.albedo_color = Color(0.7, 0.5, 0.4)
	bm.material = stone
	mi.mesh = bm
	root.add_child(mi)
	var mi2 := MeshInstance3D.new()
	var sm := SphereMesh.new()
	var glow := StandardMaterial3D.new()
	glow.resource_name = "rune_glow"
	glow.albedo_color = Color(1.0, 0.8, 0.4)
	sm.material = glow
	mi2.mesh = sm
	root.add_child(mi2)
	var made := ToonKit.apply_toon(root)
	assert_true(made.has("stone") and made.has("rune_glow"))
	assert_eq(made["stone"].shader, ToonKit.TOON_SHADER)
	assert_eq(made["stone"].get_shader_parameter(&"albedo"), Color(0.7, 0.5, 0.4), "base colour kept")
	assert_true(made["stone"].next_pass != null, "outline pass added")
	assert_eq(made["rune_glow"].shader, ToonKit.GLOW_SHADER, "_glow becomes emissive")
	assert_true(made["rune_glow"].next_pass == null, "no outline on glow")
	assert_true(mi.mesh.has_meta(&"od_smooth_normals"), "smooth normals baked for the hull")
	var arrays := mi.mesh.surface_get_arrays(0)
	assert_true(arrays[Mesh.ARRAY_CUSTOM0] != null, "CUSTOM0 present")
	root.free()
