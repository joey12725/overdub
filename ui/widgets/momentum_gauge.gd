class_name WidgetMomentumGauge
extends Control
## The momentum gauge (MOM-01 "a legible common cause"; MOM-03, MOM-04, HEALTH-02, Scenario K): a
## small two-band arc beside the live self, following her on screen.
##
##   inner band  her next LIGHT swing      outer band  her next HEAVY swing
##   solid fill  momentum if she pressed now (tape speed x motion into the swing)
##   pale fill   how far it would go if she ran fully INTO the swing (the run-in headroom)
##   "1x" notch  where the same heavy would sit on a 1x tape (shows "faster tape hits harder")
##   ticks       the faced breakable/core's threshold, the faced enemy's damage points (the last is
##               the KO), the brute's shove line, the boss's stagger line - green once met
##   chevrons    under the speed sticker: lit when moving into the swing, red when moving away
##   flash       after a CLANG / WHIFF of the live tape: why ("needs 5 · had 3")
##
## Momentum comes from WidgetMath.gauge_state, which calls the sim's own Tuning functions.
##
## API (see docs/WIDGETS.md):
##   setup(level, loadout)                       per level
##   set_aim(angle)                              live aim in sim radians (NAN = body facing)
##   update_gauge(snap, view, projector)         per frame while playing
##   on_events(events)                           this frame's SimEvents (failure flashes)
##   set_state(state, anchor)                    draw a prepared WidgetMath.GaugeState at a screen point
## Full-rect, mouse-transparent overlay.

## Arc span in screen radians (+y is down): from down-right (62 deg) up to up-right (-62 deg).
const ARC_START := 1.0821041362364843
const ARC_END := -1.0821041362364843
const FAIL_TIME := 1.9
const OK_TIME := 0.9

var level: LevelDef = null
var loadout: ResolvedLoadout = null
var state: WidgetMath.GaugeState = WidgetMath.GaugeState.new()
var anchor: Vector2 = Vector2.ZERO
var aim: float = NAN
var _target_screen: Vector2 = Vector2(NAN, NAN)
var _fail: WidgetMath.FailInfo = null
var _fail_t: float = 0.0
var _ok_t: float = 0.0
var _ok_text: String = ""
var _time: float = 0.0
var _shown: float = 0.0
## Smoothed fills so the arc does not flicker frame to frame.
var _light_disp: float = 0.0
var _heavy_disp: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(p_level: LevelDef, p_loadout: ResolvedLoadout) -> void:
	level = p_level
	loadout = p_loadout
	state = WidgetMath.GaugeState.new()
	queue_redraw()


func set_aim(angle: float) -> void:
	aim = angle


## Compute and show the gauge for the live self in `snap`. Hidden unless the session is recording
## and the live self is alive (a recording ghost still swings, so it keeps the gauge too).
func update_gauge(snap: FrameSnapshot, view: SessionView, projector: WidgetProjector) -> void:
	var live: ActorSnap = null
	if snap != null:
		for a: ActorSnap in snap.actors:
			if a.live:
				live = a
				break
	var recording := view != null and view.phase == SessionPhase.RECORDING
	if live == null or not recording or live.life == OD.LifeState.GHOST or projector == null or not projector.valid():
		state = WidgetMath.GaugeState.new()
		queue_redraw()
		return
	var speed := 1.0
	if view != null and live.tape >= 0 and live.tape < view.decks.size() and view.decks[live.tape].speed > 0.0:
		speed = view.decks[live.tape].speed
	var speeds: Array[float] = []
	if view != null and not view.speeds.is_empty():
		speeds = view.speeds
	elif level != null:
		speeds = level.speeds
	var st := WidgetMath.gauge_state(live, speed, aim, loadout, level, snap, speeds)
	var ts := Vector2(NAN, NAN)
	if st.target.kind != WidgetMath.KIND_NONE:
		ts = projector.to_screen(st.target.pos, 0.8)
	set_state(st, projector.to_screen(Vector2(live.x, live.y), 0.95), ts)


## Show a prepared state at `screen_anchor` (her body on screen). `target_screen` is where the faced
## target is on screen (NAN = unknown): the arc goes on the side away from it so it never covers it.
func set_state(st: WidgetMath.GaugeState, screen_anchor: Vector2, target_screen: Vector2 = Vector2(NAN, NAN)) -> void:
	state = st
	anchor = screen_anchor
	_target_screen = target_screen
	queue_redraw()


