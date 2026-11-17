extends ODTest
## Coach marks (docs/ONBOARDING.md): the condition language (CoachConditions over a CoachContext),
## the lifecycle (CoachEngine: skip, dismiss, linger, minShown, gap, phase budget, urgent
## pre-emption, once / per-visit, dialogue and bark gating, seen persistence, disable) and bubble
## placement (CoachLayout). Pure logic, no nodes.

const FIX := "res://tests/ui_dialogue/fixtures/"
const DT := 1.0 / 30.0

var _no_ev: Array[SimEvent] = []
var _no_r: Array[Rect2] = []


func _view(phase: StringName, active: int = 0) -> SessionView:
	var v := SessionView.new()
	v.phase = phase
	v.active = active
	for d: DeckView in v.decks:
		d.status = DeckStatus.EMPTY
	if active >= 0:
		v.decks[active].status = DeckStatus.ARMED
		v.decks[active].speed = 1.0
		v.decks[active].end_mode = OD.EndMode.STOP
		v.decks[active].life = OD.LifeState.ALIVE
	return v


func _ctx(v: SessionView, store: DlgSeenStore = null) -> CoachContext:
	var c := CoachContext.new()
	c.seen = store if store != null else DlgSeenStore.new()
	c.begin_level("t-one")
	c.advance(0.0, v)
	return c


func _ev(type: StringName, tape: int = 0, detail: String = "", id: String = "", x: float = 0.0, y: float = 0.0) -> SimEvent:
	return SimEvent.make(0, type, x, y).with_tape(tape).with_detail(detail).with_id(id)


func _actor(tape: int, x: float, y: float, life: int = OD.LifeState.ALIVE, synced: bool = true) -> ActorSnap:
	var a := ActorSnap.new()
	a.tape = tape
	a.x = x
	a.y = y
	a.life = life
	a.synced = synced
	return a


func _eval(cond: Variant, c: CoachContext, shown_at: float = 0.0) -> bool:
	return CoachConditions.eval(cond, c, shown_at)


# ───────────────────────────── conditions ─────────────────────────────

func test_conditions_session_state() -> void:
	var v := _view(SessionPhase.SETUP, 1)
	v.decks[0].status = DeckStatus.COMMITTED
	v.decks[1].speed = 2.0
	v.speeds = [0.5, 1.0, 2.0]
	v.end_modes = [OD.EndMode.STOP, OD.EndMode.REPEAT]
	v.beat = 3.0
	var c := _ctx(v)
	c.levels_cleared = 2
	assert_true(_eval({"phaseIs": "setup"}, c))
	assert_true(_eval({"phaseIs": ["decision", "setup"]}, c))
	assert_false(_eval({"phaseIs": "recording"}, c))
	assert_true(_eval({"firstTimePhase": "setup"}, c), "first visit to setup in this save")
	assert_false(_eval({"firstTimePhase": "decision"}, c), "only the current phase")
	assert_true(_eval({"phaseElapsed": {"min": 0}}, c))
	assert_true(_eval({"beat": {"min": 2, "max": 4}}, c))
	assert_true(_eval({"tapesCommitted": 1}, c), "N exact")
	assert_false(_eval({"tapesCommitted": 2}, c))
	assert_true(_eval({"tapesCommitted": {"min": 1}}, c), "N range")
	assert_true(_eval({"deckStatusIs": {"deck": 0, "status": "committed"}}, c))
	assert_true(_eval({"deckStatusIs": {"deck": "active", "status": "armed"}}, c))
	assert_true(_eval({"deckStatusIs": {"deck": "any", "status": "armed"}}, c))
	assert_false(_eval({"deckStatusIs": {"deck": 3, "status": "armed"}}, c))
	assert_true(_eval({"speedsOffered": {"min": 2}}, c))
	assert_true(_eval({"activeSpeedIs": 2}, c))
	assert_true(_eval({"endModesOffered": 2}, c))
	assert_true(_eval({"activeEndModeIs": "stop"}, c))
	assert_false(_eval({"activeEndModeIs": "repeat"}, c))
	assert_true(_eval({"outcomeIs": "none"}, c))
	assert_true(_eval({"levelsCleared": {"min": 1}}, c))
	assert_true(_eval({"takeProgress": {"min": 0}}, c) == false, "no recording deck -> false")
	assert_true(_eval({"all": [{"phaseIs": "setup"}, {"not": {"phaseIs": "review"}}]}, c))
	assert_true(_eval({"any": [{"phaseIs": "review"}, {"tapesCommitted": 1}]}, c))
	assert_false(_eval({"bogus": 1}, c), "unknown predicate is false")
	var o := Outcome.new()
	o.win = false
	v.outcome = o
	assert_true(_eval({"outcomeIs": "fail"}, c))
	# second visit to setup in the same save
	var store := c.seen
	var c2 := _ctx(_view(SessionPhase.SETUP, 0), store)
	assert_false(_eval({"firstTimePhase": "setup"}, c2), "phase.setup is remembered in the seen store")


