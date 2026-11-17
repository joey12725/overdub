class_name LevelValidator
extends RefCounted
## Authoring-time validation of level data (port of prototype/src/content/validate.ts).
##
## Every rule is a documented rule in types.ts (the doc comments on LevelDef and its family, see
## core/types/level_def.gd) or a consequence of one. The checks run on plain data, never on a running
## simulation, so a broken level is reported before the game ever loads it.
##
## Return convention: validate_level / validate_campaign return human-readable messages. Entries that
## start with `note:` are advisories and do not make a level invalid; every other entry is a problem.
## Use is_problem() to tell them apart.
##
## Two entry points:
##   validate_level(level: LevelDef)   checks the typed model. Every rule that a typed value can break.
##   validate_json(d: Dictionary)      checks prototype JSON. It reports the parse errors of
##                                     LevelDef.from_dict() and the shape rules that the typed model
##                                     cannot carry (an expression with two operators, a fractional
##                                     bars or horizonBars), then runs validate_level on the parsed level.
##
## Typed-model notes: a value that a typed field cannot hold (a non-integer tape count, an unknown
## end-mode string, a non-boolean const) is not representable, so its rule lives in validate_json.
## Entity dispatch uses the class (`is EnemyDef`...) after the kind check. A bare EntityDef whose kind
## is valid has no geometry to check, so only its id is checked.
##
## Pure static functions and inner RefCounted helpers; no Node, no clock, no randomness.

## Characters the map grammar defines (types.ts MapRows). Space is one of them.
const MAP_CHARS := "#. =:,~"
## Tiles a self can stand on. '=' is a low barrier that blocks movement, so it is not walkable; '#'
## and ' ' are never walkable. Doors and breakables sit on these floor tiles, so treating them as
## passable for reachability (types.ts EntityDef doc) falls out of the same test.
const FLOOR_CHARS := ".:,~"
const DEAD_PREFIX := "dead:"
const NOTE_PREFIX := "note:"
## Entity kinds that carry an id (and therefore share the one id namespace).
const ID_KINDS: Array[StringName] = [
	EntityKind.ENEMY,
	EntityKind.DOOR,
	EntityKind.SWITCH,
	EntityKind.PLATE,
	EntityKind.BREAKABLE,
	EntityKind.LASER,
	EntityKind.CORE,
	EntityKind.EXIT,
]
## Kinds whose id is a signal the rest of the level can read (types.ts SwitchDef..ExitDef).
const SIGNAL_KINDS: Array[StringName] = [
	EntityKind.SWITCH,
	EntityKind.PLATE,
	EntityKind.BREAKABLE,
	EntityKind.CORE,
	EntityKind.EXIT,
]
const NO_TILE := Vector2i(-1, -1)
## Index of the first campaign level (data/levels/01-*.json); the sandbox is index 0, off the path.
const FIRST_CAMPAIGN_INDEX := 1
## Trap kinds (docs/TRAPS.md) carry an id and publish it as a signal, like the classic SIGNAL_KINDS
## (EntityKind.TRAPS keeps them out of EntityKind.ALL; see core/types/entity_kind.gd).
const DIR_NAMES := "n, e, s, w"
const SENSOR_DETECTS: Array[StringName] = [&"any", &"selves", &"enemies"]
const RELAY_MODES: Array[StringName] = [&"pulse", &"latch", &"toggle"]
## Trap fields whose driving expression is required (docs/TRAPS.md JSON shapes).
const TRAP_REQUIRED_EXPRS: Dictionary = {
	"spikes": ["upWhen"],
	"crusher": ["extendWhen"],
	"flame": ["onWhen"],
	"bumper": ["fireWhen"],
	"relay": ["trigger"],
	"magnet": ["onWhen"],
}
## Every expression field a trap may carry (raw single-operator check).
const TRAP_EXPR_FIELDS: Array[String] = ["upWhen", "extendWhen", "runWhen", "reverseWhen", "onWhen", "enabledWhen", "fireWhen", "trigger"]


static func _is_id_kind(kind: StringName) -> bool:
	return ID_KINDS.has(kind) or EntityKind.is_trap(kind)


static func _is_signal_kind(kind: StringName) -> bool:
	return SIGNAL_KINDS.has(kind) or EntityKind.is_trap(kind)


## True for an entry that makes a level invalid; false for `note:` advisories.
static func is_problem(message: String) -> bool:
	return not message.begins_with(NOTE_PREFIX)


## Validates the typed model. Returns every problem and advisory, in the prototype's check order.
static func validate_level(level: LevelDef) -> PackedStringArray:
	if level == null:
		return PackedStringArray(["level is missing"])
	var ctx := Ctx.new()
	_check_identity(level, ctx)
	_check_time(level, ctx)
	_check_tapes(level, ctx)
	var ok_map := _check_map(level, ctx)
	var start := _check_start(level, ctx, ok_map)
	_check_enclosure(ctx, start)
	_check_entities(level, ctx)
	for pending: Pending in ctx.expressions:
		_check_expression(pending.expr, pending.where, ctx)
	_check_objective(level, ctx)
	_check_reachability(ctx, start)
	_check_music(level, ctx)
	_check_briefing_loot_hints(level, ctx)
	return ctx.out


## Validates prototype JSON (the shape of LevelDef.to_dict()). See the header for what it adds to
## validate_level. `d` is a parsed level object.
static func validate_json(d: Dictionary) -> PackedStringArray:
	var parse_errors: Array[String] = []
	var level := LevelDef.from_dict(d, parse_errors)
	var raw := Report.new()
	_check_raw_integers(d, raw)
	_check_raw_expressions(d, raw)
	var out := PackedStringArray()
	for message: String in parse_errors:
		out.append(message)
	out.append_array(raw.items)
	out.append_array(validate_level(level))
	return out


## Validates an ordered campaign: unique ids, index equal to campaign position + 1 (levels are
## numbered 1..N like their file names; 0 is the sandbox), and every level's problems prefixed with
## its id.
static func validate_campaign(levels: Array[LevelDef]) -> PackedStringArray:
	if levels.is_empty():
		return PackedStringArray(["campaign has no levels"])
	var out := PackedStringArray()
	var seen: Dictionary[String, int] = {}
	for position: int in range(levels.size()):
		var level: LevelDef = levels[position]
		if level == null:
			out.append("level #%d is missing" % position)
			continue
		var has_id := _non_empty(level.id)
		var label := level.id if has_id else "level #%d" % position
		if has_id:
			if seen.has(level.id):
				out.append('duplicate level id "%s" at campaign positions %d and %d' % [level.id, seen[level.id], position])
			else:
				seen[level.id] = position
		# Campaign levels are numbered from 1 (the file prefix, data/levels/README.md); index 0 is the
		# off-path sandbox.
		if level.index != position + FIRST_CAMPAIGN_INDEX:
			out.append("%s: index is %d, expected %d (campaign order is index %d..%d)" % [label, level.index, position + FIRST_CAMPAIGN_INDEX, FIRST_CAMPAIGN_INDEX, levels.size() - 1 + FIRST_CAMPAIGN_INDEX])
		for message: String in validate_level(level):
			if message.begins_with(NOTE_PREFIX):
				out.append("note: %s: %s" % [label, message.substr(NOTE_PREFIX.length()).strip_edges(true, false)])
			else:
				out.append("%s: %s" % [label, message])
	return out


