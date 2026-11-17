class_name GameSession
extends RefCounted
## One level attempt (port of prototype/src/game/session.ts; ARCHITECTURE "Session flow", REC-01..08,
## OPEN-07, OPEN-21).
##
##   briefing → setup → countin → recording → review → decision → (setup | cinematic → results)
##
## The session is node-free and deterministic: the app feeds it wall time (`advance`), one input per
## local tick while recording (`tick_local`) and player choices (`act`). Everything the HUD, the
## renderer and the audio layer need comes back out through `view()`, `current_frame()`,
## `drain_events()`, `drain_cues()` and `track_audio_states()`.
##
## Rules this file is responsible for:
##  - every take restarts the encounter at beat zero with the COMMITTED tapes playing and nothing
##    else (REC-02, REC-03; future cassettes do not exist yet);
##  - retry_take discards only the pending take (REC-04); commit locks it and arms the next cassette;
##    reset_all wipes every cassette and is the only way to change an older one (REC-05);
##  - the authoritative result is resolve_encounter over committed + pending under playback rules,
##    never the live take's own run, so a recording ghost's provisional effects cannot win
##    (REC-06, OPEN-07, chapter 06 "final-tape edge case");
##  - a winning resolution plays as the locked cinematic and goes to results (CINE-01..05); a failing
##    one plays as a skippable review (REC-08) and then waits for a decision; nothing is ever
##    committed automatically (chapter 04);
##  - boss memory is rebuilt from committed tapes only, on commit and on reset (BOSS-01/02);
##  - pausing mid-take aborts the take back to setup; there is no tactical pause (OPEN-21).
##
## Port addition — the resolving beat. resolve_encounter is slow in GDScript (about 0.3-1.3 s for a
## full encounter), so with `async_resolve` the session resolves on a worker Thread: when a take
## ends the phase becomes REVIEW at once with an internal "resolving" sub-state (GameSessionView
## .resolving / .resolve_progress, shown by the HUD as "Rewinding tape…"); no actions are offered and
## master time stands still. When the result arrives the session proceeds exactly as the prototype
## did on the same instant: the 'resolved' cue, then the 'phase' cue to review or cinematic (its
## `from` is recording, as in the prototype). Without `async_resolve` (tests, the bot) resolving is
## synchronous and the session behaves exactly like the prototype.
##
## The prototype re-resolved the committed tapes on retry. Resolving is deterministic, so the port
## keeps the committed-only run it already has (the reviewed run, once committed) and reuses it; only
## a boss level re-resolves on commit (its memory changed), in the background when async.

## Count-in length in beats ("five, six, seven, eight"; UI-04).
const COUNT_IN_BEATS: int = 4
## How far ahead the beatSight ruler looks for enemy attacks, in master beats.
const THREAT_LOOKAHEAD_BEATS: float = 8.0
const MAX_THREATS: int = 8
## Shortest time the resolving beat stays on screen in async mode, so it reads as a beat rather than
## a flicker (wall seconds).
const MIN_RESOLVING_SECONDS: float = 0.35

const CUE_PHASE: StringName = &"phase"
const CUE_COUNT: StringName = &"count"
const CUE_UI: StringName = &"ui"
## A take was abandoned (pause during count-in or recording).
const CUE_TAKE_ABORTED: StringName = &"takeAborted"
## The authoritative result of the take just recorded is known.
const CUE_RESOLVED: StringName = &"resolved"
## Port addition: the take just ended and its result is being resolved ("rewinding tape").
const CUE_RESOLVING: StringName = &"resolving"
## Port addition: resolving failed (should not happen; the take is discarded back to setup).
const CUE_RESOLVE_FAILED: StringName = &"resolveFailed"


## A presentation cue that is not a simulation event (audio blips, count-in, phase changes).
class Cue:
	extends RefCounted
	## CUE_*.
	var kind: StringName = &""
	## CUE_PHASE: the new phase and the one it left.
	var phase: StringName = &""
	var from: StringName = &""
	## CUE_COUNT: 5, 6, 7 or 8.
	var n: int = 0
	## CUE_UI: AudioBase.UI_* (select, speed, commit, retry, reset, win, fail).
	var sound: StringName = &""
	## CUE_RESOLVED.
	var outcome: Outcome = null
	## CUE_RESOLVE_FAILED.
	var message: String = ""

	static func make(p_kind: StringName) -> Cue:
		var c := Cue.new()
		c.kind = p_kind
		return c


## The snapshot pair to draw (prototype SessionFrame).
class SessionFrame:
	extends RefCounted
	var snap: FrameSnapshot = null
	var prev: FrameSnapshot = null
	var alpha: float = 1.0

	static func make(p_snap: FrameSnapshot, p_prev: FrameSnapshot, p_alpha: float) -> SessionFrame:
		var f := SessionFrame.new()
		f.snap = p_snap
		f.prev = p_prev
		f.alpha = p_alpha
		return f


