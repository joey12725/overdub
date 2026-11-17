extends ODTest
## Integration of the fx layer with traps (docs/TRAPS.md events), accessibility (docs/ACCESSIBILITY.md
## photosensitivity limits) and the cinematic director (docs/CINEMATIC.md letterbox and cues).

const Fx := preload("res://tests/fx/fx_fixtures.gd")

## Every `<kind>:<what>` detail docs/TRAPS.md lists for the 'trap' event.
const TRAP_DETAILS := [
	"spikes:warn", "crusher:warn", "flame:warn", "spikes:up", "spikes:down", "crusher:slam",
	"crusher:retract", "crusher:hold", "crusher:open", "conveyor:on", "conveyor:off",
	"conveyor:reverse", "conveyor:forward", "flame:on", "flame:off", "dart:fire", "dart:on",
	"dart:off", "bumper:fire", "sensor:on", "sensor:off", "relay:armed", "relay:on", "relay:off",
	"magnet:on", "magnet:off",
]


func _trap_event(detail: String) -> SimEvent:
	return SimEvent.make(1000, SimEventType.TRAP, 4.0, 2.5).with_id("t1").with_dir(0.0).with_power(1.0).with_detail(detail)


func test_every_trap_event_has_a_visible_effect_in_every_play_mode() -> void:
	assert_true(FxCatalog.routes_for(SimEventType.TRAP).size() > 0, "trap events are routed")
	for mode: StringName in [ViewMode.RECORD, ViewMode.REVIEW, ViewMode.CINEMATIC]:
		for detail: String in TRAP_DETAILS:
			var d := Fx.director()
			d.update(Fx.frame(mode, 4.2, [_trap_event(detail)]))
			var n := d.glow.count() + d.ink.count()
			assert_true(n > 0, "%s in %s spawns something" % [detail, mode])
			for i: int in d.glow.capacity:
				if d.glow.alive[i] == 0:
					continue
				var c := d.glow.color[i]
				for t: int in OD.TAPE_COUNT:
					assert_false(c.is_equal_approx(OD.tape_color(t)), "%s never uses a cassette colour" % detail)


func test_trap_stroke_kicks_harder_than_a_telegraph() -> void:
	var slam := Fx.director()
	slam.update(Fx.frame(ViewMode.REVIEW, 4.2, [_trap_event("crusher:slam")]))
	var warn := Fx.director()
	warn.update(Fx.frame(ViewMode.REVIEW, 4.2, [_trap_event("crusher:warn")]))
	assert_true(slam.shake_out > 0.0, "the stroke shakes")
	assert_eq(warn.shake_out, 0.0, "the telegraph does not")


func test_environment_kill_is_not_cassette_coloured() -> void:
	var d := Fx.director()
	var ev := SimEvent.make(1000, SimEventType.KILL, 4.0, 2.5).with_dir(0.0).with_power(20.0).with_detail("spikes")
	d.update(Fx.frame(ViewMode.REVIEW, 4.2, [ev]))
	var warm := 0
	for i: int in d.glow.capacity:
		if d.glow.alive[i] != 0 and d.glow.color[i].r > 0.9 and d.glow.color[i].b < 0.75:
			warm += 1
	assert_true(warm > 0, "a trap kill uses the trap's warm impact colour")


func test_flash_rate_limit_and_alpha_cap() -> void:
	var d := Fx.director()
	var lim := AccessKit.flash_limits(false)
	var peak := 0.0
	var flashes := 0
	var prev := 0.0
	# Four objective finales on consecutive frames, then one every 0.1 s for 2 s: never a strobe.
	for k: int in 120:
		var evs: Array[SimEvent] = []
		if k < 4 or k % 6 == 0:
			evs.append(Fx.event_of(SimEventType.OBJECTIVE, 20.0, 0))
			evs.append(Fx.event_of(SimEventType.BOSS_PHASE, 20.0, 0))
		d.update(Fx.frame(ViewMode.CINEMATIC, 4.0 + k / 60.0, evs))
		peak = maxf(peak, d.screen.flash_a)
		if d.screen.flash_a > prev + 0.02:
			flashes += 1
		prev = d.screen.flash_a
	assert_true(peak <= float(lim["fullscreen_flash_max_alpha"]) + 1e-4, "flash alpha within the cap (%f)" % peak)
	assert_true(flashes <= 2 * 2 + 1, "at most two flashes a second over two seconds (%d)" % flashes)


