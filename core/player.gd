class_name PlayerController
extends RefCounted
## PlayerController — the ONLY place live player physics happens (ARCHITECTURE "One clock").
## Port of prototype/src/core/player.ts.
##
## Each call to `step` advances one LOCAL tick (1/LOCAL_HZ local seconds): it turns that tick's
## input into the next pose plus any action events started on the tick. The kernel appends the pose
## to the tape and then simulates the world by reading the tape exactly as playback does.
##
## Everything here is in local time, so movement and action timing feel identical at every tape
## speed (TIME-02, COMBAT-04 "consistent in local tape time, then mapped to master time").
##
## Action timing is defined once, by `action_timing`; the controller drives its state machine from
## it and the kernel interprets recorded events through the same function (melee_hit_window,
## dodge_iframe_window, ranged_launch_tick), so live play and playback cannot drift apart.

const DT: float = 1.0 / OD.LOCAL_HZ

# ───────────────────────────── action timing (shared with the kernel) ─────────────────────────────


## Timing of one action, in local ticks as OFFSETS from the tick the action started. On a reverse
## pass the kernel applies the same offsets from the crossing instant (a fresh swing; PLAY-06).
class ActionTiming:
	extends RefCounted
	## ActionKind.*
	var kind: StringName = &"light"
	## The actor cannot start another action for ticks [0, commit).
	var commit: int = 0
	## Facing is locked to the action direction for ticks [0, face_lock).
	var face_lock: int = 0
	## Movement speed multiplier while committed.
	var move_mul: float = 1.0
	## Melee: hit volume live for [active_start, active_end). Others: both equal `effect`.
	var active_start: int = 0
	var active_end: int = 0
	## Dodge: invulnerable for [iframe_start, iframe_end). Others: empty (0, 0).
	var iframe_start: int = 0
	var iframe_end: int = 0
	## The tick the action affects the world: melee hit-frame (active_start), ranged projectile launch,
	## interact / ability / dodge 0.
	var effect: int = 0
	## The same kind cannot start again before this offset (dodge / ranged cooldowns; others = commit).
	var cooldown: int = 0

	static func make(p_kind: StringName, p_commit: int, p_face_lock: int, p_move_mul: float, p_active_start: int, p_active_end: int, p_iframe_start: int, p_iframe_end: int, p_effect: int, p_cooldown: int) -> ActionTiming:
		var t := ActionTiming.new()
		t.kind = p_kind
		t.commit = p_commit
		t.face_lock = p_face_lock
		t.move_mul = p_move_mul
		t.active_start = p_active_start
		t.active_end = p_active_end
		t.iframe_start = p_iframe_start
		t.iframe_end = p_iframe_end
		t.effect = p_effect
		t.cooldown = p_cooldown
		return t


## Gear abilities that the ability button triggers (others are passive).
const ACTIVE_ABILITIES: Array[StringName] = [AbilityId.MANUAL_DESYNC]


static func _ticks_of(v: float) -> int:
	# Math.round on a positive value: roundi (half away from zero) agrees for v > 0.
	return roundi(v) if v > 0.0 else 0


## Timing of an action of `kind` under a loadout. Pure; identical for live play and playback.
## Returns null for a kind that is not an ActionKind.
static func action_timing(kind: StringName, loadout: ResolvedLoadout) -> ActionTiming:
	var mods := loadout.mods
	var base := Tuning.BASE
	match kind:
		ActionKind.LIGHT, ActionKind.HEAVY:
			var s := loadout.melee.light if kind == ActionKind.LIGHT else loadout.melee.heavy
			var w := _ticks_of(s.windup)
			var a := maxi(1, _ticks_of(s.active))
			var r := _ticks_of(s.recover)
			return ActionTiming.make(kind, w + a + r, w + a, s.move_mul, w, w + a, 0, 0, w, w + a + r)
		ActionKind.DODGE:
			var d := base.dodge_ticks
			var is_ := base.dodge_iframe_start
			var ie := is_ + _ticks_of(base.dodge_iframes * mods.dodge_iframes)
			return ActionTiming.make(kind, d, d, 1.0, 0, 0, is_, ie, 0, d + _ticks_of(base.dodge_cooldown * mods.dodge_cooldown))
		ActionKind.RANGED:
			var c := maxi(1, _ticks_of(loadout.ranged.commit))
			var launch := mini(base.ranged_launch_delay, c - 1)
			return ActionTiming.make(kind, c, c, base.ranged_move_mul, launch, launch, 0, 0, launch, maxi(c, _ticks_of(loadout.ranged.cooldown * mods.ranged_cooldown)))
		ActionKind.INTERACT:
			var c := base.interact_ticks
			return ActionTiming.make(kind, c, 0, base.interact_move_mul, 0, 0, 0, 0, 0, c)
		ActionKind.ABILITY:
			return ActionTiming.make(kind, 0, 0, 1.0, 0, 0, 0, 0, 0, 0)
	return null


