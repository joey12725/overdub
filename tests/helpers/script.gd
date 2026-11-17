class_name TestScript
extends RefCounted
## Test helper (port of prototype/tests/helpers/script.ts): script player input by local tick,
## record takes, build exact tapes, resolve runs.
##
##   var s := TestScript.input_script() \
##       .run(0, 30, 1, 0) \            # ticks [0, 30): move right
##       .aim(0, 200, PI / 2) \         # aim down for ticks [0, 200)
##       .press(40, ActionKind.LIGHT) \ # light attack on tick 40 (aim = current aim)
##       .press(60, ActionKind.INTERACT)
##   var take := TestScript.record_take(level, 0, 1.0, s)
##   var res := TestScript.resolve(level, [take.tape])
##
## For kernel tests that need exact choreography independent of player physics, `path_tape` builds a
## tape straight from waypoints (positions per local tick) plus events.
##
## The prototype's `script()` is `input_script()` here (`script` is an Object property in Godot). The
## prototype's object literals for level entities become the small builders at the end (enemy, door,
## switch_def, ...).


## Scripted input: movement and aim spans plus button presses, by local tick.
class InputScript:
	extends RefCounted
	# Spans [from, to) in insertion order: later spans override earlier ones where they overlap.
	var _move_from: PackedInt32Array = PackedInt32Array()
	var _move_to: PackedInt32Array = PackedInt32Array()
	var _move_xy: PackedFloat64Array = PackedFloat64Array()
	var _aim_from: PackedInt32Array = PackedInt32Array()
	var _aim_to: PackedInt32Array = PackedInt32Array()
	var _aim_v: PackedFloat64Array = PackedFloat64Array()
	## tick -> Array of [button: StringName, aim: float (NAN = none)]
	var _presses: Dictionary[int, Array] = {}

	## Move along (x, y) for ticks [from, to).
	func run(from: int, to: int, x: float, y: float) -> InputScript:
		_move_from.append(from)
		_move_to.append(to)
		_move_xy.append(x)
		_move_xy.append(y)
		return self

	## Aim at `angle` (radians) for ticks [from, to).
	func aim(from: int, to: int, angle: float) -> InputScript:
		_aim_from.append(from)
		_aim_to.append(to)
		_aim_v.append(angle)
		return self

	## Press a button (ActionKind.* spelling: light, heavy, dodge, ranged, interact, ability) on one
	## tick; `aim_at` (optional, NAN = none) overrides the aim on that tick.
	func press(tick: int, button: StringName, aim_at: float = NAN) -> InputScript:
		if not _presses.has(tick):
			_presses[tick] = []
		_presses[tick].append([button, aim_at])
		return self

	## The input for one local tick.
	func input(tick: int) -> PlayerInput:
		var mx: float = 0.0
		var my: float = 0.0
		for i: int in _move_from.size():
			if tick >= _move_from[i] and tick < _move_to[i]:
				mx = _move_xy[i * 2]
				my = _move_xy[i * 2 + 1]
		var a: float = 0.0
		var aim_set: bool = false
		for i: int in _aim_from.size():
			if tick >= _aim_from[i] and tick < _aim_to[i]:
				a = _aim_v[i]
				aim_set = true
		if not aim_set and (mx != 0.0 or my != 0.0):
			a = atan2(my, mx)
		var inp := PlayerInput.make(mx, my, a)
		for p: Variant in _presses.get(tick, []):
			var pa: Array = p
			inp.set(String(pa[0]), true)
			if not is_nan(float(pa[1])):
				inp.aim = float(pa[1])
		return inp


## The result of record_take.
class TakeResult:
	extends RefCounted
	var tape: ODTape = null
	var sim: ODSim = null
	## Snapshot after every local tick (index i = after tick i, i.e. local tick i + 1 recorded).
	var frames: Array[FrameSnapshot] = []
	var events: Array[SimEvent] = []
	var outcome: Outcome = null


static func input_script() -> InputScript:
	return InputScript.new()


