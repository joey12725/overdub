extends ODTest
## The visualiser hub in a live tree (MUSIC-12): every kind builds, renders through its canvas,
## mounts on props / walls / floors / holograms without any physics, survives a level reload, and
## stays inside the decoration budget (well under 1 ms of CPU per frame in total).
## Run: `bash tools/gd test musicviz`.

const KINDS: Array[StringName] = [
	MusicVizHub.KIND_STACK_SCREEN, MusicVizHub.KIND_FRIEZE, MusicVizHub.KIND_EPICYCLE,
	MusicVizHub.KIND_EPICYCLE_WAVE, MusicVizHub.KIND_SIGILS, MusicVizHub.KIND_SIGIL,
	MusicVizHub.KIND_CONSTELLATION, MusicVizHub.KIND_RUNES, MusicVizHub.KIND_RUNE_ROW,
]

var hub: MusicVizHub = null
var root3d: Node3D = null


func before_each() -> void:
	hub = MusicVizHub.new()
	root3d = Node3D.new()
	tree().root.add_child(hub)
	tree().root.add_child(root3d)
	hub.load_level(ContentData.load_level("sandbox"))


func after_each() -> void:
	hub.dispose()
	hub.queue_free()
	root3d.queue_free()
	await tree().process_frame


func _tracks(beat: float) -> Array:
	var out: Array = []
	for i: int in 4:
		var t := TrackAudioState.make(true, [1.0, 2.0, 1.0, 0.5][i], OD.LifeState.ALIVE, true, 1)
		if i == 1 and beat > 6.0:
			t.synced = false
		if i == 2 and beat > 9.0:
			t.transport = -1
		if i == 3 and beat > 4.0:
			t.life = OD.LifeState.GHOST
		out.append(t)
	return out


func _has_physics(n: Node) -> bool:
	if n is CollisionObject3D or n is CollisionShape3D:
		return true
	for c: Node in n.get_children():
		if _has_physics(c):
			return true
	return false


func test_music12_every_kind_builds_and_renders() -> void:
	for k: StringName in KINDS:
		var c := hub.canvas(k, 1)
		if not assert_true(c != null, "kind %s" % k):
			continue
		assert_true(hub.texture(k, 1) != null)
		assert_true(c.viz.music == hub.music)
	assert_eq(hub.canvas_count(), KINDS.size())
	assert_true(hub.canvas(MusicVizHub.KIND_FRIEZE, 1) == hub.canvas(MusicVizHub.KIND_FRIEZE, 1), "shared")
	var b := 0.0
	for f: int in 30:
		b += 0.1
		hub.update(b, _tracks(b), 1.0 / 60.0)
		await tree().process_frame
	hub.redraw_all()
	await tree().process_frame
	await tree().process_frame
	assert_true(hub.draw_cost_usec() > 0, "drawers ran (%d us)" % hub.draw_cost_usec())


func test_music12_mounts_are_plain_meshes_without_physics() -> void:
	var screen_model := Node3D.new()
	var screen := MeshInstance3D.new()
	screen.name = "Screen"
	screen.mesh = QuadMesh.new()
	screen_model.add_child(screen)
	root3d.add_child(screen_model)
	assert_true(hub.mount_screen(screen_model) == screen, "found the Screen surface")
	assert_true(screen.get_surface_override_material(0) is ShaderMaterial)
	assert_true(hub.mount_screen(Node3D.new()) == null, "no screen: null")
	var fr := hub.mount_frieze(root3d, Vector3(0, 0, 0), Vector3(6, 0, 0), 0.5, 0.4, Vector3(0, 0, 1))
	assert_near(fr.global_transform.basis.z.dot(Vector3(0, 0, 1)), 1.0, 1e-5, "faces the camera side")
	assert_near((fr.mesh as QuadMesh).size.x, 6.0, 1e-6)
	var fr2 := hub.mount_frieze(root3d, Vector3(0, 0, 0), Vector3(6, 0, 0), 0.5, 0.4, Vector3(0, 0, -1))
	assert_near(fr2.global_transform.basis.z.dot(Vector3(0, 0, -1)), 1.0, 1e-5, "flipped side")
	var sig := hub.mount_signature(root3d, Vector3(5, 0, 5), 1.4, 0.6)
	assert_eq(sig.size(), 4)
	var mat := sig[3].material_override as ShaderMaterial
	assert_vec_near(mat.get_shader_parameter(&"uv_rect"), Vector4(0.5, 0.5, 0.5, 0.5), 1e-6, "atlas cell of cassette D")
	hub.mount_hologram(root3d, Vector3(2, 0, 2), 0)
	hub.mount_constellation(root3d, Vector3(3, 0, 2))
	hub.mount_runes(root3d, Vector3(0, 0, 1), Vector3(4, 0, 1), 0.2, 0.3, Vector3(0, 0, 1))
	assert_false(_has_physics(root3d), "decoration only: no colliders")


