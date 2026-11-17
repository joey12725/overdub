extends SceneTree
## Windowed playthrough of the whole campaign, for looking at the real game:
##
##   bash tools/gd shot res://tools/playthrough.gd -- <screenshot dir> [--from=N] [--to=M] [--levels=1,10,11] [--extras] [--only-extras] [--trace]
##
## Boots res://game/main.tscn exactly as the game does, with a fresh save kept in <dir>/save (the
## player's own save and replays are never touched), then for every campaign level N..M (default
## 1..12) plays the stored solution (data/levels/solutions/<id>.json) through the real game loop
## (GameApp.input_script, as tools/smoke.gd does) and saves screenshots per level:
##
##   setup of take 1 · mid-recording of the last take (earlier takes playing back) · one frame at a
##   combat hit (an enemy lost health) · a dart in flight (levels with a dart launcher) · mid-cinematic ·
##   results (plus the loot moment when there is one)
##
## Levels before N are marked cleared through the campaign so N is unlocked (their proof is an earlier
## run of this tool / the bot suite). A whole run takes longer than ten minutes: run it in pieces
## (--from=1 --to=4, --from=5 --to=8, --from=9 --to=11, --from=12 --extras).
##
## --extras (after the levels): the ending and credits when level 12 was just won, the campaign
## screen, the loadout screen with a gear swap (and Moxie in the level wearing it), the Field Guide,
## the settings screen, a replay watched from the campaign screen, and a deliberately failed attempt
## (the failed playback, the decision screen, the pause menu's Field Guide hint).
##
## Dialogue is skipped wherever the game allows (hold cancel). Prints each level's outcome and every
## script error the engine logged; exit 1 when a level did not win, a step timed out or an error was
## logged.

const SOLUTIONS := "res://data/levels/solutions/%s.json"

var _dir: String = "user://playthrough"
var _from: int = 1
var _to: int = 12
var _extras: bool = false
var _only_extras: bool = false
var _app: GameApp = null
var _shots: Array[String] = []
var _failures: Array[String] = []
var _outcomes: Array[String] = []
var _log_path: String = ""
var _log_start: int = 0
var _n: int = 0
var _plan: GameBot.BotPlan = null
var _tag: String = ""
# Recording probes (written by the input script, read by the frame loop).
var _tick: int = 0
var _hp_sum: int = -1
var _hit_flag: bool = false
var _hit_shots: int = 0
var _dart_flag: bool = false
var _dart_shot: bool = false
var _only: Array[int] = []


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--from="):
			_from = int(a.trim_prefix("--from="))
		elif a.begins_with("--to="):
			_to = int(a.trim_prefix("--to="))
		elif a.begins_with("--levels="):
			for n: String in a.trim_prefix("--levels=").split(",", false):
				_only.append(int(n))
		elif a == "--extras":
			_extras = true
		elif a == "--only-extras":
			_extras = true
			_only_extras = true
		elif not a.begins_with("--"):
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
		print("play: res://game/main.tscn failed to load")
		quit(1)
		return
	var main := scene.instantiate()
	root.add_child(main)
	_app = main as GameApp
	if OS.get_cmdline_user_args().has("--trace"):
		var tr := Tracer.new()
		tr.name = "Tracer"
		root.add_child(tr)
	await _frames(30)
	if _app == null or _app.campaign == null:
		print("play: main scene did not wire a GameApp")
		quit(1)
		return
	print("play: missing modules: %s" % (", ".join(_app.missing_modules) if not _app.missing_modules.is_empty() else "none"))
	var levels := _app.campaign.levels
	_to = mini(_to, levels.size())
	if _only_extras:
		_from = levels.size() + 1
	# Earlier levels: cleared through the campaign so this run's first level is unlocked.
	for i in mini(_from - 1, levels.size()):
		_app.campaign.record_clear(levels[i].id)
	await _seconds(1.0)
	_tag = "00"
	if _from == 1:
		await _shot("title")
	_app.on_intent(UiIntent.simple(UiIntentType.OPEN_CAMPAIGN))
	await _seconds(0.9)
	await _shot("campaign_start")

	var won_last := false
	for i in range(_from - 1, _to):
		var lv := levels[i]
		if not _only.is_empty() and not _only.has(i + 1):
			_app.campaign.record_clear(lv.id)
			continue
		_tag = "L%02d" % (i + 1)
		var ok := await _play_level(lv, i == levels.size() - 1)
		won_last = ok and i == levels.size() - 1
		if _app.session != null:
			# A level that did not end on its results: leave it.
			_app.on_intent(UiIntent.session(SessionAction.QUIT))
			await _seconds(0.6)
		if not ok and not _app.campaign.is_cleared(lv.id):
			# Keep going: the next level still has to be looked at.
			_app.campaign.record_clear(lv.id)
	if _extras:
		await _do_extras(won_last)
	_finish()


