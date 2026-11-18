extends SceneTree
## Windowed smoke run of the real game:
##
##   bash tools/gd shot res://tools/smoke.gd -- <screenshot dir>      (default user://smoke)
##
## Boots res://game/main.tscn exactly as the game does, with a fresh save kept in <dir>/save (the
## player's own save and replays are never touched), then walks a real slice of the game and saves
## a screenshot at each step:
##
##   title → campaign → loadout → level 01: chapter card → intro dialogue → briefing → setup (coach
##   mark) → count-in → recording (the level's stored solution inputs, fed through the real loop) →
##   the resolving beat → cinematic → outro → results with the loot reveal → campaign (watch button)
##   → level 03: intro skipped by holding cancel → take 1 → review → decision → commit → take 2
##   recording with take 1 playing back → pause → settings → Field Guide.
##
## Menu and session steps use real key events (Input.parse_input_event) wherever the game reads
## keys; level selection and the speed / end-mode setup use the same UiIntents the HUD and menu
## buttons emit. Level 02 is marked cleared through the campaign (its proof is the bot suite) so
## level 03 unlocks. Prints the missing facade modules, each step, and every script error the engine
## logged during the run, then quits (exit 1 when a step timed out or an error was logged).

const SOLUTIONS := "res://data/levels/solutions/%s.json"

var _dir: String = "user://smoke"
var _app: GameApp = null
var _shots: Array[String] = []
var _failures: Array[String] = []
var _log_path: String = ""
var _log_start: int = 0
var _n: int = 0
var _plan: GameBot.BotPlan = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for a: String in args:
		if not a.begins_with("--"):
			_dir = a
	if not _dir.begins_with("res://") and not _dir.begins_with("user://") and not _dir.is_absolute_path():
		_dir = ProjectSettings.globalize_path("res://").path_join(_dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	_log_path = ProjectSettings.globalize_path(str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log")))
	if FileAccess.file_exists(_log_path):
		var f := FileAccess.open(_log_path, FileAccess.READ)
		if f != null:
			_log_start = f.get_length()
			f.close()
	_run()


## A fresh save for this run, outside the player's user:// save.
func _fresh_save_dir() -> String:
	var save_dir := _dir.path_join("save")
	DirAccess.make_dir_recursive_absolute(save_dir.path_join("replays"))
	for sub: String in ["", "replays"]:
		var d := save_dir.path_join(sub)
		for f: String in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))
	return save_dir


func _run() -> void:
	GameApp.storage_dir_override = _fresh_save_dir()
	var scene := load("res://game/main.tscn") as PackedScene
	if scene == null:
		print("smoke: res://game/main.tscn failed to load")
		quit(1)
		return
	var main := scene.instantiate()
	root.add_child(main)
	_app = main as GameApp
	await _frames(30)
	if _app == null or _app.campaign == null:
		print("smoke: main scene did not wire a GameApp")
		quit(1)
		return
	print("smoke: missing modules: %s" % (", ".join(_app.missing_modules) if not _app.missing_modules.is_empty() else "none"))
	print("smoke: campaign: %d levels; dialogue layer %s; codex %d/%d pages" % [_app.campaign.levels.size(), "wired" if _app.dialogue != null else "MISSING", _app.codex.unlocked_count(), _app.codex.entry_count()])
	await _seconds(1.0)
	await _shot("title")

	_app.on_intent(UiIntent.simple(UiIntentType.OPEN_CAMPAIGN))
	await _seconds(0.8)
	await _shot("campaign")
	_app.on_intent(UiIntent.simple(UiIntentType.OPEN_LOADOUT))
	await _seconds(0.8)
	await _shot("loadout")
	_app.on_intent(UiIntent.simple(UiIntentType.OPEN_CAMPAIGN))
	await _seconds(0.4)

	# ── Level 01: the whole first-clear flow ──
	if not await _level_01():
		_finish()
		return
	# ── Level 03: two takes ──
	await _level_03()
	_finish()