## A half-open local tick window [start, end).
class TickWindow:
	extends RefCounted
	var start: int = 0
	var end: int = 0

	static func make(p_start: int, p_end: int) -> TickWindow:
		var w := TickWindow.new()
		w.start = p_start
		w.end = p_end
		return w

	func equals(o: TickWindow) -> bool:
		return o != null and start == o.start and end == o.end


## Local ticks [start, end) in which a recorded melee event's hit volume is live; null for other kinds.
static func melee_hit_window(ev: TapeEvent, loadout: ResolvedLoadout) -> TickWindow:
	if ev.kind != ActionKind.LIGHT and ev.kind != ActionKind.HEAVY:
		return null
	var t := action_timing(ev.kind, loadout)
	return TickWindow.make(ev.tick + t.active_start, ev.tick + t.active_end)


## Local ticks [start, end) of a recorded dodge's invulnerability; null for other kinds.
static func dodge_iframe_window(ev: TapeEvent, loadout: ResolvedLoadout) -> TickWindow:
	if ev.kind != ActionKind.DODGE:
		return null
	var t := action_timing(ActionKind.DODGE, loadout)
	return TickWindow.make(ev.tick + t.iframe_start, ev.tick + t.iframe_end)


## Local tick on which a recorded ranged event launches its projectile; -1 (the prototype's null)
## for other kinds.
static func ranged_launch_tick(ev: TapeEvent, loadout: ResolvedLoadout) -> int:
	if ev.kind != ActionKind.RANGED:
		return -1
	return ev.tick + action_timing(ActionKind.RANGED, loadout).effect


## Local tick on which any recorded event affects the world (see ActionTiming.effect).
static func effect_tick(ev: TapeEvent, loadout: ResolvedLoadout) -> int:
	return ev.tick + action_timing(ev.kind, loadout).effect


## Interaction reach for a loadout, tiles.
static func interact_radius(loadout: ResolvedLoadout) -> float:
	return Tuning.BASE.interact_radius + loadout.mods.interact_radius_add


## Run speed for a loadout, tiles per local second.
static func run_speed(loadout: ResolvedLoadout) -> float:
	return Tuning.BASE.run_speed * loadout.mods.move_speed


## Anim state of a committed action `elapsed` ticks after it started; &"" (the prototype's null)
## for 'ability'.
static func action_anim(kind: StringName, elapsed: int, timing: ActionTiming) -> StringName:
	match kind:
		ActionKind.LIGHT:
			return AnimState.LIGHT_WINDUP if elapsed < timing.active_start else (AnimState.LIGHT_ACTIVE if elapsed < timing.active_end else AnimState.LIGHT_RECOVER)
		ActionKind.HEAVY:
			return AnimState.HEAVY_WINDUP if elapsed < timing.active_start else (AnimState.HEAVY_ACTIVE if elapsed < timing.active_end else AnimState.HEAVY_RECOVER)
		ActionKind.DODGE:
			return AnimState.DODGE
		ActionKind.RANGED:
			return AnimState.RANGED
		ActionKind.INTERACT:
			return AnimState.INTERACT
	return &""

# ───────────────────────────── controller ─────────────────────────────


class PlayerPose:
	extends RefCounted
	var x: float = 0.0
	var y: float = 0.0
	## Radians, wrapped to (-π, π].
	var facing: float = 0.0
	## AnimState.*
	var anim: StringName = &"idle"
	## Local-space velocity, tiles per local second.
	var vx: float = 0.0
	var vy: float = 0.0


