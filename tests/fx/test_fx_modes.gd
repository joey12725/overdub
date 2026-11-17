extends ODTest
## Mode gating and the continuous treatments (port of prototype/tests/render-fx/modes.test.ts).

const Fx := preload("res://tests/fx/fx_fixtures.gd")


## Play about 4 seconds of a busy encounter: every event type, several powers, beats and chord changes.
func _play_busy(mode: StringName, world_rate: float = 1.0) -> Array:
	var d := Fx.director()
	var seen := {}
	for f: int in 240:
		var beat := f * (2.0 / 60.0) * world_rate
		var evs: Array[SimEvent] = []
		if f % 10 == 0:
			var i := 0
			for t: StringName in SimEventType.ALL:
				evs.append(Fx.event_of(t, 5.0 + ((f + i) % 6) * 12.0, (i + f) % 4))
				i += 1
		d.update(Fx.frame(mode, beat, evs, world_rate))
		for tg: int in Fx.live_tags(d):
			seen[tg] = true
	return [d, seen]


func test_record_never_spawns_cinematic_or_review_effects() -> void:
	var r := _play_busy(ViewMode.RECORD, 0.5)
	var d: FxDirector = r[0]
	var seen: Dictionary = r[1]
	var cine := Fx.tier_tags(FxCatalog.TIER_CINEMATIC)
	cine.append(FxDirector.TAG_CINE_CONTINUOUS)
	var review := Fx.tier_tags(FxCatalog.TIER_REVIEW)
	for tg: Variant in seen:
		assert_false(cine.has(tg), "cinematic tag %s spawned in record" % tg)
		assert_false(review.has(tg), "review tag %s spawned in record" % tg)
	for i: int in FxCatalog.EFFECT_IDS.size():
		if FxCatalog.EFFECT_TIER[FxCatalog.EFFECT_IDS[i]] != FxCatalog.TIER_CORE:
			assert_eq(d.spawn_counts[i], 0, "%s ran in record" % FxCatalog.EFFECT_IDS[i])
	assert_eq(d.screen.letterbox, 0.0, "no letterbox while recording")
	assert_true(d.screen.sweep_a < 0.001, "no light sweep while recording")
	assert_eq(d.focus_w, 0.0, "no focus requests while recording")
	assert_eq(d.screen.burst_amt, 0.0, "no radial speed-line burst while recording")
	assert_eq(d.chord_flashes, 0, "no chord flashes while recording")
	for t: int in 4:
		assert_eq(d.ribbons.count[t], 0, "no ribbon for tape %d while recording" % t)
	assert_true(d.shake_out <= 0.55 + 1e-6, "record shake is restrained")
	assert_true(seen.has(FxDirector.TAG_WORLD_SPEED), "a 0.5x world still shows the world-speed cue in record")


func test_review_allows_texture_but_no_cinematic_flourishes() -> void:
	var r := _play_busy(ViewMode.REVIEW)
	var d: FxDirector = r[0]
	var seen: Dictionary = r[1]
	var cine := Fx.tier_tags(FxCatalog.TIER_CINEMATIC)
	cine.append(FxDirector.TAG_CINE_CONTINUOUS)
	for tg: Variant in seen:
		assert_false(cine.has(tg), "cinematic tag %s spawned in review" % tg)
	assert_true(d.spawn_counts[FxCatalog.effect_index(FxCatalog.STEP_DUST)] > 0, "review shows step dust")
	assert_eq(d.spawn_counts[FxCatalog.effect_index(FxCatalog.INK_SPLASH)], 0, "no ink splash in review")
	assert_eq(d.screen.letterbox, 0.0, "no letterbox in review")


func test_idle_shows_no_event_effects() -> void:
	var r := _play_busy(ViewMode.IDLE)
	var d: FxDirector = r[0]
	var seen: Dictionary = r[1]
	assert_eq(seen.size(), 0, "idle spawned sprites")
	assert_eq(d.glow.count() + d.ink.count() + d.text.count(), 0, "idle pools are empty")
	var total := 0
	for c: int in d.spawn_counts:
		total += c
	assert_eq(total, 0, "idle ran no effects")


func test_cinematic_adds_flourishes() -> void:
	var r := _play_busy(ViewMode.CINEMATIC)
	var d: FxDirector = r[0]
	var seen: Dictionary = r[1]
	assert_true(d.spawn_counts[FxCatalog.effect_index(FxCatalog.INK_SPLASH)] > 0, "ink splash")
	assert_true(d.spawn_counts[FxCatalog.effect_index(FxCatalog.FINALE_BURST)] > 0, "finale")
	assert_true(d.screen.letterbox > 0.07, "letterbox eased in (%f)" % d.screen.letterbox)
	assert_true(seen.has(FxDirector.TAG_CINE_CONTINUOUS), "beat ripples")
	assert_true(d.ribbons.count[0] > 10, "tape A ribbon has points")
	assert_true(d.focus_w > 0.0, "focus request")
	assert_true(d.chord_flashes > 0, "chord-change palette flashes")
	assert_true(d.screen.sweep_a > 0.0, "bar-synced sweep")