func _level_01() -> bool:
	var id := "01-soft-open"
	if not _load_plan(id):
		return false
	_app.on_intent(UiIntent.play_level(id))
	if _app.session == null:
		_fail("could not start %s" % id)
		return false
	await _seconds(0.9)
	if _app.story_step == GameApp.STORY_CARD:
		await _shot("chapter_card")
		await _tap(KEY_ENTER)
		await _until(func() -> bool: return _app.story_step != GameApp.STORY_CARD, 6.0, "chapter card to finish")
	else:
		_fail("level 01 opened without its chapter card (story step '%s')" % _app.story_step)
	await _seconds(1.6)
	if _app.story_step == GameApp.STORY_INTRO:
		await _shot("intro_dialogue")
		await _advance_dialogue(GameApp.STORY_INTRO, "intro_dialogue_line")
	else:
		_fail("level 01 has no intro dialogue (story step '%s')" % _app.story_step)
	await _seconds(0.6)
	if _app.session.phase == SessionPhase.BRIEFING:
		await _shot("briefing")
		await _tap(KEY_ENTER)
	await _until(func() -> bool: return _app.session.phase == SessionPhase.SETUP, 3.0, "setup")
	await _seconds(2.5)
	await _shot("setup_coach")
	if not await _record_take(0, true):
		return false
	# The win: resolving → cinematic.
	await _until(func() -> bool: return _app.session.phase == SessionPhase.CINEMATIC, 30.0, "the cinematic")
	await _seconds(1.5)
	await _shot("cinematic")
	await _seconds(2.5)
	await _shot("cinematic_later")
	# Hold to skip (CINE-02).
	_key(KEY_ENTER, true)
	await _seconds(1.0)
	_key(KEY_ENTER, false)
	await _until(func() -> bool: return _app.session == null or _app.session.phase == SessionPhase.RESULTS, 30.0, "results phase")
	await _seconds(1.2)
	if _app.story_step == GameApp.STORY_OUTRO:
		await _shot("outro_dialogue")
		await _advance_dialogue(GameApp.STORY_OUTRO, "outro_dialogue_line")
	await _seconds(0.6)
	if _app.story_step == GameApp.STORY_FIRST:
		await _shot("first_loot_dialogue")
		await _advance_dialogue(GameApp.STORY_FIRST, "first_loot_dialogue_line")
	await _until(func() -> bool: return _app.screen == UiScreen.RESULTS, 10.0, "the results screen")
	await _seconds(2.2)
	await _shot("results_loot_reveal")
	await _seconds(3.0)
	await _shot("results_loot_cards")
	# LATER on the loot moment, then the results themselves.
	await _tap(KEY_ESCAPE)
	await _seconds(1.0)
	await _shot("results")
	print("smoke: level 01 outcome %s; kept replay: %s" % [JSON.stringify(_app.session.outcome.to_dict()) if _app.session != null and _app.session.outcome != null else "none", str(_app.replays.has_replay(id))])
	_app.on_intent(UiIntent.session(SessionAction.CONTINUE))
	await _seconds(1.0)
	await _shot("campaign_after_clear")
	print("smoke: replay table %s" % JSON.stringify(_app.replay_table))
	return true


func _level_03() -> void:
	var id := "03-hold-the-door"
	# Level 02's proof is the bot suite (tests/levels/test_campaign.gd); mark it cleared so 03 opens.
	_app.campaign.record_clear("02-hit-harder")
	if not _load_plan(id):
		return
	_app.on_intent(UiIntent.play_level(id))
	if _app.session == null:
		_fail("could not start %s" % id)
		return
	await _seconds(1.2)
	if _app.story_step == GameApp.STORY_INTRO:
		await _shot("l03_intro")
		# Every sequence can be skipped: hold cancel.
		_key(KEY_ESCAPE, true)
		await _seconds(1.2)
		_key(KEY_ESCAPE, false)
		await _until(func() -> bool: return _app.story_step == GameApp.STORY_NONE, 5.0, "the intro to be skipped")
	await _seconds(0.4)
	if _app.session.phase == SessionPhase.BRIEFING:
		await _tap(KEY_ENTER)
	await _until(func() -> bool: return _app.session.phase == SessionPhase.SETUP, 3.0, "setup")
	await _seconds(0.8)
	await _shot("l03_setup_take1")
	if not await _record_take(0, false):
		return
	await _until(func() -> bool: return _app.session.phase != SessionPhase.RECORDING and not _app.session.resolving, 30.0, "take 1 resolved")
	await _seconds(1.0)
	await _shot("l03_review_take1")
	if _app.session.phase == SessionPhase.REVIEW:
		await _clear_dialogue("l03_review_first")
		await _tap(KEY_ENTER)
	await _until(func() -> bool: return _app.session.phase == SessionPhase.DECISION, 5.0, "decision")
	await _seconds(1.5)
	await _clear_dialogue("l03_decision_first")
	await _shot("l03_decision")
	await _tap(KEY_ENTER)
	await _until(func() -> bool: return _app.session.phase == SessionPhase.SETUP and _app.session.committed_tapes.size() == 1, 5.0, "take 1 committed")
	await _seconds(0.8)
	await _clear_dialogue("l03_setup_first")
	await _shot("l03_setup_take2")
	if not await _record_take(1, false, 4.0):
		return
	await _shot("l03_take2_with_take1_playback")
	# Pause (abandons the live take: OPEN-21) → settings → Field Guide.
	await _tap(KEY_ESCAPE)
	await _until(func() -> bool: return _app.screen == UiScreen.PAUSE, 3.0, "pause")
	await _seconds(0.8)
	await _shot("pause")
	await _tap(KEY_DOWN)
	await _tap(KEY_DOWN)
	await _tap(KEY_ENTER)
	await _seconds(0.8)
	await _shot("pause_settings")
	await _tap(KEY_DOWN)
	await _tap(KEY_DOWN)
	await _tap(KEY_DOWN)
	await _tap(KEY_DOWN)
	await _tap(KEY_DOWN)
	await _tap(KEY_DOWN)
	await _tap(KEY_DOWN)
	await _seconds(0.5)
	await _shot("pause_settings_readability")
	_app.ui.navigate(UiBase.NAV_BACK)
	await _seconds(0.6)
	await _tap(KEY_DOWN)
	await _tap(KEY_ENTER)
	await _seconds(0.9)
	await _shot("field_guide")
	await _tap(KEY_ENTER)
	await _seconds(0.9)
	await _shot("field_guide_page")


