class_name GameBot
extends RefCounted
## Headless bot (port of prototype/src/game/bot.ts and the closed-loop controller of
## prototype/tests/game/plans.ts): plays a GameSession from a list of scripted takes and reports the
## Outcome. Level designers use it to prove a level is solvable (APP-TEST-03) without a window:
##
##     bash tools/gd script res://tools/bot.gd -- sandbox          # data/levels/solutions/sandbox.json
##     bash tools/gd script res://tools/bot.gd                     # every plan in that folder
##
## It drives the real session exactly as a player would: choose speed / end mode in setup, record
## (count-in included), one input per local tick, then commit and move to the next cassette. The last
## take's resolved run is the verdict; earlier takes are committed regardless of whether their own
## combined runs win (a plan's intermediate runs usually do not).
##
## ── Plan files (data/levels/solutions/<level id>.json) ──
##
##     {
##       "version": 1,
##       "level": "sandbox",                     // level id (data/levels/<id>.json)
##       "loadout": { "melee": "reel_lash" },    // optional; missing slots = baseline (APP-TEST-03)
##       "expect": { "win": true, "takes": 1 },  // optional; what the test / tool checks
##       "takes": [ <take>, ... ]                // at most level.maxTapes
##     }
##
## A take is { "speed": 1, "endMode": "stop", ... } plus EITHER open-loop inputs by local tick:
##
##     "inputs": [
##       { "from": 0, "to": 30, "move": [1, 0] },       // move along (x, y) for ticks [from, to)
##       { "from": 0, "to": 480, "aim": -1.5708 },      // aim (radians) for ticks [from, to)
##       { "tick": 40, "press": "light", "aim": 0.5 }   // one button on one tick (aim optional)
##     ]                                               // later spans override earlier ones
##
## (with no aim span, aim follows the move direction; buttons: light, heavy, dodge, ranged,
## interact, ability) OR a closed-loop step list, which reacts to the session's own snapshots and is
## still deterministic:
##
##     "steps": [ { "goto": [3.5, 2.3], "tol": 0.15 }, { "interact": true }, { "wait": 30 },
##                { "hold": [11.5, 3.4] } ],
##     "reflex": { "strikeRange": 1.45, "swingEvery": 22, "dodgeRange": 0, "ignore": [], "heavy": false }
##
## A file whose takes carry only a designer `plan` (no `inputs` / `steps`) is a draft the level tools
## have not compiled yet: load_plan() marks it `draft`, the tool skips it and the test only checks it
## has no `expect` block.
##
## goto walks to a point (then the next step), interact presses interact once, wait idles N ticks,
## hold stands on a point to the end. Reflexes run first each tick: dodge an enemy bolt closer than
## dodgeRange that is heading at the self, and swing (every swingEvery ticks) at the nearest living
## enemy within strikeRange (0 disables).

const WALL_STEP: float = 1.0 / 60.0
const PLAN_DIR: String = "res://data/levels/solutions"


## What a closed-loop bot controller can see on each local tick.
class BotContext:
	extends RefCounted
	## Local tick about to be recorded (0-based).
	var tick: int = 0
	## Cassette being recorded.
	var index: int = 0
	## World as of the end of the previous local tick (beat-zero state on tick 0).
	var snap: FrameSnapshot = null
	## The live self in `snap`.
	var self_actor: ActorSnap = null


## One scripted take.
class BotTake:
	extends RefCounted
	var speed: float = 1.0
	## OD.EndMode.
	var end_mode: int = OD.EndMode.STOP
	## func(tick: int, ctx: BotContext) -> PlayerInput. Open-loop scripts can ignore ctx.
	var inputs: Callable = Callable()
	## The object behind `inputs` when it is a method (a Callable does not keep its object alive).
	var controller: RefCounted = null

	static func make(p_speed: float, p_end_mode: int, p_inputs: Callable) -> BotTake:
		var t := BotTake.new()
		t.speed = p_speed
		t.end_mode = p_end_mode
		t.inputs = p_inputs
		return t


class BotOptions:
	extends RefCounted
	## Gear for every take. null = the baseline loadout (APP-TEST-03).
	var loadout: ResolvedLoadout = null
	## Stop as soon as a take wins instead of failing on leftover takes.
	var stop_on_win: bool = true


