extends ODTest
## The overlay nodes end to end: DialogueLayer + DialoguePlayer + DialogueBox (portraits, fallback
## initial, no-jump portrait frame, layout from 720p to 4K, input, skip, phase gating), barks (never
## over the ruler, off switch), coach marks anchored to a fake HUD (node-name fallback, groups,
## coach_anchor_rect hook, world callable) and the failure hint card.

const FIX := "res://tests/ui_dialogue/fixtures/"

var layer: DialogueLayer = null
var hud: Control = null
var finished: Array = []


func before_each() -> void:
	finished.clear()
	hud = _fake_hud(Vector2(1600, 900))
	tree().root.add_child(hud)
	layer = DialogueLayer.new()
	layer.autoload_data = false
	tree().root.add_child(layer)
	if not layer.is_node_ready():
		await tree().process_frame
	layer.set_anchors_preset(Control.PRESET_TOP_LEFT)
	layer.position = Vector2.ZERO
	layer.size = Vector2(1600, 900)
	var dirs: Array[String] = [FIX + "portraits"]
	layer.portraits = DlgPortraits.new(dirs)
	layer.use_data(DlgStoryData.load_file(FIX + "story_sample.json"), CoachEngine.load_file(FIX + "coachmarks_sample.json"), DlgFailureHints.load_file(FIX + "failure_hints_sample.json"))
	layer.setup(hud, _w2s)
	layer.dialogue_finished.connect(func(k: StringName, key: String, s: bool) -> void: finished.append([k, key, s]))
	layer.begin_level("t-one")


func after_each() -> void:
	for n: Node in [layer, hud]:
		if n != null:
			n.queue_free()
	layer = null
	hud = null
	await tree().process_frame


func _fake_hud(sz: Vector2) -> Control:
	var h := Control.new()
	h.name = "FakeHud"
	h.size = sz
	var ruler := Control.new()
	ruler.name = "Ruler"
	ruler.position = Vector2(0, sz.y - 120)
	ruler.size = Vector2(sz.x, 40)
	h.add_child(ruler)
	for i in 4:
		var d := Control.new()
		d.name = "Deck" + OD.TAPE_NAMES[i]
		d.position = Vector2(40 + i * 300, sz.y - 80)
		d.size = Vector2(280, 70)
		h.add_child(d)
	var dec := Control.new()
	dec.name = "Decision"
	dec.position = Vector2(sz.x * 0.5 - 200, sz.y * 0.4)
	dec.size = Vector2(400, 160)
	h.add_child(dec)
	var commit := Control.new()
	commit.name = "CommitButton"
	commit.position = Vector2(20, 100)
	commit.size = Vector2(160, 40)
	commit.add_to_group("prompt_commit")
	dec.add_child(commit)
	return h


func _view(phase: StringName, active: int = 0) -> SessionView:
	var v := SessionView.new()
	v.phase = phase
	v.active = active
	for d: DeckView in v.decks:
		d.status = DeckStatus.EMPTY
	if active >= 0:
		v.decks[active].status = DeckStatus.ARMED
	return v


## The game's world -> screen mapping: tiles to pixels, null (off screen) beyond x = 150.
static func _w2s(p: Vector2) -> Variant:
	if p.x > 150.0:
		return null
	return Vector2(100, 100) + p * 10.0


func _snap(actors: Array) -> FrameSnapshot:
	var s := FrameSnapshot.new()
	for a: Variant in actors:
		var d: Array = a
		var act := ActorSnap.new()
		act.tape = int(d[0])
		act.x = float(d[1])
		act.y = float(d[2])
		s.actors.append(act)
	return s


func _step(v: SessionView, seconds: float, evs: Array[SimEvent] = [], snap: FrameSnapshot = null) -> void:
	var t := 0.0
	var first := true
	var none: Array[SimEvent] = []
	while t < seconds:
		layer.update(v, evs if first else none, 1.0 / 30.0, snap)
		layer.player._process(1.0 / 30.0)
		layer.barks._process(1.0 / 30.0)
		layer.coach_layer._process(1.0 / 30.0)
		layer.hint_card._process(1.0 / 30.0)
		first = false
		t += 1.0 / 30.0


