extends ODTest
## Acceptance: enemies, momentum, dodge and missiles (docs/requirements.txt chapter 21: TEST-18..22),
## on the shipped core.

const K = preload("res://tests/acceptance/acceptance_kit.gd")
const S = preload("res://tests/helpers/script.gd")


func _path(res: Resolution, tape: int) -> Array:
	var out: Array = []
	for f: FrameSnapshot in res.frames:
		var a := f.actor(tape)
		out.append([a.x, a.y, a.facing])
	return out


## TEST-18 - Add a closer self to an enemy's target rule.
## Expected: "Enemy response can change without the old tape changing its aim or path."
func test_TEST18_a_closer_self_changes_the_enemys_response_while_the_old_tape_keeps_its_aim_and_path() -> void:
	var both := K.golden_run("enemy-grunt-target-switch")
	var alone := K.golden_run("enemy-grunt-target-switch", 1)
	if not assert_true(both.resolution != null and alone.resolution != null, "golden runs: %s" % [both.errors]):
		return
	var first_alone := K.first_event(alone.resolution.events, SimEventType.ENEMY_TELEGRAPH, -1, "g1")
	var first_both := K.first_event(both.resolution.events, SimEventType.ENEMY_TELEGRAPH, -1, "g1")
	if not assert_true(first_alone != null and first_both != null, K.say("TEST-18", "the grunt attacks in both runs")):
		return
	assert_eq(first_alone.tape, 0, K.say("TEST-18", "alone, the grunt goes for A"))
	assert_eq(first_both.tape, 1, K.say("TEST-18", "with the closer self B, the grunt goes for B"))
	assert_true(K.event_rows(both.resolution.events) != K.event_rows(alone.resolution.events), K.say("TEST-18", "the enemy response changed"))
	# The old tape is unchanged: same tape data, same aim and path in both runs.
	var a_alone := alone.tape(0)
	var a_both := both.tape(0)
	assert_true(TapeLib.tapes_equal(a_alone, a_both), K.say("TEST-18", "tape A itself"))
	assert_eq(_path(both.resolution, 0), _path(alone.resolution, 0), K.say("TEST-18", "A's path and facing in the run"))
	# The target switch is the enemy's: its target field reads B at some frame of the combined run.
	var saw_b := false
	for f: FrameSnapshot in both.resolution.frames:
		saw_b = saw_b or f.enemy("g1").target == 1
	assert_true(saw_b, K.say("TEST-18", "the grunt's target becomes B"))


## TEST-19 - Knock an enemy into/out of another attack.
## Expected: "Its new physical position changes later hit outcomes."
func test_TEST19_knocking_an_enemy_into_or_out_of_a_later_attack_changes_that_hits_outcome() -> void:
	# INTO: alone, A's recorded swing at an empty spot whiffs; after B knocks the grunt there, the
	# same swing kills it.
	var alone := K.golden_run("combat-knockback-alone-whiff")
	var into := K.golden_run("combat-knockback-changes-later-hit")
	if not assert_true(alone.resolution != null and into.resolution != null, "golden runs"):
		return
	assert_eq(K.events_of(alone.resolution.events, SimEventType.WHIFF, 0).size(), 1, K.say("TEST-19", "control: A's swing whiffs"))
	assert_eq(K.events_of(alone.resolution.events, SimEventType.HIT, 0).size(), 0)
	var b_hit := K.first_event(into.resolution.events, SimEventType.HIT, 1, "g1")
	var a_kill := K.first_event(into.resolution.events, SimEventType.KILL, 0, "g1")
	assert_true(b_hit != null and a_kill != null and b_hit.sub < a_kill.sub, K.say("TEST-19", "knocked into the swing, the same swing kills"))
	var at_swing := S.frame_at(into.resolution, a_kill.sub if a_kill != null else 0).enemy("g1")
	var start := into.resolution.frames[0].enemy("g1")
	assert_true(at_swing.x - start.x > 0.5, K.say("TEST-19", "the grunt really moved (x %.2f -> %.2f)" % [start.x, at_swing.x]))
	# OUT OF: A swings at the grunt where it stands; alone that lands. B shoves it away first and the
	# same recorded swing now finds nothing.
	var level := into.level
	var a_out := S.path_tape(0, 1.0, 120, [[0, 1.5, 5.5], [60, 5.0, 5.5]], [[90, ActionKind.LIGHT, 0.0]])
	var b_shove: ODTape = into.tape(1)
	var solo := K.resolve(level, [a_out], into.loadout)
	var shoved := K.resolve(level, [a_out, b_shove], into.loadout)
	assert_eq(K.events_of(solo.events, SimEventType.HIT, 0, "g1").size(), 1, K.say("TEST-19", "control: A's swing lands on the grunt where it stands"))
	assert_eq(K.events_of(shoved.events, SimEventType.HIT, 1, "g1").size(), 1, K.say("TEST-19", "B shoves the grunt first"))
	assert_eq(K.events_of(shoved.events, SimEventType.HIT, 0, "g1").size(), 0, K.say("TEST-19", "knocked out of the swing, it no longer lands"))
	assert_eq(K.events_of(shoved.events, SimEventType.WHIFF, 0).size(), 1, K.say("TEST-19", "A's swing whiffs"))


