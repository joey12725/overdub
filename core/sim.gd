class_name ODSim
extends RefCounted
## The encounter simulation kernel (prototype core/sim.ts; ARCHITECTURE "One clock", "What a tape
## is", "Life, ghosts and desync", "Authoritative result", "Combat"). ODSim is both the prototype's
## `Sim` (ISim) and its `World` interface: every subsystem takes `w: ODSim`.
##
## Clock. The world steps in master substeps of 1/SUB_HZ s. Substep s simulates the interval
## [s, s+1): tape events whose crossing sub lies in [s, s+1) fire during it, and every pose, signal
## and beat it evaluates is the instant `now = s + 1` it produces. After it, `sub == now`, and
## snapshot() describes exactly that instant (sub 0 = the initial state at beat zero; REC-02).
##
## Record mode (config.live): step_local_tick(input) runs the PlayerController for one local tick,
## appends the pose and its events to the live tape, then runs subs_per_local_tick(speed) substeps in
## which the live self is read through the same tape interpolation as every playback self.
## Playback mode: step_sub() advances one substep. ODResolve.resolve_encounter is playback mode
## over the whole horizon.
##
## SUBSTEP ORDER (fixed; every system relies on it):
##   1. playheads    every self's tape phase and projection pose at `now`; tape boundary events
##   2. sync         playback selves: obstruction -> desync (DESYNC-01); desynced selves: spark moves
##                   toward the projection and resyncs on catch-up (DESYNC-02..05)
##   3. dispatch     crossed tape events in [s, s+1), in tape-index order: melee swings open hit
##                   windows, dodges open i-frames, interacts toggle the nearest switch, ranged and
##                   ability effects are scheduled; due scheduled effects run (RANGED / ABILITY HOOKS)
##   3b. trap sense  beam sensors and relays publish their signals (core/traps; docs/TRAPS.md)
##   4. mechanisms   plates, exits, signals, doors (grid solidity), lasers, wake-ups
##   4b. traps       spikes, crushers (grid solidity), conveyors, flame jets, dart launchers,
##                   bumpers, magnets, in entity order (hits are queued for phase 7)
##   5. enemies      beat-grid decisions, movement, telegraph -> attack, stagger, knockback
##   6. projectiles  flight and contacts
##   7. damage       live melee swings tested against bodies; all queued hits applied together
##   8. objective    latch
##   9. events       footsteps; the substep's events are now drainable
##
## Life and sync gates (GHOST-01..06, DESYNC-07): a dead playback self (GHOST) has no effect and
## is never obstructed; a desynced self can neither act nor be hurt; the live self after death
## (REC_GHOST) still acts but cannot be hurt. Nothing about life is ever stored on a tape.
##
## Construction: always through ODSim.create_sim(config, errors), which validates the config the way
## the prototype's constructor threw (returns null and appends the message instead). ODSim.new()
## assumes a valid config.
##
## Threads: a sim touches nothing but its config, its own state and the type registries (enemy
## behaviours, projectile archetypes, ability handlers), which are read-only once
## ODCore.ensure_registered() has run. Scratch buffers are per sim. So one sim per thread is safe.
##
## JS vs GDScript: Math.hypot -> sqrt(a*a + b*b); Math.floor -> floor() cast to int.

# ───────────────────────────── ability hook ─────────────────────────────

## ═══ ABILITY DISPATCH HOOK ═══ - a self's recorded 'ability' event reaches the handler registered
## for each active ability in the loadout, at the event's effect tick, for any self that is not a
## dead playback ghost (the handler applies its own gates, e.g. manual desync works while desynced).
## With no handler registered the event has no effect. A handler is
## `func(w: ODSim, self_actor: SelfActor, ev: TapeEvent, pass_dir: int) -> void`.
static var _ability_handlers: Dictionary[StringName, Callable] = {}
static var _handlers_filled: bool = false


## Built-in ability rules (core/abilities.gd), registered once on first use.
static func _ensure_handlers() -> void:
	if _handlers_filled:
		return
	_handlers_filled = true
	_ability_handlers[AbilityId.MANUAL_DESYNC] = Abilities.manual_desync


## Fill the handler table now (ODCore.ensure_registered).
static func ensure_defaults() -> void:
	_ensure_handlers()


static func register_ability_handler(id: StringName, handler: Callable) -> void:
	_ensure_handlers()
	_ability_handlers[id] = handler


