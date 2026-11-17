class_name HudRuler
extends Control
## The master beat ruler (UI-01, NEW-09): one continuous MASTER timeline with beat ticks, bar lines
## and bar numbers, a moving playhead, and one lane per cassette in its colour showing where each
## tape's passes, actions and life/sync changes sit in master time. Visible in every phase,
## recording included; the cinematic shows a slim version. Port of prototype ui/hud/ruler.ts.

const SPAN_TWEEN := 0.28

var view: SessionView = null
var beat_pulse: float = 0.0
var bar_pulse: float = 0.0
var unit: float = 14.0
var slim: bool = false
var patterns: bool = false

var _time: float = 0.0
## beatSight markers (ui/widgets/threat_ticks): mounted over the threat strip above the ruler band.
var threat_ticks: WidgetThreatTicks = null
## Per lane: [from, to, t0, cur] master beats of one traversal, tweened when the speed changes (NEW-10).
var _spans: Array[PackedFloat32Array] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 4:
		_spans.append(PackedFloat32Array())
	threat_ticks = WidgetThreatTicks.new()
	threat_ticks.name = "ThreatTicks"
	threat_ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	threat_ticks.visible = false
	add_child(threat_ticks)


func set_view(v: SessionView, pulse: MusicPulse) -> void:
	view = v
	beat_pulse = pulse.beat_pulse if pulse != null else 0.0
	bar_pulse = pulse.bar_pulse if pulse != null else 0.0
	_update_spans()
	_place_threat_ticks(pulse)
	queue_redraw()


## Keep the beatSight widget over the threat strip (RulerGeometry.threat_h) and feed it the view;
## hidden when the strip is 0 (slim ruler) or there is nothing to warn about.
func _place_threat_ticks(pulse: MusicPulse) -> void:
	if threat_ticks == null or view == null:
		return
	var body := body_rect()
	var geo := HudModel.ruler_geometry(body.size.x, body.size.y, unit, slim)
	threat_ticks.visible = geo.threat_h > 0.0 and not view.threat_beats.is_empty()
	if not threat_ticks.visible:
		return
	threat_ticks.position = body.position
	threat_ticks.size = Vector2(body.size.x, geo.threat_h)
	threat_ticks.set_track(geo.track_x, geo.track_w, view.horizon_beats)
	threat_ticks.set_view(view)
	threat_ticks.set_pulse(pulse.beat_pulse if pulse != null else 0.0)


func advance(dt: float) -> void:
	_time += dt
	for i in 4:
		var t := _spans[i]
		if t.size() == 4:
			var k := clampf((_time - t[2]) / SPAN_TWEEN, 0.0, 1.0)
			var e := 1.0 - pow(1.0 - k, 3.0)
			t[3] = t[0] + (t[1] - t[0]) * e
			_spans[i] = t
	queue_redraw()


func _update_spans() -> void:
	if view == null:
		return
	for i in 4:
		var d := view.decks[i]
		var target := d.span_bars * OD.BEATS_PER_BAR if d.speed > 0.0 else 0.0
		var t := _spans[i]
		if t.size() != 4:
			_spans[i] = PackedFloat32Array([target, target, _time, target])
		elif not is_equal_approx(t[1], target):
			var from := target if t[1] == 0.0 or target == 0.0 else t[3]
			_spans[i] = PackedFloat32Array([from, target, _time, from])


## Current (possibly tweening) span of lane i in master beats.
func lane_span(i: int) -> float:
	var t := _spans[i]
	if t.size() == 4:
		return t[3]
	var d := view.decks[i]
	return d.span_bars * OD.BEATS_PER_BAR if d.speed > 0.0 else 0.0


func head_height() -> float:
	return 0.0 if slim else roundf(unit * HudModel.RULER_HEAD_U)


