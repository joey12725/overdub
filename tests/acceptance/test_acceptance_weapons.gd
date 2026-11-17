extends ODTest
## Acceptance: weapon behaviour (docs/requirements.txt Revision 1 "Implementation / acceptance checks":
## NEW-01..06) on the shipped catalogue (data/gear.json via ContentData / LoadoutRules) and core.

const K = preload("res://tests/acceptance/acceptance_kit.gd")
const S = preload("res://tests/helpers/script.gd")


func _cat() -> ContentData.GearCatalogue:
	var errors: Array[String] = []
	var c := ContentData.load_gear(errors)
	assert_true(c != null, "data/gear.json loads: %s" % [errors])
	return c


## The baseline loadout with one slot swapped to a catalogue item (resolved by LoadoutRules).
func _with(cat: ContentData.GearCatalogue, slot: StringName, id: String) -> ResolvedLoadout:
	var lo := cat.base_loadout.copy()
	lo.set_slot(slot, id)
	return LoadoutRules.resolve_loadout(lo, cat)


func _open_room(ents: Array[EntityDef], start: Vector2, bars: int = 2, map: Array[String] = []) -> LevelDef:
	var p := {"speeds": [1.0], "bars": bars, "start": start, "entities": ents}
	if not map.is_empty():
		p["map"] = map
	return TestLevels.make_level(p)


## NEW-01: Equip at least two melee weapons with visibly different effective reach, attack timing,
## knockback or other meaningful properties; both remain viable.
func test_NEW01_melee_weapons_differ_in_reach_timing_and_knockback_and_each_is_viable() -> void:
	var cat := _cat()
	if cat == null:
		return
	var melee := cat.items_in_slot(GearSlot.MELEE)
	assert_true(melee.size() >= 2, K.say("NEW-01", "at least two melee weapons"))
	for i: int in melee.size():
		for j: int in range(i + 1, melee.size()):
			var a := melee[i].melee
			var b := melee[j].melee
			var differs := a.reach != b.reach or a.light.windup != b.light.windup or a.knockback_eff != b.knockback_eff or a.arc_deg != b.arc_deg
			assert_true(differs, K.say("NEW-01", "%s vs %s are the same weapon" % [melee[i].id, melee[j].id]))
	# Viable, in the shipped sim: equipped, each one kills a 1-hp grunt with one 1x standing light from
	# inside its own reach, and the reach difference is real (the long weapon lands where the short
	# one whiffs).
	var shortest: GearItem = melee[0]
	var longest: GearItem = melee[0]
	for it: GearItem in melee:
		if it.melee.reach < shortest.melee.reach:
			shortest = it
		if it.melee.reach > longest.melee.reach:
			longest = it
		var lo := _with(cat, GearSlot.MELEE, it.id)
		var d := it.melee.reach * 0.6
		var ents: Array[EntityDef] = [S.enemy("g1", EnemyType.GRUNT, 5.0 + d, 5.5, {"hp": 1, "wake": SignalExpr.of_const(false)})]
		var lv := _open_room(ents, Vector2(5.0, 5.5))
		var tape := S.path_tape(0, 1.0, 240, [[0, 5.0, 5.5]], [[10, ActionKind.LIGHT, 0.0]])
		var res := K.resolve(lv, [tape], lo)
		assert_eq(K.events_of(res.events, SimEventType.KILL, 0, "g1").size(), 1, K.say("NEW-01", "%s is viable (kills a 1-hp grunt with a 1x light)" % it.id))
	var gap := (shortest.melee.reach + longest.melee.reach) / 2.0 + 0.35
	var ents2: Array[EntityDef] = [S.enemy("g1", EnemyType.GRUNT, 5.0 + gap, 5.5, {"hp": 1, "wake": SignalExpr.of_const(false)})]
	var lv2 := _open_room(ents2, Vector2(5.0, 5.5))
	var t2 := S.path_tape(0, 1.0, 240, [[0, 5.0, 5.5]], [[10, ActionKind.LIGHT, 0.0]])
	var long_res := K.resolve(lv2, [t2], _with(cat, GearSlot.MELEE, longest.id))
	var short_res := K.resolve(lv2, [t2], _with(cat, GearSlot.MELEE, shortest.id))
	assert_eq(K.events_of(long_res.events, SimEventType.KILL, 0).size(), 1, K.say("NEW-01", "%s reaches %.2f tiles" % [longest.id, gap]))
	assert_eq(K.events_of(short_res.events, SimEventType.KILL, 0).size(), 0, K.say("NEW-01", "%s does not" % shortest.id))


