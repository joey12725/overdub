class_name GameApp
extends Node
## The application (port of prototype/src/game/shell.ts and app.ts): owns the screens (title →
## campaign → loadout ↔ play → results → next level → … → ending, plus settings and pause), the save,
## the campaign and the current GameSession, and runs the main loop:
##
##  - recording: session.tick_local runs at exactly LOCAL_HZ from a wall-time accumulator, with a
##    bounded catch-up so a hitch never turns into a burst of hidden ticks (local == wall; TIME-02);
##  - count-in / resolving / review / cinematic: session.advance(dt) moves their wall-driven clocks;
##  - every rendered frame: interpolated world render, HUD, audio transport / layers / events.
##
## It talks to the world, audio and UI only through the game/contracts facades (plus the optional
## hooks the real modules add, called by name so stand-ins keep working), so the whole flow can be
## driven headlessly in tests with stand-ins (setup(deps) + frame(dt)). In the real game,
## game/main.gd calls wire_defaults(), which instances the fixed facade scenes defensively (a missing
## module is logged and replaced by its do-nothing base, so the game runs with whichever exist).
##
## What it wires beyond the session (docs/DIALOGUE.md, docs/CINEMATIC.md, replay/README.md,
## ui/README.md, docs/CODEX.md):
##  - story: chapter card (first level of each theme, once per save) → the level intro → briefing;
##    a win's outro → (after the last level) the ending → results; the stinger after the credits.
##    Session input is held while any of them is up (story_blocking()).
##  - dialogue layer every frame (barks, coach marks, failure hints), its seen flags in the save.
##  - HUD world widgets (camera, level, boss memory, aim, per-frame snapshot).
##  - the cinematic director's plan on a win; the winning attempt kept by ReplayStore (first clear,
##    or a clear with fewer tapes), and "watch again" from the campaign screen.
##  - the Field Guide (Codex) unlocks, persisted; settings applied live to every module.

## Seconds per local tick.
const TICK: float = 1.0 / OD.LOCAL_HZ
## Most local ticks run in one rendered frame; anything beyond is dropped, not hurried.
const MAX_CATCHUP_TICKS: int = 8
## Longest wall step any clock accepts from one frame (window drags, debugger pauses).
const MAX_FRAME_DT: float = 0.25
## Adaptive quality: average frame time (s) over a window above which 'high' drops to 'low'.
const SLOW_FRAME_SECONDS: float = 1.0 / 36.0
const QUALITY_WINDOW_FRAMES: int = 240
## Toast the resolving beat. Off: the HUD banner reads GameSessionView.resolving / status_text /
## resolve_progress and shows "REWINDING TAPE…" itself.
const TOAST_RESOLVING: bool = false
## Story steps the app is waiting on (session input is held while one is up).
const STORY_NONE: StringName = &""
const STORY_CARD: StringName = &"card"
const STORY_INTRO: StringName = &"intro"
const STORY_OUTRO: StringName = &"outro"
const STORY_ENDING: StringName = &"ending"
const STORY_STINGER: StringName = &"stinger"
## A queued "first" (e.g. once.firstLoot) playing over the world before the results screen.
const STORY_FIRST: StringName = &"first"
## A replay request from the campaign screen (MenuCampaignLogic.INTENT_WATCH_REPLAY).
const INTENT_WATCH_REPLAY: StringName = &"watchReplay"
## Aim change (radians) that counts as one "aim" use for the coach marks.
const AIM_NOTE_RADIANS: float = 0.35
## Neutral time before a stick move counts as a new "move" use (docs/DIALOGUE.md notify_input).
const MOVE_NEUTRAL_SECONDS: float = 0.25
const MOVE_DEADZONE: float = 0.22
## The dialogue seen flag that marks a chapter card as shown (DlgSeenStore prefix "chapter.").
const CHAPTER_FLAG: String = "chapter.%s"

## Tools (tools/smoke.gd) set this before the main scene wires itself: the save and the kept
## replays then live in this directory instead of user://, so a run never touches the player's save.
static var storage_dir_override: String = ""

## What setup() wires together. Missing pieces get do-nothing / default stand-ins.
class Deps:
	extends RefCounted
	var world: WorldViewBase = null
	var audio: AudioBase = null
	var ui: UiBase = null
	var input: GameInput = null
	## null = no persistence (in-memory only).
	var storage: GameSave.Storage = null
	## Campaign levels; empty = CampaignData.levels().
	var levels: Array[LevelDef] = []
	## Resolve takes on a worker thread (the game). Tests run synchronously.
	var async_resolve: bool = false
	## Where kept replays go (ReplayStore root). "" = no replays are kept.
	var replay_root: String = ""


var world: WorldViewBase = null
var audio: AudioBase = null
var ui: UiBase = null
var input: GameInput = null
var campaign: GameCampaign = null
## Facade files that were missing at wiring time (diagnostics; smoke tool prints them).
var missing_modules: Array[String] = []
## The story / onboarding layer (UiRoot.dialogue, a DialogueLayer), or null when the UI has none.
var dialogue: Node = null
## The Field Guide (data/codex/codex.gd), persisted in SaveData.codex.
var codex: Codex = null
## Kept winning performances (replay/); null = none are kept.
var replays: ReplayStore = null
## Tools: func(tick: int, ctx: GameBot.BotContext) -> PlayerInput replaces the player's input while
## recording (tools/smoke.gd plays a level's stored solution through the real loop with it). A
## non-PlayerInput result falls back to the real input for that tick.
var input_script: Callable = Callable()

var _storage: GameSave.Storage = null
var _async: bool = false
var _screen: StringName = UiScreen.TITLE
var _session: GameSession = null
var _level: LevelDef = null
var _loadout: ResolvedLoadout = null
## Level currently built in the world, and its beat-zero picture for menus.
var _shown_id: String = ""
var _shown_idle: FrameSnapshot = null
var _shown_loadout_key: String = ""
var _record_acc: float = 0.0
var _pending_events: Array[SimEvent] = []
var _tracks_key: String = ""
var _last_device: StringName = &""
var _last_frame: GameSession.SessionFrame = null
var _quality: StringName = WorldViewBase.QUALITY_HIGH
var _quality_auto: bool = true
var _perf_sum: float = 0.0
var _perf_n: int = 0
var _last_hold: float = -1.0
var _last_inset: float = -1.0
var _silent_pulse: MusicPulse = MusicPulse.new()
var _ui_layer: CanvasLayer = null
var _ready_done: bool = false
var _disposed: bool = false

var _story: StringName = STORY_NONE
## Results waiting for the outro / ending to finish.
var _pending_results: ResultsModel = null
var _pending_loot: bool = false
## The ending's stinger plays when the player leaves the credits.
var _stinger_pending: bool = false
var _stinger_target: StringName = UiScreen.CAMPAIGN
var _card: Node = null
## selfDeath events of this attempt's earlier runs (CinemaTypes.Context.prior_events).
var _prior_events: Array[SimEvent] = []
var _take_tick: int = 0
var _boss_builds: int = -1
var _aim: float = NAN
var _move_neutral_t: float = 1.0
var _moving: bool = false
var _aim_noted: float = NAN
## Replay being watched from the campaign screen.
var _replay: ReplayPlayback = null
var _replay_events: Array[SimEvent] = []
## Last campaign replay table pushed to the UI (level id -> {ok, note}).
var _replay_table: Dictionary = {}
## Field Guide page for what killed a self in the last failed run ("" = none): the pause menu's
## Field Guide opens on it (docs/CODEX.md "Where it appears").
var _codex_hint: String = ""

