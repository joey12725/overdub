class_name WorldDecals
extends RefCounted
## Painted floor decals from assets/textures/decals/ (assets/textures/README.md), placed from the
## level's own geometry so no level file needs placement data. They are albedo-only Decals on the
## environment layer (WorldBuilder.ENV_LAYER), so selves and enemies are never painted.
##
##   - hazard chevrons in front of every hazard trap (crusher lane, flame lane, dart lane) pointing the
##     way it acts, KEEP CLEAR on crusher lanes, scorch on flame lanes, DO NOT STAND beside spikes;
##   - the EXIT stencil on the floor in front of exit pads;
##   - the theme's wear: moss and fallen leaves by walls and on overgrown tiles (upper / mid), cracks
##     on cracked tiles, worn paint lines (every theme).
##
## Deterministic per level (seeded by the layout), a few dozen at most.

const DIR := "res://assets/textures/decals/"
const MAX_WEAR := 22
const H := 0.35

var level: LevelDef
var layout: WorldLayout
var pal: WorldPalette
var root: Node3D
var specs: Array[WorldTraps.TrapSpec]
## Decals placed (diagnostics / tests).
var placed: int = 0
var _holder: Node3D = null
var _taken := {}


func _init(p_level: LevelDef, p_layout: WorldLayout, p_pal: WorldPalette, p_root: Node3D, p_specs: Array[WorldTraps.TrapSpec]) -> void:
	level = p_level
	layout = p_layout
	pal = p_pal
	root = p_root
	specs = p_specs


static func tex(name: String) -> Texture2D:
	var path := DIR + name + ".png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func build() -> void:
	_holder = Node3D.new()
	_holder.name = "Decals"
	root.add_child(_holder)
	_traps()
	_exits()
	_wear()


## A floor decal centred on sim point (x, y), `w` x `d` tiles, its texture's up pointing along sim
## heading `heading` (radians, atan2(y, x)).
func floor_decal(t: Texture2D, x: float, y: float, w: float, d: float, heading: float, tint: Color = Color.WHITE) -> Decal:
	if t == null:
		return null
	var dc := Decal.new()
	dc.texture_albedo = t
	dc.albedo_mix = 1.0
	dc.modulate = tint
	dc.cull_mask = WorldBuilder.ENV_LAYER
	dc.size = Vector3(w, H, d)
	dc.upper_fade = 0.2
	dc.lower_fade = 0.2
	dc.normal_fade = 0.5
	# Texture up (-Z in decal space) along the heading: yaw so that local -Z maps to the heading.
	var yaw := RenderCtx.heading_to_yaw(heading) + PI
	dc.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0.0, y))
	_holder.add_child(dc)
	placed += 1
	return dc


func _free(c: int, r: int) -> bool:
	return not _taken.has(Vector2i(c, r)) and not layout.is_wall(c, r) and WorldLayout.is_solid_ground(layout.at(c, r))


func _take(c: int, r: int) -> void:
	_taken[Vector2i(c, r)] = true


# ───────────────────────────── traps ─────────────────────────────

