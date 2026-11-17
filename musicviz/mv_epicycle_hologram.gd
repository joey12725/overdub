class_name MVEpicycleHologram
extends MVViz
## "Epicycles" (chapter 15): one layer's contour rebuilt from its sixteen strongest Fourier
## harmonics as nested rotating circles, the last tip tracing the curve. The DFT is computed once per
## level per layer (cached on the MVLayer) from one period of the engine contour; the circles turn
## with the layer's own read position, so a 2x tape spins twice as fast, a reversing tape spins
## backwards, a desynced one slips ahead and snaps back, a dead one thins and greys.
##
## MODE_ROSETTE (default): the period wrapped around a circle (the sigil shape) as a closed complex
## curve — a showpiece for the time machine and the boss room.
## MODE_WAVE: the circles sit on the left and the tip's height writes the contour as a wave to the
## right (the classic Fourier-series picture) — suits wide panels.

const MODE_ROSETTE := 0
const MODE_WAVE := 1
## Points per period fed to the DFT (cost N^2 once per layer; 128 -> ~16k terms).
const DFT_POINTS := 128
## Inner radius of the rosette fed to the DFT: small, so the contour's modulation (not the base
## circle) carries the energy and the nested circles are big enough to read.
const R_IN := 0.16
## Points of the cached reconstruction table the trails and histories read.
const TABLE_POINTS := 512
const R_OUT := 1.0

var mode: int = MODE_ROSETTE
var harmonic_count: int = MVFourier.DEFAULT_COUNT
## Fraction of a period the bright trail covers.
var trail: float = 0.45
var line_width: float = 2.2


static func preset(p_layer: int, p_mode: int = MODE_ROSETTE) -> MVEpicycleHologram:
	var e := MVEpicycleHologram.new()
	e.layer = p_layer
	e.mode = p_mode
	e.size = Vector2(512, 512) if p_mode == MODE_ROSETTE else Vector2(1024, 384)
	return e


## The (cached) epicycle chain of `l` for `p_mode`: DC first, then the `count` strongest harmonics.
static func harmonics_for(l: MVLayer, p_mode: int, count: int = MVFourier.DEFAULT_COUNT) -> Array[MVFourier.Harmonic]:
	var key := "epi|%d|%d" % [p_mode, count]
	if l.cache.has(key):
		return l.cache[key]
	var pts := curve_samples(l, p_mode)
	var parts := MVFourier.split(pts)
	var hs := MVFourier.strongest(MVFourier.dft(parts[0], parts[1]), count, true)
	l.cache[key] = hs
	return hs


## DFT_POINTS samples of one period of `l` as a complex curve (unit scale).
static func curve_samples(l: MVLayer, p_mode: int) -> PackedVector2Array:
	var sig := l.period_signal()
	var n := sig.size()
	var lo := INF
	var hi := -INF
	for v: float in sig:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var mid := (lo + hi) * 0.5
	var half := maxf(0.05, (hi - lo) * 0.5)
	var pts := PackedVector2Array()
	pts.resize(DFT_POINTS)
	for j: int in DFT_POINTS:
		var x := float(j) * float(n) / float(DFT_POINTS)
		if p_mode == MODE_ROSETTE:
			pts[j] = MVRosette.point(sig, x, R_IN, R_OUT)
		else:
			# A real signal on the imaginary axis: the tip's y is the contour, centred and scaled to
			# span -1..1 (y down), so even a gentle contour fills the panel.
			pts[j] = Vector2(0.0, -(clampf(MVRosette.sample(sig, x), -0.2, 1.2) - mid) / half)
	return pts


## The reconstructed curve of `l` for `p_mode` as a closed table (cached with the harmonics).
static func curve_table(l: MVLayer, p_mode: int, count: int = MVFourier.DEFAULT_COUNT) -> PackedVector2Array:
	var key := "epitab|%d|%d" % [p_mode, count]
	if not l.cache.has(key):
		l.cache[key] = MVFourier.table(harmonics_for(l, p_mode, count), TABLE_POINTS)
	return l.cache[key]


## Level-load precomputation: the DFT and the reconstruction table (never during a frame).
func music_changed() -> void:
	if music != null and layer >= 0 and layer < music.layers.size():
		curve_table(music.layers[layer], mode, harmonic_count)


func _look() -> Dictionary:
	var t := music.tracks[layer]
	var base := style.tape(layer)
	var beat := music.beat
	return {
		"col": t.tint(base) if t.present else base.lerp(MVTrack.GREY, 0.6),
		"a": t.alpha(beat) if t.present else 0.22,
		"g": t.glow() if t.present else 0.0,
		"w": line_width * (t.width_scale() if t.present else 0.6),
	}


func _xf() -> Transform2D:
	if mode == MODE_ROSETTE:
		var sc := minf(size.x, size.y) * 0.4
		return Transform2D(0.0, Vector2(sc, sc), 0.0, size * 0.5)
	var s := size.y * 0.4
	return Transform2D(0.0, Vector2(s, s), 0.0, Vector2(size.y * 0.6, size.y * 0.5))


