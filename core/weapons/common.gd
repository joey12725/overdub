class_name WeaponCommon
extends RefCounted
## Shared machinery for the player's ranged weapons (WEAPON-01..03, MISSILE-01..04).
## Port of prototype/src/core/weapons/common.ts.
##
## The rule is "fixed trigger, simulated projectile" (Revision 1): a tape records when, where and in
## which direction it fired; everything after the launch is a world object simulated in master time
## against the current run. Every number comes from the equipped RangedWeaponDef, so an archetype
## file only decides how its projectile moves and what stops it.
##
## Momentum. A projectile delivers `def.impact` through the same momentum → damage / knockback /
## stagger arithmetic as melee (Tuning.strike_damage / strike_knockback / strike_stagger) and the
## loadout's damage / knockback / stagger modifiers. Tape speed is deliberately NOT multiplied in:
## a melee swing's momentum carries the tape speed because the swing and the body move in the
## self's local time (MOM-01), but a projectile's speed (RangedWeaponDef.speed) is already a
## master-time property of the object once it leaves the weapon. Multiplying again would count tape
## speed for something that no longer lives on the tape. The ranged weapon has no efficiency fields
## of its own, so its efficiencies are 1; the melee weapon's efficiencies never touch a shot.

## Momentum → effect multiplier for projectiles (RangedWeaponDef has no efficiency fields).
const RANGED_EFFICIENCY: float = 1.0

## Arc shells and phase shots stop this far inside the map edge, so they never leave the grid.
const EDGE_MARGIN: float = 1e-3


## Projectile speed of the equipped weapon, tiles per master second (StatMods.projectileSpeed applies).
static func shot_speed(w: ODSim) -> float:
	return w.loadout.ranged.speed * w.loadout.mods.projectile_speed


## Collision radius of each projectile of a weapon, tiles.
static func shot_radius(def: RangedWeaponDef) -> float:
	return def.radius if def.has_radius and def.radius > 0.0 else Tuning.SELF_SHOT_RADIUS


## Enemies one projectile may pass through, from the weapon definition (0 = stops at the first).
## (RangedWeaponDef.pierce is already an int, so the prototype's Math.floor is a no-op here.)
static func pierce_count(def: RangedWeaponDef) -> int:
	return def.pierce if def.pierce > 0 else 0


## The spawn spec of one of a self's shots, filled from the equipped weapon. Projectiles start at the
## self's centre (its recorded position at the launch instant, PLAY-01): a muzzle offset could poke
## through a wall the self is standing against.
static func self_shot(w: ODSim, self_actor: SelfActor, archetype: StringName, dir: float, pass_dir: int) -> SpawnSpec:
	var def: RangedWeaponDef = w.loadout.ranged
	var spec := SpawnSpec.new()
	spec.owner_tape = self_actor.index
	spec.archetype = archetype
	spec.x = self_actor.pose.x
	spec.y = self_actor.pose.y
	spec.dir = dir
	spec.speed = shot_speed(w)
	spec.radius = shot_radius(def)
	spec.range = def.max_range
	spec.momentum = def.impact
	spec.passes_walls = def.passes_walls
	spec.set_hits_selves(false)
	spec.hits_enemies = true
	spec.pierce = pierce_count(def)
	spec.pass_dir = pass_dir
	spec.data = {"blast": def.blast if def.blast > 0.0 else 0.0}
	return spec


## A projectile's strike on an enemy: the melee momentum model with ranged efficiencies (module doc).
static func projectile_strike(w: ODSim, p: Projectile, e: EnemyState, momentum: float, dir: float) -> EnemyStrike:
	var mods: StatMods = w.loadout.mods
	var source := StrikeSource.of_tape(p.owner_tape) if p.owner_tape >= 0 else StrikeSource.of_enemy(p.owner_enemy)
	return EnemyStrike.make(source, String(p.archetype), momentum, dir, e.x, e.y) \
		.with_damage(Tuning.strike_damage(momentum, RANGED_EFFICIENCY, mods.damage)) \
		.with_knockback(Tuning.strike_knockback(momentum, RANGED_EFFICIENCY, mods.knockback, mods.knockback_cap, e.stats.mass)) \
		.with_stagger(Tuning.strike_stagger(momentum, RANGED_EFFICIENCY, mods.stagger, e.stats.poise))


