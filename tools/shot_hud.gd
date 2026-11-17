extends SceneTree
## Screenshots of the in-level HUD (res://ui/hud/hud.tscn) driven by fake SessionViews that cycle
## through every phase and deck state. Each scenario renders in an offscreen SubViewport at its
## own resolution (1280x720 .. 3840x2160) over a reference-art backdrop, and is saved as a PNG.
##
##   bash tools/gd shot res://tools/shot_hud.gd [-- <out_dir>] [only=<name-substring>]
##
## Default out dir: $TEMP/overdub_hud_shots (outside the repo). Prints one line per file written.

const HUD_SCENE := "res://ui/hud/hud.tscn"
const WF := preload("res://tests/ui_widgets/widget_fixtures.gd")
const BACKDROPS: Array[String] = ["res://docs/reference/R03-upper-environment.png", "res://docs/reference/R04-lower-environment.png"]

var out_dir := ""
var only := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for a: String in args:
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
		out_dir = tmp.path_join("overdub_hud_shots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var scenarios: Array = [
		["01_briefing", Vector2i(1600, 900), _briefing()],
		["02_setup_tapeB", Vector2i(1600, 900), _setup()],
		["03_countin", Vector2i(1600, 900), _countin(7)],
		["04_rec_stamp", Vector2i(1600, 900), _recording(false)],
		["05_recording", Vector2i(1600, 900), _recording(false)],
		["06_recording_died", Vector2i(1600, 900), _recording(true)],
		["07_review", Vector2i(1600, 900), _review()],
		["08_decision_fail", Vector2i(1600, 900), _decision(false)],
		["09_decision_win", Vector2i(1600, 900), _decision(true)],
		["10_cinematic", Vector2i(1600, 900), _cinematic()],
		["11_setup_3tapes_gamepad", Vector2i(1600, 900), _setup_three()],
		["12_recording_720p", Vector2i(1280, 720), _recording(false)],
		["13_setup_720p", Vector2i(1280, 720), _setup()],
		["14_recording_4k", Vector2i(3840, 2160), _recording(false)],
		["15_review_patterns", Vector2i(1920, 1080), _review()],
		["16_resolving", Vector2i(1600, 900), _resolving()],
		["17_world_widgets_boss", Vector2i(1600, 900), _recording(false)],
		["18_world_widgets_boss_720p", Vector2i(1280, 720), _recording(false)],
		["19_resolving_720p", Vector2i(1280, 720), _resolving()],
		["20_briefing_720p", Vector2i(1280, 720), _briefing()],
		["21_countin_720p", Vector2i(1280, 720), _countin(6)],
		["22_review_720p", Vector2i(1280, 720), _review()],
		["23_decision_fail_720p", Vector2i(1280, 720), _decision(false)],
		["24_cinematic_720p", Vector2i(1280, 720), _cinematic()],
		["25_recording_died_720p", Vector2i(1280, 720), _recording(true)],
		["26_recording_reduce_flash_patterns", Vector2i(1600, 900), _recording(false)],
		["27_decision_win_720p", Vector2i(1280, 720), _decision(true)],
		["28_recording_shell_art_compare", Vector2i(1600, 900), _recording(false)],
	]
	var written := 0
	for sc: Array in scenarios:
		var name: String = sc[0]
		if only != "" and not name.contains(only):
			continue
		await _shoot(name, sc[1], sc[2])
		written += 1
	print("shot_hud: %d file(s) in %s" % [written, out_dir])
	quit(0)


