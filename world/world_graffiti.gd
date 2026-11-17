class_name WorldGraffiti
extends RefCounted
## Procedural spray-paint tags for graffiti decor (ART-03: graffiti is part of the visual identity;
## chapter 18: pink / purple paint is welcome, it is paint, not light). The texture is drawn into an
## Image once per (design, colour, seed) and projected onto walls or floors by a Decal, so it takes
## the surface's cel lighting.
##
## DecorDef.variant: a word (letters / digits, e.g. "MOX") is lettered as a tag in a stroke font;
## "smiley", "star", "cassette", "arrow", "crown" pick a symbol; empty picks a symbol from the seed.
## Every style has a dark outline, a highlight, overspray speckle and drips, like the R03 / R04 tags.

const SIZE := 256

const SYMBOLS: Array[String] = ["smiley", "star", "cassette", "arrow", "crown"]

## Stroke font on a 4 x 6 grid (y down); polylines separated by '|'.
const GLYPHS := {
	"A": "0,6 2,0 4,6|1,4 3,4",
	"B": "0,6 0,0 3,0 4,1 4,2 3,3 0,3|3,3 4,4 4,5 3,6 0,6",
	"C": "4,1 3,0 1,0 0,1 0,5 1,6 3,6 4,5",
	"D": "0,0 0,6 3,6 4,5 4,1 3,0 0,0",
	"E": "4,0 0,0 0,6 4,6|0,3 3,3",
	"F": "4,0 0,0 0,6|0,3 3,3",
	"G": "4,1 3,0 1,0 0,1 0,5 1,6 3,6 4,5 4,3 2,3",
	"H": "0,0 0,6|4,0 4,6|0,3 4,3",
	"I": "1,0 3,0|2,0 2,6|1,6 3,6",
	"J": "4,0 4,5 3,6 1,6 0,5",
	"K": "0,0 0,6|4,0 0,3 4,6",
	"L": "0,0 0,6 4,6",
	"M": "0,6 0,0 2,3 4,0 4,6",
	"N": "0,6 0,0 4,6 4,0",
	"O": "1,0 3,0 4,1 4,5 3,6 1,6 0,5 0,1 1,0",
	"P": "0,6 0,0 3,0 4,1 4,2 3,3 0,3",
	"Q": "1,0 3,0 4,1 4,5 3,6 1,6 0,5 0,1 1,0|2,4 4,6",
	"R": "0,6 0,0 3,0 4,1 4,2 3,3 0,3|2,3 4,6",
	"S": "4,1 3,0 1,0 0,1 0,2 1,3 3,3 4,4 4,5 3,6 1,6 0,5",
	"T": "0,0 4,0|2,0 2,6",
	"U": "0,0 0,5 1,6 3,6 4,5 4,0",
	"V": "0,0 2,6 4,0",
	"W": "0,0 1,6 2,3 3,6 4,0",
	"X": "0,0 4,6|4,0 0,6",
	"Y": "0,0 2,3 4,0|2,3 2,6",
	"Z": "0,0 4,0 0,6 4,6",
	"0": "1,0 3,0 4,1 4,5 3,6 1,6 0,5 0,1 1,0|4,1 0,5",
	"1": "1,1 2,0 2,6|1,6 3,6",
	"2": "0,1 1,0 3,0 4,1 4,2 0,6 4,6",
	"3": "0,0 4,0 2,2 3,2 4,3 4,5 3,6 1,6 0,5",
	"4": "3,6 3,0 0,4 4,4",
	"5": "4,0 0,0 0,3 3,3 4,4 4,5 3,6 0,6",
	"6": "4,0 1,0 0,1 0,5 1,6 3,6 4,5 4,4 3,3 0,3",
	"7": "0,0 4,0 1,6",
	"8": "1,0 3,0 4,1 4,2 3,3 1,3 0,4 0,5 1,6 3,6 4,5 4,4 3,3|1,3 0,2 0,1 1,0",
	"9": "4,3 1,3 0,2 0,1 1,0 3,0 4,1 4,5 3,6 0,6",
	"!": "2,0 2,4|2,5.5 2,6",
	"?": "0,1 1,0 3,0 4,1 4,2 2,3 2,4|2,5.5 2,6",
	"+": "2,1 2,5|0,3 4,3",
	"-": "0,3 4,3",
}

## Painted tags (generated art, transparent PNGs) take precedence over the procedural ones.
const PAINTED_DIR := "res://assets/textures/graffiti/"
## Symbol-only variants (which normalise to nothing) -> painted file name.
const PAINTED_ALIASES := {"<<": "rewind", ">>": "play", ">": "play", "!": "warning"}

