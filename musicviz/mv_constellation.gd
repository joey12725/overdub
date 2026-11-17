class_name MVConstellation
extends MVViz
## "Constellation" (chapter 15): a pitch-class helix (one turn per octave; octave-equivalent notes
## stacked vertically) slowly turning, with each pitched layer's recent notes lit as stars and
## joined in the order they were played — the voice traced on the helix. The chord's pitch classes
## stand as faint vertical rails. The drum layer pulses rings around the helix foot.

## Seconds of history (in master beats) of lit notes.
var history_beats: float = 6.0
## Helix turns once every this many master beats.
var turn_beats: float = 64.0
var tilt: float = 0.34


var _strand3: PackedVector3Array = PackedVector3Array()
var _strand_key: String = ""


static func preset() -> MVConstellation:
	var c := MVConstellation.new()
	c.size = Vector2(512, 512)
	return c


func _range() -> Vector2:
	var lo := 200.0
	var hi := -200.0
	for l: MVLayer in music.layers:
		if l.is_drums():
			continue
		lo = minf(lo, float(l.low))
		hi = maxf(hi, float(l.high))
	if lo > hi:
		return Vector2(48, 84)
	return Vector2(lo - 1.0, hi + 1.0)


func _paint() -> void:
	var beat := music.beat
	var rg := _range()
	var centre := (rg.x + rg.y) * 0.5
	var turns := (rg.y - rg.x) / 12.0
	var radius := size.x * 0.3
	var rise := size.y * 0.72 / maxf(1.0, turns) / maxf(0.2, cos(tilt))
	var yaw := TAU * beat / turn_beats
	var o := Vector2(size.x * 0.5, size.y * 0.5)
	# Strand, back half dim.
	var key := "%s|%s|%s" % [rg, radius, rise]
	if key != _strand_key:
		_strand_key = key
		_strand3 = MVHelix.strand3(rg.x, rg.y, radius, rise, centre, 44)
	var strand := MVHelix.project_all(_strand3, yaw, tilt)
	var seg := PackedVector2Array()
	var back := true
	for k: int in strand.size():
		var p := strand[k]
		var is_back := p.z < 0.0
		if seg.size() > 0 and is_back != back:
			seg.append(o + Vector2(p.x, p.y))
			_strand_seg(seg, back)
			seg = PackedVector2Array()
		back = is_back
		seg.append(o + Vector2(p.x, p.y))
	_strand_seg(seg, back)
	# Chord rails.
	var chord := music.chord_at(beat)
	for pc: int in chord.pcs:
		var lo_m := rg.x + float(posmod(pc - int(rg.x), 12))
		var top := MVHelix.screen(lo_m, yaw, tilt, radius, rise, centre)
		var m := lo_m
		while m + 12.0 <= rg.y:
			m += 12.0
		var bot := MVHelix.screen(m, yaw, tilt, radius, rise, centre)
		var ca := 0.28 if pc == chord.root else 0.14
		ca *= 0.55 if top.z < 0.0 else 1.0
		style.stroke(self, PackedVector2Array([o + Vector2(top.x, top.y), o + Vector2(bot.x, bot.y)]), style.frame, 1.2, 0.3, ca)
	# Drum rings around the foot.
	for i: int in OD.TAPE_COUNT:
		if music.layers[i].is_drums():
			_paint_drums(i, o, radius, rise, centre, rg, yaw, beat)
	# Voices.
	for i: int in shown_layers():
		if not music.layers[i].is_drums():
			_paint_voice(i, o, radius, rise, centre, yaw, beat)


func _strand_seg(seg: PackedVector2Array, back: bool) -> void:
	if seg.size() < 2:
		return
	style.stroke(self, seg, style.frame, 1.2 if back else 1.6, 0.0 if back else 0.35, 0.12 if back else 0.3)


func _paint_voice(i: int, o: Vector2, radius: float, rise: float, centre: float, yaw: float, beat: float) -> void:
	var t := music.tracks[i]
	if not t.present:
		return
	var col := t.tint(style.tape(i))
	var a := t.alpha(beat)
	var g := t.glow()
	var ws := t.width_scale()
	var notes := music.notes_in(i, maxf(0.0, beat - history_beats), beat + 1e-6)
	if notes.is_empty():
		return
	# Each pitch is projected once per redraw (chords repeat pitches).
	var proj: Dictionary = {}
	var trace := PackedVector2Array()
	var depth := PackedFloat32Array()
	trace.resize(notes.size())
	depth.resize(notes.size())
	for k: int in notes.size():
		var pitch := notes[k].pitch
		if not proj.has(pitch):
			proj[pitch] = MVHelix.screen(float(pitch), yaw, tilt, radius, rise, centre)
		var p: Vector3 = proj[pitch]
		trace[k] = o + Vector2(p.x, p.y)
		depth[k] = p.z
	# The traced path, fading into the past in a few segments.
	var segs := 3
	var per := maxi(2, ceili(float(trace.size()) / segs) + 1)
	var start := 0
	while start < trace.size() - 1:
		var end := mini(trace.size(), start + per)
		var f := float(end) / float(trace.size())
		style.stroke(self, trace.slice(start, end), col, 1.2 * ws, g * 0.4 * f, a * lerpf(0.15, 0.6, f))
		start = end - 1
	# Stars: the freshest flare with a halo, older ones are single soft sprites.
	var tex := MVStyle.halo_texture()
	for k: int in notes.size():
		var n := notes[k]
		var age := beat - n.beat
		var fresh := maxf(0.0, 1.0 - age / 0.6)
		var fade := clampf(1.0 - age / history_beats, 0.0, 1.0)
		var dim := 0.55 if depth[k] < 0.0 else 1.0
		var r := (1.6 + 1.8 * float(n.velocity) / 127.0 + 3.0 * fresh) * ws
		if fresh > 0.0:
			style.dot(self, trace[k], col.lerp(Color.WHITE, 0.4 * fresh), r, g * (0.5 + fresh), a * fade * dim)
		else:
			var h := r * 2.6
			draw_texture_rect(tex, Rect2(trace[k] - Vector2(h, h), Vector2(h, h) * 2.0), false, Color(col, a * fade * dim))


var _unit_ring: PackedVector2Array = PackedVector2Array()


func _paint_drums(i: int, o: Vector2, radius: float, rise: float, centre: float, rg: Vector2, yaw: float, beat: float) -> void:
	var t := music.tracks[i]
	if not t.present:
		return
	if _unit_ring.is_empty():
		for j: int in 41:
			var ang := TAU * float(j) / 40.0
			_unit_ring.append(Vector2(cos(ang), sin(ang)))
	var col := t.tint(style.tape(i))
	var a := t.alpha(beat)
	var foot := MVHelix.screen(rg.x - 2.0, 0.0, tilt, 0.0, rise, centre)
	var cy := o.y + foot.y + 10.0
	var notes := music.notes_in(i, maxf(0.0, beat - 1.5), beat + 1e-6)
	# The most recent hits only (a ring per hit, expanding and fading).
	for k: int in range(maxi(0, notes.size() - 6), notes.size()):
		var n := notes[k]
		var age := beat - n.beat
		var f := clampf(age / 1.5, 0.0, 1.0)
		var r := radius * (0.45 + 0.9 * f) * (1.2 - n.norm * 0.5)
		var xf := Transform2D(0.0, Vector2(r, r * sin(tilt)), 0.0, Vector2(o.x, cy))
		style.stroke(self, xf * _unit_ring, col, 1.6 * t.width_scale(), t.glow() * (1.0 - f) * 0.6, a * (1.0 - f) * float(n.velocity) / 127.0)
