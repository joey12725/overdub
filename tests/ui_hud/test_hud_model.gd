extends ODTest
## HUD view-model (port of prototype/tests/ui-hud/model.test.ts and ruler-geometry.test.ts) plus the
## Godot dock / deck layout rules (UI-01..07, NEW-07..11).

const BPM := 120.0 # 30 local ticks per beat at 1x
const BARS := 4.0
const M := preload("res://ui/hud/hud_model.gd")


func _marks(pairs: Array) -> Array[DeckMark]:
	var out: Array[DeckMark] = []
	for p: Array in pairs:
		out.append(DeckMark.make(int(p[0]), StringName(p[1])))
	return out


func _deck(status: StringName, end_mode: int, transport: int, progress: float, span_bars: float) -> DeckView:
	var d := DeckView.new()
	d.status = status
	d.end_mode = end_mode
	d.transport = transport
	d.local_progress = progress
	d.span_bars = span_bars
	d.speed = 1.0
	return d


# ───────────────────────────── tick → master beat (TIME-03) ─────────────────────────────

func test_time03_maps_local_tick_through_speed_at_every_speed() -> void:
	var ticks_per_beat := 60.0 * OD.LOCAL_HZ / BPM
	for s: float in OD.ALL_SPEEDS:
		assert_near(HudModel.local_tick_to_master_beat(ticks_per_beat, s, BPM), 1.0 / s, 1e-12, "speed %s" % s)
		assert_eq(HudModel.local_tick_to_master_beat(0, s, BPM), 0.0)
	assert_near(HudModel.local_tick_to_master_beat(90, 0.5, BPM), 6.0, 1e-9)
	assert_near(HudModel.local_tick_to_master_beat(90, 1.0, BPM), 3.0, 1e-9)
	assert_near(HudModel.local_tick_to_master_beat(90, 2.0, BPM), 1.5, 1e-9)
	assert_near(HudModel.local_tick_to_master_beat(90, 4.0, BPM), 0.75, 1e-9)


func test_time03_last_recorded_tick_lands_on_end_of_traversal() -> void:
	var ticks := HudModel.recording_ticks(BARS, BPM)
	assert_eq(ticks, 480)
	for s: float in OD.ALL_SPEEDS:
		assert_near(HudModel.local_tick_to_master_beat(ticks, s, BPM), HudModel.traversal_beats(BARS, s), 1e-9)
		assert_eq(HudModel.traversal_beats(BARS, s), BARS * OD.BEATS_PER_BAR / s)


func test_time03_non_power_of_two_tempo() -> void:
	assert_near(HudModel.local_tick_to_master_beat(40, 1.0, 90.0), 1.0, 1e-9)
	assert_near(HudModel.local_tick_to_master_beat(40, 2.0, 90.0), 0.5, 1e-9)


# ───────────────────────────── lane layout ─────────────────────────────

func _seg_tuples(l: HudModel.LaneLayout) -> Array:
	var out := []
	for s: HudModel.LaneSegment in l.segments:
		out.append([s.start, s.end, s.traversal, s.dir, s.partial])
	return out


func test_lane_stop_one_pass_then_hold() -> void:
	var l := HudModel.lane_layout(8, OD.EndMode.STOP, 32)
	assert_eq(_seg_tuples(l), [[0, 8, 0, 1, false]])
	assert_eq(l.hold_from, 8.0)


func test_lane_stop_no_hold_when_pass_reaches_horizon() -> void:
	assert_false(HudModel.lane_layout(32, OD.EndMode.STOP, 32).has_hold())
	var longer := HudModel.lane_layout(40, OD.EndMode.STOP, 32)
	assert_eq(_seg_tuples(longer), [[0, 32, 0, 1, true]])
	assert_false(longer.has_hold())