## NEW-02: Equip at least two ranged weapon archetypes with different weaknesses; guided missile is
## slower than at least one alternative projectile.
func test_NEW02_ranged_archetypes_have_different_weaknesses_and_the_missile_is_slower() -> void:
	var cat := _cat()
	if cat == null:
		return
	var ranged := cat.items_in_slot(GearSlot.RANGED)
	var archetypes := {}
	for it: GearItem in ranged:
		archetypes[it.ranged.archetype] = it
	assert_true(archetypes.size() >= 2, K.say("NEW-02", "at least two ranged archetypes"))
	if not assert_true(archetypes.has(RangedArchetype.MISSILE) and archetypes.has(RangedArchetype.PIERCE) and archetypes.has(RangedArchetype.BURST)):
		return
	var missile: GearItem = archetypes[RangedArchetype.MISSILE]
	var pierce: GearItem = archetypes[RangedArchetype.PIERCE]
	var burst: GearItem = archetypes[RangedArchetype.BURST]
	assert_true(missile.ranged.speed < pierce.ranged.speed, K.say("NEW-02", "missile speed %s vs %s %s" % [missile.ranged.speed, pierce.id, pierce.ranged.speed]))
	# In the shipped sim, the same recorded launch at the same grunt 6 tiles away:
	var ents: Array[EntityDef] = [S.enemy("g1", EnemyType.GRUNT, 8.5, 5.5, {"hp": 5, "wake": SignalExpr.of_const(false)})]
	var lv := _open_room(ents, Vector2(2.5, 5.5), 4)
	var tape := S.path_tape(0, 1.0, 480, [[0, 2.5, 5.5]], [[10, ActionKind.RANGED, 0.0]])
	var delay := {}
	for it: GearItem in [missile, pierce, burst]:
		var res := K.resolve(lv, [tape], _with(cat, GearSlot.RANGED, it.id))
		var fire := K.first_event(res.events, SimEventType.FIRE, 0)
		var hit := K.first_event(res.events, SimEventType.HIT, 0, "g1")
		delay[it.id] = (hit.sub - fire.sub) if fire != null and hit != null else -1
	# The missile's weakness: very long travel time.
	assert_true(delay[missile.id] > 0 and delay[pierce.id] > 0, K.say("NEW-02", "missile and pierce both reach the grunt: %s" % [delay]))
	assert_true(delay[missile.id] > 3 * delay[pierce.id], K.say("NEW-02", "the missile is much slower to arrive: %s" % [delay]))
	# The burst's weakness: short range (it does not reach 6 tiles at all).
	assert_eq(delay[burst.id], -1, K.say("NEW-02", "the burst is short-range: %s" % [delay]))
	assert_true(burst.ranged.max_range < pierce.ranged.max_range)
	# The pierce's weakness: a full wall stops it (where the phase weapon passes).
	var g := K.golden_run("ranged-phase-through-wall")
	if g.resolution != null:
		var wall_res := K.resolve(g.level, g.tapes, _with(cat, GearSlot.RANGED, pierce.id))
		assert_eq(K.events_of(wall_res.events, SimEventType.HIT, 0).size(), 0, K.say("NEW-02", "a straight shot is stopped by the wall"))


## NEW-03: A missile acquires nearest enemy once on launch, does not retarget, and may choose a
## different enemy on a subsequent tape playback if battlefield state differs.
func test_NEW03_the_same_missile_tape_locks_once_never_retargets_and_picks_another_target_when_the_field_differs() -> void:
	var alone := K.golden_run("missile-scenario-f-alone")
	var changed := K.golden_run("missile-scenario-f-target-change")
	var shoved := K.golden_run("missile-no-retarget")
	if not assert_true(alone.resolution != null and changed.resolution != null and shoved.resolution != null):
		return
	assert_true(TapeLib.tapes_equal(alone.tape(0), changed.tape(0)), "the very same missile tape in both playbacks")
	var t_alone := _targets_over_time(alone.resolution)
	var t_changed := _targets_over_time(changed.resolution)
	var t_shoved := _targets_over_time(shoved.resolution)
	assert_eq(t_alone, ["g1"], K.say("NEW-03", "locks the nearest once, holds it"))
	assert_eq(t_changed, ["g2"], K.say("NEW-03", "a different battlefield on a later playback: a different target"))
	assert_eq(t_shoved, ["g1"], K.say("NEW-03", "does not retarget when another enemy gets nearer after launch"))
	# Locked at launch: the target is known on the very first frame the missile exists.
	assert_true(_first_target(alone.resolution) == "g1", K.say("NEW-03", "acquired on launch"))