func test_conditions_history_and_scopes() -> void:
	var v := _view(SessionPhase.COUNTIN, 1)
	v.decks[0].status = DeckStatus.COMMITTED
	var c := _ctx(v)
	c.advance(0.5, _view_rec(v))
	var evs: Array[SimEvent] = [_ev(SimEventType.DESYNC, 0, "wall", "", 4.0, 5.0), _ev(SimEventType.HIT, 1)]
	c.add_events(evs)
	c.add_input(&"move")
	c.add_action(SessionAction.SPEED_UP)
	var b := CoachConditions.Binding.new()
	assert_true(CoachConditions.eval({"eventSeen": {"type": "desync", "tape": "previous"}}, c, 0.0, b))
	assert_true(b.has and b.kind == "event" and b.tape == 0, "the event binds the subject")
	assert_eq(b.pos, Vector2(4, 5))
	assert_false(_eval({"eventSeen": {"type": "desync", "tape": "live"}}, c))
	assert_true(_eval({"eventSeen": {"type": "hit", "tape": "live"}}, c))
	assert_true(_eval({"eventSeen": {"type": "desync", "detailPrefix": "wa"}}, c))
	assert_true(_eval({"eventSeen": {"type": "desync", "detailIn": ["door", "wall"]}}, c))
	assert_false(_eval({"eventSeen": {"type": "desync", "detail": "door"}}, c))
	assert_false(_eval({"eventSeen": {"type": "hit", "count": 2}}, c), "count = at least")
	var nb := CoachConditions.Binding.new()
	assert_false(CoachConditions.eval({"not": {"eventSeen": {"type": "desync"}}}, c, 0.0, nb))
	assert_false(nb.has, "never binds under not")
	assert_true(_eval({"inputUsed": {"input": "move"}}, c))
	assert_true(_eval({"inputUsed": {"input": "any"}}, c))
	assert_false(_eval({"inputUsed": {"input": "light"}}, c))
	assert_true(_eval({"sessionActionUsed": {"action": ["speedUp", "speedDown"]}}, c))
	c.advance(1.2, _view_rec(v))
	assert_true(_eval({"inputNotUsedFor": {"input": "light", "seconds": 1.0}}, c), "never used this visit")
	assert_false(_eval({"inputNotUsedFor": {"input": "move", "seconds": 1.5}}, c), "move used 1.2 s ago")
	assert_true(_eval({"shownFor": {"min": 1.0}}, c, c.clock - 1.1))
	assert_false(_eval({"sessionActionUsed": {"action": "speedUp", "scope": "shown"}}, c, c.clock - 0.1), "scope shown")
	# leave recording: phase-scoped history starts over, take-scoped history does not
	c.advance(0.1, _view_phase(v, SessionPhase.REVIEW))
	assert_false(_eval({"eventSeen": {"type": "desync"}}, c), "a new phase visit")
	assert_true(_eval({"eventSeen": {"type": "desync", "scope": "take"}}, c), "the take began at the count-in")
	assert_false(_eval({"inputNotUsedFor": {"input": "move", "seconds": 0}}, c), "only during recording")
	# retries
	c.add_action(SessionAction.RETRY_TAKE)
	c.add_action(SessionAction.RETRY_TAKE)
	assert_true(_eval({"retriesThisTake": 2}, c))
	c.add_action(SessionAction.COMMIT)
	assert_true(_eval({"retriesThisTake": 0}, c), "commit resets")
	c.advance(0.1, _view_phase(v, SessionPhase.REVIEW))
	c.add_action(SessionAction.RESET_ALL)
	assert_false(_eval({"sessionActionUsed": {"action": "commit", "scope": "attempt"}}, c), "resetAll starts a new attempt")
	assert_true(_eval({"sessionActionUsed": {"action": "commit", "scope": "level"}}, c))


