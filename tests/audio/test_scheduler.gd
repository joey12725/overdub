extends ODTest
## AudioScheduler: look-ahead planning that follows set_transport(master_beat, rate, playing)
## through rate changes, pauses, seeks and the jump back to beat 0 at every take, without stuck,
## dropped or doubled notes (port of prototype/tests/audio/scheduler.test.ts).

const D := preload("res://tests/audio/test_director.gd")
const BPM := 120.0
const BPS := BPM / 60.0


## One note on every sixteenth of track 0.
static func grid_source(from: float, to: float) -> Array[AudioLayerNote]:
	var out: Array[AudioLayerNote] = []
	var k := maxi(0, int(ceilf(from * 4.0 - 1e-9)))
	while k / 4.0 < to - 1e-9:
		out.append(AudioLayerNote.make(0, k / 4.0, 0.2, 60, 100, 0.5, k))
		k += 1
	return out


## Drives a scheduler like the game loop: 60 frames per second, beat from the sim.
class Harness:
	extends RefCounted
	var s: AudioScheduler
	var t: ODTest
	var now: float = 10.0
	var beat: float = 0.0
	var live: Dictionary = {}
	var log: Array[AudioPlannedNote] = []
	var chokes: int = 0
	var bad_cancels: int = 0

	func _init(p_s: AudioScheduler, p_t: ODTest) -> void:
		s = p_s
		t = p_t

	func frame(rate: float, playing: bool = true, dt: float = 1.0 / 60.0) -> void:
		now += dt
		if playing:
			beat += dt * rate * BPS
		apply(s.update(now, beat, rate, playing))

	func remove(cancelled: Array[AudioPlannedNote]) -> void:
		for c: AudioPlannedNote in cancelled:
			# Only notes that have not started yet may be cancelled.
			if not (c.time > now):
				bad_cancels += 1
			live.erase(c.id)
			var kept: Array[AudioPlannedNote] = []
			for p: AudioPlannedNote in log:
				if p.id != c.id:
					kept.append(p)
			log = kept

	func apply(u: AudioScheduler.Update) -> void:
		remove(u.cancel)
		if u.choke:
			chokes += 1
		for p: AudioPlannedNote in u.start:
			live[p.id] = p
			log.append(p)

	func jump(p_beat: float, rate: float) -> void:
		beat = p_beat
		now += 1.0 / 60.0
		apply(s.update(now, beat, rate, true))

	## Beats of the notes that really play (planned and never cancelled).
	func played(from_time: float = -INF) -> Array[float]:
		var out: Array[float] = []
		for p: AudioPlannedNote in log:
			if p.time >= from_time:
				out.append(p.note.beat)
		return out


func _make(lookahead: float = 0.12) -> Harness:
	return Harness.new(AudioScheduler.new(grid_source, BPM, lookahead), self)


static func _unique(a: Array[float]) -> bool:
	var seen := {}
	for x: float in a:
		var k := snappedf(x, 1e-9)
		if seen.has(k):
			return false
		seen[k] = true
	return true


static func _grid_upto(beat: float) -> Array[float]:
	var out: Array[float] = []
	for k: int in int(floorf(beat * 4.0)) + 1:
		out.append(k / 4.0)
	return out


static func _upto(a: Array[float], beat: float) -> Array[float]:
	var out: Array[float] = []
	for x: float in a:
		if x <= beat:
			out.append(x)
	return out


func test_plays_every_note_exactly_once_at_the_right_time_at_a_steady_rate() -> void:
	var h := _make()
	for i: int in 240:
		h.frame(1.0)
	var beats := h.played()
	assert_true(_unique(beats), "no note twice")
	var first: Array[float] = []
	for k: int in 20:
		first.append(k / 4.0)
	assert_eq(beats.slice(0, 20), first)
	var max_beat := -INF
	for p: AudioPlannedNote in h.log:
		# The note is due when the transport reaches its beat (start was 10 s, beat 0).
		var due := 10.0 + p.note.beat / BPS
		assert_true(p.time >= due - 1e-9 or absf(p.time - due) < 1e-9, "never early: beat %s at %s, due %s" % [p.note.beat, p.time, due])
		assert_true(p.time - due < 1.0 / 60.0 + 1e-9, "at most one frame late: beat %s" % p.note.beat)
		max_beat = maxf(max_beat, p.note.beat)
	# Planned no further ahead than the look-ahead.
	assert_true(max_beat <= h.beat + 0.12 * BPS + 1e-9, "planned within the look-ahead")
	assert_eq(h.bad_cancels, 0)


