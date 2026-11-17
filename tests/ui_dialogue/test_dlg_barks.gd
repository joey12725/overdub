extends ODTest
## Barks: DlgBarkRules (cooldowns, chance, global rate limit, one per phase, no repeats, off switch)
## and DlgBarkTriggers (SessionView + sim events -> bark keys; INTEGRATION.md "Barks"). Pure logic.


func _lines(n: int) -> Array[DlgLine]:
	var out: Array[DlgLine] = []
	for i in n:
		out.append(DlgLine.make("moxie", "neutral", "line %d" % i))
	return out


func _rules() -> DlgBarkRules:
	var r := DlgBarkRules.new(1234)
	r.one_per_phase = false
	return r


func test_never_same_line_twice_running() -> void:
	var r := _rules()
	r.gap = 0.0
	r.window_max = 1000
	var ls := _lines(3)
	var prev := ""
	for i in 200:
		r.tick(100.0)
		var l := r.request("win", ls)
		if not assert_true(l != null, "win always barks"):
			return
		if not assert_ne(l.line, prev, "no repeat at pick %d" % i):
			return
		prev = l.line


func test_cooldown_per_event() -> void:
	var r := _rules()
	r.gap = 0.0
	var ls := _lines(2)
	assert_true(r.request("lastTape", ls) != null)
	r.tick(5.0)
	assert_true(r.request("lastTape", ls) == null)
	assert_eq(r.last_reject, "cooldown")
	assert_true(r.request("win", ls) != null, "another event is not on that cooldown")
	r.tick(DlgBarkRules.rule("lastTape")[1])
	assert_true(r.request("lastTape", ls) != null, "after the cooldown it can bark again")


func test_global_gap_and_rate() -> void:
	var r := _rules()
	var ls := _lines(4)
	assert_true(r.request("win", ls) != null)
	r.tick(1.0)
	assert_true(r.request("loot", ls) == null)
	assert_eq(r.last_reject, "gap", "global gap between any two barks")
	r.gap = 0.0
	r.window_max = 3
	var keys := ["loot", "rescue", "lastTape", "resetAll"]
	var got := 1
	for k: String in keys:
		r.tick(0.5)
		if r.request(k, ls) != null:
			got += 1
	assert_eq(got, 3, "at most window_max barks per window")
	assert_eq(r.last_reject, "rate")
	r.tick(r.window + 1.0)
	assert_true(r.request("ghostTake", ls) != null, "the window slides")


func test_one_per_phase() -> void:
	var r := DlgBarkRules.new(7)
	r.gap = 0.0
	var ls := _lines(2)
	assert_true(r.request("win", ls) != null)
	r.tick(1.0)
	assert_true(r.request("loot", ls) == null)
	assert_eq(r.last_reject, "phase")
	r.new_phase()
	assert_true(r.request("loot", ls) != null)


func test_chance_is_roughly_respected_and_force() -> void:
	var r := _rules()
	r.gap = 0.0
	r.window_max = 100000
	var ls := _lines(3)
	var hits := 0
	for i in 600:
		r.tick(100.0)
		if r.request("countIn", ls) != null:
			hits += 1
	var expect: float = DlgBarkRules.rule("countIn")[0] * 600.0
	assert_true(absf(hits - expect) < 70.0, "countIn chance ~%.0f, got %d" % [expect, hits])
	r.tick(100.0)
	assert_true(r.request("countIn", ls, true) != null, "force skips the roll")


func test_disabled_and_empty() -> void:
	var r := _rules()
	r.enabled = false
	assert_true(r.request("win", _lines(2), true) == null)
	assert_eq(r.last_reject, "disabled", "the off switch beats force")
	r.enabled = true
	assert_true(r.request("win", _lines(0)) == null)
	assert_eq(r.last_reject, "empty")


# ───────────────────────────── triggers ─────────────────────────────

func _view(phase: StringName, active: int = 0) -> SessionView:
	var v := SessionView.new()
	v.phase = phase
	v.active = active
	var L := LevelDef.new()
	L.max_tapes = 4
	v.level = L
	for d: DeckView in v.decks:
		d.status = DeckStatus.EMPTY
	return v


