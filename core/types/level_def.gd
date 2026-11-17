class_name LevelDef
extends RefCounted
## One level (types.ts LevelDef). Loaded from data/levels/<id>.json by ContentData.load_level().
##
## Map rows use one character per tile (types.ts MapRows):
##   '#' solid wall          '.' floor              ' ' void (no floor, impassable)
##   '=' low barrier (blocks movement, not projectiles/line of sight)
##   ':' metal grate floor   ',' overgrown floor    '~' inscribed/rune floor
## Anything dynamic (doors, switches, enemies...) is an entity placed on top of floor.
## Tile (c, r) covers world x in [c, c+1) and y in [r, r+1). Row 0 is the top of the array.

var id: String = ""
## Position on the fixed campaign path, 0-based (LEVEL-08).
var index: int = 0
var name: String = ""
## One-line teaser shown on the campaign path.
var tagline: String = ""
## LevelTheme.*
var theme: StringName = LevelTheme.UPPER
## Master tempo. 3600 / bpm must be an integer so a beat is a whole number of local ticks.
var bpm: float = 120.0
## Local recording allowance in bars - identical for every tape speed (TIME-02, TIME-04).
var bars: int = 8
## Length of the whole encounter on the master timeline, in master bars (authored; OPEN-02).
var horizon_bars: int = 16
## How many cassettes the level offers (LEVEL-02), 1..4.
var max_tapes: int = 4
## Speeds (TapeSpeed floats) / end behaviours (OD.EndMode) the level exposes (PLAY-05).
var speeds: Array[float] = []
var end_modes: Array[int] = []
## MapRows.
var map: Array[String] = []
## Every tape starts here at beat zero (REC-02).
var start: Vector2 = Vector2.ZERO
## Absent in JSON = 0.
var start_facing: float = 0.0
var entities: Array[EntityDef] = []
var objective: ObjectiveDef = ObjectiveDef.new()
var music: LevelMusicDef = LevelMusicDef.new()
## Gear ids awarded the first time the level is cleared.
var loot: Array[String] = []
## Briefing lines shown before the first take; teach one idea at a time.
var briefing: Array[String] = []
## Optional contextual hints keyed by tape NUMBER (1-based) shown during setup. Empty = absent.
var hints: Dictionary[int, String] = {}


## Entities of one kind (EntityKind.*), in authored order.
func entities_of(kind: StringName) -> Array[EntityDef]:
	var out: Array[EntityDef] = []
	for e: EntityDef in entities:
		if e.kind == kind:
			out.append(e)
	return out


func copy() -> LevelDef:
	var o := LevelDef.new()
	o.id = id
	o.index = index
	o.name = name
	o.tagline = tagline
	o.theme = theme
	o.bpm = bpm
	o.bars = bars
	o.horizon_bars = horizon_bars
	o.max_tapes = max_tapes
	o.speeds = speeds.duplicate()
	o.end_modes = end_modes.duplicate()
	o.map = map.duplicate()
	o.start = start
	o.start_facing = start_facing
	for e: EntityDef in entities:
		o.entities.append(e.copy())
	o.objective = objective.copy()
	o.music = music.copy()
	o.loot = loot.duplicate()
	o.briefing = briefing.duplicate()
	o.hints = hints.duplicate()
	return o


## Parse one entity by its `kind`. Returns null and appends to `errors` for an unknown kind.
static func entity_from_dict(d: Variant, errors: Array[String] = []) -> EntityDef:
	if not (d is Dictionary):
		errors.append("entity must be an object")
		return null
	var dd: Dictionary = d
	match ODJson.sname(dd, "kind"):
		EntityKind.ENEMY:
			return EnemyDef.from_dict(dd, errors)
		EntityKind.DOOR:
			return DoorDef.from_dict(dd, errors)
		EntityKind.SWITCH:
			return SwitchDef.from_dict(dd)
		EntityKind.PLATE:
			return PlateDef.from_dict(dd)
		EntityKind.BREAKABLE:
			return BreakableDef.from_dict(dd)
		EntityKind.LASER:
			return LaserDef.from_dict(dd, errors)
		EntityKind.CORE:
			return CoreDef.from_dict(dd)
		EntityKind.EXIT:
			return ExitDef.from_dict(dd)
		EntityKind.DECOR:
			return DecorDef.from_dict(dd)
		EntityKind.SPIKES:
			return SpikesDef.from_dict(dd, errors)
		EntityKind.CRUSHER:
			return CrusherDef.from_dict(dd, errors)
		EntityKind.CONVEYOR:
			return ConveyorDef.from_dict(dd, errors)
		EntityKind.FLAME:
			return FlameDef.from_dict(dd, errors)
		EntityKind.DART:
			return DartDef.from_dict(dd, errors)
		EntityKind.BUMPER:
			return BumperDef.from_dict(dd, errors)
		EntityKind.SENSOR:
			return SensorDef.from_dict(dd, errors)
		EntityKind.RELAY:
			return RelayDef.from_dict(dd, errors)
		EntityKind.MAGNET:
			return MagnetDef.from_dict(dd, errors)
	errors.append("unknown entity kind '%s'" % ODJson.string(dd, "kind"))
	return null


