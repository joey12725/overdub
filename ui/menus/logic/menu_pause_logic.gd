class_name MenuPauseLogic
extends MenuSource
## Pause overlay logic (prototype ui/menus/logic.ts PauseLogic). Resume, Restart level (reset all),
## Settings (opened inside the overlay so "back" returns here without a round trip through the
## game's screen state) and Quit to path. The loadout is not offered: equipment is locked for the
## attempt.

const SUB_MENU: StringName = &"menu"
const SUB_SETTINGS: StringName = &"settings"

var sub: StringName = SUB_MENU
var settings: MenuSettingsLogic

var _emit: Callable
var _open_codex: Callable
var _focus_req: String = ""


## open_codex: opens the Field Guide inside the pause overlay (no entry when invalid).
func _init(emit: Callable, open_codex: Callable = Callable()) -> void:
	_emit = emit
	_open_codex = open_codex
	# Bound method (not a lambda capturing self): no reference cycle with the child logic.
	settings = MenuSettingsLogic.new(emit, _settings_back)


func _settings_back() -> void:
	sub = SUB_MENU
	_focus_req = "settings"


func on_show() -> void:
	sub = SUB_MENU
	_focus_req = "resume"


func menu() -> MenuDef:
	if sub == SUB_SETTINGS:
		return settings.menu()
	var entries: Array[MenuEntry] = [
		MenuEntry.make("resume", 0, 0, func() -> void: _emit.call(UiIntent.simple(UiIntentType.RESUME))),
		MenuEntry.make("restart", 1, 0, func() -> void:
			# REC-05: restart = wipe every cassette; then leave the pause overlay.
			_emit.call(UiIntent.session(SessionAction.RESET_ALL))
			_emit.call(UiIntent.simple(UiIntentType.RESUME))),
		MenuEntry.make("settings", 2, 0, func() -> void:
			sub = SUB_SETTINGS
			settings.on_show()),
		MenuEntry.make("quit", 4 if _open_codex.is_valid() else 3, 0, func() -> void: _emit.call(UiIntent.session(SessionAction.QUIT))),
	]
	if _open_codex.is_valid():
		entries.insert(3, MenuEntry.make("guide", 3, 0, func() -> void: _open_codex.call()))
	return MenuDef.make(entries, func() -> void: _emit.call(UiIntent.simple(UiIntentType.RESUME)), "resume")


## Offer the Field Guide (MenuController.set_codex wires it; an invalid Callable removes it).
func set_open_codex(c: Callable) -> void:
	_open_codex = c


## Focus `id` on the next refresh (returning from the Field Guide lands on its entry).
func request_focus(id: String) -> void:
	_focus_req = id


func take_focus_request() -> String:
	if sub == SUB_SETTINGS:
		return settings.take_focus_request()
	var r := _focus_req
	_focus_req = ""
	return r