## One resolve_encounter run, synchronous or on a worker thread.
class ResolveJob:
	extends RefCounted
	var config: SimConfig = null
	var token: ODResolve.CancelToken = ODResolve.CancelToken.new()
	var errors: Array[String] = []
	var thread: Thread = null
	var _mutex: Mutex = Mutex.new()
	var _progress: float = 0.0
	var _done: bool = false
	var _result: Resolution = null

	func run_sync() -> Resolution:
		_result = ODResolve.resolve_encounter(config, Callable(), token, errors)
		_progress = 1.0
		_done = true
		return _result

	func start() -> void:
		thread = Thread.new()
		thread.start(_work)

	func _work() -> void:
		var r := ODResolve.resolve_encounter(config, _on_progress, token, errors)
		_mutex.lock()
		_result = r
		_progress = 1.0
		_done = true
		_mutex.unlock()

	func _on_progress(f: float) -> void:
		_mutex.lock()
		_progress = f
		_mutex.unlock()

	func progress() -> float:
		_mutex.lock()
		var p := _progress
		_mutex.unlock()
		return p

	func is_done() -> bool:
		_mutex.lock()
		var d := _done
		_mutex.unlock()
		return d

	## Join the worker (if any) and return the result (null on failure / cancel).
	func finish() -> Resolution:
		if thread != null and thread.is_started():
			thread.wait_to_finish()
		thread = null
		return _result

	func cancel() -> void:
		token.cancel()
		finish()


var level: LevelDef = null
var loadout: ResolvedLoadout = null
## Master substeps in the encounter.
var horizon_subs: int = 0
## Local ticks in one recording.
var tape_ticks: int = 0
## Resolve on worker threads (the game). False: synchronously (tests, the bot).
var async_resolve: bool = false

var _spb: float = 0.0
var _speeds: Array[float] = []
var _phase: StringName = SessionPhase.BRIEFING
var _committed: Array[ODTape] = []
var _pending: ODTape = null
var _speed: float = 1.0
var _end_mode: int = OD.EndMode.STOP

var _live: ODSim = null
var _live_snap: FrameSnapshot = null
var _live_prev: FrameSnapshot = null
var _live_marks: Array = [[], [], [], []]
var _live_mark_tick: int = -1
var _live_mark_cache: Array[DeckMark] = []

## Latest authoritative run: committed tapes (+ the pending take during review → results).
var _resolution: Resolution = null
var _resolved_marks: Array = [[], [], [], []]
## The run of exactly the committed tapes under the current boss memory, when known (null = none /
## not yet known). Reused by retry_take.
var _committed_res: Resolution = null

var _boss_memory: BossMemory = null
var _boss_memory_builds: int = 0

var _count_t: float = 0.0
var _count: int = 0
## Master substeps (float) into the review / cinematic playback.
var _play_sub: float = 0.0
## Index of the next Resolution event to re-emit during review / cinematic.
var _event_cursor: int = 0

var _idle: FrameSnapshot = null
var _events: Array[SimEvent] = []
var _cues: Array[Cue] = []

## The take's resolve while resolving (null otherwise), and the frozen picture shown meanwhile.
var _take_job: ResolveJob = null
var _resolving_snap: FrameSnapshot = null
var _resolving_t: float = 0.0
## Background re-resolve of the committed tapes after a boss-level commit.
var _committed_job: ResolveJob = null
var _disposed: bool = false


## Build a session. Returns null (and appends the reason to `errors`) for a level the kernel cannot
## run: no speeds, no end modes, or a config the sim rejects (e.g. an unregistered enemy type), so
## the app can report it rather than fail mid-frame.
static func create(p_level: LevelDef, p_loadout: ResolvedLoadout, skip_briefing: bool = false, p_async: bool = false, errors: Array[String] = []) -> GameSession:
	var s := GameSession.new()
	if not s._setup(p_level, p_loadout, skip_briefing, p_async, errors):
		return null
	return s


func _setup(p_level: LevelDef, p_loadout: ResolvedLoadout, skip_briefing: bool, p_async: bool, errors: Array[String]) -> bool:
	level = p_level
	loadout = p_loadout
	async_resolve = p_async
	horizon_subs = int(ODTime.horizon_subs(p_level))
	tape_ticks = int(ODTime.tape_ticks(p_level))
	_spb = ODTime.subs_per_beat(p_level)
	for sp: float in p_level.speeds:
		if not _speeds.has(sp):
			_speeds.append(sp)
	_speeds.sort()
	if _speeds.is_empty():
		errors.append("Level %s offers no tape speeds" % p_level.id)
		return false
	if p_level.end_modes.is_empty():
		errors.append("Level %s offers no end modes" % p_level.id)
		return false
	_speed = _default_speed()
	_end_mode = _default_end_mode()
	_boss_memory = _rebuild_boss_memory()
	_phase = SessionPhase.SETUP if skip_briefing else SessionPhase.BRIEFING
	if async_resolve:
		# Registries fill lazily; do it here on the main thread before any worker reads them.
		ODCore.ensure_registered()
	# Built eagerly so a level the kernel cannot run fails here, where the app can report it.
	if _idle_frame(errors) == null:
		return false
	return true


