extends SceneTree
## Screenshots of every widget in ui/widgets with fake data, on a warm (upper) and a dark (lower)
## backdrop. Each shot renders in an offscreen SubViewport and is saved as a PNG.
##
##   bash tools/gd shot res://tools/shot_widgets.gd [-- <out_dir>] [only=<name-substring>]
##
## Default out dir: $TEMP/overdub_widget_shots (outside the repo). Prints one line per file.
##
##   world_*   a small iso room (blocks stand in for the kit): threshold badges, hit-point pips, the
##             momentum gauge beside the live self (2x tape, running into the wall), off-screen
##             chevrons (ghost, desynced self + spark, telegraphing turret), the boss bar with the
##             memory tell lit for tape B, and the beatSight ticks on a mock ruler
##   gauge_*   four gauge states side by side: 0.5x standing at the wall, 2x running into it,
##             facing a brute, a CLANG explanation
##   boss_*    three boss bar states: guarded, acting on memory of tape B, staggered in phase 3
##   loot_*    the loot reveal mid-flight and finished (prompt showing)

const BACKDROPS := {
	"warm": "res://docs/reference/R03-upper-environment.png",
	"dark": "res://docs/reference/R04-lower-environment.png",
}
const RES := Vector2i(1600, 900)
const F := preload("res://tests/ui_widgets/widget_fixtures.gd")

