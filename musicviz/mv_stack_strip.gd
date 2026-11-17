class_name MVStackStrip
extends MVViz
## "Stack" (chapter 15): every cassette layer's continuous formula contour scrolling against one
## shared playhead, each at its own tape speed (a 2x layer's contour is compressed 2x and scrolls
## twice as fast), with the notes it plays marked. The x axis is master time (past on the left,
## upcoming on the right, dimmer); a reversing layer's contour is read retrograde so its shape visibly
## runs the other way; a desynced one slips out of phase with its own notes and snaps back.
##
## Two presets: screen() for wave_screen props (lanes, backdrop, grid) and frieze() for long walls
## (overlaid contours, no backdrop).

## Master beats shown left / right of the playhead.
var past_beats: float = 3.0
var future_beats: float = 3.0
## Separate bands per layer (true) or all four overlaid (false).
var lanes: bool = true
## Beat / bar grid.
var grid: bool = true
## Line width of the contours (px).
var line_width: float = 2.4
## Vertical padding (fraction of height).
var pad: float = 0.08


static func screen_preset() -> MVStackStrip:
	var s := MVStackStrip.new()
	s.size = Vector2(512, 320)
	s.backdrop = true
	s.lanes = true
	s.grid = true
	s.past_beats = 3.0
	s.future_beats = 3.0
	s.line_width = 2.6
	return s


static func frieze_preset() -> MVStackStrip:
	var s := MVStackStrip.new()
	s.size = Vector2(2048, 192)
	s.backdrop = false
	s.lanes = false
	s.grid = false
	s.past_beats = 10.0
	s.future_beats = 6.0
	s.line_width = 3.0
	s.pad = 0.14
	return s


func _px_per_beat() -> float:
	return size.x / (past_beats + future_beats)


func _play_x() -> float:
	return size.x * past_beats / (past_beats + future_beats)


func _band(i: int, count: int) -> Rect2:
	var top := size.y * pad
	var h := size.y * (1.0 - 2.0 * pad)
	if not lanes:
		# Overlaid: each layer gets most of the height, nudged so equal values do not coincide.
		var off := (float(i) - 1.5) * h * 0.04
		return Rect2(0.0, top + off, size.x, h)
	var bh := h / float(count)
	return Rect2(0.0, top + bh * i, size.x, bh)


func _y(band: Rect2, v: float) -> float:
	return band.position.y + band.size.y * (0.08 + 0.84 * (1.0 - clampf(v, 0.0, 1.0)))


func _paint() -> void:
	var beat := music.beat
	var ppb := _px_per_beat()
	var px := _play_x()
	var show := shown_layers()
	if grid:
		_paint_grid(beat, ppb, px)
	for idx: int in show.size():
		var i := show[idx]
		_paint_layer(i, _band(idx, show.size()), beat, ppb, px)
	# The shared playhead.
	var ph := Color(style.frame, 0.55)
	style.stroke(self, PackedVector2Array([Vector2(px, size.y * 0.03), Vector2(px, size.y * 0.97)]), ph, 1.4, 0.5, 0.8)


func _paint_grid(beat: float, ppb: float, px: float) -> void:
	var b0 := ceili(beat - past_beats)
	var b1 := floori(beat + future_beats)
	for b: int in range(b0, b1 + 1):
		var x := px + (float(b) - beat) * ppb
		var bar := b % OD.BEATS_PER_BAR == 0
		var c := Color(style.frame, 0.16 if bar else 0.06)
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), c, 1.5 if bar else 1.0, true)
	if lanes:
		for idx: int in range(1, shown_layers().size()):
			var y := _band(idx, shown_layers().size()).position.y
			draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(style.frame, 0.05), 1.0, true)


func _paint_layer(i: int, band: Rect2, beat: float, ppb: float, px: float) -> void:
	var t := music.tracks[i]
	var l := music.layers[i]
	var base := style.tape(i)
	if not t.present:
		# Empty deck: a faint dashed baseline.
		var y := band.position.y + band.size.y * 0.5
		draw_dashed_line(Vector2(0.0, y), Vector2(size.x, y), Color(base, 0.16), 1.2, 6.0, true, true)
		return
	var col := t.tint(base)
	var a := t.alpha(beat)
	var w := line_width * t.width_scale()
	var g := t.glow()
	var drums := l.is_drums()
	var now_p := Vector2(px, _y(band, t.value_at(maxf(0.0, beat))))
	var top := band.position.y + band.size.y * 0.08
	var hh := band.size.y * 0.84
	var b0 := beat - px / ppb
	var b1 := beat + (size.x - px) / ppb
	var past := _line(t, l, b0, beat, b0, ppb, top, hh)
	past.append(now_p)
	var future := _line(t, l, beat, b1, b0, ppb, top, hh)
	future.insert(0, now_p)
	var contour_a := a * (0.45 if drums else 1.0)
	style.stroke(self, past, col, w * (0.7 if drums else 1.0), g * (0.6 if drums else 1.0), contour_a)
	style.stroke(self, future, col, w * 0.6, g * 0.25, contour_a * 0.38)
	_paint_notes(i, band, beat, ppb, px, col, a, g)
	# Live point at the playhead.
	style.dot(self, now_p, col, 2.6 * t.width_scale() + 1.0, g, a)


