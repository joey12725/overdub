extends SceneTree
## Headless test runner (docs/GODOT-PORT.md "Tests").
##
##   bash tools/gd test [filter]
##   (= godot_console --headless --path <repo> -s res://tests/run_tests.gd -- [filter])
##
## Discovers every res://tests/**/test_*.gd whose res:// path contains `filter` (all when absent),
## instantiates each suite (it must extend ODTest, tests/od_test.gd), and for every method whose name
## starts with `test_` (in declaration order) calls before_each(), the test, after_each(), awaiting
## each. Prints one FAIL line per failed assertion, then a summary. Exit code 0 only when at least
## one test ran and nothing failed; 1 otherwise. A suite that fails to load (parse error, wrong base
## class) is a failure, not a skip. A runtime script error logged while a test runs fails that test
## (detected through the engine log file, see _LogWatch), and so does a test that made no assertion.

const TEST_ROOT := "res://tests"

var _failed_tests: int = 0
var _passed_tests: int = 0
var _suite_failures: int = 0
var _assertions: int = 0
var _log: _LogWatch


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var filter := args[0] if args.size() > 0 else ""
	var started := Time.get_ticks_msec()
	_log = _LogWatch.new()
	if not _log.available:
		print("[tests] note: engine log file unavailable; runtime script errors cannot be attributed to tests")

	var files: Array[String] = []
	_collect(TEST_ROOT, files)
	files.sort()
	var selected: Array[String] = []
	for f: String in files:
		if filter.is_empty() or f.contains(filter):
			selected.append(f)
	print("[tests] %d suite(s) match%s" % [selected.size(), "" if filter.is_empty() else " '%s'" % filter])

	for path: String in selected:
		await _run_suite(path)

	var total := _passed_tests + _failed_tests
	var ms := Time.get_ticks_msec() - started
	print("")
	print("[tests] %d suite(s), %d test(s): %d passed, %d failed, %d suite load failure(s); %d assertion(s); %d ms" % [
		selected.size(), total, _passed_tests, _failed_tests, _suite_failures, _assertions, ms])
	var ok := total > 0 and _failed_tests == 0 and _suite_failures == 0
	if total == 0:
		print("[tests] FAILED: no tests ran")
	else:
		print("[tests] %s" % ("PASSED" if ok else "FAILED"))
	quit(0 if ok else 1)


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.include_hidden = false
	for sub: String in dir.get_directories():
		if not sub.begins_with("."):
			_collect(dir_path.path_join(sub), out)
	for file: String in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			out.append(dir_path.path_join(file))


func _suite_fail(path: String, msg: String) -> void:
	_suite_failures += 1
	print("FAIL %s :: <load> - %s" % [_short(path), msg])


func _run_suite(path: String) -> void:
	_log.mark()
	# Every suite starts from the built-in cassette colours (an app or settings test switches the
	# shared palette; that must not leak into the next suite).
	OD.set_tape_palette(PackedColorArray())
	var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	var script := res as GDScript
	# A suite (or a script it depends on) that failed to compile can still come back as a resource,
	# so any error logged while loading counts as a load failure.
	var load_errors := _log.new_errors()
	if script == null or not script.can_instantiate() or not load_errors.is_empty():
		_suite_fail(path, "suite failed to load%s" % ("" if load_errors.is_empty() else ": " + " | ".join(load_errors)))
		return
	var inst: Variant = script.new()
	if not (inst is ODTest):
		_suite_fail(path, "suite does not extend ODTest (res://tests/od_test.gd)")
		if inst is Object and not (inst is RefCounted):
			(inst as Object).free()
		return
	var suite: ODTest = inst
	suite._suite_path = path

	var names: Array[String] = []
	var has_before := false
	var has_after := false
	for m: Dictionary in script.get_script_method_list():
		var n: String = m["name"]
		if n == "before_each":
			has_before = true
		elif n == "after_each":
			has_after = true
		elif n.begins_with("test_") and not names.has(n):
			names.append(n)
	if names.is_empty():
		_suite_fail(path, "suite has no test_ methods")
		return

	for n: String in names:
		suite._test_name = n
		suite._failures.clear()
		suite._assertions = 0
		suite._allow_engine_errors = false
		_log.mark()
		if has_before:
			await suite.call("before_each")
		await suite.call(n)
		if has_after:
			await suite.call("after_each")
		var failures: Array[String] = suite._failures.duplicate()
		var engine_errors := _log.new_errors()
		if not suite._allow_engine_errors:
			for e: String in engine_errors:
				failures.append("engine error: " + e)
		if suite._assertions == 0 and failures.is_empty():
			failures.append("test made no assertions")
		_assertions += suite._assertions
		if failures.is_empty():
			_passed_tests += 1
		else:
			_failed_tests += 1
			for f: String in failures:
				print("FAIL %s :: %s - %s" % [_short(path), n, f])


func _short(path: String) -> String:
	return path.trim_prefix("res://")


## Reads what the engine appended to its log file since the last mark() and extracts error lines.
## Godot flushes the log on every error, so script errors raised inside a test are visible right
## after the test returns.
class _LogWatch:
	var available: bool = false
	var _path: String = ""
	var _pos: int = 0

	func _init() -> void:
		if not bool(ProjectSettings.get_setting("debug/file_logging/enable_file_logging", false)) \
				and not bool(ProjectSettings.get_setting("debug/file_logging/enable_file_logging.pc", false)):
			return
		_path = ProjectSettings.globalize_path(str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log")))
		available = FileAccess.file_exists(_path)
		mark()

	func mark() -> void:
		if not available:
			return
		var f := FileAccess.open(_path, FileAccess.READ)
		_pos = f.get_length() if f != null else _pos

	## Error lines ("SCRIPT ERROR: ...", "ERROR: ...") written since the last mark(); advances the mark.
	func new_errors() -> Array[String]:
		var out: Array[String] = []
		if not available:
			return out
		var f := FileAccess.open(_path, FileAccess.READ)
		if f == null:
			return out
		var length := f.get_length()
		if length <= _pos:
			_pos = length
			return out
		f.seek(_pos)
		var text := f.get_buffer(length - _pos).get_string_from_utf8()
		_pos = length
		var lines := text.split("\n")
		for i in lines.size():
			var line := lines[i].strip_edges()
			if line.begins_with("SCRIPT ERROR:") or line.begins_with("ERROR:"):
				var detail := line
				# The next line usually says where ("at: func (res://path.gd:12)").
				if i + 1 < lines.size() and lines[i + 1].strip_edges().begins_with("at:"):
					detail += " " + lines[i + 1].strip_edges()
				out.append(detail)
		return out