# ───────────────────────────── inner helpers ─────────────────────────────

## Collects the messages of one validation run.
class Report:
	extends RefCounted
	var items := PackedStringArray()

	func add(message: String) -> void:
		items.append(message)


## Walked map grid (types.ts MapRows).
class Geo:
	extends RefCounted
	var rows: int = 0
	var cols: int = 0
	var grid: Array[String] = []


## A tile-bearing entity whose tiles must be reachable from the start.
class ReachTarget:
	extends RefCounted
	var label: String = ""
	var cells: Array[Vector2i] = []


## A signal expression deferred until every producer is known.
class Pending:
	extends RefCounted
	var expr: SignalExpr = null
	var where: String = ""


## Per-run state for validate_level.
class Ctx:
	extends RefCounted
	var out := PackedStringArray()
	var geo: Geo = null
	var start: Vector2i = Vector2i(-1, -1)
	var occupied: Dictionary[String, String] = {}
	var reach_targets: Array[ReachTarget] = []
	var expressions: Array[Pending] = []
	var enemy_ids: Dictionary[String, bool] = {}
	var signal_ids: Dictionary[String, bool] = {}
	var id_kinds: Dictionary[String, String] = {}
	var exit_ids: Dictionary[String, bool] = {}
	var core_ids: Dictionary[String, bool] = {}
	var boss_count: int = 0
	var enemy_count: int = 0
	var core_count: int = 0
	var exit_count: int = 0
	## Trap bookkeeping: crusher cells as [label, Vector2i] in entity order; belt tile -> label.
	var crusher_cells: Array = []
	var belt_cells: Dictionary[String, String] = {}
	## Local ticks per master beat (NAN when bpm is unusable); trap beat grids must land on ticks.
	var ticks_per_beat: float = NAN
	var bpm: float = NAN

	func problem(message: String) -> void:
		out.append(message)


# ───────────────────────────── identity, time, tapes ─────────────────────────────

static func _check_identity(level: LevelDef, ctx: Ctx) -> void:
	if not _non_empty(level.id):
		ctx.problem("id must be a non-empty string")
	if not _non_empty(level.name):
		ctx.problem("name must be a non-empty string")
	if not _non_empty(level.tagline):
		ctx.problem("tagline must be a non-empty string")
	if not LevelTheme.has(level.theme):
		ctx.problem('theme "%s" is not one of %s' % [String(level.theme), _join(LevelTheme.ALL)])
	if level.index < 0:
		ctx.problem("index must be a non-negative integer (got %d)" % level.index)


static func _check_time(level: LevelDef, ctx: Ctx) -> void:
	# ARCHITECTURE "One clock", types.ts LevelDef.bpm / bars / horizonBars.
	if not is_finite(level.bpm) or level.bpm <= 0.0:
		ctx.problem("bpm must be a positive number (got %s)" % _num(level.bpm))
	else:
		var beat_ticks := 3600.0 / level.bpm
		if beat_ticks != floor(beat_ticks):
			ctx.problem("3600 / bpm must be an integer so a beat is a whole number of local ticks (bpm %s gives %s)" % [_num(level.bpm), _num(beat_ticks)])
	var bars_ok := level.bars > 0
	if not bars_ok:
		ctx.problem("bars must be a positive integer (got %d)" % level.bars)
	var horizon_ok := level.horizon_bars > 0
	if not horizon_ok:
		ctx.problem("horizonBars must be a positive integer (got %d)" % level.horizon_bars)
	if not (bars_ok and horizon_ok):
		return
	var valid_speeds: Array[float] = []
	for speed: float in level.speeds:
		if OD.is_speed(speed):
			valid_speeds.append(speed)
	if valid_speeds.is_empty():
		return
	var fastest: float = valid_speeds[0]
	var slowest: float = valid_speeds[0]
	for speed: float in valid_speeds:
		fastest = maxf(fastest, speed)
		slowest = minf(slowest, speed)
	# A fastest-speed pass occupies bars / speed master bars; a horizon shorter than that cannot
	# contain even one full pass of a tape the player can select.
	var bars := float(level.bars)
	var horizon := float(level.horizon_bars)
	if horizon < bars / fastest:
		ctx.problem("horizonBars %d is shorter than one pass of the fastest speed (%d / %s = %s bars)" % [level.horizon_bars, level.bars, _num(fastest), _num(bars / fastest)])
	if horizon < bars / slowest:
		ctx.problem("%s horizonBars %d is shorter than one pass of the slowest offered speed (%d / %s = %s bars); the horizon will cut that tape off" % [NOTE_PREFIX, level.horizon_bars, level.bars, _num(slowest), _num(bars / slowest)])


static func _check_tapes(level: LevelDef, ctx: Ctx) -> void:
	# PLAY-05, TIME-04, types.ts TapeSpeed.
	if level.max_tapes < 1 or level.max_tapes > OD.TAPE_COUNT:
		ctx.problem("maxTapes must be an integer 1..%d (got %d)" % [OD.TAPE_COUNT, level.max_tapes])
	var seen_speeds: Dictionary[String, bool] = {}
	for speed: float in level.speeds:
		if not OD.is_speed(speed):
			ctx.problem("speeds entry %s must be a power of two from ALL_SPEEDS" % _num(speed))
		var key := str(speed)
		if seen_speeds.has(key):
			ctx.problem("speeds lists %s more than once" % _num(speed))
		seen_speeds[key] = true
	if level.speeds.is_empty():
		ctx.problem("speeds must not be empty")
	var seen_modes: Dictionary[int, bool] = {}
	for mode: int in level.end_modes:
		var valid := mode >= 0 and mode < OD.END_MODE_NAMES.size()
		if not valid:
			ctx.problem("endModes entry %d must be one of %s" % [mode, _join(OD.END_MODE_NAMES)])
		if seen_modes.has(mode):
			var shown := '"%s"' % OD.end_mode_name(mode) if valid else str(mode)
			ctx.problem("endModes lists %s more than once" % shown)
		seen_modes[mode] = true
	if level.end_modes.is_empty():
		ctx.problem("endModes must not be empty")