## Stop any worker thread (and wait for it). Call when the session is abandoned (the app does, and
## so does every path that replaces a session); a session dropped mid-resolve without dispose() leaves
## its worker to finish on its own.
func dispose() -> void:
	_disposed = true
	_cancel_jobs()


func _cancel_jobs() -> void:
	if _take_job != null:
		_take_job.cancel()
		_take_job = null
	if _committed_job != null:
		_committed_job.cancel()
		_committed_job = null

# ───────────────────────────── read-only state ─────────────────────────────

var phase: StringName:
	get:
		return _phase

## Committed tapes in cassette order (a copy of the array; tapes are immutable by convention).
var committed_tapes: Array[ODTape]:
	get:
		return _committed.duplicate()

var pending_tape: ODTape:
	get:
		return _pending

var resolution: Resolution:
	get:
		return _resolution

var boss_memory: BossMemory:
	get:
		return _boss_memory

## How many times boss memory has been (re)built; it changes only on commit and reset.
var boss_memory_builds: int:
	get:
		return _boss_memory_builds

var speed: float:
	get:
		return _speed

var end_mode: int:
	get:
		return _end_mode

## The live record-mode sim while counting in / recording, else null.
var live_sim: ODSim:
	get:
		return _live

## True during the resolving beat (phase REVIEW, result not known yet).
var resolving: bool:
	get:
		return _take_job != null

## 0..1 progress of the resolving beat (1 when not resolving).
var resolve_progress: float:
	get:
		return _take_job.progress() if _take_job != null else 1.0

## Cassette being configured / recorded / decided on, or -1 when no take is in play.
var active_index: int:
	get:
		if _phase == SessionPhase.BRIEFING or _phase == SessionPhase.CINEMATIC or _phase == SessionPhase.RESULTS:
			return -1
		return _committed.size() if _committed.size() < level.max_tapes else -1

## Tapes that make up the latest resolved run (committed + pending).
var tapes_used: int:
	get:
		return _committed.size() + (1 if _pending != null else 0)

## Outcome of the latest resolved run including the pending take; null when there is none.
var outcome: Outcome:
	get:
		return _resolution.outcome if _resolution != null and _pending != null else null

## Seconds of wall time one count-in beat lasts (base tempo; UI-04).
var count_beat_seconds: float:
	get:
		return 60.0 / level.bpm

# ───────────────────────────── actions ─────────────────────────────


## Session actions currently offered (exactly what `act` will accept, plus 'quit').
func actions() -> Array[StringName]:
	var a: Array[StringName] = []
	match _phase:
		SessionPhase.BRIEFING:
			a.append_array([SessionAction.START, SessionAction.QUIT])
		SessionPhase.SETUP:
			var i := _speeds.find(_speed)
			if i < _speeds.size() - 1:
				a.append(SessionAction.SPEED_UP)
			if i > 0:
				a.append(SessionAction.SPEED_DOWN)
			if level.end_modes.size() > 1:
				a.append(SessionAction.CYCLE_END_MODE)
			a.append(SessionAction.RECORD)
			if _committed.size() > 0:
				a.append(SessionAction.RESET_ALL)
			a.append(SessionAction.QUIT)
		SessionPhase.COUNTIN:
			pass
		SessionPhase.RECORDING:
			a.append(SessionAction.QUIT)
		SessionPhase.REVIEW:
			# Nothing to skip while the result is still being resolved.
			if _take_job == null:
				a.append_array([SessionAction.SKIP, SessionAction.END_ATTEMPT])
		SessionPhase.DECISION:
			a.append(SessionAction.RETRY_TAKE)
			if _can_commit():
				a.append(SessionAction.COMMIT)
			a.append_array([SessionAction.RESET_ALL, SessionAction.QUIT])
		SessionPhase.CINEMATIC:
			# Skipping only stops watching; the result is already fixed (CINE-02, TEST-32).
			a.append(SessionAction.SKIP)
		SessionPhase.RESULTS:
			a.append_array([SessionAction.CONTINUE, SessionAction.QUIT])
	return a


## Apply a player choice. Returns true when it changed something (or, for 'quit' / 'continue', when
## the app should act on it). Actions not offered in the current phase are ignored.
func act(action: StringName) -> bool:
	if action == SessionAction.QUIT:
		if _phase == SessionPhase.COUNTIN or _phase == SessionPhase.RECORDING:
			abort_take()
		return true
	if not actions().has(action):
		return false
	match action:
		SessionAction.START:
			_set_phase(SessionPhase.SETUP)
			_cue_ui(AudioBase.UI_SELECT)
			return true
		SessionAction.SPEED_UP, SessionAction.SPEED_DOWN:
			var i := _speeds.find(_speed) + (1 if action == SessionAction.SPEED_UP else -1)
			_speed = _speeds[clampi(i, 0, _speeds.size() - 1)]
			_idle = null
			_cue_ui(AudioBase.UI_SPEED)
			return true
		SessionAction.CYCLE_END_MODE:
			var modes := level.end_modes
			_end_mode = modes[(modes.find(_end_mode) + 1) % modes.size()]
			_idle = null
			_cue_ui(AudioBase.UI_SELECT)
			return true
		SessionAction.RECORD:
			_begin_count_in()
			return true
		SessionAction.SKIP, SessionAction.END_ATTEMPT:
			if _phase == SessionPhase.CINEMATIC:
				_enter_results()
			else:
				_enter_decision()
			return true
		SessionAction.RETRY_TAKE:
			_retry_take()
			return true
		SessionAction.COMMIT:
			_commit()
			return true
		SessionAction.RESET_ALL:
			_reset_all()
			return true
		SessionAction.CONTINUE:
			return true
	return false


