extends SceneTree
## Screenshots of the story / onboarding overlay (ui/dialogue/DialogueLayer) over the real in-level
## HUD (res://ui/hud/hud.tscn) and a reference-art backdrop: a dialogue exchange (typing, a Moxie
## portrait, the coloured-initial fallback, 720p and 4K), barks (next to the deck, over Moxie's head),
## coach marks on a deck, a ruler lane, a world self and a decision prompt, the coach-slot fallback,
## and the failure hint card. Real data: data/story/story.json, data/onboarding/*.json and
## assets/portraits/. Coach marks are put on screen directly (engine.current = mark) so each shot is
## deterministic; the lifecycle itself is covered by tests/ui_dialogue/test_coach.gd.
##
##   bash tools/gd shot res://tools/shot_dialogue.gd [-- <out_dir>] [only=<name-substring>]
##
## Default out dir: res://art/previews/dialogue. Prints one line per file written.

const HUD_SCENE := "res://ui/hud/hud.tscn"
const BACKDROPS: Array[String] = ["res://docs/reference/R03-upper-environment.png", "res://docs/reference/R04-lower-environment.png"]
const LEVEL_ID := "01-soft-open"

var out_dir := ""
var only := ""
var _bg_cache: Dictionary = {}


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
		elif a != "":
			out_dir = a
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://art/previews/dialogue")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var shots: Array = [
		["01_intro_opal_typing", Vector2i(1600, 900)],
		["02_intro_moxie", Vector2i(1600, 900)],
		["03_intro_moxie_720p", Vector2i(1280, 720)],
		["04_intro_moxie_4k", Vector2i(3840, 2160)],
		["05_ending_archivist", Vector2i(1600, 900)],
		["06_bark_deck", Vector2i(1600, 900)],
		["07_bark_head", Vector2i(1600, 900)],
		["08_coach_deck", Vector2i(1600, 900)],
		["09_coach_ruler_lane", Vector2i(1600, 900)],
		["10_coach_world_self", Vector2i(1600, 900)],
		["11_coach_prompt_commit", Vector2i(1600, 900)],
		["12_coach_slot_fallback", Vector2i(1280, 720)],
		["13_failure_hint", Vector2i(1600, 900)],
	]
	var n := 0
	for s: Array in shots:
		if only != "" and not String(s[0]).contains(only):
			continue
		await _shoot(s[0], s[1])
		n += 1
	print("shot_dialogue: %d file(s) in %s" % [n, out_dir])
	quit(0)


# ───────────────────────────── one shot ─────────────────────────────

class Stage:
	extends RefCounted
	var vp: SubViewport
	var hud: HudBase
	var layer: DialogueLayer
	var actors: ActorMarkers
	var res: Vector2


## Stand-ins for the 3D selves so world anchors have something to point at: Moxie (yellow), and
## earlier takes in their cassette colours (a dashed outline when desynced).
class ActorMarkers:
	extends Control
	## [screen pos, tape, desynced, label]
	var items: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var u := UiPalette.unit_for(size)
		for it: Array in items:
			var p: Vector2 = it[0]
			var col := UiPalette.MOXIE_YELLOW if int(it[1]) < 0 else UiPalette.tape(int(it[1]))
			var r := u * 1.3
			draw_circle(p + Vector2(0, u * 2.4), r * 1.1, Color(0, 0, 0, 0.35))
			if bool(it[2]):
				draw_arc(p, r, 0.0, TAU, 32, col, maxf(2.0, u * 0.18), true)
				draw_arc(p + Vector2(0, r * 1.9), r * 1.2, PI, TAU, 24, col, maxf(2.0, u * 0.18), true)
			else:
				draw_circle(p, r, col)
				draw_rect(Rect2(p + Vector2(-r, r * 0.9), Vector2(r * 2.0, r * 2.0)), col)
				draw_arc(p, r, 0.0, TAU, 32, UiPalette.INK, maxf(2.0, u * 0.14), true)
			var f := UiPalette.font_ui()
			draw_string(f, p + Vector2(-r * 2.0, r * 4.2), str(it[3]), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(u * 0.9), Color(UiPalette.PAPER, 0.8))


func _w2s(res: Vector2) -> Callable:
	var k := res.x / 1600.0
	return func(p: Vector2) -> Variant:
		return (Vector2(420, 230) + p * 48.0) * k