func _view_rec(base: SessionView) -> SessionView:
	return _view_phase(base, SessionPhase.RECORDING)


func _view_phase(base: SessionView, phase: StringName) -> SessionView:
	var v := base.copy()
	v.phase = phase
	return v


func test_conditions_save_facts_persist() -> void:
	var store := DlgSeenStore.new()
	var c := _ctx(_view(SessionPhase.SETUP, 0), store)
	var cond := {"sessionActionUsed": {"action": ["speedUp", "speedDown"], "scope": "save"}}
	assert_false(_eval(cond, c))
	c.add_action(SessionAction.SPEED_DOWN)
	assert_true(_eval(cond, c))
	assert_true(store.has(CoachConditions.fact_key("sessionActionUsed", cond["sessionActionUsed"])), "stored as a fact")
	var c2 := _ctx(_view(SessionPhase.SETUP, 0), store)
	assert_true(_eval(cond, c2), "true in a later level / session from the save")


func test_conditions_selves_and_world() -> void:
	var v := _view(SessionPhase.RECORDING, 1)
	v.decks[0].status = DeckStatus.COMMITTED
	v.beat = 6.0
	var snap := FrameSnapshot.new()
	snap.actors = [_actor(0, 2.0, 2.0, OD.LifeState.ALIVE, false), _actor(1, 5.0, 5.0, OD.LifeState.REC_GHOST)]
	var en := EnemySnap.new()
	en.id = "g1"
	en.x = 6.0
	en.y = 5.0
	en.alive = true
	snap.enemies = [en]
	var c := CoachContext.new()
	c.seen = DlgSeenStore.new()
	c.begin_level("t-one")
	c.advance(0.0, v, snap)
	assert_true(_eval({"liveSelfIs": "recGhost"}, c))
	assert_false(_eval({"liveSelfIs": "alive"}, c))
	var b := CoachConditions.Binding.new()
	assert_true(CoachConditions.eval({"selfIs": {"who": "previous", "state": "desynced"}}, c, 0.0, b))
	assert_true(b.has and b.kind == "self" and b.tape == 0)
	assert_false(_eval({"selfIs": {"who": 0, "state": "alive"}}, c), "desynced is not alive")
	assert_true(_eval({"liveSelfNear": {"kind": "enemy", "tiles": 1.5}}, c))
	assert_false(_eval({"liveSelfNear": {"kind": "enemy", "tiles": 0.5}}, c))
	assert_eq(CoachWorld.entity_pos(c, "g1"), Vector2(6, 5))
	assert_eq(CoachWorld.target_kind(c, "g1"), "enemy")
	# selfFateChanged: dead (a committed tape died this visit, no death mark from the last run)
	var deaths: Array[SimEvent] = [_ev(SimEventType.SELF_DEATH, 0)]
	c.add_events(deaths)
	assert_true(_eval({"selfFateChanged": {"who": "previous", "to": "dead"}}, c))
	# alive: the last run had a death at beat 4, now it is beat 6 and the tape lives
	v.decks[0].state_marks = [DeckStateMark.make(4.0, StateMarkKind.DEATH)]
	snap.actors[0].synced = true
	assert_true(_eval({"selfFateChanged": {"who": 0, "to": "alive"}}, c))
	assert_false(_eval({"selfFateChanged": {"who": 0, "to": "dead"}}, c), "it has a death mark")
	# travel: the live self walks 3 tiles
	for i in 6:
		snap.actors[1].x += 0.5
		c.advance(0.1, v, snap)
	assert_true(_eval({"liveSelfTravelled": {"tiles": 2.9}}, c))
	assert_false(_eval({"liveSelfTravelled": {"tiles": 3.5}}, c))
	assert_false(_eval({"liveSelfTravelled": {"tiles": 1.0, "scope": "shown"}}, c, c.clock), "nothing since it was shown")