class BotRun:
	extends RefCounted
	var outcome: Outcome = null
	## Takes actually recorded (a win can come before the plan runs out).
	var takes_recorded: int = 0
	var session: GameSession = null


## A loaded plan file.
class BotPlan:
	extends RefCounted
	var path: String = ""
	var level_id: String = ""
	var loadout: Loadout = null
	var takes: Array[BotTake] = []
	var has_expect_win: bool = false
	var expect_win: bool = true
	## Expected number of recorded takes; -1 = not checked.
	var expect_takes: int = -1
	## A designer's draft: its takes have a `plan` but the level tools have not compiled it into
	## `inputs` yet (data/levels/solutions/README.md). A draft has no takes and cannot be run.
	var draft: bool = false


# ───────────────────────────── running ─────────────────────────────


static func _settle(session: GameSession, max_seconds: float, errors: Array[String]) -> bool:
	# Count-in / playback clocks; a generous bound guards against a stuck phase.
	var t := 0.0
	var start := session.phase
	while session.phase == start and t < max_seconds:
		session.advance(WALL_STEP)
		t += WALL_STEP
	if session.phase == start:
		errors.append("bot: session stuck in '%s'" % start)
		return false
	return true


static func _configure(session: GameSession, take: BotTake, n: int, errors: Array[String]) -> bool:
	var lv := session.level
	if not lv.speeds.has(take.speed):
		var sp: Array[String] = []
		for s: float in lv.speeds:
			sp.append(ObjectiveTracker.js_number(s))
		errors.append("bot: take %d wants speed %sx; level offers %s" % [n + 1, ObjectiveTracker.js_number(take.speed), ", ".join(sp)])
		return false
	if not lv.end_modes.has(take.end_mode):
		var em: Array[String] = []
		for m: int in lv.end_modes:
			em.append(OD.end_mode_name(m))
		errors.append("bot: take %d wants end mode '%s'; level offers %s" % [n + 1, OD.end_mode_name(take.end_mode), ", ".join(em)])
		return false
	var guard := 0
	while session.speed != take.speed and guard < 8:
		session.act(SessionAction.SPEED_UP if session.speed < take.speed else SessionAction.SPEED_DOWN)
		guard += 1
	guard = 0
	while session.end_mode != take.end_mode and guard < 4:
		session.act(SessionAction.CYCLE_END_MODE)
		guard += 1
	if session.speed != take.speed or session.end_mode != take.end_mode:
		errors.append("bot: could not configure take %d" % (n + 1))
		return false
	return true


static func _live_actor(snap: FrameSnapshot) -> ActorSnap:
	for a: ActorSnap in snap.actors:
		if a.live:
			return a
	return null


## Run the plan and return the full result; null (and the reason in `errors`) on a plan the level
## cannot accept.
static func run_bot_detailed(level: LevelDef, takes: Array[BotTake], options: BotOptions = null, errors: Array[String] = []) -> BotRun:
	var opts := options if options != null else BotOptions.new()
	if takes.is_empty():
		errors.append("bot: the plan has no takes")
		return null
	if takes.size() > level.max_tapes:
		errors.append("bot: %d takes but the level offers %d cassettes" % [takes.size(), level.max_tapes])
		return null
	var lo := opts.loadout if opts.loadout != null else LoadoutRules.resolve_loadout(CampaignData.base_loadout())
	var session := GameSession.create(level, lo, false, false, errors)
	if session == null:
		return null
	session.act(SessionAction.START)
	var horizon_seconds := session.horizon_subs / float(OD.SUB_HZ) + 5.0
	var ctx := BotContext.new()
	for n in takes.size():
		var take := takes[n]
		if not _configure(session, take, n, errors):
			return null
		session.act(SessionAction.RECORD)
		if not _settle(session, 10.0, errors):
			return null
		if session.phase != SessionPhase.RECORDING:
			errors.append("bot: take %d did not start recording" % (n + 1))
			return null
		var index := session.active_index
		var tick := 0
		while session.phase == SessionPhase.RECORDING:
			var snap := session.current_frame().snap
			ctx.tick = tick
			ctx.index = index
			ctx.snap = snap
			ctx.self_actor = _live_actor(snap)
			var inp: Variant = take.inputs.call(tick, ctx)
			session.tick_local(inp if inp is PlayerInput else idle_input())
			tick += 1
		var run := BotRun.new()
		run.session = session
		run.takes_recorded = n + 1
		if session.phase == SessionPhase.CINEMATIC:
			if not _settle(session, horizon_seconds, errors):
				return null
			run.outcome = session.outcome
			return run
		session.act(SessionAction.SKIP)
		run.outcome = session.outcome
		if n == takes.size() - 1 or (run.outcome.win and opts.stop_on_win):
			return run
		if not session.act(SessionAction.COMMIT):
			errors.append("bot: could not commit take %d" % (n + 1))
			return null
	errors.append("bot: unreachable")
	return null


