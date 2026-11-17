class_name WidgetWorldOverlay
extends Control
## One mountable overlay that owns the in-world widgets and feeds them from a single per-frame call,
## so integration is "add this Control on the UI layer and call update_frame". Children, bottom to top:
##   WidgetThresholdBadges, WidgetMomentumGauge, WidgetOffscreenIndicators, WidgetBossBar.
##
## API (see docs/WIDGETS.md):
##   load_level(level, loadout, boss_memory := null)
##   set_camera(camera)                  the world's Camera3D (or set_projector for a custom mapping)
##   set_bottom_inset(px)                the HUD dock height (HudBase bottom inset)
##   set_aim(angle)                      the live self's aim, sim radians (NAN = body facing)
##   set_boss_memory(memory)             when committed tapes change
##   update_frame(snap, view, events)    every rendered frame
## Phase rules: the gauge shows only while recording; badges and off-screen chevrons hide during the
## cinematic (CINE-01/02: a performance to watch); the boss bar always shows while a boss is present.

var badges: WidgetThresholdBadges = null
var gauge: WidgetMomentumGauge = null
var offscreen: WidgetOffscreenIndicators = null
var boss_bar: WidgetBossBar = null
var projector: WidgetProjector = WidgetProjector.new()
var bottom_inset: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	badges = WidgetThresholdBadges.new()
	badges.name = "ThresholdBadges"
	add_child(badges)
	gauge = WidgetMomentumGauge.new()
	gauge.name = "MomentumGauge"
	add_child(gauge)
	offscreen = WidgetOffscreenIndicators.new()
	offscreen.name = "OffscreenIndicators"
	add_child(offscreen)
	boss_bar = WidgetBossBar.new()
	boss_bar.name = "BossBar"
	add_child(boss_bar)


func load_level(level: LevelDef, loadout: ResolvedLoadout, boss_memory: BossMemory = null) -> void:
	badges.setup(level, loadout)
	gauge.setup(level, loadout)
	boss_bar.clear()
	boss_bar.set_memory(boss_memory)


func set_camera(camera: Camera3D) -> void:
	projector = WidgetProjector.for_camera(camera)


func set_projector(p: WidgetProjector) -> void:
	projector = p


func set_bottom_inset(px: float) -> void:
	bottom_inset = px


func set_aim(angle: float) -> void:
	gauge.set_aim(angle)


func set_boss_memory(memory: BossMemory) -> void:
	boss_bar.set_memory(memory)


func update_frame(snap: FrameSnapshot, view: SessionView, events: Array[SimEvent] = []) -> void:
	var cinematic := view != null and view.phase == SessionPhase.CINEMATIC
	boss_bar.update_from_snapshot(snap)
	if not events.is_empty():
		boss_bar.on_events(events)
	badges.visible = not cinematic
	offscreen.visible = not cinematic
	if not cinematic:
		badges.update_badges(snap, view, projector)
		offscreen.set_insets(boss_bar.top_inset(), bottom_inset)
		offscreen.update_indicators(snap, projector)
		if not events.is_empty():
			offscreen.on_events(events)
	gauge.update_gauge(snap, view, projector)
	if not events.is_empty():
		gauge.on_events(events)
