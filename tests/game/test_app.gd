extends ODTest
## The application driven headlessly with stand-in facades: screens, the fixed-step loop, pause
## rules, gear lock, results / save, the cinematic lock and what reaches the world and audio. Port of
## prototype/tests/game/app.test.ts.

const F = preload("res://tests/game/game_fixtures.gd")


class FakeWorld:
	extends WorldViewBase
	var renders: Array[RenderFrame] = []
	var loaded: Array[String] = []
	var shake: Array[bool] = []
	var qualities: Array[StringName] = []

	func load_level(level: LevelDef, _loadout: ResolvedLoadout) -> void:
		loaded.append(level.id)

	func render(f: RenderFrame) -> void:
		renders.append(f)

	func screen_to_world(p: Vector2) -> Vector2:
		return p

	func set_quality(q: StringName) -> void:
		super.set_quality(q)
		qualities.append(q)

	func set_screen_shake(enabled: bool) -> void:
		super.set_screen_shake(enabled)
		shake.append(enabled)


class FakeAudio:
	extends AudioBase
	var counts: Array[int] = []
	var transports: Array = []
	var modes: Array[StringName] = []
	var ui_sounds: Array[StringName] = []
	var events: int = 0
	var volumes: Array = []
	var tracks_set: int = 0

	func set_transport(b: float, r: float, p: bool) -> void:
		transports.append([b, r, p])

	func set_tracks(_t: Array[TrackAudioState]) -> void:
		tracks_set += 1

	func on_events(e: Array[SimEvent]) -> void:
		events += e.size()

	func count_in(n: int) -> void:
		counts.append(n)

	func ui(k: StringName) -> void:
		ui_sounds.append(k)

	func set_mode(m: StringName) -> void:
		modes.append(m)

	func set_volumes(m: float, mu: float, s: float) -> void:
		volumes.append([m, mu, s])


class FakeUi:
	extends UiBase
	var screens: Array[StringName] = []
	var toasts: Array[String] = []
	var results: Array[ResultsModel] = []
	var navs: Array[StringName] = []
	var huds: int = 0
	var last_view: SessionView = null
	var devices: Array[StringName] = []
	var bindings: Dictionary = {}

	func show_screen(s: StringName) -> void:
		super.show_screen(s)
		screens.append(s)

	func update_hud(v: SessionView, _p: MusicPulse) -> void:
		huds += 1
		last_view = v

	func set_results(m: ResultsModel) -> void:
		results.append(m)

	func toast(t: String, _tone: StringName = TONE_INFO) -> void:
		toasts.append(t)

	func navigate(d: StringName) -> void:
		navs.append(d)

	func set_device(d: StringName) -> void:
		devices.append(d)

	func set_bindings(p: Dictionary[StringName, ButtonPrompt]) -> void:
		bindings = p


## Ticks come from a bot plan; actions are pushed by the test.
class ScriptedInput:
	extends GameInput
	var app: GameApp = null
	var take: GameBot.BotTake = null
	var queue: Array[StringName] = []
	var tick: int = 0
	var ctx := GameBot.BotContext.new()

	func push(a: StringName) -> void:
		queue.append(a)

	func sample(_up: Vector2, _pos: Variant = null) -> PlayerInput:
		var s := app.session
		var snap := s.current_frame().snap
		ctx.tick = tick
		ctx.index = s.active_index
		ctx.snap = snap
		for a: ActorSnap in snap.actors:
			if a.live:
				ctx.self_actor = a
		var out: PlayerInput = take.inputs.call(tick, ctx)
		tick += 1
		return out

	func drain_actions() -> Array[StringName]:
		var out := queue
		queue = []
		return out


var _apps: Array[GameApp] = []


func after_each() -> void:
	for a: GameApp in _apps:
		a.dispose()
		a.free()
	_apps.clear()


func _make(input: GameInput, storage: GameSave.Storage) -> Array:
	var w := FakeWorld.new()
	var au := FakeAudio.new()
	var u := FakeUi.new()
	var d := GameApp.Deps.new()
	d.world = w
	d.audio = au
	d.ui = u
	d.input = input
	d.storage = storage
	var sb: Array[LevelDef] = [CampaignData.sandbox()]
	d.levels = sb
	var app := GameApp.new()
	app.setup(d)
	_apps.append(app)
	return [app, w, au, u]


func _key(app: GameApp, code: Key) -> void:
	for pressed: bool in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = pressed
		app.input.handle_event(e)