func _traps() -> void:
	var chev := tex("hazard_chevrons")
	var keep := tex("keep_clear")
	var no_stand := tex("do_not_stand")
	var scorch: Array[Texture2D] = [tex("scorch_a"), tex("scorch_b")]
	for s: WorldTraps.TrapSpec in specs:
		match s.kind:
			&"crusher":
				var d := s.crusher_dir()
				if d.is_empty():
					continue
				var h := WorldTraps.dir_heading(d)
				var lane := s.cells
				if lane.is_empty():
					continue
				var c0 := lane[0]
				floor_decal(keep, c0.x + 0.5, c0.y + 0.5, 0.9, 0.45, h)
				_take(c0.x, c0.y)
				var last := lane[lane.size() - 1]
				var step := WorldTraps.dir_step(d)
				if _free(last.x + step.x, last.y + step.y):
					floor_decal(chev, last.x + step.x + 0.5, last.y + step.y + 0.5, 0.9, 0.45, h)
			&"flame":
				if s.dir.is_empty():
					continue
				var h := WorldTraps.dir_heading(s.dir)
				var step := WorldTraps.dir_step(s.dir)
				var n := maxi(1, s.range_tiles)
				for k: int in n:
					var c := s.c + step.x * (k + 1)
					var r := s.r + step.y * (k + 1)
					if layout.is_wall(c, r):
						break
					var t: Texture2D = scorch[(c * 3 + r) % 2]
					floor_decal(t, c + 0.5, r + 0.5, 0.95, 0.95, h + float(k) * 1.3, Color(1, 1, 1, 0.8))
					_take(c, r)
				var c1 := s.c + step.x * (n + 1)
				var r1 := s.r + step.y * (n + 1)
				if _free(c1, r1):
					floor_decal(chev, c1 + 0.5, r1 + 0.5, 0.9, 0.45, h)
			&"dart":
				if s.dir.is_empty():
					continue
				var step := WorldTraps.dir_step(s.dir)
				var c := s.c + step.x
				var r := s.r + step.y
				if _free(c, r):
					floor_decal(chev, c + 0.5, r + 0.5, 0.9, 0.45, WorldTraps.dir_heading(s.dir))
					_take(c, r)
			&"spikes":
				# One stencil beside the bed, on the side nearest the camera, when there is floor.
				var best := Vector2i(-999, -999)
				for cell: Vector2i in s.cells:
					_take(cell.x, cell.y)
				for cell: Vector2i in s.cells:
					for off: Vector2i in [Vector2i(0, 1), Vector2i(1, 0)]:
						var q := cell + off
						if s.cells.has(q) or not _free(q.x, q.y):
							continue
						if q.x + q.y > best.x + best.y:
							best = q
				if best.x > -999:
					floor_decal(no_stand, best.x + 0.5, best.y + 0.5, 0.8, 0.8, -PI * 0.5)
					_take(best.x, best.y)
			_:
				for cell: Vector2i in s.cells:
					_take(cell.x, cell.y)


# ───────────────────────────── exits ─────────────────────────────

func _exits() -> void:
	var t := tex("exit")
	for e: EntityDef in level.entities:
		var x := e as ExitDef
		if x == null:
			continue
		for k: int in x.w:
			for j: int in x.h:
				_take(x.c + k, x.r + j)
		# The stencil sits on the first free tile in front of the pad (toward the camera).
		for cand: Vector2i in [Vector2i(x.c + x.w / 2, x.r + x.h), Vector2i(x.c + x.w, x.r + x.h / 2), Vector2i(x.c + x.w / 2, x.r - 1), Vector2i(x.c - 1, x.r + x.h / 2)]:
			if _free(cand.x, cand.y):
				floor_decal(t, cand.x + 0.5, cand.y + 0.5, 0.9, 0.45, -PI * 0.5, Color(1, 1, 1, 0.9))
				_take(cand.x, cand.y)
				break


# ───────────────────────────── wear ─────────────────────────────

func _wear() -> void:
	var rng := WorldRng.new(layout.level_seed ^ 0xdeca1)
	var metal := pal.floor_finish == WorldPalette.FINISH_METAL
	var green: Array[Texture2D] = [tex("moss_a"), tex("moss_b"), tex("leaves")]
	var cracks: Array[Texture2D] = [tex("crack_a"), tex("crack_b")]
	var worn := tex("worn_line")
	var paint := tex("worn_paint_yellow")
	var spots: Array = []
	for f: WorldLayout.Floor in layout.floors:
		if _taken.has(Vector2i(f.c, f.r)):
			continue
		var n := WorldRng.tile_noise(layout.level_seed ^ 0x51d, f.c, f.r)
		var by_wall := layout.is_wall(f.c - 1, f.r) or layout.is_wall(f.c, f.r - 1)
		if f.kind == WorldLayout.FLOOR_CRACKED and n < 0.6:
			spots.append([n, f, cracks[(f.c + f.r) % 2], 0.9])
		elif not metal and (f.kind == WorldLayout.FLOOR_OVERGROWN or (by_wall and n < 0.18)):
			spots.append([n, f, green[(f.c * 5 + f.r) % 3], 0.95])
		elif n < 0.035:
			spots.append([n, f, paint if not metal and n < 0.02 else worn, 0.7])
	spots.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var placed_wear := 0
	for s: Array in spots:
		if placed_wear >= MAX_WEAR:
			break
		var f: WorldLayout.Floor = s[1]
		var t: Texture2D = s[2]
		if t == null:
			continue
		var size: float = s[3] * rng.range_f(0.8, 1.05)
		var a := float(rng.range_i(0, 3)) * PI * 0.5 + rng.range_f(-0.3, 0.3)
		floor_decal(t, f.c + 0.5 + rng.range_f(-0.12, 0.12), f.r + 0.5 + rng.range_f(-0.12, 0.12), size, size if t != worn and t != paint else size * 0.3, a, Color(1, 1, 1, 0.85))
		_take(f.c, f.r)
		placed_wear += 1
