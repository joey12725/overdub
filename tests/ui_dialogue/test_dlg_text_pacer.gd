extends ODTest
## Typewriter pacing (DlgTextPacer) and the dialogue sequencer (DlgRunner): punctuation pauses,
## advance / complete, hold to fast-forward, hold to skip, cuts. Pure logic, no nodes.


func _lines(texts: Array) -> Array[DlgLine]:
	var out: Array[DlgLine] = []
	for t: Variant in texts:
		out.append(DlgLine.make("moxie", "neutral", str(t)))
	return out


func test_pacer_monotonic_and_complete() -> void:
	var p := DlgTextPacer.new(50.0).compute("Hello there, you. Wait... what?")
	assert_eq(p.length(), 31)
	for i in range(1, p.length()):
		if not assert_true(p.times[i] >= p.times[i - 1], "times non-decreasing at %d" % i):
			return
	assert_eq(p.visible_at(-1.0), 0)
	assert_eq(p.visible_at(0.0), 1, "the first character shows at once")
	assert_eq(p.visible_at(p.total_time()), p.length(), "everything visible at total_time")
	assert_eq(p.visible_at(999.0), p.length())


func test_pacer_pauses_after_punctuation() -> void:
	var plain := DlgTextPacer.new(50.0).compute("aaaaa bbbbb").total_time()
	var comma := DlgTextPacer.new(50.0).compute("aaaaa,bbbbb")
	var comma_sp := DlgTextPacer.new(50.0).compute("aaaa, bbbbb").total_time()
	var stop := DlgTextPacer.new(50.0).compute("aaaa. bbbbb").total_time()
	assert_near(comma.total_time(), 10.0 / 50.0, 1e-4, "a comma without a following space does not pause")
	assert_true(comma_sp > plain + 0.08, "clause pause after ', '")
	assert_true(stop > comma_sp + 0.1, "sentence pause is longer than a clause pause")


func test_pacer_no_pause_at_end_and_decimal() -> void:
	var a := DlgTextPacer.new(40.0).compute("Done.").total_time()
	var b := DlgTextPacer.new(40.0).compute("Donee").total_time()
	assert_near(a, b, 1e-5, "a trailing full stop adds nothing: lines never hang at the end")
	var dec := DlgTextPacer.new(40.0).compute("x 3.5 y").total_time()
	var nodec := DlgTextPacer.new(40.0).compute("x 3,5 y").total_time()
	assert_near(dec, nodec, 1e-5, "a decimal point is not a sentence end")


func test_pacer_ellipsis_and_dash_and_closers() -> void:
	var e := DlgTextPacer.new(50.0).compute("Huh... ok")
	# each dot of the ellipsis is slower than a normal character
	assert_true(e.times[4] - e.times[3] > 0.1, "ellipsis dots are slow")
	var d := DlgTextPacer.new(50.0).compute("don't you d-- what")
	var dash_i := d.text.find("--") + 1
	assert_true(d.times[dash_i + 1] - d.times[dash_i] > 0.15, "a radio cut dash pauses")
	var q := DlgTextPacer.new(50.0).compute("\"Easy.\" Then")
	assert_true(q.times[6] - q.times[5] < 0.05, "the closing quote rides with the full stop")
	assert_true(q.times[7] - q.times[6] > 0.2, "and the pause comes after the quote")


func test_runner_complete_then_advance_then_finish() -> void:
	var r := DlgRunner.new()
	var done: Array = []
	r.finished.connect(func(s: bool) -> void: done.append(s))
	r.start(_lines(["First line here.", "Second."]))
	assert_true(r.is_typing())
	r.tick(0.1)
	assert_true(r.visible_chars() > 0 and r.visible_chars() < 16, "typing partway")
	r.press_accept()
	r.release_accept()
	assert_true(r.is_waiting(), "accept while typing completes the line")
	assert_eq(r.index, 0, "and does not advance")
	assert_eq(r.visible_chars(), 16)
	r.tick(0.1)
	r.press_accept()
	r.release_accept()
	assert_eq(r.index, 1, "accept while waiting advances")
	r.tick(5.0)
	assert_true(r.is_waiting(), "no auto-advance: it waits after typing")
	r.tick(0.1)
	r.press_accept()
	assert_eq(done, [false], "finished(skipped = false) after the last line")
	assert_false(r.is_running())