static var _cache: Dictionary = {}
static var _painted: Dictionary = {}
static var _painted_scanned: bool = false


## Painted tag for a variant, or null: a file in PAINTED_DIR whose name matches the variant ignoring
## case, spaces and punctuation ("5 6 7 8" -> 5678.png, "Moxie was here" -> moxie_was_here.png).
## An empty variant picks a painted tag from the seed. Words and symbols without a file return null
## (the caller draws the procedural tag).
static func painted(variant: String, seed_v: int) -> Texture2D:
	var files := painted_files()
	if files.is_empty():
		return null
	var key := _norm(variant)
	var path := ""
	if key.is_empty() and PAINTED_ALIASES.has(variant.strip_edges()):
		key = PAINTED_ALIASES[variant.strip_edges()]
	if key.is_empty() and not variant.strip_edges().is_empty():
		# A symbol-only tag with no alias ("??") keeps its procedural drawing; it must not turn into
		# a random painted word.
		return null
	if key.is_empty():
		var names: Array = files.keys()
		names.sort()
		path = files[names[absi(seed_v) % names.size()]]
	elif files.has(key):
		path = files[key]
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## normalised name -> resource path of every painted tag (scanned once).
static func painted_files() -> Dictionary:
	if _painted_scanned:
		return _painted
	_painted_scanned = true
	if not DirAccess.dir_exists_absolute(PAINTED_DIR):
		return _painted
	for f: String in DirAccess.get_files_at(PAINTED_DIR):
		# Exported builds list "x.png.import" / "x.png.remap" rather than the source file.
		var name := f.trim_suffix(".import").trim_suffix(".remap")
		if name.get_extension().to_lower() != "png":
			continue
		_painted[_norm(name.get_basename())] = PAINTED_DIR + name
	return _painted


static func _norm(s: String) -> String:
	var out := ""
	for ch: String in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out


## The tag texture (cached). `paint` is the fill colour, `seed_v` varies layout / drips.
static func texture(variant: String, paint: Color, seed_v: int) -> ImageTexture:
	var key := "%s|%s|%d" % [variant, paint.to_html(), seed_v]
	if _cache.has(key):
		return _cache[key]
	var g := WorldGraffiti.new()
	var tex := ImageTexture.create_from_image(g._draw(variant, paint, seed_v))
	_cache[key] = tex
	return tex


## Clear the cache (levels hold their own references; call on level change to free memory).
static func clear_cache() -> void:
	_cache.clear()


# ───────────────────────────── drawing ─────────────────────────────

var _outline := PackedFloat32Array()
var _fill := PackedFloat32Array()
var _light := PackedFloat32Array()
var _rng: WorldRng = null


func _draw(variant: String, paint: Color, seed_v: int) -> Image:
	_rng = WorldRng.new(seed_v)
	var n := SIZE * SIZE
	_outline.resize(n)
	_fill.resize(n)
	_light.resize(n)
	var strokes := _strokes_for(variant)
	var width := 9.0 if not _is_word(variant) else 8.0
	for poly: PackedVector2Array in strokes:
		for i: int in range(poly.size() - 1):
			_segment(_outline, poly[i], poly[i + 1], width + 4.5, 1.6)
			_segment(_fill, poly[i], poly[i + 1], width, 1.2)
			# Highlight: a thin line nudged up-left, like a can's second pass.
			_segment(_light, poly[i] + Vector2(-1.5, -2.5), poly[i + 1] + Vector2(-1.5, -2.5), width * 0.22, 1.0)
	_drips(strokes, width)
	_overspray(strokes, width)
	return _compose(paint)


func _is_word(v: String) -> bool:
	if v.is_empty() or SYMBOLS.has(v.to_lower()):
		return false
	return true


func _strokes_for(variant: String) -> Array[PackedVector2Array]:
	var v := variant.strip_edges()
	if _is_word(v):
		return _word(v.to_upper())
	var sym := v.to_lower()
	if sym.is_empty():
		sym = SYMBOLS[int(_rng.next() * SYMBOLS.size()) % SYMBOLS.size()]
	match sym:
		"star":
			return _star()
		"cassette":
			return _cassette()
		"arrow":
			return _arrow()
		"crown":
			return _crown()
	return _smiley()