var screen: StringName:
	get:
		return _screen

var session: GameSession:
	get:
		return _session

var save: SaveData:
	get:
		return campaign.save

var render_quality: StringName:
	get:
		return _quality

## Last frame handed to the world (smoke tests).
var last_rendered_frame: GameSession.SessionFrame:
	get:
		return _last_frame

## The story step being waited on (STORY_*), STORY_NONE when none.
var story_step: StringName:
	get:
		return _story

## Field Guide page offered after the last failed run ("" when none).
var codex_hint: String:
	get:
		return _codex_hint

## The replay being watched (null when none).
var replay_playback: ReplayPlayback:
	get:
		return _replay

## Level id -> {ok, note} last pushed to the campaign screen.
var replay_table: Dictionary:
	get:
		return _replay_table

# ───────────────────────────── wiring ─────────────────────────────


## Instance the real modules from their fixed facade paths (game/contracts/facades.gd), the real
## input and the user:// save, then set up. Each missing module is logged and replaced by its
## do-nothing base so the game stays runnable while other engineers are still working.
func wire_defaults() -> void:
	var d := Deps.new()
	for pair: Array in [["world", Facades.WORLD_VIEW_SCENE], ["audio", Facades.AUDIO_SCENE], ["ui", Facades.UI_ROOT_SCENE], ["hud", Facades.HUD_SCENE], ["actors", Facades.ACTOR_LAYER_SCRIPT], ["fx", Facades.FX_LAYER_SCRIPT]]:
		if not Facades.is_provided(pair[1]):
			missing_modules.append(pair[1])
			print("[app] %s module missing (%s): running without it" % [pair[0], pair[1]])
	d.world = Facades.instance_world_view()
	d.audio = Facades.instance_audio()
	d.ui = Facades.instance_ui()
	d.input = GameInput.new()
	var dir := storage_dir_override
	d.storage = GameSave.FileStorage.new(dir) if dir != "" else GameSave.default_storage()
	d.replay_root = dir.path_join("replays") if dir != "" else ReplayStore.DEFAULT_ROOT
	d.async_resolve = true
	setup(d)


## Wire the app from explicit pieces (tests pass stand-ins). Adds the world, audio and UI (on a
## CanvasLayer above the world) as children, loads the save and shows the title screen.
func setup(d: Deps) -> void:
	world = d.world if d.world != null else WorldViewBase.new()
	audio = d.audio if d.audio != null else AudioBase.new()
	ui = d.ui if d.ui != null else UiBase.new()
	input = d.input if d.input != null else GameInput.new()
	_storage = d.storage
	_async = d.async_resolve
	world.name = "World"
	add_child(world)
	audio.name = "Audio"
	add_child(audio)
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UiLayer"
	_ui_layer.layer = 10
	add_child(_ui_layer)
	ui.name = "Ui"
	_ui_layer.add_child(ui)
	input.screen_to_world = func(p: Vector2) -> Vector2: return world.screen_to_world(p)
	if _async:
		ODCore.ensure_registered()
	var levels := d.levels if not d.levels.is_empty() else CampaignData.levels()
	campaign = GameCampaign.new(levels, GameSave.load_save(_storage))
	_loadout = campaign.resolved_loadout()
	replays = ReplayStore.new(d.replay_root) if d.replay_root != "" else null
	ui.intent.connect(on_intent)
	audio.unlock()
	_wire_story()
	_wire_codex()
	# The world starts on 'high'; the saved Quality setting (applied next) may pin it lower.
	_apply_quality(WorldViewBase.QUALITY_HIGH)
	_apply_settings(campaign.save.settings)
	ui.set_campaign(campaign.campaign_model())
	ui.set_loadout(campaign.loadout_model())
	_show_menu(UiScreen.TITLE)
	if not Input.joy_connection_changed.is_connected(_on_joy_connection):
		Input.joy_connection_changed.connect(_on_joy_connection)
	_ready_done = true


## The UI's dialogue layer (UiRoot mounts it above the HUD): seen flags from the save, options,
## voice through the audio facade, and the app's story steps on `dialogue_finished`.
func _wire_story() -> void:
	var dl: Variant = ui.get("dialogue")
	dialogue = dl if dl is Node and (dl as Node).has_method("play_intro") else null
	if dialogue == null:
		return
	dialogue.call("set_seen_flags", campaign.save.seen)
	dialogue.call("set_levels_cleared", campaign.save.cleared.size())
	if not dialogue.is_connected("seen_changed", _on_seen_changed):
		dialogue.connect("seen_changed", _on_seen_changed)
	if not dialogue.is_connected("dialogue_finished", _on_dialogue_finished):
		dialogue.connect("dialogue_finished", _on_dialogue_finished)
	if dialogue.has_signal("bark_shown") and not dialogue.is_connected("bark_shown", _on_bark_shown):
		dialogue.connect("bark_shown", _on_bark_shown)
	audio.connect_dialogue(dialogue)


## The Field Guide: saved pages, baseline gear pages (silently), then live unlocks with a toast.
func _wire_codex() -> void:
	codex = Codex.new()
	codex.load_unlocked(campaign.save.codex)
	codex.note_gear(campaign.save.inventory)
	campaign.set_codex(codex.unlocked_ids())
	codex.unlocked.connect(_on_codex_unlocked)
	if ui.has_method("set_codex") and codex.is_loaded():
		ui.call("set_codex", codex)


## Re-read the story flags and Field Guide pages from the save (after erasing it).
func _reload_progress() -> void:
	if dialogue != null:
		dialogue.call("set_seen_flags", campaign.save.seen)
		dialogue.call("set_levels_cleared", campaign.save.cleared.size())
	if codex != null:
		# Baseline pages come back silently, as on boot.
		codex.unlocked.disconnect(_on_codex_unlocked)
		codex.load_unlocked(campaign.save.codex)
		codex.note_gear(campaign.save.inventory)
		codex.unlocked.connect(_on_codex_unlocked)
		campaign.set_codex(codex.unlocked_ids())
		if ui.has_method("set_codex") and codex.is_loaded():
			ui.call("set_codex", codex)


func _on_seen_changed() -> void:
	if dialogue == null:
		return
	var flags: Array[String] = []
	flags.assign(dialogue.call("get_seen_flags"))
	if campaign.set_seen(flags):
		_persist()


func _on_codex_unlocked(entry_id: String) -> void:
	var e := codex.entry(entry_id)
	var title := str(e.get("title", entry_id)) if not e.is_empty() else entry_id
	ui.toast("Field Guide: new page - %s" % title, UiBase.TONE_GOOD)
	if campaign.set_codex(codex.unlocked_ids()):
		_persist()


func _on_bark_shown(key: String, _line: Variant) -> void:
	if codex != null:
		codex.note_story_trigger(key)


func _process(delta: float) -> void:
	if _ready_done and not _disposed:
		frame(delta)


## Releases are read before the GUI: a menu control that takes focus while a key is still down
## swallows its release, and the input layer would then keep the key "down" and ignore its next
## press. (The dialogue box lets releases through for the same reason.)
func _input(event: InputEvent) -> void:
	if input == null or event.is_pressed():
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		input.handle_event(event)


