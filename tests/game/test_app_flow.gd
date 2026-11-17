extends ODTest
## The game flow around the session, driven headlessly with stand-ins: story sequencing (chapter
## card → intro → briefing; outro → ending → results → credits → stinger), session input held while
## a story step is up, replay storage on a win and "watch again", Field Guide unlocks persisted, and
## the new settings reaching the modules live.

const F = preload("res://tests/game/game_fixtures.gd")
const T = preload("res://tests/game/test_app.gd")
const REPLAY_ROOT := "user://test_app_flow_replays"


## A DialogueLayer stand-in: every call is recorded; the test decides when a sequence finishes.
class FakeDialogue:
	extends Node
	signal dialogue_finished(kind: StringName, key: String, skipped: bool)
	signal seen_changed
	signal bark_shown(key: String, line: Variant)
	var seen := DlgSeenStore.new()
	var calls: Array[String] = []
	var playing: StringName = &""
	var has_intro: bool = true
	var has_outro: bool = true
	var actions: Array[StringName] = []
	var inputs: Array[StringName] = []
	var updates: int = 0
	var last_phase: StringName = &""
	var results_loot: Array[bool] = []

	func _init() -> void:
		seen.changed.connect(func() -> void: seen_changed.emit())

	func set_seen_flags(flags: Variant) -> void:
		seen.load_array(flags)

	func get_seen_flags() -> Array[String]:
		return seen.to_array()

	func set_levels_cleared(_n: int) -> void:
		pass

	func begin_level(id: String, _lv: LevelDef = null) -> void:
		calls.append("begin:" + id)

	func end_level() -> void:
		calls.append("end")
		playing = &""

	func _start(kind: StringName, key: String, flag: String, want: bool) -> bool:
		if not want or seen.has(flag):
			return false
		seen.mark(flag)
		playing = kind
		calls.append("%s:%s" % [kind, key])
		return true

	func play_intro(id: String, _replay: bool = false) -> bool:
		return _start(&"intro", id, "story.%s.intro" % id, has_intro)

	func play_outro(id: String, _replay: bool = false) -> bool:
		return _start(&"outro", id, "story.%s.outro" % id, has_outro)

	func play_ending(_art: Texture2D = null, _replay: bool = false) -> bool:
		return _start(&"ending", "ending", "story.ending", true)

	func play_stinger() -> bool:
		return _start(&"stinger", "stinger", "story.stinger", true)

	func is_blocking() -> bool:
		return playing != &""

	func finish() -> void:
		var k := playing
		playing = &""
		dialogue_finished.emit(k, "", false)

	func update(v: SessionView, _events: Array[SimEvent], _dt: float, _snap: FrameSnapshot = null) -> void:
		updates += 1
		last_phase = v.phase

	func notify_action(a: StringName) -> void:
		actions.append(a)

	func notify_input(i: StringName = &"") -> void:
		inputs.append(i)

	func on_review_result(_o: Outcome, _e: Array[SimEvent] = []) -> void:
		calls.append("review")

	func on_results(has_loot: bool) -> void:
		results_loot.append(has_loot)


class FakeCard:
	extends Node
	signal finished


## The test_app FakeUi plus the UiRoot hooks the flow uses.
class StoryUi:
	extends T.FakeUi
	var dialogue: FakeDialogue = FakeDialogue.new()
	var cards: Array[String] = []
	var card: FakeCard = null
	var replays: Dictionary = {}
	var codex: Codex = null
	var codex_hints: Array[String] = []
	var cameras: int = 0
	var widget_levels: Array[String] = []
	var world_updates: int = 0

	func show_chapter_card(theme: StringName, subtitle: String = "", _hold: float = 2.6) -> FakeCard:
		cards.append("%s|%s" % [theme, subtitle])
		card = FakeCard.new()
		add_child(card)
		return card

	func set_replays(t: Dictionary) -> void:
		replays = t.duplicate()

	func set_codex(c: Codex) -> void:
		codex = c

	func set_codex_hint(entry_id: String) -> void:
		codex_hints.append(entry_id)

	func set_world_camera(_cam: Camera3D) -> void:
		cameras += 1

	func load_level_widgets(level: LevelDef, _lo: ResolvedLoadout, _bm: BossMemory = null) -> void:
		widget_levels.append(level.id)

	func update_world(_snap: FrameSnapshot, _v: SessionView = null, _e: Array[SimEvent] = []) -> void:
		world_updates += 1

	func set_aim(_a: float) -> void:
		pass

	func set_boss_memory(_m: BossMemory) -> void:
		pass


