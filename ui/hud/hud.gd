extends HudBase
## OVERDUB in-level HUD (res://ui/hud/hud.tscn): four persistent cassette decks and the master beat
## ruler (UI-01..07, NEW-07..11), plus the per-phase layers - objective chip, phase banner, the
## active deck's setup surface, count-in, briefing card and decision panel. Port of
## prototype/src/ui/hud. Driven entirely by the SessionView passed to update_hud(); it holds no game
## state. Clicks on its own controls leave through HudBase.action (a speed pick several steps away
## emits that many speedUp/speedDown actions).
##
## Camera framing: the dock (decks + ruler) covers the bottom of the screen. bottom_inset() returns
## that height in this Control's pixels (0 when the HUD is hidden or in 'results'), and
## bottom_inset_changed(px) fires whenever it changes (phase changes resize the dock; while
## recording it stays <= 30% of the height so the playfield keeps >= 70%). Floating cards (setup
## surface, briefing, decision, count-in) overlay the playfield and are not part of the inset.

## World-anchored widgets (docs/WIDGETS.md) live in `world_overlay`, the HUD's bottom-most child:
## threshold badges, the momentum gauge near the live self, off-screen chevrons and the boss bar.
## They need the world -> screen mapping from the game layer; the hooks are below under "world
## widgets" (set_world_camera / set_world_projector, load_level_widgets, update_world, set_aim,
## set_boss_memory, world_point_to_screen). The boss bar's top inset pushes the banner down.
##
## Coach-mark anchors (docs/DIALOGUE.md "HUD anchors"): every part is in its group (deck_<n>,
## ruler, objective, count_in, setup, decision, briefing, banner) and anchor_rect(anchor, subject)
## answers the exact sub-rects (deck parts, ruler lanes / playhead, gameplay prompts on the controls
## strip, the panels' buttons).

## The dock's height from the bottom edge changed (pixels, in this Control's coordinates).
signal bottom_inset_changed(px: float)
## The top band covered by the boss bar changed (0 when no boss).
signal top_inset_changed(px: float)

var view: SessionView = null
var pulse: MusicPulse = MusicPulse.new()
var device: StringName = HudBase.DEVICE_KEYBOARD
var bindings: Dictionary = {}
var hold_progress: float = 0.0
## Accessibility "hold actions: press twice" (set_hold_mode).
var press_twice: bool = false
var patterns: bool = false

var decks: Array[HudDeck] = []
var ruler: HudRuler = null
var setup_panel: HudSetup = null
var objective: HudObjective = null
var banner: HudBanner = null
var count_in: HudCountIn = null
var briefing: HudBriefing = null
var decision: HudDecision = null
var controls: HudControls = null
var world_overlay: WidgetWorldOverlay = null
## Reduce flashing (accessibility): REC lamps and desync jitter hold still.
var reduce_flashing: bool = false

var _layout: HudModel.DockLayout = null
var _inset: float = -1.0
var _boss_top: float = 0.0
var _rec_time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var t := UiPalette.theme()
	if t != null:
		theme = t
	# World widgets first, so the dock and every card draw over chevrons and badges.
	world_overlay = (load("res://ui/widgets/world_overlay.tscn") as PackedScene).instantiate() as WidgetWorldOverlay
	world_overlay.name = "WorldOverlay"
	add_child(world_overlay)
	world_overlay.boss_bar.top_inset_changed.connect(_on_boss_top)
	ruler = HudRuler.new()
	ruler.name = "Ruler"
	add_child(ruler)
	for i in OD.TAPE_COUNT:
		var d := HudDeck.new()
		d.name = "Deck%s" % OD.TAPE_NAMES[i]
		d.index = i
		d.deck.index = i
		add_child(d)
		decks.append(d)
	objective = _panel(HudObjective.new(), "Objective") as HudObjective
	banner = _panel(HudBanner.new(), "Banner") as HudBanner
	setup_panel = _panel(HudSetup.new(), "Setup") as HudSetup
	briefing = _panel(HudBriefing.new(), "Briefing") as HudBriefing
	decision = _panel(HudDecision.new(), "Decision") as HudDecision
	count_in = _panel(HudCountIn.new(), "CountIn") as HudCountIn
	controls = _panel(HudControls.new(), "Controls") as HudControls
	ruler.add_to_group(&"ruler")
	for i in decks.size():
		decks[i].add_to_group(StringName("deck_%d" % i))
	objective.add_to_group(&"objective")
	count_in.add_to_group(&"count_in")
	setup_panel.add_to_group(&"setup")
	decision.add_to_group(&"decision")
	briefing.add_to_group(&"briefing")
	banner.add_to_group(&"banner")
	resized.connect(_relayout)
	if view != null:
		_apply()
	else:
		_hide_all()


