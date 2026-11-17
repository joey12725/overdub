extends ODTest
## The replay keeper (replay/**): CINE-01 / LEVEL-09 (watch a solved level's winning performance
## again) and requirements chapter 20 "Replay integrity" (a replay reproduces the actual resolved
## outcome, never a fresh adaptive run; changed levels / rules are reported stale, never shown wrong).

const K = preload("res://tests/acceptance/acceptance_kit.gd")
const S = preload("res://tests/helpers/script.gd")
const ROOT := "user://test_replays"

var store: ReplayStore = null


func before_each() -> void:
	_wipe()
	store = ReplayStore.new(ROOT)


func after_each() -> void:
	_wipe()


func _wipe() -> void:
	var dir := DirAccess.open(ROOT)
	if dir == null:
		return
	for f: String in dir.get_files():
		dir.remove(f)
	DirAccess.remove_absolute(ROOT)


## The rescue room won with two cassettes, exactly as GameSession hands it over at the win.
class Win:
	extends RefCounted
	var level: LevelDef
	var loadout: ResolvedLoadout
	var tapes: Array[ODTape] = []
	var memory: BossMemory
	var resolution: Resolution


func _win() -> Win:
	var w := Win.new()
	w.level = K.rescue_room()
	w.loadout = TestLoadout.base_loadout()
	w.tapes = K.rescue_win_tapes(w.level)
	var committed: Array[ODTape] = [w.tapes[0]]
	w.memory = BossMemoryLib.build_boss_memory(w.level, committed)
	w.resolution = K.resolve(w.level, w.tapes, w.loadout, w.memory)
	return w


func _record(w: Win) -> ReplayRecord:
	var errors: Array[String] = []
	var r := store.record_win(w.level, w.loadout, w.tapes, w.memory, w.resolution, 1234, errors)
	assert_true(r != null, "record_win: %s" % [errors])
	return r


# ───────────────────────────── keeping a win ─────────────────────────────


func test_a_win_is_kept_compactly_under_user_replays_and_reads_back_identically() -> void:
	var w := _win()
	if not assert_true(w.resolution.outcome.win, "fixture wins"):
		return
	var r := _record(w)
	if r == null:
		return
	assert_true(store.has_replay("rescue"))
	assert_eq(store.path_for("rescue"), ROOT + "/rescue.json")
	assert_eq(store.list_level_ids(), ["rescue"])
	var errors: Array[String] = []
	var back := store.load_record("rescue", errors)
	if not assert_true(back != null, "load: %s" % [errors]):
		return
	assert_eq(errors, [])
	assert_eq(back.level_id, "rescue")
	assert_eq(back.level_hash, ReplayVerifier.level_hash(w.level))
	assert_eq(back.saved_at, 1234)
	assert_true(back.loadout_ids.equals(w.loadout.loadout))
	assert_eq(back.tapes.size(), 2)
	for i: int in 2:
		assert_true(TapeLib.tapes_equal(back.tapes[i], w.tapes[i]), "tape %d round-trips bit for bit" % i)
		for j: int in back.tapes[i].events.size():
			var a: TapeEvent = back.tapes[i].events[j]
			var b: TapeEvent = w.tapes[i].events[j]
			assert_true(a.dir == b.dir and a.vx == b.vx and a.vy == b.vy and a.x == b.x and a.y == b.y, "tape %d event %d floats are exact" % [i, j])
	assert_json_eq(back.boss_memory.to_dict(), w.memory.to_dict(), 0.0, "boss memory input kept exactly")
	assert_json_eq(back.resolved_loadout.to_dict(), w.loadout.to_dict(), 0.0, "resolved loadout kept exactly")
	assert_eq(back.expected_outcome.win, true)
	assert_eq(back.expected_event_count, w.resolution.events.size())
	assert_eq(back.expected_events_checksum, ReplayVerifier.events_checksum(w.resolution))
	assert_json_eq(back.to_dict(), r.to_dict(), 0.0, "the stored record reads back as written")
	# Compact: the inputs, not the frames (a resolution is hundreds of snapshots).
	var size := FileAccess.get_file_as_bytes(store.path_for("rescue")).size()
	var frames_size := ODJson.stringify(w.resolution.to_dict()).length()
	assert_true(size * 10 < frames_size, "replay %d bytes vs %d for the frames" % [size, frames_size])
	assert_false(FileAccess.file_exists(store.path_for("rescue") + ".tmp"), "no temp file left behind")


