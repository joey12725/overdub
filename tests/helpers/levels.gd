class_name TestLevels
extends RefCounted
## Test helper: build a valid minimal LevelDef in a few lines (port of prototype/tests/helpers/levels.ts).
##
##   var level := TestLevels.make_level({"map": ["#####", "#...#", "#####"], "entities": [door]})
##
## Defaults: bpm 120 (30 local ticks per beat), 4 bars (480 local ticks = 8 local seconds),
## horizon = bars / slowest offered speed, all speeds and end modes, a 12×10 walled open room,
## start at the room's centre (or the first floor tile of a custom map), default music.
##
## `partial` keys are LevelDef field names, snake_case ("horizon_bars") or the prototype's camelCase
## ("horizonBars"), with values of the field's type (end_modes as OD.EndMode ints, start as Vector2,
## entities as EntityDef objects, objective / music as objects). Plain Arrays are accepted for typed
## array fields.

## A 12×10 room: walls around a floor of 10×8 tiles (interior x ∈ [1, 11), y ∈ [1, 9)).
const OPEN_ROOM: Array[String] = [
	"############",
	"#..........#",
	"#..........#",
	"#..........#",
	"#..........#",
	"#..........#",
	"#..........#",
	"#..........#",
	"#..........#",
	"############",
]

const _FLOOR: String = ".:,~"


## The default level music (a fresh object each call: the prototype's DEFAULT_MUSIC constant).
static func default_music() -> LevelMusicDef:
	var m := LevelMusicDef.new()
	m.root = 9
	m.scale = "Minor"
	m.progression = [0, 5, 2, 6]
	m.chord_bars = 1
	for pair: Array in [[MusicRole.BASS, "triangular"], [MusicRole.DRUMS, "ruler"], [MusicRole.MELODY, "recaman"], [MusicRole.CHORD, "squares"]]:
		var t := TrackMusicDef.new()
		t.role = pair[0]
		t.formula = pair[1]
		m.tracks.append(t)
	return m


## Centre of the first floor tile scanning rows top to bottom, or of the map's middle tile.
## The prototype tests `map === OPEN_ROOM` by identity; GDScript arrays compare by value, so any map
## equal to OPEN_ROOM gets OPEN_ROOM's start.
static func default_start(map: Array[String]) -> Vector2:
	if map == OPEN_ROOM:
		return Vector2(6, 5)
	for r in map.size():
		var row := map[r]
		for c in row.length():
			if _FLOOR.contains(row[c]):
				return Vector2(c + 0.5, r + 0.5)
	return Vector2((map[0].length() if map.size() > 0 else 1) / 2.0, map.size() / 2.0)


static func make_level(partial: Dictionary = {}) -> LevelDef:
	var p := {}
	for k: Variant in partial:
		p[String(k).to_snake_case()] = partial[k]
	var level := LevelDef.new()
	level.id = "test-level"
	level.index = 0
	level.name = "Test Level"
	level.tagline = "A level built by a test."
	level.theme = LevelTheme.UPPER
	level.bpm = 120.0
	level.max_tapes = 4
	level.end_modes.assign(OD.ALL_END_MODES)
	level.objective = ObjectiveDef.new()
	level.objective.type = ObjectiveType.ELIMINATE
	level.objective.text = "Test objective"
	level.music = default_music()
	level.start_facing = 0.0
	# ...partial
	for key: String in p:
		if key in ["bars", "horizon_bars", "speeds", "map", "start"]:
			continue
		_assign(level, key, p[key])
	# Derived fields last, as the prototype spreads them after `...partial`.
	var speeds: Array[float] = []
	speeds.assign(p.get("speeds", OD.ALL_SPEEDS))
	var bars: int = p.get("bars", 4)
	var slowest: float = speeds.min()
	level.bars = bars
	if p.has("horizon_bars"):
		level.horizon_bars = p["horizon_bars"]
	else:
		var hb := bars / slowest
		if hb != floorf(hb):
			push_error("make_level: horizon bars %s is not an integer (LevelDef.horizon_bars is int)" % hb)
		level.horizon_bars = int(hb)
	level.speeds = speeds
	var map: Array[String] = []
	map.assign(p.get("map", OPEN_ROOM))
	level.map = map
	level.start = p["start"] if p.has("start") else default_start(map)
	return level


static func _assign(obj: Object, key: String, value: Variant) -> void:
	if not (key in obj):
		push_error("make_level: LevelDef has no field '%s'" % key)
		return
	var cur: Variant = obj.get(key)
	if cur is Array:
		(cur as Array).assign(value)
	elif cur is Dictionary and value is Dictionary:
		(cur as Dictionary).clear()
		(cur as Dictionary).merge(value)
	else:
		obj.set(key, value)
