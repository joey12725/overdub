extends ODTest
## Fixed-capacity pools (port of prototype/tests/render-fx/pool.test.ts).


func test_sprite_pool_never_grows_and_recycles() -> void:
	var pool := FxSpritePool.new(32)
	for _i: int in 100:
		var s := pool.spawn(1)
		assert_true(s >= 0 and s < 32, "slot in range")
		pool.life[s] = 1.0
	assert_eq(pool.count(), 32, "full")
	assert_eq(pool.pos.size(), 32, "no growth")


func test_sprite_pool_reuses_freed_slot_before_stealing() -> void:
	var pool := FxSpritePool.new(4)
	var a := pool.spawn(0)
	pool.spawn(0)
	pool.kill(a)
	assert_eq(pool.count(), 1, "one live")
	assert_eq(pool.spawn(0), a, "freed slot reused")
	assert_eq(pool.count(), 2, "two live")


func test_sprite_pool_steals_the_one_closest_to_vanishing() -> void:
	var pool := FxSpritePool.new(3)
	var ages := [0.1, 0.9, 0.5]
	for i: int in 3:
		var s := pool.spawn(0)
		pool.life[s] = 1.0
		pool.age[s] = ages[i]
	var stolen := pool.spawn(7)
	assert_eq(stolen, 1, "stole the oldest")
	assert_eq(pool.tag[stolen], 7, "retagged")
	assert_eq(pool.age[stolen], 0.0, "reset")
	assert_eq(pool.count(), 3, "count unchanged")


func test_sprite_pool_expires_and_frees() -> void:
	var pool := FxSpritePool.new(8)
	for _i: int in 8:
		pool.life[pool.spawn(0)] = 0.2
	pool.update(0.1)
	assert_eq(pool.count(), 8, "alive")
	pool.update(0.15)
	assert_eq(pool.count(), 0, "expired")
	for _i: int in 8:
		pool.spawn(0)
	assert_eq(pool.count(), 8, "refilled")


func test_sprite_pool_hit_stop_freezes_then_resumes() -> void:
	var pool := FxSpritePool.new(2)
	var s := pool.spawn(0)
	pool.life[s] = 1.0
	pool.vel[s] = Vector3(10.0, 0.0, 0.0)
	pool.freeze[s] = 0.05
	pool.update(0.04)
	assert_eq(pool.pos[s].x, 0.0, "frozen")
	assert_eq(pool.age[s], 0.0, "age held")
	pool.update(0.02)
	pool.update(0.1)
	assert_true(pool.pos[s].x > 0.5, "moving again")


func test_sprite_pool_delayed_sprites_invisible_until_born() -> void:
	var pool := FxSpritePool.new(2)
	var s := pool.spawn(0)
	pool.life[s] = 1.0
	pool.age[s] = -0.2
	var buf := PackedFloat32Array()
	buf.resize(2 * FxSpritePool.STRIDE)
	assert_eq(pool.write_instances(buf), 0, "delayed")
	pool.update(0.25)
	assert_eq(pool.write_instances(buf), 1, "born")


func test_sprite_pool_packs_shape_and_mode() -> void:
	var pool := FxSpritePool.new(1)
	var s := pool.spawn(0)
	pool.shape[s] = 7
	pool.mode[s] = 2
	pool.life[s] = 1.0
	pool.pos[s] = Vector3(1.0, 2.0, 3.0)
	var buf := PackedFloat32Array()
	buf.resize(FxSpritePool.STRIDE)
	pool.write_instances(buf)
	assert_eq(buf[10], 7.0 + 64.0, "shape + 32 * mode")
	assert_eq([buf[3], buf[7], buf[11]], [1.0, 2.0, 3.0], "position in the transform origin")


func test_floor_bounce() -> void:
	var pool := FxSpritePool.new(1)
	var s := pool.spawn(0)
	pool.life[s] = 5.0
	pool.pos[s] = Vector3(0.0, 1.0, 0.0)
	pool.gravity[s] = 20.0
	pool.floor_y[s] = 0.05
	for _i: int in 60:
		pool.update(1.0 / 60.0)
		assert_true(pool.pos[s].y >= 0.05 - 1e-6, "never sinks through the floor")
		if assertion_count() > 70:
			break


func test_text_pool_never_grows_and_recycles() -> void:
	var pool := FxTextPool.new(6)
	for i: int in 40:
		pool.life[pool.spawn(0, i % 5)] = 1.0
	assert_eq(pool.count(), 6, "full")
	pool.update(2.0)
	assert_eq(pool.count(), 0, "expired")


func test_text_pool_pops_and_settles() -> void:
	var pool := FxTextPool.new(1)
	var s := pool.spawn(0, 1)
	pool.height[s] = 1.0
	pool.life[s] = 2.0
	pool.pop[s] = 0.6
	assert_near(pool.display_height(s), 1.6, 1e-5, "pop at birth")
	pool.update(0.6)
	assert_true(absf(pool.display_height(s) - 1.0) < 0.01, "settled")


# ───────────────────────────── readout legibility ─────────────────────────────

const Fx := preload("res://tests/fx/fx_fixtures.gd")


func _hit_at(x: float, y: float, power: float) -> SimEvent:
	return SimEvent.make(100, SimEventType.HIT, x, y).with_tape(0).with_dir(0.0).with_power(power)


func _live_words(d: FxDirector) -> Array[int]:
	var out: Array[int] = []
	for i: int in d.text.capacity:
		if d.text.alive[i] != 0:
			out.append(i)
	return out


func test_same_word_at_same_spot_repops_instead_of_doubling() -> void:
	var d := Fx.director()
	var evs: Array[SimEvent] = [_hit_at(4.0, 2.5, 50.0)]
	d.update(Fx.frame(ViewMode.CINEMATIC, 1.0, evs))
	var first := _live_words(d)
	assert_eq(first.size(), 1, "one tier word")
	# Same word, same place, next frame.
	evs = [_hit_at(4.1, 2.5, 50.0)]
	d.update(Fx.frame(ViewMode.CINEMATIC, 1.02, evs))
	var second := _live_words(d)
	assert_eq(second.size(), 1, "still one readout")
	assert_eq(second[0], first[0], "the existing readout was refreshed")
	assert_true(d.text.age[second[0]] < 0.05, "re-popped (age reset)")


func test_different_words_never_overlap() -> void:
	var d := Fx.director()
	# A light tap then a heavy blow on one spot: two different words.
	var evs: Array[SimEvent] = [_hit_at(4.0, 2.5, 9.0)]
	d.update(Fx.frame(ViewMode.CINEMATIC, 1.0, evs))
	evs = [_hit_at(4.0, 2.5, 50.0)]
	d.update(Fx.frame(ViewMode.CINEMATIC, 1.02, evs))
	var live := _live_words(d)
	assert_eq(live.size(), 2, "two different readouts")
	var a := live[0]
	var b := live[1]
	assert_ne(d.text.word[a], d.text.word[b], "different words")
	var gap := absf(d.text.pos[a].y - d.text.pos[b].y)
	var need := minf(d.text.height[a], d.text.height[b])
	assert_true(gap >= need, "stacked apart vertically (gap %.3f >= %.3f)" % [gap, need])
