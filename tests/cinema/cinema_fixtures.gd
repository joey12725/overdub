class_name CinemaTestFixtures
extends RefCounted
## Hand-built Resolutions for the cinematic director's tests: dense frames (one every
## OD.FRAME_SUBS substeps, like the real Resolution) from per-self position functions, plus events.
##
##   var fx := CinemaTestFixtures.new(level, 16)             # 16 beats at the level's bpm
##   fx.path(0, [Vector2(2, 2), Vector2(8, 2)])              # self A walks between waypoints
##   fx.swing(0, 3.0, "g1", true)                            # A kills g1 on beat 3 (wind-up drawn)
##   var res := fx.build()

const MUSIC := {
	"root": 9, "scale": "Minor", "progression": [0, 5, 2, 6], "chordBars": 1,
	"tracks": [
		{"role": "bass", "formula": "triangular"}, {"role": "drums", "formula": "ruler"},
		{"role": "melody", "formula": "recaman"}, {"role": "chord", "formula": "squares"},
	],
}

## Two rooms joined by a door at (6, 3): west x in [1, 6), east x in [7, 13).
const TWO_ROOMS: Array[String] = [
	"##############",
	"#.....#......#",
	"#.....#......#",
	"#............#",
	"#.....#......#",
	"#.....#......#",
	"##############",
]

## Two rooms far apart joined by a long corridor at row 3 (door at (8, 3)).
const FAR_ROOMS: Array[String] = [
	"########################",
	"#......#########.......#",
	"#......#########.......#",
	"#......................#",
	"#......#########.......#",
	"#......#########.......#",
	"########################",
]

var level: LevelDef
var beats: int = 16
var subs_per_beat: float = 120.0
var events: Array[SimEvent] = []
## tape -> waypoints (positions spread evenly over the run).
var _paths: Dictionary[int, Array] = {}
## tape -> [[from_beat, to_beat, anim]]
var _anims: Dictionary[int, Array] = {}
## tape -> death beat
var _deaths: Dictionary[int, float] = {}
## enemy id -> [type, position, death beat or -1]
var _enemies: Dictionary[String, Array] = {}
var survivors: Array[int] = []
var win: bool = true


static func make_level(map: Array[String], entities: Array = [], objective: Dictionary = {}, horizon_bars: int = 4) -> LevelDef:
	var obj := objective if not objective.is_empty() else {"type": "eliminate", "text": "Test objective"}
	var d := {
		"id": "cine-test", "index": 0, "name": "Cinema test", "tagline": "", "theme": "upper",
		"bpm": 120, "bars": 4, "horizonBars": horizon_bars, "maxTapes": 4,
		"speeds": [0.5, 1, 2, 4], "endModes": ["stop", "repeat", "reverse"],
		"map": map, "start": {"x": 2.5, "y": 3.5}, "startFacing": 0,
		"entities": entities, "objective": obj, "music": MUSIC, "loot": [], "briefing": [],
	}
	var errors: Array[String] = []
	return LevelDef.from_dict(d, errors)


func _init(p_level: LevelDef, p_beats: int) -> void:
	level = p_level
	beats = p_beats
	subs_per_beat = float(OD.SUB_HZ) * 60.0 / level.bpm


func sub_of(beat: float) -> int:
	return int(round(beat * subs_per_beat))


func path(tape: int, waypoints: Array) -> CinemaTestFixtures:
	_paths[tape] = waypoints
	if not survivors.has(tape):
		survivors.append(tape)
	return self


func enemy(id: String, type: StringName, p: Vector2) -> CinemaTestFixtures:
	_enemies[id] = [type, p, -1.0]
	return self


func anim(tape: int, from_beat: float, to_beat: float, a: StringName) -> CinemaTestFixtures:
	if not _anims.has(tape):
		_anims[tape] = []
	_anims[tape].append([from_beat, to_beat, a])
	return self