## Run a scripted plan through a real session and return the authoritative Outcome (null + errors on
## a plan the level cannot accept).
static func run_bot(level: LevelDef, takes: Array[BotTake], options: BotOptions = null, errors: Array[String] = []) -> Outcome:
	var r := run_bot_detailed(level, takes, options, errors)
	return r.outcome if r != null else null

# ───────────────────────────── controller helpers ─────────────────────────────


## A neutral input (no movement, given aim, no buttons).
static func idle_input(aim: float = 0.0) -> PlayerInput:
	return PlayerInput.make(0.0, 0.0, aim)


## Input steering toward (x, y); stops inside `tolerance`.
static func steer_to(self_pos: Vector2, x: float, y: float, tolerance: float = 0.08) -> PlayerInput:
	var dx := x - self_pos.x
	var dy := y - self_pos.y
	var d := ODGrid.hypot(dx, dy)
	var inp := idle_input(atan2(dy, dx))
	if d > tolerance:
		# Ease off near the target so the controller does not overshoot.
		var k := minf(1.0, d / 0.6) / d
		inp.move_x = dx * k
		inp.move_y = dy * k
	return inp


## A take that ignores the world: the same input every tick.
static func constant_take(speed: float, end_mode: int, input: PlayerInput = null) -> BotTake:
	var base := input if input != null else idle_input()
	return BotTake.make(speed, end_mode, func(_tick: int, _ctx: BotContext) -> PlayerInput: return base.copy())


## One step of a closed-loop plan.
class PlanStep:
	extends RefCounted
	const GOTO: StringName = &"goto"
	const INTERACT: StringName = &"interact"
	const WAIT: StringName = &"wait"
	const HOLD: StringName = &"hold"
	var kind: StringName = GOTO
	var x: float = 0.0
	var y: float = 0.0
	var tol: float = 0.15
	var ticks: int = 0

	static func goto_point(px: float, py: float, p_tol: float = 0.15) -> PlanStep:
		var s := PlanStep.new()
		s.kind = GOTO
		s.x = px
		s.y = py
		s.tol = p_tol
		return s

	static func interact() -> PlanStep:
		var s := PlanStep.new()
		s.kind = INTERACT
		return s

	static func wait(n: int) -> PlanStep:
		var s := PlanStep.new()
		s.kind = WAIT
		s.ticks = n
		return s

	static func hold(px: float, py: float) -> PlanStep:
		var s := PlanStep.new()
		s.kind = HOLD
		s.x = px
		s.y = py
		return s


class Reflex:
	extends RefCounted
	## Strike enemies whose centre is within this distance (0 = never strike).
	var strike_range: float = 1.45
	## Ticks between swings.
	var swing_every: int = 22
	## Dodge enemy bolts closer than this that are heading at the self (0 = never).
	var dodge_range: float = 0.0
	## Enemy ids to leave alone.
	var ignore: Array[String] = []
	var heavy: bool = false

	static func make(p_strike: float = 1.45, p_dodge: float = 0.0) -> Reflex:
		var r := Reflex.new()
		r.strike_range = p_strike
		r.dodge_range = p_dodge
		return r


