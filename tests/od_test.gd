class_name ODTest
extends RefCounted
## Base class for headless test suites (docs/GODOT-PORT.md "Tests").
##
## A suite is any res://tests/**/test_*.gd that extends ODTest. tests/run_tests.gd instantiates it,
## calls before_each() / after_each() around every method whose name starts with `test_` (if the
## suite defines them), and reports each failed assertion with suite, test and message. Test methods
## take no arguments; they may `await` (the runner awaits each one). Keep requirement ids in test
## names (test_time_02_same_wall_time_every_speed).
##
## Every assert_* returns true when it passed, so a test can bail out early:
##     if not assert_eq(level.id, "sandbox"): return
##
## A runtime script error inside a test (null access, bad call...) also fails that test: the runner
## watches the engine log. A test that expects engine errors (e.g. pushes an error on purpose) calls
## expect_engine_errors() first.

## Set by the runner: the suite's path and the test currently running.
var _suite_path: String = ""
var _test_name: String = ""
## Failure messages of the current test (the runner reads and clears this).
var _failures: Array[String] = []
var _assertions: int = 0
var _allow_engine_errors: bool = false


# ───────────────────────────── assertions ─────────────────────────────

## Record a failure unconditionally.
func fail(msg: String) -> bool:
	_assertions += 1
	_failures.append(msg)
	return false


func assert_true(cond: bool, msg: String = "") -> bool:
	_assertions += 1
	if cond:
		return true
	_failures.append(_m("expected true", msg))
	return false


func assert_false(cond: bool, msg: String = "") -> bool:
	_assertions += 1
	if not cond:
		return true
	_failures.append(_m("expected false", msg))
	return false


## Equality with JSON semantics: numbers by value (1 == 1.0), String == StringName by content, and
## Arrays / Dictionaries / packed arrays compared deeply. Objects compare by identity.
func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> bool:
	_assertions += 1
	var diff := _difference(actual, expected, 0.0)
	if diff.is_empty():
		return true
	_failures.append(_m("expected %s, got %s%s" % [_fmt(expected), _fmt(actual), "" if diff.begins_with("$:") else " (" + diff + ")"], msg))
	return false


func assert_ne(actual: Variant, unexpected: Variant, msg: String = "") -> bool:
	_assertions += 1
	if not _difference(actual, unexpected, 0.0).is_empty():
		return true
	_failures.append(_m("expected anything but %s" % _fmt(unexpected), msg))
	return false


## |actual - expected| <= eps.
func assert_near(actual: float, expected: float, eps: float = 1e-6, msg: String = "") -> bool:
	_assertions += 1
	if absf(actual - expected) <= eps or actual == expected:
		return true
	_failures.append(_m("expected %s +/- %s, got %s (off by %s)" % [_num(expected), _num(eps), _num(actual), _num(absf(actual - expected))], msg))
	return false


## Component-wise |a - b| <= eps for Vector2 / Vector3 / Vector2i / Vector3i.
func assert_vec_near(actual: Variant, expected: Variant, eps: float = 1e-6, msg: String = "") -> bool:
	_assertions += 1
	var a := _vec_components(actual)
	var b := _vec_components(expected)
	if a.is_empty() or a.size() != b.size():
		_failures.append(_m("assert_vec_near needs two vectors of the same size, got %s and %s" % [_fmt(actual), _fmt(expected)], msg))
		return false
	for i in a.size():
		if absf(a[i] - b[i]) > eps:
			_failures.append(_m("expected %s +/- %s, got %s" % [_fmt(expected), _num(eps), _fmt(actual)], msg))
			return false
	return true


## Same length and element-wise equal (assert_eq semantics; numbers within `eps` when eps > 0).
func assert_array_eq(actual: Variant, expected: Variant, msg: String = "", eps: float = 0.0) -> bool:
	_assertions += 1
	var t := typeof(actual)
	var u := typeof(expected)
	var lists := (t == TYPE_ARRAY or (t >= TYPE_PACKED_BYTE_ARRAY and t <= TYPE_PACKED_VECTOR4_ARRAY)) \
		and (u == TYPE_ARRAY or (u >= TYPE_PACKED_BYTE_ARRAY and u <= TYPE_PACKED_VECTOR4_ARRAY))
	if not lists:
		_failures.append(_m("assert_array_eq needs two arrays, got %s and %s" % [type_string(t), type_string(u)], msg))
		return false
	var diff := _difference(actual, expected, eps)
	if diff.is_empty():
		return true
	_failures.append(_m("arrays differ: %s" % diff, msg))
	return false


