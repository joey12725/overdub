class_name WidgetFixtures
extends RefCounted
## Fake data for the widget tests and tools/shot_widgets.gd: a small level with a breakable wall and
## a core, a baseline loadout, snapshots with selves / enemies / a boss, a session view, a boss memory
## and a few found items.


static func loadout() -> ResolvedLoadout:
	return TestLoadout.base_loadout()


## 12x10 room; tutorial-strength wall at tile (6, 4) (threshold 5, Scenario K), a core at (9.5, 7.5)
## with no threshold (sim default), and a weak wall at (2, 7) (threshold 1.5).
static func level() -> LevelDef:
	var L := LevelDef.new()
	L.id = "widget_test"
	L.name = "Widget Test"
	L.bpm = 120.0
	L.bars = 8
	L.horizon_bars = 16
	L.speeds = [0.5, 1.0, 2.0, 4.0]
	L.theme = LevelTheme.UPPER
	var b := BreakableDef.new()
	b.id = "wall"
	b.c = 6
	b.r = 4
	b.threshold = Tuning.TUTORIAL_WALL_THRESHOLD
	L.entities.append(b)
	var c := CoreDef.new()
	c.id = "core"
	c.x = 9.5
	c.y = 7.5
	L.entities.append(c)
	var b2 := BreakableDef.new()
	b2.id = "weak"
	b2.c = 2
	b2.r = 7
	b2.threshold = 1.5
	L.entities.append(b2)
	return L


static func actor(tape: int, x: float, y: float, facing: float, live: bool = false) -> ActorSnap:
	var a := ActorSnap.new()
	a.tape = tape
	a.x = x
	a.y = y
	a.facing = facing
	a.live = live
	return a


static func enemy(id: String, type: StringName, x: float, y: float, hp: int, max_hp: int) -> EnemySnap:
	var e := EnemySnap.new()
	e.id = id
	e.type = type
	e.x = x
	e.y = y
	e.hp = hp
	e.max_hp = max_hp
	return e


static func boss(hp: int, phase: int, recall_tape: int = -1) -> EnemySnap:
	var e := enemy("archivist", EnemyType.BOSS, 6.0, 2.0, hp, 40)
	e.boss_phase = phase
	e.target = 0
	if recall_tape >= 0:
		e.boss_recall = true
		e.boss_recall_tape = recall_tape
		e.boss_recall_at = Vector2(3.0, 6.0)
		e.has_boss_recall_at = true
		e.state = EnemyStateName.TELEGRAPH
		e.state_t = 0.25
	return e


static func view(phase: StringName = SessionPhase.RECORDING, live_tape: int = 0, speed: float = 1.0) -> SessionView:
	var v := SessionView.new()
	v.phase = phase
	v.level = level()
	v.active = live_tape
	v.horizon_beats = 64.0
	v.speeds = [0.5, 1.0, 2.0, 4.0]
	for i in OD.TAPE_COUNT:
		v.decks[i].status = DeckStatus.COMMITTED
		v.decks[i].speed = 1.0
	if live_tape >= 0:
		v.decks[live_tape].status = DeckStatus.RECORDING
		v.decks[live_tape].speed = speed
	return v


static func memory(tapes: Array[int]) -> BossMemory:
	var m := BossMemory.new()
	for t: int in tapes:
		var o := BossObservation.new()
		o.tape = t
		o.speed = 1.0
		# A dwell: four beats standing at one place.
		for b: int in 5:
			o.samples.append(BossSample.make(float(4 + b), 3.0 + t, 6.0))
		m.observed.append(o)
	return m


static func items() -> Array[GearItem]:
	var out: Array[GearItem] = []
	var defs := [
		["amp_sledge", GearSlot.MELEE, "Amp Sledge", "Slow, crushing hammer: 1.4-tile reach, 120° arc. Huge knockback and stagger."],
		["click_visor", GearSlot.HELMET, "Click-Track Visor", "Upcoming enemy attack beats are marked on the master beat ruler."],
		["slick_sliders", GearSlot.SHOES, "Slick Sliders", "Striking straight out of a dodge adds momentum to the hit."],
	]
	for d: Array in defs:
		var g := GearItem.new()
		g.id = d[0]
		g.slot = d[1]
		g.name = d[2]
		g.effect = d[3]
		out.append(g)
	return out


## A straight-down orthographic projection for tests: screen = origin + sim * px (height lifts y).
static func flat_projector(origin: Vector2 = Vector2(100, 100), px: float = 50.0) -> WidgetProjector:
	return WidgetProjector.for_callable(func(sim: Vector2, h: float) -> Vector2: return origin + sim * px - Vector2(0, h * px * 0.8))