func _unhandled_input(event: InputEvent) -> void:
	if input != null and input.handle_event(event):
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			on_focus_lost()
		NOTIFICATION_WM_CLOSE_REQUEST:
			if _save_dirty and campaign != null:
				_persist()
			dispose()


func _on_joy_connection(_device: int, _connected: bool) -> void:
	if input != null:
		input.release_all()


## The window lost focus: release every input, and a live take is abandoned (it must not continue or
## stall half-recorded while nobody plays it).
func on_focus_lost() -> void:
	if input != null:
		input.release_all()
	if _session != null and (_session.phase == SessionPhase.RECORDING or _session.phase == SessionPhase.COUNTIN):
		_pause()

# ───────────────────────────── the loop ─────────────────────────────


## One rendered frame, `dt` wall seconds after the previous one. Public so tests and tools can drive
## the loop.
func frame(dt_in: float) -> void:
	var dt := clampf(dt_in, 0.0, MAX_FRAME_DT) if not is_nan(dt_in) else 0.0
	_track_performance(dt)
	_sync_device()
	# Press-twice mode: a first press only arms "reset all" where the session offers it. Otherwise
	# two taps of Backspace to end a playback would wipe every cassette on the decision screen.
	var can_arm := input.press_twice and _reset_on_offer()
	for a: StringName in input.drain_actions():
		_on_input_action(a)
	if input.press_twice and not can_arm:
		input.disarm()
	if _replay != null:
		_advance_replay(dt)
		_push_hold_progress()
		_present_replay(dt)
		return
	var s := _session
	var alpha := 1.0
	if s != null and _screen == UiScreen.PLAY:
		if s.phase == SessionPhase.RECORDING:
			alpha = _run_local_ticks(s, dt)
		else:
			# A count-in that just finished starts recording on the next frame from a clean
			# accumulator.
			s.advance(dt)
		_consume_cues(s)
		_pending_events.append_array(s.drain_events())
	elif s != null:
		# Paused / results: background resolves still complete.
		s.poll_jobs()
		_consume_cues(s)
	_push_hold_progress()
	_push_bottom_inset()
	_present(dt, alpha)


## True when a key / pad "reset all" would be accepted right now.
func _reset_on_offer() -> bool:
	if _replay != null or _session == null or _screen != UiScreen.PLAY or story_blocking():
		return false
	return _session.actions().has(SessionAction.RESET_ALL)


## Simulate `seconds` of wall time in fixed frames (tests / tools).
func run_for(seconds: float, fps: float = 60.0) -> void:
	var n := roundi(seconds * fps)
	for i in n:
		frame(1.0 / fps)


func _run_local_ticks(s: GameSession, dt: float) -> float:
	_record_acc += dt
	var n := 0
	while _record_acc >= TICK and n < MAX_CATCHUP_TICKS and s.phase == SessionPhase.RECORDING:
		var snap := s.current_frame().snap
		var live: ActorSnap = null
		for a: ActorSnap in snap.actors:
			if a.live:
				live = a
				break
		var pos: Variant = null
		if live != null:
			pos = Vector2(live.x, live.y)
		var sample := input.sample(world.screen_up_in_world(), pos)
		if input_script.is_valid():
			var ctx := GameBot.BotContext.new()
			ctx.tick = _take_tick
			ctx.index = s.active_index
			ctx.snap = snap
			ctx.self_actor = live
			var scripted: Variant = input_script.call(_take_tick, ctx)
			if scripted is PlayerInput:
				sample = scripted
		_note_inputs(sample)
		s.tick_local(sample)
		_take_tick += 1
		_record_acc -= TICK
		n += 1
	if s.phase != SessionPhase.RECORDING:
		_record_acc = 0.0
		return 1.0
	# A long hitch: drop the backlog rather than replaying it in a burst the player never saw.
	if _record_acc >= TICK:
		_record_acc = fmod(_record_acc, TICK)
	return _record_acc / TICK


## Gameplay input uses for the coach marks (docs/DIALOGUE.md notify_input): each button press, a move
## once per departure from neutral after MOVE_NEUTRAL_SECONDS, an aim once per AIM_NOTE_RADIANS.
func _note_inputs(p: PlayerInput) -> void:
	_aim = p.aim
	if dialogue == null:
		return
	var moving := Vector2(p.move_x, p.move_y).length() > MOVE_DEADZONE
	if moving:
		if not _moving and _move_neutral_t >= MOVE_NEUTRAL_SECONDS:
			dialogue.call("notify_input", &"move")
		_move_neutral_t = 0.0
	else:
		_move_neutral_t += TICK
	_moving = moving
	if is_nan(_aim_noted):
		_aim_noted = p.aim
	elif absf(angle_difference(_aim_noted, p.aim)) >= AIM_NOTE_RADIANS:
		_aim_noted = p.aim
		dialogue.call("notify_input", &"aim")
	for pair: Array in [[p.light, &"light"], [p.heavy, &"heavy"], [p.dodge, &"dodge"], [p.ranged, &"ranged"], [p.interact, &"interact"], [p.ability, &"ability"]]:
		if pair[0]:
			dialogue.call("notify_input", pair[1])


func _present(dt: float, alpha: float) -> void:
	var s := _session
	var events := _pending_events
	_pending_events = []
	if s != null and (_screen == UiScreen.PLAY or _screen == UiScreen.PAUSE or _screen == UiScreen.RESULTS):
		var playing := _screen == UiScreen.PLAY
		var delay := campaign.save.settings.av_offset_ms / 1000.0 if playing else 0.0
		var f := s.current_frame(alpha, delay)
		_last_frame = f
		var v := s.view()
		var rate := v.world_rate if playing else 0.0
		var master_playing := playing and s.is_playing()
		audio.set_transport(v.beat, rate if master_playing else 0.0, master_playing)
		_push_tracks(s.track_audio_states())
		if not events.is_empty():
			audio.on_events(events)
			_deck_feedback(s, events)
		var pulse := audio.pulse()
		ui.update_hud(v, pulse)
		_feed_level_ui(s, v, f.snap, events, dt)
		var rf := RenderFrame.new()
		rf.snap = f.snap
		rf.prev = f.prev
		rf.alpha = f.alpha
		rf.dt = dt
		rf.mode = _view_mode(s.phase)
		rf.events = events
		rf.world_rate = rate
		rf.music = pulse
		rf.active = v.active if s.phase == SessionPhase.COUNTIN or s.phase == SessionPhase.RECORDING else -1
		world.render(rf)
		return
	# Menus: the current level sits behind them, calm and still.
	if _shown_idle != null:
		var mf := RenderFrame.new()
		mf.snap = _shown_idle
		mf.prev = _shown_idle
		mf.alpha = 1.0
		mf.dt = dt
		mf.mode = ViewMode.IDLE
		mf.world_rate = 0.0
		mf.music = audio.pulse()
		mf.active = -1
		world.render(mf)