# ───────────────────────────── map and start ─────────────────────────────

## Validates the map's shape and sets ctx.geo when it is usable. Returns true when the map is usable.
static func _check_map(level: LevelDef, ctx: Ctx) -> bool:
	var rows: Array[String] = level.map
	if rows.is_empty():
		ctx.problem("map must be a non-empty array of rows")
		return false
	var width := rows[0].length()
	if width == 0:
		ctx.problem("map rows must not be empty")
		return false
	var rectangular := true
	for r: int in range(rows.size()):
		if rows[r].length() != width:
			ctx.problem("map row %d has length %d, expected %d (map must be rectangular)" % [r, rows[r].length(), width])
			rectangular = false
	var bad := PackedStringArray()
	for row: String in rows:
		for c: int in range(row.length()):
			var ch := row.substr(c, 1)
			if MAP_CHARS.find(ch) < 0 and not bad.has(ch):
				bad.append(ch)
	if not bad.is_empty():
		var quoted := PackedStringArray()
		for ch: String in bad:
			quoted.append('"%s"' % ch)
		var allowed := PackedStringArray()
		for i: int in range(MAP_CHARS.length()):
			allowed.append('"%s"' % MAP_CHARS.substr(i, 1))
		ctx.problem("map uses undocumented characters %s; allowed: %s" % [", ".join(quoted), " ".join(allowed)])
	if not rectangular or not bad.is_empty():
		return false
	var geo := Geo.new()
	geo.rows = rows.size()
	geo.cols = width
	geo.grid = rows
	ctx.geo = geo
	return true


## Validates the start position and facing. Returns the start tile, or NO_TILE when there is none.
static func _check_start(level: LevelDef, ctx: Ctx, ok_map: bool) -> Vector2i:
	if not is_finite(level.start_facing):
		ctx.problem("startFacing must be a finite number when present")
	var s := level.start
	if not (is_finite(s.x) and is_finite(s.y)):
		ctx.problem("start must be a Vec2 of finite numbers")
		return NO_TILE
	if not ok_map or ctx.geo == null:
		return NO_TILE
	if not _in_map(ctx.geo, s.x, s.y):
		ctx.problem("start (%s, %s) is outside the map" % [_num(s.x), _num(s.y)])
		return NO_TILE
	var c := floori(s.x)
	var r := floori(s.y)
	if not _is_walkable(ctx.geo, c, r):
		ctx.problem("start tile (%d,%d) is not a walkable floor tile (found '%s')" % [c, r, _char_at(ctx.geo, c, r)])
		return NO_TILE
	ctx.start = Vector2i(c, r)
	return ctx.start


## Walkable border tiles the start can reach would let the playfield leak past the map edge.
## Border tiles the start cannot reach are sealed off by walls or void, which "bounded by void" permits.
static func _check_enclosure(ctx: Ctx, start: Vector2i) -> void:
	if ctx.geo == null or start == NO_TILE:
		return
	var geo := ctx.geo
	var reached := _flood(geo, start)
	var leaks := 0
	var first_leak := NO_TILE
	for r: int in range(geo.rows):
		for c: int in range(geo.cols):
			if reached[r * geo.cols + c] == 0:
				continue
			if c == 0 or r == 0 or c == geo.cols - 1 or r == geo.rows - 1:
				leaks += 1
				if first_leak == NO_TILE:
					first_leak = Vector2i(c, r)
	if leaks > 0:
		ctx.problem("walkable area leaks past the map edge at (%d,%d); %d reachable border tile(s) must be walls or void" % [first_leak.x, first_leak.y, leaks])


# ───────────────────────────── entities ─────────────────────────────

static func _check_entities(level: LevelDef, ctx: Ctx) -> void:
	var entities: Array[EntityDef] = level.entities
	# Pass 1: ids, duplicate detection and the producer tables every later check reads.
	for i: int in range(entities.size()):
		var e: EntityDef = entities[i]
		if e == null or not EntityKind.has(e.kind):
			ctx.problem('entity #%d has unknown kind "%s"' % [i, "" if e == null else String(e.kind)])
			continue
		if e.kind == EntityKind.ENEMY:
			ctx.enemy_count += 1
			if e is EnemyDef and (e as EnemyDef).type == EnemyType.BOSS:
				ctx.boss_count += 1
		if e.kind == EntityKind.CORE:
			ctx.core_count += 1
		if e.kind == EntityKind.EXIT:
			ctx.exit_count += 1
		if not _is_id_kind(e.kind):
			continue
		var label := _describe(e, i)
		if not _non_empty(e.id):
			ctx.problem("%s: id must be a non-empty string" % label)
		elif ctx.id_kinds.has(e.id):
			ctx.problem('duplicate id "%s" (%s and %s); ids must be unique across signals, enemies, doors and lasers' % [e.id, ctx.id_kinds[e.id], String(e.kind)])
		else:
			ctx.id_kinds[e.id] = String(e.kind)
			if e.kind == EntityKind.ENEMY:
				ctx.enemy_ids[e.id] = true
			if _is_signal_kind(e.kind):
				ctx.signal_ids[e.id] = true
			# Secondary trap signals (docs/TRAPS.md): a belt's reversed flag, a relay's armed flag.
			if e.kind == EntityKind.CONVEYOR:
				ctx.signal_ids[e.id + ".rev"] = true
			if e.kind == EntityKind.RELAY:
				ctx.signal_ids[e.id + ".armed"] = true
	# Trap beat grids are checked against the level's tick grid.
	ctx.bpm = level.bpm
	if is_finite(level.bpm) and level.bpm > 0.0:
		ctx.ticks_per_beat = 3600.0 / level.bpm
	# Pass 2: per-entity geometry, field rules, and the work lists the later passes consume.
	for i: int in range(entities.size()):
		var e: EntityDef = entities[i]
		if e == null or not EntityKind.has(e.kind):
			continue
		var label := _describe(e, i)
		if e is EnemyDef:
			_check_enemy(e as EnemyDef, label, ctx)
		elif e is DoorDef:
			_check_door(e as DoorDef, label, ctx)
		elif e is SwitchDef:
			_check_switch(e as SwitchDef, label, ctx)
		elif e is PlateDef:
			_check_plate(e as PlateDef, label, ctx)
		elif e is BreakableDef:
			_check_breakable(e as BreakableDef, label, ctx)
		elif e is LaserDef:
			_check_laser(e as LaserDef, label, ctx)
		elif e is CoreDef:
			_check_core(e as CoreDef, label, ctx)
		elif e is ExitDef:
			_check_exit(e as ExitDef, label, ctx)
		elif e is DecorDef:
			_check_decor(e as DecorDef, label, ctx)
		elif e is TrapDef:
			_check_trap(e as TrapDef, label, ctx)
	# A crusher turns its tiles solid, so no door, switch, breakable or core may share them (an enemy
	# may stand on one: that is how a crusher is used).
	var crusher_seen: Dictionary[String, String] = {}
	for entry: Array in ctx.crusher_cells:
		var clabel: String = entry[0]
		var cell: Vector2i = entry[1]
		var key := "%d,%d" % [cell.x, cell.y]
		if ctx.occupied.has(key) and not ctx.occupied[key].begins_with("enemy "):
			ctx.problem("%s and %s share tile (%d,%d); solid entities need their own tile" % [clabel, ctx.occupied[key], cell.x, cell.y])
		if crusher_seen.has(key) and crusher_seen[key] != clabel:
			ctx.problem("%s and %s share tile (%d,%d); a tile belongs to one crusher" % [clabel, crusher_seen[key], cell.x, cell.y])
		else:
			crusher_seen[key] = clabel


