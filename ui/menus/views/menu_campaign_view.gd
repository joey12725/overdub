class_name MenuCampaignView
extends MenuScreenView
## The descent (prototype campaignView; LEVEL-08 fixed path, LEVEL-09 replay). A vertical path from
## warm upper ruins to dark neon metal and the time machine: each level a node with name, tagline,
## cassette count, offered speeds and end modes, cleared state and loot. Locked levels are visibly
## locked (and shake when tried); cleared levels say they can be replayed.

const COLUMN_W := 880.0
const PIN_W := 84.0

var logic: MenuCampaignLogic


func _init(p_ctl: MenuController, p_logic: MenuCampaignLogic) -> void:
	super(p_ctl)
	logic = p_logic


func key() -> String:
	var c := ctl.codex_logic.codex
	return "%d|%d|%s|%s|%s|%s|%d" % [ctl.campaign_version, logic.locked_pokes, ctl.device, ctl.patterns, logic.has_guide(), logic.replays.hash(), c.unlocked_count() if c != null else -1]


func build() -> Control:
	var root := screen_root("Campaign")
	root.add_child(DescentBackdrop.new())

	var col := MenuWidgets.vbox(0)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(col)

	# Top bar: back, title, loadout.
	var bar := MenuWidgets.hbox(18)
	var back := MenuWidgets.button("back", "◀ Title", "", MenuWidgets.TONE_GHOST, true)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(back)
	var title_box := MenuWidgets.vbox(0)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := MenuStyle.title_label("THE DESCENT", 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(t)
	var sub := MenuStyle.label("Fixed path down. Cleared levels can be replayed with any gear.", MenuStyle.ui_font(), 15, MenuStyle.PAPER_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(sub)
	bar.add_child(title_box)
	var to_loadout := MenuWidgets.button("loadout", "Loadout", "Gear for every tape", MenuWidgets.TONE_DEFAULT, true)
	to_loadout.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(to_loadout)
	if logic.has_guide():
		bar.add_child(_guide_button())
	var band := PanelContainer.new()
	var band_box := MenuStyle.box(Color(MenuStyle.INK, 0.72), Color.TRANSPARENT, 0, 0)
	band_box.border_width_bottom = 3
	band_box.border_color = Color(MenuStyle.YELLOW, 0.55)
	band.add_theme_stylebox_override("panel", band_box)
	band.add_child(MenuWidgets.margin(bar, 28, 16, 28, 12))
	col.add_child(band)

	var scroll := MenuWidgets.scroller("descent")
	scroll.set_meta(&"scroll_center", true)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.use_top_left = false
	scroll.add_child(centre)
	var list := DescentList.new()
	list.custom_minimum_size.x = COLUMN_W
	list.add_theme_constant_override("separation", 18)
	centre.add_child(MenuWidgets.margin(list, 0, 18, 0, 120))

	var nodes := MenuModels.campaign_nodes(logic.model)
	var last_theme: StringName = &""
	for n in nodes:
		# A chapter card heads each stretch of the descent (the wordless card art + its title).
		if n.theme != last_theme:
			last_theme = n.theme
			var card := _chapter_banner(n.theme)
			if card != null:
				list.add_child(card)
		list.add_child(_node(n))
	if nodes.is_empty():
		list.add_child(MenuStyle.label("Loading the path…", MenuStyle.ui_italic_font(), 18, MenuStyle.PAPER_DIM))
	add_prompts(root)
	return root


func _node(n: MenuModels.CampaignNode) -> Control:
	var accent := MenuStyle.theme_accent(n.theme)
	var locked := n.status == MenuModels.STATUS_LOCKED
	var card_normal := MenuStyle.box(MenuStyle.theme_card(n.theme), MenuStyle.theme_edge(n.theme), 2, MenuStyle.RADIUS)
	MenuStyle.pad(card_normal, 20, 14)
	var card_focus := MenuStyle.box(MenuStyle.theme_card(n.theme).lightened(0.06), MenuStyle.YELLOW, 3, MenuStyle.RADIUS, MenuStyle.PINK, Vector2(7, 7))
	MenuStyle.pad(card_focus, 20, 14)

	var row := MenuWidgets.hbox(0)
	var pin := DescentPin.new()
	pin.depth = n.depth
	pin.accent = accent
	pin.final = n.final
	pin.locked = locked
	pin.custom_minimum_size = Vector2(PIN_W, 72)
	pin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(pin)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", card_normal)
	row.add_child(card)
	var body := MenuWidgets.vbox(4)
	card.add_child(body)

	var head := MenuWidgets.hbox(10)
	var depth := MenuStyle.label("DEPTH %s · %s" % [n.depth, n.theme_label.to_upper()], MenuStyle.mono_font(), 13, accent)
	depth.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(depth)
	head.add_child(_badge(n.status))
	body.add_child(head)
	var name_col := Color(MenuStyle.PAPER, 0.55) if locked else MenuStyle.PAPER
	body.add_child(MenuStyle.label(n.name.to_upper(), MenuStyle.display_font(), 26, name_col))
	body.add_child(MenuStyle.label(n.tagline, MenuStyle.ui_italic_font(), 16, MenuStyle.PAPER_DIM, true))

	var meta := HFlowContainer.new()
	meta.add_theme_constant_override("h_separation", 18)
	meta.add_theme_constant_override("v_separation", 6)
	var tapes := MenuWidgets.hbox(6)
	tapes.add_child(MenuWidgets.tape_strip(n.max_tapes, ctl.patterns, 26))
	tapes.add_child(MenuStyle.label("%d tape%s" % [n.max_tapes, "" if n.max_tapes == 1 else "s"], MenuStyle.ui_bold_font(), 14, MenuStyle.PAPER_DIM))
	meta.add_child(tapes)
	var speeds := MenuWidgets.hbox(5)
	for s in n.speeds:
		speeds.add_child(MenuWidgets.chip(s, accent))
	meta.add_child(speeds)
	if not n.end_modes.is_empty():
		var modes := MenuWidgets.hbox(5)
		for m in n.end_modes:
			modes.add_child(MenuWidgets.chip(m.to_upper(), accent, true))
		meta.add_child(modes)
	body.add_child(MenuWidgets.margin(meta, 0, 6, 0, 0))

	var loot := MenuWidgets.hbox(8)
	loot.add_child(MenuArtView.icon(Callable(MenuArt, "paint_crate"), 18, accent))
	var text := ""
	if n.loot_count == 0:
		text = "No gear here"
	elif n.loot_found:
		if not n.loot_items.is_empty():
			var names: Array[String] = []
			for g in n.loot_items:
				names.append(g.name)
			text = "Found: " + ", ".join(names)
		else:
			text = "Found %d item%s" % [n.loot_count, "" if n.loot_count == 1 else "s"]
	else:
		text = "%d item%s to find" % [n.loot_count, "" if n.loot_count == 1 else "s"]
	var loot_label := MenuStyle.label(text, MenuStyle.ui_font(), 14, MenuStyle.PAPER if n.loot_found and n.loot_count > 0 else MenuStyle.PAPER_DIM, true)
	loot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loot.add_child(loot_label)
	# Found gear as its sticker icons.
	for g in n.loot_items:
		var ic := _gear_icon(g.id, 30)
		if ic != null:
			loot.add_child(ic)
	body.add_child(MenuWidgets.margin(loot, 0, 4, 0, 0))

	var restyle := func(f: bool) -> void:
		card.add_theme_stylebox_override("panel", card_focus if f else card_normal)
		pin.focused = f
		pin.queue_redraw()
	var item := MenuNavItem.make(n.nav_id, MenuStyle.empty_box(), MenuStyle.empty_box(), restyle)
	item.add_child(row)
	if locked:
		item.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
	if logic.last_poked == n.nav_id and logic.locked_pokes > 0:
		item.set_meta(&"shake", true)
	if n.cleared and logic.can_watch(n.id):
		# "Watch again": the kept winning performance of a solved level, beside its card.
		var wrap := MenuWidgets.hbox(10)
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrap.add_child(item)
		var watch := MenuWidgets.button("watch:%s" % n.id, "▶ Watch", "the kept take", MenuWidgets.TONE_DEFAULT, true)
		watch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		watch.custom_minimum_size.x = 150
		wrap.add_child(watch)
		return wrap
	return item


static func _gear_icon(id: String, px: float) -> TextureRect:
	var t := UiArt.gear_icon(id, px)
	if t == null:
		return null
	var r := TextureRect.new()
	r.texture = t
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


## The Field Guide button: pages found out of the total, and a NEW pip when a page is unread.
func _guide_button() -> Control:
	var c := ctl.codex_logic.codex
	var sub := "%d / %d pages" % [c.unlocked_count(), c.entry_count()] if c != null else ""
	var any_new := false
	if c != null:
		for row: Dictionary in ctl.codex_logic.rows():
			if c.is_new(str((row["entry"] as Dictionary).get("id", ""))):
				any_new = true
				break
	if any_new:
		sub += "  ·  NEW PAGE"
	var b := MenuWidgets.button("guide", "Field Guide", sub, MenuWidgets.TONE_DEFAULT, true)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


## A wordless chapter card (assets/ui/art/cards) as a banner strip with its title set in engine.
func _chapter_banner(theme: StringName) -> Control:
	var t := UiArt.chapter_card(theme)
	if t == null:
		return null
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(COLUMN_W, 150)
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var img := TextureRect.new()
	img.texture = t
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(img)
	var fade := ChapterFade.new()
	fade.accent = MenuStyle.theme_accent(theme)
	holder.add_child(fade)
	var words := UiArt.chapter_title(theme)
	var v := MenuWidgets.vbox(0)
	v.add_child(MenuStyle.label(words[0], MenuStyle.mono_font(), 14, MenuStyle.theme_accent(theme)))
	v.add_child(MenuStyle.title_label(words[1], 34, MenuStyle.PAPER, MenuStyle.INK))
	var m := MenuWidgets.margin(v, 24, 0, 0, 16)
	m.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	m.grow_vertical = Control.GROW_DIRECTION_BEGIN
	holder.add_child(m)
	return holder


## Ink gradient from the left so the chapter title reads over any card, plus the theme's edge line.
class ChapterFade:
	extends Control
	var accent: Color = MenuStyle.YELLOW

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var a := Color(MenuStyle.INK, 0.85)
		var b := Color(MenuStyle.INK, 0.0)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.6, 0), Vector2(w * 0.6, h), Vector2(0, h)]), PackedColorArray([a, b, b, a]))
		draw_rect(Rect2(Vector2.ZERO, size), MenuStyle.INK, false, 3.0)
		draw_rect(Rect2(0, h - 4, w, 4), accent)