func _load_plan(id: String) -> bool:
	var errors: Array[String] = []
	_plan = GameBot.load_plan(SOLUTIONS % id, errors)
	if _plan == null or _plan.draft or _plan.takes.is_empty():
		_fail("no runnable solution for %s: %s" % [id, ", ".join(errors)])
		return false
	return true


## Configure the cassette like the HUD buttons do, record it with the stored solution inputs fed
## through GameApp.input_script, and return once the take ended (or after `stop_after` seconds of
## recording, still recording, when > 0).
func _record_take(index: int, shots: bool, stop_after: float = 0.0) -> bool:
	if index >= _plan.takes.size():
		_fail("the solution has no take %d" % (index + 1))
		return false
	var take := _plan.takes[index]
	var s := _app.session
	var guard := 0
	while s.speed != take.speed and guard < 8:
		_app.on_intent(UiIntent.session(SessionAction.SPEED_UP if s.speed < take.speed else SessionAction.SPEED_DOWN))
		guard += 1
	guard = 0
	while s.end_mode != take.end_mode and guard < 4:
		_app.on_intent(UiIntent.session(SessionAction.CYCLE_END_MODE))
		guard += 1
	if s.speed != take.speed or s.end_mode != take.end_mode:
		_fail("could not set take %d to %sx / %s" % [index + 1, take.speed, OD.end_mode_name(take.end_mode)])
		return false
	var takes := _plan.takes
	_app.input_script = func(tick: int, ctx: GameBot.BotContext) -> Variant:
		var t: GameBot.BotTake = takes[ctx.index] if ctx.index < takes.size() else null
		return t.inputs.call(tick, ctx) if t != null else null
	await _tap(KEY_ENTER)
	await _until(func() -> bool: return _app.session.phase == SessionPhase.COUNTIN, 3.0, "count-in")
	await _seconds(0.9)
	if shots:
		await _shot("countin")
	await _until(func() -> bool: return _app.session.phase == SessionPhase.RECORDING, 4.0, "recording")
	if stop_after > 0.0:
		await _seconds(stop_after)
		return _app.session.phase == SessionPhase.RECORDING or _fail_false("take %d ended early" % (index + 1))
	await _seconds(1.5)
	if shots:
		await _shot("recording")
	await _until(func() -> bool: return _app.session.phase != SessionPhase.RECORDING, 60.0, "end of take %d" % (index + 1))
	if shots and _app.session.resolving:
		await _frames(2)
		await _shot("resolving")
	return true


## A queued "first" (firstDeath, firstGhostTake ...) may open a box at the next calm phase: read it
## through (screenshot of the first one) before pressing anything meant for the session.
func _clear_dialogue(name: String) -> void:
	var presses := 0
	var shot := false
	while _app.dialogue != null and bool(_app.dialogue.call("is_blocking")) and presses < 40:
		if not shot:
			await _seconds(0.8)
			await _shot(name)
			shot = true
		await _tap(KEY_ENTER)
		await _seconds(0.35)
		presses += 1


