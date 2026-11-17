class_name MenuSettingsView
extends MenuScreenView
## Settings (prototype settingsView / settingsPanel / patchSettings): master / music / sfx volumes,
## audio-visual offset, screen shake, cassette patterns (colour-blind support), quality, and erase
## save behind a confirm. Values are patched in place on every sync so a slider drag survives.

const PANEL_W := 860.0

var logic: MenuSettingsLogic


func _init(p_ctl: MenuController, p_logic: MenuSettingsLogic) -> void:
	super(p_ctl)
	logic = p_logic


func key() -> String:
	return "%s|%s" % [logic.confirming_erase, ctl.device]


func build() -> Control:
	var root := screen_root("Settings")
	var shade := ColorRect.new()
	shade.color = Color(MenuStyle.INK, 0.5)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	centred(root, panel(ctl, logic), PANEL_W)
	add_prompts(root, ["←→ adjust"])
	return root


func sync(root: Control, _focus: String) -> void:
	patch(root, logic)


## The settings panel, shared with the pause overlay.
static func panel(c: MenuController, l: MenuSettingsLogic) -> PanelContainer:
	var p := MenuWidgets.panel(28, 22)
	var v := MenuWidgets.vbox(6)
	v.add_child(MenuStyle.title_label("SETTINGS", 34))
	# Every row scrolls in one list (sound, readability, story); focus keeps the cursor in view.
	var vh := c.get_viewport_rect().size.y if c.is_inside_tree() else 900.0
	var scroll := MenuWidgets.scroller("settings_rows")
	scroll.custom_minimum_size.y = maxf(260.0, vh - 330.0)
	var rows := MenuWidgets.vbox(6)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for r in MenuSettingsLogic.setting_rows():
		if r.section != "":
			var head := MenuStyle.label(r.section, MenuStyle.heavy_font(), 13, MenuStyle.PINK)
			rows.add_child(MenuWidgets.margin(head, 4, 8 if rows.get_child_count() > 0 else 0, 0, 0))
		rows.add_child(_row(c, l, r))
	scroll.add_child(MenuWidgets.margin(rows, 0, 0, 10, 0))
	v.add_child(scroll)
	v.add_child(_erase_row(l))
	var back := MenuWidgets.button("back", "Back", "", MenuWidgets.TONE_GHOST, true)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(MenuWidgets.margin(back, 0, 8, 0, 0))
	p.add_child(v)
	return p


static func _row_styles() -> Array[StyleBox]:
	var normal := MenuStyle.box(Color(MenuStyle.INK, 0.35), Color.TRANSPARENT, 0, MenuStyle.RADIUS_SM)
	MenuStyle.pad(normal, 14, 7)
	var focus := MenuStyle.box(UiPalette.TAPE_NIGHT[1], MenuStyle.YELLOW, 2, MenuStyle.RADIUS_SM, MenuStyle.PINK, Vector2(4, 4))
	MenuStyle.pad(focus, 14, 7)
	return [normal, focus]


static func _text_block(label_text: String, help: String) -> VBoxContainer:
	var t := MenuWidgets.vbox(0)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_child(MenuStyle.label(label_text, MenuStyle.ui_bold_font(), 17, MenuStyle.PAPER))
	t.add_child(MenuStyle.label(help, MenuStyle.ui_font(), 13, MenuStyle.PAPER_DIM, true))
	return t


static func _row(c: MenuController, l: MenuSettingsLogic, r: MenuSettingsLogic.SettingRow) -> MenuNavItem:
	var st := _row_styles()
	var h := MenuWidgets.hbox(16)
	var text := _text_block(r.label, r.help)
	h.add_child(text)
	var key := r.key
	match r.kind:
		MenuSettingsLogic.KIND_TOGGLE:
			var sw := SwitchView.new()
			sw.name = "View_%s" % key
			sw.custom_minimum_size = Vector2(118, 34)
			h.add_child(sw)
		MenuSettingsLogic.KIND_CHOICE:
			var chips := MenuWidgets.hbox(6)
			chips.name = "View_%s" % key
			for oi in r.options.size():
				var opt: Variant = r.options[oi]
				var b := Button.new()
				b.text = r.option_labels[oi] if oi < r.option_labels.size() else str(opt).to_upper()
				b.focus_mode = Control.FOCUS_NONE
				b.toggle_mode = false
				b.custom_minimum_size = Vector2(64, 34)
				b.add_theme_font_override("font", MenuStyle.heavy_font())
				b.add_theme_font_size_override("font_size", 13)
				b.set_meta(&"option", opt)
				b.add_to_group(MenuWidgets.INTERACTIVE_GROUP)
				b.pressed.connect(func() -> void: c.setting_set(key, opt))
				chips.add_child(b)
			h.add_child(chips)
		_:
			var is_offset := r.kind == MenuSettingsLogic.KIND_OFFSET
			var box := MenuWidgets.hbox(6)
			box.name = "View_%s" % key
			box.add_child(_stepper("−", func() -> void: c.adjust("%s" % key, -1)))
			var s := HSlider.new()
			s.name = "Slider"
			s.focus_mode = Control.FOCUS_NONE
			s.custom_minimum_size = Vector2(200, 30)
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			s.min_value = MenuSettingsLogic.AV_OFFSET_MIN if is_offset else 0.0
			s.max_value = MenuSettingsLogic.AV_OFFSET_MAX if is_offset else 1.0
			s.step = MenuSettingsLogic.AV_OFFSET_STEP if is_offset else MenuSettingsLogic.VOLUME_STEP
			s.set_value_no_signal(float(l.value_of(key)))
			s.value_changed.connect(func(val: float) -> void: c.setting_set(key, val))
			box.add_child(s)
			box.add_child(_stepper("+", func() -> void: c.adjust("%s" % key, 1)))
			var val := MenuStyle.label("", MenuStyle.mono_font(), 15, MenuStyle.YELLOW)
			val.name = "Value"
			val.custom_minimum_size.x = 76
			val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			box.add_child(val)
			h.add_child(box)
	var item := MenuNavItem.make(key, st[0], st[1])
	item.add_child(h)
	# Hovering a slider / stepper / chip inside the row focuses the row, like hovering the row itself.
	_hover_to_row(c, h, key)
	return item