## Geometry of the ruler body (below the header), in body-local coordinates.
func body_rect() -> Rect2:
	var u := unit
	var pad := roundf(u * (0.25 if slim else 0.4))
	var hh := head_height()
	return Rect2(pad, hh + pad * (0.5 if hh > 0.0 else 1.0), size.x - 2.0 * pad, size.y - hh - pad * (1.5 if hh > 0.0 else 2.0))


func _draw() -> void:
	if view == null:
		return
	var u := unit
	var r := Rect2(Vector2.ZERO, size)
	HudDraw.panel(self, r, UiPalette.alpha(UiPalette.PANEL_SOLID, 0.94), UiPalette.INK, maxf(2.0, roundf(u * 0.18)), u * 0.55, roundf(u * (0.18 if slim else 0.3)))
	if not slim:
		_draw_head(u)
	var body := body_rect()
	var geo := HudModel.ruler_geometry(body.size.x, body.size.y, u, slim)
	draw_set_transform(body.position, 0.0, Vector2.ONE)
	_draw_body(geo, u)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_head(u: float) -> void:
	var hh := head_height()
	var x := roundf(u * 0.45)
	var cy := hh * 0.55 + u * 0.1
	var display := UiPalette.font_display()
	var mono := UiPalette.font_mono()
	var uif := UiPalette.font_ui()
	# Title sticker.
	var title := "MASTER BEAT RULER"
	var tfs := roundi(u * 0.7)
	var tw := HudDraw.text_width(display, title, tfs)
	var tr := Rect2(x, cy - hh * 0.36, tw + u * 0.8, hh * 0.72)
	draw_set_transform(tr.get_center(), deg_to_rad(-1.5), Vector2.ONE)
	var local := Rect2(-tr.size * 0.5, tr.size)
	HudDraw.panel(self, local, UiPalette.MOXIE_YELLOW, UiPalette.INK, maxf(2.0, u * 0.12), u * 0.2, maxf(1.0, u * 0.12))
	HudDraw.text_center(self, display, local, title, tfs, UiPalette.INK)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	x = tr.end.x + u * 0.5
	# Unit reminder (chapter 03 terminology).
	var sub := "bars here are MASTER bars"
	var sfs := roundi(u * 0.56)
	HudDraw.text(self, uif, Vector2(x, HudDraw.baseline_in(uif, sfs, cy - hh * 0.4, hh * 0.8)), sub, sfs, UiPalette.PAPER_DIM)
	x += HudDraw.text_width(uif, sub, sfs) + u * 0.8
	# Beat lamp.
	var lamp_a := 0.25 + 0.75 * clampf(beat_pulse, 0.0, 1.0)
	var lamp_c := UiPalette.MOXIE_YELLOW if bar_pulse > 0.6 else UiPalette.PAPER
	draw_circle(Vector2(x + u * 0.35, cy), u * 0.36, UiPalette.INK, true, -1.0, true)
	draw_circle(Vector2(x + u * 0.35, cy), u * 0.27, UiPalette.alpha(lamp_c, lamp_a), true, -1.0, true)
	x += u * 1.0
	# Master position and horizon.
	var pos_txt := HudModel.master_position_text(view.beat, view.horizon_beats)
	var pfs := roundi(u * 0.78)
	HudDraw.text(self, display, Vector2(x, HudDraw.baseline_in(display, pfs, cy - hh * 0.4, hh * 0.8)), pos_txt, pfs, UiPalette.PAPER, maxf(2.0, u * 0.12))
	x += HudDraw.text_width(display, pos_txt, pfs) + u * 0.4
	var hz := "of %s master bars" % HudModel.format_bars(view.horizon_beats / OD.BEATS_PER_BAR)
	HudDraw.text(self, mono, Vector2(x, HudDraw.baseline_in(mono, sfs, cy - hh * 0.4, hh * 0.8)), hz, sfs, UiPalette.PAPER_DIM)
	x += HudDraw.text_width(mono, hz, sfs) + u * 0.8
	# World rate relative to the player (recording: world ×1/s).
	var rate := roundf(view.world_rate * 100.0) / 100.0
	var rel := " vs you" if (view.phase == SessionPhase.RECORDING or view.phase == SessionPhase.COUNTIN) and rate > 0.0 else ""
	var wtxt := HudModel.format_world_rate(rate) + rel
	var wfs := roundi(u * 0.66)
	var wbg := UiPalette.MUTED
	var wfg := UiPalette.PAPER
	if rate > 0.0 and rate < 0.999:
		wbg = UiPalette.NEON_CYAN
		wfg = UiPalette.INK
	elif rate > 1.001:
		wbg = UiPalette.RUST
		wfg = UiPalette.INK
	var ww := u * 1.5 + HudDraw.text_width(display, wtxt, wfs) + u * 0.5
	var wr := Rect2(x, cy - hh * 0.34, ww, hh * 0.68)
	HudDraw.panel(self, wr, wbg, UiPalette.INK, maxf(2.0, u * 0.12), u * 0.3)
	HudIcons.draw_icon(self, HudModel.ICON_WORLD, Vector2(wr.position.x + u * 0.75, wr.get_center().y), wr.size.y * 0.7, wfg, wbg)
	HudDraw.text(self, display, Vector2(wr.position.x + u * 1.4, HudDraw.baseline_in(display, wfs, wr.position.y, wr.size.y)), wtxt, wfs, wfg)
	x = wr.end.x + u * 0.8
	# Legend, right-aligned, dropping entries that do not fit.
	_draw_legend(x, size.x - u * 0.5, cy, u)