func test_note_durations_scale_with_the_transport_rate() -> void:
	var slow := _make()
	var fast := _make()
	for i: int in 30:
		slow.frame(0.25)
		fast.frame(2.0)
	assert_near(slow.log[0].dur, 0.2 / (0.25 * BPS), 1e-9)
	assert_near(fast.log[0].dur, 0.2 / (2.0 * BPS), 1e-9)


func test_follows_rate_changes_without_gaps_or_duplicates() -> void:
	var h := _make()
	for r: float in [1.0, 0.25, 2.0, 0.5, 4.0, 1.0]:
		for i: int in 50:
			h.frame(r)
	var beats := h.played()
	beats.sort()
	assert_true(_unique(beats), "no duplicates")
	# Everything up to where the transport is now has been planned, once.
	assert_eq(_upto(beats, h.beat), _upto(_grid_upto(h.beat), h.beat))
	# Times are monotonic in beat, so no note was timed for a stale rate.
	var by_beat := h.log.duplicate()
	by_beat.sort_custom(func(a: AudioPlannedNote, b: AudioPlannedNote) -> bool: return a.note.beat < b.note.beat)
	for i: int in range(1, by_beat.size()):
		assert_true(by_beat[i].time >= by_beat[i - 1].time - 1e-9, "monotonic at beat %s" % by_beat[i].note.beat)
	assert_eq(h.bad_cancels, 0)


func test_tape_speed_rates_land_on_the_master_grid_in_wall_time() -> void:
	# Recording at tape speed s runs the world at 1/s; every planned note is heard when the master
	# transport reaches it, whatever the rate, so all four speeds stay locked to one grid.
	for speed: float in OD.ALL_SPEEDS:
		var h := _make()
		var rate := 1.0 / speed
		for i: int in 180:
			h.frame(rate)
		var bps := rate * BPS
		assert_true(h.log.size() > 4, "speed %s plays" % speed)
		for p: AudioPlannedNote in h.log:
			var due := 10.0 + p.note.beat / bps
			assert_true(p.time >= due - 1e-9 and p.time - due < 1.0 / 60.0 + 1e-9, "speed %s beat %s heard on its master time" % [speed, p.note.beat])
			assert_near(p.dur, 0.2 / bps, 1e-9)


func test_a_jump_back_to_beat_0_cancels_unplayed_notes_chokes_and_restarts_cleanly() -> void:
	var h := _make()
	for i: int in 100:
		h.frame(1.0)
	var before := h.log.size()
	var chokes := h.chokes
	var jump_time := h.now + 1.0 / 60.0
	h.jump(0.0, 1.0)
	assert_eq(h.chokes, chokes + 1, "the jump chokes sounding notes")
	for id: int in h.live:
		var p: AudioPlannedNote = h.live[id]
		if p.time > jump_time:
			assert_true(p.note.beat < 1.0, "only the new take's opening is planned: %s" % p.note.beat)
	for i: int in 100:
		h.frame(1.0)
	var after := h.played(jump_time)
	assert_eq(after[0], 0.0, "the take restarts on beat 0")
	assert_true(_unique(after), "no duplicates after the jump")
	var want: Array[float] = []
	for k: int in after.size():
		want.append(k / 4.0)
	assert_eq(after, want)
	assert_true(before > 0)
	assert_eq(h.bad_cancels, 0)


func test_repeated_takes_each_replay_from_beat_0_exactly_once() -> void:
	var h := _make()
	for take: int in 3:
		var start := h.now + 1.0 / 60.0
		h.jump(0.0, 1.0)
		for i: int in 90:
			h.frame(1.0)
		var beats := h.played(start)
		assert_true(_unique(beats), "take %d: no duplicates" % take)
		assert_eq(beats[0], 0.0, "take %d starts on 0" % take)
		assert_eq(_upto(beats, h.beat), _upto(_grid_upto(h.beat), h.beat), "take %d: nothing dropped" % take)
	assert_eq(h.bad_cancels, 0)


