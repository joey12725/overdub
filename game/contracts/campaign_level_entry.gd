class_name CampaignLevelEntry
extends RefCounted
## One level on the campaign path (contracts.ts CampaignScreenModel.levels[] element).

var level: LevelDef = null
var cleared: bool = false
var unlocked: bool = false
## The resolved GearItems of level.loot, so the path can name what was found on a cleared level.
## Valid only when has_loot (absent = the path shows only how many items the level holds).
var loot: Array[GearItem] = []
var has_loot: bool = false


static func make(p_level: LevelDef, p_cleared: bool, p_unlocked: bool) -> CampaignLevelEntry:
	var e := CampaignLevelEntry.new()
	e.level = p_level
	e.cleared = p_cleared
	e.unlocked = p_unlocked
	return e
