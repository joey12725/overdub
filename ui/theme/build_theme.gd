extends SceneTree
## Rebuilds the shared UI resources from code:
##   res://ui/theme/fonts/od_display.tres, od_ui.tres, od_mono.tres   (FontVariation)
##   res://ui/theme/od_theme.tres                                      (Theme)
## Run:  bash tools/gd script res://ui/theme/build_theme.gd
##
## Style: anime-streetwear sticker UI. Near-black panels with a chunky ink border and a hard offset
## ink shadow, warm paper text, Moxie-yellow accents, rounded-but-blocky corners.
##
## Type variations defined here (Control.theme_type_variation):
##   Label:  "TitleLabel" (display font, 44), "HeaderLabel" (display, 26), "StickerLabel" (display 16,
##           ink on yellow), "MonoLabel" (mono 15), "DimLabel" (ui 15, paper-dim)
##   Button: "AccentButton" (yellow, ink text), "DangerButton" (red), "GhostButton" (outline only)
##   PanelContainer: "CardPanel" (solid panel, paper hairline + hard shadow), "StickerPanel"
##           (yellow with ink border)

const OUT_THEME := "res://ui/theme/od_theme.tres"
const P := preload("res://ui/theme/palette.gd")


func _init() -> void:
	var ok := true
	var display := P.make_font("Inter.woff2", 900, 0.0, -1)
	var ui := P.make_font("Inter.woff2", 600, 0.0, 0)
	var mono := P.make_font("DejaVuSansMono.woff2", 0, 0.55, 0)
	ok = _save(display, "res://ui/theme/fonts/od_display.tres") and ok
	ok = _save(ui, "res://ui/theme/fonts/od_ui.tres") and ok
	ok = _save(mono, "res://ui/theme/fonts/od_mono.tres") and ok
	# Reload so the theme references the saved resources by path rather than embedding copies.
	display = load("res://ui/theme/fonts/od_display.tres") as FontVariation
	ui = load("res://ui/theme/fonts/od_ui.tres") as FontVariation
	mono = load("res://ui/theme/fonts/od_mono.tres") as FontVariation
	var t := build(display, ui, mono)
	ok = _save(t, OUT_THEME) and ok
	print("build_theme: ", "ok" if ok else "FAILED")
	quit(0 if ok else 1)


func _save(res: Resource, path: String) -> bool:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("build_theme: could not save %s (%s)" % [path, error_string(err)])
		return false
	res.take_over_path(path)
	return true