func _static_key() -> String:
	if layer < 0 or mode != MODE_ROSETTE:
		return ""
	return state_key(layer)


func _paint_static(ci: CanvasItem) -> void:
	if layer >= 0 and mode == MODE_ROSETTE and settled(layer):
		_paint_full_curve(ci, _look())


func _paint_full_curve(ci: CanvasItem, lk: Dictionary) -> void:
	var full := _xf() * curve_table(music.layers[layer], mode, harmonic_count)
	style.stroke(ci, full, lk["col"], lk["w"] * 0.5, lk["g"] * 0.25, lk["a"] * 0.28)


func _paint() -> void:
	if layer < 0:
		return
	var t := music.tracks[layer]
	var l := music.layers[layer]
	var hs := harmonics_for(l, mode, harmonic_count)
	var lk := _look()
	var ph := t.period_phase(music.beat) if t.present else 0.0
	if mode == MODE_ROSETTE:
		if not settled(layer):
			_paint_full_curve(self, lk)
		_paint_rosette(hs, l, ph, lk, t)
	else:
		_paint_wave(hs, l, ph, lk, t)


func _pulse(beat: float) -> float:
	# Brightens the tip on each note the layer plays.
	var notes := music.notes_in(layer, maxf(0.0, beat - 0.6), beat + 1e-6)
	var p := 0.0
	for n: MVNote in notes:
		p = maxf(p, 1.0 - (beat - n.beat) / 0.6)
	return p


func _paint_rosette(hs: Array[MVFourier.Harmonic], l: MVLayer, ph: float, lk: Dictionary, t: MVTrack) -> void:
	var xf := _xf()
	var tab := curve_table(l, mode, harmonic_count)
	var col: Color = lk["col"]
	var a: float = lk["a"]
	var g: float = lk["g"]
	var w: float = lk["w"]
	# The freshly traced part, brighter toward the tip (reversing: the trail follows the motion).
	var dir := -1.0 if t.transport == -1 else 1.0
	var segs := 5
	for s: int in segs:
		var f0 := float(s) / segs
		var f1 := float(s + 1) / segs
		var p0 := ph - dir * trail * (1.0 - f0)
		var p1 := ph - dir * trail * (1.0 - f1)
		var part := xf * MVFourier.arc(tab, p0, p1)
		style.stroke(self, part, col, w * lerpf(0.6, 1.1, f1), g * f1, a * lerpf(0.25, 1.0, f1))
	_paint_chain(hs, ph, xf, col, a, g)


func _paint_chain(hs: Array[MVFourier.Harmonic], ph: float, xf: Transform2D, col: Color, a: float, g: float) -> void:
	var chain := MVFourier.chain(hs, ph)
	var pts := xf * chain
	var sc := xf.get_scale().x
	var ring_col := col.lerp(style.frame, 0.45)
	# Circles: centre of harmonic j (j >= 1, after the DC anchor) is chain[j], radius |X_j|.
	for j: int in range(1, hs.size()):
		var r := hs[j].amp * sc
		if r < 1.0:
			continue
		var fade := lerpf(0.5, 0.16, float(j) / float(hs.size()))
		style.ring(self, pts[j], r, ring_col, 1.0, a * fade, clampi(int(r * 0.5), 12, 64))
	# Arms.
	var arms := pts.slice(1)
	style.stroke(self, arms, ring_col, 1.3, 0.3 * g, a * 0.7)
	for j: int in range(1, mini(pts.size() - 1, 9)):
		draw_circle(pts[j], 1.6, Color(ring_col, a * 0.8), true, -1.0, true)
	var pulse := _pulse(music.beat)
	style.dot(self, pts[pts.size() - 1], col.lerp(Color.WHITE, 0.3 * pulse), 3.2 + 2.6 * pulse, g * (1.0 + pulse), a)


func _paint_wave(hs: Array[MVFourier.Harmonic], l: MVLayer, ph: float, lk: Dictionary, t: MVTrack) -> void:
	var xf := _xf()
	var col: Color = lk["col"]
	var a: float = lk["a"]
	_paint_chain(hs, ph, xf, col, a, lk["g"])
	var tab := curve_table(l, mode, harmonic_count)
	var tip := xf * MVFourier.table_at(tab, ph)
	# History: the tip height over the last beats, written to the right of the circles.
	var x0 := size.y * 1.15
	var beat := music.beat
	var hist := PackedVector2Array()
	var n := 140
	var span_beats := 8.0
	hist.resize(n)
	var sy := xf.get_scale().y
	var oy := xf.origin.y
	for k: int in n:
		var bb := beat - span_beats * float(k) / float(n - 1)
		var p := t.period_phase(maxf(0.0, bb)) if t.present else 0.0
		hist[k] = Vector2(x0 + (size.x - x0 - 8.0) * float(k) / float(n - 1), oy + sy * MVFourier.table_at(tab, p).y)
	style.stroke(self, hist, col, lk["w"], lk["g"], a)
	draw_dashed_line(tip, hist[0], Color(col, 0.4 * a), 1.0, 4.0, true, true)
