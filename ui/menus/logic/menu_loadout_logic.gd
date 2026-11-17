class_name MenuLoadoutLogic
extends MenuSource
## Loadout screen logic (prototype ui/menus/logic.ts LoadoutLogic; APPAREL-03, GEAR-03/04). A column
## of the six slots plus Done (col 0) and the item list of the active slot (col 1). Browsing slots
## previews their items; accept on a slot enters its list on the equipped item; accept on an item
## emits an equip intent (nothing when it is already equipped).

var model: LoadoutScreenModel = null
var active_slot: StringName = GearSlot.HELMET
## Focus is inside the item list (vs. the slot column).
var in_list: bool = false

var _emit: Callable
var _leave: Callable
var _focus_req: String = ""


func _init(emit: Callable, leave: Callable) -> void:
	_emit = emit
	_leave = leave


func set_model(m: LoadoutScreenModel) -> void:
	model = m


func on_show() -> void:
	in_list = false
	_focus_req = "slot:%s" % active_slot


## Open the item list for a slot (accept on a slot tile, or a paper-doll pin click).
func open_slot(slot: StringName) -> void:
	active_slot = slot
	if model == null:
		return
	var items := MenuModels.items_for_slot(model, slot)
	if items.is_empty():
		return
	var eq := model.loadout.get_slot(slot)
	in_list = true
	var target := items[0].id
	for g in items:
		if g.id == eq:
			target = eq
			break
	_focus_req = "item:%s" % target


func menu() -> MenuDef:
	var entries: Array[MenuEntry] = []
	var items: Array[GearItem] = MenuModels.items_for_slot(model, active_slot) if model != null else ([] as Array[GearItem])
	var eq_id := model.loadout.get_slot(active_slot) if model != null else ""
	var first_item := ""
	for g in items:
		if g.id == eq_id:
			first_item = "item:%s" % eq_id
	if first_item.is_empty() and not items.is_empty():
		first_item = "item:%s" % items[0].id

	for row in GearSlot.ALL.size():
		var slot := GearSlot.ALL[row]
		var e := MenuEntry.make("slot:%s" % slot, row, 0, func() -> void: open_slot(slot))
		if slot == active_slot and not first_item.is_empty():
			e.link(UiBase.NAV_RIGHT, first_item)
		# The list always previews the slot under the cursor, so browsing slots shows options.
		e.on_focus(func() -> void:
			active_slot = slot
			in_list = false)
		entries.append(e)
	entries.append(MenuEntry.make("done", GearSlot.ALL.size(), 0, func() -> void: _leave.call()).on_focus(func() -> void: in_list = false))

	var slot_now := active_slot
	for i in items.size():
		var item := items[i]
		var id := "item:%s" % item.id
		var e := MenuEntry.make(id, i, 1, func() -> void:
			if model != null and model.loadout.get_slot(slot_now) != item.id:
				_emit.call(UiIntent.equip(slot_now, item.id)))
		e.link(UiBase.NAV_LEFT, "slot:%s" % slot_now)
		# Keep the cursor inside the list at its ends instead of falling into the slot column.
		if i == 0:
			e.link(UiBase.NAV_UP, id)
		if i == items.size() - 1:
			e.link(UiBase.NAV_DOWN, id)
		e.on_focus(func() -> void: in_list = true)
		entries.append(e)

	return MenuDef.make(entries, _back, "slot:%s" % active_slot)


func take_focus_request() -> String:
	var r := _focus_req
	_focus_req = ""
	return r


func _back() -> void:
	if in_list:
		in_list = false
		_focus_req = "slot:%s" % active_slot
	else:
		_leave.call()