## The closed-loop controller behind plan_take (prototype tests/game/plans.ts). One instance per take:
## it keeps its step cursor and reflex timers.
class PlanController:
	extends RefCounted
	var steps: Array[PlanStep] = []
	var reflex: Reflex = Reflex.new()
	var _i: int = 0
	var _wait_left: int = -1
	var _last_swing: int = -1000
	var _last_dodge: int = -1000

	func input(tick: int, ctx: BotContext) -> PlayerInput:
		var me := ctx.self_actor
		var pos := Vector2(me.x, me.y)
		# Reflex: dodge a bolt that is about to arrive.
		if reflex.dodge_range > 0.0 and tick - _last_dodge > 40:
			for p: ProjectileSnap in ctx.snap.projectiles:
				if p.owner_enemy == "":
					continue
				var dx := me.x - p.x
				var dy := me.y - p.y
				var d := ODGrid.hypot(dx, dy)
				var heading := cos(p.dir) * dx + sin(p.dir) * dy
				if d < reflex.dodge_range and heading > 0.0:
					_last_dodge = tick
					var dinp := GameBot.idle_input(p.dir + PI / 2.0)
					dinp.move_x = cos(p.dir + PI / 2.0)
					dinp.move_y = sin(p.dir + PI / 2.0)
					dinp.dodge = true
					return dinp
		# Reflex: strike the nearest living enemy in reach.
		if me.life == OD.LifeState.ALIVE or me.life == OD.LifeState.REC_GHOST:
			var best: EnemySnap = null
			var best_d := INF
			for e: EnemySnap in ctx.snap.enemies:
				if not e.alive or reflex.ignore.has(e.id):
					continue
				var d := ODGrid.hypot(e.x - me.x, e.y - me.y)
				if d < reflex.strike_range and (best == null or d < best_d):
					best = e
					best_d = d
			if best != null:
				var inp := GameBot.idle_input(atan2(best.y - me.y, best.x - me.x))
				if tick - _last_swing >= reflex.swing_every:
					_last_swing = tick
					if reflex.heavy:
						inp.heavy = true
					else:
						inp.light = true
				return inp
		while _i < steps.size():
			var s := steps[_i]
			match s.kind:
				PlanStep.GOTO:
					if ODGrid.hypot(s.x - me.x, s.y - me.y) <= s.tol:
						_i += 1
						continue
					return GameBot.steer_to(pos, s.x, s.y, 0.02)
				PlanStep.INTERACT:
					_i += 1
					var iinp := GameBot.idle_input(me.facing)
					iinp.interact = true
					return iinp
				PlanStep.WAIT:
					if _wait_left < 0:
						_wait_left = s.ticks
					if _wait_left > 0:
						_wait_left -= 1
						return GameBot.idle_input(me.facing)
					_wait_left = -1
					_i += 1
					continue
			return GameBot.steer_to(pos, s.x, s.y, 0.05)
		return GameBot.idle_input(me.facing)


## A closed-loop take: walk the steps, with reflexes (prototype planTake).
static func plan_take(speed: float, end_mode: int, steps: Array[PlanStep], reflex: Reflex = null) -> BotTake:
	var c := PlanController.new()
	c.steps = steps
	if reflex != null:
		c.reflex = reflex
	var t := BotTake.make(speed, end_mode, c.input)
	t.controller = c
	return t


## Open-loop inputs by local tick (the plan file's "inputs" list).
class TickScript:
	extends RefCounted
	# Spans in insertion order: later spans override earlier ones where they overlap.
	var move_spans: Array[PackedFloat64Array] = []  # [from, to, x, y]
	var aim_spans: Array[PackedFloat64Array] = []  # [from, to, angle]
	## tick -> Array of [button: StringName, aim: float (NAN = none)]
	var presses: Dictionary[int, Array] = {}

	func input(tick: int, _ctx: BotContext = null) -> PlayerInput:
		var mx := 0.0
		var my := 0.0
		for s: PackedFloat64Array in move_spans:
			if tick >= s[0] and tick < s[1]:
				mx = s[2]
				my = s[3]
		var a := 0.0
		var aim_set := false
		for s: PackedFloat64Array in aim_spans:
			if tick >= s[0] and tick < s[1]:
				a = s[2]
				aim_set = true
		if not aim_set and (mx != 0.0 or my != 0.0):
			a = atan2(my, mx)
		var inp := PlayerInput.make(mx, my, a)
		for p: Variant in presses.get(tick, []):
			var pa: Array = p
			inp.set(String(pa[0]), true)
			if not is_nan(float(pa[1])):
				inp.aim = float(pa[1])
		return inp

# ───────────────────────────── plan files ─────────────────────────────