## The contour polyline of layer track `t` between master beats `from_b` and `to_b` under its
## current reading (forward, retrograde, stopped; desync = the current phase offset), in canvas
## pixels. The points are the cached contour table itself (MVLayer.step_curve), sliced and mapped
## by one affine transform per cycle, so the cost does not grow with the strip width.
func _line(t: MVTrack, l: MVLayer, from_b: float, to_b: float, b0: float, ppb: float, top: float, hh: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var from_c := maxf(0.0, from_b)
	if to_b <= from_c:
		return out
	var k := t.speed / l.local_rate
	if t.transport == 0:
		var v := t.value_at(music.beat)
		var y := top + hh * (1.0 - clampf(v, 0.0, 1.0))
		out.append(Vector2((from_c - b0) * ppb, y))
		out.append(Vector2((to_b - b0) * ppb, y))
		return out
	var off := t.phase_offset(music.beat)
	var xs := from_c * k + off
	var xe := to_b * k + off
	var c := float(l.cycle)
	l.ensure_steps((xe if t.transport == 1 else c) + 2.0)
	var curve := l.step_curve()
	if t.transport == 1:
		var xf := Transform2D(Vector2(ppb / k, 0.0), Vector2(0.0, -hh), Vector2((-off / k - b0) * ppb, top + hh))
		return xf * _span(l, curve, xs, xe)
	# Retrograde: inside each cycle the reading runs from step c-1 down to 0.
	for j: int in range(floori(xs / c), floori(xe / c) + 1):
		var base := float(j) * c
		var xa := maxf(xs, base)
		var xb := minf(xe, base + c)
		if xb <= xa:
			continue
		var a_hi := c - 1.0 - (xa - base)
		var a_lo := maxf(0.0, c - 1.0 - (xb - base))
		if a_hi <= a_lo:
			continue
		var seg := _span(l, curve, a_lo, a_hi)
		seg.reverse()
		var xf := Transform2D(Vector2(-ppb / k, 0.0), Vector2(0.0, -hh), Vector2(((base + c - 1.0 - off) / k - b0) * ppb, top + hh))
		out.append_array(xf * seg)
	return out


## Points (step, value) of the contour from step s0 to s1 (s0 < s1): exact end points around the
## table samples strictly between them.
static func _span(l: MVLayer, curve: PackedVector2Array, s0: float, s1: float) -> PackedVector2Array:
	var sub := float(MVLayer.SUB)
	var i0 := clampi(floori(s0 * sub) + 1, 0, curve.size())
	var i1 := clampi(ceili(s1 * sub), i0, curve.size())
	var out := PackedVector2Array([Vector2(s0, l.contour(s0))])
	out.append_array(curve.slice(i0, i1))
	out.append(Vector2(s1, l.contour(s1)))
	return out


## The notes the layer plays in view, in one pass and batched: played notes as glowing beads with
## their sustain (fresh ones flash), upcoming ones as faint rings; drum hits as stems.
func _paint_notes(i: int, band: Rect2, beat: float, ppb: float, px: float, col: Color, a: float, g: float) -> void:
	var t := music.tracks[i]
	var ws := t.width_scale()
	var drums := music.layers[i].is_drums()
	var notes := music.notes_in(i, maxf(0.0, beat - past_beats), beat + future_beats)
	var held := PackedVector2Array()
	var ahead := PackedVector2Array()
	var top := band.position.y + band.size.y * 0.08
	var hh := band.size.y * 0.84
	var y0 := band.position.y + band.size.y * 0.96
	var tex := MVStyle.halo_texture()
	var bead := Color(col, a * 0.95)
	var ring := Color(col, 0.45 * a)
	var flashes: Array[MVNote] = []
	for n: MVNote in notes:
		var nb := n.beat
		var x := px + (nb - beat) * ppb
		var y := top + hh * (1.0 - n.norm)
		var age := beat - nb
		if drums:
			if age >= 0.0:
				held.append(Vector2(x, y0))
				held.append(Vector2(x, y))
				if age < 0.35:
					flashes.append(n)
			else:
				ahead.append(Vector2(x, y0))
				ahead.append(Vector2(x, y))
			continue
		var x1 := x + n.duration * ppb
		if age >= 0.0:
			held.append(Vector2(x, y))
			held.append(Vector2(x1, y))
			if age < 0.5:
				flashes.append(n)
			else:
				var h := (1.8 + 1.4 * float(n.velocity) / 127.0) * ws * 2.4
				draw_texture_rect(tex, Rect2(x - h, y - h, h * 2.0, h * 2.0), false, bead)
		else:
			ahead.append(Vector2(x, y))
			ahead.append(Vector2(x1, y))
			draw_arc(Vector2(x, y), 2.2 + 1.2 * float(n.velocity) / 127.0, 0.0, TAU, 10, ring, 1.2, true)
	if drums:
		style.segments(self, held, col, 2.0 * ws, g * 0.8, a * 0.85)
		if ahead.size() > 0:
			draw_multiline(ahead, Color(col, 0.3 * a), 1.2 * ws, true)
	else:
		if held.size() > 0:
			draw_multiline(held, Color(col, 0.35 * a), 2.0 * ws, true)
		if ahead.size() > 0:
			draw_multiline(ahead, Color(col, 0.14 * a), 1.5, true)
	for n: MVNote in flashes:
		var age := beat - n.beat
		var p := Vector2(px + (n.beat - beat) * ppb, top + hh * (1.0 - n.norm))
		if drums:
			style.dot(self, p, col.lerp(Color.WHITE, 0.4), 3.2, g * 1.4, a * (1.0 - age / 0.35))
		else:
			var flash := 1.0 - age / 0.5
			style.dot(self, p, col.lerp(Color.WHITE, 0.35 * flash), (1.8 + 1.4 * float(n.velocity) / 127.0 + 2.5 * flash) * ws, g * (0.7 + flash), a)
