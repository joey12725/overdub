extends SceneTree
## Benchmark of ODResolve.resolve_encounter against the docs/GODOT-PORT.md performance target:
## a 16-bar, 120 bpm, four-tape encounter with 6 enemies resolved in under 3 seconds.
##
##   bash tools/gd script res://tools/bench_resolve.gd                 # 3 timed runs + phase profile
##   bash tools/gd script res://tools/bench_resolve.gd -- --runs 5
##   bash tools/gd script res://tools/bench_resolve.gd -- --no-profile
##
## The level: a 24x16 hall with two wall blocks, a door on a switch, 3 grunts and 3 turrets.
## Recording allowance 8 bars at 0.5x / 1x / 2x, horizon 16 bars (7680 master substeps). Four
## scripted tapes (path tapes at 0.5x stop, 1x repeat, 2x reverse and 1x stop) walk around, swing,
## dodge, shoot and flip the switch, so every kernel system does work.
##
## The phase profile re-runs the encounter through _ProfiledSim, which times each phase of
## ODSim._substep (it mirrors that function's phase order and must be kept in step with it), plus the
## snapshots resolve_encounter stores. Timing lives here because core/ may not read a clock.

const TARGET_SECONDS: float = 3.0


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var runs: int = 3
	var profile: bool = true
	for i: int in args.size():
		if args[i] == "--runs" and i + 1 < args.size():
			runs = maxi(1, args[i + 1].to_int())
		elif args[i] == "--no-profile":
			profile = false
	ODCore.ensure_registered()
	var cfg: SimConfig = bench_config()
	print("[bench] level %s: %d bars recorded, horizon %d bars at %s bpm, %d tapes, %d enemies, %d substeps" % [
		cfg.level.id, cfg.level.bars, cfg.level.horizon_bars, cfg.level.bpm, cfg.tapes.size(),
		cfg.level.entities_of(EntityKind.ENEMY).size(), ODTime.horizon_subs(cfg.level)])
	var times: Array[float] = []
	var res: Resolution = null
	for r: int in runs:
		var t0: int = Time.get_ticks_usec()
		res = ODResolve.resolve_encounter(cfg)
		var dt: float = (Time.get_ticks_usec() - t0) / 1e6
		times.append(dt)
		print("[bench] run %d: %.3f s" % [r + 1, dt])
	times.sort()
	var median: float = times[times.size() / 2]
	print("[bench] resolve_encounter median %.3f s over %d runs (min %.3f, max %.3f); target %.1f s: %s" % [
		median, runs, times[0], times[times.size() - 1], TARGET_SECONDS, "PASS" if median < TARGET_SECONDS else "FAIL"])
	print("[bench] result: %d frames, %d events, win=%s, survivors=%s, %.1f us per substep" % [
		res.frames.size(), res.events.size(), res.outcome.win, res.outcome.survivors, median * 1e6 / res.horizon_subs])
	_print_event_counts(res)
	_project_all_alive(cfg)
	if profile:
		_profile(cfg)
	quit(0 if median < TARGET_SECONDS else 1)


static func _print_event_counts(res: Resolution) -> void:
	var counts: Dictionary[String, int] = {}
	for e: SimEvent in res.events:
		var k: String = String(e.type)
		counts[k] = counts.get(k, 0) + 1
	var keys: Array[String] = []
	keys.assign(counts.keys())
	keys.sort()
	var parts: PackedStringArray = PackedStringArray()
	for k: String in keys:
		parts.append("%s %d" % [k, counts[k]])
	print("[bench] events: %s" % ", ".join(parts))
	# Deaths shrink the remaining workload (dead ghosts skip most phases), so say when they happen.
	var deaths: PackedStringArray = PackedStringArray()
	for e: SimEvent in res.events:
		if e.type == SimEventType.SELF_DEATH:
			deaths.append("%s at sub %d" % [OD.tape_letter(e.tape), e.sub])
	print("[bench] self deaths (of %d substeps): %s" % [res.horizon_subs, ", ".join(deaths) if not deaths.is_empty() else "none"])

