class_name ContentData
extends RefCounted
## Loads the shipped data files into typed classes (docs/GODOT-PORT.md "Data").
##
##   data/gear.json           {version: 1, items: GearItem[] (catalogue order), baseLoadout: Loadout}
##   data/levels/<id>.json    one LevelDef
##   data/levels/index.json   {version: 1, levels: [id...] (campaign order), extra: [id...]}
##   data/music/<id>.json     the composer's file for level <id> (and `menu`): its `music` block is
##                            the level's `music` (merged by art/music/merge.py), plus the extras the
##                            audio layer reads: stateMaps (OPEN-22), sfx (MUSIC-05 / OPEN-23),
##                            layers, bed (menu only). docs/MUSIC.md "Data format".
##
## All files are exported from the prototype by prototype/scripts/export-data.ts and match the
## TypeScript shapes exactly. Loading is pure (no caching, no globals) and thread-safe; callers that
## need the data repeatedly cache it (content/content.gd). Every loader returns null on a missing or
## malformed file and appends the reasons to `errors`.

const GEAR_PATH := "res://data/gear.json"
const LEVEL_DIR := "res://data/levels"
const LEVEL_INDEX_PATH := "res://data/levels/index.json"
const MUSIC_DIR := "res://data/music"
const MUSIC_SCHEMA := "overdub-music/1"


## One composer file (data/music/<id>.json, docs/MUSIC.md). `music` is the same block the level file
## carries (they are kept equal by art/music/merge.py and tests/content/test_music_files.gd); the
## rest is data for the audio layer, kept as parsed JSON because its shape is documented by the
## composer and read field by field by the director / sfx planner:
##   state_maps  {order, backgroundVoice, alive, dead, desynced, reversing, stopped, paramGlossary}
##   sfx         {palette, pitchRule, latency, classes, ui}
##   layers      [{cassette, role, formula, formulaName, equation, about}] (cassette order)
##   bed         menu only: {tracks: [{present, speed}] x4}
class MusicFile:
	extends RefCounted
	var id: String = ""
	## Tempo the piece was composed at; equals the level's bpm (the level file wins if they differ).
	var bpm: float = 0.0
	var title: String = ""
	var key: String = ""
	var music: LevelMusicDef = null
	var state_maps: Dictionary = {}
	var sfx: Dictionary = {}
	var layers: Array = []
	var bed: Dictionary = {}

	## SFX recipe of one event class (sfx.classes[name]), or {} when the file has none.
	func sfx_class(name: String) -> Dictionary:
		return ODJson.dict(ODJson.dict(sfx, "classes"), name)

	## The state map for one actor state ("dead", "desynced", "reversing", "stopped", "alive").
	func state_map(state: String) -> Variant:
		return state_maps.get(state)


## The gear catalogue: items in catalogue order (insertion order matters: UIs list items in it),
## lookup by id, and the baseline loadout (one plain item per slot; always owned, GEAR-04).
class GearCatalogue:
	extends RefCounted
	var items: Array[GearItem] = []
	var by_id: Dictionary[String, GearItem] = {}
	var base_loadout: Loadout = Loadout.new()

	## The item with `id`, or null.
	func get_item(id: String) -> GearItem:
		return by_id.get(id, null)

	func has_item(id: String) -> bool:
		return by_id.has(id)

	## Ids of the baseline items, i.e. the inventory a fresh save starts with (BASE_INVENTORY).
	func base_inventory() -> Array[String]:
		return base_loadout.ids()

	## Items of one slot in catalogue order.
	func items_in_slot(slot: StringName) -> Array[GearItem]:
		var out: Array[GearItem] = []
		for it: GearItem in items:
			if it.slot == slot:
				out.append(it)
		return out


## Load data/gear.json. Null (plus errors) when the file is missing, malformed, has duplicate ids or
## a base loadout naming an unknown item / an item of the wrong slot.
static func load_gear(errors: Array[String] = [], path: String = GEAR_PATH) -> GearCatalogue:
	var data: Variant = ODJson.read_file(path, errors)
	if not (data is Dictionary):
		if data != null:
			errors.append("%s: expected an object" % path)
		return null
	var d: Dictionary = data
	if ODJson.integer(d, "version", -1) != 1:
		errors.append("%s: unsupported version" % path)
		return null
	var cat := GearCatalogue.new()
	var ok := true
	for v: Variant in ODJson.array(d, "items"):
		if not (v is Dictionary):
			errors.append("%s: item is not an object" % path)
			ok = false
			continue
		var it := GearItem.from_dict(v)
		if it.id.is_empty() or cat.by_id.has(it.id):
			errors.append("%s: missing or duplicate item id '%s'" % [path, it.id])
			ok = false
			continue
		if not GearSlot.has(it.slot):
			errors.append("%s: item %s has unknown slot '%s'" % [path, it.id, it.slot])
			ok = false
			continue
		cat.items.append(it)
		cat.by_id[it.id] = it
	cat.base_loadout = Loadout.from_dict(ODJson.dict(d, "baseLoadout"))
	for slot: StringName in GearSlot.ALL:
		var id := cat.base_loadout.get_slot(slot)
		var it := cat.get_item(id)
		if it == null or it.slot != slot:
			errors.append("%s: baseLoadout.%s '%s' is not a %s item in the catalogue" % [path, slot, id, slot])
			ok = false
	return cat if ok else null