## Record one take by feeding the script tick by tick. `ticks` < 0 = the whole allowance.
static func record_take(
	level: LevelDef,
	index: int,
	speed: float,
	sc: InputScript,
	tapes: Array[ODTape] = [],
	loadout: ResolvedLoadout = null,
	end_mode: int = OD.EndMode.STOP,
	ticks: int = -1
) -> TakeResult:
	var lo: ResolvedLoadout = loadout if loadout != null else TestLoadout.base_loadout()
	var errors: Array[String] = []
	var sim: ODSim = ODSim.create_sim(SimConfig.make(level, lo, tapes, LiveTake.make(index, speed, end_mode)), errors)
	if sim == null:
		push_error("record_take: %s" % ", ".join(errors))
		return null
	var r := TakeResult.new()
	r.sim = sim
	var limit: int = ticks if ticks >= 0 else sim.tape_ticks
	var t: int = 0
	while t < limit and not sim.done:
		sim.step_local_tick(sc.input(t))
		r.frames.append(sim.snapshot())
		r.events.append_array(sim.drain_events())
		t += 1
	r.tape = sim.live_tape()
	r.outcome = sim.outcome()
	return r


## Resolve the combined run under playback rules.
static func resolve(level: LevelDef, tapes: Array[ODTape], loadout: ResolvedLoadout = null) -> Resolution:
	var lo: ResolvedLoadout = loadout if loadout != null else TestLoadout.base_loadout()
	var errors: Array[String] = []
	var res: Resolution = ODResolve.resolve_encounter(SimConfig.make(level, lo, tapes), Callable(), null, errors)
	if res == null:
		push_error("resolve: %s" % ", ".join(errors))
	return res


## Point of a piecewise-linear route [[tick, x, y], ...] at `tick` (held before the first and after
## the last waypoint), in full precision: [x, y] (the tape then rounds it to float32,
## exactly like the prototype's Float32Array write).
static func _point_at64(path: Array, tick: int) -> PackedFloat64Array:
	var first: Array = path[0]
	if tick <= int(first[0]):
		return PackedFloat64Array([float(first[1]), float(first[2])])
	for i: int in range(1, path.size()):
		var a: Array = path[i - 1]
		var b: Array = path[i]
		var at: int = int(a[0])
		var bt: int = int(b[0])
		if tick <= bt:
			var f: float = 1.0 if bt == at else float(tick - at) / float(bt - at)
			var ax: float = float(a[1])
			var ay: float = float(a[2])
			return PackedFloat64Array([ax + (float(b[1]) - ax) * f, ay + (float(b[2]) - ay) * f])
	var l: Array = path[path.size() - 1]
	return PackedFloat64Array([float(l[1]), float(l[2])])


## A tape built directly from waypoints: exact, physics-free choreography for kernel tests.
## `path` = [[tick, x, y], ...] (piecewise linear by local tick); `events` = [[tick, kind], ...] or
## [[tick, kind, dir], ...] (dir defaults to the motion direction at that tick, or 0).
static func path_tape(index: int, speed: float, ticks: int, path: Array, events: Array = [], end_mode: int = OD.EndMode.STOP) -> ODTape:
	var t_count: int = ticks
	var tape: ODTape = ODTape.create(index, speed, end_mode, t_count)
	var pos: PackedFloat32Array = tape.pos
	var facing: PackedFloat32Array = tape.facing
	var anim: PackedByteArray = tape.anim
	var last_facing: float = 0.0
	for i: int in t_count + 1:
		var p: PackedFloat64Array = _point_at64(path, i)
		pos[i * 2] = p[0]
		pos[i * 2 + 1] = p[1]
	var run_i: int = TapeLib.anim_index(AnimState.RUN)
	var idle_i: int = TapeLib.anim_index(AnimState.IDLE)
	for i: int in t_count + 1:
		var j: int = mini(i, t_count - 1)
		var dx: float = pos[j * 2 + 2] - pos[j * 2]
		var dy: float = pos[j * 2 + 3] - pos[j * 2 + 1]
		var moving: bool = t_count > 0 and (dx != 0.0 or dy != 0.0)
		if moving:
			last_facing = atan2(dy, dx)
		facing[i] = last_facing
		anim[i] = run_i if moving else idle_i
	# Stable sort by tick (the prototype's Array.prototype.sort is stable; Godot's is not).
	var sorted: Array = events.duplicate()
	for i: int in range(1, sorted.size()):
		var x: Array = sorted[i]
		var k: int = i - 1
		while k >= 0 and int((sorted[k] as Array)[0]) > int(x[0]):
			sorted[k + 1] = sorted[k]
			k -= 1
		sorted[k + 1] = x
	for e: Variant in sorted:
		var ea: Array = e
		var tick: int = int(ea[0])
		var i: int = mini(tick, t_count - 1)
		var vx: float = (pos[i * 2 + 2] - pos[i * 2]) * 60.0
		var vy: float = (pos[i * 2 + 3] - pos[i * 2 + 1]) * 60.0
		var dir: float = float(ea[2]) if ea.size() > 2 else facing[tick]
		tape.events.append(TapeEvent.make(tick, StringName(ea[1]), dir, pos[tick * 2], pos[tick * 2 + 1], vx, vy))
	return tape


