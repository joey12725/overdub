extends ODTest
## Port of prototype/tests/content/validate.test.ts against content/validate.gd (LevelValidator).
## Run with `bash tools/gd test validate`.
##
## Cases that need a malformed raw value (an expression with two operators, an unknown operator name,
## a non-boolean const, a fractional bars) build the level as raw JSON and call validate_json(); the
## rest mutate typed objects and call validate_level().

## A small level that satisfies every rule. Individual tests mutate one aspect and assert that the
## matching message is reported. Mutations that break one rule may cascade into related messages;
## tests only require the expected message to be present.
const MAP: Array[String] = [
	"#########",
	"#.......#",
	"#.:.=.,.#",
	"#...~...#",
	"#.#...###",
	"#.....#.#",
	"#########",
]


# ───────────────────────────── fixtures ─────────────────────────────

func _rows(source: Array[String]) -> Array[String]:
	var rows: Array[String] = []
	rows.assign(source)
	return rows


func _track(role: StringName, formula: String, params: Dictionary = {}, genre: String = "") -> TrackMusicDef:
	var t := TrackMusicDef.new()
	t.role = role
	t.formula = formula
	for name: Variant in params:
		t.params[str(name)] = float(params[name])
	t.genre = genre
	return t


func _music() -> LevelMusicDef:
	var m := LevelMusicDef.new()
	m.root = 0
	m.scale = "major"
	m.progression = [0, 3, 4, 0]
	m.tracks = [
		_track(&"bass", "pulse"),
		_track(&"drums", "pulse", {}, "house"),
		_track(&"melody", "pulse", {"density": 0.5}),
		_track(&"chord", "pulse"),
	]
	return m


func _switch(id: String, x: float, y: float) -> SwitchDef:
	var e := SwitchDef.new()
	e.id = id
	e.x = x
	e.y = y
	return e


func _plate(id: String, c: int, r: int) -> PlateDef:
	var e := PlateDef.new()
	e.id = id
	e.c = c
	e.r = r
	return e


func _breakable(id: String, c: int, r: int, threshold: float) -> BreakableDef:
	var e := BreakableDef.new()
	e.id = id
	e.c = c
	e.r = r
	e.threshold = threshold
	return e


func _door(id: String, cells: Array[Vector2i], open_when: SignalExpr) -> DoorDef:
	var e := DoorDef.new()
	e.id = id
	e.cells = cells
	e.open_when = open_when
	return e


func _laser(id: String, from: Vector2, to: Vector2, on_when: SignalExpr) -> LaserDef:
	var e := LaserDef.new()
	e.id = id
	e.from = from
	e.to = to
	e.on_when = on_when
	return e


func _core(id: String, x: float, y: float, threshold: float) -> CoreDef:
	var e := CoreDef.new()
	e.id = id
	e.x = x
	e.y = y
	e.threshold = threshold
	e.has_threshold = true
	return e


func _exit(id: String, c: int, r: int, w: int, h: int) -> ExitDef:
	var e := ExitDef.new()
	e.id = id
	e.c = c
	e.r = r
	e.w = w
	e.h = h
	return e


func _enemy(id: String, type: StringName, x: float, y: float) -> EnemyDef:
	var e := EnemyDef.new()
	e.id = id
	e.type = type
	e.x = x
	e.y = y
	return e


func _decor(type: StringName, x: float, y: float) -> DecorDef:
	var e := DecorDef.new()
	e.type = type
	e.x = x
	e.y = y
	return e


func _base_entities() -> Array[EntityDef]:
	var g1 := _enemy("g1", &"grunt", 4.5, 5.5)
	var t1 := _enemy("t1", &"turret", 5.5, 5.5)
	t1.wake_when = SignalExpr.of_sig("dead:g1")
	var l1 := _laser("l1", Vector2(2.5, 1.5), Vector2(6.5, 1.5), SignalExpr.of_not(SignalExpr.of_sig("sw1")))
	var d1_cells: Array[Vector2i] = [Vector2i(7, 3)]
	var list: Array[EntityDef] = [
		_switch("sw1", 1.5, 3.5),
		_plate("p1", 3, 5),
		_breakable("b1", 4, 3, 2.0),
		_door("d1", d1_cells, SignalExpr.of_sig("sw1")),
		l1,
		_core("c1", 3.5, 1.5, 1.0),
		_exit("x1", 7, 1, 1, 1),
		g1,
		t1,
		_decor(&"crate", 1.5, 5.5),
	]
	return list