func _ev(type: StringName, tape: int = 0) -> SimEvent:
	return SimEvent.make(0, type, 0.0, 0.0).with_tape(tape)


func test_triggers_phase_entries() -> void:
	var t := DlgBarkTriggers.new()
	var none: Array[SimEvent] = []
	assert_eq(t.observe(_view(SessionPhase.SETUP, 0), none, 0.016), [], "setup on tape A is not the last tape")
	assert_eq(t.observe(_view(SessionPhase.COUNTIN, 0), none, 0.016), ["countIn"])
	assert_eq(t.observe(_view(SessionPhase.COUNTIN, 0), none, 0.016), [], "only on entry")
	assert_eq(t.observe(_view(SessionPhase.SETUP, 3), none, 0.016), ["lastTape"])
	var v2 := _view(SessionPhase.SETUP, 1)
	v2.level.max_tapes = 2
	v2.decks[2].status = DeckStatus.UNAVAILABLE
	v2.decks[3].status = DeckStatus.UNAVAILABLE
	t.observe(_view(SessionPhase.DECISION, 0), none, 0.016)
	assert_eq(t.observe(v2, none, 0.016), ["lastTape"], "last tape of a two-tape level")
	assert_eq(t.observe(_view(SessionPhase.CINEMATIC, 1), none, 0.016), ["win"])


func test_triggers_death_desync_and_boss() -> void:
	var t := DlgBarkTriggers.new()
	var none: Array[SimEvent] = []
	t.observe(_view(SessionPhase.RECORDING, 1), none, 0.016)
	var evs: Array[SimEvent] = [_ev(SimEventType.SELF_DEATH, 0), _ev(SimEventType.SELF_DEATH, 1), _ev(SimEventType.DESYNC, 0), _ev(SimEventType.BOSS_RECALL, 0)]
	assert_eq(t.observe(_view(SessionPhase.RECORDING, 1), evs, 0.016), ["death", "desync", "bossRecall"], "only the live self's death barks")
	var rev: Array[SimEvent] = [_ev(SimEventType.SELF_DEATH, 1), _ev(SimEventType.RESYNC, 0)]
	t.observe(_view(SessionPhase.REVIEW, 1), none, 0.016)
	assert_eq(t.observe(_view(SessionPhase.REVIEW, 1), rev, 0.016), ["resync"], "deaths replayed in review are not news")


func test_triggers_ghost_take_once() -> void:
	var t := DlgBarkTriggers.new()
	var none: Array[SimEvent] = []
	var v := _view(SessionPhase.RECORDING, 0)
	v.decks[0].life = OD.LifeState.REC_GHOST
	var got: Array[String] = []
	for i in 400:
		got.append_array(t.observe(v, none, 1.0 / 60.0))
	assert_eq(got, ["ghostTake"], "one ghostTake bark per take, a few seconds in")


func test_triggers_fail_and_rescue() -> void:
	var t := DlgBarkTriggers.new()
	var none: Array[SimEvent] = []
	t.observe(_view(SessionPhase.BRIEFING), none, 0.016)
	# run 1: tapes A, B recorded; only B survives; fails
	var r1 := _view(SessionPhase.REVIEW, 1)
	t.observe(r1, none, 0.016)
	var d1 := _view(SessionPhase.DECISION, 1)
	d1.decks[0].status = DeckStatus.COMMITTED
	d1.decks[1].status = DeckStatus.PENDING
	d1.outcome = Outcome.new()
	d1.outcome.win = false
	d1.outcome.survivors = [1]
	assert_eq(t.observe(d1, none, 0.016), ["fail"])
	# run 2: A now survives too (it died last time)
	t.observe(_view(SessionPhase.REVIEW, 1), none, 0.016)
	var d2 := _view(SessionPhase.DECISION, 1)
	d2.decks[0].status = DeckStatus.COMMITTED
	d2.decks[1].status = DeckStatus.PENDING
	d2.outcome = Outcome.new()
	d2.outcome.win = false
	d2.outcome.survivors = [0, 1]
	assert_eq(t.observe(d2, none, 0.016), ["rescue", "fail"], "a self that died last run survives: rescue")
