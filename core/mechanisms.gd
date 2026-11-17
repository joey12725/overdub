class_name Mechanisms
extends RefCounted
## Mechanisms (prototype core/mechanisms.ts): switches, pressure plates, doors, lasers, breakables,
## cores and exits, plus the signal table that ties them together (LEVEL vocabulary, Scenarios B, C,
## H, K).
##
## Signals published (id -> bool), all readable by SignalExpr:
##   switch id     - on/off (toggled by an 'interact' attempt in reach; PLAY-02)
##   plate id      - an effective body stands on the tile this substep
##   breakable id  - broken (latched)
##   core id       - activated (latched)
##   exit id       - an alive, synced self stands inside
##   door id       - door is open (passable)
##   laser id      - beam is on
##
## Mechanisms phase order (one substep): plates -> exits -> evaluate doors / lasers / wake conditions
## against the updated table -> door travel and grid solidity -> laser contact.
##
## Doors travel for DOOR_TRAVEL_SUBS substeps and are solid while less than half open, which is
## what drives the grid's dynamic overlay. A door that becomes solid never deletes a body inside
## it: enemies are pushed to the nearest free side immediately; a playback self is desynced by the
## obstruction test on the next substep (its projection continues); the live self is pushed out by
## its own controller's collision on its next local tick.
##
## Only effective bodies operate anything: alive or recording-ghost selves that are synced, and
## living enemies (GHOST-03/05, DESYNC-07). Dead playback ghosts never touch the world.
##
## Port addition (the prototype engineers' reported gap): a self's projectile that reaches an
## unbroken breakable or a core strikes it with its momentum under the same threshold rule as a
## melee swing ('clang' and a weak-hit note when too weak). ProjectileSystem.fly_straight calls
## projectile_strike_breakable / projectile_strike_core. A projectile that passes walls (the 'phase'
## archetype) never meets a breakable, so it flies through one without striking it.
##
## JS vs GDScript: Math.hypot -> sqrt(a*a + b*b).

## Door open/close travel time, master substeps (0.15 master s).
const DOOR_TRAVEL_SUBS: int = 36


class DoorState:
	extends RefCounted
	var def: DoorDef = null
	## Travel progress in substeps, 0 (closed) ... DOOR_TRAVEL_SUBS (open).
	var k: int = 0
	var passable: bool = false


class SwitchState:
	extends RefCounted
	var def: SwitchDef = null
	var on: bool = false


class PlateState:
	extends RefCounted
	var def: PlateDef = null
	var on: bool = false


class BreakableState:
	extends RefCounted
	var def: BreakableDef = null
	var broken: bool = false


class LaserState:
	extends RefCounted
	var def: LaserDef = null
	var on: bool = false


class CoreState:
	extends RefCounted
	var def: CoreDef = null
	var on: bool = false


class ExitState:
	extends RefCounted
	var def: ExitDef = null
	var on: bool = false


var doors: Array[DoorState] = []
var switches: Array[SwitchState] = []
var plates: Array[PlateState] = []
var breakables: Array[BreakableState] = []
var lasers: Array[LaserState] = []
var cores: Array[CoreState] = []
var exits: Array[ExitState] = []

var _grid: ODGrid = null
var _signals: Dictionary[String, bool] = {}
## Signal prefix of an enemy's death (`dead:<enemy id>`), and which enemies (by index in
## ODSim.enemies) have had theirs published.
const DEAD_PREFIX: String = "dead:"
var _dead_published: PackedByteArray = PackedByteArray()
## Snapshot order = entity order: parallel arrays of MechKind and the state object.
var _order_kind: Array[StringName] = []
var _order_state: Array[RefCounted] = []
## Tile index -> id of the door / breakable occupying it (for player-readable desync causes).
var _cell_owner: Dictionary[int, String] = {}
## Tile index -> breakable on it (projectile strikes).
var _breakable_at: Dictionary[int, BreakableState] = {}


