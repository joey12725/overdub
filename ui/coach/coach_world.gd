class_name CoachWorld
extends RefCounted
## World positions for coach marks, in sim tiles (x, y): selves, sparks, enemies, mechanisms and the
## nearest entity of a kind. Reads the FrameSnapshot first (moving things), then the LevelDef
## (fixed things). Node-free. Kinds: enemy (alive), breakable (unbroken), switch, plate, door, core,
## exit, laser, trap.


## Position of the self of `tape` (its projection, even when desynced), or Vector2.INF.
static func self_pos(ctx: CoachContext, tape: int) -> Vector2:
	var a := ctx.actor(tape)
	return Vector2(a.x, a.y) if a != null else Vector2.INF


## Its recovery spark while desynced, else the self.
static func spark_pos(ctx: CoachContext, tape: int) -> Vector2:
	var a := ctx.actor(tape)
	if a == null:
		return Vector2.INF
	return a.spark if a.has_spark else Vector2(a.x, a.y)


## Enemy (snapshot) or entity (level) position by id, or Vector2.INF.
static func entity_pos(ctx: CoachContext, id: String) -> Vector2:
	if id == "":
		return Vector2.INF
	if ctx.snap != null:
		for e: EnemySnap in ctx.snap.enemies:
			if e.id == id:
				return Vector2(e.x, e.y)
	if ctx.level != null:
		for ent: EntityDef in ctx.level.entities:
			if ent.id == id:
				return def_pos(ent)
	return Vector2.INF


## "enemy" | "mech" | "trap" | "" for an event's id.
static func target_kind(ctx: CoachContext, id: String) -> String:
	if id == "":
		return ""
	if ctx.snap != null:
		for e: EnemySnap in ctx.snap.enemies:
			if e.id == id:
				return "enemy"
	if ctx.level != null:
		for ent: EntityDef in ctx.level.entities:
			if ent.id == id:
				if ent.kind == EntityKind.ENEMY:
					return "enemy"
				if String(ent.kind) == "trap":
					return "trap"
				return "mech"
	return ""


## Centre of a level entity, in tiles.
static func def_pos(ent: EntityDef) -> Vector2:
	if ent is EnemyDef:
		return Vector2((ent as EnemyDef).x, (ent as EnemyDef).y)
	if ent is SwitchDef:
		return Vector2((ent as SwitchDef).x, (ent as SwitchDef).y)
	if ent is CoreDef:
		return Vector2((ent as CoreDef).x, (ent as CoreDef).y)
	if ent is PlateDef:
		return Vector2((ent as PlateDef).c + 0.5, (ent as PlateDef).r + 0.5)
	if ent is BreakableDef:
		return Vector2((ent as BreakableDef).c + 0.5, (ent as BreakableDef).r + 0.5)
	if ent is ExitDef:
		var x := ent as ExitDef
		return Vector2(x.c + x.w * 0.5, x.r + x.h * 0.5)
	if ent is DoorDef:
		var dd := ent as DoorDef
		if dd.cells.is_empty():
			return Vector2.INF
		var s := Vector2.ZERO
		for c: Vector2i in dd.cells:
			s += Vector2(c.x + 0.5, c.y + 0.5)
		return s / dd.cells.size()
	if ent is LaserDef:
		return ((ent as LaserDef).from + (ent as LaserDef).to) * 0.5
	# traps and future kinds: duck-typed x/y or c/r
	var px: Variant = ent.get("x")
	var py: Variant = ent.get("y")
	if (px is float or px is int) and (py is float or py is int):
		return Vector2(float(px), float(py))
	var pc: Variant = ent.get("c")
	var pr: Variant = ent.get("r")
	if (pc is int or pc is float) and (pr is int or pr is float):
		return Vector2(float(pc) + 0.5, float(pr) + 0.5)
	return Vector2.INF


## The nearest entity of `kind` to `from` (tiles), or Vector2.INF.
static func nearest(ctx: CoachContext, kind: String, from: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	if kind == "enemy":
		if ctx.snap != null and not ctx.snap.enemies.is_empty():
			for e: EnemySnap in ctx.snap.enemies:
				if not e.alive:
					continue
				var p := Vector2(e.x, e.y)
				var dd := p.distance_to(from)
				if dd < best_d:
					best_d = dd
					best = p
			return best
	if ctx.level == null:
		return best
	for ent: EntityDef in ctx.level.entities:
		if String(ent.kind) != kind:
			continue
		if kind == "breakable" and ctx.snap != null:
			var m := _mech(ctx, ent.id)
			if m != null and m.on:
				continue # broken
		var p := def_pos(ent)
		if p == Vector2.INF:
			continue
		var dd := p.distance_to(from)
		if dd < best_d:
			best_d = dd
			best = p
	return best


static func _mech(ctx: CoachContext, id: String) -> MechSnap:
	for m: MechSnap in ctx.snap.mechs:
		if m.id == id:
			return m
	return null