## Abandon a take in count-in or recording and return to setup with the same cassette armed
## (OPEN-21: no mid-take tactical pause). Returns false when no take was in progress.
func abort_take() -> bool:
	if _phase != SessionPhase.COUNTIN and _phase != SessionPhase.RECORDING:
		return false
	_drop_live()
	_count = 0
	_cue(Cue.make(CUE_TAKE_ABORTED))
	_set_phase(SessionPhase.SETUP)
	return true


## Wipe every cassette from any phase (the pause menu's "restart"; REC-05). Unlike act('resetAll'),
## which is offered only where the HUD shows it, this always applies, except once the level has been
## won (cinematic / results), where there is no attempt left to restart.
func restart_attempt() -> bool:
	if _phase == SessionPhase.CINEMATIC or _phase == SessionPhase.RESULTS:
		return false
	_reset_all()
	return true

# ───────────────────────────── clocks ─────────────────────────────


## One local tick of live control. Only meaningful while recording; returns false otherwise. The
## take ends when the local allowance is used up (or the encounter horizon is reached). Death does
## not end it (GHOST-01).
func tick_local(input: PlayerInput) -> bool:
	poll_jobs()
	if _phase != SessionPhase.RECORDING or _live == null:
		return false
	var sim := _live
	_live_prev = _live_snap
	sim.step_local_tick(input)
	_live_snap = sim.snapshot()
	for e: SimEvent in sim.drain_events():
		_events.append(e)
		_note_state_mark(_live_marks, e)
	if sim.done or sim.sub >= horizon_subs:
		_finish_take()
	return true


## Advance wall-clock driven phases: count-in, the resolving beat, review and cinematic playback.
func advance(dt_wall_seconds: float) -> void:
	var dt := dt_wall_seconds if not is_nan(dt_wall_seconds) and not is_inf(dt_wall_seconds) and dt_wall_seconds > 0.0 else 0.0
	poll_jobs(dt)
	if dt == 0.0:
		return
	if _phase == SessionPhase.COUNTIN:
		_count_t += dt
		var b := int(floorf(_count_t / count_beat_seconds))
		if b >= COUNT_IN_BEATS:
			_count = 0
			_set_phase(SessionPhase.RECORDING)
			return
		var n := 5 + b
		if n != _count:
			_count = n
			var c := Cue.make(CUE_COUNT)
			c.n = n
			_cue(c)
		return
	if _take_job != null:
		return
	if _phase == SessionPhase.REVIEW or _phase == SessionPhase.CINEMATIC:
		# True master speed: SUB_HZ substeps per wall second (CINE-01, CINE-04).
		_play_sub = minf(horizon_subs, _play_sub + dt * OD.SUB_HZ)
		_emit_playback_events()
		if _play_sub >= horizon_subs:
			if _phase == SessionPhase.REVIEW:
				_enter_decision()
			else:
				_enter_results()


## Collect finished background resolves. `dt` (wall seconds) counts toward the resolving beat's
## minimum on-screen time in async mode. Called by advance() and tick_local(); safe to call any time.
func poll_jobs(dt: float = 0.0) -> void:
	if _committed_job != null and _committed_job.is_done():
		var job := _committed_job
		_committed_job = null
		var r := job.finish()
		if r != null:
			_committed_res = r
			if _pending == null and _take_job == null:
				_set_resolution(r)
	if _take_job != null:
		_resolving_t += dt
		if _take_job.is_done() and (_take_job.thread == null or _resolving_t >= MIN_RESOLVING_SECONDS):
			var job2 := _take_job
			_take_job = null
			var res := job2.finish()
			if res == null:
				_resolve_failed(job2.errors)
			else:
				_proceed_with(res)

# ───────────────────────────── outputs ─────────────────────────────


