class_name UiArt
extends RefCounted
## The generated interface art (assets/ui/art, assets/ui/icons, assets/portraits, assets/codex) behind
## one cached lookup, so the HUD, menus and widgets all read the same files the same way.
##
## - tex(path): an imported texture, or the PNG read from disk when the import is missing / invalid
##   (new art shows up without an editor import). Null when the file does not exist.
## - icon(path, px): the same texture pre-shrunk (Lanczos, then mipmapped) for small on-screen sizes.
##   The icon masters are 256-512 px and import without mipmaps, so drawing them at 16-64 px straight
##   from the import aliases badly; this keeps them crisp. Cached per (path, size bucket).
## - gear_icon / slot_icon / ability_icon / action_icon / tape_icon: file name = id
##   (assets/ui/icons/README.md).
## - nine(name): a StyleBoxTexture for a sliced piece with the margins from assets/ui/art/ui/slices.json.
## - chapter_card(theme) / ending_card() / key_art() / logo(): the cards and title art.
## Never instantiated.

const ART := "res://assets/ui/art/"
const ICONS := "res://assets/ui/icons/"
const SLICES := "res://assets/ui/art/ui/slices.json"

const LOGO_WORDMARK := ART + "logo/overdub_logo_wordmark_1024.png"
const LOGO_MARK := ART + "logo/overdub_mark_128.png"
const KEY_ART := ART + "keyart/title_1600x900.png"
const ENDING := ART + "cards/ending.png"
const ENDING_APPROACH := ART + "cards/ending_alt_approach.png"
const DOLL := ART + "doll/moxie_doll.png"
const DOLL_REGIONS := ART + "doll/moxie_doll_regions.json"

static var _tex: Dictionary[String, Texture2D] = {}
static var _missing: Dictionary[String, bool] = {}
static var _icons: Dictionary[String, Texture2D] = {}
static var _slices: Dictionary = {}
static var _doll: Dictionary = {}


## The texture at `path` (imported, or read from disk), or null when there is no such file.
static func tex(path: String) -> Texture2D:
	if _tex.has(path):
		return _tex[path]
	if _missing.has(path):
		return null
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = ResourceLoader.load(path, "Texture2D") as Texture2D
	if t == null and FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null and not img.is_empty():
			t = ImageTexture.create_from_image(img)
	if t == null:
		_missing[path] = true
		return null
	_tex[path] = t
	return t


static func exists(path: String) -> bool:
	return tex(path) != null


## `path` shrunk for drawing at about `px` pixels (bucketed to 24 / 48 / 96 / 192 so the cache stays
## small), mipmapped, so tiny icons stay clean. Null when the file does not exist.
static func icon(path: String, px: float = 48.0) -> Texture2D:
	var bucket := 24
	for b: int in [24, 48, 96, 192]:
		bucket = b
		if px * 1.5 <= b:
			break
	if px > 160:
		bucket = 512
	var key := "%s@%d" % [path, bucket]
	if _icons.has(key):
		return _icons[key]
	var src := tex(path)
	if src == null:
		return null
	var img := src.get_image()
	if img == null or img.is_empty():
		_icons[key] = src
		return src
	img = img.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var s := float(bucket) / maxf(img.get_width(), img.get_height())
	if s < 1.0:
		img.resize(maxi(1, roundi(img.get_width() * s)), maxi(1, roundi(img.get_height() * s)), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_icons[key] = t
	return t


static func gear_icon(item_id: String, px: float = 48.0) -> Texture2D:
	return icon(ICONS + "gear/%s.png" % item_id, px)


static func slot_icon(slot: StringName, px: float = 48.0) -> Texture2D:
	return icon(ICONS + "slots/%s.png" % slot, px)


static func ability_icon(ability_id: String, px: float = 48.0) -> Texture2D:
	return icon(ICONS + "abilities/%s.png" % ability_id, px)


## ActionKind.* (light, heavy, dodge, ranged, interact, ability).
static func action_icon(kind: StringName, px: float = 24.0) -> Texture2D:
	return icon(ICONS + "actions/%s.png" % kind, px)


## stop / repeat / reverse / alive / dead / desync / resync / locked / rec.
static func tape_icon(name: String, px: float = 24.0) -> Texture2D:
	return icon(ICONS + "tape/%s.png" % name, px)


## Draw `t` centred at `c`, fitting a `size` box, tinted by `modulate` (white glyphs take the tint;
## their ink outline stays black). Returns false when `t` is null so callers can fall back.
static func draw_centered(ci: CanvasItem, t: Texture2D, c: Vector2, size: float, modulate: Color = Color.WHITE) -> bool:
	if t == null:
		return false
	var ts := t.get_size()
	var s := size / maxf(1.0, maxf(ts.x, ts.y))
	var d := ts * s
	ci.draw_texture_rect(t, Rect2(c - d * 0.5, d), false, modulate)
	return true


# ───────────────────────────── nine-slices ─────────────────────────────

static func slices() -> Dictionary:
	if _slices.is_empty() and FileAccess.file_exists(SLICES):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(SLICES))
		if v is Dictionary:
			_slices = v
	return _slices


## Margins [left, top, right, bottom] of a sliced piece ("ui/panel.png"); zeros when unknown.
static func margins(name: String) -> PackedFloat32Array:
	var d: Dictionary = slices().get(name, {})
	return PackedFloat32Array([float(d.get("left", 0)), float(d.get("top", 0)), float(d.get("right", 0)), float(d.get("bottom", 0))])


