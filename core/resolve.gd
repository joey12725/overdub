class_name ODResolve
extends RefCounted
## The authoritative result (prototype core/resolve.ts; REC-06, REC-07, OPEN-07).
##
## resolve_encounter runs every tape - including the one just recorded - under playback rules for
## the whole horizon. Only that run decides victory, so a recording ghost's provisional effects can
## never count (Scenario C). Its frames are replayed verbatim by the cinematic (CINE-04).
##
## Worker threads (port requirement). resolve_encounter reads nothing but its arguments (and the
## type registries, read-only after ODCore.ensure_registered(), which the game calls once on the main
## thread first). It never mutates the config: the caller must not mutate it either while a resolve
## runs (hand the worker `config.deep_copy()` made on the main thread). It allocates no shared
## scratch, so several resolves may run on different threads. Progress is reported through an
## optional callback, called ON THE RESOLVING THREAD (use call_deferred inside it to touch nodes), and
## the run stops early when an optional CancelToken is cancelled.
##
##     var token := ODResolve.CancelToken.new()
##     var thread := Thread.new()
##     thread.start(ODResolve.resolve_encounter.bind(cfg, func(f: float) -> void: bar.set_deferred("value", f), token))
##     ...  token.cancel()            # from any thread; resolve returns null soon after
##     var res: Resolution = thread.wait_to_finish()


## Cooperative cancel flag shared between the caller and a resolving thread.
class CancelToken:
	extends RefCounted
	var _cancelled: bool = false
	var _lock: Mutex = Mutex.new()

	## Ask the resolve to stop at its next check (every PROGRESS_SUBS substeps).
	func cancel() -> void:
		_lock.lock()
		_cancelled = true
		_lock.unlock()

	func is_cancelled() -> bool:
		_lock.lock()
		var c := _cancelled
		_lock.unlock()
		return c


## Substeps between progress reports and cancel checks (one master second).
const PROGRESS_SUBS: int = 240


## Play the combined encounter to the horizon. Stores a snapshot at substep 0, every FRAME_SUBS
## substeps, and at the final substep (also when the horizon is not a multiple of FRAME_SUBS), plus
## every event in order. `config.live` is ignored.
##
## `progress(fraction: float)`, if valid, is called with 0.0 first, then every PROGRESS_SUBS
## substeps with the fraction of the horizon simulated, and with 1.0 when done. When `cancel` is
## cancelled the resolve stops and returns null ("resolve cancelled" is appended to `errors`). An
## invalid config also returns null with the prototype's message in `errors`.
static func resolve_encounter(
	config: SimConfig, progress: Callable = Callable(), cancel: CancelToken = null, errors: Array[String] = []
) -> Resolution:
	var playback := SimConfig.make(config.level, config.loadout, config.tapes, null, config.boss_memory)
	var sim: ODSim = ODSim.create_sim(playback, errors)
	if sim == null:
		return null
	var report: bool = progress.is_valid()
	var h: int = sim.horizon_subs
	var res := Resolution.new()
	var frames: Array[FrameSnapshot] = res.frames
	var events: Array[SimEvent] = res.events
	frames.append(sim.snapshot())
	if report:
		progress.call(0.0)
	while sim.sub < h:
		sim.step_sub()
		var ev: Array[SimEvent] = sim.drain_events()
		if not ev.is_empty():
			events.append_array(ev)
		var at: int = sim.sub
		if at % OD.FRAME_SUBS == 0 or at == h:
			frames.append(sim.snapshot())
		if at % PROGRESS_SUBS == 0 and at < h:
			if cancel != null and cancel.is_cancelled():
				errors.append("resolve cancelled")
				return null
			if report:
				progress.call(float(at) / h)
	res.outcome = sim.outcome()
	res.horizon_subs = h
	if report:
		progress.call(1.0)
	return res
