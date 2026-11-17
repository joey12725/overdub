class_name MenuController
extends Control
## Menu shell (prototype ui/menus/menus.ts Menus): owns the menu screens' Controls, routes keyboard /
## gamepad navigation and the pointer through one MenuHost per screen, and turns choices into
## UiIntents through `emit`. Holds no game state: the game answers intents by calling the UiBase
## set_* / show_screen methods, which UiRoot forwards here.

## Emitted for every intent (UiRoot forwards it to UiBase.intent).
signal intent(i: UiIntent)

## The Field Guide is a menu-internal screen (no UiScreen value): opened from the campaign screen or
## the pause overlay, it returns there on back without a round trip through the game.
const CODEX: StringName = &"codex"

var title_logic: MenuTitleLogic
var campaign_logic: MenuCampaignLogic
var loadout_logic: MenuLoadoutLogic
var settings_logic: MenuSettingsLogic
var pause_logic: MenuPauseLogic
var results_logic: MenuResultsLogic
var ending_logic: MenuEndingLogic
var codex_logic: MenuCodexLogic
## The screen the Field Guide returns to (&"" when it is not open).
var codex_return: StringName = &""
## Page the pause menu's Field Guide opens on (what stopped the last failed run); "" = last read.
var codex_hint: String = ""
## The loot moment over the results screen (null when none is up).
var loot_reveal: WidgetLootReveal = null
var _loot_pending: bool = false

## UiScreen.* currently shown (&"" before the first show()).
var screen: StringName = &""
## Last screen that was not loadout / settings / pause: where those return to.
var origin: StringName = &""
var device: StringName = UiBase.DEVICE_KEYBOARD
## Colour-blind cassette patterns (SaveSettings.patterns).
var patterns: bool = false
var campaign_model: CampaignScreenModel = null
var campaign_version: int = 0
var loadout_version: int = 0
var results_version: int = 0
## Context from the HUD feed, used by the pause overlay.
var play_level_name: String = ""
var play_phase: StringName = &""
## Phase at the moment pause opened; the note about losing the take is about that moment.
var paused_phase: StringName = &""

var _views: Dictionary[StringName, MenuScreenView] = {}
var _host: MenuHost = null
var _built_screen: StringName = &""
var _built_key: String = ""
var _built_node: Control = null
var _nav: Dictionary[String, Array] = {}
var _last_focus: String = ""
## True while handling a pointer event: the pointer already shows where it is, so never auto-scroll.
var _pointer_driven: bool = false
var _scroll_memory: Dictionary[String, int] = {}
## Platforms where quitting the app makes no sense get no Quit entry on the title.
var _offer_quit: bool = not OS.has_feature("web")


func _init() -> void:
	name = "Menus"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var emit := func(i: UiIntent) -> void: intent.emit(i)
	var leave := func() -> void: emit.call(return_intent(origin))
	var has_progress := func() -> bool:
		if campaign_model == null:
			return false
		for e in campaign_model.levels:
			if e.cleared:
				return true
		return false
	title_logic = MenuTitleLogic.new(emit, has_progress, _offer_quit)
	campaign_logic = MenuCampaignLogic.new(emit)
	loadout_logic = MenuLoadoutLogic.new(emit, leave)
	settings_logic = MenuSettingsLogic.new(emit, leave)
	pause_logic = MenuPauseLogic.new(emit)
	results_logic = MenuResultsLogic.new(emit)
	ending_logic = MenuEndingLogic.new(emit)
	codex_logic = MenuCodexLogic.new(close_codex)
	_views[UiScreen.TITLE] = MenuTitleView.new(self, title_logic)
	_views[UiScreen.CAMPAIGN] = MenuCampaignView.new(self, campaign_logic)
	_views[UiScreen.LOADOUT] = MenuLoadoutView.new(self, loadout_logic)
	_views[UiScreen.SETTINGS] = MenuSettingsView.new(self, settings_logic)
	_views[UiScreen.PAUSE] = MenuPauseView.new(self, pause_logic)
	_views[UiScreen.RESULTS] = MenuResultsView.new(self, results_logic)
	_views[UiScreen.ENDING] = MenuEndingView.new(self, ending_logic)
	_views[CODEX] = MenuCodexView.new(self, codex_logic)


## Where "back" from a shared screen (loadout, settings) returns, based on where it was opened.
static func return_intent(from: StringName) -> UiIntent:
	if from == UiScreen.TITLE or from == &"":
		return UiIntent.simple(UiIntentType.OPEN_TITLE)
	return UiIntent.simple(UiIntentType.OPEN_CAMPAIGN)


var focus: String:
	get:
		return _host.focus if _host != null else ""


var loadout_model: LoadoutScreenModel:
	get:
		return loadout_logic.model


## The built screen root (null on 'play' / before the first show).
var current_node: Control:
	get:
		return _built_node