func test_music12_static_layer_rerecords_only_on_change() -> void:
	var c := hub.canvas(MusicVizHub.KIND_SIGILS)
	var v := c.viz
	var st: Array = []
	for i: int in 4:
		st.append(TrackAudioState.make(true, 1.0, OD.LifeState.ALIVE, true, 1))
	hub.update(4.0 * hub.music.chord_beats - 0.5, st, 0.0)
	hub.redraw_all()
	await tree().process_frame
	var k0: String = v._recorded_key
	# Moving on inside the same settled chord keeps the static layer.
	hub.update(4.0 * hub.music.chord_beats - 0.25, st, 0.0)
	hub.redraw_all()
	assert_eq(v._recorded_key, k0, "settled: no re-record")
	# A chord change (redraw in progress) and a desync both change it.
	hub.update(4.0 * hub.music.chord_beats + 0.5, st, 0.0)
	hub.redraw_all()
	assert_ne(v._recorded_key, k0, "chord change re-records")
	var k1: String = v._recorded_key
	st[1].synced = false
	hub.update(4.0 * hub.music.chord_beats + 0.75, st, 0.0)
	hub.redraw_all()
	assert_ne(v._recorded_key, k1, "desync moves the cell to the dynamic layer")
	await tree().process_frame


func test_music12_reload_keeps_canvases_and_repoints_music() -> void:
	var c := hub.canvas(MusicVizHub.KIND_SIGILS)
	var old := hub.music
	hub.load_level(ContentData.load_level("sandbox"))
	assert_true(hub.music != old)
	assert_true(c.viz.music == hub.music)
	assert_eq(hub.canvas_count(), 1)


func test_music12_budget_well_under_a_millisecond() -> void:
	# A heavy level: a wave screen, a frieze, the signature, an epicycle hologram, the constellation
	# and a rune wall, mid-level (B desynced, C reversing, D dead).
	for k: StringName in [MusicVizHub.KIND_STACK_SCREEN, MusicVizHub.KIND_FRIEZE, MusicVizHub.KIND_SIGILS, MusicVizHub.KIND_CONSTELLATION, MusicVizHub.KIND_RUNES]:
		hub.canvas(k)
	hub.canvas(MusicVizHub.KIND_EPICYCLE, 2)
	var frames := 180
	var dt := 1.0 / 60.0
	# Dry pass: compiles every note bar the run will draw. In the game these bars are compiled by
	# the audio director ahead of playback (use_audio_director) or by the hub's prefetch, never in
	# the middle of a draw; the compile cost is reported, not budgeted as drawing.
	var compile_worst := 0
	var b := 24.0
	for f: int in frames + 30:
		var t0 := Time.get_ticks_usec()
		for i: int in 4:
			hub.music.update(b, _tracks(b))
			hub.music.notes_in(i, maxf(0.0, b - 10.0), b + 8.0)
		compile_worst = maxi(compile_worst, Time.get_ticks_usec() - t0)
		b += dt * 2.0
	# Measured pass from the same start (jumping back resets the visual memory, as a new take does).
	hub.update(24.0, _tracks(24.0), 0.0)
	hub.redraw_all()
	await tree().process_frame
	var update_us := 0
	var worst := 0
	b = 24.0
	for f: int in frames:
		b += dt * 2.0
		hub.update(b, _tracks(b), dt)
		update_us += hub.last_update_usec
		worst = maxi(worst, hub.last_update_usec)
		await tree().process_frame
	var per_frame := hub.frame_cost_usec(60.0) - hub.last_update_usec + float(update_us) / frames
	for line: String in hub.cost_report():
		print("[musicviz]   " + line)
	print("[musicviz] budget: update %.1f us/frame (worst %d us), total %.1f us/frame; one note-bar compile (cold, no audio director) up to %d us" % [float(update_us) / frames, worst, per_frame, compile_worst])
	assert_true(per_frame < 1000.0, "total CPU %.1f us/frame" % per_frame)