## Worst-case projection: the selves die part-way through the bench encounter, and dead ghosts are
## cheap, so time the substeps (with resolve_encounter's per-frame snapshots) while all of them are
## still alive and extrapolate that cost to the whole horizon.
static func _project_all_alive(cfg: SimConfig) -> void:
	var sim: ODSim = ODSim.create_sim(SimConfig.make(cfg.level, cfg.loadout, cfg.tapes, null, cfg.boss_memory))
	var h: int = sim.horizon_subs
	var frames: Array[FrameSnapshot] = [sim.snapshot()]
	var events: Array[SimEvent] = []
	var t0: int = Time.get_ticks_usec()
	var all_alive: bool = true
	while sim.sub < h and all_alive:
		sim.step_sub()
		events.append_array(sim.drain_events())
		if sim.sub % OD.FRAME_SUBS == 0:
			frames.append(sim.snapshot())
		for se: SelfActor in sim.selves:
			if se.life == OD.LifeState.GHOST:
				all_alive = false
	var n: int = sim.sub
	var us: float = float(Time.get_ticks_usec() - t0) / n
	print("[bench] all %d selves alive for %d substeps: %.1f us per substep -> projected %.3f s for a %d-substep horizon with nobody dying (target %.1f s)" % [
		sim.selves.size(), n, us, us * h / 1e6, h, TARGET_SECONDS])

# ───────────────────────────── the encounter ─────────────────────────────


static func bench_config() -> SimConfig:
	var level := LevelDef.new()
	level.id = "bench-hall"
	level.name = "Bench Hall"
	level.bpm = 120.0
	level.bars = 8
	level.horizon_bars = 16
	level.speeds.assign([0.5, 1.0, 2.0])
	level.end_modes.assign(OD.ALL_END_MODES)
	level.map.assign([
		"########################",
		"#......................#",
		"#......................#",
		"#....####.......####...#",
		"#....####.......####...#",
		"#......................#",
		"#......................#",
		"###########.############",
		"#......................#",
		"#......................#",
		"#....####.......####...#",
		"#....####.......####...#",
		"#......................#",
		"#......................#",
		"#......................#",
		"########################",
	])
	level.start = Vector2(2.5, 5.5)
	var ents: Array[EntityDef] = []
	ents.append(_enemy("g1", EnemyType.GRUNT, 12.5, 2.5, 0.0))
	ents.append(_enemy("g2", EnemyType.GRUNT, 20.5, 5.5, 0.0))
	ents.append(_enemy("g3", EnemyType.GRUNT, 12.5, 12.5, 0.0))
	ents.append(_enemy("t1", EnemyType.TURRET, 22.5, 1.5, PI))
	ents.append(_enemy("t2", EnemyType.TURRET, 22.5, 13.5, PI))
	ents.append(_enemy("t3", EnemyType.TURRET, 1.5, 14.5, 0.0))
	var sw := SwitchDef.new()
	sw.id = "sw"
	sw.x = 3.5
	sw.y = 6.5
	ents.append(sw)
	var door := DoorDef.new()
	door.id = "d1"
	door.cells.assign([Vector2i(11, 7)])
	door.open_when = SignalExpr.of_sig("sw")
	ents.append(door)
	level.entities = ents
	level.objective = ObjectiveDef.new()
	level.objective.type = ObjectiveType.ELIMINATE
	level.objective.text = "Clear the hall"

	var t: int = ODTime.tape_ticks(level)
	var tapes: Array[ODTape] = [
		_path_tape(0, 0.5, OD.EndMode.STOP, t,
			[[0, 2.5, 5.5], [40, 3.5, 6.0], [200, 10.5, 5.5], [320, 11.5, 9.0], [600, 12.0, 12.0], [960, 6.0, 13.5]],
			[[20, ActionKind.INTERACT], [150, ActionKind.LIGHT], [250, ActionKind.DODGE], [400, ActionKind.HEAVY],
			 [520, ActionKind.RANGED], [700, ActionKind.LIGHT], [820, ActionKind.DODGE], [900, ActionKind.RANGED]]),
		_path_tape(1, 1.0, OD.EndMode.REPEAT, t,
			[[0, 2.5, 5.5], [120, 9.0, 1.5], [360, 14.5, 1.5], [600, 20.0, 4.0], [960, 2.5, 5.5]],
			[[100, ActionKind.LIGHT], [180, ActionKind.RANGED], [300, ActionKind.DODGE], [380, ActionKind.HEAVY],
			 [500, ActionKind.LIGHT], [640, ActionKind.RANGED], [760, ActionKind.DODGE], [880, ActionKind.LIGHT]]),
		_path_tape(2, 2.0, OD.EndMode.REVERSE, t,
			[[0, 2.5, 5.5], [200, 7.0, 6.0], [480, 15.0, 6.0], [720, 21.0, 2.5], [960, 21.0, 6.0]],
			[[60, ActionKind.RANGED], [240, ActionKind.LIGHT], [420, ActionKind.HEAVY], [560, ActionKind.DODGE],
			 [700, ActionKind.LIGHT], [860, ActionKind.RANGED]]),
		_path_tape(3, 1.0, OD.EndMode.STOP, t,
			[[0, 2.5, 5.5], [100, 2.5, 2.0], [300, 8.0, 2.0], [500, 11.5, 6.0], [700, 11.5, 11.0], [960, 18.0, 12.5]],
			[[80, ActionKind.DODGE], [160, ActionKind.LIGHT], [340, ActionKind.RANGED], [460, ActionKind.HEAVY],
			 [620, ActionKind.LIGHT], [780, ActionKind.RANGED], [900, ActionKind.HEAVY]]),
	]
	var lo := ResolvedLoadout.new()
	lo.loadout = Loadout.make("base-helmet", "base-top", "base-pants", "base-shoes", "base-melee", "base-missile")
	lo.mods = Tuning.neutral_mods()
	var mel := MeleeWeaponDef.new()
	mel.reach = 1.1
	mel.arc_deg = 110.0
	mel.light = _swing(6, 4, 10, 1.2, 0.5)
	mel.heavy = _swing(16, 5, 18, 2.0, 0.25)
	lo.melee = mel
	var rng := RangedWeaponDef.new()
	rng.archetype = RangedArchetype.MISSILE
	rng.speed = 6.0
	rng.max_range = 14.0
	rng.impact = 1.2
	rng.commit = 12.0
	rng.cooldown = 45.0
	rng.turn_rate = 2.5
	lo.ranged = rng
	return SimConfig.make(level, lo, tapes)


