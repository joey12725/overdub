class_name MenuResultsLogic
extends MenuSource
## Results screen logic (prototype ui/menus/logic.ts ResultsLogic): Next / Replay / Path / Loadout in
## one row. "Next level" plays next_id when the model names it, else continues to the path.

var model: ResultsModel = null

var _emit: Callable
var _focus_req: String = ""


func _init(emit: Callable) -> void:
	_emit = emit


func set_model(m: ResultsModel) -> void:
	model = m
	_focus_req = "next" if m.has_next else "path"


func menu() -> MenuDef:
	var m := model
	var entries: Array[MenuEntry] = []
	var col := 0
	if m != null and m.has_next:
		var next_id := m.next_id
		entries.append(MenuEntry.make("next", 0, col, func() -> void:
			if not next_id.is_empty():
				_emit.call(UiIntent.play_level(next_id))
			else:
				_emit.call(UiIntent.session(SessionAction.CONTINUE))))
		col += 1
	if m != null and m.level != null:
		var level_id := m.level.id
		entries.append(MenuEntry.make("replay", 0, col, func() -> void: _emit.call(UiIntent.play_level(level_id))))
		col += 1
	entries.append(MenuEntry.make("path", 0, col, func() -> void: _emit.call(UiIntent.session(SessionAction.CONTINUE))))
	col += 1
	entries.append(MenuEntry.make("loadout", 0, col, func() -> void: _emit.call(UiIntent.simple(UiIntentType.OPEN_LOADOUT))))
	return MenuDef.make(entries, func() -> void: _emit.call(UiIntent.session(SessionAction.CONTINUE)),
		"next" if m != null and m.has_next else "path")


func take_focus_request() -> String:
	var r := _focus_req
	_focus_req = ""
	return r