## One light swing at a tough sleeping grunt (hp 10) from the prototype-authored momentum fixtures
## (tests/goldens/momentum-<speed>-<stand|into|away>.json: same level, same swing tick and direction,
## only the tape speed or the self's motion into the strike differs), resolved by the port.
## Returns {hits, damage, knock (max x displacement), stagger (seconds, from its enemyStagger event)}.
func _momentum(name: String) -> Dictionary:
	var g := K.golden_run(name)
	if g.resolution == null:
		return {"hits": -1, "damage": -1, "knock": -1.0, "stagger": -1}
	# The stagger is read from the enemyStagger event the strike emits (power = stagger seconds).
	# A frame count of EnemyStateName.STAGGER does not measure it: the grunt is asleep (never awake),
	# and common.gd only moves an awake enemy out of STAGGER, so its snapshot state reads STAGGER
	# until the horizon in every variant (it measured "time since the hit").
	var res := g.resolution
	var g0 := res.frames[0].enemy("g1")
	var max_dx := 0.0
	var hp := g0.hp
	for f: FrameSnapshot in res.frames:
		var e := f.enemy("g1")
		max_dx = maxf(max_dx, e.x - g0.x)
		hp = e.hp
	var stagger := 0.0
	var staggers := K.events_of(res.events, SimEventType.ENEMY_STAGGER, -1, "g1")
	for e: SimEvent in staggers:
		stagger += e.power
	return {"hits": K.events_of(res.events, SimEventType.HIT, 0, "g1").size(), "damage": g0.hp - hp, "knock": max_dx, "stagger": stagger if not staggers.is_empty() else -1.0}


## TEST-20 - Compare movement/tape-speed combinations on the same attack.
## Expected: "Effective momentum meaningfully influences damage, stagger and knockback."
func test_TEST20_tape_speed_and_movement_change_damage_stagger_and_knockback_of_the_same_attack() -> void:
	var slow := _momentum("momentum-0_5x-stand")
	var mid := _momentum("momentum-1x-stand")
	var fast := _momentum("momentum-2x-stand")
	var into := _momentum("momentum-1x-into")
	var away := _momentum("momentum-1x-away")
	for r: Dictionary in [slow, mid, fast, into, away]:
		assert_eq(r["hits"], 1, K.say("TEST-20", "every variant lands the same one swing: %s" % [r]))
		assert_true(r["stagger"] > 0, K.say("TEST-20", "the strike staggers the grunt (enemyStagger event): %s" % [r]))
	# Tape speed: never less from 0.5x to 1x to 2x, and 2x clearly beats 0.5x, on all three.
	assert_true(slow["knock"] <= mid["knock"] and mid["knock"] <= fast["knock"] and slow["knock"] < fast["knock"], K.say("TEST-20", "knockback by speed %s / %s / %s" % [slow["knock"], mid["knock"], fast["knock"]]))
	assert_true(slow["stagger"] <= mid["stagger"] and mid["stagger"] <= fast["stagger"] and slow["stagger"] < fast["stagger"], K.say("TEST-20", "stagger by speed %s / %s / %s" % [slow["stagger"], mid["stagger"], fast["stagger"]]))
	assert_true(slow["damage"] <= mid["damage"] and mid["damage"] <= fast["damage"] and slow["damage"] < fast["damage"], K.say("TEST-20", "damage by speed %s / %s / %s" % [slow["damage"], mid["damage"], fast["damage"]]))
	# Movement: away <= standing <= into, and into clearly beats away, on all three.
	assert_true(away["knock"] <= mid["knock"] and mid["knock"] <= into["knock"] and away["knock"] < into["knock"], K.say("TEST-20", "knockback by movement %s / %s / %s" % [away["knock"], mid["knock"], into["knock"]]))
	assert_true(away["stagger"] <= mid["stagger"] and mid["stagger"] <= into["stagger"] and away["stagger"] < into["stagger"], K.say("TEST-20", "stagger by movement %s / %s / %s" % [away["stagger"], mid["stagger"], into["stagger"]]))
	assert_true(away["damage"] <= mid["damage"] and mid["damage"] <= into["damage"] and away["damage"] < into["damage"], K.say("TEST-20", "damage by movement %s / %s / %s" % [away["damage"], mid["damage"], into["damage"]]))
	# Meaningfully: the 2x swing knocks back at least three times as far as the 0.5x one.
	assert_true(fast["knock"] >= 3.0 * slow["knock"], K.say("TEST-20", "2x vs 0.5x knockback ratio"))


