class_name WorldMechAccent
extends RefCounted
## Mechanism accent colours (port of prototype render/mechs/accent.ts). A door and the switch /
## plate that opens it share an accent so the wiring reads at a glance (chapter 19: functional doors
## must be distinguishable; chapter 11's puzzle vocabulary depends on seeing cause and effect).
##
## The accent set deliberately avoids the four cassette identity hues (red, yellow, blue, green;
## UI-02) so a mechanism is never mistaken for a self.

const MECH_ACCENTS: Array[Color] = [
	Color("#ff8a1f"), # orange
	Color("#1fe8c0"), # teal
	Color("#f04dff"), # magenta
	Color("#9a6bff"), # violet
	Color("#f3ead2"), # ivory
	Color("#ff9ec4"), # coral pink
]

## Accent for mechanisms driven only by the beat grid or constants (no switch to match).
const BEAT_ACCENT := Color("#fff3c4")
## Exit zones read the same in every level.
const EXIT_ACCENT := Color("#c8fff4")
## Laser beams are always hazard red-magenta so danger is never colour-coded away.
const LASER_BEAM := Color("#ff2b5e")
## Door status lamp while closed.
const STATUS_CLOSED := Color("#ff3048")


## Pure-hash accent for a signal id (used when no level-wide assignment is available).
static func signal_accent(id: String) -> Color:
	return MECH_ACCENTS[WorldRng.hash_string(id) % MECH_ACCENTS.size()]


## Signal ids referenced by an expression, depth-first, in source order, without duplicates.
static func expr_signals(expr: SignalExpr, out: Array[String] = []) -> Array[String]:
	if expr == null:
		return out
	match expr.op:
		SignalExpr.Op.SIG:
			if not out.has(expr.sig):
				out.append(expr.sig)
		SignalExpr.Op.NOT, SignalExpr.Op.AND, SignalExpr.Op.OR, SignalExpr.Op.XOR:
			for a: SignalExpr in expr.args:
				expr_signals(a, out)
	return out


## Signals a mechanism consumes (doors, lasers, waking enemies) or produces (switch, plate,
## breakable, core, exit).
static func entity_signals(e: EntityDef) -> Array[String]:
	if e is DoorDef:
		return expr_signals((e as DoorDef).open_when)
	if e is LaserDef:
		return expr_signals((e as LaserDef).on_when)
	if e is EnemyDef:
		var w := (e as EnemyDef).wake_when
		return expr_signals(w) if w != null else ([] as Array[String])
	if e is SwitchDef or e is PlateDef or e is BreakableDef or e is CoreDef or e is ExitDef:
		return [e.id] as Array[String]
	return [] as Array[String]


## Level-wide signal -> accent table. Ids are visited in sorted order; each takes its hash-preferred
## slot, probing forward to the next unused accent so signals in one level stay distinct while the
## palette lasts. Deterministic for a given level.
## `extra` adds signal ids the entity list cannot show (trap drivers and trap sources; WorldTraps).
static func build_map(level: LevelDef, extra: Array[String] = []) -> Dictionary:
	var ids := {}
	for e: EntityDef in level.entities:
		for s: String in entity_signals(e):
			ids[s] = true
	for s: String in extra:
		ids[s] = true
	var sorted: Array[String] = []
	for k: String in ids:
		sorted.append(k)
	sorted.sort()
	var used := {}
	var out := {}
	for id: String in sorted:
		var start := WorldRng.hash_string(id) % MECH_ACCENTS.size()
		var slot := start
		if used.size() < MECH_ACCENTS.size():
			for k: int in range(MECH_ACCENTS.size()):
				var s := (start + k) % MECH_ACCENTS.size()
				if not used.has(s):
					slot = s
					break
		used[slot] = true
		out[id] = MECH_ACCENTS[slot]
	return out


## Accent for an expression: the colour of its first referenced signal, or the beat accent.
static func expr_accent(expr: SignalExpr, map: Dictionary = {}) -> Color:
	var sigs := expr_signals(expr)
	if sigs.is_empty():
		return BEAT_ACCENT
	return map.get(sigs[0], signal_accent(sigs[0]))
