extends ODTest
## Acceptance: music and gameplay timing (docs/requirements.txt chapter 21: TEST-27..30). What the
## shipped game can prove without listening: gameplay timing is never adjusted for music, a
## cassette's music-facing state (GameSession.track_audio_states, the data the audio layer plays from)
## follows its own self only, and enemies keep beat time without touching the cassettes' music.
## How it sounds is by ear (docs/ACCEPTANCE.md).

const K = preload("res://tests/acceptance/acceptance_kit.gd")
const S = preload("res://tests/helpers/script.gd")


## A sleeping 1-hp grunt right in front of the start: a 1x standing light kills it.
func _strike_room() -> LevelDef:
	var ents: Array[EntityDef] = [S.enemy("g1", EnemyType.GRUNT, 7.0, 5.5, {"hp": 1, "wake": SignalExpr.of_const(false)})]
	var targets: Array[String] = ["g1"]
	return TestLevels.make_level(
		{"id": "strike", "speeds": [1.0], "bars": 2, "start": Vector2(6.0, 5.5), "entities": ents, "objective": S.objective(ObjectiveType.ELIMINATE, "Destroy the grunt", targets)}
	)


## TEST-27 - Produce a mechanically valid but unusual rhythm.
## Expected: "The solution is not rejected or steered away solely for musical reasons."
func test_TEST27_an_off_beat_solution_is_accepted_exactly_as_performed() -> void:
	var level := _strike_room()
	var tpb := ODTime.ticks_per_beat(level)
	var odd_tick := 37
	assert_true(fmod(float(odd_tick), tpb / 4.0) != 0.0, "tick 37 is off every sixteenth of the beat grid")
	var s := K.new_session(level)
	K.record_with(s, S.input_script().aim(0, 480, 0.0).press(odd_tick, ActionKind.LIGHT, 0.0))
	assert_eq(s.phase, SessionPhase.CINEMATIC, K.say("TEST-27", "the off-beat solution wins and plays as the cinematic"))
	var tape := s.pending_tape
	if not assert_true(tape != null and tape.events.size() == 1, "one recorded strike"):
		return
	assert_eq(tape.events[0].tick, odd_tick, K.say("TEST-27", "the recorded action is not moved onto the beat"))
	var swing := K.first_event(s.resolution.events, SimEventType.SWING, 0)
	var timing := PlayerController.action_timing(ActionKind.LIGHT, s.loadout)
	if assert_true(swing != null):
		assert_eq(swing.sub, (odd_tick + timing.active_start) * OD.subs_per_local_tick(1.0), K.say("TEST-27", "the strike lands when it was performed"))
	# The same solution on the beat is not treated any differently: same outcome.
	var on_beat := K.new_session(level)
	K.record_with(on_beat, S.input_script().aim(0, 480, 0.0).press(int(tpb), ActionKind.LIGHT, 0.0))
	assert_eq(on_beat.phase, SessionPhase.CINEMATIC)
	assert_eq(ReplayVerifier.outcome_key(s.resolution.outcome), ReplayVerifier.outcome_key(on_beat.resolution.outcome), K.say("TEST-27", "rhythm alone does not change the result"))


