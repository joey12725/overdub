class_name FxWordAtlas
extends Node
## The readout atlas: every FxWords.WORDS entry painted once, at level load, in bold hand-inked
## anime-graphic lettering (Mob Psycho 100 / Idaten references, chapter 17 "Art style"; port of
## prototype gpu/textMesh.ts createWordAtlas).
##
## Each word is inked in three channels so the shader can colour it per readout: red = fill (tinted by
## tape / tier), green = heavy ink outline, blue = an offset drop shadow. Glyphs get a forward lean,
## per-letter wobble (rotation, baseline, size) and the loud words trailing speed slashes, so they read
## as brushed lettering rather than UI text. Only fonts already on the machine are used (SystemFont:
## Impact, then other heavy faces), never downloaded ones.
##
## The layout (rects / aspects) is computed from font metrics on construction, so it exists headless;
## the texture is painted in a one-shot SubViewport and becomes available a frame later (`ready_atlas`
## emits). Under the headless dummy renderer there is no texture and readouts are simply not drawn.

signal ready_atlas(texture: Texture2D)

const ATLAS := 1024
const CELL_W := 512
const CELL_H := 112
const COLS := 2
const FONT_PX := 84
const FONT_NAMES: PackedStringArray = ["Impact", "Haettenschweiler", "Arial Black", "Franklin Gothic Heavy", "Segoe UI Black", "Arial", "sans-serif"]

## Per word: UV rect (top-left origin) of its cell's used part.
var rects: Array[Rect2] = []
## Per word: width / height of its quad.
var aspects := PackedFloat32Array()
var texture: Texture2D = null

var _font: Font
var _layout: Array = []
var _vp: SubViewport = null


func _init() -> void:
	name = "FxWordAtlas"
	var sf := SystemFont.new()
	sf.font_names = FONT_NAMES
	sf.font_weight = 900
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	sf.multichannel_signed_distance_field = false
	_font = sf
	_compute_layout()


func font() -> Font:
	return _font


## Per-word layout: cell origin, font size, glyph advances, jitter and the used rect.
func _compute_layout() -> void:
	var rng := FxRng.new(0x0DD5)
	rects.clear()
	aspects.resize(FxWords.WORDS.size())
	_layout.clear()
	for w: int in FxWords.WORDS.size():
		var word := FxWords.WORDS[w]
		var col := w % COLS
		var row := w / COLS
		var cx := col * CELL_W
		var cy := row * CELL_H
		var px := FONT_PX
		var spacing := 2.0
		var total := _measure(word, px, spacing)
		var max_w := CELL_W - 70.0
		if total > max_w:
			px = int(floor(px * max_w / total))
			total = _measure(word, px, spacing)
		var loud := FxWords.LOUD.has(w)
		var jr := PackedFloat32Array()
		var jy := PackedFloat32Array()
		var js := PackedFloat32Array()
		for _i: int in word.length():
			jr.append(rng.sym(0.09))
			jy.append(rng.sym(3.5))
			js.append(1.0 + rng.sym(0.07))
		var slashes: Array[PackedVector2Array] = []
		var start_x := cx + (CELL_W - total) / 2.0
		if loud:
			for k: int in 3:
				var y := cy + 30.0 + k * 24.0 + rng.sym(4.0)
				var x1 := start_x - 8.0 - k * 10.0
				var ln := 46.0 + rng.next() * 30.0
				slashes.append(PackedVector2Array([Vector2(x1, y - 4.0), Vector2(x1 - ln, y + 1.0), Vector2(x1, y + 5.0)]))
		var pad := 34.0
		var used_w := minf(CELL_W, total + pad * 2.0 + (80.0 if loud else 0.0))
		var x0 := cx + (CELL_W - used_w) / 2.0 - (40.0 if loud else 0.0)
		var x1r := x0 + used_w
		var u0 := maxf(cx, x0)
		var u1 := minf(cx + CELL_W, x1r)
		rects.append(Rect2(u0 / ATLAS, float(cy) / ATLAS, (u1 - u0) / ATLAS, float(CELL_H) / ATLAS))
		aspects[w] = (u1 - u0) / CELL_H
		_layout.append({
			"word": word, "px": px, "spacing": spacing, "start_x": start_x,
			"base_y": cy + CELL_H / 2.0 + px * 0.36, "jr": jr, "jy": jy, "js": js, "slashes": slashes,
		})


