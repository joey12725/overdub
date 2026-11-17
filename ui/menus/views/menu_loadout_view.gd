class_name MenuLoadoutView
extends MenuScreenView
## Loadout (prototype loadoutScreenView; APPAREL-01..03, GEAR-03/04, WEAPON-01..04). Six clearly
## labelled slots, each with the equipped item and its effect; a stylised Moxie marking the slots;
## the combined summary; the owned items of the browsed slot (NEW / EQUIPPED tags); and a details
## panel with the item's effect, comparison against what is equipped, its real numbers and lore.

const SLOTS_W := 372.0
const DOLL_W := 320.0
const ITEMS_W := 318.0
## Longest effect text a slot tile shows before trimming at a word boundary: two lines of the tile
## at most (six three-line tiles push Done off the bottom of the screen and into the key prompts).
const EFFECT_CHARS := 74
## Weapon turntable in the details panel.
const WEAPON_STAGE_H := 130.0
const WEAPON_TILT_DEG := -60.0

var logic: MenuLoadoutLogic


func _init(p_ctl: MenuController, p_logic: MenuLoadoutLogic) -> void:
	super(p_ctl)
	logic = p_logic


func key() -> String:
	return "%d|%s|%s" % [ctl.loadout_version, logic.active_slot, ctl.device]


func build() -> Control:
	var root := screen_root("Loadout")
	var shade := ColorRect.new()
	shade.color = Color(MenuStyle.INK, 0.42)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	var model := logic.model
	var col := MenuWidgets.vbox(14)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 32
	col.offset_right = -32
	col.offset_top = 22
	col.offset_bottom = -58
	root.add_child(col)

	var head := MenuWidgets.hbox(20)
	head.add_child(MenuStyle.title_label("LOADOUT", 40))
	var sub := MenuStyle.label("One loadout for all four tapes. Swap freely between levels; it locks once a level starts.",
		MenuStyle.ui_font(), 15, MenuStyle.PAPER_DIM)
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sub)
	col.add_child(head)

	if model == null:
		var waiting := MenuWidgets.panel()
		waiting.add_child(MenuStyle.label("Loading gear…", MenuStyle.ui_italic_font(), 18, MenuStyle.PAPER_DIM))
		col.add_child(waiting)
		col.add_child(MenuWidgets.button("done", "Done", "", MenuWidgets.TONE_PRIMARY))
		add_prompts(root)
		return root

	var v := MenuModels.loadout_view(model, logic.active_slot)
	var grid := MenuWidgets.hbox(20)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(grid)

	# Column 1: the six slots, then Done.
	var slots := MenuWidgets.vbox(8)
	slots.custom_minimum_size.x = SLOTS_W
	for s in v.slots:
		slots.add_child(_slot_tile(s, s.slot == v.active_slot))
	slots.add_child(MenuWidgets.spacer(false, true))
	slots.add_child(MenuWidgets.button("done", "Done", "Back to %s" % ("the path" if ctl.origin != UiScreen.TITLE else "the title"), MenuWidgets.TONE_PRIMARY))
	grid.add_child(slots)

	# Column 2: Moxie with slot pins, and the combined effects.
	var mid := MenuWidgets.vbox(12)
	mid.custom_minimum_size.x = DOLL_W
	var doll_panel := PanelContainer.new()
	doll_panel.add_theme_stylebox_override("panel", MenuStyle.panel_box(10, 10))
	doll_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var stage := DollStage.new(v.active_slot)
	doll_panel.add_child(stage)
	mid.add_child(doll_panel)
	mid.add_child(_summary(v.summary))
	grid.add_child(mid)

	# Column 3: items of the browsed slot.
	var lab := MenuFormat.slot_label(v.active_slot)
	var items_col := MenuWidgets.vbox(8)
	items_col.custom_minimum_size.x = ITEMS_W
	# The list header sits over the live world, so it gets its own translucent backing to stay legible.
	var list_head := PanelContainer.new()
	list_head.add_theme_stylebox_override("panel", MenuStyle.panel_box(12, 8))
	var head_col := MenuWidgets.vbox(2)
	head_col.add_child(MenuStyle.title_label(lab.title, 24, MenuStyle.PAPER, MenuStyle.PINK))
	var info := MenuStyle.label("%s · %d owned\n%s" % [lab.kind, v.items.size(), lab.touches], MenuStyle.ui_font(), 13, MenuStyle.PAPER_DIM, true)
	head_col.add_child(info)
	list_head.add_child(head_col)
	items_col.add_child(list_head)
	var scroll := MenuWidgets.scroller("items:%s" % v.active_slot)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := MenuWidgets.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it in v.items:
		list.add_child(_item_card(it))
	if v.items.is_empty():
		list.add_child(MenuStyle.label("Nothing owned for this slot yet.", MenuStyle.ui_italic_font(), 15, MenuStyle.PAPER_DIM, true))
	scroll.add_child(MenuWidgets.margin(list, 0, 0, 10, 8))
	items_col.add_child(scroll)
	grid.add_child(items_col)

	# Column 4: details of the focused (or equipped) item.
	var details := PanelContainer.new()
	details.name = "Details"
	details.add_theme_stylebox_override("panel", MenuStyle.panel_box(22, 18))
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dscroll := MenuWidgets.scroller("details")
	dscroll.name = "DetailsScroll"
	details.add_child(dscroll)
	var dslot := MenuWidgets.vbox(10)
	dslot.name = "DetailsSlot"
	dslot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dscroll.add_child(dslot)
	grid.add_child(details)

	add_prompts(root, [_hint()])
	return root


