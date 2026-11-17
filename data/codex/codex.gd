class_name Codex
extends RefCounted
## The field guide (docs/CODEX.md): loads data/codex/codex.json, answers "which entries exist, in
## what order, and which are unlocked", and turns game happenings into unlocks.
##
## Node-free and persistence-free, like DlgSeenStore: the game loads the saved id list into
## load_unlocked() at boot and writes unlocked_ids() back whenever `unlocked` fires. The menu reads
## groups() / entries_in() / is_unlocked() / illustration_path().
##
## Reporting API (call from game/, each returns the ids newly unlocked by that call):
##   note_level(level_id, enemy_types, entity_kinds, end_modes)   when a level's briefing opens
##   note_level_dict(level_json)                                  same, from a parsed level file
##   note_sim_event(type)                                         for every SimEvent in a take or review
##   note_story_trigger(trigger)                                  bark triggers: "rescue", "ghostTake"
##   note_gear(owned_item_ids)                                    at boot and whenever loot is awarded
## `always` entries unlock in load_unlocked() / _init, so a fresh save already has them.

## Emitted once per newly unlocked entry (drive a "new page" toast and the save write from it).
signal unlocked(entry_id: String)

const DATA_PATH: String = "res://data/codex/codex.json"

## SimEvent types some entry listens for; note_sim_event() ignores everything else cheaply.
var _sim_events: Dictionary[String, bool] = {}
var _data: Dictionary = {}
var _entries: Array[Dictionary] = []
var _by_id: Dictionary[String, Dictionary] = {}
var _unlocked: Dictionary[String, bool] = {}
## Ids unlocked since the last clear_new(): the menu shows a "new" pip on them.
var _new: Dictionary[String, bool] = {}


func _init(path: String = DATA_PATH) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		_data = parsed
	var raw: Variant = _data.get("entries", [])
	if raw is Array:
		for v: Variant in raw:
			if v is Dictionary and v.has("id"):
				var e: Dictionary = v
				_entries.append(e)
				_by_id[str(e["id"])] = e
				for c: Dictionary in _conditions(e):
					if str(c.get("type", "")) == "simEvent":
						_sim_events[str(c.get("event", ""))] = true
	_unlock_always()


# ───────────────────────────── reading ─────────────────────────────

## True when codex.json was found and parsed.
func is_loaded() -> bool:
	return not _entries.is_empty()


func title() -> String:
	return str(_data.get("title", "Field Guide"))


func subtitle() -> String:
	return str(_data.get("subtitle", ""))


## Text for a page that has not been unlocked.
func locked_text() -> String:
	return str(_data.get("lockedText", ""))


## Footnotes about what the numbers assume ("note", "counting", "placements").
func baseline() -> Dictionary:
	var b: Variant = _data.get("baseline", {})
	return b if b is Dictionary else {}


## [{ id, title, blurb }] in display order.
func groups() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = _data.get("groups", [])
	if raw is Array:
		for g: Variant in raw:
			if g is Dictionary:
				out.append(g)
	return out


