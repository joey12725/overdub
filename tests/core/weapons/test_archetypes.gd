extends ODTest
## Ranged weapon archetypes (WEAPON-01..03, NEW-02, NEW-04, NEW-05): fixed trigger, simulated
## projectile. Every scene uses a stationary shooter built with path_tape and sleeping enemies, so the
## only thing that changes between runs is the weapon data.
## Port of prototype/tests/core/weapons/archetypes.test.ts.

var SLEEP: SignalExpr = SignalExpr.of_const(false)

## Launch substep of the tick-10 shot at 1x (commit ≥ 5 ⇒ launch delay = BASE.rangedLaunchDelay).
var LAUNCH: int = (10 + Tuning.BASE.ranged_launch_delay) * 4

## RangedWeaponDef patches (TestLoadout.base_loadout "ranged"); an optional field the prototype
## writes (radius, minRange) also sets its has_ flag.
var WEAPONS: Dictionary = {
	RangedArchetype.MISSILE: {"archetype": RangedArchetype.MISSILE, "speed": 2.5, "range": 14.0, "turn_rate": 2.5, "pierce": 0},
	RangedArchetype.PIERCE: {"archetype": RangedArchetype.PIERCE, "speed": 24.0, "range": 12.0, "pierce": 3, "radius": 0.12, "has_radius": true, "turn_rate": 0.0},
	RangedArchetype.PHASE: {"archetype": RangedArchetype.PHASE, "speed": 6.0, "range": 9.0, "passes_walls": true, "pierce": 0, "turn_rate": 0.0},
	RangedArchetype.ARC: {"archetype": RangedArchetype.ARC, "speed": 7.0, "range": 6.0, "lobbed": true, "blast": 1.2, "pierce": 0, "turn_rate": 0.0},
	RangedArchetype.BURST: {"archetype": RangedArchetype.BURST, "speed": 16.0, "range": 8.0, "count": 5, "spread_deg": 40.0, "pierce": 0, "turn_rate": 0.0, "radius": 0.2, "has_radius": true},
}

# ───────────────────────────── helpers ─────────────────────────────


func _grunt(id: String, x: float, y: float, hp: int = 1) -> EnemyDef:
	return TestScript.enemy(id, EnemyType.GRUNT, x, y, {"hp": hp, "wake": SLEEP})


func _level(entities: Array, map: Array[String] = TestLevels.OPEN_ROOM) -> LevelDef:
	return TestLevels.make_level({"speeds": [1.0], "bars": 4, "map": map, "start": Vector2(2.5, 5.5), "entities": entities})


## Shooter standing at (x, y) firing once at local tick 10 along `dir`.
func _shooter(dir: float = 0.0, speed: float = 1.0, x: float = 2.5, y: float = 5.5) -> ODTape:
	return TestScript.path_tape(0, speed, 480, [[0, x, y]], [[10, ActionKind.RANGED, dir]])


## A weapon patch with some fields overridden (the prototype's `{ ...WEAPONS.x, ... }`).
func _w(arch: StringName, over: Dictionary = {}) -> Dictionary:
	var d: Dictionary = (WEAPONS[arch] as Dictionary).duplicate()
	d.merge(over, true)
	return d


func _fire(lv: LevelDef, ranged: Dictionary, dir: float = 0.0, speed: float = 1.0) -> Resolution:
	return TestScript.resolve(lv, [_shooter(dir, speed)], TestLoadout.base_loadout({"ranged": ranged}))


func _hits_on(res: Resolution, id: String) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e: SimEvent in TestScript.events_of(res.events, SimEventType.HIT, -1, id):
		if e.tape == 0:
			out.append(e)
	return out


func _proj_hits(res: Resolution, detail: String) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e: SimEvent in TestScript.events_of(res.events, SimEventType.PROJECTILE_HIT):
		if e.detail == detail:
			out.append(e)
	return out


