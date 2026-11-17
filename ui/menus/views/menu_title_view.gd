class_name MenuTitleView
extends MenuScreenView
## Title screen (prototype titleView): the title key art full-screen (assets/ui/art/keyart, its
## quiet left 560 px holds the menu), the OVERDUB wordmark, the line, and Continue / New descent /
## Loadout / Settings / Quit. Without the art it falls back to the drawn cassette logotype on a
## translucent graffiti band over the 3D world.

const TAGLINE := "Four tapes. One world. A solution worth watching."

var logic: MenuTitleLogic


func _init(p_ctl: MenuController, p_logic: MenuTitleLogic) -> void:
	super(p_ctl)
	logic = p_logic


func key() -> String:
	var cleared := -1
	if ctl.campaign_model != null:
		cleared = 0
		for e in ctl.campaign_model.levels:
			if e.cleared:
				cleared += 1
	return "%s|%d|%s" % [logic.confirming_new, cleared, ctl.device]


func build() -> Control:
	var root := screen_root("Title")
	# The band does not swallow clicks over the open world half; only the nav items do.
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := UiArt.key_art()
	var word := UiArt.logo()
	if art != null:
		root.add_child(KeyArt.new(art))
	else:
		root.add_child(TitleBackdrop.new())

	var stack := MenuWidgets.vbox(14)
	var vs := ctl.get_viewport_rect().size if ctl.is_inside_tree() else Vector2(1600, 900)
	if word != null:
		var logo := TextureRect.new()
		logo.texture = word
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		var lw := clampf(vs.x * 0.33, 380.0, 640.0)
		logo.custom_minimum_size = Vector2(lw, lw * float(word.get_height()) / float(word.get_width()))
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(logo)
	else:
		stack.add_child(MenuArtView.make(Callable(MenuArt, "paint_logo"), MenuArt.LOGO_BOX, Vector2(620, 227), true))
	var tag := MenuStyle.label(TAGLINE, MenuStyle.ui_italic_font(), 22, MenuStyle.PAPER)
	tag.add_theme_color_override("font_shadow_color", Color(MenuStyle.INK, 0.85))
	tag.add_theme_constant_override("shadow_offset_x", 2)
	tag.add_theme_constant_override("shadow_offset_y", 2)
	stack.add_child(MenuWidgets.margin(tag, 34, 0, 0, 10))

	var menu := MenuWidgets.vbox(10)
	menu.custom_minimum_size.x = 430
	menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if logic.confirming_new:
		menu.add_child(_confirm())
	else:
		var c := ctl.campaign_model
		var cur: CampaignLevelEntry = null
		if c != null and c.current >= 0 and c.current < c.levels.size():
			cur = c.levels[c.current]
		var has_continue := false
		for e in logic.menu().entries:
			if e.id == "continue":
				has_continue = true
		for e in logic.menu().entries:
			match e.id:
				"continue":
					var sub := "Depth %s — %s" % [MenuModels.depth_label(c.current), cur.level.name] if cur != null else ""
					menu.add_child(MenuWidgets.button("continue", "Continue", sub, MenuWidgets.TONE_PRIMARY))
				"new":
					if has_continue:
						menu.add_child(MenuWidgets.button("new", "New descent", "Erases progress"))
					else:
						menu.add_child(MenuWidgets.button("new", "New descent", "Into the ruins", MenuWidgets.TONE_PRIMARY))
				"loadout":
					menu.add_child(MenuWidgets.button("loadout", "Loadout", "Gear for all four tapes"))
				"settings":
					menu.add_child(MenuWidgets.button("settings", "Settings", "Volume, offset, patterns, quality"))
				"quit":
					menu.add_child(MenuWidgets.button("quit", "Quit", "", MenuWidgets.TONE_GHOST, true))
	stack.add_child(MenuWidgets.margin(menu, 46, 4, 0, 0))

	var m := MenuWidgets.margin(stack, 56, 40 if word != null else 52, 0, 0)
	m.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.add_child(m)
	add_prompts(root)
	return root


func _confirm() -> Control:
	var p := MenuWidgets.panel(22, 18)
	var sb := MenuStyle.panel_box(22, 18)
	sb.border_color = Color(MenuStyle.BAD, 0.7)
	p.add_theme_stylebox_override("panel", sb)
	var v := MenuWidgets.vbox(8)
	v.add_child(MenuStyle.title_label("START A NEW DESCENT?", 22, MenuStyle.PAPER, MenuStyle.BAD))
	v.add_child(MenuStyle.label("This erases cleared levels and every piece of gear you found.", MenuStyle.ui_font(), 15, MenuStyle.PAPER_DIM, true))
	var row := MenuWidgets.hbox(12)
	row.add_child(MenuWidgets.button("new-no", "Keep my save", "", MenuWidgets.TONE_GHOST))
	row.add_child(MenuWidgets.button("new-yes", "Erase & start over", "", MenuWidgets.TONE_DANGER))
	v.add_child(row)
	p.add_child(v)
	return p


## The key art, covering the screen and anchored to its right edge (Moxie and the echoes stay in
## view at any aspect), with an ink fade over the quiet left side so the menu always reads.
class KeyArt:
	extends Control
	var tex: Texture2D

	func _init(t: Texture2D) -> void:
		tex = t
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var ts := tex.get_size()
		var s := maxf(size.x / ts.x, size.y / ts.y)
		var d := ts * s
		draw_texture_rect(tex, Rect2(Vector2(size.x - d.x, (size.y - d.y) * 0.5), d), false)
		var w := minf(size.x * 0.46, 760.0)
		var a := Color(MenuStyle.INK, 0.78)
		var b := Color(MenuStyle.INK, 0.0)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, size.y), Vector2(0, size.y)]), PackedColorArray([a, b, b, a]))


## The graffiti band behind the title column: a slanted translucent ink slab with yellow and pink
## sticker stripes, and the four cassette colours running down its edge.
class TitleBackdrop:
	extends Control

	var _t: float = 0.0

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var x0 := minf(w * 0.47, 780.0)
		var x1 := x0 - h * 0.16
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(x0, 0), Vector2(x1, h), Vector2(0, h)]), Color(MenuStyle.INK, 0.74))
		# Sticker stripes along the slab edge.
		draw_colored_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x0 + 14, 0), Vector2(x1 + 14, h), Vector2(x1, h)]), MenuStyle.YELLOW)
		draw_colored_polygon(PackedVector2Array([Vector2(x0 + 22, 0), Vector2(x0 + 28, 0), Vector2(x1 + 28, h), Vector2(x1 + 22, h)]), MenuStyle.PINK)
		# Four cassette colours as a moving tape lane inside the edge.
		var lane := 10.0
		for i in OD.TAPE_COUNT:
			var off := -18.0 - (i + 1) * (lane + 4)
			var col := Color(MenuStyle.tape(i), 0.55)
			var seg := 70.0
			var y := fmod(_t * (24.0 + i * 9.0), seg * 2.0) - seg * 2.0
			while y < h:
				var a := Vector2(lerpf(x0, x1, y / h) + off, y)
				var b := Vector2(lerpf(x0, x1, (y + seg) / h) + off, y + seg)
				draw_line(a, b, col, lane * 0.45)
				y += seg * 2.0
		# Halftone dots in the open corner, so the world half still reads as part of the poster.
		for gy in range(0, 7):
			for gx in range(0, 12):
				var r := 2.6 * (1.0 - gy / 7.0)
				if r > 0.3:
					draw_circle(Vector2(w - 30 - gx * 22, h - 34 - gy * 22), r * (1.0 - gx / 14.0), Color(MenuStyle.YELLOW, 0.22))