# ───────────────────────────── one level ─────────────────────────────

func _play_level(lv: LevelDef, is_final: bool) -> bool:
	var id := lv.id
	var errors: Array[String] = []
	_plan = GameBot.load_plan(SOLUTIONS % id, errors)
	if _plan == null or _plan.draft or _plan.takes.is_empty():
		return _level_failed(id, "no runnable solution: %s" % ", ".join(errors))
	_app.on_intent(UiIntent.play_level(id))
	if _app.session == null:
		return _level_failed(id, "could not start")
	await _seconds(0.9)
	if _app.story_step == GameApp.STORY_CARD:
		await _shot("chapter_card")
	await _pass_story("intro")
	await _seconds(0.4)
	if _app.session.phase == SessionPhase.BRIEFING:
		await _shot("briefing")
		await _tap(KEY_ENTER)
	await _until(func() -> bool: return _app.session.phase == SessionPhase.SETUP, 4.0, "setup")
	await _seconds(2.2)
	await _clear_dialogue("setup_box")
	await _shot("setup_take1")
	_hit_shots = 0
	_dart_flag = false
	_dart_shot = false
	var last := _plan.takes.size() - 1
	for t in _plan.takes.size():
		if not await _record_take(t, t == last):
			return _level_failed(id, "take %d could not be recorded" % (t + 1))
		if t == last:
			break
		await _until(func() -> bool: return _app.session.phase != SessionPhase.RECORDING and not _app.session.resolving, 40.0, "take %d resolved" % (t + 1))
		if _app.session.phase == SessionPhase.CINEMATIC:
			break
		await _seconds(0.5)
		await _clear_dialogue("review_box")
		if _app.session.phase == SessionPhase.REVIEW:
			await _tap(KEY_ENTER)
		await _until(func() -> bool: return _app.session.phase == SessionPhase.DECISION, 6.0, "decision")
		await _seconds(0.8)
		await _clear_dialogue("decision_box")
		if t == 0:
			await _shot("decision_take1")
		var want := _app.session.committed_tapes.size() + 1
		await _tap(KEY_ENTER)
		await _until(func() -> bool: return _app.session.phase == SessionPhase.SETUP and _app.session.committed_tapes.size() == want, 6.0, "take %d committed" % (t + 1))
		await _seconds(0.7)
		await _clear_dialogue("setup_box")
		if t + 1 == last:
			await _seconds(0.6)
			await _shot("setup_take%d" % (last + 1))
	# The verdict.
	await _until(func() -> bool: return _app.session.phase != SessionPhase.RECORDING and not _app.session.resolving, 40.0, "the last take resolved")
	var s := _app.session
	if s.phase != SessionPhase.CINEMATIC:
		await _seconds(1.0)
		await _shot("NOT_WON")
		var why := JSON.stringify(s.outcome.to_dict()) if s.outcome != null else "no outcome"
		return _level_failed(id, "the solution did not win in the real loop: %s" % why)
	var outcome := s.outcome
	await _seconds(3.2)
	await _shot("cinematic")
	if is_final or lv.index == 1:
		await _seconds(3.0)
		await _shot("cinematic_later")
	# Hold to skip (CINE-02).
	_key(KEY_ENTER, true)
	await _seconds(1.0)
	_key(KEY_ENTER, false)
	await _until(func() -> bool: return _app.session == null or _app.session.phase == SessionPhase.RESULTS, 60.0, "results phase")
	await _seconds(1.0)
	if _app.story_step == GameApp.STORY_OUTRO and lv.index == 1:
		await _shot("outro_dialogue")
	await _pass_story("outro")
	await _until(func() -> bool: return _app.screen == UiScreen.RESULTS, 20.0, "the results screen")
	await _seconds(2.4)
	var menus: Variant = _app.ui.get("menus")
	if menus != null and menus.loot_reveal != null and is_instance_valid(menus.loot_reveal):
		await _seconds(2.6)
		await _shot("loot")
		await _tap(KEY_ESCAPE)
		await _seconds(1.0)
	await _shot("results")
	var line := "%s: WIN, %d take(s), survivors %s, replay kept %s" % [id, s.tapes_used, str(outcome.survivors), str(_app.replays.has_replay(id))]
	_outcomes.append(line)
	print("play: level %s" % line)
	_app.on_intent(UiIntent.session(SessionAction.CONTINUE))
	await _seconds(1.0)
	return true


