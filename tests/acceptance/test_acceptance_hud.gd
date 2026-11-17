extends ODTest
## Acceptance: the cassette HUD (docs/requirements.txt Revision 1: NEW-07..11). The information is
## checked where it is decided - GameSession.view() (SessionView / DeckView), the HUD model tables
## (ui/hud/hud_model.gd), the actor style table (actors/actor_style.gd), the palettes - and the HUD
## scene (ui/hud/hud.tscn) is instanced to prove the four decks exist on screen with the right
## colours. Whether it all READS clearly at a glance is by eye (docs/ACCEPTANCE.md).

const K = preload("res://tests/acceptance/acceptance_kit.gd")
const S = preload("res://tests/helpers/script.gd")
const SIZE := Vector2(1600, 900)

var hud: HudBase = null


func after_each() -> void:
	if hud != null:
		hud.queue_free()
		hud = null
		await tree().process_frame


func _make_hud() -> HudBase:
	hud = (load("res://ui/hud/hud.tscn") as PackedScene).instantiate() as HudBase
	tree().root.add_child(hud)
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.position = Vector2.ZERO
	hud.size = SIZE
	return hud


func _frames(n: int = 2) -> void:
	for k in n:
		await tree().process_frame


## A session part-way through cassette two: A (1x) committed, B (2x) recording.
func _recording_b() -> GameSession:
	var s := K.new_session(K.rescue_room())
	K.take_a_to_decision(s)
	s.act(SessionAction.COMMIT)
	K.set_speed(s, 2.0)
	s.act(SessionAction.RECORD)
	K.advance_until_phase_changes(s, 10.0)
	for t: int in 20:
		s.tick_local(K.no_input())
	return s


## NEW-07: Four separately identifiable on-screen cassette elements are present during level play;
## their colors correspond to the four player recordings.
func test_NEW07_four_cassette_decks_with_the_recordings_colours_are_on_screen_during_play() -> void:
	# The session always reports four decks, in every phase of play.
	var s := K.new_session(K.rescue_room(3))
	var phases := {}
	var bad: Array[int] = [0]
	var check := func() -> void:
		var v := s.view()
		phases[v.phase] = true
		if v.decks.size() != OD.TAPE_COUNT:
			bad[0] += 1
		for i: int in v.decks.size():
			if v.decks[i].index != i:
				bad[0] += 1
	check.call()
	s.act(SessionAction.RECORD)
	check.call()
	K.advance_until_phase_changes(s, 10.0)
	var sc := K.tape_a_script()
	var t := 0
	while s.phase == SessionPhase.RECORDING:
		s.tick_local(sc.input(t))
		t += 1
		if t % 60 == 0:
			check.call()
	check.call()
	K.advance_until_phase_changes(s)
	check.call()
	assert_true(phases.size() >= 5, "phases seen: %s" % [phases.keys()])
	assert_eq(bad[0], 0, K.say("NEW-07", "a view without exactly four indexed decks"))
	# Colours: the HUD's cassette colours are the colours the world draws each self with.
	for i: int in OD.TAPE_COUNT:
		assert_eq(UiPalette.tape(i), OD.tape_color(i), K.say("NEW-07", "deck %s colour = self colour" % OD.TAPE_NAMES[i]))
		for j: int in range(i + 1, OD.TAPE_COUNT):
			var a := OD.tape_color(i)
			var b := OD.tape_color(j)
			assert_true(absf(a.h - b.h) > 0.05 and absf(a.h - b.h) < 0.95, K.say("NEW-07", "cassettes %d and %d need distinct hues" % [i, j]))
	# On screen: the HUD scene builds four decks, one per cassette, visible and not overlapping.
	var h := _make_hud()
	var rec := _recording_b()
	h.update_hud(rec.view(), MusicPulse.new())
	await _frames(3)
	var decks: Array = h.get("decks")
	if not assert_eq(decks.size(), OD.TAPE_COUNT, K.say("NEW-07", "HUD deck elements")):
		return
	var rects: Array[Rect2] = []
	for i: int in decks.size():
		var d: Control = decks[i]
		assert_true(d.is_visible_in_tree(), K.say("NEW-07", "deck %d visible while recording" % i))
		assert_eq(int(d.get("index")), i)
		assert_true(d.size.x > 20 and d.size.y > 20, K.say("NEW-07", "deck %d has a real on-screen size %s" % [i, d.size]))
		rects.append(Rect2(d.global_position, d.size))
	for i: int in rects.size():
		for j: int in range(i + 1, rects.size()):
			assert_false(rects[i].grow(-1.0).intersects(rects[j].grow(-1.0)), K.say("NEW-07", "decks %d and %d overlap" % [i, j]))


