extends UiBase
## The UI facade implementation (prototype ui/index.ts createUi), one full-screen root above the 3D
## view. Children, bottom to top:
##   Hud        the in-level HUD (res://ui/hud; shown on 'play' / 'pause'), which owns the
##              world-anchored widgets (badges, momentum gauge, off-screen chevrons, boss bar) and
##              the beatSight ticks on its ruler
##   Dialogue   DialogueLayer (res://ui/dialogue): dialogue box with portraits, barks, coach marks,
##              failure hints - above the HUD, below the menus
##   Menus      MenuController: title, campaign, loadout, settings, pause, results (+ loot reveal),
##              ending, Field Guide
##   Card       chapter cards between levels (show_chapter_card)
##   Toasts     MenuToasts
## The UI never mutates game state: every choice leaves as a UiIntent through `intent`, and the game
## layer answers with set_* / show_screen.
##
## Game-layer hooks beyond UiBase (all optional; docs/GODOT-PORT.md "UI integration hooks"):
##   dialogue                          the DialogueLayer (docs/DIALOGUE.md: begin_level, play_intro,
##                                     update(view, events, dt, snap), notify_action/input, ...)
##   set_world_camera(cam)             world -> screen for widgets, coach marks and barks
##   load_level_widgets(level, loadout, boss_memory) / set_boss_memory(m) / set_aim(angle)
##   update_world(snap, view, events)  every rendered frame next to update_hud
##   set_codex(codex)                  the Field Guide's Codex (campaign + pause entries)
##   open_codex(entry_id)              open the guide on a page (e.g. after a failed run)
##   set_codex_hint(entry_id)          the page the pause menu's Field Guide opens on ("" = none)
##   set_replays({level_id: {ok, note}})  "Watch" buttons on the path; intent type "watchReplay"
##   show_chapter_card(theme, subtitle) -> MenuChapterCard (await its `finished`)

## The dialogue / bark / coach-mark / failure-hint layer (null before _ready).
var dialogue: DialogueLayer = null
var menus: MenuController
var toasts: MenuToasts
var card: MenuChapterCard = null

## Accessibility state the UI applies itself (from SaveSettings when it has the field, else from
## the settings screen's session value).
var reduce_flashing: bool = false
var text_scale: float = 1.0
var voices: bool = true


func _init() -> void:
	# Built here, not in _ready, so the game may push models before adding the UI to the tree.
	menus = MenuController.new()
	menus.intent.connect(_on_menu_intent)
	add_child(menus)
	toasts = MenuToasts.new()
	add_child(toasts)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# The root itself never eats clicks: on 'play' the world (and the HUD's own controls) get them.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	theme = MenuStyle.build_theme()
	# HUD first (below menus and toasts); UiBase routes its clicks out as session intents.
	attach_hud()
	var ps := load("res://ui/dialogue/dialogue_layer.tscn") as PackedScene
	if ps != null:
		dialogue = ps.instantiate() as DialogueLayer
		dialogue.name = "Dialogue"
		add_child(dialogue)
		move_child(dialogue, hud.get_index() + 1)
		var map := Callable(hud, "world_point_to_screen") if hud.has_method("world_point_to_screen") else Callable()
		dialogue.setup(hud, map)
	show_screen(screen)


func show_screen(s: StringName) -> void:
	super(s)
	if menus != null:
		menus.show_screen(s)


func update_hud(view: SessionView, pulse: MusicPulse) -> void:
	if menus != null and view != null:
		menus.set_play_context(view.level.name if view.level != null else "", view.phase)
	super(view, pulse)


func set_campaign(model: CampaignScreenModel) -> void:
	menus.set_campaign(model)


func set_loadout(model: LoadoutScreenModel) -> void:
	menus.set_loadout(model)


func set_results(model: ResultsModel) -> void:
	menus.set_results(model)


## Also forwards `patterns` to the HUD (super): the colour-blind cassette patterns apply to the HUD
## decks and to every cassette the menus draw. Accessibility and story options go to the HUD, the
## palette and the dialogue layer.
func set_settings(settings: SaveSettings) -> void:
	super(settings)
	menus.set_settings(settings)
	_apply_options()


func toast(text: String, tone: StringName = TONE_INFO) -> void:
	toasts.push(text, tone)


func navigate(dir: StringName) -> void:
	if card != null and is_instance_valid(card):
		if dir == NAV_ACCEPT or dir == NAV_BACK:
			card.skip()
		return
	if screen == UiScreen.PLAY:
		return
	menus.navigate(dir)


func set_device(device: StringName) -> void:
	super(device)
	menus.set_device(device)
	if dialogue != null:
		dialogue.set_device(device)


func set_bindings(prompts: Dictionary[StringName, ButtonPrompt]) -> void:
	super(prompts)
	if dialogue != null:
		dialogue.set_bindings(prompts)


