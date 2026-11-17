class_name SaveData
extends RefCounted
## Persistent campaign save (types.ts SaveData). from_dict() is structural only (wrong-typed fields
## fall back to defaults); the game's save module validates ids, sanitises the loadout and falls back
## to a fresh save on a foreign version (game/save.ts validateSave).
##
## `seen` and `codex` are the Godot game's additions (the story / onboarding flags and the Field
## Guide pages). Like the extra settings they are written only when non-empty, so an untouched save
## keeps the prototype's exact format and an older save loads them as empty.

const VERSION: int = 1

var version: int = VERSION
## Ids of cleared levels.
var cleared: Array[String] = []
## Owned gear ids (generous inventory: never discarded; GEAR-04).
var inventory: Array[String] = []
var loadout: Loadout = Loadout.new()
var settings: SaveSettings = SaveSettings.new()
## Story / onboarding "seen" flags (docs/DIALOGUE.md "Save data": story.*, once.*, coach.*, phase.*,
## fact.*, hint.*, chapter.*). Sorted, unique.
var seen: Array[String] = []
## Unlocked Field Guide entry ids (data/codex/codex.gd unlocked_ids()). Sorted, unique.
var codex: Array[String] = []


func copy() -> SaveData:
	var o := SaveData.new()
	o.version = version
	o.cleared = cleared.duplicate()
	o.inventory = inventory.duplicate()
	o.loadout = loadout.copy()
	o.settings = settings.copy()
	o.seen = seen.duplicate()
	o.codex = codex.duplicate()
	return o


static func from_dict(d: Dictionary) -> SaveData:
	var o := SaveData.new()
	o.version = ODJson.integer(d, "version", 0)
	o.cleared = ODJson.strings(d.get("cleared"))
	o.inventory = ODJson.strings(d.get("inventory"))
	o.loadout = Loadout.from_dict(ODJson.dict(d, "loadout"))
	o.settings = SaveSettings.from_dict(ODJson.dict(d, "settings"))
	o.seen = ODJson.strings(d.get("seen"))
	o.codex = ODJson.strings(d.get("codex"))
	return o


func to_dict() -> Dictionary:
	var out := {
		"version": version,
		"cleared": ODJson.strings_to_array(cleared),
		"inventory": ODJson.strings_to_array(inventory),
		"loadout": loadout.to_dict(),
		"settings": settings.to_dict(),
	}
	if not seen.is_empty():
		out["seen"] = ODJson.strings_to_array(seen)
	if not codex.is_empty():
		out["codex"] = ODJson.strings_to_array(codex)
	return out
