class_name WorldMechs
extends RefCounted
## Mechanism visuals, driven purely by MechSnap (port of prototype render/mechs/index.ts): the view
## never infers state, so a review or cinematic replay always shows exactly what the resolved run
## did (CINE-04).
##
## Readability (chapter 19: functional doors and walls must be distinguishable from decorative
## remnants): every functional piece carries the accent colour shared with whatever drives it
## (WorldMechAccent), lit when active and dim when not. Kit models (door: Frame/Panel, switch:
## Base/Lever, plate: Base/Pad, breakable + breakable_chunks, laser_emitter: Body/Lens, core:
## Shell/Heart, exit_pad) are used when present; their `accent_glow` materials take the wire colour.
## Stand-ins with the same named parts are built otherwise.

## Render layer (bit value) of mechanism geometry: visible to the camera but not to graffiti decals.
const MECH_LAYER := 4
## Kit door: Panel slides down by this much when open (art/kit/mechanisms.py PANEL_DROP).
const KIT_PANEL_DROP := 1.58
## Kit door height (DOOR_TOP); scaled down where the door stands in a cut-away wall line.
const KIT_DOOR_TOP := 1.8
const KIT_LEVER_ANGLE := 0.65
const KIT_PAD_TRAVEL := 0.045
const BEAM_Y := 0.45
const HEART_Y := 0.95
## Stand-in door height (a door in a cut-away wall line stays low enough to never hide a self).
const DOOR_HEIGHT := 0.95
const DOOR_HEIGHT_FULL := 1.5
const BREAKABLE_HEIGHT := 1.0


static func _damp(a: float, b: float, rate: float, dt: float) -> float:
	return b + (a - b) * exp(-rate * dt)


