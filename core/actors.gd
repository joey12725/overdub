class_name SelfActor
extends RefCounted
## Selves (prototype core/actors.ts): one per cassette in the run. Owns the per-run life and sync
## state (GHOST-01..06, DESYNC-01..08), the playhead/pose read from the tape, the recovery spark, and
## the per-self action state opened by crossed tape events (melee swings, dodge i-frames, scheduled
## effects).
##
## Nothing in here is ever written back to a tape: life and sync are recomputed every run (GHOST-06).
##
## The live self is read through exactly the same pose interpolation as a playback self; the only
## differences are who produces the samples (the PlayerController, one local tick ahead of the
## world) and the death state it falls into (REC_GHOST rather than GHOST).
##
## JS vs GDScript: Math.hypot -> sqrt(a*a + b*b) (never Vector2.length(): Vector2 is float32).


## A half-open window of master substeps [start, end).
class SubWindow:
	extends RefCounted
	var start: int = 0
	var end: int = 0


## One firing of a recorded melee event: a fresh swing at the recorded place and direction (PLAY-02).
class ActiveSwing:
	extends RefCounted
	## ActionKind.LIGHT | ActionKind.HEAVY
	var kind: StringName = &"light"
	## Recorded swing direction (never re-aimed; PLAY-01).
	var dir: float = 0.0
	## Master substep the event was crossed (windup starts).
	var cross_sub: int = 0
	## Hit volume live for substeps [start, end).
	var start: int = 0
	var end: int = 0
	## Momentum of this swing, computed once when it was crossed (MOM-01).
	var momentum: float = 0.0
	## +1 forward pass, -1 a reverse pass re-firing the event (PLAY-06).
	var pass_dir: int = 1
	## Ids of enemies / objects this swing already struck: a swing hits each target at most once.
	var struck: Dictionary[String, bool] = {}
	## True once the swing has been live while its self was effective ('swing' event emitted).
	var announced: bool = false
	var connected: bool = false


## An action effect that lands some substeps after its event was crossed (ranged launch, ...).
class ScheduledEffect:
	extends RefCounted
	var sub: int = 0
	var event: TapeEvent = null
	var pass_dir: int = 1
	var traversal: int = 0


## The recovery spark: the physically reachable position of a desynced self (DESYNC-02).
class SparkState:
	extends RefCounted
	var x: float = 0.0
	var y: float = 0.0
	## Current route toward the projection (excluding the spark's own position).
	var path: Array[Vector2] = []
	var path_idx: int = 0
	## Grid revision and substep the route was planned at (re-planned on any door change; DESYNC-04).
	var plan_rev: int = -1
	var plan_sub: float = -INF
	## Substep the desync began (for notes).
	var since: int = 0


## Effective collision radius used to decide that a recorded pose is obstructed (DESYNC trigger).
static var OBSTRUCTION_RADIUS: float = Tuning.BASE.actor_radius - Tuning.DESYNC_PENETRATION_TOLERANCE

## Stride length (tiles) between footstep events.
const STRIDE: float = 0.85

var index: int = 0
var live: bool = false
## The tape being read. For the live self it is a growing view whose `ticks` is the full allowance.
var tape: ODTape = null
## Master substeps per local tick of this tape.
var m: int = 4

## OD.LifeState
var life: int = OD.LifeState.ALIVE
var synced: bool = true

var phase: TapePhase = TapePhase.new()
var pose: TapeLib.PoseSample = TapeLib.PoseSample.new()
## Projection position at the previous instant (for the straight-step obstruction test).
var prev_x: float = 0.0
var prev_y: float = 0.0
## True when the last advance crossed a repeat cut (the projection teleported).
var cut: bool = false
## Master-space velocity of the projection, tiles per master second.
var vx: float = 0.0
var vy: float = 0.0

var spark: SparkState = null
## 'manualDesync' (Abilities): the spark is held where the self left its body and neither moves nor
## resyncs until the ability is pressed again.
var spark_held: bool = false
## Last position at which this self was physically valid (spark origin on desync).
var last_valid_x: float = 0.0
var last_valid_y: float = 0.0

var iframes: Array[SubWindow] = []
var swings: Array[ActiveSwing] = []
var scheduled: Array[ScheduledEffect] = []

## Distance travelled since the last footstep event.
var stride_acc: float = 0.0

var death_sub: int = -1
var death_cause: String = ""

## Can this self's attempts affect the world right now? (alive or recording ghost, and synced)
var can_act: bool:
	get:
		return synced and (life == OD.LifeState.ALIVE or life == OD.LifeState.REC_GHOST)