## Everything level-bound beside the HUD: the dialogue layer (barks, coach marks, hints, queued
## firsts), the world widgets, the Field Guide's event unlocks and the boss memory.
func _feed_level_ui(s: GameSession, v: SessionView, snap: FrameSnapshot, events: Array[SimEvent], dt: float) -> void:
	if dialogue != null:
		dialogue.call("update", v, events, dt, snap)
	if ui.has_method("update_world"):
		ui.call("update_world", snap, v, events)
		if s.phase == SessionPhase.RECORDING:
			ui.call("set_aim", _aim)
		elif not is_nan(_aim):
			_aim = NAN
			ui.call("set_aim", NAN)
	if s.boss_memory_builds != _boss_builds:
		_boss_builds = s.boss_memory_builds
		if ui.has_method("set_boss_memory"):
			ui.call("set_boss_memory", s.boss_memory)
	if codex != null:
		for e: SimEvent in events:
			codex.note_sim_event(String(e.type))
	if s.phase == SessionPhase.RECORDING:
		_note_prior_deaths(events)


func _view_mode(phase: StringName) -> StringName:
	match phase:
		SessionPhase.SETUP, SessionPhase.COUNTIN, SessionPhase.RECORDING:
			return ViewMode.RECORD
		SessionPhase.REVIEW, SessionPhase.DECISION:
			return ViewMode.REVIEW
		SessionPhase.CINEMATIC, SessionPhase.RESULTS:
			return ViewMode.CINEMATIC
	return ViewMode.IDLE


func _push_tracks(tracks: Array[TrackAudioState]) -> void:
	var parts: PackedStringArray = []
	for t: TrackAudioState in tracks:
		parts.append("%d%s%d%d%d" % [int(t.present), t.speed, t.life, int(t.synced), t.transport])
	var key := "|".join(parts)
	if key == _tracks_key:
		return
	_tracks_key = key
	audio.set_tracks(tracks)
	if world.has_method("set_music_tracks"):
		world.call("set_music_tracks", tracks)


func _silent_tracks() -> Array[TrackAudioState]:
	var out: Array[TrackAudioState] = []
	for i in OD.TAPE_COUNT:
		out.append(TrackAudioState.make(false, 1.0, OD.LifeState.ALIVE, true, 0))
	return out


func _deck_feedback(s: GameSession, events: Array[SimEvent]) -> void:
	for e: SimEvent in events:
		if e.tape < 0:
			continue
		match e.type:
			SimEventType.SWING:
				ui.deck_event(e.tape, ActionKind.HEAVY if e.detail == "heavy" else ActionKind.LIGHT)
			SimEventType.DODGE:
				ui.deck_event(e.tape, ActionKind.DODGE)
			SimEventType.FIRE:
				ui.deck_event(e.tape, ActionKind.RANGED)
			SimEventType.INTERACT, SimEventType.INTERACT_FAIL:
				ui.deck_event(e.tape, ActionKind.INTERACT)
			SimEventType.SELF_DEATH:
				ui.deck_event(e.tape, StateMarkKind.DEATH)
				if s != null and s.phase == SessionPhase.RECORDING and e.tape == s.active_index:
					# GHOST-01: death never ends the take.
					ui.toast("Tape %s died. Keep recording: you are a ghost for this take." % OD.TAPE_NAMES[e.tape], UiBase.TONE_WARN)
			SimEventType.DESYNC:
				ui.deck_event(e.tape, StateMarkKind.DESYNC)
			SimEventType.RESYNC:
				ui.deck_event(e.tape, StateMarkKind.RESYNC)


func _consume_cues(s: GameSession) -> void:
	for c: GameSession.Cue in s.drain_cues():
		_on_cue(s, c)


func _on_cue(s: GameSession, c: GameSession.Cue) -> void:
	match c.kind:
		GameSession.CUE_COUNT:
			audio.count_in(c.n)
		GameSession.CUE_UI:
			audio.ui(c.sound)
		GameSession.CUE_TAKE_ABORTED:
			# Moxie's count words are queued on the beat grid: an abandoned count-in drops them.
			audio.cancel_count_in()
			ui.toast("Take abandoned. Takes always restart from beat zero.", UiBase.TONE_INFO)
		GameSession.CUE_RESOLVING:
			# The take is over; master time stands still while the combined run is resolved.
			audio.set_mode(AudioBase.MODE_REVIEW)
			if TOAST_RESOLVING:
				ui.toast(GameSessionView.RESOLVING_TEXT, UiBase.TONE_INFO)
		GameSession.CUE_RESOLVE_FAILED:
			ui.toast("This take could not be played back (%s). Record it again." % c.message, UiBase.TONE_WARN)
		GameSession.CUE_RESOLVED:
			if c.outcome != null:
				if dialogue != null:
					dialogue.call("on_review_result", c.outcome)
				if not c.outcome.win and s.resolution != null:
					_note_prior_deaths(s.resolution.events)
					note_failure(s.level, s.resolution.events)
				elif c.outcome.win:
					_set_codex_hint("")
		GameSession.CUE_PHASE:
			if c.phase == SessionPhase.RECORDING:
				# The press that started the count-in must not become the first recorded action.
				input.clear_presses()
				_record_acc = 0.0
				_take_tick = 0
			if c.phase == SessionPhase.CINEMATIC:
				# CINE-02: only a fresh hold can skip; a button already held from the take cannot.
				input.cancel_holds()
				_on_win_cinematic(s)
			_set_actor_flavour(&"countin" if c.phase == SessionPhase.COUNTIN else &"")
			var mode := AudioBase.MODE_RECORD
			if c.phase == SessionPhase.REVIEW or c.phase == SessionPhase.DECISION:
				mode = AudioBase.MODE_REVIEW
			elif c.phase == SessionPhase.CINEMATIC or c.phase == SessionPhase.RESULTS:
				mode = AudioBase.MODE_CINEMATIC
			audio.set_mode(mode)
			if c.phase == SessionPhase.RESULTS:
				_on_level_won(s)


## The selfDeath events of a run that was not the win (the cinematic shows who was rescued).
func _note_prior_deaths(events: Array[SimEvent]) -> void:
	for e: SimEvent in events:
		if e.type == SimEventType.SELF_DEATH:
			_prior_events.append(e)


## A failed run: point the Field Guide at the page for whatever killed the last self to die, and say
## so once per page (the pause menu's Field Guide then opens there).
func note_failure(lv: LevelDef, events: Array[SimEvent]) -> void:
	if codex == null:
		return
	var page := ""
	for e: SimEvent in events:
		if e.type == SimEventType.SELF_DEATH:
			var p := codex_page_for_cause(lv, e.detail)
			if p != "":
				page = p
	if page == "" or not codex.is_unlocked(page):
		return
	var is_new := page != _codex_hint
	_set_codex_hint(page)
	if is_new:
		var entry := codex.entry(page)
		ui.toast("Field Guide: \"%s\" explains what stopped that run. Pause to read it." % str(entry.get("title", page)), UiBase.TONE_INFO)


## The Field Guide page for a death cause as the sim words it ("struck by brute b2", "skewered by
## spikes s1", "burned by laser beam"): the level entity the cause names, else a hazard word. ""
## when the guide has no page for it.
func codex_page_for_cause(lv: LevelDef, cause: String) -> String:
	if codex == null or cause == "":
		return ""
	var words := cause.split(" ", false)
	if lv != null:
		for e: EntityDef in lv.entities:
			if e.id == "" or not words.has(e.id):
				continue
			var page := codex.entry_for_enemy(String((e as EnemyDef).type)) if e is EnemyDef else codex.entry_for_entity(String(e.kind))
			if page != "":
				return page
	for w: String in words:
		var page := codex.entry_for_enemy(w)
		if page == "":
			page = codex.entry_for_entity(w)
		if page != "":
			return page
	return ""