func _shoot(name: String, res: Vector2i, view: SessionView) -> void:
	var vp := SubViewport.new()
	vp.size = res
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var img := Image.load_from_file(ProjectSettings.globalize_path(BACKDROPS[1 if name.contains("review") or name.contains("cinematic") else 0]))
	if img != null:
		bg.texture = ImageTexture.create_from_image(img)
	bg.modulate = Color(0.8, 0.8, 0.8)
	vp.add_child(bg)
	var hud: HudBase = (load(HUD_SCENE) as PackedScene).instantiate() as HudBase
	vp.add_child(hud)
	hud.action.connect(func(a: StringName) -> void: print("  action: ", a))
	var pulse := MusicPulse.new()
	pulse.beat_pulse = 0.8
	if name.contains("gamepad"):
		hud.set_device(HudBase.DEVICE_GAMEPAD)
		var b: Dictionary[StringName, ButtonPrompt] = {}
		for a: StringName in SessionAction.ALL:
			b[a] = HudModel.default_bindings(HudModel.DEVICE_GAMEPAD)[a]
		hud.set_bindings(b)
	if name.contains("patterns"):
		hud.set_patterns(true)
	HudDeck.use_shell_art = name.contains("shell_art")
	if name.contains("reduce_flash"):
		hud.call("set_reduce_flashing", true)
	if name.contains("world_widgets"):
		# World-anchored widgets through the HUD's game hooks, with a flat projection of the widget
		# test room onto the backdrop (a stand-in for the world camera).
		var ppx := 48.0 * res.y / 900.0
		var origin := Vector2(res.x * 0.28, res.y * 0.2)
		hud.call("set_world_projector", func(sim: Vector2, h: float) -> Vector2: return origin + sim * ppx - Vector2(0, h * ppx * 0.8))
		hud.call("load_level_widgets", WF.level(), WF.loadout(), WF.memory([0, 1, 2] as Array[int]))
	if name.contains("rec_stamp"):
		hud.update_hud(_countin(8), pulse)
		await process_frame
	hud.update_hud(view, pulse)
	if name.contains("world_widgets"):
		await process_frame
		var snap := _world_snap()
		var first := _world_snap()
		first.enemies[3].hp = 40
		hud.call("update_world", first, view, [] as Array[SimEvent])
		await process_frame
		var events: Array[SimEvent] = [SimEvent.make(0, SimEventType.BOSS_RECALL, 3, 6).with_id("archivist").with_tape(1).with_power(12.0).with_detail("dwell")]
		hud.call("update_world", snap, view, events)
		for k in 30:
			await process_frame
			hud.call("update_world", snap, view, [] as Array[SimEvent])
		print("  anchors: prompt:light=%s deck.speed=%s ruler.lane:2=%s world(4.6,4.5)=%s top_inset=%.0f" % [
			hud.call("anchor_rect", "prompt:light", {}), hud.call("anchor_rect", "deck.speed", {}),
			hud.call("anchor_rect", "ruler.lane:2", {}), hud.call("world_point_to_screen", Vector2(4.6, 4.5)), hud.call("top_inset")])
	if name.contains("decision_fail"):
		hud.set_hold_progress(0.62)
	var frames := 4 if name.contains("rec_stamp") else 12
	for k in frames:
		await process_frame
		if name.contains("recording") and k == 2:
			hud.deck_event(0, ActionKind.HEAVY)
			hud.deck_event(1, StateMarkKind.DESYNC)
		if name.contains("review") and k == 2:
			hud.deck_event(3, StateMarkKind.DEATH)
	await RenderingServer.frame_post_draw
	var shot := vp.get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	var err := shot.save_png(path)
	print("%s %s  inset=%.0f/%d" % ["wrote" if err == OK else "FAILED", path, hud.call("bottom_inset"), res.y])
	vp.queue_free()
	await process_frame


# ───────────────────────────── fake data ─────────────────────────────

func _level(max_tapes: int = 4) -> LevelDef:
	var L := LevelDef.new()
	L.id = "echo_chamber"
	L.index = 2
	L.name = "Echo Chamber"
	L.tagline = "Three doors, one switch and not enough of you. Yet."
	L.bpm = 120.0
	L.bars = 8
	L.horizon_bars = 16
	L.max_tapes = max_tapes
	L.speeds = [0.5, 1.0, 2.0, 4.0]
	L.end_modes = [OD.EndMode.STOP, OD.EndMode.REPEAT, OD.EndMode.REVERSE]
	L.objective.text = "Smash the time core and keep one self standing"
	L.briefing = [
		"Every take starts at master beat 0 - earlier tapes play alongside you.",
		"Record tape A to hold the switch; tape B can run through the open door.",
		"Faster tapes hit harder but finish sooner: 2x covers half the master bars.",
	]
	return L


func _base(phase: StringName, active: int, beat: float, max_tapes: int = 4) -> SessionView:
	var v := SessionView.new()
	v.phase = phase
	v.level = _level(max_tapes)
	v.active = active
	v.beat = beat
	v.horizon_beats = v.level.horizon_bars * OD.BEATS_PER_BAR
	v.world_rate = 1.0
	v.speeds = [0.5, 1.0, 2.0, 4.0]
	v.end_modes = [OD.EndMode.STOP, OD.EndMode.REPEAT, OD.EndMode.REVERSE]
	v.objective.text = v.level.objective.text
	v.objective.progress = 0.35
	v.objective.survivors = 2
	for i in 4:
		var d := v.decks[i]
		d.status = DeckStatus.UNAVAILABLE if i >= max_tapes else DeckStatus.EMPTY
	return v


func _marks(pairs: Array) -> Array[DeckMark]:
	var out: Array[DeckMark] = []
	for p: Array in pairs:
		out.append(DeckMark.make(p[0], p[1]))
	return out