func _panel(p: HudPanel, n: String) -> HudPanel:
	p.name = n
	p.visible = false
	add_child(p)
	p.pressed.connect(_on_pressed)
	return p


func _on_pressed(a: StringName, times: int) -> void:
	for k in maxi(1, times):
		action.emit(a)


# ───────────────────────────── HudBase ─────────────────────────────

func update_hud(v: SessionView, p: MusicPulse) -> void:
	view = v
	pulse = p if p != null else MusicPulse.new()
	if is_node_ready():
		_apply()


func deck_event(tape: int, kind: StringName) -> void:
	if tape >= 0 and tape < decks.size():
		decks[tape].flash(kind)


func set_device(d: StringName) -> void:
	device = d
	if is_node_ready():
		_push_prompts()


func set_bindings(prompts: Dictionary[StringName, ButtonPrompt]) -> void:
	bindings = prompts.duplicate()
	if is_node_ready():
		_push_prompts()


func set_hold_progress(progress: float) -> void:
	hold_progress = clampf(progress, 0.0, 1.0)
	if is_node_ready():
		for p: HudPanel in _panels():
			p.hold_progress = hold_progress
		decision.queue_redraw()
		banner.queue_redraw()


## Accessibility "hold actions" (SaveSettings.hold_mode == "press"): the reset control reads PRESS
## TWICE / PRESS AGAIN TO CONFIRM instead of HOLD, and its ring fills when the first press armed it.
func set_hold_mode(press: bool) -> void:
	press_twice = press
	if is_node_ready():
		for p: HudPanel in _panels():
			p.press_twice = press
			p.queue_redraw()


## Text size option (SaveSettings.text_scale): the HUD's reading text (decision notes and option
## details, briefing lines, objective, setup copy and hint) follows UiPalette.text_scale; the cards
## are measured again so they grow with it.
func set_text_scale(sc: float) -> void:
	UiPalette.text_scale = clampf(sc, 0.75, 2.0)
	if is_node_ready():
		for p: HudPanel in _panels():
			p.queue_redraw()
		_relayout()


func set_patterns(enabled: bool) -> void:
	patterns = enabled
	if is_node_ready():
		for d: HudDeck in decks:
			d.patterns = enabled
			d.queue_redraw()
		ruler.patterns = enabled
		ruler.queue_redraw()


## Pixels at the bottom of the HUD covered by the dock (decks + ruler + the active deck's tab);
## 0 when nothing is shown. Use it to frame the playfield above the HUD.
func bottom_inset() -> float:
	return maxf(0.0, _inset) if visible else 0.0


# ───────────────────────────── per frame ─────────────────────────────

func _process(delta: float) -> void:
	if view == null or not visible:
		return
	for d: HudDeck in decks:
		d.advance(delta)
	ruler.advance(delta)
	for p: HudPanel in _panels():
		p.advance(delta)
	# The controls strip is a reminder: full strength for the first bars of a take, then it recedes.
	_rec_time = _rec_time + delta if view.phase == SessionPhase.RECORDING else 0.0
	controls.fade = 1.0 if _rec_time < 6.0 else maxf(0.55, 1.0 - (_rec_time - 6.0) * 0.25)
	if count_in.visible != count_in.is_showing():
		_relayout()


func _panels() -> Array[HudPanel]:
	return [objective, banner, setup_panel, briefing, decision, count_in, controls]


func _push_prompts() -> void:
	for p: HudPanel in _panels():
		p.device = device
		p.bindings = bindings
		p.queue_redraw()
	if view != null:
		_relayout()


func _hide_all() -> void:
	for c: Node in get_children():
		if c != world_overlay:
			(c as CanvasItem).visible = false


func _apply() -> void:
	var v := view
	var bars := float(v.level.bars) if v.level != null else 8.0
	var lspeeds: Array[float] = v.level.speeds if v.level != null else v.speeds
	for i in OD.TAPE_COUNT:
		var dv: DeckView = v.decks[i] if i < v.decks.size() else DeckView.new()
		decks[i].set_deck(dv, v.phase, v.active == i, v.beat, bars, lspeeds, pulse.beat_pulse)
		decks[i].patterns = patterns
		decks[i].reduce_flashing = reduce_flashing
	ruler.patterns = patterns
	ruler.set_view(v, pulse)
	for p: HudPanel in _panels():
		p.device = device
		p.bindings = bindings
		p.hold_progress = hold_progress
		p.press_twice = press_twice
		p.reduce_flashing = reduce_flashing
		p.set_view(v)
	_relayout()


