class_name WorldMusicViz
extends RefCounted
## Mounts the music visualisers (musicviz/, docs/MUSICVIZ.md section 4) into a built level and feeds
## them every frame. The world view owns one hub node (MusicVizHub); this class decides where things
## go from the level's own geometry, so no level file needs placement data:
##
##   - every wave_screen prop shows the Stack strip on its "Screen" surface (its own glow material is
##     dropped from the music-reactive list, so the fx layer's pulse never fights the strip);
##   - one Stack frieze on the longest unbroken camera-facing run of full-height wall (never a cut
##     wall, a crusher housing or a graffiti face);
##   - a rune sequencer strip on the wall behind each rune panel, and inlaid along the longest runs
##     of rune floor (lower / core levels);
##   - the level signature (the four Shape sigils) on clear floor near the spawn;
##   - the Epicycle hologram inside the time machine's rings, and a large one plus the constellation
##     behind the arena in a boss room.
##
## Decoration only: no colliders, nothing read back by gameplay. Tracks come from set_tracks() (the
## array the game sends the audio) or, until the game sends one, are derived from the snapshot.

## Minimum full-height wall run (tiles) for the frieze.
const FRIEZE_MIN_RUN := 3
const FRIEZE_HEIGHT := 0.6
## Rune strips inlaid in rune floor runs at least this long (tiles); at most MAX_FLOOR_RUNES runs.
const FLOOR_RUNE_MIN_RUN := 3
const MAX_FLOOR_RUNES := 2
const MAX_PANEL_RUNES := 4
## Signature: tiles of clear floor wanted in a row, search radius around the spawn.
const SIGNATURE_RUN := 5
const SIGNATURE_SEARCH := 5

var hub: MusicVizHub = null
## Diagnostics / tests: what was mounted this level.
var counts: Dictionary = {}

var _root: Node3D = null
var _tracks_given: bool = false
var _derived: Array[TrackAudioState] = []
var _derived_key: String = ""
var _mode: StringName = &""


func _init(p_hub: MusicVizHub) -> void:
	hub = p_hub


## Load the level's music and mount everything. `env_root` holds the built world (decor nodes are
## found by name), `reactive` is the builder's music-reactive list (edited in place).
func build(level: LevelDef, layout: WorldLayout, env_root: Node3D, reactive: Array[MusicReactive], skip_walls: Dictionary) -> void:
	counts = {"screen": 0, "frieze": 0, "runes": 0, "floor_runes": 0, "sigils": 0, "hologram": 0, "constellation": 0}
	_tracks_given = false
	_derived_key = ""
	_mode = &""
	hub.dispose()
	hub.load_level(level)
	_root = Node3D.new()
	_root.name = "MusicViz"
	env_root.add_child(_root)
	var occupied := _occupied_cells(level)
	_mount_screens(env_root, reactive)
	_mount_frieze(level, layout, skip_walls, _graffiti_faces(level, layout))
	_mount_panel_runes(level, layout)
	if level.theme == LevelTheme.LOWER or level.theme == LevelTheme.CORE or level.theme == LevelTheme.MID:
		_mount_floor_runes(layout)
	_mount_signature(level, layout, occupied)
	_mount_showpieces(level, layout)
	hub.redraw_all()


func mounted() -> bool:
	var n := 0
	for k: String in counts:
		n += int(counts[k])
	return n > 0


## The game's cassette states (same array as AudioBase.set_tracks).
func set_tracks(tracks: Array) -> void:
	_tracks_given = true
	hub.set_tracks(tracks)


func update(frame: RenderFrame) -> void:
	if hub == null or hub.music == null or frame == null:
		return
	if frame.mode != _mode:
		_mode = frame.mode
		hub.set_intensity(MusicVizHub.intensity_for_mode(frame.mode))
	if not _tracks_given and frame.snap != null:
		_derive_tracks(frame.snap)
	hub.update_from_frame(frame)


