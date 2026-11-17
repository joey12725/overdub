extends SceneTree
## Screenshots of every menu screen (res://ui/ui_root.tscn) over a small 3D room built from the
## environment kit, driven by fake campaign / loadout / results / settings models.
##
##   bash tools/gd shot res://tools/shot_menus.gd [-- <out_dir>] [only=<name-substring>]
##
## Default out dir: $TEMP/overdub_menu_shots (outside the repo). Prints one line per file written.
## Models are loaded by the asset-contract names (docs/GODOT-PORT.md); anything not delivered yet is a
## clearly temporary primitive (a magenta-tagged box / capsule) so the shot still composes.

const UI_SCENE := "res://ui/ui_root.tscn"
const KIT := "res://assets/models/kit/"
const MOXIE := "res://assets/models/moxie.glb"
const MOXIE_ANIMS := "res://assets/anim/moxie_anims.res"
const ENEMIES := "res://assets/models/enemies/"

var out_dir := ""
var only := ""
var ui: UiBase
var gear: ContentData.GearCatalogue
var intents: Array[String] = []
var stand_ins: Array[String] = []


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
		out_dir = tmp.path_join("overdub_menu_shots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var errors: Array[String] = []
	gear = ContentData.load_gear(errors)
	if gear == null:
		push_error("shot_menus: gear.json failed: %s" % [errors])
		quit(1)
		return
	root.size = Vector2i(1600, 900)
	_build_world()
	var layer := CanvasLayer.new()
	layer.layer = 10
	root.add_child(layer)
	ui = (load(UI_SCENE) as PackedScene).instantiate() as UiBase
	layer.add_child(ui)
	ui.intent.connect(func(i: UiIntent) -> void: intents.append(i.describe()))
	await process_frame

	ui.set_settings(_settings(false))
	ui.set_campaign(_campaign(3))
	ui.set_loadout(_loadout())

	var shots: Array = [
		["01_title", func() -> void: _show(UiScreen.TITLE)],
		["02_title_confirm_new", func() -> void:
			_show(UiScreen.TITLE)
			_nav([UiBase.NAV_DOWN, UiBase.NAV_ACCEPT])],
		["03_title_fresh_gamepad", func() -> void:
			ui.set_campaign(_campaign(0))
			ui.set_device(UiBase.DEVICE_GAMEPAD)
			_show(UiScreen.CAMPAIGN)
			_show(UiScreen.TITLE)],
		["04_campaign", func() -> void:
			ui.set_device(UiBase.DEVICE_KEYBOARD)
			ui.set_campaign(_campaign(3))
			_show(UiScreen.CAMPAIGN)],
		["05_campaign_locked_poke", func() -> void:
			_show(UiScreen.CAMPAIGN)
			_nav([UiBase.NAV_DOWN, UiBase.NAV_DOWN, UiBase.NAV_ACCEPT])],
		["06_campaign_bottom_patterns", func() -> void:
			ui.set_settings(_settings(true))
			ui.set_campaign(_campaign(7))
			_show(UiScreen.CAMPAIGN)],
		["07_loadout_slots", func() -> void:
			ui.set_settings(_settings(false))
			_loadout_at(1)],
		["08_loadout_melee_compare", func() -> void:
			_loadout_at(4)
			_nav([UiBase.NAV_ACCEPT, UiBase.NAV_DOWN, UiBase.NAV_DOWN, UiBase.NAV_DOWN])],
		["09_loadout_ranged_compare", func() -> void:
			_loadout_at(5)
			_nav([UiBase.NAV_ACCEPT, UiBase.NAV_DOWN])],
		["10_settings", func() -> void:
			_show(UiScreen.SETTINGS)
			_nav([UiBase.NAV_DOWN, UiBase.NAV_LEFT, UiBase.NAV_LEFT])],
		["11_settings_erase_confirm", func() -> void:
			_show(UiScreen.SETTINGS)
			for k in 7:
				_nav([UiBase.NAV_DOWN])
			_nav([UiBase.NAV_ACCEPT])],
		["12_play_toasts", func() -> void:
			_show(UiScreen.PLAY)
			ui.update_hud(_session(SessionPhase.SETUP), MusicPulse.new())
			ui.toast("Tape B desynced — its spark is finding the way back", UiBase.TONE_WARN)
			ui.toast("New gear: Needle Rail", UiBase.TONE_GOOD)
			ui.toast("Committed tape A at ½×")],
		["13_pause_mid_take", func() -> void:
			_show(UiScreen.PLAY)
			ui.update_hud(_session(SessionPhase.RECORDING), MusicPulse.new())
			_show(UiScreen.PAUSE)],
		["14_pause_settings", func() -> void:
			_show(UiScreen.PLAY)
			ui.update_hud(_session(SessionPhase.SETUP), MusicPulse.new())
			_show(UiScreen.PAUSE)
			_nav([UiBase.NAV_DOWN, UiBase.NAV_DOWN, UiBase.NAV_ACCEPT, UiBase.NAV_DOWN, UiBase.NAV_DOWN, UiBase.NAV_DOWN])],
		["15_results_win", func() -> void:
			ui.set_results(_results(true))
			_show(UiScreen.RESULTS)],
		["16_results_fail", func() -> void:
			ui.set_results(_results(false))
			_show(UiScreen.RESULTS)
			_nav([UiBase.NAV_RIGHT])],
		["17_ending", func() -> void:
			ui.set_campaign(_campaign(8))
			_show(UiScreen.ENDING)],
		["18_loadout_720p", func() -> void:
			root.size = Vector2i(1280, 720)
			ui.set_campaign(_campaign(3))
			_loadout_at(4)
			_nav([UiBase.NAV_ACCEPT, UiBase.NAV_DOWN])],
		["19_campaign_720p", func() -> void:
			_show(UiScreen.CAMPAIGN)],
		["20_pause_720p", func() -> void:
			root.size = Vector2i(1280, 720)
			_show(UiScreen.PLAY)
			ui.update_hud(_session(SessionPhase.RECORDING), MusicPulse.new())
			_show(UiScreen.PAUSE)],
	]
	# Integration screens (Field Guide, replays, loot moment, chapter card, dialogue, settings rows),
	# each at 1600x900 and 1280x720.
	for res: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		var tag := "" if res.x == 1600 else "_720p"
		var r := res
		shots.append_array([
			["21_title_keyart" + tag, func() -> void:
				root.size = r
				ui.set_device(UiBase.DEVICE_KEYBOARD)
				ui.set_campaign(_campaign(3))
				_show(UiScreen.TITLE)],
			["22_campaign_guide_watch" + tag, func() -> void:
				root.size = r
				ui.call("set_codex", _codex())
				ui.call("set_replays", {"gate": {"ok": true}, "cloister": {"ok": true}})
				ui.set_campaign(_campaign(3))
				_show(UiScreen.CAMPAIGN)
				_nav([UiBase.NAV_UP, UiBase.NAV_RIGHT])],
			["23_codex_page" + tag, func() -> void:
				root.size = r
				_show(UiScreen.CAMPAIGN)
				ui.call("open_codex", "shielder")],
			["24_codex_locked" + tag, func() -> void:
				root.size = r
				_show(UiScreen.CAMPAIGN)
				ui.call("open_codex", "laser")],
			["25_pause_guide" + tag, func() -> void:
				root.size = r
				_show(UiScreen.PLAY)
				ui.update_hud(_session(SessionPhase.SETUP), MusicPulse.new())
				_show(UiScreen.PAUSE)
				_nav([UiBase.NAV_DOWN, UiBase.NAV_DOWN, UiBase.NAV_DOWN])],
			["26_codex_from_pause" + tag, func() -> void:
				root.size = r
				_show(UiScreen.PLAY)
				ui.update_hud(_session(SessionPhase.DECISION), MusicPulse.new())
				_show(UiScreen.PAUSE)
				_nav([UiBase.NAV_DOWN, UiBase.NAV_DOWN, UiBase.NAV_DOWN, UiBase.NAV_ACCEPT, UiBase.NAV_DOWN, UiBase.NAV_DOWN])],
			["27_settings_access" + tag, func() -> void:
				root.size = r
				_show(UiScreen.SETTINGS)
				for k in 9:
					_nav([UiBase.NAV_DOWN])
				_nav([UiBase.NAV_RIGHT])],
			["28_settings_story" + tag, func() -> void:
				root.size = r
				_show(UiScreen.SETTINGS)
				for k in 13:
					_nav([UiBase.NAV_DOWN])],
			["29_results_loot" + tag, func() -> void:
				root.size = r
				ui.set_results(_results(true))
				_show(UiScreen.RESULTS)
				_nav([UiBase.NAV_ACCEPT])],
			["30_results_after_loot" + tag, func() -> void:
				root.size = r
				ui.set_results(_results(true))
				_show(UiScreen.RESULTS)
				_nav([UiBase.NAV_ACCEPT, UiBase.NAV_BACK])],
			["31_chapter_card" + tag, func() -> void:
				root.size = r
				_show(UiScreen.CAMPAIGN)
				var c: MenuChapterCard = ui.call("show_chapter_card", LevelTheme.LOWER, "Depth 06 - Glyphworks")
				c.seek(1.4)],
			["32_dialogue_intro" + tag, func() -> void:
				root.size = r
				_show(UiScreen.PLAY)
				var v := _session(SessionPhase.BRIEFING)
				ui.update_hud(v, MusicPulse.new())
				var dl: DialogueLayer = ui.get("dialogue")
				dl.begin_level("01-soft-open")
				dl.update(v, [] as Array[SimEvent], 0.016)
				print("  intro playing: %s" % dl.play_intro("01-soft-open", true))
				dl.player.box.call("set", "skip_progress", 0.0)],
			["33_play_toasts_art" + tag, func() -> void:
				root.size = r
				_show(UiScreen.PLAY)
				ui.update_hud(_session(SessionPhase.SETUP), MusicPulse.new())
				ui.toast("Tape B desynced — its spark is finding the way back", UiBase.TONE_WARN)
				ui.toast("Field guide: Shielder", UiBase.TONE_GOOD)
				ui.toast("Committed tape A at ½×")],
			["34_ending_card" + tag, func() -> void:
				root.size = r
				ui.set_campaign(_campaign(8))
				_show(UiScreen.ENDING)],
			["35_loadout_doll_icons" + tag, func() -> void:
				root.size = r
				ui.set_campaign(_campaign(3))
				_loadout_at(2)
				_nav([UiBase.NAV_ACCEPT, UiBase.NAV_DOWN, UiBase.NAV_DOWN])],
			["36_results_fail" + tag, func() -> void:
				root.size = r
				ui.set_results(_results(false))
				_show(UiScreen.RESULTS)],
		])
	var written := 0
	for sc: Array in shots:
		var name: String = sc[0]
		if only != "" and not name.contains(only):
			continue
		# Leave the previous screen so each shot enters fresh, without the previous shot's toasts.
		_show(UiScreen.PLAY)
		(ui.get("toasts") as MenuToasts).clear()
		await process_frame
		(sc[1] as Callable).call()
		var waits := 24
		if name.contains("dialogue"):
			waits = 150
		elif name.contains("ending_card") or name.contains("keyart"):
			waits = 60
		for k in waits:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var path := out_dir.path_join(name + ".png")
		var err := img.save_png(path)
		print("%s %s  %dx%d  screen=%s focus=%s" % ["wrote" if err == OK else "FAILED", path, img.get_width(), img.get_height(),
			ui.screen, (ui.get("menus") as MenuController).focus])
		written += 1
	print("shot_menus: intents seen: %s" % [intents])
	if not stand_ins.is_empty():
		print("shot_menus: temporary stand-ins for missing models: %s" % [stand_ins])
	print("shot_menus: %d file(s) in %s" % [written, out_dir])
	quit(0)


func _show(s: StringName) -> void:
	ui.show_screen(s)


## Open the loadout with the cursor on slot row `row` (0 = helmet ... 5 = ranged). The screen
## reopens on the slot browsed last, so walk to the top first.
func _loadout_at(row: int) -> void:
	_show(UiScreen.LOADOUT)
	for k in GearSlot.ALL.size():
		ui.navigate(UiBase.NAV_UP)
	for k in row:
		ui.navigate(UiBase.NAV_DOWN)


func _nav(cmds: Array) -> void:
	for c: StringName in cmds:
		ui.navigate(c)


# ───────────────────────────── fake models ─────────────────────────────

## A Field Guide with the machines, two traps and the tape pages met; the shielder page still new.
func _codex() -> Codex:
	var c := Codex.new()
	c.load_unlocked(["grunt", "stalker", "turret", "spikes", "crusher", "tape-speed", "count-in", "momentum", "gear-slots"])
	c.clear_new()
	c.unlock("shielder")
	return c


func _settings(patterns: bool) -> SaveSettings:
	var s := SaveSettings.new()
	s.master = 0.85
	s.music = 0.7
	s.sfx = 0.9
	s.av_offset_ms = 40
	s.patterns = patterns
	return s


const LEVELS := [
	["gate", "Sunlit Gate", "Two doors, one switch, and only you. For now.", LevelTheme.UPPER, 1, [1.0], [], ["kneepad_joggers"]],
	["cloister", "Vine Cloister", "The plate wants weight. Bring a friend from five seconds ago.", LevelTheme.UPPER, 2, [1.0, 2.0], [], ["hush_hood", "snap_trackies"]],
	["aqueduct", "Dry Aqueduct", "A turret lane, a slow rocket, and the long way round.", LevelTheme.UPPER, 2, [0.5, 1.0, 2.0], [OD.EndMode.STOP], ["needle_rail"]],
	["relay", "Relay Station", "Somebody wired the ruins for sound. Loudly.", LevelTheme.MID, 3, [0.5, 1.0, 2.0], [OD.EndMode.STOP, OD.EndMode.REPEAT], ["amp_sledge", "click_visor"]],
	["switchyard", "Switchyard", "Three gates on three beats. Pick your speeds.", LevelTheme.MID, 3, [0.5, 1.0, 2.0, 4.0], [OD.EndMode.STOP, OD.EndMode.REPEAT], ["bass_drop"]],
	["glyphworks", "Glyphworks", "Rune-cut metal and lasers that keep perfect time.", LevelTheme.LOWER, 4, [0.5, 1.0, 2.0, 4.0], [OD.EndMode.STOP, OD.EndMode.REPEAT, OD.EndMode.REVERSE], ["prism_goggles"]],
	["undertow", "Undertow", "Everything down here remembers what you did.", LevelTheme.LOWER, 4, [0.5, 1.0, 2.0, 4.0], [OD.EndMode.STOP, OD.EndMode.REPEAT, OD.EndMode.REVERSE], []],
	["chronovault", "The Time Machine", "The guardian learns from every tape you commit.", LevelTheme.CORE, 4, [0.5, 1.0, 2.0, 4.0], [OD.EndMode.STOP, OD.EndMode.REPEAT, OD.EndMode.REVERSE], []],
]


func _level(i: int) -> LevelDef:
	var d: Array = LEVELS[i]
	var l := LevelDef.new()
	l.id = d[0]
	l.index = i
	l.name = d[1]
	l.tagline = d[2]
	l.theme = d[3]
	l.max_tapes = d[4]
	l.speeds.assign(d[5])
	l.end_modes.assign(d[6])
	l.loot.assign(d[7])
	l.bars = 8
	l.horizon_bars = 16
	return l


func _campaign(cleared: int) -> CampaignScreenModel:
	var m := CampaignScreenModel.new()
	var n := LEVELS.size()
	m.current = mini(cleared, n - 1)
	for i in n:
		var e := CampaignLevelEntry.make(_level(i), i < cleared, i <= m.current)
		if e.cleared:
			e.has_loot = true
			for id in e.level.loot:
				var g := gear.get_item(id)
				if g != null:
					e.loot.append(g)
		m.levels.append(e)
	return m


func _loadout() -> LoadoutScreenModel:
	var m := LoadoutScreenModel.new()
	var owned := ["scrap_cap", "hush_hood", "click_visor", "lined_bomber", "ballast_puffer", "patchcord_hoodie",
		"olive_cargos", "snap_trackies", "kneepad_joggers", "beater_hightops", "grip_sprinters",
		"splice_blade", "amp_sledge", "reel_lash", "stylus_shiv", "mixtape_rocket", "needle_rail", "bass_drop"]
	for g in gear.items:
		if owned.has(g.id):
			m.inventory.append(g)
	m.loadout = gear.base_loadout.copy()
	m.loadout.pants = "kneepad_joggers"
	m.fresh.assign(["needle_rail", "bass_drop", "click_visor"])
	m.summary.assign(["Kneepad Joggers: Dodge cooldown −30%, dodge distance −15%", "Everything else baseline."])
	return m


func _results(win: bool) -> ResultsModel:
	var r := ResultsModel.new()
	r.level = _level(2)
	var o := Outcome.new()
	o.win = win
	o.objective_complete = win
	if win:
		o.notes.assign(["Objective complete: the aqueduct gate is open.", "Tape A held the plate for the whole run.", "Survivors: A, B."])
		r.loot.assign([gear.get_item("needle_rail")])
		r.has_next = true
		r.next_id = "relay"
	else:
		o.reason = FailReason.NO_SURVIVOR
		o.notes.assign(["Every self was down before the horizon.", "The turret lane caught tape B at beat 22."])
	r.outcome = o
	r.tapes_used = 2
	return r


func _session(phase: StringName) -> SessionView:
	var v := SessionView.new()
	v.phase = phase
	v.level = _level(4)
	v.active = 1
	v.horizon_beats = 64
	v.beat = 10.0
	v.speeds.assign([0.5, 1.0, 2.0, 4.0])
	v.objective.text = "Open all three gates"
	v.decks[0].status = DeckStatus.COMMITTED
	v.decks[0].speed = 0.5
	v.decks[0].end_mode = OD.EndMode.STOP
	v.decks[0].span_bars = 16
	v.decks[0].life = OD.LifeState.ALIVE
	v.decks[1].status = DeckStatus.RECORDING if phase == SessionPhase.RECORDING else DeckStatus.ARMED
	v.decks[1].speed = 2.0
	v.decks[1].end_mode = OD.EndMode.REPEAT
	v.decks[1].span_bars = 4
	v.decks[3].status = DeckStatus.UNAVAILABLE
	v.actions.assign([SessionAction.RECORD, SessionAction.QUIT] if phase == SessionPhase.SETUP else [SessionAction.QUIT])
	return v


# ───────────────────────────── 3D backdrop ─────────────────────────────

## A small upper-ruins room built from the kit, with a few enemies and Moxie, under an isometric
## orthographic camera, so the translucent menus are judged over a real-looking world.
func _build_world() -> void:
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#2a2420")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1.0, 0.86, 0.7)
	e.ambient_light_energy = 0.55
	e.glow_enabled = true
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	world.add_child(sun)

	var floors := ["floor_solid", "floor_cracked", "floor_overgrown", "floor_solid", "floor_rune", "floor_grate"]
	var w := 12
	var h := 10
	for z in h:
		for x in w:
			var edge := x == 0 or z == 0
			var piece: String = "wall" if edge else floors[(x * 7 + z * 3) % floors.size()]
			_place(world, _kit(piece), Vector3(x + 0.5, 0, z + 0.5), 0.0)
	_place(world, _kit("door"), Vector3(6.5, 0, 0.5), 0.0)
	_place(world, _kit("switch"), Vector3(3.5, 0, 3.5), 0.0)
	_place(world, _kit("plate"), Vector3(8.5, 0, 6.5), 0.0)
	_place(world, _kit("barrier_low"), Vector3(5.5, 0, 5.5), 0.0)
	_place(world, _kit("breakable"), Vector3(9.5, 0, 3.5), 0.0)
	_place(world, _kit("exit_pad"), Vector3(10.5, 0, 8.5), 0.0)
	_place(world, _model(ENEMIES + "grunt.glb", "grunt"), Vector3(7.5, 0, 4.5), PI)
	_place(world, _model(ENEMIES + "stalker.glb", "stalker"), Vector3(4.5, 0, 7.5), PI * 0.6)
	_place(world, _model(ENEMIES + "turret.glb", "turret"), Vector3(10.5, 0, 2.5), PI * 1.2)
	var moxie := _model(MOXIE, "moxie")
	_place(world, moxie, Vector3(5.5, 0, 3.0), 0.3)
	_pose_moxie(moxie)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 13.0
	var target := Vector3(6.5, 0, 5.0)
	var yaw := deg_to_rad(45.0)
	var pitch := deg_to_rad(35.0)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	world.add_child(cam)
	cam.look_at_from_position(target + dir * 30.0, target, Vector3.UP)
	cam.current = true


## Play Moxie's `idle` loop (docs/GODOT-PORT.md: res://assets/anim/moxie_anims.res, then any clip
## inside the glb, then the static rest pose), so the backdrop does not show a T-pose.
func _pose_moxie(moxie: Node3D) -> void:
	if moxie == null:
		return
	# The contract names the skeleton `Rig`; the interim glb nests it as Rig/Skeleton3D, so find it by class.
	var skels := moxie.find_children("*", "Skeleton3D", true, false)
	var skel: Skeleton3D = skels[0] as Skeleton3D if not skels.is_empty() else null
	if skel == null:
		return
	var players := moxie.find_children("*", "AnimationPlayer", true, false)
	var player: AnimationPlayer = players[0] as AnimationPlayer if not players.is_empty() else null
	if player == null:
		player = AnimationPlayer.new()
		moxie.add_child(player)
	if ResourceLoader.exists(MOXIE_ANIMS):
		var lib := load(MOXIE_ANIMS) as AnimationLibrary
		if lib != null and lib.has_animation(&"idle"):
			if player.has_animation_library(&"menu"):
				player.remove_animation_library(&"menu")
			# Keep the player's own root when the clip's tracks resolve from it; otherwise bind them
			# from the skeleton's parent (tracks are authored as Rig:<bone>).
			var idle := lib.get_animation(&"idle")
			if idle.get_track_count() > 0:
				var track_node := String(idle.track_get_path(0).get_concatenated_names())
				var from_root := player.get_node_or_null(player.root_node)
				if from_root == null or from_root.get_node_or_null(track_node) == null:
					player.root_node = player.get_path_to(skel.get_parent())
			player.add_animation_library(&"menu", lib)
			player.play(&"menu/idle")
			return
	for clip: StringName in [&"idle", &"Idle"]:
		if player.has_animation(clip):
			player.play(clip)
			return


func _kit(name: String) -> Node3D:
	for p: String in [KIT + name + "__upper.glb", KIT + name + ".glb"]:
		if ResourceLoader.exists(p):
			var n := _model(p, name)
			if n != null:
				return n
	return _stand_in(name)


func _model(path: String, name: String) -> Node3D:
	if ResourceLoader.exists(path):
		var ps := load(path) as PackedScene
		if ps != null:
			return ps.instantiate() as Node3D
	return _stand_in(name)


## Clearly temporary stand-in: a primitive in a loud magenta so nobody mistakes it for art.
func _stand_in(name: String) -> Node3D:
	if not stand_ins.has(name):
		stand_ins.append(name)
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.0, 0.8)
	if name == "moxie":
		var cap := CapsuleMesh.new()
		cap.radius = 0.25
		cap.height = 1.6
		cap.material = mat
		mi.mesh = cap
		mi.position.y = 0.8
	else:
		var box := BoxMesh.new()
		box.size = Vector3(0.9, 1.0 if name == "wall" else 0.1, 0.9)
		box.material = mat
		mi.mesh = box
		mi.position.y = box.size.y * 0.5
	var holder := Node3D.new()
	holder.add_child(mi)
	return holder


func _place(parent: Node3D, n: Node3D, pos: Vector3, yaw: float) -> void:
	if n == null:
		return
	n.position = pos
	n.rotation.y = yaw
	parent.add_child(n)
