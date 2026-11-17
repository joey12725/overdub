extends ODTest
## Port of prototype/tests/core/foundation/helpers.test.ts: the TestLevels / TestLoadout helpers.


func test_make_level_builds_a_valid_minimal_level_with_a_walkable_start() -> void:
	var level := TestLevels.make_level()
	assert_eq(level.bpm, 120)
	assert_eq(level.bars, 4)
	assert_eq(level.horizon_bars, 8)
	assert_eq(level.music.tracks.size(), 4)
	assert_eq(fmod(3600.0, level.bpm), 0.0, "3600 / bpm is an integer")
	var g := ODGrid.from_level(level)
	assert_true(g.is_walkable(floori(level.start.x), floori(level.start.y)))
	assert_eq(ODTime.tape_ticks(level), 480)
	assert_eq(ODTime.horizon_subs(level), 3840)
	assert_eq(level.speeds, OD.ALL_SPEEDS)
	assert_eq(level.end_modes, OD.ALL_END_MODES)
	assert_eq(level.objective.type, ObjectiveType.ELIMINATE)
	assert_eq(level.start, Vector2(6, 5))


func test_make_level_honours_overrides_and_derives_start_and_horizon() -> void:
	var level := TestLevels.make_level({"map": ["####", "#..#", "####"], "speeds": [1.0, 2.0], "bars": 2})
	assert_eq(level.start, Vector2(1.5, 1.5))
	assert_eq(level.horizon_bars, 2)
	assert_eq(TestLevels.make_level({"horizonBars": 3}).horizon_bars, 3)
	assert_eq(TestLevels.make_level({"horizon_bars": 5, "bpm": 80}).horizon_bars, 5)
	var door := DoorDef.new()
	door.id = "d1"
	var with_entities := TestLevels.make_level({"entities": [door], "start": Vector2(2.5, 3.5), "id": "custom"})
	assert_eq(with_entities.entities.size(), 1)
	assert_eq(with_entities.entities[0], door)
	assert_eq(with_entities.start, Vector2(2.5, 3.5))
	assert_eq(with_entities.id, "custom")


func test_base_loadout_is_neutral_and_patchable_without_sharing_state() -> void:
	var a := TestLoadout.base_loadout()
	assert_eq(a.mods.move_speed, 1)
	assert_eq(a.melee.light.windup, 6)
	assert_eq(a.ranged.archetype, RangedArchetype.MISSILE)
	var b := TestLoadout.base_loadout({"mods": {"damage": 2}, "melee": {"light": {"windup": 3, "active": 4, "recover": 10, "impact": 1.2, "moveMul": 0.5}}})
	assert_eq(b.mods.damage, 2)
	assert_eq(b.melee.light.windup, 3)
	assert_eq(b.melee.heavy.windup, 16, "the other swing keeps its baseline")
	a.melee.light.windup = 99
	assert_eq(TestLoadout.base_loadout().melee.light.windup, 6)
	var c := TestLoadout.base_loadout({"ranged": {"range": 9, "commit": 20}, "abilities": [AbilityId.PARRY], "mods": {"move_speed": 1.25}})
	assert_eq(c.ranged.max_range, 9)
	assert_eq(c.ranged.commit, 20)
	assert_eq(c.abilities, [AbilityId.PARRY])
	assert_eq(c.mods.move_speed, 1.25)
	assert_eq(c.loadout.ids(), ["base-helmet", "base-top", "base-pants", "base-shoes", "base-melee", "base-missile"])