func _init(level: LevelDef, grid: ODGrid, signals: Dictionary[String, bool]) -> void:
	_grid = grid
	_signals = signals
	for ent: EntityDef in level.entities:
		match ent.kind:
			EntityKind.DOOR:
				var dd: DoorDef = ent as DoorDef
				var ds := DoorState.new()
				ds.def = dd
				doors.append(ds)
				_push_order(MechKind.DOOR, ds)
				for c: Vector2i in dd.cells:
					_cell_owner[grid.index(c.x, c.y)] = "door %s" % dd.id
			EntityKind.SWITCH:
				var sd: SwitchDef = ent as SwitchDef
				var ss := SwitchState.new()
				ss.def = sd
				ss.on = sd.initial == true
				switches.append(ss)
				_push_order(MechKind.SWITCH, ss)
			EntityKind.PLATE:
				var ps := PlateState.new()
				ps.def = ent as PlateDef
				plates.append(ps)
				_push_order(MechKind.PLATE, ps)
			EntityKind.BREAKABLE:
				var bd: BreakableDef = ent as BreakableDef
				var bs := BreakableState.new()
				bs.def = bd
				breakables.append(bs)
				_push_order(MechKind.BREAKABLE, bs)
				_cell_owner[grid.index(bd.c, bd.r)] = "breakable wall %s" % bd.id
				_breakable_at[grid.index(bd.c, bd.r)] = bs
			EntityKind.LASER:
				var ls := LaserState.new()
				ls.def = ent as LaserDef
				lasers.append(ls)
				_push_order(MechKind.LASER, ls)
			EntityKind.CORE:
				var cs := CoreState.new()
				cs.def = ent as CoreDef
				cores.append(cs)
				_push_order(MechKind.CORE, cs)
			EntityKind.EXIT:
				var xs := ExitState.new()
				xs.def = ent as ExitDef
				exits.append(xs)
				_push_order(MechKind.EXIT, xs)
			_:
				pass


func _push_order(kind: StringName, state: RefCounted) -> void:
	_order_kind.append(kind)
	_order_state.append(state)


## Initial state at beat zero: switches, breakables solid, doors settled (no travel at start).
func init(w: ODSim) -> void:
	for s: SwitchState in switches:
		_signals[s.def.id] = s.on
	for p: PlateState in plates:
		_signals[p.def.id] = false
	for b: BreakableState in breakables:
		_signals[b.def.id] = false
		_grid.set_dynamic_solid(b.def.c, b.def.r, true)
	for c: CoreState in cores:
		_signals[c.def.id] = false
	for x: ExitState in exits:
		_signals[x.def.id] = false
	for d: DoorState in doors:
		var open: bool = ODSignals.eval_signal(d.def.open_when, _signals, 0.0)
		d.k = DOOR_TRAVEL_SUBS if open else 0
		d.passable = open
		_signals[d.def.id] = open
		for c: Vector2i in d.def.cells:
			_grid.set_dynamic_solid(c.x, c.y, not open)
	for l: LaserState in lasers:
		l.on = ODSignals.eval_signal(l.def.on_when, _signals, 0.0)
		_signals[l.def.id] = l.on
	for e: EnemyState in w.enemies:
		if not e.awake and e.def.wake_when != null and ODSignals.eval_signal(e.def.wake_when, _signals, 0.0):
			_wake(e)


## Name of the dynamic obstacle at a tile, if any ("door d1", "breakable wall w1"); "" for none.
func owner_at(c: int, r: int) -> String:
	if not _grid.in_bounds(c, r):
		return ""
	return _cell_owner.get(_grid.index(c, r), "")

# ───────────────────────────── actions ─────────────────────────────


## An 'interact' attempt by a self that can act: toggles the nearest switch within reach (ties by
## entity order). Reverse passes toggle again (PLAY-06: on -> off). Returns true if one toggled.
func interact(w: ODSim, self_actor: SelfActor) -> bool:
	var reach: float = PlayerController.interact_radius(w.loadout)
	var best: SwitchState = null
	var best_d: float = INF
	for s: SwitchState in switches:
		var dx: float = s.def.x - self_actor.pose.x
		var dy: float = s.def.y - self_actor.pose.y
		var d: float = sqrt(dx * dx + dy * dy)
		if d <= reach and d < best_d:
			best_d = d
			best = s
	if best == null:
		w.emit(
			SimEvent.make(0, SimEventType.INTERACT_FAIL, self_actor.pose.x, self_actor.pose.y)
			.with_tape(self_actor.index)
			.with_detail("nothing in reach")
		)
		return false
	best.on = not best.on
	_signals[best.def.id] = best.on
	w.emit(
		SimEvent.make(0, SimEventType.INTERACT, best.def.x, best.def.y)
		.with_tape(self_actor.index)
		.with_id(best.def.id)
		.with_detail("on" if best.on else "off")
	)
	return true


