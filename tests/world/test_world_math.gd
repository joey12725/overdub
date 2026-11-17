extends ODTest
## World maths: deterministic RNG parity with the prototype, the layout (cutaway rule, cliff skirt,
## surface heights), palettes (WORLD-04 lighting discipline) and the isometric camera's projections
## (checked against Godot's own Camera3D). Run with `bash tools/gd test world/`.


func _level(map: Array[String], theme: StringName = LevelTheme.UPPER, id: String = "t") -> LevelDef:
	var l := LevelDef.new()
	l.id = id
	l.theme = theme
	l.map = map
	return l


# ───────────────────────────── rng ─────────────────────────────

func test_rng_matches_prototype() -> void:
	# Values printed by prototype/src/render/env/rng.ts (vite-node).
	var s := WorldRng.hash_string("sandbox")
	assert_eq(s, 3659520292)
	assert_eq(WorldRng.hash_string("lever"), 2644110083)
	assert_eq(WorldRng.hash3(s, -2, 7), 3057743015)
	assert_near(WorldRng.tile_noise(s, 3, 4), 0.8117375816218555, 1e-12)
	var r := WorldRng.new(123)
	assert_near(r.next(), 0.7872516233474016, 1e-12)
	assert_near(r.next(), 0.1785435655619949, 1e-12)
	assert_near(r.next(), 0.49531551403924823, 1e-12)


func test_rng_ranges() -> void:
	var r := WorldRng.new(7)
	for i: int in range(200):
		var v := r.range_i(2, 4)
		assert_true(v >= 2 and v <= 4, "range_i in bounds")
		var f := r.range_f(-1.0, 1.0)
		assert_true(f >= -1.0 and f < 1.0, "range_f in bounds")


# ───────────────────────────── layout ─────────────────────────────

func test_layout_cutaway_rule() -> void:
	var L := WorldLayout.compute(_level([
		"#####",
		"#...#",
		"#.#.#",
		"#####",
	]))
	var by_cell := {}
	for w: WorldLayout.Wall in L.walls:
		by_cell[Vector2i(w.c, w.r)] = w
	# Back walls (row 0, column 0) stand full height.
	assert_false((by_cell[Vector2i(2, 0)] as WorldLayout.Wall).cut, "back wall full")
	assert_false((by_cell[Vector2i(0, 2)] as WorldLayout.Wall).cut, "left wall full")
	assert_true((by_cell[Vector2i(2, 0)] as WorldLayout.Wall).rim, "back wall is rim")
	# Camera-side walls with floor behind them are cut.
	assert_true((by_cell[Vector2i(2, 2)] as WorldLayout.Wall).cut, "interior wall with floor behind is cut")
	assert_true((by_cell[Vector2i(4, 1)] as WorldLayout.Wall).cut, "east rim with floor behind is cut")
	assert_true((by_cell[Vector2i(2, 3)] as WorldLayout.Wall).cut, "south rim with floor behind is cut")
	assert_near((by_cell[Vector2i(2, 3)] as WorldLayout.Wall).height, WorldLayout.WALL_CUT_HEIGHT, 1e-6)
	# Corner (0, 0) has nothing behind: full and a little taller as a rim wall.
	assert_true((by_cell[Vector2i(0, 0)] as WorldLayout.Wall).height > 1.4)


func test_layout_counts_and_bounds() -> void:
	var lv := ContentData.load_level("sandbox", [])
	assert_true(lv != null, "sandbox loads")
	var L := WorldLayout.compute(lv)
	assert_eq(L.cols, 14)
	assert_eq(L.rows, 10)
	var walls := 0
	var floors := 0
	for r: int in range(L.rows):
		for c: int in range(L.cols):
			if L.at(c, r) == "#":
				walls += 1
			elif WorldLayout.is_solid_ground(L.at(c, r)):
				floors += 1
	assert_eq(L.walls.size(), walls)
	assert_eq(L.floors.size(), floors)
	assert_eq(L.count_floor_kind(WorldLayout.FLOOR_RUNE), 4)
	assert_eq(L.count_floor_kind(WorldLayout.FLOOR_OVERGROWN), 5)
	assert_eq(L.barriers.size(), 2)
	# Every tile on the outline gets a cliff column, interior tiles none.
	assert_eq(L.cliffs.size(), 2 * 14 + 2 * 8)
	var b := L.bounds_aabb()
	assert_vec_near(b.position, Vector3(0, b.position.y, 0), 1e-6)
	assert_near(b.end.x, 14.0, 1e-6)
	assert_near(b.end.z, 10.0, 1e-6)
	assert_true(b.position.y < -1.0, "cliff below the floor")


