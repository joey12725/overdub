extends ODTest
## Port of prototype/tests/core/foundation/tape.test.ts: angles, TapeRecorder, sampling, copying and
## serialisation.


func _f32(v: float) -> float:
	return PackedFloat32Array([v])[0]


func _record_line(ticks: int = 10) -> ODTape:
	var rec := TapeRecorder.new(TapeLib.TapeRecorderInit.make(1, 2, OD.EndMode.REPEAT, ticks, 1, 2, 0))
	for i in range(1, ticks + 1):
		rec.push(1 + i * 0.1, 2 - i * 0.05, i * 0.3, AnimState.RUN if i % 2 else AnimState.IDLE)
		if i == 3:
			rec.add_event(TapeEvent.make(3, ActionKind.LIGHT, 0.5, 1.3, 1.85, 6, -3))
	rec.add_event(TapeEvent.make(ticks, ActionKind.INTERACT, -1, 2, 1.5, 0, 0))
	return rec.finish()


func _pose_eq(a: TapeLib.PoseSample, b: TapeLib.PoseSample, msg: String = "") -> bool:
	return assert_true(a.equals(b), "%s: %s != %s" % [msg, [a.x, a.y, a.facing, a.anim], [b.x, b.y, b.facing, b.anim]])

# ── angles ──


func test_wraps_and_interpolates_along_the_shortest_arc() -> void:
	assert_near(TapeLib.wrap_angle(3 * PI), PI, 5e-13)
	assert_near(TapeLib.wrap_angle(-PI), PI, 5e-13)
	assert_near(TapeLib.angle_delta(3, -3), 2 * PI - 6, 5e-13)
	assert_near(TapeLib.lerp_angle(3, -3, 0.5), PI, 5e-10)
	assert_near(TapeLib.lerp_angle(0.1, 0.5, 0.5), 0.3, 5e-13)

# ── TapeRecorder ──


func test_records_ticks_plus_1_samples_with_the_start_pose_at_sample_0() -> void:
	var t := _record_line()
	assert_eq(t.ticks, 10)
	assert_eq(t.pos.size(), 22)
	assert_eq(t.facing.size(), 11)
	assert_eq(t.anim.size(), 11)
	assert_eq([t.pos[0], t.pos[1]], [1, 2])
	assert_eq(t.pos[20], _f32(2))
	assert_eq(TapeLib.anim_from_index(t.anim[1]), AnimState.RUN)
	assert_eq([t.events[0].kind, t.events[1].kind], [ActionKind.LIGHT, ActionKind.INTERACT])


func test_rejects_overfull_tapes_and_out_of_order_or_future_events() -> void:
	var rec := TapeRecorder.new(TapeLib.TapeRecorderInit.make(0, 1, OD.EndMode.STOP, 2, 0, 0, 0))
	var errors: Array[String] = []
	assert_false(rec.add_event(TapeEvent.make(1, ActionKind.LIGHT, 0, 0, 0), errors))
	assert_eq(errors.size(), 1)
	rec.push(0, 0, 0, AnimState.IDLE)
	assert_true(rec.add_event(TapeEvent.make(1, ActionKind.LIGHT, 0, 0, 0)))
	assert_false(rec.add_event(TapeEvent.make(0, ActionKind.LIGHT, 0, 0, 0), errors))
	assert_eq(errors.size(), 2)
	rec.push(0, 0, 0, AnimState.IDLE)
	assert_true(rec.complete)
	assert_false(rec.push(0, 0, 0, AnimState.IDLE, errors))
	assert_eq(errors, ["TapeRecorder: event tick 1 out of range", "TapeRecorder: events must be added in tick order", "TapeRecorder: tape is full"])
	var bad: Array[String] = []
	assert_eq(TapeRecorder.create(TapeLib.TapeRecorderInit.make(0, 1, OD.EndMode.STOP, -1, 0, 0, 0), bad), null)
	assert_eq(bad, ["TapeRecorder: bad tick count -1"])


