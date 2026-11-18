class_name WorldTraps
extends RefCounted
## Trap and machinery visuals (docs/TRAPS.md "Snapshot fields" and "Presentation notes"), driven
## purely by MechSnap exactly like doors and lasers (WorldMechs): the view never infers trap state,
## so a review or cinematic replay shows what the resolved run did.
##
## Models: assets/models/kit/trap_*.glb, placed by the contract written into the kit manifest
## (`placement`, `head_z`, `pad_y`, `jet_scale_z` ... per piece, mirrored by the constants below).
## Every moving part is its own node (Spikes, Head/Ram, Belt/Arrows/Roller_*, Nozzle/Pilot/Jet,
## Muzzle/Shutter/Flash/Pip_NN, Pad/Spring, Lens/Beam, Lamp/Tick_NN, Coil/Ring); `warn_glow` is the
## telegraph lamp on every hazard and `accent_glow` carries the wire colour of whatever drives the
## machine. When a model is missing a clearly-temporary stand-in with the same named parts is built.
##
## Definitions come from the level's TrapDef entities (core/types/*_def.gd) through their to_dict(),
## i.e. the authored JSON shape of TRAPS.md "Vocabulary", parsed once into TrapSpec here.
## Snapshots: traps appear in FrameSnapshot.mechs as MechSnap with kind = the trap kind and the
## optional `warn` / `dir` / `reach` / `firing` fields, each valid when its has_* flag is set.

const KINDS: Array[StringName] = [&"spikes", &"crusher", &"conveyor", &"flame", &"dart", &"bumper", &"sensor", &"relay", &"magnet"]

# ── numbers from the kit contract (art/traps/traps.py, mirrored in manifest.json) ──
const SPIKE_REST := 0.02
const SPIKE_WARN_RISE := 0.1
const HEAD_HOME_Z := 0.53
const HEAD_END_GAP := 0.02
const HEAD_DEPTH := 0.45
const HEAD_TOP := 1.3
const RAM_INTO_HEAD := 0.35
const STAMP_HOME_Y := 1.3
const STAMP_DOWN_Y := 0.02
const STAMP_ROD := 1.35
const BELT_Y := 0.05
const BELT_HALF_W := 0.392
const ROLLER_R := 0.062
const NOZZLE_Y := 0.26
const NOZZLE_MOUTH_Z := 0.845
const DART_Y := 0.3
const MUZZLE_RECOIL := 0.04
const SHUTTER_TRAVEL := 0.095
const PIPS := 8
const PAD_POP := 0.2
const SPRING_REST := 0.04
const SENSOR_Y := 0.32
const TICKS := 8
## Housing height kept when a crusher housing replaces a camera-side (cut) wall.
const CUT_HOUSING_SCALE := 0.55
## Master seconds a bumper pad takes to settle / a dart flash lasts (TRAPS.md).
const BUMPER_SETTLE := 0.25
const DART_FLASH := 0.1
const DEFAULT_BELT_SPEED := 2.0
## Chevrons per tile painted on a belt (the kit's Arrows period is 1/3).
const BELT_CHEVRONS := 3.0
## Telegraph colour (TRAPS.md: orange-red, never a cassette colour).
const WARN_COLOR := Color("#ff6a1e")
const SENSOR_COLOR := Color("#cfe4ff")
const MAGNET_COLOR := Color("#b060ff")
const FLAME_COLOR := Color("#ff7a1a")


## The trap fields of one MechSnap, with absent optionals at their neutral values.
class TrapState:
	extends RefCounted
	var on: bool = false
	var t: float = 0.0
	var has_t: bool = false
	var warn: float = 0.0
	var dir: float = 0.0
	var has_dir: bool = false
	var reach: float = 0.0
	var has_reach: bool = false
	var firing: bool = false

	static func read(m: MechSnap) -> TrapState:
		var s := TrapState.new()
		s.on = m.on
		s.t = m.t
		s.has_t = m.has_t
		s.warn = clampf(m.warn, 0.0, 1.0) if m.has_warn else 0.0
		s.dir = m.dir
		s.has_dir = m.has_dir
		s.reach = maxf(0.0, m.reach)
		s.has_reach = m.has_reach
		s.firing = m.has_firing and m.firing
		return s


## One trap entity as authored (TRAPS.md "Vocabulary"), from its JSON dictionary.
class TrapSpec:
	extends RefCounted
	var id: String = ""
	var kind: StringName = &""
	var cells: Array[Vector2i] = []
	## "n" | "e" | "s" | "w", or "" when absent.
	var dir: String = ""
	var c: int = 0
	var r: int = 0
	var x: float = 0.0
	var y: float = 0.0
	var has_pos: bool = false
	var from: Vector2 = Vector2.ZERO
	var to: Vector2 = Vector2.ZERO
	var range_tiles: int = 0
	var speed: float = DEFAULT_BELT_SPEED
	var radius: float = 0.0
	## Signals the machine reads (first one decides its wire accent).
	var drivers: Array[String] = []

	static func from_dict(d: Dictionary) -> TrapSpec:
		var kind := StringName(ODJson.string(d, "kind"))
		if not KINDS.has(kind):
			return null
		var s := TrapSpec.new()
		s.kind = kind
		s.id = ODJson.string(d, "id")
		s.dir = ODJson.string(d, "dir")
		var cells: Variant = d.get("cells", [])
		if cells is Array:
			for v: Variant in cells:
				if v is Dictionary:
					s.cells.append(Vector2i(ODJson.integer(v, "c"), ODJson.integer(v, "r")))
		s.c = ODJson.integer(d, "c")
		s.r = ODJson.integer(d, "r")
		s.has_pos = ODJson.is_number(d.get("x")) and ODJson.is_number(d.get("y"))
		s.x = ODJson.num(d, "x")
		s.y = ODJson.num(d, "y")
		s.from = ODJson.vec2(d.get("from")) if d.get("from") is Dictionary else Vector2.ZERO
		s.to = ODJson.vec2(d.get("to")) if d.get("to") is Dictionary else Vector2.ZERO
		s.range_tiles = ODJson.integer(d, "range")
		s.speed = ODJson.num(d, "speed", DEFAULT_BELT_SPEED)
		s.radius = ODJson.num(d, "radius")
		for key: String in ["upWhen", "extendWhen", "runWhen", "reverseWhen", "onWhen", "enabledWhen", "fireWhen", "trigger"]:
			if d.has(key):
				var errors: Array[String] = []
				var e := SignalExpr.from_dict(d[key], errors)
				WorldMechAccent.expr_signals(e, s.drivers)
		return s

	## Crusher travel direction: `dir`, else inferred from the first two cells, else "" (stamper).
	func crusher_dir() -> String:
		if not dir.is_empty():
			return dir
		if cells.size() >= 2:
			var dv := cells[1] - cells[0]
			if dv == Vector2i(1, 0):
				return "e"
			if dv == Vector2i(-1, 0):
				return "w"
			if dv == Vector2i(0, 1):
				return "s"
			if dv == Vector2i(0, -1):
				return "n"
		return ""


