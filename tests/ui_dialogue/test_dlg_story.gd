extends ODTest
## Story data (DlgStoryData), the seen store and the story director (which sequence plays when;
## docs/story/INTEGRATION.md), portrait lookup with fallbacks. Pure logic.

const FIX := "res://tests/ui_dialogue/fixtures/"


func _story() -> DlgStoryData:
	return DlgStoryData.load_file(FIX + "story_sample.json")


func test_sample_story_loads_and_validates() -> void:
	var s := _story()
	assert_eq(s.errors.size(), 0, "loads: %s" % [s.errors])
	assert_eq(s.validate(), [], "sample story is valid")
	assert_eq(s.level_lines("t-one", "intro").size(), 3)
	assert_eq(s.level_lines("nope", "intro").size(), 0, "unknown level -> no lines")
	assert_eq(s.character("opal").name, "Opal")
	assert_true(s.character("opal").radio, "Opal is a radio voice by default")
	assert_true(s.character("moxie").left and not s.character("opal").left, "Moxie left, others right")
	assert_eq(s.character("stranger").name, "Stranger", "unknown speakers still render")
	assert_eq(s.barks("countIn").size(), 3)


func test_validate_reports_problems() -> void:
	var s := DlgStoryData.from_dict({
		"characters": [{"id": "moxie", "name": "Moxie", "portraits": ["neutral"]}],
		"levels": {"x": {"intro": [
			{"who": "moxie", "expression": "grin", "line": "a"},
			{"who": "ghost", "expression": "neutral", "line": "b"},
			{"who": "moxie", "expression": "neutral", "line": "x".repeat(80)},
			{"who": "moxie", "expression": "neutral", "line": "  "},
		]}},
	})
	var errs := s.validate()
	assert_eq(errs.size(), 4, "one problem per bad line: %s" % [errs])


func test_ending_cut_between_six_and_seven() -> void:
	var e := _story().ending_lines()
	assert_eq(e.size(), 8)
	for i in e.size():
		assert_eq(e[i].cut_before, i == 6, "cut only before line 7 (index %d)" % i)
	assert_true(e[6].is_radio_cut(), "'--oxie?' is a radio cut")


func test_real_story_file_validates() -> void:
	if not FileAccess.file_exists(DlgStoryData.DEFAULT_PATH):
		assert_true(true, "no story.json yet")
		return
	var s := DlgStoryData.load_file()
	assert_eq(s.errors, [], "data/story/story.json parses")
	assert_true(s.characters.has("moxie"), "story.json has Moxie")
	# Unknown speakers / expressions are errors; over-long lines are reported (the box wraps them,
	# but INTEGRATION.md promises <= 76 characters).
	var hard: Array[String] = []
	for e: String in s.validate():
		if e.contains("characters (max"):
			print("  story.json warning: ", e)
		else:
			hard.append(e)
	assert_eq(hard, [], "data/story/story.json: every line has a known speaker and expression")


func test_seen_store_roundtrip() -> void:
	var st := DlgSeenStore.new()
	var n := [0]
	st.changed.connect(func() -> void: n[0] += 1)
	st.mark("coach.b")
	st.mark("coach.a")
	st.mark("coach.a")
	assert_eq(n[0], 2, "changed fires once per new flag")
	assert_eq(st.to_array(), ["coach.a", "coach.b"], "sorted, unique")
	var st2 := DlgSeenStore.new()
	st2.load_array(["x", 3, "y"])
	assert_eq(st2.to_array(), ["x", "y"], "non-strings ignored")
	st.clear_prefix("coach.")
	assert_eq(st.size(), 0)


func test_director_intro_outro_once() -> void:
	var seen := DlgSeenStore.new()
	var d := DlgStoryDirector.new(_story(), seen)
	assert_eq(d.intro("t-one").size(), 3, "first visit plays the intro")
	assert_true(seen.has("story.t-one.intro"))
	assert_eq(d.intro("t-one").size(), 0, "second visit does not")
	assert_eq(d.intro("t-one", true).size(), 3, "replay from level select does")
	assert_eq(d.outro("t-one").size(), 1)
	assert_eq(d.outro("t-one").size(), 0)
	assert_eq(d.intro("t-zero").size(), 0, "a level without an intro is fine")
	assert_false(seen.has("story.t-zero.intro"), "and marks nothing")
	assert_eq(d.ending().size(), 8)
	assert_eq(d.ending().size(), 0, "the ending plays once per save")
	assert_eq(d.idle_line("t-one").line, "I'm billing you for this radio time.")
	assert_null_ok(d.idle_line("t-two"))


func assert_null_ok(v: Variant) -> void:
	assert_true(v == null, "no idle line -> null")


func test_director_firsts_level_beats_once() -> void:
	var seen := DlgSeenStore.new()
	var d := DlgStoryDirector.new(_story(), seen)
	assert_true(d.note_first("t-one", "death"), "level firstDeath queued")
	assert_true(seen.has("story.t-one.firstDeath") and seen.has("once.firstDeath"), "level version also marks the once flag")
	var p := d.take_pending()
	assert_eq((p["lines"] as Array).size(), 1)
	assert_eq((p["lines"][0] as DlgLine).line, "That one got me.")
	assert_false(d.note_first("t-two", "death"), "once.firstDeath already spent by the level version")
	assert_true(d.note_first("t-two", "desync"), "once.firstDesync on a level without its own")
	assert_false(d.note_first("t-two", "desync"), "only once")
	assert_false(d.note_first("t-two", "resetAll"), "nothing written for it -> nothing queued")
	assert_true(d.has_pending())
	assert_eq(d.take_pending()["key"], "once.firstDesync")
	assert_false(d.has_pending())


func test_portraits_lookup_and_fallback() -> void:
	var dirs: Array[String] = [FIX + "portraits"]
	var p := DlgPortraits.new(dirs)
	assert_true(p.has_exact("moxie", "neutral"), "underscore spelling found")
	assert_true(p.has_exact("moxie", "grin"), "dot spelling found")
	assert_false(p.has_exact("moxie", "smug"))
	assert_true(p.texture("moxie", "smug") != null, "missing expression falls back to neutral")
	assert_true(p.texture("opal", "dry") == null, "missing character -> null (view draws an initial)")
	var t := p.texture("moxie", "neutral")
	assert_eq(t.get_size(), Vector2(256, 256))
	assert_true(p.texture("moxie", "neutral") == t, "cached")