func _fail_false(msg: String) -> bool:
	_fail(msg)
	return false


## Accept through a dialogue sequence one line at a time (complete the typing, then advance),
## screenshotting the second line.
func _advance_dialogue(step: StringName, name: String) -> void:
	var presses := 0
	while _app.story_step == step and presses < 40:
		await _tap(KEY_ENTER)
		await _seconds(0.35)
		presses += 1
		if presses == 3:
			await _shot(name)
	if _app.story_step == step:
		_fail("dialogue '%s' did not finish" % step)


func _finish() -> void:
	var errors := _logged_errors()
	for e: String in errors:
		print("smoke: logged error: %s" % e)
	print("smoke: %d screenshot(s) in %s" % [_shots.size(), ProjectSettings.globalize_path(_dir)])
	for f: String in _failures:
		print("smoke: FAILED: %s" % f)
	var ok := _failures.is_empty() and errors.is_empty()
	print("smoke: %s" % ("OK" if ok else "FAILED"))
	if _app != null:
		_app.dispose()
	GameApp.storage_dir_override = ""
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("smoke: step failed: %s" % msg)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _until(cond: Callable, timeout_s: float, what: String) -> void:
	var t0 := Time.get_ticks_msec()
	while not bool(cond.call()):
		if Time.get_ticks_msec() - t0 > timeout_s * 1000.0:
			_fail("timed out waiting for %s (screen %s, phase %s, story '%s')" % [what, _app.screen, _app.session.phase if _app.session != null else &"-", _app.story_step])
			return
		await process_frame


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	if OS.get_environment("OVERDUB_DIAG") == "1" and name == "briefing":
		_instance_uniform_report()
	_n += 1
	var img := root.get_texture().get_image()
	var path := _dir.path_join("%02d_%s.png" % [_n, name])
	if img == null or img.save_png(path) != OK:
		_fail("could not save %s" % path)
		return
	_shots.append(path)
	print("smoke: shot %s (screen %s, phase %s, story '%s')" % [path.get_file(), _app.screen, _app.session.phase if _app.session != null else &"-", _app.story_step])


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _tap(code: Key) -> void:
	_key(code, true)
	await _frames(3)
	_key(code, false)
	await _frames(2)


func _mouse_move(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)


## SCRIPT ERROR / ERROR lines the engine logged since the run started.
func _logged_errors() -> Array[String]:
	var out: Array[String] = []
	if _log_path == "" or not FileAccess.file_exists(_log_path):
		return out
	var f := FileAccess.open(_log_path, FileAccess.READ)
	if f == null:
		return out
	f.seek(_log_start)
	var text := f.get_buffer(f.get_length() - _log_start).get_string_from_utf8()
	f.close()
	var lines := text.split("\n")
	for i in lines.size():
		var l := lines[i]
		if l.begins_with("SCRIPT ERROR") or l.begins_with("ERROR:") or l.begins_with("USER SCRIPT ERROR") or l.begins_with("USER ERROR"):
			var at := lines[i + 1].strip_edges() if i + 1 < lines.size() else ""
			out.append(l.strip_edges() + ("  " + at if at.begins_with("at:") else ""))
	return out


## OVERDUB_DIAG=1: count the geometry instances whose materials declare instance uniforms, per
## shader (the web renderer holds at most 4,096 instance-uniform slots in all).
func _instance_uniform_report() -> void:
	var counts := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch: Node in n.get_children():
			stack.append(ch)
		var gi := n as GeometryInstance3D
		if gi == null:
			continue
		var mats: Array[Material] = [gi.material_override, gi.material_overlay]
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			for i: int in range(mi.mesh.get_surface_count()):
				mats.append(mi.get_surface_override_material(i))
				mats.append(mi.mesh.surface_get_material(i))
		var seen := {}
		for m: Material in mats:
			var sm := m as ShaderMaterial
			while sm != null:
				if sm.shader != null and RegEx.create_from_string(r"(?m)^\s*instance\s+uniform\s").search(sm.shader.code) != null and not seen.has(sm.shader.resource_path):
					seen[sm.shader.resource_path] = true
					var key := "%s (%s)" % [sm.shader.resource_path, n.get_class()]
					counts[key] = int(counts.get(key, 0)) + 1
				sm = sm.next_pass as ShaderMaterial
	for k: String in counts:
		print("diag: %5d %s" % [counts[k], k])
