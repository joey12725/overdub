extends SceneTree
## Screenshot harness for the music visualisers (musicviz/, MUSIC-12). Renders every visualiser for
## the sandbox level's music at several beats and layer-state scenarios, on the warm (upper ruins)
## and dark (lower depths) styles: first as a flat board of every canvas, then mounted in a small 3D
## diorama (wave screen, wall frieze, rune strip, floor signature, epicycle and constellation
## holograms).
##
##   bash tools/gd shot res://tools/shot_musicviz.gd [-- <out_dir>]
##
## <out_dir> defaults to <OS temp>/overdub_musicviz_shots. Dev tool only, never shipped.

const KIT := "res://assets/models/kit/%s.glb"

## [name, capture beat, description]
const SCENARIOS: Array = [
	["intro", 2.0, "A and B recorded, C and D empty"],
	["states", 9.4, "B desynced since 6, C reversing since 7, D dead since 4"],
	["resync", 13.12, "B resynced at 13.0 (snap), C reversing, D dead"],
	["chord", 24.7, "all alive, chord changed at 24 (sigils mid-redraw)"],
]

var _out_dir: String = ""
var _boot: int = 0
var _jobs: Array = []
var _job: int = -1
var _wait: int = 0
var _saved: Array[String] = []
var _level: LevelDef = null
var _hubs: Dictionary = {}
var _boards: Dictionary = {}
var _worlds: Dictionary = {}
var _env: Environment = null
var _board_layer: CanvasLayer = null
var _cam: Camera3D = null
var _sun: DirectionalLight3D = null


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			_out_dir = a
	if _out_dir.is_empty():
		_out_dir = OS.get_temp_dir().path_join("overdub_musicviz_shots")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_level = ContentData.load_level("sandbox")
	_build_env()
	for theme: StringName in [LevelTheme.UPPER, LevelTheme.LOWER]:
		var hub := MusicVizHub.new()
		hub.name = "Hub_%s" % theme
		root.add_child(hub)
		hub.load_music(_level.music, _level.bpm, _level.horizon_bars, theme)
		_hubs[theme] = hub
		_boards[theme] = _build_board(hub, theme)
		_worlds[theme] = _build_world(hub, theme)
	for theme: StringName in [LevelTheme.UPPER, LevelTheme.LOWER]:
		for s: Array in SCENARIOS:
			_jobs.append([theme, s, "board"])
		for s: Array in SCENARIOS:
			if s[0] == "states" or s[0] == "resync" or s[0] == "chord":
				_jobs.append([theme, s, "world"])


func _process(_delta: float) -> bool:
	if _boot < 6:
		_boot += 1
		return false
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			var j: Array = _jobs[_job]
			_save("%s_%s_%s" % [j[2], "warm" if j[0] == LevelTheme.UPPER else "dark", j[1][0]])
		return false
	_job += 1
	if _job >= _jobs.size():
		print("[shot_musicviz] saved %d shots to %s" % [_saved.size(), _out_dir])
		for s: String in _saved:
			print("  " + s)
		for t: StringName in _hubs:
			var h: MusicVizHub = _hubs[t]
			print("[shot_musicviz] %s: %d canvases, est. %.0f us/frame at 60 fps" % [t, h.canvas_count(), h.frame_cost_usec()])
			for line: String in h.cost_report():
				print("    " + line)
		return true
	var job: Array = _jobs[_job]
	_show(job[0], job[2])
	_simulate(_hubs[job[0]], job[1])
	_wait = 4
	return false


func _save(nm: String) -> void:
	var img := root.get_texture().get_image()
	var path := _out_dir.path_join(nm + ".png")
	img.save_png(path)
	_saved.append(path)


# ───────────────────────────── scenarios ─────────────────────────────

