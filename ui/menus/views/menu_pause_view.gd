class_name MenuPauseView
extends MenuScreenView
## Pause overlay (prototype pauseView): Resume, Restart level, Settings, Quit to path, over a dimmed
## HUD that stays readable. States that equipment is locked for the attempt, and warns when pausing
## threw away a take in progress (no tactical pause, OPEN-21).

## Fraction of the screen height above the HUD's bottom deck strip (the decks start near 71% of the
## height at 1600×900 and 1280×720).
const HUD_CLEAR_ANCHOR := 0.71
## ...and below the HUD's top-centre take banner and its bars-left meter.
const HUD_TOP_ANCHOR := 0.09

var logic: MenuPauseLogic


func _init(p_ctl: MenuController, p_logic: MenuPauseLogic) -> void:
	super(p_ctl)
	logic = p_logic


func key() -> String:
	return "%s|%s|%s|%s|%s|%s" % [logic.sub, logic.settings.confirming_erase, ctl.play_level_name, ctl.paused_mid_take(), ctl.device, ctl.codex_logic.codex != null]


func build() -> Control:
	var root := screen_root("Pause")
	var shade := ColorRect.new()
	# Settings is a full modal: dim the HUD further so its setup card does not read through the
	# translucent settings panel.
	shade.color = Color(MenuStyle.INK, 0.86 if logic.sub == MenuPauseLogic.SUB_SETTINGS else 0.58)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	# The HUD stays readable under the overlay, so the prompts live inside the panel instead of over
	# the beat ruler at the bottom of the screen.
	if logic.sub == MenuPauseLogic.SUB_SETTINGS:
		var sp := MenuSettingsView.panel(ctl, logic.settings)
		(sp.get_child(0) as VBoxContainer).add_child(_prompts(["←→ adjust"]))
		centred(root, sp, MenuSettingsView.PANEL_W)
		return root

	var p := MenuWidgets.panel(30, 24)
	var v := MenuWidgets.vbox(12)
	var head := MenuWidgets.hbox(16)
	head.add_child(MenuStyle.title_label("PAUSED", 44))
	if not ctl.play_level_name.is_empty():
		var lvl := MenuStyle.label(ctl.play_level_name, MenuStyle.ui_italic_font(), 17, MenuStyle.PAPER_DIM)
		lvl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(lvl)
	v.add_child(head)
	if ctl.paused_mid_take():
		v.add_child(_note("No tactical pause: the take in progress goes back to setup.", MenuStyle.WARN, false))
	var menu := MenuWidgets.vbox(10)
	menu.add_child(MenuWidgets.button("resume", "Resume", "", MenuWidgets.TONE_PRIMARY))
	menu.add_child(MenuWidgets.button("restart", "Restart level", "Wipes every cassette (reset all)"))
	menu.add_child(MenuWidgets.button("settings", "Settings"))
	if ctl.codex_logic.codex != null:
		var c := ctl.codex_logic.codex
		menu.add_child(MenuWidgets.button("guide", "Field Guide", "%d / %d pages · what you have met so far" % [c.unlocked_count(), c.entry_count()]))
	menu.add_child(MenuWidgets.button("quit", "Quit to path", "Leaves this attempt"))
	v.add_child(menu)
	v.add_child(_note("Loadout is locked for this attempt — change gear between levels.", MenuStyle.PAPER_DIM, true))
	v.add_child(_prompts([]))
	p.add_child(v)
	# Centre in the band above the HUD's deck strip and beat ruler, so the card never sits over the
	# cassettes the player is about to come back to.
	var band := Control.new()
	band.name = "AboveHud"
	band.set_anchors_preset(Control.PRESET_FULL_RECT)
	band.anchor_top = HUD_TOP_ANCHOR
	band.anchor_bottom = HUD_CLEAR_ANCHOR
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(band)
	centred(band, p, 560)
	return root


func _prompts(extra: Array[String]) -> Control:
	var pr := MenuWidgets.prompts(ctl.device, extra)
	pr.name = "Prompts"
	return MenuWidgets.margin(pr, 0, 6, 0, 0)


func sync(root: Control, _focus: String) -> void:
	if logic.sub == MenuPauseLogic.SUB_SETTINGS:
		MenuSettingsView.patch(root, logic.settings)


static func _note(text: String, col: Color, lock_icon: bool) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", MenuStyle.pad(MenuStyle.box(Color(col, 0.1), Color(col, 0.45), 1, MenuStyle.RADIUS_SM), 12, 8))
	var h := MenuWidgets.hbox(8)
	if lock_icon:
		var ic := MenuArtView.icon(Callable(MenuArt, "paint_lock"), 18, col)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	var l := MenuStyle.label(text, MenuStyle.ui_bold_font(), 14, col if col != MenuStyle.PAPER_DIM else MenuStyle.PAPER, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	p.add_child(h)
	return p
