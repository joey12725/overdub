class_name GameCampaign
extends RefCounted
## Fixed-path campaign progression (port of prototype/src/game/campaign.ts; LEVEL-08, LEVEL-09,
## GEAR-01..04, APPAREL-02).
##
##  - The path is the levels in index order. The first level is always open; every other level opens
##    once the one before it is cleared. Cleared levels can always be replayed (LEVEL-09).
##  - Clearing a level awards its loot into the inventory the first time only; nothing is ever
##    removed from the inventory (GEAR-04).
##  - The loadout can change only between levels (GEAR-03): while a level attempt is in progress
##    `equip` refuses, so a committed tape is never reinterpreted under different gear.
##  - Every loadout is sanitised against the inventory (owned items of the right slot only).
##
## Pure state + functions over SaveData; persistence is the caller's job (GameSave).


## Result of record_clear.
class ClearResult:
	extends RefCounted
	## True the first time this level is cleared.
	var first_clear: bool = false
	## Items newly added to the inventory by this clear (empty on revisits).
	var loot: Array[GearItem] = []


## Levels on the path, sorted by index (stable: equal indices keep their given order).
var levels: Array[LevelDef] = []
var catalogue: ContentData.GearCatalogue = null
var _save: SaveData = null
var _active_level: String = ""
## Item ids picked up since the loadout screen was last opened.
var _fresh: Array[String] = []

## The save (validated). Read-only from outside: change it through the methods.
var save: SaveData:
	get:
		return _save

## Id of the level whose attempt is in progress (gear is locked), or "" between levels.
var active_level: String:
	get:
		return _active_level


func _init(p_levels: Array[LevelDef], p_save: SaveData, p_catalogue: ContentData.GearCatalogue = null) -> void:
	catalogue = p_catalogue if p_catalogue != null else CampaignData.gear()
	# Stable insertion sort by index (Godot's sort is not stable; Array.prototype.sort is).
	for l: LevelDef in p_levels:
		var i := levels.size()
		while i > 0 and levels[i - 1].index > l.index:
			i -= 1
		levels.insert(i, l)
	_save = GameSave.validate_save(p_save, catalogue)


func _gear_items(ids: Array[String]) -> Array[GearItem]:
	var out: Array[GearItem] = []
	for id: String in ids:
		var it := catalogue.get_item(id)
		if it != null:
			out.append(it)
	return out


func _index_of(id: String) -> int:
	for i in levels.size():
		if levels[i].id == id:
			return i
	return -1


## The level with `id` on the path, or null.
func level(id: String) -> LevelDef:
	var i := _index_of(id)
	return levels[i] if i >= 0 else null


func is_cleared(id: String) -> bool:
	return _save.cleared.has(id)


## LEVEL-08: the first level and every level after a cleared one; LEVEL-09: cleared levels stay open.
func is_unlocked(id: String) -> bool:
	var i := _index_of(id)
	if i < 0:
		return false
	if i == 0 or is_cleared(id):
		return true
	return is_cleared(levels[i - 1].id)


## Index (into `levels`) of the next uncleared level; the last level once everything is cleared.
func current_index() -> int:
	for i in levels.size():
		if not is_cleared(levels[i].id):
			return i
	return maxi(0, levels.size() - 1)


## The level after `id` on the path, or null after the final level.
func next_level(id: String) -> LevelDef:
	var i := _index_of(id)
	return levels[i + 1] if i >= 0 and i + 1 < levels.size() else null


func all_cleared() -> bool:
	if levels.is_empty():
		return false
	for l: LevelDef in levels:
		if not is_cleared(l.id):
			return false
	return true


## Lock gear for a level attempt. Returns false (and changes nothing) if the level is locked.
func begin_level(id: String) -> bool:
	if not is_unlocked(id):
		return false
	_active_level = id
	return true


## The attempt is over (won, quit or abandoned): gear may change again.
func end_level() -> void:
	_active_level = ""


## Record a clear. Loot is awarded only on the first clear, and only items not already owned are
## reported as new.
func record_clear(id: String) -> ClearResult:
	var r := ClearResult.new()
	var lv := level(id)
	if lv == null or is_cleared(id):
		return r
	var s := _save.copy()
	for it: GearItem in _gear_items(lv.loot):
		if s.inventory.has(it.id):
			continue
		s.inventory.append(it.id)
		r.loot.append(it)
		_fresh.append(it.id)
	s.cleared.append(id)
	_save = s
	r.first_clear = true
	return r


## Equip an owned item between levels (GEAR-03). Returns false when a level attempt is active, the
## item is unknown, not owned, or belongs to another slot.
func equip(slot: StringName, id: String) -> bool:
	if _active_level != "":
		return false
	var item := catalogue.get_item(id)
	if item == null or item.slot != slot:
		return false
	var owned := false
	for it: GearItem in LoadoutRules.items_for_slot(_save.inventory, slot, catalogue):
		if it.id == id:
			owned = true
			break
	if not owned:
		return false
	var want := _save.loadout.copy()
	want.set_slot(slot, id)
	var lo := LoadoutRules.sanitise_loadout(want, _save.inventory, catalogue)
	if lo.get_slot(slot) != id:
		return false
	var s := _save.copy()
	s.loadout = lo
	_save = s
	return true


func set_settings(settings: SaveSettings) -> void:
	var s := _save.copy()
	s.settings = settings.copy()
	_save = GameSave.validate_save(s, catalogue)


## Story / onboarding flags (DialogueLayer.get_seen_flags()). Returns true when they changed.
func set_seen(flags: Array[String]) -> bool:
	var sorted := flags.duplicate()
	sorted.sort()
	if sorted == _save.seen:
		return false
	var s := _save.copy()
	s.seen = sorted
	_save = s
	return true


## Unlocked Field Guide pages (Codex.unlocked_ids()). Returns true when they changed.
func set_codex(ids: Array[String]) -> bool:
	var sorted := ids.duplicate()
	sorted.sort()
	if sorted == _save.codex:
		return false
	var s := _save.copy()
	s.codex = sorted
	_save = s
	return true


## Replace the whole save (erase / load). Ends any active attempt's gear lock.
func replace_save(p_save: SaveData) -> void:
	_save = GameSave.validate_save(p_save, catalogue)
	_active_level = ""
	_fresh = []


func resolved_loadout() -> ResolvedLoadout:
	return LoadoutRules.resolve_loadout(LoadoutRules.sanitise_loadout(_save.loadout, _save.inventory, catalogue), catalogue)


func campaign_model() -> CampaignScreenModel:
	var m := CampaignScreenModel.new()
	for lv: LevelDef in levels:
		var cleared := is_cleared(lv.id)
		var e := CampaignLevelEntry.make(lv, cleared, is_unlocked(lv.id))
		if cleared:
			e.loot = _gear_items(lv.loot)
			e.has_loot = true
		m.levels.append(e)
	m.current = current_index()
	return m


## Loadout screen model. `consume_fresh` clears the "new" markers (the screen is being opened).
func loadout_model(consume_fresh: bool = false) -> LoadoutScreenModel:
	var m := LoadoutScreenModel.new()
	for slot: StringName in OD.GEAR_SLOTS:
		m.inventory.append_array(LoadoutRules.items_for_slot(_save.inventory, slot, catalogue))
	m.loadout = _save.loadout.copy()
	m.summary = LoadoutRules.describe_loadout(_save.loadout, catalogue)
	m.fresh = _fresh.duplicate()
	if consume_fresh:
		_fresh = []
	return m