class FlowWorld:
	extends T.FakeWorld
	var plans: Array = []
	var reduce: Array[bool] = []
	var shake_scales: Array[float] = []
	var music_tracks: int = 0

	func set_cinema_plan(p: CinemaPlan) -> void:
		plans.append(p)

	func set_reduce_flashing(on: bool) -> void:
		reduce.append(on)

	func set_shake_scale(k: float) -> void:
		shake_scales.append(k)

	func set_music_tracks(_t: Array) -> void:
		music_tracks += 1


class FlowAudio:
	extends T.FakeAudio
	var voice_opts: Array = []

	func set_voice_options(v: StringName, b: bool, vol: float) -> void:
		voice_opts.append([v, b, vol])


var _apps: Array[GameApp] = []


func before_each() -> void:
	_wipe_replays()


func after_each() -> void:
	for a: GameApp in _apps:
		a.dispose()
		a.free()
	_apps.clear()
	_wipe_replays()


func _wipe_replays() -> void:
	var store := ReplayStore.new(REPLAY_ROOT)
	for id: String in store.list_level_ids():
		store.remove(id)


func _make(input: GameInput, storage: GameSave.Storage, replay_root: String = "") -> Array:
	var w := FlowWorld.new()
	var au := FlowAudio.new()
	var u := StoryUi.new()
	u.add_child(u.dialogue)
	var d := GameApp.Deps.new()
	d.world = w
	d.audio = au
	d.ui = u
	d.input = input
	d.storage = storage
	d.replay_root = replay_root
	var sb: Array[LevelDef] = [CampaignData.sandbox()]
	d.levels = sb
	var app := GameApp.new()
	app.setup(d)
	_apps.append(app)
	return [app, w, au, u]


## Play the sandbox through to the cinematic with the solo sweep (story steps finished on the way).
func _win(app: GameApp, input: T.ScriptedInput, u: StoryUi) -> bool:
	if u.card != null and is_instance_valid(u.card):
		u.card.finished.emit()
	if u.dialogue.playing == &"intro":
		u.dialogue.finish()
	input.tick = 0
	input.push(GameInput.ACCEPT)
	app.frame(0.0)
	input.push(GameInput.ACCEPT)
	app.frame(0.016)
	var frames := 0
	while app.session != null and app.session.phase != SessionPhase.CINEMATIC and frames < 5000:
		app.frame(1.0 / 60.0)
		frames += 1
	return app.session != null and app.session.phase == SessionPhase.CINEMATIC


func _to_results_phase(app: GameApp) -> void:
	var frames := 0
	while app.session != null and app.session.phase != SessionPhase.RESULTS and frames < 20000:
		app.frame(1.0 / 60.0)
		frames += 1


func test_story_sequences_card_intro_briefing_and_holds_session_input() -> void:
	var input := T.ScriptedInput.new()
	input.take = F.solo_sweep()
	var made := _make(input, GameSave.memory_storage())
	var app: GameApp = made[0]
	var u: StoryUi = made[3]
	input.app = app
	assert_true(app.dialogue == u.dialogue, "the UI's dialogue layer is wired")
	assert_true(app.play_level("sandbox"))
	# The first level of a theme opens with its chapter card, then the intro, then the briefing.
	assert_eq(u.cards.size(), 1)
	assert_true(u.cards[0].begins_with(String(CampaignData.sandbox().theme)))
	assert_eq(app.story_step, GameApp.STORY_CARD)
	assert_true(app.story_blocking())
	assert_has(u.dialogue.calls, "begin:sandbox")
	# Nothing reaches the session while the card is up (keys and HUD clicks alike).
	input.push(GameInput.ACCEPT)
	app.frame(0.016)
	u.emit_intent(UiIntent.session(SessionAction.START))
	assert_eq(app.session.phase, SessionPhase.BRIEFING)
	u.card.finished.emit()
	assert_eq(app.story_step, GameApp.STORY_INTRO)
	assert_has(u.dialogue.calls, "intro:sandbox")
	input.push(GameInput.ACCEPT)
	app.frame(0.016)
	assert_eq(app.session.phase, SessionPhase.BRIEFING, "the intro holds the briefing")
	assert_true(u.dialogue.updates > 0, "the layer is fed every frame")
	u.dialogue.finish()
	assert_eq(app.story_step, GameApp.STORY_NONE)
	input.push(GameInput.ACCEPT)
	app.frame(0.016)
	assert_eq(app.session.phase, SessionPhase.SETUP)
	assert_has(u.dialogue.actions, SessionAction.START, "applied actions reach the layer")
	# The flags are saved: a second visit plays neither the card nor the intro.
	assert_has(app.save.seen, "chapter.sandbox")
	assert_has(app.save.seen, "story.sandbox.intro")
	u.emit_intent(UiIntent.session(SessionAction.QUIT))
	assert_has(u.dialogue.calls, "end")
	assert_true(app.play_level("sandbox"))
	assert_eq(u.cards.size(), 1)
	assert_eq(app.story_step, GameApp.STORY_NONE)
	assert_false(app.story_blocking())


