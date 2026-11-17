class_name Projectile
extends RefCounted
## A projectile in flight (prototype core/projectiles.ts Projectile; MISSILE-04, WEAPON-01..03).
## Simulated in master time by ProjectileSystem; created only through ProjectileSystem.spawn.
##
## Owner (prototype `owner: {tape} | {enemy}`): exactly one of owner_tape >= 0 / owner_enemy != "".

var id: int = 0
## Tape index of the self that fired it; -1 = an enemy's.
var owner_tape: int = -1
## Id of the enemy that fired it; "" = a self's.
var owner_enemy: String = ""
## RangedArchetype.* (self weapons, BOLT, SHOCK).
var archetype: StringName = &""
var x: float = 0.0
var y: float = 0.0
## Presentation height above the floor (arc shots).
var z: float = 0.0
## Heading, radians.
var dir: float = 0.0
## Tiles per master second.
var speed: float = 0.0
## Collision radius, tiles.
var radius: float = 0.0
## Remaining flight distance is range - travelled.
var range: float = 0.0
var travelled: float = 0.0
var alive: bool = true
## Momentum delivered on hit (same damage/knockback/stagger model as melee).
var momentum: float = 0.0
var passes_walls: bool = false
var hits_selves: bool = false
var hits_enemies: bool = true
## Enemies this projectile may still pass through after a hit (pierce).
var pierce_left: int = 0
## Ids already struck or passed ("enemy:<id>", "self:<index>", "core:<id>", "breakable:<id>"),
## never re-tested.
var struck: Dictionary[String, bool] = {}
## Missile lock (MISSILE-03); "" = none.
var target_id: String = ""
var spawn_sub: int = 0
## +1 / -1: the tape pass direction of the event that launched it.
var pass_dir: int = 1
## Per-projectile scratch (plain numbers), e.g. "blast", "turnRate".
var data: Dictionary[String, float] = {}
## The archetype object for `archetype`, looked up once at spawn (null when none is registered).
var arch: ProjectileArchetype = null


## True for a self's projectile.
func is_self_owned() -> bool:
	return owner_tape >= 0