func test_layout_surface_height() -> void:
	var lv := ContentData.load_level("sandbox", [])
	var L := WorldLayout.compute(lv)
	assert_near(L.surface_height(3.5, 3.5), 0.0, 1e-6, "floor")
	assert_near(L.surface_height(9.5, 4.5), WorldLayout.BARRIER_HEIGHT, 1e-6, "barrier")
	assert_true(L.surface_height(0.5, 0.5) > 1.0, "back corner wall is tall")
	assert_near(L.surface_height(13.5, 4.5), WorldLayout.WALL_CUT_HEIGHT, 1e-6, "camera-side wall cut")
	assert_near(L.surface_height(-5.0, 2.0), 0.0, 1e-6, "void")


func test_layout_is_deterministic() -> void:
	var lv := ContentData.load_level("sandbox", [])
	var a := WorldLayout.compute(lv)
	var b := WorldLayout.compute(lv)
	for i: int in range(a.floors.size()):
		assert_eq(a.floors[i].kind, b.floors[i].kind)
		assert_eq(a.floors[i].rot, b.floors[i].rot)
	for i: int in range(a.walls.size()):
		assert_near(a.walls[i].height, b.walls[i].height, 0.0)


# ───────────────────────────── palettes ─────────────────────────────

func test_palettes_upper_has_no_purple_light() -> void:
	# Chapter 18: no purple lighting cast up top (purple stays in the graffiti only).
	var p := WorldPalette.for_theme(LevelTheme.UPPER)
	for c: Color in [p.key_light, p.ambient, p.fill, p.shadow_tint]:
		var h := WorldPalette.hsl(c)
		var purple := h.x > 250.0 and h.x < 330.0 and h.y > 0.25
		assert_false(purple, "upper light %s is not purple" % c)
	var g := WorldPalette.hsl(p.graffiti_alt)
	assert_true(g.x > 250.0 and g.x < 300.0, "graffiti may be purple")


func test_palettes_darker_with_depth_but_floor_readable() -> void:
	var up := WorldPalette.for_theme(LevelTheme.UPPER)
	var low := WorldPalette.for_theme(LevelTheme.LOWER)
	var core := WorldPalette.for_theme(LevelTheme.CORE)
	assert_true(low.background.get_luminance() < up.background.get_luminance())
	assert_true(low.sun_energy < up.sun_energy)
	assert_true(core.sun_energy <= low.sun_energy)
	for p: WorldPalette in [low, core]:
		# A mid-value floor: never near black against the background.
		assert_true(p.floor_color.get_luminance() > p.background.get_luminance() + 0.2, "%s floor readable" % p.theme)
	assert_eq(WorldPalette.for_theme(&"nonsense").theme, LevelTheme.UPPER)


# ───────────────────────────── camera ─────────────────────────────

func _camera_for(size: Vector2, inset: float) -> WorldIsoCamera:
	var c := WorldIsoCamera.new()
	c.set_viewport(size.x, size.y)
	c.set_bottom_inset(inset)
	c.set_bounds(AABB(Vector3(0, -2, 0), Vector3(14, 4, 10)))
	c.introduce()
	var f := WorldIsoCamera.Framing.new()
	f.mode = ViewMode.RECORD
	c.settle(f)
	return c


func test_camera_iso_angles() -> void:
	var c := _camera_for(Vector2(1600, 900), 0.0)
	var fwd := c.forward_vector()
	assert_near(rad_to_deg(asin(-fwd.y)), 35.264, 0.01, "pitch")
	assert_near(rad_to_deg(atan2(-fwd.x, -fwd.z)), 45.0, 0.01, "yaw")
	# Camera sits on the +X / +Z side, so it looks toward -X / -Z.
	assert_true(fwd.x < 0.0 and fwd.z < 0.0)


func test_camera_projection_round_trip() -> void:
	for inset: float in [0.0, 180.0]:
		var c := _camera_for(Vector2(1600, 900), inset)
		c.target_x += 0.37
		c.shake_x = 0.05
		for p: Vector2 in [Vector2(0, 0), Vector2(800, 450), Vector2(1599, 899), Vector2(311, 712)]:
			var w := c.screen_to_world(p)
			var back := c.world_to_screen(Vector3(w.x, 0.0, w.y))
			assert_vec_near(back, p, 1e-3, "round trip at %s inset %s" % [p, inset])


