extends RefCounted
## Shared fixtures for the fx suites (port of prototype/tests/render-fx/fixtures.ts). Load with
## `const Fx := preload("res://tests/fx/fx_fixtures.gd")`.


static func palette() -> ThemePalette:
	var p := ThemePalette.new()
	p.theme = LevelTheme.LOWER
	p.background = Color("#120e16")
	p.fog = Color("#120e16")
	p.floor_color = Color("#3a3040")
	p.floor_alt = Color("#2e2634")
	p.wall = Color("#4a3c4c")
	p.wall_top = Color("#5c4a5e")
	p.metal = Color("#6a5a6e")
	p.trim = Color("#8a7a8e")
	p.hazard = Color("#ffb21f")
	p.foliage = Color("#6fae3a")
	p.neon_a = Color("#ff3fa4")
	p.neon_b = Color("#4ff3ff")
	p.neon_c = Color("#b05cff")
	p.graffiti = Color("#ff4fa3")
	p.ink = Color("#14110f")
	return p


static func level() -> LevelDef:
	var d := {
		"id": "fx-test",
		"index": 0,
		"name": "FX Test",
		"tagline": "",
		"theme": "lower",
		"bpm": 120,
		"bars": 4,
		"horizonBars": 8,
		"maxTapes": 4,
		"speeds": [0.5, 1, 2, 4],
		"endModes": ["stop", "repeat", "reverse"],
		"map": ["##########", "#........#", "#..~~~...#", "#........#", "##########"],
		"start": {"x": 2.5, "y": 2.5},
		"entities": [
			{"kind": "core", "id": "core1", "x": 7.5, "y": 2.5},
			{"kind": "exit", "id": "exit1", "c": 7, "r": 3, "w": 2, "h": 1},
			{"kind": "decor", "type": "waveScreen", "x": 5, "y": 1},
			{"kind": "decor", "type": "runePanel", "x": 3, "y": 1},
		],
		"objective": {"type": "activate", "text": "Light the core"},
		"music": {"root": 0, "scale": "minor", "progression": [0, 5, 3, 4], "tracks": [
			{"role": "bass", "formula": "a"}, {"role": "drums", "formula": "b"},
			{"role": "melody", "formula": "c"}, {"role": "chord", "formula": "d"}]},
		"loot": [],
		"briefing": [],
	}
	var errors: Array[String] = []
	return LevelDef.from_dict(d, errors)


static func env() -> FxEnv:
	var e := FxEnv.new()
	e.palette = palette()
	e.level = level()
	e.ref_momentum = 10.0
	e.melee_reach = 1.2
	e.melee_arc_deg = 120.0
	e.quality = &"high"
	return e


static func director() -> FxDirector:
	return FxDirector.new(env())


static func actor(tape: int, x: float, y: float, life: int = OD.LifeState.ALIVE, synced: bool = true) -> ActorSnap:
	var a := ActorSnap.new()
	a.tape = tape
	a.live = tape == 0
	a.x = x
	a.y = y
	a.anim = AnimState.RUN
	a.life = life
	a.synced = synced
	if not synced:
		a.has_spark = true
		a.spark = Vector2(x - 1.0, y)
	return a


static func boss(x: float, y: float) -> EnemySnap:
	var e := EnemySnap.new()
	e.id = "boss"
	e.type = EnemyType.BOSS
	e.x = x
	e.y = y
	e.hp = 10
	e.max_hp = 10
	return e


static func music(beat: float, chord: int = 0) -> MusicPulse:
	var m := MusicPulse.new()
	var f := beat - floorf(beat)
	m.beat = beat
	m.beat_pulse = 1.0 - f
	m.bar_pulse = 1.0 - (beat / 4.0 - floorf(beat / 4.0))
	m.levels = PackedFloat32Array([0.8, 0.5, 0.6, 0.3])
	m.pitches = PackedFloat32Array([0.2 + 0.1 * sin(beat), 0.5, 0.7 + 0.1 * cos(beat * 2.0), 0.4])
	m.chord = chord
	return m


## A render frame like the prototype fixture: four selves (one desynced, one ghost) and a boss.
static func frame(mode: StringName, beat: float, events: Array[SimEvent] = [], world_rate: float = 1.0) -> RenderFrame:
	var snap := FrameSnapshot.new()
	snap.sub = roundi(beat * 120.0)
	snap.beat = beat
	snap.actors = [actor(0, 2.5, 2.5), actor(1, 4.0, 2.5), actor(2, 6.0, 3.0, OD.LifeState.ALIVE, false), actor(3, 7.0, 2.0, OD.LifeState.GHOST)]
	snap.enemies = [boss(8.0, 3.0)]
	var f := RenderFrame.new()
	f.snap = snap
	f.prev = snap
	f.alpha = 1.0
	f.dt = 1.0 / 60.0
	f.mode = mode
	f.events = events
	f.world_rate = world_rate
	f.music = music(beat, int(floorf(beat / 4.0)) % 4)
	f.active = 0 if mode == ViewMode.RECORD else -1
	return f


## One event of a type with plausible fields.
static func event_of(type: StringName, power: float = 20.0, tape: int = 1) -> SimEvent:
	return SimEvent.make(1000, type, 4.0, 2.5).with_tape(tape).with_id("e1").with_dir(0.7).with_power(power).with_detail("heavy" if type == SimEventType.SWING else "on")


## Every event type once.
static func all_events(power: float = 20.0, tape: int = 1) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for t: StringName in SimEventType.ALL:
		out.append(event_of(t, power, tape))
	return out


## Tags of every live sprite and word.
static func live_tags(d: FxDirector) -> Array[int]:
	var tags: Array[int] = []
	for pool: FxSpritePool in [d.glow, d.ink]:
		for i: int in pool.capacity:
			if pool.alive[i] != 0:
				tags.append(pool.tag[i])
	for i: int in d.text.capacity:
		if d.text.alive[i] != 0:
			tags.append(d.text.tag[i])
	return tags


## Effect tags of a tier.
static func tier_tags(tier: int) -> Array[int]:
	var out: Array[int] = []
	for i: int in FxCatalog.EFFECT_IDS.size():
		if FxCatalog.EFFECT_TIER[FxCatalog.EFFECT_IDS[i]] == tier:
			out.append(i)
	return out