func _walled() -> Array[String]:
	# A full-height wall at column 5 between the shooter (x 2.5) and the enemy (x 8.5).
	var map: Array[String] = []
	var n := TestLevels.OPEN_ROOM.size()
	for r in n:
		var row: String = TestLevels.OPEN_ROOM[r]
		map.append(row if r == 0 or r == n - 1 else row.substr(0, 5) + "#" + row.substr(6))
	return map


func _doorway() -> Array[String]:
	var map: Array[String] = []
	var n := TestLevels.OPEN_ROOM.size()
	for r in n:
		var row: String = TestLevels.OPEN_ROOM[r]
		map.append(row if r == 0 or r == n - 1 else row.substr(0, 5) + ("." if r == 5 else "#") + row.substr(6))
	return map

# ───────────────────────────── launch ─────────────────────────────


func test_launch_every_archetype_launches_through_the_ranged_hook_and_announces_fire() -> void:
	for arch: StringName in RangedArchetype.SELF:
		var res := _fire(_level([]), WEAPONS[arch])
		var fires := TestScript.events_of(res.events, SimEventType.FIRE)
		var got: Array = []
		for e: SimEvent in fires:
			got.append([e.sub, e.tape, e.detail])
		assert_eq(got, [[LAUNCH, 0, String(arch)]], "%s fire events" % arch)
		if fires.size() > 0:
			assert_eq(fires[0].power, 5.0 if arch == RangedArchetype.BURST else 1.0, "%s fire power" % arch)
		var after := TestScript.frame_exact(res.frames, LAUNCH + 4)
		assert_true(after != null, "frame at LAUNCH + 4")
		if after == null:
			continue
		assert_eq(after.projectiles.size(), 5 if arch == RangedArchetype.BURST else 1, "%s projectile count" % arch)
		for p: ProjectileSnap in after.projectiles:
			assert_eq(p.owner_tape, 0, "%s owner" % arch)
			assert_eq(p.archetype, arch, "%s archetype" % arch)

# ───────────────────────────── NEW-02: the missile is very slow ─────────────────────────────


func _first_hit(lv: LevelDef, w: Dictionary) -> float:
	var h := _hits_on(_fire(lv, w), "g1")
	return float(h[0].sub) if h.size() > 0 else INF


func test_new02_a_missile_reaches_the_same_target_much_later_than_direct_fire() -> void:
	var lv := _level([_grunt("g1", 8.5, 5.5)])
	var missile := _first_hit(lv, WEAPONS[RangedArchetype.MISSILE])
	var pierce := _first_hit(lv, WEAPONS[RangedArchetype.PIERCE])
	var burst := _first_hit(lv, WEAPONS[RangedArchetype.BURST])
	assert_true(missile < INF, "missile hits")
	assert_true(pierce < missile, "pierce before missile")
	assert_true(burst < missile, "burst before missile")
	# ~5.5 tiles at 2.5 tiles/s is over two master seconds; the needle covers it in about a quarter second.
	assert_true(missile - LAUNCH > 2 * 240, "missile flight > 2 s")
	assert_true(pierce - LAUNCH < 0.3 * 240, "pierce flight < 0.3 s")


func test_new02_projectile_speed_is_master_time_across_tape_speeds() -> void:
	var lv := TestLevels.make_level({"speeds": [0.5, 1.0, 2.0], "bars": 2, "start": Vector2(2.5, 5.5), "entities": [_grunt("g1", 8.5, 5.5, 5)]})
	var travel := func(speed: float) -> Array:
		var tape := TestScript.path_tape(0, speed, 240, [[0, 2.5, 5.5]], [[10, ActionKind.RANGED, 0.0]])
		var res := TestScript.resolve(lv, [tape], TestLoadout.base_loadout({"ranged": _w(RangedArchetype.PIERCE, {"pierce": 0, "impact": 2.4})}))
		var fire_sub: int = TestScript.events_of(res.events, SimEventType.FIRE)[0].sub
		var hit: SimEvent = _hits_on(res, "g1")[0]
		return [hit.sub - fire_sub, hit.power]
	var a: Array = travel.call(0.5)
	var b: Array = travel.call(1.0)
	var c: Array = travel.call(2.0)
	assert_eq(a, b, "0.5x flies like 1x")
	assert_eq(c, b, "2x flies like 1x")
	# Tape speed is not multiplied into a projectile's momentum (weapons/common.gd).
	assert_eq(b[1], 2.4, "power")