func _level_failed(id: String, why: String) -> bool:
	_outcomes.append("%s: FAILED - %s" % [id, why])
	_fail("level %s: %s" % [id, why])
	return false


## Configure the cassette like the HUD buttons do and record it with the stored solution inputs.
## Returns once the take ended. On the last take: a screenshot mid-take; on any take, one at the
## first combat hit (at most two per level).
func _record_take(index: int, is_last: bool) -> bool:
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
	_tick = 0
	_hp_sum = -1
	_hit_flag = false
	_app.input_script = func(tick: int, ctx: GameBot.BotContext) -> Variant:
		_tick = tick
		var hp := 0
		for e: EnemySnap in ctx.snap.enemies:
			hp += maxi(0, e.hp) if e.alive else 0
		if _hp_sum >= 0 and hp < _hp_sum:
			_hit_flag = true
		for p: ProjectileSnap in ctx.snap.projectiles:
			if p.archetype == RangedArchetype.DART and not _dart_shot:
				_dart_flag = true
		_hp_sum = hp
		var t: GameBot.BotTake = takes[ctx.index] if ctx.index < takes.size() else null
		return t.inputs.call(tick, ctx) if t != null else null
	await _tap(KEY_ENTER)
	await _until(func() -> bool: return _app.session.phase == SessionPhase.COUNTIN or _app.session.phase == SessionPhase.RECORDING, 3.0, "count-in")
	await _until(func() -> bool: return _app.session.phase == SessionPhase.RECORDING, 6.0, "recording")
	if _app.session.phase != SessionPhase.RECORDING:
		return false
	var expect_ticks := mini(s.tape_ticks, int(s.horizon_subs / (OD.FRAME_SUBS * take.speed)))
	var mid := int(expect_ticks * 0.45)
	var mid_done := not is_last
	var t0 := Time.get_ticks_msec()
	while _app.session != null and _app.session.phase == SessionPhase.RECORDING:
		if _hit_flag:
			_hit_flag = false
			if _hit_shots < 2 and (is_last or _hit_shots == 0):
				_hit_shots += 1
				await _shot("hit_take%d" % (index + 1), 0)
		if _dart_flag and not _dart_shot:
			_dart_shot = true
			await _shot("dart_in_flight_take%d" % (index + 1), 1)
		if not mid_done and _tick >= mid:
			mid_done = true
			await _shot("recording_take%d_mid" % (index + 1), 0)
		if Time.get_ticks_msec() - t0 > 120000:
			_fail("take %d never ended" % (index + 1))
			return false
		await process_frame
	if not mid_done:
		await _shot("recording_take%d_end" % (index + 1), 0)
	return true


# ───────────────────────────── extras ─────────────────────────────