## TEST-28 - Produce ordinary movement/combat sounds.
## Expected: "They use the agreed fine rhythmic integration policy; no unapproved gameplay-time
## adjustment." The policy (ARCHITECTURE "Music"): sounds are nudged to the next sixteenth, late only,
## by at most one sixteenth, in the AUDIO layer; gameplay timing is never touched.
func test_TEST28_sound_events_keep_their_gameplay_time_and_the_late_only_sfx_policy_is_shipped() -> void:
	# The two-cassette rescue: tape B is recorded live while tape A plays back, and nobody dies, so
	# every sound-bearing event of the live take must reappear in the authoritative run.
	var level := K.rescue_room()
	var a := S.record_take(level, 0, 1.0, K.tape_a_script())
	var take := S.record_take(level, 1, 2.0, K.tape_b_script(), [a.tape])
	var res := K.resolve(level, [a.tape, take.tape])
	assert_true(res.outcome.win, "fixture: the rescue win")
	# No gameplay-time adjustment: every sound-bearing event (steps, swings, hits, kills, switch,
	# door) happens at the same substep in the take and in the authoritative run, off the beat grid
	# where it fell.
	var kinds: Array[StringName] = [SimEventType.STEP, SimEventType.SWING, SimEventType.HIT, SimEventType.KILL, SimEventType.INTERACT, SimEventType.DOOR, SimEventType.ENEMY_SHOT, SimEventType.ENEMY_TELEGRAPH, SimEventType.PROJECTILE_HIT]
	var rec_rows: Array = []
	var rep_rows: Array = []
	for e: SimEvent in take.events:
		if e.type in kinds:
			rec_rows.append("%d|%s|%d|%s" % [e.sub, e.type, e.tape, e.id])
	# The live take ends with tape B's recording; the authoritative run goes on to the horizon, so
	# compare up to the last substep the take covered.
	var take_end := take.frames[take.frames.size() - 1].sub
	for e: SimEvent in res.events:
		if e.type in kinds and e.sub <= take_end:
			rep_rows.append("%d|%s|%d|%s" % [e.sub, e.type, e.tape, e.id])
	assert_true(rec_rows.size() > 3, K.say("TEST-28", "the live take emits sound-bearing events (%d)" % rec_rows.size()))
	assert_eq(rep_rows, rec_rows, K.say("TEST-28", "sound events moved between recording and replay"))
	var spb := ODTime.subs_per_beat(level)
	var off_grid := 0
	for e: SimEvent in K.events_of(res.events, SimEventType.STEP):
		if fmod(float(e.sub), spb / 4.0) != 0.0:
			off_grid += 1
	assert_true(off_grid > 0, K.say("TEST-28", "footsteps were snapped to sixteenths in gameplay time"))
	# Playback re-emits each event at its own instant (sub + 1), never delayed to a grid.
	var s := K.new_session(K.rescue_room(1))
	K.record_with(s, K.tape_a_script())
	s.drain_events()
	var played := 0.0
	var late := 0
	while s.phase == SessionPhase.REVIEW:
		s.advance(K.STEP)
		played = minf(played + K.STEP * OD.SUB_HZ, s.horizon_subs)
		for e: SimEvent in s.drain_events():
			if e.sub + 1 < played - K.STEP * OD.SUB_HZ - 1e-6:
				late += 1
	assert_eq(late, 0, K.say("TEST-28", "events the session held back past their own instant"))
	# The fine rhythmic integration policy itself belongs to the audio layer's SFX scheduler.
	var found := _audio_scripts_defining(["quantize_late", "quantise_late"])
	assert_false(found.is_empty(), K.say("TEST-28", "no audio script ships the late-only sixteenth SFX quantiser (prototype audio/sfx.ts quantizeLate); res://audio holds only %s" % [_audio_files()]))


func _audio_files() -> Array[String]:
	var out: Array[String] = []
	_collect("res://audio", out)
	return out


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for f: String in dir.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))


func _audio_scripts_defining(names: Array) -> Array[String]:
	var out: Array[String] = []
	for path: String in _audio_files():
		var src := FileAccess.get_file_as_string(path)
		for n: String in names:
			if src.contains("func " + n):
				out.append(path)
	return out


## TEST-29 - Kill/desync a cassette.
## Expected: "Its own generated musical channel changes state; shared coherence remains a design goal."
func test_TEST29_a_dead_or_desynced_cassette_changes_only_its_own_music_channel_state() -> void:
	# Death: tape A dies in its review; track 0 turns ghost, the rest do not change.
	var s := K.new_session(K.rescue_room())
	K.record_with(s, K.tape_a_script())
	var death := K.first_event(s.resolution.events, SimEventType.SELF_DEATH, 0)
	if not assert_true(death != null):
		return
	var before: Array = []
	var after: Array = []
	while s.phase == SessionPhase.REVIEW:
		s.advance(K.STEP)
		var sub := s.current_frame().snap.sub
		var tr := s.track_audio_states()
		if sub < death.sub - OD.FRAME_SUBS and before.is_empty():
			before = _track_rows(tr)
		if sub > death.sub + OD.FRAME_SUBS * 2 and after.is_empty():
			after = _track_rows(tr)
	if not assert_true(not before.is_empty() and not after.is_empty(), "sampled both sides of the death"):
		return
	assert_eq(before[0][2], OD.LifeState.ALIVE)
	assert_eq(after[0][2], OD.LifeState.GHOST, K.say("TEST-29", "the dead cassette's channel state"))
	for i: int in range(1, 4):
		assert_eq(after[i], before[i], K.say("TEST-29", "channel %d is not touched by tape A's death" % i))
	# Desync: B closes the door across A's run (Scenario I) and only A's channel loses sync.
	# The golden room is a reach level tape A wins alone; here the objective can never complete, so
	# the session goes on to a second take instead of the cinematic.
	var lv := K.golden_run("desync-scenario-i-detour").level.copy()
	lv.objective = S.objective(ObjectiveType.SIGNAL, "Hold the line", [], SignalExpr.of_const(false))
	var d := K.new_session(lv)
	K.record_with(d, S.input_script().run(0, 480, 1, 0))
	K.advance_until_phase_changes(d)
	d.act(SessionAction.COMMIT)
	K.record_with(d, S.input_script().press(5, ActionKind.INTERACT))
	var ds := K.first_event(d.resolution.events, SimEventType.DESYNC, 0)
	if not assert_true(ds != null, K.say("TEST-29", "tape A desyncs in the combined run")):
		return
	var saw_desync := false
	var other_changed := false
	var b_first: Array = []
	while d.phase == SessionPhase.REVIEW or d.phase == SessionPhase.CINEMATIC:
		d.advance(K.STEP)
		var rows := _track_rows(d.track_audio_states())
		var snap := d.current_frame().snap
		if snap.sub > ds.sub + OD.FRAME_SUBS and not snap.actor(0).synced:
			saw_desync = saw_desync or rows[0][3] == false
		if b_first.is_empty():
			b_first = rows[1]
		elif rows[1].slice(0, 4) != b_first.slice(0, 4):
			other_changed = true
	assert_true(saw_desync, K.say("TEST-29", "the desynced cassette's channel reports desync"))
	assert_false(other_changed, K.say("TEST-29", "tape B's channel changed state because of A's desync"))
	# Each cassette has its own generated layer: the level music defines one track per cassette.
	var formulas := {}
	for t: TrackMusicDef in lv.music.tracks:
		formulas[t.formula] = true
	assert_eq(lv.music.tracks.size(), OD.TAPE_COUNT, K.say("TEST-29", "one generated channel per cassette"))
	assert_eq(formulas.size(), OD.TAPE_COUNT, K.say("TEST-29", "each channel has its own formula"))


