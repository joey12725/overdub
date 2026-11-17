class_name MenuWidgets
extends RefCounted
## Builders for the shared menu pieces (prototype ui/menus/views.ts btn / prompts / tapeStrip /
## statTable / compareTable). Never instantiated.

const TONE_DEFAULT: StringName = &""
const TONE_PRIMARY: StringName = &"primary"
const TONE_DANGER: StringName = &"danger"
const TONE_GHOST: StringName = &"ghost"

## Group for controls that handle the mouse themselves inside a nav item (sliders, steppers, chips).
const INTERACTIVE_GROUP := &"menu_interactive"


## A menu button: display-type label (+ optional sub line). The focus look, shared by every
## interactive element: a yellow sticker with a pink print offset, ink text.
static func button(nav: String, text: String, sub: String = "", tone: StringName = TONE_DEFAULT, small: bool = false) -> MenuNavItem:
	var label_col := MenuStyle.PAPER
	var edge := MenuStyle.PANEL_EDGE
	var bg := Color(MenuStyle.INK, 0.78)
	match tone:
		TONE_PRIMARY:
			label_col = MenuStyle.YELLOW
			edge = Color(MenuStyle.YELLOW, 0.6)
		TONE_DANGER:
			label_col = MenuStyle.BAD
			edge = Color(MenuStyle.BAD, 0.55)
		TONE_GHOST:
			bg = Color(MenuStyle.INK, 0.45)
	var pad_h := 18.0 if small else 22.0
	var pad_v := 6.0 if small else 10.0
	var normal := MenuStyle.box(bg, edge, 2, MenuStyle.RADIUS_SM)
	normal.skew = Vector2(0.12, 0)
	MenuStyle.pad(normal, pad_h, pad_v)
	var focus := MenuStyle.box(MenuStyle.YELLOW, MenuStyle.INK, 2, MenuStyle.RADIUS_SM, MenuStyle.PINK, Vector2(5, 5))
	focus.skew = Vector2(0.12, 0)
	MenuStyle.pad(focus, pad_h, pad_v)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lab := MenuStyle.label(text.to_upper(), MenuStyle.display_font(), 15 if small else 20, label_col)
	vb.add_child(lab)
	var sub_label: Label = null
	if not sub.is_empty():
		sub_label = MenuStyle.label(sub, MenuStyle.ui_font(), 13, MenuStyle.PAPER_DIM)
		vb.add_child(sub_label)
	var restyle := func(f: bool) -> void:
		lab.add_theme_color_override("font_color", MenuStyle.INK if f else label_col)
		if sub_label != null:
			sub_label.add_theme_color_override("font_color", Color(MenuStyle.INK, 0.8) if f else MenuStyle.PAPER_DIM)
	var item := MenuNavItem.make(nav, normal, focus, restyle)
	item.custom_minimum_size = Vector2(0, 38 if small else 50)
	item.add_child(vb)
	return item


## Device prompts strip (prototype prompts()).
static func prompts(device: StringName, extra: Array[String] = []) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var items: Array = [["D-pad", "move"], ["A", "select"], ["B", "back"]] if device == UiBase.DEVICE_GAMEPAD \
		else [["↑↓←→", "move"], ["Enter", "select"], ["Esc", "back"]]
	for kv: Array in items:
		row.add_child(prompt(kv[0], kv[1]))
	for t in extra:
		row.add_child(MenuStyle.label(t, MenuStyle.ui_font(), 14, MenuStyle.PAPER_DIM))
	return row