func test_intro_plays_with_portraits_and_fallback() -> void:
	assert_true(layer.play_intro("t-one"), "intro queued")
	assert_true(layer.is_dialogue_open() and layer.is_blocking())
	var box := layer.player.box
	assert_true(box.visible)
	assert_eq(box.speaker_name, "Opal")
	assert_true(box.portrait.is_fallback(), "no Opal art -> coloured initial")
	assert_eq(box.portrait.initial, "O")
	assert_false(box.portrait_left, "Opal on the right")
	var pr_opal := box.portrait_rect()
	layer.player.input_accept(true) # guarded: line just started
	layer.player.input_accept(false)
	_step(_view(SessionPhase.BRIEFING), 0.2)
	layer.player.input_accept(true)
	layer.player.input_accept(false)
	assert_true(layer.player.runner.is_waiting(), "accept completes the line")
	_step(_view(SessionPhase.BRIEFING), 0.1)
	layer.player.input_accept(true)
	layer.player.input_accept(false)
	assert_eq(box.speaker_name, "Moxie")
	assert_false(box.portrait.is_fallback(), "Moxie's grin from the fixture dir")
	assert_true(box.portrait_left, "Moxie on the left")
	assert_false(box.portrait.flip, "never mirrored (INTEGRATION.md: her face paint is asymmetric)")
	var pr_grin := box.portrait_rect()
	_step(_view(SessionPhase.BRIEFING), 2.0)
	layer.player.input_accept(true)
	layer.player.input_accept(false)
	assert_eq(box.text_label.text, "Back by dinner.")
	assert_false(box.portrait.is_fallback(), "smug missing -> neutral fallback texture")
	assert_eq(box.portrait_rect(), pr_grin, "expression swap: the portrait frame does not move")
	assert_eq(pr_opal.size, pr_grin.size, "same frame size on both sides")
	_step(_view(SessionPhase.BRIEFING), 2.0)
	layer.player.input_accept(true)
	layer.player.input_accept(false)
	assert_eq(finished, [[DialoguePlayer.KIND_INTRO, "t-one", false]])
	assert_false(layer.is_blocking())
	assert_false(layer.play_intro("t-one"), "intro only on the first visit")


func test_skip_all_and_hold_skip() -> void:
	layer.play_intro("t-one")
	layer.player.input_skip_now()
	assert_eq(finished, [[DialoguePlayer.KIND_INTRO, "t-one", true]], "skip-all ends the sequence")
	layer.play_outro("t-one")
	layer.player.input_skip(true)
	_step(_view(SessionPhase.RESULTS), 1.0)
	assert_eq(finished.size(), 2, "holding cancel skips")
	assert_eq(finished[1][2], true)


func test_never_opens_during_take_and_closes_if_one_starts() -> void:
	_step(_view(SessionPhase.RECORDING), 0.1)
	layer.play_lines(DlgLine.list_from([{"who": "moxie", "expression": "neutral", "line": "Hi."}]), DialoguePlayer.KIND_OTHER, "x")
	assert_false(layer.is_dialogue_open(), "queued, not opened, during recording")
	assert_true(layer.is_blocking(), "but pending")
	_step(_view(SessionPhase.REVIEW), 0.2)
	assert_false(layer.is_dialogue_open(), "not during review either")
	_step(_view(SessionPhase.DECISION), 0.1)
	assert_true(layer.is_dialogue_open(), "opens at the decision screen")
	_step(_view(SessionPhase.COUNTIN), 0.1)
	assert_false(layer.is_dialogue_open(), "a count-in closes it at once")
	assert_eq(finished, [[DialoguePlayer.KIND_OTHER, "x", true]])