func test_only_a_winning_run_is_kept() -> void:
	var level := K.rescue_room()
	var a := S.record_take(level, 0, 1.0, K.tape_a_script()).tape
	var tapes: Array[ODTape] = [a]
	var lose := K.resolve(level, tapes)
	assert_false(lose.outcome.win)
	var errors: Array[String] = []
	expect_engine_errors()
	assert_true(store.record_win(level, TestLoadout.base_loadout(), tapes, null, lose, 0, errors) == null)
	assert_false(errors.is_empty())
	assert_false(store.has_replay(level.id))


func test_playing_a_replay_re_resolves_the_exact_winning_run() -> void:
	var w := _win()
	if _record(w) == null:
		return
	var check := store.play(w.level, w.loadout)
	if not assert_true(check.ok(), "play: %s %s %s" % [check.status, check.reason, check.message]):
		return
	var res := check.resolution
	assert_json_eq(res.outcome.to_dict(), w.resolution.outcome.to_dict(), 0.0, "outcome")
	assert_eq(K.event_rows(res.events), K.event_rows(w.resolution.events), "every event at its substep")
	assert_json_eq(K.frames_json(res.frames), K.frames_json(w.resolution.frames), 0.0, "every frame (the cinematic draws these)")
	# It is a playback of the stored inputs, never a fresh adaptive run: no live take, and the boss
	# memory is the stored one (not rebuilt from all tapes, which would be a new learning step).
	var cfg := check.record.config(w.level)
	assert_true(cfg.live == null)
	assert_json_eq(cfg.boss_memory.to_dict(), w.memory.to_dict(), 0.0)
	var all: Array[ODTape] = w.tapes
	var relearned := BossMemoryLib.build_boss_memory(w.level, all)
	assert_false(ODJson.deep_equal(cfg.boss_memory.to_dict(), relearned.to_dict()), "the stored memory is not a re-learned one")


func test_verify_twice_is_identical_determinism() -> void:
	var w := _win()
	var r := _record(w)
	if r == null:
		return
	var c1 := ReplayVerifier.verify(r, w.level)
	var c2 := ReplayVerifier.verify(r, w.level)
	assert_true(c1.ok() and c2.ok())
	if c1.ok() and c2.ok():
		assert_json_eq(c1.resolution.to_dict(), c2.resolution.to_dict(), 0.0)


# ───────────────────────────── stale, never shown wrong ─────────────────────────────


func test_a_changed_level_marks_the_replay_stale() -> void:
	var w := _win()
	if _record(w) == null:
		return
	var edited := w.level.copy()
	for e: EntityDef in edited.entities:
		if e is EnemyDef and e.id == "g1":
			(e as EnemyDef).x += 0.5
	var quick := store.quick_check(edited)
	assert_eq(quick.status, ReplayVerifier.STATUS_STALE)
	assert_eq(quick.reason, ReplayVerifier.REASON_LEVEL_CHANGED)
	var check := store.play(edited)
	assert_true(check.is_stale())
	assert_true(check.resolution == null, "a stale replay offers nothing to show")
	assert_false(check.message.is_empty())
	# The unchanged level still plays.
	assert_true(store.play(w.level).ok())


