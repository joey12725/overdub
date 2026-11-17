class_name UiPalette
extends RefCounted
## OVERDUB UI design tokens (port of prototype/src/ui/tokens.css), shared by the HUD (ui/hud) and the
## menus (ui/menus). Colours, fonts and the fluid size unit live here so every screen reads as one
## piece: inked outlines, warm paper text on near-black panels, the four cassette colours.
##
## Fonts are bundled under ui/theme/fonts (Inter, SIL OFL 1.1; DejaVu Sans Mono, Bitstream Vera
## licence) and exposed as FontVariation resources:
##   font_display()  Inter Black (wght 900), tight tracking - titles, speed readouts, sticker words
##   font_ui()       Inter SemiBold (wght 600) - body copy, badges
##   font_mono()     DejaVu Sans Mono, emboldened - keycaps, numbers, unit captions
## The shared Theme resource is res://ui/theme/od_theme.tres (built by ui/theme/build_theme.gd).

# ───────────────────────────── cassette identities ─────────────────────────────

## Cassette colours. Same values as OD.TAPE_COLORS_RGB (the Moxie copies in the world use these).
const TAPE: Array[Color] = [Color("#ff4d6d"), Color("#ffd23f"), Color("#3ec5ff"), Color("#7dff6b")]
## Darker shade of each cassette colour (shell shading, inactive fills).
const TAPE_DEEP: Array[Color] = [Color("#b3263f"), Color("#c99a12"), Color("#1a85b8"), Color("#3fae32")]
## Very dark tint of each cassette colour (lane backgrounds, deck body).
const TAPE_NIGHT: Array[Color] = [Color("#3a1820"), Color("#3a3014"), Color("#132a38"), Color("#1a3418")]

# ───────────────────────────── Moxie's palette ─────────────────────────────

const MOXIE_YELLOW := Color("#ffd23f")
const INK := Color("#14110f")
const INK_SOFT := Color("#2a2420")
const PAPER := Color("#f3ead8")
const PAPER_DIM := Color("#c9bfa9")
const OLIVE := Color("#6b6a3a")
const RUST := Color("#d9662b")
const GRAFFITI_PINK := Color("#ff4fa3")
const GRAFFITI_VIOLET := Color("#a25bff")
const NEON_CYAN := Color("#4ff3ff")

# ───────────────────────────── state colours ─────────────────────────────

## State colours never reuse a cassette colour (docs/ACCESSIBILITY.md H4; palette.json
## ui_state_colors): "good" is paper, danger is a vermilion distinct from every tape.
const STATE_DEAD := Color("#9aa3b5")
const STATE_DESYNC := Color("#c98bff")
const STATE_GOOD := Color("#f3ead8")
const STATE_WARN := Color("#ffb347")
const STATE_BAD := Color("#ff5a3c")
const REC_RED := Color("#ff2a3d")
const THREAT := Color("#ff5a3c")

# ───────────────────────────── surfaces ─────────────────────────────

const PANEL := Color(20.0 / 255.0, 17.0 / 255.0, 15.0 / 255.0, 0.86)
const PANEL_EDGE := Color(243.0 / 255.0, 234.0 / 255.0, 216.0 / 255.0, 0.16)
const PANEL_SOLID := Color("#1b1714")
const TRACK := Color("#0d0b0a")
const MUTED := Color("#2b2521")
const MUTED_TEXT := Color("#8b8178")

# ───────────────────────────── gamepad face buttons ─────────────────────────────

const FACE_A := Color("#5fe08a")
const FACE_B := Color("#ff5a5f")
const FACE_X := Color("#4fa8ff")
const FACE_Y := Color("#ffd23f")
const FACE_NEUTRAL := Color("#d8d2c4")

const THEME_PATH := "res://ui/theme/od_theme.tres"
const FONT_DIR := "res://ui/theme/fonts/"

## Text size option (SaveSettings textScale): dialogue, barks, coach marks, hints, toasts and menu
## body text multiply their font sizes by this. The HUD dock keeps its fixed text grid.
static var text_scale: float = 1.0

static var _display: Font = null
static var _ui: Font = null
static var _mono: Font = null
static var _theme: Theme = null


