class_name EnemyStrike
extends RefCounted
## Momentum delivered to an enemy (prototype core/combat.ts EnemyStrike). Damage / knockback /
## stagger are derived from it by Combat.apply_strike unless overridden (has_* flags).
##
##     w.combat.strike_enemy(e, EnemyStrike.make(StrikeSource.of_tape(i), "light", m, dir, e.x, e.y))
##     EnemyStrike.make(src, "bolt", 1.0, dir, e.x, e.y).with_damage(1).with_knockback(0.0).with_stagger(0.25)

var source: StrikeSource = null
## "light" | "heavy" | projectile archetype | "bolt" | ... (SimEvent.detail of the 'hit').
var kind: String = ""
var momentum: float = 0.0
## Direction of the push, radians.
var dir: float = 0.0
## Where the strike landed (event position).
var x: float = 0.0
var y: float = 0.0
## Explicit damage points; absent (has_damage false) = Tuning.strike_damage(momentum, ...).
var damage: float = 0.0
var has_damage: bool = false
## Explicit knockback distance in tiles; absent = Tuning.strike_knockback(...).
var knockback: float = 0.0
var has_knockback: bool = false
## Explicit stagger in master seconds; absent = Tuning.strike_stagger(...).
var stagger: float = 0.0
var has_stagger: bool = false
## True for melee swings (killRefresh refunds the live self's dodge on a melee kill).
var melee: bool = false


static func make(p_source: StrikeSource, p_kind: String, p_momentum: float, p_dir: float, p_x: float, p_y: float) -> EnemyStrike:
	var s := EnemyStrike.new()
	s.source = p_source
	s.kind = p_kind
	s.momentum = p_momentum
	s.dir = p_dir
	s.x = p_x
	s.y = p_y
	return s


func with_damage(v: float) -> EnemyStrike:
	damage = v
	has_damage = true
	return self


func with_knockback(v: float) -> EnemyStrike:
	knockback = v
	has_knockback = true
	return self


func with_stagger(v: float) -> EnemyStrike:
	stagger = v
	has_stagger = true
	return self


func with_melee(v: bool = true) -> EnemyStrike:
	melee = v
	return self


## Copy (the source is copied too), for behaviours that answer HitResponse.replace(modified strike).
func copy() -> EnemyStrike:
	var s := EnemyStrike.make(source.copy() if source != null else null, kind, momentum, dir, x, y)
	s.damage = damage
	s.has_damage = has_damage
	s.knockback = knockback
	s.has_knockback = has_knockback
	s.stagger = stagger
	s.has_stagger = has_stagger
	s.melee = melee
	return s