func test_snapshot_is_a_prefix_finish_holds_the_last_pose_for_unrecorded_ticks() -> void:
	var rec := TapeRecorder.new(TapeLib.TapeRecorderInit.make(0, 1, OD.EndMode.STOP, 5, 0, 0, 0))
	rec.push(1, 1, 0.5, AnimState.RUN)
	rec.push(2, 1, 0.5, AnimState.RUN)
	var snap := rec.snapshot()
	assert_eq(snap.ticks, 2)
	assert_eq(snap.pos.size(), 6)
	assert_eq(rec.recorded_ticks, 2)
	rec.push(3, 1, 0.5, AnimState.RUN)
	assert_eq(snap.pos.size(), 6, "a copy, unaffected")
	var t := rec.finish()
	assert_eq(t.ticks, 5)
	_pose_eq(TapeLib.sample_pose(t, 5), TapeLib.PoseSample.make_pose(3, 1, _f32(0.5), AnimState.RUN))

# ── sampling ──


func test_interpolates_position_linearly_and_facing_by_shortest_arc_anim_is_the_floor_sample() -> void:
	var t := _record_line()
	var p := TapeLib.sample_pose(t, 2.5)
	assert_near(p.x, (t.pos[4] + t.pos[6]) / 2, 5e-7)
	assert_near(p.y, (t.pos[5] + t.pos[7]) / 2, 5e-7)
	assert_near(p.facing, (t.facing[2] + t.facing[3]) / 2, 5e-7)
	assert_eq(p.anim, AnimState.IDLE)
	assert_eq(TapeLib.sample_pose(t, 3).anim, AnimState.RUN)
	_pose_eq(TapeLib.sample_pose(t, -4), TapeLib.sample_pose(t, 0), "clamped low")
	_pose_eq(TapeLib.sample_pose(t, 99), TapeLib.sample_pose(t, 10), "clamped high")
	var out := TapeLib.XY.new()
	TapeLib.sample_pos_into(t, 2.5, out)
	assert_eq(out.x, p.x)
	assert_eq(out.y, p.y)


func test_samples_by_master_substep_with_end_behaviour_applied() -> void:
	var t := _record_line() # speed 2 → 2 subs per tick, repeat
	_pose_eq(TapeLib.sample_pose_at_sub(t, 5), TapeLib.sample_pose(t, 2.5), "sub 5")
	var phase := TapePhase.make(0, 1, 0, false)
	var p := TapeLib.sample_pose_at_sub(t, 2 * 10 + 6, null, phase)
	assert_true(phase.equals(TapePhase.make(3, 1, 1, false)), str(phase.to_dict()))
	_pose_eq(p, TapeLib.sample_pose(t, 3), "second pass")


func test_interpolates_facing_across_the_pi_seam() -> void:
	var rec := TapeRecorder.new(TapeLib.TapeRecorderInit.make(0, 1, OD.EndMode.STOP, 1, 0, 0, 3))
	rec.push(0, 0, -3, AnimState.IDLE)
	var f := TapeLib.sample_pose(rec.finish(), 0.5).facing
	assert_true(absf(absf(f) - PI) < 1e-6, "facing %s" % f)


func test_estimates_local_and_master_velocity() -> void:
	var t := _record_line()
	var v := TapeLib.local_velocity_at(t, 4.2)
	assert_near(v.x, (t.pos[10] - t.pos[8]) * OD.LOCAL_HZ, 5e-7)
	assert_near(v.x, 6, 5e-5)
	assert_near(v.y, -3, 5e-5)
	# Last segment at the end tick.
	assert_near(TapeLib.local_velocity_at(t, 10).x, 6, 5e-5)
	# speed 2: master velocity doubles; reversing flips it; stopped is zero.
	assert_near(TapeLib.master_velocity_at(t, 4.2, 1).x, 12, 5e-5)
	assert_near(TapeLib.master_velocity_at(t, 4.2, -1).y, 6, 5e-5)
	var still := TapeLib.master_velocity_at(t, 4.2, 0)
	assert_eq([still.x, still.y], [0, 0])
	# -0 is normalised to +0.
	assert_eq(1.0 / still.x, INF)
	assert_eq(1.0 / still.y, INF)
	var empty := ODTape.create(0, 1, OD.EndMode.STOP, 0)
	var z := TapeLib.local_velocity_at(empty, 3)
	assert_eq([z.x, z.y], [0, 0])