## The game's take loop: the take stops where it ended, the count-in holds the stopped transport at
## beat 0 for a bar, then the next take plays from 0. Every note of the new take must play.
func test_a_take_counted_in_at_beat_0_with_the_transport_stopped_replays_every_note() -> void:
	var h := _make()
	for take: int in 3:
		for i: int in 20:
			h.frame(1.0, false)
		h.beat = 0.0
		for i: int in 60:
			h.frame(1.0, false)
		var start := h.now
		for i: int in 90:
			h.frame(1.0)
		var beats := h.played(start)
		assert_true(_unique(beats), "take %d: no duplicates" % take)
		assert_eq(_upto(beats, h.beat), _upto(_grid_upto(h.beat), h.beat), "take %d: nothing dropped" % take)
	assert_eq(h.bad_cancels, 0)


func test_a_forward_seek_skips_ahead_instead_of_bursting_the_skipped_notes() -> void:
	var h := _make()
	for i: int in 30:
		h.frame(1.0)
	var t := h.now + 1.0 / 60.0
	h.jump(40.0, 1.0)
	for i: int in 10:
		h.frame(1.0)
	var after := h.played(t)
	assert_true(after.size() > 0)
	assert_true(after.min() >= 40.0 - 0.1, "nothing from before the seek: %s" % after.min())


func test_pause_cancels_planned_notes_and_resume_continues_without_repeats() -> void:
	var h := _make()
	for i: int in 60:
		h.frame(1.0)
	h.frame(1.0, false)
	assert_eq(h.chokes, 1, "pausing chokes once")
	for p: AudioPlannedNote in h.log:
		assert_true(p.time <= h.now + 1e-9, "no note left planned after the pause")
	for i: int in 30:
		h.frame(1.0, false)
	assert_eq(h.chokes, 1, "staying paused does not choke again")
	for i: int in 60:
		h.frame(1.0)
	var beats := h.played()
	assert_true(_unique(beats))
	beats.sort()
	assert_eq(_upto(beats, h.beat), _upto(_grid_upto(h.beat), h.beat))
	assert_eq(h.bad_cancels, 0)


func test_rate_zero_while_playing_holds_like_a_pause() -> void:
	var h := _make()
	for i: int in 30:
		h.frame(1.0)
	var n := h.log.size()
	for i: int in 30:
		h.frame(0.0)
	assert_true(h.log.size() <= n, "nothing new is planned at rate 0")
	for p: AudioPlannedNote in h.log:
		assert_true(p.time <= h.now + 1e-9)
	for i: int in 30:
		h.frame(1.0)
	assert_true(_unique(h.played()))


func test_invalidation_replans_upcoming_notes_without_doubling_started_ones() -> void:
	var level := D.standard_level()
	var seq := AudioSequencer.new(AudioDirector.new(level))
	seq.set_tracks(D.tracks4(D.tas(), D.tas(), D.tas(), D.tas()), 0)
	var s := AudioScheduler.new(func(a: float, b: float) -> Array[AudioLayerNote]: return seq.collect(a, b), level.bpm)
	var h := Harness.new(s, self)
	for i: int in 200:
		h.frame(1.0)
		if i == 90:
			seq.set_tracks(D.tracks4(D.tas({"life": OD.LifeState.GHOST}), D.tas(), D.tas({"synced": false}), D.tas({"transport": -1})), h.beat)
			h.remove(s.invalidate(h.now))
	var keys := {}
	var dup := 0
	for p: AudioPlannedNote in h.log:
		var k := p.note.key()
		if keys.has(k):
			dup += 1
		keys[k] = true
	assert_eq(dup, 0, "no note planned twice")
	# Every note of the composition actually in force was planned.
	var end := h.beat - 0.1
	var first_after: AudioPlannedNote = null
	for p: AudioPlannedNote in h.log:
		if p.time > 10.0 + 91.0 / 60.0:
			first_after = p
			break
	if not assert_true(first_after != null):
		return
	var want := seq.collect(first_after.note.beat, end).size()
	var got := 0
	for p: AudioPlannedNote in h.log:
		if p.note.beat >= first_after.note.beat and p.note.beat < end:
			got += 1
	assert_eq(got, want)
	assert_eq(h.bad_cancels, 0)