func _tracks(scen: String, b: float) -> Array:
	var out: Array = []
	var speeds := [1.0, 2.0, 1.0, 0.5]
	for i: int in 4:
		var t := TrackAudioState.make(true, speeds[i], OD.LifeState.ALIVE, true, 1)
		match scen:
			"intro":
				t.present = i < 2
			"states", "resync":
				if i == 1 and b >= 6.0 and (scen == "states" or b < 13.0):
					t.synced = false
				if i == 2 and b >= 7.0:
					t.transport = -1
				if i == 3 and b >= 4.0:
					t.life = OD.LifeState.GHOST
		out.append(t)
	return out


func _simulate(hub: MusicVizHub, s: Array) -> void:
	var target: float = s[1]
	var b := 0.0
	hub.music.update(-100.0, _tracks(s[0], 0.0))
	while b < target:
		hub.music.update(b, _tracks(s[0], b))
		b += 1.0 / 30.0
	hub.music.update(target, _tracks(s[0], target))
	hub.redraw_all()


func _show(theme: StringName, what: String) -> void:
	for t: StringName in _boards:
		(_boards[t] as Control).visible = what == "board" and t == theme
		(_worlds[t] as Node3D).visible = what == "world" and t == theme
	_env.background_color = Color("#d7b596") if theme == LevelTheme.UPPER else Color("#0a0910")
	if what == "world":
		_env.background_color = Color("#2a1f1c") if theme == LevelTheme.UPPER else Color("#0b0912")
		_env.ambient_light_color = Color("#c9c2bb") if theme == LevelTheme.UPPER else Color("#8a86a8")
		_env.ambient_light_energy = 0.45 if theme == LevelTheme.UPPER else 0.7
		_sun.light_energy = 0.75 if theme == LevelTheme.UPPER else 1.2


# ───────────────────────────── board ─────────────────────────────

func _build_env() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.glow_enabled = true
	_env.glow_intensity = 0.8
	_env.glow_bloom = 0.06
	_env.glow_hdr_threshold = 1.0
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = _env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.light_energy = 1.2
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(30.0), 0.0)
	root.add_child(sun)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 8.5
	_cam.far = 200.0
	var target := Vector3(6.0, 0.6, 3.4)
	var dir := Vector3(sin(deg_to_rad(45.0)) * cos(deg_to_rad(35.0)), sin(deg_to_rad(35.0)), cos(deg_to_rad(45.0)) * cos(deg_to_rad(35.0)))
	_cam.transform = Transform3D(Basis(), target + dir * 40.0).looking_at(target, Vector3.UP)
	root.add_child(_cam)
	_cam.current = true
	_board_layer = CanvasLayer.new()
	_board_layer.layer = 5
	root.add_child(_board_layer)


func _tex_rect(parent: Control, tex: Texture2D, r: Rect2, label: String, ink: Color) -> void:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.position = r.position
	tr.size = r.size
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	tr.material = m
	parent.add_child(tr)
	var lb := Label.new()
	lb.text = label
	lb.position = r.position + Vector2(4, r.size.y - 2)
	lb.add_theme_font_size_override(&"font_size", 12)
	lb.add_theme_color_override(&"font_color", ink)
	parent.add_child(lb)


