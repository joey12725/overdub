class_name CinemaScene
extends RefCounted
## Read-only view of a resolved encounter for the editor: beat <-> substep, positions of selves and
## enemies at any beat (from the snapshots, which may be dense, as Resolution.frames, or sparse, as
## the goldens' 60-substep samples), mechanism positions, and rooms.
##
## Rooms are a flood fill of the map's non-wall tiles, with door and breakable cells as separators,
## so "a different room" is what a player would call one.

var level: LevelDef
var res: Resolution
var subs_per_beat: float = 120.0
var horizon_beats: int = 0
## Frames sorted by sub (Resolution.frames already is).
var frames: Array[FrameSnapshot] = []
var _frame_subs: PackedInt32Array = PackedInt32Array()

var cols: int = 0
var rows: int = 0
## Room id per tile (r * cols + c); -1 = wall / door / outside.
var _room: PackedInt32Array = PackedInt32Array()
var room_rects: Array[Rect2] = []
var level_rect: Rect2 = Rect2()
## Mechanism / enemy start positions by id (sim axes).
var entity_points: Dictionary[String, Vector2] = {}
var entity_kinds: Dictionary[String, StringName] = {}
## Enemy type by id.
var enemy_types: Dictionary[String, StringName] = {}
## Selves present in the run (tape indices, ascending).
var tapes: Array[int] = []


static func create(p_res: Resolution, p_level: LevelDef) -> CinemaScene:
	var s := CinemaScene.new()
	s.res = p_res
	s.level = p_level
	var bpm := p_level.bpm if p_level != null and p_level.bpm > 0.0 else 120.0
	s.subs_per_beat = float(OD.SUB_HZ) * 60.0 / bpm
	var hs := p_res.horizon_subs if p_res != null else 0
	if hs > 0:
		s.horizon_beats = int(ceil(float(hs) / s.subs_per_beat - 1e-6))
	elif p_level != null:
		s.horizon_beats = p_level.horizon_bars * OD.BEATS_PER_BAR
	s.horizon_beats = maxi(s.horizon_beats, CinemaGrammar.MIN_SHOT_BEATS)
	if p_res != null:
		s.frames = p_res.frames
	for f: FrameSnapshot in s.frames:
		s._frame_subs.append(f.sub)
		for a: ActorSnap in f.actors:
			if not s.tapes.has(a.tape):
				s.tapes.append(a.tape)
	s.tapes.sort()
	s._build_geometry()
	return s


func beat_of_sub(sub: int) -> float:
	return float(sub) / subs_per_beat


func beat_of(ev: SimEvent) -> float:
	return float(ev.sub) / subs_per_beat


# ───────────────────────────── snapshots ─────────────────────────────

## Index of the last frame at or before `sub` (0 when before the first), -1 when there are none.
func _frame_index(sub: int) -> int:
	if _frame_subs.is_empty():
		return -1
	var i := _frame_subs.bsearch(sub, false) - 1
	if i < 0:
		return 0
	return mini(i, _frame_subs.size() - 1)


func frame_at_beat(beat: float) -> FrameSnapshot:
	var i := _frame_index(int(floor(beat * subs_per_beat)))
	return frames[i] if i >= 0 else null


## Interpolated projection position of self `tape` at `beat`; `fallback` when unknown.
func actor_pos(tape: int, beat: float, fallback: Vector2 = Vector2.INF) -> Vector2:
	var sub := beat * subs_per_beat
	var i := _frame_index(int(floor(sub)))
	if i < 0:
		return _fallback(fallback)
	var a := frames[i].actor(tape)
	if a == null:
		return _fallback(fallback)
	var p := Vector2(a.x, a.y)
	if i + 1 < frames.size():
		var b := frames[i + 1].actor(tape)
		var s0 := float(frames[i].sub)
		var s1 := float(frames[i + 1].sub)
		if b != null and s1 > s0 and sub > s0:
			var k := clampf((sub - s0) / (s1 - s0), 0.0, 1.0)
			# A repeat cut teleports: do not interpolate across a jump.
			if Vector2(b.x, b.y).distance_to(p) < 3.0:
				p = p.lerp(Vector2(b.x, b.y), k)
	return p