func _set_codex_hint(page: String) -> void:
	if page == _codex_hint:
		return
	_codex_hint = page
	if ui.has_method("set_codex_hint"):
		ui.call("set_codex_hint", page)


## The winning take was resolved: keep it as a replay (first clear or fewer tapes) and hand the
## cinematic director's shot list to the world camera.
func _on_win_cinematic(s: GameSession) -> void:
	if s.resolution == null or s.outcome == null or not s.outcome.win:
		return
	keep_replay(s)
	if world.has_method("set_cinema_plan"):
		var ctx := CinemaTypes.Context.new()
		ctx.prior_events = _prior_events.duplicate()
		world.call("set_cinema_plan", CinemaPlanner.plan(s.resolution, s.level, ctx))


## Store the session's winning attempt with ReplayStore when it is the first kept win of the level,
## the kept one no longer plays, or this one uses fewer tapes. Returns true when it was stored.
func keep_replay(s: GameSession) -> bool:
	if replays == null or s == null or s.resolution == null or s.pending_tape == null:
		return false
	var tapes: Array = s.committed_tapes.duplicate()
	tapes.append(s.pending_tape)
	var kept := replays.quick_check(s.level)
	if kept.ok() and kept.record != null and kept.record.tapes.size() <= tapes.size():
		return false
	var errors: Array[String] = []
	var r := replays.record_win(s.level, s.loadout, tapes, s.boss_memory, s.resolution, int(Time.get_unix_time_from_system()), errors)
	if r == null:
		push_warning("GameApp: the winning run was not kept as a replay: %s" % ", ".join(errors))
		return false
	return true


func _on_level_won(s: GameSession) -> void:
	var lv := s.level
	var clear := campaign.record_clear(lv.id)
	# The attempt is over: gear may change from the results screen (GEAR-03).
	campaign.end_level()
	_persist()
	var next := campaign.next_level(lv.id)
	var m := ResultsModel.new()
	m.level = lv
	m.outcome = s.outcome
	m.tapes_used = s.tapes_used
	m.loot = clear.loot
	m.has_next = next != null
	m.next_id = next.id if next != null else ""
	if codex != null and not clear.loot.is_empty():
		codex.note_gear(campaign.save.inventory)
	if dialogue != null:
		dialogue.call("set_levels_cleared", campaign.save.cleared.size())
	_pending_results = m
	_pending_loot = not clear.loot.is_empty()
	# The level's outro plays over the world first (first clear only), then the results.
	if dialogue != null and bool(dialogue.call("play_outro", lv.id)):
		_story = STORY_OUTRO
		return
	_after_outro()


## The outro is over (or there was none). After the final level the ending plays first; then the
## results screen (with the loot moment on a first clear).
func _after_outro() -> void:
	_story = STORY_NONE
	var m := _pending_results
	if m == null:
		return
	if not m.has_next and dialogue != null and campaign.all_cleared():
		if bool(dialogue.call("play_ending", UiArt.ending_card())):
			_story = STORY_ENDING
			_stinger_pending = true
			if ui.hud != null:
				ui.hud.visible = false
			return
	_show_results()


func _show_results() -> void:
	_story = STORY_NONE
	var m := _pending_results
	if m == null:
		return
	if dialogue != null and _session != null:
		# The loot reaction (once.firstLoot, or the loot bark) comes first, over the world: the
		# results screen sits above the dialogue layer and would hide a box.
		dialogue.call("on_results", _pending_loot)
		var none: Array[SimEvent] = []
		dialogue.call("update", _session.view(), none, 0.0, null)
		if bool(dialogue.call("is_blocking")):
			_story = STORY_FIRST
			return
	_open_results()


func _open_results() -> void:
	_story = STORY_NONE
	var m := _pending_results
	_pending_results = null
	if m == null:
		return
	ui.set_results(m)
	ui.set_campaign(campaign.campaign_model())
	ui.set_loadout(campaign.loadout_model())
	for it: GearItem in m.loot:
		ui.toast("New gear: %s" % it.name, UiBase.TONE_GOOD)
	if not m.loot.is_empty():
		audio.ui(AudioBase.UI_LOOT)
	_set_screen(UiScreen.RESULTS)

# ───────────────────────────── story ─────────────────────────────


## True while a chapter card or a story sequence is up: session input (keys, pad, HUD clicks) is
## held, and the briefing does not advance (docs/DIALOGUE.md "is_blocking").
func story_blocking() -> bool:
	if _story != STORY_NONE:
		return true
	if _card != null and is_instance_valid(_card):
		return true
	return dialogue != null and bool(dialogue.call("is_blocking"))


## Level start: the chapter card (first level of a theme, once per save), then the intro (first
## visit), then the briefing.
func _begin_story(lv: LevelDef) -> void:
	_story = STORY_NONE
	if dialogue == null:
		return
	dialogue.call("begin_level", lv.id, lv)
	# The layer gates boxes by phase: give it this session's phase before anything is queued.
	var none: Array[SimEvent] = []
	dialogue.call("update", _session.view(), none, 0.0, null)
	if is_chapter_start(lv) and ui.has_method("show_chapter_card") and not _seen(CHAPTER_FLAG % lv.id):
		_mark_seen(CHAPTER_FLAG % lv.id)
		var card: Variant = ui.call("show_chapter_card", lv.theme, chapter_subtitle(lv))
		if card is Node and (card as Node).has_signal("finished"):
			_card = card
			_story = STORY_CARD
			(card as Node).connect("finished", _on_card_finished, CONNECT_ONE_SHOT)
			return
	_play_intro(lv)


func _on_card_finished() -> void:
	_card = null
	if _story != STORY_CARD:
		return
	_story = STORY_NONE
	if _level != null:
		_play_intro(_level)


func _play_intro(lv: LevelDef) -> void:
	if dialogue != null and bool(dialogue.call("play_intro", lv.id)):
		_story = STORY_INTRO


func _on_dialogue_finished(kind: StringName, _key: String, _skipped: bool) -> void:
	match _story:
		STORY_INTRO:
			if kind == DialoguePlayer.KIND_INTRO:
				_story = STORY_NONE
				# The press that ended the dialogue must not also start the take.
				input.clear_presses()
		STORY_OUTRO:
			if kind == DialoguePlayer.KIND_OUTRO:
				_after_outro()
		STORY_ENDING:
			if kind == DialoguePlayer.KIND_ENDING:
				_show_results()
		STORY_FIRST:
			if not bool(dialogue.call("is_blocking")):
				_open_results()
		STORY_STINGER:
			if kind == DialoguePlayer.KIND_STINGER:
				_story = STORY_NONE
				_stinger_pending = false
				_show_menu(_stinger_target)


## Leaving the credits: the post-credits stinger over the world, then `target`.
func _play_stinger(target: StringName) -> void:
	_stinger_target = target
	_stinger_pending = false
	_leave_level()
	if dialogue == null or not bool(dialogue.call("play_stinger")):
		_show_menu(target)
		return
	_story = STORY_STINGER
	_set_screen(UiScreen.PLAY)
	if ui.hud != null:
		ui.hud.visible = false


func _close_card() -> void:
	if _card != null and is_instance_valid(_card):
		_card.queue_free()
	_card = null


