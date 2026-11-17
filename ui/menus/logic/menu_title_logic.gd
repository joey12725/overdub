class_name MenuTitleLogic
extends MenuSource
## Title screen logic (prototype ui/menus/logic.ts TitleLogic). Owns only presentation state (the
## "erase progress?" confirm) and turns choices into UiIntents.

## Intent type for "quit the application" from the title. Not (yet) a member of UiIntentType: the
## contract has no quit-game intent, so the title emits UiIntent.simple(QUIT_GAME) and the game layer
## decides (save flush, get_tree().quit()). Omitted on platforms where quitting makes no sense.
const QUIT_GAME: StringName = &"quitGame"

## Showing "New descent erases progress — sure?".
var confirming_new: bool = false

var _emit: Callable
var _has_progress: Callable
var _offer_quit: bool
var _focus_req: String = ""
## -1 unknown, 0 false, 1 true: the progress state the cursor was last placed for.
var _last_progress: int = -1


## emit: func(UiIntent). has_progress: func() -> bool. offer_quit: show the Quit entry.
func _init(emit: Callable, has_progress: Callable, offer_quit: bool = true) -> void:
	_emit = emit
	_has_progress = has_progress
	_offer_quit = offer_quit


## Entering the title never resumes a half-answered "erase progress?" question.
func on_show() -> void:
	confirming_new = false


func has_progress() -> bool:
	return bool(_has_progress.call())


func menu() -> MenuDef:
	if confirming_new:
		var confirm: Array[MenuEntry] = [
			MenuEntry.make("new-no", 0, 0, _cancel_new),
			MenuEntry.make("new-yes", 0, 1, func() -> void:
				confirming_new = false
				_emit.call(UiIntent.simple(UiIntentType.ERASE_SAVE))
				_emit.call(UiIntent.simple(UiIntentType.OPEN_CAMPAIGN))),
		]
		return MenuDef.make(confirm, _cancel_new, "new-no")
	var progress := has_progress()
	var entries: Array[MenuEntry] = []
	var row := 0
	if progress:
		entries.append(MenuEntry.make("continue", row, 0, func() -> void: _emit.call(UiIntent.simple(UiIntentType.OPEN_CAMPAIGN))))
		row += 1
	entries.append(MenuEntry.make("new", row, 0, func() -> void:
		# A fresh save has nothing to lose, so no confirm step.
		if has_progress():
			confirming_new = true
			# Land on "keep" so a double press can never erase a save.
			_focus_req = "new-no"
		else:
			_emit.call(UiIntent.simple(UiIntentType.OPEN_CAMPAIGN))))
	row += 1
	entries.append(MenuEntry.make("loadout", row, 0, func() -> void: _emit.call(UiIntent.simple(UiIntentType.OPEN_LOADOUT))))
	row += 1
	entries.append(MenuEntry.make("settings", row, 0, func() -> void: _emit.call(UiIntent.simple(UiIntentType.OPEN_SETTINGS))))
	row += 1
	if _offer_quit:
		entries.append(MenuEntry.make("quit", row, 0, func() -> void: _emit.call(UiIntent.simple(QUIT_GAME))))
	return MenuDef.make(entries, Callable(), "continue" if progress else "new")


func take_focus_request() -> String:
	var r := _focus_req
	_focus_req = ""
	# The save usually arrives after the title is already up; when progress appears (or is erased)
	# the cursor jumps to the sensible default instead of staying on "New descent".
	var p := 1 if has_progress() else 0
	if p != _last_progress and not confirming_new:
		_last_progress = p
		if r.is_empty():
			return "continue" if p == 1 else "new"
	return r


func _cancel_new() -> void:
	confirming_new = false
	_focus_req = "new"
