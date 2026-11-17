class_name MenuModels
extends RefCounted
## Node-free view-models derived from the screen models the game pushes (prototype ui/menus/logic.ts
## campaignNodes / loadoutView / resultsView). Views read these; tests check them. Never instantiated.


# ───────────────────────────── campaign ─────────────────────────────

class LootLine:
	extends RefCounted
	var name: String
	## Slot title (MenuFormat.slot_label(slot).title).
	var slot: String
	var effect: String
	var lore: String
	## Gear id (icon lookup: res://assets/ui/icons/gear/<id>.png); "" when unknown.
	var id: String = ""

	func _init(p_name: String, p_slot: String, p_effect: String, p_lore: String = "", p_id: String = "") -> void:
		name = p_name
		slot = p_slot
		effect = p_effect
		lore = p_lore
		id = p_id


class CampaignNode:
	extends RefCounted
	var id: String
	var nav_id: String
	var index: int
	## "01", "02"... depth counter on the descent.
	var depth: String
	var name: String
	var tagline: String
	var theme: StringName
	var theme_label: String
	var max_tapes: int
	var speeds: Array[String] = []
	var end_modes: Array[String] = []
	var cleared: bool
	var unlocked: bool
	var current: bool
	## Last node on the path: the time machine (WORLD-05).
	var final: bool
	var loot_count: int
	var loot_found: bool
	## Named only once found: unfound loot stays a mystery (naming it would spoil the find).
	var loot_items: Array[LootLine] = []
	## STATUS_*: single-line status for the node badge.
	var status: StringName


const STATUS_CLEARED: StringName = &"cleared"
const STATUS_NEXT: StringName = &"next"
const STATUS_OPEN: StringName = &"open"
const STATUS_LOCKED: StringName = &"locked"


## Label for a 0-based position on the campaign path.
static func depth_label(index: int) -> String:
	return "%02d" % (index + 1)


## Label for a level by its own index. Campaign levels are numbered from 1 (data/levels/README.md),
## so the index is already the number the player sees.
static func level_number(level: LevelDef) -> String:
	return "%02d" % level.index


static func campaign_nodes(model: CampaignScreenModel) -> Array[CampaignNode]:
	var out: Array[CampaignNode] = []
	if model == null:
		return out
	var n := model.levels.size()
	for i in n:
		var e := model.levels[i]
		var l := e.level
		var node := CampaignNode.new()
		if not e.unlocked:
			node.status = STATUS_LOCKED
		elif e.cleared:
			node.status = STATUS_CLEARED
		elif i == model.current:
			node.status = STATUS_NEXT
		else:
			node.status = STATUS_OPEN
		node.id = l.id
		node.nav_id = "level:%s" % l.id
		node.index = i
		node.depth = depth_label(i)
		node.name = l.name
		node.tagline = l.tagline
		node.theme = l.theme
		node.theme_label = MenuFormat.theme_label(l.theme)
		node.max_tapes = l.max_tapes
		for s in l.speeds:
			node.speeds.append(MenuFormat.speed_label(s))
		for m in l.end_modes:
			node.end_modes.append(MenuFormat.end_mode_label(m))
		node.cleared = e.cleared
		node.unlocked = e.unlocked
		node.current = i == model.current
		node.final = i == n - 1
		node.loot_count = l.loot.size()
		node.loot_found = e.cleared
		if e.cleared and e.has_loot:
			for g in e.loot:
				node.loot_items.append(LootLine.new(g.name, MenuFormat.slot_label(g.slot).title, g.effect, "", g.id))
		out.append(node)
	return out


# ───────────────────────────── loadout ─────────────────────────────

class SlotView:
	extends RefCounted
	var slot: StringName
	var nav_id: String
	var title: String
	var kind: String
	## null = nothing equipped / unknown id.
	var equipped: GearItem
	var owned: int
	var has_fresh: bool


class ItemRow:
	extends RefCounted
	var item: GearItem
	var nav_id: String
	var equipped: bool
	var fresh: bool


class LoadoutView:
	extends RefCounted
	var slots: Array[SlotView] = []
	var active_slot: StringName
	## Every owned item for the active slot, inventory order (GEAR-04: nothing is ever discarded).
	var items: Array[ItemRow] = []
	var summary: Array[String] = []


static func items_for_slot(model: LoadoutScreenModel, slot: StringName) -> Array[GearItem]:
	var out: Array[GearItem] = []
	for g in model.inventory:
		if g.slot == slot:
			out.append(g)
	return out


static func equipped_item(model: LoadoutScreenModel, slot: StringName) -> GearItem:
	var id := model.loadout.get_slot(slot)
	for g in model.inventory:
		if g.id == id:
			return g
	return null


static func find_item(model: LoadoutScreenModel, id: String) -> GearItem:
	for g in model.inventory:
		if g.id == id:
			return g
	return null


static func loadout_view(model: LoadoutScreenModel, active_slot: StringName) -> LoadoutView:
	var v := LoadoutView.new()
	for slot in GearSlot.ALL:
		var lab := MenuFormat.slot_label(slot)
		var owned := items_for_slot(model, slot)
		var s := SlotView.new()
		s.slot = slot
		s.nav_id = "slot:%s" % slot
		s.title = lab.title
		s.kind = lab.kind
		s.equipped = equipped_item(model, slot)
		s.owned = owned.size()
		s.has_fresh = false
		for g in owned:
			if model.fresh.has(g.id):
				s.has_fresh = true
				break
		v.slots.append(s)
	v.active_slot = active_slot
	for item in items_for_slot(model, active_slot):
		var row := ItemRow.new()
		row.item = item
		row.nav_id = "item:%s" % item.id
		row.equipped = model.loadout.get_slot(active_slot) == item.id
		row.fresh = model.fresh.has(item.id)
		v.items.append(row)
	v.summary = model.summary.duplicate()
	return v


# ───────────────────────────── results ─────────────────────────────

class ResultsView:
	extends RefCounted
	var title: String
	var win: bool
	var level_name: String
	var depth: String
	var tapes_used: int
	var max_tapes: int
	var notes: Array[String] = []
	var loot: Array[LootLine] = []
	var has_next: bool


static func results_view(m: ResultsModel) -> ResultsView:
	var v := ResultsView.new()
	var win := m.outcome != null and m.outcome.win
	v.title = "LEVEL CLEARED" if win else "ATTEMPT ENDED"
	v.win = win
	v.level_name = m.level.name if m.level != null else ""
	v.depth = level_number(m.level) if m.level != null else "--"
	v.tapes_used = m.tapes_used
	v.max_tapes = m.level.max_tapes if m.level != null else OD.TAPE_COUNT
	if m.outcome != null:
		v.notes = m.outcome.notes.duplicate()
	for g in m.loot:
		v.loot.append(LootLine.new(g.name, MenuFormat.slot_label(g.slot).title, g.effect, g.lore, g.id))
	v.has_next = m.has_next
	return v