class PlayerStepResult:
	extends PlayerPose
	## Events started on this tick (their `tick` is the tick just simulated).
	var events: Array[TapeEvent] = []
	## Dodge invulnerability covers the tick just simulated.
	var iframes: bool = false


class PlayerStart:
	extends RefCounted
	var x: float = 0.0
	var y: float = 0.0
	## Absent in the prototype = 0.
	var facing: float = 0.0

	static func make(p_x: float, p_y: float, p_facing: float = 0.0) -> PlayerStart:
		var s := PlayerStart.new()
		s.x = p_x
		s.y = p_y
		s.facing = p_facing
		return s


class _ActiveAction:
	extends RefCounted
	var kind: StringName
	var start: int = 0
	var dir: float = 0.0
	var timing: ActionTiming
	## Dodge dash direction (unit).
	var dx: float = 0.0
	var dy: float = 0.0


## Press priority when several buttons go down on the same tick.
const PRESS_ORDER: Array[StringName] = [ActionKind.DODGE, ActionKind.HEAVY, ActionKind.LIGHT, ActionKind.RANGED, ActionKind.INTERACT]

static var _PHASE_OPTS: ODGrid.MoveOpts = ODGrid.MoveOpts.make(true)

var _x: float = 0.0
var _y: float = 0.0
var _vx: float = 0.0
var _vy: float = 0.0
var _facing: float = 0.0
var _tick: int = 0
var _action: _ActiveAction = null
var _next_dodge: int = 0
var _next_ranged: int = 0
## Buffered press: kind (&"" = none) and the last tick it may still start.
var _buffered_kind: StringName = &""
var _buffered_until: int = 0
var _move_res: ODGrid.MoveResult = ODGrid.MoveResult.new()
## Math.fround scratch: writing into a PackedFloat32Array rounds to float32 exactly like it.
var _f32: PackedFloat32Array = PackedFloat32Array([0.0])

## The local tick the next `step` will simulate (= ticks simulated so far).
var tick: int:
	get:
		return _tick

## Current pose (the pose of sample `tick`). A fresh object each read.
var pose: PlayerPose:
	get:
		var p := PlayerPose.new()
		p.x = _x
		p.y = _y
		p.facing = _facing
		p.anim = _current_anim(_tick - 1)
		p.vx = _vx
		p.vy = _vy
		return p

## Kind of the action in progress (ActionKind.*), &"" when none (for HUD prompts).
var action_kind: StringName:
	get:
		return _action.kind if _action != null else &""

## Ticks until a dodge may start (0 = ready).
var dodge_cooldown: int:
	get:
		return maxi(0, _next_dodge - _tick)

## Ticks until a ranged shot may start (0 = ready).
var ranged_cooldown: int:
	get:
		return maxi(0, _next_ranged - _tick)


func _init(start: PlayerStart) -> void:
	_x = _fround(start.x)
	_y = _fround(start.y)
	_facing = _fround(TapeLib.wrap_angle(start.facing))


func _fround(v: float) -> float:
	_f32[0] = v
	return _f32[0]


## Move the body from outside the controller (belts and bumpers, docs/TRAPS.md "The live self"):
## sets the position, rounded to float32 like every position the controller stores, and leaves the
## velocity alone, so the world moving the body adds no swing momentum. The prototype wrote the two
## private fields directly (traps/live.ts displaceController); the porting notes ask for this method.
func displace(x: float, y: float) -> void:
	_x = _fround(x)
	_y = _fround(y)


## 'killRefresh' ability: the kernel calls this when the live self's melee kills an enemy.
func refresh_dodge() -> void:
	_next_dodge = _tick


static func _pressed(input: PlayerInput, kind: StringName) -> bool:
	match kind:
		ActionKind.DODGE:
			return input.dodge
		ActionKind.HEAVY:
			return input.heavy
		ActionKind.LIGHT:
			return input.light
		ActionKind.RANGED:
			return input.ranged
		ActionKind.INTERACT:
			return input.interact
	return false


