class_name AccessKit
extends RefCounted
## Readability / accessibility data for every layer (docs/ACCESSIBILITY.md): the measured cassette
## colour sets, the non-colour identity of each cassette (letter, shape, pattern) and the
## photosensitivity limits. Reads data/accessibility/*.json once and caches the result.
##
## Nothing in the game calls this yet; the integration steps are in docs/ACCESSIBILITY.md
## ("Integration"). Everything is static and side-effect free.
##
##   AccessKit.colors(set_id)            Array[Color] of 4, set_id = SET_DEFAULT / SET_HIGH_CONTRAST / SET_LEGACY
##   AccessKit.deep(set_id) / night(set_id) / on_color(set_id) / text_on_panel(set_id)
##   AccessKit.letter(tape) / shape_id(tape) / pattern_id(tape)
##   AccessKit.shape_polygon(tape)       unit outline (x right, y down) for _draw() code
##   AccessKit.shape_texture(tape, ring) white RGBA mask, 128 px
##   AccessKit.pattern_texture(tape)     greyscale coverage tile, 128 px, seamless
##   AccessKit.draw_shape(ci, tape, center, radius, fill, ink, ink_w, paper_w)
##   AccessKit.draw_pattern(ci, rect, tape, color, tile_px)
##   AccessKit.ring_mesh(tape, radius, width)   flat XZ ring in the cassette shape (floor rings)
##   AccessKit.flash_limits(reduced)     Dictionary from options.json "photosensitivity"
##   AccessKit.option_defaults()         { key: default } for every option in options.json

const DIR := "res://data/accessibility/"
const SET_DEFAULT := "default"
const SET_HIGH_CONTRAST := "high_contrast"
const SET_LEGACY := "legacy"
const TAPE_COUNT := 4

static var _palette: Dictionary = {}
static var _patterns: Dictionary = {}
static var _options: Dictionary = {}
static var _tex: Dictionary = {}


