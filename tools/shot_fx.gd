extends SceneTree
## Screenshot harness for the fx layer (fx/fx_layer.gd). Builds a small lit diorama with
## representative fake data, drives the real fx layer through several scripted phases (every sim
## event fired on a labelled grid in record and in cinematic mode, a flowing cinematic, a fast-world
## record, the idle ambient backdrop) and saves one PNG per phase.
##
##   bash tools/gd shot res://tools/shot_fx.gd [-- <out_dir>] [--labels]
##
## <out_dir> defaults to <OS temp>/overdub_fx_shots (outside the repo). The diorama geometry here is
## harness-only scenery; kit models / Moxie are used when their .glb files exist, else plain boxes and
## capsules stand in (this file is a dev tool, never shipped content).

const FX_LAYER := "res://fx/fx_layer.gd"
const MOXIE := "res://assets/models/moxie.glb"
const KIT := "res://assets/models/kit/%s.glb"
const BOSS := "res://assets/models/enemies/boss.glb"
const WALL_H := 1.4

const MAP: Array[String] = [
	"##################",
	"#................#",
	"#..~~~......~~~..#",
	"#..~~~......~~~..#",
	"#................#",
	"#................#",
	"#.......==.......#",
	"#................#",
	"#..~~~......,,,..#",
	"#..~~~......,,,..#",
	"#................#",
	"##################",
]


## A world view with a real shake/focus response so the shots show what the camera would do.
class ShotView:
	extends WorldViewBase
	var shake_amt: float = 0.0
	var focus_target := Vector3.ZERO
	var focus_w: float = 0.0

	func request_shake(m: float) -> void:
		shake_amt = maxf(shake_amt, m)

	func request_focus(x: float, y: float, w: float) -> void:
		if w >= focus_w:
			focus_target = Vector3(x, 0.0, y)
			focus_w = w

	func surface_height(x: float, y: float) -> float:
		var r := int(floor(y))
		var c := int(floor(x))
		if r < 0 or r >= MAP.size() or c < 0 or c >= MAP[r].length():
			return 0.0
		return WALL_H if MAP[r][c] == "#" else 0.0


class Phase:
	extends RefCounted
	var name: String
	var mode: StringName
	var world_rate: float
	var frames: int
	## Frame at which every event type fires on the labelled grid (-1 = never).
	var grid_at: int
	## Fire a stream of combat events around the selves (cinematic flow).
	var flow: bool
	var shots: Array[int] = []

	func _init(p_name: String, p_mode: StringName, p_rate: float, p_frames: int, p_grid_at: int, p_flow: bool, p_shots: Array[int]) -> void:
		name = p_name
		mode = p_mode
		world_rate = p_rate
		frames = p_frames
		grid_at = p_grid_at
		flow = p_flow
		shots = p_shots


var _out_dir: String = ""
var _labels: bool = false
var _view: ShotView
var _layer: FxLayerBase
var _ctx: RenderCtx
var _cam: Camera3D
var _cam_home := Transform3D()
var _level: LevelDef
var _palette: ThemePalette
var _actors: Array[Node3D] = []
var _boss: Node3D
var _label_root: Node3D
var _phases: Array[Phase] = []
var _phase_i: int = -1
var _f: int = 0
var _beat: float = 0.0
var _prev_snap: FrameSnapshot = null
var _saved: Array[String] = []
var _boot: int = 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for a: String in args:
		if a == "--labels":
			_labels = true
		elif not a.begins_with("--"):
			_out_dir = a
	if _out_dir.is_empty():
		_out_dir = OS.get_temp_dir().path_join("overdub_fx_shots")
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_build_world()
	_phases = [
		Phase.new("record_events", ViewMode.RECORD, 0.5, 70, 10, false, [14, 34]),
		Phase.new("cinematic_events", ViewMode.CINEMATIC, 1.0, 140, 80, false, [84, 104]),
		Phase.new("cinematic_flow", ViewMode.CINEMATIC, 1.0, 420, -1, true, [300, 419]),
		Phase.new("record_fast_world", ViewMode.RECORD, 2.0, 150, -1, true, [149]),
		Phase.new("review_flow", ViewMode.REVIEW, 1.0, 160, -1, true, [159]),
		Phase.new("idle_ambient", ViewMode.IDLE, 1.0, 240, -1, false, [239]),
	]


