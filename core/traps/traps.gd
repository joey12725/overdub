class_name Traps
extends RefCounted
## Traps and automated machinery (prototype core/traps/system.ts; docs/TRAPS.md): spikes, crushers,
## conveyors, flame jets, dart launchers, bumpers, beam sensors, relays and magnets.
##
## Traps are deterministic machines driven by SignalExpr. They are indifferent to who triggers them:
## the same rule kills a self and damages an enemy. Nothing here targets, randomises or remembers
## anything across runs.
##
## WHERE THEY RUN IN A SUBSTEP (ODSim substep order; `now = s + 1` is the instant being produced):
##
##   3b. sense   sensors (entity order), then relays (entity order). Their signals are written before
##               mechanisms run, so a door reads a sensor of the SAME substep.
##   4.  mechanisms (unchanged)
##   4b. step    first: push living enemies out of any crusher that turned solid on the previous
##               substep; then every other trap in ENTITY ORDER (spikes raise/drop and contact hits,
##               crusher stroke / hold / retract, conveyor carry, flame reach and contact hits, dart
##               spawns on the beat grid, bumper fires on the rising edge, magnet pulls). Each trap
##               writes its `id` signal as it goes, so a trap later in entity order reads it the same
##               substep; mechanisms and earlier traps read it on the next.
##   5-9         (unchanged): trap hits are queued on w.combat and applied in phase 7 together with
##               every other hit of the substep.
##
## THE LIVE SELF. Belts and bumpers physically move the live self (alive or recording ghost, synced)
## once per LOCAL tick, in ODSim.step_local_tick before the PlayerController runs (live_carry), by
## the amount the world moves in that tick, so the displacement is recorded on the tape as ordinary
## movement. Playback selves are never displaced (PLAY-01, MOM-06).
##
## TELEGRAPH. `warn` (0..1) is presentation only. While a hazard is off, the system looks for the
## first instant on the sixteenth grid within TRAP_WARN_BEATS at which its expression will be true,
## holding every signal at its current value except relay outputs, which are forecast from their
## armed / running state. The forecast never changes the simulation.
##
## A level with no trap entities builds an empty system: every entry point returns at once and the
## run is bit for bit what it was before traps existed.
##
## One Traps per sim (it holds per-run state and scratch); nothing here is static.
##
## JS vs GDScript: Math.round -> floori(x + 0.5); Math.hypot -> ODGrid.hypot; Map/Set -> Dictionary.

const PHASE_OPEN: int = 0
const PHASE_EXTENDED: int = 1
const PHASE_RETRACTING: int = 2


## Per-trap state (the prototype's TrapState union; `kind` tells which fields are used).
class TrapState:
	extends RefCounted
	var kind: StringName = &""
	var id: String = ""
	var def: TrapDef = null
	## Tile indices covered (spikes, crusher, conveyor).
	var cells: Dictionary[int, bool] = {}
	## Event / presentation position.
	var at_x: float = 0.0
	var at_y: float = 0.0
	## spikes: raised. flame / magnet: on. dart: enabled. conveyor: running. sensor: tripped.
	## relay: output.
	var on: bool = false
	## conveyor: reversed.
	var reversed: bool = false
	## crusher: PHASE_*; k = retract substeps left.
	var phase: int = PHASE_OPEN
	var k: int = 0
	## spikes / flame: enemy id -> substep of its next hit while contact is unbroken.
	var contact: Dictionary[String, int] = {}
	## Telegraph: instant (`now` units) the hazard is forecast to activate, or -1; warn as of the last
	## update.
	var tele_on_at: int = -1
	var tele_warn: float = 0.0
	## flame: tiles covered now. sensor: live beam length.
	var reach: float = 0.0
	## dart: grid period and offset in substeps; substep of the last shot (-1 = none).
	var per: int = 1
	var off: int = 0
	var last_fire: int = -1
	## bumper / relay: trigger as of the previous substep (rising-edge detector).
	var prev: bool = false
	## bumper: substep it last fired (-1 = never) and whether its pulse is up.
	var fired_at: int = -1
	var pulse: bool = false
	## relay: armed, the instants (`now` units) it was armed and fires, and the pulse end (-1 = none).
	var armed: bool = false
	var armed_at: int = -1
	var fire_at: int = -1
	var end_at: int = -1


## Number of trap entities in the level. 0 = the whole system is inert.
var count: int = 0
## Belt carry / bumper launch result of the last live_carry() that returned true.
var carry_x: float = 0.0
var carry_y: float = 0.0