## Lay the dock and the phase layers out for the current size and phase.
func _relayout() -> void:
	if view == null or not is_node_ready():
		return
	var v := view
	var sz := size
	if sz.x < 2.0 or sz.y < 2.0:
		sz = get_viewport_rect().size
	var L := HudModel.dock_layout(sz, v.phase, v.active)
	_layout = L
	var u := L.unit
	var m := roundf(u * HudModel.MARGIN_U)
	var phase := v.phase
	var shown := L.visible

	ruler.visible = shown
	ruler.unit = u
	ruler.slim = L.slim
	ruler.position = L.ruler.position
	ruler.size = L.ruler.size
	for i in OD.TAPE_COUNT:
		var d := decks[i]
		d.visible = shown
		d.unit = u
		d.slim = L.slim
		d.tab_h = L.tab_h
		d.position = L.decks[i].position
		d.size = L.decks[i].size

	for p: HudPanel in _panels():
		p.unit = u

	# Top-left objective chip.
	var obj_w := minf(u * 17.5, sz.x * 0.3)
	objective.visible = shown and phase != SessionPhase.BRIEFING and phase != SessionPhase.CINEMATIC
	if objective.visible:
		var oh := objective.measure(obj_w, sz.y * 0.3).y
		objective.position = Vector2(m, m)
		objective.size = Vector2(obj_w, oh)

	# Top-centre banner, clear of the objective chip and below the boss bar when a boss is up.
	var top_y := m + _boss_top
	banner.visible = shown and (phase == SessionPhase.SETUP or phase == SessionPhase.RECORDING or phase == SessionPhase.REVIEW or phase == SessionPhase.CINEMATIC)
	if banner.visible:
		var side := obj_w + m * 2.0 if objective.visible else m
		var bw := minf(u * 46.0, sz.x - 2.0 * side)
		var bh := banner.measure(bw, sz.y * 0.4).y
		banner.position = Vector2((sz.x - bw) * 0.5, top_y)
		banner.size = Vector2(bw, bh)
		top_y += bh
	var stage := Rect2(m, top_y + m * 0.5, sz.x - 2.0 * m, sz.y - L.bottom_inset - top_y - m * 1.5)

	# Setup surface above the active deck.
	setup_panel.visible = shown and phase == SessionPhase.SETUP and v.active >= 0
	if setup_panel.visible:
		var sh := setup_panel.measure(L.setup_w, sz.y).y
		var sy := maxf(top_y + m * 0.5, L.setup_bottom - sh)
		setup_panel.position = Vector2(L.setup_x, sy)
		setup_panel.size = Vector2(L.setup_w, sh)

	briefing.visible = shown and phase == SessionPhase.BRIEFING and v.level != null
	if briefing.visible:
		_center_in(briefing, stage)
	decision.visible = shown and phase == SessionPhase.DECISION
	if decision.visible:
		_center_in(decision, stage)
	count_in.visible = shown and count_in.is_showing()
	if count_in.visible:
		count_in.position = stage.position
		count_in.size = stage.size

	# Controls strip: bottom-right, just above the dock, while the player is about to play / playing.
	controls.visible = shown and (phase == SessionPhase.RECORDING or phase == SessionPhase.COUNTIN) and not L.slim
	if controls.visible:
		var cs := controls.measure(sz.x * 0.62, sz.y)
		controls.size = cs
		controls.position = Vector2(sz.x - m - cs.x, sz.y - L.bottom_inset - m * 0.6 - cs.y)

	var inset := L.bottom_inset if shown else 0.0
	if absf(inset - _inset) > 0.5:
		_inset = inset
		world_overlay.set_bottom_inset(inset)
		bottom_inset_changed.emit(inset)


func _center_in(p: HudPanel, stage: Rect2) -> void:
	var s := p.measure(minf(stage.size.x, unit_width_cap()), stage.size.y)
	p.size = s
	p.position = Vector2(stage.position.x + (stage.size.x - s.x) * 0.5, stage.position.y + maxf(0.0, (stage.size.y - s.y) * 0.5))


func unit_width_cap() -> float:
	return (_layout.unit if _layout != null else 14.0) * 52.0


## The dock layout last applied (tests and tools).
func dock_layout() -> HudModel.DockLayout:
	return _layout


func _on_boss_top(px: float) -> void:
	_boss_top = px
	top_inset_changed.emit(px)
	_relayout()


## Pixels at the top covered by the boss bar (0 when no boss is up).
func top_inset() -> float:
	return _boss_top if visible else 0.0


## Accessibility: hold REC lamps and desync jitter still (docs/ACCESSIBILITY.md H6/H7).
func set_reduce_flashing(on: bool) -> void:
	reduce_flashing = on
	if is_node_ready():
		for d: HudDeck in decks:
			d.reduce_flashing = on
		banner.reduce_flashing = on