func test_lane_repeat_tiles_horizon_forward() -> void:
	var l := HudModel.lane_layout(8, OD.EndMode.REPEAT, 32)
	assert_eq(_seg_tuples(l), [[0, 8, 0, 1, false], [8, 16, 1, 1, false], [16, 24, 2, 1, false], [24, 32, 3, 1, false]])
	assert_false(l.has_hold())


func test_lane_reverse_ping_pong_last_pass_cut() -> void:
	var l := HudModel.lane_layout(12, OD.EndMode.REVERSE, 32)
	assert_eq(_seg_tuples(l), [[0, 12, 0, 1, false], [12, 24, 1, -1, false], [24, 32, 2, 1, true]])


func test_lane_degenerate_spans_terminate() -> void:
	assert_eq(HudModel.lane_layout(0, OD.EndMode.REPEAT, 32).segments.size(), 0)
	assert_eq(HudModel.lane_layout(8, OD.EndMode.REPEAT, 0).segments.size(), 0)
	assert_true(HudModel.lane_layout(1e-6, OD.EndMode.REPEAT, 32).segments.size() <= 512)


# ───────────────────────────── marks ─────────────────────────────

func test_marks_stop_places_once() -> void:
	var marks := _marks([[30, "light"], [150, "heavy"]])
	var l := HudModel.lane_layout(HudModel.traversal_beats(BARS, 1.0), OD.EndMode.STOP, 32)
	var p := HudModel.place_marks(marks, 1.0, BPM, l)
	assert_eq(p.size(), 2)
	assert_near(p[0].beat, 1.0, 1e-9)
	assert_eq(p[0].kind, ActionKind.LIGHT)
	assert_near(p[1].beat, 5.0, 1e-9)
	assert_eq(p[1].kind, ActionKind.HEAVY)


func test_marks_repeat_refire_every_pass_at_every_speed() -> void:
	var marks := _marks([[30, "light"], [150, "heavy"]])
	for s: float in OD.ALL_SPEEDS:
		var span := HudModel.traversal_beats(BARS, s)
		var l := HudModel.lane_layout(span, OD.EndMode.REPEAT, 32)
		var p := HudModel.place_marks(marks, s, BPM, l)
		var expected := 0
		for seg: HudModel.LaneSegment in l.segments:
			for m: DeckMark in marks:
				if seg.start + m.tick / 30.0 / s <= seg.end + 1e-9:
					expected += 1
		assert_eq(p.size(), expected, "speed %s" % s)
		for m: HudModel.PlacedMark in p:
			var local := m.beat - m.traversal * span
			assert_true(absf(local - 1.0 / s) < 1e-9 or absf(local - 5.0 / s) < 1e-9, "local beat %s at speed %s" % [local, s])
			assert_eq(m.dir, 1)


func test_marks_reverse_mirror_from_far_end() -> void:
	var marks := _marks([[30, "light"], [150, "heavy"]])
	var span := HudModel.traversal_beats(BARS, 2.0) # 8 master beats
	var l := HudModel.lane_layout(span, OD.EndMode.REVERSE, 32)
	var p := HudModel.place_marks(marks, 2.0, BPM, l)
	var first: Array[float] = []
	var second: Array[float] = []
	for m: HudModel.PlacedMark in p:
		if m.traversal == 0:
			first.append(m.beat)
		elif m.traversal == 1:
			second.append(m.beat)
			assert_eq(m.dir, -1)
	second.sort()
	assert_array_eq(first, [0.5, 2.5], "forward pass", 1e-9)
	assert_array_eq(second, [13.5, 15.5], "backward pass", 1e-9)


func test_marks_past_horizon_dropped() -> void:
	var marks := _marks([[30, "light"], [150, "heavy"]])
	var l := HudModel.lane_layout(16, OD.EndMode.REPEAT, 18)
	var p := HudModel.place_marks(marks, 1.0, BPM, l)
	var beats: Array[float] = []
	for m: HudModel.PlacedMark in p:
		beats.append(m.beat)
		assert_true(m.beat <= 18.0)
	assert_array_eq(beats, [1.0, 5.0, 17.0], "", 1e-9)


