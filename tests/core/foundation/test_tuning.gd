extends ODTest
## Port of prototype/tests/core/foundation/tuning.test.ts: the architecture combat targets and base stats.

var mods: StatMods = StatMods.new()
var run: float = Tuning.BASE.run_speed
var melee: MeleeWeaponDef = TestLoadout.base_melee()


func _dmg(swing: String, speed: float, vx: float) -> int:
	var s := melee.light if swing == "light" else melee.heavy
	var m := Tuning.swing_momentum(s, mods, speed, vx, 0.0, 0.0)
	return Tuning.strike_damage(m, melee.damage_eff, mods.damage)


func _heavy_m(speed: float, vx: float) -> float:
	return Tuning.swing_momentum(melee.heavy, mods, speed, vx, 0.0, 0.0)

# ── architecture combat targets ──


func test_a_1x_standing_light_kills_a_1_hit_enemy_a_0_5x_one_does_not_even_running() -> void:
	assert_true(_dmg("light", 1, 0) >= Tuning.enemy_stats(EnemyType.GRUNT).hp)
	assert_eq(_dmg("light", 0.5, 0), 0)
	assert_eq(_dmg("light", 0.5, run), 0)


func test_a_2x_running_heavy_breaks_the_tutorial_wall_slower_or_standing_heavies_do_not() -> void:
	assert_true(_heavy_m(2, run) >= Tuning.TUTORIAL_WALL_THRESHOLD)
	assert_true(_heavy_m(1, run) < Tuning.TUTORIAL_WALL_THRESHOLD)
	assert_true(_heavy_m(2, 0) < Tuning.TUTORIAL_WALL_THRESHOLD)


func test_tape_speed_is_counted_once_momentum_is_linear_in_speed() -> void:
	var m1 := Tuning.swing_momentum(melee.light, mods, 1, run, 0, 0)
	assert_near(Tuning.swing_momentum(melee.light, mods, 2, run, 0, 0), 2 * m1, 5e-13)
	assert_near(Tuning.swing_momentum(melee.light, mods, 4, run, 0, 0), 4 * m1, 5e-13)


func test_mom_03_direction_matters_approach_is_clamped() -> void:
	assert_eq(Tuning.strike_approach(run, 0, 0), 1)
	assert_eq(Tuning.strike_approach(2 * run, 0, 0), 1)
	assert_eq(Tuning.strike_approach(-run, 0, 0), -0.5)
	assert_near(Tuning.strike_approach(0, run, 0), 0, 5e-13)
	var into := Tuning.swing_momentum(melee.heavy, mods, 1, run, 0, 0)
	var away := Tuning.swing_momentum(melee.heavy, mods, 1, -run, 0, 0)
	assert_true(into > away)
	assert_true(away > 0)


func test_knockback_divides_by_mass_and_is_capped_stagger_divides_by_poise_immovables_ignore_both() -> void:
	assert_eq(Tuning.strike_knockback(2, 1, 1, 1, 1), 2)
	assert_eq(Tuning.strike_knockback(2, 1, 1, 1, 4), 0.5)
	assert_eq(Tuning.strike_knockback(100, 1, 1, 1, 1), Tuning.BASE.knockback_cap)
	assert_eq(Tuning.strike_knockback(100, 1, 1, 2, 1), Tuning.BASE.knockback_cap * 2)
	assert_eq(Tuning.strike_knockback(5, 1, 1, 1, Tuning.enemy_stats(EnemyType.TURRET).mass), 0)
	assert_eq(Tuning.strike_stagger(4, 1, 1, 2), 2)
	assert_eq(Tuning.strike_stagger(4, 1, 1, INF), 0)
	assert_eq(Tuning.strike_damage(-3, 1, 1), 0)


func test_the_brute_takes_several_standing_lights_but_one_1x_running_heavy() -> void:
	assert_true(_dmg("light", 1, 0) < Tuning.enemy_stats(EnemyType.BRUTE).hp)
	assert_true(_dmg("heavy", 1, run) >= Tuning.enemy_stats(EnemyType.BRUTE).hp)

# ── base stats ──


func test_fit_comfortably_through_1_tile_corridors_and_spark_outruns_a_1x_runner() -> void:
	var b := Tuning.BASE
	assert_true(b.actor_radius * 2 < 1)
	assert_true(b.spark_speed > b.run_speed)
	assert_true(b.dodge_iframe_start + b.dodge_iframes <= b.dodge_ticks)


func test_neutral_mods_is_a_fresh_identity_copy() -> void:
	var m := Tuning.neutral_mods()
	m.move_speed = 3
	assert_eq(Tuning.neutral_mods().move_speed, 1)
	assert_eq(m.interact_radius_add, 0)
	var n := Tuning.neutral_mods()
	for k: String in StatMods.keys():
		assert_eq(n.get_stat(k), 0.0 if k.ends_with("Add") else 1.0, k)


func test_enemy_roster_covers_every_enemy_type() -> void:
	for t: StringName in EnemyType.ALL:
		assert_true(Tuning.enemy_stats(t) != null, String(t))
	assert_eq(Tuning.ENEMY_STATS.keys(), EnemyType.ALL)
	assert_true(is_inf(Tuning.enemy_stats(EnemyType.TURRET).poise))
	assert_eq(Tuning.enemy_stats(EnemyType.BOSS).hp, 40)