## One key cap plus its meaning.
static func prompt(key: String, meaning: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_theme_stylebox_override("panel", MenuStyle.pad(MenuStyle.box(MenuStyle.PAPER, MenuStyle.INK, 1, 4, Color(MenuStyle.INK, 0.6), Vector2(0, 2)), 7, 1))
	cap.add_child(MenuStyle.label(key, MenuStyle.mono_font(), 13, MenuStyle.INK))
	h.add_child(cap)
	h.add_child(MenuStyle.label(meaning, MenuStyle.ui_font(), 14, MenuStyle.PAPER_DIM))
	return h


## Small rounded tag ("NEW", "EQUIPPED").
static func tag(text: String, bg: Color, fg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", MenuStyle.pad(MenuStyle.box(bg, Color.TRANSPARENT, 0, 4), 6, 0))
	p.add_child(MenuStyle.label(text, MenuStyle.heavy_font(), 11, fg))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


static func new_tag() -> PanelContainer:
	return tag("NEW", MenuStyle.PINK, MenuStyle.INK)


## A chip (speed / end mode readout). dashed = end-mode chips (drawn with a double border).
static func chip(text: String, accent: Color, dashed: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := MenuStyle.box(Color(accent, 0.12) if dashed else Color.TRANSPARENT, accent, 1 if dashed else 2, 10)
	MenuStyle.pad(sb, 8, 0)
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(MenuStyle.label(text, MenuStyle.mono_font(), 13, accent))
	return p


## Always four cassettes so "2 of a possible 4" reads at a glance; the first `count` are coloured.
static func tape_strip(count: int, patterns: bool, width: float = 26.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in OD.TAPE_COUNT:
		h.add_child(MenuArtView.cassette(i, i < count, patterns, width))
	return h


## Two-column label / value table (prototype statTable).
static func stat_table(rows: Array[MenuFormat.StatRow], width: float) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 4)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for r in rows:
		var k := MenuStyle.label(r.label, MenuStyle.ui_bold_font(), 13, MenuStyle.PAPER_DIM)
		k.custom_minimum_size.x = 112
		g.add_child(k)
		var v := MenuStyle.label(r.value, MenuStyle.ui_font(), 14, MenuStyle.PAPER, true)
		v.custom_minimum_size.x = maxf(width - 126, 80)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(v)
	return g


## Equipped-vs-this comparison (prototype compareTable): better rows green ▲, worse red ▼.
static func compare_table(rows: Array[MenuFormat.CompareRow]) -> Control:
	if rows.is_empty():
		return MenuStyle.label("No mechanical difference.", MenuStyle.ui_italic_font(), 14, MenuStyle.PAPER_DIM)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 3)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(MenuStyle.label("", MenuStyle.ui_font(), 12, MenuStyle.PAPER_DIM))
	g.add_child(MenuStyle.label("EQUIPPED", MenuStyle.mono_font(), 11, MenuStyle.PAPER_DIM))
	g.add_child(MenuStyle.label("THIS", MenuStyle.mono_font(), 11, MenuStyle.YELLOW))
	for r in rows:
		var col := MenuStyle.PAPER
		var mark := ""
		if r.dir > 0:
			col = MenuStyle.GOOD
			mark = "  ▲"
		elif r.dir < 0:
			col = MenuStyle.BAD
			mark = "  ▼"
		g.add_child(MenuStyle.label(r.label, MenuStyle.ui_bold_font(), 13, MenuStyle.PAPER_DIM))
		g.add_child(MenuStyle.label(r.from, MenuStyle.ui_font(), 14, Color(MenuStyle.PAPER, 0.7)))
		g.add_child(MenuStyle.label(r.to + mark, MenuStyle.ui_bold_font(), 14, col))
	return g


## A translucent panel container.
static func panel(pad_h: float = 26, pad_v: float = 22) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", MenuStyle.panel_box(pad_h, pad_v))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


static func spacer(expand_h: bool = true, expand_v: bool = false) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand_h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if expand_v:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func margin(child: Control, l: int, t: int, r: int, b: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	m.add_child(child)
	# Inside a ScrollContainer the content must claim the full width or wrapped text collapses.
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return m


## Scroll container that never steals keyboard focus.
static func scroller(key: String) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.focus_mode = Control.FOCUS_NONE
	s.mouse_filter = Control.MOUSE_FILTER_PASS
	s.set_meta(&"scroll_key", key)
	return s


## Make every descendant that is not interactive ignore the mouse so hover/click land on the nav item
## (or the slider / stepper) under the pointer.
static func passthrough(root: Node) -> void:
	for c in root.get_children():
		var ctl := c as Control
		if ctl != null:
			if ctl is MenuNavItem or ctl is ScrollContainer or ctl is ScrollBar or ctl is Slider or ctl.is_in_group(INTERACTIVE_GROUP):
				pass
			else:
				ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		passthrough(c)