## TEST-21 - Dodge a qualifying hit.
## Expected: "The selected i-frame interval can prevent death; exact timing is tunable."
func test_TEST21_the_dodge_iframe_interval_prevents_death_and_its_timing_is_tunable() -> void:
	var good := K.golden_run("dodge-iframes-pass-through")
	var early := K.golden_run("dodge-too-early-dies")
	if not assert_true(good.resolution != null and early.resolution != null, "golden runs"):
		return
	# Inside the i-frame interval the bolt passes through: no death.
	assert_eq(K.events_of(good.resolution.events, SimEventType.SELF_DEATH, 0).size(), 0, K.say("TEST-21", "the timed dodge prevents death"))
	assert_true(K.events_of(good.resolution.events, SimEventType.ENEMY_SHOT, 0).size() > 0, "the turret did fire at the self")
	var saw_iframes := false
	for f: FrameSnapshot in good.resolution.frames:
		saw_iframes = saw_iframes or f.actor(0).iframes
	assert_true(saw_iframes, K.say("TEST-21", "the self shows i-frames during the dodge"))
	# Outside it (the same dodge started too early) the same bolt kills.
	var death := K.first_event(early.resolution.events, SimEventType.SELF_DEATH, 0)
	if not assert_true(death != null, K.say("TEST-21", "control: an early dodge's interval is over when the bolt lands")):
		return
	var dodge_ev: TapeEvent = early.tape(0).events[0]
	var w := PlayerController.dodge_iframe_window(dodge_ev, early.loadout)
	assert_true(death.sub >= w.end * OD.subs_per_local_tick(1.0), K.say("TEST-21", "the fatal bolt arrived after the interval [%d, %d)" % [w.start, w.end]))
	# Exact timing is tunable: the interval comes from tuning x the loadout's dodgeIframes stat, and a
	# longer tuned interval lets the very same early dodge survive the very same bolt.
	var base_len := w.end - w.start
	assert_eq(base_len, int(round(Tuning.BASE.dodge_iframes)), K.say("TEST-21", "the interval is the tuned length"))
	var tuned := early.loadout.copy()
	tuned.mods.dodge_iframes = 3.2
	var tw := PlayerController.dodge_iframe_window(dodge_ev, tuned)
	assert_true(tw.end - tw.start > base_len, K.say("TEST-21", "the dodgeIframes stat retunes the interval"))
	var res := K.resolve(early.level, early.tapes, tuned)
	assert_eq(K.events_of(res.events, SimEventType.SELF_DEATH, 0).size(), 0, K.say("TEST-21", "with the retuned interval the same dodge prevents the death"))


## TEST-22 - Fire a recorded missile after changing enemy positions.
## Expected: "Nearest target is acquired once at launch; the missile does not continuously retarget."
func test_TEST22_the_missile_locks_the_nearest_enemy_once_at_launch_and_never_retargets() -> void:
	var alone := K.golden_run("missile-scenario-f-alone")
	var changed := K.golden_run("missile-scenario-f-target-change")
	var shoved := K.golden_run("missile-no-retarget")
	if not assert_true(alone.resolution != null and changed.resolution != null and shoved.resolution != null, "golden runs"):
		return
	# Alone the nearest enemy at launch is g1.
	assert_eq(_missile_targets(alone.resolution), ["g1"], K.say("TEST-22", "alone it locks g1, the nearest at launch"))
	assert_eq(K.first_event(alone.resolution.events, SimEventType.HIT, 0).id, "g1")
	# Enemy positions changed BEFORE launch (B knocks g2 closer): the same recorded launch locks g2.
	assert_eq(_missile_targets(changed.resolution), ["g2"], K.say("TEST-22", "positions changed before launch: nearest is now g2"))
	assert_eq(K.first_event(changed.resolution.events, SimEventType.HIT, 0).id, "g2")
	# Changed AFTER launch (g2 shoved nearer the flying missile): it keeps g1 and hits g1.
	var fire := K.first_event(shoved.resolution.events, SimEventType.FIRE, 0)
	var shove := K.first_event(shoved.resolution.events, SimEventType.HIT, 2, "g2")
	assert_true(fire != null and shove != null and shove.sub > fire.sub, "g2 is shoved after the launch")
	assert_eq(_missile_targets(shoved.resolution), ["g1"], K.say("TEST-22", "the missile does not retarget after launch"))
	assert_eq(K.first_event(shoved.resolution.events, SimEventType.HIT, 0).id, "g1", K.say("TEST-22", "it still strikes its launch target"))


## Every distinct target id a tape-0 missile carries over the run, in order of appearance.
func _missile_targets(res: Resolution) -> Array:
	var out: Array = []
	for f: FrameSnapshot in res.frames:
		for p: ProjectileSnap in f.projectiles:
			if p.owner_tape == 0 and p.archetype == RangedArchetype.MISSILE and not out.has(p.target_id):
				out.append(p.target_id)
	return out