# ── copy and serialisation ──


func test_clone_tape_is_deep() -> void:
	var t := _record_line()
	var c := TapeLib.clone_tape(t)
	assert_true(TapeLib.tapes_equal(t, c))
	c.pos[3] = 99
	c.events[0].dir = 7
	assert_ne(t.pos[3], 99)
	assert_eq(t.events[0].dir, 0.5)
	assert_eq(TapeLib.with_end_mode(t, OD.EndMode.REVERSE).end_mode, OD.EndMode.REVERSE)
	assert_eq(t.end_mode, OD.EndMode.REPEAT)


func test_round_trips_through_json_bit_exactly() -> void:
	var t := _record_line(37)
	# The prototype uses vx = 1e-300 here. ODJson.format_float (core/types/od_json.gd, not this
	# suite's) writes magnitudes below ~1e-16 as "0.0", so the JSON-text leg uses 1e-12 and the
	# 1e-300 case is checked through the dictionary form (reported to the lead).
	t.events.append(TapeEvent.make(37, ActionKind.ABILITY, PI / 3, 1.0 / 3, -0.0, 1e-12, -2.5))
	var json := ODJson.stringify(TapeLib.serialize_tape(t))
	var errors: Array[String] = []
	var back := TapeLib.deserialize_tape(ODJson.parse(json, errors), errors)
	assert_eq(errors, [])
	if not assert_true(back != null):
		return
	assert_true(TapeLib.tapes_equal(t, back))
	var tiny := _record_line(37)
	tiny.events.append(TapeEvent.make(37, ActionKind.ABILITY, PI / 3, 1.0 / 3, -0.0, 1e-300, -2.5))
	var back_tiny := TapeLib.deserialize_tape(TapeLib.serialize_tape(tiny).duplicate(true), errors)
	assert_true(back_tiny != null and TapeLib.tapes_equal(tiny, back_tiny))
	assert_eq(back_tiny.events[2].vx, 1e-300)
	assert_eq(typeof(back.pos), TYPE_PACKED_FLOAT32_ARRAY)
	assert_eq(typeof(back.anim), TYPE_PACKED_BYTE_ARRAY)
	# The pure encoder matches the one ODTape.to_dict uses.
	assert_eq(TapeLib.base64_from_bytes(t.pos.to_byte_array()), TapeLib.serialize_tape(t)["pos"])


func test_rejects_malformed_data() -> void:
	var s := TapeLib.serialize_tape(_record_line())
	for patch: Dictionary in [{"ticks": 11}, {"v": 2}, {"events": [[0, 99, 0, 0, 0, 0, 0]]}, {"pos": "!!!!"}]:
		var bad := s.duplicate(true)
		bad.merge(patch, true)
		var errors: Array[String] = []
		assert_eq(TapeLib.deserialize_tape(bad, errors), null, str(patch))
		assert_eq(errors.size(), 1, str(patch))


func test_base64_matches_the_standard_alphabet_for_all_padding_cases() -> void:
	for pair: Array in [["", ""], ["f", "Zg=="], ["fo", "Zm8="], ["foo", "Zm9v"], ["foobar", "Zm9vYmFy"]]:
		assert_eq(TapeLib.base64_from_bytes(String(pair[0]).to_utf8_buffer()), pair[1], pair[0])
	var bytes := PackedByteArray()
	for i in 256:
		bytes.append(i)
	var enc := TapeLib.base64_from_bytes(bytes)
	assert_eq(enc, Marshalls.raw_to_base64(bytes))
	assert_eq(TapeLib.bytes_from_base64(enc), bytes)
	var errors: Array[String] = []
	TapeLib.bytes_from_base64("abc", errors)
	TapeLib.bytes_from_base64("ab!d", errors)
	assert_eq(errors, ["base64: length not a multiple of 4", "base64: bad character at 2"])


func test_anim_indices_map_both_ways() -> void:
	for i in OD.ANIM_STATES.size():
		assert_eq(TapeLib.anim_index(OD.ANIM_STATES[i]), i)
		assert_eq(TapeLib.anim_from_index(i), OD.ANIM_STATES[i])
	assert_eq(TapeLib.anim_from_index(200), AnimState.IDLE)