## The handler registered for an ability (an invalid Callable when none), e.g. to restore it after a
## test replaced it.
static func get_ability_handler(id: StringName) -> Callable:
	_ensure_handlers()
	return _ability_handlers.get(id, Callable())

# ───────────────────────────── state ─────────────────────────────

var config: SimConfig = null
var level: LevelDef = null
var loadout: ResolvedLoadout = null
var grid: ODGrid = null
var paths: Pathfinder = null
## Master substeps per master beat.
var spb: int = 0
var horizon_subs: int = 0
var tape_ticks: int = 0
## Selves sorted by tape index.
var selves: Array[SelfActor] = []
## Enemies in entity order.
var enemies: Array[EnemyState] = []
var mechs: Mechanisms = null
## Traps and automated machinery (docs/TRAPS.md). Inert (count 0) when the level has none.
var traps: Traps = null
var projectiles: ProjectileSystem = ProjectileSystem.new()
var signals: Dictionary[String, bool] = {}
var combat: CombatQueue = CombatQueue.new()
var log: RunLog = RunLog.new()
## The outside-the-loop boss's memory for this run (SimConfig.boss_memory). Read-only; may be null.
var boss_memory: BossMemory = null

## ISim: the master instant the world has reached (snapshot() describes it).
var sub: int = 0
## World: substep being simulated, the interval [s, s+1).
var s: int = 0
## World: instant this substep produces (s + 1); poses, signals and beats are evaluated here.
var now: int = 1
## World: master beat at `now`.
var beat: float = 0.0

## Perceived-distance factor of this loadout (Abilities.effective_distance(abilities, 1)); see
## EnemyCommon.perceived_distance. Port cache.
var perceive_k: float = 1.0
## Port scratch for ODGrid.move_circle in enemy movement (one per sim: thread safety).
var move_scratch: ODGrid.MoveResult = ODGrid.MoveResult.new()

## ISim: local ticks recorded so far (record mode).
var local_tick: int:
	get:
		return _live_ticks

## ISim: the take (record mode) or the horizon (playback) is complete.
var done: bool:
	get:
		return _live_ticks >= tape_ticks if config.live != null else sub >= horizon_subs

var _objective: ObjectiveTracker = null
var _enemy_index: Dictionary[String, EnemyState] = {}
var _events: Array[SimEvent] = []
var _cross_buf: Array[ODTime.EventCrossing] = []
var _bound_buf: Array[ODTime.TapeBoundary] = []
## Per self (parallel to `selves`): 1 at local tick e when the tape has an event on tick e (port
## prefilter for event crossings; empty for the live self, which is always queried).
var _event_ticks: Array[PackedByteArray] = []

# record mode
var _controller: PlayerController = null
var _live_self: SelfActor = null
var _live_tape_view: ODTape = null
var _live_ticks: int = 0

# ───────────────────────────── construction ─────────────────────────────


## Validate `config` (the checks the prototype's Sim constructor threw on) and build the sim.
## Returns null and appends the prototype's message to `errors` when the config is invalid.
static func create_sim(p_config: SimConfig, errors: Array[String] = []) -> ODSim:
	var lv: LevelDef = p_config.level
	var g: ODGrid = ODGrid.parse_grid(lv.map, errors)
	if g == null:
		return null
	var spbf: float = ODTime.subs_per_beat(lv)
	if spbf != floorf(spbf):
		errors.append("Level %s: bpm %s does not give whole substeps per beat" % [lv.id, ObjectiveTracker.js_number(lv.bpm)])
		return null
	var used: Dictionary[int, bool] = {}
	var live: LiveTake = p_config.live
	for t: ODTape in p_config.tapes:
		if live != null and t.index == live.index:
			continue
		if used.has(t.index):
			errors.append("Two tapes share cassette index %d" % t.index)
			return null
		if t.pos.size() != (t.ticks + 1) * 2 or t.facing.size() != t.ticks + 1 or t.anim.size() != t.ticks + 1:
			errors.append("Tape %d arrays do not match its %d ticks" % [t.index, t.ticks])
			return null
		used[t.index] = true
	var ids: Dictionary[String, bool] = {}
	for ent: EntityDef in lv.entities:
		if ent.kind != EntityKind.ENEMY:
			continue
		if ids.has(ent.id):
			errors.append("Duplicate enemy id %s" % ent.id)
			return null
		ids[ent.id] = true
		if EnemyRegistry.get_enemy_behaviour((ent as EnemyDef).type, errors) == null:
			return null
	return ODSim.new(p_config, g)