## NEW-08: Each cassette visibly states its tape speed and status, including which tape is currently
## recording and which are committed.
func test_NEW08_each_deck_states_its_speed_and_status_including_recording_and_committed() -> void:
	var s := _recording_b()
	var v := s.view()
	assert_eq([v.decks[0].status, v.decks[0].speed], [DeckStatus.COMMITTED, 1.0], K.say("NEW-08", "deck A: committed at 1x"))
	assert_eq([v.decks[1].status, v.decks[1].speed], [DeckStatus.RECORDING, 2.0], K.say("NEW-08", "deck B: recording at 2x"))
	assert_eq(v.active, 1, K.say("NEW-08", "the recording tape is the active one"))
	assert_eq(v.decks[2].status, DeckStatus.EMPTY)
	# Every status has its own words and icon (never colour only), and every speed its own readout.
	var labels := {}
	var icons := {}
	for st: StringName in DeckStatus.ALL:
		var b := HudModel.status_badge(st)
		assert_false(b.label.is_empty(), "status %s has words" % st)
		labels[b.label] = st
		icons[b.icon] = st
	assert_eq(labels.size(), DeckStatus.ALL.size(), K.say("NEW-08", "distinct status words"))
	assert_true(icons.size() >= DeckStatus.ALL.size() - 1, K.say("NEW-08", "status icons: %s" % [icons]))
	assert_ne(HudModel.status_badge(DeckStatus.RECORDING).icon, HudModel.status_badge(DeckStatus.COMMITTED).icon, K.say("NEW-08", "recording vs committed icon"))
	var readouts := {}
	for sp: float in OD.ALL_SPEEDS:
		readouts[HudModel.format_speed(sp)] = sp
	assert_eq(readouts.size(), OD.ALL_SPEEDS.size(), K.say("NEW-08", "speed readouts %s" % [readouts.keys()]))
	assert_true(HudModel.format_speed(0.5).contains("0.5") and HudModel.format_speed(2.0).contains("2"), K.say("NEW-08", "the readout names the speed"))
	# The badge rows the HUD draws for the two decks carry the status and the speed is set.
	var rows_a := HudModel.deck_badges(v.decks[0], v.beat, v.phase, 4)
	var rows_b := HudModel.deck_badges(v.decks[1], v.beat, v.phase, 4)
	assert_eq(rows_a[0].label, HudModel.status_badge(DeckStatus.COMMITTED).label)
	assert_eq(rows_b[0].label, HudModel.status_badge(DeckStatus.RECORDING).label)