## `text` cut to at most `n` characters at a word boundary, with an ellipsis when cut.
static func clip_words(text: String, n: int) -> String:
	if text.length() <= n:
		return text
	var cut := text.left(n)
	var sp := cut.rfind(" ")
	if sp > n / 2:
		cut = cut.left(sp)
	return cut.rstrip(" ,.;:—") + "…"


func _hint() -> String:
	return "Select equips" if logic.in_list else "Select opens the slot"


func _slot_tile(s: MenuModels.SlotView, active: bool) -> MenuNavItem:
	var normal := MenuStyle.box(Color(MenuStyle.INK, 0.8), Color(MenuStyle.YELLOW, 0.55) if active else MenuStyle.PANEL_EDGE, 2, MenuStyle.RADIUS_SM)
	MenuStyle.pad(normal, 14, 8)
	var focus := MenuStyle.box(MenuStyle.YELLOW, MenuStyle.INK, 2, MenuStyle.RADIUS_SM, MenuStyle.PINK, Vector2(5, 5))
	MenuStyle.pad(focus, 14, 8)
	var v := MenuWidgets.vbox(1)
	var top := MenuWidgets.hbox(8)
	var title := MenuStyle.label(s.title, MenuStyle.heavy_font(), 13, MenuStyle.YELLOW)
	top.add_child(title)
	if s.has_fresh:
		top.add_child(MenuWidgets.new_tag())
	top.add_child(MenuWidgets.spacer())
	var owned := MenuStyle.label("%d owned" % s.owned, MenuStyle.mono_font(), 12, MenuStyle.PAPER_DIM)
	top.add_child(owned)
	v.add_child(top)
	var name := MenuStyle.label(s.equipped.name if s.equipped != null else "—", MenuStyle.display_font(), 19, MenuStyle.PAPER)
	v.add_child(name)
	# The tile states the effect in a line or two; the details panel carries the whole text.
	var eff := MenuStyle.label(clip_words(s.equipped.effect, EFFECT_CHARS) if s.equipped != null else "Nothing equipped.",
		MenuStyle.ui_font(), 13, MenuStyle.PAPER_DIM, true)
	eff.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(eff)
	var restyle := func(f: bool) -> void:
		title.add_theme_color_override("font_color", MenuStyle.INK if f else MenuStyle.YELLOW)
		owned.add_theme_color_override("font_color", Color(MenuStyle.INK, 0.7) if f else MenuStyle.PAPER_DIM)
		name.add_theme_color_override("font_color", MenuStyle.INK if f else MenuStyle.PAPER)
		eff.add_theme_color_override("font_color", Color(MenuStyle.INK, 0.85) if f else MenuStyle.PAPER_DIM)
	var item := MenuNavItem.make(s.nav_id, normal, focus, restyle)
	var row := MenuWidgets.hbox(10)
	row.add_child(_icon(s.equipped.id if s.equipped != null else "", s.slot, 52))
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	item.add_child(row)
	return item


