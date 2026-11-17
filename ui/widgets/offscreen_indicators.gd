class_name WidgetOffscreenIndicators
extends Control
## Edge-of-screen chevrons for things outside the camera view (chapter 16; UI-03; OPEN-20):
##   - every self (cassette colour + letter, state icon: alive / recording ghost / ghost / desynced)
##     with a pulse when that self acts (swing, shot, dodge, interact);
##   - each recovery spark (DESYNC-02), drawn as a spark in its cassette colour;
##   - each telegraphing enemy (threat icon, pulsing faster as its telegraph fills).
## Indicators sharing an edge cluster (WidgetOffscreen.layout) into one chevron with a stack.
##
## API (see docs/WIDGETS.md):
##   set_insets(top, bottom)                 screen px reserved by the boss bar / HUD dock
##   update_indicators(snap, projector)      per frame
##   on_events(events)                       this frame's SimEvents (action pulses)
## Full-rect, mouse-transparent overlay.

const PULSE_TIME := 0.55
## Max icons shown in one cluster before "+N".
const MAX_STACK := 4

var top_inset: float = 0.0
var bottom_inset: float = 0.0
var clusters: Array[WidgetOffscreen.Cluster] = []
var _pulse: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _last_anim: Array[StringName] = [&"", &"", &"", &""]
var _time: float = 0.0
var _safe: Rect2 = Rect2()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_insets(top: float, bottom: float) -> void:
	top_inset = top
	bottom_inset = bottom


## The rect indicators sit on.
func safe_rect() -> Rect2:
	var u := WidgetDraw.unit(self)
	return WidgetOffscreen.safe_rect(Rect2(Vector2.ZERO, size), top_inset, bottom_inset, u * 1.6)


func on_events(events: Array[SimEvent]) -> void:
	for ev: SimEvent in events:
		if ev.tape < 0 or ev.tape >= OD.TAPE_COUNT:
			continue
		match ev.type:
			SimEventType.SWING, SimEventType.FIRE, SimEventType.DODGE, SimEventType.INTERACT, SimEventType.HIT, SimEventType.BREAK:
				_pulse[ev.tape] = 1.0


func update_indicators(snap: FrameSnapshot, projector: WidgetProjector) -> void:
	_safe = safe_rect()
	var items: Array[WidgetOffscreen.Item] = []
	if snap != null and projector != null and projector.valid():
		items = collect_items(snap, projector, _pulse)
		# Anim-change pulses for callers that do not forward events.
		for a: ActorSnap in snap.actors:
			if a.tape < 0 or a.tape >= OD.TAPE_COUNT:
				continue
			if a.anim != _last_anim[a.tape] and _is_action_anim(a.anim):
				_pulse[a.tape] = maxf(_pulse[a.tape], 1.0)
			_last_anim[a.tape] = a.anim
	clusters = WidgetOffscreen.layout(items, _safe, WidgetDraw.unit(self) * 4.5)
	queue_redraw()


## Items for every self, spark and telegraphing enemy in `snap` (on-screen ones are filtered later).
static func collect_items(snap: FrameSnapshot, projector: WidgetProjector, pulses: PackedFloat32Array) -> Array[WidgetOffscreen.Item]:
	var items: Array[WidgetOffscreen.Item] = []
	for a: ActorSnap in snap.actors:
		var p := Vector2(a.x, a.y)
		var it := WidgetOffscreen.Item.make(WidgetOffscreen.KIND_SELF, a.tape, WidgetOffscreen.self_state(a), projector.to_screen(p, 1.0))
		it.behind = projector.is_behind(p, 1.0)
		if a.tape >= 0 and a.tape < pulses.size():
			it.pulse = pulses[a.tape]
		items.append(it)
		if a.has_spark:
			var sp := WidgetOffscreen.Item.make(WidgetOffscreen.KIND_SPARK, a.tape, WidgetOffscreen.STATE_DESYNC, projector.to_screen(a.spark, 0.6))
			sp.behind = projector.is_behind(a.spark, 0.6)
			items.append(sp)
	for e: EnemySnap in snap.enemies:
		if not e.alive or e.state != EnemyStateName.TELEGRAPH:
			continue
		var h: float = WidgetMath.HEAD_HEIGHT.get(e.type, 1.5) * 0.6
		var it := WidgetOffscreen.Item.make(WidgetOffscreen.KIND_THREAT, -1, &"", projector.to_screen(Vector2(e.x, e.y), h))
		it.id = e.id
		it.pulse = clampf(e.state_t, 0.0, 1.0)
		it.behind = projector.is_behind(Vector2(e.x, e.y), h)
		items.append(it)
	return items


static func _is_action_anim(anim: StringName) -> bool:
	return anim == AnimState.LIGHT_WINDUP or anim == AnimState.HEAVY_WINDUP or anim == AnimState.RANGED or anim == AnimState.DODGE or anim == AnimState.INTERACT