## A live melee swing against breakables and cores (Scenario K). A breakable or core needs one
## swing with momentum >= its threshold; a weaker swing 'clang's and is logged with the momentum it
## had and needed, so the outcome can say which swing lacked momentum.
func strike_objects(w: ODSim, self_actor: SelfActor, sw: SelfActor.ActiveSwing, ox: float, oy: float, reach: float, arc: float) -> void:
	for b: BreakableState in breakables:
		if b.broken or sw.struck.has(b.def.id):
			continue
		if not _box_in_swing(_grid, ox, oy, sw.dir, reach, arc, b.def.c, b.def.r):
			continue
		sw.struck[b.def.id] = true
		sw.connected = true
		_strike_breakable(w, b, self_actor.index, sw.kind, sw.momentum, sw.dir)
	for c: CoreState in cores:
		if c.on or sw.struck.has(c.def.id):
			continue
		if not Combat.in_swing_volume(ox, oy, sw.dir, reach, arc, c.def.x, c.def.y, Combat.CORE_RADIUS):
			continue
		if _grid.segment_blocked(ox, oy, c.def.x, c.def.y, true):
			continue
		sw.struck[c.def.id] = true
		sw.connected = true
		_strike_core(w, c, self_actor.index, sw.kind, sw.momentum, sw.dir)


## A strike of `momentum` on a breakable: breaks it at or above its threshold, else 'clang' + note.
func _strike_breakable(w: ODSim, b: BreakableState, tape: int, kind: String, momentum: float, dir: float) -> void:
	var cx: float = b.def.c + 0.5
	var cy: float = b.def.r + 0.5
	if momentum >= b.def.threshold:
		b.broken = true
		_signals[b.def.id] = true
		_grid.set_dynamic_solid(b.def.c, b.def.r, false)
		w.emit(
			SimEvent.make(0, SimEventType.HIT, cx, cy).with_tape(tape).with_id(b.def.id).with_power(momentum).with_dir(dir).with_detail(kind)
		)
		w.emit(
			SimEvent.make(0, SimEventType.BREAK, cx, cy).with_tape(tape).with_id(b.def.id).with_power(momentum).with_dir(dir).with_detail(kind)
		)
	else:
		w.emit(
			SimEvent.make(0, SimEventType.CLANG, cx, cy)
			.with_tape(tape)
			.with_id(b.def.id)
			.with_power(momentum)
			.with_dir(dir)
			.with_detail("needs %s" % ObjectiveTracker.js_number(b.def.threshold))
		)
		w.log.weak(tape, w.s, kind, "breakable wall %s" % b.def.id, momentum, b.def.threshold, "too weak")


## A strike of `momentum` on a core: activates it at or above its threshold, else 'clang' + note.
func _strike_core(w: ODSim, c: CoreState, tape: int, kind: String, momentum: float, dir: float) -> void:
	var need: float = Combat.core_threshold(c.def.threshold, c.def.has_threshold)
	if momentum >= need:
		c.on = true
		_signals[c.def.id] = true
		w.emit(
			SimEvent.make(0, SimEventType.HIT, c.def.x, c.def.y)
			.with_tape(tape)
			.with_id(c.def.id)
			.with_power(momentum)
			.with_dir(dir)
			.with_detail(kind)
		)
		w.emit(SimEvent.make(0, SimEventType.CORE, c.def.x, c.def.y).with_tape(tape).with_id(c.def.id).with_power(momentum).with_detail("on"))
	else:
		w.emit(
			SimEvent.make(0, SimEventType.CLANG, c.def.x, c.def.y)
			.with_tape(tape)
			.with_id(c.def.id)
			.with_power(momentum)
			.with_dir(dir)
			.with_detail("needs %s" % ObjectiveTracker.js_number(need))
		)
		w.log.weak(tape, w.s, kind, "core %s" % c.def.id, momentum, need, "too weak")

# ───────────────────────── projectile strikes (port addition) ─────────────────────────


## The unbroken breakable on tile (c, r), or null.
func breakable_at(c: int, r: int) -> BreakableState:
	if _breakable_at.is_empty() or not _grid.in_bounds(c, r):
		return null
	var b: BreakableState = _breakable_at.get(_grid.index(c, r))
	return b if b != null and not b.broken else null


## A self's projectile reached the face of tile (c, r). If that tile is an unbroken breakable the
## projectile strikes it once with its momentum (break at or above the threshold, else 'clang' and a
## weak-hit note naming the projectile archetype) and true is returned; the projectile's own wall rule
## (ProjectileArchetype.on_hit_wall) still decides whether it stops there. Enemy projectiles never
## strike objects (false). Called by ProjectileSystem.fly_straight.
func projectile_strike_breakable(w: ODSim, p: Projectile, c: int, r: int) -> bool:
	if p.owner_tape < 0:
		return false
	var b: BreakableState = breakable_at(c, r)
	if b == null:
		return false
	var key: String = "breakable:%s" % b.def.id
	if p.struck.has(key):
		return false
	p.struck[key] = true
	_strike_breakable(w, b, p.owner_tape, String(p.archetype), p.momentum, p.dir)
	return true