static func _enemy(id: String, type: StringName, x: float, y: float, facing: float) -> EnemyDef:
	var e := EnemyDef.new()
	e.id = id
	e.type = type
	e.x = x
	e.y = y
	e.facing = facing
	return e


static func _swing(windup: float, active: float, recover: float, impact: float, move_mul: float) -> MeleeSwingDef:
	var s := MeleeSwingDef.new()
	s.windup = windup
	s.active = active
	s.recover = recover
	s.impact = impact
	s.move_mul = move_mul
	return s


## Piecewise-linear path tape (tests/helpers/script.gd path_tape, inlined so tools/ needs no tests/).
## Event dirs face the direction of travel at the event tick.
static func _path_tape(index: int, speed: float, end_mode: int, ticks: int, path: Array, events: Array) -> ODTape:
	var tape: ODTape = ODTape.create(index, speed, end_mode, ticks)
	for i: int in ticks + 1:
		var p: Vector2 = _point_at(path, i)
		tape.pos[i * 2] = p.x
		tape.pos[i * 2 + 1] = p.y
	var last: float = 0.0
	for i: int in ticks + 1:
		var j: int = mini(i, ticks - 1)
		var dx: float = tape.pos[j * 2 + 2] - tape.pos[j * 2]
		var dy: float = tape.pos[j * 2 + 3] - tape.pos[j * 2 + 1]
		var moving: bool = dx != 0.0 or dy != 0.0
		if moving:
			last = atan2(dy, dx)
		tape.facing[i] = last
		tape.anim[i] = TapeLib.anim_index(AnimState.RUN if moving else AnimState.IDLE)
	for ev: Variant in events:
		var a: Array = ev
		var tick: int = a[0]
		var i: int = mini(tick, ticks - 1)
		tape.events.append(TapeEvent.make(tick, a[1], tape.facing[tick], tape.pos[tick * 2], tape.pos[tick * 2 + 1],
			(tape.pos[i * 2 + 2] - tape.pos[i * 2]) * 60.0, (tape.pos[i * 2 + 3] - tape.pos[i * 2 + 1]) * 60.0))
	return tape