func test_marks_sorted_by_beat() -> void:
	var marks := _marks([[150, "heavy"], [30, "light"], [90, "dodge"]])
	var l := HudModel.lane_layout(16, OD.EndMode.STOP, 32)
	var p := HudModel.place_marks(marks, 1.0, BPM, l)
	assert_eq([p[0].kind, p[1].kind, p[2].kind], [ActionKind.LIGHT, ActionKind.DODGE, ActionKind.HEAVY])


func test_traversal_at_counts_passes() -> void:
	assert_eq(HudModel.traversal_at(0, 8), 0)
	assert_eq(HudModel.traversal_at(7.99, 8), 0)
	assert_eq(HudModel.traversal_at(8, 8), 1)
	assert_eq(HudModel.traversal_at(17, 8), 2)


# ───────────────────────────── status / state tables (NEW-08, NEW-11) ─────────────────────────────

func test_new08_every_status_has_own_word_and_icon() -> void:
	var labels := {}
	var icons := {}
	for s: StringName in DeckStatus.ALL:
		labels[HudModel.status_badge(s).label] = true
		icons[HudModel.status_badge(s).icon] = true
	assert_eq(labels.size(), DeckStatus.ALL.size())
	assert_eq(icons.size(), DeckStatus.ALL.size())
	assert_eq(HudModel.status_badge(DeckStatus.EMPTY).label, "NOT RECORDED")
	assert_eq(HudModel.status_badge(DeckStatus.PENDING).label, "TAKE — NOT COMMITTED")
	assert_eq(HudModel.status_badge(DeckStatus.COMMITTED).icon, HudModel.ICON_LOCK)
	assert_eq(HudModel.status_badge(DeckStatus.RECORDING).label, "RECORDING")
	var shorts := {}
	for s: StringName in DeckStatus.ALL:
		shorts[HudModel.status_badge(s).short] = true
	assert_eq(shorts.size(), DeckStatus.ALL.size(), "compact wording stays distinct")


func test_new11_every_status_life_sync_combination_distinct() -> void:
	var keys := {}
	var lives: Array[int] = [-1, OD.LifeState.ALIVE, OD.LifeState.REC_GHOST, OD.LifeState.GHOST]
	for s: StringName in DeckStatus.ALL:
		for l: int in lives:
			for sy: bool in [true, false]:
				if l == -1:
					assert_eq(HudModel.life_badge(l, sy), null, "no self, nothing extra")
					continue
				assert_ne(HudModel.life_badge(l, sy), null)
				var k := HudModel.presentation_key(s, l, sy)
				assert_false(keys.has(k), "%s/%s/%s collides with %s" % [s, l, sy, keys.get(k)])
				keys[k] = "%s/%s/%s" % [s, l, sy]
	assert_eq(keys.size(), DeckStatus.ALL.size() * 3 * 2)


func test_new11_life_states_word_and_icon() -> void:
	var words := {}
	var shorts := {}
	for l: int in [OD.LifeState.ALIVE, OD.LifeState.REC_GHOST, OD.LifeState.GHOST]:
		for sy: bool in [true, false]:
			words[HudModel.life_badge(l, sy).label] = true
			shorts[HudModel.life_badge(l, sy).short] = true
	assert_eq(words.size(), 6)
	assert_eq(shorts.size(), 6, "compact life words stay distinct")
	assert_eq(HudModel.life_badge(OD.LifeState.ALIVE, true).icon, HudModel.ICON_ALIVE)
	assert_eq(HudModel.life_badge(OD.LifeState.ALIVE, false).icon, HudModel.ICON_DESYNC)
	assert_eq(HudModel.life_badge(OD.LifeState.GHOST, true).icon, HudModel.ICON_GHOST)
	assert_eq(HudModel.life_badge(OD.LifeState.REC_GHOST, true).icon, HudModel.ICON_REC_GHOST)
	# A recording ghost is obviously distinct from a playback ghost (UI-03).
	assert_ne(HudModel.life_badge(OD.LifeState.REC_GHOST, true).label, HudModel.life_badge(OD.LifeState.GHOST, true).label)