## Is the arc drawn on her left? Away from the target, and never off the screen's edge.
func flipped() -> bool:
	var u := WidgetDraw.unit(self)
	var w := size.x
	var flip := false
	if is_finite(_target_screen.x):
		flip = _target_screen.x > anchor.x
	if anchor.x > w - u * 10.0:
		flip = true
	elif anchor.x < u * 10.0:
		flip = false
	return flip


func on_events(events: Array[SimEvent]) -> void:
	if not state.visible:
		return
	for ev: SimEvent in events:
		if ev.tape != state.tape:
			continue
		if ev.type == SimEventType.CLANG or ev.type == SimEventType.WHIFF:
			var f := WidgetMath.failure_info(ev, state.tape, loadout)
			if f.valid:
				_fail = f
				_fail_t = FAIL_TIME
				_ok_t = 0.0
		elif ev.type == SimEventType.BREAK:
			_ok_text = "BROKE IT · %s" % WidgetMath.fmt(ev.power)
			_ok_t = OK_TIME
		elif ev.type == SimEventType.CORE:
			_ok_text = "CHARGED"
			_ok_t = OK_TIME
	queue_redraw()


## Show a failure explanation directly (tests and screenshots).
func show_failure(f: WidgetMath.FailInfo) -> void:
	_fail = f
	_fail_t = FAIL_TIME
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_fail_t = maxf(0.0, _fail_t - delta)
	_ok_t = maxf(0.0, _ok_t - delta)
	_shown = move_toward(_shown, 1.0 if state.visible else 0.0, delta * 6.0)
	var k := 1.0 - exp(-delta * 18.0)
	_light_disp = lerpf(_light_disp, state.light.momentum, k)
	_heavy_disp = lerpf(_heavy_disp, state.heavy.momentum, k)
	if _shown > 0.0 or state.visible:
		queue_redraw()


## Snap the smoothed fills to the current state (screenshots, tests).
func settle() -> void:
	_shown = 1.0 if state.visible else 0.0
	_light_disp = state.light.momentum
	_heavy_disp = state.heavy.momentum
	queue_redraw()