## The gear sticker icon (assets/ui/icons/gear/<id>.png), or the slot's empty glyph dimmed when
## nothing is equipped / the art is missing.
static func _icon(gear_id: String, slot: StringName, px: float) -> Control:
	var r := TextureRect.new()
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var t := UiArt.gear_icon(gear_id, px) if gear_id != "" else null
	if t == null:
		t = UiArt.slot_icon(slot, px)
		r.modulate = Color(1, 1, 1, 0.45)
	r.texture = t
	return r


func _item_card(row: MenuModels.ItemRow) -> MenuNavItem:
	var g := row.item
	var normal := MenuStyle.box(Color(MenuStyle.INK, 0.82), Color(MenuStyle.GOOD, 0.6) if row.equipped else MenuStyle.PANEL_EDGE, 2, MenuStyle.RADIUS_SM)
	MenuStyle.pad(normal, 12, 8)
	var focus := MenuStyle.box(MenuStyle.YELLOW, MenuStyle.INK, 2, MenuStyle.RADIUS_SM, MenuStyle.PINK, Vector2(5, 5))
	MenuStyle.pad(focus, 12, 8)
	var v := MenuWidgets.vbox(2)
	var top := MenuWidgets.hbox(6)
	var name := MenuStyle.label(g.name, MenuStyle.ui_bold_font(), 17, MenuStyle.PAPER)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(name)
	if row.fresh:
		top.add_child(MenuWidgets.new_tag())
	if row.equipped:
		top.add_child(MenuWidgets.tag("EQUIPPED", MenuStyle.GOOD, MenuStyle.INK))
	v.add_child(top)
	var eff := MenuStyle.label(g.effect, MenuStyle.ui_font(), 13, MenuStyle.PAPER_DIM, true)
	v.add_child(eff)
	var head_text := MenuFormat.weapon_headline(g)
	var head: Label = null
	if not head_text.is_empty():
		head = MenuStyle.label(head_text, MenuStyle.mono_font(), 12, MenuStyle.YELLOW, true)
		v.add_child(head)
	var restyle := func(f: bool) -> void:
		name.add_theme_color_override("font_color", MenuStyle.INK if f else MenuStyle.PAPER)
		eff.add_theme_color_override("font_color", Color(MenuStyle.INK, 0.85) if f else MenuStyle.PAPER_DIM)
		if head != null:
			head.add_theme_color_override("font_color", Color(MenuStyle.INK, 0.8) if f else MenuStyle.YELLOW)
	var item := MenuNavItem.make(row.nav_id, normal, focus, restyle)
	var h := MenuWidgets.hbox(10)
	var ic := _icon(g.id, g.slot, 44)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	item.add_child(h)
	return item


func _summary(lines: Array[String]) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", MenuStyle.panel_box(16, 12))
	var v := MenuWidgets.vbox(4)
	v.add_child(MenuStyle.label("COMBINED EFFECTS", MenuStyle.heavy_font(), 13, MenuStyle.YELLOW))
	if lines.is_empty():
		v.add_child(MenuStyle.label("Baseline Moxie — no modifiers.", MenuStyle.ui_italic_font(), 14, MenuStyle.PAPER_DIM, true))
	for s in lines:
		v.add_child(MenuStyle.label("• " + s, MenuStyle.ui_font(), 13, MenuStyle.PAPER, true))
	p.add_child(v)
	return p