## Where the self is "really" (its recovery spark while desynced), else its projection.
func actor_body_pos(tape: int, beat: float) -> Vector2:
	var f := frame_at_beat(beat)
	if f != null:
		var a := f.actor(tape)
		if a != null and not a.synced and a.has_spark:
			return a.spark
	return actor_pos(tape, beat)


func actor_life(tape: int, beat: float) -> int:
	var f := frame_at_beat(beat)
	if f == null:
		return OD.LifeState.ALIVE
	var a := f.actor(tape)
	return a.life if a != null else OD.LifeState.ALIVE


func actor_anim(tape: int, beat: float) -> StringName:
	var f := frame_at_beat(beat)
	if f == null:
		return AnimState.IDLE
	var a := f.actor(tape)
	return a.anim if a != null else AnimState.IDLE


func enemy_pos(id: String, beat: float, fallback: Vector2 = Vector2.INF) -> Vector2:
	var f := frame_at_beat(beat)
	if f != null:
		var e := f.enemy(id)
		if e != null:
			return Vector2(e.x, e.y)
	if fallback != Vector2.INF:
		return fallback
	return entity_points.get(id, level_centre())


## Centroid of the selves that are alive (not ghost) at `beat`; every self if none; level centre if
## there are no snapshots.
func crowd_pos(beat: float, only: Array[int] = []) -> Vector2:
	var f := frame_at_beat(beat)
	if f == null or f.actors.is_empty():
		return level_centre()
	var sum := Vector2.ZERO
	var n := 0
	for a: ActorSnap in f.actors:
		if not only.is_empty() and not only.has(a.tape):
			continue
		if a.life == OD.LifeState.GHOST and only.is_empty():
			continue
		sum += actor_pos(a.tape, beat)
		n += 1
	if n == 0:
		for a: ActorSnap in f.actors:
			sum += actor_pos(a.tape, beat)
			n += 1
	return sum / float(n) if n > 0 else level_centre()


## Largest distance from `centre` to any of the given selves at `beat` (0 when none).
func crowd_radius(beat: float, centre: Vector2, only: Array[int] = []) -> float:
	var f := frame_at_beat(beat)
	if f == null:
		return 0.0
	var r := 0.0
	for a: ActorSnap in f.actors:
		if not only.is_empty() and not only.has(a.tape):
			continue
		r = maxf(r, actor_pos(a.tape, beat).distance_to(centre))
	return r


func _fallback(fallback: Vector2) -> Vector2:
	return fallback if fallback != Vector2.INF else (level.start if level != null else Vector2.ZERO)


# ───────────────────────────── geometry ─────────────────────────────

func level_centre() -> Vector2:
	return level_rect.get_center()


## Diameter of the level in tiles (WIDE span).
func level_span() -> float:
	return maxf(level_rect.size.x, level_rect.size.y) * 1.05


func room_of(p: Vector2) -> int:
	if cols <= 0:
		return 0
	var c := int(floor(p.x))
	var r := int(floor(p.y))
	var id := _room_at(c, r)
	if id >= 0:
		return id
	# On a door or wall cell: the nearest room tile within two tiles.
	var best := -1
	var best_d := 1e9
	for dr: int in range(-2, 3):
		for dc: int in range(-2, 3):
			var k := _room_at(c + dc, r + dr)
			if k >= 0:
				var d := float(dc * dc + dr * dr)
				if d < best_d:
					best_d = d
					best = k
	return best


func room_rect_of(p: Vector2) -> Rect2:
	var id := room_of(p)
	return room_rects[id] if id >= 0 and id < room_rects.size() else level_rect


func room_span_of(p: Vector2) -> float:
	var r := room_rect_of(p)
	return clampf(maxf(r.size.x, r.size.y) * 1.1, CinemaGrammar.SPAN_ROOM_MIN, level_span())


func same_room(a: Vector2, b: Vector2) -> bool:
	return room_of(a) == room_of(b)


func room_count() -> int:
	return room_rects.size()