func _word(text: String) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var letters: Array[String] = []
	for i: int in range(text.length()):
		var ch := text.substr(i, 1)
		if GLYPHS.has(ch) or ch == " ":
			letters.append(ch)
	if letters.is_empty():
		return _smiley()
	letters = letters.slice(0, 8)
	var advance := 5.4
	var total := advance * letters.size() - 1.4
	# Fit the word into the canvas with a margin; tall letters on short words.
	var scale := minf((SIZE - 56.0) / total, (SIZE - 90.0) / 6.0)
	var x0 := (SIZE - total * scale) * 0.5
	var y0 := SIZE * 0.5 - 3.0 * scale
	var slant := 0.22
	for li: int in range(letters.size()):
		var ch := letters[li]
		if ch == " ":
			continue
		var bounce := (_rng.next() - 0.5) * 0.9
		var tilt := (_rng.next() - 0.5) * 0.25
		var ox := x0 + li * advance * scale
		for part: String in String(GLYPHS[ch]).split("|"):
			var poly := PackedVector2Array()
			for pt: String in part.split(" "):
				var xy := pt.split(",")
				var gx := float(xy[0])
				var gy := float(xy[1])
				var lx := (gx - 2.0) * cos(tilt) - (gy - 3.0) * sin(tilt) + 2.0
				var ly := (gx - 2.0) * sin(tilt) + (gy - 3.0) * cos(tilt) + 3.0 + bounce
				poly.append(Vector2(ox + (lx + (6.0 - ly) * slant) * scale, y0 + ly * scale))
			out.append(poly)
	# A swoosh under the word, and a star after it on some seeds.
	var sw := PackedVector2Array()
	for i: int in range(9):
		var t := float(i) / 8.0
		sw.append(Vector2(x0 - 6.0 + t * (total * scale + 20.0), y0 + 6.9 * scale + sin(t * PI) * 10.0 - t * 8.0))
	out.append(sw)
	if _rng.next() < 0.6:
		var c := Vector2(minf(SIZE - 26.0, x0 + total * scale + 18.0), y0 - 4.0)
		for p: PackedVector2Array in _star_at(c, 16.0):
			out.append(p)
	return out


func _circle(c: Vector2, r: float, a0: float = 0.0, a1: float = TAU, steps: int = 28) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i: int in range(steps + 1):
		var a := lerpf(a0, a1, float(i) / float(steps))
		p.append(c + Vector2(cos(a), sin(a)) * r)
	return p


func _smiley() -> Array[PackedVector2Array]:
	var c := Vector2(SIZE * 0.5, SIZE * 0.47)
	var out: Array[PackedVector2Array] = [_circle(c, 84.0)]
	for sx: float in [-1.0, 1.0]:
		var e := c + Vector2(sx * 32.0, -22.0)
		out.append(PackedVector2Array([e + Vector2(-13, -13), e + Vector2(13, 13)]))
		out.append(PackedVector2Array([e + Vector2(13, -13), e + Vector2(-13, 13)]))
	out.append(_circle(c + Vector2(0, 8), 44.0, 0.35, PI - 0.35, 14))
	return out


func _star_at(c: Vector2, r: float) -> Array[PackedVector2Array]:
	var p := PackedVector2Array()
	for i: int in range(6):
		var a := -PI * 0.5 + float(i % 5) * TAU * 2.0 / 5.0
		p.append(c + Vector2(cos(a), sin(a)) * r)
	return [p]


func _star() -> Array[PackedVector2Array]:
	var out := _star_at(Vector2(SIZE * 0.5, SIZE * 0.5), 92.0)
	out.append(_circle(Vector2(SIZE * 0.5, SIZE * 0.5), 104.0, 0.2, TAU - 0.9, 30))
	return out


func _cassette() -> Array[PackedVector2Array]:
	var x0 := 40.0
	var x1 := SIZE - 40.0
	var y0 := 62.0
	var y1 := SIZE - 62.0
	var out: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(x0 + 10, y0), Vector2(x1 - 10, y0), Vector2(x1, y0 + 10), Vector2(x1, y1 - 10), Vector2(x1 - 10, y1), Vector2(x0 + 10, y1), Vector2(x0, y1 - 10), Vector2(x0, y0 + 10), Vector2(x0 + 10, y0)]),
		_circle(Vector2(SIZE * 0.5 - 40, SIZE * 0.5 - 6), 18.0),
		_circle(Vector2(SIZE * 0.5 + 40, SIZE * 0.5 - 6), 18.0),
		PackedVector2Array([Vector2(SIZE * 0.5 - 22, SIZE * 0.5 - 6), Vector2(SIZE * 0.5 + 22, SIZE * 0.5 - 6)]),
		PackedVector2Array([Vector2(x0 + 34, y1), Vector2(x0 + 46, y1 - 24), Vector2(x1 - 46, y1 - 24), Vector2(x1 - 34, y1)]),
	]
	return out