func _do_extras(won_last: bool) -> void:
	_tag = "X"
	if won_last:
		# Continue on the last results went to the ending.
		await _seconds(1.5)
		await _shot("ending_%s" % _app.screen)
		await _seconds(4.0)
		await _shot("ending_later")
		_app.on_intent(UiIntent.simple(UiIntentType.OPEN_CAMPAIGN))
		await _seconds(1.5)
		if _app.story_step == GameApp.STORY_STINGER:
			await _shot("stinger")
			await _pass_story("stinger")
		await _seconds(1.0)
	if _app.session != null:
		_app.on_intent(UiIntent.session(SessionAction.QUIT))
	_app.on_intent(UiIntent.simple(UiIntentType.OPEN_CAMPAIGN))
	await _seconds(1.2)
	await _shot("campaign_all")
	for k in 6:
		await _tap(KEY_UP)
	await _seconds(0.6)
	await _shot("campaign_scrolled")

	# Loadout and a gear swap.
	_app.on_intent(UiIntent.simple(UiIntentType.OPEN_LOADOUT))
	await _seconds(1.2)
	await _shot("loadout_base")
	var model := _app.campaign.loadout_model()
	var base := model.loadout.copy()
	var swapped: Array[String] = []
	for slot: StringName in OD.GEAR_SLOTS:
		for it: GearItem in model.inventory:
			if it.slot == slot and it.id != base.get_slot(slot):
				_app.on_intent(UiIntent.equip(slot, it.id))
				swapped.append("%s=%s" % [slot, it.id])
				break
	print("play: gear swap %s" % ", ".join(swapped))
	await _seconds(1.5)
	await _shot("loadout_swapped")
	# Moxie in a level wearing it.
	if not swapped.is_empty():
		var first := _app.campaign.levels[0]
		_app.on_intent(UiIntent.play_level(first.id))
		await _seconds(0.9)
		await _pass_story("intro")
		if _app.session != null and _app.session.phase == SessionPhase.BRIEFING:
			await _tap(KEY_ENTER)
		await _seconds(2.5)
		await _clear_dialogue("")
		_app.input_script = func(_tick: int, _ctx: GameBot.BotContext) -> Variant:
			var inp := GameBot.idle_input(0.6)
			inp.move_x = 0.5
			inp.light = _tick % 40 == 20
			return inp
		await _tap(KEY_ENTER)
		await _until(func() -> bool: return _app.session != null and _app.session.phase == SessionPhase.RECORDING, 8.0, "recording with swapped gear")
		await _seconds(1.2)
		await _shot("swapped_gear_in_level", 0)
		_app.on_intent(UiIntent.session(SessionAction.QUIT))
		await _seconds(0.6)
		# Back to the baseline.
		_app.on_intent(UiIntent.simple(UiIntentType.OPEN_LOADOUT))
		await _seconds(0.5)
		for slot: StringName in OD.GEAR_SLOTS:
			if base.get_slot(slot) != "":
				_app.on_intent(UiIntent.equip(slot, base.get_slot(slot)))
		await _seconds(0.5)

	# Field Guide from the campaign screen.
	_app.on_intent(UiIntent.simple(UiIntentType.OPEN_CAMPAIGN))
	await _seconds(0.8)
	if _app.ui.has_method("open_codex"):
		_app.ui.call("open_codex", "")
		await _seconds(1.0)
		await _shot("field_guide")
		await _tap(KEY_DOWN)
		await _tap(KEY_DOWN)
		await _tap(KEY_ENTER)
		await _seconds(1.0)
		await _shot("field_guide_page")
		_app.ui.navigate(UiBase.NAV_BACK)
		await _seconds(0.3)
		_app.ui.navigate(UiBase.NAV_BACK)
		await _seconds(0.5)

	# Settings.
	_app.on_intent(UiIntent.simple(UiIntentType.OPEN_SETTINGS))
	await _seconds(1.0)
	await _shot("settings")
	for k in 9:
		await _tap(KEY_DOWN)
	await _seconds(0.5)
	await _shot("settings_lower")
	for k in 9:
		await _tap(KEY_DOWN)
	await _seconds(0.5)
	await _shot("settings_bottom")
	_app.on_intent(UiIntent.simple(UiIntentType.OPEN_CAMPAIGN))
	await _seconds(0.8)

	# A replay watched from the campaign screen.
	var rid := ""
	for lv: LevelDef in _app.campaign.levels:
		if _app.replays != null and _app.replays.has_replay(lv.id):
			rid = lv.id
	if rid == "":
		print("play: no kept replay in this run (run the extras together with a level)")
	else:
		var wi := UiIntent.simple(GameApp.INTENT_WATCH_REPLAY)
		wi.id = rid
		_app.on_intent(wi)
		await _seconds(0.5)
		if _app.replay_playback == null:
			_fail("the replay of %s did not start" % rid)
		else:
			await _seconds(4.0)
			await _shot("replay_%s" % rid.substr(0, 2), 0)
			await _seconds(4.0)
			await _shot("replay_%s_later" % rid.substr(0, 2), 0)
			_key(KEY_ENTER, true)
			await _seconds(1.1)
			_key(KEY_ENTER, false)
			await _until(func() -> bool: return _app.replay_playback == null, 60.0, "the replay to stop")
			await _seconds(0.8)

	# A deliberately failed attempt: level 01 with nobody at the controls.
	var l1 := _app.campaign.levels[0]
	_app.on_intent(UiIntent.play_level(l1.id))
	if _app.session == null:
		_fail("could not start the failed attempt")
		return
	await _seconds(0.9)
	await _pass_story("intro")
	if _app.session.phase == SessionPhase.BRIEFING:
		await _tap(KEY_ENTER)
	await _until(func() -> bool: return _app.session.phase == SessionPhase.SETUP, 4.0, "setup")
	await _seconds(1.5)
	await _clear_dialogue("")
	_app.input_script = func(_tick: int, _ctx: GameBot.BotContext) -> Variant: return GameBot.idle_input(0.0)
	await _tap(KEY_ENTER)
	await _until(func() -> bool: return _app.session.phase == SessionPhase.RECORDING, 8.0, "recording")
	var dead := func() -> bool:
		if _app.session.phase != SessionPhase.RECORDING:
			return true
		var f := _app.last_rendered_frame
		if f == null or f.snap == null:
			return false
		for a: ActorSnap in f.snap.actors:
			if a.live and a.life != OD.LifeState.ALIVE:
				return true
		return false
	await _until(dead, 60.0, "the idle self to die or the take to end")
	if _app.session.phase == SessionPhase.RECORDING:
		await _seconds(0.5)
		await _shot("fail_died_recording_ghost", 0)
	await _until(func() -> bool: return _app.session.phase != SessionPhase.RECORDING and not _app.session.resolving, 90.0, "the failed take resolved")
	await _seconds(2.0)
	await _shot("fail_review")
	await _clear_dialogue("fail_review_box")
	if _app.session.phase == SessionPhase.REVIEW:
		await _tap(KEY_ENTER)
	await _until(func() -> bool: return _app.session.phase == SessionPhase.DECISION, 8.0, "decision after the failure")
	await _seconds(1.5)
	await _clear_dialogue("fail_decision_box")
	await _seconds(0.5)
	await _shot("fail_decision")
	print("play: failed attempt outcome %s; Field Guide hint '%s'" % [JSON.stringify(_app.session.outcome.to_dict()) if _app.session.outcome != null else "none", _app.codex_hint])
	await _tap(KEY_ESCAPE)
	await _until(func() -> bool: return _app.screen == UiScreen.PAUSE, 3.0, "pause")
	await _seconds(0.8)
	await _shot("fail_pause")
	if _app.ui.has_method("open_codex"):
		_app.ui.call("open_codex", "")
		await _seconds(1.0)
		await _shot("fail_field_guide_hint")
		_app.ui.navigate(UiBase.NAV_BACK)
		await _seconds(0.4)
	_app.on_intent(UiIntent.session(SessionAction.QUIT))
	await _seconds(0.6)