func _room_at(c: int, r: int) -> int:
	if c < 0 or r < 0 or c >= cols or r >= rows:
		return -1
	return _room[r * cols + c]


func _build_geometry() -> void:
	var map: Array[String] = []
	if level != null:
		map = level.map
	rows = map.size()
	cols = 0
	for line: String in map:
		cols = maxi(cols, line.length())
	level_rect = Rect2(0, 0, maxf(1.0, float(cols)), maxf(1.0, float(rows)))
	if level == null:
		return
	# Entity points.
	var door_cells: Dictionary[Vector2i, bool] = {}
	for e: EntityDef in level.entities:
		entity_kinds[e.id] = e.kind
		if e is EnemyDef:
			var en := e as EnemyDef
			entity_points[e.id] = Vector2(en.x, en.y)
			enemy_types[e.id] = en.type
		elif e is DoorDef:
			var d := e as DoorDef
			var sum := Vector2.ZERO
			for cell: Vector2i in d.cells:
				door_cells[cell] = true
				sum += Vector2(cell.x + 0.5, cell.y + 0.5)
			entity_points[e.id] = sum / float(maxi(1, d.cells.size()))
		elif e is SwitchDef:
			var s := e as SwitchDef
			entity_points[e.id] = Vector2(s.x, s.y)
		elif e is PlateDef:
			var p := e as PlateDef
			entity_points[e.id] = Vector2(p.c + 0.5, p.r + 0.5)
		elif e is LaserDef:
			var l := e as LaserDef
			entity_points[e.id] = (l.from + l.to) * 0.5
		elif e is CoreDef:
			var co := e as CoreDef
			entity_points[e.id] = Vector2(co.x, co.y)
		elif e is BreakableDef:
			var b := e as BreakableDef
			entity_points[e.id] = Vector2(b.c + 0.5, b.r + 0.5)
			# An unbroken breakable is a wall: it separates rooms like a door.
			door_cells[Vector2i(b.c, b.r)] = true
		elif e is ExitDef:
			var x := e as ExitDef
			entity_points[e.id] = Vector2(x.c + x.w * 0.5, x.r + x.h * 0.5)
		else:
			# Traps and future entities: use an x/y or c/r property when they have one.
			var vx: Variant = e.get("x")
			var vy: Variant = e.get("y")
			var vc: Variant = e.get("c")
			var vr: Variant = e.get("r")
			if (vx is float or vx is int) and (vy is float or vy is int):
				entity_points[e.id] = Vector2(float(vx), float(vy))
			elif (vc is int) and (vr is int):
				entity_points[e.id] = Vector2(float(vc) + 0.5, float(vr) + 0.5)
	# Rooms: flood fill over non-wall tiles; door cells separate rooms.
	_room = PackedInt32Array()
	_room.resize(cols * rows)
	_room.fill(-1)
	var next_id := 0
	for r: int in rows:
		for c: int in cols:
			if _room[r * cols + c] != -1 or not _open(map, c, r, door_cells):
				continue
			var mn := Vector2i(c, r)
			var mx := Vector2i(c, r)
			var stack: Array[Vector2i] = [Vector2i(c, r)]
			_room[r * cols + c] = next_id
			while not stack.is_empty():
				var t: Vector2i = stack.pop_back()
				mn = Vector2i(mini(mn.x, t.x), mini(mn.y, t.y))
				mx = Vector2i(maxi(mx.x, t.x), maxi(mx.y, t.y))
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n := t + d
					if n.x < 0 or n.y < 0 or n.x >= cols or n.y >= rows:
						continue
					if _room[n.y * cols + n.x] != -1 or not _open(map, n.x, n.y, door_cells):
						continue
					_room[n.y * cols + n.x] = next_id
					stack.append(n)
			room_rects.append(Rect2(mn.x, mn.y, mx.x - mn.x + 1, mx.y - mn.y + 1))
			next_id += 1


static func _open(map: Array[String], c: int, r: int, door_cells: Dictionary[Vector2i, bool]) -> bool:
	if door_cells.has(Vector2i(c, r)):
		return false
	var line := map[r]
	if c >= line.length():
		return false
	return line[c] != "#"
