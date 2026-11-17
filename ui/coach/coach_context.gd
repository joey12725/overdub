class_name CoachContext
extends RefCounted
## Everything coach-mark conditions read (docs/ONBOARDING.md "Conditions"), for the current frame.
## Node-free. CoachEngine.update() feeds it the SessionView, the FrameSnapshot and the frame's sim
## events; the game adds inputs, session actions and the cleared-level count.
##
## Time is the level clock: wall seconds since begin_level(). Logs carry their clock time, so every
## `scope` is just a start time: shown (the mark became visible), phase (this phase visit began),
## take (the latest count-in began), attempt (level load or the last resetAll), level (level load),
## save (persisted facts, plus everything since level load).

const LOG_MAX := 4096

var clock: float = 0.0
var level_id: String = ""
var level: LevelDef = null
var view: SessionView = null
var snap: FrameSnapshot = null
var phase: StringName = &""
var phase_start: float = 0.0
var take_start: float = 0.0
var attempt_start: float = 0.0
## This phase visit is the first visit to the phase in the save (firstTimePhase).
var first_visit: bool = false
var levels_cleared: int = 0
var retries_this_take: int = 0
var device: StringName = &"keyboard"
## The seen store: done marks (coach.<id>), visited phases (phase.<name>), save facts (fact.<key>).
var seen: DlgSeenStore = null
## once = false marks retired during this level visit (markDone sees them too).
var visit_done: Dictionary[String, bool] = {}

## [t, type, tape, detail, id, x, y]
var events: Array[Array] = []
## [t, action]
var actions: Array[Array] = []
## [t, input]
var inputs: Array[Array] = []
## Live actor path length: parallel arrays of clock time and cumulative tiles.
var travel_t: PackedFloat32Array = PackedFloat32Array()
var travel_d: PackedFloat32Array = PackedFloat32Array()
var travelled: float = 0.0
var _last_live_pos: Vector2 = Vector2.INF
var _last_live_tape: int = -2


func begin_level(p_level_id: String, p_level: LevelDef = null) -> void:
	level_id = p_level_id
	level = p_level
	clock = 0.0
	phase = &""
	phase_start = 0.0
	take_start = 0.0
	attempt_start = 0.0
	first_visit = false
	retries_this_take = 0
	events.clear()
	actions.clear()
	inputs.clear()
	travel_t = PackedFloat32Array()
	travel_d = PackedFloat32Array()
	travelled = 0.0
	_last_live_pos = Vector2.INF
	_last_live_tape = -2
	view = null
	snap = null


## Advance the clock and take this frame's view / snapshot. Returns true when the phase changed.
func advance(dt: float, p_view: SessionView, p_snap: FrameSnapshot = null) -> bool:
	clock += maxf(0.0, dt)
	view = p_view
	snap = p_snap
	if level == null and p_view != null:
		level = p_view.level
	var ph: StringName = p_view.phase if p_view != null else &""
	var changed := ph != phase
	if changed:
		phase = ph
		phase_start = clock
		if ph == SessionPhase.COUNTIN:
			take_start = clock
		var key := "phase." + String(ph)
		first_visit = seen != null and not seen.has(key)
		if seen != null and ph != &"":
			seen.mark(key)
	_track_travel()
	return changed


func add_events(evs: Array[SimEvent]) -> void:
	for e: SimEvent in evs:
		events.append([clock, String(e.type), e.tape, e.detail, e.id, e.x, e.y])
	if events.size() > LOG_MAX:
		events = events.slice(events.size() - LOG_MAX)


func add_action(a: StringName) -> void:
	actions.append([clock, String(a)])
	match a:
		SessionAction.RETRY_TAKE:
			retries_this_take += 1
		SessionAction.COMMIT:
			retries_this_take = 0
		SessionAction.RESET_ALL:
			retries_this_take = 0
			attempt_start = clock
	if actions.size() > LOG_MAX:
		actions = actions.slice(actions.size() - LOG_MAX)


## One use of a gameplay input (move, aim, light, heavy, dodge, ranged, interact, ability).
func add_input(input: StringName) -> void:
	inputs.append([clock, String(input)])
	if inputs.size() > LOG_MAX:
		inputs = inputs.slice(inputs.size() - LOG_MAX)


func phase_time() -> float:
	return clock - phase_start


## Start time of a scope ("save" maps to the level start; facts cover what came before).
func scope_start(scope: String, shown_at: float) -> float:
	match scope:
		"shown":
			return shown_at
		"take":
			return take_start
		"attempt":
			return attempt_start
		"level", "save":
			return 0.0
	return phase_start


## The live tape: view.active during countin / recording; afterwards the deck recorded in this take
## (pending, else the last committed). -1 when none.
func live_tape() -> int:
	if view == null:
		return -1
	if view.phase == SessionPhase.COUNTIN or view.phase == SessionPhase.RECORDING or view.phase == SessionPhase.SETUP or view.phase == SessionPhase.BRIEFING:
		return view.active
	for d: DeckView in view.decks:
		if d.status == DeckStatus.PENDING or d.status == DeckStatus.RECORDING:
			return d.index
	var last := -1
	for d: DeckView in view.decks:
		if d.status == DeckStatus.COMMITTED:
			last = d.index
	return last if last >= 0 else view.active


## Tapes that exist (committed / pending / recording) other than the live one.
func previous_tapes() -> Array[int]:
	var out: Array[int] = []
	if view == null:
		return out
	var live := live_tape()
	for d: DeckView in view.decks:
		if d.index == live:
			continue
		if d.status == DeckStatus.COMMITTED or d.status == DeckStatus.PENDING or d.status == DeckStatus.RECORDING:
			out.append(d.index)
	return out


func actor(tape: int) -> ActorSnap:
	if snap == null:
		return null
	for a: ActorSnap in snap.actors:
		if a.tape == tape:
			return a
	return null


## Path length the live actor covered since `t0`.
func travelled_since(t0: float) -> float:
	var n := travel_t.size()
	if n == 0:
		return 0.0
	# last sample at or before t0
	var lo := 0
	var hi := n
	while lo < hi:
		var mid := (lo + hi) >> 1
		if travel_t[mid] <= t0:
			lo = mid + 1
		else:
			hi = mid
	var base := travel_d[lo - 1] if lo > 0 else 0.0
	return travelled - base


func _track_travel() -> void:
	var live := live_tape()
	var a := actor(live)
	if a == null or not (phase == SessionPhase.RECORDING or phase == SessionPhase.COUNTIN):
		_last_live_pos = Vector2.INF
		return
	var p := Vector2(a.x, a.y)
	if live == _last_live_tape and _last_live_pos != Vector2.INF:
		var step := p.distance_to(_last_live_pos)
		if step < 3.0: # a teleport (new take, repeat cut) is not travel
			travelled += step
	_last_live_pos = p
	_last_live_tape = live
	if travel_t.size() == 0 or travel_d[travel_d.size() - 1] != travelled:
		travel_t.append(clock)
		travel_d.append(travelled)