var out_dir := ""
var only := ""


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
		elif a != "":
			out_dir = a
	if out_dir == "":
		var tmp := OS.get_environment("TEMP")
		if tmp == "":
			tmp = OS.get_environment("TMP")
		if tmp == "":
			tmp = "/tmp"
		out_dir = tmp.path_join("overdub_widget_shots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var written := 0
	for bg: String in ["warm", "dark"]:
		for kind: String in ["world", "gauge", "boss", "loot_mid", "loot_done"]:
			var name := "%s_%s" % [kind, bg]
			if only != "" and not name.contains(only):
				continue
			await _shoot(name, kind, bg)
			written += 1
	print("shot_widgets: %d file(s) in %s" % [written, out_dir])
	quit(0)


func _shoot(name: String, kind: String, bg: String) -> void:
	var vp := SubViewport.new()
	vp.size = RES
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_4X
	vp.msaa_2d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	# Backdrop on a canvas layer below the 3D (the environment uses the canvas as its background).
	var back := CanvasLayer.new()
	back.layer = -1
	vp.add_child(back)
	var tr := TextureRect.new()
	tr.size = Vector2(RES)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var img := Image.load_from_file(ProjectSettings.globalize_path(BACKDROPS[bg]))
	if img != null:
		tr.texture = ImageTexture.create_from_image(img)
	tr.modulate = Color(0.78, 0.78, 0.78) if bg == "warm" else Color(0.9, 0.9, 0.9)
	back.add_child(tr)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CANVAS
	e.background_canvas_max_layer = -1
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	e.ambient_light_energy = 0.8
	env.environment = e
	vp.add_child(env)
	var ui := Control.new()
	ui.size = Vector2(RES)
	vp.add_child(ui)
	match kind:
		"world":
			await _world(vp, ui, bg)
		"gauge":
			await _gauges(ui)
		"boss":
			await _bosses(ui)
		"loot_mid", "loot_done":
			await _loot(ui, bg, kind == "loot_done")
	await RenderingServer.frame_post_draw
	var shot := vp.get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	var err := shot.save_png(path)
	print("%s %s" % ["wrote" if err == OK else "FAILED", path])
	vp.queue_free()
	await process_frame


func _frames(n: int) -> void:
	for k in n:
		await process_frame


# ───────────────────────────── world ─────────────────────────────

func _block(parent: Node3D, pos: Vector3, size: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if col.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.position = pos + Vector3(0, size.y * 0.5, 0)
	parent.add_child(mi)


func _world(vp: SubViewport, ui: Control, bg: String) -> void:
	var w := Node3D.new()
	vp.add_child(w)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(30), 0)
	w.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 11.0
	cam.near = 1.0
	cam.far = 300.0
	w.add_child(cam)
	var target := Vector3(6.0, 0.0, 4.6)
	var yaw := PI / 4.0
	var pitch := 0.6154797086703873
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * 60.0
	cam.look_at_from_position(target + off, target, Vector3.UP)
	cam.current = true
	var floor_col := Color(0.45, 0.4, 0.33, 0.85) if bg == "warm" else Color(0.12, 0.12, 0.18, 0.9)
	_block(w, Vector3(6, -0.1, 5), Vector3(12, 0.1, 10), floor_col)
	var lvl := F.level()
	_block(w, Vector3(6.5, 0, 4.5), Vector3(1, 1.5, 1), Color("#b08a5a"))       # wall (threshold 5)
	_block(w, Vector3(2.5, 0, 7.5), Vector3(1, 1.5, 1), Color("#9a7a50"))       # weak wall
	_block(w, Vector3(9.5, 0, 7.5), Vector3(0.6, 1.0, 0.6), Color("#4ff3ff"))   # core
	_block(w, Vector3(8.0, 0, 7.0), Vector3(0.9, 1.9, 0.9), Color("#7a6a5a"))   # brute
	_block(w, Vector3(3.0, 0, 2.0), Vector3(0.6, 1.4, 0.6), Color("#6a7a8a"))   # shielder
	_block(w, Vector3(6.0, 0, 1.0), Vector3(1.8, 3.4, 1.8), Color("#3a2a4a"))   # boss
	_block(w, Vector3(4.6, 0, 4.5), Vector3(0.5, 1.6, 0.5), UiPalette.tape(0))  # live self
	var overlay := WidgetWorldOverlay.new()
	ui.add_child(overlay)
	await process_frame
	overlay.load_level(lvl, F.loadout(), F.memory([0, 1, 2] as Array[int]))
	overlay.set_camera(cam)
	overlay.set_bottom_inset(150.0)
	var snap := _world_snap()
	var view := F.view(SessionPhase.RECORDING, 0, 2.0)
	view.beat = 10.5
	view.threat_beats = [10.8, 12.0, 14.0, 14.02, 17.5]
	# Feed one healthy frame first so the boss bar has a damage-lag ghost to show.
	var first := _world_snap()
	first.enemies[3].hp = 40
	overlay.update_frame(first, view, [] as Array[SimEvent])
	await _frames(2)
	var events: Array[SimEvent] = [
		SimEvent.make(0, SimEventType.SWING, 14, 3).with_tape(1),
		SimEvent.make(0, SimEventType.BOSS_RECALL, 3, 6).with_id("archivist").with_tape(1).with_power(12.0).with_detail("dwell"),
	]
	overlay.update_frame(snap, view, events)
	overlay.boss_bar._fade = 1.0
	overlay.gauge.settle()
	# Mock ruler at the bottom with the beatSight ticks mounted on its top strip.
	var ruler := Panel.new()
	ruler.position = Vector2(200, RES.y - 120)
	ruler.size = Vector2(1200, 90)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiPalette.PANEL
	sb.set_corner_radius_all(10)
	ruler.add_theme_stylebox_override("panel", sb)
	ui.add_child(ruler)
	var ticks := WidgetThreatTicks.new()
	ticks.position = Vector2(0, 4)
	ticks.size = Vector2(1200, 22)
	ruler.add_child(ticks)
	ticks.set_track(60.0, 1120.0, view.horizon_beats)
	ticks.set_view(view)
	var line := ColorRect.new()
	line.color = UiPalette.PAPER
	line.position = Vector2(60, 28)
	line.size = Vector2(1120, 2)
	ruler.add_child(line)
	var head := ColorRect.new()
	head.color = UiPalette.PAPER
	head.position = Vector2(60 + 1120 * view.beat / view.horizon_beats, 4)
	head.size = Vector2(2, 80)
	ruler.add_child(head)
	await _frames(10)


func _world_snap() -> FrameSnapshot:
	var s := FrameSnapshot.new()
	s.beat = 10.5
	var live := F.actor(0, 4.6, 4.5, 0.0, true)
	live.vx = 9.0
	s.actors.append(live)
	var ghost := F.actor(1, 21.0, 1.5, 0.0)
	ghost.life = OD.LifeState.GHOST
	s.actors.append(ghost)
	var des := F.actor(2, -6.0, 12.0, 0.0)
	des.synced = false
	des.has_spark = true
	des.spark = Vector2(-5.0, 13.5)
	s.actors.append(des)
	var alive := F.actor(3, 21.5, 2.5, 0.0)
	s.actors.append(alive)
	s.enemies.append(F.enemy("brute", EnemyType.BRUTE, 8.0, 7.0, 2, 3))
	var sh := F.enemy("shielder", EnemyType.SHIELDER, 3.0, 2.0, 2, 2)
	sh.has_shield = true
	sh.shield = true
	s.enemies.append(sh)
	var tur := F.enemy("turret", EnemyType.TURRET, 2.0, 18.0, 1, 1)
	tur.state = EnemyStateName.TELEGRAPH
	tur.state_t = 0.7
	s.enemies.append(tur)
	s.enemies.append(F.boss(31, 2, 1))
	return s


# ───────────────────────────── gauges ─────────────────────────────

func _gauges(ui: Control) -> void:
	var lo := F.loadout()
	var lvl := F.level()
	var speeds: Array[float] = [0.5, 1.0, 2.0, 4.0]
	var cases := [
		["0.5× STANDING AT THE WALL", 0.5, Vector2.ZERO, false, ""],
		["2× RUNNING INTO THE WALL", 2.0, Vector2(9.0, 0), false, ""],
		["1× FACING A BRUTE (2/3 HP)", 1.0, Vector2(4.5, 0), true, ""],
		["1× CLANG ON THE WALL", 1.0, Vector2(4.5, 0), false, "needs 5"],
	]
	for i: int in cases.size():
		var c: Array = cases[i]
		var cell := Control.new()
		cell.size = Vector2(RES)
		ui.add_child(cell)
		var ox := i * 400.0
		var g := WidgetMomentumGauge.new()
		cell.add_child(g)
		g.setup(lvl, lo)
		var a := F.actor(i % 4, 4.6, 4.5, 0.0, true)
		var v: Vector2 = c[2]
		a.vx = v.x
		var snap := FrameSnapshot.new()
		snap.actors.append(a)
		if c[3]:
			snap.enemies.append(F.enemy("brute", EnemyType.BRUTE, 5.6, 4.5, 2, 3))
		var st := WidgetMath.gauge_state(a, float(c[1]), NAN, lo, lvl, snap, speeds)
		g.set_state(st, Vector2(ox + 200, 470), Vector2(ox + 290, 470))
		g.settle()
		if String(c[4]) != "":
			var ev: Array[SimEvent] = [SimEvent.make(0, SimEventType.CLANG, 6.5, 4.5).with_tape(a.tape).with_power(st.heavy.momentum).with_detail(c[4])]
			g.on_events(ev)
		var lab := Label.new()
		lab.text = c[0]
		lab.position = Vector2(ox + 20, 60)
		lab.add_theme_font_override("font", UiPalette.font_display())
		lab.add_theme_font_size_override("font_size", 20)
		lab.add_theme_color_override("font_outline_color", UiPalette.INK)
		lab.add_theme_constant_override("outline_size", 6)
		cell.add_child(lab)
		# A stand-in for Moxie under the gauge.
		var dot := ColorRect.new()
		dot.color = UiPalette.tape(a.tape)
		dot.position = Vector2(ox + 188, 440)
		dot.size = Vector2(24, 60)
		cell.add_child(dot)
		cell.move_child(dot, 0)
	await _frames(6)


# ───────────────────────────── boss bars ─────────────────────────────

func _bosses(ui: Control) -> void:
	var states := [
		[F.boss(40, 1), null, 0.0],
		[F.boss(24, 2, 1), F.memory([0, 1, 3] as Array[int]), 10.5],
		[F.boss(9, 3), F.memory([0, 2] as Array[int]), 20.0],
	]
	for i: int in states.size():
		var cell := Control.new()
		cell.position = Vector2(0, i * 300)
		cell.size = Vector2(RES.x, 300)
		ui.add_child(cell)
		var bar := WidgetBossBar.new()
		cell.add_child(bar)
		var s: Array = states[i]
		bar.set_memory(s[1])
		var e: EnemySnap = s[0]
		if i == 2:
			e.state = EnemyStateName.STAGGER
		# Previous frame with more hp so the ghost bar shows the last chunk.
		var prev := e.copy()
		prev.hp = mini(40, e.hp + 5)
		prev.boss_recall = false
		bar.update_boss(prev, float(s[2]) - 0.5)
		if i == 1:
			bar.on_events([SimEvent.make(0, SimEventType.BOSS_RECALL, 3, 6).with_id("archivist").with_tape(1).with_power(12.0).with_detail("dwell")] as Array[SimEvent])
		bar.update_boss(e, float(s[2]))
		if i == 2:
			bar.on_events([SimEvent.make(0, SimEventType.CLANG, 6, 2).with_id("archivist").with_tape(3).with_detail("armour")] as Array[SimEvent])
		bar._fade = 1.0
	await _frames(4)


# ───────────────────────────── loot ─────────────────────────────

func _loot(ui: Control, bg: String, done: bool) -> void:
	var lr := WidgetLootReveal.new()
	ui.add_child(lr)
	await process_frame
	lr.show_loot(F.items(), LevelTheme.UPPER if bg == "warm" else LevelTheme.LOWER, ["click_visor"])
	lr.playing = false
	if done:
		lr.skip()
	else:
		lr.seek(WidgetLootReveal.T_OPEN + 0.15 + WidgetLootReveal.CARD_GAP * 1.0 + 0.3)
	await _frames(8)