func _draw() -> void:
	if _shown <= 0.01 or not state.visible:
		return
	var u := WidgetDraw.unit(self)
	var a := _shown
	var flip := flipped()
	var c := anchor + Vector2(-u * 0.4 if flip else u * 0.4, 0)
	var r_l0 := u * 3.2
	var r_l1 := u * 3.95
	var r_h0 := u * 4.2
	var r_h1 := u * 5.3
	var segs := state.segments
	var tape_col := UiPalette.tape(state.tape)
	var deep := UiPalette.tape_deep(state.tape)
	var ink := UiPalette.alpha(UiPalette.INK, a)
	var ang := func(m: float) -> float:
		var f := WidgetMath.gauge_fraction(m, segs)
		var a0 := ARC_START
		var a1 := ARC_END
		if flip:
			a0 = PI - ARC_START
			a1 = PI - ARC_END
		return lerpf(a0, a1, f)
	var a_start: float = ang.call(0.0)
	var a_end: float = ang.call(float(segs) * WidgetMath.PIP_MOMENTUM)

	# Backing: a soft dark halo, a paper rim (reads on dark floors) and ink between the bands.
	var pad_a := 0.05
	var s0 := a_start + (pad_a if not flip else -pad_a)
	var s1 := a_end - (pad_a if not flip else -pad_a)
	WidgetDraw.arc_band(self, c, r_l0 - u * 0.45, r_h1 + u * 0.45, s0, s1, UiPalette.alpha(UiPalette.INK, a * 0.35))
	WidgetDraw.arc_band(self, c, r_l0 - 3.5, r_h1 + 3.5, a_start, a_end, UiPalette.alpha(UiPalette.PAPER, a * 0.75))
	WidgetDraw.arc_band(self, c, r_l0 - 2.0, r_h1 + 2.0, a_start, a_end, UiPalette.alpha(UiPalette.INK, a))
	WidgetDraw.arc_band(self, c, r_l0, r_l1, a_start, a_end, UiPalette.alpha(UiPalette.TRACK, a))
	WidgetDraw.arc_band(self, c, r_h0, r_h1, a_start, a_end, UiPalette.alpha(UiPalette.TRACK, a))
	# Run-in headroom (pale) then the current momentum (solid).
	WidgetDraw.arc_band(self, c, r_l0, r_l1, a_start, ang.call(state.light.full), UiPalette.alpha(tape_col, a * 0.22))
	WidgetDraw.arc_band(self, c, r_h0, r_h1, a_start, ang.call(state.heavy.full), UiPalette.alpha(tape_col, a * 0.22))
	WidgetDraw.arc_band(self, c, r_l0, r_l1, a_start, ang.call(_light_disp), UiPalette.alpha(tape_col.lerp(UiPalette.PAPER, 0.25), a))
	WidgetDraw.arc_band(self, c, r_h0, r_h1, a_start, ang.call(_heavy_disp), UiPalette.alpha(tape_col, a))
	WidgetDraw.arc_band(self, c, r_h1 - (r_h1 - r_h0) * 0.3, r_h1, a_start, ang.call(_heavy_disp), UiPalette.alpha(deep, a))
	# Segment separators (one per PIP_MOMENTUM, matching the badges' pips).
	for k: int in range(1, segs):
		var aa: float = ang.call(float(k) * WidgetMath.PIP_MOMENTUM)
		var d := Vector2.from_angle(aa)
		draw_line(c + d * r_l0, c + d * r_l1, ink, maxf(1.5, u * 0.1))
		draw_line(c + d * r_h0, c + d * r_h1, ink, maxf(1.5, u * 0.1))
	# 1x notch on the heavy band when the tape is not 1x.
	if not is_equal_approx(state.speed, 1.0):
		var a1x: float = ang.call(state.heavy.at_1x)
		var d1 := Vector2.from_angle(a1x)
		draw_line(c + d1 * (r_l0 - u * 0.35), c + d1 * r_h1, UiPalette.alpha(UiPalette.INK, a), maxf(3.0, u * 0.22))
		draw_line(c + d1 * (r_l0 - u * 0.3), c + d1 * r_h1, UiPalette.alpha(UiPalette.PAPER_DIM, a), maxf(1.5, u * 0.1))
		var mono := UiPalette.font_mono()
		WidgetDraw.text_centered(self, mono, c + d1 * (r_l0 - u * 0.95), "1×", int(u * 0.6), UiPalette.alpha(UiPalette.PAPER, a), u * 0.22)

	# Threshold ticks.
	var main := WidgetMath.main_threshold(state.target, loadout)
	for t: WidgetMath.Tick in state.ticks:
		_draw_tick(c, t, ang.call(t.momentum), r_l0, r_h1, u, a, main)

	# Band letters at the start.
	var mono2 := UiPalette.font_mono()
	var ls := int(u * 0.55)
	var ds := Vector2.from_angle(a_start)
	var tang := Vector2(-ds.y, ds.x) * (1.0 if not flip else -1.0)
	WidgetDraw.text_centered(self, mono2, c + ds * (r_l0 + r_l1) * 0.5 + tang * u * 0.55, "L", ls, UiPalette.alpha(UiPalette.PAPER, a), u * 0.16)
	WidgetDraw.text_centered(self, mono2, c + ds * (r_h0 + r_h1) * 0.5 + tang * u * 0.55, "H", ls, UiPalette.alpha(UiPalette.PAPER, a), u * 0.16)

	# Speed sticker + approach chevrons below the arc's start.
	var sp := c + ds * (r_h1 + u * 0.2) + Vector2(0, u * 1.1)
	_draw_speed(sp, u, a, tape_col, flip)
	# Target caption above the arc's end.
	var de := Vector2.from_angle(a_end)
	_draw_target_caption(c + de * (r_h1 + u * 0.1) + Vector2(0, -u * 0.9), u, a, flip, main)
	# Failure / success flash.
	if _fail != null and _fail_t > 0.0:
		_draw_flash(sp + Vector2(0, u * 1.9), u, minf(1.0, _fail_t / 0.4) * a, flip)
	elif _ok_t > 0.0:
		_draw_flash(sp + Vector2(0, u * 1.9), u, minf(1.0, _ok_t / 0.3) * a, flip, true)