func test_reduce_flashing_caps_flashes_and_glitch() -> void:
	var on := Fx.director()
	on.env.reduce_flashing = true
	on.update(Fx.frame(ViewMode.CINEMATIC, 4.2, [Fx.event_of(SimEventType.OBJECTIVE, 20.0, 0), Fx.event_of(SimEventType.DESYNC, 20.0, 2)]))
	var off := Fx.director()
	off.update(Fx.frame(ViewMode.CINEMATIC, 4.2, [Fx.event_of(SimEventType.OBJECTIVE, 20.0, 0), Fx.event_of(SimEventType.DESYNC, 20.0, 2)]))
	var lim := AccessKit.flash_limits(true)
	assert_true(on.screen.flash_a <= float(lim["fullscreen_flash_max_alpha"]) + 1e-4, "reduced flash alpha %f" % on.screen.flash_a)
	assert_true(on.screen.flash_a < off.screen.flash_a, "reduce flashing dims the flash")
	assert_true(on.screen.glitch < off.screen.glitch, "reduce flashing scales the glitch tear")


func test_no_saturated_red_flash() -> void:
	var d := Fx.director()
	d.call("_flash", Color(1.0, 0.05, 0.05), 0.2)
	var c := d.screen.flash
	assert_true(c.r / maxf(1e-4, c.r + c.g + c.b) < 0.8, "a red flash is desaturated")


func _cinema_frame(letterbox: float, cues: Array[CinemaTypes.Cue]) -> CinemaFrame:
	var cf := CinemaFrame.new()
	cf.shot = CinemaShot.new()
	cf.shot_index = 0
	cf.letterbox = letterbox
	cf.cues = cues
	return cf


func test_director_letterbox_and_cues_drive_the_cinematic() -> void:
	var d := Fx.director()
	for k: int in 240:
		var f := Fx.frame(ViewMode.CINEMATIC, 4.0 + k / 60.0)
		f.cinema = _cinema_frame(CinemaGrammar.LETTERBOX_DEEP, [])
		d.update(f)
	assert_near(d.screen.letterbox, CinemaGrammar.LETTERBOX_DEEP, 0.005, "letterbox follows the director (deep)")
	# Chord changes come from the plan's cues while directed, not from the music clock.
	var before := d.chord_flashes
	var f2 := Fx.frame(ViewMode.CINEMATIC, 9.0, [])
	f2.music.chord = 3
	f2.cinema = _cinema_frame(CinemaGrammar.LETTERBOX_BASE, [])
	d.update(f2)
	assert_eq(d.chord_flashes, before, "no self-detected chord flash under a plan")
	var cue := CinemaTypes.Cue.new()
	cue.kind = CinemaGrammar.CUE_CHORD_FLASH
	cue.chord = 2
	var imp := CinemaTypes.Cue.new()
	imp.kind = CinemaGrammar.CUE_IMPACT
	imp.tape = 1
	imp.point = Vector2(3.0, 2.0)
	var f3 := Fx.frame(ViewMode.CINEMATIC, 9.2, [])
	f3.cinema = _cinema_frame(CinemaGrammar.LETTERBOX_BASE, [cue, imp])
	d.update(f3)
	assert_eq(d.chord_flashes, before + 1, "chordFlash cue flashes")
	assert_true(d.screen.burst_amt > 0.0, "impact cue bursts speed lines")


func test_fx_ambient_yields_to_mounted_musicviz() -> void:
	var ctx := RenderCtx.new()
	ctx.level = Fx.level()
	ctx.palette = Fx.palette()
	ctx.musicviz_mounted = true
	var a := FxAmbient.new()
	tree().root.add_child(a)
	a.build(ctx)
	assert_false(a.structural, "structural visuals left to musicviz")
	assert_eq(a.sigil_count, 0, "no fx sigils")
	assert_false(a.edge_built, "no fx edge display")
	a.update(Fx.music(2.0), 1.0, 1.0 / 60.0, null)
	a.queue_free()
	var b := FxAmbient.new()
	tree().root.add_child(b)
	ctx.musicviz_mounted = false
	b.build(ctx)
	assert_true(b.sigil_count > 0 and b.edge_built, "without musicviz the fx ambient draws its own")
	b.queue_free()