func test_new11_transport_states() -> void:
	var c := DeckStatus.COMMITTED
	assert_eq(HudModel.transport_badge(_deck(c, OD.EndMode.REPEAT, 1, 0.4, 2), 2).label, "PLAYING")
	assert_eq(HudModel.transport_badge(_deck(c, OD.EndMode.REPEAT, 1, 0.4, 2), 9).label, "LOOPING · PASS 2")
	assert_eq(HudModel.transport_badge(_deck(c, OD.EndMode.REVERSE, -1, 0.4, 2), 9).label, "REVERSING · PASS 2")
	assert_eq(HudModel.transport_badge(_deck(c, OD.EndMode.REVERSE, 1, 0.4, 2), 17).label, "FORWARD · PASS 3")
	assert_eq(HudModel.transport_badge(_deck(c, OD.EndMode.STOP, 0, 1.0, 2), 12).label, "STOPPED — HOLDING POSE")
	assert_eq(HudModel.transport_badge(_deck(c, OD.EndMode.STOP, 0, 0.0, 2), 0).label, "CUED AT BEAT 0")
	assert_eq(HudModel.transport_badge(_deck(c, OD.EndMode.REPEAT, 0, 0.4, 2), 5).label, "PAUSED")
	assert_eq(HudModel.transport_badge(_deck(DeckStatus.EMPTY, -1, 0, 0.4, 2), 0), null)
	assert_eq(HudModel.transport_badge(_deck(DeckStatus.ARMED, OD.EndMode.STOP, 0, 0.4, 2), 0), null)
	var icons := {}
	icons[HudModel.transport_badge(_deck(c, OD.EndMode.REPEAT, 1, 0.4, 2), 9).icon] = true
	icons[HudModel.transport_badge(_deck(c, OD.EndMode.REVERSE, -1, 0.4, 2), 9).icon] = true
	icons[HudModel.transport_badge(_deck(c, OD.EndMode.STOP, 0, 1.0, 2), 12).icon] = true
	assert_eq(icons.size(), 3)


func test_new11_compact_deck_still_tells_stopped_looping_reversing_apart() -> void:
	var c := DeckStatus.COMMITTED
	var dl := _deck(c, OD.EndMode.REPEAT, 1, 0.4, 2)
	var dr := _deck(c, OD.EndMode.REVERSE, -1, 0.4, 2)
	var dh := _deck(c, OD.EndMode.STOP, 0, 1.0, 2)
	for d: DeckView in [dl, dr, dh]:
		d.life = OD.LifeState.ALIVE
	var looping := HudModel.deck_badges(dl, 9, SessionPhase.REVIEW, 3)
	var reversing := HudModel.deck_badges(dr, 9, SessionPhase.REVIEW, 3)
	var holding := HudModel.deck_badges(dh, 12, SessionPhase.REVIEW, 3)
	for rows: Array in [looping, reversing, holding]:
		assert_true(rows.size() <= 3)
	var last := {}
	for rows: Array in [looping, reversing, holding]:
		var b: HudModel.Badge = rows[rows.size() - 1]
		last[b.label] = b.icon
	assert_eq(last.size(), 3, "three distinct words")
	assert_true(String(looping[looping.size() - 1].label).contains("REPEAT"))
	assert_true(String(reversing[reversing.size() - 1].label).contains("REVERSE"))
	assert_true(String(holding[holding.size() - 1].label).contains("HOLD"))
	# Wide decks list end mode and transport separately.
	var wide := HudModel.deck_badges(dl, 9, SessionPhase.REVIEW, 4)
	assert_eq(wide.size(), 4)
	assert_eq(wide[1].label, "ALIVE")
	assert_eq(wide[2].label, "REPEAT")
	assert_eq(wide[3].label, "LOOPING · PASS 2")
	# Unavailable decks show only their status.
	assert_eq(HudModel.deck_badges(_deck(DeckStatus.UNAVAILABLE, -1, 0, 0, 0), 0, SessionPhase.SETUP, 4).size(), 1)