func test_a_win_plays_the_outro_then_the_ending_then_results_credits_and_stinger() -> void:
	var input := T.ScriptedInput.new()
	input.take = F.solo_sweep()
	var made := _make(input, GameSave.memory_storage())
	var app: GameApp = made[0]
	var w: FlowWorld = made[1]
	var u: StoryUi = made[3]
	input.app = app
	assert_true(app.play_level("sandbox"))
	if not assert_true(_win(app, input, u), "reached the cinematic"):
		return
	assert_eq(w.plans.size(), 1, "the cinematic director's plan drives the camera")
	assert_true(w.plans[0] is CinemaPlan)
	_to_results_phase(app)
	# The outro plays over the world before the results.
	assert_eq(app.story_step, GameApp.STORY_OUTRO)
	assert_eq(app.screen, UiScreen.PLAY)
	assert_eq(u.results.size(), 0)
	u.dialogue.finish()
	# Sandbox is the whole (one-level) campaign here, so the ending follows.
	assert_eq(app.story_step, GameApp.STORY_ENDING)
	assert_eq(u.results.size(), 0)
	u.dialogue.finish()
	assert_eq(app.screen, UiScreen.RESULTS)
	assert_eq(u.results.size(), 1)
	assert_eq(u.dialogue.results_loot, [true])
	u.emit_intent(UiIntent.session(SessionAction.CONTINUE))
	assert_eq(app.screen, UiScreen.ENDING)
	# Leaving the credits: the stinger, then the campaign.
	u.emit_intent(UiIntent.simple(UiIntentType.OPEN_CAMPAIGN))
	assert_eq(app.story_step, GameApp.STORY_STINGER)
	assert_has(u.dialogue.calls, "stinger:stinger")
	u.dialogue.finish()
	assert_eq(app.screen, UiScreen.CAMPAIGN)
	assert_eq(app.story_step, GameApp.STORY_NONE)


func test_the_winning_attempt_is_kept_and_can_be_watched_again() -> void:
	var input := T.ScriptedInput.new()
	input.take = F.solo_sweep()
	var made := _make(input, GameSave.memory_storage(), REPLAY_ROOT)
	var app: GameApp = made[0]
	var w: FlowWorld = made[1]
	var u: StoryUi = made[3]
	u.dialogue.has_intro = false
	u.dialogue.has_outro = false
	input.app = app
	assert_true(app.play_level("sandbox"))
	if not assert_true(_win(app, input, u)):
		return
	assert_true(app.replays.has_replay("sandbox"), "first clear: the win is kept")
	var first := app.replays.load_record("sandbox")
	assert_eq(first.tapes.size(), 1)
	# The same performance again (not fewer tapes) does not replace it.
	first.saved_at = 7
	app.replays.save(first)
	assert_false(app.keep_replay(app.session), "an equal clear keeps the kept replay")
	assert_eq(app.replays.load_record("sandbox").saved_at, 7)
	_to_results_phase(app)
	if u.dialogue.playing != &"":
		u.dialogue.finish()
	u.emit_intent(UiIntent.simple(UiIntentType.OPEN_CAMPAIGN))
	assert_eq(app.screen, UiScreen.CAMPAIGN)
	assert_eq(u.replays, {"sandbox": {"ok": true, "note": ""}})
	# Watch again: verified, played as the locked cinematic, back to the campaign when done.
	var i := UiIntent.new()
	i.type = GameApp.INTENT_WATCH_REPLAY
	i.id = "sandbox"
	var plans_before := w.plans.size()
	u.emit_intent(i)
	if not assert_true(app.replay_playback != null, "replay playing"):
		return
	assert_eq(app.screen, UiScreen.PLAY)
	assert_true(w.plans.size() > plans_before and w.plans[w.plans.size() - 1] is CinemaPlan)
	app.frame(1.0 / 60.0)
	assert_eq(w.renders[w.renders.size() - 1].mode, ViewMode.CINEMATIC)
	assert_true(u.last_view.actions.size() == 1 and u.last_view.actions[0] == SessionAction.SKIP)
	var frames := 0
	while app.replay_playback != null and frames < 20000:
		app.frame(1.0 / 60.0)
		frames += 1
	assert_true(app.replay_playback == null)
	assert_eq(app.screen, UiScreen.CAMPAIGN)


