class_name DlgBarkTriggers
extends RefCounted
## Turns the per-frame SessionView and sim events into bark keys (INTEGRATION.md "Barks" table).
## Node-free and stateful (it remembers the previous phase, the last reviewed survivors and how long
## the live self has been a recording ghost). Keys that need knowledge the view does not carry come
## from the game through DialogueLayer instead: takeCommitted / retry / resetAll (notify_action),
## loot (on_results), archivistSurprised (bark()).
##
##   countIn        entering countin
##   lastTape       entering setup on the final cassette the level offers (not on a 1-tape level)
##   death          the live self dies during recording (selfDeath for the active tape)
##   ghostTake      GHOST_TAKE_AFTER seconds into recording as recGhost, once per take
##   desync/resync  a self desyncs / resyncs during recording or review
##   rescue         review ended with a survivor that did not survive the previous combined run
##   fail           review ended with a failed outcome
##   win            entering cinematic
##   bossRecall     a bossRecall sim event (the layer plays archivistRecall, then Moxie's bossRecall)

const GHOST_TAKE_AFTER := 2.5

var prev_phase: StringName = &""
var _prev_survivors: Array[int] = []
var _prev_present: Array[int] = []
var _have_prev_run: bool = false
var _ghost_time: float = 0.0
var _ghost_fired: bool = false


func reset() -> void:
	prev_phase = &""
	_prev_survivors.clear()
	_prev_present.clear()
	_have_prev_run = false
	_ghost_time = 0.0
	_ghost_fired = false


## Bark keys for this frame, in priority order.
func observe(view: SessionView, events: Array[SimEvent], dt: float) -> Array[String]:
	var out: Array[String] = []
	if view == null:
		return out
	var phase := view.phase
	var entered := phase != prev_phase
	if entered:
		if prev_phase == SessionPhase.REVIEW and view.outcome != null:
			_after_review(view, out)
		match phase:
			SessionPhase.COUNTIN:
				out.append("countIn")
			SessionPhase.SETUP:
				if _is_last_tape(view):
					out.append("lastTape")
			SessionPhase.CINEMATIC:
				out.append("win")
			SessionPhase.RECORDING:
				_ghost_time = 0.0
				_ghost_fired = false
		if phase == SessionPhase.BRIEFING:
			_have_prev_run = false
			_prev_survivors.clear()
			_prev_present.clear()
	prev_phase = phase

	var live := phase == SessionPhase.RECORDING
	var watching := live or phase == SessionPhase.REVIEW
	for e: SimEvent in events:
		match e.type:
			SimEventType.SELF_DEATH:
				if live and e.tape == view.active:
					out.append("death")
			SimEventType.DESYNC:
				if watching:
					out.append("desync")
			SimEventType.RESYNC:
				if watching:
					out.append("resync")
			SimEventType.BOSS_RECALL:
				out.append("bossRecall")

	if live and view.active >= 0 and view.active < view.decks.size():
		if view.decks[view.active].life == OD.LifeState.REC_GHOST:
			_ghost_time += dt
			if not _ghost_fired and _ghost_time >= GHOST_TAKE_AFTER:
				_ghost_fired = true
				out.append("ghostTake")
	return out


func _after_review(view: SessionView, out: Array[String]) -> void:
	var o := view.outcome
	var present: Array[int] = []
	for d: DeckView in view.decks:
		if d.status == DeckStatus.COMMITTED or d.status == DeckStatus.PENDING:
			present.append(d.index)
	if _have_prev_run:
		for t: int in o.survivors:
			if _prev_present.has(t) and not _prev_survivors.has(t):
				out.append("rescue")
				break
	if not o.win:
		out.append("fail")
	_prev_survivors = o.survivors.duplicate()
	_prev_present = present
	_have_prev_run = true


static func _is_last_tape(view: SessionView) -> bool:
	if view.active < 1:
		return false
	var last := -1
	for d: DeckView in view.decks:
		if d.status != DeckStatus.UNAVAILABLE:
			last = d.index
	if view.level != null:
		last = mini(last if last >= 0 else view.level.max_tapes - 1, view.level.max_tapes - 1)
	return view.active == last