func test_validate_conditions_and_fixture() -> void:
	assert_eq(CoachConditions.validate({"all": [{"phaseIs": "setup"}, {"wat": 1}]}, "m"), ["m: unknown condition 'wat'"])
	assert_eq(CoachConditions.validate({"any": {"phaseIs": "setup"}}, "m"), ["m: 'any' needs a list"])
	var e := CoachEngine.load_file(FIX + "coachmarks_sample.json")
	assert_eq(e.marks.size(), 7)
	assert_eq(e.validate(), [], "fixture marks are valid")
	assert_true(e.get_mark("desync").urgent)
	assert_false(e.get_mark("ruler-lane").once)
	assert_eq(e.get_mark("deck-armed").linger, 30.0)
	assert_eq(e.limit("minGapSeconds"), 1.5)
	var want_phases: Array[String] = ["countin"]
	assert_eq(e.get_mark("count-in").phases, want_phases)


func test_real_coachmarks_validate_if_present() -> void:
	if not FileAccess.file_exists(CoachEngine.DEFAULT_PATH):
		assert_true(true, "no coachmarks.json yet")
		return
	var e := CoachEngine.load_file()
	assert_true(e.marks.size() > 0, "coachmarks.json has marks: %s" % [e.errors])
	var problems := e.validate()
	for p: String in problems:
		print("  coachmarks.json: ", p)
	assert_eq(problems, [], "data/onboarding/coachmarks.json uses only known conditions")
	# every anchor resolves to a known form
	var bad: Array[String] = []
	for m: CoachMarkDef in e.marks:
		if not m.anchor.begins_with("world:") and CoachAnchors.group_name(m.anchor, 0, _subj(1)) == "":
			bad.append(m.id + ": " + m.anchor)
	assert_eq(bad, [], "every HUD anchor maps to a group name")


func _subj(tape: int) -> CoachConditions.Binding:
	var b := CoachConditions.Binding.new()
	b.has = true
	b.tape = tape
	return b


# ───────────────────────────── engine ─────────────────────────────

func _engine(level_id: String = "t-one") -> CoachEngine:
	var e := CoachEngine.load_file(FIX + "coachmarks_sample.json")
	e.seen = DlgSeenStore.new()
	e.begin_level(level_id)
	return e


func _run(e: CoachEngine, v: SessionView, seconds: float, evs: Array[SimEvent] = [], snap: FrameSnapshot = null) -> void:
	var t := 0.0
	var first := true
	while t < seconds - 1e-6:
		e.update(DT, v, evs if first else _no_ev, snap)
		first = false
		t += DT


func _cur(e: CoachEngine) -> String:
	return e.current.id if e.current != null else ""


func test_engine_show_dismiss_gap_and_once() -> void:
	var e := _engine()
	var log: Array[String] = []
	e.shown.connect(func(m: CoachMarkDef) -> void: log.append("show " + m.id))
	e.hidden.connect(func(m: CoachMarkDef, reason: String, done: bool) -> void: log.append("%s %s %s" % ["done" if done else "hide", m.id, reason]))
	var v := _view(SessionPhase.SETUP, 0)
	v.speeds = [1.0, 2.0]
	e.update(DT, v)
	assert_eq(_cur(e), "deck-armed", "first in file order whose trigger holds")
	_run(e, v, 0.5)
	e.note_action(SessionAction.RECORD)
	e.update(DT, v)
	assert_eq(_cur(e), "", "dismissOn met: retired by the player")
	assert_true(e.seen.has("coach.deck-armed"), "once: stored in the save")
	_run(e, v, 1.0)
	assert_eq(_cur(e), "", "minGapSeconds between marks")
	_run(e, v, 0.6)
	assert_eq(_cur(e), "speed-pick", "then the next eligible mark")
	e.note_action(SessionAction.SPEED_UP)
	e.update(DT, v)
	assert_eq(log, ["show deck-armed", "done deck-armed player", "show speed-pick", "done speed-pick player"])
	_run(e, v, 3.0)
	assert_eq(_cur(e), "", "a done mark never returns")


func test_engine_budget_linger_and_min_shown() -> void:
	var e := _engine()
	var v := _view(SessionPhase.SETUP, 0)
	v.speeds = [1.0, 2.0]
	e.update(DT, v)
	assert_eq(_cur(e), "deck-armed")
	# leave the phase after 0.5 s: shown less than minShownSecondsToCount -> back to unseen
	_run(e, v, 0.5)
	e.update(DT, _view(SessionPhase.BRIEFING, 0))
	assert_eq(_cur(e), "")
	assert_false(e.seen.has("coach.deck-armed"), "not counted: it may show again")
	_run(e, v, 1.7)
	assert_eq(_cur(e), "speed-pick", "a new setup visit; deck-armed needs a first visit, speed-pick shows")
	_run(e, v, 10.1)
	assert_eq(_cur(e), "", "faded by defaultLingerSeconds")
	assert_true(e.seen.has("coach.speed-pick"), "up long enough: spent even though the player did nothing")