func test_menus_count_in_pause_aborts_take_gear_lock_and_quitting() -> void:
	var made := _make(GameInput.new(), GameSave.memory_storage())
	var app: GameApp = made[0]
	var w: FakeWorld = made[1]
	var au: FakeAudio = made[2]
	var u: FakeUi = made[3]
	assert_eq(app.screen, UiScreen.TITLE)
	assert_has(w.loaded, "sandbox", "the backdrop level is built")
	app.frame(0.0)
	assert_eq(w.renders[w.renders.size() - 1].mode, ViewMode.IDLE)
	assert_true(u.bindings.has(SessionAction.RECORD), "bindings reach the UI")

	# Menu keys go to the UI.
	_key(app, KEY_DOWN)
	_key(app, KEY_ENTER)
	_key(app, KEY_ESCAPE)
	app.frame(0.016)
	assert_eq(u.navs, [UiBase.NAV_DOWN, UiBase.NAV_ACCEPT, UiBase.NAV_BACK])

	u.emit_intent(UiIntent.play_level("sandbox"))
	assert_eq(app.screen, UiScreen.PLAY)
	assert_eq(app.session.phase, SessionPhase.BRIEFING)
	_key(app, KEY_ENTER)
	app.frame(0.016)
	assert_eq(app.session.phase, SessionPhase.SETUP)
	_key(app, KEY_E)
	app.frame(0.016)
	assert_eq(app.session.speed, 2.0)
	_key(app, KEY_LEFT)
	app.frame(0.016)
	assert_eq(app.session.speed, 1.0)

	# GEAR-03: no loadout changes mid-level.
	u.emit_intent(UiIntent.simple(UiIntentType.OPEN_LOADOUT))
	assert_eq(app.screen, UiScreen.PLAY)
	assert_true(u.toasts[u.toasts.size() - 1].contains("locked"))
	u.emit_intent(UiIntent.equip(GearSlot.MELEE, "splice_blade"))
	assert_true(u.toasts[u.toasts.size() - 1].contains("cannot be equipped"))

	_key(app, KEY_SPACE)
	app.frame(0.016)
	assert_eq(app.session.phase, SessionPhase.COUNTIN)
	app.run_for(2.1)
	assert_eq(au.counts, [5, 6, 7, 8])
	assert_eq(app.session.phase, SessionPhase.RECORDING)
	app.run_for(1.0)
	var ticked := app.session.live_sim.local_tick
	assert_true(ticked > 50 and ticked <= 66, "ticked %d" % ticked)
	var rec := w.renders[w.renders.size() - 1]
	assert_eq(rec.mode, ViewMode.RECORD)
	assert_eq(rec.active, 0)
	assert_eq(rec.world_rate, 1.0)
	assert_eq(au.transports[au.transports.size() - 1][2], true)

	# OPEN-21: pausing mid-take abandons it.
	_key(app, KEY_ESCAPE)
	app.frame(0.25)
	assert_eq(app.screen, UiScreen.PAUSE)
	assert_eq(app.session.phase, SessionPhase.SETUP)
	assert_true(app.session.live_sim == null)
	assert_eq(au.transports[au.transports.size() - 1][2], false)
	u.emit_intent(UiIntent.simple(UiIntentType.RESUME))
	assert_eq(app.screen, UiScreen.PLAY)

	u.emit_intent(UiIntent.session(SessionAction.QUIT))
	assert_eq(app.screen, UiScreen.CAMPAIGN)
	assert_true(app.session == null)
	assert_eq(au.modes[au.modes.size() - 1], AudioBase.MODE_MENU, "a calm bed behind menus")
	u.emit_intent(UiIntent.simple(UiIntentType.OPEN_LOADOUT))
	assert_eq(app.screen, UiScreen.LOADOUT)