func _stage(res: Vector2i, backdrop: int, hud_visible: bool) -> Stage:
	var st := Stage.new()
	st.res = Vector2(res)
	st.vp = SubViewport.new()
	st.vp.size = res
	st.vp.transparent_bg = false
	st.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(st.vp)
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.texture = _backdrop(backdrop)
	bg.modulate = Color(0.78, 0.78, 0.78)
	st.vp.add_child(bg)
	st.actors = ActorMarkers.new()
	st.vp.add_child(st.actors)
	st.hud = (load(HUD_SCENE) as PackedScene).instantiate() as HudBase
	st.vp.add_child(st.hud)
	st.hud.visible = hud_visible
	var b: Dictionary[StringName, ButtonPrompt] = {}
	var defaults: Dictionary = HudModel.default_bindings(HudModel.DEVICE_KEYBOARD)
	for a: StringName in SessionAction.ALL:
		if defaults.has(a):
			b[a] = defaults[a]
	st.hud.set_bindings(b)
	st.layer = DialogueLayer.new()
	st.vp.add_child(st.layer)
	st.layer.setup(st.hud, _w2s(st.res))
	var prompts: Dictionary = b.duplicate()
	prompts[&"move"] = ButtonPrompt.make("WASD")
	prompts[&"aim"] = ButtonPrompt.make("Mouse")
	st.layer.set_bindings(prompts)
	st.layer.begin_level(LEVEL_ID)
	return st


func _backdrop(i: int) -> Texture2D:
	if _bg_cache.has(i):
		return _bg_cache[i]
	var img := Image.load_from_file(ProjectSettings.globalize_path(BACKDROPS[i]))
	var t: Texture2D = ImageTexture.create_from_image(img) if img != null else null
	_bg_cache[i] = t
	return t


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _save(st: Stage, name: String, extra: String = "") -> void:
	await RenderingServer.frame_post_draw
	var img := st.vp.get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	var err := img.save_png(path)
	print("%s %s %s" % ["wrote" if err == OK else "FAILED", path, extra])
	st.vp.queue_free()
	await process_frame


func _shoot(name: String, res: Vector2i) -> void:
	match name:
		"01_intro_opal_typing":
			var st := _stage(res, 0, false)
			st.layer.play_intro(LEVEL_ID)
			await _frames(22)
			await _save(st, name, "chars=%d" % st.layer.player.runner.visible_chars())
		"02_intro_moxie", "03_intro_moxie_720p", "04_intro_moxie_4k":
			var st := _stage(res, 0, false)
			var intro := st.layer.story.level_lines(LEVEL_ID, "intro")
			var moxie: Array[DlgLine] = []
			for l: DlgLine in intro:
				if l.who == "moxie":
					moxie.append(l)
			st.layer.play_lines(moxie.slice(0, 1), DialoguePlayer.KIND_INTRO, LEVEL_ID)
			await _complete_line(st)
			var box := st.layer.player.box
			await _save(st, name, "unit=%.1f font=%d portrait=%s fallback=%s" % [box.unit, box.text_label.get_theme_font_size("font_size"), box.portrait_rect(), box.portrait.is_fallback()])
		"05_ending_archivist":
			var st := _stage(res, 1, false)
			var end := st.layer.story.ending_lines()
			st.layer.play_lines(end.slice(0, 1), DialoguePlayer.KIND_ENDING, "ending")
			await _complete_line(st)
			await _save(st, name)
		"06_bark_deck":
			var st := _stage(res, 0, true)
			st.layer.set_options(true, false)
			var v := _setup_view()
			st.hud.update_hud(v, MusicPulse.new())
			st.layer.update(v, [], 0.016)
			st.layer.bark("lastTape", true)
			for k in 14:
				await process_frame
				st.layer.update(v, [], 0.016)
			await _save(st, name, "bubble=%s" % st.layer.barks.bubble_rect())
		"07_bark_head":
			var st := _stage(res, 0, true)
			st.layer.set_options(true, false)
			st.layer.barks_over_head = true
			var v := _recording_view()
			var snap := _snap()
			_mark_actors(st, snap, v)
			st.hud.update_hud(v, MusicPulse.new())
			st.layer.update(v, [], 0.016, snap)
			st.layer.bark("resync", true)
			for k in 14:
				await process_frame
				st.layer.update(v, [], 0.016, snap)
			await _save(st, name, "bubble=%s" % st.layer.barks.bubble_rect())
		"08_coach_deck":
			var st := _stage(res, 0, true)
			await _coach(st, _setup_view(), null, "deck-armed", -1)
			await _save(st, name, _coach_info(st))
		"09_coach_ruler_lane":
			var st := _stage(res, 0, true)
			var v := _recording_view()
			await _coach(st, v, _snap(), "ruler-lane", -1)
			await _save(st, name, _coach_info(st))
		"10_coach_world_self":
			var st := _stage(res, 1, true)
			var v := _recording_view()
			var snap := _snap()
			_mark_actors(st, snap, v)
			await _coach(st, v, snap, "desync", 1)
			await _save(st, name, _coach_info(st))
		"11_coach_prompt_commit":
			var st := _stage(res, 1, true)
			await _coach(st, _decision_view(true), null, "decide", -1)
			await _save(st, name, _coach_info(st))
		"12_coach_slot_fallback":
			var st := _stage(res, 0, true)
			await _coach(st, _recording_view(), _snap(), "move", -1)
			await _save(st, name, _coach_info(st))
		"13_failure_hint":
			var st := _stage(res, 1, true)
			st.layer.set_options(true, false)
			var dv := _decision_view(false)
			st.hud.update_hud(dv, MusicPulse.new())
			for run in 2:
				var rv := _recording_view()
				rv.phase = SessionPhase.REVIEW
				st.layer.update(rv, [], 0.016)
				st.layer.on_review_result(dv.outcome)
				st.layer.update(dv, [], 0.016)
			for k in 14:
				await process_frame
				st.layer.update(dv, [], 0.016)
			await _save(st, name, "hint='%s' card=%s" % [st.layer.hint_card.text, st.layer.hint_card.card_rect()])