func test_end_modes_word_icon_explanation() -> void:
	var labels := {}
	var icons := {}
	for m: int in OD.ALL_END_MODES:
		var b := HudModel.end_mode_info(m)
		labels[b.label] = true
		icons[b.icon] = true
		assert_true(b.copy.length() > 10)
	assert_eq(labels.size(), 3)
	assert_eq(icons.size(), 3)


# ───────────────────────────── speed copy (UI-05, UI-07) ─────────────────────────────

func test_ui05_speed_consequence_lines() -> void:
	assert_eq(HudModel.speed_consequence(2.0), "2× — this take plays back in half the time and hits twice as hard; the world runs at half speed while you record")
	var half := HudModel.speed_consequence(0.5)
	assert_true(half.begins_with("0.5× — ") and half.contains("twice the time") and half.contains("half as hard") and half.contains("double speed"))
	assert_true(HudModel.speed_consequence(1.0).begins_with("1× — ") and HudModel.speed_consequence(1.0).contains("normal speed"))
	var quad := HudModel.speed_consequence(4.0)
	assert_true(quad.contains("quarter of the time") and quad.contains("four times as hard") and quad.contains("quarter speed"))
	var all := {}
	for s: float in OD.ALL_SPEEDS:
		all[HudModel.speed_consequence(s)] = true
	assert_eq(all.size(), 4)


func test_ui07_readouts_name_units() -> void:
	var f: Array[String] = []
	for s: float in OD.ALL_SPEEDS:
		f.append(HudModel.format_speed(s))
	assert_eq(f, ["0.5×", "1×", "2×", "4×"])
	assert_eq(HudModel.format_speed(0.0), "--")
	assert_eq(HudModel.span_copy(4, 2), "4 local bars → 2 master bars")
	assert_eq(HudModel.span_copy(4, 4), "4 local bars → 1 master bar")
	assert_eq(HudModel.span_copy(4, 0.5), "4 local bars → 8 master bars")
	assert_eq(HudModel.span_copy(3, 2), "3 local bars → 1.5 master bars")
	assert_eq(HudModel.format_world_rate(0.5), "world ×0.5")
	assert_eq(HudModel.format_world_rate(2.0), "world ×2")
	assert_eq(HudModel.format_world_rate(0.0), "world paused")
	assert_eq(HudModel.format_bars(0.25), "0.25")
	assert_eq(HudModel.format_bars(1.0 / 3.0), "0.33")


func test_ui07_span_scale_half_double() -> void:
	var offered: Array[float] = [0.5, 1.0, 2.0, 4.0]
	assert_eq(HudModel.span_scale_fill(0.5, offered), 1.0)
	assert_eq(HudModel.span_scale_fill(1.0, offered), 0.5)
	assert_eq(HudModel.span_scale_fill(2.0, offered), 0.25)
	assert_eq(HudModel.span_scale_fill(4.0, offered), 0.125)
	var one: Array[float] = [1.0]
	assert_eq(HudModel.span_scale_fill(1.0, one), 1.0)
	var two: Array[float] = [1.0, 2.0]
	assert_eq(HudModel.span_scale_fill(2.0, two), 0.5)
	assert_eq(HudModel.span_scale_bars(8, offered, 2.0), 16.0)


