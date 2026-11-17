class_name CampaignData
extends RefCounted
## Cached content for the game layer (prototype content/index.ts: LEVELS, SANDBOX, GEAR,
## BASE_LOADOUT, BASE_INVENTORY). ContentData loads files and caches nothing; this class loads each
## file once on first use and hands out the shared objects. Treat everything it returns as
## read-only: levels and gear items are shared by every session, screen and test.
##
## Main thread only (the caches are plain statics). A worker thread resolving an encounter receives
## its LevelDef / ResolvedLoadout through SimConfig and never calls in here.

static var _gear: ContentData.GearCatalogue = null
static var _levels: Array[LevelDef] = []
static var _levels_loaded: bool = false
static var _extra: Dictionary[String, LevelDef] = {}
static var _errors: Array[String] = []
static var _music: Dictionary[String, ContentData.MusicFile] = {}


## The gear catalogue (data/gear.json). Never null: a missing or broken file is reported with
## push_error and replaced by an empty catalogue whose base loadout is empty (the game then shows the
## problem instead of crashing).
static func gear() -> ContentData.GearCatalogue:
	if _gear == null:
		var errors: Array[String] = []
		_gear = ContentData.load_gear(errors)
		if _gear == null:
			for e: String in errors:
				_errors.append(e)
				push_error("CampaignData: %s" % e)
			_gear = ContentData.GearCatalogue.new()
	return _gear


## The baseline loadout (one plain item per slot; always owned). A copy.
static func base_loadout() -> Loadout:
	return gear().base_loadout.copy()


## The inventory a fresh save starts with (BASE_INVENTORY).
static func base_inventory() -> Array[String]:
	return gear().base_inventory()


## Campaign levels in path order (LEVELS; data/levels/index.json "levels", sorted by index). Levels
## that fail to load are skipped and reported with push_error.
static func levels() -> Array[LevelDef]:
	if not _levels_loaded:
		_levels_loaded = true
		var errors: Array[String] = []
		_levels = ContentData.load_campaign(errors)
		for e: String in errors:
			_errors.append(e)
			push_error("CampaignData: %s" % e)
	return _levels


## Any level by id: a campaign level, else an extra (off-path) level loaded on demand; null when
## there is no such level file.
static func level(id: String) -> LevelDef:
	for l: LevelDef in levels():
		if l.id == id:
			return l
	if _extra.has(id):
		return _extra[id]
	var errors: Array[String] = []
	var l := ContentData.load_level(id, errors)
	if l != null:
		_extra[id] = l
	return l


## The sandbox level (SANDBOX).
static func sandbox() -> LevelDef:
	return level("sandbox")


## The composer's file for a level id (or "menu"): data/music/<id>.json with the state maps and sfx
## pitch tables the audio layer reads (docs/MUSIC.md). Cached; null (reported once) when missing.
## The level's own `music` block (LevelDef.music) is the same music; prefer it for the score.
static func music_file(id: String) -> ContentData.MusicFile:
	if _music.has(id):
		return _music[id]
	var errors: Array[String] = []
	var f := ContentData.load_music_file(id, errors)
	for e: String in errors:
		_errors.append(e)
		push_warning("CampaignData: %s" % e)
	_music[id] = f
	return f


## The menu bed (data/music/menu.json: music at its bpm, bed.tracks = cassette states).
static func menu_music() -> ContentData.MusicFile:
	return music_file("menu")


## Load problems seen so far (for diagnostics screens / tests).
static func load_errors() -> Array[String]:
	return _errors.duplicate()