## Every trap in entity order (= snapshot order).
var _order: Array[TrapState] = []
var _sensors: Array[TrapState] = []
var _relays: Array[TrapState] = []
var _conveyors: Array[TrapState] = []
## Tile index -> crusher id (player-readable desync causes).
var _crusher_cell: Dictionary[int, String] = {}
var _grid: ODGrid = null
var _signals: Dictionary[String, bool] = {}
## A crusher turned solid last substep: enemies left inside solid geometry must be pushed out.
var _needs_clear: bool = false
## Enemy id -> substep it was last belt-carried (a body is carried by one belt per substep).
var _carried_at: Dictionary[String, int] = {}
## Remaining bumper launch of the live self: per-substep displacement and substeps left.
var _launch_dx: float = 0.0
var _launch_dy: float = 0.0
var _launch_subs: int = 0
var _spb: int = 1
## Telegraph scratch: the signal table as forecast at a future instant (FutureSignals).
var _future: Dictionary[String, bool] = {}
var _mv: ODGrid.MoveResult = ODGrid.MoveResult.new()
var _ray: ODGrid.RayHit = ODGrid.RayHit.new()


static func _js_round(v: float) -> int:
	return floori(v + 0.5)


static func _centroid(t: TrapState, cells: Array[Vector2i]) -> void:
	var x: float = 0.0
	var y: float = 0.0
	for c: Vector2i in cells:
		x += c.x + 0.5
		y += c.y + 0.5
	var n: int = maxi(1, cells.size())
	t.at_x = x / n
	t.at_y = y / n