## Advance one local tick.
##
## `_life` (OD.LifeState.ALIVE or REC_GHOST) does not change physics on purpose: a recording ghost
## keeps normal movement, collision and actions (GHOST-02, GHOST-03); invulnerability (GHOST-04) is
## the kernel's rule. It is taken so the call site states which body it is driving, and to keep the
## signature stable if gear ever differentiates the two.
func step(input: PlayerInput, grid: ODGrid, loadout: ResolvedLoadout, _life: int) -> PlayerStepResult:
	var base := Tuning.BASE
	var t := _tick
	var events: Array[TapeEvent] = []
	var mods := loadout.mods

	# Sanitise input: NaN-safe, length clamped to 1.
	var mx := input.move_x if is_finite(input.move_x) else 0.0
	var my := input.move_y if is_finite(input.move_y) else 0.0
	var mlen := ODGrid.hypot(mx, my)
	if mlen > 1.0:
		mx /= mlen
		my /= mlen
	var move_len := minf(1.0, mlen)
	var aim := TapeLib.wrap_angle(input.aim) if is_finite(input.aim) else _facing
	var start_x := _x
	var start_y := _y
	var start_vx := _vx
	var start_vy := _vy

	# Ability presses are instant and never commit the body.
	if input.ability:
		var any_active := false
		for a: StringName in loadout.abilities:
			if ACTIVE_ABILITIES.has(a):
				any_active = true
				break
		if any_active:
			events.append(TapeEvent.make(t, ActionKind.ABILITY, aim, start_x, start_y, start_vx, start_vy))

	# Buffer the highest-priority press of this tick (a newer press replaces an older one).
	for k: StringName in PRESS_ORDER:
		if _pressed(input, k):
			_buffered_kind = k
			_buffered_until = t + base.input_buffer_ticks
			break
	if _buffered_kind != &"" and t > _buffered_until:
		_buffered_kind = &""

	# End finished actions; a dodge hands its dash speed back as running momentum.
	if _action != null and t - _action.start >= _action.timing.commit:
		if _action.kind == ActionKind.DODGE:
			var exit := base.run_speed * mods.move_speed * base.dodge_exit_speed
			_vx = _action.dx * exit
			_vy = _action.dy * exit
		_action = null
	# A buffered dodge may cancel a melee swing's recovery (never its windup or hit frames).
	if (
		_action != null
		and _buffered_kind == ActionKind.DODGE
		and t >= _next_dodge
		and (_action.kind == ActionKind.LIGHT or _action.kind == ActionKind.HEAVY)
		and t - _action.start >= _action.timing.active_end
	):
		_action = null

	# Start the buffered action if the body is free and its cooldown has elapsed.
	if _action == null and _buffered_kind != &"":
		var kind := _buffered_kind
		var ready := t >= _next_dodge if kind == ActionKind.DODGE else (t >= _next_ranged if kind == ActionKind.RANGED else true)
		if ready:
			_buffered_kind = &""
			var timing := action_timing(kind, loadout)
			var dir := aim
			var dx := 0.0
			var dy := 0.0
			if kind == ActionKind.DODGE:
				if move_len > 1e-6:
					dir = atan2(my, mx)
				else:
					dir = _facing
				dx = cos(dir)
				dy = sin(dir)
				_next_dodge = t + timing.cooldown
			elif kind == ActionKind.RANGED:
				_next_ranged = t + timing.cooldown
			var act := _ActiveAction.new()
			act.kind = kind
			act.start = t
			act.dir = dir
			act.timing = timing
			act.dx = dx
			act.dy = dy
			_action = act
			events.append(TapeEvent.make(t, kind, dir, start_x, start_y, start_vx, start_vy))

	# ── locomotion ──
	var act := _action
	var elapsed := t - act.start if act != null else 0
	var move_opts: ODGrid.MoveOpts = _PHASE_OPTS if act != null and act.kind == ActionKind.DODGE and loadout.abilities.has(AbilityId.PHASE_DODGE) else null
	# A door can close onto the body between ticks (the kernel never deletes a body): step out to
	# the nearest free side first, so the push is not mistaken for running speed below.
	if grid.is_solid_at(_x, _y, base.actor_radius, move_opts):
		var pushed := grid.move_circle(_x, _y, 0.0, 0.0, base.actor_radius, move_opts, _move_res)
		_x = _fround(pushed.x)
		_y = _fround(pushed.y)
	if act != null and act.kind == ActionKind.DODGE:
		var speed := (base.dodge_distance * mods.dodge_distance) / (act.timing.commit * DT)
		_vx = act.dx * speed
		_vy = act.dy * speed
	else:
		var mul := act.timing.move_mul if act != null else 1.0
		_locomote(mx, my, move_len, base.run_speed * mods.move_speed * mul, mods.accel, mods.momentum_retention)

	var res := grid.move_circle(_x, _y, _vx * DT, _vy * DT, base.actor_radius, move_opts, _move_res)
	var nx := _fround(res.x)
	var ny := _fround(res.y)
	if res.blocked:
		# Keep only the motion the walls allowed: sliding survives, the normal component dies.
		_vx = (nx - _x) / DT
		_vy = (ny - _y) / DT
	_x = nx
	_y = ny

	# ── facing ──
	if act != null and elapsed < act.timing.face_lock:
		_facing = act.dir
	elif move_len > 1e-6:
		var want := atan2(my, mx)
		var d := TapeLib.angle_delta(_facing, want)
		var max_turn := base.facing_turn_rate * DT
		_facing = want if absf(d) <= max_turn else TapeLib.wrap_angle(_facing + signf(d) * max_turn)
	_facing = _fround(_facing)

	var anim := _current_anim(t)
	var iframes := act != null and act.kind == ActionKind.DODGE and elapsed >= act.timing.iframe_start and elapsed < act.timing.iframe_end
	_tick = t + 1
	var out := PlayerStepResult.new()
	out.x = _x
	out.y = _y
	out.facing = _facing
	out.anim = anim
	out.vx = _vx
	out.vy = _vy
	out.events = events
	out.iframes = iframes
	return out