func _init(p_config: SimConfig, p_grid: ODGrid = null) -> void:
	_ensure_handlers()
	config = p_config
	level = p_config.level
	loadout = p_config.loadout
	boss_memory = p_config.boss_memory
	grid = p_grid if p_grid != null else ODGrid.parse_grid(p_config.level.map)
	paths = Pathfinder.new(grid)
	spb = int(ODTime.subs_per_beat(level))
	horizon_subs = int(ODTime.horizon_subs(level))
	tape_ticks = int(ODTime.tape_ticks(level))
	beat = float(now) / spb
	perceive_k = Abilities.effective_distance(loadout.abilities, 1.0)

	var live: LiveTake = p_config.live
	for t: ODTape in p_config.tapes:
		if live != null and t.index == live.index:
			continue
		selves.append(SelfActor.new(t.index, t, false))
	if live != null:
		var tt: int = tape_ticks
		var start: Vector2 = level.start
		var view: ODTape = ODTape.create(live.index, live.speed, live.end_mode, tt)
		view.pos[0] = start.x
		view.pos[1] = start.y
		# Written into a PackedFloat32Array: Math.fround(wrapAngle(startFacing)).
		view.facing[0] = TapeLib.wrap_angle(level.start_facing)
		view.anim[0] = TapeLib.anim_index(AnimState.IDLE)
		_live_tape_view = view
		var ps := PlayerController.PlayerStart.new()
		ps.x = start.x
		ps.y = start.y
		ps.facing = level.start_facing
		_controller = PlayerController.new(ps)
		_live_self = SelfActor.new(live.index, view, true)
		selves.append(_live_self)
	# Tape indices are unique, so this total order makes Godot's unstable sort deterministic.
	selves.sort_custom(func(a: SelfActor, b: SelfActor) -> bool: return a.index < b.index)
	for se: SelfActor in selves:
		_event_ticks.append(PackedByteArray() if se.live else _event_tick_table(se.tape))

	for ent: EntityDef in level.entities:
		if ent.kind != EntityKind.ENEMY:
			continue
		var e: EnemyState = EnemyCommon.create_enemy_state(ent as EnemyDef)
		enemies.append(e)
		_enemy_index[e.id] = e
	mechs = Mechanisms.new(level, grid, signals)
	_objective = ObjectiveTracker.new(level)
	traps = Traps.new(level, grid, signals)
	# Trap signals first so doors can read them at beat zero, then again so traps read the doors.
	traps.init(self)
	mechs.init(self)
	traps.init(self)
	for e: EnemyState in enemies:
		e.beh.init(self, e)


static func _event_tick_table(tape: ODTape) -> PackedByteArray:
	var t: int = maxi(tape.ticks, 0)
	var out := PackedByteArray()
	out.resize(t + 1)
	for ev: TapeEvent in tape.events:
		if ev.tick >= 0 and ev.tick <= t:
			out[ev.tick] = 1
	return out

# ───────────────────────────── World ─────────────────────────────


## Record an event at the current substep (the event's own `sub` is overwritten).
func emit(ev: SimEvent) -> void:
	ev.sub = s
	_events.append(ev)


## The enemy with `id`, or null.
func enemy_by_id(id: String) -> EnemyState:
	return _enemy_index.get(id)


## A self's melee killed an enemy ('killRefresh' refunds the live self's dodge).
func on_melee_kill(tape: int) -> void:
	if _controller != null and _live_self != null and _live_self.index == tape and loadout.has_ability(AbilityId.KILL_REFRESH):
		_controller.refresh_dodge()


## Put a self into desync on demand (gear abilities such as 'manualDesync').
func desync(self_actor: SelfActor, cause: String) -> void:
	if not self_actor.synced or self_actor.life == OD.LifeState.GHOST:
		return
	SelfActor.begin_desync(grid, self_actor, s)
	emit(
		SimEvent.make(0, SimEventType.DESYNC, self_actor.pose.x, self_actor.pose.y).with_tape(self_actor.index).with_detail(cause)
	)
	log.desync(self_actor.index, s, cause)

# ───────────────────────────── ISim ─────────────────────────────