func test_changed_rules_mark_the_replay_stale_after_re_resolving() -> void:
	var w := _win()
	var r := _record(w)
	if r == null:
		return
	# Simulate a rules change that the level hash cannot see: the stored inputs now produce another
	# result (here: the weapon numbers the run used no longer kill).
	r.resolved_loadout.melee.damage_eff = 0.0
	var check := ReplayVerifier.verify(r, w.level)
	assert_eq(check.status, ReplayVerifier.STATUS_STALE)
	assert_eq(check.reason, ReplayVerifier.REASON_RULES_CHANGED)
	assert_true(check.resolution == null)
	assert_true(check.message.contains("outcome") or check.message.contains("event"), check.message)
	# Same for a run that still wins but whose events moved (a timing change).
	var r2 := _record(w)
	r2.expected_events_checksum = "0".repeat(64)
	var c2 := ReplayVerifier.verify(r2, w.level)
	assert_eq([c2.status, c2.reason], [ReplayVerifier.STATUS_STALE, ReplayVerifier.REASON_RULES_CHANGED])
	assert_true(c2.message.contains("checksum"), c2.message)


func test_gear_that_changed_since_marks_the_replay_stale() -> void:
	var w := _win()
	if _record(w) == null:
		return
	var now := w.loadout.copy()
	now.melee.reach += 0.2
	var check := store.play(w.level, now)
	assert_eq([check.status, check.reason], [ReplayVerifier.STATUS_STALE, ReplayVerifier.REASON_GEAR_CHANGED])
	assert_true(store.play(w.level, w.loadout).ok())
	assert_true(store.play(w.level).ok(), "without a current loadout only the stored numbers are used")