static func _vec(v: Variant, where: String, errors: Array[String]) -> Vector2:
	if v is Array and (v as Array).size() == 2 and ODJson.is_number(v[0]) and ODJson.is_number(v[1]):
		return Vector2(float(v[0]), float(v[1]))
	if v is Dictionary and ODJson.is_number((v as Dictionary).get("x")) and ODJson.is_number((v as Dictionary).get("y")):
		return Vector2(float(v["x"]), float(v["y"]))
	errors.append("%s: expected [x, y]" % where)
	return Vector2.ZERO


## Parse one take of a plan file; null (plus errors) when malformed.
static func take_from_dict(d: Dictionary, where: String, errors: Array[String]) -> BotTake:
	var n0 := errors.size()
	if not ODJson.is_number(d.get("speed")):
		errors.append("%s: missing speed" % where)
	var em := OD.end_mode_from_name(ODJson.string(d, "endMode", "stop"))
	if em < 0:
		errors.append("%s: unknown endMode '%s'" % [where, d.get("endMode")])
	var take := BotTake.new()
	take.speed = ODJson.num(d, "speed", 1.0)
	take.end_mode = maxi(em, 0)
	if d.has("steps"):
		var steps: Array[PlanStep] = []
		var arr: Array = ODJson.array(d, "steps")
		for i in arr.size():
			var sw := "%s.steps[%d]" % [where, i]
			if not (arr[i] is Dictionary):
				errors.append("%s: expected an object" % sw)
				continue
			var s: Dictionary = arr[i]
			if s.has("goto"):
				var p := _vec(s["goto"], sw, errors)
				steps.append(PlanStep.goto_point(p.x, p.y, ODJson.num(s, "tol", 0.15)))
			elif s.has("hold"):
				var p := _vec(s["hold"], sw, errors)
				steps.append(PlanStep.hold(p.x, p.y))
			elif s.has("interact"):
				steps.append(PlanStep.interact())
			elif s.has("wait") and ODJson.is_number(s["wait"]):
				steps.append(PlanStep.wait(int(s["wait"])))
			else:
				errors.append("%s: unknown step (use goto, hold, interact or wait)" % sw)
		var rf := Reflex.new()
		var r: Dictionary = ODJson.dict(d, "reflex")
		rf.strike_range = ODJson.num(r, "strikeRange", rf.strike_range)
		rf.swing_every = ODJson.integer(r, "swingEvery", rf.swing_every)
		rf.dodge_range = ODJson.num(r, "dodgeRange", rf.dodge_range)
		rf.ignore = ODJson.strings(r.get("ignore"))
		rf.heavy = ODJson.boolean(r, "heavy", false)
		take = plan_take(take.speed, take.end_mode, steps, rf)
	elif d.has("inputs"):
		var sc := TickScript.new()
		var arr: Array = ODJson.array(d, "inputs")
		for i in arr.size():
			var iw := "%s.inputs[%d]" % [where, i]
			if not (arr[i] is Dictionary):
				errors.append("%s: expected an object" % iw)
				continue
			var s: Dictionary = arr[i]
			if s.has("press"):
				var btn := StringName(ODJson.string(s, "press"))
				if not GameInput.GAMEPLAY.has(btn) or not ODJson.is_number(s.get("tick")):
					errors.append("%s: press needs a tick and one of light, heavy, dodge, ranged, interact, ability" % iw)
					continue
				var t := int(s["tick"])
				if not sc.presses.has(t):
					sc.presses[t] = []
				sc.presses[t].append([btn, ODJson.num(s, "aim", NAN) if s.has("aim") else NAN])
				continue
			if not ODJson.is_number(s.get("from")) or not ODJson.is_number(s.get("to")):
				errors.append("%s: a span needs from and to" % iw)
				continue
			var from := float(s["from"])
			var to := float(s["to"])
			if s.has("move"):
				var m := _vec(s["move"], iw, errors)
				sc.move_spans.append(PackedFloat64Array([from, to, m.x, m.y]))
			if s.has("aim"):
				sc.aim_spans.append(PackedFloat64Array([from, to, ODJson.num(s, "aim")]))
			if not s.has("move") and not s.has("aim"):
				errors.append("%s: a span needs move or aim" % iw)
		take.inputs = sc.input
		take.controller = sc
	else:
		errors.append("%s: a take needs steps or inputs" % where)
	return take if errors.size() == n0 else null