func test_camera_matches_godot_camera3d() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1600, 900)
	vp.disable_3d = false
	var cam := Camera3D.new()
	vp.add_child(cam)
	tree().root.add_child.call_deferred(vp)
	await tree().process_frame
	if not assert_true(cam.is_inside_tree(), "camera in tree"):
		return
	cam.current = true
	for inset: float in [0.0, 200.0]:
		var c := _camera_for(Vector2(1600, 900), inset)
		c.target_x += 1.3
		c.target_z -= 0.6
		c.apply_to(cam)
		for p: Vector2 in [Vector2(10, 20), Vector2(800, 450), Vector2(1500, 860), Vector2(420, 640)]:
			var o := cam.project_ray_origin(p)
			var n := cam.project_ray_normal(p)
			var k := -o.y / n.y
			var hit := o + n * k
			var mine := c.screen_to_world(p)
			assert_vec_near(mine, Vector2(hit.x, hit.z), 1e-3, "screen_to_world vs Camera3D at %s inset %s" % [p, inset])
			var unp := cam.unproject_position(Vector3(mine.x, 0.0, mine.y))
			assert_vec_near(c.world_to_screen(Vector3(mine.x, 0.0, mine.y)), unp, 1e-2, "world_to_screen vs Camera3D")
	vp.queue_free()


func test_camera_screen_up_in_world() -> void:
	var c := _camera_for(Vector2(1600, 900), 120.0)
	var up := c.screen_up_in_world()
	assert_near(up.length(), 1.0, 1e-9)
	# At yaw 45 deg screen-up points to sim (-x, -y) equally.
	assert_vec_near(up, Vector2(-1.0, -1.0).normalized(), 1e-6)
	# Moving a point "up" on screen moves it along screen_up_in_world on the floor.
	var a := c.screen_to_world(Vector2(800, 500))
	var b := c.screen_to_world(Vector2(800, 400))
	assert_vec_near((b - a).normalized(), up, 1e-6)


func test_camera_fits_level_above_hud() -> void:
	for inset: float in [0.0, 220.0]:
		var c := _camera_for(Vector2(1600, 900), inset)
		# The level's floor corners all land inside the usable band (fits at a readable size).
		for corner: Vector3 in [Vector3(0, 0, 0), Vector3(14, 0, 0), Vector3(0, 0, 10), Vector3(14, 0, 10)]:
			var s := c.world_to_screen(corner)
			assert_true(s.x >= 0.0 and s.x <= 1600.0, "corner %s x on screen (inset %s)" % [corner, inset])
			assert_true(s.y >= 0.0 and s.y <= 900.0 - inset, "corner %s above the HUD (inset %s): %s" % [corner, inset, s])
		# Centred in the usable band.
		var mid := (c.world_to_screen(Vector3(0, 0, 0)).y + c.world_to_screen(Vector3(14, 0, 10)).y) * 0.5
		assert_true(absf(mid - (900.0 - inset) * 0.5) < (900.0 - inset) * 0.2, "level centred above the HUD")


func test_camera_follows_on_big_levels() -> void:
	var c := WorldIsoCamera.new()
	c.set_viewport(1600, 900)
	c.set_bounds(AABB(Vector3(0, -2, 0), Vector3(60, 4, 60)))
	c.introduce()
	var f := WorldIsoCamera.Framing.new()
	f.mode = ViewMode.RECORD
	f.follow = Vector2(8.0, 50.0)
	f.has_follow = true
	c.settle(f)
	assert_near(c.view_size, c.readable_size(), 1e-3, "zoomed to the readable size")
	var s := c.world_to_screen(Vector3(8.0, 0.0, 50.0))
	assert_true(s.x > 0.0 and s.x < 1600.0 and s.y > 0.0 and s.y < 900.0, "followed self on screen: %s" % s)


func test_camera_shake_and_focus() -> void:
	var c := _camera_for(Vector2(1600, 900), 0.0)
	c.add_trauma(0.8)
	assert_near(c.trauma, 0.8, 1e-9)
	c.add_trauma(-1.0)
	assert_near(c.trauma, 0.8, 1e-9, "negative ignored")
	var f := WorldIsoCamera.Framing.new()
	f.mode = ViewMode.CINEMATIC
	f.dt = 1.0 / 60.0
	f.time = 3.0
	c.request_focus(2.0, 3.0, 1.0)
	c.request_focus(4.0, 3.0, 1.0)
	c.update(f)
	assert_near(c.focus_x, 3.0, 1e-6, "weighted focus")
	assert_true(absf(c.shake_x) + absf(c.shake_y) > 0.0, "shake applied")
	for i: int in range(300):
		c.update(f)
	assert_near(c.trauma, 0.0, 1e-9, "trauma decays")