# ───────────────────────────── traps (docs/TRAPS.md) ─────────────────────────────

static func _check_trap(e: TrapDef, label: String, ctx: Ctx) -> void:
	if e is SpikesDef:
		var s := e as SpikesDef
		_trap_cells(label, s.cells, ctx)
		_require_trap_expr(label, "upWhen", s.up_when, ctx)
		_optional_positive(label, "damage", s.damage, true, ctx)
	elif e is CrusherDef:
		var k := e as CrusherDef
		var cells := _trap_cells(label, k.cells, ctx)
		if cells.size() == k.cells.size() and cells.size() > 1:
			var dc := cells[1].x - cells[0].x
			var dr := cells[1].y - cells[0].y
			var straight := absi(dc) + absi(dr) == 1
			if straight:
				for i: int in range(cells.size()):
					if cells[i].x != cells[0].x + dc * i or cells[i].y != cells[0].y + dr * i:
						straight = false
						break
			if not straight:
				ctx.problem("%s: cells must form one straight, contiguous line ordered from the housing outward" % label)
		for cell: Vector2i in cells:
			ctx.crusher_cells.append([label, cell])
		_require_trap_expr(label, "extendWhen", k.extend_when, ctx)
		if k.dir != &"":
			_require_dir(label, k.dir, ctx)
		_optional_positive(label, "damage", k.damage, true, ctx)
	elif e is ConveyorDef:
		var b := e as ConveyorDef
		for cell: Vector2i in _trap_cells(label, b.cells, ctx):
			var key := "%d,%d" % [cell.x, cell.y]
			if ctx.belt_cells.has(key):
				ctx.problem("%s and %s share tile (%d,%d); a tile belongs to one belt" % [label, ctx.belt_cells[key], cell.x, cell.y])
			else:
				ctx.belt_cells[key] = label
		_require_dir(label, b.dir, ctx)
		_optional_positive(label, "speed", b.speed, false, ctx)
		_optional_trap_expr(label, "runWhen", b.run_when, ctx)
		_optional_trap_expr(label, "reverseWhen", b.reverse_when, ctx)
	elif e is FlameDef:
		var f := e as FlameDef
		_emitter_tile(label, f.c, f.r, f.dir, ctx)
		if not (is_finite(f.range) and f.range > 0.0 and f.range == floor(f.range)):
			ctx.problem("%s: range must be a positive integer number of tiles" % label)
		_require_trap_expr(label, "onWhen", f.on_when, ctx)
		_optional_positive(label, "damage", f.damage, true, ctx)
	elif e is DartDef:
		var d := e as DartDef
		_emitter_tile(label, d.c, d.r, d.dir, ctx)
		if TrapDef.has_num(d.every) and not (is_finite(d.every) and d.every > 0.0):
			ctx.problem("%s: every must be a positive number of beats" % label)
		elif TrapDef.has_num(d.every) and not _on_tick_grid(d.every, ctx):
			ctx.problem("%s: every %s beats is not a whole number of local ticks at %s bpm" % [label, _num(d.every), _num(ctx.bpm)])
		if TrapDef.has_num(d.offset) and not (is_finite(d.offset) and d.offset >= 0.0):
			ctx.problem("%s: offset must be a non-negative number of beats" % label)
		elif TrapDef.has_num(d.offset) and not _on_tick_grid(d.offset, ctx):
			ctx.problem("%s: offset %s beats is not a whole number of local ticks at %s bpm" % [label, _num(d.offset), _num(ctx.bpm)])
		_optional_trap_expr(label, "enabledWhen", d.enabled_when, ctx)
		_optional_positive(label, "speed", d.speed, false, ctx)
	elif e is BumperDef:
		var p := e as BumperDef
		_cell_tile(label, p.c, p.r, ctx)
		_require_dir(label, p.dir, ctx)
		_optional_positive(label, "power", p.power, false, ctx)
		_require_trap_expr(label, "fireWhen", p.fire_when, ctx)
	elif e is SensorDef:
		var s := e as SensorDef
		if not (is_finite(s.from_x) and is_finite(s.from_y) and is_finite(s.to_x) and is_finite(s.to_y)):
			ctx.problem("%s: from and to must be Vec2 of finite numbers" % label)
		else:
			if s.from_x == s.to_x and s.from_y == s.to_y:
				ctx.problem("%s: from and to must differ" % label)
			for end: Array in [["from", s.from_x, s.from_y], ["to", s.to_x, s.to_y]]:
				var ename := "%s.%s" % [label, end[0]]
				var x: float = end[1]
				var y: float = end[2]
				_inside_only(ename, x, y, ctx)
				if ctx.geo != null and _in_map(ctx.geo, x, y) and _char_at(ctx.geo, floori(x), floori(y)) == "#":
					ctx.problem("%s: (%s, %s) is inside a wall tile; put both ends of the beam over open tiles" % [ename, _num(x), _num(y)])
		if s.detects != &"" and not SENSOR_DETECTS.has(s.detects):
			ctx.problem("%s: detects must be any, selves or enemies" % label)
	elif e is RelayDef:
		var r := e as RelayDef
		_require_trap_expr(label, "trigger", r.trigger, ctx)
		if r.mode != &"" and not RELAY_MODES.has(r.mode):
			ctx.problem("%s: mode must be pulse, latch or toggle" % label)
		for field: Array in [["quantize", r.quantize], ["delay", r.delay], ["hold", r.hold]]:
			var fname: String = field[0]
			var v: float = field[1]
			if not TrapDef.has_num(v):
				continue
			var is_hold := fname == "hold"
			if not is_finite(v) or v < 0.0 or (is_hold and v <= 0.0):
				ctx.problem("%s: %s must be a %s number of beats" % [label, fname, "positive" if is_hold else "non-negative"])
			elif not _on_tick_grid(v, ctx):
				ctx.problem("%s: %s %s beats is not a whole number of local ticks at %s bpm" % [label, fname, _num(v), _num(ctx.bpm)])
		if is_nan(r.x) != is_nan(r.y):
			ctx.problem("%s: give both x and y, or neither" % label)
		elif not is_nan(r.x):
			_inside_only(label, r.x, r.y, ctx)
	elif e is MagnetDef:
		var m := e as MagnetDef
		_inside_only(label, m.x, m.y, ctx)
		if not (is_finite(m.radius) and m.radius > 0.0):
			ctx.problem("%s: radius must be a positive number" % label)
		_optional_positive(label, "pull", m.pull, false, ctx)
		_require_trap_expr(label, "onWhen", m.on_when, ctx)


