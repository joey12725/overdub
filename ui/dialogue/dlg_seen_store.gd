class_name DlgSeenStore
extends RefCounted
## "Seen" flags for story beats and coach marks: the small persistence interface the dialogue and
## coach layers use instead of touching game/save.gd. Node-free.
##
## The game owns persistence: it loads the array from the save into load_array() at boot and writes
## to_array() back whenever `changed` fires (docs/DIALOGUE.md "Save data"). Proposed SaveData field:
## `"seen": string[]` (sorted, unique). Keys used:
##   coach.<markId>                 a coach mark was completed (dismissed by its condition / timeout)
##   story.<levelId>.intro|outro    a level's intro / outro was shown (INTEGRATION.md introSeen/outroSeen)
##   story.<levelId>.<section>      level firsts (firstDeath, firstDesync, ...)
##   once.<key>                     once.* beats (firstDeath, firstGhostTake, firstDesync, ...)
##   story.ending                   the ending played
##   hint.<hintId>                  a failure hint was shown at least once

signal changed

var _flags: Dictionary[String, bool] = {}


func has(key: String) -> bool:
	return _flags.has(key)


## Set a flag; emits `changed` only when it was not set before.
func mark(key: String) -> void:
	if key == "" or _flags.has(key):
		return
	_flags[key] = true
	changed.emit()


func unmark(key: String) -> void:
	if _flags.erase(key):
		changed.emit()


## Remove every flag whose key starts with `prefix` ("coach." resets the tutorial marks).
func clear_prefix(prefix: String) -> void:
	var gone := false
	for k: String in _flags.keys():
		if k.begins_with(prefix):
			_flags.erase(k)
			gone = true
	if gone:
		changed.emit()


## Replace everything from a saved array (non-strings ignored). Does not emit `changed`.
func load_array(arr: Variant) -> void:
	_flags.clear()
	if arr is Array or arr is PackedStringArray:
		for v: Variant in arr:
			if v is String or v is StringName:
				_flags[str(v)] = true


## Sorted, unique: stable in the save file.
func to_array() -> Array[String]:
	var out: Array[String] = []
	for k: String in _flags.keys():
		out.append(k)
	out.sort()
	return out


func size() -> int:
	return _flags.size()