func test_new10_reels_speed_direction_stillness() -> void:
	assert_near(HudModel.reel_spin(2, 1), 2.0 * HudModel.reel_spin(1, 1), 1e-12)
	assert_near(HudModel.reel_spin(1, -1), -HudModel.reel_spin(1, 1), 1e-12)
	assert_eq(HudModel.reel_spin(2, 0), 0.0)
	var r0 := HudModel.tape_pack_radii(0, 9, 21)
	var r1 := HudModel.tape_pack_radii(1, 9, 21)
	assert_near(r0.x, 21, 1e-5)
	assert_near(r0.y, 9, 1e-5)
	assert_near(r1.x, 9, 1e-5)
	assert_near(r1.y, 21, 1e-5)
	var rm := HudModel.tape_pack_radii(0.5, 9, 21)
	assert_near(rm.x, rm.y, 1e-5)
	# Setup previews the chosen speed; otherwise the deck's real transport.
	var d := DeckView.new()
	d.speed = 2.0
	d.reel_rate = 0.0
	d.transport = 0
	assert_near(HudModel.deck_reel_spin(d, true), 2.0 * HudModel.BASE_REEL_RPS, 1e-12)
	assert_eq(HudModel.deck_reel_spin(d, false), 0.0)


func test_recording_time_left_counts_local_bars() -> void:
	assert_eq(HudModel.recording_time_left(0, 4).text, "4 local bars left")
	assert_eq(HudModel.recording_time_left(0.5, 4).text, "2 local bars left")
	assert_eq(HudModel.recording_time_left(0.7, 4).text, "2 local bars left")
	assert_eq(HudModel.recording_time_left(0.75, 4).text, "1 local bar left")
	assert_eq(HudModel.recording_time_left(0.8, 4).text, "0.8 local bars left")
	assert_eq(HudModel.recording_time_left(0.9, 4).text, "0.4 local bars left")
	assert_eq(HudModel.recording_time_left(1, 4).fraction, 0.0)


func test_master_position_text() -> void:
	assert_eq(HudModel.master_position_text(0), "bar 1 · beat 1")
	assert_eq(HudModel.master_position_text(5.5), "bar 2 · beat 2")
	assert_eq(HudModel.master_position_text(32, 32), "end · 8 bars")


func test_bar_labels_thin_out() -> void:
	assert_eq(HudModel.bar_label_step(8, 800, 30), 1)
	assert_eq(HudModel.bar_label_step(64, 800, 30), 4)
	assert_eq(HudModel.bar_label_step(0, 800), 1)


# ───────────────────────────── prompts ─────────────────────────────

func test_every_session_action_has_prompt_on_both_devices() -> void:
	for dev: StringName in [HudModel.DEVICE_KEYBOARD, HudModel.DEVICE_GAMEPAD]:
		for a: StringName in SessionAction.ALL:
			var p := HudModel.prompt_for(a, dev)
			assert_ne(p.binding.key, "?", "%s/%s" % [dev, a])
			assert_eq(p.text, "[%s] %s" % [p.binding.key, p.label])
	assert_eq(HudModel.prompt_for(SessionAction.RECORD, HudModel.DEVICE_KEYBOARD).text, "[Space] RECORD")
	assert_eq(HudModel.prompt_for(SessionAction.RECORD, HudModel.DEVICE_GAMEPAD).text, "[A] RECORD")
	assert_eq(HudModel.prompt_for(SessionAction.SPEED_UP, HudModel.DEVICE_GAMEPAD).binding.style, ButtonPrompt.STYLE_SHOULDER)


func test_live_bindings_override_defaults() -> void:
	var b: Dictionary[StringName, ButtonPrompt] = {SessionAction.RECORD: ButtonPrompt.make("F", ButtonPrompt.STYLE_KEY)}
	assert_eq(HudModel.prompt_for(SessionAction.RECORD, HudModel.DEVICE_KEYBOARD, b).text, "[F] RECORD")
	assert_eq(HudModel.prompt_for(SessionAction.COMMIT, HudModel.DEVICE_KEYBOARD, b).text, "[Enter] COMMIT TAPE")


