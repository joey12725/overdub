extends ODTest
## Level validation of trap entities (port of prototype/tests/core/traps/validate.test.ts;
## content/validate.gd, docs/TRAPS.md JSON shapes). Levels are written as plain JSON, the way a level
## file is, and checked with LevelValidator.validate_json (typed rules plus the raw-only ones).

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

const TRAPS_JSON := """[
  { "kind": "enemy", "id": "g1", "type": "grunt", "x": 9.5, "y": 2.5 },
  { "kind": "switch", "id": "lever", "x": 2.5, "y": 2.5 },
  { "kind": "spikes", "id": "sp1", "cells": [ { "c": 4, "r": 3 }, { "c": 5, "r": 3 } ],
    "upWhen": { "beat": { "every": 4, "from": 2, "to": 3 } } },
  { "kind": "crusher", "id": "cr1", "cells": [ { "c": 6, "r": 1 }, { "c": 6, "r": 2 }, { "c": 6, "r": 3 } ], "dir": "s",
    "extendWhen": { "sig": "slam" } },
  { "kind": "conveyor", "id": "belt1", "cells": [ { "c": 2, "r": 5 }, { "c": 3, "r": 5 }, { "c": 4, "r": 5 } ],
    "dir": "e", "speed": 2, "reverseWhen": { "sig": "lever" } },
  { "kind": "flame", "id": "fl1", "c": 0, "r": 7, "dir": "e", "range": 5,
    "onWhen": { "and": [ { "beat": { "every": 2, "from": 1, "to": 2 } }, { "not": { "sig": "belt1.rev" } } ] } },
  { "kind": "dart", "id": "d1", "c": 11, "r": 4, "dir": "w", "every": 2, "offset": 0.5 },
  { "kind": "bumper", "id": "bm1", "c": 7, "r": 6, "dir": "n", "power": 3,
    "fireWhen": { "beat": { "every": 4, "from": 3, "to": 3.5 } } },
  { "kind": "sensor", "id": "trip1", "from": { "x": 3.5, "y": 4.0 }, "to": { "x": 3.5, "y": 7.0 }, "detects": "enemies" },
  { "kind": "relay", "id": "slam", "trigger": { "sig": "trip1" }, "mode": "pulse", "quantize": 1, "delay": 1, "hold": 1 },
  { "kind": "door", "id": "gate", "cells": [ { "c": 9, "r": 8 } ], "openWhen": { "or": [ { "sig": "slam.armed" }, { "sig": "bm1" } ] } },
  { "kind": "magnet", "id": "mag1", "x": 8.5, "y": 4.5, "radius": 4, "pull": 1.5, "onWhen": { "sig": "lever" } }
]"""


func _traps() -> Array:
	return JSON.parse_string(TRAPS_JSON)


## A valid level (prototype tests/helpers makeLevel + the trap fixture) as plain JSON.
func _level(entities: Array) -> Dictionary:
	return {
		"id": "test-level", "index": 0, "name": "Test Level", "tagline": "A level built by a test.",
		"theme": "upper", "bpm": 120, "bars": 4, "horizonBars": 8, "maxTapes": 4,
		"speeds": [0.5, 1, 2, 4], "endModes": ["stop", "repeat", "reverse"], "map": OPEN_ROOM,
		"start": {"x": 1.5, "y": 1.5}, "startFacing": 0, "entities": entities,
		"objective": {"type": "eliminate", "text": "Test objective"},
		"music": {"root": 9, "scale": "Minor", "progression": [0, 5, 2, 6], "chordBars": 1, "tracks": [
			{"role": "bass", "formula": "triangular"}, {"role": "drums", "formula": "ruler"},
			{"role": "melody", "formula": "recaman"}, {"role": "chord", "formula": "squares"}]},
		"loot": [], "briefing": ["Mind the machines."],
	}


func _problems(entities: Array) -> Array[String]:
	var out: Array[String] = []
	for m: String in LevelValidator.validate_json(_level(entities)):
		if LevelValidator.is_problem(m):
			out.append(m)
	return out


## The valid fixture with one entity patched: keys in `patch` replace (null erases the key).
func _with_patch(id: String, patch: Dictionary) -> Array:
	var out := _traps()
	for e: Dictionary in out:
		if e.get("id") == id:
			for k: String in patch:
				if patch[k] == null:
					e.erase(k)
				else:
					e[k] = patch[k]
	return out


func _expect_problem(entities: Array, pattern: String) -> void:
	var re := RegEx.create_from_string(pattern)
	var list := _problems(entities)
	for p: String in list:
		if re.search(p) != null:
			assert_true(true)
			return
	fail("expected a problem matching /%s/; got:\n%s" % [pattern, "\n".join(list) if not list.is_empty() else "(none)"])


func test_accepts_a_level_that_uses_every_trap_kind_and_their_secondary_signals() -> void:
	assert_eq(_problems(_traps()), [] as Array[String])
	# The typed model agrees with the raw JSON.
	var errors: Array[String] = []
	var lv := LevelDef.from_dict(_level(_traps()), errors)
	assert_eq(errors, [] as Array[String])
	var typed: Array[String] = []
	for m: String in LevelValidator.validate_level(lv):
		if LevelValidator.is_problem(m):
			typed.append(m)
	assert_eq(typed, [] as Array[String])