func test_a_stalled_frame_loop_does_not_replay_a_backlog() -> void:
	var h := _make()
	for i: int in 20:
		h.frame(1.0)
	h.frame(1.0, true, 1.5)  # 1.5 s hitch: the beat advanced 3 beats
	var before_hitch := 20.0 / 60.0 * BPS + 0.12 * BPS
	for p: AudioPlannedNote in h.log:
		if p.note.beat < h.beat - 0.1:
			assert_true(p.note.beat <= before_hitch + 1e-9, "late note %s was planned before the hitch" % p.note.beat)


func test_the_full_pipeline_is_deterministic_across_rate_changes_and_takes() -> void:
	var run := func() -> Array:
		var seq := AudioSequencer.new(AudioDirector.new(D.standard_level()))
		seq.set_tracks(D.tracks4(D.tas({"speed": 2.0}), D.tas(), D.tas({"speed": 0.5}), D.tas({"speed": 4.0})), 0)
		var h := Harness.new(AudioScheduler.new(func(a: float, b: float) -> Array[AudioLayerNote]: return seq.collect(a, b), BPM), self)
		for r: float in [1.0, 0.5, 2.0]:
			for i: int in 60:
				h.frame(r)
		h.jump(0.0, 1.0)
		seq.restart()
		for i: int in 60:
			h.frame(0.25)
		var out: Array = []
		for p: AudioPlannedNote in h.log:
			out.append([p.note.strip(), snappedf(p.time, 1e-9), snappedf(p.dur, 1e-9)])
		return out
	var a: Array = run.call()
	assert_true(a.size() > 50, "a real amount of music: %d" % a.size())
	assert_eq(run.call(), a)


func test_invalidation_keeps_notes_already_committed_to_the_output() -> void:
	# A layer-state change arriving on the beat must not swap on-time notes for late replacements:
	# notes due inside the commit window (next mix + output latency) play as planned, the new
	# composition takes over right after them, and nothing doubles or goes missing.
	var level := D.standard_level()
	var seq := AudioSequencer.new(AudioDirector.new(level))
	seq.set_tracks(D.tracks4(D.tas(), D.tas(), D.tas(), D.tas()), 0)
	var s := AudioScheduler.new(func(a: float, b: float) -> Array[AudioLayerNote]: return seq.collect(a, b), level.bpm, 0.15)
	var h := Harness.new(s, self)
	var commit := 0.03
	var change_now := 0.0
	var change_beat := 0.0
	var kept_late := 0
	for i: int in 240:
		h.frame(1.0)
		if i == 119:
			change_now = h.now
			change_beat = h.beat
			seq.set_tracks(D.tracks4(D.tas({"life": OD.LifeState.GHOST}), D.tas({"synced": false}), D.tas({"transport": -1}), D.tas({"transport": 0})), h.beat)
			var cancelled := s.invalidate(h.now, commit)
			for c: AudioPlannedNote in cancelled:
				if c.time <= h.now + commit:
					kept_late += 1
			h.remove(cancelled)
	assert_eq(kept_late, 0, "nothing inside the commit window is cancelled")
	var keys := {}
	var dup := 0
	for p: AudioPlannedNote in h.log:
		var k := p.note.key()
		if keys.has(k):
			dup += 1
		keys[k] = true
	assert_eq(dup, 0, "no note planned twice")
	# Every planned note is heard on its master time (none was re-planned late).
	for p: AudioPlannedNote in h.log:
		var due := 10.0 + p.note.beat / BPS
		assert_true(p.time - due < 1.0 / 60.0 + 1e-9, "beat %s on time" % p.note.beat)
	# After the window the new composition is complete.
	var resume := change_beat + commit * BPS + 1e-6
	var end := h.beat - 0.1
	var want := seq.collect(resume, end)
	var got := 0
	for p: AudioPlannedNote in h.log:
		if p.note.beat >= resume and p.note.beat < end:
			got += 1
	assert_true(want.size() > 10)
	assert_eq(got, want.size(), "the new composition plays in full after the window")
	assert_eq(h.bad_cancels, 0)
	assert_true(change_now > 0.0)