func _draw_tick(c: Vector2, t: WidgetMath.Tick, aa: float, r0: float, r1: float, u: float, a: float, main: float) -> void:
	var d := Vector2.from_angle(aa)
	var met_heavy := WidgetMath.meets(state.heavy.momentum, t.momentum)
	var met_light := WidgetMath.meets(state.light.momentum, t.momentum)
	var col := UiPalette.PAPER
	match t.kind:
		WidgetMath.TICK_THRESHOLD, WidgetMath.TICK_KILL, WidgetMath.TICK_STAGGER:
			col = UiPalette.STATE_GOOD if (met_heavy or met_light) else UiPalette.THREAT
		WidgetMath.TICK_SHOVE:
			col = UiPalette.STATE_WARN
		_:
			col = UiPalette.alpha(UiPalette.PAPER, 0.85)
	var major := t.kind != WidgetMath.TICK_DAMAGE
	var w := maxf(3.0, u * (0.26 if major else 0.14))
	draw_line(c + d * (r0 - u * 0.25), c + d * (r1 + u * 0.3), UiPalette.alpha(UiPalette.INK, a), w + 3.0)
	draw_line(c + d * (r0 - u * 0.2), c + d * (r1 + u * 0.25), UiPalette.alpha(col, a), w)
	if not major:
		return
	var tip := c + d * (r1 + u * 0.95)
	if t.kind == WidgetMath.TICK_KILL:
		WidgetDraw.icon(self, WidgetDraw.ICON_SKULL, tip + Vector2(1, 1), u * 0.95, UiPalette.alpha(UiPalette.INK, a))
		WidgetDraw.icon(self, WidgetDraw.ICON_SKULL, tip, u * 0.95, UiPalette.alpha(col, a))
	else:
		var txt := t.label
		if t.kind == WidgetMath.TICK_THRESHOLD:
			txt = WidgetMath.fmt(t.momentum)
		WidgetDraw.text_centered(self, UiPalette.font_display(), tip, txt, int(u * (0.8 if t.kind == WidgetMath.TICK_THRESHOLD else 0.5)), UiPalette.alpha(col, a), u * 0.22)


func _draw_speed(p: Vector2, u: float, a: float, tape_col: Color, flip: bool) -> void:
	var display := UiPalette.font_display()
	var txt := WidgetMath.speed_label(state.speed)
	var fs := int(u * 0.95)
	var tw := WidgetDraw.text_width(display, txt, fs)
	var box_w := tw + u * 4.0
	var box := Rect2(Vector2(p.x - (box_w if flip else 0.0), p.y - u * 0.7), Vector2(box_w, u * 1.4))
	WidgetDraw.panel(self, box, UiPalette.alpha(UiPalette.INK, a * 0.9), UiPalette.alpha(tape_col, a), maxf(1.5, u * 0.12), u * 0.3)
	WidgetDraw.text(self, display, Vector2(box.position.x + u * 0.4, box.get_center().y + fs * 0.36), txt, fs, UiPalette.alpha(tape_col, a))
	# Approach chevrons: three, lit by how much of her motion goes into the swing.
	var ap := state.approach
	var cx := box.position.x + u * 0.7 + tw + u * 0.3
	for k: int in 3:
		var lit := clampf(ap * 3.0 - k, 0.0, 1.0)
		var away := ap < -0.05
		var colr := UiPalette.STATE_BAD if away else UiPalette.PAPER.lerp(tape_col, lit)
		var al := (0.9 if away and k == 0 else 0.2) if away else (0.25 + 0.75 * lit)
		var dir := PI if away else 0.0
		WidgetDraw.chevron(self, Vector2(cx + k * u * 0.75, box.get_center().y), dir, u * 0.75, UiPalette.alpha(colr, a * al), maxf(1.0, u * 0.08))