## The first level of each theme opens a chapter (01, 05, 08, 12 in the shipped campaign).
func is_chapter_start(lv: LevelDef) -> bool:
	var i := campaign.levels.find(lv)
	if i < 0:
		return false
	return i == 0 or campaign.levels[i - 1].theme != lv.theme


## "Depth 05 · Dead Air".
func chapter_subtitle(lv: LevelDef) -> String:
	return "Depth %02d · %s" % [maxi(1, lv.index), lv.name]


func _seen(flag: String) -> bool:
	if dialogue == null:
		return campaign.save.seen.has(flag)
	var st: Variant = dialogue.get("seen")
	return st != null and bool(st.call("has", flag))


func _mark_seen(flag: String) -> void:
	if dialogue == null:
		return
	var st: Variant = dialogue.get("seen")
	if st != null:
		st.call("mark", flag)
		_on_seen_changed()


func _set_actor_flavour(f: StringName) -> void:
	var layer: Variant = world.actor_layer
	if layer != null and (layer as Object).has_method("set_flavour"):
		(layer as Object).call("set_flavour", f)


func _note_level_codex(lv: LevelDef) -> void:
	var enemies: Array = []
	var kinds: Array = []
	for e: EntityDef in lv.entities:
		kinds.append(String(e.kind))
		if e is EnemyDef:
			enemies.append(String((e as EnemyDef).type))
	var modes: Array = []
	for m: int in lv.end_modes:
		modes.append(OD.end_mode_name(m))
	codex.note_level(lv.id, enemies, kinds, modes)

# ───────────────────────────── replays ─────────────────────────────


## Push the "Watch" / "out of date" table for every cleared level to the campaign screen.
func refresh_replays() -> void:
	var table := {}
	if replays != null:
		for lv: LevelDef in campaign.levels:
			if not campaign.is_cleared(lv.id) or not replays.has_replay(lv.id):
				continue
			var chk := replays.quick_check(lv)
			if chk.ok():
				table[lv.id] = {"ok": true, "note": ""}
			elif chk.status != ReplayVerifier.STATUS_MISSING:
				table[lv.id] = {"ok": false, "note": "Replay out of date: %s" % chk.message}
	_replay_table = table
	if ui.has_method("set_replays"):
		ui.call("set_replays", table)


## "Watch again": fully verify the kept replay (a stale one is marked, never shown wrong) and play it
## as the locked cinematic. Returns true when playback started.
func watch_replay(level_id: String) -> bool:
	var lv := campaign.level(level_id)
	if lv == null or replays == null or _session != null:
		return false
	var chk := replays.play(lv)
	if not chk.ok() or chk.resolution == null:
		ui.toast("This replay no longer matches the level (%s)." % chk.message, UiBase.TONE_WARN)
		refresh_replays()
		return false
	_replay = ReplayPlayback.new(chk.resolution, lv, chk.record)
	_replay_events = []
	_show_level(lv, null, chk.record.resolved_loadout)
	audio.load_level(lv)
	_use_audio_director()
	audio.set_mode(AudioBase.MODE_CINEMATIC)
	_tracks_key = ""
	if world.has_method("set_cinema_plan"):
		world.call("set_cinema_plan", CinemaPlanner.plan(chk.resolution, lv, null))
	if ui.has_method("load_level_widgets"):
		ui.call("load_level_widgets", lv, chk.record.resolved_loadout, chk.record.boss_memory)
	input.cancel_holds()
	input.clear_presses()
	_set_screen(UiScreen.PLAY)
	return true


func _advance_replay(dt: float) -> void:
	if _screen == UiScreen.PLAY:
		_replay.advance(dt)
	_replay_events.append_array(_replay.drain_events())
	if _replay.done:
		end_replay()


## Stop watching (skip, done or pause) and return to the campaign screen.
func end_replay() -> void:
	if _replay == null:
		return
	_replay = null
	_replay_events = []
	if world.has_method("set_cinema_plan"):
		world.call("set_cinema_plan", null)
	audio.set_transport(0.0, 0.0, false)
	audio.set_tracks(_silent_tracks())
	_tracks_key = ""
	var lv := campaign.level(_shown_id)
	if lv != null:
		_shown_idle = _idle_snapshot(lv)
	_show_menu(UiScreen.CAMPAIGN)


func _present_replay(dt: float) -> void:
	if _replay == null:
		# Finished this frame: the menu branch draws the backdrop.
		_present(dt, 1.0)
		return
	var events := _replay_events
	_replay_events = []
	var f := _replay.current_frame(campaign.save.settings.av_offset_ms / 1000.0)
	var v := _replay.view()
	audio.set_transport(_replay.beat(), 1.0, true)
	var tracks: Array[TrackAudioState] = []
	for i in OD.TAPE_COUNT:
		var tape: ODTape = _replay.record.tapes[i] if _replay.record != null and i < _replay.record.tapes.size() else null
		var actor := f.snap.actor(i)
		tracks.append(TrackAudioState.make(tape != null, tape.speed if tape != null else 1.0,
			actor.life if actor != null else OD.LifeState.ALIVE, actor.synced if actor != null else true,
			actor.phase.dir if actor != null else 0))
	_push_tracks(tracks)
	if not events.is_empty():
		audio.on_events(events)
		_deck_feedback(null, events)
	var pulse := audio.pulse()
	ui.update_hud(v, pulse)
	if ui.has_method("update_world"):
		ui.call("update_world", f.snap, v, events)
	var rf := RenderFrame.new()
	rf.snap = f.snap
	rf.prev = f.prev
	rf.alpha = f.alpha
	rf.dt = dt
	rf.mode = ViewMode.CINEMATIC
	rf.events = events
	rf.world_rate = 1.0
	rf.music = pulse
	rf.active = -1
	world.render(rf)

# ───────────────────────────── intents and input ─────────────────────────────


## Route a UI intent (also used by tests).
func on_intent(i: UiIntent) -> void:
	if i.type == INTENT_WATCH_REPLAY:
		watch_replay(i.id)
		return
	if _stinger_pending and _screen == UiScreen.ENDING and (i.type == UiIntentType.OPEN_CAMPAIGN or i.type == UiIntentType.OPEN_TITLE):
		_play_stinger(UiScreen.TITLE if i.type == UiIntentType.OPEN_TITLE else UiScreen.CAMPAIGN)
		return
	match i.type:
		UiIntentType.SESSION:
			if _replay != null:
				if i.action == SessionAction.SKIP or i.action == SessionAction.QUIT:
					end_replay()
				return
			if story_blocking():
				return
			_on_session_action(i.action)
		UiIntentType.OPEN_CAMPAIGN:
			_leave_level()
			_show_menu(UiScreen.CAMPAIGN)
		UiIntentType.OPEN_LOADOUT:
			# GEAR-03: equipment changes between levels only; a finished level counts as "between".
			if _session != null and _session.phase != SessionPhase.RESULTS:
				ui.toast("Gear is locked until this level ends.", UiBase.TONE_WARN)
				return
			_leave_level()
			ui.set_loadout(campaign.loadout_model(true))
			_show_menu(UiScreen.LOADOUT)
		UiIntentType.OPEN_SETTINGS:
			_show_menu(UiScreen.SETTINGS)
		UiIntentType.OPEN_TITLE:
			_leave_level()
			_show_menu(UiScreen.TITLE)
		UiIntentType.PLAY_LEVEL:
			play_level(i.id)
		UiIntentType.EQUIP:
			if campaign.equip(i.slot, i.id):
				_loadout = campaign.resolved_loadout()
				_persist()
				ui.set_loadout(campaign.loadout_model())
				audio.ui(AudioBase.UI_SELECT)
			else:
				ui.toast("That item cannot be equipped right now.", UiBase.TONE_WARN)
		UiIntentType.SETTING:
			var st := campaign.save.settings.copy()
			if st.set_by_key(i.key, i.value):
				campaign.set_settings(st)
				_apply_settings(campaign.save.settings)
				_persist()
		UiIntentType.RESUME:
			if _screen == UiScreen.PAUSE:
				_set_screen(UiScreen.PLAY)
		UiIntentType.ERASE_SAVE:
			_leave_level()
			GameSave.erase_save(_storage)
			campaign.replace_save(GameSave.fresh_save())
			_loadout = campaign.resolved_loadout()
			if replays != null:
				for id: String in replays.list_level_ids():
					replays.remove(id)
			_reload_progress()
			_persist()
			_apply_settings(campaign.save.settings)
			ui.set_campaign(campaign.campaign_model())
			ui.set_loadout(campaign.loadout_model())
			refresh_replays()