func test_decision_and_setup_actions_never_share_a_button() -> void:
	for dev: StringName in [HudModel.DEVICE_KEYBOARD, HudModel.DEVICE_GAMEPAD]:
		var t := HudModel.default_bindings(dev)
		var dec := {}
		for a: StringName in [SessionAction.RETRY_TAKE, SessionAction.COMMIT, SessionAction.RESET_ALL]:
			dec[(t[a] as ButtonPrompt).key] = true
		assert_eq(dec.size(), 3, "decision keys on %s" % dev)
		var setup := {}
		for a: StringName in [SessionAction.SPEED_UP, SessionAction.SPEED_DOWN, SessionAction.CYCLE_END_MODE, SessionAction.RECORD]:
			setup[(t[a] as ButtonPrompt).key] = true
		assert_eq(setup.size(), 4, "setup keys on %s" % dev)


# ───────────────────────────── decision (REC-04, REC-05) ─────────────────────────────

func test_rec04_rec05_decision_options() -> void:
	var acts: Array[StringName] = [SessionAction.RETRY_TAKE, SessionAction.COMMIT]
	var o := HudModel.decision_options(acts, 1)
	assert_eq([o[0].action, o[1].action, o[2].action], [SessionAction.RETRY_TAKE, SessionAction.COMMIT, SessionAction.RESET_ALL])
	assert_eq([o[0].enabled, o[1].enabled, o[2].enabled], [true, true, false])
	assert_true(o[0].detail.contains("keeps every earlier tape"))
	assert_true(o[2].detail.contains("wipes every cassette"))
	assert_true(o[0].detail.contains("tape B"))
	assert_true(o[2].hold and not o[0].hold and not o[1].hold)


func test_rec07_verdicts() -> void:
	assert_eq(HudModel.verdict(null).tone, &"neutral")
	var win := Outcome.new()
	win.win = true
	assert_eq(HudModel.verdict(win).tone, &"win")
	var ns := Outcome.new()
	ns.reason = FailReason.NO_SURVIVOR
	assert_eq(HudModel.verdict(ns).title, "NO SURVIVOR AT THE END")
	var obj := Outcome.new()
	obj.reason = FailReason.OBJECTIVE
	assert_eq(HudModel.verdict(obj).title, "OBJECTIVE NOT COMPLETE")


func test_count_in_caption_and_flash_text() -> void:
	var v := SessionView.new()
	v.active = 1
	v.decks[1].speed = 2.0
	assert_eq(HudModel.count_in_caption(v), "TAPE B · 2× · world ×0.5 while you record")
	var texts := {}
	for k: StringName in ActionKind.ALL + StateMarkKind.ALL:
		texts[HudModel.flash_text(k)] = true
	assert_eq(texts.size(), ActionKind.ALL.size() + StateMarkKind.ALL.size())


# ───────────────────────────── layout ─────────────────────────────

func test_ruler_geometry_fits_four_lanes() -> void:
	for c: Array in [[1240, 100, 12, false], [1880, 150, 17, false], [3800, 260, 29, false], [960, 90, 11, false], [700, 46, 12, true]]:
		var g := HudModel.ruler_geometry(c[0], c[1], c[2], c[3])
		assert_eq(g.track_x, g.gutter)
		assert_true(g.track_x + g.track_w <= c[0], "track inside %s" % [c])
		assert_true(g.lane_y[0] >= g.band_h)
		for i in range(1, 4):
			assert_true(g.lane_y[i] >= g.lane_y[i - 1] + g.lane_h - 1e-4, "lanes do not overlap %s" % [c])
		assert_true(g.lane_y[3] + g.lane_h <= c[1] + 1e-4, "lanes inside %s" % [c])
		assert_true(g.lane_h >= 3)


const SIZES: Array[Vector2] = [Vector2(1280, 720), Vector2(1600, 900), Vector2(1920, 1080), Vector2(2560, 1440), Vector2(3840, 2160), Vector2(1600, 1200)]


