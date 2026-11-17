class_name MVShapeSigil
extends MVViz
## "Shape" (chapter 15) as a floor inscription: one period of a layer wrapped into a radial rosette,
## re-quantised under the chord in force (the engine's chord gravity made visible) and slowly
## REDRAWN, stylus-like, from twelve o'clock each time the chord changes while the previous chord's
## figure fades. Inside sits the chord star (the chord's pitch classes on a 12-gon, relative to the
## level key); around it a ring of step ticks, the gate steps notched deeper. A bright point travels
## the rosette at the layer's read position (backwards when reversing, slipping when desynced).
##
## With layer = -1 the canvas is a 2 x 2 atlas of all four sigils — the level's "signature" — and
## cell_rect(i) gives the UV rect of cassette i's cell for floor decals.

## Beats a chord change takes to redraw the rosette.
const REDRAW_BEATS := 2.5
const R_IN := 0.42
const R_OUT := 0.84
const STAR_R := 0.3

var line_width: float = 2.4


static func preset_atlas() -> MVShapeSigil:
	var s := MVShapeSigil.new()
	s.layer = -1
	s.size = Vector2(1024, 1024)
	return s


static func preset_single(p_layer: int) -> MVShapeSigil:
	var s := MVShapeSigil.new()
	s.layer = p_layer
	s.size = Vector2(512, 512)
	return s


## UV rect (0..1) of cassette `i`'s cell on an atlas canvas (layer = -1); the whole canvas otherwise.
func cell_rect(i: int) -> Rect2:
	if layer >= 0:
		return Rect2(0, 0, 1, 1)
	return Rect2(0.5 * (i % 2), 0.5 * (i / 2), 0.5, 0.5)


func _cell(i: int) -> Rect2:
	if layer >= 0:
		return Rect2(Vector2.ZERO, size)
	var r := cell_rect(i)
	return Rect2(r.position * size, r.size * size)


## Repeats so short periods still read as a rosette.
static func repeats_for(n: int) -> int:
	return maxi(1, ceili(8.0 / float(maxi(1, n))))


## One period of layer `l` re-quantised under `chord` (cached per chord).
static func chord_signal(l: MVLayer, chord: HGChord) -> PackedFloat32Array:
	var key := "sig|" + ",".join(PackedStringArray(chord.pcs.map(func(p: int) -> String: return str(p))))
	if l.cache.has(key):
		return l.cache[key]
	var sig := l.period_signal()
	var out := sig if l.is_drums() else MVRosette.snap_to_chord(sig, chord.pcs, l.low, l.high)
	l.cache[key] = out
	return out


## Level-load precomputation: every layer's period and its rosette under each chord of the
## progression.
func music_changed() -> void:
	if music == null:
		return
	for i: int in shown_layers():
		var l := music.layers[i]
		_wrapped(l, "raw", l.period_signal(), false)
		for slot: int in music.progression.size():
			var ch := music.chord_at(float(slot) * music.chord_beats)
			_wrapped(l, _chord_key(ch), chord_signal(l, ch), true)


## The unit-scale closed rosette of `sig` for layer `l` (cached by `key`).
static func _wrapped(l: MVLayer, key: String, sig: PackedFloat32Array, stepped: bool) -> PackedVector2Array:
	var k := "wrap|" + key
	if not l.cache.has(k):
		l.cache[k] = MVRosette.wrap(sig, R_IN, R_OUT, 6, repeats_for(sig.size()), stepped)
	return l.cache[k]


static func _chord_key(chord: HGChord) -> String:
	return ",".join(PackedStringArray(chord.pcs.map(func(p: int) -> String: return str(p))))


## Redraw progress (0..1) of the chord figure at the current beat.
func _redraw_progress() -> float:
	var cs := music.chord_start(music.beat)
	return clampf((music.beat - cs) / REDRAW_BEATS, 0.0, 1.0) if cs > 0.0 else 1.0


## Whether cell i is fully still apart from its read point (drawn on the static layer).
func _cell_static(i: int) -> bool:
	return settled(i) and _redraw_progress() >= 1.0


func _static_key() -> String:
	var parts := PackedStringArray()
	parts.append(str(music.chord_index(music.beat)))
	for i: int in shown_layers():
		parts.append(state_key(i) + ("s" if _cell_static(i) else "d"))
	return "|".join(parts)


func _paint_static(ci: CanvasItem) -> void:
	for i: int in shown_layers():
		if _cell_static(i):
			_paint_sigil(ci, i, _cell(i), true)


func _paint() -> void:
	for i: int in shown_layers():
		if _cell_static(i):
			_paint_read_point(i, _cell(i))
		else:
			_paint_sigil(self, i, _cell(i), false)
			_paint_read_point(i, _cell(i))


func _look(i: int) -> Dictionary:
	var t := music.tracks[i]
	var base := style.tape(i)
	var present := t.present
	return {
		"base": base,
		"col": t.tint(base) if present else base.lerp(MVTrack.GREY, 0.7),
		"a": t.alpha(music.beat) if present else 0.3,
		"g": t.glow() if present else 0.0,
		"ws": t.width_scale() if present else 0.5,
	}