func _committed(d: DeckView, speed: float, mode: int, beat: float, bars: float) -> void:
	d.status = DeckStatus.COMMITTED
	d.speed = speed
	d.end_mode = mode
	d.span_bars = bars / speed
	d.life = OD.LifeState.ALIVE
	d.synced = true
	var span := d.span_bars * OD.BEATS_PER_BAR
	var pass_i := floori(beat / span)
	var within := fmod(beat, span) / span
	if mode == OD.EndMode.STOP:
		d.local_progress = minf(1.0, beat / span)
		d.transport = 0 if beat >= span else 1
	elif mode == OD.EndMode.REPEAT:
		d.local_progress = within
		d.transport = 1
	else:
		d.local_progress = within if pass_i % 2 == 0 else 1.0 - within
		d.transport = 1 if pass_i % 2 == 0 else -1
	d.reel_rate = speed if d.transport != 0 else 0.0
	d.marks = _marks([[40, ActionKind.LIGHT], [130, ActionKind.HEAVY], [260, ActionKind.INTERACT], [400, ActionKind.DODGE], [700, ActionKind.RANGED]])


func _briefing() -> SessionView:
	var v := _base(SessionPhase.BRIEFING, 0, 0.0)
	v.actions = [SessionAction.START, SessionAction.QUIT]
	v.decks[0].status = DeckStatus.ARMED
	v.decks[0].speed = 1.0
	v.decks[0].end_mode = OD.EndMode.STOP
	v.decks[0].span_bars = 8.0
	return v


func _setup() -> SessionView:
	var v := _base(SessionPhase.SETUP, 1, 0.0)
	v.actions = [SessionAction.SPEED_UP, SessionAction.SPEED_DOWN, SessionAction.CYCLE_END_MODE, SessionAction.RECORD, SessionAction.QUIT]
	_committed(v.decks[0], 0.5, OD.EndMode.STOP, 0.0, 8.0)
	v.decks[0].transport = 0
	v.decks[0].local_progress = 0.0
	v.decks[0].life = -1
	var b := v.decks[1]
	b.status = DeckStatus.ARMED
	b.speed = 2.0
	b.end_mode = OD.EndMode.REPEAT
	b.span_bars = 4.0
	v.hint = "Tape A holds the switch from beat 4 - send B through the door before it closes."
	return v


func _setup_three() -> SessionView:
	var v := _base(SessionPhase.SETUP, 2, 0.0, 3)
	v.actions = [SessionAction.SPEED_UP, SessionAction.SPEED_DOWN, SessionAction.RECORD, SessionAction.QUIT]
	v.speeds = [1.0, 2.0]
	v.end_modes = [OD.EndMode.STOP]
	v.level.speeds = [1.0, 2.0]
	v.level.end_modes = [OD.EndMode.STOP]
	_committed(v.decks[0], 1.0, OD.EndMode.STOP, 0.0, 8.0)
	_committed(v.decks[1], 2.0, OD.EndMode.STOP, 0.0, 8.0)
	for d: DeckView in [v.decks[0], v.decks[1]]:
		d.transport = 0
		d.local_progress = 0.0
		d.life = -1
	var c := v.decks[2]
	c.status = DeckStatus.ARMED
	c.speed = 1.0
	c.end_mode = OD.EndMode.STOP
	c.span_bars = 8.0
	return v


func _countin(n: int) -> SessionView:
	var v := _setup()
	v.phase = SessionPhase.COUNTIN
	v.count = n
	v.actions = [SessionAction.QUIT]
	v.world_rate = 0.5
	v.hint = ""
	return v


func _recording(died: bool) -> SessionView:
	var beat := 13.5
	var v := _base(SessionPhase.RECORDING, 2, beat)
	v.actions = [SessionAction.QUIT]
	v.world_rate = 1.0
	_committed(v.decks[0], 0.5, OD.EndMode.STOP, beat, 8.0)
	_committed(v.decks[1], 2.0, OD.EndMode.REVERSE, beat, 8.0)
	v.decks[1].synced = false
	v.decks[1].state_marks = [DeckStateMark.make(10.0, StateMarkKind.DESYNC)]
	var c := v.decks[2]
	c.status = DeckStatus.RECORDING
	c.speed = 1.0
	c.end_mode = OD.EndMode.REPEAT
	c.span_bars = 8.0
	c.local_progress = beat / 32.0
	c.transport = 1
	c.reel_rate = 1.0
	c.life = OD.LifeState.REC_GHOST if died else OD.LifeState.ALIVE
	c.marks = _marks([[60, ActionKind.LIGHT], [150, ActionKind.DODGE], [300, ActionKind.HEAVY]])
	if died:
		c.state_marks = [DeckStateMark.make(11.0, StateMarkKind.DEATH)]
		v.objective.survivors = 1
	v.threat_beats = [16.0, 20.0, 24.5]
	return v


