class_name MenuCodexView
extends MenuScreenView
## The Field Guide screen (docs/CODEX.md "Where it appears" / suggested layout): the grouped page list
## on the left (locked pages read "???" with a padlock, new pages carry a NEW tag), and the page on the
## right: its plate (assets/codex/<illustration>.png), title, the rule in the largest type, the notes
## as a hand-annotated list and the numbers as a two-column table. Locked pages show the locked line
## and no plate. The baseline footnote (starting blade, beat counting) is printed once at the bottom.

const LIST_W := 340.0

var logic: MenuCodexLogic
var _shown: String = "-"


func _init(p_ctl: MenuController, p_logic: MenuCodexLogic) -> void:
	super(p_ctl)
	logic = p_logic


func key() -> String:
	var c := logic.codex
	return "%s|%d|%s" % [ctl.device, c.unlocked_count() if c != null else -1, ctl.get_viewport_rect().size if ctl.is_inside_tree() else Vector2.ZERO]


func build() -> Control:
	_shown = "-"
	var root := screen_root("Codex")
	var shade := ColorRect.new()
	shade.color = Color(MenuStyle.INK, 0.9)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var c := logic.codex
	var vs := ctl.get_viewport_rect().size if ctl.is_inside_tree() else Vector2(1600, 900)
	var compact := vs.y < 800.0

	var outer := MenuWidgets.vbox(10)
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := MenuWidgets.margin(outer, 32, 22, 32, 52)
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(m)

	# Header: back, title, count.
	var bar := MenuWidgets.hbox(18)
	var back := MenuWidgets.button("back", "◀ Back", "", MenuWidgets.TONE_GHOST, true)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(back)
	var tb := MenuWidgets.vbox(0)
	tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb.add_child(MenuStyle.title_label((c.title() if c != null else "Field Guide").to_upper(), 34 if compact else 40))
	if c != null and c.subtitle() != "":
		tb.add_child(MenuStyle.label(c.subtitle(), MenuStyle.ui_italic_font(), 15, MenuStyle.PAPER_DIM, true))
	bar.add_child(tb)
	if c != null:
		var count := MenuStyle.label("%d / %d pages" % [c.unlocked_count(), c.entry_count()], MenuStyle.mono_font(), 16, MenuStyle.YELLOW)
		count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_child(count)
	outer.add_child(bar)

	var body := MenuWidgets.hbox(18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)

	# Page list.
	var list_panel := MenuWidgets.panel(12, 12)
	list_panel.custom_minimum_size.x = LIST_W * (0.86 if compact else 1.0)
	var scroll := MenuWidgets.scroller("codex_list")
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_panel.add_child(scroll)
	var list := MenuWidgets.vbox(4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var last_group := ""
	for row: Dictionary in logic.rows():
		var g: Dictionary = row["group"]
		var e: Dictionary = row["entry"]
		var gid := str(g.get("id", ""))
		if gid != last_group:
			last_group = gid
			var gl := MenuStyle.label(str(g.get("title", gid)).to_upper(), MenuStyle.heavy_font(), 13, MenuStyle.PINK)
			list.add_child(MenuWidgets.margin(gl, 6, 8 if list.get_child_count() > 0 else 0, 0, 0))
		list.add_child(_entry_item(e))
	body.add_child(list_panel)

	# Page.
	var page := MenuWidgets.panel(26, 20)
	page.name = "Page"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var holder := MenuWidgets.vbox(0)
	holder.name = "PageHolder"
	page.add_child(holder)
	body.add_child(page)

	var pr := MenuWidgets.prompts(ctl.device)
	pr.name = "Prompts"
	pr.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	pr.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(pr)
	return root


func _entry_item(e: Dictionary) -> MenuNavItem:
	var c := logic.codex
	var id := str(e.get("id", ""))
	var unlocked := c != null and c.is_unlocked(id)
	var normal := MenuStyle.pad(MenuStyle.box(Color(MenuStyle.INK_SOFT, 0.0), Color.TRANSPARENT, 0, MenuStyle.RADIUS_SM), 10, 4)
	var focus := MenuStyle.pad(MenuStyle.box(MenuStyle.YELLOW, MenuStyle.INK, 2, MenuStyle.RADIUS_SM, MenuStyle.PINK, Vector2(3, 3)), 10, 4)
	var h := MenuWidgets.hbox(8)
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(30, 30)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if unlocked:
		thumb.texture = UiArt.icon(c.illustration_path(id), 30)
	h.add_child(thumb)
	var title := str(e.get("title", id)) if unlocked else "???"
	var lab := MenuStyle.label(title, MenuStyle.ui_bold_font(), 15, MenuStyle.PAPER if unlocked else UiPalette.MUTED_TEXT)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(lab)
	if not unlocked:
		var lock := MenuArtView.icon(Callable(MenuArt, "paint_lock"), 14, MenuStyle.STATE_DEAD)
		lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(lock)
	elif c.is_new(id):
		h.add_child(MenuWidgets.new_tag())
	var restyle := func(f: bool) -> void:
		lab.add_theme_color_override("font_color", MenuStyle.INK if f else (MenuStyle.PAPER if unlocked else UiPalette.MUTED_TEXT))
	var item := MenuNavItem.make("entry:%s" % id, normal, focus, restyle)
	item.add_child(h)
	return item


func sync(root: Control, focus: String) -> void:
	if focus.begins_with("entry:"):
		logic.selected = focus.substr(6)
	if logic.selected == _shown:
		return
	_shown = logic.selected
	var holder := root.find_child("PageHolder", true, false) as VBoxContainer
	if holder == null:
		return
	for ch in holder.get_children():
		holder.remove_child(ch)
		ch.queue_free()
	holder.add_child(_page(logic.selected, root.get_viewport_rect().size if root.is_inside_tree() else Vector2(1600, 900)))


func _page(id: String, vs: Vector2) -> Control:
	var c := logic.codex
	var v := MenuWidgets.vbox(10)
	if c == null or id == "":
		v.add_child(MenuStyle.label("Nothing in the guide yet.", MenuStyle.ui_italic_font(), 18, MenuStyle.PAPER_DIM, true))
		return v
	var e := c.entry(id)
	var unlocked := c.is_unlocked(id)
	var group := ""
	for g: Dictionary in c.groups():
		if str(g.get("id", "")) == str(e.get("group", "")):
			group = str(g.get("title", ""))
	var compact := vs.y < 800.0
	var row := MenuWidgets.hbox(22)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)

	var plate_px := clampf(vs.y * 0.5, 260.0, 470.0) if not compact else clampf(vs.y * 0.44, 220.0, 330.0)
	var plate_box := PanelContainer.new()
	plate_box.add_theme_stylebox_override("panel", MenuStyle.pad(MenuStyle.box(MenuStyle.PAPER, MenuStyle.INK, 3, 4, MenuStyle.PINK, Vector2(6, 6)), 6, 6))
	plate_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var plate := TextureRect.new()
	plate.custom_minimum_size = Vector2(plate_px, plate_px)
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if unlocked:
		plate.texture = UiArt.icon(c.illustration_path(id), plate_px)
	else:
		plate_box.add_theme_stylebox_override("panel", MenuStyle.pad(MenuStyle.box(Color(MenuStyle.INK_SOFT, 0.8), Color(MenuStyle.PAPER, 0.25), 2, 4), 6, 6))
		var q := MenuStyle.label("?", MenuStyle.display_font(), int(plate_px * 0.4), Color(MenuStyle.PAPER, 0.12))
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q.set_anchors_preset(Control.PRESET_FULL_RECT)
		plate.add_child(q)
	plate_box.add_child(plate)
	row.add_child(plate_box)

	var text_col := MenuWidgets.vbox(8)
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_col)
	text_col.add_child(MenuStyle.label(group.to_upper(), MenuStyle.mono_font(), 13, MenuStyle.YELLOW))
	if not unlocked:
		text_col.add_child(MenuStyle.title_label("???", 36))
		text_col.add_child(MenuStyle.label(c.locked_text(), MenuStyle.ui_italic_font(), 18, MenuStyle.PAPER_DIM, true))
		return v
	text_col.add_child(MenuStyle.title_label(str(e.get("title", id)).to_upper(), 30 if compact else 36))
	var rule := MenuStyle.label(str(e.get("rule", "")), MenuStyle.ui_bold_font(), 18 if compact else 21, MenuStyle.PAPER, true)
	text_col.add_child(rule)
	var notes: Variant = e.get("notes", [])
	if notes is Array:
		var nb := MenuWidgets.vbox(5)
		for n: Variant in notes:
			nb.add_child(MenuStyle.label("✎  " + str(n), MenuStyle.ui_font(), 14 if compact else 15, MenuStyle.PAPER_DIM, true))
		text_col.add_child(MenuWidgets.margin(nb, 0, 4, 0, 0))
	var nums: Variant = e.get("numbers", [])
	if nums is Array and not (nums as Array).is_empty():
		var g := GridContainer.new()
		g.columns = 2
		g.add_theme_constant_override("h_separation", 14)
		g.add_theme_constant_override("v_separation", 3)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for n: Variant in nums:
			if n is Dictionary:
				var k := MenuStyle.label(str(n.get("label", "")), MenuStyle.ui_bold_font(), 13, MenuStyle.YELLOW)
				k.custom_minimum_size.x = 110
				g.add_child(k)
				var val := MenuStyle.label(str(n.get("value", "")), MenuStyle.mono_font(), 13, MenuStyle.PAPER, true)
				val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				g.add_child(val)
		text_col.add_child(MenuWidgets.margin(g, 0, 6, 0, 0))
	var base: Variant = c.baseline().get("note", "")
	if str(base) != "" and str(e.get("group", "")) in ["machines", "force"]:
		v.add_child(MenuStyle.label(str(base), MenuStyle.ui_italic_font(), 12, UiPalette.MUTED_TEXT, true))
	return v