func test_first_death_queued_for_decision() -> void:
	_step(_view(SessionPhase.RECORDING, 0), 0.1)
	var evs: Array[SimEvent] = [SimEvent.make(0, SimEventType.SELF_DEATH, 0, 0).with_tape(0).with_detail("strike")]
	_step(_view(SessionPhase.RECORDING, 0), 0.1, evs)
	assert_false(layer.is_dialogue_open(), "never during the take")
	assert_false(layer.barks.is_showing(), "the first replaces the bark")
	_step(_view(SessionPhase.REVIEW, 0), 0.1)
	_step(_view(SessionPhase.DECISION, 0), 0.1)
	assert_true(layer.is_dialogue_open())
	assert_eq(layer.player.box.text_label.text, "That one got me.", "level firstDeath")
	assert_true(layer.seen.has("once.firstDeath"))


func test_layout_scales_720p_to_4k() -> void:
	for sz: Vector2 in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(3840, 2160)]:
		layer.size = sz
		layer.play_lines(DlgLine.list_from([{"who": "opal", "expression": "dry", "line": "Radio check. If you can hear me, you still owe me for the headphones."}]))
		_step(_view(SessionPhase.SETUP), 0.05)
		var box := layer.player.box
		box._layout()
		var screen := Rect2(Vector2.ZERO, sz)
		var b := box.box_rect()
		assert_true(screen.encloses(b), "%s: box on screen" % sz)
		assert_true(screen.encloses(box.portrait_rect()), "%s: portrait on screen" % sz)
		assert_true(b.encloses(box.text_rect()), "%s: text inside the box" % sz)
		assert_true(b.size.y < sz.y * 0.25, "%s: box leaves the world visible" % sz)
		var fs := box.text_label.get_theme_font_size("font_size")
		var lines := box.text_label.get_line_count()
		assert_true(lines <= 2, "%s: a 71-char line fits in two lines (%d)" % [sz, lines])
		assert_true(fs >= 16, "%s: readable font (%d)" % [sz, fs])
		layer.player.skip_all(true)
	assert_true(UiPalette.unit_for(Vector2(3840, 2160)) > UiPalette.unit_for(Vector2(1280, 720)) * 1.8, "scales with resolution")


func test_bark_shows_near_deck_and_avoids_ruler() -> void:
	_step(_view(SessionPhase.CINEMATIC, 1), 0.1)
	assert_true(layer.barks.is_showing(), "win bark on entering the cinematic")
	_step(_view(SessionPhase.CINEMATIC, 1), 0.3)
	var ruler := Rect2(0, 780, 1600, 40)
	var r := layer.barks.bubble_rect()
	assert_false(r.intersects(ruler), "bark bubble never covers the ruler (%s)" % r)
	assert_true(r.end.y <= 780.0 + 0.5, "it sits above the dock")
	assert_true(absf(r.get_center().x - (340.0 + 140.0)) < 400.0, "near tape B's deck")
	layer.set_options(false, true)
	assert_false(layer.barks.is_showing(), "turning barks off clears the toast")
	assert_false(layer.bark("loot", true), "and no more barks")


func test_bark_over_head_uses_world_anchor() -> void:
	layer.barks_over_head = true
	var snap := _snap([[0, 70.0, 30.0]]) # -> screen (800, 400)
	_step(_view(SessionPhase.RESULTS, 0), 0.05, [], snap)
	assert_true(layer.bark("loot", true))
	_step(_view(SessionPhase.RESULTS, 0), 0.3, [], snap)
	var r := layer.barks.bubble_rect()
	assert_true(r.end.y <= 400.0 and absf(r.get_center().x - 800.0) < 250.0, "above Moxie's head (%s)" % r)