func _process(_delta: float) -> bool:
	# Give the window and the word atlas a few frames to come up.
	if _boot < 8:
		_boot += 1
		return false
	if _phase_i < 0 or _f >= _phases[_phase_i].frames:
		_phase_i += 1
		if _phase_i >= _phases.size():
			print("[shot_fx] saved %d shots to %s" % [_saved.size(), _out_dir])
			for s: String in _saved:
				print("  " + s)
			return true
		_start_phase(_phases[_phase_i])
	var ph := _phases[_phase_i]
	_step(ph)
	if ph.shots.has(_f):
		_save("%s_%03d" % [ph.name, _f])
	_f += 1
	return false


func _save(nm: String) -> void:
	var img := root.get_texture().get_image()
	var path := _out_dir.path_join(nm + ".png")
	img.save_png(path)
	_saved.append(path)


# ───────────────────────────── scene ─────────────────────────────

func _level_def() -> LevelDef:
	var d := {
		"id": "fx-shot", "index": 3, "name": "FX Shot", "theme": "lower", "bpm": 120, "bars": 4,
		"horizonBars": 8, "maxTapes": 4, "speeds": [0.5, 1, 2, 4], "endModes": ["stop", "repeat", "reverse"],
		"map": MAP, "start": {"x": 3.5, "y": 5.5},
		"entities": [
			{"kind": "core", "id": "core1", "x": 14.5, "y": 2.5},
			{"kind": "exit", "id": "exit1", "c": 15, "r": 8, "w": 2, "h": 2},
			{"kind": "decor", "type": "waveScreen", "x": 6.5, "y": 1.5},
			{"kind": "decor", "type": "waveScreen", "x": 11.5, "y": 1.5},
			{"kind": "decor", "type": "runePanel", "x": 9.0, "y": 1.5},
			{"kind": "decor", "type": "runePanel", "x": 1.5, "y": 7.0},
		],
		"objective": {"type": "activate", "text": "Light the core"},
		"music": {"root": 0, "scale": "minor", "progression": [0, 5, 3, 4], "tracks": []},
	}
	var errors: Array[String] = []
	return LevelDef.from_dict(d, errors)


func _lower_palette() -> ThemePalette:
	var p := ThemePalette.new()
	p.theme = LevelTheme.LOWER
	p.background = Color("#120e16")
	p.fog = Color("#120e16")
	p.floor_color = Color("#3a3040")
	p.floor_alt = Color("#2e2634")
	p.wall = Color("#4a3c4c")
	p.wall_top = Color("#5c4a5e")
	p.metal = Color("#6a5a6e")
	p.trim = Color("#8a7a8e")
	p.hazard = Color("#ffb21f")
	p.neon_a = Color("#ff3fa4")
	p.neon_b = Color("#4ff3ff")
	p.neon_c = Color("#b05cff")
	p.ink = Color("#14110f")
	return p