func test_engine_phase_budget() -> void:
	var e := _engine()
	e.limits["maxPerPhaseVisit"] = 1
	var v := _view(SessionPhase.SETUP, 0)
	v.speeds = [1.0, 2.0]
	e.update(DT, v)
	e.note_action(SessionAction.RECORD)
	_run(e, v, 3.0)
	assert_eq(_cur(e), "", "the phase-visit budget is spent")
	e.update(DT, _view(SessionPhase.DECISION, 0))
	_run(e, v, 2.0)
	assert_eq(_cur(e), "speed-pick", "a new visit, a new budget")


func test_engine_urgent_preempts_and_binds_subject() -> void:
	var e := _engine()
	var v := _view(SessionPhase.RECORDING, 1)
	v.decks[0].status = DeckStatus.COMMITTED
	var snap := FrameSnapshot.new()
	snap.actors = [_actor(0, 2.0, 2.0, OD.LifeState.ALIVE, false), _actor(1, 5.0, 5.0)]
	_run(e, v, 2.2, [], snap)
	assert_eq(_cur(e), "move", "inputNotUsedFor move 2 s")
	var evs: Array[SimEvent] = [_ev(SimEventType.DESYNC, 0, "wall", "", 2.0, 2.0)]
	e.update(DT, v, evs, snap)
	assert_eq(_cur(e), "desync", "an urgent mark pre-empts at once, no gap")
	assert_true(e.subject.has and e.subject.tape == 0, "subject: the desynced tape")
	assert_false(e.seen.has("coach.move"), "pre-empted under 1.5 s: may show again")
	assert_eq(CoachLayer.substitute(e.current.text, {}, e.ctx, e.subject), "Tape A is skipping. That outline is only the recording.")
	assert_has(e.shown_this_take, "desync", "for bark suppression")
	var evs2: Array[SimEvent] = [_ev(SimEventType.RESYNC, 0)]
	_run(e, v, 0.3, evs2, snap)
	assert_eq(_cur(e), "", "dismissed by the resync")


func test_engine_skip_if_dialogue_bark_and_disable() -> void:
	var store := DlgSeenStore.new()
	store.mark(CoachConditions.fact_key("sessionActionUsed", {"action": ["speedUp", "speedDown"], "scope": "save"}))
	store.mark("coach.deck-armed")
	var e := CoachEngine.load_file(FIX + "coachmarks_sample.json")
	e.seen = store
	e.begin_level("t-one")
	var v := _view(SessionPhase.SETUP, 0)
	v.speeds = [1.0, 2.0]
	_run(e, v, 1.0)
	assert_eq(_cur(e), "", "deck-armed done in the save; speed-pick skipped (the player already changes speed)")
	assert_true(store.has("coach.speed-pick"), "skipIf retires silently")
	# dialogue and barks
	var e2 := _engine()
	e2.dialogue_open = true
	_run(e2, v, 0.5)
	assert_eq(_cur(e2), "", "nothing over a dialogue box")
	e2.dialogue_open = false
	e2.bark_on_screen = true
	_run(e2, v, 0.5)
	assert_eq(_cur(e2), "", "a bark on screen delays the next mark")
	e2.bark_on_screen = false
	e2.update(DT, v)
	assert_eq(_cur(e2), "deck-armed")
	e2.dialogue_open = true
	e2.update(DT, v)
	assert_eq(_cur(e2), "", "a dialogue box opening fades the visible mark")
	e2.dialogue_open = false
	e2.enabled = false
	_run(e2, v, 3.0)
	assert_eq(_cur(e2), "", "disabled in settings")
	e2.enabled = true
	_run(e2, v, 2.0)
	assert_eq(_cur(e2), "deck-armed", "back on")