## Anim for tick `t` given the current action state (called after the tick's state is settled).
func _current_anim(t: int) -> StringName:
	var act := _action
	if act != null and t >= act.start and t - act.start < act.timing.commit:
		var a := action_anim(act.kind, t - act.start, act.timing)
		if a != &"":
			return a
	return AnimState.RUN if ODGrid.hypot(_vx, _vy) >= Tuning.BASE.run_anim_threshold else AnimState.IDLE


## Velocity update toward the input. The component along the input accelerates linearly to the
## cap; sideways velocity and overspeed decay exponentially at rates divided by momentum
## retention (so retention gear carries momentum through turns and out of dashes); with no input
## the body brakes linearly.
func _locomote(mx: float, my: float, move_len: float, max_speed: float, accel_mod: float, retention_mod: float) -> void:
	var base := Tuning.BASE
	var ret := retention_mod if retention_mod > 0.05 else 0.05
	if move_len > 1e-6:
		var inv := 1.0 / ODGrid.hypot(mx, my)
		var ux := mx * inv
		var uy := my * inv
		var target := max_speed * move_len
		var par := _vx * ux + _vy * uy
		var px := _vx - par * ux
		var py := _vy - par * uy
		var keep := exp((-base.turn_damping / ret) * DT)
		px *= keep
		py *= keep
		if par < target:
			# Reversing brakes with decel on top of accel so direction changes stay snappy.
			var a := (base.accel + base.decel if par < 0.0 else base.accel) * accel_mod
			par = minf(target, par + a * DT)
		elif par > target:
			par = target + (par - target) * exp((-base.overspeed_decay / ret) * DT)
		_vx = par * ux + px
		_vy = par * uy + py
	else:
		var speed := ODGrid.hypot(_vx, _vy)
		if speed > 0.0:
			var ns := maxf(0.0, speed - ((base.decel * accel_mod) / ret) * DT)
			var k := ns / speed
			_vx *= k
			_vy *= k
	# Snap tiny residuals so a released stick reaches true rest (stable idle anim, clean tapes).
	if absf(_vx) < 1e-6:
		_vx = 0.0
	if absf(_vy) < 1e-6:
		_vy = 0.0


## A neutral input (no movement, no buttons), handy for tests and for idling the live self.
static func idle_input(aim: float = 0.0) -> PlayerInput:
	return PlayerInput.make(0.0, 0.0, aim)