func test_effect_allowed_agrees_with_the_tiers() -> void:
	for id: StringName in FxCatalog.EFFECT_IDS:
		assert_false(FxCatalog.effect_allowed(id, ViewMode.IDLE), "%s allowed in idle" % id)
		assert_true(FxCatalog.effect_allowed(id, ViewMode.CINEMATIC), "%s not allowed in cinematic" % id)
		assert_eq(FxCatalog.effect_allowed(id, ViewMode.RECORD), FxCatalog.EFFECT_TIER[id] == FxCatalog.TIER_CORE, "%s in record" % id)
		assert_eq(FxCatalog.effect_allowed(id, ViewMode.REVIEW), FxCatalog.EFFECT_TIER[id] <= FxCatalog.TIER_REVIEW, "%s in review" % id)


func test_world_speed_treatment_from_world_rate() -> void:
	var slow := Fx.director()
	var fast := Fx.director()
	var normal := Fx.director()
	for f: int in 120:
		slow.update(Fx.frame(ViewMode.RECORD, f / 60.0, [], 0.5))
		fast.update(Fx.frame(ViewMode.RECORD, f / 60.0, [], 2.0))
		normal.update(Fx.frame(ViewMode.RECORD, f / 60.0, [], 1.0))
	assert_true(slow.world_speed < -0.3, "recording a 2x tape (world 0.5) reads as slowed: %f" % slow.world_speed)
	assert_true(fast.world_speed > 0.3, "recording a 0.5x tape (world 2) reads as sped up: %f" % fast.world_speed)
	assert_eq(slow.screen.speed_sign, -1.0, "slow sign")
	assert_eq(fast.screen.speed_sign, 1.0, "fast sign")
	assert_true(slow.screen.tint_a > 0.0, "slow tint")
	# Readability: the tint stays faint.
	assert_true(fast.screen.tint_a < 0.1, "tint stays faint")
	assert_eq(normal.screen.tint_a, 0.0, "no tint at 1x")
	assert_eq(normal.screen.speed, 0.0, "no speed lines at 1x")


func test_steady_state_pools_never_grow() -> void:
	var d := Fx.director()
	var caps := [d.glow.capacity, d.ink.capacity, d.text.capacity]
	var sizes := [d.glow.pos.size(), d.ink.pos.size(), d.text.pos.size()]
	for f: int in 600:
		d.update(Fx.frame(ViewMode.CINEMATIC, f / 30.0, Fx.all_events(60.0)))
		if d.glow.count() > d.glow.capacity or d.ink.count() > d.ink.capacity or d.text.count() > d.text.capacity:
			fail("a pool exceeded capacity at frame %d" % f)
			return
	assert_true(d.glow.count() <= d.glow.capacity, "glow within capacity")
	assert_true(d.ink.count() <= d.ink.capacity, "ink within capacity")
	assert_true(d.text.count() <= d.text.capacity, "text within capacity")
	assert_eq([d.glow.capacity, d.ink.capacity, d.text.capacity], caps, "capacities unchanged")
	assert_eq([d.glow.pos.size(), d.ink.pos.size(), d.text.pos.size()], sizes, "buffers never resized")
	assert_true(d.glow.count() > d.glow.capacity / 2, "the flood actually filled the glow pool")


func test_words_per_frame_budget() -> void:
	var d := Fx.director()
	var evs: Array[SimEvent] = []
	for i: int in 40:
		evs.append(Fx.event_of(SimEventType.KILL, 60.0, i % 4))
	d.update(Fx.frame(ViewMode.CINEMATIC, 1.0, evs))
	assert_true(d.text.count() <= FxDirector.WORDS_PER_FRAME, "at most %d new readouts per frame" % FxDirector.WORDS_PER_FRAME)


func test_low_quality_halves_particle_pools() -> void:
	var e := Fx.env()
	e.quality = WorldViewBase.QUALITY_LOW
	var d := FxDirector.new(e)
	assert_eq(d.glow.capacity, FxDirector.GLOW_CAPACITY >> 1, "glow halved")
	assert_eq(d.ink.capacity, FxDirector.INK_CAPACITY >> 1, "ink halved")


func test_letterbox_eases_out_after_cinematic() -> void:
	var d := Fx.director()
	for f: int in 180:
		d.update(Fx.frame(ViewMode.CINEMATIC, f / 30.0))
	assert_true(d.screen.letterbox > 0.08, "letterbox in")
	d.update(Fx.frame(ViewMode.IDLE, 7.0))
	assert_true(d.screen.letterbox > 0.0, "eases, does not snap")
	for f: int in 400:
		d.update(Fx.frame(ViewMode.IDLE, 7.0 + f / 30.0))
	assert_eq(d.screen.letterbox, 0.0, "letterbox gone")