func _badge(status: StringName) -> Control:
	var h := MenuWidgets.hbox(5)
	var col := MenuStyle.PAPER_DIM
	var text := "OPEN"
	match status:
		MenuModels.STATUS_LOCKED:
			col = MenuStyle.STATE_DEAD
			text = "LOCKED"
			h.add_child(MenuArtView.icon(Callable(MenuArt, "paint_lock"), 16, col))
		MenuModels.STATUS_CLEARED:
			col = MenuStyle.GOOD
			text = "CLEARED · REPLAY"
			h.add_child(MenuArtView.icon(Callable(MenuArt, "paint_check"), 16, col))
		MenuModels.STATUS_NEXT:
			col = MenuStyle.YELLOW
			text = "NEXT"
	var p := PanelContainer.new()
	var sb := MenuStyle.box(Color(col, 0.14) if status != MenuModels.STATUS_NEXT else MenuStyle.YELLOW, Color(col, 0.6), 1, 4)
	MenuStyle.pad(sb, 8, 1)
	p.add_theme_stylebox_override("panel", sb)
	h.add_child(MenuStyle.label(text, MenuStyle.heavy_font(), 12, MenuStyle.INK if status == MenuModels.STATUS_NEXT else col))
	p.add_child(h)
	return p


func sync(root: Control, _focus: String) -> void:
	# Shake a freshly poked locked level once.
	for item in ctl.nav_items_of(root):
		if item.has_meta(&"shake"):
			item.remove_meta(&"shake")
			ctl.shake(item)


