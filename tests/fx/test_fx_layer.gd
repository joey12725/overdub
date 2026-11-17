extends ODTest
## The fx layer as the world view drives it: facade loading, load_level / update / dispose in every
## mode, shake / focus requests, music-reactive modulation, post controls and the ambient build.

const Fx := preload("res://tests/fx/fx_fixtures.gd")


## A world view that records the requests the layers make through RenderCtx.
class RecordingView:
	extends WorldViewBase
	var shakes: Array[float] = []
	var focuses: Array[Vector3] = []

	func request_shake(magnitude: float) -> void:
		shakes.append(magnitude)

	func request_focus(x: float, y: float, weight: float) -> void:
		focuses.append(Vector3(x, y, weight))

	func surface_height(_x: float, _y: float) -> float:
		return 1.4


var _view: RecordingView
var _layer: FxLayerBase
var _ctx: RenderCtx
var _levels: Dictionary = {}


func before_each() -> void:
	_view = RecordingView.new()
	tree().root.add_child(_view)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 14.0
	_view.add_child(cam)
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-35.0), deg_to_rad(45.0), 0.0)), Vector3(14.0, 12.0, 14.0))
	_ctx = _view.new_ctx(Fx.level(), ResolvedLoadout.new())
	_ctx.camera = cam
	_ctx.palette = Fx.palette()
	_ctx.bounds = AABB(Vector3.ZERO, Vector3(10.0, 1.4, 5.0))
	_levels.clear()
	_ctx.music_reactive = []
	for kind: StringName in [MusicReactive.KIND_NEON, MusicReactive.KIND_SCREEN, MusicReactive.KIND_CORE]:
		var k := kind
		_ctx.music_reactive.append(MusicReactive.make(kind, null, func(v: float) -> void: _levels[k] = v))
	_layer = Facades.instance_fx_layer()
	_view.add_child(_layer)


func after_each() -> void:
	if _layer != null:
		_layer.dispose()
	if _view != null:
		_view.queue_free()
	_view = null
	_layer = null
	await tree().process_frame


func test_facade_provides_the_fx_layer() -> void:
	assert_true(Facades.is_provided(Facades.FX_LAYER_SCRIPT), "res://fx/fx_layer.gd exists")
	assert_true(_layer is FxLayerBase, "extends FxLayerBase")
	assert_eq((_layer.get_script() as Script).resource_path, Facades.FX_LAYER_SCRIPT, "the real layer, not the do-nothing base")


func test_load_update_dispose_in_every_mode() -> void:
	_layer.load_level(_ctx)
	var layer: Variant = _layer
	assert_true(layer.director != null, "director built")
	for mode: StringName in [ViewMode.IDLE, ViewMode.RECORD, ViewMode.REVIEW, ViewMode.CINEMATIC]:
		for f: int in 30:
			var evs: Array[SimEvent] = []
			if f % 10 == 0:
				evs = Fx.all_events(30.0, f % 4)
			_layer.update(Fx.frame(mode, f / 15.0, evs), _ctx)
	assert_true(layer.glow.drawn > 0 or layer.ink.drawn > 0, "sprites reached the GPU buffers")
	_layer.dispose()
	assert_true(layer.director == null, "disposed")
	assert_eq(_layer.get_child_count() <= 1, true, "only the shared word atlas survives dispose")


func test_shake_and_focus_go_through_the_ctx() -> void:
	_layer.load_level(_ctx)
	_layer.update(Fx.frame(ViewMode.RECORD, 1.0, [Fx.event_of(SimEventType.KILL, 40.0)]), _ctx)
	assert_true(_view.shakes.size() > 0, "a kill requests shake")
	assert_true(_view.shakes[0] <= FxCatalog.profile(ViewMode.RECORD).shake + 1e-6, "record shake restrained")
	assert_eq(_view.focuses.size(), 0, "no focus outside the cinematic")
	_layer.update(Fx.frame(ViewMode.CINEMATIC, 2.0, [Fx.event_of(SimEventType.OBJECTIVE, 40.0)]), _ctx)
	assert_true(_view.focuses.size() > 0, "objective focuses the cinematic camera")
	assert_true(_view.focuses[-1].z > 0.95, "the finale is the most important thing happening (%f)" % _view.focuses[-1].z)
	_view.shakes.clear()
	_ctx.screen_shake_enabled = false
	_layer.update(Fx.frame(ViewMode.CINEMATIC, 3.0, [Fx.event_of(SimEventType.BOSS_PHASE, 40.0)]), _ctx)
	assert_eq(_view.shakes.size(), 0, "the screen-shake setting is honoured")


func test_music_reactive_surfaces_are_pulsed() -> void:
	_layer.load_level(_ctx)
	for k: StringName in _levels:
		assert_eq(_levels[k], 1.0, "%s starts as built" % k)
	var seen := {}
	for f: int in 60:
		_layer.update(Fx.frame(ViewMode.IDLE, f / 15.0), _ctx)
		for k: StringName in _levels:
			if absf(_levels[k] - 1.0) > 0.02:
				seen[k] = true
	assert_eq((_layer as Variant).reactive_driven, 3, "every surface driven")
	assert_eq(seen.size(), 3, "every kind actually pulses with the music")
	_layer.dispose()
	for k: StringName in _levels:
		assert_eq(_levels[k], 1.0, "%s restored on dispose" % k)