## The snapshot pair to draw. While recording, `record_alpha` is the fraction of the next local tick
## that has elapsed in wall time (the app's fixed-step accumulator); playback phases compute their
## own interpolation from the playback clock. `visual_delay_seconds` is the settings A/V offset
## (positive = picture later), applied to review / cinematic playback only.
func current_frame(record_alpha: float = 1.0, visual_delay_seconds: float = 0.0) -> SessionFrame:
	match _phase:
		SessionPhase.COUNTIN, SessionPhase.RECORDING:
			var snap := _live_snap if _live_snap != null else _idle_frame()
			return SessionFrame.make(snap, _live_prev if _live_prev != null else snap, clampf(record_alpha, 0.0, 1.0) if _phase == SessionPhase.RECORDING else 1.0)
		SessionPhase.REVIEW, SessionPhase.CINEMATIC, SessionPhase.DECISION, SessionPhase.RESULTS:
			if _take_job != null and _resolving_snap != null:
				return SessionFrame.make(_resolving_snap, _resolving_snap, 1.0)
			if _resolution != null:
				# Playback is presentation only, so the picture can be shifted against the audible
				# playhead. A live take cannot be.
				var delay := visual_delay_seconds * OD.SUB_HZ if _phase == SessionPhase.REVIEW or _phase == SessionPhase.CINEMATIC else 0.0
				if is_nan(delay) or is_inf(delay):
					delay = 0.0
				return _playback_frame(minf(horizon_subs, maxf(0.0, _play_sub - delay)))
	var idle := _idle_frame()
	return SessionFrame.make(idle, idle, 1.0)


## Simulation events since the last drain: live events while recording, re-emitted ones in playback.
func drain_events() -> Array[SimEvent]:
	var out := _events
	_events = []
	return out


func drain_cues() -> Array[Cue]:
	var out := _cues
	_cues = []
	return out


## Music layer state per cassette for this instant (MUSIC-02; dead / desynced / reversing layers).
func track_audio_states() -> Array[TrackAudioState]:
	var snap := current_frame().snap
	var playing := is_playing()
	var out: Array[TrackAudioState] = []
	for i in OD.TAPE_COUNT:
		var cfg := _deck_config(i)
		var actor := snap.actor(i)
		out.append(TrackAudioState.make(
			not cfg.is_empty(),
			float(cfg["speed"]) if not cfg.is_empty() else 1.0,
			actor.life if actor != null else OD.LifeState.ALIVE,
			actor.synced if actor != null else true,
			actor.phase.dir if playing and actor != null else 0))
	return out


## Everything the HUD needs this frame.
func view() -> GameSessionView:
	var snap := current_frame().snap
	var rate := world_rate()
	var v := GameSessionView.new()
	v.phase = _phase
	v.level = level
	v.decks.clear()
	for i in OD.TAPE_COUNT:
		v.decks.append(_deck_view(i, snap, rate))
	var active := active_index
	v.active = active
	v.beat = snap.beat
	v.horizon_beats = horizon_subs / _spb
	v.world_rate = rate
	v.count = _count
	v.speeds = _speeds.duplicate()
	v.end_modes = level.end_modes.duplicate()
	v.objective = ObjectiveView.make(snap.objective, level.objective.text)
	var show_outcome := _phase == SessionPhase.DECISION or _phase == SessionPhase.CINEMATIC or _phase == SessionPhase.RESULTS
	v.outcome = outcome if show_outcome else null
	v.actions = actions()
	v.threat_beats = _threat_beats(snap)
	v.hint = level.hints.get(active + 1, "") if _phase == SessionPhase.SETUP and active >= 0 else ""
	v.resolving = _take_job != null
	v.resolve_progress = resolve_progress if v.resolving else 0.0
	v.status_text = GameSessionView.RESOLVING_TEXT if v.resolving else ""
	return v


## Master seconds per wall second right now (1/speed while recording; TIME-03).
func world_rate() -> float:
	if _phase == SessionPhase.RECORDING:
		return 1.0 / _speed
	if (_phase == SessionPhase.REVIEW or _phase == SessionPhase.CINEMATIC) and _take_job == null:
		return 1.0
	return 0.0


## True while master time is moving (recording, review, cinematic).
func is_playing() -> bool:
	if _take_job != null:
		return false
	return _phase == SessionPhase.RECORDING or _phase == SessionPhase.REVIEW or _phase == SessionPhase.CINEMATIC

# ───────────────────────────── transitions ─────────────────────────────


func _set_phase(p: StringName) -> void:
	if p == _phase:
		return
	var from := _phase
	_phase = p
	# The beat-zero picture differs between briefing (no armed self) and setup (armed self).
	if p == SessionPhase.SETUP or p == SessionPhase.BRIEFING:
		_idle = null
	_cue_phase(p, from)


func _cue_phase(p: StringName, from: StringName) -> void:
	var c := Cue.make(CUE_PHASE)
	c.phase = p
	c.from = from
	_cue(c)


func _cue(c: Cue) -> void:
	_cues.append(c)


func _cue_ui(sound: StringName) -> void:
	var c := Cue.make(CUE_UI)
	c.sound = sound
	_cue(c)


func _can_commit() -> bool:
	return _pending != null and _committed.size() + 1 < level.max_tapes


func _config(tapes: Array[ODTape], live: LiveTake = null) -> SimConfig:
	return SimConfig.make(level, loadout, tapes, live, _boss_memory)


