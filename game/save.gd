class_name GameSave
extends RefCounted
## Persistent campaign save (port of prototype/src/game/save.ts; GEAR-01, GEAR-04, LEVEL-08/09),
## stored as versioned JSON under user://.
##
## Policy: loading never fails and never returns something the game cannot use. A missing,
## unreadable, corrupt or foreign save falls back to a fresh one (baseline loadout and inventory); a
## partly damaged save keeps every field that still validates. Storage failures (read-only profile,
## full disk) are reported as `false` and swallowed: the game keeps running with its in-memory save.
##
## Storage is pluggable (FileStorage for the game, MemoryStorage for tests and as a fallback), so the
## whole policy is testable without touching the user's real save.

## Versioned key: a future incompatible format gets a new key instead of misreading this one.
const SAVE_KEY: String = "overdub.save.v1"
## Range the A/V offset is clamped to, in ms (matches the settings screen).
const AV_OFFSET_LIMIT: int = 300


## Minimal key/value storage surface (the prototype's SaveStorage). Every method reports failure
## instead of raising.
class Storage:
	extends RefCounted

	## Stored text for `key`, or null when absent or unreadable.
	func get_item(_key: String) -> Variant:
		return null

	## Store `value`; false when the storage refused.
	func set_item(_key: String, _value: String) -> bool:
		return false

	## Remove `key`; false when the storage refused. Removing an absent key succeeds.
	func remove_item(_key: String) -> bool:
		return false


## In-memory storage (tests, and a fallback when the disk refuses).
class MemoryStorage:
	extends Storage
	var data: Dictionary[String, String] = {}

	func _init(initial: Dictionary = {}) -> void:
		for k: Variant in initial:
			data[str(k)] = str(initial[k])

	func get_item(key: String) -> Variant:
		return data[key] if data.has(key) else null

	func set_item(key: String, value: String) -> bool:
		data[key] = value
		return true

	func remove_item(key: String) -> bool:
		data.erase(key)
		return true


## One JSON file per key under a directory (default user://). Writes go to a temporary file first
## and are then renamed over the old one, so a crash mid-write never leaves half a save.
class FileStorage:
	extends Storage
	var dir: String = "user://"

	func _init(p_dir: String = "user://") -> void:
		dir = p_dir

	func path_for(key: String) -> String:
		return dir.path_join(key + ".json")

	func get_item(key: String) -> Variant:
		var path := path_for(key)
		if not FileAccess.file_exists(path):
			# A write that was interrupted between its two renames leaves the old save as .bak (and
			# the new one as .tmp, which may be incomplete): put the old one back.
			if FileAccess.file_exists(path + ".bak"):
				DirAccess.rename_absolute(path + ".bak", path)
			if not FileAccess.file_exists(path):
				return null
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			return null
		var text := f.get_as_text()
		f.close()
		return text

	func set_item(key: String, value: String) -> bool:
		if not DirAccess.dir_exists_absolute(dir):
			if DirAccess.make_dir_recursive_absolute(dir) != OK:
				return false
		var path := path_for(key)
		var tmp := path + ".tmp"
		var f := FileAccess.open(tmp, FileAccess.WRITE)
		if f == null:
			return false
		f.store_string(value)
		var ok := f.get_error() == OK
		f.close()
		if not ok:
			DirAccess.remove_absolute(tmp)
			return false
		# Replace through a backup so there is always one whole save on disk: old -> .bak, new into
		# place, then drop the backup. A failure puts the old save back.
		var bak := path + ".bak"
		var had_old := FileAccess.file_exists(path)
		if had_old:
			if FileAccess.file_exists(bak):
				DirAccess.remove_absolute(bak)
			if DirAccess.rename_absolute(path, bak) != OK:
				DirAccess.remove_absolute(tmp)
				return false
		if DirAccess.rename_absolute(tmp, path) != OK:
			if had_old:
				DirAccess.rename_absolute(bak, path)
			DirAccess.remove_absolute(tmp)
			return false
		if had_old:
			DirAccess.remove_absolute(bak)
		return true

	func remove_item(key: String) -> bool:
		var path := path_for(key)
		for extra: String in [path + ".bak", path + ".tmp"]:
			if FileAccess.file_exists(extra):
				DirAccess.remove_absolute(extra)
		if not FileAccess.file_exists(path):
			return true
		return DirAccess.remove_absolute(path) == OK


## The game's storage: user://overdub.save.v1.json.
static func default_storage() -> Storage:
	return FileStorage.new("user://")


static func default_settings() -> SaveSettings:
	return SaveSettings.new()


## The baseline kit with nothing cleared.
static func fresh_save(catalogue: ContentData.GearCatalogue = null) -> SaveData:
	var cat := catalogue if catalogue != null else CampaignData.gear()
	var s := SaveData.new()
	s.version = 1
	s.cleared = []
	s.inventory = cat.base_inventory()
	s.loadout = cat.base_loadout.copy()
	s.settings = default_settings()
	return s


