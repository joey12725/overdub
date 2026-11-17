extends ODTest
## Stalker (AI-01, AI-02, AI-07): hunts the FARTHEST effective self; fast; one hit.
## bpm 120 -> 120 substeps per beat; a 1x tape advances 4 substeps per local tick.
## Port of prototype/tests/core/enemies/stalker.test.ts.

const K = preload("res://tests/core/enemies/test_enemy_kit.gd")
const SPB: int = 120


## Wakes at beat 1, by which time the selves have spread out (they all start together; REC-02).
func _stalker(o: Dictionary = {}) -> EnemyDef:
	var opts := {"wake": SignalExpr.of_beat(1000, 1, 1000)}
	opts.merge(o, true)
	return K.enemy("s1", EnemyType.STALKER, 6, 5, opts)


func _level() -> LevelDef:
	return K.make_level({"speeds": [1.0], "bars": 4, "start": Vector2(2, 5), "entities": [_stalker()]})


# A stays at the start, 4 tiles from the stalker. B runs to the far corner (5 tiles away).
func _tape_a() -> ODTape:
	return K.path_tape(0, 1.0, 480, [[0, 2, 5]])


func _tape_b() -> ODTape:
	return K.path_tape(1, 1.0, 480, [[0, 2, 5], [20, 10, 8]])


func test_AI01_alone_with_one_self_it_hunts_that_self() -> void:
	var res := K.resolve(_level(), [_tape_a()])
	var f := K.frame_at(res, SPB + 40)
	assert_eq(f.enemies[0].target, 0)
	assert_true(f.enemies[0].x < 6.0)


func test_AI02_a_self_far_away_drags_it_across_the_room_past_a_nearer_self() -> void:
	var solo := K.resolve(_level(), [_tape_a()])
	var both := K.resolve(_level(), [_tape_a(), _tape_b()])
	assert_eq(K.frame_at(both, SPB + 40).enemies[0].target, 1)
	# It heads for B (east and south) instead of toward A (west), and A's path is unchanged.
	assert_true(K.frame_at(both, 2 * SPB).enemies[0].x > 7.0, "heads for B")
	assert_true(K.frame_at(solo, 2 * SPB).enemies[0].x < 5.0, "alone it heads for A")
	assert_eq(both.frames.size(), solo.frames.size())
	var same := true
	for i: int in range(mini(both.frames.size(), solo.frames.size())):
		var a: ActorSnap = both.frames[i].actors[0]
		var b: ActorSnap = solo.frames[i].actors[0]
		if a.x != b.x or a.y != b.y:
			same = false
	assert_true(same, "A's path is unchanged")
	# B is the one it kills first.
	var deaths := K.events_of(both.events, SimEventType.SELF_DEATH)
	assert_eq(deaths[0].tape, 1)
	assert_eq(deaths[0].detail, "struck by stalker s1")


func test_AI07_strikes_land_on_its_beat_grid_then_it_repicks_the_farthest_survivor() -> void:
	var both := K.resolve(_level(), [_tape_a(), _tape_b()])
	var attacks := K.events_of(both.events, SimEventType.ENEMY_ATTACK, -1, "s1")
	assert_true(attacks.size() >= 2, "at least two strikes")
	for a: SimEvent in attacks:
		assert_eq(a.sub % (2 * SPB), SPB, "on beats 1, 3, 5 ...")
	var tel := K.events_of(both.events, SimEventType.ENEMY_TELEGRAPH, -1, "s1")
	assert_eq(tel[0].sub, attacks[0].sub - SPB / 2)
	assert_eq(tel[0].tape, 1)
	# After killing B it hunts the only one left.
	var later: SimEvent = null
	for t: SimEvent in tel:
		if t.sub > attacks[0].sub:
			later = t
			break
	assert_true(later != null and later.tape == 0, "re-picks A")
	var tapes: Array[int] = []
	for d: SimEvent in K.events_of(both.events, SimEventType.SELF_DEATH):
		tapes.append(d.tape)
	assert_eq(tapes, [1, 0])


func test_AI01_ties_go_to_the_lowest_tape_index() -> void:
	var twin := K.path_tape(2, 1.0, 480, [[0, 2, 5]])
	var res := K.resolve(_level(), [twin, _tape_a()])
	assert_eq(K.frame_at(res, SPB + 8).enemies[0].target, 0)


func test_HEALTH02_one_hit_kills_it() -> void:
	var lvl := K.make_level({"speeds": [1.0], "bars": 1, "start": Vector2(5, 5), "entities": [_stalker({"wake": SignalExpr.of_const(false)})]})
	var swing := K.path_tape(0, 1.0, 120, [[0, 5, 5]], [[10, ActionKind.LIGHT, 0.0]])
	var res := K.resolve(lvl, [swing])
	assert_eq(K.events_of(res.events, SimEventType.KILL, -1, "s1").size(), 1)