func dispose() -> void:
	if toasts != null:
		toasts.clear()
	if menus != null:
		menus.dispose()
	if dialogue != null:
		dialogue.end_level()


# ───────────────────────────── world widgets ─────────────────────────────

## The world view's Camera3D (WorldViewBase.ctx.camera).
func set_world_camera(cam: Camera3D) -> void:
	if hud != null and hud.has_method("set_world_camera"):
		hud.call("set_world_camera", cam)


## Custom sim -> screen mapping func(sim: Vector2, h: float) -> Vector2 (tests, tools).
func set_world_projector(fn: Callable) -> void:
	if hud != null and hud.has_method("set_world_projector"):
		hud.call("set_world_projector", fn)


func load_level_widgets(level: LevelDef, loadout: ResolvedLoadout, boss_memory: BossMemory = null) -> void:
	if hud != null and hud.has_method("load_level_widgets"):
		hud.call("load_level_widgets", level, loadout, boss_memory)


func set_boss_memory(memory: BossMemory) -> void:
	if hud != null and hud.has_method("set_boss_memory"):
		hud.call("set_boss_memory", memory)


func set_aim(angle: float) -> void:
	if hud != null and hud.has_method("set_aim"):
		hud.call("set_aim", angle)


## Every rendered frame while a level is up (next to update_hud): the frame's snapshot and events.
func update_world(snap: FrameSnapshot, view: SessionView = null, events: Array[SimEvent] = []) -> void:
	if hud != null and hud.visible and hud.has_method("update_world"):
		hud.call("update_world", snap, view, events)


# ───────────────────────────── Field Guide / replays / cards ─────────────────────────────

func set_codex(codex: Codex) -> void:
	menus.set_codex(codex)


func open_codex(entry_id: String = "") -> void:
	menus.open_codex(entry_id)


## The page for what stopped the last failed run: the pause menu's Field Guide opens on it
## (docs/CODEX.md "Where it appears"). "" clears it.
func set_codex_hint(entry_id: String) -> void:
	menus.codex_hint = entry_id


## level id -> {"ok": bool, "note": String}: which solved levels have a kept replay to watch.
func set_replays(replays: Dictionary) -> void:
	menus.campaign_logic.replays = replays.duplicate()
	menus.campaign_version += 1
	menus._refresh_if([UiScreen.CAMPAIGN])
	if menus.screen == UiScreen.CAMPAIGN:
		menus._sync(false)


## Full-screen chapter card (wordless art + title) for a LevelTheme; await `finished` on the result.
func show_chapter_card(theme_id: StringName, subtitle: String = "", hold: float = 2.6) -> MenuChapterCard:
	if card != null and is_instance_valid(card):
		card.queue_free()
	card = MenuChapterCard.new(theme_id, subtitle, hold)
	add_child(card)
	move_child(card, toasts.get_index())
	return card


# ───────────────────────────── options ─────────────────────────────

func _on_menu_intent(i: UiIntent) -> void:
	# Setting changes the UI can show at once (accessibility, story options) apply before the game
	# echoes them back.
	if i.type == UiIntentType.SETTING:
		_apply_options()
	emit_intent(i)


func _opt(key: String) -> Variant:
	var l := menus.settings_logic if menus.screen != UiScreen.PAUSE else menus.pause_logic.settings
	return l.value_of(key)


func _apply_options() -> void:
	var sl := menus.settings_logic
	var pl := menus.pause_logic.settings
	# Keep both settings panels (title and pause) in step for the extras.
	if menus.screen == UiScreen.PAUSE:
		sl.extras = pl.extras.duplicate()
	else:
		pl.extras = sl.extras.duplicate()
	reduce_flashing = bool(_opt("reduceFlashing"))
	text_scale = float(_opt("textScale"))
	voices = bool(_opt("voices"))
	# Cassette colours come from the core (OD.tape_color); the "cassettePalette" intent asks the game
	# to switch them, and UiPalette follows whatever the core uses.
	if hud != null and hud.has_method("set_reduce_flashing"):
		hud.call("set_reduce_flashing", reduce_flashing)
	if hud != null:
		hud.set_patterns(bool(_opt("patterns")))
	if hud != null and hud.has_method("set_hold_mode"):
		hud.call("set_hold_mode", String(_opt("holdMode")) == "press")
	if dialogue != null:
		dialogue.set_options(bool(_opt("barks")), bool(_opt("coachMarks")), float(_opt("textSpeed")), bool(_opt("patterns")))
		dialogue.set_text_scale(text_scale)
	toasts.set_text_scale(text_scale)
	menus.set_text_scale(text_scale)
	if hud != null and hud.has_method("set_text_scale"):
		hud.call("set_text_scale", text_scale)