func _objective(type: StringName, text: String, targets: Array[String] = [], when_expr: SignalExpr = null) -> ObjectiveDef:
	var o := ObjectiveDef.new()
	o.type = type
	o.text = text
	o.targets = targets
	o.when_expr = when_expr
	return o


func _level() -> LevelDef:
	var l := LevelDef.new()
	l.id = "lvl-a"
	l.index = 0
	l.name = "Test Room"
	l.tagline = "A room for tests."
	l.theme = LevelTheme.UPPER
	l.bpm = 120.0
	l.bars = 8
	l.horizon_bars = 16
	l.max_tapes = 2
	l.speeds = [0.5, 1.0, 2.0, 4.0]
	l.end_modes = [OD.EndMode.STOP, OD.EndMode.REPEAT, OD.EndMode.REVERSE]
	l.map = _rows(MAP)
	l.start = Vector2(1.5, 1.5)
	l.entities = _base_entities()
	l.objective = _objective(ObjectiveType.ELIMINATE, "Clear the room")
	l.music = _music()
	l.loot = ["gear-a"]
	l.briefing = ["Record a take."]
	l.hints = {1: "Stand on the plate."}
	return l


## The entity with the given id in a level's typed list, or null.
func _find(l: LevelDef, id: String) -> EntityDef:
	for e: EntityDef in l.entities:
		if e.id == id:
			return e
	return null


## Every entity whose kind is not `kind`.
func _without_kind(kind: StringName) -> LevelDef:
	var l := _level()
	var kept: Array[EntityDef] = []
	for e: EntityDef in l.entities:
		if e.kind != kind:
			kept.append(e)
	l.entities = kept
	return l


## The raw JSON object of the entity with the given id inside a level's to_dict() output.
func _raw_entity(d: Dictionary, id: String) -> Dictionary:
	for e: Variant in d["entities"]:
		if e is Dictionary and (e as Dictionary).get("id", "") == id:
			return e
	return {}


func _problems(level: LevelDef) -> PackedStringArray:
	var out := PackedStringArray()
	for m: String in LevelValidator.validate_level(level):
		if LevelValidator.is_problem(m):
			out.append(m)
	return out