## Distance from (px, py) to the segment a-b (traps/system.ts pointSegDist).
static func point_seg_dist(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
	var vx: float = bx - ax
	var vy: float = by - ay
	var l2: float = vx * vx + vy * vy
	var t: float = ((px - ax) * vx + (py - ay) * vy) / l2 if l2 > 0.0 else 0.0
	t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
	return ODGrid.hypot(ax + vx * t - px, ay + vy * t - py)


func _init(level: LevelDef, grid: ODGrid, signals: Dictionary[String, bool]) -> void:
	_grid = grid
	_signals = signals
	for ent: EntityDef in level.entities:
		if not EntityKind.is_trap(ent.kind):
			continue
		var t := TrapState.new()
		t.kind = ent.kind
		t.id = ent.id
		t.def = ent as TrapDef
		match ent.kind:
			EntityKind.SPIKES:
				var d: SpikesDef = ent as SpikesDef
				_cell_set(t, d.cells)
				_centroid(t, d.cells)
			EntityKind.CRUSHER:
				var d: CrusherDef = ent as CrusherDef
				_cell_set(t, d.cells)
				for i: int in t.cells:
					_crusher_cell[i] = d.id
				_centroid(t, d.cells)
			EntityKind.CONVEYOR:
				var d: ConveyorDef = ent as ConveyorDef
				_cell_set(t, d.cells)
				_centroid(t, d.cells)
				_conveyors.append(t)
			EntityKind.FLAME:
				var d: FlameDef = ent as FlameDef
				t.at_x = d.c + 0.5
				t.at_y = d.r + 0.5
			EntityKind.DART:
				var d: DartDef = ent as DartDef
				t.at_x = d.c + 0.5
				t.at_y = d.r + 0.5
			EntityKind.BUMPER:
				var d: BumperDef = ent as BumperDef
				t.at_x = d.c + 0.5
				t.at_y = d.r + 0.5
			EntityKind.SENSOR:
				var d: SensorDef = ent as SensorDef
				t.at_x = (d.from_x + d.to_x) / 2.0
				t.at_y = (d.from_y + d.to_y) / 2.0
				_sensors.append(t)
			EntityKind.RELAY:
				var d: RelayDef = ent as RelayDef
				t.at_x = TrapDef.num_or(d.x, 0.0)
				t.at_y = TrapDef.num_or(d.y, 0.0)
				_relays.append(t)
			EntityKind.MAGNET:
				var d: MagnetDef = ent as MagnetDef
				t.at_x = d.x
				t.at_y = d.y
		_order.append(t)
	count = _order.size()


func _cell_set(t: TrapState, cells: Array[Vector2i]) -> void:
	for c: Vector2i in cells:
		if _grid.in_bounds(c.x, c.y):
			t.cells[_grid.index(c.x, c.y)] = true


## State at beat zero. Idempotent: the sim calls it before AND after Mechanisms.init so that doors
## see trap signals and traps see door signals in the initial state. Nothing strokes, fires or
## launches at beat zero: a crusher whose expression starts true starts extended, harmlessly.
func init(w: ODSim) -> void:
	if count == 0:
		return
	var spb: int = w.spb
	_spb = spb
	for t: TrapState in _sensors:
		t.on = false
		_sense_one(w, t, true)
	for t: TrapState in _order:
		match t.kind:
			EntityKind.RELAY:
				var d: RelayDef = t.def as RelayDef
				t.on = false
				t.armed = false
				t.end_at = -1
				t.prev = ODSignals.eval_signal(d.trigger, _signals, 0.0)
				_signals[t.id] = false
				_signals[t.id + ".armed"] = false
			EntityKind.SPIKES:
				var d: SpikesDef = t.def as SpikesDef
				t.on = ODSignals.eval_signal(d.up_when, _signals, 0.0)
				_signals[t.id] = t.on
			EntityKind.CRUSHER:
				var d: CrusherDef = t.def as CrusherDef
				var ext: bool = ODSignals.eval_signal(d.extend_when, _signals, 0.0)
				t.phase = PHASE_EXTENDED if ext else PHASE_OPEN
				t.k = 0
				_set_solid(d, ext)
				_signals[t.id] = ext
			EntityKind.CONVEYOR:
				var d: ConveyorDef = t.def as ConveyorDef
				t.on = ODSignals.eval_signal(d.run_when, _signals, 0.0) if d.run_when != null else true
				t.reversed = ODSignals.eval_signal(d.reverse_when, _signals, 0.0) if d.reverse_when != null else false
				_signals[t.id] = t.on
				_signals[t.id + ".rev"] = t.reversed
			EntityKind.FLAME:
				var d: FlameDef = t.def as FlameDef
				t.on = ODSignals.eval_signal(d.on_when, _signals, 0.0)
				t.reach = _flame_reach(d)
				_signals[t.id] = t.on
			EntityKind.DART:
				var d: DartDef = t.def as DartDef
				t.per = maxi(1, _js_round(TrapDef.num_or(d.every, TrapTuning.DART_EVERY) * spb))
				t.off = _js_round(TrapDef.num_or(d.offset, TrapTuning.DART_OFFSET) * spb)
				t.on = ODSignals.eval_signal(d.enabled_when, _signals, 0.0) if d.enabled_when != null else true
				_signals[t.id] = t.on
			EntityKind.BUMPER:
				var d: BumperDef = t.def as BumperDef
				t.prev = ODSignals.eval_signal(d.fire_when, _signals, 0.0)
				t.pulse = false
				_signals[t.id] = false
			EntityKind.MAGNET:
				var d: MagnetDef = t.def as MagnetDef
				t.on = ODSignals.eval_signal(d.on_when, _signals, 0.0)
				_signals[t.id] = t.on


## Name of the trap making a tile solid ("crusher cr1"), or "" for none.
func owner_at(c: int, r: int) -> String:
	if count == 0 or not _grid.in_bounds(c, r):
		return ""
	var idx: int = _grid.index(c, r)
	if not _crusher_cell.has(idx):
		return ""
	return "crusher %s" % _crusher_cell[idx]

# ───────────────────────────── phase 3b: signal sources ─────────────────────────────


func sense(w: ODSim) -> void:
	if count == 0:
		return
	for t: TrapState in _sensors:
		_sense_one(w, t, false)
	for t: TrapState in _relays:
		_step_relay(w, t)


func _sense_one(w: ODSim, t: TrapState, initial: bool) -> void:
	var d: SensorDef = t.def as SensorDef
	var fx: float = d.from_x
	var fy: float = d.from_y
	var vx: float = d.to_x - fx
	var vy: float = d.to_y - fy
	var len: float = ODGrid.hypot(vx, vy)
	var reach: float = len
	if len > 0.0:
		var hit: ODGrid.RayHit = _grid.raycast(fx, fy, vx, vy, len, true, _ray)
		if hit.hit:
			reach = hit.dist
	t.reach = reach
	if t.on and d.latch:
		return
	var k: float = reach / len if len > 0.0 else 0.0
	var ex: float = fx + vx * k
	var ey: float = fy + vy * k
	var detects: StringName = d.detects if d.detects != &"" else SensorDef.DETECTS_ANY
	var on: bool = false
	if detects != SensorDef.DETECTS_ENEMIES:
		var ar: float = Tuning.BASE.actor_radius
		for se: SelfActor in w.selves:
			if not se.can_act:
				continue
			if point_seg_dist(se.pose.x, se.pose.y, fx, fy, ex, ey) < ar:
				on = true
				break
	if not on and detects != SensorDef.DETECTS_SELVES:
		for e: EnemyState in w.enemies:
			if not e.alive:
				continue
			if point_seg_dist(e.x, e.y, fx, fy, ex, ey) < e.stats.radius:
				on = true
				break
	if initial:
		t.on = on
		_signals[t.id] = on
		return
	if on != t.on:
		t.on = on
		_signals[t.id] = on
		w.emit(SimEvent.make(0, SimEventType.TRAP, t.at_x, t.at_y).with_id(t.id).with_detail("sensor:on" if on else "sensor:off"))


static func _hold_subs(d: RelayDef, spb: int) -> int:
	return maxi(1, _js_round(TrapDef.num_or(d.hold, TrapTuning.RELAY_HOLD) * spb))


func _step_relay(w: ODSim, t: TrapState) -> void:
	var d: RelayDef = t.def as RelayDef
	var now: int = w.now
	var mode: StringName = d.mode_or_default()
	var trig: bool = ODSignals.eval_signal(d.trigger, _signals, w.beat)
	var rising: bool = trig and not t.prev
	t.prev = trig
	# A running pulse ends first, so a pulse of exactly one period can be re-armed back to back.
	if t.end_at >= 0 and now >= t.end_at:
		t.end_at = -1
		_set_relay_out(w, t, false)
	if rising and not t.armed and t.end_at < 0 and not (mode == RelayDef.MODE_LATCH and t.on):
		var q: int = _js_round(TrapDef.num_or(d.quantize, TrapTuning.RELAY_QUANTIZE) * w.spb)
		var base: int = ceili(float(now) / q) * q if q > 0 else now
		t.armed = true
		t.armed_at = now
		t.fire_at = base + maxi(0, _js_round(TrapDef.num_or(d.delay, TrapTuning.RELAY_DELAY) * w.spb))
		_signals[t.id + ".armed"] = true
		w.emit(
			SimEvent.make(0, SimEventType.TRAP, t.at_x, t.at_y).with_id(t.id).with_detail("relay:armed")
			.with_power(float(t.fire_at - now) / w.spb)
		)
	if t.armed and now >= t.fire_at:
		t.armed = false
		_signals[t.id + ".armed"] = false
		if mode == RelayDef.MODE_TOGGLE:
			_set_relay_out(w, t, not t.on)
		elif mode == RelayDef.MODE_LATCH:
			_set_relay_out(w, t, true)
		else:
			t.end_at = t.fire_at + _hold_subs(d, w.spb)
			_set_relay_out(w, t, true)


func _set_relay_out(w: ODSim, t: TrapState, out: bool) -> void:
	if t.on == out:
		return
	t.on = out
	_signals[t.id] = out
	w.emit(SimEvent.make(0, SimEventType.TRAP, t.at_x, t.at_y).with_id(t.id).with_detail("relay:on" if out else "relay:off"))

# ───────────────────────────── phase 4b: machines ─────────────────────────────


func step(w: ODSim) -> void:
	if count == 0:
		return
	if _needs_clear:
		_needs_clear = false
		_clear_enemies(w)
	for t: TrapState in _order:
		match t.kind:
			EntityKind.SPIKES:
				_step_spikes(w, t)
			EntityKind.CRUSHER:
				_step_crusher(w, t)
			EntityKind.CONVEYOR:
				_step_conveyor(w, t)
			EntityKind.FLAME:
				_step_flame(w, t)
			EntityKind.DART:
				_step_dart(w, t)
			EntityKind.BUMPER:
				_step_bumper(w, t)
			EntityKind.MAGNET:
				_step_magnet(w, t)


## A '<kind>:<what>' trap event; `dir` / `power` are added when not NAN.
func _emit(w: ODSim, t: TrapState, what: String, dir: float = NAN, power: float = NAN) -> void:
	var ev := SimEvent.make(0, SimEventType.TRAP, t.at_x, t.at_y).with_id(t.id).with_detail("%s:%s" % [t.kind, what])
	if not is_nan(dir):
		ev.with_dir(dir)
	if not is_nan(power):
		ev.with_power(power)
	w.emit(ev)


## The relay output forecast at instant `at` (FutureSignals.get for a relay).
func _relay_forecast(r: TrapState, at: int) -> bool:
	var out: bool = r.on
	if r.armed and r.fire_at <= at:
		var mode: StringName = (r.def as RelayDef).mode_or_default()
		if mode == RelayDef.MODE_TOGGLE:
			out = not out
		elif mode == RelayDef.MODE_LATCH:
			out = true
		else:
			out = at < r.fire_at + _hold_subs(r.def as RelayDef, _spb)
	elif r.end_at >= 0 and r.end_at <= at:
		out = false
	return out


## Telegraph forecast for a hazard that is currently off (see the file header). Emits '<kind>:warn'
## once when an activation first comes into view.
func _telegraph(w: ODSim, t: TrapState, expr: SignalExpr, active: bool) -> void:
	if active:
		t.tele_on_at = -1
		t.tele_warn = 0.0
		return
	var now: int = w.now
	var spb: int = w.spb
	var span: int = _js_round(TrapTuning.TRAP_WARN_BEATS * spb)
	var refresh: int = maxi(1, _js_round(spb / TrapTuning.TRAP_WARN_REFRESH_PER_BEAT))
	if t.tele_on_at <= now or now % refresh == 0:
		var had: bool = t.tele_on_at > now
		var g: int = maxi(1, _js_round(spb / TrapTuning.TRAP_WARN_GRID_PER_BEAT))
		var found: int = -1
		# Every signal holds its current value except relay outputs, which follow their schedule.
		var table: Dictionary[String, bool] = _signals
		if not _relays.is_empty():
			_future.clear()
			_future.merge(_signals)
			table = _future
		# Nothing is forecast past the end of the encounter: no activation follows the horizon.
		var until: int = mini(now + span, w.horizon_subs)
		@warning_ignore("integer_division")
		var at: int = (now / g + 1) * g
		while at <= until:
			for r: TrapState in _relays:
				_future[r.id] = _relay_forecast(r, at)
			if ODSignals.eval_signal(expr, table, float(at) / spb):
				found = at
				break
			at += g
		t.tele_on_at = found
		if found >= 0 and not had:
			_emit(w, t, "warn", NAN, float(found - now) / spb)
	t.tele_warn = clampf(1.0 - float(t.tele_on_at - now) / span, 0.0, 1.0) if t.tele_on_at > now else 0.0


## One hazard contact test for an enemy: hit on first contact, then once per full beat of contact.
func _hazard_touch(w: ODSim, t: TrapState, e: EnemyState, touching: bool, damage: float, cause: String) -> void:
	var has: bool = t.contact.has(e.id)
	if not touching:
		if has:
			t.contact.erase(e.id)
		return
	var s: int = w.s
	var next: int = t.contact[e.id] if has else 0
	if has and s < next:
		return
	var retick: int = maxi(1, _js_round(TrapTuning.HAZARD_RETICK_BEATS * w.spb))
	t.contact[e.id] = next + retick if has else s + retick
	w.combat.strike_enemy(
		e,
		(
			EnemyStrike.make(StrikeSource.of_env(cause), String(t.kind), 1.0, 0.0, e.x, e.y)
			.with_damage(damage)
			.with_knockback(0.0)
			.with_stagger(TrapTuning.HAZARD_STAGGER)
		)
	)


func _tile_index_at(x: float, y: float) -> int:
	var c: int = floori(x)
	var r: int = floori(y)
	return _grid.index(c, r) if _grid.in_bounds(c, r) else -1

# ── spikes ──


func _step_spikes(w: ODSim, t: TrapState) -> void:
	var d: SpikesDef = t.def as SpikesDef
	var up: bool = ODSignals.eval_signal(d.up_when, _signals, w.beat)
	if up != t.on:
		t.on = up
		_signals[t.id] = up
		_emit(w, t, "up" if up else "down")
		if not up:
			t.contact.clear()
	_telegraph(w, t, d.up_when, up)
	if not up:
		return
	var cause: String = "spikes %s" % t.id
	for se: SelfActor in w.selves:
		if not se.vulnerable:
			continue
		if t.cells.has(_tile_index_at(se.pose.x, se.pose.y)):
			w.combat.hit_self(SelfHit.make(se, "skewered by %s" % cause, se.pose.x, se.pose.y, 0.0))
	var damage: float = TrapDef.num_or(d.damage, TrapTuning.SPIKES_DAMAGE)
	for e: EnemyState in w.enemies:
		if not e.alive:
			continue
		var touching: bool = not e.beh.hovering and t.cells.has(_tile_index_at(e.x, e.y))
		_hazard_touch(w, t, e, touching, damage, cause)

# ── crusher ──


func _set_solid(d: CrusherDef, solid: bool) -> void:
	for c: Vector2i in d.cells:
		_grid.set_dynamic_solid(c.x, c.y, solid)


func _step_crusher(w: ODSim, t: TrapState) -> void:
	var d: CrusherDef = t.def as CrusherDef
	var want: bool = ODSignals.eval_signal(d.extend_when, _signals, w.beat)
	if t.phase == PHASE_OPEN:
		if want:
			_stroke(w, t)
	elif t.phase == PHASE_EXTENDED:
		if not want:
			t.phase = PHASE_RETRACTING
			t.k = TrapTuning.CRUSHER_RETRACT_SUBS
			_emit(w, t, "retract")
	elif want:
		# Re-extends without a stroke: the tiles never opened, so nothing can be under the head.
		t.phase = PHASE_EXTENDED
		t.k = 0
		_emit(w, t, "hold")
	else:
		t.k -= 1
		if t.k <= 0:
			t.k = 0
			t.phase = PHASE_OPEN
			_set_solid(d, false)
			_signals[t.id] = false
			_emit(w, t, "open")
	_telegraph(w, t, d.extend_when, t.phase != PHASE_OPEN)


func _stroke(w: ODSim, t: TrapState) -> void:
	var d: CrusherDef = t.def as CrusherDef
	t.phase = PHASE_EXTENDED
	t.k = 0
	var cause: String = "crusher %s" % t.id
	var struck: int = 0
	for se: SelfActor in w.selves:
		if not se.vulnerable:
			continue
		if t.cells.has(_tile_index_at(se.pose.x, se.pose.y)):
			struck += 1
			w.combat.hit_self(SelfHit.make(se, "crushed by %s" % cause, se.pose.x, se.pose.y, 0.0))
	var damage: float = TrapDef.num_or(d.damage, TrapTuning.CRUSHER_DAMAGE)
	for e: EnemyState in w.enemies:
		if not e.alive or not t.cells.has(_tile_index_at(e.x, e.y)):
			continue
		struck += 1
		w.combat.strike_enemy(
			e,
			(
				EnemyStrike.make(StrikeSource.of_env(cause), "crusher", damage, 0.0, e.x, e.y)
				.with_damage(damage)
				.with_knockback(0.0)
				.with_stagger(TrapTuning.HAZARD_STAGGER)
			)
		)
	_set_solid(d, true)
	_signals[t.id] = true
	_needs_clear = true
	_emit(w, t, "slam", NAN, float(struck))


## Push living enemies out of solid geometry (never delete a body); same rule as a closing door.
func _clear_enemies(w: ODSim) -> void:
	for e: EnemyState in w.enemies:
		if not e.alive:
			continue
		var r: float = e.stats.radius
		var solid: bool = DroneBehaviour.hover_solid_at(_grid, e.x, e.y, r) if e.beh.hovering else _grid.is_solid_at(e.x, e.y, r)
		if not solid:
			continue
		var res: ODGrid.MoveResult = _grid.move_circle(e.x, e.y, 0.0, 0.0, r, null, _mv)
		e.x = res.x
		e.y = res.y
		e.path = []
		e.path_idx = 0

# ── conveyor ──


static func _belt_angle(t: TrapState) -> float:
	var a: float = Dir4.angle((t.def as ConveyorDef).dir)
	if not t.reversed:
		return a
	return a - PI if a > 0.0 else a + PI


## A body belts and bumpers can move: on the floor and not bolted down.
static func _grounded_movable(e: EnemyState) -> bool:
	return not e.beh.hovering and is_finite(e.stats.mass)


func _step_conveyor(w: ODSim, t: TrapState) -> void:
	var d: ConveyorDef = t.def as ConveyorDef
	var beat: float = w.beat
	var running: bool = ODSignals.eval_signal(d.run_when, _signals, beat) if d.run_when != null else true
	var reversed: bool = ODSignals.eval_signal(d.reverse_when, _signals, beat) if d.reverse_when != null else false
	if running != t.on:
		t.on = running
		_signals[t.id] = running
		_emit(w, t, "on" if running else "off", _belt_angle(t))
	if reversed != t.reversed:
		t.reversed = reversed
		_signals[t.id + ".rev"] = reversed
		_emit(w, t, "reverse" if reversed else "forward", _belt_angle(t))
	if not running:
		return
	var dist: float = (TrapDef.num_or(d.speed, TrapTuning.CONVEYOR_SPEED) / OD.SUB_HZ) * (-1.0 if reversed else 1.0)
	var dx: float = Dir4.dx(d.dir) * dist
	var dy: float = Dir4.dy(d.dir) * dist
	var s: int = w.s
	for e: EnemyState in w.enemies:
		if not e.alive or not _grounded_movable(e):
			continue
		if _carried_at.get(e.id, -1) == s:
			continue
		if not t.cells.has(_tile_index_at(e.x, e.y)):
			continue
		_carried_at[e.id] = s
		var res: ODGrid.MoveResult = _grid.move_circle(e.x, e.y, dx, dy, e.stats.radius, null, _mv)
		e.x = res.x
		e.y = res.y
	for p: Projectile in w.projectiles.list:
		if not p.alive or p.z > 0.0:
			continue
		if not t.cells.has(_tile_index_at(p.x, p.y)):
			continue
		var nx: float = p.x + dx
		var ny: float = p.y + dy
		if not p.passes_walls and _grid.blocks_shot(floori(nx), floori(ny)):
			continue
		p.x = nx
		p.y = ny

# ── flame ──


func _flame_reach(d: FlameDef) -> float:
	var vx: int = Dir4.dx(d.dir)
	var vy: int = Dir4.dy(d.dir)
	var rng: int = maxi(0, floori(d.range))
	var n: int = 0
	for k: int in range(1, rng + 1):
		if _grid.blocks_shot(d.c + vx * k, d.r + vy * k):
			break
		n = k
	return float(n)


## Is world point (x, y) on one of the first `reach` tiles of the jet?
func _in_flame(t: TrapState, x: float, y: float) -> bool:
	var d: FlameDef = t.def as FlameDef
	var vx: int = Dir4.dx(d.dir)
	var vy: int = Dir4.dy(d.dir)
	var dc: int = floori(x) - d.c
	var dr: int = floori(y) - d.r
	var k: int = dc * vx + dr * vy
	return k >= 1 and k <= t.reach and dc == vx * k and dr == vy * k


func _step_flame(w: ODSim, t: TrapState) -> void:
	var d: FlameDef = t.def as FlameDef
	var on: bool = ODSignals.eval_signal(d.on_when, _signals, w.beat)
	t.reach = _flame_reach(d)
	var lane: float = Dir4.angle(d.dir)
	if on != t.on:
		t.on = on
		_signals[t.id] = on
		_emit(w, t, "on" if on else "off", lane, t.reach)
		if not on:
			t.contact.clear()
	_telegraph(w, t, d.on_when, on)
	if not on:
		return
	var cause: String = "flame jet %s" % t.id
	for se: SelfActor in w.selves:
		if not se.vulnerable:
			continue
		if _in_flame(t, se.pose.x, se.pose.y):
			w.combat.hit_self(SelfHit.make(se, "burned by %s" % cause, se.pose.x, se.pose.y, lane))
	var damage: float = TrapDef.num_or(d.damage, TrapTuning.FLAME_DAMAGE)
	for e: EnemyState in w.enemies:
		if not e.alive:
			continue
		_hazard_touch(w, t, e, _in_flame(t, e.x, e.y), damage, cause)

# ── dart launcher ──


func _step_dart(w: ODSim, t: TrapState) -> void:
	var d: DartDef = t.def as DartDef
	var enabled: bool = ODSignals.eval_signal(d.enabled_when, _signals, w.beat) if d.enabled_when != null else true
	if enabled != t.on:
		t.on = enabled
		_signals[t.id] = enabled
		_emit(w, t, "on" if enabled else "off")
	var s: int = w.s
	if not enabled or s < t.off or (s - t.off) % t.per != 0:
		return
	var vx: int = Dir4.dx(d.dir)
	var vy: int = Dir4.dy(d.dir)
	# A muzzle sealed by a door or an extended crusher fires nothing.
	if _grid.blocks_shot(d.c + vx, d.r + vy):
		return
	var lead: float = 0.5 + TrapTuning.DART_RADIUS + 0.01
	var dir: float = Dir4.angle(d.dir)
	DartArchetype.spawn_dart(w, t.id, t.at_x + vx * lead, t.at_y + vy * lead, dir, TrapDef.num_or(d.speed, TrapTuning.DART_SPEED))
	t.last_fire = s
	_emit(w, t, "fire", dir)

# ── bumper ──


func _step_bumper(w: ODSim, t: TrapState) -> void:
	var d: BumperDef = t.def as BumperDef
	var s: int = w.s
	if t.pulse and s >= t.fired_at + TrapTuning.BUMPER_PULSE_SUBS:
		t.pulse = false
		_signals[t.id] = false
	var want: bool = ODSignals.eval_signal(d.fire_when, _signals, w.beat)
	var rising: bool = want and not t.prev
	t.prev = want
	if not rising:
		return
	var power: float = TrapDef.num_or(d.power, TrapTuning.BUMPER_POWER)
	var dir: float = Dir4.angle(d.dir)
	var tile: int = _grid.index(d.c, d.r) if _grid.in_bounds(d.c, d.r) else -2
	var launched: int = 0
	for e: EnemyState in w.enemies:
		if not e.alive or not _grounded_movable(e):
			continue
		if _tile_index_at(e.x, e.y) != tile:
			continue
		EnemyCommon.apply_knockback(w, e, dir, power / e.stats.mass)
		launched += 1
	var live: SelfActor = _live_body(w)
	if live != null and _tile_index_at(live.pose.x, live.pose.y) == tile:
		_launch_dx = (Dir4.dx(d.dir) * power) / TrapTuning.BUMPER_FLIGHT_SUBS
		_launch_dy = (Dir4.dy(d.dir) * power) / TrapTuning.BUMPER_FLIGHT_SUBS
		_launch_subs = TrapTuning.BUMPER_FLIGHT_SUBS
		launched += 1
	t.fired_at = s
	t.pulse = true
	_signals[t.id] = true
	_emit(w, t, "fire", dir, float(launched))

# ── magnet ──


func _step_magnet(w: ODSim, t: TrapState) -> void:
	var d: MagnetDef = t.def as MagnetDef
	var on: bool = ODSignals.eval_signal(d.on_when, _signals, w.beat)
	if on != t.on:
		t.on = on
		_signals[t.id] = on
		_emit(w, t, "on" if on else "off")
	if not on:
		return
	var pull: float = TrapDef.num_or(d.pull, TrapTuning.MAGNET_PULL) / OD.SUB_HZ
	for e: EnemyState in w.enemies:
		var mass: float = e.stats.mass
		if not e.alive or not is_finite(mass) or not (mass > 0.0):
			continue
		var dx: float = d.x - e.x
		var dy: float = d.y - e.y
		var dist: float = ODGrid.hypot(dx, dy)
		if dist > d.radius or dist <= TrapTuning.MAGNET_HOLD_RADIUS:
			continue
		var stp: float = minf(pull / mass, dist - TrapTuning.MAGNET_HOLD_RADIUS)
		var mx: float = (dx / dist) * stp
		var my: float = (dy / dist) * stp
		if e.beh.hovering:
			DroneBehaviour.hover_move(w, e, mx, my)
		else:
			var res: ODGrid.MoveResult = _grid.move_circle(e.x, e.y, mx, my, e.stats.radius, null, _mv)
			e.x = res.x
			e.y = res.y

# ───────────────────────────── the live self ─────────────────────────────


## The live self while it has a physical body (alive or recording ghost, synced), or null.
static func _live_body(w: ODSim) -> SelfActor:
	for se: SelfActor in w.selves:
		if se.live:
			return se if se.can_act else null
	return null


## Belt carry and bumper launch of the live self for one local tick of `subs` master substeps.
## (x, y) is the PlayerController's current position. Returns true and sets carry_x / carry_y to the
## displaced position, or false when nothing moves it. Called by ODSim.step_local_tick before the
## controller steps.
func live_carry(w: ODSim, x: float, y: float, subs: int) -> bool:
	if count == 0:
		return false
	var live: SelfActor = _live_body(w)
	var dx: float = 0.0
	var dy: float = 0.0
	if _launch_subs > 0:
		var n: int = mini(subs, _launch_subs)
		_launch_subs -= n
		if live != null:
			dx += _launch_dx * n
			dy += _launch_dy * n
	if live == null:
		return false
	var tile: int = _tile_index_at(x, y)
	for t: TrapState in _conveyors:
		if not t.on or not t.cells.has(tile):
			continue
		var d: ConveyorDef = t.def as ConveyorDef
		var dist: float = (TrapDef.num_or(d.speed, TrapTuning.CONVEYOR_SPEED) / OD.SUB_HZ) * subs * (-1.0 if t.reversed else 1.0)
		dx += Dir4.dx(d.dir) * dist
		dy += Dir4.dy(d.dir) * dist
		break
	if dx == 0.0 and dy == 0.0:
		return false
	var res: ODGrid.MoveResult = _grid.move_circle(x, y, dx, dy, Tuning.BASE.actor_radius, null, _mv)
	carry_x = res.x
	carry_y = res.y
	return true

# ───────────────────────────── snapshot ─────────────────────────────


## Presentation direction of a crusher's piston, or NAN for a one-cell crusher with no `dir`.
static func crusher_dir(d: CrusherDef) -> float:
	if d.dir != &"":
		return Dir4.angle(d.dir)
	if d.cells.size() < 2:
		return NAN
	var dc: int = d.cells[1].x - d.cells[0].x
	var dr: int = d.cells[1].y - d.cells[0].y
	if dc == 0 and dr == 0:
		return NAN
	return atan2(float(dr), float(dc))


## Every trap's snapshot at instant `sub`, in entity order (appended after the classic mechanisms).
func snapshot(sub: int) -> Array[MechSnap]:
	var out: Array[MechSnap] = []
	out.resize(_order.size())
	for i: int in _order.size():
		var t: TrapState = _order[i]
		var m := MechSnap.new()
		m.id = t.id
		m.kind = t.kind
		match t.kind:
			EntityKind.SPIKES:
				m.on = t.on
				m.with_t(1.0 if t.on else 0.0).with_warn(t.tele_warn)
			EntityKind.CRUSHER:
				m.on = t.phase != PHASE_OPEN
				var ext: float = 0.0
				if t.phase == PHASE_EXTENDED:
					ext = 1.0
				elif t.phase == PHASE_RETRACTING:
					ext = float(t.k) / TrapTuning.CRUSHER_RETRACT_SUBS
				m.with_t(ext).with_warn(t.tele_warn)
				var cd: float = crusher_dir(t.def as CrusherDef)
				if not is_nan(cd):
					m.with_dir(cd)
			EntityKind.CONVEYOR:
				m.on = t.on
				m.with_dir(_belt_angle(t))
			EntityKind.FLAME:
				m.on = t.on
				m.with_dir(Dir4.angle((t.def as FlameDef).dir)).with_reach(t.reach).with_warn(t.tele_warn)
			EntityKind.DART:
				var ph: float = 0.0 if sub <= t.off else float((sub - 1 - t.off) % t.per) / t.per
				m.on = t.on
				m.with_t(ph).with_dir(Dir4.angle((t.def as DartDef).dir))
				m.with_firing(t.last_fire >= 0 and sub - 1 - t.last_fire < TrapTuning.DART_FLASH_SUBS)
			EntityKind.BUMPER:
				var since: float = float(sub - 1 - t.fired_at) if t.fired_at >= 0 else INF
				m.on = t.pulse
				m.with_t(1.0 - since / TrapTuning.BUMPER_PULSE_SUBS if since < TrapTuning.BUMPER_PULSE_SUBS else 0.0)
				m.with_dir(Dir4.angle((t.def as BumperDef).dir)).with_firing(t.pulse)
			EntityKind.SENSOR:
				m.on = t.on
				m.with_reach(t.reach)
			EntityKind.RELAY:
				var span: int = t.fire_at - t.armed_at
				var prog: float = 0.0
				if t.armed:
					prog = clampf(float(sub - t.armed_at) / span, 0.0, 1.0) if span > 0 else 1.0
				m.on = t.on
				m.with_t(prog).with_warn(1.0 if t.armed else 0.0)
			EntityKind.MAGNET:
				m.on = t.on
		out[i] = m
	return out