func _targets_over_time(res: Resolution) -> Array:
	var out: Array = []
	for f: FrameSnapshot in res.frames:
		for p: ProjectileSnap in f.projectiles:
			if p.owner_tape == 0 and p.archetype == RangedArchetype.MISSILE and (out.is_empty() or out[out.size() - 1] != p.target_id):
				out.append(p.target_id)
	return out


func _first_target(res: Resolution) -> String:
	for f: FrameSnapshot in res.frames:
		for p: ProjectileSnap in f.projectiles:
			if p.owner_tape == 0:
				return p.target_id
	return "<none>"


## NEW-04: A fast piercing projectile may strike successive targets in its line when that weapon
## property applies; a normal projectile does not inherit piercing automatically.
func test_NEW04_piercing_strikes_successive_targets_only_on_the_piercing_weapon() -> void:
	var g := K.golden_run("ranged-pierce-line")
	if not assert_true(g.resolution != null):
		return
	var struck: Array = []
	for e: SimEvent in K.events_of(g.resolution.events, SimEventType.HIT, 0):
		struck.append(e.id)
	assert_eq(struck, ["g1", "g2", "g3"], K.say("NEW-04", "the piercing shot strikes each enemy in its line once"))
	assert_true(g.loadout.ranged.pierce > 0)
	# Every non-piercing catalogue weapon fired along the same line stops at the first enemy.
	var cat := _cat()
	if cat == null:
		return
	for it: GearItem in cat.items_in_slot(GearSlot.RANGED):
		if it.ranged.pierce > 0:
			assert_eq(it.ranged.archetype, RangedArchetype.PIERCE, K.say("NEW-04", "only the pierce archetype pierces (%s)" % it.id))
			continue
		if it.ranged.lobbed or it.ranged.count > 1:
			continue  # arc (lands on one spot) and burst (spread) are covered by NEW-05 / NEW-02
		var res := K.resolve(g.level, g.tapes, _with(cat, GearSlot.RANGED, it.id))
		var ids := {}
		for e: SimEvent in K.events_of(res.events, SimEventType.HIT, 0):
			ids[e.id] = true
		assert_true(ids.size() <= 1, K.say("NEW-04", "%s (%s) struck %s: it inherited piercing" % [it.id, it.ranged.archetype, ids.keys()]))


## NEW-05: A wall-piercing or vertical-trajectory weapon follows only its own documented
## collision/trajectory rules; never grant every ranged attack these abilities.
func test_NEW05_only_the_phase_weapon_passes_walls_and_only_the_arc_weapon_lobs() -> void:
	var cat := _cat()
	var phase := K.golden_run("ranged-phase-through-wall")
	var arc := K.golden_run("ranged-arc-over-wall")
	if cat == null or not assert_true(phase.resolution != null and arc.resolution != null):
		return
	assert_eq(K.events_of(phase.resolution.events, SimEventType.KILL, 0, "g1").size(), 1, K.say("NEW-05", "the phase shot passes the wall"))
	assert_eq(K.events_of(arc.resolution.events, SimEventType.KILL, 0, "g1").size(), 1, K.say("NEW-05", "the arc shot is lobbed over the wall"))
	for it: GearItem in cat.items_in_slot(GearSlot.RANGED):
		var r := it.ranged
		assert_eq(r.passes_walls, r.archetype == RangedArchetype.PHASE, K.say("NEW-05", "%s passes walls" % it.id))
		assert_eq(r.lobbed, r.archetype == RangedArchetype.ARC, K.say("NEW-05", "%s is lobbed" % it.id))
		# Fired at the grunt behind the same full wall, only the phase and arc weapons get there.
		var res := K.resolve(phase.level, phase.tapes, _with(cat, GearSlot.RANGED, it.id))
		var through := K.events_of(res.events, SimEventType.HIT, 0, "g1").size() > 0
		if r.archetype == RangedArchetype.PHASE:
			assert_true(through, K.say("NEW-05", "%s should pass the wall" % it.id))
		elif r.archetype != RangedArchetype.ARC:
			assert_false(through, K.say("NEW-05", "%s (%s) got through a full wall" % [it.id, r.archetype]))
	# The phase shot still obeys its own rule: it stops at the map edge.
	var edge := K.golden_run("ranged-phase-map-edge")
	if edge.resolution != null:
		assert_true(K.events_of(edge.resolution.events, SimEventType.PROJECTILE_HIT).size() > 0 or edge.resolution.frames[edge.resolution.frames.size() - 1].projectiles.is_empty(), K.say("NEW-05", "the phase shot ends at the map edge"))