## A self's projectile touched core `c` (ProjectileSystem.fly_straight found the contact; cores are
## bodies of radius Combat.CORE_RADIUS). It strikes the core once with its momentum under the core's
## threshold. The projectile stops on the core (fly_straight).
func projectile_strike_core(w: ODSim, p: Projectile, c: CoreState) -> void:
	p.struck["core:%s" % c.def.id] = true
	_strike_core(w, c, p.owner_tape, String(p.archetype), p.momentum, p.dir)

# ───────────────────────────── per-substep update ─────────────────────────────


func step(w: ODSim) -> void:
	var heavy_step: bool = w.loadout.has_ability(AbilityId.HEAVY_STEP)
	for p: PlateState in plates:
		var on: bool = _plate_occupied(w, p.def, heavy_step)
		if on != p.on:
			p.on = on
			_signals[p.def.id] = on
			w.emit(SimEvent.make(0, SimEventType.PLATE, p.def.c + 0.5, p.def.r + 0.5).with_id(p.def.id).with_detail("on" if on else "off"))
	for x: ExitState in exits:
		var xon: bool = false
		for s: SelfActor in w.selves:
			if s.life != OD.LifeState.ALIVE or not s.synced:
				continue
			var px: float = s.pose.x
			var py: float = s.pose.y
			if px >= x.def.c and px < x.def.c + x.def.w and py >= x.def.r and py < x.def.r + x.def.h:
				xon = true
				break
		if xon != x.on:
			x.on = xon
			_signals[x.def.id] = xon

	# dead:<enemy id> (data/levels/README.md "Signal expressions"): true from the first update after
	# the enemy died. Published once per enemy; an id missing from the table reads as false.
	if _dead_published.size() != w.enemies.size():
		_dead_published.resize(w.enemies.size())
	for i: int in w.enemies.size():
		if _dead_published[i] == 0 and not w.enemies[i].alive:
			_dead_published[i] = 1
			_signals[DEAD_PREFIX + w.enemies[i].def.id] = true

	var beat: float = w.beat
	for e: EnemyState in w.enemies:
		if e.alive and not e.awake and e.def.wake_when != null and ODSignals.eval_signal(e.def.wake_when, _signals, beat):
			_wake(e, w.s)
	for d: DoorState in doors:
		var want: bool = ODSignals.eval_signal(d.def.open_when, _signals, beat)
		if want and d.k < DOOR_TRAVEL_SUBS:
			d.k += 1
		elif not want and d.k > 0:
			d.k -= 1
		var passable: bool = d.k * 2 >= DOOR_TRAVEL_SUBS
		if passable != d.passable:
			d.passable = passable
			_signals[d.def.id] = passable
			var sx: float = 0.0
			var sy: float = 0.0
			for c: Vector2i in d.def.cells:
				sx = sx + c.x + 0.5
			for c: Vector2i in d.def.cells:
				sy = sy + c.y + 0.5
			for c: Vector2i in d.def.cells:
				_grid.set_dynamic_solid(c.x, c.y, not passable)
			var n: float = float(maxi(1, d.def.cells.size()))
			w.emit(SimEvent.make(0, SimEventType.DOOR, sx / n, sy / n).with_id(d.def.id).with_detail("open" if passable else "closed"))
			if not passable:
				_clear_enemies_from(w)
	for l: LaserState in lasers:
		var lon: bool = ODSignals.eval_signal(l.def.on_when, _signals, beat)
		if lon != l.on:
			l.on = lon
			_signals[l.def.id] = lon
			w.emit(
				SimEvent.make(0, SimEventType.LASER, (l.def.from.x + l.def.to.x) / 2.0, (l.def.from.y + l.def.to.y) / 2.0)
				.with_id(l.def.id)
				.with_detail("on" if lon else "off")
			)
		if not lon:
			continue
		var ar: float = Tuning.BASE.actor_radius
		for s: SelfActor in w.selves:
			if not s.vulnerable:
				continue
			if _point_seg_dist(s.pose.x, s.pose.y, l.def.from.x, l.def.from.y, l.def.to.x, l.def.to.y) < ar:
				w.combat.hit_self(SelfHit.make(s, "burned by laser %s" % l.def.id, s.pose.x, s.pose.y, 0.0, true))