func _begin_count_in() -> void:
	var index := _committed.size()
	# REC-02 / REC-03: the encounter is rebuilt from beat zero with exactly the committed tapes.
	var errors: Array[String] = []
	_live = ODSim.create_sim(_config(_committed.duplicate(), LiveTake.make(index, _speed, _end_mode)), errors)
	if _live == null:
		push_error("GameSession: cannot start a take: %s" % ", ".join(errors))
		return
	_live_snap = _live.snapshot()
	_live_prev = _live_snap
	_live_marks = [[], [], [], []]
	_live_mark_tick = -1
	_events = []
	_count_t = 0.0
	_count = 5
	_set_phase(SessionPhase.COUNTIN)
	var c := Cue.make(CUE_COUNT)
	c.n = 5
	_cue(c)


func _finish_take() -> void:
	var take := _live.live_tape()
	var last := _live_snap
	_drop_live()
	_pending = take
	# OPEN-07: only the combined run under playback rules decides; the live run (with any
	# recording-ghost effects) is discarded here.
	var tapes := _committed.duplicate()
	tapes.append(take)
	_play_sub = 0.0
	_event_cursor = 0
	if not async_resolve:
		var job := _make_job(tapes)
		var res := job.run_sync()
		if res == null:
			_resolve_failed(job.errors)
		else:
			_proceed_with(res)
		return
	# The resolving beat: phase REVIEW (no cue yet), frozen on the take's last picture.
	_set_resolution(null)
	_resolving_snap = last
	_resolving_t = 0.0
	_phase = SessionPhase.REVIEW
	_take_job = _make_job(tapes)
	_take_job.start()
	_cue(Cue.make(CUE_RESOLVING))


func _make_job(tapes: Array[ODTape]) -> ResolveJob:
	var job := ResolveJob.new()
	var cfg := _config(tapes)
	# A worker gets its own copy of everything it reads (ODResolve's threading contract).
	job.config = cfg.deep_copy() if async_resolve else cfg
	return job


## The result of the take just recorded is known: continue exactly as the prototype's finishTake.
func _proceed_with(res: Resolution) -> void:
	_resolving_snap = null
	_set_resolution(res)
	_play_sub = 0.0
	_event_cursor = 0
	var c := Cue.make(CUE_RESOLVED)
	c.outcome = res.outcome
	_cue(c)
	var next := SessionPhase.REVIEW
	if res.outcome.win:
		_cue_ui(AudioBase.UI_WIN)
		next = SessionPhase.CINEMATIC
	# Leaving the take: the phase cue is the one the prototype emitted (from 'recording').
	_phase = next
	_cue_phase(next, SessionPhase.RECORDING)


func _resolve_failed(errors: Array[String]) -> void:
	_resolving_snap = null
	var msg := ", ".join(errors) if not errors.is_empty() else "unknown error"
	push_error("GameSession: resolving the take failed: %s" % msg)
	_pending = null
	_set_resolution(_committed_res if not _committed.is_empty() else null)
	var c := Cue.make(CUE_RESOLVE_FAILED)
	c.message = msg
	_cue(c)
	_idle = null
	_phase = SessionPhase.RECORDING
	_set_phase(SessionPhase.SETUP)


func _enter_decision() -> void:
	_play_sub = horizon_subs
	_event_cursor = _resolution.events.size() if _resolution != null else 0
	_cue_ui(AudioBase.UI_FAIL)
	_set_phase(SessionPhase.DECISION)


func _enter_results() -> void:
	_play_sub = horizon_subs
	_event_cursor = _resolution.events.size() if _resolution != null else 0
	_set_phase(SessionPhase.RESULTS)


func _retry_take() -> void:
	_pending = null
	# The latest resolved run now describes only the committed tapes again (known already: the run
	# reviewed before this take, or the background re-resolve after a boss commit).
	_set_resolution(_committed_res if not _committed.is_empty() else null)
	if not _committed.is_empty() and _committed_res == null and _committed_job == null:
		_start_committed_resolve()
	_idle = null
	_cue_ui(AudioBase.UI_RETRY)
	_set_phase(SessionPhase.SETUP)


func _commit() -> void:
	var take := _pending
	_committed.append(take)
	_pending = null
	_boss_memory = _rebuild_boss_memory()
	# The reviewed run was resolved with the previous memory; only a boss reads it, so only then does
	# the committed set's run need resolving again.
	if _level_has_boss():
		_committed_res = null
		_start_committed_resolve()
	else:
		_committed_res = _resolution
	_speed = _default_speed()
	_end_mode = _default_end_mode()
	_idle = null
	_cue_ui(AudioBase.UI_COMMIT)
	_set_phase(SessionPhase.SETUP)


## Resolve exactly the committed tapes: synchronously (prototype behaviour) or in the background.
func _start_committed_resolve() -> void:
	if _committed_job != null:
		_committed_job.cancel()
		_committed_job = null
	var job := _make_job(_committed.duplicate())
	if not async_resolve:
		var r := job.run_sync()
		_committed_res = r
		if _pending == null:
			_set_resolution(r)
		return
	_committed_job = job
	job.start()


