class_name EnemyTestKit
extends ODTest
## Test kit for the enemy-roster suites (tests/core/enemies/), ported from prototype
## tests/helpers/{levels,loadout,script}.ts: makeLevel, baseLoadout, pathTape, resolve, eventsOf,
## frameAt. The other suites call these statics (EnemyTestKit.path_tape(...)); they never extend this
## class, so its own tests run once.
##
## This suite's own tests cover the port additions shared by the roster: every enemy decision about
## WHO to target and WHETHER someone is in aggro / firing range goes through the single
## effective-distance helper (EnemyCommon.perceived_distance -> Abilities.effective_distance), while
## physical reach stays raw distance.

const SPB: int = 120

## A 12x10 room: walls around a floor of 10x8 tiles (interior x in [1, 11), y in [1, 9)).
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


# ───────────────────────────── levels ─────────────────────────────

## makeLevel. Keys of `o` (all optional): map, speeds, bars, horizon_bars, start (Vector2),
## entities (Array[EntityDef]), objective (ObjectiveType.*). Defaults as the prototype: bpm 120,
## 4 bars, horizon = bars / slowest speed, all speeds and end modes, OPEN_ROOM, start at the room's
## centre (or the first floor tile of a custom map).
static func make_level(o: Dictionary = {}) -> LevelDef:
	var l := LevelDef.new()
	var map: Array[String] = []
	if o.has("map"):
		map.assign(o["map"])
	else:
		map = OPEN_ROOM.duplicate()
	var speeds: Array[float] = [0.5, 1.0, 2.0, 4.0]
	if o.has("speeds"):
		speeds.assign(o["speeds"])
	var bars: int = int(o.get("bars", 4))
	var slowest: float = speeds.min()
	l.id = "test-level"
	l.index = 0
	l.name = "Test Level"
	l.tagline = "A level built by a test."
	l.theme = LevelTheme.UPPER
	l.bpm = 120.0
	l.max_tapes = 4
	l.end_modes.assign([OD.EndMode.STOP, OD.EndMode.REPEAT, OD.EndMode.REVERSE])
	if o.has("entities"):
		l.entities.assign(o["entities"])
	l.objective = ObjectiveDef.new()
	l.objective.type = StringName(o.get("objective", ObjectiveType.ELIMINATE))
	l.objective.text = "Test objective"
	l.music = _default_music()
	l.start_facing = 0.0
	l.bars = bars
	l.horizon_bars = int(o.get("horizon_bars", roundi(bars / slowest)))
	l.speeds = speeds
	l.map = map
	l.start = o.get("start", _default_start(map, not o.has("map")))
	return l


static func _default_music() -> LevelMusicDef:
	var m := LevelMusicDef.new()
	m.root = 9
	m.scale = "Minor"
	m.progression.assign([0, 5, 2, 6])
	m.chord_bars = 1
	var roles: Array[StringName] = [MusicRole.BASS, MusicRole.DRUMS, MusicRole.MELODY, MusicRole.CHORD]
	var formulas: Array[String] = ["triangular", "ruler", "recaman", "squares"]
	for i: int in range(4):
		var t := TrackMusicDef.new()
		t.role = roles[i]
		t.formula = formulas[i]
		m.tracks.append(t)
	return m


static func _default_start(map: Array[String], open_room: bool) -> Vector2:
	if open_room:
		return Vector2(6, 5)
	for r: int in range(map.size()):
		for c: int in range(map[r].length()):
			if ".:,~".contains(map[r][c]):
				return Vector2(c + 0.5, r + 0.5)
	return Vector2(map[0].length() / 2.0, map.size() / 2.0)


## An EnemyDef. Keys of `o`: facing, hp, beat ([every, offset]), wake (SignalExpr; "asleep" = never
## wakes, i.e. {const: false}), arc.
static func enemy(id: String, type: StringName, x: float, y: float, o: Dictionary = {}) -> EnemyDef:
	var e := EnemyDef.new()
	e.id = id
	e.type = type
	e.x = x
	e.y = y
	e.facing = float(o.get("facing", 0.0))
	if o.has("hp"):
		e.hp = int(o["hp"])
		e.has_hp = true
	if o.has("beat"):
		e.beat_every = int(o["beat"][0])
		e.beat_offset = float(o["beat"][1])
		e.has_beat = true
	if o.has("arc"):
		e.arc = float(o["arc"])
		e.has_arc = true
	if o.has("wake"):
		e.wake_when = o["wake"]
	elif o.get("asleep", false):
		e.wake_when = SignalExpr.of_const(false)
	return e