func _plate_occupied(w: ODSim, def: PlateDef, heavy_step: bool) -> bool:
	if not def.heavy or heavy_step:
		for s: SelfActor in w.selves:
			if not s.can_act:
				continue
			if int(floor(s.pose.x)) == def.c and int(floor(s.pose.y)) == def.r:
				return true
	for e: EnemyState in w.enemies:
		if not e.alive:
			continue
		var beh: EnemyBehaviour = e.beh
		if beh.hovering:
			continue
		if def.heavy and not beh.heavy_body:
			continue
		if int(floor(e.x)) == def.c and int(floor(e.y)) == def.r:
			return true
	return false


## Push living enemies out of anything that just became solid (never delete a body).
func _clear_enemies_from(w: ODSim) -> void:
	for e: EnemyState in w.enemies:
		if not e.alive:
			continue
		var solid: bool
		if e.beh.hovering:
			solid = DroneBehaviour.hover_solid_at(_grid, e.x, e.y, e.stats.radius)
		else:
			solid = _grid.is_solid_at(e.x, e.y, e.stats.radius)
		if not solid:
			continue
		var res: ODGrid.MoveResult = _grid.move_circle(e.x, e.y, 0.0, 0.0, e.stats.radius)
		e.x = res.x
		e.y = res.y
		e.path = []
		e.path_idx = 0


func snapshot() -> Array[MechSnap]:
	var out: Array[MechSnap] = []
	out.resize(_order_kind.size())
	for i: int in _order_kind.size():
		var kind: StringName = _order_kind[i]
		var st: RefCounted = _order_state[i]
		var m := MechSnap.new()
		m.kind = kind
		match kind:
			MechKind.DOOR:
				var d: DoorState = st
				m.id = d.def.id
				m.on = d.passable
				m.t = float(d.k) / DOOR_TRAVEL_SUBS
				m.has_t = true
			MechKind.SWITCH:
				var s: SwitchState = st
				m.id = s.def.id
				m.on = s.on
			MechKind.PLATE:
				var p: PlateState = st
				m.id = p.def.id
				m.on = p.on
			MechKind.BREAKABLE:
				var b: BreakableState = st
				m.id = b.def.id
				m.on = b.broken
			MechKind.LASER:
				var l: LaserState = st
				m.id = l.def.id
				m.on = l.on
			MechKind.CORE:
				var c: CoreState = st
				m.id = c.def.id
				m.on = c.on
			MechKind.EXIT:
				var x: ExitState = st
				m.id = x.def.id
				m.on = x.on
		out[i] = m
	return out


static func _wake(e: EnemyState, sub: int = 0) -> void:
	e.awake = true
	e.state = EnemyStateName.IDLE
	e.state_start = sub
	e.state_end = sub


static func _point_seg_dist(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
	var vx: float = bx - ax
	var vy: float = by - ay
	var l2: float = vx * vx + vy * vy
	var t: float = ((px - ax) * vx + (py - ay) * vy) / l2 if l2 > 0.0 else 0.0
	t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
	var dx: float = ax + vx * t - px
	var dy: float = ay + vy * t - py
	return sqrt(dx * dx + dy * dy)


## Is tile box (c, r) inside a swing volume? The nearest point of the box must be within reach and
## either it or the box centre must lie inside the arc; the line to the face must not pass another
## wall first.
static func _box_in_swing(grid: ODGrid, ox: float, oy: float, dir: float, reach: float, arc: float, c: int, r: int) -> bool:
	var qx: float = float(c) if ox < c else (float(c + 1) if ox > c + 1 else ox)
	var qy: float = float(r) if oy < r else (float(r + 1) if oy > r + 1 else oy)
	var dx: float = qx - ox
	var dy: float = qy - oy
	var d: float = sqrt(dx * dx + dy * dy)
	if d > reach:
		return false
	if d > 1e-9:
		var half: float = arc / 2.0
		if not _in_arc(ox, oy, dir, half, qx, qy) and not _in_arc(ox, oy, dir, half, c + 0.5, r + 0.5):
			return false
		# Probe a point just short of the face so the breakable itself does not count as the blocker.
		var k: float = maxf(0.0, d - 0.02) / d
		if grid.segment_blocked(ox, oy, ox + dx * k, oy + dy * k, true):
			return false
	return true


static func _in_arc(ox: float, oy: float, dir: float, half: float, x: float, y: float) -> bool:
	var a: float = atan2(y - oy, x - ox) - dir
	var wa: float = atan2(sin(a), cos(a))
	return absf(wa) <= half