## The current screen's menu definition (empty on 'play').
func definition() -> MenuDef:
	return _host.definition if _host != null else MenuDef.new()


func paused_mid_take() -> bool:
	return paused_phase == SessionPhase.RECORDING or paused_phase == SessionPhase.COUNTIN


func show_screen(s: StringName) -> void:
	var prev := screen
	if s != CODEX:
		codex_return = &""
	if s != UiScreen.RESULTS:
		_close_loot()
	screen = s
	if s != UiScreen.LOADOUT and s != UiScreen.SETTINGS and s != UiScreen.PAUSE and s != CODEX:
		origin = s
	if s == UiScreen.PAUSE and prev != UiScreen.PAUSE:
		paused_phase = play_phase
	if s == UiScreen.PLAY or not _views.has(s):
		_host = null
		_drop_built()
		visible = false
		return
	visible = true
	if prev != s:
		match s:
			UiScreen.TITLE:
				title_logic.on_show()
			UiScreen.CAMPAIGN:
				campaign_logic.on_show()
			UiScreen.LOADOUT:
				loadout_logic.on_show()
			UiScreen.SETTINGS:
				settings_logic.on_show()
			UiScreen.PAUSE:
				pause_logic.on_show()
		if prev == CODEX and (s == UiScreen.CAMPAIGN or s == UiScreen.PAUSE):
			(campaign_logic if s == UiScreen.CAMPAIGN else pause_logic).request_focus("guide")
		_last_focus = ""
		# The host calls back during its own constructor (initial refresh); that call is ignored
		# (_host is still null) and the explicit _sync below builds the screen.
		_host = null
		_host = MenuHost.new(_source(s), _on_host_change)
	_sync(prev != s)


func _on_host_change(_focus: String) -> void:
	if _host != null:
		_sync(false)


func navigate(cmd: StringName) -> void:
	if loot_reveal != null and is_instance_valid(loot_reveal) and loot_reveal.visible:
		_loot_navigate(cmd)
		return
	if _host == null:
		return
	_host.navigate(cmd)


# ───────────────────────────── Field Guide ─────────────────────────────

## The game's Codex (data/codex/codex.gd): unlock state and NEW flags. Enables the "Field Guide"
## entries on the campaign screen and in the pause menu.
func set_codex(c: Codex) -> void:
	codex_logic.set_codex(c)
	var open := Callable(self, "open_codex") if c != null else Callable()
	campaign_logic.set_open_codex(open)
	pause_logic.set_open_codex(open)
	_refresh_if([UiScreen.CAMPAIGN, UiScreen.PAUSE])
	if screen == UiScreen.CAMPAIGN or screen == UiScreen.PAUSE:
		_sync(false)


## Open the Field Guide over the current screen, on `entry_id` when given (e.g. the page for what
## just killed a self: Codex.entry_for_enemy / entry_for_entity).
func open_codex(entry_id: String = "") -> void:
	if codex_logic.codex == null:
		return
	if entry_id == "" and screen == UiScreen.PAUSE and codex_hint != "":
		# From the pause menu after a failed run: the page for what stopped it.
		entry_id = codex_hint
	if screen != CODEX:
		codex_return = screen
	codex_logic.on_show(entry_id)
	var ret := codex_return
	show_screen(CODEX)
	codex_return = ret


func close_codex() -> void:
	var ret := codex_return if codex_return != &"" else UiScreen.CAMPAIGN
	codex_return = &""
	show_screen(ret)


func codex_open() -> bool:
	return screen == CODEX


func set_campaign(model: CampaignScreenModel) -> void:
	campaign_model = model
	campaign_logic.set_model(model)
	campaign_version += 1
	_refresh_if([UiScreen.CAMPAIGN, UiScreen.TITLE, UiScreen.ENDING])


func set_loadout(model: LoadoutScreenModel) -> void:
	loadout_logic.set_model(model)
	loadout_version += 1
	_refresh_if([UiScreen.LOADOUT, UiScreen.ENDING])


func set_results(model: ResultsModel) -> void:
	results_logic.set_model(model)
	results_version += 1
	_close_loot()
	_loot_pending = model != null and not model.loot.is_empty()
	_refresh_if([UiScreen.RESULTS])
	if screen == UiScreen.RESULTS:
		_sync(false)


# ───────────────────────────── loot moment (results) ─────────────────────────────