## Record mode: run the controller for one local tick, append its sample, then run the substeps
## that tick covers.
func step_local_tick(input: PlayerInput) -> void:
	var ctl: PlayerController = _controller
	var se: SelfActor = _live_self
	var view: ODTape = _live_tape_view
	if ctl == null or se == null or view == null:
		push_error("stepLocalTick: this sim is not in record mode")
		return
	if done:
		return
	# Belts and bumpers move the live body by what the world moves in this tick (docs/TRAPS.md).
	if traps.count > 0:
		var at: PlayerController.PlayerPose = ctl.pose
		if traps.live_carry(self, at.x, at.y, OD.subs_per_local_tick(view.speed)):
			ctl.displace(traps.carry_x, traps.carry_y)
	var life: int = OD.LifeState.ALIVE if se.life == OD.LifeState.ALIVE else OD.LifeState.REC_GHOST
	var r: PlayerController.PlayerStepResult = ctl.step(input, grid, loadout, life)
	_live_ticks += 1
	var i: int = _live_ticks
	view.pos[i * 2] = r.x
	view.pos[i * 2 + 1] = r.y
	view.facing[i] = r.facing
	view.anim[i] = TapeLib.anim_index(r.anim)
	for ev: TapeEvent in r.events:
		view.events.append(ev.copy())
	var m: int = OD.subs_per_local_tick(view.speed)
	for k: int in m:
		_substep()


## Playback mode: advance one substep.
func step_sub() -> void:
	if config.live != null:
		push_error("stepSub: this sim is in record mode; use stepLocalTick")
		return
	if sub >= horizon_subs:
		return
	_substep()


## Record mode: the take so far (the whole allowance once done), as an independent tape.
func live_tape() -> ODTape:
	var view: ODTape = _live_tape_view
	if view == null:
		push_error("liveTape: this sim is not in record mode")
		return null
	var n: int = view.ticks if done else _live_ticks
	var t := ODTape.new()
	t.index = view.index
	t.speed = view.speed
	t.end_mode = view.end_mode
	t.ticks = n
	t.pos = view.pos.slice(0, (n + 1) * 2)
	t.facing = view.facing.slice(0, n + 1)
	t.anim = view.anim.slice(0, n + 1)
	for e: TapeEvent in view.events:
		if e.tick <= n:
			t.events.append(e.copy())
	return t


func drain_events() -> Array[SimEvent]:
	var out: Array[SimEvent] = _events
	_events = []
	return out


func outcome() -> Outcome:
	return ObjectiveTracker.build_outcome(self, _objective, level)


## 'beatSight': master beats of upcoming enemy attacks from now to `look_ahead_beats` beats ahead
## (see Abilities.upcoming_attack_beats; default Abilities.BEAT_SIGHT_LOOKAHEAD_BEATS = 8). Empty
## unless the loadout has the ability.
func threat_beats(look_ahead_beats: float = 8.0) -> Array[float]:
	if not loadout.has_ability(AbilityId.BEAT_SIGHT):
		var none: Array[float] = []
		return none
	return Abilities.upcoming_attack_beats(self, sub, look_ahead_beats)


func snapshot() -> FrameSnapshot:
	var f := FrameSnapshot.new()
	f.sub = sub
	f.beat = float(sub) / spb
	var actors: Array[ActorSnap] = []
	actors.resize(selves.size())
	for i: int in selves.size():
		var se: SelfActor = selves[i]
		var a := ActorSnap.new()
		a.tape = se.index
		a.live = se.live
		a.x = se.pose.x
		a.y = se.pose.y
		a.facing = se.pose.facing
		a.anim = se.pose.anim
		a.life = se.life
		a.synced = se.synced
		a.iframes = se.life != OD.LifeState.GHOST and se.in_iframes(sub)
		a.phase = se.phase.copy()
		a.vx = se.vx
		a.vy = se.vy
		if se.spark != null:
			a.spark = Vector2(se.spark.x, se.spark.y)
			a.has_spark = true
		actors[i] = a
	f.actors = actors
	var es: Array[EnemySnap] = []
	es.resize(enemies.size())
	for i: int in enemies.size():
		es[i] = EnemyCommon.enemy_snapshot(self, enemies[i], sub)
	f.enemies = es
	f.projectiles = projectiles.snapshot()
	f.mechs = mechs.snapshot()
	if traps.count > 0:
		f.mechs.append_array(traps.snapshot(sub))
	f.objective = _objective.snapshot(self)
	return f

# ───────────────────────────── one substep ─────────────────────────────