## NEW-09: Continuous-time master timeline with beat markers remains visible during recording, not
## only during the final cinematic replay.
func test_NEW09_the_master_timeline_runs_continuously_and_is_shown_while_recording() -> void:
	var s := K.new_session(K.rescue_room())
	s.act(SessionAction.RECORD)
	K.advance_until_phase_changes(s, 10.0)
	var beats: Array[float] = []
	var horizon := s.view().horizon_beats
	var sc := K.tape_a_script()
	for t: int in 120:
		s.tick_local(sc.input(t))
		beats.append(s.view().beat)
	assert_true(horizon > 0.0, K.say("NEW-09", "the timeline has the encounter's length"))
	assert_near(horizon, s.horizon_subs / ODTime.subs_per_beat(s.level), 1e-9)
	var increasing := true
	var fractional := 0
	for i: int in range(1, beats.size()):
		increasing = increasing and beats[i] > beats[i - 1]
		if beats[i] != floorf(beats[i]):
			fractional += 1
	assert_true(increasing, K.say("NEW-09", "the master position moves every tick while recording"))
	assert_true(fractional > beats.size() / 2, K.say("NEW-09", "continuous time, not beat steps"))
	# Recorded action markers appear on the live lane as they are made (tick 100: the light).
	var marks := s.view().decks[0].marks
	assert_eq(marks.size(), 1, K.say("NEW-09", "the live take's marker on the timeline"))
	# Beat markers: the ruler model labels bars across the horizon.
	assert_true(HudModel.bar_label_step(horizon / OD.BEATS_PER_BAR, 1200.0) >= 1)
	var lane := HudModel.lane_layout(s.view().decks[0].span_bars * OD.BEATS_PER_BAR, OD.EndMode.STOP, horizon)
	assert_true(lane != null)
	# On screen: the HUD shows the ruler during recording.
	var h := _make_hud()
	h.update_hud(s.view(), MusicPulse.new())
	await _frames(3)
	var ruler: Control = h.get("ruler")
	assert_true(ruler != null and ruler.is_visible_in_tree(), K.say("NEW-09", "the master ruler is on screen while recording"))
	assert_true(ruler.size.x > SIZE.x * 0.3, K.say("NEW-09", "the ruler spans the screen (%s)" % [ruler.size]))


## NEW-10: Switching tape speed changes readout and any corresponding reel/transport feedback without
## losing master-beat alignment.
func test_NEW10_switching_speed_changes_readout_and_reels_but_keeps_master_beat_alignment() -> void:
	var s := K.new_session(TestLevels.make_level({"id": "new10", "speeds": [0.5, 1.0, 2.0, 4.0], "bars": 2}))
	var seen := {}
	var before := s.view()
	for sp: float in [0.5, 1.0, 2.0, 4.0]:
		K.set_speed(s, sp)
		var v := s.view()
		var d := v.decks[0]
		assert_eq(d.speed, sp, K.say("NEW-10", "the deck reads the chosen speed"))
		assert_near(d.span_bars, s.level.bars / sp, 1e-9, K.say("NEW-10", "the tape's master span follows the speed"))
		var spin := HudModel.deck_reel_spin(d, true)
		seen[sp] = [HudModel.format_speed(sp), spin]
		assert_eq(v.beat, before.beat, K.say("NEW-10", "switching speed does not move the master playhead"))
		# Alignment: a local tick lands on the master beat the clock defines for this speed.
		var tpb := ODTime.ticks_per_beat(s.level)
		assert_near(HudModel.local_tick_to_master_beat(60.0, sp, s.level.bpm), 60.0 / tpb / sp, 1e-9, K.say("NEW-10", "marker placement at %sx" % sp))
	for a: float in seen:
		for b: float in seen:
			if a < b:
				assert_ne(seen[a][0], seen[b][0], K.say("NEW-10", "readouts differ"))
				assert_true(absf(seen[b][1]) > absf(seen[a][1]), K.say("NEW-10", "reel feedback faster at %sx than %sx" % [b, a]))
	# While recording at 2x the live reel spins at the player's rate and the committed 1x reel at half
	# of it, and the HUD beat is exactly the world's master beat.
	var r := _recording_b()
	var v2 := r.view()
	assert_near(v2.world_rate, 0.5, 1e-12)
	assert_near(v2.decks[1].reel_rate, 1.0, 1e-12, K.say("NEW-10", "the live 2x reel"))
	assert_near(v2.decks[0].reel_rate, 0.5, 1e-12, K.say("NEW-10", "the committed 1x reel against a half-speed world"))
	assert_near(v2.beat, r.current_frame().snap.sub / ODTime.subs_per_beat(r.level), 1e-9, K.say("NEW-10", "HUD beat = master beat"))