func test_a_stale_replay_is_marked_and_not_played() -> void:
	var made := _make(GameInput.new(), GameSave.memory_storage(), REPLAY_ROOT)
	var app: GameApp = made[0]
	var u: StoryUi = made[3]
	# A kept replay whose level hash no longer matches.
	var input := T.ScriptedInput.new()
	input.take = F.solo_sweep()
	var made2 := _make(input, GameSave.memory_storage(), REPLAY_ROOT)
	var winner: GameApp = made2[0]
	var u2: StoryUi = made2[3]
	u2.dialogue.has_intro = false
	input.app = winner
	assert_true(winner.play_level("sandbox"))
	if not assert_true(_win(winner, input, u2)):
		return
	var rec := app.replays.load_record("sandbox")
	rec.level_hash = "0000"
	app.replays.save(rec)
	app.campaign.record_clear("sandbox")
	app.refresh_replays()
	assert_false(bool(u.replays["sandbox"]["ok"]))
	assert_true(String(u.replays["sandbox"]["note"]).begins_with("Replay out of date"))
	assert_false(app.watch_replay("sandbox"))
	assert_true(app.replay_playback == null)


func test_field_guide_pages_unlock_on_first_encounter_and_persist() -> void:
	var storage := GameSave.memory_storage()
	var made := _make(GameInput.new(), storage)
	var app: GameApp = made[0]
	var u: StoryUi = made[3]
	if not assert_true(app.codex != null and app.codex.is_loaded(), "codex.json loads"):
		return
	assert_true(u.codex == app.codex, "the Field Guide reaches the menus")
	var before := app.codex.unlocked_count()
	assert_true(app.play_level("sandbox"))
	assert_true(app.codex.unlocked_count() > before, "the sandbox's enemies and props open pages")
	assert_eq(app.save.codex, app.codex.unlocked_ids())
	var stored: Variant = JSON.parse_string(storage.data[GameSave.SAVE_KEY])
	assert_eq(stored["codex"], app.save.codex, "persisted")
	var page_toasts := 0
	for t: String in u.toasts:
		if t.begins_with("Field Guide"):
			page_toasts += 1
	assert_eq(page_toasts, app.codex.unlocked_count() - before)
	# A fresh app on the same storage starts with those pages, and replaying unlocks nothing new.
	var made2 := _make(GameInput.new(), storage)
	var app2: GameApp = made2[0]
	var u2: StoryUi = made2[3]
	assert_eq(app2.codex.unlocked_ids(), app.codex.unlocked_ids())
	var t0 := u2.toasts.size()
	assert_true(app2.play_level("sandbox"))
	for k in range(t0, u2.toasts.size()):
		assert_false(u2.toasts[k].begins_with("Field Guide"))