func _measure(word: String, px: int, spacing: float) -> float:
	var total := 0.0
	for i: int in word.length():
		total += _font.get_string_size(word[i], HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + spacing
	return total


## Paint the atlas in a one-shot SubViewport (call once the node is in the tree). Emits ready_atlas
## when the texture exists; does nothing under the headless dummy renderer.
func paint() -> void:
	if texture != null or _vp != null or not is_inside_tree():
		return
	if DisplayServer.get_name() == "headless":
		return
	_vp = SubViewport.new()
	_vp.size = Vector2i(ATLAS, ATLAS)
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	var painter := Painter.new()
	painter.atlas = self
	painter.size = Vector2(ATLAS, ATLAS)
	_vp.add_child(painter)
	add_child(_vp)
	_grab.call_deferred()


func _grab() -> void:
	# Two post-draw signals: the first frame may still be the one that queued the viewport.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if _vp == null:
		return
	var img := _vp.get_texture().get_image()
	if img != null and not img.is_empty():
		img.convert(Image.FORMAT_RGBA8)
		img.generate_mipmaps()
		texture = ImageTexture.create_from_image(img)
	else:
		# Keep the live viewport texture if a read-back is not possible.
		texture = _vp.get_texture()
	if texture is ImageTexture:
		_vp.queue_free()
		_vp = null
	ready_atlas.emit(texture)


## Draws the words into the SubViewport.
class Painter:
	extends Control
	var atlas: FxWordAtlas

	func _draw() -> void:
		var f := atlas.font()
		for entry: Dictionary in atlas._layout:
			var slashes: Array[PackedVector2Array] = entry["slashes"]
			draw_set_transform_matrix(Transform2D.IDENTITY)
			for poly: PackedVector2Array in slashes:
				draw_colored_polygon(poly, Color(0.0, 1.0, 0.0, 1.0))
			_glyphs(f, entry, 0)
			_glyphs(f, entry, 1)
			_glyphs(f, entry, 2)
		draw_set_transform_matrix(Transform2D.IDENTITY)

	## pass 0 = shadow (blue), 1 = ink outline (green), 2 = fill (red).
	func _glyphs(f: Font, e: Dictionary, pass_index: int) -> void:
		var word: String = e["word"]
		var px: int = e["px"]
		var spacing: float = e["spacing"]
		var x: float = e["start_x"]
		var base_y: float = e["base_y"]
		var jr: PackedFloat32Array = e["jr"]
		var jy: PackedFloat32Array = e["jy"]
		var js: PackedFloat32Array = e["js"]
		for i: int in word.length():
			var ch := word[i]
			var cw := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			var ox := 7.0 if pass_index == 0 else 0.0
			var oy := 6.0 if pass_index == 0 else 0.0
			var tr := Transform2D(0.0, Vector2(x + cw / 2.0 + ox, base_y + jy[i] + oy))
			# Forward lean (italic shear) plus a per-letter wobble.
			var shear := Transform2D(Vector2(1.0, 0.0), Vector2(-0.18, 1.0), Vector2.ZERO)
			var rot := Transform2D(jr[i], Vector2.ZERO)
			var sc := Transform2D(Vector2(js[i], 0.0), Vector2(0.0, js[i]), Vector2.ZERO)
			draw_set_transform_matrix(tr * shear * rot * sc)
			var at := Vector2(-cw / 2.0, 0.0)
			match pass_index:
				0:
					draw_string_outline(f, at, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 15, Color(0.0, 0.0, 1.0, 1.0))
					draw_string(f, at, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0.0, 0.0, 1.0, 1.0))
				1:
					draw_string_outline(f, at, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 13, Color(0.0, 1.0, 0.0, 1.0))
				_:
					draw_string(f, at, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(1.0, 0.0, 0.0, 1.0))
			x += cw + spacing