## Strike every living enemy whose body overlaps a blast of `radius` centred on (x, y), each pushed
## away from the centre. Walls and closed doors shield an enemy from the blast unless the centre
## itself sits in a shot-blocking tile (a shell landing on top of a wall bursts over it). Returns how
## many enemies were caught. `exclude` is an enemy already struck directly by the same projectile
## ("" = none).
static func detonate(w: ODSim, p: Projectile, x: float, y: float, radius: float, exclude: String = "") -> int:
	if not (radius > 0.0):
		return 0
	var in_solid: bool = w.grid.blocks_shot(floori(x), floori(y))
	var n := 0
	for e: EnemyState in w.enemies:
		if not e.alive or (not exclude.is_empty() and e.id == exclude):
			continue
		var dx := e.x - x
		var dy := e.y - y
		# Math.hypot: ODGrid.hypot reproduces V8 bit for bit (a naive sqrt can differ in the last bit).
		var d := ODGrid.hypot(dx, dy)
		if d > radius + e.stats.radius:
			continue
		if not in_solid and w.grid.segment_blocked(x, y, e.x, e.y, true):
			continue
		p.struck["enemy:" + e.id] = true
		var dir := atan2(dy, dx) if d > 1e-9 else p.dir
		w.combat.strike_enemy(e, projectile_strike(w, p, e, p.momentum, dir))
		n += 1
	return n


## Contact with an enemy for every self projectile that flies straight (missile, pierce, phase,
## burst): deliver the momentum, then keep going while the weapon may still pierce (NEW-04). A
## pass-through is announced as its own 'projectileHit'; the stopping hit is announced by fly_straight.
## A stopping hit bursts the weapon's blast radius around the struck enemy, if it has one.
static func hit_enemy_straight(w: ODSim, p: Projectile, e: EnemyState) -> StringName:
	p.struck["enemy:" + e.id] = true
	w.combat.strike_enemy(e, projectile_strike(w, p, e, p.momentum, p.dir))
	if p.pierce_left > 0:
		p.pierce_left -= 1
		w.emit(SimEvent.make(0, SimEventType.PROJECTILE_HIT, e.x, e.y).with_id(e.id).with_tape(owner_tape(p)) \
			.with_dir(p.dir).with_detail(String(p.archetype) + ":pass"))
		return ProjectileArchetype.VERDICT_PASS
	detonate(w, p, e.x, e.y, float(p.data.get("blast", 0.0)), e.id)
	return ProjectileArchetype.VERDICT_STOP


## A straight shot stopping against a wall bursts its blast radius at the impact point.
static func hit_wall_straight(w: ODSim, p: Projectile, x: float, y: float) -> StringName:
	detonate(w, p, x, y, float(p.data.get("blast", 0.0)))
	return ProjectileArchetype.VERDICT_STOP


## The tape that owns a projectile, or -1 for an enemy's.
static func owner_tape(p: Projectile) -> int:
	return p.owner_tape


## Distance from (x, y) along `dir` to the edge of the map rectangle [0, cols] × [0, rows]. INF
## never comes back: every direction leaves a finite rectangle.
static func distance_to_edge(grid: ODGrid, x: float, y: float, dir: float) -> float:
	var ux := cos(dir)
	var uy := sin(dir)
	var t := INF
	if ux > 1e-12:
		t = minf(t, (grid.cols - x) / ux)
	elif ux < -1e-12:
		t = minf(t, -x / ux)
	if uy > 1e-12:
		t = minf(t, (grid.rows - y) / uy)
	elif uy < -1e-12:
		t = minf(t, -y / uy)
	return t if t > 0.0 else 0.0