## Can this self be hurt / targeted right now? (alive and synced; DESYNC-07, GHOST-04/05)
var vulnerable: bool:
	get:
		return synced and life == OD.LifeState.ALIVE

## Port scratch: the obstruction test's options while a 'phaseDodge' dodge plays (prototype
## PHASE_DODGE_OPTS); one per self so nothing is shared between sims on different threads.
var _phase_dodge_opts: ODGrid.MoveOpts = null
## Port scratch for spark navigation (created on first re-plan).
var _path_opts: Pathfinder.PathOpts = null


func _init(p_index: int, p_tape: ODTape, p_live: bool) -> void:
	index = p_index
	tape = p_tape
	live = p_live
	m = OD.subs_per_local_tick(p_tape.speed)
	ODTime.tape_phase_into(p_tape, 0, phase)
	TapeLib.sample_pose_into(p_tape, 0.0, pose)
	prev_x = pose.x
	prev_y = pose.y
	last_valid_x = pose.x
	last_valid_y = pose.y
	_phase_dodge_opts = ODGrid.MoveOpts.new()
	_phase_dodge_opts.ignore_low = true


## Move the playhead to master instant `at` and re-sample the projection. `max_tick` bounds the
## velocity estimate for a live tape whose later samples are not written yet.
func advance(at: int, max_tick: int) -> void:
	var prev_traversal: int = phase.traversal
	prev_x = pose.x
	prev_y = pose.y
	ODTime.tape_phase_into(tape, at, phase)
	TapeLib.sample_pose_into(tape, phase.tick, pose)
	cut = tape.end_mode == OD.EndMode.REPEAT and phase.traversal != prev_traversal
	_segment_velocity(phase.tick, max_tick, phase.dir)


func in_iframes(sub: int) -> bool:
	for w: SubWindow in iframes:
		if sub >= w.start and sub < w.end:
			return true
	return false


## Drop action state that can no longer matter.
func prune(sub: int) -> void:
	for i: int in range(iframes.size() - 1, -1, -1):
		if iframes[i].end <= sub:
			iframes.remove_at(i)


## Master-space velocity of a tape's motion at fractional tick t: the slope of the segment that ends
## at or after t, never reading past `max_tick` (the live tape's newest sample).
func _segment_velocity(t: float, max_tick: int, dir: int) -> void:
	var last: int = mini(tape.ticks, max_tick)
	if last <= 0 or dir == 0:
		vx = 0.0
		vy = 0.0
		return
	var i: int = int(ceil(t)) - 1 if t > 0.0 else 0
	if i > last - 1:
		i = last - 1
	if i < 0:
		i = 0
	var p: PackedFloat32Array = tape.pos
	var k: float = OD.LOCAL_HZ * tape.speed * dir
	var nvx: float = (p[i * 2 + 2] - p[i * 2]) * k
	var nvy: float = (p[i * 2 + 3] - p[i * 2 + 1]) * k
	# -0 normalised to 0 like the prototype (snapshots compare cleanly).
	vx = 0.0 if nvx == 0.0 else nvx
	vy = 0.0 if nvy == 0.0 else nvy

# ───────────────────────────── obstruction & desync (DESYNC-01..05) ─────────────────────────────


## Is the recorded step prev -> current impossible in the current world? True when the recorded
## position overlaps solid geometry (walls, void, low barriers, closed doors, unbroken breakables)
## by more than DESYNC_PENETRATION_TOLERANCE, or the straight step to it is blocked. A repeat cut is
## a teleport, not a step, so only its landing point is tested.
static func is_obstructed(grid: ODGrid, self_actor: SelfActor, loadout: ResolvedLoadout) -> bool:
	var opts: ODGrid.MoveOpts = null
	if self_actor.pose.anim == AnimState.DODGE and loadout.has_ability(AbilityId.PHASE_DODGE):
		opts = self_actor._phase_dodge_opts
	var x: float = self_actor.pose.x
	var y: float = self_actor.pose.y
	if grid.is_solid_at(x, y, OBSTRUCTION_RADIUS, opts):
		return true
	if not self_actor.cut and (self_actor.prev_x != x or self_actor.prev_y != y):
		if grid.sweep_circle_blocked(self_actor.prev_x, self_actor.prev_y, x, y, OBSTRUCTION_RADIUS, opts):
			return true
	return false