# ───────────────────────────── helpers ─────────────────────────────

## Get past whatever story is up: a chapter card (accept), then dialogue (hold cancel to skip the
## sequence; accept through it when that does not end it).
func _pass_story(what: String) -> void:
	var guard := 0
	while _app.story_blocking() and guard < 12:
		guard += 1
		if _app.story_step == GameApp.STORY_CARD:
			await _tap(KEY_ENTER)
			await _until(func() -> bool: return _app.story_step != GameApp.STORY_CARD, 6.0, "chapter card to finish")
			await _seconds(1.0)
			continue
		var step := _app.story_step
		_key(KEY_ESCAPE, true)
		await _seconds(1.2)
		_key(KEY_ESCAPE, false)
		await _seconds(0.5)
		if _app.story_blocking() and _app.story_step == step:
			for k in 6:
				await _tap(KEY_ENTER)
				await _seconds(0.25)
	if _app.story_blocking():
		_fail("story '%s' (%s) did not finish" % [_app.story_step, what])


## A queued "first" may open a box at a calm phase: skip it (screenshot of the first when named).
func _clear_dialogue(name: String) -> void:
	var presses := 0
	var shot := name == ""
	while _app.dialogue != null and bool(_app.dialogue.call("is_blocking")) and presses < 40:
		if not shot:
			await _seconds(0.8)
			await _shot(name)
			shot = true
		await _tap(KEY_ENTER)
		await _seconds(0.3)
		presses += 1