func _arrow() -> Array[PackedVector2Array]:
	var pts := PackedVector2Array()
	for i: int in range(10):
		var t := float(i) / 9.0
		pts.append(Vector2(36.0 + t * 160.0, SIZE * 0.62 - sin(t * PI * 1.2) * 70.0))
	var tip := pts[pts.size() - 1]
	return [pts, PackedVector2Array([tip + Vector2(-34, -20), tip, tip + Vector2(-12, 34)])]


func _crown() -> Array[PackedVector2Array]:
	var y1 := SIZE * 0.7
	return [
		PackedVector2Array([Vector2(52, y1), Vector2(40, 82), Vector2(92, 134), Vector2(128, 62), Vector2(164, 134), Vector2(216, 82), Vector2(204, y1), Vector2(52, y1)]),
		_circle(Vector2(40, 70), 9.0),
		_circle(Vector2(128, 50), 9.0),
		_circle(Vector2(216, 70), 9.0),
	]


## Max-blend a soft line of half-width `r` into `buf`.
func _segment(buf: PackedFloat32Array, a: Vector2, b: Vector2, r: float, feather: float) -> void:
	var x0 := maxi(0, int(floor(minf(a.x, b.x) - r - feather)))
	var x1 := mini(SIZE - 1, int(ceil(maxf(a.x, b.x) + r + feather)))
	var y0 := maxi(0, int(floor(minf(a.y, b.y) - r - feather)))
	var y1 := mini(SIZE - 1, int(ceil(maxf(a.y, b.y) + r + feather)))
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 1e-6)
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			var cov := clampf((r - d) / feather + 0.5, 0.0, 1.0)
			if cov > 0.0:
				var i := y * SIZE + x
				if cov > buf[i]:
					buf[i] = cov


func _drips(strokes: Array[PackedVector2Array], width: float) -> void:
	var count := 3 + int(_rng.next() * 4.0)
	for k: int in range(count):
		var poly: PackedVector2Array = strokes[int(_rng.next() * strokes.size()) % strokes.size()]
		var p := poly[int(_rng.next() * poly.size()) % poly.size()]
		var drip_len := 14.0 + _rng.next() * 40.0
		var w := width * (0.28 + _rng.next() * 0.2)
		var end := p + Vector2(_rng.next() * 2.0 - 1.0, drip_len)
		_segment(_outline, p, end, w + 3.0, 1.4)
		_segment(_fill, p, end, w, 1.0)
		_segment(_outline, end, end, w * 1.7 + 3.0, 1.4)
		_segment(_fill, end, end, w * 1.7, 1.0)


func _overspray(strokes: Array[PackedVector2Array], width: float) -> void:
	var dots := 260
	for k: int in range(dots):
		var poly: PackedVector2Array = strokes[int(_rng.next() * strokes.size()) % strokes.size()]
		var i := int(_rng.next() * maxf(1.0, poly.size() - 1))
		var a := poly[mini(i, poly.size() - 1)]
		var b := poly[mini(i + 1, poly.size() - 1)]
		var p := a.lerp(b, _rng.next())
		var ang := _rng.next() * TAU
		var dist := width + 3.0 + pow(_rng.next(), 2.0) * 16.0
		var q := p + Vector2(cos(ang), sin(ang)) * dist
		var x := int(q.x)
		var y := int(q.y)
		if x >= 0 and y >= 0 and x < SIZE and y < SIZE:
			_fill[y * SIZE + x] = maxf(_fill[y * SIZE + x], 0.7)


func _compose(paint: Color) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var ink := Color(paint.r * 0.22, paint.g * 0.16, paint.b * 0.3)
	var hi := paint.lerp(Color.WHITE, 0.55)
	for y: int in range(SIZE):
		for x: int in range(SIZE):
			var i := y * SIZE + x
			var o := _outline[i]
			var f := _fill[i]
			var l := _light[i] * f
			if o <= 0.0 and f <= 0.0:
				continue
			var c := ink.lerp(paint, f).lerp(hi, l)
			# Paint is semi-opaque: the surface texture shows through a little.
			img.set_pixel(x, y, Color(c.r, c.g, c.b, maxf(o, f) * 0.92))
	img.generate_mipmaps()
	return img