func test_record_restrains_music_modulation() -> void:
	var m := MusicReactive.make(MusicReactive.KIND_NEON, null, Callable())
	var pulse := Fx.music(0.0)
	pulse.bar_pulse = 1.0
	pulse.beat_pulse = 1.0
	var raw := FxMusicDrive.level_for(m, 0, pulse)
	var got: Array[float] = []
	var probe := MusicReactive.make(MusicReactive.KIND_NEON, null, func(v: float) -> void: got.append(v))
	FxMusicDrive.apply([probe], pulse, FxCatalog.profile(ViewMode.RECORD).ambient)
	FxMusicDrive.apply([probe], pulse, FxCatalog.profile(ViewMode.IDLE).ambient)
	assert_true(absf(got[0] - 1.0) < absf(got[1] - 1.0), "record pulses less than idle")
	assert_near(got[1], raw, 1e-6, "idle gets the full level")


func test_post_controls() -> void:
	_layer.load_level(_ctx)
	_layer.update(Fx.frame(ViewMode.RECORD, 1.0, [Fx.event_of(SimEventType.DESYNC, 10.0, 2)]), _ctx)
	assert_true(_ctx.post.chromatic > 0.0, "desync kicks the chromatic split")
	for f: int in 120:
		_layer.update(Fx.frame(ViewMode.CINEMATIC, 1.0 + f / 30.0), _ctx)
	assert_true(_ctx.post.vignette > 1.1, "cinematic deepens the vignette")
	_layer.dispose()
	assert_eq(_ctx.post.saturation, 1.0, "saturation restored")
	assert_eq(_ctx.post.vignette, 1.0, "vignette restored")


func test_ambient_builds_on_the_level() -> void:
	_layer.load_level(_ctx)
	var amb: FxAmbient = (_layer as Variant).ambient
	assert_eq(amb.sigil_count, 3, "start, core and exit sigils")
	assert_eq(amb.screen_count, 1, "one wave screen")
	assert_eq(amb.panel_count, 1, "one rune panel without a world rune surface")
	assert_true(amb.rune_stroke_count > 0, "rune strokes on the '~' tiles")
	assert_true(amb.edge_built, "edge display built")
	# Anchored to the bounds: the rail lies on an edge of the diorama, at the edge's wall height.
	var o := amb.edge_origin
	var on_edge := absf(o.x - 0.25) < 0.3 or absf(o.x - 9.75) < 0.3 or absf(o.z - 0.25) < 0.3 or absf(o.z - 4.75) < 0.3
	assert_true(on_edge, "rail origin on the bounds edge: %s" % o)
	assert_near(amb.rail_y, 1.4, 1e-5, "rail on the edge's top surface")
	var end := o + amb.edge_along * amb.edge_len
	assert_true(end.x > -0.6 and end.x < 10.6 and end.z > -0.6 and end.z < 5.6, "rail stays within the diorama: %s" % end)
	for f: int in 90:
		_layer.update(Fx.frame(ViewMode.IDLE, f / 8.0), _ctx)
	assert_true(amb.epi_count > 0, "epicycles reconstruct the contour")
	assert_true(is_finite(amb.epi_tip.x) and is_finite(amb.epi_tip.y), "epicycle tip finite")


func test_world_rune_surfaces_replace_procedural_runes() -> void:
	var rune := MusicReactive.make(MusicReactive.KIND_RUNE, null, Callable())
	rune.has_at = true
	rune.at = Vector2(3.0, 1.0)
	_ctx.music_reactive.append(rune)
	_layer.load_level(_ctx)
	var amb: FxAmbient = (_layer as Variant).ambient
	assert_eq(amb.rune_stroke_count, 0, "no procedural floor runes over the world's own")
	assert_eq(amb.panel_count, 0, "the panel with a registered rune surface is left to the world")


func test_ribbons_only_in_cinematic() -> void:
	_layer.load_level(_ctx)
	var layer: Variant = _layer
	for f: int in 60:
		var fr := Fx.frame(ViewMode.RECORD, f / 30.0)
		for a: ActorSnap in fr.snap.actors:
			a.x += f * 0.05
		_layer.update(fr, _ctx)
	assert_eq(layer.ribbons.drawn, 0, "no ribbons while recording")
	for f: int in 60:
		var fr := Fx.frame(ViewMode.CINEMATIC, f / 30.0)
		for a: ActorSnap in fr.snap.actors:
			a.x += f * 0.05
		_layer.update(fr, _ctx)
	assert_true(layer.ribbons.drawn >= 3, "a ribbon per present self in the cinematic (%d)" % layer.ribbons.drawn)