## A non-empty list of distinct floor cells. Returns the valid ones in order.
static func _trap_cells(label: String, cells: Array[Vector2i], ctx: Ctx) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if cells.is_empty():
		ctx.problem("%s: needs at least one cell" % label)
		return out
	var seen: Dictionary[String, bool] = {}
	for cell: Vector2i in cells:
		var tile := _cell_tile(label, cell.x, cell.y, ctx)
		if tile == NO_TILE:
			continue
		var key := "%d,%d" % [tile.x, tile.y]
		if seen.has(key):
			ctx.problem("%s: cell (%d,%d) is listed twice" % [label, tile.x, tile.y])
			continue
		seen[key] = true
		out.append(tile)
	return out


static func _require_trap_expr(label: String, field: String, expr: SignalExpr, ctx: Ctx) -> void:
	if expr == null:
		ctx.problem("%s: %s is required" % [label, field])
	else:
		_defer_expression(expr, "%s.%s" % [label, field], ctx)


static func _optional_trap_expr(label: String, field: String, expr: SignalExpr, ctx: Ctx) -> void:
	if expr != null:
		_defer_expression(expr, "%s.%s" % [label, field], ctx)


static func _require_dir(label: String, dir: StringName, ctx: Ctx) -> bool:
	if Dir4.has(dir):
		return true
	ctx.problem('%s: dir must be one of %s (got %s)' % [label, DIR_NAMES, "undefined" if dir == &"" else '"%s"' % dir])
	return false


static func _optional_positive(label: String, field: String, v: float, integer: bool, ctx: Ctx) -> void:
	if not TrapDef.has_num(v):
		return
	if not is_finite(v) or v <= 0.0 or (integer and v != floor(v)):
		ctx.problem("%s: %s must be a positive %s when present" % [label, field, "integer" if integer else "number"])


## Emitter tile (flame nozzle, dart launcher): any tile in the map whose front tile is not a wall.
static func _emitter_tile(label: String, c: int, r: int, dir: StringName, ctx: Ctx) -> void:
	var dir_ok := _require_dir(label, dir, ctx)
	if ctx.geo == null:
		return
	if c < 0 or r < 0 or c >= ctx.geo.cols or r >= ctx.geo.rows:
		ctx.problem("%s: tile (%d,%d) is outside the map" % [label, c, r])
		return
	if not dir_ok:
		return
	var fc := c + Dir4.dx(dir)
	var fr := r + Dir4.dy(dir)
	if fc < 0 or fr < 0 or fc >= ctx.geo.cols or fr >= ctx.geo.rows or _char_at(ctx.geo, fc, fr) == "#":
		ctx.problem("%s: the tile in front of it (%d,%d) is a wall or outside the map, so it can never reach anything" % [label, fc, fr])


## True when `beats` is a whole number of local ticks at the level's tempo (always true when the
## tempo itself is off-grid, which _check_time reports).
static func _on_tick_grid(beats: float, ctx: Ctx) -> bool:
	var tpb := ctx.ticks_per_beat
	if not is_finite(tpb) or tpb != floor(tpb):
		return true
	var t := roundf(beats * tpb * 1e6) / 1e6
	return t == floor(t)


static func _check_enemy(e: EnemyDef, label: String, ctx: Ctx) -> void:
	if not EnemyType.has(e.type):
		ctx.problem('%s: unknown enemy type "%s"' % [label, String(e.type)])
	if not is_finite(e.facing):
		ctx.problem("%s: facing must be a finite number" % label)
	if e.has_hp and e.hp <= 0:
		ctx.problem("%s: hp must be a positive integer" % label)
	if e.has_beat and (e.beat_every <= 0 or not is_finite(e.beat_offset)):
		ctx.problem("%s: beat must be { every: positive integer, offset: number }" % label)
	if e.has_arc and not is_finite(e.arc):
		ctx.problem("%s: arc must be a finite number" % label)
	var tile := _point_tile(label, e.x, e.y, ctx)
	if tile != NO_TILE:
		_occupy(label, tile, ctx)
		_add_reach(label, [tile], ctx)
	if e.wake_when != null:
		_defer_expression(e.wake_when, "%s.wakeWhen" % label, ctx)


static func _check_door(e: DoorDef, label: String, ctx: Ctx) -> void:
	if e.cells.is_empty():
		ctx.problem("%s: a door needs at least one cell" % label)
	else:
		var seen: Dictionary[String, bool] = {}
		for cell: Vector2i in e.cells:
			var tile := _cell_tile(label, cell.x, cell.y, ctx)
			if tile == NO_TILE:
				continue
			var key := "%d,%d" % [tile.x, tile.y]
			if seen.has(key):
				ctx.problem("%s: cell (%d,%d) is listed twice" % [label, tile.x, tile.y])
				continue
			seen[key] = true
			_occupy(label, tile, ctx)
	if e.open_when == null:
		ctx.problem("%s: openWhen is required" % label)
	else:
		_defer_expression(e.open_when, "%s.openWhen" % label, ctx)


static func _check_switch(e: SwitchDef, label: String, ctx: Ctx) -> void:
	var tile := _point_tile(label, e.x, e.y, ctx)
	if tile != NO_TILE:
		_occupy(label, tile, ctx)
		_add_reach(label, [tile], ctx)


static func _check_plate(e: PlateDef, label: String, ctx: Ctx) -> void:
	var tile := _cell_tile(label, e.c, e.r, ctx)
	if tile != NO_TILE:
		_add_reach(label, [tile], ctx)


