class_name MVRuneSequencer
extends MVViz
## Rune glyph strips whose glyphs light in their layer's gate rhythm (MUSIC-12 "runes ... make the
## relationship visible"). One row per cassette (layer = -1) or a single row. Each row is a loop of
## SLOTS glyphs = SLOTS consecutive local steps of the layer: the cursor walks it at the layer's tape
## speed (backwards when reversing), every note the layer plays lights the glyph of the step it
## was played on, and the glyph shapes are chosen by the contour value at that step — the strip
## re-carves itself every SLOTS steps as the formula moves on. Unlit glyphs stay as faint etching.
##
## glyph_sheet: optional rune sheet texture (a grid of sheet_grid glyphs, white on transparent).
## Without it, MVGlyphs draws procedural runes.

const SLOTS := 16
## Light decay (1/beats) after a hit.
const DECAY := 2.2

var glyph_sheet: Texture2D = null
var sheet_grid: Vector2i = Vector2i(8, 4)
var line_width: float = 2.2


static func preset(p_layer: int = -1) -> MVRuneSequencer:
	var r := MVRuneSequencer.new()
	r.layer = p_layer
	r.size = Vector2(1024, 256) if p_layer < 0 else Vector2(1024, 80)
	return r


## Glyph index of local step `step` of layer `l`: the contour value there (in eight bands) and the
## step's place in the loop pick the rune, so a strip changes as the formula moves on, yet a flat
## contour still carves varied runes. Deterministic.
static func glyph_for(l: MVLayer, step: int, layer_index: int) -> int:
	var s := maxi(0, step)
	var band := int(floor(clampf(l.contour(float(s)), 0.0, 0.999) * 8.0))
	return posmod(band * 11 + s * 7 + layer_index * 5, MVGlyphs.GLYPH_COUNT)


## Slot (0..SLOTS-1) of the step layer track `t` reads at master beat b.
static func slot_at(t: MVTrack, b: float) -> int:
	return posmod(floori(t.read_step(b)), SLOTS)


func _row_rect(r: int, rows: int) -> Rect2:
	var rh := size.y / float(rows)
	return Rect2(0.0, rh * r, size.x, rh)


## First local step of the page of SLOTS steps layer i is reading.
func _page(i: int) -> int:
	var t := music.tracks[i]
	if not t.present:
		return 0
	return floori(maxf(0.0, t.read_step(music.beat)) / SLOTS) * SLOTS


func _static_key() -> String:
	var parts := PackedStringArray()
	for i: int in shown_layers():
		parts.append("%s:%d" % ["1" if music.tracks[i].present else "0", _page(i)])
	return "|".join(parts)


## The faint etching of every glyph (changes only when a row turns its page).
func _paint_static(ci: CanvasItem) -> void:
	var show := shown_layers()
	for r: int in show.size():
		var i := show[r]
		var row := _row_rect(r, show.size())
		var t := music.tracks[i]
		var l := music.layers[i]
		var base := style.tape(i)
		var cw := row.size.x / SLOTS
		var gs := minf(cw * 0.72, row.size.y * 0.72)
		var page := _page(i)
		var etch := Color(style.ink, 0.3) if style.kind == MVStyle.WARM else Color(style.frame.lerp(base, 0.3), 0.16 if t.present else 0.08)
		for s: int in SLOTS:
			var cell_c := Vector2(row.position.x + cw * (s + 0.5), row.position.y + row.size.y * 0.5)
			_glyph(ci, glyph_for(l, page + s, i), cell_c - Vector2(gs, gs) * 0.5, gs, etch, 1.3, 0.0, 1.0)


func _paint() -> void:
	var show := shown_layers()
	for r: int in show.size():
		_paint_row(show[r], _row_rect(r, show.size()))


## The lit glyphs and the cursor of one row.
func _paint_row(i: int, row: Rect2) -> void:
	var t := music.tracks[i]
	if not t.present:
		return
	var l := music.layers[i]
	var beat := music.beat
	var col := t.tint(style.tape(i))
	var a := t.alpha(beat)
	var ws := t.width_scale()
	var cw := row.size.x / SLOTS
	var gs := minf(cw * 0.72, row.size.y * 0.72)
	var lights := PackedFloat32Array()
	lights.resize(SLOTS)
	var cursor := posmod(floori(t.read_step(beat)), SLOTS)
	var page := _page(i)
	for n: MVNote in music.notes_in(i, maxf(0.0, beat - 2.5), beat + 1e-6):
		var s := slot_at(t, n.beat)
		var lv := exp(-DECAY * (beat - n.beat)) * (0.55 + 0.45 * float(n.velocity) / 127.0)
		lights[s] = maxf(lights[s], lv)
	# Lit glyphs, batched by light level (four levels) into multi-segment strokes.
	for q: int in 4:
		var lv := (float(q) + 0.5) / 4.0
		var lcol := col.lerp(Color.WHITE, 0.3 * lv)
		var la := a * minf(1.0, 0.25 + lv)
		var pairs := PackedVector2Array()
		for s: int in SLOTS:
			var lit := lights[s]
			if lit <= 0.02 or clampi(int(lit * 4.0), 0, 3) != q:
				continue
			var origin := Vector2(row.position.x + cw * (s + 0.5), row.position.y + row.size.y * 0.5) - Vector2(gs, gs) * 0.5
			if glyph_sheet != null:
				_glyph(self, glyph_for(l, page + s, i), origin, gs, lcol, 1.0, 0.0, la)
				continue
			for st: PackedVector2Array in MVGlyphs.glyph(glyph_for(l, page + s, i)):
				for j: int in st.size() - 1:
					pairs.append(origin + st[j] * gs)
					pairs.append(origin + st[j + 1] * gs)
		style.segments(self, pairs, lcol, line_width * ws * (0.8 + 0.4 * lv), t.glow() * lv, la)
	# The cursor under the glyph being read.
	var cc := Vector2(row.position.x + cw * (cursor + 0.5), row.position.y + row.size.y * 0.5 + gs * 0.58)
	style.stroke(self, PackedVector2Array([Vector2(cc.x - gs * 0.35, cc.y), Vector2(cc.x + gs * 0.35, cc.y)]), col, 2.0 * ws, t.glow() * 0.6, a * 0.9)


func _glyph(ci: CanvasItem, gi: int, origin: Vector2, gs: float, col: Color, w: float, glow: float, alpha: float) -> void:
	if glyph_sheet != null:
		var cols := maxi(1, sheet_grid.x)
		var cell := Vector2(glyph_sheet.get_size()) / Vector2(sheet_grid)
		var src := Rect2(Vector2(gi % cols, (gi / cols) % maxi(1, sheet_grid.y)) * cell, cell)
		ci.draw_texture_rect_region(glyph_sheet, Rect2(origin, Vector2(gs, gs)), src, Color(col, col.a * alpha))
		return
	for stroke: PackedVector2Array in MVGlyphs.glyph(gi):
		var pts := PackedVector2Array()
		for p: Vector2 in stroke:
			pts.append(origin + p * gs)
		if glow > 0.0:
			style.stroke(ci, pts, col, w, glow, alpha)
		else:
			ci.draw_polyline(pts, Color(col, col.a * alpha), w, true)
