extends SceneTree
## Headless self-check of the field guide:  bash tools/gd script res://data/codex/codex_selfcheck.gd
## Loads codex.json through Codex, checks every entry and plate, and walks the unlock API against
## data/levels/sandbox.json. Prints "CODEX OK" or the failures, and exits 1 on failure.

var _fails: Array[String] = []


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)


func _same(got: Array[String], want: Array) -> bool:
	if got.size() != want.size():
		return false
	for i: int in got.size():
		if got[i] != str(want[i]):
			return false
	return true


func _init() -> void:
	var cx := Codex.new()
	_check(cx.is_loaded(), "codex.json did not load")
	_check(cx.groups().size() == 5, "expected 5 groups")
	var seen: Dictionary[String, bool] = {}
	var total := 0
	for g: Dictionary in cx.groups():
		var list: Array[Dictionary] = cx.entries_in(str(g["id"]))
		_check(not list.is_empty(), "group %s is empty" % g["id"])
		for e: Dictionary in list:
			total += 1
			var id: String = str(e["id"])
			_check(not seen.has(id), "duplicate id %s" % id)
			seen[id] = true
			_check(str(e.get("rule", "")) != "", "%s: no rule" % id)
			var notes: Array = e.get("notes", [])
			_check(notes.size() >= 2 and notes.size() <= 3, "%s: needs 2-3 notes" % id)
			var path: String = cx.illustration_path(id)
			_check(ResourceLoader.exists(path) or FileAccess.file_exists(path), "%s: missing plate %s" % [id, path])
	_check(total == cx.entry_count(), "an entry belongs to no listed group")

	# A fresh guide has only the `always` pages.
	_check(cx.is_unlocked("tape-speed") and cx.is_unlocked("count-in"), "always pages are not unlocked")
	_check(not cx.is_unlocked("grunt") and not cx.is_unlocked("desync"), "pages unlocked too early")
	var fresh: int = cx.unlocked_count()

	# The sandbox has grunts, a turret, a laser and a breakable wall.
	var emitted: Array[String] = []
	cx.unlocked.connect(func(id: String) -> void: emitted.append(id))
	var level: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/sandbox.json"))
	_check(level is Dictionary, "sandbox.json did not parse")
	if level is Dictionary:
		var got: Array[String] = cx.note_level_dict(level)
		for want: String in ["grunt", "turret", "laser", "breakables"]:
			_check(got.has(want) and cx.is_unlocked(want) and cx.is_new(want), "sandbox should unlock %s" % want)
		_check(not cx.is_unlocked("stalker"), "sandbox must not unlock the stalker")
		_check(cx.note_level_dict(level).is_empty(), "a second visit must unlock nothing")
		_check(emitted.size() == got.size(), "unlocked signal count mismatch")

	_check(cx.note_sim_event("swing").is_empty(), "an unrelated sim event unlocked something")
	_check(_same(cx.note_sim_event("selfDeath"), ["dying-on-tape"]), "selfDeath should unlock dying-on-tape")
	_check(_same(cx.note_sim_event("desync"), ["desync"]), "desync should unlock desync")
	_check(cx.note_sim_event("clang").has("momentum"), "clang should unlock momentum")
	_check(_same(cx.note_story_trigger("rescue"), ["rescue"]), "rescue trigger should unlock rescue")
	_check(_same(cx.note_gear(["splice_blade", "needle_rail"]), ["ranged-pierce"]), "needle_rail should unlock ranged-pierce")
	_check(cx.note_level("11-the-archivist", [], [], ["stop"]).has("archivist"), "level 11 should unlock the Archivist")
	_check(cx.is_unlocked("end-modes"), "the sandbox offers repeat, so end-modes should be unlocked")
	var bare := Codex.new()
	_check(bare.note_level("x", [], [], ["stop"]).is_empty(), "stop alone must not unlock end-modes")
	_check(_same(bare.note_level("x", ["boss"], [], ["stop", "repeat"]), ["archivist", "end-modes"]), "boss + repeat should unlock archivist and end-modes")
	_check(cx.entry_for_enemy("boss") == "archivist", "entry_for_enemy(boss)")
	_check(cx.entry_for_entity("spikes") == "spikes", "entry_for_entity(spikes)")

	# Round trip through the save shape.
	var saved: Array[String] = cx.unlocked_ids()
	var again := Codex.new()
	again.load_unlocked(saved)
	_check(again.unlocked_ids() == saved, "save round trip changed the unlocked set")
	_check(not again.is_new("grunt"), "loading must not mark pages new")
	again.load_unlocked(["nonsense", 7])
	_check(again.unlocked_count() == fresh, "unknown ids must be dropped on load")

	if _fails.is_empty():
		print("CODEX OK  %d entries, %d plates checked" % [total, total])
		quit(0)
	else:
		for f: String in _fails:
			print("CODEX FAIL  " + f)
		quit(1)