## Cassette colour for tape 0..3 (paper for anything else). Always the core's OD.tape_color, so the
## HUD and the world can never disagree; when core switches to an AccessKit set (default / high
## contrast, docs/ACCESSIBILITY.md), the HUD follows, with that set's deep and night shades.
static func tape(i: int) -> Color:
	if i < 0 or i >= OD.TAPE_COUNT:
		return PAPER
	return OD.tape_color(i)


static func tape_deep(i: int) -> Color:
	if i < 0 or i >= TAPE_DEEP.size():
		return PAPER_DIM
	var s := _access_set()
	return AccessKit.deep(s)[i] if s != "" else TAPE_DEEP[i]


static func tape_night(i: int) -> Color:
	if i < 0 or i >= TAPE_NIGHT.size():
		return INK_SOFT
	var s := _access_set()
	return AccessKit.night(s)[i] if s != "" else TAPE_NIGHT[i]


## Colour for text drawn ON a cassette fill (ink, or paper for a dark tape such as high-contrast C).
static func on_tape(i: int) -> Color:
	var s := _access_set()
	if s == "" or i < 0 or i >= OD.TAPE_COUNT:
		return INK
	return AccessKit.on_color(s)[i]


static var _set_key: String = "?"
static var _set_id: String = ""


## The AccessKit set whose colours the core is using now ("" = the legacy constants above).
static func _access_set() -> String:
	var key := OD.tape_color(0).to_html(false)
	if key == _set_key:
		return _set_id
	_set_key = key
	_set_id = ""
	for sid: String in [AccessKit.SET_DEFAULT, AccessKit.SET_HIGH_CONTRAST]:
		if AccessKit.colors(sid)[0].to_html(false) == key:
			_set_id = sid
	return _set_id


## `c` with alpha `a`.
static func alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


## The fluid UI unit in pixels for a canvas of `size` (port of the HUD's CSS root size:
## clamp(11px, min(0.62vw + 5px, 1.45vh + 2px), 30px)). Everything in the HUD is sized in units of
## this, so it scales from 1280x720 up to 4K.
static func unit_for(size: Vector2) -> float:
	var u := minf(size.x * 0.0062 + 5.0, size.y * 0.0145 + 2.0)
	return clampf(u, 11.0, 30.0)


## Inter Black: titles, speed readouts, sticker words.
static func font_display() -> Font:
	if _display == null:
		_display = _load_font("od_display.tres", "Inter.woff2", 900, 0.0, -1)
	return _display


## Inter SemiBold: body copy and badges.
static func font_ui() -> Font:
	if _ui == null:
		_ui = _load_font("od_ui.tres", "Inter.woff2", 600, 0.0, 0)
	return _ui


## DejaVu Sans Mono, emboldened: keycaps, numbers, unit captions.
static func font_mono() -> Font:
	if _mono == null:
		_mono = _load_font("od_mono.tres", "DejaVuSansMono.woff2", 0, 0.55, 0)
	return _mono


## The shared Theme (menus use it as their root theme). Null only if the resource is missing.
static func theme() -> Theme:
	if _theme == null and ResourceLoader.exists(THEME_PATH):
		_theme = load(THEME_PATH) as Theme
	return _theme


## Build a FontVariation over a bundled font file. Used by build_theme.gd to write the .tres files
## and as a fallback when they are missing.
static func make_font(file: String, weight: int, embolden: float, spacing_glyph: int) -> FontVariation:
	var fv := FontVariation.new()
	var base: Font = null
	var path := FONT_DIR + file
	if ResourceLoader.exists(path):
		base = load(path) as Font
	if base == null:
		base = ThemeDB.fallback_font
	fv.base_font = base
	if weight > 0:
		var ts := TextServerManager.get_primary_interface()
		fv.variation_opentype = {ts.name_to_tag("wght"): weight}
	if embolden != 0.0:
		fv.variation_embolden = embolden
	if spacing_glyph != 0:
		fv.spacing_glyph = spacing_glyph
	return fv


static func _load_font(res_name: String, file: String, weight: int, embolden: float, spacing_glyph: int) -> Font:
	var path := FONT_DIR + res_name
	if ResourceLoader.exists(path):
		var f := load(path) as Font
		if f != null:
			return f
	return make_font(file, weight, embolden, spacing_glyph)