func _mat(c: Color, emissive: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _model_or_null(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	return ps.instantiate() as Node3D if ps != null else null


## Kit lookup as the contract describes: `<name>__lower` (this diorama's theme), then `<name>`.
func _kit_or_null(kit_name: String) -> Node3D:
	var n := _model_or_null(KIT % (kit_name + "__lower"))
	return n if n != null else _model_or_null(KIT % kit_name)


func _build_world() -> void:
	_level = _level_def()
	_palette = _lower_palette()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = _palette.background
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#8a86a8")
	e.ambient_light_energy = 0.9
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.08
	e.glow_hdr_threshold = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.1
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(30.0), 0.0)
	sun.shadow_enabled = true
	root.add_child(sun)

	_view = ShotView.new()
	_view.name = "ShotView"
	root.add_child(_view)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 11.5
	_cam.far = 200.0
	_view.add_child(_cam)
	var target := Vector3(9.0, 0.0, 6.4)
	var dir := Vector3(sin(deg_to_rad(45.0)) * cos(deg_to_rad(35.0)), sin(deg_to_rad(35.0)), cos(deg_to_rad(45.0)) * cos(deg_to_rad(35.0)))
	# Computed without global_transform: in _initialize the view is not inside the tree yet.
	_cam_home = Transform3D(Basis(), target + dir * 40.0).looking_at(target, Vector3.UP)
	_cam.transform = _cam_home
	_cam.current = true

	var scenery := Node3D.new()
	scenery.name = "Scenery"
	_view.add_child(scenery)
	var floor_m := _mat(_palette.floor_color)
	var floor_alt := _mat(_palette.floor_alt)
	var rune_m := _mat(_palette.floor_alt.lerp(_palette.neon_c, 0.12))
	var wall_m := _mat(_palette.wall)
	var top_m := _mat(_palette.wall_top)
	var low_m := _mat(_palette.metal)
	for r: int in MAP.size():
		for c: int in MAP[r].length():
			var ch := MAP[r][c]
			var p := Vector3(c + 0.5, 0.0, r + 0.5)
			if ch == "#":
				# Camera-side walls are cut low so nothing important is hidden (wall_cut).
				var near := r == MAP.size() - 1 or c == MAP[r].length() - 1
				var h := 0.35 if near else WALL_H
				_box(Vector3(1.0, h, 1.0), p + Vector3(0.0, h * 0.5, 0.0), wall_m, scenery)
				_box(Vector3(1.0, 0.04, 1.0), p + Vector3(0.0, h + 0.02, 0.0), top_m, scenery)
			else:
				var m: Material = floor_m if (r + c) % 2 == 0 else floor_alt
				if ch == "~":
					m = rune_m
				_box(Vector3(0.98, 0.1, 0.98), p + Vector3(0.0, -0.05, 0.0), m, scenery)
				if ch == "=":
					_box(Vector3(1.0, 0.55, 0.6), p + Vector3(0.0, 0.275, 0.0), low_m, scenery)
	# Props: kit models when they exist, else boxes (harness scenery only).
	for ent: EntityDef in _level.entities:
		if ent is DecorDef:
			var dd := ent as DecorDef
			var kit_name := "wave_screen" if dd.type == DecorType.WAVE_SCREEN else "rune_panel"
			var model := _kit_or_null(kit_name)
			if model != null:
				model.position = Vector3(dd.x, 0.0, dd.y)
				scenery.add_child(model)
			elif dd.type == DecorType.WAVE_SCREEN:
				_box(Vector3(1.3, 1.0, 0.25), Vector3(dd.x, 1.45, dd.y), _mat(Color("#1c2230")), scenery)
				_box(Vector3(0.2, 1.0, 0.2), Vector3(dd.x, 0.5, dd.y), low_m, scenery)
			else:
				_box(Vector3(0.6, 1.9, 0.3), Vector3(dd.x, 0.95, dd.y), _mat(Color("#2a2234")), scenery)
		elif ent is CoreDef:
			var cd := ent as CoreDef
			var core_model := _kit_or_null("core")
			if core_model != null:
				core_model.position = Vector3(cd.x, 0.0, cd.y)
				scenery.add_child(core_model)
				continue
			_box(Vector3(0.7, 0.9, 0.7), Vector3(cd.x, 0.45, cd.y), _mat(_palette.metal), scenery)
			_box(Vector3(0.36, 0.36, 0.36), Vector3(cd.x, 1.1, cd.y), _mat(_palette.neon_a, 2.0), scenery)
		elif ent is ExitDef:
			var xd := ent as ExitDef
			_box(Vector3(xd.w - 0.2, 0.06, xd.h - 0.2), Vector3(xd.c + xd.w / 2.0, 0.03, xd.r + xd.h / 2.0), _mat(_palette.hazard, 0.6), scenery)

	# Selves: Moxie when exported, else capsules; a tape-coloured disc marks each cassette.
	for t: int in 4:
		var n := _model_or_null(MOXIE)
		if n == null:
			n = Node3D.new()
			var body := MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.25
			cap.height = 1.5
			body.mesh = cap
			body.position = Vector3(0.0, 0.75, 0.0)
			body.material_override = _mat(Color("#e8d7c8").lerp(OD.tape_color(t), 0.35))
			n.add_child(body)
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.42
		cyl.bottom_radius = 0.42
		cyl.height = 0.02
		disc.mesh = cyl
		disc.material_override = _mat(OD.tape_color(t), 1.5)
		disc.position = Vector3(0.0, 0.012, 0.0)
		n.add_child(disc)
		scenery.add_child(n)
		_actors.append(n)
	_boss = _model_or_null(BOSS)
	if _boss == null:
		_boss = Node3D.new()
		_box(Vector3(1.2, 1.8, 1.2), Vector3(0.0, 0.9, 0.0), _mat(Color("#5a3a48")), _boss)
	scenery.add_child(_boss)
	_boss.position = Vector3(14.0, 0.0, 6.5)
	_label_root = Node3D.new()
	_view.add_child(_label_root)

	# The layer under test, exactly as the world view would instance it.
	_layer = Facades.instance_fx_layer()
	_view.fx_layer = _layer
	_view.add_child(_layer)
	# A plausible melee loadout so momentum tiers grade like in play (1x standing light = 10).
	var lo := ResolvedLoadout.new()
	lo.melee.light.impact = 10.0
	lo.melee.reach = 1.2
	lo.melee.arc_deg = 120.0
	_ctx = _view.new_ctx(_level, lo)
	_ctx.camera = _cam
	_ctx.palette = _palette
	_ctx.bounds = AABB(Vector3.ZERO, Vector3(18.0, WALL_H, 12.0))
	var core_mat := _mat(_palette.neon_a, 2.0)
	_ctx.music_reactive = [MusicReactive.make(MusicReactive.KIND_CORE, core_mat, func(v: float) -> void: core_mat.emission_energy_multiplier = 2.0 * v)]


func _start_phase(ph: Phase) -> void:
	_f = 0
	_beat = 0.0
	_prev_snap = null
	_layer.load_level(_ctx)
	for c: Node in _label_root.get_children():
		c.queue_free()
	_cam.transform = _cam_home
	print("[shot_fx] phase %s (%s, world x%.2f)" % [ph.name, ph.mode, ph.world_rate])


# ───────────────────────────── per frame ─────────────────────────────

func _grid_pos(i: int) -> Vector2:
	var cols := 8
	return Vector2(2.2 + (i % cols) * 1.85, 2.3 + (i / cols) * 2.0)


func _snapshot(ph: Phase) -> FrameSnapshot:
	var s := FrameSnapshot.new()
	s.beat = _beat * ph.world_rate
	s.sub = roundi(s.beat * 120.0)
	var tt := _f / 60.0
	var paths := [
		Vector2(5.0 + 2.2 * cos(tt * 0.9), 5.5 + 1.6 * sin(tt * 0.9)),
		Vector2(9.0 + 2.6 * cos(tt * 0.7 + 1.5), 7.0 + 1.2 * sin(tt * 1.4)),
		Vector2(12.0 + 1.5 * sin(tt * 1.1), 4.8 + 1.5 * cos(tt * 0.8)),
		Vector2(7.5 + 3.0 * sin(tt * 0.5), 9.0 + 0.6 * cos(tt * 1.3)),
	]
	for t: int in 4:
		var a := ActorSnap.new()
		a.tape = t
		a.live = t == 0
		var p: Vector2 = paths[t]
		a.x = p.x
		a.y = p.y
		a.anim = AnimState.RUN
		a.life = OD.LifeState.GHOST if t == 3 else OD.LifeState.ALIVE
		a.synced = t != 2
		if not a.synced:
			a.has_spark = true
			a.spark = p - Vector2(0.8, 0.0)
		s.actors.append(a)
		_actors[t].position = Vector3(a.x, 0.0, a.y)
	var boss := EnemySnap.new()
	boss.id = "boss"
	boss.type = EnemyType.BOSS
	boss.x = 14.0
	boss.y = 6.5
	s.enemies.append(boss)
	return s


func _music() -> MusicPulse:
	var m := MusicPulse.new()
	var b := _beat
	m.beat = b
	m.beat_pulse = pow(1.0 - (b - floorf(b)), 3.0)
	m.bar_pulse = pow(1.0 - (b / 4.0 - floorf(b / 4.0)), 2.0)
	m.levels = PackedFloat32Array([0.55 + 0.4 * m.beat_pulse, 0.5 + 0.3 * sin(b * 0.7), 0.45 + 0.35 * m.bar_pulse, 0.3])
	m.pitches = PackedFloat32Array([
		0.5 + 0.35 * sin(b * PI * 0.5),
		0.3 + 0.2 * sin(b * PI * 0.25 + 1.0) + 0.1 * sin(b * PI * 1.5),
		0.65 + 0.25 * cos(b * PI * 0.75),
		0.45 + 0.3 * sin(b * PI * 0.125) * cos(b * PI),
	])
	m.chord = int(floorf(b / 4.0)) % 4
	return m


func _event(type: StringName, x: float, y: float, tape: int, power: float, dir: float) -> SimEvent:
	var detail := "heavy" if type == SimEventType.SWING else "on"
	return SimEvent.make(_f * 4, type, x, y).with_tape(tape).with_id("e%d" % _f).with_dir(dir).with_power(power).with_detail(detail)


func _grid_events() -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	var i := 0
	for t: StringName in SimEventType.ALL:
		var p := _grid_pos(i)
		out.append(_event(t, p.x, p.y, i % 4, 30.0, 0.6 + i * 0.4))
		if _labels:
			var lb := Label3D.new()
			lb.text = String(t)
			lb.font_size = 22
			lb.pixel_size = 0.006
			lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lb.no_depth_test = true
			lb.modulate = Color(1.0, 1.0, 1.0, 0.75)
			lb.position = Vector3(p.x, 0.05, p.y + 0.55)
			_label_root.add_child(lb)
		i += 1
	return out


func _flow_events(snap: FrameSnapshot) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	var a0 := snap.actors[0]
	var a1 := snap.actors[1]
	var a2 := snap.actors[2]
	match _f % 45:
		5:
			out.append(_event(SimEventType.SWING, a0.x, a0.y, 0, 20.0, 0.3))
		9:
			# Walk the momentum ladder (TAP .. OVERDUB!!) across successive hits.
			var ladder := [3.0, 10.0, 18.0, 28.0, 45.0]
			out.append(_event(SimEventType.HIT, a0.x + 0.8, a0.y, 0, ladder[(_f / 45) % ladder.size()], 0.3))
		14:
			out.append(_event(SimEventType.FIRE, a1.x, a1.y, 1, 10.0, -0.4))
		22:
			out.append(_event(SimEventType.CLANG, a1.x + 0.7, a1.y - 0.3, 1, 6.0, 2.4))
		30:
			out.append(_event(SimEventType.ENEMY_TELEGRAPH, 14.0, 6.5, -1, 0.0, PI))
		36:
			out.append(_event(SimEventType.ENEMY_ATTACK, 14.0, 6.5, -1, 0.0, PI))
		40:
			out.append(_event(SimEventType.STEP, a2.x, a2.y, 2, 0.0, 0.0))
	if _f == 120:
		out.append(_event(SimEventType.KILL, a0.x + 0.6, a0.y + 0.3, 0, 60.0, 0.5))
	if _f == 200:
		out.append(_event(SimEventType.BOSS_RECALL, 14.0, 6.5, 2, 0.0, PI))
	if _f == 260:
		out.append(_event(SimEventType.BREAK, 9.5, 6.5, 1, 70.0, 1.2))
	if _f == 296:
		out.append(_event(SimEventType.OBJECTIVE, 14.5, 2.5, -1, 0.0, 0.0))
	if _f == 380:
		out.append(_event(SimEventType.DESYNC, a2.x, a2.y, 2, 0.0, 0.0))
	return out


func _step(ph: Phase) -> void:
	var dt := 1.0 / 60.0
	_beat += dt * 2.0 * ph.world_rate
	var snap := _snapshot(ph)
	var frame := RenderFrame.new()
	frame.snap = snap
	frame.prev = _prev_snap if _prev_snap != null else snap
	frame.alpha = 1.0
	frame.dt = dt
	frame.mode = ph.mode
	frame.world_rate = ph.world_rate
	frame.music = _music()
	frame.active = 0 if ph.mode == ViewMode.RECORD else -1
	var evs: Array[SimEvent] = []
	if _f == ph.grid_at:
		evs.append_array(_grid_events())
	if ph.flow:
		evs.append_array(_flow_events(snap))
	frame.events = evs
	_view.shake_amt = 0.0
	_layer.update(frame, _ctx)
	# Cheap stand-in for the world view's camera response (shake, cinematic focus drift).
	_view.focus_w *= 0.97
	var off := Vector3.ZERO
	if _view.shake_amt > 0.0:
		off = Vector3(sin(_f * 1.7), cos(_f * 2.3), 0.0) * 0.12 * _view.shake_amt
	var tr := _cam_home
	if ph.mode == ViewMode.CINEMATIC and _view.focus_w > 0.0:
		var home_target := Vector3(9.0, 0.0, 6.4)
		tr.origin += (_view.focus_target - home_target) * 0.15 * _view.focus_w
	tr.origin += tr.basis * off
	_cam.transform = tr
	_prev_snap = snap
