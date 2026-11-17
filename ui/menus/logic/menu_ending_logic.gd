class_name MenuEndingLogic
extends MenuSource
## The closing card for reaching the time machine (prototype ui/menus/logic.ts EndingLogic): back to
## the path, or to the title.

var _emit: Callable


func _init(emit: Callable) -> void:
	_emit = emit


func menu() -> MenuDef:
	var entries: Array[MenuEntry] = [
		MenuEntry.make("path", 0, 0, func() -> void: _emit.call(UiIntent.simple(UiIntentType.OPEN_CAMPAIGN))),
		MenuEntry.make("title", 0, 1, func() -> void: _emit.call(UiIntent.simple(UiIntentType.OPEN_TITLE))),
	]
	return MenuDef.make(entries, func() -> void: _emit.call(UiIntent.simple(UiIntentType.OPEN_CAMPAIGN)), "path")