func test_runner_press_guard() -> void:
	var r := DlgRunner.new()
	r.start(_lines(["Alpha beta gamma.", "Two."]))
	r.tick(0.2)
	r.press_accept() # completes
	r.release_accept()
	r.tick(0.2)
	r.press_accept() # advances to line 2 (line_age 0)
	r.release_accept()
	r.press_accept() # same frame: guarded, must not complete line 2 instantly
	assert_true(r.is_typing(), "a second press in the same instant is ignored")


func test_runner_hold_fast_forward() -> void:
	var r := DlgRunner.new()
	var done: Array = []
	r.finished.connect(func(s: bool) -> void: done.append(s))
	r.start(_lines(["One one one one one.", "Two two two two two.", "Three three three."]))
	r.tick(0.1)
	r.press_accept() # complete line 0; keep holding
	var t := 0.0
	while r.is_running() and t < 10.0:
		r.tick(1.0 / 60.0)
		t += 1.0 / 60.0
	assert_eq(done, [false], "holding accept fast-forwards through every line")
	assert_true(t < 2.5, "and does it quickly (%.2fs)" % t)


func test_runner_hold_skip_and_skip_all() -> void:
	var r := DlgRunner.new()
	var done: Array = []
	r.finished.connect(func(s: bool) -> void: done.append(s))
	r.start(_lines(["a", "b", "c"]))
	r.set_skip_held(true)
	r.tick(0.3)
	assert_true(r.is_running(), "not skipped before the hold time")
	assert_true(r.skip_progress() > 0.3 and r.skip_progress() < 0.6)
	r.set_skip_held(false)
	assert_eq(r.skip_progress(), 0.0, "releasing resets the hold")
	r.set_skip_held(true)
	r.tick(DlgRunner.SKIP_HOLD + 0.01)
	assert_eq(done, [true], "holding skip ends the whole sequence")
	r.start(_lines(["x", "y"]))
	r.skip_all()
	assert_eq(done, [true, true], "skip_all works at any time")
	r.skip_all()
	assert_eq(done.size(), 2, "skipping a finished sequence is a no-op")


func test_runner_empty_and_cut() -> void:
	var r := DlgRunner.new()
	var done: Array = []
	var cuts: Array = []
	r.finished.connect(func(s: bool) -> void: done.append(s))
	r.cut_started.connect(func(i: int) -> void: cuts.append(i))
	r.start(_lines([]))
	assert_eq(done, [false], "an empty sequence finishes at once")
	var ls := _lines(["one", "two"])
	ls[1].cut_before = true
	r.start(ls)
	r.tick(0.5)
	r.tick(0.1)
	r.press_accept()
	r.release_accept()
	assert_eq(cuts, [1], "the cut starts before line 2")
	r.press_accept()
	r.release_accept()
	assert_eq(r.state, DlgRunner.State.CUT, "accept does nothing during a cut")
	r.tick(DlgRunner.CUT_TIME + 0.01)
	assert_true(r.is_typing() and r.index == 1, "line 2 types after the cut")
	r.skip_all()
	assert_eq(done, [false, true])


func test_runner_text_speed_setting() -> void:
	var slow := DlgRunner.new()
	slow.speed_mult = 0.5
	var fast := DlgRunner.new()
	fast.speed_mult = 2.0
	slow.start(_lines(["The quick brown fox jumps."]))
	fast.start(_lines(["The quick brown fox jumps."]))
	slow.tick(0.2)
	fast.tick(0.2)
	assert_true(fast.visible_chars() > slow.visible_chars() * 2, "text speed scales typing")
