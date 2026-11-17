class_name WorldLayout
extends RefCounted
## Pure level -> placement layout (port of prototype render/env/layout.ts). No nodes here, so the
## counts and the cutaway rule are unit-tested headless; WorldBuilder turns a layout into meshes.
##
## Scene convention (RenderCtx): tile (c, r) covers scene X in [c, c+1), Z in [r, r+1); the floor
## top is at Y = 0. The camera sits on the +X / +Z side, so a tile's "front" neighbours are (c+1, r)
## and (c, r+1) and its "behind" neighbours are (c-1, r) and (c, r-1).
##
## Map legend (prototype core/types.ts): '#' wall, '.' floor, ':' grate, ',' overgrown, '~' rune
## floor, '=' low barrier, ' ' void.

## Floor slab thickness (the kit's floor tiles and wall bases hang 0.2 below the walkable top).
const TILE_THICK := 0.2
## Height of a wall cut away because it would hide the playfield behind it (chapter 16 cutaways).
const WALL_CUT_HEIGHT := 0.45
const BARRIER_HEIGHT := 0.55

const FLOOR_SOLID: StringName = &"solid"
const FLOOR_ALT: StringName = &"alt"
const FLOOR_CRACKED: StringName = &"cracked"
const FLOOR_GRATE: StringName = &"grate"
const FLOOR_OVERGROWN: StringName = &"overgrown"
const FLOOR_RUNE: StringName = &"rune"
const FLOOR_KINDS: Array[StringName] = [FLOOR_SOLID, FLOOR_ALT, FLOOR_CRACKED, FLOOR_GRATE, FLOOR_OVERGROWN, FLOOR_RUNE]

const SIDE_N := 0
const SIDE_E := 1
const SIDE_S := 2
const SIDE_W := 3

const WALL_STEPS := {
	&"upper": [1.25, 1.5, 1.5, 1.8, 2.15],
	&"mid": [1.5, 1.7, 1.7, 1.95],
	&"lower": [1.8, 1.8, 2.0, 2.0, 2.3],
	&"core": [2.0, 2.0, 2.3, 2.6],
}


class Floor:
	extends RefCounted
	var c: int
	var r: int
	var kind: StringName
	## Quarter turns of the tile top, for variety.
	var rot: int
	## 0..1 deterministic tone variation.
	var shade: float
	## 0..1 contact darkening from walls standing behind this tile.
	var ao: float


class Wall:
	extends RefCounted
	var c: int
	var r: int
	var height: float
	## True when the wall was cut low so it does not hide floor behind it.
	var cut: bool
	## True when the wall stands on the level's outer rim (back walls).
	var rim: bool
	var shade: float


class Barrier:
	extends RefCounted
	var c: int
	var r: int
	## Which neighbours are barriers or walls (rails connect toward them).
	var n: bool
	var e: bool
	var s: bool
	var w: bool


class Cliff:
	extends RefCounted
	var c: int
	var r: int
	## Depth of the skirt below the tile underside.
	var depth: float
	var shade: float


class Edge:
	extends RefCounted
	var c: int
	var r: int
	## SIDE_*: the outward side with void beyond.
	var side: int
	## The tile is a wall block (no floor lip).
	var wall: bool


var cols: int = 0
var rows: int = 0
var floors: Array[Floor] = []
var walls: Array[Wall] = []
var barriers: Array[Barrier] = []
var cliffs: Array[Cliff] = []
var edges: Array[Edge] = []
## Level extents in scene units: x = min X, y = min Z, z = max X, w = max Z.
var min_x: float = 0.0
var min_z: float = 0.0
var max_x: float = 1.0
var max_z: float = 1.0
## Tallest wall top and deepest cliff bottom (negative).
var max_y: float = 0.0
var min_y: float = -TILE_THICK
var level_seed: int = 0
var _map: Array[String] = []
var _heights: PackedFloat32Array = PackedFloat32Array()


static func is_floor_char(ch: String) -> bool:
	return ch == "." or ch == ":" or ch == "," or ch == "~"


## Any tile that has ground under it (floor, wall or barrier).
static func is_solid_ground(ch: String) -> bool:
	return ch != " " and ch != ""


static func wall_height_for(theme: StringName, n: float, rim: bool) -> float:
	var list: Array = WALL_STEPS.get(theme, WALL_STEPS[&"upper"])
	var h: float = list[int(floor(n * list.size())) % list.size()]
	# The outer rim reads as the room's back wall; give it a touch more presence.
	return h + 0.25 if rim else h


## Map character at (c, r); " " outside the map.
func at(c: int, r: int) -> String:
	if r < 0 or r >= rows or c < 0:
		return " "
	var row: String = _map[r]
	return row[c] if c < row.length() else " "


func is_wall(c: int, r: int) -> bool:
	return at(c, r) == "#"


## Wall height at (c, r), 0 when not a wall.
func wall_height(c: int, r: int) -> float:
	if c < 0 or r < 0 or c >= cols or r >= rows:
		return 0.0
	return _heights[r * cols + c]


## Top surface height at a sim point: wall top, barrier top, or 0 on the floor (and in the void).
func surface_height(x: float, y: float) -> float:
	var c := int(floor(x))
	var r := int(floor(y))
	var ch := at(c, r)
	if ch == "#":
		return wall_height(c, r)
	if ch == "=":
		return BARRIER_HEIGHT
	return 0.0