func _draw_legend(x0: float, x1: float, cy: float, u: float) -> void:
	var font := UiPalette.font_ui()
	var fs := roundi(u * 0.55)
	var gs := u * 0.8
	var entries: Array = [
		[ActionKind.LIGHT, "light"], [ActionKind.HEAVY, "heavy"], [ActionKind.DODGE, "dodge"],
		[ActionKind.RANGED, "ranged"], [ActionKind.INTERACT, "interact"], [ActionKind.ABILITY, "ability"],
		[StateMarkKind.DEATH, "died"], [StateMarkKind.DESYNC, "desync"], [StateMarkKind.RESYNC, "resync"]]
	var widths: Array[float] = []
	var total := 0.0
	for e: Array in entries:
		var w := gs + u * 0.2 + HudDraw.text_width(font, e[1], fs) + u * 0.45
		widths.append(w)
		total += w
	# Drop from the action list's end until it fits (state marks are kept longest).
	var keep: Array[bool] = []
	for i in entries.size():
		keep.append(true)
	var order: Array[int] = [5, 4, 3, 2, 8, 7, 1, 0, 6]
	var oi := 0
	while total > x1 - x0 and oi < order.size():
		keep[order[oi]] = false
		total -= widths[order[oi]]
		oi += 1
	var x := x1 - total
	for i in entries.size():
		if not keep[i]:
			continue
		var kind: StringName = entries[i][0]
		var gx := x + gs * 0.5
		if StateMarkKind.has(kind):
			HudIcons.draw_state_glyph(self, kind, gx, cy, gs * 1.05)
		else:
			HudIcons.draw_glyph(self, kind, gx, cy, gs, UiPalette.PAPER)
		HudDraw.text(self, font, Vector2(x + gs + u * 0.2, HudDraw.baseline_in(font, fs, cy - u * 0.5, u)), entries[i][1], fs, UiPalette.PAPER_DIM)
		x += widths[i]


