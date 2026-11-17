extends ODTest
## Port of prototype/tests/core/foundation/signals.test.ts.

var table: Dictionary[String, bool] = {"a": true, "b": false, "c": true}


func _sig(id: String) -> SignalExpr:
	return SignalExpr.of_sig(id)


func _ev(e: SignalExpr, beat: float = 0.0) -> bool:
	return ODSignals.eval_signal(e, table, beat)

# ── evalSignal ──


func test_reads_signals_missing_ids_are_false() -> void:
	assert_true(_ev(_sig("a")))
	assert_false(_ev(_sig("b")))
	assert_false(_ev(_sig("nope")))


func test_combines_with_not_and_or_xor_const() -> void:
	assert_true(_ev(SignalExpr.of_not(_sig("b"))))
	assert_true(_ev(SignalExpr.of_and([_sig("a"), _sig("c")])))
	assert_false(_ev(SignalExpr.of_and([_sig("a"), _sig("b")])))
	assert_true(_ev(SignalExpr.of_or([_sig("b"), _sig("c")])))
	assert_false(_ev(SignalExpr.of_or([_sig("b"), _sig("x")])))
	assert_true(_ev(SignalExpr.of_and([])))
	assert_false(_ev(SignalExpr.of_or([])))
	for row: Array in [["a", "b", true], ["a", "c", false], ["b", "x", false]]:
		assert_eq(_ev(SignalExpr.of_xor(_sig(row[0]), _sig(row[1]))), row[2], "xor %s %s" % [row[0], row[1]])
	assert_true(_ev(SignalExpr.of_const(true)))
	assert_false(_ev(SignalExpr.of_const(false)))


func test_beat_windows_follow_the_master_beat_half_open_with_wrap_around() -> void:
	var w := SignalExpr.of_beat(4, 0, 2)
	assert_true(_ev(w, 0))
	assert_true(_ev(w, 1.999))
	assert_false(_ev(w, 2))
	assert_false(_ev(w, 3.5))
	assert_true(_ev(w, 4))
	assert_true(_ev(w, 9))
	var wrap := SignalExpr.of_beat(4, 3, 1)
	var got: Array[bool] = []
	for b: float in [0.0, 0.5, 1.0, 2.0, 3.0, 3.5, 7.25]:
		got.append(_ev(wrap, b))
	assert_eq(got, [true, true, false, false, true, true, true])
	assert_false(ODSignals.in_beat_window(5, 4, 1, 1))
	assert_false(ODSignals.in_beat_window(5, 0, 0, 1))
	assert_true(ODSignals.in_beat_window(5, 4, 0, 4))
	assert_true(ODSignals.in_beat_window(-1, 4, 3, 4), "negative beats wrap like positive ones")
	assert_false(ODSignals.in_beat_window(2.5, 4, -1, 1))
	assert_true(ODSignals.in_beat_window(3.5, 4, -1, 1))


func test_composes_timed_and_signal_logic() -> void:
	# A laser that fires on beats 0-1 while a switch is off.
	var laser := SignalExpr.of_and([SignalExpr.of_not(_sig("sw")), SignalExpr.of_beat(2, 0, 1)])
	var t: Dictionary[String, bool] = {}
	assert_true(ODSignals.eval_signal(laser, t, 0.5))
	assert_false(ODSignals.eval_signal(laser, t, 1.5))
	t["sw"] = true
	assert_false(ODSignals.eval_signal(laser, t, 0.5))

# ── introspection ──


func _intro_expr() -> SignalExpr:
	return SignalExpr.of_or([
		SignalExpr.of_and([_sig("door"), SignalExpr.of_not(_sig("plate"))]),
		SignalExpr.of_xor(_sig("door"), _sig("core")),
		SignalExpr.of_beat(4, 0, 2),
		SignalExpr.of_const(true),
	])


func test_collects_every_referenced_id_once() -> void:
	assert_eq(ODSignals.collect_signal_ids(_intro_expr()).keys(), ["door", "plate", "core"])
	var s: Dictionary[String, bool] = {"x": true}
	ODSignals.collect_signal_ids(_sig("y"), s)
	assert_eq(s.keys(), ["x", "y"])
	# A fresh default set per call.
	assert_eq(ODSignals.collect_signal_ids(_sig("z")).keys(), ["z"])


func test_detects_beat_timed_expressions_and_formats_readably() -> void:
	assert_true(ODSignals.is_timed_expr(_intro_expr()))
	assert_false(ODSignals.is_timed_expr(SignalExpr.of_not(_sig("a"))))
	assert_eq(ODSignals.format_signal_expr(_intro_expr()), "(door & !plate) | (door ^ core) | beat%4∈[0,2) | true")
	assert_eq(ODSignals.format_signal_expr(SignalExpr.of_beat(2.5, 0.5, 1)), "beat%2.5∈[0.5,1)")
	assert_eq(ODSignals.format_signal_expr(SignalExpr.of_and([])), "true")


func test_parses_the_prototype_json_shape() -> void:
	var errors: Array[String] = []
	var e := SignalExpr.from_dict({"and": [{"not": {"sig": "sw"}}, {"beat": {"every": 2, "from": 0, "to": 1}}]}, errors)
	assert_eq(errors, [])
	var empty: Dictionary[String, bool] = {}
	assert_true(ODSignals.eval_signal(e, empty, 0.5))
	assert_eq(ODSignals.format_signal_expr(e), "!sw & beat%2∈[0,1)")