## Load a plan file (see the header). Null (plus errors) when missing or malformed.
static func load_plan(path: String, errors: Array[String] = []) -> BotPlan:
	var data: Variant = ODJson.read_file(path, errors)
	if not (data is Dictionary):
		if data != null:
			errors.append("%s: expected an object" % path)
		return null
	var d: Dictionary = data
	var n0 := errors.size()
	if ODJson.integer(d, "version", -1) != 1:
		errors.append("%s: unsupported version" % path)
	var plan := BotPlan.new()
	plan.path = path
	plan.level_id = ODJson.string(d, "level", path.get_file().get_basename())
	if d.get("loadout") is Dictionary:
		var lo := CampaignData.base_loadout()
		var ld: Dictionary = d["loadout"]
		for slot: StringName in OD.GEAR_SLOTS:
			if ld.get(String(slot)) is String:
				lo.set_slot(slot, ld[String(slot)])
		plan.loadout = lo
	var ex: Dictionary = ODJson.dict(d, "expect")
	if ex.get("win") is bool:
		plan.has_expect_win = true
		plan.expect_win = ex["win"]
	plan.expect_takes = ODJson.integer(ex, "takes", -1)
	var arr: Array = ODJson.array(d, "takes")
	# A draft: some take has only a plan (the level tools write `inputs` and `expect` on --write).
	for i in arr.size():
		var td: Variant = arr[i]
		if td is Dictionary and (td as Dictionary).has("plan") and not (td as Dictionary).has("inputs") and not (td as Dictionary).has("steps"):
			plan.draft = true
	if plan.draft:
		if d.has("expect"):
			errors.append("%s: has an expect block but take plans without inputs (stale file: re-run `level.ts run %s --write`)" % [path, plan.level_id])
		return plan if errors.size() == n0 else null
	for i in arr.size():
		if not (arr[i] is Dictionary):
			errors.append("%s: takes[%d] is not an object" % [path, i])
			continue
		var t := take_from_dict(arr[i], "%s: takes[%d]" % [path, i], errors)
		if t != null:
			plan.takes.append(t)
	return plan if errors.size() == n0 else null


## Fresh takes for a plan (closed-loop controllers keep state, so every run needs new ones).
static func reload_takes(plan: BotPlan, errors: Array[String] = []) -> Array[BotTake]:
	var again := load_plan(plan.path, errors)
	var none: Array[BotTake] = []
	return again.takes if again != null else none


## Paths of every plan file in data/levels/solutions/, sorted.
static func plan_paths() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(PLAN_DIR)
	if dir == null:
		return out
	var files := dir.get_files()
	files.sort()
	for f: String in files:
		if f.ends_with(".json"):
			out.append(PLAN_DIR.path_join(f))
	return out


## Load and run one plan file against its level. The result's `outcome` is the verdict; null (plus
## errors) when the file, the level or the plan is invalid.
static func run_plan_file(path: String, errors: Array[String] = []) -> BotRun:
	var plan := load_plan(path, errors)
	if plan == null:
		return null
	if plan.draft:
		errors.append("%s: a draft (plans not compiled into inputs yet: run `level.ts run %s --write`)" % [path, plan.level_id])
		return null
	var lv := CampaignData.level(plan.level_id)
	if lv == null:
		errors.append("%s: no level '%s'" % [path, plan.level_id])
		return null
	var opts := BotOptions.new()
	if plan.loadout != null:
		opts.loadout = LoadoutRules.resolve_loadout(plan.loadout)
	return run_bot_detailed(lv, plan.takes, opts, errors)


## Human summary of a run's outcome ("WIN with 1 take(s); survivors A" / "FAIL (objective): ...").
static func describe_run(run: BotRun) -> String:
	var o := run.outcome
	var names: Array[String] = []
	for s: int in o.survivors:
		names.append(OD.TAPE_NAMES[s])
	var head := "WIN" if o.win else "FAIL (%s)" % o.reason
	var text := "%s with %d take(s); survivors %s" % [head, run.takes_recorded, ", ".join(names) if not names.is_empty() else "none"]
	if not o.notes.is_empty():
		text += "; " + " / ".join(o.notes)
	return text