static func _point_at(path: Array, tick: int) -> Vector2:
	if tick <= int(path[0][0]):
		return Vector2(path[0][1], path[0][2])
	for i: int in range(1, path.size()):
		var a: Array = path[i - 1]
		var b: Array = path[i]
		if tick <= int(b[0]):
			var f: float = 1.0 if int(b[0]) == int(a[0]) else float(tick - int(a[0])) / float(int(b[0]) - int(a[0]))
			return Vector2(float(a[1]) + (float(b[1]) - float(a[1])) * f, float(a[2]) + (float(b[2]) - float(a[2])) * f)
	var l: Array = path[path.size() - 1]
	return Vector2(l[1], l[2])

# ───────────────────────────── phase profile ─────────────────────────────


const PHASES: Array[String] = [
	"1 playheads", "2 sync", "3 dispatch", "4 mechanisms", "5 enemies", "6 projectiles",
	"7 damage", "8 objective", "9 footsteps", "snapshots", "drain/collect",
]


## ODSim with a timed copy of _substep (same calls in the same order; keep in step with core/sim.gd).
class _ProfiledSim:
	extends ODSim
	var usec: PackedFloat64Array = PackedFloat64Array()

	func _init(p_config: SimConfig) -> void:
		super(p_config)
		usec.resize(PHASES.size())

	func _substep() -> void:
		var cur: int = sub
		s = cur
		now = cur + 1
		beat = float(now) / spb
		var at: int = now
		var t: int = Time.get_ticks_usec()
		for se: SelfActor in selves:
			se.advance(at, _live_ticks if se.live else se.tape.ticks)
			if not se.live:
				_emit_boundaries(se, at)
		t = _lap(0, t)
		for se: SelfActor in selves:
			if se.life == OD.LifeState.GHOST:
				continue
			if not se.synced:
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
		t = _lap(1, t)
		for i: int in selves.size():
			var se: SelfActor = selves[i]
			se.prune(cur)
			if _may_cross(se, _event_ticks[i], cur):
				_cross_buf.clear()
				ODTime.collect_event_crossings(se.tape, cur, at, _cross_buf)
				for c: ODTime.EventCrossing in _cross_buf:
					_dispatch(se, c)
			_run_scheduled(se, cur)
		t = _lap(2, t)
		# Trap sense / step are timed with the mechanisms (the bench level has no traps: both are no-ops).
		traps.sense(self)
		mechs.step(self)
		traps.step(self)
		t = _lap(3, t)
		EnemyCommon.step_enemies(self)
		t = _lap(4, t)
		Abilities.parry_projectiles(self)
		projectiles.step(self)
		t = _lap(5, t)
		Combat.resolve_swings(self)
		combat.resolve(self)
		t = _lap(6, t)
		_objective.update(self)
		t = _lap(7, t)
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
				emit(SimEvent.make(0, SimEventType.STEP, se.pose.x, se.pose.y).with_tape(se.index).with_detail(OD.life_state_name(se.life)))
		_lap(8, t)
		sub = at

	func _lap(i: int, t0: int) -> int:
		var t1: int = Time.get_ticks_usec()
		usec[i] += t1 - t0
		return t1


func _profile(cfg: SimConfig) -> void:
	var sim := _ProfiledSim.new(SimConfig.make(cfg.level, cfg.loadout, cfg.tapes, null, cfg.boss_memory))
	var h: int = sim.horizon_subs
	var frames: Array[FrameSnapshot] = [sim.snapshot()]
	var events: Array[SimEvent] = []
	var t_all: int = Time.get_ticks_usec()
	while sim.sub < h:
		sim.step_sub()
		var t0: int = Time.get_ticks_usec()
		events.append_array(sim.drain_events())
		var t1: int = Time.get_ticks_usec()
		sim.usec[10] += t1 - t0
		if sim.sub % OD.FRAME_SUBS == 0 or sim.sub == h:
			frames.append(sim.snapshot())
			sim.usec[9] += Time.get_ticks_usec() - t1
	var total: float = (Time.get_ticks_usec() - t_all) / 1e6
	print("[bench] profile (one run, %.3f s with timer overhead):" % total)
	var order: Array[int] = []
	for i: int in PHASES.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return sim.usec[a] > sim.usec[b])
	for i: int in order:
		print("[bench]   %-14s %8.1f ms  %5.1f%%" % [PHASES[i], sim.usec[i] / 1000.0, 100.0 * sim.usec[i] / (total * 1e6)])