static func _check_breakable(e: BreakableDef, label: String, ctx: Ctx) -> void:
	if not (is_finite(e.threshold) and e.threshold > 0.0):
		ctx.problem("%s: threshold must be a positive number" % label)
	var tile := _cell_tile(label, e.c, e.r, ctx)
	if tile != NO_TILE:
		_occupy(label, tile, ctx)


static func _check_laser(e: LaserDef, label: String, ctx: Ctx) -> void:
	if not (is_finite(e.from.x) and is_finite(e.from.y) and is_finite(e.to.x) and is_finite(e.to.y)):
		ctx.problem("%s: from and to must be Vec2 of finite numbers" % label)
	else:
		_inside_only("%s.from" % label, e.from.x, e.from.y, ctx)
		_inside_only("%s.to" % label, e.to.x, e.to.y, ctx)
	if e.on_when == null:
		ctx.problem("%s: onWhen is required" % label)
	else:
		_defer_expression(e.on_when, "%s.onWhen" % label, ctx)


static func _check_core(e: CoreDef, label: String, ctx: Ctx) -> void:
	if e.has_threshold and not (is_finite(e.threshold) and e.threshold > 0.0):
		ctx.problem("%s: threshold must be a positive number when present" % label)
	var tile := _point_tile(label, e.x, e.y, ctx)
	if tile != NO_TILE:
		_occupy(label, tile, ctx)
		ctx.core_ids[e.id] = true
		_add_reach(label, [tile], ctx)


static func _check_exit(e: ExitDef, label: String, ctx: Ctx) -> void:
	if e.w <= 0 or e.h <= 0:
		ctx.problem("%s: w and h must be positive integers" % label)
		return
	var cells: Array[Vector2i] = []
	for dr: int in range(e.h):
		for dc: int in range(e.w):
			var tile := _cell_tile(label, e.c + dc, e.r + dr, ctx)
			if tile != NO_TILE:
				cells.append(tile)
	ctx.exit_ids[e.id] = true
	if not cells.is_empty():
		_add_reach(label, cells, ctx)


static func _check_decor(e: DecorDef, label: String, ctx: Ctx) -> void:
	if not DecorType.has(e.type):
		ctx.problem('%s: unknown decor type "%s"' % [label, String(e.type)])
	if e.rot < 0 or e.rot > 3:
		ctx.problem("%s: rot must be 0..3" % label)
	_inside_only(label, e.x, e.y, ctx)


## Point entity (enemy, switch, core): position must be in the map and on a floor tile.
## Returns the tile, or NO_TILE after reporting a problem (or when there is no usable map).
static func _point_tile(label: String, x: float, y: float, ctx: Ctx) -> Vector2i:
	if not (is_finite(x) and is_finite(y)):
		ctx.problem("%s: position must be finite numbers" % label)
		return NO_TILE
	if ctx.geo == null:
		return NO_TILE
	if not _in_map(ctx.geo, x, y):
		ctx.problem("%s: position (%s, %s) is outside the map" % [label, _num(x), _num(y)])
		return NO_TILE
	var c := floori(x)
	var r := floori(y)
	if not _is_walkable(ctx.geo, c, r):
		ctx.problem("%s: tile (%d,%d) is '%s', not a floor tile" % [label, c, r, _char_at(ctx.geo, c, r)])
		return NO_TILE
	return Vector2i(c, r)


## Cell entity (plate, breakable, door cell, exit cell): integer tile on a floor tile.
static func _cell_tile(label: String, c: int, r: int, ctx: Ctx) -> Vector2i:
	if ctx.geo == null:
		return NO_TILE
	if c < 0 or r < 0 or c >= ctx.geo.cols or r >= ctx.geo.rows:
		ctx.problem("%s: cell (%d,%d) is outside the map" % [label, c, r])
		return NO_TILE
	if not _is_walkable(ctx.geo, c, r):
		ctx.problem("%s: cell (%d,%d) is '%s', not a floor tile" % [label, c, r, _char_at(ctx.geo, c, r)])
		return NO_TILE
	return Vector2i(c, r)


static func _inside_only(label: String, x: float, y: float, ctx: Ctx) -> void:
	if not (is_finite(x) and is_finite(y)):
		ctx.problem("%s: position must be finite numbers" % label)
		return
	if ctx.geo != null and not _in_map(ctx.geo, x, y):
		ctx.problem("%s: position (%s, %s) is outside the map" % [label, _num(x), _num(y)])


## Records a solid tile; two solid entities on one tile are a problem.
static func _occupy(label: String, tile: Vector2i, ctx: Ctx) -> void:
	var key := "%d,%d" % [tile.x, tile.y]
	if ctx.occupied.has(key):
		ctx.problem("%s and %s share tile (%d,%d); solid entities need their own tile" % [label, ctx.occupied[key], tile.x, tile.y])
	else:
		ctx.occupied[key] = label


static func _add_reach(label: String, cells: Array[Vector2i], ctx: Ctx) -> void:
	var target := ReachTarget.new()
	target.label = label
	target.cells = cells
	ctx.reach_targets.append(target)


static func _defer_expression(expr: SignalExpr, where: String, ctx: Ctx) -> void:
	var pending := Pending.new()
	pending.expr = expr
	pending.where = where
	ctx.expressions.append(pending)


# ───────────────────────────── signal expressions ─────────────────────────────