func _complete_line(st: Stage) -> void:
	await _frames(6)
	st.layer.player.input_accept(true)
	st.layer.player.input_accept(false)
	await _frames(12)


## Put a mark on screen directly (deterministic; the lifecycle is tested elsewhere).
func _coach(st: Stage, v: SessionView, snap: FrameSnapshot, mark_id: String, subject_tape: int) -> void:
	st.hud.update_hud(v, MusicPulse.new())
	var e := st.layer.coach
	e.ctx.advance(0.016, v, snap)
	var b := CoachConditions.Binding.new()
	if subject_tape >= 0:
		b.has = true
		b.kind = "self"
		b.tape = subject_tape
	e.current = e.get_mark(mark_id)
	e.subject = b
	e.shown_at = e.ctx.clock
	if e.current == null:
		push_error("shot_dialogue: no coach mark '%s' in %s" % [mark_id, CoachEngine.DEFAULT_PATH])
	await _frames(14)
	st.layer.coach_layer.refresh()


func _coach_info(st: Stage) -> String:
	var cl := st.layer.coach_layer
	var a := cl.anchor_resolved()
	return "'%s' anchor=%s ok=%s rect=%s label=%s" % [cl.label_text(), a.name, a.ok, a.rect, cl.label_rect()]


func _mark_actors(st: Stage, snap: FrameSnapshot, v: SessionView) -> void:
	var w := _w2s(st.res)
	for a: ActorSnap in snap.actors:
		var desynced := not a.synced
		var lbl := "Moxie (live)" if a.tape == v.active else "Tape %s%s" % [OD.TAPE_NAMES[a.tape], " (desynced)" if desynced else ""]
		st.actors.items.append([w.call(Vector2(a.x, a.y)), -1 if a.tape == v.active else a.tape, desynced, lbl])
	st.actors.queue_redraw()


# ───────────────────────────── fake session data ─────────────────────────────

func _level() -> LevelDef:
	var L := LevelDef.new()
	L.id = LEVEL_ID
	L.index = 1
	L.name = "Soft Open"
	L.bpm = 120.0
	L.bars = 8
	L.horizon_bars = 16
	L.max_tapes = 3
	L.speeds = [0.5, 1.0, 2.0]
	L.end_modes = [OD.EndMode.STOP, OD.EndMode.REPEAT]
	L.objective.text = "Break the wall and walk out"
	return L


