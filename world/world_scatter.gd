class_name WorldScatter
extends RefCounted
## Ambient dressing so a level never looks bare (chapter 19: cracked masonry, cables, vents,
## vegetation growing through seams); port of prototype render/env/scatter.ts. Seeded by the level
## id, never randf(), so every view of a level (record, review, cinematic) is identical.
##
## Readability rule: ambient dressing never stands on the walkable floor as something that could be
## mistaken for an obstacle. Floor items are flat (tufts, pebbles, stains, paint); anything bulky
## goes on wall faces, wall tops or the cliff skirt, and nothing lands on a tile an entity uses.

const TUFT: StringName = &"tuft"
const PEBBLES: StringName = &"pebbles"
const STAIN: StringName = &"stain"
const FLOOR_PAINT: StringName = &"floorPaint"
const WALL_VINE: StringName = &"wallVine"
const WALL_PIPE: StringName = &"wallPipe"
const WALL_NEON: StringName = &"wallNeon"
const WALL_VENT: StringName = &"wallVent"
const WALL_CABLE: StringName = &"wallCable"
const TOP_GRASS: StringName = &"topGrass"
const TOP_RUBBLE: StringName = &"topRubble"
const CLIFF_ROOT: StringName = &"cliffRoot"
const CLIFF_ROCK: StringName = &"cliffRock"

## Kinds that stand on the walkable floor (must stay flat: tufts, pebbles, stains, paint).
const FLOOR_KINDS: Array[StringName] = [TUFT, PEBBLES, STAIN, FLOOR_PAINT]
## Maximum height of a floor item (world units) - lower than an ankle, never an obstacle.
const FLOOR_MAX_HEIGHT := 0.25

## Face ids: the camera-facing sides of a wall / cliff tile.
const FACE_E := 1
const FACE_S := 2


class Item:
	extends RefCounted
	var kind: StringName
	## Floor items: exact position. Wall / cliff items: centre of the owning tile (sim axes).
	var x: float
	var y: float
	## FACE_E (+X face) or FACE_S (+Z face) for wall / cliff items, 0 otherwise.
	var face: int = 0
	## 0..1 variant / scale parameters.
	var v: float
	var s: float


## Tiles that entities occupy or stand on; ambient dressing keeps off them.
static func occupied_tiles(level: LevelDef) -> Dictionary:
	var out := {}
	out[Vector2i(int(floor(level.start.x)), int(floor(level.start.y)))] = true
	for e: EntityDef in level.entities:
		if e is EnemyDef:
			out[Vector2i(int(floor((e as EnemyDef).x)), int(floor((e as EnemyDef).y)))] = true
		elif e is SwitchDef:
			out[Vector2i(int(floor((e as SwitchDef).x)), int(floor((e as SwitchDef).y)))] = true
		elif e is CoreDef:
			out[Vector2i(int(floor((e as CoreDef).x)), int(floor((e as CoreDef).y)))] = true
		elif e is DecorDef:
			out[Vector2i(int(floor((e as DecorDef).x)), int(floor((e as DecorDef).y)))] = true
		elif e is DoorDef:
			for cell: Vector2i in (e as DoorDef).cells:
				out[cell] = true
		elif e is PlateDef:
			out[Vector2i((e as PlateDef).c, (e as PlateDef).r)] = true
		elif e is BreakableDef:
			out[Vector2i((e as BreakableDef).c, (e as BreakableDef).r)] = true
		elif e is ExitDef:
			var x := e as ExitDef
			for dr: int in range(x.h):
				for dc: int in range(x.w):
					out[Vector2i(x.c + dc, x.r + dr)] = true
		elif e is LaserDef:
			# Keep the beam corridor clean so the hazard reads.
			var l := e as LaserDef
			var steps := int(ceil(l.from.distance_to(l.to) * 2.0)) + 1
			for i: int in range(steps + 1):
				var p := l.from.lerp(l.to, float(i) / float(steps))
				out[Vector2i(int(floor(p.x)), int(floor(p.y)))] = true
	return out