func test_music12_update_from_frame_uses_tracks_from_set_tracks() -> void:
	var f := RenderFrame.new()
	f.music.beat = 5.5
	f.dt = 1.0 / 60.0
	hub.set_tracks(_tracks(5.5))
	hub.update_from_frame(f)
	assert_near(hub.music.beat, 5.5, 1e-9)
	assert_true(hub.music.tracks[0].present, "states came from set_tracks")
	assert_near(hub.music.tracks[1].speed, 2.0, 1e-9)
	assert_eq(hub.music.tracks[3].life, OD.LifeState.GHOST)


func test_music13_intensity_dims_every_mount_and_themes_follow_the_level() -> void:
	var fr := hub.mount_frieze(root3d, Vector3(0, 0, 0), Vector3(4, 0, 0), 0.5, 0.4, Vector3(0, 0, 1))
	var ho := hub.mount_hologram(root3d, Vector3(2, 0, 2), 0)
	hub.set_intensity(MusicVizHub.intensity_for_mode(ViewMode.RECORD))
	for mi: MeshInstance3D in [fr, ho]:
		assert_near((mi.material_override as ShaderMaterial).get_shader_parameter(&"intensity"), 0.55, 1e-6)
	assert_near(MusicVizHub.intensity_for_mode(ViewMode.CINEMATIC), 1.0, 1e-9)
	# Theme: warm caps the energy and draws holograms over the scene; dark is additive light.
	var hm := ho.material_override as ShaderMaterial
	var lvl := ContentData.load_level("sandbox")
	hub.load_music(lvl.music, lvl.bpm, lvl.horizon_bars, LevelTheme.LOWER)
	assert_near(hm.get_shader_parameter(&"additive"), 1.0, 1e-6, "dark: additive")
	assert_near(hm.get_shader_parameter(&"energy"), 2.2, 1e-6)
	hub.load_music(lvl.music, lvl.bpm, lvl.horizon_bars, LevelTheme.UPPER)
	assert_near(hm.get_shader_parameter(&"additive"), MVMount.WARM_HOLOGRAM_ADDITIVE, 1e-6, "warm: over")
	assert_near(hm.get_shader_parameter(&"energy"), MVMount.WARM_HOLOGRAM_ENERGY, 1e-6)
	assert_near((fr.material_override as ShaderMaterial).get_shader_parameter(&"energy"), MVMount.WARM_SURFACE_ENERGY, 1e-6)


func test_music12_audio_director_notes_match_the_visualiser_port() -> void:
	var lvl := ContentData.load_level("sandbox")
	var director := AudioDirector.new(lvl)
	var adapter := MVAudioNotes.make(director)
	if not assert_true(adapter != null, "adapter accepts the AudioDirector"):
		return
	var own := MVMusic.from_level(lvl)
	var compared := 0
	for i: int in 4:
		for v: MVVariant in [MVVariant.make(1.0), MVVariant.make(2.0), MVVariant.make(1.0, true), MVVariant.make(0.5, false, -1), MVVariant.make(1.0, false, 0), MVVariant.make(1.0, false, 1, 0.5)]:
			for bar: int in [0, 3]:
				var a := adapter.bar_notes(i, v, bar)
				var m := own.notes.bar_notes(i, v, bar)
				if not assert_eq(a.size(), m.size(), "layer %d variant %s bar %d: note count" % [i, v.key(), bar]):
					continue
				for k: int in a.size():
					assert_near(a[k].beat, m[k].beat, 1e-6, "onset")
					assert_eq(a[k].pitch, m[k].pitch, "pitch")
					assert_eq(a[k].velocity, m[k].velocity, "velocity")
					assert_near(a[k].duration, m[k].duration, 1e-6, "duration")
					compared += 1
	assert_true(compared > 50, "compared %d notes" % compared)
	# Installed through the hub, queries go to the director.
	assert_true(hub.use_audio_director(director))
	assert_true(hub.music.note_source.is_valid())
	assert_false(hub.use_audio_director(Object.new()), "not a director")