static func plate(id: String, c: int, r: int, heavy: bool = false) -> PlateDef:
	var p := PlateDef.new()
	p.id = id
	p.c = c
	p.r = r
	p.heavy = heavy
	return p


# ───────────────────────────── loadout ─────────────────────────────

## baseLoadout: plain baseline melee (light 6/4/10 ticks, heavy 16/5/18) and missile, neutral mods,
## the given abilities.
static func base_loadout(abilities: Array[StringName] = []) -> ResolvedLoadout:
	var l := ResolvedLoadout.new()
	l.loadout = Loadout.make("base-helmet", "base-top", "base-pants", "base-shoes", "base-melee", "base-missile")
	l.mods = StatMods.new()
	l.abilities = abilities.duplicate()
	var m := MeleeWeaponDef.new()
	m.reach = 1.1
	m.arc_deg = 110.0
	m.light = _swing(6, 4, 10, 1.2, 0.5)
	m.heavy = _swing(16, 5, 18, 2.0, 0.25)
	m.damage_eff = 1.0
	m.knockback_eff = 1.0
	m.stagger_eff = 1.0
	m.style = MeleeStyle.BLADE
	l.melee = m
	var r := RangedWeaponDef.new()
	r.archetype = RangedArchetype.MISSILE
	r.speed = 2.5
	r.max_range = 14.0
	r.impact = 1.2
	r.commit = 12.0
	r.cooldown = 45.0
	r.pierce = 0
	r.passes_walls = false
	r.lobbed = false
	r.count = 1
	r.spread_deg = 0.0
	r.turn_rate = 2.5
	r.blast = 0.0
	l.ranged = r
	return l


static func _swing(windup: float, active: float, recover: float, impact: float, move_mul: float) -> MeleeSwingDef:
	var s := MeleeSwingDef.new()
	s.windup = windup
	s.active = active
	s.recover = recover
	s.impact = impact
	s.move_mul = move_mul
	return s


# ───────────────────────────── tapes ─────────────────────────────

## pathTape: a tape built directly from waypoints (exact, physics-free choreography).
## `path` = [[tick, x, y], ...] piecewise-linear, held before the first / after the last waypoint;
## `events` = [[tick, ActionKind, dir?], ...] (dir defaults to the motion direction at that tick).
static func path_tape(index: int, speed: float, ticks: int, path: Array, events: Array = [], end_mode: int = OD.EndMode.STOP) -> ODTape:
	var t := ODTape.create(index, speed, end_mode, ticks)
	var last_facing: float = 0.0
	for i: int in range(ticks + 1):
		var px: float = 0.0
		var py: float = 0.0
		var done := false
		if i <= int(path[0][0]):
			px = float(path[0][1])
			py = float(path[0][2])
			done = true
		if not done:
			for k: int in range(1, path.size()):
				var a: Array = path[k - 1]
				var b: Array = path[k]
				if i <= int(b[0]):
					var f: float = 1.0 if int(b[0]) == int(a[0]) else float(i - int(a[0])) / float(int(b[0]) - int(a[0]))
					px = float(a[1]) + (float(b[1]) - float(a[1])) * f
					py = float(a[2]) + (float(b[2]) - float(a[2])) * f
					done = true
					break
		if not done:
			var l: Array = path[path.size() - 1]
			px = float(l[1])
			py = float(l[2])
		t.pos[i * 2] = px
		t.pos[i * 2 + 1] = py
	for i: int in range(ticks + 1):
		var j: int = mini(i, ticks - 1)
		var dx: float = t.pos[j * 2 + 2] - t.pos[j * 2]
		var dy: float = t.pos[j * 2 + 3] - t.pos[j * 2 + 1]
		var moving: bool = ticks > 0 and (dx != 0.0 or dy != 0.0)
		if moving:
			last_facing = atan2(dy, dx)
		t.facing[i] = last_facing
		t.anim[i] = TapeLib.anim_index(AnimState.RUN if moving else AnimState.IDLE)
	# Sorted by tick, stable (as the prototype's Array.sort).
	var evs: Array = events.duplicate()
	for a: int in range(1, evs.size()):
		var cur: Array = evs[a]
		var b: int = a - 1
		while b >= 0 and int(evs[b][0]) > int(cur[0]):
			evs[b + 1] = evs[b]
			b -= 1
		evs[b + 1] = cur
	for ev: Array in evs:
		var tick: int = int(ev[0])
		var i: int = mini(tick, ticks - 1)
		var vx: float = (t.pos[i * 2 + 2] - t.pos[i * 2]) * 60.0
		var vy: float = (t.pos[i * 2 + 3] - t.pos[i * 2 + 1]) * 60.0
		var dir: float = float(ev[2]) if ev.size() > 2 else t.facing[tick]
		t.events.append(TapeEvent.make(tick, StringName(ev[1]), dir, t.pos[tick * 2], t.pos[tick * 2 + 1], vx, vy))
	return t