func test_engine_level_filter_per_visit_and_markdone() -> void:
	var e := _engine("t-two")
	var v := _view(SessionPhase.SETUP, 0)
	_run(e, v, 1.0)
	assert_eq(_cur(e), "", "deck-armed is t-one only")
	# ruler-lane (once = false) needs markDone move and a quarter of the take
	e.seen.mark("coach.move")
	var rv := _view(SessionPhase.RECORDING, 0)
	rv.decks[0].status = DeckStatus.RECORDING
	rv.decks[0].local_progress = 0.3
	e.note_input(&"move")
	_run(e, rv, 0.2)
	assert_eq(_cur(e), "ruler-lane")
	_run(e, rv, 4.1)
	assert_eq(_cur(e), "", "dismissed by shownFor")
	assert_false(e.seen.has("coach.ruler-lane"), "once = false: not in the save")
	assert_true(e.ctx.visit_done.has("ruler-lane"), "retired for this visit")
	_run(e, _view(SessionPhase.DECISION, 0), 0.1)
	_run(e, rv, 2.0)
	assert_eq(_cur(e), "", "not again in this visit")
	e.begin_level("t-two")
	e.note_input(&"move")
	_run(e, rv, 0.2)
	assert_eq(_cur(e), "ruler-lane", "a new level visit")


func test_engine_count_in_first_time_only() -> void:
	var store := DlgSeenStore.new()
	var e := CoachEngine.load_file(FIX + "coachmarks_sample.json")
	e.seen = store
	e.begin_level("t-two")
	var c := _view(SessionPhase.COUNTIN, 0)
	e.update(DT, c)
	assert_eq(_cur(e), "count-in")
	e.update(DT, _view(SessionPhase.RECORDING, 0))
	assert_eq(_cur(e), "", "dismissOn phaseIs recording (it also leaves its phase)")
	var e2 := CoachEngine.load_file(FIX + "coachmarks_sample.json")
	store.unmark("coach.count-in")
	e2.seen = store
	e2.begin_level("t-two")
	e2.update(DT, c)
	assert_eq(_cur(e2), "", "not the first count-in of the save any more")


# ───────────────────────────── layout ─────────────────────────────

func test_layout_avoids_and_stays_on_screen() -> void:
	var screen := Rect2(0, 0, 1600, 900)
	var ruler := Rect2(0, 760, 1600, 60)
	var anchor := Rect2(100, 780, 200, 30) # inside the ruler, bottom left
	var avoid: Array[Rect2] = [ruler]
	var p := CoachLayout.place(anchor, true, Vector2(300, 100), screen, avoid)
	assert_eq(p.side, "above")
	assert_true(screen.encloses(p.rect), "on screen")
	assert_false(p.rect.intersects(ruler), "never over the ruler")
	assert_true(p.tip.y <= anchor.position.y + 0.01, "pointer touches the anchor's top")
	var top := CoachLayout.place(Rect2(700, 10, 100, 30), true, Vector2(300, 100), screen, _no_r)
	assert_eq(top.side, "below", "no room above -> below")
	var edge := CoachLayout.place(Rect2(1580, 400, 20, 20), true, Vector2(300, 100), screen, _no_r, "right")
	assert_true(screen.encloses(edge.rect) and edge.side != "right", "no room right -> another side")
	var none := CoachLayout.place(Rect2(), false, Vector2(300, 100), screen, _no_r)
	assert_eq(none.side, "none")
	assert_true(screen.encloses(none.rect))


func test_anchor_group_names() -> void:
	var s := _subj(2)
	assert_eq(CoachAnchors.group_name("deck:active", 1, null), "deck_1")
	assert_eq(CoachAnchors.group_name("deck:subject", 1, s), "deck_2")
	assert_eq(CoachAnchors.group_name("deck:subject", 1, null), "", "no subject -> unresolved")
	assert_eq(CoachAnchors.group_name("deck.speed", 1, null), "deck_speed")
	assert_eq(CoachAnchors.group_name("deck.endMode", 1, null), "deck_endMode")
	assert_eq(CoachAnchors.group_name("ruler", 1, null), "ruler")
	assert_eq(CoachAnchors.group_name("ruler.playhead", 1, null), "ruler_playhead")
	assert_eq(CoachAnchors.group_name("ruler.lane:active", 3, null), "ruler_lane_3")
	assert_eq(CoachAnchors.group_name("objective", 1, null), "objective")
	assert_eq(CoachAnchors.group_name("countin", 1, null), "count_in")
	assert_eq(CoachAnchors.group_name("prompt:commit", 1, null), "prompt_commit")
	assert_eq(CoachLayer.format_speed(0.5), "0.5x")
	assert_eq(CoachLayer.format_speed(2.0), "2x")