func sync(root: Control, focus: String) -> void:
	var model := logic.model
	var slot_box := root.find_child("DetailsSlot", true, false) as VBoxContainer
	if model == null or slot_box == null:
		return
	var eq := MenuModels.equipped_item(model, logic.active_slot)
	var shown := eq
	if focus.begins_with("item:"):
		var it := MenuModels.find_item(model, focus.substr(5))
		if it != null:
			shown = it
	var shown_id := shown.id if shown != null else ""
	if slot_box.get_meta(&"shown", "<none>") != shown_id:
		slot_box.set_meta(&"shown", shown_id)
		for c in slot_box.get_children():
			slot_box.remove_child(c)
			c.queue_free()
		_details(slot_box, shown, eq)
		var sc := root.find_child("DetailsScroll", true, false) as ScrollContainer
		if sc != null:
			sc.scroll_vertical = 0
	var prompts := root.find_child("Prompts", false, false) as HBoxContainer
	if prompts != null and prompts.get_child_count() > 0:
		var last := prompts.get_child(prompts.get_child_count() - 1) as Label
		if last != null:
			last.text = _hint()


func _details(box: VBoxContainer, item: GearItem, equipped: GearItem) -> void:
	var width := 420.0
	if item == null:
		box.add_child(MenuStyle.label("Nothing owned for %s." % MenuFormat.slot_label(logic.active_slot).title, MenuStyle.ui_italic_font(), 15, MenuStyle.PAPER_DIM, true))
		return
	var is_eq := equipped != null and equipped.id == item.id
	box.add_child(MenuStyle.label("%s%s" % [MenuFormat.slot_label(item.slot).title, " · EQUIPPED" if is_eq else ""], MenuStyle.mono_font(), 12, MenuStyle.YELLOW))
	var title_row := MenuWidgets.hbox(14)
	title_row.add_child(_icon(item.id, item.slot, 84))
	var tl := MenuStyle.title_label(item.name.to_upper(), 26, MenuStyle.PAPER, MenuStyle.PINK)
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(tl)
	box.add_child(title_row)
	# The ability this item grants, as its emblem (assets/ui/icons/abilities).
	for ability: StringName in item.abilities:
		if UiArt.ability_icon(String(ability), 40) == null:
			continue
		var ab := MenuWidgets.hbox(8)
		var at := TextureRect.new()
		at.texture = UiArt.ability_icon(String(ability), 40)
		at.custom_minimum_size = Vector2(40, 40)
		at.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		at.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ab.add_child(at)
		var al := MenuStyle.label("ABILITY · %s" % String(ability).capitalize().to_upper(), MenuStyle.heavy_font(), 13, MenuStyle.CYAN)
		al.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ab.add_child(al)
		box.add_child(ab)
	# Weapons turn on a small stage when their model has been delivered (no stand-in otherwise: the
	# numbers below are the content, the model is a bonus).
	if item.melee != null or item.ranged != null:
		var stage := MenuModelStage.try_make(MenuModelStage.weapon_paths(item.id), Vector2(260, WEAPON_STAGE_H), WEAPON_TILT_DEG)
		if stage != null:
			stage.name = "WeaponStage"
			stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			box.add_child(stage)
	box.add_child(MenuStyle.label(item.effect, MenuStyle.ui_bold_font(), 16, MenuStyle.PAPER, true))
	if not is_eq and equipped != null:
		box.add_child(_heading("COMPARED WITH %s" % equipped.name.to_upper()))
		box.add_child(MenuWidgets.compare_table(MenuFormat.compare_items(equipped, item)))
	var rows := MenuFormat.item_detail_rows(item)
	if not rows.is_empty():
		box.add_child(_heading("MECHANICS"))
		box.add_child(MenuWidgets.stat_table(rows, width))
	if not item.lore.is_empty():
		var lore := MenuStyle.label(item.lore, MenuStyle.ui_italic_font(), 14, Color(MenuStyle.PAPER_DIM, 0.9), true)
		box.add_child(MenuWidgets.margin(lore, 0, 6, 0, 0))