## A tape standing still at (x, y).
static func still(index: int, x: float, y: float, ticks: int = 480) -> ODTape:
	return path_tape(index, 1.0, ticks, [[0, x, y]])


# ───────────────────────────── runs ─────────────────────────────

## resolve: the combined run under playback rules.
static func resolve(level: LevelDef, tapes: Array[ODTape], loadout: ResolvedLoadout = null, memory: BossMemory = null) -> Resolution:
	var l: ResolvedLoadout = loadout if loadout != null else base_loadout()
	return ODResolve.resolve_encounter(SimConfig.make(level, l, tapes, null, memory))


## eventsOf: events of one type (optionally for one tape / id).
static func events_of(events: Array[SimEvent], type: StringName, tape: int = -1, id: String = "") -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e: SimEvent in events:
		if e.type == type and (tape < 0 or e.tape == tape) and (id.is_empty() or e.id == id):
			out.append(e)
	return out


## frameAt: the frame at (or just after) a master substep.
static func frame_at(res: Resolution, sub: int) -> FrameSnapshot:
	for f: FrameSnapshot in res.frames:
		if f.sub >= sub:
			return f
	return res.frames[res.frames.size() - 1]


static func last_frame(res: Resolution) -> FrameSnapshot:
	return res.frames[res.frames.size() - 1]


static func dist(e: EnemySnap, x: float, y: float) -> float:
	return ODGrid.hypot(e.x - x, e.y - y)


# ───────────────────────────── shared rules: effective distance ─────────────────────────────

func test_stalker_commit_range_is_perceived_distance_lowProfile() -> void:
	# A stalker 2 tiles from its quarry is committed (2 < 2.5); with lowProfile the quarry reads as
	# 3 tiles away, so on the bar line it reconsiders.
	var lvl := make_level({"speeds": [1.0], "bars": 1, "start": Vector2(4, 5), "entities": [enemy("s1", EnemyType.STALKER, 6, 5, {"asleep": true})]})
	var sim: ODSim = ODSim.create_sim(SimConfig.make(lvl, base_loadout(), [still(0, 4, 5, 120)]))
	var e: EnemyState = sim.enemy_by_id("s1")
	e.target = 0
	var beh: StalkerBehaviour = EnemyRegistry.get_enemy_behaviour(EnemyType.STALKER)
	assert_false(beh.profile.retarget_on_beat.call(sim, e, 4), "raw 2 tiles: committed")
	var low: ODSim = ODSim.create_sim(SimConfig.make(lvl, base_loadout([AbilityId.LOW_PROFILE]), [still(0, 4, 5, 120)]))
	var e2: EnemyState = low.enemy_by_id("s1")
	e2.target = 0
	assert_true(beh.profile.retarget_on_beat.call(low, e2, 4), "lowProfile: perceived 3 > commit range")
	assert_false(beh.profile.retarget_on_beat.call(low, e2, 3), "never off the bar line")


func test_drone_firing_range_is_perceived_distance() -> void:
	# A drone keeps 5 +- 0.5 tiles (physical spacing) and shoots within 8 tiles of PERCEIVED
	# distance. Settled at ~5.5 tiles from a plain self it fires; with lowProfile that self reads as
	# ~8.2 tiles away, out of range, so at the same spacing it never fires.
	var lvl := make_level({"speeds": [1.0], "bars": 4, "start": Vector2(2, 5), "entities": [enemy("d1", EnemyType.DRONE, 9, 5)]})
	var plain := resolve(lvl, [still(0, 2, 5)])
	var low := resolve(lvl, [still(0, 2, 5)], base_loadout([AbilityId.LOW_PROFILE]))
	assert_true(events_of(plain.events, SimEventType.ENEMY_TELEGRAPH, -1, "d1").size() > 0, "plain: it fires")
	assert_eq(events_of(low.events, SimEventType.ENEMY_TELEGRAPH, -1, "d1").size(), 0, "lowProfile: out of perceived range")
	var e0 := last_frame(plain).enemies[0]
	var e1 := last_frame(low).enemies[0]
	assert_eq([e1.x, e1.y], [e0.x, e0.y], "spacing is physical: the same resting place")
	assert_true(dist(e1, 2, 5) * Abilities.LOW_PROFILE_FACTOR > 8.0, "perceived beyond range")
	assert_eq(last_frame(low).enemies[0].target, 0, "still its target (target choice is perceived nearest)")