func test_new_settings_apply_live_and_persist() -> void:
	var storage := GameSave.memory_storage()
	var made := _make(GameInput.new(), storage)
	var app: GameApp = made[0]
	var w: FlowWorld = made[1]
	var au: FlowAudio = made[2]
	var u: StoryUi = made[3]
	u.emit_intent(UiIntent.setting("reduceFlashing", true))
	assert_eq(w.reduce[w.reduce.size() - 1], true)
	assert_true(ActorOptions.reduce_flashing)
	u.emit_intent(UiIntent.setting("shakeScale", 0.4))
	assert_near(w.shake_scales[w.shake_scales.size() - 1], 0.4)
	u.emit_intent(UiIntent.setting("screenShake", false))
	assert_near(w.shake_scales[w.shake_scales.size() - 1], 0.0)
	u.emit_intent(UiIntent.setting("voices", false))
	assert_eq(au.voice_opts[au.voice_opts.size() - 1][0], AudioBase.VOICES_OFF)
	u.emit_intent(UiIntent.setting("holdMode", "press"))
	assert_true(app.input.press_twice)
	u.emit_intent(UiIntent.setting("quality", "low"))
	assert_eq(app.render_quality, WorldViewBase.QUALITY_LOW)
	u.emit_intent(UiIntent.setting("cassettePalette", "high_contrast"))
	assert_eq(ActorOptions.cassette_set, "high_contrast")
	u.emit_intent(UiIntent.setting("coachMarks", false))
	u.emit_intent(UiIntent.setting("holdMode", "sideways"))
	var stored: Dictionary = JSON.parse_string(storage.data[GameSave.SAVE_KEY])["settings"]
	assert_eq(stored["reduceFlashing"], true)
	assert_eq(stored["shakeScale"], 0.4)
	assert_eq(stored["voices"], false)
	assert_eq(stored["holdMode"], "press", "an unknown choice is refused")
	assert_eq(stored["quality"], "low")
	assert_eq(stored["coachMarks"], false)
	# A restart reads them back.
	var made2 := _make(GameInput.new(), storage)
	var app2: GameApp = made2[0]
	assert_true(app2.save.settings.reduce_flashing)
	assert_true(app2.input.press_twice)
	assert_eq(app2.render_quality, WorldViewBase.QUALITY_LOW)
	assert_eq((made2[1] as FlowWorld).quality, WorldViewBase.QUALITY_LOW, "the world got the saved quality")
	# Back to Auto after a pinned Low: high again, adaptive from there.
	(made2[3] as StoryUi).emit_intent(UiIntent.setting("quality", "auto"))
	assert_eq(app2.render_quality, WorldViewBase.QUALITY_HIGH)
	# The voice volume fader reaches the audio module and the save.
	u.emit_intent(UiIntent.setting("voiceVolume", 0.35))
	assert_near(float(au.voice_opts[au.voice_opts.size() - 1][2]), 0.35)
	assert_near(float(JSON.parse_string(storage.data[GameSave.SAVE_KEY])["settings"]["voiceVolume"]), 0.35)
	# Put the static actor options back for other suites.
	u.emit_intent(UiIntent.simple(UiIntentType.ERASE_SAVE))
	assert_false(ActorOptions.reduce_flashing)
	assert_eq(ActorOptions.cassette_set, AccessKit.SET_DEFAULT)


func test_press_twice_mode_confirms_reset_all_with_a_second_press() -> void:
	var t := [0.0]
	var gi := GameInput.new(func() -> float: return t[0])
	gi.press_twice = true
	var e := InputEventKey.new()
	e.physical_keycode = KEY_BACKSPACE
	e.keycode = KEY_BACKSPACE
	# Backspace is also the tap that ends a failing playback (endAttempt, tests/game/test_input.gd):
	# that tap still fires on every press, in this mode too. The session only accepts it in review,
	# where reset all is never on offer, so it is not counted here.
	var resets := func() -> int: return gi.drain_actions().count(SessionAction.RESET_ALL)
	for pressed: bool in [true, false]:
		e.pressed = pressed
		gi.handle_event(e.duplicate())
	assert_eq(resets.call(), 0, "the first press only arms")
	assert_eq(gi.hold_progress(SessionAction.RESET_ALL), 1.0, "armed: the ring shows full")
	assert_true(gi.is_armed(SessionAction.RESET_ALL))
	t[0] = 1.0
	for pressed: bool in [true, false]:
		e.pressed = pressed
		gi.handle_event(e.duplicate())
	assert_eq(resets.call(), 1, "the second press confirms, once")
	assert_eq(gi.hold_progress(SessionAction.RESET_ALL), 0.0)
	# An arm expires after 3 s.
	for pressed: bool in [true, false]:
		e.pressed = pressed
		gi.handle_event(e.duplicate())
	t[0] = 5.0
	for pressed: bool in [true, false]:
		e.pressed = pressed
		gi.handle_event(e.duplicate())
	assert_eq(resets.call(), 0, "too late: this press arms again")
	# Any other press cancels the arm.
	var other := InputEventKey.new()
	other.physical_keycode = KEY_R
	other.keycode = KEY_R
	other.pressed = true
	gi.handle_event(other)
	assert_eq(gi.hold_progress(SessionAction.RESET_ALL), 0.0, "another key disarms")
	for pressed: bool in [true, false]:
		e.pressed = pressed
		gi.handle_event(e.duplicate())
	assert_eq(resets.call(), 0)
	# The prompt drops "Hold" in this mode.
	assert_eq(GameInput.prompts(GameInput.DEVICE_KEYBOARD, true)[SessionAction.RESET_ALL].key, "Backspace")
	assert_eq(GameInput.prompts(GameInput.DEVICE_KEYBOARD)[SessionAction.RESET_ALL].key, "Hold Backspace")
	gi.dispose()


