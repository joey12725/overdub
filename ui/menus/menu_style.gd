class_name MenuStyle
extends RefCounted
## Menu look: colours, fonts and StyleBox builders (prototype ui/tokens.css + shell.css). Colours and
## fonts come from the shared UI tokens (ui/theme/palette.gd, UiPalette) so the menus and the HUD are
## one family: Moxie's palette (yellow headphones and Walkman as the key colour, ink/charcoal, olive
## cargo, pink graffiti), the cassette identities, and the bundled Inter / DejaVu Sans Mono faces.
## Never instantiated.

# ───────────────────────────── palette ─────────────────────────────

const YELLOW := UiPalette.MOXIE_YELLOW
const YELLOW_DEEP := Color("#f0bf1f")
const INK := UiPalette.INK
const INK_SOFT := UiPalette.INK_SOFT
const PAPER := UiPalette.PAPER
const PAPER_DIM := UiPalette.PAPER_DIM
const OLIVE := UiPalette.OLIVE
const RUST := UiPalette.RUST
const PINK := UiPalette.GRAFFITI_PINK
const VIOLET := UiPalette.GRAFFITI_VIOLET
const CYAN := UiPalette.NEON_CYAN
const STATE_DEAD := UiPalette.STATE_DEAD
const STATE_DESYNC := UiPalette.STATE_DESYNC
const GOOD := UiPalette.STATE_GOOD
const WARN := UiPalette.STATE_WARN
const BAD := UiPalette.STATE_BAD

## Translucent panel fill: the 3D world shows through behind every menu.
const PANEL := UiPalette.PANEL
const PANEL_EDGE := UiPalette.PANEL_EDGE

const RADIUS := 10
const RADIUS_SM := 6


## Cassette identity colour (OD.TAPE_COLORS_RGB).
static func tape(i: int) -> Color:
	return OD.tape_color(clampi(i, 0, OD.TAPE_COUNT - 1))


## Per-theme accent / card fill / card edge for the descent (WORLD-04 light arc: sunlit stone at the
## top, neon-dark metal at the bottom).
static func theme_accent(t: StringName) -> Color:
	match t:
		LevelTheme.MID:
			return Color("#ff9a4f")
		LevelTheme.LOWER:
			return PINK
		LevelTheme.CORE:
			return CYAN
	return YELLOW


static func theme_card(t: StringName) -> Color:
	match t:
		LevelTheme.MID:
			return Color(0.18, 0.149, 0.133, 0.88)
		LevelTheme.LOWER:
			return Color(0.071, 0.078, 0.141, 0.9)
		LevelTheme.CORE:
			return Color(0.063, 0.039, 0.133, 0.92)
	return Color(0.29, 0.204, 0.118, 0.86)


static func theme_edge(t: StringName) -> Color:
	match t:
		LevelTheme.MID:
			return Color(CYAN, 0.3)
		LevelTheme.LOWER:
			return Color(PINK, 0.45)
		LevelTheme.CORE:
			return Color(VIOLET, 0.6)
	return Color(YELLOW, 0.4)


# ───────────────────────────── fonts ─────────────────────────────

const INTER := "Inter.woff2"

static var _fonts: Dictionary[StringName, Font] = {}


## Inter Black slanted like a sticker print: titles and button labels.
static func display_font() -> Font:
	return _slanted(&"display", 900, -1)


## Inter Black upright (badges, pins, big numerals) - the HUD's display face.
static func heavy_font() -> Font:
	return UiPalette.font_display()


## Inter SemiBold - the HUD's body face.
static func ui_font() -> Font:
	return UiPalette.font_ui()


static func ui_bold_font() -> Font:
	if not _fonts.has(&"ui_bold"):
		_fonts[&"ui_bold"] = UiPalette.make_font(INTER, 760, 0.0, 0)
	return _fonts[&"ui_bold"]


## Inter Medium with a synthetic lean (Inter ships no italic axis).
static func ui_italic_font() -> Font:
	return _slanted(&"ui_italic", 520, 0)


## DejaVu Sans Mono, emboldened - keycaps, numbers, captions.
static func mono_font() -> Font:
	return UiPalette.font_mono()


## A FontVariation over the Inter file itself (a variation wrapping another variation would drop the
## weight axis), with a synthetic forward lean.
static func _slanted(key: StringName, weight: int, spacing: int) -> Font:
	if _fonts.has(key):
		return _fonts[key]
	var fv := UiPalette.make_font(INTER, weight, 0.0, spacing)
	# Synthetic italic: a forward lean reads as motion, like the prototype's italic display type.
	fv.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)
	_fonts[key] = fv
	return fv


# ───────────────────────────── styleboxes ─────────────────────────────

static func box(bg: Color, border: Color = Color.TRANSPARENT, border_w: int = 0, radius: int = RADIUS,
		shadow: Color = Color.TRANSPARENT, shadow_offset: Vector2 = Vector2.ZERO) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 6
	sb.anti_aliasing = true
	if shadow.a > 0.0:
		sb.shadow_color = shadow
		sb.shadow_size = 1
		sb.shadow_offset = shadow_offset
	return sb


static func pad(sb: StyleBox, h: float, v: float) -> StyleBox:
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v
	return sb


## The translucent menu panel (prototype .od-panel): ink at 86%, faint paper edge, hard offset shadow.
static func panel_box(pad_h: float = 26, pad_v: float = 22) -> StyleBoxFlat:
	var sb := box(PANEL, PANEL_EDGE, 2, RADIUS, Color(0, 0, 0, 0.35), Vector2(6, 6))
	pad(sb, pad_h, pad_v)
	return sb


static func empty_box() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


# ───────────────────────────── labels ─────────────────────────────

static func label(text: String, font: Font, size: int, col: Color, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	# Body text follows the text size option; display titles keep their size so headers still fit.
	var sc := UiPalette.text_scale if font != display_font() and font != heavy_font() else 1.0
	l.add_theme_font_size_override("font_size", roundi(size * sc))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Display title with the pink offset print behind it (prototype .od-panel-title).
static func title_label(text: String, size: int = 34, col: Color = YELLOW, print_col: Color = PINK) -> Label:
	var l := label(text, display_font(), size, col)
	var ls := LabelSettings.new()
	ls.font = display_font()
	ls.font_size = size
	ls.font_color = col
	ls.shadow_color = print_col
	ls.shadow_size = 0
	ls.shadow_offset = Vector2(3, 3)
	l.label_settings = ls
	return l


# ───────────────────────────── theme ─────────────────────────────

## Root theme for the UI: the shared HUD/menu theme (UiPalette.theme()) plus the menu's slider knob.
static func build_theme() -> Theme:
	var t := Theme.new()
	var shared := UiPalette.theme()
	if shared != null:
		t.merge_with(shared)
	else:
		t.default_font = ui_font()
		t.default_font_size = 16
		t.set_color("font_color", "Label", PAPER)
	t.set_icon("grabber", "HSlider", MenuArt.slider_grabber(false))
	t.set_icon("grabber_highlight", "HSlider", MenuArt.slider_grabber(true))
	t.set_icon("grabber_disabled", "HSlider", MenuArt.slider_grabber(false))
	t.set_stylebox("focus", "HSlider", empty_box())
	return t