func _reset_all() -> void:
	_drop_live()
	_cancel_jobs()
	_resolving_snap = null
	_committed = []
	_pending = null
	_committed_res = null
	_set_resolution(null)
	_boss_memory = _rebuild_boss_memory()
	_speed = _default_speed()
	_end_mode = _default_end_mode()
	_idle = null
	_count = 0
	_cue_ui(AudioBase.UI_RESET)
	_set_phase(SessionPhase.SETUP)


func _drop_live() -> void:
	_live = null
	_live_snap = null
	_live_prev = null
	_live_marks = [[], [], [], []]
	_live_mark_tick = -1


func _set_resolution(r: Resolution) -> void:
	_resolution = r
	_resolved_marks = [[], [], [], []]
	if r != null:
		for e: SimEvent in r.events:
			_note_state_mark(_resolved_marks, e)


func _rebuild_boss_memory() -> BossMemory:
	_boss_memory_builds += 1
	return BossMemoryLib.build_boss_memory(level, _committed.duplicate())


func _level_has_boss() -> bool:
	for e: EntityDef in level.entities:
		if e is EnemyDef and (e as EnemyDef).type == EnemyType.BOSS:
			return true
	return false


func _default_speed() -> float:
	return 1.0 if _speeds.has(1.0) else _speeds[0]


func _default_end_mode() -> int:
	return OD.EndMode.STOP if level.end_modes.has(OD.EndMode.STOP) else level.end_modes[0]

# ───────────────────────────── frames ─────────────────────────────


## Beat-zero picture for briefing / setup: committed tapes plus (in setup) the armed self.
func _idle_frame(errors: Array[String] = []) -> FrameSnapshot:
	if _idle != null:
		return _idle
	var index := _committed.size()
	var armed := _phase != SessionPhase.BRIEFING and index < level.max_tapes
	var live := LiveTake.make(index, _speed, _end_mode) if armed else null
	var sim := ODSim.create_sim(_config(_committed.duplicate(), live), errors)
	if sim == null:
		return null
	_idle = sim.snapshot()
	return _idle


func _playback_frame(at: float) -> SessionFrame:
	var frames := _resolution.frames
	var last := frames.size() - 1
	# frames[k].sub == k · FRAME_SUBS except possibly the final one; search from the estimate.
	var step := frames[1].sub if frames.size() > 1 and frames[1].sub > 0 else 1
	var k := clampi(int(floorf(at / step)), 0, maxi(0, last))
	while k > 0 and frames[k].sub > at:
		k -= 1
	while k < last and frames[k + 1].sub <= at:
		k += 1
	if k >= last:
		return SessionFrame.make(frames[last], frames[last], 1.0)
	var prev := frames[k]
	var snap := frames[k + 1]
	return SessionFrame.make(snap, prev, clampf((at - prev.sub) / float(snap.sub - prev.sub), 0.0, 1.0))


## Re-emit resolution events whose instant (sub + 1) the playback clock has reached.
func _emit_playback_events() -> void:
	if _resolution == null:
		return
	var evs := _resolution.events
	while _event_cursor < evs.size() and evs[_event_cursor].sub + 1 <= _play_sub:
		_events.append(evs[_event_cursor])
		_event_cursor += 1

# ───────────────────────────── decks ─────────────────────────────


## Speed / end mode / tape of a cassette that exists in some form right now; {} when none.
## Keys: speed (float), end_mode (int), tape (ODTape or null), live (bool).
func _deck_config(i: int) -> Dictionary:
	if i >= level.max_tapes:
		return {}
	if i < _committed.size():
		var t := _committed[i]
		return {"speed": t.speed, "end_mode": t.end_mode, "tape": t, "live": false}
	if i != _committed.size():
		return {}
	if _pending != null:
		return {"speed": _pending.speed, "end_mode": _pending.end_mode, "tape": _pending, "live": false}
	if _phase == SessionPhase.SETUP or _phase == SessionPhase.COUNTIN or _phase == SessionPhase.RECORDING:
		return {"speed": _speed, "end_mode": _end_mode, "tape": null, "live": true}
	return {}


func _deck_status(i: int) -> StringName:
	if i >= level.max_tapes:
		return DeckStatus.UNAVAILABLE
	if i < _committed.size():
		return DeckStatus.COMMITTED
	if i != _committed.size():
		return DeckStatus.EMPTY
	if _pending != null:
		# A winning take is final: the attempt is over and it is locked into the performance.
		return DeckStatus.COMMITTED if _phase == SessionPhase.CINEMATIC or _phase == SessionPhase.RESULTS else DeckStatus.PENDING
	match _phase:
		SessionPhase.SETUP, SessionPhase.COUNTIN:
			return DeckStatus.ARMED
		SessionPhase.RECORDING:
			return DeckStatus.RECORDING
	return DeckStatus.EMPTY