## Put the chest reveal (ui/widgets/loot_reveal.tscn) over the results screen for fresh loot. EQUIP
## NOW emits one equip intent per found item (the loadout rules decide what sticks) and opens the
## loadout; LATER just closes it. Either way the results screen underneath stays.
func _show_loot() -> void:
	_loot_pending = false
	var m := results_logic.model
	if m == null or m.loot.is_empty() or not is_inside_tree():
		return
	var ps := load("res://ui/widgets/loot_reveal.tscn") as PackedScene
	if ps == null:
		return
	loot_reveal = ps.instantiate() as WidgetLootReveal
	loot_reveal.name = "LootReveal"
	loot_reveal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(loot_reveal)
	var owned: Array = []
	var lm := loadout_logic.model
	var found: Dictionary = {}
	for it: GearItem in m.loot:
		found[it.id] = true
	if lm != null:
		for it: Variant in lm.inventory:
			var iid := str(it.id) if it is GearItem else str(it)
			if not found.has(iid):
				owned.append(iid)
	loot_reveal.show_loot(m.loot, m.level.theme if m.level != null else LevelTheme.UPPER, owned)
	loot_reveal.choice_made.connect(_on_loot_choice)


func _on_loot_choice(equip_now: bool, ids: PackedStringArray) -> void:
	var m := results_logic.model
	_close_loot()
	if equip_now and m != null:
		for it: GearItem in m.loot:
			if ids.has(it.id):
				intent.emit(UiIntent.equip(it.slot, it.id))
		intent.emit(UiIntent.simple(UiIntentType.OPEN_LOADOUT))


func _close_loot() -> void:
	if loot_reveal != null and is_instance_valid(loot_reveal):
		loot_reveal.queue_free()
	loot_reveal = null


func _loot_navigate(cmd: StringName) -> void:
	if cmd == UiBase.NAV_ACCEPT or cmd == UiBase.NAV_BACK:
		var ev := InputEventAction.new()
		ev.action = &"ui_accept" if cmd == UiBase.NAV_ACCEPT else &"ui_cancel"
		ev.pressed = true
		loot_reveal._unhandled_input(ev)


func set_settings(s: SaveSettings) -> void:
	settings_logic.set_model(s)
	pause_logic.settings.set_model(s)
	patterns = s.patterns
	_refresh_if([UiScreen.SETTINGS, UiScreen.PAUSE, UiScreen.CAMPAIGN, UiScreen.RESULTS])


## Text size option: menu body text scales by UiPalette.text_scale (MenuStyle.label); the current
## screen is rebuilt when it changes.
func set_text_scale(sc: float) -> void:
	if is_equal_approx(sc, _text_scale):
		return
	_text_scale = sc
	UiPalette.text_scale = clampf(sc, 0.75, 2.0)
	if _host != null:
		_drop_built()
		_sync(false)


var _text_scale: float = 1.0


func set_device(d: StringName) -> void:
	if d == device:
		return
	device = d
	_sync(false)


func set_play_context(level_name: String, phase: StringName) -> void:
	play_level_name = level_name
	play_phase = phase


func dispose() -> void:
	_host = null
	_drop_built()


# ───────────────────────────── called by views ─────────────────────────────

## Every nav item under `root` (a built screen).
func nav_items_of(root: Node) -> Array[MenuNavItem]:
	var out: Array[MenuNavItem] = []
	_collect(root, out)
	return out


## The nav items currently showing `id` (a slot has its tile and its doll pin).
func nav_items(id: String) -> Array:
	return _nav.get(id, [])


## Pointer hovered something belonging to entry `id`.
func pointer_hover(id: String) -> void:
	if _host == null:
		return
	_pointer_driven = true
	_host.hover(id)
	_pointer_driven = false


## Pointer clicked entry `id`: focus + accept.
func pointer_click(id: String) -> void:
	if _host == null:
		return
	_pointer_driven = true
	_host.click(id)
	_pointer_driven = false


## Mouse on a stepper: identical to left/right on that entry.
func adjust(id: String, delta: int) -> void:
	if _host == null:
		return
	_pointer_driven = true
	_host.adjust(id, delta)
	_pointer_driven = false


## A slider drag or quality chip: set an absolute value on the settings shown now.
func setting_set(key: String, value: Variant) -> void:
	var logic := pause_logic.settings if screen == UiScreen.PAUSE else settings_logic
	_pointer_driven = true
	if _host != null:
		_host.hover(key)
	logic.set_value(key, value)
	_sync(false)
	_pointer_driven = false


## Shake a control sideways (a locked level that refused).
func shake(c: Control) -> void:
	if not c.is_inside_tree():
		return
	var x := c.position.x
	var tw := c.create_tween()
	for d: float in [-10.0, 9.0, -7.0, 5.0, -3.0, 0.0]:
		tw.tween_property(c, "position:x", x + d, 0.045)


# ───────────────────────────── internals ─────────────────────────────

func _source(s: StringName) -> MenuSource:
	match s:
		UiScreen.TITLE:
			return title_logic
		UiScreen.CAMPAIGN:
			return campaign_logic
		UiScreen.LOADOUT:
			return loadout_logic
		UiScreen.SETTINGS:
			return settings_logic
		UiScreen.PAUSE:
			return pause_logic
		UiScreen.RESULTS:
			return results_logic
		UiScreen.ENDING:
			return ending_logic
		CODEX:
			return codex_logic
	return MenuSource.new()