func test_new02_statmods_projectile_speed_scales_flight_speed() -> void:
	var lv := _level([_grunt("g1", 8.5, 5.5)])
	var base: int = _hits_on(TestScript.resolve(lv, [_shooter()], TestLoadout.base_loadout({"ranged": WEAPONS[RangedArchetype.MISSILE]})), "g1")[0].sub - LAUNCH
	var fast: int = _hits_on(TestScript.resolve(lv, [_shooter()], TestLoadout.base_loadout({"ranged": WEAPONS[RangedArchetype.MISSILE], "mods": {"projectileSpeed": 2.0}})), "g1")[0].sub - LAUNCH
	assert_true(fast < base * 0.6, "fast %d < 0.6 * base %d" % [fast, base])

# ───────────────────────────── momentum model ─────────────────────────────


func test_momentum_a_hit_delivers_impact_through_the_melee_arithmetic_with_ranged_efficiencies() -> void:
	var lv := _level([_grunt("g1", 6.5, 5.5, 5)])
	# A heavy-handed melee weapon must not change what the gun does.
	var res := TestScript.resolve(lv, [_shooter()], TestLoadout.base_loadout({"ranged": _w(RangedArchetype.PIERCE, {"pierce": 0, "impact": 2.4}), "melee": {"damage_eff": 3.0, "knockback_eff": 3.0}}))
	var hit: SimEvent = _hits_on(res, "g1")[0]
	assert_eq(hit.power, 2.4, "power")
	var last: EnemySnap = res.frames[res.frames.size() - 1].enemies[0]
	assert_eq(last.hp, 5 - 2, "hp after floor(2.4) damage")
	assert_near(last.x, 6.5 + 2.4, 5e-4, "knockback = 2.4 / mass 1, along the shot")
	assert_eq(TestScript.events_of(res.events, SimEventType.ENEMY_STAGGER, -1, "g1").size(), 1, "one stagger")
	# The loadout's damage modifier applies to shots too.
	var strong := TestScript.resolve(lv, [_shooter()], TestLoadout.base_loadout({"ranged": _w(RangedArchetype.PIERCE, {"pierce": 0, "impact": 2.4}), "mods": {"damage": 1.5}}))
	assert_eq(strong.frames[strong.frames.size() - 1].enemies[0].hp, 5 - 3, "hp after floor(3.6) damage")

# ───────────────────────────── NEW-04: piercing ─────────────────────────────


func _pierce_level() -> LevelDef:
	return _level([_grunt("g1", 5.5, 5.5, 5), _grunt("g2", 7.5, 5.5, 5), _grunt("g3", 9.5, 5.5, 5)])


func test_new04_a_piercing_shot_strikes_successive_enemies_each_exactly_once() -> void:
	var res := _fire(_pierce_level(), WEAPONS[RangedArchetype.PIERCE])
	var subs: Array[int] = []
	for id: String in ["g1", "g2", "g3"]:
		var h := _hits_on(res, id)
		assert_eq(h.size(), 1, "%s hit once" % id)
		if h.size() > 0:
			assert_eq(h[0].detail, "pierce", "%s detail" % id)
			subs.append(h[0].sub)
	if subs.size() == 3:
		assert_true(subs[0] < subs[1] and subs[1] < subs[2], "hits in line order %s" % [subs])
	var passes: Array = []
	for e: SimEvent in _proj_hits(res, "pierce:pass"):
		passes.append(e.id)
	assert_eq(passes, ["g1", "g2", "g3"], "pass-throughs")
	# Three pass-throughs left nothing to stop it, so it ends at the far wall.
	assert_eq(_proj_hits(res, "pierce:wall").size(), 1, "ends at the wall")