static func _smooth(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## A glow material whose brightness is set per frame without allocating.
class Lamp:
	extends RefCounted
	var materials: Array[ShaderMaterial] = []
	var param: StringName = &"energy"

	static func of(m: ShaderMaterial, p: StringName = &"energy") -> Lamp:
		var l := Lamp.new()
		l.materials.append(m)
		l.param = p
		return l

	func set_level(v: float) -> void:
		for m: ShaderMaterial in materials:
			m.set_shader_parameter(param, v)

	func set_color(c: Color) -> void:
		for m: ShaderMaterial in materials:
			m.set_shader_parameter(&"color", c)


## Base class of one mechanism's visual.
class Visual:
	extends RefCounted
	var id: String = ""
	var node: Node3D = null

	func apply(_snap: MechSnap, _dt: float) -> void:
		pass

	func tick(_dt: float, _time: float) -> void:
		pass

	func on_event(_e: SimEvent) -> void:
		pass


var level: LevelDef
var pal: WorldPalette
var kit: WorldKit
var layout: WorldLayout
var root: Node3D
## Signal id -> accent colour for this level (shared with fx / actors through accent_for()).
var accents: Dictionary = {}
var visuals: Dictionary = {}
var list: Array[Visual] = []
var used_models: Dictionary = {}
var used_standins: Dictionary = {}
var _mesh_cache: Dictionary = {}
var _dash_tex: Texture2D = null
var _exit_tex: Texture2D = null


func _init(p_level: LevelDef, p_pal: WorldPalette, p_kit: WorldKit, p_layout: WorldLayout, p_root: Node3D, extra_signals: Array[String] = []) -> void:
	level = p_level
	pal = p_pal
	kit = p_kit
	layout = p_layout
	root = p_root
	accents = WorldMechAccent.build_map(level, extra_signals)
	for e: EntityDef in level.entities:
		var v: Visual = null
		if e is DoorDef:
			v = _door(e as DoorDef, WorldMechAccent.expr_accent((e as DoorDef).open_when, accents))
		elif e is SwitchDef:
			v = _switch(e as SwitchDef, accent_for(e.id))
		elif e is PlateDef:
			v = _plate(e as PlateDef, accent_for(e.id))
		elif e is BreakableDef:
			v = _breakable(e as BreakableDef, accent_for(e.id))
		elif e is LaserDef:
			v = _laser(e as LaserDef, WorldMechAccent.expr_accent((e as LaserDef).on_when, accents))
		elif e is CoreDef:
			v = _core(e as CoreDef, accent_for(e.id))
		elif e is ExitDef:
			v = _exit(e as ExitDef)
		if v != null:
			v.id = e.id
			v.node.name = ("mech_%s" % e.id).validate_node_name()
			_set_layers(v.node)
			root.add_child(v.node)
			visuals[e.id] = v
			list.append(v)
	# Initial state from the level data, so the first frame is right even before a snapshot.
	for e: EntityDef in level.entities:
		if e is SwitchDef and visuals.has(e.id):
			var s := MechSnap.new()
			s.id = e.id
			s.kind = MechKind.SWITCH
			s.on = (e as SwitchDef).initial
			(visuals[e.id] as Visual).apply(s, 0.0)
	for v: Visual in list:
		v.tick(1.0, 0.0)


## Accent colour for a mechanism / signal id (the colour the player learns for that wire).
func accent_for(id: String) -> Color:
	return accents.get(id, WorldMechAccent.signal_accent(id))


func update(frame: RenderFrame, dt: float, time: float) -> void:
	if frame != null:
		for e: SimEvent in frame.events:
			if e.id.is_empty():
				continue
			var v: Visual = visuals.get(e.id, null)
			if v != null:
				v.on_event(e)
		if frame.snap != null:
			for m: MechSnap in frame.snap.mechs:
				var v: Visual = visuals.get(m.id, null)
				if v != null:
					v.apply(m, dt)
	for v: Visual in list:
		v.tick(dt, time)


# ───────────────────────────── shared builders ─────────────────────────────

func _set_layers(n: Node) -> void:
	if n is VisualInstance3D and not (n is Light3D) and not (n is Decal):
		(n as VisualInstance3D).layers = MECH_LAYER
	for c: Node in n.get_children():
		_set_layers(c)


func _mesh(key: String, make: Callable) -> Mesh:
	if not _mesh_cache.has(key):
		_mesh_cache[key] = make.call()
	return _mesh_cache[key]


func _box(size: Vector3, bevel: float = 0.03, y0: float = 0.0) -> Mesh:
	return _mesh("box:%s:%s:%s" % [size, bevel, y0], func() -> Mesh: return WorldGeom.chamfer_box(size, bevel, y0))


func _cyl(r0: float, r1: float, h: float, sides: int = 10, axis: int = 1) -> Mesh:
	return _mesh("cyl:%s:%s:%s:%d:%d" % [r0, r1, h, sides, axis], func() -> Mesh:
		var bld := WorldGeom.Builder.new()
		WorldGeom.cylinder_into(bld, Vector3.ZERO, r0, r1, h, sides, axis)
		return bld.build())


func _ring(big_r: float, r: float, segs: int = 24) -> Mesh:
	return _mesh("ring:%s:%s:%d" % [big_r, r, segs], func() -> Mesh:
		var bld := WorldGeom.Builder.new()
		WorldGeom.ring_into(bld, Vector3.ZERO, big_r, r, segs, 6)
		return bld.build())


func _plane(w: float, d: float) -> Mesh:
	return _mesh("plane:%s:%s" % [w, d], func() -> Mesh:
		var pm := PlaneMesh.new()
		pm.size = Vector2(w, d)
		return pm)


static func _part(parent: Node3D, m: Mesh, material: Material, pos: Vector3 = Vector3.ZERO, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _toon(c: Color, px: float = ToonKit.OUTLINE_PX) -> ShaderMaterial:
	return ToonKit.toon(c, px, pal.ink)


## Instance a kit piece (or null), noting which path was taken.
func _kit(piece: String, c: int = 0, r: int = 0) -> Node3D:
	var n: Node3D = null
	if kit != null:
		var opts := ToonKit.Options.new()
		opts.outline_color = pal.ink
		n = kit.instance(piece, c, r, opts)
	if n != null:
		used_models[piece] = true
	else:
		used_standins[piece] = true
	return n


## Glow materials of a kit instance whose name starts with `prefix`, recolour optional.
static func _glows(n: Node, prefix: String, recolor: Variant = null) -> Lamp:
	var lamp := Lamp.new()
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		for ch: Node in x.get_children():
			stack.append(ch)
		var mi := x as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s: int in range(mi.mesh.get_surface_count()):
			var m := mi.get_surface_override_material(s) as ShaderMaterial
			if m != null and m.shader == ToonKit.GLOW_SHADER and m.resource_name.begins_with(prefix) and not lamp.materials.has(m):
				if recolor is Color:
					m.set_shader_parameter(&"color", recolor)
				lamp.materials.append(m)
	return lamp


static func _find(n: Node, part: String) -> Node3D:
	if n.name == part:
		return n as Node3D
	return n.find_child(part, true, false) as Node3D


func _glow_add(c: Color, energy: float, opacity: float, radial: float = 0.0) -> ShaderMaterial:
	return ToonKit.glow_add(c, energy, opacity, radial)


# ───────────────────────────── door ─────────────────────────────

class DoorVisual:
	extends Visual
	var panels: Array[Node3D] = []
	var panel_rest: Array[float] = []
	var drop: float = 1.0
	var sink_scale: bool = false
	var strip: Lamp = Lamp.new()
	var slot: Lamp = Lamp.new()
	var status: Lamp = Lamp.new()
	var accent: Color = Color.WHITE
	var open: float = -1.0

	func apply(snap: MechSnap, dt: float) -> void:
		var target := snap.t if snap.has_t else (1.0 if snap.on else 0.0)
		if open < 0.0 or snap.has_t:
			open = target
		else:
			open = WorldMechs._damp(open, target, 10.0, dt)

	func tick(_dt: float, _time: float) -> void:
		var e := WorldMechs._smooth(maxf(0.0, open))
		for i: int in range(panels.size()):
			var p := panels[i]
			if sink_scale:
				# Sinks into the floor; a sliver stays as the lit threshold so open still reads as a door.
				p.scale.y = maxf(0.001, 1.0 - 0.95 * e)
			else:
				p.position.y = panel_rest[i] - drop * e
			p.visible = e < 0.999 or not sink_scale
		strip.set_level(2.4 - 1.8 * e)
		slot.set_level(0.35 + 2.2 * e)
		status.set_color(WorldMechAccent.STATUS_CLOSED.lerp(accent, e))
		status.set_level(2.2)


func _door(def: DoorDef, accent: Color) -> Visual:
	var v := DoorVisual.new()
	v.accent = accent
	v.node = Node3D.new()
	var cells := {}
	for cell: Vector2i in def.cells:
		cells[cell] = true
	var blocking := func(c: int, r: int) -> bool: return layout.is_wall(c, r) or cells.has(Vector2i(c, r))
	var slot_m := _glow_add(accent, 1.0, 0.85)
	v.slot = Lamp.of(slot_m)
	var strip_m := ToonKit.glow(accent, 2.4)
	var status_m := ToonKit.glow(WorldMechAccent.STATUS_CLOSED, 2.2)
	v.strip = Lamp.of(strip_m)
	v.status = Lamp.of(status_m)
	for cell: Vector2i in def.cells:
		# Span along X when the door continues a wall line east-west, otherwise along Z.
		var along_x: bool = blocking.call(cell.x - 1, cell.y) or blocking.call(cell.x + 1, cell.y) or not (blocking.call(cell.x, cell.y - 1) or blocking.call(cell.x, cell.y + 1))
		# A door in a camera-side wall line (open floor behind it) stays low, like the cut walls.
		var behind := Vector2i(cell.x, cell.y - 1) if along_x else Vector2i(cell.x - 1, cell.y)
		var behind_ch := layout.at(behind.x, behind.y)
		var behind_open := behind_ch != "#" and behind_ch != " "
		var g := Node3D.new()
		g.position = Vector3(cell.x + 0.5, 0.0, cell.y + 0.5)
		g.rotation.y = 0.0 if along_x else PI * 0.5
		v.node.add_child(g)
		var model := _kit("door", cell.x, cell.y)
		if model != null:
			var k := (DOOR_HEIGHT_FULL / KIT_DOOR_TOP) if behind_open else 1.0
			model.scale = Vector3(1.0, k, 1.0)
			g.add_child(model)
			var panel := _find(model, "Panel")
			if panel != null:
				v.panels.append(panel)
				v.panel_rest.append(panel.position.y)
			v.drop = KIT_PANEL_DROP
			v.strip.materials.append_array(_glows(model, "accent", accent).materials)
			v.status.materials.append_array(_glows(model, "status").materials)
		else:
			var h := DOOR_HEIGHT if behind_open else DOOR_HEIGHT_FULL
			v.sink_scale = true
			var panel := Node3D.new()
			panel.name = "Panel"
			g.add_child(panel)
			_part(panel, _box(Vector3(0.98, h, 0.24), 0.04), _toon(WorldPalette.mix_color(pal.metal, accent, 0.14)))
			_part(panel, _box(Vector3(0.82, 0.07, 0.26), 0.0), strip_m, Vector3(0, h * 0.72, 0), false)
			for x: float in [-0.2, 0.0, 0.2]:
				var chev := _part(panel, _box(Vector3(0.06, 0.25, 0.25), 0.0, -0.125), strip_m, Vector3(x, h * 0.35, 0), false)
				chev.rotation.z = 0.5
			v.panels.append(panel)
			v.panel_rest.append(0.0)
			var frame := Node3D.new()
			frame.name = "Frame"
			g.add_child(frame)
			var ends := [[-0.5, Vector2i(cell.x - 1, cell.y)], [0.5, Vector2i(cell.x + 1, cell.y)]] if along_x else [[-0.5, Vector2i(cell.x, cell.y - 1)], [0.5, Vector2i(cell.x, cell.y + 1)]]
			for en: Array in ends:
				if cells.has(en[1]):
					continue
				_part(frame, _box(Vector3(0.16, h + 0.2, 0.34), 0.03), _toon(WorldPalette.scale_color(pal.metal, 0.75)), Vector3(en[0], 0, 0))
				_part(frame, _box(Vector3(0.12, 0.06, 0.3), 0.0), status_m, Vector3(en[0], h + 0.22, 0), false)
		# Lit floor slots on both sides of the threshold: brighten as the door opens.
		for z: float in [-0.2, 0.2]:
			_part(g, _plane(0.94, 0.12), slot_m, Vector3(0, 0.012, z), false)
	return v


# ───────────────────────────── switch ─────────────────────────────

class SwitchVisual:
	extends Visual
	var lever: Node3D = null
	var kit_lever: bool = false
	var knob: Lamp = Lamp.new()
	var face: Lamp = Lamp.new()
	var ring: Lamp = Lamp.new()
	var target: float = 0.0
	var s: float = 0.0

	func apply(snap: MechSnap, _dt: float) -> void:
		target = 1.0 if snap.on else 0.0

	func tick(dt: float, time: float) -> void:
		s = WorldMechs._damp(s, target, 14.0, dt)
		if lever != null:
			lever.rotation.z = WorldMechs.KIT_LEVER_ANGLE - 2.0 * WorldMechs.KIT_LEVER_ANGLE * s
		knob.set_level(0.35 + 2.4 * s)
		face.set_level(0.25 + 2.0 * s)
		ring.set_level(0.3 + (1.3 + 0.3 * sin(time * 4.0)) * s)


func _switch(def: SwitchDef, accent: Color) -> Visual:
	var v := SwitchVisual.new()
	v.node = Node3D.new()
	v.node.position = Vector3(def.x, 0.0, def.y)
	v.target = 1.0 if def.initial else 0.0
	v.s = v.target
	var model := _kit("switch", int(floor(def.x)), int(floor(def.y)))
	if model != null:
		v.node.add_child(model)
		v.lever = _find(model, "Lever")
		v.knob = _glows(model, "accent", accent)
	else:
		var stone := pal.floor_finish == WorldPalette.FINISH_STONE
		_part(v.node, _box(Vector3(0.46, 0.34, 0.4), 0.04), _toon(pal.hazard if stone else WorldPalette.mix_color(pal.metal, pal.hazard, 0.25)))
		_part(v.node, _box(Vector3(0.36, 0.06, 0.3), 0.02, 0.34), _toon(pal.trim))
		var pivot := Node3D.new()
		pivot.name = "Lever"
		pivot.position = Vector3(0, 0.4, 0)
		v.node.add_child(pivot)
		var arm := _part(pivot, _cyl(0.03, 0.03, 0.34, 8), _toon(pal.metal, 1.5), Vector3(0, 0.17, 0))
		arm.name = "Arm"
		var knob_m := ToonKit.glow(accent, 1.0)
		_part(pivot, _mesh("knob", func() -> Mesh:
			var sm := SphereMesh.new()
			sm.radius = 0.075
			sm.height = 0.15
			sm.radial_segments = 12
			sm.rings = 6
			return sm), knob_m, Vector3(0, 0.36, 0), false)
		v.knob = Lamp.of(knob_m)
		v.lever = pivot
		var face_m := ToonKit.glow(accent, 1.0)
		_part(v.node, _box(Vector3(0.2, 0.08, 0.02), 0.0), face_m, Vector3(0, 0.16, 0.205), false)
		v.face = Lamp.of(face_m)
	var ring_m := _glow_add(accent, 1.0, 0.9)
	ring_m.set_shader_parameter(&"use_texture", true)
	ring_m.set_shader_parameter(&"tex", _ring_texture())
	_part(v.node, _plane(0.9, 0.9), ring_m, Vector3(0, 0.012, 0), false)
	v.ring = Lamp.of(ring_m)
	return v


# ───────────────────────────── plate ─────────────────────────────

class PlateVisual:
	extends Visual
	var pad: Node3D = null
	var pad_rest: float = 0.0
	var edge: Lamp = Lamp.new()
	var glow: Lamp = Lamp.new()
	var target: float = 0.0
	var s: float = 0.0

	func apply(snap: MechSnap, _dt: float) -> void:
		target = 1.0 if snap.on else 0.0

	func tick(dt: float, _time: float) -> void:
		s = WorldMechs._damp(s, target, 18.0, dt)
		if pad != null:
			pad.position.y = pad_rest - WorldMechs.KIT_PAD_TRAVEL * s
		edge.set_level(0.45 + 2.3 * s)
		glow.set_level(0.08 + 1.2 * s)


func _plate(def: PlateDef, accent: Color) -> Visual:
	var v := PlateVisual.new()
	v.node = Node3D.new()
	v.node.position = Vector3(def.c + 0.5, 0.0, def.r + 0.5)
	var size := 0.84 if def.heavy else 0.7
	var model := _kit("plate", def.c, def.r)
	if model != null:
		if def.heavy:
			model.scale = Vector3(1.2, 1.0, 1.2)
		v.node.add_child(model)
		v.pad = _find(model, "Pad")
		v.edge = _glows(model, "accent", accent)
	else:
		var frame_m: Material = _toon(pal.trim, 1.0)
		if def.heavy:
			frame_m = ToonKit.surface(5, 5, pal.hazard, pal.trim, WorldPalette.scale_color(pal.trim, 0.6), 1.0, pal.ink)
			(frame_m as ShaderMaterial).set_shader_parameter(&"accent_color", pal.hazard)
		_part(v.node, _box(Vector3(size + 0.12, 0.035, size + 0.12), 0.01), frame_m, Vector3.ZERO, false)
		var pad := Node3D.new()
		pad.name = "Pad"
		v.node.add_child(pad)
		_part(pad, _box(Vector3(size - 0.06, 0.07, size - 0.06), 0.02), _toon(WorldPalette.mix_color(pal.metal, accent, 0.22), 1.0), Vector3.ZERO, false)
		var edge_m := ToonKit.glow(accent, 1.0)
		var e := size * 0.5
		for spec: Array in [[Vector3(0, 0.045, -e), 0.0], [Vector3(0, 0.045, e), 0.0], [Vector3(-e, 0.045, 0), PI * 0.5], [Vector3(e, 0.045, 0), PI * 0.5]]:
			var bar := _part(pad, _box(Vector3(size, 0.03, 0.04), 0.0), edge_m, spec[0], false)
			bar.rotation.y = spec[1]
		v.pad = pad
		v.edge = Lamp.of(edge_m)
	var glow_m := _glow_add(accent, 1.0, 0.9, 1.0)
	_part(v.node, _plane(size * 1.3, size * 1.3), glow_m, Vector3(0, 0.09, 0), false)
	v.glow = Lamp.of(glow_m)
	return v


# ───────────────────────────── breakable ─────────────────────────────

class BreakableVisual:
	extends Visual
	var block: Node3D = null
	var chunks: Array[Node3D] = []
	var start: PackedVector3Array = PackedVector3Array()
	var rest: PackedVector3Array = PackedVector3Array()
	var vel: PackedVector3Array = PackedVector3Array()
	var spin: PackedVector3Array = PackedVector3Array()
	var rng: WorldRng = null
	var broken: bool = false
	var first: bool = true
	var flying: float = 0.0
	var push := Vector2.ZERO

	func on_event(e: SimEvent) -> void:
		if e.type == SimEventType.BREAK and e.has_dir:
			push = Vector2(cos(e.dir), sin(e.dir))

	func apply(snap: MechSnap, _dt: float) -> void:
		if snap.on == broken and not first:
			return
		var was_first := first
		first = false
		broken = snap.on
		block.visible = not broken
		if broken:
			# Already broken when first seen (joining a replay mid-way): show the rubble.
			if was_first:
				_settle()
			else:
				_shatter()
		else:
			for c: Node3D in chunks:
				c.visible = false
			flying = 0.0
			push = Vector2.ZERO

	func _settle() -> void:
		for i: int in range(chunks.size()):
			var c := chunks[i]
			c.visible = true
			c.position = rest[i]
			c.rotation = Vector3(0, i * 1.7, 0)
		flying = 0.0

	func _shatter() -> void:
		for i: int in range(chunks.size()):
			var c := chunks[i]
			c.visible = true
			c.position = start[i]
			c.rotation = Vector3.ZERO
			var o := start[i]
			vel[i] = Vector3(o.x * 3.0 + push.x * rng.range_f(1.5, 3.5), rng.range_f(1.5, 4.0), o.z * 3.0 + push.y * rng.range_f(1.5, 3.5))
			spin[i] = Vector3(rng.range_f(-9, 9), rng.range_f(-9, 9), rng.range_f(-9, 9))
		flying = 2.2

	func tick(dt: float, _time: float) -> void:
		if flying <= 0.0:
			return
		flying -= dt
		var step := minf(dt, 1.0 / 30.0)
		for i: int in range(chunks.size()):
			var c := chunks[i]
			var vv := vel[i]
			vv.y -= 14.0 * step
			var p := c.position + vv * step
			var sp := spin[i]
			if p.y < 0.0:
				p.y = 0.0
				vv = Vector3(vv.x * 0.6, -vv.y * 0.3, vv.z * 0.6)
				sp = Vector3(sp.x * 0.5, sp.y, sp.z * 0.5)
			c.position = p
			c.rotation += sp * step
			vel[i] = vv
			spin[i] = sp
		if flying <= 0.0:
			for c: Node3D in chunks:
				c.position.y = maxf(0.0, c.position.y)
				c.rotation.x = 0.0
				c.rotation.z = 0.0


func _breakable(def: BreakableDef, accent: Color) -> Visual:
	var v := BreakableVisual.new()
	v.node = Node3D.new()
	v.node.position = Vector3(def.c + 0.5, 0.0, def.r + 0.5)
	v.rng = WorldRng.new(WorldRng.hash_string(def.id) ^ 0xb7ea)
	var model := _kit("breakable", def.c, def.r)
	if model != null:
		v.block = model
		v.node.add_child(model)
		_glows(model, "accent", accent)
	else:
		var block := Node3D.new()
		block.name = "Block"
		v.node.add_child(block)
		var crack_m := ToonKit.surface(1, 1, WorldPalette.mix_color(pal.wall_top, pal.rust, 0.2), WorldPalette.mix_color(pal.wall, pal.rust, 0.15), pal.grout, ToonKit.OUTLINE_PX, pal.ink)
		crack_m.set_shader_parameter(&"wear", 0.9)
		crack_m.set_shader_parameter(&"blotch", 0.3)
		crack_m.set_shader_parameter(&"accent_color", WorldPalette.mix_color(pal.warm, accent, 0.35))
		_part(block, _box(Vector3(0.96, BREAKABLE_HEIGHT, 0.96), 0.07), crack_m)
		# Glowing fissures and a hazard tag so the breakable reads as functional at a glance (chapter 19).
		var fissure := ToonKit.glow(WorldPalette.mix_color(pal.warm, accent, 0.35), 2.2)
		for spec: Array in [[Vector3(0.1, 0.5, 0.485), Vector3(0.04, 0.7, 0.02), 0.35], [Vector3(0.485, 0.45, -0.05), Vector3(0.02, 0.6, 0.04), -0.4]]:
			var f := _part(block, _box(spec[1], 0.0), fissure, spec[0], false)
			f.rotation.z = spec[2]
		var tag_m := ToonKit.glow(accent, 1.8)
		_part(block, _box(Vector3(0.5, 0.06, 0.02), 0.0), tag_m, Vector3(0, BREAKABLE_HEIGHT * 0.82, 0.49), false)
		var t2 := _part(block, _box(Vector3(0.5, 0.06, 0.02), 0.0), tag_m, Vector3(0.49, BREAKABLE_HEIGHT * 0.82, 0), false)
		t2.rotation.y = PI * 0.5
		v.block = block
	var chunk_model := _kit("breakable_chunks", def.c, def.r)
	if chunk_model != null:
		v.node.add_child(chunk_model)
		for i: int in range(1, 13):
			var c := _find(chunk_model, "Chunk_%02d" % i)
			if c == null:
				continue
			v.chunks.append(c)
			v.start.append(c.position)
			var a := v.rng.range_f(0.0, TAU)
			var d := v.rng.range_f(0.25, 0.9)
			v.rest.append(Vector3(cos(a) * d, 0.0, sin(a) * d))
			c.visible = false
	else:
		var chunk_m := _toon(WorldPalette.mix_color(pal.wall, pal.rust, 0.15), 1.5)
		for i: int in range(12):
			var k := v.rng.range_i(0, 3)
			var c := _part(v.node, _mesh("chunk%d" % k, func() -> Mesh: return WorldGeom.rock(k * 31 + 7, 0.18, 0.8)), chunk_m)
			c.scale = Vector3.ONE * v.rng.range_f(0.6, 1.25)
			c.visible = false
			v.chunks.append(c)
			v.start.append(Vector3(v.rng.range_f(-0.35, 0.35), v.rng.range_f(0.1, BREAKABLE_HEIGHT - 0.1), v.rng.range_f(-0.35, 0.35)))
			var a := v.rng.range_f(0.0, TAU)
			var d := v.rng.range_f(0.25, 0.9)
			v.rest.append(Vector3(cos(a) * d, 0.0, sin(a) * d))
	v.vel.resize(v.chunks.size())
	v.spin.resize(v.chunks.size())
	return v


# ───────────────────────────── laser ─────────────────────────────

class LaserVisual:
	extends Visual
	var beam: Node3D = null
	var core: MeshInstance3D = null
	var halo: MeshInstance3D = null
	var guide: MeshInstance3D = null
	var core_l: Lamp = Lamp.new()
	var halo_l: Lamp = Lamp.new()
	var lens: Lamp = Lamp.new()
	var ring: Lamp = Lamp.new()
	var guide_m: ShaderMaterial = null
	var target: float = 0.0
	var s: float = 0.0

	func apply(snap: MechSnap, _dt: float) -> void:
		target = 1.0 if snap.on else 0.0

	func tick(dt: float, time: float) -> void:
		s = WorldMechs._damp(s, target, 30.0, dt)
		var flicker := 1.0 + 0.08 * sin(time * 61.0) + 0.05 * sin(time * 23.0)
		beam.visible = s > 0.02
		core.scale = Vector3(1.0, 0.4 + 0.6 * s, 0.4 + 0.6 * s)
		var hs := (0.6 + 0.4 * s) * flicker
		halo.scale = Vector3(1.0, hs, hs)
		core_l.set_level(3.2 * s * flicker)
		halo_l.set_level(1.4 * s)
		lens.set_level(0.4 + 2.6 * s)
		ring.set_level(0.5 + 1.8 * s)
		# Off: a faint dashed guide on the floor shows where the beam will be.
		guide.visible = s < 0.98
		guide_m.set_shader_parameter(&"opacity", 0.6 * (1.0 - s))


func _laser(def: LaserDef, accent: Color) -> Visual:
	var v := LaserVisual.new()
	v.node = Node3D.new()
	var d := def.to - def.from
	var length := maxf(0.01, d.length())
	var ang := atan2(d.y, d.x)
	var lens_m := ToonKit.glow(WorldMechAccent.LASER_BEAM, 1.0)
	var ring_m := ToonKit.glow(accent, 1.0)
	v.lens = Lamp.of(lens_m)
	v.ring = Lamp.of(ring_m)
	for spec: Array in [[def.from, ang], [def.to, ang + PI]]:
		var p: Vector2 = spec[0]
		var g := Node3D.new()
		g.position = Vector3(p.x, 0.0, p.y)
		g.rotation.y = RenderCtx.heading_to_yaw(spec[1])
		v.node.add_child(g)
		var model := _kit("laser_emitter", int(floor(p.x)), int(floor(p.y)))
		if model != null:
			g.add_child(model)
			v.lens.materials.append_array(_glows(model, "lens", WorldMechAccent.LASER_BEAM).materials)
			v.ring.materials.append_array(_glows(model, "accent", accent).materials)
		else:
			_part(g, _box(Vector3(0.36, 0.7, 0.36), 0.04), _toon(pal.trim))
			_part(g, _box(Vector3(0.38, 0.05, 0.38), 0.0), ring_m, Vector3(0, 0.6, 0), false)
			var lens := _part(g, _cyl(0.08, 0.08, 0.06, 12, 2), lens_m, Vector3(0, BEAM_Y, 0.19), false)
			lens.name = "Lens"
	var beam := Node3D.new()
	beam.position = Vector3((def.from.x + def.to.x) * 0.5, BEAM_Y, (def.from.y + def.to.y) * 0.5)
	beam.rotation.y = -ang
	v.node.add_child(beam)
	var core_m := ToonKit.glow(WorldPalette.mix_color(WorldMechAccent.LASER_BEAM, Color.WHITE, 0.35), 3.2)
	var halo_m := _glow_add(WorldMechAccent.LASER_BEAM, 1.4, 0.55)
	halo_m.set_shader_parameter(&"fresnel_fade", 0.7)
	v.core = _part(beam, _cyl(0.035, 0.035, length, 8, 0), core_m, Vector3.ZERO, false)
	v.halo = _part(beam, _cyl(0.11, 0.11, length, 10, 0), halo_m, Vector3.ZERO, false)
	v.core_l = Lamp.of(core_m)
	v.halo_l = Lamp.of(halo_m)
	v.beam = beam
	var guide_m := _glow_add(WorldMechAccent.LASER_BEAM, 0.9, 0.6)
	guide_m.set_shader_parameter(&"use_texture", true)
	guide_m.set_shader_parameter(&"tex", _dash_texture())
	guide_m.set_shader_parameter(&"uv_scale", Vector2(length * 3.0, 1.0))
	guide_m.set_shader_parameter(&"uv_scroll", Vector2(-0.6, 0.0))
	v.guide = _part(v.node, _plane(length, 0.08), guide_m, Vector3(beam.position.x, 0.012, beam.position.z), false)
	v.guide.rotation.y = -ang
	v.guide_m = guide_m
	return v


# ───────────────────────────── core ─────────────────────────────

class CoreVisual:
	extends Visual
	var heart: Node3D = null
	var heart_rest: float = HEART_Y
	var heart_m: Lamp = Lamp.new()
	var ring_node: Node3D = null
	var ring: Lamp = Lamp.new()
	var halo: MeshInstance3D = null
	var halo_l: Lamp = Lamp.new()
	var target: float = 0.0
	var s: float = 0.0
	var spin: float = 0.0
	var flash: float = 0.0

	func apply(snap: MechSnap, _dt: float) -> void:
		var next := 1.0 if snap.on else 0.0
		if next == 1.0 and target == 0.0 and s < 0.5:
			flash = 1.0
		target = next

	func on_event(e: SimEvent) -> void:
		if e.type == SimEventType.CORE:
			flash = 1.0

	func tick(dt: float, time: float) -> void:
		s = WorldMechs._damp(s, target, 5.0, dt)
		flash = maxf(0.0, flash - dt * 2.5)
		spin += dt * (0.5 + 3.0 * s)
		if heart != null:
			heart.rotation.y = spin
			heart.position.y = heart_rest + s * (0.12 + sin(time * 2.2) * 0.05)
		heart_m.set_level(0.25 + 2.4 * s + flash * 2.0)
		ring.set_level(0.3 + 2.2 * s)
		if ring_node != null:
			ring_node.scale = Vector3.ONE * (1.0 + flash * 0.8)
			ring_node.rotation.y = -spin * 0.5
		halo_l.set_level(0.6 * s + flash)
		halo.visible = s > 0.02 or flash > 0.0
		if heart != null:
			halo.position.y = heart.position.y
		halo.scale = Vector3.ONE * (1.0 + 0.08 * sin(time * 5.0) + flash * 0.6)


func _core(def: CoreDef, accent: Color) -> Visual:
	var v := CoreVisual.new()
	v.node = Node3D.new()
	v.node.position = Vector3(def.x, 0.0, def.y)
	var model := _kit("core", int(floor(def.x)), int(floor(def.y)))
	if model != null:
		v.node.add_child(model)
		v.heart = _find(model, "Heart")
		if v.heart != null:
			v.heart_rest = v.heart.position.y
		v.heart_m = _glows(model, "core", accent)
		v.ring = _glows(model, "accent", accent)
	else:
		_part(v.node, _cyl(0.36, 0.42, 0.22, 8), _toon(pal.trim), Vector3(0, 0.11, 0))
		_part(v.node, _cyl(0.16, 0.24, 0.3, 8), _toon(pal.metal), Vector3(0, 0.37, 0))
		var heart := Node3D.new()
		heart.name = "Heart"
		heart.position = Vector3(0, HEART_Y, 0)
		v.node.add_child(heart)
		var crystal_m := ToonKit.toon_emissive(WorldPalette.mix_color(pal.metal, accent, 0.3), accent, 0.25, 1.5)
		var crystal := _part(heart, _mesh("coreCrystal", func() -> Mesh:
			var bld := WorldGeom.Builder.new()
			var pts := [Vector3(0, 0.36, 0), Vector3(0, -0.36, 0), Vector3(0.24, 0, 0), Vector3(-0.24, 0, 0), Vector3(0, 0, 0.24), Vector3(0, 0, -0.24)]
			for f: Array in [[0, 2, 4], [0, 4, 3], [0, 3, 5], [0, 5, 2], [1, 4, 2], [1, 3, 4], [1, 5, 3], [1, 2, 5]]:
				bld.poly([pts[f[0]], pts[f[1]], pts[f[2]]], Vector3.ZERO)
			return bld.build()), crystal_m, Vector3.ZERO, false)
		crystal.name = "Crystal"
		v.heart = heart
		v.heart_m = Lamp.of(crystal_m, &"emission_energy")
		var ring_m := ToonKit.glow(accent, 1.0)
		v.ring_node = _part(v.node, _ring(0.34, 0.025, 32), ring_m, Vector3(0, 0.55, 0), false)
		v.ring = Lamp.of(ring_m)
	var halo_m := _glow_add(accent, 1.0, 0.6)
	halo_m.set_shader_parameter(&"fresnel_fade", 1.0)
	v.halo = _part(v.node, _mesh("coreHalo", func() -> Mesh:
		var sm := SphereMesh.new()
		sm.radius = 0.42
		sm.height = 0.84
		sm.radial_segments = 16
		sm.rings = 8
		return sm), halo_m, Vector3(0, HEART_Y, 0), false)
	v.halo_l = Lamp.of(halo_m)
	return v


# ───────────────────────────── exit ─────────────────────────────

class ExitVisual:
	extends Visual
	var pad: Lamp = Lamp.new()
	var tips: Lamp = Lamp.new()
	var pad_m: ShaderMaterial = null
	var target: float = 0.0
	var s: float = 0.0

	func apply(snap: MechSnap, _dt: float) -> void:
		target = 1.0 if snap.on else 0.0

	func tick(dt: float, time: float) -> void:
		s = WorldMechs._damp(s, target, 8.0, dt)
		var breathe := 0.5 + 0.5 * sin(time * 3.0)
		pad.set_level(0.55 + 0.2 * breathe + 1.9 * s)
		tips.set_level(0.8 + 2.0 * s)
		pad_m.set_shader_parameter(&"uv_scroll", Vector2(0.0, -(0.2 + 0.6 * s)))


func _exit(def: ExitDef) -> Visual:
	var v := ExitVisual.new()
	v.node = Node3D.new()
	v.node.position = Vector3(def.c + def.w * 0.5, 0.0, def.r + def.h * 0.5)
	var any_model := false
	for dr: int in range(def.h):
		for dc: int in range(def.w):
			var model := _kit("exit_pad", def.c + dc, def.r + dr)
			if model != null:
				any_model = true
				model.position = Vector3(dc - def.w * 0.5 + 0.5, 0.0, dr - def.h * 0.5 + 0.5)
				v.node.add_child(model)
				v.tips.materials.append_array(_glows(model, "exit", WorldMechAccent.EXIT_ACCENT).materials)
	var pad_m := _glow_add(WorldMechAccent.EXIT_ACCENT, 1.0, 0.9)
	pad_m.set_shader_parameter(&"use_texture", true)
	pad_m.set_shader_parameter(&"tex", _exit_texture())
	pad_m.set_shader_parameter(&"uv_scale", Vector2(def.w, def.h))
	_part(v.node, _plane(def.w - 0.08, def.h - 0.08), pad_m, Vector3(0, 0.014 if not any_model else 0.06, 0), false)
	v.pad = Lamp.of(pad_m)
	v.pad_m = pad_m
	if not any_model:
		var tip_m := ToonKit.glow(WorldMechAccent.EXIT_ACCENT, 1.0)
		v.tips = Lamp.of(tip_m)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var x := sx * (def.w - 0.14) * 0.5
				var z := sz * (def.h - 0.14) * 0.5
				_part(v.node, _box(Vector3(0.12, 0.36, 0.12), 0.02), _toon(pal.metal, 1.5), Vector3(x, 0, z))
				_part(v.node, _box(Vector3(0.1, 0.06, 0.1), 0.0), tip_m, Vector3(x, 0.38, z), false)
	return v


# ───────────────────────────── textures ─────────────────────────────

func _dash_texture() -> Texture2D:
	if _dash_tex == null:
		var img := Image.create(32, 8, false, Image.FORMAT_RGBA8)
		for x: int in range(32):
			for y: int in range(8):
				var on := x < 18
				img.set_pixel(x, y, Color(1, 1, 1, 1) if on else Color(0, 0, 0, 0))
		img.generate_mipmaps()
		_dash_tex = ImageTexture.create_from_image(img)
	return _dash_tex


func _exit_texture() -> Texture2D:
	if _exit_tex == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y: int in range(n):
			for x: int in range(n):
				var u := float(x) / n
				var vv := float(y) / n
				# Chevrons pointing "up" the pad, plus a bright border.
				var chev := fposmod(vv + absf(u - 0.5) * 0.8, 0.5) < 0.16
				var border := u < 0.06 or u > 0.94 or vv < 0.06 or vv > 0.94
				var a := 0.9 if border else (0.65 if chev else 0.12)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		img.generate_mipmaps()
		_exit_tex = ImageTexture.create_from_image(img)
	return _exit_tex


static var _ring_tex: Texture2D = null


static func _ring_texture() -> Texture2D:
	if _ring_tex == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y: int in range(n):
			for x: int in range(n):
				var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
				var a := clampf(1.0 - absf(d - 0.85) / 0.08, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		img.generate_mipmaps()
		_ring_tex = ImageTexture.create_from_image(img)
	return _ring_tex