func dispose() -> void:
	if hub != null:
		hub.dispose()
	_root = null


# ───────────────────────────── tracks ─────────────────────────────

## Cassette states from the snapshot (present = a self exists for the tape; speed unknown here, so 1).
func _derive_tracks(snap: FrameSnapshot) -> void:
	var parts: PackedStringArray = []
	for i: int in OD.TAPE_COUNT:
		var a := snap.actor(i)
		parts.append("0" if a == null else "1%d%d%d" % [a.life, int(a.synced), a.phase.dir])
	var key := "|".join(parts)
	if key == _derived_key:
		return
	_derived_key = key
	_derived.clear()
	for i: int in OD.TAPE_COUNT:
		var a := snap.actor(i)
		if a == null:
			_derived.append(TrackAudioState.make(false, 1.0, OD.LifeState.ALIVE, true, 0))
		else:
			_derived.append(TrackAudioState.make(true, 1.0, a.life, a.synced, a.phase.dir if not a.phase.ended else 0))
	hub.set_tracks(_derived)


# ───────────────────────────── placement ─────────────────────────────

func _mount_screens(env_root: Node3D, reactive: Array[MusicReactive]) -> void:
	var stack: Array[Node] = [env_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if String(n.name).contains("decor_waveScreen"):
			var scr := MVMount.find_screen(n)
			if scr != null:
				var old: Array[Material] = []
				for s: int in scr.mesh.get_surface_count():
					var m := scr.get_surface_override_material(s)
					if m == null:
						m = scr.mesh.surface_get_material(s)
					if m != null:
						old.append(m)
				if hub.mount_screen(n) != null:
					counts["screen"] += 1
					for i: int in range(reactive.size() - 1, -1, -1):
						if reactive[i] != null and old.has(reactive[i].material):
							reactive.remove_at(i)
			continue
		for ch: Node in n.get_children():
			stack.append(ch)


## Wall faces (Vector3i(c, r, face)) that carry a graffiti tag, so the frieze never covers one.
func _graffiti_faces(level: LevelDef, _layout: WorldLayout) -> Dictionary:
	var out := {}
	for e: EntityDef in level.entities:
		var d := e as DecorDef
		if d == null or d.type != DecorType.GRAFFITI:
			continue
		var c := int(floor(d.x))
		var r := int(floor(d.y))
		for dc: int in range(-1, 2):
			for dr: int in range(-1, 2):
				out[Vector2i(c + dc, r + dr)] = true
	return out


func _visible_face_ok(layout: WorldLayout, c: int, r: int, face: int) -> bool:
	var nc := c + 1 if face == WorldScatter.FACE_E else c
	var nr := r + 1 if face == WorldScatter.FACE_S else r
	return not layout.is_wall(nc, nr) and WorldLayout.is_solid_ground(layout.at(nc, nr))


func _frieze_wall(layout: WorldLayout, c: int, r: int, face: int, skip_walls: Dictionary, tags: Dictionary) -> bool:
	if not layout.is_wall(c, r) or skip_walls.has(Vector2i(c, r)) or tags.has(Vector2i(c, r)):
		return false
	if layout.wall_height(c, r) < 1.2:
		return false
	return _visible_face_ok(layout, c, r, face)


func _mount_frieze(level: LevelDef, layout: WorldLayout, skip_walls: Dictionary, tags: Dictionary) -> void:
	var best_len := 0
	var best: Array = []
	for face: int in [WorldScatter.FACE_S, WorldScatter.FACE_E]:
		var outer := layout.rows if face == WorldScatter.FACE_S else layout.cols
		var inner := layout.cols if face == WorldScatter.FACE_S else layout.rows
		for o: int in outer:
			var start := -1
			var min_h := INF
			for i: int in inner + 1:
				var c := i if face == WorldScatter.FACE_S else o
				var r := o if face == WorldScatter.FACE_S else i
				var ok := i < inner and _frieze_wall(layout, c, r, face, skip_walls, tags)
				if ok:
					if start < 0:
						start = i
						min_h = INF
					min_h = minf(min_h, layout.wall_height(c, r))
					continue
				if start >= 0:
					var n := i - start
					if n > best_len:
						best_len = n
						best = [face, o, start, i - 1, min_h]
					start = -1
	if best_len < FRIEZE_MIN_RUN:
		return
	var face: int = best[0]
	var o: int = best[1]
	var i0: int = best[2]
	var i1: int = best[3]
	var h: float = best[4]
	var inset := 0.18
	var a: Vector3
	var b: Vector3
	var facing: Vector3
	if face == WorldScatter.FACE_S:
		a = Vector3(i0 + inset, 0.0, o + 1)
		b = Vector3(i1 + 1 - inset, 0.0, o + 1)
		facing = Vector3(0, 0, 1)
	else:
		a = Vector3(o + 1, 0.0, i0 + inset)
		b = Vector3(o + 1, 0.0, i1 + 1 - inset)
		facing = Vector3(1, 0, 0)
	var height := minf(FRIEZE_HEIGHT, h * 0.4)
	var y0 := clampf(h - height - 0.22, 0.45, 1.1)
	hub.mount_frieze(_root, a, b, y0, height, facing)
	counts["frieze"] = 1


## Rune strips on the wall face behind each rune panel (the panel's own glyph columns read with them).
func _mount_panel_runes(level: LevelDef, layout: WorldLayout) -> void:
	var n := 0
	for e: EntityDef in level.entities:
		var d := e as DecorDef
		if d == null or d.type != DecorType.RUNE_PANEL or n >= MAX_PANEL_RUNES:
			continue
		var face := _wall_face_near(layout, d.x, d.y)
		if face.is_empty():
			continue
		var c: int = face["c"]
		var r: int = face["r"]
		var f: int = face["face"]
		var h: float = face["height"]
		if h < 1.0:
			continue
		var a: Vector3
		var b: Vector3
		var facing: Vector3
		if f == WorldScatter.FACE_S:
			a = Vector3(c + 0.08, 0.0, r + 1)
			b = Vector3(c + 0.92, 0.0, r + 1)
			facing = Vector3(0, 0, 1)
		else:
			a = Vector3(c + 1, 0.0, r + 0.08)
			b = Vector3(c + 1, 0.0, r + 0.92)
			facing = Vector3(1, 0, 0)
		# One cassette's row per panel (12.8 : 1 would be too thin on one tile): a short 4-row block.
		var height := minf(0.21, h - 1.0)
		hub.mount_runes(_root, a, b, h - height - 0.12, height, facing, -1)
		n += 1
	counts["runes"] = n


## The camera-visible wall face next to (x, y): the wall's own +X / +Z face, or the face of the wall
## just behind the point. {} when there is none.
func _wall_face_near(layout: WorldLayout, x: float, y: float) -> Dictionary:
	var c := int(floor(x))
	var r := int(floor(y))
	var opts: Array = []
	if layout.is_wall(c, r):
		opts = [[c, r, WorldScatter.FACE_S], [c, r, WorldScatter.FACE_E]]
	else:
		opts = [[c, r - 1, WorldScatter.FACE_S], [c - 1, r, WorldScatter.FACE_E], [c, r - 2, WorldScatter.FACE_S], [c - 2, r, WorldScatter.FACE_E]]
	for o: Array in opts:
		var oc: int = o[0]
		var orr: int = o[1]
		if layout.is_wall(oc, orr) and _visible_face_ok(layout, oc, orr, o[2]) and layout.wall_height(oc, orr) > WorldLayout.WALL_CUT_HEIGHT + 0.01:
			return {"c": oc, "r": orr, "face": o[2], "height": layout.wall_height(oc, orr)}
	return {}


## Inlaid rune strips along the longest straight runs of rune floor.
func _mount_floor_runes(layout: WorldLayout) -> void:
	var rune := {}
	for f: WorldLayout.Floor in layout.floors:
		if f.kind == WorldLayout.FLOOR_RUNE:
			rune[Vector2i(f.c, f.r)] = true
	if rune.is_empty():
		return
	var runs: Array = []
	for horizontal: bool in [true, false]:
		var outer := layout.rows if horizontal else layout.cols
		var inner := layout.cols if horizontal else layout.rows
		for o: int in outer:
			var start := -1
			for i: int in inner + 1:
				var cell := Vector2i(i, o) if horizontal else Vector2i(o, i)
				if i < inner and rune.has(cell):
					if start < 0:
						start = i
					continue
				if start >= 0 and i - start >= FLOOR_RUNE_MIN_RUN:
					runs.append([i - start, horizontal, o, start, i - 1])
				start = -1
	runs.sort_custom(func(p: Array, q: Array) -> bool: return p[0] > q[0])
	var n := 0
	var used := {}
	for run: Array in runs:
		if n >= MAX_FLOOR_RUNES:
			break
		var horizontal: bool = run[1]
		var o: int = run[2]
		var key := Vector2i(int(horizontal), o)
		if used.has(key):
			continue
		used[key] = true
		var i0: int = run[3]
		var i1: int = run[4]
		var a := Vector3(i0 + 0.1, 0.0, o + 0.5) if horizontal else Vector3(o + 0.5, 0.0, i0 + 0.1)
		var b := Vector3(i1 + 0.9, 0.0, o + 0.5) if horizontal else Vector3(o + 0.5, 0.0, i1 + 0.9)
		var length := (b - a).length()
		hub.mount_floor_runes(_root, a, b, minf(0.8, length / 4.0), -1, 1.4)
		n += 1
	counts["floor_runes"] = n


## Floor cells covered by gameplay entities and traps (the signature keeps off them).
func _occupied_cells(level: LevelDef) -> Dictionary:
	var out := {}
	for e: EntityDef in level.entities:
		if e is DecorDef and (e as DecorDef).type == DecorType.GRAFFITI:
			continue
		var cx: Variant = e.get("c")
		var cy: Variant = e.get("r")
		var w: Variant = e.get("w")
		var h: Variant = e.get("h")
		if cx is int and cy is int:
			for dc: int in maxi(1, w if w is int else 1):
				for dr: int in maxi(1, h if h is int else 1):
					out[Vector2i(cx + dc, cy + dr)] = true
		var x: Variant = e.get("x")
		var y: Variant = e.get("y")
		if (x is float or x is int) and (y is float or y is int):
			var big := 1 if e is DecorDef and (e as DecorDef).type == DecorType.TIME_MACHINE else 0
			for dc: int in range(-big, big + 1):
				for dr: int in range(-big, big + 1):
					out[Vector2i(int(floor(float(x))) + dc, int(floor(float(y))) + dr)] = true
	for s: WorldTraps.TrapSpec in WorldTraps.specs_from(WorldTraps.defs_for(level)):
		for cell: Vector2i in s.cells:
			out[cell] = true
		if s.has_pos:
			out[Vector2i(int(floor(s.x)), int(floor(s.y)))] = true
		out[Vector2i(s.c, s.r)] = true
	return out


func _clear_floor(layout: WorldLayout, occupied: Dictionary, c: int, r: int) -> bool:
	if occupied.has(Vector2i(c, r)) or layout.is_wall(c, r):
		return false
	var ch := layout.at(c, r)
	if not WorldLayout.is_solid_ground(ch):
		return false
	for f: WorldLayout.Floor in layout.floors:
		if f.c == c and f.r == r:
			return f.kind != WorldLayout.FLOOR_GRATE and f.kind != WorldLayout.FLOOR_RUNE
	return false


func _mount_signature(level: LevelDef, layout: WorldLayout, occupied: Dictionary) -> void:
	var sc := int(floor(level.start.x))
	var sr := int(floor(level.start.y))
	var best_score := INF
	var best: Array = []
	for want: int in [SIGNATURE_RUN, SIGNATURE_RUN - 1]:
		for horizontal: bool in [true, false]:
			for dr: int in range(-SIGNATURE_SEARCH, SIGNATURE_SEARCH + 1):
				for dc: int in range(-SIGNATURE_SEARCH, SIGNATURE_SEARCH + 1):
					var c0 := sc + dc
					var r0 := sr + dr
					var ok := true
					for k: int in want:
						var c := c0 + (k if horizontal else 0)
						var r := r0 + (0 if horizontal else k)
						if not _clear_floor(layout, occupied, c, r):
							ok = false
							break
					if not ok:
						continue
					var centre := Vector2(c0 + 0.5, r0 + 0.5) + (Vector2(want * 0.5 - 0.5, 0.0) if horizontal else Vector2(0.0, want * 0.5 - 0.5))
					# Near the spawn, but not under the selves' feet at beat zero.
					var dist := centre.distance_to(level.start)
					var score := absf(dist - 2.5) + (0.0 if horizontal else 0.3)
					if score < best_score:
						best_score = score
						best = [centre, horizontal, want]
		if not best.is_empty():
			break
	if best.is_empty():
		return
	var centre: Vector2 = best[0]
	var horizontal: bool = best[1]
	var want: int = best[2]
	var spacing := minf(1.5, float(want) / 4.0)
	hub.mount_signature(_root, Vector3(centre.x, 0.0, centre.y), spacing, spacing * 0.42, Vector3.RIGHT if horizontal else Vector3.BACK)
	counts["sigils"] = 4


func _mount_showpieces(level: LevelDef, layout: WorldLayout) -> void:
	for e: EntityDef in level.entities:
		var d := e as DecorDef
		if d != null and d.type == DecorType.TIME_MACHINE:
			hub.mount_hologram(_root, Vector3(d.x, 0.0, d.y), _lead_layer(level), 1.4, 0.95)
			counts["hologram"] += 1
	var boss: EnemyDef = null
	for e: EntityDef in level.entities:
		if e is EnemyDef and (e as EnemyDef).type == EnemyType.BOSS:
			boss = e
			break
	if boss == null:
		return
	# Behind the arena, as seen from the camera (which looks from the +X / +Z side): step from the
	# boss toward the back corner until just before a wall.
	var back := _toward_back(layout, Vector2(boss.x, boss.y), Vector2(-1, -1).normalized(), 3.5)
	hub.mount_hologram(_root, Vector3(back.x, 0.0, back.y), (_lead_layer(level) + 1) % OD.TAPE_COUNT, 2.4, 0.6)
	counts["hologram"] += 1
	var side := _toward_back(layout, Vector2(boss.x, boss.y), Vector2(-1, 0.35).normalized(), 4.5)
	if side.distance_to(back) < 2.0:
		side = _toward_back(layout, Vector2(boss.x, boss.y), Vector2(0.35, -1).normalized(), 4.5)
	if side.distance_to(back) >= 2.0:
		hub.mount_constellation(_root, Vector3(side.x, 0.0, side.y), 1.8, 0.5)
		counts["constellation"] = 1


func _toward_back(layout: WorldLayout, from: Vector2, dir: Vector2, max_d: float) -> Vector2:
	var p := from
	var d := 0.0
	while d < max_d:
		var q := p + dir * 0.25
		var c := int(floor(q.x))
		var r := int(floor(q.y))
		if layout.is_wall(c, r) or not WorldLayout.is_solid_ground(layout.at(c, r)):
			break
		p = q
		d += 0.25
	return p - dir * 0.6


## The layer that carries the tune: the first cassette layer of the level's music (layer 0 when the
## music does not say).
func _lead_layer(_level: LevelDef) -> int:
	return 0