## Start a desync: the projection keeps following the tape; a spark appears at the last valid position.
static func begin_desync(grid: ODGrid, self_actor: SelfActor, sub: int) -> void:
	self_actor.synced = false
	var sx: float = self_actor.last_valid_x
	var sy: float = self_actor.last_valid_y
	var sr: float = Tuning.BASE.spark_radius
	# A door can close onto the last valid position itself; the spark then starts just outside it.
	if grid.is_solid_at(sx, sy, sr):
		var res: ODGrid.MoveResult = grid.move_circle(sx, sy, 0.0, 0.0, sr)
		sx = res.x
		sy = res.y
	# Open swings are kept: they are gated on every live substep, so a swing whose hit frame comes
	# after a resync still lands (and one that comes while desynced does nothing).
	var sp := SparkState.new()
	sp.x = sx
	sp.y = sy
	sp.path = []
	sp.path_idx = 0
	sp.plan_rev = -1
	sp.plan_sub = -INF
	sp.since = sub
	self_actor.spark = sp


## Can the spark resync with the projection right now? (DESYNC-05: within tolerance, clear line, valid pose)
static func _can_resync(grid: ODGrid, self_actor: SelfActor, spark_state: SparkState) -> bool:
	var dx: float = self_actor.pose.x - spark_state.x
	var dy: float = self_actor.pose.y - spark_state.y
	var tol: float = Tuning.BASE.resync_tolerance
	if dx * dx + dy * dy > tol * tol:
		return false
	if grid.is_solid_at(self_actor.pose.x, self_actor.pose.y, OBSTRUCTION_RADIUS):
		return false
	return not grid.sweep_circle_blocked(spark_state.x, spark_state.y, self_actor.pose.x, self_actor.pose.y, Tuning.BASE.spark_radius)


## Move a desynced self's spark one substep toward its projection and resync on catch-up.
## Returns true if the self resynced this substep.
##
## The spark heads straight for the projection whenever that line is clear; otherwise it follows an
## A* route over walkable tiles, re-planned whenever the grid changes (a door opening gives it the
## shorter route; DESYNC-04) and periodically as the projection moves. When the projection is
## unreachable it waits as close as it can get (partial route). No timeout, no teleport (DESYNC).
static func step_spark(grid: ODGrid, paths: Pathfinder, self_actor: SelfActor, loadout: ResolvedLoadout, sub: int) -> bool:
	var sp: SparkState = self_actor.spark
	if sp == null:
		return false
	if _can_resync(grid, self_actor, sp):
		return _resync(self_actor)
	var budget: float = (Tuning.BASE.spark_speed * loadout.mods.spark_speed) / OD.SUB_HZ
	var tx: float = self_actor.pose.x
	var ty: float = self_actor.pose.y
	var sr: float = Tuning.BASE.spark_radius

	var direct: bool = not grid.is_solid_at(tx, ty, sr) and not grid.sweep_circle_blocked(sp.x, sp.y, tx, ty, sr)
	if direct:
		_move_toward(sp, tx, ty, budget)
	else:
		var stale: bool = (
			sp.plan_rev != grid.revision or sub - sp.plan_sub >= Tuning.BASE.spark_replan_subs or sp.path_idx >= sp.path.size()
		)
		if stale:
			if self_actor._path_opts == null:
				self_actor._path_opts = Pathfinder.PathOpts.make(true).with_radius(sr)
			var res: Pathfinder.PathResult = paths.find_path(sp.x, sp.y, tx, ty, self_actor._path_opts)
			if res != null:
				sp.path = res.points
			else:
				sp.path = []
			sp.path_idx = 0
			sp.plan_rev = grid.revision
			sp.plan_sub = sub
		while budget > 1e-12 and sp.path_idx < sp.path.size():
			var p: Vector2 = sp.path[sp.path_idx]
			var px: float = p.x
			var py: float = p.y
			var dx: float = px - sp.x
			var dy: float = py - sp.y
			var d: float = sqrt(dx * dx + dy * dy)
			if d <= budget:
				sp.x = px
				sp.y = py
				budget -= d
				sp.path_idx += 1
			else:
				_move_toward(sp, px, py, budget)
				budget = 0.0
	if _can_resync(grid, self_actor, sp):
		return _resync(self_actor)
	return false


static func _move_toward(p: SparkState, tx: float, ty: float, dist: float) -> void:
	var dx: float = tx - p.x
	var dy: float = ty - p.y
	var d: float = sqrt(dx * dx + dy * dy)
	if d <= dist or d == 0.0:
		p.x = tx
		p.y = ty
	else:
		p.x += (dx / d) * dist
		p.y += (dy / d) * dist


static func _resync(self_actor: SelfActor) -> bool:
	self_actor.synced = true
	self_actor.spark = null
	self_actor.last_valid_x = self_actor.pose.x
	self_actor.last_valid_y = self_actor.pose.y
	return true