func _base(phase: StringName, active: int, beat: float) -> SessionView:
	var v := SessionView.new()
	v.phase = phase
	v.level = _level()
	v.active = active
	v.beat = beat
	v.horizon_beats = v.level.horizon_bars * OD.BEATS_PER_BAR
	v.speeds = [0.5, 1.0, 2.0]
	v.end_modes = [OD.EndMode.STOP, OD.EndMode.REPEAT]
	v.objective.text = v.level.objective.text
	v.objective.progress = 0.3
	v.objective.survivors = 1
	for i in 4:
		v.decks[i].status = DeckStatus.UNAVAILABLE if i >= v.level.max_tapes else DeckStatus.EMPTY
	return v


func _committed(d: DeckView, speed: float, beat: float) -> void:
	d.status = DeckStatus.COMMITTED
	d.speed = speed
	d.end_mode = OD.EndMode.STOP
	d.span_bars = 8.0 / speed
	d.life = OD.LifeState.ALIVE
	d.synced = true
	d.local_progress = minf(1.0, beat / (d.span_bars * OD.BEATS_PER_BAR))
	d.transport = 1
	d.reel_rate = speed
	d.marks = [DeckMark.make(40, ActionKind.LIGHT), DeckMark.make(160, ActionKind.HEAVY)]


func _setup_view() -> SessionView:
	var v := _base(SessionPhase.SETUP, 1, 0.0)
	v.actions = [SessionAction.SPEED_UP, SessionAction.SPEED_DOWN, SessionAction.CYCLE_END_MODE, SessionAction.RECORD, SessionAction.QUIT]
	_committed(v.decks[0], 1.0, 0.0)
	v.decks[0].life = -1
	v.decks[0].transport = 0
	var b := v.decks[1]
	b.status = DeckStatus.ARMED
	b.speed = 1.0
	b.end_mode = OD.EndMode.STOP
	b.span_bars = 8.0
	return v


func _recording_view() -> SessionView:
	var beat := 11.0
	var v := _base(SessionPhase.RECORDING, 2, beat)
	v.actions = [SessionAction.QUIT]
	_committed(v.decks[0], 1.0, beat)
	_committed(v.decks[1], 2.0, beat)
	v.decks[1].synced = false
	v.decks[1].state_marks = [DeckStateMark.make(9.0, StateMarkKind.DESYNC)]
	var c := v.decks[2]
	c.status = DeckStatus.RECORDING
	c.speed = 1.0
	c.end_mode = OD.EndMode.STOP
	c.span_bars = 8.0
	c.local_progress = beat / 32.0
	c.transport = 1
	c.reel_rate = 1.0
	c.life = OD.LifeState.ALIVE
	c.marks = [DeckMark.make(60, ActionKind.LIGHT)]
	return v


func _decision_view(win: bool) -> SessionView:
	var v := _recording_view()
	v.phase = SessionPhase.DECISION
	v.beat = 64.0
	v.decks[2].status = DeckStatus.PENDING
	var o := Outcome.new()
	o.win = win
	o.objective_complete = win
	if win:
		o.survivors = [0, 2]
		o.notes = ["Objective complete at beat 40: Break the wall and walk out."]
		v.actions = [SessionAction.RETRY_TAKE, SessionAction.COMMIT, SessionAction.RESET_ALL]
	else:
		o.reason = FailReason.OBJECTIVE
		o.notes = [
			"Tape C's heavy at beat 2.02 hit breakable wall w1 with momentum 4; it needs 5.",
			"Objective not complete: Break the wall and walk out. Not activated: w1.",
		]
		v.actions = [SessionAction.RETRY_TAKE, SessionAction.RESET_ALL]
	v.outcome = o
	return v


func _snap() -> FrameSnapshot:
	var s := FrameSnapshot.new()
	var pos := [Vector2(3.5, 6.0), Vector2(9.0, 3.5), Vector2(14.0, 6.5)]
	for i in 3:
		var a := ActorSnap.new()
		a.tape = i
		a.x = pos[i].x
		a.y = pos[i].y
		a.synced = i != 1
		a.live = i == 2
		s.actors.append(a)
	return s