func test_puts_trap_ids_in_the_one_id_namespace_and_makes_them_signals() -> void:
	_expect_problem(_with_patch("sp1", {"id": "lever"}), 'duplicate id "lever"')
	_expect_problem(_with_patch("cr1", {"extendWhen": {"sig": "nope"}}), 'signal "nope" is not produced')
	_expect_problem(_with_patch("gate", {"openWhen": {"sig": "lever.rev"}}), 'signal "lever\\.rev" is not produced')


func test_requires_each_traps_driving_expression() -> void:
	_expect_problem(_with_patch("sp1", {"upWhen": null}), 'spikes "sp1": upWhen is required')
	_expect_problem(_with_patch("cr1", {"extendWhen": null}), 'crusher "cr1": extendWhen is required')
	_expect_problem(_with_patch("fl1", {"onWhen": null}), 'flame "fl1": onWhen is required')
	_expect_problem(_with_patch("bm1", {"fireWhen": null}), 'bumper "bm1": fireWhen is required')
	_expect_problem(_with_patch("slam", {"trigger": null}), 'relay "slam": trigger is required')
	_expect_problem(_with_patch("mag1", {"onWhen": null}), 'magnet "mag1": onWhen is required')
	_expect_problem(_with_patch("sp1", {"upWhen": {"beat": {"every": 4, "from": 3, "to": 2}}}), "beat window")


func test_checks_cells_on_the_floor_in_the_map_not_repeated_and_crushers_in_one_straight_line() -> void:
	_expect_problem(_with_patch("sp1", {"cells": []}), 'spikes "sp1": needs at least one cell')
	_expect_problem(_with_patch("sp1", {"cells": [{"c": 0, "r": 3}]}), "not a floor tile")
	_expect_problem(_with_patch("belt1", {"cells": [{"c": 2, "r": 5}, {"c": 2, "r": 5}]}), "listed twice")
	_expect_problem(_with_patch("cr1", {"cells": [{"c": 6, "r": 1}, {"c": 6, "r": 3}]}), "straight, contiguous line")
	_expect_problem(_with_patch("cr1", {"cells": [{"c": 6, "r": 1}, {"c": 7, "r": 2}]}), "straight, contiguous line")
	_expect_problem(_with_patch("cr1", {"cells": [{"c": 9, "r": 8}]}), 'crusher "cr1" and door "gate" share tile')
	var more := _traps()
	more.append({"kind": "conveyor", "id": "belt2", "cells": [{"c": 4, "r": 5}], "dir": "n"})
	_expect_problem(more, "share tile \\(4,5\\); a tile belongs to one belt")


func test_lets_an_enemy_start_on_a_crusher_cell() -> void:
	var more := _traps()
	more.append({"kind": "enemy", "id": "g2", "type": "grunt", "x": 6.5, "y": 2.5})
	assert_eq(_problems(more), [] as Array[String])


func test_checks_directions_numbers_and_beat_grids() -> void:
	_expect_problem(_with_patch("belt1", {"dir": "north"}), "dir must be one of n, e, s, w")
	_expect_problem(_with_patch("belt1", {"speed": 0}), "speed must be a positive number")
	_expect_problem(_with_patch("fl1", {"range": 2.5}), "range must be a positive integer")
	_expect_problem(_with_patch("fl1", {"dir": "w"}), "tile in front of it \\(-1,7\\) is a wall or outside the map")
	_expect_problem(_with_patch("d1", {"c": 12}), "outside the map")
	_expect_problem(_with_patch("d1", {"every": 0}), "every must be a positive number")
	_expect_problem(_with_patch("d1", {"offset": 0.01}), "not a whole number of local ticks")
	_expect_problem(_with_patch("bm1", {"power": -1}), "power must be a positive number")
	_expect_problem(_with_patch("bm1", {"c": 0}), "not a floor tile")
	_expect_problem(_with_patch("slam", {"mode": "blink"}), "mode must be pulse, latch or toggle")
	_expect_problem(_with_patch("slam", {"hold": 0}), "hold must be a positive number of beats")
	_expect_problem(_with_patch("slam", {"delay": -1}), "delay must be a non-negative number of beats")
	_expect_problem(_with_patch("slam", {"x": 3}), "give both x and y")
	_expect_problem(_with_patch("mag1", {"radius": 0}), "radius must be a positive number")
	_expect_problem(_with_patch("sp1", {"damage": 0.5}), "damage must be a positive integer")


func test_checks_sensor_geometry_and_options() -> void:
	_expect_problem(_with_patch("trip1", {"to": {"x": 3.5, "y": 4.0}}), "from and to must differ")
	_expect_problem(_with_patch("trip1", {"from": {"x": 0.5, "y": 4.5}}), "inside a wall tile")
	_expect_problem(_with_patch("trip1", {"detects": "ghosts"}), "detects must be any, selves or enemies")
	_expect_problem(_with_patch("trip1", {"latch": "yes"}), "latch must be a boolean")