func _draw_target_caption(p: Vector2, u: float, a: float, flip: bool, main: float) -> void:
	var t := state.target
	if t.kind == WidgetMath.KIND_NONE:
		return
	var ui := UiPalette.font_ui()
	var display := UiPalette.font_display()
	var fs := int(u * 0.82)
	var head := ""
	var sub := ""
	var icon_id := WidgetDraw.ICON_BREAKABLE
	var col := UiPalette.PAPER
	match t.kind:
		WidgetMath.KIND_BREAKABLE, WidgetMath.KIND_CORE:
			icon_id = WidgetDraw.ICON_BREAKABLE if t.kind == WidgetMath.KIND_BREAKABLE else WidgetDraw.ICON_CORE
			head = "%s NEEDS %s" % ["WALL" if t.kind == WidgetMath.KIND_BREAKABLE else "CORE", WidgetMath.fmt(t.threshold)]
			if state.heavy_meets or state.light_meets:
				sub = "%s breaks it" % ("light" if state.light_meets else "heavy")
				col = UiPalette.STATE_GOOD
			elif state.heavy_can_meet:
				sub = "run INTO a heavy"
				col = UiPalette.STATE_WARN
			elif state.min_speed > 0.0:
				sub = "needs a %s tape" % WidgetMath.speed_label(state.min_speed)
				col = UiPalette.THREAT
			else:
				sub = "too strong for this gear"
				col = UiPalette.THREAT
		WidgetMath.KIND_ENEMY:
			icon_id = WidgetDraw.ICON_SHIELD if t.shielded else WidgetDraw.ICON_SKULL
			head = "%s %d/%d HP" % [String(t.enemy_type).to_upper(), t.hp, t.max_hp]
			sub = "H: %s · L: %s" % [_hits(state.heavy_hits), _hits(state.light_hits)]
			col = UiPalette.STATE_GOOD if state.heavy_hits == 1 or state.light_hits == 1 else UiPalette.PAPER
		WidgetMath.KIND_BOSS:
			icon_id = WidgetDraw.ICON_EYE
			head = "STAGGER NEEDS %s" % WidgetMath.fmt(main)
			sub = "from behind, off its watch"
			col = UiPalette.STATE_GOOD if state.heavy_meets else UiPalette.STATE_WARN
	var w := maxf(WidgetDraw.text_width(display, head, fs), WidgetDraw.text_width(ui, sub, int(fs * 0.9))) + u * 2.0
	var box := Rect2(Vector2(p.x - (w if flip else 0.0), p.y - u * 1.6), Vector2(w, u * 1.9))
	WidgetDraw.panel(self, box, UiPalette.alpha(UiPalette.PANEL, a), UiPalette.alpha(UiPalette.INK, a), maxf(1.5, u * 0.12), u * 0.3, u * 0.12)
	WidgetDraw.icon(self, icon_id, box.position + Vector2(u * 0.8, box.size.y * 0.5), u * 1.05, UiPalette.alpha(col, a))
	WidgetDraw.text(self, display, box.position + Vector2(u * 1.55, box.size.y * 0.45), head, fs, UiPalette.alpha(UiPalette.PAPER, a))
	WidgetDraw.text(self, ui, box.position + Vector2(u * 1.55, box.size.y * 0.84), sub, int(fs * 0.9), UiPalette.alpha(col, a))


static func _hits(n: int) -> String:
	if n < 0:
		return "no dmg"
	return "%d hit%s" % [n, "" if n == 1 else "s"]


func _draw_flash(p: Vector2, u: float, a: float, flip: bool, ok: bool = false) -> void:
	var display := UiPalette.font_display()
	var ui := UiPalette.font_ui()
	var title := _ok_text if ok else _fail.title
	var line := "" if ok else _fail.line
	var ts := int(u * 0.95)
	var lsz := int(u * 0.62)
	var w := maxf(WidgetDraw.text_width(display, title, ts), WidgetDraw.text_width(ui, line, lsz)) + u * 1.2
	var h := u * (1.5 if line == "" else 2.4)
	var shake := 0.0 if ok else sin(_time * 60.0) * u * 0.12 * clampf(_fail_t - (FAIL_TIME - 0.3), 0.0, 1.0) * 3.0
	var box := Rect2(Vector2(p.x - (w if flip else 0.0) + shake, p.y - u * 0.6), Vector2(w, h))
	var col := UiPalette.STATE_GOOD if ok else UiPalette.STATE_BAD
	WidgetDraw.panel(self, box, UiPalette.alpha(col, a), UiPalette.alpha(UiPalette.INK, a), maxf(2.0, u * 0.14), u * 0.25, u * 0.15)
	WidgetDraw.text(self, display, box.position + Vector2(u * 0.6, u * 1.05), title, ts, UiPalette.alpha(UiPalette.INK, a))
	if line != "":
		WidgetDraw.text(self, ui, box.position + Vector2(u * 0.6, u * 1.95), line, lsz, UiPalette.alpha(UiPalette.INK, a))