func test_coach_mark_anchored_to_hud_and_suppressed_by_dialogue() -> void:
	_step(_view(SessionPhase.SETUP, 0), 0.2)
	assert_eq(layer.coach.current.id if layer.coach.current != null else "", "deck-armed")
	layer.coach_layer.refresh()
	var a := layer.coach_layer.anchor_resolved()
	assert_true(a.ok and a.kind == "hud")
	assert_eq(a.rect, Rect2(40, 820, 280, 70), "deck:active resolved to DeckA by node name")
	assert_eq(a.tape, 0, "edge colour: tape A")
	var lr := layer.coach_layer.label_rect()
	assert_false(lr.intersects(Rect2(0, 780, 1600, 40)), "label clear of the ruler (%s)" % lr)
	for i in 4:
		assert_false(lr.intersects(Rect2(40 + i * 300, 820, 280, 70)), "label clear of deck %d" % i)
	assert_true(layer.coach_layer.label_text().begins_with("This cassette is your take."))
	assert_false(layer.barks.is_showing())
	assert_false(layer.bark("countIn"), "no bark starts while a mark is visible")
	layer.play_lines(DlgLine.list_from([{"who": "moxie", "expression": "neutral", "line": "Hi."}]))
	_step(_view(SessionPhase.SETUP, 0), 0.1)
	assert_true(layer.coach.current == null, "coach marks give way to dialogue")


func test_coach_unresolved_anchor_uses_coach_slot() -> void:
	var v := _view(SessionPhase.RECORDING, 0)
	_step(v, 2.3)
	assert_eq(layer.coach.current.id if layer.coach.current != null else "", "move")
	layer.coach_layer.refresh()
	assert_false(layer.coach_layer.anchor_resolved().ok, "the fake HUD has no move prompt")
	var lr := layer.coach_layer.label_rect()
	assert_true(lr.end.y <= 780.0 + 0.5, "the coach slot sits just above the dock (%s)" % lr)
	assert_true(absf(lr.get_center().x - 800.0) < 2.0, "centred")
	assert_true(layer.coach_layer.label_text().contains("Move"), "the {btn:move} token falls back to a readable name")


func test_anchor_resolution_forms() -> void:
	var an := layer.anchors
	var v := _view(SessionPhase.RECORDING, 2)
	var snap := _snap([[2, 2.0, 3.0], [0, 60.0, 1.0]])
	var en := EnemySnap.new()
	en.id = "g1"
	en.x = 4.0
	en.y = 4.0
	en.alive = true
	snap.enemies = [en]
	_step(v, 0.05, [], snap)
	var ctx := layer.coach.ctx
	var space := layer.coach_layer
	assert_eq(an.resolve("deck:active", space, ctx).rect, Rect2(640, 820, 280, 70), "active = tape C")
	assert_eq(an.resolve("prompt:commit", space, ctx).rect, Rect2(620, 460, 160, 40), "group prompt_commit")
	assert_eq(an.resolve("Decision/CommitButton", space, ctx).rect, Rect2(620, 460, 160, 40), "node path")
	var w := an.resolve("world:self", space, ctx)
	assert_true(w.ok and w.kind == "world" and w.tape == 2)
	assert_true(w.rect.has_point(Vector2(120, 130)), "live self through the callable (%s)" % w.rect)
	assert_true(an.resolve("world:self:0", space, ctx).rect.has_point(Vector2(700, 110)))
	assert_true(an.resolve("world:entity:g1", space, ctx).rect.has_point(Vector2(140, 140)))
	assert_true(an.resolve("world:nearest:enemy", space, ctx).rect.has_point(Vector2(140, 140)))
	var subj := CoachConditions.Binding.new()
	subj.has = true
	subj.tape = 0
	subj.pos = Vector2(1, 1)
	subj.has_pos = true
	assert_true(an.resolve("world:event", space, ctx, subj).rect.has_point(Vector2(110, 110)))
	assert_eq(an.resolve("deck:subject", space, ctx, subj).rect, Rect2(40, 820, 280, 70))
	assert_false(an.resolve("deck:subject", space, ctx, null).ok, "no subject -> unresolved")
	assert_false(an.resolve("world:entity:door_9", space, ctx).ok, "unknown entity -> unresolved")
	var off := _snap([[2, 200.0, 3.0]])
	_step(v, 0.05, [], off)
	assert_false(an.resolve("world:self", space, ctx).ok, "callable returned null (off screen) -> unresolved")
	assert_false(an.resolve("nowhere", space, ctx).ok)
	var hook := HookHud.new()
	hook.size = Vector2(1600, 900)
	tree().root.add_child(hook)
	an.hud_root = hook
	assert_eq(an.resolve("ruler", space, ctx).rect, Rect2(10, 20, 30, 40), "coach_anchor_rect(group) hook")
	assert_eq(an.resolve("deck:active", space, ctx).rect, Rect2(1, 2, 3, 4), "anchor_rect(anchor, subject) hook wins, active substituted")
	hook.queue_free()
	an.hud_root = hud