func _substep() -> void:
	var cur: int = sub
	s = cur
	now = cur + 1
	beat = float(now) / spb
	var at: int = now

	# 1. playheads
	for se: SelfActor in selves:
		se.advance(at, _live_ticks if se.live else se.tape.ticks)
		if not se.live:
			_emit_boundaries(se, at)

	# 2. sync: obstruction -> desync; spark catch-up -> resync
	for se: SelfActor in selves:
		if se.life == OD.LifeState.GHOST:
			continue
		if not se.synced:
			# 'manualDesync' holds the spark where the self left its body until released (Abilities).
			if se.spark_held:
				continue
			if SelfActor.step_spark(grid, paths, se, loadout, cur):
				emit(SimEvent.make(0, SimEventType.RESYNC, se.pose.x, se.pose.y).with_tape(se.index))
				log.resync(se.index, cur)
			continue
		if not se.live and SelfActor.is_obstructed(grid, se, loadout):
			desync(se, _obstruction_cause(se))
			continue
		se.last_valid_x = se.pose.x
		se.last_valid_y = se.pose.y

	# 3. dispatch crossed tape events, then due scheduled effects
	for i: int in selves.size():
		var se: SelfActor = selves[i]
		se.prune(cur)
		if _may_cross(se, _event_ticks[i], cur):
			var crossings: Array[ODTime.EventCrossing] = _cross_buf
			crossings.clear()
			ODTime.collect_event_crossings(se.tape, cur, at, crossings)
			for c: ODTime.EventCrossing in crossings:
				_dispatch(se, c)
		_run_scheduled(se, cur)

	# 3b. trap sense: sensors and relays (their signals reach this substep's mechanisms)
	traps.sense(self)

	# 4. mechanisms
	mechs.step(self)

	# 4b. traps
	traps.step(self)

	# 5. enemies
	EnemyCommon.step_enemies(self)

	# 6. projectiles ('parry' turns enemy shots inside live heavy swings first, before they move)
	Abilities.parry_projectiles(self)
	projectiles.step(self)

	# 7. damage
	Combat.resolve_swings(self)
	combat.resolve(self)

	# 8. objective
	_objective.update(self)

	# 9. footsteps
	for se: SelfActor in selves:
		if se.life == OD.LifeState.GHOST or se.cut:
			continue
		if se.pose.anim != AnimState.RUN:
			se.stride_acc = 0.0
			continue
		var dx: float = se.pose.x - se.prev_x
		var dy: float = se.pose.y - se.prev_y
		se.stride_acc += sqrt(dx * dx + dy * dy)
		if se.stride_acc >= SelfActor.STRIDE:
			se.stride_acc -= SelfActor.STRIDE
			emit(
				SimEvent.make(0, SimEventType.STEP, se.pose.x, se.pose.y).with_tape(se.index).with_detail(OD.life_state_name(se.life))
			)

	sub = at


## Port prefilter (no prototype counterpart): can any of this self's events cross in [cur, cur + 1)?
## Event ticks are integers, so a crossing sub is (k*T + u)*m for u in [0, T]: it needs cur % m == 0,
## and the tick it would fire is u or T - u (forward / backward pass; both 0 and T at a wrap or turn).
## A "maybe" calls ODTime.collect_event_crossings, which decides exactly, so this never changes
## behaviour, it only skips the per-substep scan of every event.
func _may_cross(se: SelfActor, table: PackedByteArray, cur: int) -> bool:
	if se.live:
		return true
	if se.tape.events.is_empty():
		return false
	var m: int = se.m
	if cur % m != 0:
		return false
	@warning_ignore("integer_division")
	var u: int = cur / m
	var t: int = se.tape.ticks
	if t <= 0 or se.tape.end_mode == OD.EndMode.STOP:
		return u <= maxi(t, 0) and table[u] == 1
	var r: int = u % t
	return table[r] == 1 or table[t - r] == 1


func _emit_boundaries(se: SelfActor, at: int) -> void:
	# A boundary that coincides with the end of the encounter is not announced: nothing follows it.
	if at >= horizon_subs:
		return
	var tape: ODTape = se.tape
	if tape.ticks <= 0:
		return
	# Boundaries fall on whole traversals only (prefilter; collect_boundaries decides).
	var trav: int = tape.ticks * se.m
	if at % trav != 0:
		return
	var bs: Array[ODTime.TapeBoundary] = _bound_buf
	bs.clear()
	ODTime.collect_boundaries(tape, at, at + 1, bs)
	for b: ODTime.TapeBoundary in bs:
		var type: StringName = SimEventType.TAPE_END
		if b.kind == ODTime.BOUNDARY_WRAP:
			type = SimEventType.TAPE_WRAP
		elif b.kind == ODTime.BOUNDARY_TURN:
			type = SimEventType.TAPE_TURN
		var ev: SimEvent = SimEvent.make(0, type, se.pose.x, se.pose.y).with_tape(se.index).with_power(b.traversal)
		if b.kind == ODTime.BOUNDARY_TURN:
			ev.with_detail("backward" if b.dir == -1 else "forward")
		emit(ev)