## Deep JSON-value equality (ODJson.first_difference) with numeric tolerance `eps`.
func assert_json_eq(actual: Variant, expected: Variant, eps: float = 0.0, msg: String = "") -> bool:
	_assertions += 1
	var diff := ODJson.first_difference(actual, expected, eps)
	if diff.is_empty():
		return true
	_failures.append(_m("JSON differs: %s" % diff, msg))
	return false


## `container` holds `item`: Array / packed array element, Dictionary key, or String substring.
func assert_has(container: Variant, item: Variant, msg: String = "") -> bool:
	_assertions += 1
	var found := false
	match typeof(container):
		TYPE_DICTIONARY:
			found = (container as Dictionary).has(item)
		TYPE_STRING, TYPE_STRING_NAME:
			found = String(container).contains(str(item))
		TYPE_ARRAY:
			for v: Variant in container:
				if _difference(v, item, 0.0).is_empty():
					found = true
					break
		_:
			var t := typeof(container)
			if t >= TYPE_PACKED_BYTE_ARRAY and t <= TYPE_PACKED_VECTOR4_ARRAY:
				for v: Variant in Array(container):
					if _difference(v, item, 0.0).is_empty():
						found = true
						break
	if found:
		return true
	_failures.append(_m("%s does not contain %s" % [_fmt(container, 160), _fmt(item)], msg))
	return false


## Engine errors logged during the current test (push_error, SCRIPT ERROR...) do not fail it.
func expect_engine_errors() -> void:
	_allow_engine_errors = true


# ───────────────────────────── helpers ─────────────────────────────

## Parse a JSON file (res:// or user://). Records a failure and returns null on any problem.
func load_json(path: String) -> Variant:
	var errors: Array[String] = []
	var data: Variant = ODJson.read_file(path, errors)
	for e: String in errors:
		fail("load_json: " + e)
	return data


## Number of assertions made by the current test (the runner flags a test that made none).
func assertion_count() -> int:
	return _assertions


## The running SceneTree (the test runner), for suites that need to add nodes or await frames:
##     tree().root.add_child(node)      await tree().process_frame
## Suites must free the nodes they add.
func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _m(what: String, msg: String) -> String:
	return what if msg.is_empty() else "%s: %s" % [msg, what]


func _difference(a: Variant, b: Variant, eps: float) -> String:
	# Objects and other non-JSON values compare with == (identity for objects).
	var ta := typeof(a)
	var tb := typeof(b)
	if ta == TYPE_OBJECT or tb == TYPE_OBJECT:
		return "" if ta == tb and a == b else "$: objects differ"
	if _is_vector(a) or _is_vector(b):
		return "" if ta == tb and a == b else "$: %s != %s" % [_fmt(a), _fmt(b)]
	return ODJson.first_difference(a, b, eps)


func _is_vector(v: Variant) -> bool:
	return typeof(v) in [TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_COLOR]


func _vec_components(v: Variant) -> PackedFloat64Array:
	match typeof(v):
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return PackedFloat64Array([v.x, v.y])
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return PackedFloat64Array([v.x, v.y, v.z])
		TYPE_VECTOR4, TYPE_VECTOR4I:
			return PackedFloat64Array([v.x, v.y, v.z, v.w])
	return PackedFloat64Array()


func _num(f: float) -> String:
	return String.num(f, 9)


func _fmt(v: Variant, limit: int = 120) -> String:
	var s: String
	if v is String:
		s = "\"%s\"" % v
	elif v is StringName:
		s = "&\"%s\"" % v
	elif v is float:
		s = _num(v)
	else:
		s = var_to_str(v).replace("\n", " ")
	return s if s.length() <= limit else s.substr(0, limit) + "..."