func test_new04_pierce_n_passes_through_n_enemies_and_stops_at_the_next() -> void:
	var res := _fire(_pierce_level(), _w(RangedArchetype.PIERCE, {"pierce": 1}))
	assert_eq(_hits_on(res, "g1").size(), 1, "g1")
	assert_eq(_hits_on(res, "g2").size(), 1, "g2")
	assert_eq(_hits_on(res, "g3").size(), 0, "g3")


func test_new04_a_normal_projectile_does_not_inherit_piercing() -> void:
	var lv := _pierce_level()
	for w: Dictionary in [WEAPONS[RangedArchetype.MISSILE], _w(RangedArchetype.BURST, {"count": 1}), WEAPONS[RangedArchetype.PHASE]]:
		var res := _fire(lv, w)
		assert_eq(_hits_on(res, "g1").size(), 1, "%s g1" % w["archetype"])
		assert_eq(_hits_on(res, "g2").size(), 0, "%s g2" % w["archetype"])
		assert_eq(_hits_on(res, "g3").size(), 0, "%s g3" % w["archetype"])

# ───────────────────────────── NEW-05: walls and cover ─────────────────────────────


func test_new05_only_phase_passes_walls_and_only_arc_flies_over_them() -> void:
	var lv := _level([_grunt("g1", 8.5, 5.5)], _walled())
	for arch: StringName in [RangedArchetype.MISSILE, RangedArchetype.PIERCE, RangedArchetype.BURST]:
		var res := _fire(lv, WEAPONS[arch])
		assert_eq(_hits_on(res, "g1").size(), 0, "%s stopped" % arch)
		assert_true(_proj_hits(res, "%s:wall" % arch).size() > 0, "%s hits the wall" % arch)
	var phase := _fire(lv, WEAPONS[RangedArchetype.PHASE])
	assert_eq(_hits_on(phase, "g1").size(), 1, "phase hits")
	assert_eq(TestScript.events_of(phase.events, SimEventType.KILL, -1, "g1").size(), 1, "phase kills")
	var arc := _fire(lv, WEAPONS[RangedArchetype.ARC])
	assert_eq(_hits_on(arc, "g1").size(), 1, "arc hits")
	assert_eq(_proj_hits(arc, "arc:land").size(), 1, "arc lands")


func test_new05_a_weapon_only_passes_walls_when_its_own_data_says_so() -> void:
	var lv := _level([_grunt("g1", 8.5, 5.5)], _walled())
	assert_eq(_hits_on(_fire(lv, _w(RangedArchetype.PIERCE, {"passes_walls": true})), "g1").size(), 1, "pierce with passesWalls")


func test_new05_a_closed_door_stops_a_straight_shot_but_not_a_phase_shot() -> void:
	var map := _doorway()
	var cells: Array[Vector2i] = [Vector2i(5, 5)]
	var lv := _level([TestScript.door("d1", cells, SignalExpr.of_const(false)), _grunt("g1", 8.5, 5.5)], map)
	assert_eq(_hits_on(_fire(lv, WEAPONS[RangedArchetype.PIERCE]), "g1").size(), 0, "pierce stopped by the door")
	assert_eq(_hits_on(_fire(lv, WEAPONS[RangedArchetype.PHASE]), "g1").size(), 1, "phase passes the door")
	var open := _level([TestScript.door("d1", cells, SignalExpr.of_const(true)), _grunt("g1", 8.5, 5.5)], map)
	assert_eq(_hits_on(_fire(open, WEAPONS[RangedArchetype.PIERCE]), "g1").size(), 1, "pierce through the open door")