## Events of one type (optionally for one tape / id).
static func events_of(events: Array[SimEvent], type: StringName, tape: int = -1, id: String = "") -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e: SimEvent in events:
		if e.type == type and (tape < 0 or e.tape == tape) and (id.is_empty() or e.id == id):
			out.append(e)
	return out


## The frame of a resolution at (or just after) a master substep.
static func frame_at(res: Resolution, sub: int) -> FrameSnapshot:
	for f: FrameSnapshot in res.frames:
		if f.sub >= sub:
			return f
	return res.frames[res.frames.size() - 1]


## The frame with exactly this sub, or null (the prototype's Map lookups by f.sub).
static func frame_exact(frames: Array[FrameSnapshot], sub: int) -> FrameSnapshot:
	for f: FrameSnapshot in frames:
		if f.sub == sub:
			return f
	return null

# ───────────────────────────── entity builders (the prototype's object literals) ─────────────────────────────


## { kind: 'enemy', id, type, x, y, ... }. Options: facing, hp, beat ([every, offset]), arc, wake (SignalExpr).
static func enemy(id: String, type: StringName, x: float, y: float, o: Dictionary = {}) -> EnemyDef:
	var e := EnemyDef.new()
	e.id = id
	e.type = type
	e.x = x
	e.y = y
	e.facing = float(o.get("facing", 0.0))
	if o.has("hp"):
		e.hp = int(o["hp"])
		e.has_hp = true
	if o.has("beat"):
		e.beat_every = int(o["beat"][0])
		e.beat_offset = float(o["beat"][1])
		e.has_beat = true
	if o.has("arc"):
		e.arc = float(o["arc"])
		e.has_arc = true
	if o.has("wake"):
		e.wake_when = o["wake"]
	return e


static func door(id: String, cells: Array[Vector2i], open_when: SignalExpr) -> DoorDef:
	var d := DoorDef.new()
	d.id = id
	d.cells = cells
	d.open_when = open_when
	return d


static func switch_def(id: String, x: float, y: float, initial: bool = false) -> SwitchDef:
	var s := SwitchDef.new()
	s.id = id
	s.x = x
	s.y = y
	s.initial = initial
	return s


static func plate(id: String, c: int, r: int, heavy: bool = false) -> PlateDef:
	var p := PlateDef.new()
	p.id = id
	p.c = c
	p.r = r
	p.heavy = heavy
	return p


static func breakable(id: String, c: int, r: int, threshold: float) -> BreakableDef:
	var b := BreakableDef.new()
	b.id = id
	b.c = c
	b.r = r
	b.threshold = threshold
	return b


static func laser(id: String, from: Vector2, to: Vector2, on_when: SignalExpr) -> LaserDef:
	var l := LaserDef.new()
	l.id = id
	l.from = from
	l.to = to
	l.on_when = on_when
	return l


## threshold < 0 = absent (the default core threshold applies).
static func core_def(id: String, x: float, y: float, threshold: float = -1.0) -> CoreDef:
	var c := CoreDef.new()
	c.id = id
	c.x = x
	c.y = y
	if threshold >= 0.0:
		c.threshold = threshold
		c.has_threshold = true
	return c


static func exit_def(id: String, c: int, r: int, w: int, h: int) -> ExitDef:
	var x := ExitDef.new()
	x.id = id
	x.c = c
	x.r = r
	x.w = w
	x.h = h
	return x


static func objective(type: StringName, text: String, targets: Array[String] = [], when_expr: SignalExpr = null) -> ObjectiveDef:
	var o := ObjectiveDef.new()
	o.type = type
	o.text = text
	o.targets = targets
	o.when_expr = when_expr
	return o


## A recorded frame as playback would describe it: no live self, a recording ghost is a ghost
## (as JSON, for deep comparison).
static func actors_as_playback(f: FrameSnapshot) -> Array:
	var out: Array = []
	for a: ActorSnap in f.actors:
		var c: ActorSnap = a.copy()
		c.live = false
		if c.life == OD.LifeState.REC_GHOST:
			c.life = OD.LifeState.GHOST
		out.append(c.to_dict())
	return out


## Snapshots of a list as JSON (for deep comparison with assert_json_eq / ODJson.deep_equal).
static func dicts(list: Array) -> Array:
	var out: Array = []
	for o: Variant in list:
		out.append((o as Object).call("to_dict"))
	return out