## Sim heading (radians) of a direction letter: e = +x, s = +y (toward higher rows).
static func dir_heading(d: String) -> float:
	match d:
		"e":
			return 0.0
		"s":
			return PI * 0.5
		"w":
			return PI
		"n":
			return -PI * 0.5
	return 0.0


static func dir_step(d: String) -> Vector2i:
	match d:
		"e":
			return Vector2i(1, 0)
		"s":
			return Vector2i(0, 1)
		"w":
			return Vector2i(-1, 0)
		"n":
			return Vector2i(0, -1)
	return Vector2i.ZERO


## Trap entity dictionaries of a level (TrapDef.to_dict(), in entity order). [] when there are none.
static func defs_for(level: LevelDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: EntityDef in level.entities:
		if e is TrapDef and KINDS.has(e.kind):
			var d: Variant = e.call("to_dict")
			if d is Dictionary:
				out.append(d)
	return out


static func specs_from(defs: Array) -> Array[TrapSpec]:
	var out: Array[TrapSpec] = []
	for d: Variant in defs:
		if d is Dictionary:
			var s := TrapSpec.from_dict(d)
			if s != null:
				out.append(s)
	return out


## Wall tiles whose piece a crusher housing replaces (the tile behind cells[0]).
static func replaced_walls(specs: Array[TrapSpec], layout: WorldLayout) -> Dictionary:
	var out := {}
	for s: TrapSpec in specs:
		if s.kind != &"crusher" or s.cells.is_empty():
			continue
		var d := s.crusher_dir()
		if d.is_empty():
			continue
		var h := s.cells[0] - dir_step(d)
		if layout.is_wall(h.x, h.y):
			out[h] = true
	return out


## Signal ids traps read or publish as sources (for the level-wide accent table).
static func accent_signals(specs: Array[TrapSpec]) -> Array[String]:
	var out: Array[String] = []
	for s: TrapSpec in specs:
		for d: String in s.drivers:
			if not out.has(d):
				out.append(d)
		if (s.kind == &"sensor" or s.kind == &"relay") and not out.has(s.id):
			out.append(s.id)
	return out


## Master-clock bookkeeping shared by every trap visual (belts scroll in master time).
class Clock:
	extends RefCounted
	var master_dt: float = 0.0
	var last_sub: int = -1


## Base class of one trap's visual.
class TrapVisual:
	extends WorldMechs.Visual
	var spec: TrapSpec = null
	var clock: Clock = null
	var state := TrapState.new()
	var seen: bool = false

	func apply(snap: MechSnap, _dt: float) -> void:
		state = TrapState.read(snap)
		seen = true


var mechs: WorldMechs
var pal: WorldPalette
var layout: WorldLayout
var root: Node3D
var specs: Array[TrapSpec] = []
var visuals: Dictionary = {}
var list: Array[TrapVisual] = []
var clock := Clock.new()
var _walls: Dictionary = {}
var _chevron_tex: Texture2D = null


func _init(p_specs: Array[TrapSpec], p_mechs: WorldMechs, p_root: Node3D) -> void:
	specs = p_specs
	mechs = p_mechs
	pal = p_mechs.pal
	layout = p_mechs.layout
	root = p_root
	for w: WorldLayout.Wall in layout.walls:
		_walls[Vector2i(w.c, w.r)] = w
	for s: TrapSpec in specs:
		var v: TrapVisual = null
		match s.kind:
			&"spikes":
				v = _spikes(s)
			&"crusher":
				v = _crusher(s)
			&"conveyor":
				v = _conveyor(s)
			&"flame":
				v = _flame(s)
			&"dart":
				v = _dart(s)
			&"bumper":
				v = _bumper(s)
			&"sensor":
				v = _sensor(s)
			&"relay":
				v = _relay(s)
			&"magnet":
				v = _magnet(s)
		if v == null:
			continue
		v.id = s.id
		v.spec = s
		v.clock = clock
		v.node.name = ("trap_%s" % s.id).validate_node_name()
		mechs._set_layers(v.node)
		root.add_child(v.node)
		visuals[s.id] = v
		list.append(v)
	for v: TrapVisual in list:
		v.tick(1.0, 0.0)


func update(frame: RenderFrame, dt: float, time: float) -> void:
	clock.master_dt = 0.0
	if frame != null and frame.snap != null:
		var sub := frame.snap.sub
		if clock.last_sub >= 0 and sub > clock.last_sub:
			clock.master_dt = minf(float(sub - clock.last_sub) / float(OD.SUB_HZ), 0.25)
		clock.last_sub = sub
	if frame != null:
		for e: SimEvent in frame.events:
			var v: TrapVisual = visuals.get(e.id, null)
			if v != null:
				v.on_event(e)
		if frame.snap != null:
			for m: MechSnap in frame.snap.mechs:
				var v: TrapVisual = visuals.get(m.id, null)
				if v != null:
					v.apply(m, dt)
	for v: TrapVisual in list:
		v.tick(dt, time)


# ───────────────────────────── shared helpers ─────────────────────────────

func _accent(s: TrapSpec) -> Color:
	if s.kind == &"sensor":
		return mechs.accent_for(s.id)
	if s.drivers.is_empty():
		return WorldMechAccent.BEAT_ACCENT
	return mechs.accent_for(s.drivers[0])


## Kit model or the stand-in with the same parts; `accent_glow` takes the wire colour.
func _model(piece: String, c: int, r: int, accent: Color) -> Node3D:
	var n := mechs._kit(piece, c, r)
	if n == null:
		n = _standin(piece)
	WorldMechs._glows(n, "accent", accent)
	return n


func _cell_node(c: float, r: float, heading: float, h: float = 0.0) -> Node3D:
	var g := Node3D.new()
	g.position = Vector3(c, h, r)
	g.rotation.y = RenderCtx.heading_to_yaw(heading)
	return g


static func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n == null:
		return out
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is MeshInstance3D:
			out.append(x as MeshInstance3D)
		for ch: Node in x.get_children():
			stack.append(ch)
	return out


## Per-node glow multiplier (glow shaders' instance_energy) for parts that share one material.
static func _node_energy(n: Node, e: float) -> void:
	for mi: MeshInstance3D in _meshes(n):
		WebCompat.set_param(mi, &"instance_energy", e)


static func _rest(n: Node3D) -> Vector3:
	return n.position if n != null else Vector3.ZERO


func _is_floor(c: int, r: int) -> bool:
	return WorldLayout.is_floor_char(layout.at(c, r))


# ───────────────────────────── spikes ─────────────────────────────

class SpikesVisual:
	extends TrapVisual
	var spikes: Array[Node3D] = []
	var warn_l := WorldMechs.Lamp.new()
	var h: float = 0.0

	func tick(dt: float, time: float) -> void:
		var target := state.t if state.has_t else (1.0 if state.on else 0.0)
		# Snap up in under two frames, drop over about 0.1 s (TRAPS.md presentation notes).
		h = WorldMechs._damp(h, target, 70.0 if target > h else 30.0, dt)
		var w := state.warn if h < 0.05 else 0.0
		var k := lerpf(SPIKE_REST, 1.0, h) + SPIKE_WARN_RISE * w + 0.012 * w * sin(time * 80.0)
		for s: Node3D in spikes:
			s.scale.y = maxf(0.001, k)
		warn_l.set_level(0.12 + 2.6 * maxf(w, h))


func _spikes(s: TrapSpec) -> TrapVisual:
	var v := SpikesVisual.new()
	v.node = Node3D.new()
	var accent := _accent(s)
	for cell: Vector2i in s.cells:
		var yaw_k := int(WorldRng.tile_noise(0x5b1e, cell.x, cell.y) * 4.0)
		var g := _cell_node(cell.x + 0.5, cell.y + 0.5, yaw_k * PI * 0.5 - PI * 0.5)
		v.node.add_child(g)
		var m := _model("trap_spikes", cell.x, cell.y, accent)
		g.add_child(m)
		var sp := WorldMechs._find(m, "Spikes")
		if sp != null:
			v.spikes.append(sp)
		v.warn_l.materials.append_array(WorldMechs._glows(m, "warn", WARN_COLOR).materials)
	return v


# ───────────────────────────── crusher ─────────────────────────────

class CrusherVisual:
	extends TrapVisual
	var head: Node3D = null
	var ram: Node3D = null
	var housing: Node3D = null
	var housing_rest := Vector3.ZERO
	var stamper: bool = false
	var home: float = HEAD_HOME_Z
	var extended: float = 1.0
	var ram_rest_scale := Vector3.ONE
	var warn_l := WorldMechs.Lamp.new()
	var ghost: MeshInstance3D = null
	var ghost_m: ShaderMaterial = null
	var e: float = 0.0

	func tick(dt: float, time: float) -> void:
		if state.has_t:
			e = clampf(state.t, 0.0, 1.0)
		else:
			var target := 1.0 if state.on else 0.0
			# Slam fast, retract visibly slowly (0.25 s; TRAPS.md).
			e = WorldMechs._damp(e, target, 60.0 if target > e else 12.0, dt)
		var w := state.warn if e < 0.01 else 0.0
		if head != null:
			if stamper:
				head.position.y = lerpf(STAMP_HOME_Y, STAMP_DOWN_Y, e)
				if ram != null:
					ram.scale = Vector3(ram_rest_scale.x, maxf(0.001, STAMP_ROD - head.position.y), ram_rest_scale.z)
			else:
				head.position.z = lerpf(home, extended, e)
				if ram != null:
					ram.scale = Vector3(ram_rest_scale.x, ram_rest_scale.y, maxf(0.001, head.position.z - RAM_INTO_HEAD))
		if housing != null:
			# The housing shudders while the warning fills.
			housing.position = housing_rest + Vector3(sin(time * 90.0), 0.0, cos(time * 73.0)) * 0.012 * w
		# Lamp: fills with warn, hot while the stroke lands, dark (steam, no glow) on the retract.
		var live := 1.0 if (state.on and e > 0.5) else 0.0
		warn_l.set_level(0.12 + 2.8 * maxf(w, live))
		if ghost != null:
			ghost.visible = w > 0.01
			ghost_m.set_shader_parameter(&"opacity", 0.45 * w)


func _crusher(s: TrapSpec) -> TrapVisual:
	if s.cells.is_empty():
		return null
	var v := CrusherVisual.new()
	v.node = Node3D.new()
	var accent := _accent(s)
	var d := s.crusher_dir()
	if d.is_empty():
		# One cell, no direction: the overhead stamper.
		v.stamper = true
		var cell := s.cells[0]
		var g := _cell_node(cell.x + 0.5, cell.y + 0.5, PI * 0.5)
		v.node.add_child(g)
		var m := _model("trap_crusher_stamper", cell.x, cell.y, accent)
		g.add_child(m)
		v.head = WorldMechs._find(m, "Head")
		v.ram = WorldMechs._find(m, "Ram")
		if v.ram != null:
			v.ram_rest_scale = v.ram.scale
		v.warn_l = WorldMechs._glows(m, "warn", WARN_COLOR)
		v.ghost = _ghost(g, Vector3(0.9, STAMP_HOME_Y - 0.5, 0.9), Vector3(0, 0, 0), v)
		return v
	var heading := dir_heading(d)
	var back := s.cells[0] - dir_step(d)
	var g := _cell_node(back.x + 0.5, back.y + 0.5, heading)
	v.node.add_child(g)
	var m := _model("trap_crusher", back.x, back.y, accent)
	g.add_child(m)
	v.head = WorldMechs._find(m, "Head")
	v.ram = WorldMechs._find(m, "Ram")
	v.housing = WorldMechs._find(m, "Housing")
	if v.ram != null:
		v.ram_rest_scale = v.ram.scale
	if v.head != null:
		v.home = v.head.position.z
	v.extended = s.cells.size() + 0.5 - HEAD_END_GAP
	# On a camera-side (cut) wall the housing stays low so it never hides the floor behind it.
	var w: WorldLayout.Wall = _walls.get(back, null)
	if w != null and w.cut and v.housing != null:
		v.housing.scale.y = CUT_HOUSING_SCALE
	v.housing_rest = _rest(v.housing)
	v.warn_l = WorldMechs._glows(m, "warn", WARN_COLOR)
	for cell: Vector2i in s.cells:
		var lg := _cell_node(cell.x + 0.5, cell.y + 0.5, heading)
		v.node.add_child(lg)
		var lane := _model("trap_crusher_lane", cell.x, cell.y, accent)
		lg.add_child(lane)
		v.warn_l.materials.append_array(WorldMechs._glows(lane, "warn", WARN_COLOR).materials)
	# Ghosted outline of the head where it will land.
	v.ghost = _ghost(g, Vector3(0.96, HEAD_TOP, HEAD_DEPTH), Vector3(0, 0, v.extended - HEAD_DEPTH * 0.5), v)
	return v


func _ghost(parent: Node3D, size: Vector3, centre: Vector3, v: CrusherVisual) -> MeshInstance3D:
	var gm := ToonKit.glow_add(WARN_COLOR, 1.2, 0.0)
	gm.set_shader_parameter(&"fresnel_fade", 0.85)
	var y0 := STAMP_DOWN_Y if v.stamper else 0.0
	var mi := WorldMechs._part(parent, mechs._box(size, 0.02, y0), gm, Vector3(centre.x, 0.0, centre.z), false)
	mi.visible = false
	v.ghost_m = gm
	return mi


# ───────────────────────────── conveyor ─────────────────────────────

class ConveyorVisual:
	extends TrapVisual
	var cells: Array[Node3D] = []
	var rollers: Array[Node3D] = []
	var arrows_m: ShaderMaterial = null
	var run_l := WorldMechs.Lamp.new()
	var base_heading: float = 0.0
	var heading: float = 0.0
	var scroll: float = 0.0
	var spin: float = 0.0

	func tick(_dt: float, _time: float) -> void:
		var running := state.on if seen else true
		var h := state.dir if state.has_dir else base_heading
		if not is_equal_approx(h, heading):
			# Reversal flips the chevrons in one frame.
			heading = h
			for g: Node3D in cells:
				g.rotation.y = RenderCtx.heading_to_yaw(heading)
		if running:
			var dist := spec.speed * clock.master_dt
			scroll = fposmod(scroll + dist, 1.0)
			spin += dist / ROLLER_R
		if arrows_m != null:
			arrows_m.set_shader_parameter(&"uv_offset", Vector2(0.0, -scroll * BELT_CHEVRONS))
		for r: Node3D in rollers:
			r.rotation.x = spin
		run_l.set_level(1.8 if running else 0.08)


func _conveyor(s: TrapSpec) -> TrapVisual:
	var v := ConveyorVisual.new()
	v.node = Node3D.new()
	var accent := _accent(s)
	v.base_heading = dir_heading(s.dir if not s.dir.is_empty() else "e")
	v.heading = v.base_heading
	var arrow_color := pal.hazard
	for cell: Vector2i in s.cells:
		var g := _cell_node(cell.x + 0.5, cell.y + 0.5, v.base_heading)
		v.node.add_child(g)
		var m := _model("trap_conveyor", cell.x, cell.y, accent)
		g.add_child(m)
		v.cells.append(g)
		for part: String in ["Roller_Back", "Roller_Front"]:
			var rn := WorldMechs._find(m, part)
			if rn != null:
				v.rollers.append(rn)
		var arrows := WorldMechs._find(m, "Arrows")
		if arrows != null:
			# The model's painted chevrons are static; the belt draws its own that scroll at the real speed.
			for mi: MeshInstance3D in _meshes(arrows):
				var am := mi.get_surface_override_material(0) as ShaderMaterial
				if am != null and ToonKit.is_toon(am) and am.get_shader_parameter(&"albedo") is Color:
					arrow_color = am.get_shader_parameter(&"albedo")
			arrows.visible = false
		v.run_l.materials.append_array(WorldMechs._glows(m, "run").materials)
	var tex := _chevrons()
	v.arrows_m = ToonKit.toon_cutout(arrow_color, tex, 0.5)
	v.arrows_m.set_shader_parameter(&"uv_scale", Vector2(1.0, BELT_CHEVRONS))
	var plane := mechs._plane(BELT_HALF_W * 1.7, 1.0)
	for g: Node3D in v.cells:
		WorldMechs._part(g, plane, v.arrows_m, Vector3(0.0, BELT_Y + 0.004, 0.0), false)
	return v


## Chevron strip pointing toward +V (= +Z on a PlaneMesh), transparent between chevrons.
func _chevrons() -> Texture2D:
	if _chevron_tex == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for py: int in range(n):
			for px: int in range(n):
				var u := (px + 0.5) / n
				var vv := (py + 0.5) / n
				var k := fposmod(vv + absf(u - 0.5) * 0.9, 1.0)
				var on := k > 0.2 and k < 0.52 and u > 0.12 and u < 0.88
				img.set_pixel(px, py, Color(1, 1, 1, 1.0 if on else 0.0))
		img.generate_mipmaps()
		_chevron_tex = ImageTexture.create_from_image(img)
	return _chevron_tex


# ───────────────────────────── flame ─────────────────────────────

class FlameVisual:
	extends TrapVisual
	var jet: Node3D = null
	var jet_rest_scale := Vector3.ONE
	var lanes: Array[Node3D] = []
	var pilot_l := WorldMechs.Lamp.new()
	var heat_l := WorldMechs.Lamp.new()
	var fire_l := WorldMechs.Lamp.new()
	var fire_core_l := WorldMechs.Lamp.new()
	var warn_l := WorldMechs.Lamp.new()
	var shimmer: Node3D = null
	var shimmer_m: ShaderMaterial = null
	var splash: MeshInstance3D = null
	var splash_l := WorldMechs.Lamp.new()
	var heading: float = 0.0
	var b: float = 0.0

	func tick(dt: float, time: float) -> void:
		var reach := state.reach if state.has_reach else float(spec.range_tiles)
		b = WorldMechs._damp(b, 1.0 if state.on else 0.0, 40.0, dt)
		var w := state.warn if not state.on else 0.0
		# Scorch lanes only as far as the jet can currently go (a closed door shortens the danger).
		for i: int in range(lanes.size()):
			lanes[i].visible = float(i) < reach - 0.001
		var flicker := 1.0 + 0.1 * sin(time * 47.0) + 0.06 * sin(time * 113.0)
		if jet != null:
			var len_z := reach - (NOZZLE_MOUTH_Z - 0.5)
			jet.visible = b > 0.03 and len_z > 0.02
			jet.scale = Vector3(jet_rest_scale.x * flicker * b, jet_rest_scale.y * flicker * b, maxf(0.001, len_z * b))
		# Kept near 1 so the jet stays orange under the linear tonemap (2.6 would clip it to yellow).
		fire_l.set_level(1.05 + 0.2 * sin(time * 37.0))
		fire_core_l.set_level(1.6 + 0.3 * sin(time * 53.0))
		pilot_l.set_level(1.2 + 2.4 * maxf(w, b) + 0.3 * sin(time * 9.0))
		heat_l.set_level(0.2 + 3.0 * b)
		warn_l.set_level(0.12 + 2.4 * maxf(w, b))
		if shimmer != null:
			shimmer.visible = w > 0.01 and reach > 0.0
			shimmer.scale = Vector3(1.0, 1.0, maxf(0.001, reach))
			shimmer_m.set_shader_parameter(&"opacity", 0.5 * w)
		if splash != null:
			splash.visible = b > 0.05 and reach > 0.0
			splash.position.z = 0.5 + reach
			splash.scale = Vector3.ONE * (0.8 + 0.25 * sin(time * 31.0)) * b
			splash_l.set_level(1.3 * b)


func _flame(s: TrapSpec) -> TrapVisual:
	var v := FlameVisual.new()
	v.node = Node3D.new()
	var accent := _accent(s)
	var d := s.dir if not s.dir.is_empty() else "e"
	v.heading = dir_heading(d)
	var g := _cell_node(s.c + 0.5, s.r + 0.5, v.heading)
	v.node.add_child(g)
	var m := _model("trap_flame", s.c, s.r, accent)
	g.add_child(m)
	v.jet = WorldMechs._find(m, "Jet")
	if v.jet != null:
		v.jet_rest_scale = v.jet.scale
	v.pilot_l = WorldMechs._glows(m, "pilot")
	v.heat_l = WorldMechs._glows(m, "heat")
	v.fire_l = WorldMechs._glows(m, "flame_glow")
	v.fire_core_l = WorldMechs._glows(m, "flame_core")
	v.warn_l = WorldMechs._glows(m, "warn", WARN_COLOR)
	var step := dir_step(d)
	for k: int in range(1, maxi(1, s.range_tiles) + 1):
		var cell := Vector2i(s.c, s.r) + step * k
		var lg := _cell_node(cell.x + 0.5, cell.y + 0.5, v.heading)
		v.node.add_child(lg)
		var lane := _model("trap_flame_lane", cell.x, cell.y, accent)
		lg.add_child(lane)
		v.lanes.append(lg)
		v.warn_l.materials.append_array(WorldMechs._glows(lane, "warn", WARN_COLOR).materials)
	# Gas shimmer along the lane while the warning fills; a splash where the jet stops.
	v.shimmer_m = ToonKit.glow_add(WARN_COLOR, 1.0, 0.0)
	v.shimmer_m.set_shader_parameter(&"fresnel_fade", 0.6)
	# The holder sits on the wall face; scaling it along Z stretches the unit-long shimmer to `reach`.
	var sh := Node3D.new()
	sh.name = "Shimmer"
	sh.position = Vector3(0.0, NOZZLE_Y, 0.5)
	g.add_child(sh)
	WorldMechs._part(sh, mechs._box(Vector3(0.3, 0.3, 1.0), 0.0, -0.15), v.shimmer_m, Vector3(0, 0, 0.5), false)
	sh.visible = false
	v.shimmer = sh
	var splash_m := ToonKit.glow_add(FLAME_COLOR, 2.0, 0.85, 1.0)
	splash_m.set_shader_parameter(&"fresnel_fade", 0.7)
	v.splash = WorldMechs._part(g, mechs._mesh("flameSplash", func() -> Mesh:
		var sm := SphereMesh.new()
		sm.radius = 0.32
		sm.height = 0.5
		sm.radial_segments = 12
		sm.rings = 6
		return sm), splash_m, Vector3(0, NOZZLE_Y, 1.5), false)
	v.splash_l = WorldMechs.Lamp.of(splash_m)
	v.splash.visible = false
	return v


# ───────────────────────────── dart ─────────────────────────────

class DartVisual:
	extends TrapVisual
	var muzzle: Node3D = null
	var muzzle_rest := Vector3.ZERO
	var shutter: Node3D = null
	var shutter_rest := Vector3.ZERO
	var flash: Node3D = null
	var pips: Array[Node3D] = []
	var warn_l := WorldMechs.Lamp.new()
	var muzzle_l := WorldMechs.Lamp.new()
	var flash_left: float = 0.0
	var last_t: float = -1.0
	var open: float = 1.0

	func on_event(e: SimEvent) -> void:
		if String(e.type) == "trap" and e.detail == "dart:fire":
			flash_left = DART_FLASH

	func apply(snap: MechSnap, dt: float) -> void:
		super.apply(snap, dt)
		# Without a `firing` field, a wrap of the progress toward the next shot is the shot.
		if state.firing:
			flash_left = maxf(flash_left, DART_FLASH * 0.5)
		elif state.has_t and last_t >= 0.0 and state.t + 0.5 < last_t and state.on:
			flash_left = DART_FLASH
		last_t = state.t if state.has_t else -1.0

	func tick(dt: float, _time: float) -> void:
		var enabled := state.on if seen else true
		open = WorldMechs._damp(open, 1.0 if enabled else 0.0, 18.0, dt)
		flash_left = maxf(0.0, flash_left - dt)
		var f := flash_left / DART_FLASH
		if shutter != null:
			shutter.position.y = shutter_rest.y - SHUTTER_TRAVEL * (1.0 - open)
		if muzzle != null:
			muzzle.position.z = muzzle_rest.z - MUZZLE_RECOIL * f
		if flash != null:
			flash.visible = f > 0.0
			flash.scale = Vector3.ONE * (0.6 + 0.6 * f)
		var t := clampf(state.t, 0.0, 1.0) if state.has_t else 0.0
		var lit := int(floor(t * PIPS + 1e-4)) if enabled else 0
		for i: int in range(pips.size()):
			WorldTraps._node_energy(pips[i], 1.0 if i < lit else 0.06)
		# The last quarter of the cycle: the slot glows.
		var slot := clampf((t - 0.75) * 4.0, 0.0, 1.0) if enabled else 0.0
		warn_l.set_level(0.1 + 2.4 * maxf(slot, f))
		muzzle_l.set_level(3.0 * f)


func _dart(s: TrapSpec) -> TrapVisual:
	var v := DartVisual.new()
	v.node = Node3D.new()
	var accent := _accent(s)
	var d := s.dir if not s.dir.is_empty() else "e"
	var heading := dir_heading(d)
	var g := _cell_node(s.c + 0.5, s.r + 0.5, heading)
	v.node.add_child(g)
	var m := _model("trap_dart", s.c, s.r, accent)
	g.add_child(m)
	v.muzzle = WorldMechs._find(m, "Muzzle")
	v.muzzle_rest = _rest(v.muzzle)
	v.shutter = WorldMechs._find(m, "Shutter")
	v.shutter_rest = _rest(v.shutter)
	v.flash = WorldMechs._find(m, "Flash")
	if v.flash != null:
		v.flash.visible = false
	for i: int in range(1, PIPS + 1):
		var p := WorldMechs._find(m, "Pip_%02d" % i)
		if p != null:
			v.pips.append(p)
	v.warn_l = WorldMechs._glows(m, "warn", WARN_COLOR)
	v.muzzle_l = WorldMechs._glows(m, "muzzle")
	# The scored lane: every open tile down the lane until a wall or the map edge.
	var step := dir_step(d)
	var cell := Vector2i(s.c, s.r) + step
	var guard := 0
	while guard < 256 and not layout.is_wall(cell.x, cell.y) and cell.x >= 0 and cell.y >= 0 and cell.x < layout.cols and cell.y < layout.rows:
		if _is_floor(cell.x, cell.y):
			var lg := _cell_node(cell.x + 0.5, cell.y + 0.5, heading)
			v.node.add_child(lg)
			lg.add_child(_model("trap_dart_lane", cell.x, cell.y, accent))
		cell += step
		guard += 1
	return v


# ───────────────────────────── bumper ─────────────────────────────

class BumperVisual:
	extends TrapVisual
	var pad: Node3D = null
	var pad_rest := Vector3.ZERO
	var spring: Node3D = null
	var spring_rest_scale := Vector3.ONE
	var group: Node3D = null
	var base_heading: float = 0.0
	var warn_l := WorldMechs.Lamp.new()
	var k: float = 0.0
	var was_on: bool = false

	func tick(dt: float, _time: float) -> void:
		if state.has_t:
			k = clampf(state.t, 0.0, 1.0)
		else:
			if state.on and not was_on:
				k = 1.0
			k = maxf(0.0, k - dt / BUMPER_SETTLE)
		was_on = state.on
		if state.has_dir and group != null:
			group.rotation.y = RenderCtx.heading_to_yaw(state.dir)
		if pad != null:
			pad.position.y = pad_rest.y + PAD_POP * k
		if spring != null:
			spring.scale = Vector3(spring_rest_scale.x, SPRING_REST + PAD_POP * k, spring_rest_scale.z)
		warn_l.set_level(0.15 + 2.6 * k)


func _bumper(s: TrapSpec) -> TrapVisual:
	var v := BumperVisual.new()
	v.node = Node3D.new()
	var accent := _accent(s)
	v.base_heading = dir_heading(s.dir if not s.dir.is_empty() else "n")
	var g := _cell_node(s.c + 0.5, s.r + 0.5, v.base_heading)
	v.node.add_child(g)
	v.group = g
	var m := _model("trap_bumper", s.c, s.r, accent)
	g.add_child(m)
	v.pad = WorldMechs._find(m, "Pad")
	v.pad_rest = _rest(v.pad)
	v.spring = WorldMechs._find(m, "Spring")
	if v.spring != null:
		v.spring_rest_scale = v.spring.scale
	v.warn_l = WorldMechs._glows(m, "warn", WARN_COLOR)
	return v


# ───────────────────────────── sensor ─────────────────────────────

class SensorVisual:
	extends TrapVisual
	var beam: Node3D = null
	var beam_rest_scale := Vector3.ONE
	var length: float = 1.0
	var beam_l := WorldMechs.Lamp.new()
	var lens_l := WorldMechs.Lamp.new()
	var b: float = 0.0

	func tick(dt: float, time: float) -> void:
		b = WorldMechs._damp(b, 1.0 if state.on else 0.0, 25.0, dt)
		var reach := state.reach if state.has_reach else length
		if beam != null:
			beam.visible = reach > 0.02
			beam.scale = Vector3(beam_rest_scale.x, beam_rest_scale.y, maxf(0.001, reach))
		# Pale and steady when clear; both posts and the beam flash bright while tripped.
		beam_l.set_level(0.9 + 2.6 * b + 0.25 * b * sin(time * 30.0))
		lens_l.set_level(1.0 + 2.4 * b)


func _sensor(s: TrapSpec) -> TrapVisual:
	var v := SensorVisual.new()
	v.node = Node3D.new()
	var accent := _accent(s)
	var dv := s.to - s.from
	v.length = maxf(0.01, dv.length())
	var heading := atan2(dv.y, dv.x)
	for end: int in range(2):
		var p := s.from if end == 0 else s.to
		var g := _cell_node(p.x, p.y, heading if end == 0 else heading + PI)
		v.node.add_child(g)
		var m := _model("trap_sensor", int(floor(p.x)), int(floor(p.y)), accent)
		g.add_child(m)
		var bm := WorldMechs._find(m, "Beam")
		if end == 0:
			v.beam = bm
			if bm != null:
				v.beam_rest_scale = bm.scale
		elif bm != null:
			bm.visible = false
		v.beam_l.materials.append_array(WorldMechs._glows(m, "beam", SENSOR_COLOR).materials)
		v.lens_l.materials.append_array(WorldMechs._glows(m, "sensor", SENSOR_COLOR).materials)
	return v


# ───────────────────────────── relay ─────────────────────────────

class RelayVisual:
	extends TrapVisual
	var lamp: Node3D = null
	var ticks: Array[Node3D] = []

	func tick(_dt: float, time: float) -> void:
		var armed := state.warn >= 0.5
		var lamp_e := 0.08
		if state.on:
			lamp_e = 3.0
		elif armed:
			lamp_e = 0.4 + (2.4 if fposmod(time * 6.0, 1.0) < 0.5 else 0.0)
		if lamp != null:
			WorldTraps._node_energy(lamp, lamp_e)
		var lit := int(ceil(clampf(state.t, 0.0, 1.0) * TICKS)) if armed and state.has_t else (TICKS if state.on else 0)
		for i: int in range(ticks.size()):
			WorldTraps._node_energy(ticks[i], 1.6 if i < lit else 0.05)


func _relay(s: TrapSpec) -> TrapVisual:
	if not s.has_pos:
		# TRAPS.md: a relay has no body; it is drawn only when the designer places its lamp.
		return null
	var v := RelayVisual.new()
	v.node = Node3D.new()
	var accent := _accent(s)
	var g := _cell_node(s.x, s.y, PI * 0.5, layout.surface_height(s.x, s.y))
	v.node.add_child(g)
	var m := _model("trap_relay", int(floor(s.x)), int(floor(s.y)), accent)
	g.add_child(m)
	v.lamp = WorldMechs._find(m, "Lamp")
	for i: int in range(1, TICKS + 1):
		var t := WorldMechs._find(m, "Tick_%02d" % i)
		if t != null:
			v.ticks.append(t)
	return v


# ───────────────────────────── magnet ─────────────────────────────

class MagnetVisual:
	extends TrapVisual
	var coil_l := WorldMechs.Lamp.new()
	var ring_l := WorldMechs.Lamp.new()
	var pulses: Array[MeshInstance3D] = []
	var pulse_m: Array[ShaderMaterial] = []
	var radius: float = 1.0
	var b: float = 0.0
	var phase: float = 0.0

	func tick(dt: float, time: float) -> void:
		b = WorldMechs._damp(b, 1.0 if state.on else 0.0, 10.0, dt)
		coil_l.set_level(0.3 + 2.6 * b + 0.3 * b * sin(time * 14.0))
		ring_l.set_level(0.35 + 1.1 * b)
		phase = fposmod(phase + dt * 0.9 * b, 1.0)
		# Concentric rings contract toward the centre while pulling.
		for i: int in range(pulses.size()):
			var ph := fposmod(phase + float(i) / pulses.size(), 1.0)
			var rr := lerpf(radius, 0.6, ph)
			pulses[i].visible = b > 0.03
			pulses[i].scale = Vector3(rr, 1.0, rr)
			pulse_m[i].set_shader_parameter(&"opacity", 0.7 * b * sin(ph * PI))


func _magnet(s: TrapSpec) -> TrapVisual:
	var v := MagnetVisual.new()
	v.node = Node3D.new()
	var accent := _accent(s)
	v.radius = maxf(0.6, s.radius)
	var g := _cell_node(s.x, s.y, PI * 0.5)
	v.node.add_child(g)
	var m := _model("trap_magnet", int(floor(s.x)), int(floor(s.y)), accent)
	g.add_child(m)
	var ring := WorldMechs._find(m, "Ring")
	if ring != null:
		ring.scale = Vector3(v.radius, 1.0, v.radius)
	v.coil_l = WorldMechs._glows(m, "magnet_glow")
	v.ring_l = WorldMechs._glows(m, "magnet_ring")
	# WorldMechs' ring texture draws its ring at 0.85 of the half-size: size the plane so scale = radius.
	var plane := mechs._plane(2.0 / 0.85, 2.0 / 0.85)
	for i: int in range(3):
		var pm := ToonKit.glow_add(MAGNET_COLOR, 1.4, 0.0)
		pm.set_shader_parameter(&"use_texture", true)
		pm.set_shader_parameter(&"tex", WorldMechs._ring_texture())
		var mi := WorldMechs._part(g, plane, pm, Vector3(0.0, 0.02 + 0.002 * i, 0.0), false)
		mi.visible = false
		v.pulses.append(mi)
		v.pulse_m.append(pm)
	return v


# ───────────────────────────── stand-ins ─────────────────────────────
## Clearly temporary primitives with the contract's part names, used only when a trap model is
## missing (every trap_*.glb exists at the time of writing, so these normally never appear).

func _sglow(name: String, c: Color) -> ShaderMaterial:
	var g := ToonKit.glow(c, 1.0)
	g.resource_name = name
	return g


func _sp(parent: Node3D, part: String, origin: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = part
	n.position = origin
	parent.add_child(n)
	return n


func _standin(piece: String) -> Node3D:
	var root_n := Node3D.new()
	root_n.name = "StandIn_" + piece
	var steel := mechs._toon(pal.metal)
	var hazard := mechs._toon(pal.hazard, 1.0)
	var warn := _sglow("warn_glow", WARN_COLOR)
	var accent := _sglow("accent_glow", Color.WHITE)
	match piece:
		"trap_spikes":
			var base := _sp(root_n, "Base")
			WorldMechs._part(base, mechs._box(Vector3(0.92, 0.04, 0.92), 0.01, -0.02), hazard, Vector3.ZERO, false)
			WorldMechs._part(base, mechs._box(Vector3(0.7, 0.012, 0.7), 0.0), warn, Vector3(0, 0.02, 0), false)
			var sp := _sp(root_n, "Spikes", Vector3(0, -0.02, 0))
			for ix: int in range(3):
				for iz: int in range(3):
					WorldMechs._part(sp, mechs._cyl(0.05, 0.0, 0.64, 6), steel, Vector3(-0.25 + ix * 0.25, 0.32, -0.25 + iz * 0.25))
		"trap_crusher":
			var h := _sp(root_n, "Housing")
			WorldMechs._part(h, mechs._box(Vector3(1.0, 1.8, 1.0), 0.04), mechs._toon(pal.trim))
			WorldMechs._part(h, mechs._box(Vector3(0.6, 0.08, 0.04), 0.0), warn, Vector3(0, 1.62, 0.51), false)
			WorldMechs._part(h, mechs._box(Vector3(0.12, 0.03, 0.04), 0.0), accent, Vector3(0, 1.5, 0.51), false)
			var head := _sp(root_n, "Head", Vector3(0, 0, HEAD_HOME_Z))
			WorldMechs._part(head, mechs._box(Vector3(0.96, HEAD_TOP, HEAD_DEPTH), 0.03), hazard, Vector3(0, 0, -HEAD_DEPTH * 0.5))
			var ram := _sp(root_n, "Ram", Vector3(0, 0, 0.05))
			WorldMechs._part(ram, mechs._cyl(0.14, 0.14, 1.0, 10, 2), steel, Vector3(0, 0.65, 0.5))
		"trap_crusher_lane", "trap_flame_lane":
			var lane := _sp(root_n, "Lane")
			for sx: float in [-0.41, 0.41]:
				WorldMechs._part(lane, mechs._box(Vector3(0.05, 0.012, 1.0), 0.0), warn, Vector3(sx, 0.004, 0), false)
				WorldMechs._part(lane, mechs._box(Vector3(0.08, 0.01, 1.0), 0.0), hazard, Vector3(sx * 0.9, 0.002, 0), false)
		"trap_crusher_stamper":
			var fr := _sp(root_n, "Frame")
			for sx: float in [-0.44, 0.44]:
				WorldMechs._part(fr, mechs._box(Vector3(0.1, 2.4, 0.1), 0.02), steel, Vector3(sx, 0, 0))
			WorldMechs._part(fr, mechs._box(Vector3(1.0, 0.16, 0.3), 0.02, 2.25), mechs._toon(pal.trim))
			WorldMechs._part(fr, mechs._box(Vector3(0.3, 0.06, 0.06), 0.0), warn, Vector3(0, 2.42, 0.16), false)
			var head := _sp(root_n, "Head", Vector3(0, STAMP_HOME_Y, 0))
			WorldMechs._part(head, mechs._box(Vector3(0.84, 0.8, 0.84), 0.03), hazard)
			var ram := _sp(root_n, "Ram", Vector3(0, 2.1, 0))
			WorldMechs._part(ram, mechs._cyl(0.12, 0.12, 1.0, 10), steel, Vector3(0, -0.5, 0))
		"trap_conveyor":
			var fr := _sp(root_n, "Frame")
			WorldMechs._part(fr, mechs._box(Vector3(0.96, 0.03, 1.0), 0.0), mechs._toon(pal.trim), Vector3.ZERO, false)
			for sx: float in [-0.396, 0.396]:
				WorldMechs._part(fr, mechs._box(Vector3(0.012, 0.014, 1.0), 0.0), _sglow("run_glow", Color("#ffe7a0")), Vector3(sx, 0.05, 0), false)
			var belt := _sp(root_n, "Belt")
			WorldMechs._part(belt, mechs._box(Vector3(BELT_HALF_W * 2.0, 0.03, 1.0), 0.0, 0.02), mechs._toon(Color("#3b3230")), Vector3.ZERO, false)
			_sp(root_n, "Arrows")
			for spec: Array in [["Roller_Back", -0.435], ["Roller_Front", 0.435]]:
				var rl := _sp(root_n, spec[0], Vector3(0, 0.035, spec[1]))
				WorldMechs._part(rl, mechs._cyl(ROLLER_R, ROLLER_R, 0.9, 8, 0), steel, Vector3.ZERO, false)
		"trap_flame":
			var body := _sp(root_n, "Body")
			WorldMechs._part(body, mechs._box(Vector3(0.6, 0.45, 0.3), 0.03), mechs._toon(pal.trim), Vector3(0, 0, 0.65))
			WorldMechs._part(body, mechs._box(Vector3(0.1, 0.03, 0.02), 0.0), accent, Vector3(-0.2, 0.38, 0.81), false)
			WorldMechs._part(body, mechs._box(Vector3(0.4, 0.04, 0.02), 0.0), warn, Vector3(0, 0.05, 0.81), false)
			var nz := _sp(root_n, "Nozzle", Vector3(0, NOZZLE_Y, 0.66))
			WorldMechs._part(nz, mechs._cyl(0.1, 0.1, 0.2, 10, 2), steel, Vector3(0, 0, 0.1))
			var pilot := _sp(root_n, "Pilot", Vector3(0, 0.142, 0.8))
			WorldMechs._part(pilot, mechs._cyl(0.03, 0.03, 0.06, 6), _sglow("pilot_glow", Color("#4c7cff")), Vector3.ZERO, false)
			var jet := _sp(root_n, "Jet", Vector3(0, NOZZLE_Y, NOZZLE_MOUTH_Z))
			WorldMechs._part(jet, mechs._cyl(0.15, 0.04, 1.0, 8, 2), _sglow("flame_glow", FLAME_COLOR), Vector3(0, 0, 0.5), false)
			jet.visible = false
		"trap_dart":
			var body := _sp(root_n, "Body")
			WorldMechs._part(body, mechs._box(Vector3(0.5, 0.56, 0.4), 0.03), mechs._toon(pal.trim), Vector3(0, 0, 0.7))
			WorldMechs._part(body, mechs._box(Vector3(0.1, 0.03, 0.02), 0.0), accent, Vector3(0.19, 0.42, 0.91), false)
			WorldMechs._part(body, mechs._box(Vector3(0.2, 0.06, 0.02), 0.0), warn, Vector3(0, DART_Y, 0.905), false)
			var mz := _sp(root_n, "Muzzle", Vector3(0, DART_Y, 0.66))
			WorldMechs._part(mz, mechs._cyl(0.05, 0.05, 0.26, 8, 2), steel, Vector3(0, 0, 0.13))
			var sh := _sp(root_n, "Shutter", Vector3(0, 0.396, 0.9))
			WorldMechs._part(sh, mechs._box(Vector3(0.3, 0.09, 0.02), 0.0), hazard, Vector3.ZERO, false)
			var fl := _sp(root_n, "Flash", Vector3(0, DART_Y, 0.95))
			WorldMechs._part(fl, mechs._box(Vector3(0.24, 0.24, 0.02), 0.0), _sglow("muzzle_glow", Color("#fff4d0")), Vector3(0, -0.12, 0), false)
			var pip_m := _sglow("pip_glow", Color("#f2ecff"))
			for i: int in range(PIPS):
				var p := _sp(root_n, "Pip_%02d" % (i + 1), Vector3(-0.21 + i * 0.06, 0.556, 0.53))
				WorldMechs._part(p, mechs._box(Vector3(0.034, 0.01, 0.035), 0.0), pip_m, Vector3.ZERO, false)
		"trap_dart_lane":
			var lane := _sp(root_n, "Lane")
			WorldMechs._part(lane, mechs._box(Vector3(0.05, 0.01, 1.0), 0.0), mechs._toon(pal.grout, 0.0), Vector3(0, 0.002, 0), false)
		"trap_bumper":
			var base := _sp(root_n, "Base")
			WorldMechs._part(base, mechs._cyl(0.46, 0.46, 0.06, 16), hazard, Vector3(0, 0.0, 0), false)
			WorldMechs._part(base, mechs._box(Vector3(0.28, 0.01, 0.04), 0.0), accent, Vector3(0, 0.035, -0.425), false)
			var pad := _sp(root_n, "Pad")
			WorldMechs._part(pad, mechs._cyl(0.36, 0.36, 0.05, 16), steel, Vector3(0, 0.06, 0))
			var arrow := WorldMechs._part(pad, mechs._box(Vector3(0.1, 0.012, 0.4), 0.0), warn, Vector3(0, 0.09, 0), false)
			arrow.name = "Arrow"
			var sp := _sp(root_n, "Spring", Vector3(0, -0.02, 0))
			WorldMechs._part(sp, mechs._cyl(0.12, 0.12, 1.0, 8), steel, Vector3(0, 0.5, 0), false)
		"trap_sensor":
			var post := _sp(root_n, "Post")
			WorldMechs._part(post, mechs._box(Vector3(0.12, 0.4, 0.12), 0.02), steel)
			WorldMechs._part(post, mechs._box(Vector3(0.04, 0.09, 0.008), 0.0), accent, Vector3(0, 0.27, -0.065), false)
			var lens := _sp(root_n, "Lens")
			WorldMechs._part(lens, mechs._cyl(0.032, 0.032, 0.02, 8, 2), _sglow("sensor_glow", SENSOR_COLOR), Vector3(0, SENSOR_Y, 0.068), false)
			var beam := _sp(root_n, "Beam", Vector3(0, SENSOR_Y, 0.08))
			WorldMechs._part(beam, mechs._box(Vector3(0.014, 0.014, 1.0), 0.0, -0.007), _sglow("beam_glow", SENSOR_COLOR), Vector3(0, 0, 0.5), false)
		"trap_relay":
			var body := _sp(root_n, "Body")
			WorldMechs._part(body, mechs._box(Vector3(0.26, 0.19, 0.26), 0.02), mechs._toon(pal.trim))
			WorldMechs._part(body, mechs._box(Vector3(0.1, 0.025, 0.008), 0.0), accent, Vector3(0, 0.12, 0.133), false)
			var rg := _sglow("relay_glow", Color("#ff9a2e"))
			var lamp := _sp(root_n, "Lamp", Vector3(0, 0.19, 0))
			WorldMechs._part(lamp, mechs._cyl(0.06, 0.04, 0.07, 10), rg, Vector3(0, 0.035, 0), false)
			for i: int in range(TICKS):
				var a := -PI * 0.5 + i * TAU / TICKS
				var t := _sp(root_n, "Tick_%02d" % (i + 1), Vector3(cos(a) * 0.105, 0.195, sin(a) * 0.105))
				WorldMechs._part(t, mechs._box(Vector3(0.03, 0.008, 0.03), 0.0), rg, Vector3.ZERO, false)
		"trap_magnet":
			var base := _sp(root_n, "Base")
			WorldMechs._part(base, mechs._cyl(0.42, 0.46, 0.05, 20), mechs._toon(Color("#b8402e")), Vector3(0, 0.025, 0), false)
			WorldMechs._part(base, mechs._box(Vector3(0.1, 0.008, 0.025), 0.0), accent, Vector3(0, 0.054, -0.34), false)
			var coil := _sp(root_n, "Coil", Vector3(0, 0.05, 0))
			WorldMechs._part(coil, mechs._ring(0.22, 0.03, 20), _sglow("magnet_glow", MAGNET_COLOR), Vector3(0, 0.02, 0), false)
			var ring := _sp(root_n, "Ring")
			WorldMechs._part(ring, mechs._ring(1.0, 0.01, 48), _sglow("magnet_ring_glow", MAGNET_COLOR), Vector3(0, 0.008, 0), false)
		_:
			WorldMechs._part(root_n, mechs._box(Vector3(0.8, 0.2, 0.8), 0.02), hazard)
	return root_n