func _build_board(hub: MusicVizHub, theme: StringName) -> Control:
	var c := Control.new()
	c.size = Vector2(1600, 900)
	_board_layer.add_child(c)
	var bg := ColorRect.new()
	bg.color = Color("#d7b596") if theme == LevelTheme.UPPER else Color("#0a0910")
	bg.size = c.size
	c.add_child(bg)
	var ink := Color("#3a2418") if theme == LevelTheme.UPPER else Color("#7f86a8")
	_tex_rect(c, hub.texture(MusicVizHub.KIND_STACK_SCREEN), Rect2(16, 12, 480, 300), "stack (wave screen)", ink)
	_tex_rect(c, hub.texture(MusicVizHub.KIND_EPICYCLE, 2), Rect2(510, 12, 300, 300), "epicycles C", ink)
	_tex_rect(c, hub.texture(MusicVizHub.KIND_CONSTELLATION), Rect2(824, 12, 300, 300), "constellation", ink)
	_tex_rect(c, hub.texture(MusicVizHub.KIND_EPICYCLE_WAVE, 0), Rect2(1140, 12, 444, 166), "epicycles A (wave)", ink)
	_tex_rect(c, hub.texture(MusicVizHub.KIND_RUNE_ROW, 1), Rect2(1140, 214, 444, 35), "rune row B", ink)
	_tex_rect(c, hub.texture(MusicVizHub.KIND_FRIEZE), Rect2(16, 334, 1568, 147), "frieze", ink)
	_tex_rect(c, hub.texture(MusicVizHub.KIND_SIGILS), Rect2(16, 504, 380, 380), "signature (4 sigils)", ink)
	_tex_rect(c, hub.texture(MusicVizHub.KIND_SIGIL, 2), Rect2(410, 504, 380, 380), "sigil C", ink)
	_tex_rect(c, hub.texture(MusicVizHub.KIND_EPICYCLE, 0), Rect2(804, 504, 380, 380), "epicycles A", ink)
	_tex_rect(c, hub.texture(MusicVizHub.KIND_RUNES), Rect2(1198, 600, 386, 97), "runes", ink)
	return c


# ───────────────────────────── diorama ─────────────────────────────

func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _kit(nm: String, theme: StringName) -> Node3D:
	var suffix := "__upper" if theme == LevelTheme.UPPER else "__lower"
	for p: String in [KIT % (nm + suffix), KIT % nm]:
		if ResourceLoader.exists(p):
			var ps := load(p) as PackedScene
			if ps != null:
				return ps.instantiate() as Node3D
	return null


func _build_world(hub: MusicVizHub, theme: StringName) -> Node3D:
	var w := Node3D.new()
	w.visible = false
	root.add_child(w)
	var warm := theme == LevelTheme.UPPER
	var floor_c := Color("#cfae92") if warm else Color("#2c2634")
	var wall_c := Color("#b99178") if warm else Color("#3a3044")
	_box(w, Vector3(12, 0.2, 8), Vector3(6, -0.1, 4), _mat(floor_c))
	_box(w, Vector3(12.4, 1.7, 0.4), Vector3(6, 0.85, -0.2), _mat(wall_c))
	_box(w, Vector3(0.4, 1.7, 8), Vector3(-0.2, 0.85, 4), _mat(wall_c))
	# Wall frieze and rune strip on the back wall (faces +Z, toward the camera).
	hub.mount_frieze(w, Vector3(0.6, 0, 0), Vector3(7.4, 0, 0), 0.98, 0.62, Vector3(0, 0, 1))
	hub.mount_runes(w, Vector3(8.0, 0, 0), Vector3(11.4, 0, 0), 0.1, 0.85, Vector3(0, 0, 1))
	# A wave screen prop (kit model when present, else a stand-in quad named Screen).
	var ws := _kit("wave_screen", theme)
	if ws == null:
		ws = Node3D.new()
		var q := MeshInstance3D.new()
		q.name = "Screen"
		var qm := QuadMesh.new()
		qm.size = Vector2(1.1, 0.7)
		q.mesh = qm
		q.position = Vector3(0, 0.75, 0.0)
		ws.add_child(q)
	ws.position = Vector3(9.6, 0, 0.45)
	w.add_child(ws)
	if hub.mount_screen(ws) == null:
		push_warning("shot_musicviz: wave_screen has no Screen mesh")
	# The level signature on the floor and two holograms.
	hub.mount_signature(w, Vector3(3.6, 0, 3.3), 1.55, 0.68)
	hub.mount_hologram(w, Vector3(8.2, 0, 4.6), 2, 2.0, 0.25)
	hub.mount_constellation(w, Vector3(10.6, 0, 3.4), 1.7, 0.2)
	return w
