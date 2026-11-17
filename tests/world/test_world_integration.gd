extends ODTest
## The world view with the modules wired into it: music visualisers mounted from the level geometry,
## the cinematic director driving the camera, split-screen panes, painted decals and the
## accessibility options. Run with `bash tools/gd test world/`.

var _view: WorldViewBase = null


func before_each() -> void:
	_view = Facades.instance_world_view()
	tree().root.add_child(_view)
	# The runner starts suites from SceneTree._initialize(), before the root is in the tree. Split
	# panes, global transforms and afterimages need a live tree, so do not depend on an earlier
	# suite having awaited a frame (this suite is the first one under the `world` filter).
	if not _view.is_inside_tree():
		await tree().process_frame


func after_each() -> void:
	if _view != null:
		_view.dispose()
		_view.queue_free()
		_view = null


func _load(id: String) -> LevelDef:
	var lv := CampaignData.level(id)
	assert_true(lv != null, "level %s" % id)
	_view.load_level(lv, ResolvedLoadout.new())
	return lv


func _frame(mode: StringName, beat: float = 0.0) -> RenderFrame:
	var snap := FrameSnapshot.new()
	snap.beat = beat
	var f := RenderFrame.new()
	f.snap = snap
	f.prev = snap
	f.dt = 1.0 / 60.0
	f.mode = mode
	f.music = MusicPulse.new()
	f.music.beat = beat
	return f


func _nodes_named(root: Node, prefix: String) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if String(n.name).contains(prefix):
			out.append(n)
		for c: Node in n.get_children():
			stack.append(c)
	return out


func test_musicviz_mounted_on_every_campaign_level() -> void:
	var any_screen := false
	for lv: LevelDef in CampaignData.levels():
		_view.load_level(lv, ResolvedLoadout.new())
		var counts: Dictionary = _view.call("musicviz_counts")
		assert_true(int(counts.get("frieze", 0)) + int(counts.get("sigils", 0)) > 0, "%s: a frieze or the signature" % lv.id)
		assert_true(_view.ctx.musicviz_mounted, "%s: ctx says musicviz is mounted" % lv.id)
		var screens := 0
		for e: EntityDef in lv.entities:
			if e is DecorDef and (e as DecorDef).type == DecorType.WAVE_SCREEN:
				screens += 1
		assert_eq(int(counts.get("screen", 0)), screens, "%s: every wave screen shows the strip" % lv.id)
		any_screen = any_screen or screens > 0
		for mv: Node in _nodes_named(_view, "MV"):
			for c: Node in mv.get_children():
				assert_false(c is CollisionObject3D or c is CollisionShape3D, "no colliders under musicviz")
		_view.render(_frame(ViewMode.RECORD, 1.0))
	assert_true(any_screen, "some level has wave screens")


func test_mounted_screens_leave_the_fx_pulse() -> void:
	_load("11-the-archivist")
	var hub: MusicVizHub = _view.call("musicviz")
	var screen_mats: Array[Material] = []
	for n: Node in _nodes_named(_view, "decor_waveScreen"):
		var mi := MVMount.find_screen(n)
		if mi != null:
			for s: int in mi.mesh.get_surface_count():
				screen_mats.append(mi.get_surface_override_material(s))
	assert_true(screen_mats.size() > 0, "wave screens found")
	for m: Material in screen_mats:
		assert_true(m is ShaderMaterial and (m as ShaderMaterial).shader == MVMount.SURFACE_SHADER, "screen shows the Stack strip")
		for r: MusicReactive in _view.ctx.music_reactive:
			assert_false(r.material == m, "a musicviz surface is never pulsed by the fx layer")
	assert_true(hub.canvas_count() > 0, "canvases exist")


func test_boss_room_and_time_machine_get_holograms() -> void:
	_load("11-the-archivist")
	var c11: Dictionary = _view.call("musicviz_counts")
	assert_true(int(c11["hologram"]) >= 1, "boss room hologram")
	_load("12-master-tape")
	var c12: Dictionary = _view.call("musicviz_counts")
	assert_true(int(c12["hologram"]) >= 1, "time machine hologram")


func test_intensity_follows_mode() -> void:
	_load("05-dead-air")
	var hub: MusicVizHub = _view.call("musicviz")
	_view.render(_frame(ViewMode.RECORD))
	assert_near(hub.intensity, MusicVizHub.intensity_for_mode(ViewMode.RECORD), 1e-6)
	_view.render(_frame(ViewMode.CINEMATIC))
	assert_near(hub.intensity, 1.0, 1e-6)


func _cinema_frame(target: Vector2, span: float, cut: bool) -> CinemaFrame:
	var cf := CinemaFrame.new()
	cf.shot = CinemaShot.new()
	cf.shot_index = 1
	cf.target = target
	cf.span = span
	cf.cut = cut
	return cf