func _draw_body(geo: HudModel.RulerGeometry, u: float) -> void:
	var horizon := maxf(1e-6, view.horizon_beats)
	var track_x := geo.track_x
	var track_w := geo.track_w
	var band_h := geo.band_h
	var threat_h := geo.threat_h
	var lanes_bottom := geo.lane_y[3] + geo.lane_h
	var paper := UiPalette.PAPER
	var total_beats := ceili(horizon - 1e-6)
	var beat_px := track_w / horizon
	var xb := func(b: float) -> float: return track_x + (b / horizon) * track_w

	# Beat grid through the lanes (faint) so every lane reads against master beats.
	for b in total_beats + 1:
		var is_bar := b % OD.BEATS_PER_BAR == 0
		if not is_bar and beat_px < 5.0:
			continue
		var x := roundf(xb.call(minf(b, horizon))) + 0.5
		draw_line(Vector2(x, band_h), Vector2(x, lanes_bottom), UiPalette.alpha(paper, 0.16 if is_bar else 0.05), 1.0)

	# Ruler band: ticks, bar lines, bar numbers.
	var horizon_bars := horizon / OD.BEATS_PER_BAR
	var step := HudModel.bar_label_step(horizon_bars, track_w, u * 2.1)
	draw_rect(Rect2(track_x, threat_h, track_w, band_h - threat_h), UiPalette.alpha(paper, 0.06), true)
	var display := UiPalette.font_display()
	var nfs := roundi(minf(u * 0.72, (band_h - threat_h) * 0.62))
	for b in total_beats + 1:
		var is_bar := b % OD.BEATS_PER_BAR == 0
		if not is_bar and beat_px < 3.0:
			continue
		var x := roundf(xb.call(minf(b, horizon))) + 0.5
		var len := (band_h - threat_h) * (0.62 if is_bar else 0.24)
		draw_line(Vector2(x, band_h), Vector2(x, band_h - len), paper if is_bar else UiPalette.alpha(paper, 0.55), 2.0 if is_bar else 1.0)
		var bar := b / OD.BEATS_PER_BAR
		if is_bar and bar % step == 0 and bar < horizon_bars - 1e-6 and not slim:
			HudDraw.text(self, display, Vector2(x + 3.0, band_h - (band_h - threat_h) * 0.3), str(bar + 1), nfs, paper)
	draw_rect(Rect2(track_x, band_h - 2.0, track_w, 2.0), paper, true)
	draw_rect(Rect2(track_x + track_w - 3.0, threat_h, 3.0, lanes_bottom - threat_h), paper, true)

	# Threat beats (beatSight ability) are drawn by the WidgetThreatTicks child (_place_threat_ticks).

	# Gutter caption: unit reminder.
	if not slim:
		var mono := UiPalette.font_mono()
		var cfs := roundi(u * 0.5)
		HudDraw.text(self, mono, Vector2(4, threat_h + (band_h - threat_h) * 0.45), "MASTER", cfs, UiPalette.alpha(paper, 0.7))
		HudDraw.text(self, mono, Vector2(4, threat_h + (band_h - threat_h) * 0.95), "BARS →", cfs, UiPalette.alpha(paper, 0.7))

	var live := view.active if view.phase == SessionPhase.RECORDING and view.active >= 0 else -1
	for i in 4:
		_draw_lane(geo, i, i == live, xb, u)

	# Playhead.
	var px := track_x + clampf(view.beat / horizon, 0.0, 1.0) * track_w
	draw_line(Vector2(px, threat_h), Vector2(px, lanes_bottom + 2.0), UiPalette.INK, 5.0)
	draw_line(Vector2(px, threat_h), Vector2(px, lanes_bottom + 2.0), paper, 2.0)
	var hs := maxf(5.0, u * 0.42)
	var head := PackedVector2Array([Vector2(px - hs, threat_h - 1.0), Vector2(px + hs, threat_h - 1.0), Vector2(px, threat_h + hs * 1.1)])
	HudIcons.fill_poly(self, head, paper)
	var rim2 := head.duplicate()
	rim2.append(head[0])
	draw_polyline(rim2, UiPalette.INK, 1.5, true)