## NEW-11: A player can distinguish a cassette that is unrecorded, committed, stopped, looping,
## reversing, dead or desynchronized without relying exclusively on audio.
func test_NEW11_every_cassette_state_has_its_own_visible_reading() -> void:
	var readings := {}
	readings["unrecorded"] = HudModel.status_badge(DeckStatus.EMPTY)
	readings["committed"] = HudModel.status_badge(DeckStatus.COMMITTED)
	var deck := DeckView.new()
	deck.status = DeckStatus.COMMITTED
	deck.speed = 1.0
	deck.span_bars = 1.0
	deck.end_mode = OD.EndMode.STOP
	deck.transport = 0
	deck.local_progress = 1.0
	readings["stopped"] = HudModel.transport_badge(deck, 6.0)
	deck.end_mode = OD.EndMode.REPEAT
	deck.transport = 1
	deck.local_progress = 0.3
	readings["looping"] = HudModel.transport_badge(deck, 6.0)
	deck.end_mode = OD.EndMode.REVERSE
	deck.transport = -1
	readings["reversing"] = HudModel.transport_badge(deck, 6.0)
	readings["dead"] = HudModel.life_badge(OD.LifeState.GHOST, true)
	readings["desynchronized"] = HudModel.life_badge(OD.LifeState.ALIVE, false)
	var labels := {}
	var icons := {}
	for k: String in readings:
		var b: HudModel.Badge = readings[k]
		if not assert_true(b != null, K.say("NEW-11", "no visible reading for %s" % k)):
			continue
		assert_false(b.label.is_empty(), K.say("NEW-11", "%s has words" % k))
		labels[b.label] = k
		icons[b.icon] = k
	assert_eq(labels.size(), readings.size(), K.say("NEW-11", "distinct words: %s" % [labels]))
	assert_eq(icons.size(), readings.size(), K.say("NEW-11", "distinct icons: %s" % [icons]))
	# The compact deck keeps them apart too (looping / reversing / holding fold into the end-mode row).
	deck.end_mode = OD.EndMode.REPEAT
	deck.transport = 1
	var compact_loop := HudModel.deck_badges(deck, 6.0, SessionPhase.REVIEW, 3)
	deck.end_mode = OD.EndMode.REVERSE
	deck.transport = -1
	var compact_rev := HudModel.deck_badges(deck, 6.0, SessionPhase.REVIEW, 3)
	assert_ne(compact_loop[compact_loop.size() - 1].key(), compact_rev[compact_rev.size() - 1].key(), K.say("NEW-11", "compact looping vs reversing"))
	# Every status x life x sync combination presents differently on the deck...
	var keys := {}
	var combos := 0
	for st: StringName in [DeckStatus.RECORDING, DeckStatus.PENDING, DeckStatus.COMMITTED]:
		for life: int in [OD.LifeState.ALIVE, OD.LifeState.REC_GHOST, OD.LifeState.GHOST]:
			for synced: bool in [true, false]:
				keys[HudModel.presentation_key(st, life, synced)] = true
				combos += 1
	assert_eq(keys.size(), combos, K.say("NEW-11", "status x life x sync presentations collide"))
	# ...and every life x sync state of a self has its own look in the world.
	var sigs := {}
	for life: int in [OD.LifeState.ALIVE, OD.LifeState.REC_GHOST, OD.LifeState.GHOST]:
		for synced: bool in [true, false]:
			var id := ActorStyle.select(life, synced)
			sigs[str(ActorStyle.params(id).signature())] = id
	assert_eq(sigs.size(), 6, K.say("NEW-11", "world styles for the six life x sync states: %s" % [sigs.values()]))
	# And the session really reports these states on its decks (a dead and a stopped cassette).
	var s := K.new_session(K.rescue_room(1))
	K.record_with(s, K.tape_a_script())
	s.act(SessionAction.SKIP)
	var d0 := s.view().decks[0]
	assert_eq(d0.life, OD.LifeState.GHOST, K.say("NEW-11", "the dead cassette is reported dead"))
	assert_eq(d0.transport, 0, K.say("NEW-11", "and stopped once playback is over"))