## NEW-06: Different cassette speeds and local velocity influence melee momentum and its
## damage/stagger/knockback consequences, with weapon-specific characteristics.
func test_NEW06_speed_velocity_and_the_weapon_shape_the_momentum_consequences() -> void:
	var stand := K.golden_run("momentum-1x-stand")
	var fast := K.golden_run("momentum-2x-stand")
	var into := K.golden_run("momentum-1x-into")
	if not assert_true(stand.resolution != null and fast.resolution != null and into.resolution != null):
		return
	var k_stand := _knock(stand.resolution)
	assert_true(_knock(fast.resolution) > k_stand, K.say("NEW-06", "tape speed raises the knockback"))
	assert_true(_knock(into.resolution) > k_stand, K.say("NEW-06", "moving into the strike raises the knockback"))
	# The momentum model itself (Tuning.swing_momentum): tape speed and local velocity both enter.
	var lo := stand.loadout
	var sw := lo.melee.light
	var m_stand := Tuning.swing_momentum(sw, lo.mods, 1.0, 0.0, 0.0, 0.0)
	assert_near(Tuning.swing_momentum(sw, lo.mods, 2.0, 0.0, 0.0, 0.0), 2.0 * m_stand, 1e-9, K.say("NEW-06", "momentum scales with tape speed"))
	assert_true(Tuning.swing_momentum(sw, lo.mods, 1.0, 3.0, 0.0, 0.0) > m_stand, K.say("NEW-06", "moving into the swing adds momentum"))
	assert_true(Tuning.swing_momentum(sw, lo.mods, 1.0, -3.0, 0.0, 0.0) < m_stand, K.say("NEW-06", "moving away from the swing loses momentum"))
	# Weapon-specific: the same standing 1x swing with different catalogue weapons gives different
	# knockback and damage, following each weapon's efficiencies.
	var cat := _cat()
	if cat == null:
		return
	var rows := {}
	for it: GearItem in cat.items_in_slot(GearSlot.MELEE):
		if it.melee.reach < 1.1:
			continue
		var wlo := stand.loadout.copy()
		wlo.melee = it.melee.copy()
		var res := K.resolve(stand.level, stand.tapes, wlo)
		var g0 := res.frames[0].enemy("g1")
		var gl := res.frames[res.frames.size() - 1].enemy("g1")
		rows[it.id] = [snappedf(_knock(res), 0.001), g0.hp - gl.hp, it.melee.knockback_eff, it.melee.damage_eff]
	var knocks := {}
	for id: String in rows:
		knocks[rows[id][0]] = true
	assert_true(rows.size() >= 3, "three weapons compared")
	assert_true(knocks.size() >= 2, K.say("NEW-06", "weapon-specific knockback: %s" % [rows]))
	# Higher knockback efficiency never knocks back less (same swing, same momentum otherwise).
	var ids := rows.keys()
	for a: String in ids:
		for b: String in ids:
			if rows[a][2] > rows[b][2] and cat.get_item(a).melee.light.impact == cat.get_item(b).melee.light.impact:
				assert_true(rows[a][0] >= rows[b][0], K.say("NEW-06", "%s knockbackEff %s vs %s %s" % [a, rows[a][2], b, rows[b][2]]))


func _knock(res: Resolution) -> float:
	var g0 := res.frames[0].enemy("g1")
	var best := 0.0
	for f: FrameSnapshot in res.frames:
		best = maxf(best, absf(f.enemy("g1").x - g0.x))
	return best