func _json_problems(d: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for m: String in LevelValidator.validate_json(d):
		if LevelValidator.is_problem(m):
			out.append(m)
	return out


func _contains(list: PackedStringArray, needle: String) -> bool:
	for s: String in list:
		if s.contains(needle):
			return true
	return false


func _listing(list: PackedStringArray) -> String:
	return "(none)" if list.is_empty() else "\n".join(list)


func _expect_problem(level: LevelDef, needle: String) -> void:
	var problems := _problems(level)
	assert_true(_contains(problems, needle), "expected a problem containing '%s'; got:\n%s" % [needle, _listing(problems)])


func _expect_no_problems(level: LevelDef) -> void:
	var problems := _problems(level)
	assert_true(problems.is_empty(), "expected no problems; got:\n%s" % _listing(problems))


func _expect_json_problem(d: Dictionary, needle: String) -> void:
	var problems := _json_problems(d)
	assert_true(_contains(problems, needle), "expected a problem containing '%s'; got:\n%s" % [needle, _listing(problems)])


# ───────────────────────────── valid fixture ─────────────────────────────

func test_valid_fixture_reports_nothing() -> void:
	var messages := LevelValidator.validate_level(_level())
	assert_eq(messages.size(), 0, "a level that satisfies every rule reports nothing")


func test_horizon_shorter_than_slowest_speed_is_a_note_not_a_problem() -> void:
	var l := _level()
	l.speeds = [1.0, 2.0]
	l.horizon_bars = 6
	var messages := LevelValidator.validate_level(l)
	var found_note := false
	for m: String in messages:
		if m.begins_with("note: ") and m.contains("slowest offered speed"):
			found_note = true
	assert_true(found_note, "a horizon shorter than one slowest pass is reported as a note")
	_expect_no_problems(l)


func test_is_problem_separates_notes_from_problems() -> void:
	assert_false(LevelValidator.is_problem("note: horizon is short"), "a note: entry is an advisory")
	assert_true(LevelValidator.is_problem("bars must be a positive integer"), "any other entry is a problem")


func test_json_round_trip_of_the_fixture_reports_nothing() -> void:
	# to_dict() output is the prototype JSON shape; the raw path must accept what the typed path accepts.
	assert_eq(_json_problems(_level().to_dict()).size(), 0, "the fixture's JSON form is valid")


# ───────────────────────────── time and tempo ─────────────────────────────

func test_rejects_bpm_where_3600_over_bpm_is_not_an_integer() -> void:
	var l := _level()
	l.bpm = 7.0
	_expect_problem(l, "3600 / bpm must be an integer")


func test_rejects_non_positive_bars() -> void:
	var l := _level()
	l.bars = 0
	_expect_problem(l, "bars must be a positive integer")


func test_rejects_non_positive_horizon_bars() -> void:
	var l := _level()
	l.horizon_bars = 0
	_expect_problem(l, "horizonBars must be a positive integer")


func test_rejects_fractional_bars_in_json() -> void:
	# The typed model holds ints, so a fractional value is only visible in the raw JSON.
	var d := _level().to_dict()
	d["horizonBars"] = 10.5
	_expect_json_problem(d, "horizonBars must be a positive integer (got 10.5)")


func test_rejects_horizon_shorter_than_one_pass_of_the_fastest_speed() -> void:
	var l := _level()
	l.horizon_bars = 1
	_expect_problem(l, "shorter than one pass of the fastest speed")


# ───────────────────────────── tapes, speeds and end modes ─────────────────────────────

func test_rejects_max_tapes_outside_1_to_4() -> void:
	var l := _level()
	l.max_tapes = 5
	_expect_problem(l, "maxTapes must be an integer 1..4")


func test_rejects_a_speed_that_is_not_in_all_speeds() -> void:
	var l := _level()
	l.speeds = [1.0, 3.0]
	_expect_problem(l, "must be a power of two from ALL_SPEEDS")


func test_rejects_duplicate_speeds() -> void:
	var l := _level()
	l.speeds = [1.0, 1.0]
	_expect_problem(l, "speeds lists 1 more than once")


func test_rejects_an_empty_speeds_list() -> void:
	var l := _level()
	l.speeds = []
	_expect_problem(l, "speeds must not be empty")


func test_rejects_duplicate_end_modes() -> void:
	var l := _level()
	l.end_modes = [OD.EndMode.STOP, OD.EndMode.STOP]
	_expect_problem(l, 'endModes lists "stop" more than once')


func test_rejects_an_unknown_end_mode() -> void:
	var l := _level()
	l.end_modes = [7]
	_expect_problem(l, "must be one of stop, repeat, reverse")


func test_json_rejects_an_unknown_end_mode_name() -> void:
	# A name that is not an end mode is dropped by LevelDef.from_dict and reported there.
	var d := _level().to_dict()
	d["endModes"] = ["spin"]
	_expect_json_problem(d, "unknown end mode 'spin'")


func test_rejects_an_empty_end_mode_list() -> void:
	var l := _level()
	l.end_modes = []
	_expect_problem(l, "endModes must not be empty")


# ───────────────────────────── map ─────────────────────────────

func test_rejects_an_empty_map() -> void:
	var l := _level()
	l.map = []
	_expect_problem(l, "map must be a non-empty array")


func test_rejects_a_non_rectangular_map() -> void:
	var rows := _rows(MAP)
	rows[3] = "#...~..."
	var l := _level()
	l.map = rows
	_expect_problem(l, "map row 3 has length 8, expected 9")


func test_rejects_characters_outside_the_documented_set() -> void:
	var rows := _rows(MAP)
	rows[1] = "#.......X"
	var l := _level()
	l.map = rows
	_expect_problem(l, 'undocumented characters "X"')


func test_rejects_a_walkable_border_that_the_start_can_reach() -> void:
	var rows := _rows(MAP)
	rows[0] = "###.#####"
	var l := _level()
	l.map = rows
	_expect_problem(l, "walkable area leaks past the map edge at (3,0)")


func test_accepts_a_walkable_border_tile_that_the_start_cannot_reach() -> void:
	# The corner floor tile touches only walls, so it is sealed off by void and walls.
	var rows := _rows(MAP)
	rows[0] = ".########"
	var l := _level()
	l.map = rows
	_expect_no_problems(l)


# ───────────────────────────── start and positions ─────────────────────────────

func test_rejects_a_start_on_a_wall_tile() -> void:
	var l := _level()
	l.start = Vector2(2.5, 4.5)
	_expect_problem(l, "start tile (2,4) is not a walkable floor tile")


func test_rejects_a_start_outside_the_map() -> void:
	var l := _level()
	l.start = Vector2(99.0, 1.0)
	_expect_problem(l, "start (99, 1) is outside the map")


func test_rejects_an_entity_position_outside_the_map() -> void:
	var l := _level()
	(_find(l, "g1") as EnemyDef).x = 20.0
	_expect_problem(l, 'enemy "g1": position (20, 5.5) is outside the map')


func test_rejects_an_enemy_standing_on_a_wall_tile() -> void:
	var l := _level()
	var g1 := _find(l, "g1") as EnemyDef
	g1.x = 2.5
	g1.y = 4.5
	_expect_problem(l, "enemy \"g1\": tile (2,4) is '#', not a floor tile")


func test_rejects_a_switch_on_a_low_barrier() -> void:
	var l := _level()
	var sw := _find(l, "sw1") as SwitchDef
	sw.x = 4.5
	sw.y = 2.5
	_expect_problem(l, "switch \"sw1\": tile (4,2) is '=', not a floor tile")


func test_rejects_a_breakable_placed_on_a_wall() -> void:
	var l := _level()
	var b1 := _find(l, "b1") as BreakableDef
	b1.c = 2
	b1.r = 4
	_expect_problem(l, "breakable \"b1\": cell (2,4) is '#', not a floor tile")


func test_rejects_a_door_cell_placed_on_a_wall() -> void:
	var l := _level()
	var d1 := _find(l, "d1") as DoorDef
	var cells: Array[Vector2i] = [Vector2i(0, 0)]
	d1.cells = cells
	_expect_problem(l, "door \"d1\": cell (0,0) is '#', not a floor tile")


func test_rejects_a_laser_endpoint_outside_the_map() -> void:
	var l := _level()
	(_find(l, "l1") as LaserDef).to = Vector2(12.0, 1.5)
	_expect_problem(l, 'laser "l1".to: position (12, 1.5) is outside the map')


func test_rejects_an_exit_rectangle_that_extends_past_the_map() -> void:
	var l := _level()
	(_find(l, "x1") as ExitDef).w = 3
	_expect_problem(l, 'exit "x1": cell (9,1) is outside the map')


# ───────────────────────────── solid occupancy ─────────────────────────────

func test_rejects_two_solid_entities_on_one_tile() -> void:
	var l := _level()
	var entities := l.entities
	entities.append(_breakable("b2", 1, 3, 1.0))
	l.entities = entities
	_expect_problem(l, 'breakable "b2" and switch "sw1" share tile (1,3)')


func test_allows_a_body_to_stand_on_a_plate() -> void:
	var l := _level()
	var entities := l.entities
	entities.append(_enemy("g2", &"grunt", 3.5, 5.5))
	l.entities = entities
	_expect_no_problems(l)


# ───────────────────────────── ids and signals ─────────────────────────────

func test_rejects_duplicate_ids_across_entity_kinds() -> void:
	var l := _level()
	(_find(l, "c1") as CoreDef).id = "sw1"
	_expect_problem(l, 'duplicate id "sw1" (switch and core)')


func test_rejects_a_signal_that_no_entity_produces() -> void:
	var l := _level()
	(_find(l, "d1") as DoorDef).open_when = SignalExpr.of_sig("nope")
	_expect_problem(l, 'signal "nope" is not produced')


func test_rejects_a_dead_reference_to_an_enemy_that_does_not_exist() -> void:
	var l := _level()
	(_find(l, "t1") as EnemyDef).wake_when = SignalExpr.of_sig("dead:ghost")
	_expect_problem(l, 'refers to enemy "ghost", which does not exist')


func test_accepts_a_dead_reference_to_an_existing_enemy() -> void:
	_expect_no_problems(_level())


func test_json_rejects_an_expression_node_with_two_operators() -> void:
	var d := _level().to_dict()
	_raw_entity(d, "d1")["openWhen"] = {"sig": "sw1", "const": true}
	_expect_json_problem(d, "exactly one operator (has sig, const)")


func test_rejects_an_unknown_operator() -> void:
	var l := _level()
	(_find(l, "d1") as DoorDef).open_when.op = 42
	_expect_problem(l, "unknown signal operator")


func test_json_rejects_an_unknown_operator_name() -> void:
	var d := _level().to_dict()
	_raw_entity(d, "d1")["openWhen"] = {"nand": []}
	_expect_json_problem(d, "unknown expression")


func test_rejects_an_xor_that_does_not_have_two_operands() -> void:
	var l := _level()
	var expr := SignalExpr.new()
	expr.op = SignalExpr.Op.XOR
	expr.args = [SignalExpr.of_sig("sw1")]
	(_find(l, "d1") as DoorDef).open_when = expr
	_expect_problem(l, "xor needs exactly two expressions")


func test_rejects_an_empty_and() -> void:
	var l := _level()
	var none: Array[SignalExpr] = []
	(_find(l, "d1") as DoorDef).open_when = SignalExpr.of_and(none)
	_expect_problem(l, "and needs a non-empty array")


func test_json_rejects_a_non_boolean_const() -> void:
	var d := _level().to_dict()
	_raw_entity(d, "d1")["openWhen"] = {"const": "yes"}
	_expect_json_problem(d, "const must be a boolean")


func test_rejects_a_beat_window_with_every_at_or_below_zero() -> void:
	var l := _level()
	(_find(l, "l1") as LaserDef).on_when = SignalExpr.of_beat(0.0, 0.0, 0.0)
	_expect_problem(l, "every > 0")


func test_rejects_a_beat_window_whose_from_is_not_below_to() -> void:
	var l := _level()
	(_find(l, "l1") as LaserDef).on_when = SignalExpr.of_beat(4.0, 3.0, 2.0)
	_expect_problem(l, "0 <= from < to <= every")


func test_rejects_a_beat_window_that_ends_after_every() -> void:
	var l := _level()
	(_find(l, "l1") as LaserDef).on_when = SignalExpr.of_beat(4.0, 0.0, 5.0)
	_expect_problem(l, "0 <= from < to <= every")


func test_accepts_a_well_formed_beat_window() -> void:
	var l := _level()
	(_find(l, "l1") as LaserDef).on_when = SignalExpr.of_beat(4.0, 0.0, 2.0)
	_expect_no_problems(l)


func test_requires_a_door_to_have_open_when() -> void:
	var l := _level()
	(_find(l, "d1") as DoorDef).open_when = null
	_expect_problem(l, 'door "d1": openWhen is required')


# ───────────────────────────── objective ─────────────────────────────

func test_rejects_eliminate_with_no_enemies_and_no_targets() -> void:
	_expect_problem(_without_kind(EntityKind.ENEMY), "eliminate objective needs at least one enemy")


func test_rejects_eliminate_targets_that_are_not_enemies() -> void:
	var l := _level()
	var targets: Array[String] = ["ghost"]
	l.objective = _objective(ObjectiveType.ELIMINATE, "Go", targets)
	_expect_problem(l, 'objective target "ghost" is not a enemy')


func test_rejects_reach_without_an_exit() -> void:
	var l := _without_kind(EntityKind.EXIT)
	l.objective = _objective(ObjectiveType.REACH, "Get out")
	_expect_problem(l, "reach objective needs at least one exit")


func test_rejects_activate_without_cores() -> void:
	var l := _without_kind(EntityKind.CORE)
	l.objective = _objective(ObjectiveType.ACTIVATE, "Light up")
	_expect_problem(l, "activate objective needs at least one core")


func test_rejects_boss_without_exactly_one_boss_enemy() -> void:
	var l := _level()
	l.objective = _objective(ObjectiveType.BOSS, "Defeat it")
	_expect_problem(l, "boss objective needs exactly one boss enemy (found 0)")


func test_rejects_signal_without_a_when_expression() -> void:
	var l := _level()
	l.objective = _objective(ObjectiveType.SIGNAL, "Wait")
	_expect_problem(l, 'signal objective needs a "when" expression')


func test_rejects_an_objective_when_expression_with_an_unproduced_signal() -> void:
	var l := _level()
	var none: Array[String] = []
	l.objective = _objective(ObjectiveType.SIGNAL, "Wait", none, SignalExpr.of_sig("ghost"))
	_expect_problem(l, 'signal "ghost" is not produced')


func test_accepts_a_signal_objective_whose_when_is_a_produced_signal() -> void:
	var l := _level()
	var none: Array[String] = []
	l.objective = _objective(ObjectiveType.SIGNAL, "Wait", none, SignalExpr.of_sig("dead:g1"))
	_expect_no_problems(l)


# ───────────────────────────── reachability ─────────────────────────────

func test_reports_an_enemy_sealed_off_from_the_start() -> void:
	var l := _level()
	var g1 := _find(l, "g1") as EnemyDef
	g1.x = 7.5
	g1.y = 5.5
	_expect_problem(l, 'enemy "g1" is unreachable from the start')


func test_treats_a_closed_door_as_passable_when_checking_reachability() -> void:
	# The only route into the pocket at (7,5) runs through the door cell at (7,4). Doors are passable
	# for reachability (ARCHITECTURE: "treating doors and breakables as passable"), so the grunt behind
	# it still counts as reachable.
	var rows := _rows(MAP)
	rows[4] = "#.#...#.#"
	var l := _level()
	l.map = rows
	var cells: Array[Vector2i] = [Vector2i(7, 4)]
	(_find(l, "d1") as DoorDef).cells = cells
	var g1 := _find(l, "g1") as EnemyDef
	g1.x = 7.5
	g1.y = 5.5
	_expect_no_problems(l)


# ───────────────────────────── music ─────────────────────────────

func test_rejects_a_track_list_that_does_not_have_four_entries() -> void:
	var l := _level()
	var music := _music()
	var three: Array[TrackMusicDef] = []
	for t: int in range(3):
		three.append(music.tracks[t])
	music.tracks = three
	l.music = music
	_expect_problem(l, "tracks must have exactly four entries (found 3)")


func test_rejects_an_unknown_track_role() -> void:
	var l := _level()
	l.music.tracks[0].role = &"lead"
	_expect_problem(l, 'role "lead" is not one of')


func test_rejects_a_root_outside_0_to_11() -> void:
	var l := _level()
	l.music.root = 12
	_expect_problem(l, "music.root must be an integer 0..11")


func test_rejects_an_empty_progression() -> void:
	var l := _level()
	l.music.progression = []
	_expect_problem(l, "progression must be a non-empty array")


func test_rejects_a_progression_degree_outside_0_to_6() -> void:
	var l := _level()
	l.music.progression = [0, 7]
	_expect_problem(l, "progression degree 7 must be an integer 0..6")


func test_rejects_a_negative_chord_bars() -> void:
	var l := _level()
	l.music.chord_bars = -2
	_expect_problem(l, "music.chordBars must be a positive integer when present")


func test_json_rejects_a_present_zero_or_fractional_chord_bars() -> void:
	# The typed model reads an absent chordBars as 0, so a present 0 or a fraction is only visible in JSON.
	var d := _level().to_dict()
	(d["music"] as Dictionary)["chordBars"] = 0
	_expect_json_problem(d, "music.chordBars must be a positive integer when present")
	d = _level().to_dict()
	(d["music"] as Dictionary)["chordBars"] = 1.5
	_expect_json_problem(d, "music.chordBars must be a positive integer when present")


# ───────────────────────────── briefing, loot and hints ─────────────────────────────

func test_rejects_an_empty_briefing() -> void:
	var l := _level()
	l.briefing = []
	_expect_problem(l, "briefing needs at least one line")


func test_rejects_an_empty_loot_id() -> void:
	var l := _level()
	l.loot = [""]
	_expect_problem(l, "every loot id must be a non-empty string")


func test_rejects_a_hint_keyed_by_something_other_than_a_tape_number() -> void:
	var l := _level()
	l.hints = {7: "Too many"}
	_expect_problem(l, 'hint key "7" must be a tape number 1..4')


# ───────────────────────────── campaign ─────────────────────────────

func test_campaign_accepts_an_ordered_campaign_of_valid_levels() -> void:
	var a := _level()
	a.index = 1
	var b := _level()
	b.id = "lvl-b"
	b.index = 2
	var levels: Array[LevelDef] = [a, b]
	assert_eq(LevelValidator.validate_campaign(levels).size(), 0, "an ordered campaign of valid levels reports nothing")


func test_campaign_reports_duplicate_level_ids() -> void:
	var a := _level()
	a.id = "dup"
	a.index = 1
	var b := _level()
	b.id = "dup"
	b.index = 2
	var levels: Array[LevelDef] = [a, b]
	var messages := LevelValidator.validate_campaign(levels)
	assert_true(_contains(messages, 'duplicate level id "dup"'), "a repeated id is reported")


func test_campaign_reports_index_values_that_are_not_1_to_n_in_order() -> void:
	var a := _level()
	a.index = 1
	var b := _level()
	b.id = "lvl-b"
	b.index = 3
	var levels: Array[LevelDef] = [a, b]
	assert_eq(
		Array(LevelValidator.validate_campaign(levels)),
		["lvl-b: index is 3, expected 2 (campaign order is index 1..2)"],
		"the index mismatch is the only message",
	)


func test_campaign_prefixes_every_level_problem_with_the_level_id() -> void:
	var a := _level()
	a.index = 1
	var b := _level()
	b.id = "lvl-b"
	b.index = 2
	b.bpm = 7.0
	var levels: Array[LevelDef] = [a, b]
	var messages := LevelValidator.validate_campaign(levels)
	var prefixed := false
	for m: String in messages:
		if m.begins_with("lvl-b: 3600 / bpm must be an integer"):
			prefixed = true
	assert_true(prefixed, "a level problem carries its id as a prefix")


func test_campaign_reports_an_empty_campaign() -> void:
	var none: Array[LevelDef] = []
	assert_eq(Array(LevelValidator.validate_campaign(none)), ["campaign has no levels"], "an empty campaign is reported")


# ───────────────────────────── shipped content ─────────────────────────────

func test_shipped_campaign_validates_without_problems() -> void:
	# The shipped data (data/levels) is the reference content; it must pass the validator it is held to.
	var errors: Array[String] = []
	var levels := ContentData.load_campaign(errors)
	assert_eq(errors.size(), 0, "the campaign loads without parse errors: %s" % "; ".join(PackedStringArray(errors)))
	assert_false(levels.is_empty(), "the campaign has levels")
	var problems := PackedStringArray()
	for m: String in LevelValidator.validate_campaign(levels):
		if LevelValidator.is_problem(m):
			problems.append(m)
	assert_true(problems.is_empty(), "the shipped campaign has no validator problems:\n%s" % _listing(problems))