static func plan(level: LevelDef, layout: WorldLayout, pal: WorldPalette) -> Array[Item]:
	var rng := WorldRng.new(layout.level_seed ^ 0x5ca77e5)
	var busy := occupied_tiles(level)
	var out: Array[Item] = []
	var green := pal.overgrowth
	var tech := 0.25 if pal.floor_finish == WorldPalette.FINISH_STONE else (0.6 if pal.floor_finish == WorldPalette.FINISH_MIXED else 1.0)

	for f: WorldLayout.Floor in layout.floors:
		var ch := layout.at(f.c, f.r)
		if busy.has(Vector2i(f.c, f.r)) or ch == "=":
			continue
		var west_wall := layout.at(f.c - 1, f.r) == "#"
		var north_wall := layout.at(f.c, f.r - 1) == "#"
		var near_wall := west_wall or north_wall
		var overgrown := ch == ","
		var tuft_chance := 0.85 if overgrown else (0.35 if near_wall else 0.08) * green * 3.0
		if rng.chance(minf(0.9, tuft_chance)):
			var n := rng.range_i(2, 4) if overgrown else 1
			for i: int in range(n):
				# Hug the back edges of the tile so the playable centre stays clear.
				var x := f.c + (rng.range_f(0.08, 0.3) if near_wall and west_wall else rng.range_f(0.1, 0.9))
				var y := f.r + (rng.range_f(0.08, 0.3) if near_wall and north_wall else rng.range_f(0.1, 0.9))
				out.append(_item(TUFT, x, y, 0, rng.next(), rng.range_f(0.6, 1.1)))
		if rng.chance(0.22 if near_wall else 0.05):
			out.append(_item(PEBBLES, f.c + rng.range_f(0.15, 0.85), f.r + rng.range_f(0.15, 0.85), 0, rng.next(), rng.range_f(0.6, 1.0)))
		# Worn hazard paint across a tile (both reference tile sets carry painted markings).
		if ch != "," and rng.chance(0.045):
			out.append(_item(FLOOR_PAINT, f.c + 0.5, f.r + 0.5, 0, rng.next(), rng.range_f(0.7, 1.0)))
		if rng.chance(0.06 * (0.5 + tech)):
			out.append(_item(STAIN, f.c + rng.range_f(0.3, 0.7), f.r + rng.range_f(0.3, 0.7), 0, rng.next(), rng.range_f(0.5, 1.0)))

	for w: WorldLayout.Wall in layout.walls:
		if w.cut:
			continue
		var faces: Array[int] = []
		var ce := layout.at(w.c + 1, w.r)
		var cs := layout.at(w.c, w.r + 1)
		if WorldLayout.is_floor_char(ce) or ce == "=":
			faces.append(FACE_E)
		if WorldLayout.is_floor_char(cs) or cs == "=":
			faces.append(FACE_S)
		for face: int in faces:
			var roll := rng.next()
			var a := 0.28 * green * 3.0
			var b := a + 0.16 * tech
			if roll < a:
				out.append(_item(WALL_VINE, w.c + 0.5, w.r + 0.5, face, rng.next(), rng.range_f(0.5, 1.0)))
			elif roll < b:
				out.append(_item(WALL_NEON, w.c + 0.5, w.r + 0.5, face, rng.next(), rng.range_f(0.6, 1.0)))
			elif roll < b + 0.12:
				out.append(_item(WALL_PIPE, w.c + 0.5, w.r + 0.5, face, rng.next(), rng.range_f(0.4, 0.8)))
			elif roll < b + 0.2:
				out.append(_item(WALL_VENT, w.c + 0.5, w.r + 0.5, face, rng.next(), rng.range_f(0.7, 1.0)))
			elif roll < b + 0.27:
				out.append(_item(WALL_CABLE, w.c + 0.5, w.r + 0.5, face, rng.next(), rng.range_f(0.5, 1.0)))
		if rng.chance(0.35 * (green * 3.0 + 0.2)):
			out.append(_item(TOP_GRASS, w.c + 0.5, w.r + 0.5, 0, rng.next(), rng.range_f(0.6, 1.1)))
		elif rng.chance(0.25 if pal.floor_finish == WorldPalette.FINISH_STONE else 0.1):
			out.append(_item(TOP_RUBBLE, w.c + 0.5, w.r + 0.5, 0, rng.next(), rng.range_f(0.6, 1.0)))

	for cl: WorldLayout.Cliff in layout.cliffs:
		var faces: Array[int] = []
		if layout.at(cl.c + 1, cl.r) == " ":
			faces.append(FACE_E)
		if layout.at(cl.c, cl.r + 1) == " ":
			faces.append(FACE_S)
		for face: int in faces:
			if rng.chance(0.3 * (green * 2.0 + 0.25)):
				out.append(_item(CLIFF_ROOT, cl.c + 0.5, cl.r + 0.5, face, rng.next(), rng.range_f(0.5, 1.0)))
			if rng.chance(0.3):
				out.append(_item(CLIFF_ROCK, cl.c + 0.5, cl.r + 0.5, face, rng.next(), rng.range_f(0.5, 1.0)))
	return out


static func _item(kind: StringName, x: float, y: float, face: int, v: float, s: float) -> Item:
	var it := Item.new()
	it.kind = kind
	it.x = x
	it.y = y
	it.face = face
	it.v = v
	it.s = s
	return it


## Transform that puts a node's local +Z out of a wall face of tile (c, r), at height h, offset
## `along` the face and `out` away from it (prototype mountOnFace).
static func mount_on_face(c: int, r: int, face: int, h: float, along: float = 0.0, out: float = 0.012) -> Transform3D:
	if face == FACE_E:
		return Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(c + 1 + out, h, r + 0.5 - along))
	return Transform3D(Basis.IDENTITY, Vector3(c + 0.5 + along, h, r + 1 + out))
