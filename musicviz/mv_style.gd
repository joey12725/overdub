class_name MVStyle
extends RefCounted
## Look of the music visualisers for one depth theme, and the glowing anti-aliased stroke they all
## draw with. WARM (upper / mid ruins: sunlit stone) lays a soft ink under-stroke so the lines read
## as inscribed light on pale stone; DARK (lower / core: rune-inscribed metal, neon) uses wide halos.
## Cassette colours are OD.TAPE_COLORS_RGB (UI-02).

const WARM := 0
const DARK := 1

var kind: int = DARK
## Ink colour of the under-stroke (WARM) / faint structure lines.
var ink: Color = Color("#1f1412")
## Neutral line colour for rings, grids and empty lanes.
var frame: Color = Color("#9fb4c8")
## Halo opacity multiplier.
var halo: float = 1.0
## Overall line width multiplier.
var width: float = 1.0
## Backdrop for screens (wave_screen glass) — drawn only by visualisers that fill their canvas.
var screen_bg: Color = Color("#07090f")


static func for_theme(theme: StringName) -> MVStyle:
	return dark() if (theme == LevelTheme.LOWER or theme == LevelTheme.CORE) else warm()


static func warm() -> MVStyle:
	var s := MVStyle.new()
	s.kind = WARM
	s.ink = Color("#2a1712")
	s.frame = Color("#ffe2b0")
	s.halo = 0.75
	s.width = 1.15
	s.screen_bg = Color("#120c0a")
	return s


static func dark() -> MVStyle:
	var s := MVStyle.new()
	s.kind = DARK
	s.ink = Color("#05040a")
	s.frame = Color("#8fa6ff")
	s.halo = 1.0
	s.width = 1.0
	s.screen_bg = Color("#05060c")
	return s


## Cassette colour, slightly deepened on the warm theme so it holds up against pale stone.
func tape(i: int) -> Color:
	var c := OD.tape_color(clampi(i, 0, OD.TAPE_COUNT - 1))
	if kind == WARM:
		c = Color.from_hsv(c.h, minf(1.0, c.s * 1.08), c.v * 0.97)
	return c


## A glowing anti-aliased polyline: (WARM) ink under-stroke, a wide soft halo (not anti-aliased:
## at its low opacity the edge does not show, and it halves the geometry), an anti-aliased inner
## halo, the core, and a hot centre on wide bright lines. `glow` scales the halo (0 = a plain
## line); `alpha` fades everything.
func stroke(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float, glow: float = 1.0, alpha: float = 1.0) -> void:
	if pts.size() < 2 or alpha <= 0.003:
		return
	var ww := w * width
	if kind == WARM:
		ci.draw_polyline(pts, Color(ink, 0.42 * alpha), ww * 2.4 + 1.5, true)
	if glow > 0.01:
		ci.draw_polyline(pts, Color(col, 0.075 * halo * glow * alpha), ww * 6.5, false)
		ci.draw_polyline(pts, Color(col, 0.2 * halo * glow * alpha), ww * 3.0, true)
	ci.draw_polyline(pts, Color(col, alpha), ww, true)
	if glow > 0.3 and ww > 1.6:
		ci.draw_polyline(pts, Color(col.lerp(Color.WHITE, 0.6), 0.85 * alpha * minf(1.0, glow)), ww * 0.4, false)


## A glowing dot: (WARM) ink disc, one soft halo sprite, the core, and a hot centre on big dots.
func dot(ci: CanvasItem, at: Vector2, col: Color, r: float, glow: float = 1.0, alpha: float = 1.0) -> void:
	if alpha <= 0.003:
		return
	var rr := r * width
	if kind == WARM:
		ci.draw_circle(at, rr + 1.6, Color(ink, 0.45 * alpha), true, -1.0, true)
	if glow > 0.01:
		var h := rr * 3.4
		ci.draw_texture_rect(halo_texture(), Rect2(at - Vector2(h, h), Vector2(h, h) * 2.0), false, Color(col, minf(1.0, 0.6 * halo * glow * alpha)))
	ci.draw_circle(at, rr, Color(col, alpha), true, -1.0, true)
	if glow > 0.3 and rr > 2.6:
		ci.draw_circle(at, rr * 0.45, Color(col.lerp(Color.WHITE, 0.7), alpha), true, -1.0, false)


## Many glowing segments in one go: `pairs` holds segment end points (a0, b0, a1, b1, ...), drawn
## with draw_multiline — three or four draw calls whatever the count. Same look as stroke().
func segments(ci: CanvasItem, pairs: PackedVector2Array, col: Color, w: float, glow: float = 1.0, alpha: float = 1.0) -> void:
	if pairs.size() < 2 or alpha <= 0.003:
		return
	var ww := w * width
	if kind == WARM:
		ci.draw_multiline(pairs, Color(ink, 0.42 * alpha), ww * 2.4 + 1.5, true)
	if glow > 0.01:
		ci.draw_multiline(pairs, Color(col, 0.075 * halo * glow * alpha), ww * 6.5, false)
		ci.draw_multiline(pairs, Color(col, 0.2 * halo * glow * alpha), ww * 3.0, true)
	ci.draw_multiline(pairs, Color(col, alpha), ww, true)


static var _halo_tex: ImageTexture = null


## White soft round sprite (alpha = Gaussian falloff to the rim), shared by every dot halo.
static func halo_texture() -> Texture2D:
	if _halo_tex == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y: int in n:
			for x: int in n:
				var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
				var a := exp(-d * d * 4.0) * (1.0 - smoothstep(0.82, 1.0, d))
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(a, 0.0, 1.0)))
		_halo_tex = ImageTexture.create_from_image(img)
	return _halo_tex


## A thin structural ring (no halo).
func ring(ci: CanvasItem, at: Vector2, r: float, col: Color, w: float, alpha: float = 1.0, points: int = 72) -> void:
	if alpha <= 0.003 or r <= 0.5:
		return
	if kind == WARM:
		ci.draw_arc(at, r, 0.0, TAU, points, Color(ink, 0.35 * alpha), w * width * 2.2 + 1.0, true)
	ci.draw_arc(at, r, 0.0, TAU, points, Color(col, alpha), w * width, true)
