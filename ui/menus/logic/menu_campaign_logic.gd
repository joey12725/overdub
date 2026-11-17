class_name MenuCampaignLogic
extends MenuSource
## The descent path (prototype ui/menus/logic.ts CampaignLogic; LEVEL-08 fixed path, LEVEL-09
## revisiting). Locked levels stay focusable so their name and tagline can be read; accepting one
## only "pokes" it (visual feedback, no intent).
##
## Optional extras (offered only when wired, so the plain path behaves exactly as before):
## - a "Field Guide" button in the top bar (open_codex callable, see MenuController.open_codex);
## - a "Watch again" button beside each cleared level that has a kept replay (`replays`, set by the
##   game through UiRoot.set_replays), which emits UiIntent type INTENT_WATCH_REPLAY with the id.

## UiIntent.type for "watch the kept replay of a solved level" (UiIntent.id = level id). Not in
## UiIntentType yet (that contract is not the UI's); the game layer matches this value.
const INTENT_WATCH_REPLAY: StringName = &"watchReplay"

var model: CampaignScreenModel = null
## Bumped when the player tries a locked level, so the view can shake it.
var locked_pokes: int = 0
var last_poked: String = ""

## level id -> {"ok": bool, "note": String}: kept replays (ok = playable; not ok = out of date).
var replays: Dictionary = {}

var _emit: Callable
var _on_back: Callable
var _open_codex: Callable
var _focus_req: String = ""


## emit: func(UiIntent). on_back: where "back" goes (default: the title). open_codex: opens the
## Field Guide (no button when invalid).
func _init(emit: Callable, on_back: Callable = Callable(), open_codex: Callable = Callable()) -> void:
	_emit = emit
	_on_back = on_back if on_back.is_valid() else _back_to_title
	_open_codex = open_codex


func has_guide() -> bool:
	return _open_codex.is_valid()


## Offer the Field Guide (MenuController.set_codex wires it; an invalid Callable removes it).
func set_open_codex(c: Callable) -> void:
	_open_codex = c


## Focus `id` on the next refresh (returning from the Field Guide lands on its button).
func request_focus(id: String) -> void:
	_focus_req = id


## A kept, playable replay for `level_id`.
func can_watch(level_id: String) -> bool:
	var r: Variant = replays.get(level_id)
	return r is Dictionary and bool((r as Dictionary).get("ok", false))


static func watch_intent(level_id: String) -> UiIntent:
	var i := UiIntent.new()
	i.type = INTENT_WATCH_REPLAY
	i.id = level_id
	return i


func _back_to_title() -> void:
	_emit.call(UiIntent.simple(UiIntentType.OPEN_TITLE))


func set_model(m: CampaignScreenModel) -> void:
	var first := model == null
	model = m
	# Entering the path lands on the next uncleared level (LEVEL-08: the path always moves down).
	if first:
		var cur := _current_entry()
		if cur != null:
			_focus_req = "level:%s" % cur.level.id


## Called when the screen is shown, so returning from a level re-focuses the next one.
func on_show() -> void:
	var cur := _current_entry()
	if cur != null:
		_focus_req = "level:%s" % cur.level.id


func menu() -> MenuDef:
	var entries: Array[MenuEntry] = [
		MenuEntry.make("back", 0, 0, func() -> void: _on_back.call()),
		MenuEntry.make("loadout", 0, 1, func() -> void: _emit.call(UiIntent.simple(UiIntentType.OPEN_LOADOUT))),
	]
	if _open_codex.is_valid():
		entries.append(MenuEntry.make("guide", 0, 2, func() -> void: _open_codex.call()))
	var levels: Array[CampaignLevelEntry] = model.levels if model != null else ([] as Array[CampaignLevelEntry])
	for i in levels.size():
		var e := levels[i]
		var id := e.level.id
		var nav := "level:%s" % id
		var unlocked := e.unlocked
		var on_accept := func() -> void:
			if unlocked:
				_emit.call(UiIntent.play_level(id))
			else:
				poke_locked(nav)
		# Locked levels stay focusable so their name / tagline can be read; accept just refuses
		# (visibly, via the poke counter the view animates).
		if e.cleared and can_watch(id):
			var watch := "watch:%s" % id
			entries.append(MenuEntry.make(nav, i + 1, 0, on_accept).link(UiBase.NAV_RIGHT, watch))
			entries.append(MenuEntry.make(watch, i + 1, 1, func() -> void: _emit.call(watch_intent(id))).link(UiBase.NAV_LEFT, nav))
		else:
			entries.append(MenuEntry.make(nav, i + 1, 0, on_accept).link(UiBase.NAV_RIGHT, "loadout"))
	var cur := _current_entry()
	return MenuDef.make(entries, func() -> void: _on_back.call(), "level:%s" % cur.level.id if cur != null else "back")


## Accept pressed on a locked level: purely visual feedback.
func poke_locked(nav_id: String) -> void:
	locked_pokes += 1
	last_poked = nav_id


func take_focus_request() -> String:
	var r := _focus_req
	_focus_req = ""
	return r


func _current_entry() -> CampaignLevelEntry:
	if model == null or model.current < 0 or model.current >= model.levels.size():
		return null
	return model.levels[model.current]