func test_missing_corrupt_foreign_and_newer_files_are_never_played() -> void:
	var lv := K.rescue_room()
	assert_eq(store.quick_check(lv).status, ReplayVerifier.STATUS_MISSING)
	assert_true(store.load_record(lv.id) == null)
	DirAccess.make_dir_recursive_absolute(ROOT)
	var f := FileAccess.open(store.path_for(lv.id), FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	var c := store.quick_check(lv)
	assert_eq([c.status, c.reason], [ReplayVerifier.STATUS_INVALID, ReplayVerifier.REASON_UNREADABLE])
	assert_eq(store.list_level_ids(), [])
	var w := _win()
	var r := ReplayRecord.from_win(w.level, w.loadout, w.tapes, w.memory, w.resolution)
	var d := r.to_dict()
	d["version"] = ReplayRecord.VERSION + 1
	f = FileAccess.open(store.path_for(lv.id), FileAccess.WRITE)
	f.store_string(ODJson.stringify(d))
	f.close()
	var errors: Array[String] = []
	assert_true(store.load_record(lv.id, errors) == null)
	assert_true(", ".join(errors).contains("newer"), str(errors))
	var foreign := {"format": "something-else", "version": 1}
	f = FileAccess.open(store.path_for(lv.id), FileAccess.WRITE)
	f.store_string(JSON.stringify(foreign))
	f.close()
	assert_eq(store.quick_check(lv).status, ReplayVerifier.STATUS_INVALID)


func test_a_hand_edited_file_without_exact_bits_still_loads_with_json_precision() -> void:
	var w := _win()
	var r := ReplayRecord.from_win(w.level, w.loadout, w.tapes, w.memory, w.resolution)
	var d := r.to_dict()
	d.erase("inputBits")
	var errors: Array[String] = []
	var back := ReplayRecord.from_dict(JSON.parse_string(ODJson.stringify(d)), errors)
	assert_true(back != null, str(errors))
	assert_eq(back.tapes.size(), 2)
	# And a mismatching bit block is reported and ignored rather than misapplied.
	d = r.to_dict()
	d["inputBits"] = Marshalls.raw_to_base64(PackedFloat64Array([1.0, 2.0]).to_byte_array())
	errors.clear()
	back = ReplayRecord.from_dict(d, errors)
	assert_true(back != null)
	assert_true(", ".join(errors).contains("inputBits"), str(errors))


# ───────────────────────────── store housekeeping ─────────────────────────────


func test_a_new_win_replaces_the_kept_replay_and_remove_forgets_it() -> void:
	var w := _win()
	var r1 := _record(w)
	var errors: Array[String] = []
	var r2 := store.record_win(w.level, w.loadout, w.tapes, w.memory, w.resolution, 99, errors)
	assert_true(r1 != null and r2 != null)
	assert_eq(store.load_record("rescue").saved_at, 99, "the latest win is the one kept")
	assert_eq(store.list_level_ids(), ["rescue"])
	assert_true(store.remove("rescue"))
	assert_false(store.has_replay("rescue"))
	assert_true(store.remove("rescue"), "removing nothing succeeds")


func test_file_names_are_safe_for_any_level_id() -> void:
	assert_eq(ReplayStore.file_stem("Level 3/../Boss"), "level_3____boss")
	assert_eq(ReplayStore.file_stem("upper-01_a"), "upper-01_a")
	assert_eq(ReplayStore.file_stem(""), "_")
	var other := ReplayStore.new("user://elsewhere")
	assert_eq(other.path_for("x"), "user://elsewhere/x.json")
	assert_eq(ReplayStore.DEFAULT_ROOT, "user://replays")


# ───────────────────────────── the cinematic player ─────────────────────────────


func test_replay_playback_shows_the_resolution_at_true_master_speed_and_takes_no_input() -> void:
	var w := _win()
	var r := _record(w)
	if r == null:
		return
	var check := store.play(w.level)
	if not assert_true(check.ok()):
		return
	var res := check.resolution
	var pb := ReplayPlayback.new(res, w.level, check.record)
	var v0 := pb.view()
	assert_eq(v0.phase, SessionPhase.CINEMATIC)
	assert_eq(v0.actions, [SessionAction.SKIP], "watching offers only skip")
	assert_eq([v0.decks[0].status, v0.decks[1].status, v0.decks[2].status], [DeckStatus.COMMITTED, DeckStatus.COMMITTED, DeckStatus.EMPTY])
	assert_eq([v0.decks[0].speed, v0.decks[1].speed], [1.0, 2.0])
	assert_eq(v0.decks.size(), OD.TAPE_COUNT)
	var events: Array[SimEvent] = []
	var steps := 0
	var drawn: Array[FrameSnapshot] = []
	while not pb.done and steps < 100000:
		pb.advance(K.STEP)
		var f := pb.current_frame()
		assert_true(f.alpha >= 0.0 and f.alpha <= 1.0)
		drawn.append(f.prev)
		events.append_array(pb.drain_events())
		steps += 1
	var expect := res.horizon_subs / float(OD.SUB_HZ) * 60.0
	assert_true(absf(steps - expect) <= 2.0, "%d steps for %.1f" % [steps, expect])
	assert_eq(K.event_rows(events), K.event_rows(res.events), "every event once, in order")
	var last := -1
	var bad := 0
	for f: FrameSnapshot in drawn:
		var i := res.frames.find(f)
		if i < last or i < 0:
			bad += 1
		last = maxi(last, i)
	assert_eq(bad, 0, "frames drawn verbatim, in order")
	assert_eq(last, res.frames.size() - 1)
	assert_true(pb.view().outcome.win)
	# Skip changes nothing about the performance.
	var before := res.to_dict()
	var pb2 := ReplayPlayback.new(res, w.level, check.record)
	pb2.advance(0.5)
	pb2.skip()
	assert_true(pb2.done)
	assert_json_eq(res.to_dict(), before, 0.0)
	assert_true(pb2.current_frame().snap == res.frames[res.frames.size() - 1])


func test_the_win_handed_over_by_game_session_round_trips_through_the_store() -> void:
	# The integration contract: what GameSession exposes at the win is exactly what record_win needs.
	var s := K.new_session(K.rescue_room())
	if not assert_true(K.take_a_to_decision(s)):
		return
	s.act(SessionAction.COMMIT)
	K.set_speed(s, 2.0)
	K.record_with(s, K.tape_b_script())
	if not assert_eq(s.phase, SessionPhase.CINEMATIC):
		return
	var tapes: Array = s.committed_tapes.duplicate()
	tapes.append(s.pending_tape)
	var errors: Array[String] = []
	var r := store.record_win(s.level, s.loadout, tapes, s.boss_memory, s.resolution, 0, errors)
	assert_true(r != null, str(errors))
	var check := store.play(s.level, s.loadout)
	if assert_true(check.ok(), check.message):
		assert_json_eq(check.resolution.to_dict(), s.resolution.to_dict(), 0.0, "the replay is the session's own winning resolution")