func test_new05_a_phase_shot_never_crosses_the_map_edge() -> void:
	var res := _fire(_level([]), _w(RangedArchetype.PHASE, {"range": 40.0}))
	var edge := _proj_hits(res, "phase:edge")
	assert_eq(edge.size(), 1, "one edge event")
	if edge.size() > 0:
		assert_true(edge[0].x > 11.99, "edge x > 11.99 (%f)" % edge[0].x)
		assert_true(edge[0].x <= 12.0, "edge x <= 12")
	var inside := true
	for f: FrameSnapshot in res.frames:
		for p: ProjectileSnap in f.projectiles:
			if p.x > 12.0:
				inside = false
	assert_true(inside, "no projectile beyond x 12")


func test_new05_a_phase_shot_stops_at_the_first_enemy_it_meets() -> void:
	var res := _fire(_level([_grunt("g1", 5.5, 5.5, 5), _grunt("g2", 7.5, 5.5, 5)]), WEAPONS[RangedArchetype.PHASE])
	assert_eq(_hits_on(res, "g1").size(), 1, "g1")
	assert_eq(_hits_on(res, "g2").size(), 0, "g2")

# ───────────────────────────── arc ─────────────────────────────


func _arc_land(res: Resolution) -> SimEvent:
	var l := _proj_hits(res, "arc:land")
	return l[0] if l.size() > 0 else null


func test_arc_flies_over_enemies_in_flight_and_bursts_at_its_landing_point() -> void:
	var lv := _level([_grunt("near", 4.5, 5.5), _grunt("far", 8.5, 5.5)])
	var arc := _fire(lv, WEAPONS[RangedArchetype.ARC])
	assert_eq(_hits_on(arc, "near").size(), 0, "flies over near")
	assert_eq(_hits_on(arc, "far").size(), 1, "bursts on far")
	var land := _arc_land(arc)
	assert_true(land != null, "lands")
	if land != null:
		assert_near(land.x, 8.5, 5e-6, "land x")
		assert_near(land.y, 5.5, 5e-6, "land y")
		assert_eq(land.power, 1.2, "land power = blast")
	# A straight, non-piercing shot is stopped by the first body instead.
	var straight := _fire(lv, _w(RangedArchetype.BURST, {"count": 1}))
	assert_eq(_hits_on(straight, "near").size(), 1, "straight hits near")
	assert_eq(_hits_on(straight, "far").size(), 0, "straight misses far")


func test_arc_reports_its_height_peaking_mid_way() -> void:
	var res := _fire(_level([]), WEAPONS[RangedArchetype.ARC])
	var zs: Array[float] = []
	for f: FrameSnapshot in res.frames:
		for p: ProjectileSnap in f.projectiles:
			if p.archetype == RangedArchetype.ARC:
				zs.append(p.z)
	assert_true(zs.size() > 10, "enough samples")
	var all_up := true
	for i in range(1, zs.size()):
		if not (zs[i] > 0.0):
			all_up = false
	assert_true(all_up, "above the floor in flight")
	var peak: float = zs.max()
	# toBeCloseTo(x, 1): |a - b| < 0.05.
	assert_near(peak, ArcArchetype.arc_height(0.5), 0.05, "peak")
	var i_peak := zs.find(peak)
	assert_true(i_peak > zs.size() * 0.3, "peak after 30%")
	assert_true(i_peak < zs.size() * 0.7, "peak before 70%")


func test_arc_lands_at_its_range_never_short_of_min_range_never_beyond_the_edge() -> void:
	var land_x := func(w: Dictionary) -> float:
		var l := _arc_land(_fire(_level([]), w))
		return l.x if l != null else NAN
	assert_near(land_x.call(_w(RangedArchetype.ARC, {"range": 5.0})), 7.5, 5e-6, "range 5")
	assert_near(land_x.call(_w(RangedArchetype.ARC, {"range": 2.0, "min_range": 4.0, "has_min_range": true})), 6.5, 5e-6, "minRange 4")
	var edge: float = land_x.call(_w(RangedArchetype.ARC, {"range": 30.0}))
	assert_true(edge < 12.0, "edge < 12 (%f)" % edge)
	assert_true(edge > 11.99, "edge > 11.99 (%f)" % edge)


