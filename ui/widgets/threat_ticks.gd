class_name WidgetThreatTicks
extends Control
## The 'beatSight' overlay for the master beat ruler: upcoming enemy attack beats
## (SessionView.threat_beats) as red markers on the ruler's top band, growing and pulsing as they
## come due, with a beat countdown over the next one and a bracket showing the look-ahead window.
##
## Mount it as a child of the ruler covering the strip above the ruler band (the ruler's
## RulerGeometry threat_h strip), with mouse_filter IGNORE. Coordinates are this control's own.
##
## API (see docs/WIDGETS.md):
##   set_track(track_x, track_w, horizon_beats)   the ruler's track in this control's x coordinates
##   set_threats(beats, now_beat)                  upcoming attack beats and the playhead
##   set_view(view)                                 convenience: threat_beats, beat, horizon_beats
##   set_pulse(beat_pulse)                          optional 0..1 music pulse (ticks throb on the beat)

var track_x: float = 0.0
var track_w: float = 0.0
var horizon: float = 16.0
var now_beat: float = 0.0
var beats: Array[float] = []
var look_ahead: float = Abilities.BEAT_SIGHT_LOOKAHEAD_BEATS
var beat_pulse: float = 0.0
var ticks: Array[WidgetThreat.Tick] = []
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false


func set_track(p_track_x: float, p_track_w: float, horizon_beats: float) -> void:
	track_x = p_track_x
	track_w = p_track_w
	horizon = maxf(1e-6, horizon_beats)
	_rebuild()


func set_threats(p_beats: Array[float], p_now_beat: float) -> void:
	beats = p_beats.duplicate()
	now_beat = p_now_beat
	_rebuild()


func set_view(view: SessionView) -> void:
	if view == null:
		return
	horizon = maxf(1e-6, view.horizon_beats)
	if track_w <= 0.0:
		track_w = size.x
	set_threats(view.threat_beats, view.beat)


func set_pulse(p: float) -> void:
	beat_pulse = clampf(p, 0.0, 1.0)


func _rebuild() -> void:
	ticks = WidgetThreat.ticks(beats, now_beat, horizon, track_x, track_w, look_ahead)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if not ticks.is_empty():
		queue_redraw()


func _draw() -> void:
	if ticks.is_empty():
		return
	var h := size.y
	var s := maxf(5.0, h * 0.62)
	# Look-ahead bracket: from the playhead to now + look_ahead.
	var x0 := WidgetThreat.beat_x(now_beat, horizon, track_x, track_w)
	var x1 := WidgetThreat.beat_x(minf(horizon, now_beat + look_ahead), horizon, track_x, track_w)
	draw_rect(Rect2(x0, h - 2.0, x1 - x0, 2.0), UiPalette.alpha(UiPalette.THREAT, 0.35))
	draw_line(Vector2(x1, h * 0.35), Vector2(x1, h), UiPalette.alpha(UiPalette.THREAT, 0.45), 1.0)
	for t: WidgetThreat.Tick in ticks:
		var grow := 1.0 + 0.45 * t.imminence + 0.12 * beat_pulse
		var throb := 0.0
		if t.imminence > 0.0:
			throb = 0.5 + 0.5 * sin(_time * TAU * 4.0)
		var ss := s * grow
		var col := UiPalette.THREAT.lerp(UiPalette.PAPER, throb * t.imminence * 0.6)
		col = UiPalette.alpha(col, t.alpha)
		var top := h - ss * 1.2 - 1.0
		var tri := PackedVector2Array([Vector2(t.x - ss * 0.7, top), Vector2(t.x + ss * 0.7, top), Vector2(t.x, top + ss * 1.2)])
		draw_colored_polygon(tri, col)
		var rim := tri.duplicate()
		rim.append(tri[0])
		draw_polyline(rim, UiPalette.alpha(UiPalette.INK, t.alpha), 1.5, true)
		if t.count > 1:
			WidgetDraw.text_centered(self, UiPalette.font_mono(),Vector2(t.x + ss * 0.95, top + ss * 0.3), "×%d" % t.count, int(maxf(8.0, s * 0.8)), UiPalette.PAPER, 2.0)
	# Countdown over the next attack when it is close.
	var nxt := WidgetThreat.next_tick(ticks)
	if nxt != null and nxt.countdown <= 4:
		var txt := "NOW" if nxt.countdown == 0 else str(nxt.countdown)
		var fs := int(maxf(9.0, s * 1.05))
		var top_y := h - s * 1.2 * (1.0 + 0.45 * nxt.imminence) - fs * 0.55
		WidgetDraw.text_centered(self, UiPalette.font_display(), Vector2(nxt.x, top_y), txt, fs, UiPalette.THREAT, 3.0)