func _draw_lane(geo: HudModel.RulerGeometry, i: int, live: bool, xb: Callable, u: float) -> void:
	var d := view.decks[i]
	var color := UiPalette.tape(i)
	var ink := UiPalette.INK
	var paper := UiPalette.PAPER
	var y := geo.lane_y[i]
	var lh := geo.lane_h
	var cy := y + lh * 0.5
	var track_x := geo.track_x
	var track_w := geo.track_w
	var horizon := maxf(1e-6, view.horizon_beats)
	var is_active := view.active == i
	var unavailable := d.status == DeckStatus.UNAVAILABLE
	var display := UiPalette.font_display()

	# Gutter label: cassette letter chip + its speed, so every lane names its tape and rate.
	var chip_w := geo.gutter - 4.0 if slim else minf(lh * 1.3, u * 1.6)
	var chip := Rect2(2, y, chip_w, lh)
	HudDraw.panel(self, chip, Color("#3a332d") if unavailable else color, ink, 1.0 if lh < 10.0 else 1.5, minf(4.0, lh / 3.0))
	if is_active and not slim:
		draw_rect(chip.grow(1.0), paper, false, 2.0, true)
	if lh >= 8.0:
		var lfs := roundi(minf(lh * 0.82, u * 0.95))
		HudDraw.text_center(self, display, chip, OD.TAPE_NAMES[i], lfs, Color("#7a7068") if unavailable else ink)
	if not slim and lh >= 8.0:
		var sfs := roundi(minf(lh * 0.74, u * 0.82))
		var stxt := "—" if unavailable else HudModel.format_speed(d.speed)
		HudDraw.text(self, display, Vector2(chip.end.x + 5.0, HudDraw.baseline_in(display, sfs, y, lh)), stxt, sfs, Color("#7a7068") if unavailable else paper)

	# Track background.
	draw_rect(Rect2(track_x, y, track_w, lh), UiPalette.TRACK, true)
	if unavailable:
		HudDraw.hatch(self, Rect2(track_x, y, track_w, lh), Color("#5a524b"), 7.0, 1.6)
		return

	var span := lane_span(i)
	var show_layout := d.speed > 0.0 and d.end_mode >= 0 and span > 0.0 and d.status != DeckStatus.EMPTY
	if not show_layout:
		# Future, unrecorded cassette: an empty lane, never a predicted performer (REC-03).
		draw_rect(Rect2(track_x, y, track_w, lh), UiPalette.alpha(color, 0.06), true)
		draw_dashed_line(Vector2(track_x, y + 0.5), Vector2(track_x + track_w, y + 0.5), UiPalette.alpha(color, 0.5), 1.0, 5.0)
		draw_dashed_line(Vector2(track_x, y + lh - 0.5), Vector2(track_x + track_w, y + lh - 0.5), UiPalette.alpha(color, 0.5), 1.0, 5.0)
		if lh >= 9.0 and not slim:
			var mono := UiPalette.font_mono()
			var efs := roundi(minf(lh * 0.66, u * 0.62))
			var et := "NOT RECORDED — no performer on this lane yet"
			HudDraw.text(self, mono, Vector2(track_x + 8.0, HudDraw.baseline_in(mono, efs, y, lh)), et, efs, UiPalette.alpha(color, 0.8))
		return

	var layout := HudModel.lane_layout(span, d.end_mode, horizon)
	var recorded := d.status == DeckStatus.PENDING or d.status == DeckStatus.COMMITTED
	var inset := maxf(1.0, roundf(lh * 0.1))
	for seg: HudModel.LaneSegment in layout.segments:
		var x0: float = xb.call(seg.start)
		var x1: float = xb.call(seg.end)
		var w := maxf(1.0, x1 - x0)
		var first := seg.traversal == 0
		var seg_r := Rect2(x0, y + inset, w, lh - inset * 2.0)
		if recorded:
			draw_rect(seg_r, UiPalette.alpha(color, (1.0 if d.status == DeckStatus.COMMITTED else 0.78) if first else 0.36), true)
			if d.status == DeckStatus.PENDING and first:
				# Uncommitted take: striped so "not locked yet" reads without colour.
				HudDraw.hatch(self, seg_r, UiPalette.alpha(ink, 0.35), 7.0, 1.6)
			# Every recorded pass carries the pattern, not only the first (ACCESSIBILITY.md H2).
			if patterns:
				HudDraw.tape_pattern(self, seg_r, i, UiPalette.alpha(ink, 0.3 if first else 0.22), maxf(5.0, lh * 0.5))
		else:
			# Armed preview / recording: the tape's time layout as outlines; the recorded part fills live.
			draw_rect(seg_r, UiPalette.alpha(color, 0.2 if first else 0.08), true)
			var out_r := Rect2(x0 + 1.0, y + inset + 0.5, w - 2.0, lh - inset * 2.0 - 1.0)
			if not first or d.status == DeckStatus.ARMED:
				HudIcons._dashed_rect(self, out_r, UiPalette.alpha(color, 0.95 if first else 0.55), 1.5 if first else 1.0, 4.0)
			else:
				draw_rect(out_r, UiPalette.alpha(color, 0.95), false, 2.0)
		# Boundary between passes: a hard ink cut for repeat, a turn notch for reverse.
		if not first:
			draw_rect(Rect2(x0 - 1.5, y, 3.0, lh), ink, true)
			if d.end_mode == OD.EndMode.REVERSE:
				var nn := minf(6.0, lh * 0.45)
				HudIcons.fill_poly(self, PackedVector2Array([Vector2(x0 - 1.0, y), Vector2(x0 + nn, y), Vector2(x0 - 1.0, y + nn)]), paper)
		# Direction arrows on the repeat / reverse passes.
		if not first and w > lh * 1.4 and lh >= 6.0:
			var n := clampi(floori(w / (lh * 5.0)), 1, 4)
			var ac := UiPalette.alpha(ink, 0.75) if recorded else UiPalette.alpha(color, 0.7)
			var ah := lh * 0.26
			for a in n:
				var ax := x0 + w * (a + 0.5) / n
				var dd := float(seg.dir)
				draw_polyline(PackedVector2Array([Vector2(ax - dd * ah * 0.6, cy - ah), Vector2(ax + dd * ah * 0.6, cy), Vector2(ax - dd * ah * 0.6, cy + ah)]), ac, maxf(1.2, lh * 0.13), true)

	# 'stop' tapes: a hold line to the horizon - the self stays where it ended (still solid).
	if layout.has_hold():
		var hx: float = xb.call(layout.hold_from)
		var hend: float = xb.call(horizon)
		draw_dashed_line(Vector2(hx + 2.0, cy), Vector2(hend - 2.0, cy), UiPalette.alpha(color, 0.85 if recorded else 0.5), maxf(1.5, lh * 0.16), 3.0)
		var s := maxf(3.0, lh * 0.36)
		var sq := Rect2(hx + 3.0, cy - s * 0.5, s, s)
		draw_rect(sq, color if recorded else UiPalette.alpha(color, 0.6), true)
		draw_rect(sq, ink, false, 1.5)
		if lh >= 10.0 and not slim and hend - hx > u * 5.0:
			var mono := UiPalette.font_mono()
			var hfs := roundi(minf(lh * 0.6, u * 0.6))
			var tx := hx + s + 9.0
			var tw := HudDraw.text_width(mono, "HOLDS POSE", hfs)
			draw_rect(Rect2(tx - 3.0, y + 1.0, tw + 6.0, lh - 2.0), UiPalette.TRACK, true)
			HudDraw.text(self, mono, Vector2(tx, HudDraw.baseline_in(mono, hfs, y, lh)), "HOLDS POSE", hfs, UiPalette.alpha(color, 0.9))

	# Live fill: the lane being recorded fills in as the master playhead advances.
	if live:
		var fx1 := minf(float(xb.call(maxf(0.0, view.beat))), float(xb.call(minf(span, horizon))))
		if fx1 > track_x:
			draw_rect(Rect2(track_x, y + inset, fx1 - track_x, lh - inset * 2.0), color, true)
			draw_rect(Rect2(fx1 - 2.0, y, 2.0, lh), paper, true)

	# End cap: the cassette's shape (A circle, B triangle, C square, D plus) where its take ends, so
	# a lane links to the shape on the floor ring without relying on colour (ACCESSIBILITY.md H3).
	if lh >= 8.0 and span > 0.0:
		var ex: float = xb.call(minf(span, horizon))
		AccessKit.draw_shape(self, i, Vector2(minf(ex, track_x + track_w - lh * 0.5), cy), lh * 0.42, color, ink, maxf(1.5, lh * 0.12))

	# Action marks, mapped from local ticks through the tape's speed onto master beats.
	if d.marks.size() > 0 and d.speed > 0.0 and lh >= 5.0:
		var bpm := view.level.bpm if view.level != null else 120.0
		var placed := HudModel.place_marks(d.marks, d.speed, bpm, layout)
		var gsz := minf(lh * 0.78, u * 1.0)
		for p: HudModel.PlacedMark in placed:
			if live and p.traversal == 0 and p.beat > view.beat + 1e-6:
				continue # not recorded yet
			var gc := ink if recorded or (live and p.traversal == 0) else UiPalette.alpha(color, 0.9)
			if p.traversal > 0:
				gc = UiPalette.alpha(gc, 0.6)
			HudIcons.draw_glyph(self, p.kind, xb.call(p.beat), cy, gsz, gc)

	# State marks from the latest resolved run: dead / desynced stretches, then the event glyphs.
	var marks: Array[DeckStateMark] = d.state_marks.duplicate()
	for a in range(1, marks.size()):
		var cur := marks[a]
		var j := a - 1
		while j >= 0 and marks[j].beat > cur.beat:
			marks[j + 1] = marks[j]
			j -= 1
		marks[j + 1] = cur
	var desync_from := -1.0
	for m: DeckStateMark in marks:
		if m.kind == StateMarkKind.DESYNC:
			desync_from = m.beat
		elif m.kind == StateMarkKind.RESYNC and desync_from >= 0.0:
			_shade(xb.call(desync_from), xb.call(m.beat), y, lh, UiPalette.STATE_DESYNC, 0.75)
			desync_from = -1.0
		elif m.kind == StateMarkKind.DEATH:
			if desync_from >= 0.0:
				_shade(xb.call(desync_from), xb.call(m.beat), y, lh, UiPalette.STATE_DESYNC, 0.75)
				desync_from = -1.0
			var dx0: float = xb.call(m.beat)
			var dx1: float = xb.call(horizon)
			if dx1 > dx0:
				draw_rect(Rect2(dx0, y, dx1 - dx0, lh), UiPalette.alpha(UiPalette.INK, 0.55), true)
			_shade(dx0, dx1, y, lh, UiPalette.STATE_DEAD, 0.55)
	if desync_from >= 0.0:
		_shade(xb.call(desync_from), xb.call(horizon), y, lh, UiPalette.STATE_DESYNC, 0.75)
	for m: DeckStateMark in marks:
		var sx: float = xb.call(clampf(m.beat, 0.0, horizon))
		HudIcons.draw_state_glyph(self, m.kind, sx, cy, minf(lh * 0.95, u * 1.1))

	if is_active and not slim:
		draw_rect(Rect2(track_x - 0.5, y - 0.5, track_w + 1.0, lh + 1.0), paper, false, 1.5)


func _shade(x0: float, x1: float, y: float, lh: float, color: Color, alpha: float) -> void:
	if x1 <= x0:
		return
	HudDraw.hatch(self, Rect2(x0, y, x1 - x0, lh), UiPalette.alpha(color, alpha), 7.0, 1.6)