func test_targets_use_perceived_distance_and_reach_stays_physical() -> void:
	# loudmouth makes selves read nearer, but a melee strike still needs the body within raw reach:
	# a shielder whose quarry stands 1.1 tiles away (perceived 0.825 < reach 0.9) never telegraphs.
	var lvl := make_level({"speeds": [1.0], "bars": 1, "start": Vector2(4.9, 5), "entities": [enemy("sh", EnemyType.SHIELDER, 6, 5)]})
	var res := resolve(lvl, [still(0, 4.9, 5, 120)], base_loadout([AbilityId.LOUDMOUTH]))
	var tels: Array[SimEvent] = events_of(res.events, SimEventType.ENEMY_TELEGRAPH, -1, "sh")
	for t: SimEvent in tels:
		var f: FrameSnapshot = frame_at(res, t.sub)
		assert_true(dist(f.enemies[0], 4.9, 5) <= 0.9 + 1e-6, "telegraph only within raw reach")
	assert_true(tels.size() > 0, "it walks in and strikes")
	assert_eq(frame_at(res, 10).enemies[0].target, 0, "it targets the self")


func test_grunt_target_choice_goes_through_the_helper_and_its_reach_stays_raw() -> void:
	# The candidate filter of nearest_target sees perceived distance (loudmouth: 2 tiles read as 1.5).
	var lvl := make_level({"speeds": [1.0], "bars": 1, "start": Vector2(4, 5), "entities": [enemy("g1", EnemyType.GRUNT, 6, 5, {"asleep": true})]})
	var loud: ODSim = ODSim.create_sim(SimConfig.make(lvl, base_loadout([AbilityId.LOUDMOUTH]), [still(0, 4, 5, 120)]))
	var seen: Array[float] = []
	var t: SelfActor = EnemyCommon.nearest_target(loud, 6, 5, func(_s: SelfActor, d: float) -> bool:
		seen.append(d)
		return true)
	assert_true(t != null and t.index == 0, "targets the self")
	assert_eq(seen.size(), 1)
	if seen.size() == 1:
		assert_near(seen[0], 2.0 * Abilities.LOUDMOUTH_FACTOR, 1e-12, "perceived distance")
	# Which self is nearest does not change with the shared factor: A (2 tiles) over B (2.5 tiles).
	var two := make_level({"speeds": [1.0], "bars": 1, "start": Vector2(4, 5), "entities": [enemy("g1", EnemyType.GRUNT, 6, 5)]})
	for abilities: Array[StringName] in [[] as Array[StringName], [AbilityId.LOUDMOUTH] as Array[StringName], [AbilityId.LOW_PROFILE] as Array[StringName]]:
		var res := resolve(two, [still(0, 4, 5, 120), still(1, 8.5, 5, 120)], base_loadout(abilities))
		assert_eq(frame_at(res, 8).enemies[0].target, 0, "nearest with %s" % [abilities])
	# Reach is physical: a self 1.1 tiles away reads as 0.825 (< reach 0.9) under loudmouth, but the
	# grunt still has to walk in until the raw distance is within reach before it telegraphs.
	var near := make_level({"speeds": [1.0], "bars": 1, "start": Vector2(4.9, 5), "entities": [enemy("g1", EnemyType.GRUNT, 6, 5)]})
	var res2 := resolve(near, [still(0, 4.9, 5, 120)], base_loadout([AbilityId.LOUDMOUTH]))
	var tels: Array[SimEvent] = events_of(res2.events, SimEventType.ENEMY_TELEGRAPH, -1, "g1")
	assert_true(tels.size() > 0, "it walks in and strikes")
	for tel: SimEvent in tels:
		assert_true(dist(frame_at(res2, tel.sub).enemies[0], 4.9, 5) <= Tuning.enemy_stats(EnemyType.GRUNT).reach + 1e-6, "telegraph only within raw reach")


func test_kit_path_tape_matches_prototype_shape() -> void:
	var t := path_tape(1, 1.0, 120, [[0, 2, 2], [60, 8, 2]], [[30, ActionKind.LIGHT]])
	assert_eq(t.pos.size(), 242)
	assert_near(t.pos[60], 5.0, 1e-6, "halfway at tick 30")
	assert_near(t.pos[240], 8.0, 1e-6, "held at the end")
	assert_eq(t.events.size(), 1)
	assert_near(t.events[0].dir, 0.0, 1e-9, "dir defaults to the motion direction")
	assert_near(t.events[0].vx, 6.0, 1e-4, "recorded local velocity")