## Walks a SignalExpr (types.ts SignalExpr). Every `sig` must be produced by a signal-producing entity,
## or be `dead:<enemyId>` for an existing enemy.
static func _check_expression(expr: SignalExpr, where: String, ctx: Ctx) -> void:
	if expr == null:
		ctx.problem("%s: signal expression must be an object" % where)
		return
	match expr.op:
		SignalExpr.Op.SIG:
			if not _non_empty(expr.sig):
				ctx.problem("%s: sig must be a non-empty signal id" % where)
			elif expr.sig.begins_with(DEAD_PREFIX):
				var enemy := expr.sig.substr(DEAD_PREFIX.length())
				if enemy == "":
					ctx.problem('%s: "%s" names no enemy' % [where, expr.sig])
				elif not ctx.enemy_ids.has(enemy):
					ctx.problem('%s: "%s" refers to enemy "%s", which does not exist' % [where, expr.sig, enemy])
			elif not ctx.signal_ids.has(expr.sig):
				ctx.problem('%s: signal "%s" is not produced by any switch, plate, breakable, core or exit' % [where, expr.sig])
		SignalExpr.Op.NOT:
			if expr.args.size() != 1:
				ctx.problem("%s: not needs exactly one expression" % where)
			else:
				_check_expression(expr.args[0], where + ".not", ctx)
		SignalExpr.Op.AND, SignalExpr.Op.OR:
			var op_name := "and" if expr.op == SignalExpr.Op.AND else "or"
			if expr.args.is_empty():
				ctx.problem("%s: %s needs a non-empty array of expressions" % [where, op_name])
			else:
				for i: int in range(expr.args.size()):
					_check_expression(expr.args[i], "%s.%s[%d]" % [where, op_name, i], ctx)
		SignalExpr.Op.XOR:
			if expr.args.size() != 2:
				ctx.problem("%s: xor needs exactly two expressions" % where)
			else:
				_check_expression(expr.args[0], where + ".xor[0]", ctx)
				_check_expression(expr.args[1], where + ".xor[1]", ctx)
		SignalExpr.Op.CONST:
			# The value is a typed bool, so "const must be true or false" is a raw JSON rule (validate_json).
			pass
		SignalExpr.Op.BEAT:
			if not (is_finite(expr.every) and expr.every > 0.0 and is_finite(expr.from) and is_finite(expr.to)):
				ctx.problem("%s: beat must be { every > 0, from, to } with finite numbers" % where)
			elif not (expr.from >= 0.0 and expr.from < expr.to and expr.to <= expr.every):
				ctx.problem("%s: beat window [%s, %s) must satisfy 0 <= from < to <= every (every = %s)" % [where, _num(expr.from), _num(expr.to), _num(expr.every)])
		_:
			ctx.problem('%s: unknown signal operator "%d"' % [where, expr.op])


# ───────────────────────────── objective ─────────────────────────────

static func _check_objective(level: LevelDef, ctx: Ctx) -> void:
	var objective := level.objective
	if objective == null:
		ctx.problem("objective is required")
		return
	if not ObjectiveType.has(objective.type):
		ctx.problem('objective type "%s" is not recognised' % String(objective.type))
	if not _non_empty(objective.text):
		ctx.problem("objective text must be a non-empty string")
	var targets: Array[String] = objective.targets
	var kind := objective.type
	if kind == ObjectiveType.ELIMINATE:
		if not targets.is_empty():
			_require_targets_in(targets, ctx.enemy_ids, "enemy", ctx)
		elif ctx.enemy_count == 0:
			ctx.problem("eliminate objective needs at least one enemy or explicit targets")
	elif kind == ObjectiveType.REACH:
		if ctx.exit_count == 0:
			ctx.problem("reach objective needs at least one exit")
		if not targets.is_empty():
			_require_targets_in(targets, ctx.exit_ids, "exit", ctx)
	elif kind == ObjectiveType.ACTIVATE:
		if not targets.is_empty():
			_require_targets_in(targets, ctx.core_ids, "core", ctx)
		elif ctx.core_count == 0:
			ctx.problem("activate objective needs at least one core")
	elif kind == ObjectiveType.BOSS:
		if ctx.boss_count != 1:
			ctx.problem("boss objective needs exactly one boss enemy (found %d)" % ctx.boss_count)
		if not targets.is_empty():
			_require_targets_in(targets, ctx.enemy_ids, "enemy", ctx)
	elif kind == ObjectiveType.SIGNAL:
		if objective.when_expr == null:
			ctx.problem('signal objective needs a "when" expression')
		if not targets.is_empty():
			_require_targets_in(targets, ctx.id_kinds, "known id", ctx)
	if objective.when_expr != null:
		_check_expression(objective.when_expr, "objective.when", ctx)


static func _require_targets_in(targets: Array[String], known: Dictionary, kind: String, ctx: Ctx) -> void:
	for t: String in targets:
		if not known.has(t):
			ctx.problem('objective target "%s" is not a %s' % [t, kind])


# ───────────────────────────── reachability ─────────────────────────────

## Every tile-bearing entity must be reachable from the start (ARCHITECTURE "everything reachable";
## doors and breakables are floor, so passable).
static func _check_reachability(ctx: Ctx, start: Vector2i) -> void:
	if ctx.geo == null or start == NO_TILE:
		return
	var reached := _flood(ctx.geo, start)
	for target: ReachTarget in ctx.reach_targets:
		var ok := false
		for cell: Vector2i in target.cells:
			if reached[cell.y * ctx.geo.cols + cell.x] == 1:
				ok = true
				break
		if not ok:
			ctx.problem("%s is unreachable from the start" % target.label)


# ───────────────────────────── music, briefing, loot, hints ─────────────────────────────

static func _check_music(level: LevelDef, ctx: Ctx) -> void:
	var music := level.music
	if music == null:
		ctx.problem("music is required")
		return
	if music.root < 0 or music.root > 11:
		ctx.problem("music.root must be an integer 0..11 (got %d)" % music.root)
	if not _non_empty(music.scale):
		ctx.problem("music.scale must be a non-empty string")
	if music.progression.is_empty():
		ctx.problem("music.progression must be a non-empty array of scale degrees")
	else:
		for degree: int in music.progression:
			if degree < 0 or degree > 6:
				ctx.problem("music.progression degree %d must be an integer 0..6" % degree)
	if music.chord_bars < 0:
		ctx.problem("music.chordBars must be a positive integer when present")
	if music.tracks.size() != 4:
		ctx.problem("music.tracks must have exactly four entries (found %d)" % music.tracks.size())
	else:
		for t: int in range(music.tracks.size()):
			_check_track(music.tracks[t], t, ctx)


static func _check_track(track: TrackMusicDef, t: int, ctx: Ctx) -> void:
	var where := "music.tracks[%d]" % t
	if track == null:
		ctx.problem("%s must be an object" % where)
		return
	if not MusicRole.has(track.role):
		ctx.problem('%s.role "%s" is not one of %s' % [where, String(track.role), _join(MusicRole.ALL)])
	if not _non_empty(track.formula):
		ctx.problem("%s.formula must be a non-empty string" % where)
	for name: String in track.params:
		if not is_finite(track.params[name]):
			ctx.problem("%s.params must map names to finite numbers" % where)
			break


static func _check_briefing_loot_hints(level: LevelDef, ctx: Ctx) -> void:
	if level.briefing.is_empty():
		ctx.problem("briefing needs at least one line")
	else:
		for line: String in level.briefing:
			if not _non_empty(line):
				ctx.problem("every briefing line must be a non-empty string")
				break
	for loot_id: String in level.loot:
		if not _non_empty(loot_id):
			ctx.problem("every loot id must be a non-empty string")
			break
	for tape: int in level.hints:
		if tape < 1 or tape > OD.TAPE_COUNT:
			ctx.problem('hint key "%d" must be a tape number 1..%d' % [tape, OD.TAPE_COUNT])
		if not _non_empty(level.hints[tape]):
			ctx.problem("hint for tape %d must be a non-empty string" % tape)