## Every entry of a group, in display order, locked or not.
func entries_in(group_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in _entries:
		if str(e.get("group", "")) == group_id:
			out.append(e)
	return out


## The entry dictionary ({ id, group, title, rule, notes, numbers, unlock, illustration }) or {}.
func entry(entry_id: String) -> Dictionary:
	return _by_id.get(entry_id, {})


func entry_count() -> int:
	return _entries.size()


func unlocked_count() -> int:
	return _unlocked.size()


func is_unlocked(entry_id: String) -> bool:
	return _unlocked.has(entry_id)


## Unlocked since the last clear_new() (not persisted).
func is_new(entry_id: String) -> bool:
	return _new.has(entry_id)


func clear_new(entry_id: String = "") -> void:
	if entry_id == "":
		_new.clear()
	else:
		_new.erase(entry_id)


## res:// path of an entry's plate (1024x1024 PNG), or "" for an unknown entry.
func illustration_path(entry_id: String) -> String:
	var e: Dictionary = entry(entry_id)
	if e.is_empty():
		return ""
	var pattern: String = str(_data.get("illustrationPath", "res://assets/codex/{illustration}.png"))
	return pattern.replace("{illustration}", str(e.get("illustration", entry_id)))


## The entry for an enemy type as the simulation spells it ("grunt" ... "boss"), or "".
## Use it to open the right page from a failure note ("struck by brute b2").
func entry_for_enemy(enemy_type: String) -> String:
	return _first_with("enemySeen", "enemy", enemy_type)


## The entry for a level entity kind ("spikes", "crusher", "laser", "breakable" ...), or "".
func entry_for_entity(kind: String) -> String:
	return _first_with("entitySeen", "kind", kind)


# ───────────────────────────── persistence ─────────────────────────────

## Replace the unlocked set from a saved array (unknown ids and non-strings are dropped), then add
## the `always` entries. Does not emit `unlocked` and marks nothing as new.
func load_unlocked(arr: Variant) -> void:
	_unlocked.clear()
	_new.clear()
	if arr is Array or arr is PackedStringArray:
		for v: Variant in arr:
			if (v is String or v is StringName) and _by_id.has(str(v)):
				_unlocked[str(v)] = true
	_unlock_always()


## Sorted, unique: stable in the save file.
func unlocked_ids() -> Array[String]:
	var out: Array[String] = []
	for k: String in _unlocked:
		out.append(k)
	out.sort()
	return out


## Unlock one entry directly (debug menus, tests). Returns true if it was locked.
func unlock(entry_id: String) -> bool:
	if not _by_id.has(entry_id) or _unlocked.has(entry_id):
		return false
	_unlocked[entry_id] = true
	_new[entry_id] = true
	unlocked.emit(entry_id)
	return true


func unlock_all() -> void:
	for e: Dictionary in _entries:
		unlock(str(e["id"]))


# ───────────────────────────── reporting ─────────────────────────────

## A level's briefing opened. `enemy_types` are EnemyDef.type values, `entity_kinds` are
## LevelDef.entities[].kind values, `end_modes` is LevelDef.endModes. Duplicates are fine.
func note_level(level_id: String, enemy_types: Array, entity_kinds: Array, end_modes: Array) -> Array[String]:
	var got: Array[String] = []
	for e: Dictionary in _entries:
		if _unlocked.has(str(e["id"])):
			continue
		for c: Dictionary in _conditions(e):
			var hit := false
			match str(c.get("type", "")):
				"levelStarted":
					hit = str(c.get("level", "")) == level_id
				"enemySeen":
					hit = _has_str(enemy_types, str(c.get("enemy", "")))
				"entitySeen":
					hit = _has_str(entity_kinds, str(c.get("kind", "")))
				"endModeOffered":
					var modes: Variant = c.get("modes", [])
					if modes is Array:
						for m: Variant in modes:
							if _has_str(end_modes, str(m)):
								hit = true
			if hit:
				if unlock(str(e["id"])):
					got.append(str(e["id"]))
				break
	return got


## note_level() from a parsed data/levels/*.json dictionary.
func note_level_dict(level: Dictionary) -> Array[String]:
	var enemy_types: Array = []
	var kinds: Array = []
	var ents: Variant = level.get("entities", [])
	if ents is Array:
		for v: Variant in ents:
			if v is Dictionary:
				var kind: String = str(v.get("kind", ""))
				kinds.append(kind)
				if kind == "enemy":
					enemy_types.append(str(v.get("type", "")))
	var modes: Variant = level.get("endModes", [])
	return note_level(str(level.get("id", "")), enemy_types, kinds, modes if modes is Array else [])


## A SimEvent happened in a take or a review (pass SimEvent.type: "selfDeath", "desync", "clang",
## "hit", "enemyStagger" ...). Cheap for types no entry cares about.
func note_sim_event(type: String) -> Array[String]:
	if not _sim_events.has(type):
		return []
	return _note_simple("simEvent", "event", type)


## A story bark trigger fired (docs/story/INTEGRATION.md "Barks"): "rescue", "ghostTake".
func note_story_trigger(trigger: String) -> Array[String]:
	return _note_simple("storyTrigger", "trigger", trigger)


## The player's inventory (gear item ids). Call at boot and after loot.
func note_gear(owned_item_ids: Array) -> Array[String]:
	var got: Array[String] = []
	for id: Variant in owned_item_ids:
		got.append_array(_note_simple("gearOwned", "item", str(id)))
	return got


# ───────────────────────────── internals ─────────────────────────────

func _conditions(e: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var u: Variant = e.get("unlock", {})
	if u is Dictionary:
		var any: Variant = u.get("any", [])
		if any is Array:
			for c: Variant in any:
				if c is Dictionary:
					out.append(c)
	return out


func _unlock_always() -> void:
	for e: Dictionary in _entries:
		for c: Dictionary in _conditions(e):
			if str(c.get("type", "")) == "always":
				_unlocked[str(e["id"])] = true


func _note_simple(type: String, field: String, value: String) -> Array[String]:
	var got: Array[String] = []
	for e: Dictionary in _entries:
		if _unlocked.has(str(e["id"])):
			continue
		for c: Dictionary in _conditions(e):
			if str(c.get("type", "")) == type and str(c.get(field, "")) == value:
				if unlock(str(e["id"])):
					got.append(str(e["id"]))
				break
	return got


func _first_with(type: String, field: String, value: String) -> String:
	for e: Dictionary in _entries:
		for c: Dictionary in _conditions(e):
			if str(c.get("type", "")) == type and str(c.get(field, "")) == value:
				return str(e["id"])
	return ""


static func _has_str(arr: Array, value: String) -> bool:
	for v: Variant in arr:
		if str(v) == value:
			return true
	return false