static func _load(file: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(DIR + file)
	if txt.is_empty():
		push_error("AccessKit: cannot read %s%s" % [DIR, file])
		return {}
	var v: Variant = JSON.parse_string(txt)
	if not (v is Dictionary):
		push_error("AccessKit: %s is not a JSON object" % file)
		return {}
	return v


static func palette() -> Dictionary:
	if _palette.is_empty():
		_palette = _load("palette.json")
	return _palette


static func patterns() -> Dictionary:
	if _patterns.is_empty():
		_patterns = _load("patterns.json")
	return _patterns


static func options() -> Dictionary:
	if _options.is_empty():
		_options = _load("options.json")
	return _options


# ───────────────────────────── colours ─────────────────────────────

static func set_ids() -> Array[String]:
	var out: Array[String] = []
	for k: String in palette().get("sets", {}):
		out.append(k)
	return out


static func _colors(set_id: String, field: String) -> Array[Color]:
	var sets: Dictionary = palette().get("sets", {})
	var s: Dictionary = sets.get(set_id, sets.get(SET_DEFAULT, {}))
	var out: Array[Color] = []
	for h: Variant in s.get(field, []):
		out.append(Color(String(h)))
	while out.size() < TAPE_COUNT:
		out.append(Color.WHITE)
	return out


## The four cassette colours of a set.
static func colors(set_id: String = SET_DEFAULT) -> Array[Color]:
	return _colors(set_id, "colors")


## Darker shade of each cassette colour (shell shading, inactive fills).
static func deep(set_id: String = SET_DEFAULT) -> Array[Color]:
	return _colors(set_id, "deep")


## Near-black tint of each cassette colour (lane and deck backgrounds).
static func night(set_id: String = SET_DEFAULT) -> Array[Color]:
	return _colors(set_id, "night")


## Colour for text / icons drawn ON a fill of the cassette colour (ink or paper).
static func on_color(set_id: String = SET_DEFAULT) -> Array[Color]:
	return _colors(set_id, "on_color")


## The cassette colour lifted until it reads as text on the HUD panel (4.5:1).
static func text_on_panel(set_id: String = SET_DEFAULT) -> Array[Color]:
	return _colors(set_id, "text_on_panel")


## Display name of each colour in a set ("Rose", "Lemon", ...), for legends and settings.
static func color_names(set_id: String = SET_DEFAULT) -> Array[String]:
	var sets: Dictionary = palette().get("sets", {})
	var s: Dictionary = sets.get(set_id, sets.get(SET_DEFAULT, {}))
	var out: Array[String] = []
	for n: Variant in s.get("names", []):
		out.append(String(n))
	return out


## Keyline widths in pixels for a viewport of `viewport_h`: Vector2(ink, paper). Paper is 0 unless
## high contrast.
static func keyline_px(viewport_h: float, high_contrast: bool) -> Vector2:
	var k: Dictionary = palette().get("keylines", {})
	var d: Dictionary = k.get("high_contrast" if high_contrast else "default", {})
	var s := maxf(viewport_h, 1.0) / 1080.0
	var ink := maxf(1.5, float(d.get("ink_px_at_1080p", 2.0)) * s)
	var paper := float(d.get("paper_px_at_1080p", 0.0)) * s
	return Vector2(ink, paper if paper <= 0.0 else maxf(1.5, paper))


# ───────────────────────────── identity ─────────────────────────────

static func _cassette(tape: int) -> Dictionary:
	var list: Array = patterns().get("cassettes", [])
	if tape < 0 or tape >= list.size():
		return {}
	return list[tape]


static func letter(tape: int) -> String:
	return String(_cassette(tape).get("letter", "?"))


## "circle" / "triangle" / "square" / "plus".
static func shape_id(tape: int) -> String:
	return String((_cassette(tape).get("shape", {}) as Dictionary).get("id", ""))


## "stripes" / "dots" / "chevrons" / "grid".
static func pattern_id(tape: int) -> String:
	return String((_cassette(tape).get("pattern", {}) as Dictionary).get("id", ""))


## Unit outline of the cassette shape, x right / y down, inside [-1, 1].
static func shape_polygon(tape: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Variant in (_cassette(tape).get("shape", {}) as Dictionary).get("polygon", []):
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


static func _texture(path: String) -> Texture2D:
	if _tex.has(path):
		return _tex[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_tex[path] = t
	return t


## White RGBA mask of the cassette shape (filled, or the ring).
static func shape_texture(tape: int, ring: bool = false) -> Texture2D:
	var s: Dictionary = _cassette(tape).get("shape", {})
	return _texture(String(s.get("ring_texture" if ring else "texture", "")))


## Seamless 128 px coverage tile of the cassette pattern (white = pattern). Sample it with
## repeat enabled and tint it; see patterns.json "use".
static func pattern_texture(tape: int) -> Texture2D:
	var p: Dictionary = _cassette(tape).get("pattern", {})
	return _texture(String(p.get("texture", "")))


# ───────────────────────────── 2D drawing ─────────────────────────────

## Draw the cassette shape centred at `center` with circumradius `radius`: ink keyline outside
## (ink_w px), optional paper line inside it (paper_w px, high contrast), then the fill.
static func draw_shape(ci: CanvasItem, tape: int, center: Vector2, radius: float, fill: Color,
		ink: Color = Color("#14110f"), ink_w: float = 2.0, paper_w: float = 0.0, paper: Color = Color("#f3ead8")) -> void:
	var poly := shape_polygon(tape)
	if poly.size() < 3:
		return
	if ink_w > 0.0:
		_fill(ci, _placed(_inset(poly, -(ink_w + paper_w) / radius), center, radius), ink)
	if paper_w > 0.0:
		_fill(ci, _placed(_inset(poly, -paper_w / radius), center, radius), paper)
	_fill(ci, _placed(poly, center, radius), fill)


## Tile the cassette pattern over `r`, tinted `color`, one tile = `tile_px` on screen. Partial tiles
## at the right / bottom edge are clipped, so nothing draws outside `r`.
static func draw_pattern(ci: CanvasItem, r: Rect2, tape: int, color: Color, tile_px: float = 48.0) -> void:
	var tex := pattern_texture(tape)
	if tex == null or r.size.x <= 0.0 or r.size.y <= 0.0 or tile_px < 4.0:
		return
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


static func _placed(poly: PackedVector2Array, center: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(poly.size())
	for i in poly.size():
		out[i] = center + poly[i] * radius
	return out


static func _fill(ci: CanvasItem, poly: PackedVector2Array, color: Color) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		return
	var pts := PackedVector2Array()
	pts.resize(idx.size())
	for i in idx.size():
		pts[i] = poly[idx[i]]
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(color)
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), range(pts.size()), pts, cols)


## Polygon moved inward by `d` (unit coordinates; negative grows it), mitred corners.
static func _inset(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	var n := poly.size()
	var out := PackedVector2Array()
	out.resize(n)
	# Signed area tells which side is inside.
	var area := 0.0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	var side := 1.0 if area > 0.0 else -1.0
	for i in n:
		var p0 := poly[(i + n - 1) % n]
		var p1 := poly[i]
		var p2 := poly[(i + 1) % n]
		var e0 := (p1 - p0).normalized()
		var e1 := (p2 - p1).normalized()
		var n0 := Vector2(-e0.y, e0.x) * side
		var n1 := Vector2(-e1.y, e1.x) * side
		var k := 1.0 + n0.dot(n1)
		var m := (n0 + n1) / maxf(k, 0.2)
		out[i] = p1 + m * d
	return out


# ───────────────────────────── 3D floor ring ─────────────────────────────

## A flat ring in the cassette shape on the XZ plane (y = 0), outer circumradius `radius` metres,
## band `width` metres, both faces. UV.x runs 0..1 around the perimeter (for dash / dot line styles
## in the shader), UV.y is 0 on the outer edge and 1 on the inner.
static func ring_mesh(tape: int, radius: float = 0.45, width: float = 0.07) -> ArrayMesh:
	var poly := shape_polygon(tape)
	var mesh := ArrayMesh.new()
	if poly.size() < 3 or radius <= 0.0:
		return mesh
	var inner := _inset(poly, width / radius)
	var n := poly.size()
	var per := PackedFloat32Array()
	per.resize(n + 1)
	var total := 0.0
	for i in n:
		per[i] = total
		total += poly[i].distance_to(poly[(i + 1) % n])
	per[n] = total
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in n + 1:
		var o := poly[i % n] * radius
		var q := inner[i % n] * radius
		var u := per[i] / maxf(total, 1e-6)
		verts.append(Vector3(o.x, 0.0, o.y))
		verts.append(Vector3(q.x, 0.0, q.y))
		uvs.append(Vector2(u, 0.0))
		uvs.append(Vector2(u, 1.0))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
	for i in n:
		var a := i * 2
		idx.append_array(PackedInt32Array([a, a + 1, a + 2, a + 2, a + 1, a + 3]))
		idx.append_array(PackedInt32Array([a, a + 2, a + 1, a + 2, a + 3, a + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ───────────────────────────── options and limits ─────────────────────────────

## { key: default } for every option in options.json (keys in SaveSettings prototype spelling).
static func option_defaults() -> Dictionary:
	var out := {}
	for o: Variant in options().get("options", []):
		out[String(o["key"])] = o["default"]
	return out


## Photosensitivity limits (options.json "photosensitivity"): the `reduced` block when the
## reduce-flashing option is on, else `default`.
static func flash_limits(reduced: bool) -> Dictionary:
	var p: Dictionary = options().get("photosensitivity", {})
	return p.get("reduced" if reduced else "default", {})


## Scale a requested full-screen flash alpha to the limit for the current mode.
static func clamp_flash_alpha(alpha: float, reduced: bool) -> float:
	return minf(alpha, float(flash_limits(reduced).get("fullscreen_flash_max_alpha", 0.25)))
