class_name MenuEndingView
extends MenuScreenView
## The closing card for reaching the time machine (prototype endingView). Short and non-committal: it
## names what she found and leaves what happens next unsaid (the ending is unspecified in the bible).
## Over the ending card art (assets/ui/art/cards: the approach cross-fading into the gate opening),
## with the words on an ink band at the bottom. Without the art: the time machine model when the kit
## provides one, else the drawn emblem, over a violet field.

var logic: MenuEndingLogic


func _init(p_ctl: MenuController, p_logic: MenuEndingLogic) -> void:
	super(p_ctl)
	logic = p_logic


func _stats() -> Array[int]:
	var cleared := 0
	var total := 0
	if ctl.campaign_model != null:
		total = ctl.campaign_model.levels.size()
		for e in ctl.campaign_model.levels:
			if e.cleared:
				cleared += 1
	var gear := -1
	if ctl.loadout_model != null:
		gear = ctl.loadout_model.inventory.size()
	return [cleared, total, gear]


func key() -> String:
	return "%s|%s" % [_stats(), ctl.device]


func build() -> Control:
	var root := screen_root("Ending")
	var card := UiArt.ending_card()
	if card != null:
		root.add_child(EndingArt.new(UiArt.tex(UiArt.ENDING_APPROACH), card))
	else:
		root.add_child(EndingBackdrop.new())
	var s := _stats()
	var p := MenuWidgets.panel(40, 30)
	var sb := MenuStyle.panel_box(40, 30)
	sb.border_color = Color(MenuStyle.VIOLET, 0.7)
	sb.shadow_color = Color(MenuStyle.VIOLET, 0.45)
	p.add_theme_stylebox_override("panel", sb)
	var v := MenuWidgets.vbox(12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER

	if card == null:
		var art: Control = MenuModelStage.try_make(MenuModelStage.time_machine_paths(), Vector2(260, 220))
		if art == null:
			art = MenuArtView.make(Callable(MenuArt, "paint_time_machine"), MenuArt.TM_BOX, Vector2(200, 200), true)
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(art)

	var kicker := MenuStyle.label("THE BOTTOM OF THE DESCENT", MenuStyle.mono_font(), 15, MenuStyle.CYAN)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(kicker)
	var title := MenuStyle.title_label("SHE FOUND IT.", 56 if card == null else 46, MenuStyle.YELLOW, MenuStyle.VIOLET)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var text := MenuStyle.label("Past the last door and the last take: the time machine. What Moxie does with it is her business.",
		MenuStyle.ui_font(), 18, MenuStyle.PAPER, true)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(text)
	var stats := "%d / %d levels cleared" % [s[0], s[1]]
	if s[2] >= 0:
		stats += " · %d pieces of gear found" % s[2]
	var st := MenuStyle.label(stats, MenuStyle.mono_font(), 14, MenuStyle.PAPER_DIM)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st)
	var row := MenuWidgets.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(MenuWidgets.button("path", "Back to the path", "", MenuWidgets.TONE_PRIMARY))
	row.add_child(MenuWidgets.button("title", "Title", "", MenuWidgets.TONE_GHOST))
	v.add_child(MenuWidgets.margin(row, 0, 8, 0, 0))
	p.add_child(v)
	if card == null:
		centred(root, p, 760)
	else:
		# The words sit low so the gate and the four echoes stay in view.
		var band := Control.new()
		band.set_anchors_preset(Control.PRESET_FULL_RECT)
		band.anchor_top = 0.5
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(band)
		var cc := CenterContainer.new()
		cc.set_anchors_preset(Control.PRESET_FULL_RECT)
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.custom_minimum_size.x = 820
		cc.add_child(p)
		band.add_child(cc)
	add_prompts(root)
	return root


## The ending card: `approach` (her walking up) cross-fades into `card` (the gate open, cassette
## raised) over the first seconds, then holds; a slow push-in keeps it alive.
class EndingArt:
	extends Control
	var approach: Texture2D
	var card: Texture2D
	var _t: float = 0.0

	func _init(p_approach: Texture2D, p_card: Texture2D) -> void:
		approach = p_approach
		card = p_card
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		if _t < 12.0:
			queue_redraw()

	func _cover(t: Texture2D, zoom: float, a: float) -> void:
		var ts := t.get_size()
		var s := maxf(size.x / ts.x, size.y / ts.y) * zoom
		var d := ts * s
		draw_texture_rect(t, Rect2((size - d) * 0.5, d), false, Color(1, 1, 1, a))

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
		var zoom := 1.0 + minf(_t, 12.0) * 0.004
		var k := clampf((_t - 0.8) / 2.2, 0.0, 1.0)
		if approach != null and k < 1.0:
			_cover(approach, zoom, 1.0)
		_cover(card, zoom, k if approach != null else 1.0)
		# Ink at the bottom so the card's words read.
		var top := size.y * 0.45
		draw_polygon(PackedVector2Array([Vector2(0, top), Vector2(size.x, top), Vector2(size.x, size.y), Vector2(0, size.y)]),
			PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.8), Color(0, 0, 0, 0.8)]))


## Deep violet field with slow concentric "clock" rings around the card.
class EndingBackdrop:
	extends Control
	var _t: float = 0.0

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.02, 0.08, 0.86))
		var c := size * 0.5
		for i in 7:
			var r := 220.0 + i * 70.0 + fmod(_t * 18.0, 70.0)
			var a := clampf(1.0 - (r - 220.0) / 520.0, 0.0, 1.0) * 0.35
			var col := (MenuStyle.CYAN if i % 2 == 0 else MenuStyle.VIOLET)
			MenuVector.dashed_circle(self, c, r, Color(col, a), 2.0, 14.0, 10.0, _t * (0.05 if i % 2 == 0 else -0.04))