# ───────────────────────────── raw JSON rules ─────────────────────────────

## Integer fields that the typed model would silently round.
static func _check_raw_integers(d: Dictionary, out: Report) -> void:
	for key: String in ["bars", "horizonBars"]:
		if d.has(key) and not _is_whole(d[key]):
			out.add("%s must be a positive integer (got %s)" % [key, str(d[key])])
	# music.chordBars: LevelMusicDef reads an absent value as 0, so a present 0 (or a fraction) is only
	# visible in the raw JSON. A negative value is caught by validate_level.
	var music: Variant = d.get("music")
	if music is Dictionary and (music as Dictionary).has("chordBars"):
		var chord: Variant = (music as Dictionary)["chordBars"]
		if not _is_whole(chord) or float(chord) == 0.0:
			out.add("music.chordBars must be a positive integer when present")


## Signal expressions in raw JSON: exactly one operator per node. LevelDef.from_dict reads the
## first key of a multi-key node silently, so the rule is checked here on the raw tree.
static func _check_raw_expressions(d: Dictionary, out: Report) -> void:
	var entities: Variant = d.get("entities", [])
	if entities is Array:
		var list: Array = entities
		for e: Variant in list:
			if not (e is Dictionary):
				continue
			var ed: Dictionary = e
			var where := "%s %s" % [str(ed.get("kind", "")), str(ed.get("id", ""))]
			match str(ed.get("kind", "")):
				"enemy":
					if ed.has("wakeWhen"):
						_check_raw_expression(ed["wakeWhen"], where + ".wakeWhen", out)
				"door":
					if ed.has("openWhen"):
						_check_raw_expression(ed["openWhen"], where + ".openWhen", out)
				"laser":
					if ed.has("onWhen"):
						_check_raw_expression(ed["onWhen"], where + ".onWhen", out)
				_:
					if EntityKind.is_trap(StringName(str(ed.get("kind", "")))):
						_check_raw_trap(ed, out)
	var objective: Variant = d.get("objective")
	if objective is Dictionary and (objective as Dictionary).has("when"):
		_check_raw_expression((objective as Dictionary)["when"], "objective.when", out)


## Trap rules only the raw JSON can show (docs/TRAPS.md): a missing driving expression (the typed
## model stands a constant false in for it), a non-boolean sensor latch, and multi-operator nodes.
static func _check_raw_trap(ed: Dictionary, out: Report) -> void:
	var kind := str(ed.get("kind", ""))
	var id: Variant = ed.get("id")
	var label := '%s "%s"' % [kind, id] if id is String and (id as String) != "" else kind
	for field: String in TRAP_REQUIRED_EXPRS.get(kind, []):
		if not ed.has(field) or ed[field] == null:
			out.add("%s: %s is required" % [label, field])
	if kind == "sensor" and ed.has("latch") and not (ed["latch"] is bool):
		out.add("%s: latch must be a boolean" % label)
	for field: String in TRAP_EXPR_FIELDS:
		if ed.has(field) and ed[field] != null:
			_check_raw_expression(ed[field], "%s.%s" % [label, field], out)


static func _check_raw_expression(v: Variant, where: String, out: Report) -> void:
	if not (v is Dictionary):
		return
	var node: Dictionary = v
	var keys: Array = node.keys()
	if keys.size() != 1:
		var names := PackedStringArray()
		for k: Variant in keys:
			names.append(str(k))
		var has := "none" if keys.is_empty() else ", ".join(names)
		out.add("%s: signal expression must have exactly one operator (has %s)" % [where, has])
		return
	var op := str(keys[0])
	var arg: Variant = node[keys[0]]
	if op == "not":
		_check_raw_expression(arg, where + ".not", out)
	elif op == "and" or op == "or":
		if arg is Array:
			var list: Array = arg
			for i: int in range(list.size()):
				_check_raw_expression(list[i], "%s.%s[%d]" % [where, op, i], out)
	elif op == "xor":
		if arg is Array:
			var pair: Array = arg
			for i: int in range(pair.size()):
				_check_raw_expression(pair[i], "%s.xor[%d]" % [where, i], out)


static func _is_whole(v: Variant) -> bool:
	if v is int:
		return true
	if v is float:
		var f: float = v
		return is_finite(f) and f == floor(f)
	return false


# ───────────────────────────── shared helpers ─────────────────────────────

static func _non_empty(s: String) -> bool:
	return s.strip_edges() != ""


static func _in_map(geo: Geo, x: float, y: float) -> bool:
	return x >= 0.0 and y >= 0.0 and x < float(geo.cols) and y < float(geo.rows)


static func _char_at(geo: Geo, c: int, r: int) -> String:
	return geo.grid[r].substr(c, 1)


static func _is_walkable(geo: Geo, c: int, r: int) -> bool:
	if c < 0 or r < 0 or c >= geo.cols or r >= geo.rows:
		return false
	return FLOOR_CHARS.find(_char_at(geo, c, r)) >= 0


## 4-connected flood over walkable tiles from `start`. Returns 1 for each reached tile, indexed r * cols + c.
static func _flood(geo: Geo, start: Vector2i) -> PackedByteArray:
	var reached := PackedByteArray()
	reached.resize(geo.cols * geo.rows)
	reached.fill(0)
	var stack: Array[Vector2i] = [start]
	reached[start.y * geo.cols + start.x] = 1
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		var neighbours: Array[Vector2i] = [
			Vector2i(cur.x + 1, cur.y),
			Vector2i(cur.x - 1, cur.y),
			Vector2i(cur.x, cur.y + 1),
			Vector2i(cur.x, cur.y - 1),
		]
		for n: Vector2i in neighbours:
			if not _is_walkable(geo, n.x, n.y):
				continue
			var idx := n.y * geo.cols + n.x
			if reached[idx] != 0:
				continue
			reached[idx] = 1
			stack.append(n)
	return reached


static func _describe(e: EntityDef, index: int) -> String:
	if e.id != "":
		return '%s "%s"' % [String(e.kind), e.id]
	return "%s #%d" % [String(e.kind), index]


## Formats a number the way JavaScript prints it: whole values without a fraction.
static func _num(v: float) -> String:
	if is_finite(v) and v == floor(v):
		return "%d" % int(v)
	return "%s" % str(v)


static func _join(names: Array) -> String:
	var parts := PackedStringArray()
	for n: Variant in names:
		parts.append(String(n))
	return ", ".join(parts)