func _heading(text: String) -> Label:
	var l := MenuStyle.label(text, MenuStyle.heavy_font(), 12, MenuStyle.PINK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Moxie with a clickable pin per slot, placed on the same aspect-fit as the picture. The picture is
## the generated paper doll (assets/ui/art/doll: 480x880, twice MenuArt.DOLL_BOX) with the active
## slot's region mask lit in Moxie yellow; without the art, the drawn doll (MenuArt.paint_doll).
class DollStage:
	extends Control
	var art: Control
	var pins: Dictionary[StringName, MenuNavItem] = {}
	## Pin anchors in DOLL_BOX fractions from moxie_doll_regions.json (fallback: MenuArt.DOLL_PINS).
	var anchors: Dictionary[StringName, Vector2] = {}

	const REGION_FOR: Dictionary = {
		&"helmet": "head", &"top": "torso", &"pants": "legs", &"shoes": "feet",
		&"melee": "right_hand", &"ranged": "left_wrist",
	}

	func _init(active: StringName) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(280, 380)
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		var doll := UiArt.tex(UiArt.DOLL)
		if doll != null:
			var d := DollArt.new()
			d.doll = doll
			d.mask = UiArt.tex(UiArt.ART + "doll/region_%s.png" % REGION_FOR.get(active, "torso"))
			art = d
			var regions: Dictionary = UiArt.doll_regions().get("regions", {})
			var canvas: Array = UiArt.doll_regions().get("canvas", [480, 880])
			for slot: StringName in REGION_FOR:
				var r: Dictionary = regions.get(REGION_FOR[slot], {})
				var a: Array = r.get("anchor", [])
				if a.size() == 2:
					anchors[slot] = Vector2(float(a[0]) / float(canvas[0]), float(a[1]) / float(canvas[1]))
		else:
			var drawn := MenuArtView.make(Callable(MenuArt, "paint_doll"), MenuArt.DOLL_BOX, Vector2.ZERO, true)
			drawn.slot = active
			art = drawn
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(art)
		for slot in GearSlot.ALL:
			var lab := MenuFormat.slot_label(slot)
			var on := slot == active
			var normal := MenuStyle.box(MenuStyle.INK, MenuStyle.YELLOW if on else Color(MenuStyle.PAPER, 0.5), 2, 12)
			MenuStyle.pad(normal, 8, 1)
			var focus := MenuStyle.box(MenuStyle.YELLOW, MenuStyle.INK, 2, 12, MenuStyle.PINK, Vector2(3, 3))
			MenuStyle.pad(focus, 8, 1)
			var l := MenuStyle.label(lab.short, MenuStyle.heavy_font(), 12, MenuStyle.YELLOW if on else MenuStyle.PAPER)
			var pin := MenuNavItem.make("slot:%s" % slot, normal, focus, func(f: bool) -> void:
				l.add_theme_color_override("font_color", MenuStyle.INK if f else (MenuStyle.YELLOW if on else MenuStyle.PAPER)))
			pin.tooltip_text = lab.title
			pin.add_child(l)
			add_child(pin)
			pins[slot] = pin
		resized.connect(_layout)

	func _ready() -> void:
		_layout.call_deferred()

	func _layout() -> void:
		var box := MenuArt.DOLL_BOX
		var s := minf(size.x / box.x, size.y / box.y)
		var off := (size - box * s) * 0.5
		for slot: StringName in pins:
			var pin := pins[slot]
			var f: Vector2 = anchors.get(slot, MenuArt.DOLL_PINS[slot])
			var ps := pin.get_combined_minimum_size()
			pin.size = ps
			var p := off + Vector2(f.x * box.x, f.y * box.y) * s - ps * 0.5
			pin.position = Vector2(clampf(p.x, 0, maxf(0, size.x - ps.x)), clampf(p.y, 0, maxf(0, size.y - ps.y)))


## The paper-doll picture aspect-fit in MenuArt.DOLL_BOX, with the active slot's mask over it.
class DollArt:
	extends Control
	var doll: Texture2D
	var mask: Texture2D
	var _t: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var box := MenuArt.DOLL_BOX
		var s := minf(size.x / box.x, size.y / box.y)
		var r := Rect2((size - box * s) * 0.5, box * s)
		# A soft floor shadow and the figure.
		draw_circle(Vector2(r.get_center().x, r.end.y - r.size.y * 0.03), r.size.x * 0.32, Color(0, 0, 0, 0.0))
		draw_texture_rect(doll, r, false)
		if mask != null:
			var a := 0.42 + 0.12 * sin(_t * 3.0)
			draw_texture_rect(mask, r, false, Color(MenuStyle.YELLOW, a))