func _finish() -> void:
	var errors := _logged_errors()
	print("play: ───── outcomes ─────")
	for o: String in _outcomes:
		print("play: %s" % o)
	for e: String in errors:
		print("play: logged error: %s" % e)
	print("play: %d screenshot(s) in %s" % [_shots.size(), ProjectSettings.globalize_path(_dir)])
	for f: String in _failures:
		print("play: FAILED: %s" % f)
	var ok := _failures.is_empty() and errors.is_empty()
	print("play: %s" % ("OK" if ok else "FAILED"))
	if _app != null:
		_app.dispose()
	GameApp.storage_dir_override = ""
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("play: step failed: %s" % msg)


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
			var pl: Variant = _app.dialogue.get("player") if _app.dialogue != null else null
			var fo := root.gui_get_focus_owner()
			print("play:   blocking %s; dialogue open %s queued %s phase '%s'; focus owner %s; actions %s" % [
				str(_app.story_blocking()), str(pl.is_open()) if pl != null else "-", str(pl.queued()) if pl != null else "-",
				str(pl.phase) if pl != null else "-", str(fo.get_path()) if fo != null else "none",
				str(_app.session.actions()) if _app.session != null else "-"])
			print("play:   input down %s holds %s queue %s latched %s" % [str(_app.input.get("_down")), str((_app.input.get("_holds") as Dictionary).keys()), str(_app.input.get("_queue")), str(_app.input.get("_latched"))])
			return
		await process_frame


func _shot(name: String, settle_frames: int = 2) -> void:
	for i in settle_frames:
		await process_frame
	_n += 1
	var img := root.get_texture().get_image()
	var path := _dir.path_join("%s_%03d_%s.png" % [_tag, _n, name])
	if img == null or img.save_png(path) != OK:
		_fail("could not save %s" % path)
		return
	_shots.append(path)
	print("play: shot %s (screen %s, phase %s, story '%s', tick %d)" % [path.get_file(), _app.screen, _app.session.phase if _app.session != null else &"-", _app.story_step, _tick])


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


## --trace: where each Enter / Esc key event gets to (debugging swallowed input).
class Tracer:
	extends Node

	func _input(e: InputEvent) -> void:
		var k := e as InputEventKey
		if k != null and not k.echo:
			var fo := get_viewport().gui_get_focus_owner()
			print("play:   [trace] _input %s %s (focus %s)" % [OS.get_keycode_string(k.physical_keycode), "down" if k.pressed else "up", str(fo.get_path()) if fo != null else "none"])

	func _unhandled_input(e: InputEvent) -> void:
		var k := e as InputEventKey
		if k != null and not k.echo:
			print("play:   [trace] _unhandled_input %s %s" % [OS.get_keycode_string(k.physical_keycode), "down" if k.pressed else "up"])