func ev(beat: float, type: StringName, p: Vector2, tape: int = -1, id: String = "", detail: String = "") -> SimEvent:
	var e := SimEvent.make(sub_of(beat), type, p.x, p.y).with_tape(tape).with_id(id).with_detail(detail)
	events.append(e)
	return e


## A self's light swing landing on `beat` (wind-up drawn for 0.3 beats); kills `id` when `kill`.
func swing(tape: int, beat: float, id: String, kill: bool, detail: String = "light") -> CinemaTestFixtures:
	var me := pos(tape, beat)
	var ep: Vector2 = _enemies[id][1] if _enemies.has(id) else me + Vector2(1, 0)
	anim(tape, beat - 0.3, beat, AnimState.LIGHT_WINDUP if detail == "light" else AnimState.HEAVY_WINDUP)
	anim(tape, beat, beat + 0.15, AnimState.LIGHT_ACTIVE if detail == "light" else AnimState.HEAVY_ACTIVE)
	ev(beat, SimEventType.SWING, me, tape, "", detail)
	if id.is_empty():
		return self
	ev(beat, SimEventType.HIT, ep, tape, id, detail).with_power(1.0)
	if kill:
		ev(beat, SimEventType.KILL, ep, tape, id, detail).with_power(1.0)
		if _enemies.has(id):
			_enemies[id][2] = beat
	return self


func death(tape: int, beat: float, cause: String) -> CinemaTestFixtures:
	_deaths[tape] = beat
	survivors.erase(tape)
	ev(beat, SimEventType.SELF_DEATH, pos(tape, beat), tape, "", cause)
	return self


func pos(tape: int, beat: float) -> Vector2:
	var w: Array = _paths.get(tape, [level.start])
	if w.size() == 1:
		return w[0]
	var u := clampf(beat / float(beats), 0.0, 1.0) * float(w.size() - 1)
	var i := mini(int(floor(u)), w.size() - 2)
	return (w[i] as Vector2).lerp(w[i + 1], u - float(i))


func _anim_at(tape: int, beat: float) -> StringName:
	for a: Array in _anims.get(tape, []):
		if beat >= float(a[0]) and beat < float(a[1]):
			return a[2]
	return AnimState.RUN if _paths.get(tape, []).size() > 1 else AnimState.IDLE


func build() -> Resolution:
	events.sort_custom(func(a: SimEvent, b: SimEvent) -> bool: return a.sub < b.sub)
	var res := Resolution.new()
	res.horizon_subs = sub_of(float(beats))
	var tapes: Array[int] = []
	for t: int in _paths.keys():
		tapes.append(t)
	tapes.sort()
	var ids: Array[String] = []
	for k: String in _enemies.keys():
		ids.append(k)
	ids.sort()
	var sub := 0
	while sub <= res.horizon_subs:
		var b := float(sub) / subs_per_beat
		var f := FrameSnapshot.new()
		f.sub = sub
		f.beat = b
		for t: int in tapes:
			var a := ActorSnap.new()
			a.tape = t
			var p := pos(t, b)
			a.x = p.x
			a.y = p.y
			a.anim = _anim_at(t, b)
			a.life = OD.LifeState.GHOST if _deaths.has(t) and b >= _deaths[t] else OD.LifeState.ALIVE
			f.actors.append(a)
		for id: String in ids:
			var e := EnemySnap.new()
			e.id = id
			e.type = _enemies[id][0]
			var ep: Vector2 = _enemies[id][1]
			e.x = ep.x
			e.y = ep.y
			var db: float = _enemies[id][2]
			e.alive = db < 0.0 or b < db
			f.enemies.append(e)
		res.frames.append(f)
		sub += OD.FRAME_SUBS
	res.events = events
	res.outcome.win = win
	res.outcome.objective_complete = win
	res.outcome.survivors = survivors.duplicate()
	res.outcome.survivors.sort()
	return res