class HookHud:
	extends Control
	func anchor_rect(anchor: String, _subject: Dictionary) -> Rect2:
		return Rect2(1, 2, 3, 4) if anchor == "deck:2" else Rect2()
	func coach_anchor_rect(n: StringName) -> Rect2:
		return Rect2(10, 20, 30, 40) if n == &"ruler" else Rect2()


const WALL := "Tape B's heavy at beat 2.02 hit breakable wall w1 with momentum 4; it needs 5."
const OBJ := "Objective not complete: Break the wall. Not activated: w1."


func _fail(notes: Array) -> Outcome:
	var o := Outcome.new()
	o.win = false
	o.reason = FailReason.OBJECTIVE
	for n: Variant in notes:
		o.notes.append(str(n))
	return o


func test_failure_hint_after_second_identical_failure() -> void:
	var o := _fail([WALL, OBJ])
	for run in 2:
		_step(_view(SessionPhase.REVIEW, 1), 0.1)
		layer.on_review_result(o)
		var dv := _view(SessionPhase.DECISION, 1)
		dv.outcome = o
		_step(dv, 0.4)
		if run == 0:
			assert_false(layer.hint_card.is_showing(), "no hint after the first failure")
	assert_true(layer.hint_card.is_showing(), "hint after the second identical failure")
	assert_eq(layer.hint_card.text, "Still bouncing off. Stack swing, run-up and tape speed.")
	assert_true(layer.seen.has("hint.weak.breakable"))
	var cr := layer.hint_card.card_rect()
	assert_true(Rect2(Vector2.ZERO, Vector2(1600, 900)).encloses(cr), "card on screen")
	assert_false(cr.intersects(Rect2(0, 780, 1600, 40)), "card clear of the ruler")
	_step(_view(SessionPhase.SETUP, 1), 0.1)
	assert_false(layer.hint_card.is_showing(), "only on the decision screen")


func test_failure_hint_from_view_outcome_without_explicit_result() -> void:
	var o := _fail([WALL])
	for run in 2:
		var rv := _view(SessionPhase.REVIEW, 1)
		rv.outcome = o
		_step(rv, 0.1)
		var dv := _view(SessionPhase.DECISION, 1)
		dv.outcome = o
		_step(dv, 0.3)
	assert_true(layer.hint_card.is_showing(), "read view.outcome when review ended")


func test_seen_flags_roundtrip_and_settings() -> void:
	var fired := [0]
	layer.seen_changed.connect(func() -> void: fired[0] += 1)
	layer.play_intro("t-one")
	assert_true(fired[0] >= 1, "seen_changed when a story flag is set")
	assert_has(layer.get_seen_flags(), "story.t-one.intro")
	layer.set_seen_flags(["coach.deck_intro", "story.t-one.intro"])
	assert_eq(layer.get_seen_flags(), ["coach.deck_intro", "story.t-one.intro"])
	layer.set_options(true, false)
	layer.player.skip_all(true)
	_step(_view(SessionPhase.SETUP, 0), 1.0)
	assert_true(layer.coach.current == null, "coach marks off in settings")


func test_ending_has_one_cut() -> void:
	var cuts := [0]
	layer.player.runner.cut_started.connect(func(_i: int) -> void: cuts[0] += 1)
	assert_true(layer.play_ending())
	for i in 40:
		layer.player.input_accept(true)
		layer.player.input_accept(false)
		layer.player._process(0.5)
	assert_eq(cuts[0], 1, "one fade between line 6 and line 7")
	assert_eq(finished.size(), 1)
	assert_eq(finished[0][0], DialoguePlayer.KIND_ENDING)
	assert_false(layer.play_ending(), "once per save")