func test_a_winning_take_plays_the_cinematic_records_the_clear_and_loot_and_ends_on_the_ending_screen() -> void:
	var storage := GameSave.memory_storage()
	var input := ScriptedInput.new()
	input.take = F.solo_sweep()
	var made := _make(input, storage)
	var app: GameApp = made[0]
	var w: FakeWorld = made[1]
	var au: FakeAudio = made[2]
	var u: FakeUi = made[3]
	input.app = app
	u.emit_intent(UiIntent.play_level("sandbox"))
	input.push(GameInput.ACCEPT)  # briefing → setup
	app.frame(0.0)
	input.push(GameInput.ACCEPT)  # record
	app.frame(0.016)
	assert_eq(app.session.phase, SessionPhase.COUNTIN)
	var frames := 0
	while app.session.phase != SessionPhase.CINEMATIC and frames < 5000:
		app.frame(1.0 / 60.0)
		frames += 1
	if not assert_eq(app.session.phase, SessionPhase.CINEMATIC):
		return
	# 4-beat count-in (2 s) + 8 bars at 120 bpm (16 s) of wall time, one local tick per 1/60 s.
	assert_true(frames >= 18 * 60 - 3 and frames <= 18 * 60 + 3, "frames %d" % frames)
	app.frame(1.0 / 60.0)
	assert_eq(w.renders[w.renders.size() - 1].mode, ViewMode.CINEMATIC)
	assert_eq(w.renders[w.renders.size() - 1].active, -1)
	# CINE-02: gameplay keys and session actions during the cinematic change nothing.
	for a: StringName in [SessionAction.RETRY_TAKE, SessionAction.RESET_ALL, GameInput.ACCEPT, GameInput.PAUSE, SessionAction.SKIP]:
		input.push(a)
	app.frame(1.0 / 60.0)
	assert_eq(app.session.phase, SessionPhase.CINEMATIC)
	assert_eq(app.screen, UiScreen.PLAY)
	while app.screen != UiScreen.RESULTS and frames < 20000:
		app.frame(1.0 / 60.0)
		frames += 1
	assert_eq(app.screen, UiScreen.RESULTS)
	assert_eq(app.save.cleared, ["sandbox"])
	for id: String in CampaignData.sandbox().loot:
		assert_has(app.save.inventory, id)
	var stored: Variant = JSON.parse_string(storage.data[GameSave.SAVE_KEY])
	assert_eq(stored["cleared"], ["sandbox"])
	var res: ResultsModel = u.results[u.results.size() - 1]
	assert_false(res.has_next)
	assert_eq(res.tapes_used, 1)
	assert_true(res.outcome.win)
	var gear_toasts := 0
	for t: String in u.toasts:
		if t.begins_with("New gear"):
			gear_toasts += 1
	assert_eq(gear_toasts, CampaignData.sandbox().loot.size())
	assert_true(au.events > 0)
	assert_has(au.ui_sounds, AudioBase.UI_LOOT)

	# After the level, gear may change again (GEAR-03) …
	u.emit_intent(UiIntent.equip(GearSlot.MELEE, "reel_lash"))
	assert_eq(app.save.loadout.melee, "reel_lash")
	# … and continuing past the final level shows the ending.
	u.emit_intent(UiIntent.session(SessionAction.CONTINUE))
	assert_eq(app.screen, UiScreen.ENDING)


func test_cine_02_holding_skip_ends_the_cinematic_early_without_changing_the_result() -> void:
	var input := ScriptedInput.new()
	input.take = F.solo_sweep()
	var made := _make(input, null)
	var app: GameApp = made[0]
	var u: FakeUi = made[3]
	input.app = app
	u.emit_intent(UiIntent.play_level("sandbox"))
	input.push(GameInput.ACCEPT)
	app.frame(0.0)
	input.push(GameInput.ACCEPT)
	app.frame(0.016)
	var frames := 0
	while app.session.phase != SessionPhase.CINEMATIC and frames < 5000:
		app.frame(1.0 / 60.0)
		frames += 1
	if not assert_eq(app.session.phase, SessionPhase.CINEMATIC):
		return
	var res := app.session.resolution
	app.run_for(1.0)
	assert_eq(app.session.phase, SessionPhase.CINEMATIC)
	input.push(GameInput.SKIP_CINEMATIC)
	app.frame(1.0 / 60.0)
	assert_eq(app.screen, UiScreen.RESULTS)
	assert_true(app.session.resolution == res)
	assert_true(u.results[u.results.size() - 1].outcome.win)


func test_settings_apply_live_and_persist_erasing_the_save_starts_fresh() -> void:
	var storage := GameSave.memory_storage()
	var made := _make(GameInput.new(), storage)
	var app: GameApp = made[0]
	var w: FakeWorld = made[1]
	var au: FakeAudio = made[2]
	var u: FakeUi = made[3]
	u.emit_intent(UiIntent.setting("music", 0.3))
	assert_eq(au.volumes[au.volumes.size() - 1], [0.8, 0.3, 0.8])
	var stored: Variant = JSON.parse_string(storage.data[GameSave.SAVE_KEY])
	assert_eq(stored["settings"]["music"], 0.3)
	u.emit_intent(UiIntent.setting("screenShake", false))
	assert_eq(w.shake[w.shake.size() - 1], false)
	u.emit_intent(UiIntent.setting("nonsense", 1.0))
	u.emit_intent(UiIntent.simple(UiIntentType.ERASE_SAVE))
	assert_eq(app.save.settings.music, 0.8)
	assert_eq(app.save.cleared.size(), 0)
	assert_eq(w.shake[w.shake.size() - 1], true)
	app.set_quality(WorldViewBase.QUALITY_LOW)
	assert_eq(app.render_quality, WorldViewBase.QUALITY_LOW)
	assert_eq(w.qualities[w.qualities.size() - 1], WorldViewBase.QUALITY_LOW)


func test_a_locked_level_cannot_be_played_and_the_session_reaches_the_hud_each_frame() -> void:
	var made := _make(GameInput.new(), null)
	var app: GameApp = made[0]
	var u: FakeUi = made[3]
	assert_false(app.play_level("no_such_level"))
	assert_true(u.toasts[u.toasts.size() - 1].contains("locked"))
	assert_true(app.play_level("sandbox"))
	var before := u.huds
	app.run_for(0.5)
	assert_true(u.huds >= before + 29)
	assert_true(u.last_view is GameSessionView)
	assert_eq(u.last_view.phase, SessionPhase.BRIEFING)