func _slip(i: int) -> float:
	var t := music.tracks[i]
	var l := music.layers[i]
	var total := l.period_steps() * repeats_for(l.period_steps())
	return TAU * t.phase_offset(music.beat) / float(maxi(1, total)) if t.present else 0.0


## Everything of sigil i except the travelling read point. `still`: the settled figure (no redraw
## in progress), as recorded on the static layer.
func _paint_sigil(ci: CanvasItem, i: int, cell: Rect2, still: bool) -> void:
	var l := music.layers[i]
	var beat := music.beat
	var c := cell.get_center()
	var R := minf(cell.size.x, cell.size.y) * 0.47
	var lk := _look(i)
	var col: Color = lk["col"]
	var a: float = lk["a"]
	var g: float = lk["g"]
	var ws: float = lk["ws"]
	var n := l.period_steps()
	var reps := repeats_for(n)
	var frame := style.frame.lerp(lk["base"], 0.35)
	# Outer double ring and step ticks.
	style.ring(ci, c, R, frame, 1.4, 0.55 * maxf(a, 0.3), 96)
	style.ring(ci, c, R * 0.93, frame, 1.0, 0.3 * maxf(a, 0.3), 96)
	var total := n * reps
	var hits := PackedVector2Array()
	var rests := PackedVector2Array()
	for s: int in total:
		var ang := MVRosette.angle(float(s), n, reps)
		var dirv := Vector2(cos(ang), sin(ang))
		if l.gate_hit(s % n):
			hits.append(c + dirv * R * 0.86)
			hits.append(c + dirv * R * 0.93)
		else:
			rests.append(c + dirv * R * 0.9)
			rests.append(c + dirv * R * 0.93)
	if hits.size() > 0:
		ci.draw_multiline(hits, Color(frame, 0.55 * maxf(a, 0.3)), 2.0, true)
	if rests.size() > 0:
		ci.draw_multiline(rests, Color(frame, 0.25 * maxf(a, 0.3)), 1.0, true)
	# Rotation of the bright figure by the desync phase slip (snaps back on resync).
	var slip := 0.0 if still else _slip(i)
	var xf := Transform2D(slip, Vector2(R, R), 0.0, c)
	# Raw contour, faint and thin: the formula itself.
	var raw := xf * _wrapped(l, "raw", l.period_signal(), false)
	style.stroke(ci, raw, col, 1.0 * ws, 0.0, a * 0.3)
	# Chord figure: the previous chord fades while the new one is drawn on.
	var cs := music.chord_start(beat)
	var p := 1.0 if still else _redraw_progress()
	var now := music.chord_at(beat)
	if p < 1.0:
		var prev := music.chord_at(cs - 0.001)
		var old := xf * _wrapped(l, _chord_key(prev), chord_signal(l, prev), true)
		style.stroke(ci, old, col, line_width * ws, g * 0.5, a * (1.0 - p) * 0.9)
		_star(ci, prev, c, R, col, a * (1.0 - p), ws, g * 0.4, slip)
	var fig := xf * _wrapped(l, _chord_key(now), chord_signal(l, now), true)
	var cut := clampi(int(ceil(p * float(fig.size() - 1))) + 1, 2, fig.size())
	var drawn := fig.slice(0, cut) if cut < fig.size() else fig
	style.stroke(ci, drawn, col, line_width * ws, g, a)
	if p < 1.0:
		style.dot(ci, drawn[drawn.size() - 1], col.lerp(Color.WHITE, 0.5), 3.0, g * 1.6, a)
	_star(ci, now, c, R, col, a * p, ws, g * p, slip)
	style.dot(ci, c, col, 2.2, g * 0.6, a * 0.8)


## The bright point travelling the rosette at the layer's read position, and its spoke.
func _paint_read_point(i: int, cell: Rect2) -> void:
	var t := music.tracks[i]
	if not t.present:
		return
	var l := music.layers[i]
	var c := cell.get_center()
	var R := minf(cell.size.x, cell.size.y) * 0.47
	var lk := _look(i)
	var col: Color = lk["col"]
	var a: float = lk["a"]
	var n := l.period_steps()
	var xf := Transform2D(_slip(i), Vector2(R, R), 0.0, c)
	var x := t.period_phase(music.beat) * float(n)
	var on := xf * MVRosette.point(chord_signal(l, music.chord_at(music.beat)), x, R_IN, R_OUT, repeats_for(n), true)
	draw_line(c, on, Color(col, 0.18 * a), 1.0, true)
	style.dot(self, on, col, 3.0 * lk["ws"] + 1.0, lk["g"] * 1.2, a)


func _star(ci: CanvasItem, chord: HGChord, c: Vector2, R: float, col: Color, a: float, ws: float, g: float, slip: float) -> void:
	if a <= 0.01:
		return
	var star := MVRosette.chord_star(chord.pcs, R * STAR_R, music.root)
	if star.size() < 2:
		return
	var xf := Transform2D(slip * 0.5, c)
	style.stroke(ci, xf * star, col, 1.6 * ws, g * 0.6, a * 0.8)
	# The chord root brightest.
	var ra := MVRosette.TOP + TAU * float(posmod(chord.root - music.root, 12)) / 12.0 + slip * 0.5
	style.dot(ci, c + Vector2(cos(ra), sin(ra)) * R * STAR_R, col, 2.4 * ws + 0.6, g, a)