func test_playfield_keeps_70_percent_while_recording() -> void:
	for s: Vector2 in SIZES:
		for a: int in [-1, 0, 3]:
			for ph: StringName in [SessionPhase.RECORDING, SessionPhase.COUNTIN]:
				var L := HudModel.dock_layout(s, ph, a)
				assert_true(L.bottom_inset <= s.y * 0.30 + 0.5, "inset %s of %s at %s active %d" % [L.bottom_inset, s.y, ph, a])
	for s: Vector2 in SIZES:
		var c := HudModel.dock_layout(s, SessionPhase.CINEMATIC, 2)
		var r := HudModel.dock_layout(s, SessionPhase.RECORDING, 2)
		assert_true(c.bottom_inset < r.bottom_inset, "cinematic steps back at %s" % s)
		assert_eq(HudModel.dock_layout(s, SessionPhase.RESULTS, 2).bottom_inset, 0.0)


func test_dock_decks_inside_screen_ordered_and_active_prominent() -> void:
	for s: Vector2 in SIZES:
		for ph: StringName in SessionPhase.ALL:
			if ph == SessionPhase.RESULTS:
				continue
			for a: int in [-1, 0, 1, 2, 3]:
				var L := HudModel.dock_layout(s, ph, a)
				var screen := Rect2(Vector2.ZERO, s)
				for i in 4:
					var r: Rect2 = L.decks[i]
					assert_true(screen.encloses(r), "deck %d inside at %s %s" % [i, s, ph])
					assert_false(r.intersects(L.ruler), "deck %d clear of the ruler" % i)
					if i > 0:
						assert_true(r.position.x >= L.decks[i - 1].end.x, "decks in order")
				assert_true(screen.encloses(L.ruler))
				if a >= 0 and ph != SessionPhase.CINEMATIC:
					for i in 4:
						if i != a:
							assert_true(L.decks[a].size.x > L.decks[i].size.x, "active deck wider (%s %s)" % [s, ph])
							assert_true(L.decks[a].size.y >= L.decks[i].size.y)


func test_ui07_speed_readout_never_covered() -> void:
	for s: Vector2 in SIZES:
		for ph: StringName in [SessionPhase.SETUP, SessionPhase.RECORDING, SessionPhase.REVIEW, SessionPhase.CINEMATIC]:
			var L := HudModel.dock_layout(s, ph, 1)
			for i in 4:
				var g := HudModel.deck_geometry(L.decks[i].size, L.unit, L.slim)
				var body := g.body
				assert_true(g.speed.size.x > 0 and g.speed.size.y > 0, "speed readout exists")
				assert_true(body.grow(0.5).encloses(g.speed), "speed inside deck body %s %s %d" % [s, ph, i])
				assert_false(g.flash.intersects(g.speed), "flash never covers speed")
				assert_false(g.cassette.intersects(g.speed), "cassette beside speed")
				for b: Rect2 in g.badges:
					assert_false(b.intersects(g.speed), "badges beside speed (%s %s deck %d)" % [s, ph, i])
					assert_true(b.size.x > 0, "badge row has width (%s %s deck %d)" % [s, ph, i])
				assert_true(g.speed_font >= L.unit * 1.5, "speed readout stays big: %s at %s %s" % [g.speed_font, s, ph])
			# The setup surface sits above the active deck, never over any deck's speed column.
			if ph == SessionPhase.SETUP:
				assert_true(L.setup_bottom <= L.decks[1].position.y, "setup card above the deck")


func test_deck_rows_by_size() -> void:
	var L := HudModel.dock_layout(Vector2(1600, 900), SessionPhase.RECORDING, 0)
	var active := HudModel.deck_geometry(L.decks[0].size, L.unit, false)
	var inactive := HudModel.deck_geometry(L.decks[1].size, L.unit, false)
	assert_true(HudModel.badge_rows(active) >= 4, "active deck shows status, life, end and transport")
	assert_true(HudModel.badge_rows(inactive) >= 3, "compact deck shows status, life and end/transport")