## Start (or restart) a level attempt. Returns false if it is locked or cannot run.
func play_level(id: String) -> bool:
	var lv := campaign.level(id)
	if lv == null or not campaign.is_unlocked(id):
		ui.toast("That level is still locked.", UiBase.TONE_WARN)
		return false
	end_replay_silently()
	_leave_level()
	campaign.begin_level(id)
	_loadout = campaign.resolved_loadout()
	var errors: Array[String] = []
	var s := GameSession.create(lv, _loadout, lv.briefing.is_empty(), _async, errors)
	if s == null:
		campaign.end_level()
		ui.toast("This level cannot start: %s" % ", ".join(errors), UiBase.TONE_WARN)
		return false
	_session = s
	_level = lv
	_show_level(lv, null)
	audio.load_level(lv)
	audio.set_mode(AudioBase.MODE_RECORD)
	_use_audio_director()
	_tracks_key = ""
	_record_acc = 0.0
	_pending_events = []
	_prior_events = []
	_take_tick = 0
	_boss_builds = s.boss_memory_builds
	input.clear_presses()
	if ui.has_method("load_level_widgets"):
		ui.call("load_level_widgets", lv, _loadout, s.boss_memory)
	if codex != null:
		_note_level_codex(lv)
	_set_screen(UiScreen.PLAY)
	_begin_story(lv)
	return true


## Drop a replay being watched without changing screens (a level is about to start).
func end_replay_silently() -> void:
	if _replay == null:
		return
	_replay = null
	_replay_events = []
	if world.has_method("set_cinema_plan"):
		world.call("set_cinema_plan", null)


func _on_input_action(a: StringName) -> void:
	if _replay != null:
		# Watching a replay: a deliberate hold (or pause / back) stops watching.
		if a == GameInput.SKIP_CINEMATIC or a == GameInput.PAUSE or a == GameInput.BACK:
			end_replay()
		return
	if _screen != UiScreen.PLAY:
		if _screen == UiScreen.PAUSE and a == GameInput.PAUSE:
			ui.navigate(UiBase.NAV_BACK)
			return
		match a:
			GameInput.NAV_UP, GameInput.NAV_DOWN, GameInput.NAV_LEFT, GameInput.NAV_RIGHT, GameInput.ACCEPT, GameInput.BACK:
				ui.navigate(a)
			GameInput.PAUSE:
				ui.navigate(UiBase.NAV_BACK)
		return
	if story_blocking():
		# A chapter card or dialogue box is up: it owns accept / back; nothing reaches the session.
		if _card != null and is_instance_valid(_card) and (a == GameInput.ACCEPT or a == GameInput.BACK):
			ui.navigate(UiBase.NAV_ACCEPT)
		return
	var s := _session
	if s == null:
		return
	if s.phase == SessionPhase.CINEMATIC:
		# CINE-02: the winning performance is locked; only a deliberate hold skips to the results.
		if a == GameInput.SKIP_CINEMATIC:
			_on_session_action(SessionAction.SKIP)
		return
	if a == GameInput.PAUSE:
		_pause()
		return
	# While a take is live, only pause leaves it; everything else is gameplay (sampled per tick).
	if s.phase == SessionPhase.RECORDING or s.phase == SessionPhase.COUNTIN:
		return
	match a:
		GameInput.ACCEPT:
			_on_session_action(_accept_action(s))
		GameInput.NAV_LEFT:
			if s.phase == SessionPhase.SETUP:
				_on_session_action(SessionAction.SPEED_DOWN)
		GameInput.NAV_RIGHT:
			if s.phase == SessionPhase.SETUP:
				_on_session_action(SessionAction.SPEED_UP)
		GameInput.NAV_UP, GameInput.NAV_DOWN, GameInput.BACK, GameInput.SKIP_CINEMATIC:
			pass
		_:
			if SessionAction.has(a):
				_on_session_action(a)


## What Enter / Space / A means in each phase.
func _accept_action(s: GameSession) -> StringName:
	match s.phase:
		SessionPhase.BRIEFING:
			return SessionAction.START
		SessionPhase.SETUP:
			return SessionAction.RECORD
		SessionPhase.REVIEW:
			return SessionAction.SKIP
		SessionPhase.DECISION:
			return SessionAction.COMMIT if s.actions().has(SessionAction.COMMIT) else SessionAction.RETRY_TAKE
	return SessionAction.CONTINUE


func _on_session_action(action: StringName) -> void:
	var s := _session
	if action == SessionAction.QUIT:
		_leave_level()
		_show_menu(UiScreen.CAMPAIGN)
		return
	if action == SessionAction.CONTINUE:
		if s != null and s.phase != SessionPhase.RESULTS:
			return
		var lv := _level
		_leave_level()
		if lv != null and campaign.next_level(lv.id) == null and campaign.all_cleared():
			_show_menu(UiScreen.ENDING)
		else:
			_show_menu(UiScreen.CAMPAIGN)
		return
	if s == null:
		return
	if action == SessionAction.RESET_ALL and _screen == UiScreen.PAUSE:
		# Pause menu "restart": the take (if any) was already abandoned when pausing.
		if s.restart_attempt():
			_prior_events = []
			if dialogue != null:
				dialogue.call("notify_action", action)
		_consume_cues(s)
		return
	if _screen != UiScreen.PLAY:
		return
	if s.act(action):
		if action == SessionAction.RESET_ALL:
			_prior_events = []
		if dialogue != null:
			dialogue.call("notify_action", action)
		_consume_cues(s)


func _pause() -> void:
	var s := _session
	if s == null or _screen != UiScreen.PLAY:
		return
	# OPEN-21: no tactical pause mid-take; pausing abandons the take.
	if s.phase == SessionPhase.COUNTIN or s.phase == SessionPhase.RECORDING:
		s.abort_take()
	_consume_cues(s)
	audio.set_transport(s.view().beat, 0.0, false)
	_set_screen(UiScreen.PAUSE)

# ───────────────────────────── screens ─────────────────────────────


func _set_screen(s: StringName) -> void:
	_screen = s
	ui.show_screen(s)
	if s != UiScreen.PLAY and s != UiScreen.PAUSE and s != UiScreen.RESULTS:
		# A calm musical bed behind the menus.
		audio.set_mode(AudioBase.MODE_MENU)