func test_camera_obeys_the_director_and_snaps_on_cuts() -> void:
	_load("05-dead-air")
	var iso: WorldIsoCamera = _view.call("camera_rig")
	var f := _frame(ViewMode.CINEMATIC, 2.0)
	f.cinema = _cinema_frame(Vector2(4.5, 4.5), 6.0, true)
	_view.render(f)
	var pose := CinemaCameraBridge.pose(f.cinema, iso.aspect(), iso.fit_size())
	var want := iso.clamp_target(4.5, 4.5, pose.view_size, 1.5)
	assert_near(iso.view_size, pose.view_size, 1e-3, "a cut sets the zoom at once")
	assert_near(iso.target_x, want.x, 1e-3, "a cut sets the target at once (x)")
	assert_near(iso.target_z, want.y, 1e-3, "a cut sets the target at once (z)")
	# Within a shot the camera follows the director quickly (no drift of its own).
	var g := _frame(ViewMode.CINEMATIC, 2.1)
	g.cinema = _cinema_frame(Vector2(9.5, 6.5), 6.0, false)
	for i: int in 90:
		_view.render(g)
	var want2 := iso.clamp_target(9.5, 6.5, iso.view_size, 1.5)
	assert_near(iso.target_x, want2.x, 0.05, "tracks the new target")
	# Layer focus requests are ignored while directed.
	_view.request_focus(1.0, 1.0, 1.0)
	_view.render(g)
	assert_near(iso.target_x, want2.x, 0.05, "focus requests do not pull a directed camera")


func test_world_runs_its_own_director_from_a_plan() -> void:
	var g := CinemaGolden.load_named("ghost-rescue")
	assert_true(g != null, "golden")
	_view.load_level(g.level, ResolvedLoadout.new())
	_view.call("set_cinema_plan", g.plan())
	var cuts := 0
	var frames := g.resolution.frames
	for k: int in range(1, frames.size()):
		var f := RenderFrame.new()
		f.snap = frames[k]
		f.prev = frames[k - 1]
		f.dt = 1.0 / 60.0
		f.mode = ViewMode.CINEMATIC
		f.music = MusicPulse.new()
		f.music.beat = frames[k].beat
		_view.render(f)
		var cf: CinemaFrame = _view.get("cinema_frame")
		assert_true(cf != null and cf.shot != null, "directed frame %d" % k)
		assert_true(f.cinema == cf, "the fx layer sees the same frame")
		if cf.cut:
			cuts += 1
	assert_true(cuts >= 2, "several hard cuts over the playback (%d)" % cuts)
	_view.render(_frame(ViewMode.REVIEW))
	assert_true(_view.get("cinema_frame") == null, "no direction outside the cinematic")


func test_split_screen_panes() -> void:
	_load("05-dead-air")
	var f := _frame(ViewMode.CINEMATIC, 2.0)
	var cf := _cinema_frame(Vector2(6.0, 4.0), 10.0, true)
	cf.split_t = 1.0
	for i: int in 2:
		var p := CinemaTypes.Pane.new()
		p.tape = i
		p.color = OD.tape_color(i)
		p.rect = Rect2(0.5 * i, 0.0, 0.5, 1.0)
		p.focus = Vector2(3.0 + 6.0 * i, 4.0)
		p.span = 6.0
		cf.panes.append(p)
	f.cinema = cf
	_view.render(f)
	var split: WorldSplitView = _view.get("_split")
	assert_eq(split.shown, 2, "two panes drawn")
	assert_true(split.visible, "split layer visible")
	_view.render(_frame(ViewMode.CINEMATIC, 3.0))
	assert_eq(split.shown, 0, "panes close when the shot has none")


func test_decals_painted_from_the_level() -> void:
	_load("09-rewind")
	var decals := 0
	for n: Node in _nodes_named(_view, "Decals"):
		for c: Node in n.get_children():
			if c is Decal:
				decals += 1
				assert_eq((c as Decal).cull_mask, WorldBuilder.ENV_LAYER, "decals paint the environment only")
	assert_true(decals > 0, "the flame lane and wear are painted (%d)" % decals)


func test_shake_scale_and_reduce_flashing_reach_the_layers() -> void:
	_load("01-soft-open")
	var iso: WorldIsoCamera = _view.call("camera_rig")
	_view.call("set_shake_scale", 0.0)
	_view.request_shake(1.0)
	assert_eq(iso.trauma, 0.0, "shake off")
	_view.call("set_shake_scale", 0.4)
	_view.request_shake(0.5)
	assert_near(iso.trauma, 0.2, 1e-6, "reduced shake")
	_view.call("set_reduce_flashing", true)
	_view.render(_frame(ViewMode.RECORD))
	assert_true(_view.ctx.reduce_flashing, "ctx carries reduce flashing")
	var fx: Node = _view.fx_layer
	var d: FxDirector = fx.get("director")
	assert_true(d.env.reduce_flashing, "the fx director honours it")