## The descent's light arc behind the whole screen (WORLD-04): sunlit stone at the top, neon-dark
## metal at the bottom; translucent so the level behind still shows.
class DescentBackdrop:
	extends Control

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var stops: Array[Color] = [
			Color(0.47, 0.32, 0.13, 0.5), Color(0.2, 0.15, 0.1, 0.62), Color(0.07, 0.08, 0.13, 0.78), Color(0.04, 0.02, 0.09, 0.9)]
		var ys: Array[float] = [0.0, 0.35, 0.7, 1.0]
		for i in stops.size() - 1:
			var y0 := ys[i] * size.y
			var y1 := ys[i + 1] * size.y
			draw_polygon(PackedVector2Array([Vector2(0, y0), Vector2(size.x, y0), Vector2(size.x, y1), Vector2(0, y1)]),
				PackedColorArray([stops[i], stops[i], stops[i + 1], stops[i + 1]]))


## The node list; draws the descent track (dashed, yellow -> rust -> pink -> violet -> cyan) behind
## the pins.
class DescentList:
	extends VBoxContainer

	func _draw() -> void:
		var x := MenuCampaignView.PIN_W * 0.5
		var top := 30.0
		var bottom := size.y - 30.0
		if bottom <= top:
			return
		var grad: Array[Color] = [MenuStyle.YELLOW, MenuStyle.RUST, MenuStyle.PINK, MenuStyle.VIOLET, MenuStyle.CYAN]
		var y := top
		while y < bottom:
			var f := (y - top) / (bottom - top)
			var gi := f * (grad.size() - 1)
			var c := grad[int(gi)].lerp(grad[mini(int(gi) + 1, grad.size() - 1)], gi - int(gi))
			draw_line(Vector2(x, y), Vector2(x, minf(y + 10, bottom)), c, 6)
			y += 16.0


