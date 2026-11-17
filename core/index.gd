class_name ODCore
extends RefCounted
## Public face of the simulation core (prototype core/index.ts; see game/contracts for the
## presentation side). Static forwards to the modules, plus ensure_registered().
##
## Extension points for later engineers:
##   - enemy types:           EnemyRegistry.register_enemy_behaviour (+ one file per type in core/enemies/)
##   - projectile archetypes: ProjectileSystem.register_projectile_archetype
##   - gear abilities:        ODSim.register_ability_handler


## Fill every lazily-built registry now: enemy behaviours, projectile archetypes (bolt, the five self
## weapons, shock) and ability handlers. Call once on the main thread before resolving on a worker
## thread; after it the registries are only read.
static func ensure_registered() -> void:
	EnemyRegistry.ensure_defaults()
	ProjectileSystem.get_projectile_archetype(RangedArchetype.BOLT)
	ODSim.ensure_defaults()


static func create_sim(config: SimConfig, errors: Array[String] = []) -> ODSim:
	return ODSim.create_sim(config, errors)


static func resolve_encounter(
	config: SimConfig, progress: Callable = Callable(), cancel: ODResolve.CancelToken = null, errors: Array[String] = []
) -> Resolution:
	return ODResolve.resolve_encounter(config, progress, cancel, errors)


static func build_boss_memory(level: LevelDef, committed: Array[ODTape]) -> BossMemory:
	return BossMemoryLib.build_boss_memory(level, committed)


static func recall_candidates(memory: BossMemory) -> Array[BossMemoryLib.RecallCandidate]:
	return BossMemoryLib.recall_candidates(memory)


static func tape_phase_at(tape: ODTape, sub: float) -> TapePhase:
	return ODTime.tape_phase_at(tape, sub)


static func horizon_subs(level: LevelDef) -> int:
	return int(ODTime.horizon_subs(level))


static func tape_ticks(level: LevelDef) -> int:
	return int(ODTime.tape_ticks(level))


static func sub_to_beat(level: LevelDef, sub: float) -> float:
	return ODTime.sub_to_beat(level, sub)


static func subs_per_beat(level: LevelDef) -> float:
	return ODTime.subs_per_beat(level)


static func ticks_per_beat(level: LevelDef) -> float:
	return ODTime.ticks_per_beat(level)


static func beat_to_sub(level: LevelDef, beat: float) -> float:
	return ODTime.beat_to_sub(level, beat)


static func span_bars(level: LevelDef, speed: float) -> float:
	return ODTime.span_bars(level, speed)


static func traversal_subs(tape: ODTape) -> int:
	return int(ODTime.traversal_subs(tape))


static func register_enemy_behaviour(b: EnemyBehaviour) -> void:
	EnemyRegistry.register_enemy_behaviour(b)


static func get_enemy_behaviour(type: StringName, errors: Array[String] = []) -> EnemyBehaviour:
	return EnemyRegistry.get_enemy_behaviour(type, errors)


static func registered_enemy_types() -> Array[StringName]:
	return EnemyRegistry.registered_enemy_types()


static func register_projectile_archetype(a: ProjectileArchetype) -> void:
	ProjectileSystem.register_projectile_archetype(a)


static func get_projectile_archetype(id: StringName) -> ProjectileArchetype:
	return ProjectileSystem.get_projectile_archetype(id)


static func fly_straight(w: ODSim, p: Projectile, dist: float = NAN) -> void:
	ProjectileSystem.fly_straight(w, p, dist)


static func default_hit_enemy(w: ODSim, p: Projectile, e: EnemyState) -> StringName:
	return ProjectileSystem.default_hit_enemy(w, p, e)


static func register_ability_handler(id: StringName, handler: Callable) -> void:
	ODSim.register_ability_handler(id, handler)
