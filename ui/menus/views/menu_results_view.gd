class_name MenuResultsView
extends MenuScreenView
## Results (prototype resultsScreenView): outcome title and notes, the tapes used out of the level's
## allowance, the loot found with its effect lines and lore, and Next / Replay / Path / Loadout.

const PANEL_W := 900.0

var logic: MenuResultsLogic


func _init(p_ctl: MenuController, p_logic: MenuResultsLogic) -> void:
	super(p_ctl)
	logic = p_logic


func key() -> String:
	return "%d|%s|%s" % [ctl.results_version, ctl.device, ctl.patterns]


func build() -> Control:
	var root := screen_root("Results")
	var shade := ColorRect.new()
	shade.color = Color(MenuStyle.INK, 0.5)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var m := logic.model
	if m == null:
		centred(root, MenuWidgets.button("path", "Path"), 320)
		add_prompts(root)
		return root
	var v := MenuModels.results_view(m)

	var p := MenuWidgets.panel(34, 26)
	var col := MenuWidgets.vbox(12)
	col.add_child(MenuStyle.label("DEPTH %s · %s" % [v.depth, v.level_name.to_upper()], MenuStyle.mono_font(), 14, MenuStyle.YELLOW))
	var title := MenuStyle.title_label(v.title, 60, MenuStyle.YELLOW if v.win else MenuStyle.PAPER, MenuStyle.PINK if v.win else MenuStyle.BAD)
	col.add_child(title)

	var tapes := MenuWidgets.hbox(16)
	tapes.add_child(MenuWidgets.tape_strip(v.tapes_used, ctl.patterns, 54))
	var used := MenuWidgets.hbox(6)
	used.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	used.add_child(MenuStyle.label(str(v.tapes_used), MenuStyle.heavy_font(), 30, MenuStyle.YELLOW))
	var of := MenuStyle.label("of %d tape%s used" % [v.max_tapes, "" if v.max_tapes == 1 else "s"], MenuStyle.ui_bold_font(), 17, MenuStyle.PAPER)
	of.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	used.add_child(of)
	tapes.add_child(used)
	col.add_child(tapes)

	if not v.notes.is_empty():
		var notes := MenuWidgets.vbox(3)
		for n in v.notes:
			notes.add_child(MenuStyle.label("▸ " + n, MenuStyle.ui_font(), 16, MenuStyle.PAPER, true))
		col.add_child(notes)

	col.add_child(MenuStyle.label("LOOT", MenuStyle.heavy_font(), 15, MenuStyle.PINK))
	if v.loot.is_empty():
		col.add_child(MenuStyle.label("Nothing new this time — this level’s gear is already yours.", MenuStyle.ui_italic_font(), 15, MenuStyle.PAPER_DIM, true))
	else:
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 12)
		flow.add_theme_constant_override("v_separation", 12)
		for g in v.loot:
			flow.add_child(_loot_card(g))
		col.add_child(flow)

	var actions := MenuWidgets.hbox(12)
	var labels := {"next": "Next level", "replay": "Replay", "path": "Path", "loadout": "Loadout"}
	var entries := logic.menu().entries
	for i in entries.size():
		var id := entries[i].id
		actions.add_child(MenuWidgets.button(id, labels.get(id, id), "", MenuWidgets.TONE_PRIMARY if i == 0 else MenuWidgets.TONE_DEFAULT))
	col.add_child(MenuWidgets.margin(actions, 0, 8, 0, 0))
	p.add_child(col)
	centred(root, p, PANEL_W)
	add_prompts(root)
	return root


func _loot_card(g: MenuModels.LootLine) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size.x = 300
	p.add_theme_stylebox_override("panel", MenuStyle.pad(MenuStyle.box(Color(MenuStyle.INK_SOFT, 0.9), Color(MenuStyle.YELLOW, 0.5), 2, MenuStyle.RADIUS_SM, MenuStyle.PINK, Vector2(4, 4)), 14, 10))
	var row := MenuWidgets.hbox(12)
	var icon := MenuCampaignView._gear_icon(g.id, 64)
	if icon != null:
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(icon)
	var v := MenuWidgets.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top := MenuWidgets.hbox(8)
	top.add_child(MenuWidgets.new_tag())
	top.add_child(MenuStyle.label(g.slot, MenuStyle.mono_font(), 12, MenuStyle.YELLOW))
	v.add_child(top)
	v.add_child(MenuStyle.label(g.name.to_upper(), MenuStyle.display_font(), 20, MenuStyle.PAPER))
	var text_w := 270.0 - (76.0 if icon != null else 0.0)
	var eff := MenuStyle.label(g.effect, MenuStyle.ui_bold_font(), 14, MenuStyle.PAPER, true)
	eff.custom_minimum_size.x = text_w
	v.add_child(eff)
	if not g.lore.is_empty():
		var lore := MenuStyle.label(g.lore, MenuStyle.ui_italic_font(), 13, MenuStyle.PAPER_DIM, true)
		lore.custom_minimum_size.x = text_w
		v.add_child(lore)
	row.add_child(v)
	p.add_child(row)
	return p