static func _string_list(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if not (v is Array):
		return out
	for x: Variant in v:
		if (x is String or x is StringName) and String(x).length() > 0 and not out.has(String(x)):
			out.append(String(x))
	return out


static func _unit(v: Variant, fallback: float) -> float:
	if ODJson.is_number(v):
		var f := float(v)
		if not is_nan(f) and not is_inf(f):
			return clampf(f, 0.0, 1.0)
	return fallback


static func _bool(v: Variant, fallback: bool) -> bool:
	return v if v is bool else fallback


static func _valid_settings(v: Variant) -> SaveSettings:
	var s: Dictionary = v if v is Dictionary else {}
	var d := default_settings()
	var o := SaveSettings.new()
	var off: float = float(d.av_offset_ms)
	if ODJson.is_number(s.get("avOffsetMs")):
		var f := float(s["avOffsetMs"])
		if not is_nan(f) and not is_inf(f):
			off = f
	o.master = _unit(s.get("master"), d.master)
	o.music = _unit(s.get("music"), d.music)
	o.sfx = _unit(s.get("sfx"), d.sfx)
	o.av_offset_ms = int(floorf(clampf(off, -AV_OFFSET_LIMIT, AV_OFFSET_LIMIT) + 0.5))
	o.screen_shake = _bool(s.get("screenShake"), d.screen_shake)
	o.patterns = _bool(s.get("patterns"), d.patterns)
	# The Godot game's options: each one validated by set_by_key (wrong kind / unknown choice keeps
	# the default), the voice volume clamped like the other faders.
	o.apply_extras(s)
	o.voice_volume = _unit(s.get("voiceVolume"), d.voice_volume)
	return o


## Coerce anything (parsed JSON, or a SaveData) into a usable SaveData. Unknown gear ids are dropped
## (an item removed from the catalogue cannot be equipped), the baseline items are always owned, and
## the loadout is sanitised against the inventory so it only ever holds owned items of the right slot.
static func validate_save(raw: Variant, catalogue: ContentData.GearCatalogue = null) -> SaveData:
	var cat := catalogue if catalogue != null else CampaignData.gear()
	var d: Variant = raw.to_dict() if raw is SaveData else raw
	if not (d is Dictionary):
		return fresh_save(cat)
	var rec: Dictionary = d
	var ver: Variant = rec.get("version")
	if not ODJson.is_number(ver) or float(ver) != 1.0:
		return fresh_save(cat)
	var inventory: Array[String] = cat.base_inventory()
	for id: String in _string_list(rec.get("inventory")):
		if cat.has_item(id) and not inventory.has(id):
			inventory.append(id)
	var loadout_in: Loadout = null
	if rec.get("loadout") is Dictionary:
		var ld: Dictionary = rec["loadout"]
		loadout_in = Loadout.new()
		for slot: StringName in OD.GEAR_SLOTS:
			var v: Variant = ld.get(String(slot))
			loadout_in.set_slot(slot, String(v) if (v is String or v is StringName) else "")
	var out := SaveData.new()
	out.version = 1
	out.cleared = _string_list(rec.get("cleared"))
	out.inventory = inventory
	out.loadout = LoadoutRules.sanitise_loadout(loadout_in, inventory, cat)
	out.settings = _valid_settings(rec.get("settings"))
	out.seen = _sorted(_string_list(rec.get("seen")))
	out.codex = _sorted(_string_list(rec.get("codex")))
	return out


static func _sorted(list: Array[String]) -> Array[String]:
	var out := list.duplicate()
	out.sort()
	return out


## Load the save; any problem yields a fresh save. Never fails.
static func load_save(storage: Storage = default_storage(), catalogue: ContentData.GearCatalogue = null) -> SaveData:
	if storage == null:
		return fresh_save(catalogue)
	var text: Variant = storage.get_item(SAVE_KEY)
	if not (text is String):
		return fresh_save(catalogue)
	var json := JSON.new()
	if json.parse(text) != OK:
		return fresh_save(catalogue)
	return validate_save(json.data, catalogue)


## Persist the save (validated first). False when storage is unavailable or refused the write.
static func write_save(data: SaveData, storage: Storage = default_storage(), catalogue: ContentData.GearCatalogue = null) -> bool:
	if storage == null:
		return false
	return storage.set_item(SAVE_KEY, ODJson.stringify(validate_save(data, catalogue).to_dict(), "  "))


## Remove the save entirely. False when storage is unavailable or refused.
static func erase_save(storage: Storage = default_storage()) -> bool:
	if storage == null:
		return false
	return storage.remove_item(SAVE_KEY)


static func memory_storage(initial: Dictionary = {}) -> MemoryStorage:
	return MemoryStorage.new(initial)