## A StyleBoxTexture for sliced piece `name` ("panel", "button_normal", "toast", "dialogue_box"...),
## its slice margins scaled by `scale` (the art is authored 1:1 for 1600x900), with content margins
## `pad` (h, v) added inside the slice margins. Null when the file is missing.
static func nine(name: String, scale: float = 1.0, pad: Vector2 = Vector2.ZERO, modulate: Color = Color.WHITE) -> StyleBoxTexture:
	var path := ART + "ui/%s.png" % name
	var t := scaled(path, scale)
	if t == null:
		return null
	var m := margins("ui/%s.png" % name)
	var k := float(t.get_width()) / maxf(1.0, float(tex(path).get_width()))
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.texture_margin_left = roundf(m[0] * k)
	sb.texture_margin_top = roundf(m[1] * k)
	sb.texture_margin_right = roundf(m[2] * k)
	sb.texture_margin_bottom = roundf(m[3] * k)
	# Content sits inside the inked rim (about half the slice margin), plus the caller's padding.
	sb.content_margin_left = roundf(m[0] * k * 0.5) + pad.x
	sb.content_margin_right = roundf(m[2] * k * 0.5) + pad.x
	sb.content_margin_top = roundf(m[1] * k * 0.5) + pad.y
	sb.content_margin_bottom = roundf(m[3] * k * 0.5) + pad.y
	sb.modulate_color = modulate
	return sb


## `path` resampled by `scale` (Lanczos), cached; the original texture when scale is ~1.
static func scaled(path: String, scale: float) -> Texture2D:
	var src := tex(path)
	if src == null or absf(scale - 1.0) < 0.01:
		return src
	var key := "%s#%.3f" % [path, scale]
	if _icons.has(key):
		return _icons[key]
	var img := src.get_image()
	if img == null or img.is_empty():
		return src
	img = img.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(maxi(2, roundi(img.get_width() * scale)), maxi(2, roundi(img.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	var t := ImageTexture.create_from_image(img)
	_icons[key] = t
	return t


# ───────────────────────────── cards and title ─────────────────────────────

## The wordless chapter card for a LevelTheme (UPPER, MID, LOWER, CORE -> chapters 1..4).
static func chapter_card_path(theme: StringName) -> String:
	match theme:
		LevelTheme.MID:
			return ART + "cards/chapter_2_the_middle.png"
		LevelTheme.LOWER:
			return ART + "cards/chapter_3_neon_depths.png"
		LevelTheme.CORE:
			return ART + "cards/chapter_4_time_machine.png"
	return ART + "cards/chapter_1_upper_ruins.png"


static func chapter_card(theme: StringName) -> Texture2D:
	return tex(chapter_card_path(theme))


## Chapter number and title for a LevelTheme (titles drawn in engine; the cards are wordless).
static func chapter_title(theme: StringName) -> Array[String]:
	match theme:
		LevelTheme.MID:
			return ["CHAPTER 2", "THE MIDDLE"]
		LevelTheme.LOWER:
			return ["CHAPTER 3", "NEON DEPTHS"]
		LevelTheme.CORE:
			return ["CHAPTER 4", "THE TIME MACHINE"]
	return ["CHAPTER 1", "THE UPPER RUINS"]


static func ending_card() -> Texture2D:
	return tex(ENDING)


static func key_art() -> Texture2D:
	return tex(KEY_ART)


static func logo() -> Texture2D:
	return tex(LOGO_WORDMARK)


## The paper-doll region table (assets/ui/art/doll/moxie_doll_regions.json), {} when missing.
static func doll_regions() -> Dictionary:
	if _doll.is_empty() and FileAccess.file_exists(DOLL_REGIONS):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(DOLL_REGIONS))
		if v is Dictionary:
			_doll = v
	return _doll


# ───────────────────────────── cassette patterns ─────────────────────────────

static var _pattern_masks: Dictionary[int, Texture2D] = {}


## The cassette pattern tile (AccessKit.pattern_texture: greyscale coverage) as a white alpha mask,
## so a CanvasItem can tint it. Null when the tile is missing.
static func pattern_mask(tape: int) -> Texture2D:
	if _pattern_masks.has(tape):
		return _pattern_masks[tape]
	var src := AccessKit.pattern_texture(tape)
	if src == null:
		return null
	var img := src.get_image()
	if img == null or img.is_empty():
		return null
	img = img.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_L8)
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_LA8)
	for y in img.get_height():
		for x in img.get_width():
			out.set_pixel(x, y, Color(1, 1, 1, img.get_pixel(x, y).r))
	var t := ImageTexture.create_from_image(out)
	_pattern_masks[tape] = t
	return t


## Tile the shared cassette pattern (A stripes, B dots, C chevrons, D grid) over `r` in `color`,
## one tile = `tile_px`. Returns false when the pattern art is missing (callers draw their own).
static func draw_pattern(ci: CanvasItem, r: Rect2, tape: int, color: Color, tile_px: float) -> bool:
	var tex := pattern_mask(tape)
	if tex == null:
		return false
	if r.size.x <= 0.0 or r.size.y <= 0.0 or tile_px < 4.0:
		return true
	var ts := tex.get_size()
	var y := r.position.y
	var guard := 0
	while y < r.end.y and guard < 4096:
		var h := minf(tile_px, r.end.y - y)
		var x := r.position.x
		while x < r.end.x and guard < 4096:
			var w := minf(tile_px, r.end.x - x)
			ci.draw_texture_rect_region(tex, Rect2(x, y, w, h), Rect2(0, 0, ts.x * w / tile_px, ts.y * h / tile_px), color)
			x += tile_px
			guard += 1
		y += tile_px
	return true