func test_arc_the_landing_blast_strikes_every_enemy_it_overlaps_and_pushes_each_away() -> void:
	var lv := _level([_grunt("centre", 8.5, 5.5), _grunt("side", 8.5, 6.5, 5), _grunt("out", 8.5, 7.9)])
	var res := _fire(lv, WEAPONS[RangedArchetype.ARC])
	assert_eq(TestScript.events_of(res.events, SimEventType.KILL, -1, "centre").size(), 1, "centre killed")
	assert_eq(_hits_on(res, "side").size(), 1, "side struck")
	assert_eq(_hits_on(res, "out").size(), 0, "out untouched")
	var side: EnemySnap = null
	for e: EnemySnap in res.frames[res.frames.size() - 1].enemies:
		if e.id == "side":
			side = e
	assert_true(side.y > 6.5 + 0.5, "side pushed away (y %f)" % side.y)
	assert_near(side.x, 8.5, 5e-6, "side x unchanged")


func test_arc_a_wall_shields_an_enemy_from_the_blast() -> void:
	var map: Array[String] = []
	for r in TestLevels.OPEN_ROOM.size():
		var row: String = TestLevels.OPEN_ROOM[r]
		map.append(row.substr(0, 7) + "###" + row.substr(10) if r == 6 else row)
	var res := _fire(_level([_grunt("centre", 8.5, 5.5), _grunt("behind", 8.5, 7.1)], map), WEAPONS[RangedArchetype.ARC])
	assert_eq(_hits_on(res, "centre").size(), 1, "centre struck")
	assert_eq(_hits_on(res, "behind").size(), 0, "behind shielded")

# ───────────────────────────── burst ─────────────────────────────


func test_burst_fans_count_pellets_evenly_across_spread_around_the_recorded_direction() -> void:
	var res := _fire(_level([]), WEAPONS[RangedArchetype.BURST])
	var f := TestScript.frame_exact(res.frames, LAUNCH + 4)
	var degs: Array = []
	for p: ProjectileSnap in f.projectiles:
		# Math.round (JS rounds .5 up; no pellet sits on a .5 boundary here).
		degs.append(int(floor(p.dir * 180.0 / PI + 0.5)))
	assert_eq(degs, [-20, -10, 0, 10, 20], "pellet headings")


func test_burst_pellets_reach_the_fan_edges_but_fizzle_out_at_short_range() -> void:
	var a := 20.0 * PI / 180.0
	var lv := _level([
		_grunt("up", 2.5 + 2.5 * cos(a), 5.5 - 2.5 * sin(a), 9),
		_grunt("down", 2.5 + 2.5 * cos(a), 5.5 + 2.5 * sin(a), 9),
		_grunt("far", 9.5, 5.5, 9),
	])
	var res := _fire(lv, _w(RangedArchetype.BURST, {"range": 3.5}))
	assert_true(_hits_on(res, "up").size() > 0, "up struck")
	assert_true(_hits_on(res, "down").size() > 0, "down struck")
	assert_eq(_hits_on(res, "far").size(), 0, "far untouched")
	# Every pellet is gone well before the far enemy's distance.
	var within := true
	for fr: FrameSnapshot in res.frames:
		for p: ProjectileSnap in fr.projectiles:
			var dx := p.x - 2.5
			var dy := p.y - 5.5
			if sqrt(dx * dx + dy * dy) > 3.5 + 1e-6:
				within = false
	assert_true(within, "pellets stay within 3.5 tiles")
