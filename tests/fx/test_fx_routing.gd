extends ODTest
## Event -> effect routing (port of prototype/tests/render-fx/routing.test.ts).

const Fx := preload("res://tests/fx/fx_fixtures.gd")


func test_every_sim_event_type_has_a_route() -> void:
	assert_true(SimEventType.ALL.size() > 20, "SimEventType.ALL looks truncated")
	var missing: Array[String] = []
	for t: StringName in SimEventType.ALL:
		if not FxCatalog.EVENT_ROUTES.has(t):
			missing.append(String(t))
	assert_eq(missing, [], "SimEventTypes without an fx route: %s" % ", ".join(missing))
	var stale: Array[String] = []
	for t: StringName in FxCatalog.EVENT_ROUTES:
		if not SimEventType.has(t):
			stale.append(String(t))
	assert_eq(stale, [], "fx routes for event types that no longer exist: %s" % ", ".join(stale))


func test_every_route_names_known_effects_and_every_effect_is_reachable() -> void:
	var used := {}
	for t: StringName in FxCatalog.EVENT_ROUTES:
		var effects: Array = FxCatalog.EVENT_ROUTES[t]
		assert_true(effects.size() > 0, "%s has an empty route" % t)
		for id: Variant in effects:
			assert_true(FxCatalog.EFFECT_IDS.has(id), "%s -> unknown effect %s" % [t, id])
			used[id] = true
	for id: StringName in FxCatalog.EFFECT_IDS:
		assert_true(FxCatalog.EFFECT_TIER.has(id), "%s has no tier" % id)
		assert_true(used.has(id), "effect %s is never triggered" % id)
	assert_eq(FxCatalog.EFFECT_TIER.size(), FxCatalog.EFFECT_IDS.size(), "tier table size")
	assert_true(FxCatalog.EFFECT_IDS.size() < FxDirector.TAG_WORLD_SPEED, "effect tags must stay below the continuous tags")


func test_every_event_has_a_non_cinematic_tell() -> void:
	# Cinematic flourishes must be extra, never the only feedback (MUSIC-13: readability while recording).
	for t: StringName in FxCatalog.EVENT_ROUTES:
		if t == SimEventType.STEP:
			continue
		var has_core := false
		for id: Variant in FxCatalog.EVENT_ROUTES[t]:
			if FxCatalog.EFFECT_TIER[id] == FxCatalog.TIER_CORE:
				has_core = true
		assert_true(has_core, "%s has no core-tier tell" % t)


func test_every_effect_runs_in_cinematic_and_spawns_something() -> void:
	for t: StringName in SimEventType.ALL:
		var d := Fx.director()
		d.update(Fx.frame(ViewMode.CINEMATIC, 4.2, [Fx.event_of(t, 40.0)]))
		var sprites := d.glow.count() + d.ink.count() + d.text.count()
		var scr := d.screen.burst_amt + d.screen.flash_a + d.screen.glitch + d.focus_w
		assert_true(sprites + scr > 0.0, "%s produced nothing" % t)
		for id: Variant in FxCatalog.EVENT_ROUTES[t]:
			assert_true(d.spawn_counts[FxCatalog.effect_index(id)] > 0, "%s -> %s never ran" % [t, id])


func test_events_with_missing_optional_fields_are_tolerated() -> void:
	var d := Fx.director()
	var evs: Array[SimEvent] = []
	var i := 0
	for t: StringName in SimEventType.ALL:
		evs.append(SimEvent.make(i, t, 3.0, 3.0))
		i += 1
	d.update(Fx.frame(ViewMode.CINEMATIC, 2.0, evs))
	var finite := true
	for k: int in d.glow.capacity:
		var p := d.glow.pos[k]
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			finite = false
	assert_true(finite, "sprite positions stay finite")
	assert_true(d.glow.count() > 0, "events without optional fields still draw")


func test_unknown_event_type_is_ignored() -> void:
	var d := Fx.director()
	d.update(Fx.frame(ViewMode.CINEMATIC, 1.0, [SimEvent.make(0, &"fromTheFuture", 1.0, 1.0)]))
	var total := 0
	for c: int in d.spawn_counts:
		total += c
	assert_eq(total, 0, "an unknown event type spawns nothing")


func test_clang_is_clearly_different_from_a_hit() -> void:
	# Scenario K: a blow without enough momentum must never read as a real hit.
	var hit := Fx.director()
	hit.update(Fx.frame(ViewMode.RECORD, 1.0, [Fx.event_of(SimEventType.HIT, 30.0)]))
	var clang := Fx.director()
	clang.update(Fx.frame(ViewMode.RECORD, 1.0, [Fx.event_of(SimEventType.CLANG, 30.0)]))
	var frozen_clang := 0
	for i: int in clang.glow.capacity:
		if clang.glow.alive[i] != 0:
			if clang.glow.freeze[i] > 0.0:
				frozen_clang += 1
			var c := clang.glow.color[i]
			assert_true(absf(c.r - c.g) < 0.1 and absf(c.g - c.b) < 0.1, "clang sprites are grey")
	assert_eq(frozen_clang, 0, "clang never gets the hit-stop freeze")
	var frozen_hit := 0
	for i: int in hit.glow.capacity:
		if hit.glow.alive[i] != 0 and hit.glow.freeze[i] > 0.0:
			frozen_hit += 1
	assert_true(frozen_hit > 0, "a real hit freezes its burst")
	assert_true(clang.shake_out == 0.0, "clang requests no shake")
	assert_true(hit.shake_out > 0.0, "a strong hit requests shake")


func test_shake_scales_with_power() -> void:
	var weak := Fx.director()
	weak.update(Fx.frame(ViewMode.REVIEW, 1.0, [Fx.event_of(SimEventType.HIT, 10.0)]))
	var strong := Fx.director()
	strong.update(Fx.frame(ViewMode.REVIEW, 1.0, [Fx.event_of(SimEventType.HIT, 50.0)]))
	assert_true(strong.shake_out > weak.shake_out, "harder hits shake more (%f vs %f)" % [strong.shake_out, weak.shake_out])
	assert_true(strong.shake_out <= 1.0, "shake stays within 0..1")


func test_boss_recall_tell_is_unmistakable() -> void:
	var d := Fx.director()
	d.update(Fx.frame(ViewMode.RECORD, 1.0, [Fx.event_of(SimEventType.BOSS_RECALL, 0.0, 2)]))
	assert_true(d.screen.glitch > 0.0, "recall tears the screen")
	var words: Array[int] = []
	for i: int in d.text.capacity:
		if d.text.alive[i] != 0:
			words.append(d.text.word[i])
	assert_has(words, FxWords.W_REMEMBERS, "REMEMBERS readout")
	assert_has(words, FxWords.W_TAPE_A + 2, "remembered tape letter")
	assert_eq(d.screen.glitch_color, OD.tape_color(2), "tear in the remembered tape's colour")