func _deck_view(i: int, snap: FrameSnapshot, rate: float) -> DeckView:
	var d := DeckView.new()
	d.index = i
	d.status = _deck_status(i)
	var cfg := _deck_config(i)
	var has_cfg := not cfg.is_empty()
	var actor: ActorSnap = snap.actor(i) if has_cfg else null
	var tape: ODTape = cfg.get("tape") if has_cfg else null
	var ticks := tape.ticks if tape != null else tape_ticks
	var transport := actor.phase.dir if is_playing() and actor != null else 0
	d.speed = float(cfg["speed"]) if has_cfg else 0.0
	d.end_mode = int(cfg["end_mode"]) if has_cfg else -1
	d.local_progress = clampf(actor.phase.tick / ticks, 0.0, 1.0) if actor != null and ticks > 0 else 0.0
	d.transport = transport
	# Local seconds per wall second: the live tape always spins at 1 while every other tape spins at
	# its speed relative to the world's current rate (UI-07, NEW-10).
	d.reel_rate = d.speed * rate * absi(transport) if has_cfg else 0.0
	d.life = (actor.life if actor != null else OD.LifeState.ALIVE) if has_cfg else -1
	d.synced = actor.synced if actor != null else true
	d.span_bars = ODTime.span_bars(level, d.speed) if has_cfg else 0.0
	if has_cfg:
		d.marks = _marks_for(i, tape, bool(cfg["live"]))
	d.state_marks = _state_marks_for(i)
	return d


func _marks_for(i: int, tape: ODTape, live: bool) -> Array[DeckMark]:
	var out: Array[DeckMark] = []
	if tape != null:
		for e: TapeEvent in tape.events:
			out.append(DeckMark.make(e.tick, e.kind))
		return out
	if not live or _live == null or i != _committed.size():
		return out
	var tick := _live.local_tick
	if _live_mark_tick != tick:
		_live_mark_tick = tick
		_live_mark_cache = []
		for e: TapeEvent in _live.live_tape().events:
			_live_mark_cache.append(DeckMark.make(e.tick, e.kind))
	for m: DeckMark in _live_mark_cache:
		out.append(m.copy())
	return out


func _state_marks_for(i: int) -> Array[DeckStateMark]:
	var out: Array[DeckStateMark] = []
	var src: Array
	if _phase == SessionPhase.COUNTIN or _phase == SessionPhase.RECORDING:
		src = _live_marks[i]
	elif i >= _committed.size() + (1 if _pending != null else 0):
		return out
	else:
		src = _resolved_marks[i]
	for m: Variant in src:
		out.append((m as DeckStateMark).copy())
	return out


func _note_state_mark(into: Array, e: SimEvent) -> void:
	if e.tape < 0 or e.tape >= OD.TAPE_COUNT:
		return
	var kind: StringName = &""
	match e.type:
		SimEventType.SELF_DEATH:
			kind = StateMarkKind.DEATH
		SimEventType.DESYNC:
			kind = StateMarkKind.DESYNC
		SimEventType.RESYNC:
			kind = StateMarkKind.RESYNC
	if kind == &"":
		return
	(into[e.tape] as Array).append(DeckStateMark.make((e.sub + 1) / _spb, kind))

# ───────────────────────────── beatSight ─────────────────────────────


## Upcoming enemy attack beats for the 'beatSight' helmet. A telegraphing enemy's strike lands on its
## next grid beat (AI-07); in review / cinematic the resolved run also tells exactly when attacks
## happen.
func _threat_beats(snap: FrameSnapshot) -> Array[float]:
	var none: Array[float] = []
	if not loadout.has_ability(AbilityId.BEAT_SIGHT):
		return none
	var now := snap.beat
	var out: Array[float] = []
	for e: EnemySnap in snap.enemies:
		if not e.alive or e.state != EnemyStateName.TELEGRAPH:
			continue
		var def: EnemyDef = null
		for d: EntityDef in level.entities:
			if d is EnemyDef and d.id == e.id:
				def = d
				break
		var stats := Tuning.enemy_stats(e.type)
		var every: float = 0.0
		var offset: float = 0.0
		if def != null and def.has_beat:
			every = float(def.beat_every)
			offset = def.beat_offset
		elif stats != null:
			every = stats.every
			offset = stats.offset
		if not (every > 0.0):
			continue
		var k := ceilf((now - offset) / every - 1e-9)
		out.append(offset + k * every)
	if (_phase == SessionPhase.REVIEW or _phase == SessionPhase.CINEMATIC) and _resolution != null:
		for ev: SimEvent in _resolution.events:
			if ev.type != SimEventType.ENEMY_ATTACK and ev.type != SimEventType.ENEMY_SHOT:
				continue
			var b := (ev.sub + 1) / _spb
			if b > now and b <= now + THREAT_LOOKAHEAD_BEATS:
				out.append(b)
	var uniq: Array[float] = []
	for b: float in out:
		var r := floorf(b * 1000.0 + 0.5) / 1000.0
		if not uniq.has(r) and r >= now - 1e-6:
			uniq.append(r)
	uniq.sort()
	return uniq.slice(0, MAX_THREATS)