## Parse the prototype JSON shape. Structural problems (unknown entity kinds, malformed signal
## expressions, unknown end modes) are appended to `errors`; the offending item is skipped. Semantic
## validation (map shape, ids, reachability...) is LevelValidator's job (content/validate.gd).
static func from_dict(d: Dictionary, errors: Array[String] = []) -> LevelDef:
	var o := LevelDef.new()
	o.id = ODJson.string(d, "id")
	o.index = ODJson.integer(d, "index")
	o.name = ODJson.string(d, "name")
	o.tagline = ODJson.string(d, "tagline")
	o.theme = ODJson.sname(d, "theme", LevelTheme.UPPER)
	o.bpm = ODJson.num(d, "bpm", 120.0)
	o.bars = ODJson.integer(d, "bars", 8)
	o.horizon_bars = ODJson.integer(d, "horizonBars", 16)
	o.max_tapes = ODJson.integer(d, "maxTapes", 4)
	o.speeds = ODJson.floats(d.get("speeds"))
	for name_v: String in ODJson.strings(d.get("endModes")):
		var m := OD.end_mode_from_name(name_v)
		if m < 0:
			errors.append("level %s: unknown end mode '%s'" % [o.id, name_v])
		else:
			o.end_modes.append(m)
	o.map = ODJson.strings(d.get("map"))
	o.start = ODJson.vec2(d.get("start"))
	o.start_facing = ODJson.num(d, "startFacing")
	for e: Variant in ODJson.array(d, "entities"):
		var ent := entity_from_dict(e, errors)
		if ent != null:
			o.entities.append(ent)
	o.objective = ObjectiveDef.from_dict(ODJson.dict(d, "objective"), errors)
	o.music = LevelMusicDef.from_dict(ODJson.dict(d, "music"))
	o.loot = ODJson.strings(d.get("loot"))
	o.briefing = ODJson.strings(d.get("briefing"))
	var h := ODJson.dict(d, "hints")
	for k: Variant in h:
		var key := str(k)
		if key.is_valid_int() and (h[k] is String):
			o.hints[key.to_int()] = h[k]
		else:
			errors.append("level %s: bad hint key '%s'" % [o.id, key])
	return o


func to_dict() -> Dictionary:
	var ents: Array = []
	for e: EntityDef in entities:
		ents.append(e.to_dict())
	var modes: Array = []
	for m: int in end_modes:
		modes.append(OD.end_mode_name(m))
	var out := {
		"id": id,
		"index": index,
		"name": name,
		"tagline": tagline,
		"theme": String(theme),
		"bpm": bpm,
		"bars": bars,
		"horizonBars": horizon_bars,
		"maxTapes": max_tapes,
		"speeds": speeds.duplicate(),
		"endModes": modes,
		"map": ODJson.strings_to_array(map),
		"start": ODJson.vec2_to_dict(start),
	}
	if start_facing != 0.0:
		out["startFacing"] = start_facing
	out["entities"] = ents
	out["objective"] = objective.to_dict()
	out["music"] = music.to_dict()
	out["loot"] = ODJson.strings_to_array(loot)
	out["briefing"] = ODJson.strings_to_array(briefing)
	if not hints.is_empty():
		var hd := {}
		for k: int in hints:
			hd[str(k)] = hints[k]
		out["hints"] = hd
	return out