static func _hover_to_row(c: MenuController, n: Node, key: String) -> void:
	for ch in n.get_children():
		if ch is Control and ((ch as Control).is_in_group(MenuWidgets.INTERACTIVE_GROUP) or ch is Slider):
			(ch as Control).mouse_entered.connect(func() -> void: c.pointer_hover(key))
		_hover_to_row(c, ch, key)


static func _stepper(text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(32, 32)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_override("font", MenuStyle.heavy_font())
	b.add_theme_font_size_override("font_size", 16)
	_style_button(b, false)
	b.add_to_group(MenuWidgets.INTERACTIVE_GROUP)
	b.pressed.connect(fn)
	return b


static func _style_button(b: Button, on: bool) -> void:
	var bg := MenuStyle.YELLOW if on else Color(MenuStyle.INK, 0.85)
	var fg := MenuStyle.INK if on else MenuStyle.PAPER
	var normal := MenuStyle.pad(MenuStyle.box(bg, MenuStyle.YELLOW if on else Color(MenuStyle.PAPER, 0.3), 2, 6), 6, 2)
	var hover := MenuStyle.pad(MenuStyle.box(bg.lightened(0.12), MenuStyle.YELLOW, 2, 6), 6, 2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", MenuStyle.pad(MenuStyle.box(MenuStyle.PINK, MenuStyle.INK, 2, 6), 6, 2))
	b.add_theme_stylebox_override("focus", MenuStyle.empty_box())
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", MenuStyle.INK)


static func _erase_row(l: MenuSettingsLogic) -> Control:
	var panel_box := MenuStyle.box(Color(MenuStyle.BAD, 0.08), Color(MenuStyle.BAD, 0.35), 1, MenuStyle.RADIUS_SM)
	MenuStyle.pad(panel_box, 14, 8)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_box)
	var h := MenuWidgets.hbox(12)
	if l.confirming_erase:
		h.add_child(_text_block("Erase everything?", "Cleared levels, found gear and your loadout are wiped. This cannot be undone."))
		h.add_child(MenuWidgets.button("erase-no", "Keep", "", MenuWidgets.TONE_GHOST, true))
		h.add_child(MenuWidgets.button("erase-yes", "Erase save", "", MenuWidgets.TONE_DANGER, true))
	else:
		h.add_child(_text_block("Save data", "Progress saves automatically on this device."))
		h.add_child(MenuWidgets.button("erase", "Erase save…", "", MenuWidgets.TONE_DANGER, true))
	p.add_child(h)
	return p


## Update slider positions, value labels, switches and quality chips in place (no rebuild).
static func patch(root: Control, l: MenuSettingsLogic) -> void:
	for r in MenuSettingsLogic.setting_rows():
		var view := root.find_child("View_%s" % r.key, true, false)
		if view == null:
			continue
		var v: Variant = l.value_of(r.key)
		if view is SwitchView:
			var sw := view as SwitchView
			sw.on = bool(v)
			sw.text = MenuSettingsLogic.format_setting(r.key, v)
			sw.queue_redraw()
		elif r.kind == MenuSettingsLogic.KIND_CHOICE:
			for b in view.get_children():
				var btn := b as Button
				if btn != null:
					_style_button(btn, MenuSettingsLogic._same(btn.get_meta(&"option", ""), v))
		else:
			var s := view.find_child("Slider", false, false) as HSlider
			if s != null and not is_equal_approx(s.value, float(v)):
				s.set_value_no_signal(float(v))
			var val := view.find_child("Value", false, false) as Label
			if val != null:
				val.text = MenuSettingsLogic.format_setting(r.key, v)


## On / off switch drawn as a pill with a knob and its state text.
class SwitchView:
	extends Control
	var on: bool = false
	var text: String = "Off"

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var pill := Rect2(0, (size.y - 26) * 0.5, 54, 26)
		var poly := MenuVector.rounded_rect(pill, 13)
		draw_colored_polygon(poly, MenuStyle.YELLOW if on else Color(MenuStyle.INK, 0.9))
		var outline := poly.duplicate()
		outline.append(poly[0])
		draw_polyline(outline, MenuStyle.INK if on else Color(MenuStyle.PAPER, 0.4), 2, true)
		var kx := pill.end.x - 13 if on else pill.position.x + 13
		draw_circle(Vector2(kx, pill.get_center().y), 9, MenuStyle.INK if on else MenuStyle.PAPER_DIM)
		var font := MenuStyle.heavy_font()
		draw_string(font, Vector2(pill.end.x + 12, pill.get_center().y + 6), text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			MenuStyle.YELLOW if on else MenuStyle.PAPER_DIM)