func _refresh_if(screens: Array[StringName]) -> void:
	if screens.has(screen) and _host != null:
		_host.refresh()


func _drop_built() -> void:
	if _built_node != null:
		_remember_scrolls(_built_node)
		_built_node.hide()
		_built_node.queue_free()
	_built_node = null
	_built_screen = &""
	_built_key = ""
	_nav.clear()


## Rebuild the screen if its structure changed, then re-apply focus and in-place patches.
func _sync(entering: bool) -> void:
	if screen == &"" or screen == UiScreen.PLAY or _host == null or not _views.has(screen):
		return
	var view: MenuScreenView = _views[screen]
	var key := view.key()
	if _built_node == null or _built_screen != screen or _built_key != key:
		_drop_built()
		var node := view.build()
		MenuWidgets.passthrough(node)
		add_child(node)
		_built_node = node
		_built_screen = screen
		_built_key = key
		for item in nav_items_of(node):
			if not _nav.has(item.nav_id):
				_nav[item.nav_id] = []
			_nav[item.nav_id].append(item)
			item.hovered.connect(pointer_hover)
			item.clicked.connect(pointer_click)
		_restore_scrolls(node)
		if entering:
			_enter_animation(node)
		_last_focus = ""
	var f := _host.focus
	for id: String in _nav:
		for item: MenuNavItem in _nav[id]:
			item.set_focused(id == f)
	view.sync(_built_node, f)
	if screen == UiScreen.RESULTS and _loot_pending:
		_show_loot()
	if not f.is_empty() and f != _last_focus and not _pointer_driven:
		_scroll_to_focus(f)
	_last_focus = f


func _collect(n: Node, out: Array[MenuNavItem]) -> void:
	for c in n.get_children():
		if c is MenuNavItem:
			out.append(c)
		_collect(c, out)


func _scrollers(n: Node, out: Array[ScrollContainer]) -> void:
	for c in n.get_children():
		if c is ScrollContainer:
			out.append(c)
		_scrollers(c, out)


func _remember_scrolls(node: Node) -> void:
	var list: Array[ScrollContainer] = []
	_scrollers(node, list)
	for s in list:
		if s.has_meta(&"scroll_key"):
			_scroll_memory[String(s.get_meta(&"scroll_key"))] = s.scroll_vertical


func _restore_scrolls(node: Node) -> void:
	if not is_inside_tree():
		return
	var list: Array[ScrollContainer] = []
	_scrollers(node, list)
	for s in list:
		var k := String(s.get_meta(&"scroll_key", ""))
		if _scroll_memory.has(k):
			_set_scroll_later(s, _scroll_memory[k])


func _set_scroll_later(s: ScrollContainer, v: int) -> void:
	# Layout settles over the next frame; a scroll set before that would clamp to 0.
	await get_tree().process_frame
	if is_instance_valid(s) and s.is_inside_tree():
		s.scroll_vertical = v


func _enter_animation(node: Control) -> void:
	if not is_inside_tree():
		return
	node.modulate = Color(1, 1, 1, 0)
	node.position = Vector2(0, 14)
	var tw := node.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "modulate:a", 1.0, 0.18)
	tw.tween_property(node, "position", Vector2.ZERO, 0.22)


## Keep the keyboard cursor visible in long lists; the descent keeps it centred so what comes next
## is visible.
func _scroll_to_focus(id: String) -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	var items: Array = _nav.get(id, [])
	if items.is_empty() or _host == null or _host.focus != id:
		return
	var item: MenuNavItem = items[0]
	if not is_instance_valid(item) or not item.is_inside_tree():
		return
	var p := item.get_parent()
	var sc: ScrollContainer = null
	while p != null and p != _built_node:
		if p is ScrollContainer:
			sc = p
			break
		p = p.get_parent()
	if sc == null:
		return
	var view_rect := sc.get_global_rect()
	var r := item.get_global_rect()
	var target := sc.scroll_vertical
	if sc.get_meta(&"scroll_center", false):
		target = int(sc.scroll_vertical + (r.get_center().y - view_rect.get_center().y))
	elif r.position.y < view_rect.position.y:
		target = int(sc.scroll_vertical - (view_rect.position.y - r.position.y) - 8)
	elif r.end.y > view_rect.end.y:
		target = int(sc.scroll_vertical + (r.end.y - view_rect.end.y) + 8)
	var vbar := sc.get_v_scroll_bar()
	target = clampi(target, 0, maxi(0, int(vbar.max_value - vbar.page)))
	if target != sc.scroll_vertical:
		var tw := sc.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(sc, "scroll_vertical", target, 0.2)