func _review() -> SessionView:
	var beat := 41.0
	var v := _base(SessionPhase.REVIEW, 3, beat)
	v.actions = [SessionAction.SKIP, SessionAction.END_ATTEMPT, SessionAction.QUIT]
	_committed(v.decks[0], 0.5, OD.EndMode.STOP, beat, 8.0)
	_committed(v.decks[1], 2.0, OD.EndMode.REVERSE, beat, 8.0)
	_committed(v.decks[2], 4.0, OD.EndMode.REPEAT, beat, 8.0)
	_committed(v.decks[3], 1.0, OD.EndMode.STOP, beat, 8.0)
	v.decks[3].status = DeckStatus.PENDING
	v.decks[2].life = OD.LifeState.GHOST
	v.decks[2].state_marks = [DeckStateMark.make(30.0, StateMarkKind.DEATH)]
	v.decks[1].state_marks = [DeckStateMark.make(6.0, StateMarkKind.DESYNC), DeckStateMark.make(14.0, StateMarkKind.RESYNC)]
	v.objective.progress = 0.8
	v.objective.survivors = 3
	v.threat_beats = [44.0, 48.0, 52.0]
	return v


## The game's resolving beat: phase REVIEW with GameSessionView.resolving (the take is being lined up).
func _resolving() -> SessionView:
	var r := _review()
	var v := GameSessionView.new()
	for f: String in ["phase", "level", "active", "beat", "horizon_beats", "world_rate", "speeds", "end_modes", "objective", "threat_beats"]:
		v.set(f, r.get(f))
	v.decks = r.decks
	v.beat = 0.0
	v.actions = [SessionAction.QUIT]
	v.resolving = true
	v.resolve_progress = 0.45
	v.status_text = GameSessionView.RESOLVING_TEXT
	return v


func _world_snap() -> FrameSnapshot:
	var s := FrameSnapshot.new()
	s.beat = 13.5
	var live := WF.actor(2, 4.6, 4.5, 0.0, true)
	live.vx = 9.0
	s.actors.append(live)
	var ghost := WF.actor(1, 21.0, 1.5, 0.0)
	ghost.life = OD.LifeState.GHOST
	s.actors.append(ghost)
	var des := WF.actor(0, -6.0, 12.0, 0.0)
	des.synced = false
	des.has_spark = true
	des.spark = Vector2(-5.0, 9.5)
	s.actors.append(des)
	s.enemies.append(WF.enemy("brute", EnemyType.BRUTE, 8.0, 7.0, 2, 3))
	var sh := WF.enemy("shielder", EnemyType.SHIELDER, 3.0, 2.0, 2, 2)
	sh.has_shield = true
	sh.shield = true
	s.enemies.append(sh)
	var tur := WF.enemy("turret", EnemyType.TURRET, 30.0, 4.0, 1, 1)
	tur.state = EnemyStateName.TELEGRAPH
	tur.state_t = 0.7
	s.enemies.append(tur)
	s.enemies.append(WF.boss(31, 2, 1))
	return s


func _decision(win: bool) -> SessionView:
	var v := _review()
	v.phase = SessionPhase.DECISION
	v.beat = 64.0
	v.actions = [SessionAction.RETRY_TAKE, SessionAction.COMMIT, SessionAction.RESET_ALL]
	var o := Outcome.new()
	o.win = win
	o.objective_complete = win
	if win:
		o.survivors = [0, 1, 3]
		o.notes = ["Tape A held the switch until bar 9 - the door stayed open for B."]
	else:
		o.survivors = []
		o.reason = FailReason.NO_SURVIVOR
		o.notes = [
			"Tape C died at master beat 30 - the turret's third volley.",
			"Tape B desynced at beat 6: the door closed in front of it; its spark caught up at beat 14.",
			"Tape D was hit at the very end - nobody was standing when bar 16 finished.",
		]
		v.actions = [SessionAction.RETRY_TAKE, SessionAction.RESET_ALL]
	v.outcome = o
	return v


func _cinematic() -> SessionView:
	var v := _review()
	v.phase = SessionPhase.CINEMATIC
	v.actions = [SessionAction.SKIP]
	v.decks[3].status = DeckStatus.COMMITTED
	v.objective.complete = true
	v.objective.progress = 1.0
	return v