## Load data/levels/<id>.json. Null (plus errors) when missing / malformed or when the file's id does
## not match. Structural problems inside the level (unknown entity kinds...) are reported in `errors`
## and also make the load fail; semantic validation is LevelValidator's job.
static func load_level(id: String, errors: Array[String] = []) -> LevelDef:
	if id.is_empty() or id.contains("/") or id.contains("\\") or id.contains(".."):
		errors.append("load_level: bad level id '%s'" % id)
		return null
	var path := LEVEL_DIR.path_join(id + ".json")
	var data: Variant = ODJson.read_file(path, errors)
	if not (data is Dictionary):
		if data != null:
			errors.append("%s: expected an object" % path)
		return null
	var problems: Array[String] = []
	var level := LevelDef.from_dict(data, problems)
	if level.id != id:
		problems.append("id '%s' does not match the file name" % level.id)
	for p: String in problems:
		errors.append("%s: %s" % [path, p])
	return level if problems.is_empty() else null


## Ids of the campaign levels in path order (data/levels/index.json "levels"). With
## `include_extra`, the extra (off-path) levels such as the sandbox follow. Falls back to every
## data/levels/*.json (sorted, index.json excluded) when the index is missing.
static func list_level_ids(include_extra: bool = false, errors: Array[String] = []) -> Array[String]:
	var out: Array[String] = []
	if FileAccess.file_exists(LEVEL_INDEX_PATH):
		var data: Variant = ODJson.read_file(LEVEL_INDEX_PATH, errors)
		if data is Dictionary:
			out = ODJson.strings((data as Dictionary).get("levels"))
			if include_extra:
				for x: String in ODJson.strings((data as Dictionary).get("extra")):
					if not out.has(x):
						out.append(x)
		return out
	var dir := DirAccess.open(LEVEL_DIR)
	if dir == null:
		errors.append("%s: cannot open" % LEVEL_DIR)
		return out
	var files := dir.get_files()
	files.sort()
	for f: String in files:
		if f.ends_with(".json") and f != "index.json":
			out.append(f.get_basename())
	return out


## Every campaign level, sorted by LevelDef.index (LEVELS). Levels that fail to load are skipped and
## reported in `errors`.
static func load_campaign(errors: Array[String] = []) -> Array[LevelDef]:
	var out: Array[LevelDef] = []
	for id: String in list_level_ids(false, errors):
		var l := load_level(id, errors)
		if l != null:
			out.append(l)
	out.sort_custom(func(a: LevelDef, b: LevelDef) -> bool: return a.index < b.index)
	return out


## Load data/music/<id>.json (a level id, or "menu"). Null (plus errors) when missing or malformed.
static func load_music_file(id: String, errors: Array[String] = []) -> MusicFile:
	if id.is_empty() or id.contains("/") or id.contains("\\") or id.contains(".."):
		errors.append("load_music_file: bad id '%s'" % id)
		return null
	var path := MUSIC_DIR.path_join(id + ".json")
	if not FileAccess.file_exists(path):
		errors.append("%s: missing" % path)
		return null
	var data: Variant = ODJson.read_file(path, errors)
	if not (data is Dictionary):
		if data != null:
			errors.append("%s: expected an object" % path)
		return null
	var d: Dictionary = data
	if ODJson.string(d, "schema") != MUSIC_SCHEMA:
		errors.append("%s: schema is not %s" % [path, MUSIC_SCHEMA])
		return null
	if not (d.get("music") is Dictionary):
		errors.append("%s: no music block" % path)
		return null
	var f := MusicFile.new()
	f.id = ODJson.string(d, "id", id)
	if f.id != id:
		errors.append("%s: id '%s' does not match the file name" % [path, f.id])
		return null
	f.bpm = ODJson.num(d, "bpm")
	f.title = ODJson.string(d, "title")
	f.key = ODJson.string(d, "key")
	f.music = LevelMusicDef.from_dict(d["music"])
	f.state_maps = ODJson.dict(d, "stateMaps")
	f.sfx = ODJson.dict(d, "sfx")
	f.layers = ODJson.array(d, "layers")
	f.bed = ODJson.dict(d, "bed")
	return f