# ───────────────────────────── world widgets (game hooks) ─────────────────────────────

## The world's Camera3D (WorldViewBase.ctx.camera): badges, gauge, chevrons and the coach / bark
## world anchors are projected through it.
func set_world_camera(cam: Camera3D) -> void:
	world_overlay.set_camera(cam)


## Custom mapping instead of a camera: func(sim: Vector2, h: float) -> Vector2 (tests, tools).
func set_world_projector(fn: Callable) -> void:
	world_overlay.set_projector(WidgetProjector.for_callable(fn))


## On level load: the level, the resolved loadout and the boss memory (SimConfig.boss_memory or null).
func load_level_widgets(level: LevelDef, loadout: ResolvedLoadout, boss_memory: BossMemory = null) -> void:
	world_overlay.load_level(level, loadout, boss_memory)


## On every commit / reset: the boss's new memory of the committed tapes.
func set_boss_memory(memory: BossMemory) -> void:
	world_overlay.set_boss_memory(memory)


## While recording: the live self's aim in sim radians (NAN = body facing).
func set_aim(angle: float) -> void:
	world_overlay.set_aim(angle)


## Every rendered frame, next to update_hud: the frame's snapshot and sim events.
func update_world(snap: FrameSnapshot, v: SessionView = null, events: Array[SimEvent] = []) -> void:
	if snap == null:
		return
	world_overlay.visible = visible
	world_overlay.update_frame(snap, v if v != null else view, events)


## Sim tiles -> viewport pixels at about head height, or null when off screen / no mapping (the
## callable DialogueLayer.setup() wants for world:self coach marks and over-head barks).
func world_point_to_screen(p: Vector2) -> Variant:
	var pr := world_overlay.projector
	if pr == null or not pr.valid() or pr.is_behind(p, 1.2):
		return null
	var sp := pr.to_screen(p, 1.2)
	return sp if get_viewport_rect().has_point(sp) else null


# ───────────────────────────── coach-mark anchors ─────────────────────────────

## docs/DIALOGUE.md hook: `anchor` with :active / :subject resolved ("deck:2", "deck.speed",
## "ruler.lane:1", "prompt:light"...). HUD-local rect, Rect2() when not on screen (the resolver then
## tries groups and node-name fallbacks).
func anchor_rect(anchor: String, _subject: Dictionary = {}) -> Rect2:
	if view == null or not visible:
		return Rect2()
	var live := view.active
	if anchor.begins_with("prompt:"):
		var act := StringName(anchor.substr(7))
		if controls.visible:
			var r := controls.prompt_rect(act)
			if r.has_area():
				return Rect2(controls.position + r.position, r.size)
		for p: HudPanel in [setup_panel, decision, banner, briefing]:
			if not p.visible:
				continue
			for z: Array in p.zones():
				if z[1] == act and z[3]:
					var zr := z[0] as Rect2
					return Rect2(p.position + zr.position, zr.size)
		return Rect2()
	if anchor.begins_with("deck."):
		if live < 0 or live >= decks.size() or not decks[live].visible:
			return Rect2()
		var d := decks[live]
		var g := d.geometry()
		var r := Rect2()
		match anchor.substr(5):
			"speed":
				r = g.speed
			"reels":
				r = g.cassette
			"status":
				r = g.badges[0] if g.badges.size() > 0 else Rect2()
			"endMode":
				r = g.badges[g.badges.size() - 1] if g.badges.size() > 0 else Rect2()
		return Rect2(d.position + r.position, r.size) if r.has_area() else Rect2()
	if anchor.begins_with("ruler") and ruler.visible:
		var body := ruler.body_rect()
		var geo := HudModel.ruler_geometry(body.size.x, body.size.y, ruler.unit, ruler.slim)
		var o := ruler.position + body.position
		if anchor.begins_with("ruler.lane:"):
			var i := anchor.substr(11).to_int()
			if i < 0 or i > 3:
				return Rect2()
			return Rect2(o + Vector2(geo.track_x, geo.lane_y[i]), Vector2(geo.track_w, geo.lane_h))
		if anchor == "ruler.playhead":
			var horizon := maxf(1.0, view.horizon_beats)
			var px := geo.track_x + geo.track_w * clampf(view.beat / horizon, 0.0, 1.0)
			var bottom: float = geo.lane_y[3] + geo.lane_h
			return Rect2(o + Vector2(px - ruler.unit * 0.5, geo.threat_h), Vector2(ruler.unit, bottom - geo.threat_h))
	return Rect2()
