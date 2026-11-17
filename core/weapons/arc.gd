class_name ArcArchetype
extends ProjectileArchetype
## Arc / vertical shot (WEAPON-03, NEW-05): a lobbed shell.
## Port of prototype/src/core/weapons/arc.ts (the prototype's ARC = ArcArchetype.new()).
##
##   - It travels along the recorded direction to a landing point `def.range` tiles away (never less
##     than `def.minRange`), cut short only by the map edge.
##   - In flight it is above everything: low barriers, walls of ordinary height, closed doors and
##     enemies do not touch it. The snapshot reports its height `z` (> 0 in flight, peak
##     ARC_PEAK_HEIGHT at mid-flight) so the renderer can draw the lob.
##   - On landing it bursts: every living enemy whose body overlaps the blast radius (def.blast, at
##     least ARC_MIN_BLAST) is struck with the weapon's impact and pushed away from the centre.
##     Walls shield enemies from the blast unless the shell lands on top of the wall itself.
##   - Speed is horizontal tiles per master second, like every other projectile.


func _init() -> void:
	id = RangedArchetype.ARC


## Height of a shell that has covered fraction `f` of its flight (a parabola peaking mid-flight).
static func arc_height(f: float) -> float:
	var t := 0.0 if f < 0.0 else (1.0 if f > 1.0 else f)
	return 4.0 * Tuning.ARC_PEAK_HEIGHT * t * (1.0 - t)


## Blast radius an arc weapon actually uses.
static func arc_blast(blast: float) -> float:
	return blast if blast > Tuning.ARC_MIN_BLAST else Tuning.ARC_MIN_BLAST


func launch(w: ODSim, self_actor: SelfActor, ev: TapeEvent, pass_dir: int) -> int:
	var def: RangedWeaponDef = w.loadout.ranged
	var spec := WeaponCommon.self_shot(w, self_actor, RangedArchetype.ARC, ev.dir, pass_dir)
	# `def.minRange ?? 0`: an absent minimum reads as 0.
	var wanted := maxf(def.min_range if def.has_min_range else 0.0, def.max_range)
	var edge := WeaponCommon.distance_to_edge(w.grid, self_actor.pose.x, self_actor.pose.y, ev.dir) - WeaponCommon.EDGE_MARGIN
	spec.range = maxf(0.0, minf(wanted, edge))
	spec.passes_walls = true
	spec.hits_enemies = false
	spec.pierce = 0
	spec.data = {"blast": arc_blast(def.blast)}
	w.projectiles.spawn(w, spec)
	return 1


func step(w: ODSim, p: Projectile) -> void:
	var remaining: float = p.range - p.travelled
	var d := minf(p.speed / OD.SUB_HZ, remaining if remaining > 0.0 else 0.0)
	p.x += cos(p.dir) * d
	p.y += sin(p.dir) * d
	p.travelled += d
	if p.travelled < p.range - 1e-9:
		p.z = arc_height(p.travelled / p.range)
		return
	p.z = 0.0
	p.alive = false
	var radius: float = float(p.data.get("blast", Tuning.ARC_MIN_BLAST))
	w.emit(SimEvent.make(0, SimEventType.PROJECTILE_HIT, p.x, p.y).with_tape(WeaponCommon.owner_tape(p)) \
		.with_dir(p.dir).with_power(radius).with_detail("arc:land"))
	WeaponCommon.detonate(w, p, p.x, p.y, radius)