## Level bounds as an AABB in scene units (Y from the deepest cliff to the tallest wall).
func bounds_aabb() -> AABB:
	return AABB(Vector3(min_x, min_y, min_z), Vector3(max_x - min_x, max_y - min_y, max_z - min_z))


func count_floor_kind(kind: StringName) -> int:
	var n := 0
	for f: Floor in floors:
		if f.kind == kind:
			n += 1
	return n


static func compute(level: LevelDef) -> WorldLayout:
	var L := WorldLayout.new()
	L._map = level.map.duplicate()
	L.rows = L._map.size()
	L.cols = 0
	for row: String in L._map:
		L.cols = maxi(L.cols, row.length())
	L.level_seed = WorldRng.hash_string(level.id)
	L._heights.resize(L.rows * L.cols)
	var sd0 := L.level_seed
	var mnx := INF
	var mnz := INF
	var mxx := -INF
	var mxz := -INF
	var mxy := 0.0
	var mny := -TILE_THICK

	for r: int in range(L.rows):
		for c: int in range(L.cols):
			var ch := L.at(c, r)
			if not is_solid_ground(ch):
				continue
			mnx = minf(mnx, c)
			mnz = minf(mnz, r)
			mxx = maxf(mxx, c + 1)
			mxz = maxf(mxz, r + 1)
			var n := WorldRng.tile_noise(sd0, c, r)
			var n2 := WorldRng.tile_noise(sd0 ^ 0x9e3779b9, c, r)

			if ch == "#":
				# Cutaway (chapter 16): a wall that has open floor behind it, from the camera's point
				# of view, is cut low so it can never hide a self, an enemy tell or a spark.
				var hides := L._open(c - 1, r) or L._open(c, r - 1) or L._open(c - 1, r - 1)
				var rim := not L._ground(c - 1, r) or not L._ground(c, r - 1)
				var w := Wall.new()
				w.c = c
				w.r = r
				w.cut = hides
				w.rim = rim
				w.height = WALL_CUT_HEIGHT if hides else wall_height_for(level.theme, n, rim)
				w.shade = n2
				L.walls.append(w)
				L._heights[r * L.cols + c] = w.height
				mxy = maxf(mxy, w.height)
			else:
				var kind: StringName
				if ch == ":":
					kind = FLOOR_GRATE
				elif ch == ",":
					kind = FLOOR_OVERGROWN
				elif ch == "~":
					kind = FLOOR_RUNE
				else:
					kind = FLOOR_SOLID if n < 0.58 else (FLOOR_ALT if n < 0.86 else FLOOR_CRACKED)
				var w_behind := L.is_wall(c - 1, r)
				var n_behind := L.is_wall(c, r - 1)
				var corner := L.is_wall(c - 1, r - 1) and not w_behind and not n_behind
				var f := Floor.new()
				f.c = c
				f.r = r
				f.kind = kind
				f.rot = int(floor(n2 * 4.0)) & 3
				f.shade = n2
				f.ao = minf(1.0, (0.55 if w_behind else 0.0) + (0.55 if n_behind else 0.0) + (0.3 if corner else 0.0))
				L.floors.append(f)
				if ch == "=":
					var b := Barrier.new()
					b.c = c
					b.r = r
					b.n = L._links(c, r - 1)
					b.e = L._links(c + 1, r)
					b.s = L._links(c, r + 1)
					b.w = L._links(c - 1, r)
					L.barriers.append(b)
					mxy = maxf(mxy, BARRIER_HEIGHT)

			var sides := [[SIDE_N, c, r - 1], [SIDE_E, c + 1, r], [SIDE_S, c, r + 1], [SIDE_W, c - 1, r]]
			for sd: Array in sides:
				if not L._ground(sd[1], sd[2]):
					var e := Edge.new()
					e.c = c
					e.r = r
					e.side = sd[0]
					e.wall = ch == "#"
					L.edges.append(e)

			var exposed := not L._ground(c + 1, r) or not L._ground(c, r + 1) or not L._ground(c - 1, r) or not L._ground(c, r - 1)
			if exposed:
				# Chunky, irregular skirt so the level reads as a floating diorama (R03 / R04 boards).
				var cl := Cliff.new()
				cl.c = c
				cl.r = r
				cl.depth = 1.1 + floor(WorldRng.tile_noise(sd0 ^ 0x51ed27, c, r) * 4.0) * 0.35
				cl.shade = n
				L.cliffs.append(cl)
				mny = minf(mny, -TILE_THICK - cl.depth)

	if mnx == INF:
		mnx = 0.0
		mnz = 0.0
		mxx = maxf(1.0, L.cols)
		mxz = maxf(1.0, L.rows)
	L.min_x = mnx
	L.min_z = mnz
	L.max_x = mxx
	L.max_z = mxz
	L.max_y = mxy
	L.min_y = mny
	return L


func _ground(c: int, r: int) -> bool:
	return is_solid_ground(at(c, r))


func _open(c: int, r: int) -> bool:
	var ch := at(c, r)
	return is_floor_char(ch) or ch == "="


func _links(c: int, r: int) -> bool:
	var ch := at(c, r)
	return ch == "=" or ch == "#"