## [present, speed, life, synced, transport] per track.
func _track_rows(tracks: Array[TrackAudioState]) -> Array:
	var out: Array = []
	for t: TrackAudioState in tracks:
		out.append([t.present, t.speed, t.life, t.synced, t.transport])
	return out


## TEST-30 - Let enemies attack.
## Expected: "Their timing can be beat-based, but they do not directly rewrite player wave functions."
func test_TEST30_enemy_attacks_keep_beat_time_but_never_rewrite_a_cassettes_music() -> void:
	# Two cassettes stand in the turret's line (A as scripted, B idle at the start), so the turret
	# fires more than once in the combined run.
	var level := K.rescue_room(2)
	var music_before := ODJson.stringify(level.music.to_dict())
	var s := K.new_session(level)
	if not assert_true(K.take_a_to_decision(s) and s.act(SessionAction.COMMIT), "fixture: tape A committed"):
		return
	K.record_with(s, null)
	var res := s.resolution
	var spb := ODTime.subs_per_beat(level)
	var attacks: Array[SimEvent] = []
	for e: SimEvent in res.events:
		if e.type == SimEventType.ENEMY_SHOT or e.type == SimEventType.ENEMY_ATTACK:
			attacks.append(e)
	if not assert_true(attacks.size() >= 2, K.say("TEST-30", "the turret attacks")):
		return
	# Beat-based timing: every shot / strike falls on the enemy's beat grid (offset + k * every); the
	# telegraph that announces it comes a beat earlier and is not checked here.
	var off := 0
	for e: SimEvent in attacks:
		var def: EnemyDef = null
		for x: EntityDef in level.entities_of(EntityKind.ENEMY):
			if x.id == e.id:
				def = x
		var st := Tuning.enemy_stats(def.type)
		var every: float = float(def.beat_every) if def.has_beat else st.every
		var offset: float = def.beat_offset if def.has_beat else st.offset
		var b := e.sub / spb
		if absf(fposmod(b - offset + 1e-9, every) - 1e-9) > 1e-6:
			off += 1
	assert_eq(off, 0, K.say("TEST-30", "enemy attack events off their beat grid"))
	# They do not rewrite player wave functions: the level music is untouched by the run, and each
	# cassette's channel state does not change while it is merely attacked (only its own death does).
	assert_eq(ODJson.stringify(level.music.to_dict()), music_before, K.say("TEST-30", "the music definition changed"))
	var death := K.first_event(res.events, SimEventType.SELF_DEATH, 0)
	var first_threat := attacks[0]
	for e: SimEvent in res.events:
		if e.type == SimEventType.SELF_DEATH and (death == null or e.sub < death.sub):
			death = e
	var rows: Array = []
	while s.phase == SessionPhase.REVIEW:
		s.advance(K.STEP)
		var sub := s.current_frame().snap.sub
		if sub >= first_threat.sub and (death == null or sub < death.sub):
			rows.append(_track_rows(s.track_audio_states()))
	assert_true(rows.size() > 2, "sampled the window between the first attack and the death")
	var changed := 0
	for r: Array in rows:
		if r != rows[0]:
			changed += 1
	assert_eq(changed, 0, K.say("TEST-30", "a cassette's channel changed while enemies attacked it"))
	# A cassette's music state has no enemy input at all (TrackAudioState fields).
	var fields: Array = []
	for p: Dictionary in TrackAudioState.new().get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			fields.append(p["name"])
	assert_eq(fields, ["present", "speed", "life", "synced", "transport"], K.say("TEST-30", "the per-cassette music state is fed by the self only"))
