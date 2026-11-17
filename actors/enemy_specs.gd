class_name EnemySpecs
extends RefCounted
## Presentation facts per enemy type: footprint, marker height, hover, and the TELEGRAPH shape drawn
## on the floor before an attack. Telegraph sizes are the simulation's real hit volumes
## (prototype core/tuning.ts ENEMY_STATS and core/enemies/*.ts; the strike hits a self whose centre
## is within reach + actorRadius of the enemy centre and inside the arc), so the decal is an honest
## read of where it is dangerous to stand (AI-04).

## Radius of a self (core/tuning.gd BASE.actor_radius; the specs read the live value).
const ACTOR_RADIUS: float = 0.3

const SHAPE_CONE: int = 0
const SHAPE_CIRCLE: int = 1
## Aimed line from the body toward the facing (turret / drone shots, boss volley fan).
const SHAPE_LINE: int = 2

## Hot orange: telegraphs and enemy shots, distinct from every cassette colour.
const DANGER: Color = Color("#ff6a1a")
const EYE: Color = Color("#ff6a1a")
## X-ray tint for occluded enemies.
const WARNING: Color = Color("#ff3d3d")


class Spec:
	extends RefCounted
	var type: StringName = &""
	## Footprint radius (sim stats.radius).
	var radius: float = 0.3
	## Height above the floor of the head marker (pips, target pip).
	var top: float = 0.9
	## Hovering units draw a ground shadow.
	var hover: float = 0.0
	var shape: int = SHAPE_CONE
	## Cone / circle: radius of the danger zone measured from the enemy centre (tiles).
	var reach: float = 1.0
	## Cone: total arc (radians).
	var arc: float = PI
	## Line: maximum length (the weapon's reach) and drawn width.
	var length: float = 0.0
	var width: float = 0.1

	static func make(p_type: StringName, p_radius: float, p_top: float, p_hover: float, p_shape: int, p_reach: float,
			p_arc_deg: float, p_length: float, p_width: float) -> Spec:
		var s := Spec.new()
		s.type = p_type
		s.radius = p_radius
		s.top = p_top
		s.hover = p_hover
		s.shape = p_shape
		s.reach = p_reach
		s.arc = deg_to_rad(p_arc_deg)
		s.length = p_length
		s.width = p_width
		return s


static var _specs: Dictionary[StringName, Spec] = {}


static func _ensure() -> void:
	if not _specs.is_empty():
		return
	# Every number is read from the simulation (core/tuning.gd ENEMY_STATS and the behaviours' own
	# arc constants), so the decal cannot drift from the real hit volume. A melee strike hits a self
	# whose centre is within reach + actor radius of the enemy centre and inside the arc.
	var ar: float = Tuning.BASE.actor_radius
	var g := Tuning.enemy_stats(EnemyType.GRUNT)
	_specs[EnemyType.GRUNT] = Spec.make(EnemyType.GRUNT, g.radius, 0.95, 0.0, SHAPE_CONE, g.reach + ar, rad_to_deg(GruntBehaviour.GRUNT_ARC), 0.0, 0.0)
	var st := Tuning.enemy_stats(EnemyType.STALKER)
	_specs[EnemyType.STALKER] = Spec.make(EnemyType.STALKER, st.radius, 0.9, 0.0, SHAPE_CONE, st.reach + ar, rad_to_deg(StalkerBehaviour.STALKER_ARC), 0.0, 0.0)
	# turret: an aimed bolt out to its reach.
	var tu := Tuning.enemy_stats(EnemyType.TURRET)
	_specs[EnemyType.TURRET] = Spec.make(EnemyType.TURRET, tu.radius, 0.95, 0.0, SHAPE_LINE, 0.0, 0.0, tu.reach, 0.08)
	var sh := Tuning.enemy_stats(EnemyType.SHIELDER)
	_specs[EnemyType.SHIELDER] = Spec.make(EnemyType.SHIELDER, sh.radius, 1.0, 0.0, SHAPE_CONE, sh.reach + ar, rad_to_deg(ShielderBehaviour.SHIELDER_ARC), 0.0, 0.0)
	# brute: a wide arc (hard to stand near it except squarely behind).
	var br := Tuning.enemy_stats(EnemyType.BRUTE)
	_specs[EnemyType.BRUTE] = Spec.make(EnemyType.BRUTE, br.radius, 1.45, 0.0, SHAPE_CONE, br.reach + ar, rad_to_deg(BruteBehaviour.BRUTE_ARC), 0.0, 0.0)
	# drone: an aimed bolt, hovering about a tile up.
	var dr := Tuning.enemy_stats(EnemyType.DRONE)
	_specs[EnemyType.DRONE] = Spec.make(EnemyType.DRONE, dr.radius, 1.4, 1.0, SHAPE_LINE, 0.0, 0.0, dr.reach, 0.08)
	# boss: cleave = radius + reach (other modes below); its volley bolts fly as far as a turret's.
	var bo := Tuning.enemy_stats(EnemyType.BOSS)
	_specs[EnemyType.BOSS] = Spec.make(EnemyType.BOSS, bo.radius, 2.8, 0.0, SHAPE_CONE, bo.radius + bo.reach + ar, rad_to_deg(BossBehaviour.BOSS_CLEAVE_ARC), tu.reach, 0.1)


static func spec(type: StringName) -> Spec:
	_ensure()
	return _specs.get(type, _specs[EnemyType.GRUNT])


# Boss attack modes (prototype core/enemies/boss.ts): which telegraph its commitment draws.
const BOSS_CLEAVE: StringName = &"cleave"
const BOSS_VOLLEY: StringName = &"volley"
const BOSS_SWEEP: StringName = &"sweep"
const BOSS_RECALL: StringName = &"recall"
## Volley: BOSS_VOLLEY_COUNT bolts fanned BOSS_VOLLEY_SPREAD apart.
const BOSS_VOLLEY_COUNT: int = BossBehaviour.BOSS_VOLLEY_COUNT
const BOSS_VOLLEY_SPREAD: float = BossBehaviour.BOSS_VOLLEY_SPREAD
## Sweep ring: shots out to BOSS_SWEEP_RANGE, radius BOSS_SWEEP_RADIUS.
const BOSS_SWEEP_RANGE: float = BossBehaviour.BOSS_SWEEP_RANGE
const BOSS_SWEEP_RADIUS: float = BossBehaviour.BOSS_SWEEP_RADIUS
## Memory strike: lands within BOSS_RECALL_RADIUS (+ actor radius) of the remembered place.
const BOSS_RECALL_RADIUS: float = BossBehaviour.BOSS_RECALL_RADIUS


## The boss's current mode: the 'enemyTelegraph' event detail when one was seen for this
## commitment, else inferred from the snapshot (recall is flagged in the snapshot; a target beyond
## cleave reach means a volley).
static func boss_mode(e: ActorInterp.EnemyFrame, event_mode: StringName, target_dist: float) -> StringName:
	if e.boss_recall:
		return BOSS_RECALL
	if event_mode == BOSS_CLEAVE or event_mode == BOSS_VOLLEY or event_mode == BOSS_SWEEP:
		return event_mode
	var s := spec(EnemyType.BOSS)
	if target_dist >= 0.0 and target_dist > s.reach:
		return BOSS_VOLLEY
	return BOSS_CLEAVE