## Player-readable name of what obstructs a self's recorded pose.
func _obstruction_cause(se: SelfActor) -> String:
	var r: float = Tuning.BASE.actor_radius
	var x: float = se.pose.x
	var y: float = se.pose.y
	var c0: int = int(floor(minf(x, se.prev_x) - r))
	var c1: int = int(floor(maxf(x, se.prev_x) + r))
	var r0: int = int(floor(minf(y, se.prev_y) - r))
	var r1: int = int(floor(maxf(y, se.prev_y) + r))
	for rr: int in range(r0, r1 + 1):
		for cc: int in range(c0, c1 + 1):
			if not grid.is_dynamic_solid(cc, rr):
				continue
			var owner: String = mechs.owner_at(cc, rr)
			if owner.is_empty():
				owner = traps.owner_at(cc, rr)
			if not owner.is_empty():
				return "blocked by %s" % owner
	return "blocked by a wall"


func _dispatch(se: SelfActor, c: ODTime.EventCrossing) -> void:
	# GHOST-05: a dead playback self's attempts have no effect at all.
	if se.life == OD.LifeState.GHOST:
		return
	var ev: TapeEvent = c.event
	var pass_dir: int = c.dir
	var csub: int = int(c.sub)
	match ev.kind:
		ActionKind.LIGHT, ActionKind.HEAVY:
			# The swing itself checks can_act on every live substep: a self that dies or desyncs during
			# the windup does not hit, one that resyncs before the hit frame does (TEST-11, TEST-17).
			Combat.open_swing(self, se, ev, csub, pass_dir)
		ActionKind.DODGE:
			var t: PlayerController.ActionTiming = PlayerController.action_timing(ActionKind.DODGE, loadout)
			var win := SelfActor.SubWindow.new()
			win.start = csub + t.iframe_start * se.m
			win.end = csub + t.iframe_end * se.m
			se.iframes.append(win)
			emit(SimEvent.make(0, SimEventType.DODGE, se.pose.x, se.pose.y).with_tape(se.index).with_dir(ev.dir))
		ActionKind.INTERACT, ActionKind.RANGED, ActionKind.ABILITY:
			var t2: PlayerController.ActionTiming = PlayerController.action_timing(ev.kind, loadout)
			var fx := SelfActor.ScheduledEffect.new()
			fx.sub = csub + t2.effect * se.m
			fx.event = ev
			fx.pass_dir = pass_dir
			fx.traversal = c.traversal
			se.scheduled.append(fx)


func _run_scheduled(se: SelfActor, cur: int) -> void:
	if se.scheduled.is_empty():
		return
	var j: int = 0
	var list: Array[SelfActor.ScheduledEffect] = se.scheduled
	var i: int = 0
	# The prototype's index loop re-reads list.length, so effects scheduled while running are seen.
	while i < list.size():
		var fx: SelfActor.ScheduledEffect = list[i]
		i += 1
		if fx.sub > cur:
			list[j] = fx
			j += 1
			continue
		if se.life == OD.LifeState.GHOST:
			continue
		var ev: TapeEvent = fx.event
		if ev.kind == ActionKind.INTERACT:
			if se.can_act:
				mechs.interact(self, se)
			else:
				emit(
					SimEvent.make(0, SimEventType.INTERACT_FAIL, se.pose.x, se.pose.y).with_tape(se.index).with_detail("desynced")
				)
		elif ev.kind == ActionKind.RANGED:
			# Only a self that can act launches (Scenario F); see ProjectileSystem.launch_from_self.
			if se.can_act:
				projectiles.launch_from_self(self, se, ev, fx.pass_dir)
		elif ev.kind == ActionKind.ABILITY:
			for id: StringName in loadout.abilities:
				var h: Callable = _ability_handlers.get(id, Callable())
				if h.is_valid():
					h.call(self, se, ev, fx.pass_dir)
	list.resize(j)