func _process(delta: float) -> void:
	_time += delta
	var any := false
	for i: int in _pulse.size():
		if _pulse[i] > 0.0:
			_pulse[i] = maxf(0.0, _pulse[i] - delta / PULSE_TIME)
			any = true
	if any or not clusters.is_empty():
		queue_redraw()


func _draw() -> void:
	var u := WidgetDraw.unit(self)
	for cl: WidgetOffscreen.Cluster in clusters:
		_draw_cluster(cl, u)


func _item_color(it: WidgetOffscreen.Item) -> Color:
	if it.kind == WidgetOffscreen.KIND_THREAT:
		return UiPalette.THREAT
	return UiPalette.tape(it.tape)


func _draw_cluster(cl: WidgetOffscreen.Cluster, u: float) -> void:
	# Order inside a stack: threats first (most urgent), then selves by cassette, then sparks.
	var items: Array[WidgetOffscreen.Item] = cl.items.duplicate()
	items.sort_custom(func(a: WidgetOffscreen.Item, b: WidgetOffscreen.Item) -> bool:
		var ka := 0 if a.kind == WidgetOffscreen.KIND_THREAT else (1 if a.kind == WidgetOffscreen.KIND_SELF else 2)
		var kb := 0 if b.kind == WidgetOffscreen.KIND_THREAT else (1 if b.kind == WidgetOffscreen.KIND_SELF else 2)
		if ka != kb:
			return ka < kb
		return a.tape < b.tape)
	var lead := items[0]
	var col := _item_color(lead)
	var pulse := 0.0
	for it: WidgetOffscreen.Item in items:
		var p := it.pulse
		if it.kind == WidgetOffscreen.KIND_THREAT:
			# Telegraphs pulse faster as they fill.
			p = (0.5 + 0.5 * sin(_time * TAU * (1.5 + 3.0 * it.pulse))) * (0.4 + 0.6 * it.pulse)
		pulse = maxf(pulse, p)
	var dir := Vector2.from_angle(cl.angle)
	# Chevron sits on the border, pointing out; the stack sits just inside it.
	var chev := cl.pos
	if pulse > 0.01:
		draw_arc(chev, u * (1.1 + 0.9 * (1.0 - pulse)), 0, TAU, 28, UiPalette.alpha(col, pulse * 0.8), maxf(2.0, u * 0.18), true)
	WidgetDraw.chevron(self, chev + Vector2(1.5, 1.5), cl.angle, u * 1.8, UiPalette.alpha(UiPalette.INK, 0.6), 0.0)
	WidgetDraw.chevron(self, chev, cl.angle, u * 1.8, col, maxf(1.5, u * 0.14))
	# Stack direction: along the edge.
	var along := Vector2(1, 0) if cl.edge == WidgetOffscreen.EDGE_TOP or cl.edge == WidgetOffscreen.EDGE_BOTTOM else Vector2(0, 1)
	var inward := -dir
	var shown := mini(items.size(), MAX_STACK)
	var step := u * 1.55
	var base := chev + inward * u * 1.9 - along * step * (shown - 1) * 0.5
	for k: int in shown:
		_draw_item(items[k], base + along * step * k, u)
	if items.size() > MAX_STACK:
		var more := "+%d" % (items.size() - MAX_STACK)
		WidgetDraw.text_centered(self, UiPalette.font_display(), base + along * step * shown, more, int(u * 0.7), UiPalette.PAPER, u * 0.2)


func _draw_item(it: WidgetOffscreen.Item, c: Vector2, u: float) -> void:
	var s := u * 1.35
	match it.kind:
		WidgetOffscreen.KIND_THREAT:
			# A red diamond with a bold "!": an attack is being telegraphed out there.
			var d := PackedVector2Array([c + Vector2(0, -s * 0.72), c + Vector2(s * 0.72, 0), c + Vector2(0, s * 0.72), c + Vector2(-s * 0.72, 0)])
			draw_colored_polygon(d, UiPalette.THREAT)
			var rim := d.duplicate()
			rim.append(d[0])
			draw_polyline(rim, UiPalette.INK, 2.0, true)
			WidgetDraw.text_centered(self, UiPalette.font_display(), c, "!", int(s * 0.85), UiPalette.INK)
		WidgetOffscreen.KIND_SPARK:
			WidgetDraw.panel(self, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), UiPalette.INK, UiPalette.tape(it.tape), 2.0, s * 0.5)
			WidgetDraw.icon(self, WidgetDraw.ICON_SPARK, c, s * 0.85, UiPalette.tape(it.tape))
		_:
			var lit := it.state == WidgetOffscreen.STATE_ALIVE or it.state == WidgetOffscreen.STATE_DESYNC
			WidgetDraw.tape_badge(self, c, s, it.tape, lit)
			# State icon in a small corner disc.
			var ic := c + Vector2(s * 0.5, -s * 0.5)
			draw_circle(ic, s * 0.32, UiPalette.INK)
			WidgetDraw.icon(self, WidgetDraw.state_icon(it.state), ic, s * 0.5, WidgetDraw.state_color(it.state))