func _show_menu(s: StringName) -> void:
	if s == UiScreen.CAMPAIGN or s == UiScreen.TITLE or s == UiScreen.ENDING:
		ui.set_campaign(campaign.campaign_model())
	if s == UiScreen.CAMPAIGN:
		refresh_replays()
	var idx := campaign.current_index()
	if idx < campaign.levels.size() and _session == null and _replay == null:
		var backdrop := campaign.levels[idx]
		_show_level(backdrop, _idle_snapshot(backdrop))
	_set_screen(s)


## End the current attempt (if any) and silence it. Gear unlocks again.
func _leave_level() -> void:
	_close_card()
	if _session == null:
		return
	_session.dispose()
	_session = null
	_level = null
	campaign.end_level()
	_pending_events = []
	_prior_events = []
	_pending_results = null
	_set_codex_hint("")
	if _story != STORY_STINGER:
		_story = STORY_NONE
	if dialogue != null:
		dialogue.call("end_level")
	if world.has_method("set_cinema_plan"):
		world.call("set_cinema_plan", null)
	_set_actor_flavour(&"")
	_tracks_key = ""
	audio.set_transport(0.0, 0.0, false)
	audio.set_tracks(_silent_tracks())
	audio.set_mode(AudioBase.MODE_MENU)
	# The world still holds the level; its beat-zero picture becomes the menu backdrop.
	if _shown_id != "" and _shown_idle == null:
		var lv := campaign.level(_shown_id)
		if lv != null:
			_shown_idle = _idle_snapshot(lv)


func _show_level(lv: LevelDef, idle: FrameSnapshot, loadout: ResolvedLoadout = null) -> void:
	var lo := loadout if loadout != null else _loadout
	# The look follows the loadout (wardrobe), so a gear change reloads the same level too.
	var lo_key := JSON.stringify(lo.to_dict()) if lo != null else ""
	if _shown_id != lv.id or _shown_loadout_key != lo_key:
		world.load_level(lv, lo)
		_shown_loadout_key = lo_key
		_on_world_loaded()
	_shown_id = lv.id
	_shown_idle = idle


## A level was (re)built in the world: the widgets, coach marks and barks project through its camera.
func _on_world_loaded() -> void:
	if world.ctx != null and world.ctx.camera != null and ui.has_method("set_world_camera"):
		ui.call("set_world_camera", world.ctx.camera)


## The music visualisers follow the audio director's live parts (after both loaded the level).
func _use_audio_director() -> void:
	if not world.has_method("musicviz") or not audio.has_method("director"):
		return
	var hub: Variant = world.call("musicviz")
	var dir: Variant = audio.call("director")
	if hub != null and dir != null:
		(hub as Object).call("use_audio_director", dir)


func _idle_snapshot(lv: LevelDef) -> FrameSnapshot:
	var none: Array[ODTape] = []
	var errors: Array[String] = []
	var sim := ODSim.create_sim(SimConfig.make(lv, _loadout, none), errors)
	return sim.snapshot() if sim != null else null

# ───────────────────────────── settings, save, device ─────────────────────────────


## Render quality. 'auto' (the default): 'high' until frames run slow during play, then 'low' for
## the rest of the session. Calling this (or the Quality setting) pins the choice.
func set_quality(q: StringName) -> void:
	_quality_auto = false
	_apply_quality(q)


func _apply_quality(q: StringName) -> void:
	_quality = q
	world.set_quality(q)


func _track_performance(dt: float) -> void:
	if not _quality_auto or _quality == WorldViewBase.QUALITY_LOW or _screen != UiScreen.PLAY or dt <= 0.0:
		return
	_perf_sum += dt
	_perf_n += 1
	if _perf_n < QUALITY_WINDOW_FRAMES:
		return
	var avg := _perf_sum / _perf_n
	_perf_sum = 0.0
	_perf_n = 0
	if avg > SLOW_FRAME_SECONDS:
		_apply_quality(WorldViewBase.QUALITY_LOW)
		ui.toast("Switched to low graphics quality to keep the beat steady.", UiBase.TONE_INFO)


## Every setting reaches its module at once (and on boot).
func _apply_settings(st: SaveSettings) -> void:
	audio.set_volumes(st.master, st.music, st.sfx)
	world.set_screen_shake(st.screen_shake)
	if world.has_method("set_shake_scale"):
		world.call("set_shake_scale", st.shake_scale if st.screen_shake else 0.0)
	if world.has_method("set_reduce_flashing"):
		world.call("set_reduce_flashing", st.reduce_flashing)
	ActorOptions.apply_settings(st)
	audio.set_voice_options(AudioBase.VOICES_ON if st.voices else AudioBase.VOICES_OFF, st.barks, st.voice_volume)
	var press := st.hold_mode == "press"
	if press != input.press_twice:
		input.press_twice = press
		input.disarm()
		# The reset prompt reads "Hold Backspace" or just "Backspace": push the bindings again.
		_last_device = &""
	match st.quality:
		"high":
			set_quality(WorldViewBase.QUALITY_HIGH)
		"low":
			set_quality(WorldViewBase.QUALITY_LOW)
		_:
			if not _quality_auto:
				# Back from a pinned choice: start again on 'high' and let the frame times decide.
				_quality_auto = true
				_perf_sum = 0.0
				_perf_n = 0
				_apply_quality(WorldViewBase.QUALITY_HIGH)
	ui.set_settings(st)


## Write the save. A failed write (disk full, file locked) is told to the player once and retried on
## every later save and when the game closes, so progress shown on screen is not silently lost.
var _save_dirty: bool = false


func _persist() -> void:
	if GameSave.write_save(campaign.save, _storage):
		_save_dirty = false
		return
	if not _save_dirty and ui != null:
		ui.toast("Could not write the save file. Progress is kept while the game is open and will be saved when the disk allows.", UiBase.TONE_WARN)
	_save_dirty = true



func _sync_device() -> void:
	var d := input.device()
	if d != _last_device:
		_last_device = d
		ui.set_device(d)
		ui.set_bindings(GameInput.prompts(d, input.press_twice))


func _push_hold_progress() -> void:
	var watching := _replay != null or (_session != null and _session.phase == SessionPhase.CINEMATIC)
	var id := GameInput.SKIP_CINEMATIC if watching else SessionAction.RESET_ALL
	var p := input.hold_progress(id)
	if p != _last_hold:
		_last_hold = p
		ui.set_hold_progress(p)


## The HUD dock covers the bottom of the screen; the camera frames the playfield above it.
func _push_bottom_inset() -> void:
	var hud: Node = ui.hud
	if hud == null or not hud.has_method("bottom_inset") or not world.has_method("set_bottom_inset"):
		return
	var px := float(hud.call("bottom_inset"))
	if px != _last_inset:
		_last_inset = px
		world.call("set_bottom_inset", px)


## Stop everything: the session's worker, input, UI, audio and the world.
func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	if _session != null:
		_session.dispose()
		_session = null
	_replay = null
	if Input.joy_connection_changed.is_connected(_on_joy_connection):
		Input.joy_connection_changed.disconnect(_on_joy_connection)
	if input != null:
		input.dispose()
	if ui != null:
		ui.dispose()
	if audio != null:
		audio.dispose()
	if world != null:
		world.dispose()