func _tap(gi: GameInput, key: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = key
	e.keycode = key
	for pressed: bool in [true, false]:
		e.pressed = pressed
		gi.handle_event(e.duplicate())


func test_press_twice_only_arms_where_reset_all_is_offered() -> void:
	var t := [0.0]
	var gi := GameInput.new(func() -> float: return t[0])
	var made := _make(gi, GameSave.memory_storage())
	var app: GameApp = made[0]
	var u: StoryUi = made[3]
	u.dialogue.has_intro = false
	u.emit_intent(UiIntent.setting("holdMode", "press"))
	assert_true(app.input.press_twice)
	app.frame(0.016)
	assert_eq((u.bindings[SessionAction.RESET_ALL] as ButtonPrompt).key, "Backspace", "the prompt follows the hold mode")
	assert_true(app.play_level("sandbox"))
	if u.card != null and is_instance_valid(u.card):
		u.card.finished.emit()
	# Setup with nothing committed: reset all is not offered, so a Backspace tap must not arm it
	# (two taps that end a playback would otherwise wipe every cassette a moment later).
	_tap(gi, KEY_ENTER)
	app.frame(0.016)
	assert_eq(app.session.phase, SessionPhase.SETUP)
	assert_false(app.session.actions().has(SessionAction.RESET_ALL))
	_tap(gi, KEY_BACKSPACE)
	assert_true(gi.is_armed(SessionAction.RESET_ALL), "the input layer arms on any first press")
	app.frame(0.016)
	assert_false(gi.is_armed(SessionAction.RESET_ALL), "the app drops an arm the session does not offer")
	assert_eq(gi.hold_progress(SessionAction.RESET_ALL), 0.0)


func test_a_failed_run_points_the_field_guide_at_what_killed_a_self() -> void:
	var made := _make(GameInput.new(), GameSave.memory_storage())
	var app: GameApp = made[0]
	var u: StoryUi = made[3]
	assert_true(app.play_level("sandbox"))
	var lv := app.session.level
	var grunt := app.codex.entry_for_enemy("grunt")
	if not assert_true(grunt != "" and app.codex.is_unlocked(grunt), "the sandbox's grunt page is open"):
		return
	assert_eq(app.codex_page_for_cause(lv, "struck by grunt g1"), grunt)
	assert_eq(app.codex_page_for_cause(lv, "burned by laser beam"), app.codex.entry_for_entity("laser"))
	assert_eq(app.codex_page_for_cause(lv, "fell asleep"), "")
	var death := SimEvent.make(0, SimEventType.SELF_DEATH, 0.0, 0.0).with_tape(0).with_detail("struck by grunt g1")
	var events: Array[SimEvent] = [death]
	var toasts := u.toasts.size()
	app.note_failure(lv, events)
	assert_eq(app.codex_hint, grunt)
	assert_eq(u.codex_hints, [grunt], "the UI is told which page to open")
	assert_eq(u.toasts.size(), toasts + 1)
	assert_true(u.toasts[toasts].begins_with("Field Guide:"))
	# The same cause again does not nag.
	app.note_failure(lv, events)
	assert_eq(u.toasts.size(), toasts + 1)
	assert_eq(u.codex_hints, [grunt])
	# Leaving the level forgets it.
	u.emit_intent(UiIntent.simple(UiIntentType.OPEN_CAMPAIGN))
	assert_eq(app.codex_hint, "")
	assert_eq(u.codex_hints, [grunt, ""])