## A level's pin on the track: a ringed depth counter, a padlock tint when locked, and the time
## machine for the last level.
class DescentPin:
	extends Control
	var depth: String = "01"
	var accent: Color = MenuStyle.YELLOW
	var final: bool = false
	var locked: bool = false
	var focused: bool = false
	var _t: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(final)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, 38)
		if final:
			draw_circle(c, 36, Color(MenuStyle.VIOLET, 0.25 + (0.2 if focused else 0.0)))
			draw_set_transform(c - Vector2(32, 32) * 1.05, 0.0, Vector2(1.05, 1.05))
			MenuArt.paint_time_machine(self, _t, null)
			draw_set_transform(Vector2.ZERO)
			return
		var r := 24.0
		if focused:
			draw_circle(c, r + 7, Color(MenuStyle.YELLOW, 0.35))
			draw_circle(c, r, MenuStyle.YELLOW)
			draw_arc(c, r, 0, TAU, 40, MenuStyle.INK, 3, true)
		else:
			draw_circle(c, r, MenuStyle.INK)
			draw_arc(c, r, 0, TAU, 40, Color(accent, 0.5) if locked else accent, 3, true)
		var font := MenuStyle.heavy_font()
		var fs := 17
		var col := MenuStyle.INK if focused else (Color(accent, 0.55) if locked else accent)
		var ts := font.get_string_size(depth, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, c + Vector2(-ts.x * 0.5, ts.y * 0.32), depth, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