static func box(bg: Color, border: Color, bw: int, radius: int, shadow: bool, pad_x: int, pad_y: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	s.anti_aliasing = true
	if shadow:
		s.shadow_color = P.INK
		s.shadow_size = 0
		s.shadow_offset = Vector2(5, 5)
	return s


static func build(display: Font, ui: Font, mono: Font) -> Theme:
	var t := Theme.new()
	t.default_font = ui
	t.default_font_size = 18

	# ── Label
	t.set_color("font_color", "Label", P.PAPER)
	t.set_color("font_outline_color", "Label", P.INK)
	t.set_constant("outline_size", "Label", 0)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))

	_label_variation(t, "TitleLabel", display, 44, P.PAPER, 10)
	_label_variation(t, "HeaderLabel", display, 26, P.PAPER, 6)
	_label_variation(t, "MonoLabel", mono, 15, P.PAPER, 0)
	_label_variation(t, "DimLabel", ui, 15, P.PAPER_DIM, 0)
	t.add_type("StickerLabel")
	t.set_type_variation("StickerLabel", "Label")
	t.set_font("font", "StickerLabel", display)
	t.set_font_size("font_size", "StickerLabel", 16)
	t.set_color("font_color", "StickerLabel", P.INK)
	t.set_stylebox("normal", "StickerLabel", box(P.MOXIE_YELLOW, P.INK, 3, 5, false, 8, 2))

	# ── Buttons
	_button(t, "Button", P.PANEL_SOLID, P.PAPER, P.MOXIE_YELLOW)
	t.set_font("font", "Button", display)
	t.set_font_size("font_size", "Button", 18)
	_button(t, "AccentButton", P.MOXIE_YELLOW, P.INK, P.PAPER)
	t.set_type_variation("AccentButton", "Button")
	_button(t, "DangerButton", P.STATE_BAD, P.INK, P.PAPER)
	t.set_type_variation("DangerButton", "Button")
	t.add_type("GhostButton")
	t.set_type_variation("GhostButton", "Button")
	t.set_stylebox("normal", "GhostButton", box(Color(0, 0, 0, 0), P.PAPER_DIM, 3, 8, false, 16, 8))
	t.set_stylebox("hover", "GhostButton", box(P.alpha(P.PAPER, 0.08), P.PAPER, 3, 8, false, 16, 8))
	t.set_stylebox("pressed", "GhostButton", box(P.alpha(P.PAPER, 0.16), P.MOXIE_YELLOW, 3, 8, false, 16, 8))

	for b: StringName in [&"CheckBox", &"CheckButton", &"OptionButton", &"MenuButton"]:
		t.set_font("font", b, ui)
		t.set_color("font_color", b, P.PAPER)
		t.set_color("font_hover_color", b, P.MOXIE_YELLOW)
		t.set_color("font_pressed_color", b, P.MOXIE_YELLOW)
		t.set_color("font_focus_color", b, P.PAPER)
		t.set_color("font_disabled_color", b, P.MUTED_TEXT)
	t.set_stylebox("normal", "OptionButton", box(P.PANEL_SOLID, P.INK, 3, 8, true, 14, 8))
	t.set_stylebox("hover", "OptionButton", box(P.INK_SOFT, P.MOXIE_YELLOW, 3, 8, true, 14, 8))
	t.set_stylebox("pressed", "OptionButton", box(P.INK_SOFT, P.MOXIE_YELLOW, 3, 8, true, 14, 8))
	t.set_stylebox("focus", "OptionButton", _focus())

	# ── Panels
	var panel := box(P.PANEL_SOLID, P.INK, 4, 12, true, 18, 14)
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.add_type("CardPanel")
	t.set_type_variation("CardPanel", "PanelContainer")
	var card := box(P.PANEL_SOLID, P.INK, 4, 14, true, 22, 18)
	card.expand_margin_left = 0
	t.set_stylebox("panel", "CardPanel", card)
	t.add_type("StickerPanel")
	t.set_type_variation("StickerPanel", "PanelContainer")
	t.set_stylebox("panel", "StickerPanel", box(P.MOXIE_YELLOW, P.INK, 4, 8, true, 12, 6))

	# ── Text inputs
	t.set_stylebox("normal", "LineEdit", box(P.TRACK, P.INK, 3, 6, false, 10, 6))
	t.set_stylebox("focus", "LineEdit", box(P.TRACK, P.MOXIE_YELLOW, 3, 6, false, 10, 6))
	t.set_color("font_color", "LineEdit", P.PAPER)
	t.set_color("caret_color", "LineEdit", P.MOXIE_YELLOW)
	t.set_font("font", "LineEdit", mono)

	# ── Sliders / progress
	var groove := box(P.TRACK, P.INK, 2, 6, false, 0, 4)
	t.set_stylebox("slider", "HSlider", groove)
	t.set_stylebox("grabber_area", "HSlider", box(P.MOXIE_YELLOW, P.INK, 2, 6, false, 0, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(P.PAPER, P.INK, 2, 6, false, 0, 4))
	t.set_stylebox("background", "ProgressBar", box(P.TRACK, P.INK, 3, 6, false, 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(P.MOXIE_YELLOW, P.INK, 3, 6, false, 0, 0))
	t.set_color("font_color", "ProgressBar", P.PAPER)
	t.set_font("font", "ProgressBar", mono)

	# ── Scroll bars
	t.set_stylebox("scroll", "VScrollBar", box(P.TRACK, P.INK, 0, 4, false, 4, 4))
	t.set_stylebox("grabber", "VScrollBar", box(P.PAPER_DIM, P.INK, 2, 4, false, 4, 4))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(P.MOXIE_YELLOW, P.INK, 2, 4, false, 4, 4))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(P.MOXIE_YELLOW, P.INK, 2, 4, false, 4, 4))

	# ── Tooltips / popups
	t.set_stylebox("panel", "TooltipPanel", box(P.PAPER, P.INK, 3, 6, false, 10, 6))
	t.set_color("font_color", "TooltipLabel", P.INK)
	t.set_font("font", "TooltipLabel", ui)
	t.set_stylebox("panel", "PopupMenu", box(P.PANEL_SOLID, P.INK, 3, 8, true, 6, 6))
	t.set_stylebox("hover", "PopupMenu", box(P.MOXIE_YELLOW, P.INK, 0, 4, false, 6, 2))
	t.set_color("font_color", "PopupMenu", P.PAPER)
	t.set_color("font_hover_color", "PopupMenu", P.INK)

	# ── Separators
	var sep := StyleBoxLine.new()
	sep.color = P.PANEL_EDGE
	sep.thickness = 2
	t.set_stylebox("separator", "HSeparator", sep)
	return t


static func _label_variation(t: Theme, name: StringName, font: Font, size: int, color: Color, outline: int) -> void:
	t.add_type(name)
	t.set_type_variation(name, "Label")
	t.set_font("font", name, font)
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, color)
	t.set_color("font_outline_color", name, P.INK)
	t.set_constant("outline_size", name, outline)


static func _focus() -> StyleBoxFlat:
	var f := box(Color(0, 0, 0, 0), P.PAPER, 3, 10, false, 0, 0)
	f.draw_center = false
	f.expand_margin_left = 4
	f.expand_margin_right = 4
	f.expand_margin_top = 4
	f.expand_margin_bottom = 4
	return f


static func _button(t: Theme, type: StringName, bg: Color, fg: Color, accent: Color) -> void:
	t.add_type(type)
	t.set_stylebox("normal", type, box(bg, P.INK, 4, 9, true, 18, 9))
	var hover := box(bg.lightened(0.08), accent, 4, 9, true, 18, 9)
	t.set_stylebox("hover", type, hover)
	var pressed := box(bg.darkened(0.12), accent, 4, 9, false, 18, 9)
	pressed.expand_margin_left = -3
	pressed.expand_margin_top = -3
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("disabled", type, box(P.MUTED, P.INK, 4, 9, false, 18, 9))
	t.set_stylebox("focus", type, _focus())
	t.set_color("font_color", type, fg)
	t.set_color("font_hover_color", type, fg if type != &"Button" else accent)
	t.set_color("font_pressed_color", type, fg if type != &"Button" else accent)
	t.set_color("font_focus_color", type, fg)
	t.set_color("font_hover_pressed_color", type, fg if type != &"Button" else accent)
	t.set_color("font_disabled_color", type, P.MUTED_TEXT)
	t.set_color("font_outline_color", type, P.INK)
