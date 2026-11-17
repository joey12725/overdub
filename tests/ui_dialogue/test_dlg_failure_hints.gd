extends ODTest
## Failure hints (docs/ONBOARDING.md "Failure hints"): note regexes, ignore patterns, signatures,
## streaks (present +1, absent dropped, a win clears), show after the second identical failure, once
## per hint per level visit, earliest in file order, {tape}. Pure logic.

const FIX := "res://tests/ui_dialogue/fixtures/"


func _fail(notes: Array) -> Outcome:
	var o := Outcome.new()
	o.win = false
	o.reason = FailReason.OBJECTIVE
	for n: Variant in notes:
		o.notes.append(str(n))
	return o


func _hints() -> DlgFailureHints:
	var h := DlgFailureHints.load_file(FIX + "failure_hints_sample.json")
	h.begin_level("t-one")
	return h


const WALL := "Tape A's heavy at beat 2.02 hit breakable wall w1 with momentum 4; it needs 5."
const WALL2 := "Tape B's light at beat 7 hit breakable wall w1 with momentum 1; it needs 5."
const DIED_A := "Tape A died at beat 3.5: struck by grunt g1."
const DIED_A_LATER := "Tape A died at beat 9: struck by grunt g1."
const OBJ := "Objective not complete: Break the core. Not activated: c1."


func test_classify_and_ignore() -> void:
	var h := _hints()
	assert_eq(h.errors, [])
	var m := h.classify(WALL)
	assert_eq(m.hint.id, "weak.breakable")
	assert_eq(m.signature, "weak.breakable|w1", "signature: id + named groups, never the beat")
	assert_eq(h.classify(WALL2).signature, m.signature, "same wall, other tape and beat: same failure")
	assert_eq(h.classify(DIED_A).tape, "A")
	assert_true(h.classify("Survivors: Tape B.") == null, "ignored note")
	assert_true(h.classify("Something new.") == null, "unmatched note")
	assert_true(h.classify("x" + WALL) == null, "the regex must match the whole note")


func test_second_identical_failure_then_once_per_visit() -> void:
	var h := _hints()
	assert_eq(h.on_resolved(_fail([WALL, OBJ])), "", "first failure: the notes only")
	assert_eq(h.on_resolved(_fail([WALL2, OBJ])), "Still bouncing off. Stack swing, run-up and tape speed.", "second: earliest hint in file order")
	assert_eq(h.last.hint.id, "weak.breakable")
	assert_eq(h.on_resolved(_fail([WALL, OBJ])), "The job isn't done yet.", "weak.breakable already shown this visit -> next eligible")
	assert_eq(h.on_resolved(_fail([WALL, OBJ])), "", "every streaking hint shown: nothing more")
	h.begin_level("t-one")
	h.on_resolved(_fail([WALL]))
	assert_ne(h.on_resolved(_fail([WALL])), "", "a new level visit starts over")


func test_streak_drops_absent_and_win_clears() -> void:
	var h := _hints()
	h.on_resolved(_fail([WALL]))
	h.on_resolved(_fail([DIED_A]))
	assert_eq(h.on_resolved(_fail([WALL])), "", "the wall streak was broken by a different failure")
	var win := Outcome.new()
	win.win = true
	h.on_resolved(win)
	assert_eq(h.on_resolved(_fail([WALL])), "", "a win clears the streaks")
	assert_eq(h.on_resolved(_fail([WALL])), "Still bouncing off. Stack swing, run-up and tape speed.")


func test_tape_token() -> void:
	var h := _hints()
	h.on_resolved(_fail([DIED_A]))
	assert_eq(h.on_resolved(_fail([DIED_A_LATER])), "Tape A keeps meeting that swing. It hits on the beat.")


func test_real_failure_hints_load() -> void:
	if not FileAccess.file_exists(DlgFailureHints.DEFAULT_PATH):
		assert_true(true, "no failure_hints.json yet")
		return
	var h := DlgFailureHints.load_file()
	assert_eq(h.errors, [], "every regex in data/onboarding/failure_hints.json compiles in Godot's RegEx")
	assert_true(h.hints.size() > 10)
	var raw: Variant = load_json(DlgFailureHints.DEFAULT_PATH)
	var bad: Array[String] = []
	for e: Variant in (raw as Dictionary)["hints"]:
		for ex: Variant in (e as Dictionary).get("examples", []):
			var m := h.classify(str(ex))
			if m == null or m.hint.id != str((e as Dictionary)["id"]):
				bad.append("%s -> %s" % [ex, m.hint.id if m != null else "nothing"])
	assert_eq(bad, [], "each example resolves to its own hint first (Godot RegEx agrees with Python)")


func test_prompt_substitution() -> void:
	var b: Dictionary = {SessionAction.SPEED_UP: ButtonPrompt.make("E"), SessionAction.COMMIT: ButtonPrompt.make("Enter")}
	assert_eq(DlgPrompts.substitute("Try {btn:speedUp}, then {commit}.", b), "Try E, then Enter.")
	assert_eq(DlgPrompts.substitute("No {btn:move} here {{literal}", b), "No Move here {literal}")
	assert_eq(DlgPrompts.substitute("plain", b), "plain")
