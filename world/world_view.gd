extends WorldViewBase
## OVERDUB's 3D world (prototype render/Renderer.ts): builds a level from the kit, owns the
## isometric camera, lighting, WorldEnvironment and post grade, animates mechanisms from MechSnap,
## and hosts the actor and fx layers (RenderLayerBase plumbing in WorldViewBase).
##
## Per frame (render): mechanisms and ambient animation, then the layers update (and may request
## shake / focus through RenderCtx), then the camera frames the result and the post pass is fed.
##
## Extra API beyond WorldViewBase (for the game / UI engineers):
##   set_bottom_inset(px)   viewport pixels at the bottom covered by the HUD; the camera frames
##                          the level in the band above it (screen_to_world stays exact).
##   accent_for(id) -> Color  the wire accent colour of a mechanism / signal id.
##   palette() -> WorldPalette, layout() -> WorldLayout, camera_rig() -> WorldIsoCamera.
##   traps() -> WorldTraps  the trap visuals of the loaded level (TrapDef entities).
##   set_backdrop(tex)      a plate drawn behind the diorama (null = the theme's flat background).
##                          load_level picks assets/textures/backdrops/<theme>.(png|jpg|webp) when
##                          such a file exists.
##   musicviz() -> MusicVizHub   the music visualisers mounted in the level (WorldMusicViz places
##                          them); set_music_tracks(tracks) passes the cassette states the game
##                          sends the audio (until then they are derived from the snapshot).
##   set_cinema_plan(plan)  the cinematic director's plan for the coming CINEMATIC playback (null
##                          clears it). In CINEMATIC mode the camera then obeys the director's
##                          per-frame directives (target, zoom, yaw, hard cuts on the beat, letterbox
##                          via the fx layer, split-screen panes). A RenderFrame.cinema the game
##                          fills itself takes precedence.
##   set_reduce_flashing(on), set_shake_scale(k)   accessibility (docs/ACCESSIBILITY.md).

var camera: Camera3D = null
var key_light: DirectionalLight3D = null
var world_env: WorldEnvironment = null
var post: WorldPost = null
var iso: WorldIsoCamera = WorldIsoCamera.new()
## Backdrop plate (camera child, just inside the far plane); hidden when no plate is set.
var backdrop: MeshInstance3D = null

const BACKDROP_DIR := "res://assets/textures/backdrops/"
## The plate is drawn slightly below full brightness so it never feeds the glow pass.
const BACKDROP_ENERGY := 0.88

var _env_root: Node3D = null
var _builder: WorldBuilder = null
var _mechs: WorldMechs = null
var _traps: WorldTraps = null
var _layout: WorldLayout = null
var _pal: WorldPalette = WorldPalette.for_theme(LevelTheme.UPPER)
var _practicals: Array[OmniLight3D] = []
var _time: float = 0.0
var _bottom_inset: float = 0.0
var _framing := WorldIsoCamera.Framing.new()
var _hub: MusicVizHub = null
var _mv: WorldMusicViz = null
var _cine: CinemaDirector = null
var _split: WorldSplitView = null
## Last cinema frame applied (tools / tests); null outside a directed cinematic.
var cinema_frame: CinemaFrame = null
var reduce_flashing: bool = false
## Screen-shake scale (0 off, 0.4 reduced, 1 full); multiplies every shake request.
var shake_scale: float = 1.0


func _ready() -> void:
	_ensure_nodes()
	attach_layers()


func _ensure_nodes() -> void:
	if camera != null:
		return
	camera = Camera3D.new()
	camera.name = "Camera"
	add_child(camera)
	camera.current = true
	backdrop = MeshInstance3D.new()
	backdrop.name = "Backdrop"
	backdrop.mesh = QuadMesh.new()
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	backdrop.position = Vector3(0.0, 0.0, -WorldIsoCamera.FAR * 0.97)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(BACKDROP_ENERGY, BACKDROP_ENERGY, BACKDROP_ENERGY)
	bm.disable_receive_shadows = true
	bm.disable_fog = true
	bm.render_priority = -100
	backdrop.material_override = bm
	backdrop.visible = false
	camera.add_child(backdrop)
	key_light = DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.shadow_enabled = true
	key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	key_light.shadow_bias = 0.04
	key_light.shadow_normal_bias = 1.2
	key_light.shadow_blur = 0.6
	add_child(key_light)
	world_env = WorldEnvironment.new()
	world_env.name = "Environment"
	world_env.environment = Environment.new()
	add_child(world_env)
	post = WorldPost.new()
	add_child(post)
	_hub = MusicVizHub.new()
	_hub.name = "MusicViz"
	add_child(_hub)
	_mv = WorldMusicViz.new(_hub)
	_cine = CinemaDirector.new()
	_cine.name = "CinemaDirector"
	add_child(_cine)
	_split = WorldSplitView.new()
	add_child(_split)
	_apply_lighting(_pal, null)


# ───────────────────────────── facade ─────────────────────────────

func load_level(level: LevelDef, loadout: ResolvedLoadout) -> void:
	_ensure_nodes()
	attach_layers()
	_unload()
	_pal = WorldPalette.for_theme(level.theme)
	ToonKit.theme_shadow_tint = _pal.shadow_tint
	ToonKit.theme_ink = _pal.ink
	_layout = WorldLayout.compute(level)

	_env_root = Node3D.new()
	_env_root.name = "World"
	add_child(_env_root)
	var kit := WorldKit.new(level.theme, _pal.ink, WorldKit.glow_overrides(_pal))
	var trap_specs := WorldTraps.specs_from(WorldTraps.defs_for(level))
	_builder = WorldBuilder.new(level, _layout, _pal, kit, _env_root)
	_builder.skip_walls = WorldTraps.replaced_walls(trap_specs, _layout)
	_builder.build()
	var mech_root := Node3D.new()
	mech_root.name = "Mechanisms"
	_env_root.add_child(mech_root)
	_mechs = WorldMechs.new(level, _pal, kit, _layout, mech_root, WorldTraps.accent_signals(trap_specs))
	_traps = WorldTraps.new(trap_specs, _mechs, mech_root)
	WorldDecals.new(level, _layout, _pal, _env_root, trap_specs).build()
	# A plan belongs to one level's playback; the game sets a new one when the cinematic starts.
	set_cinema_plan(null)
	_mv.build(level, _layout, _env_root, _builder.reactive, _builder.skip_walls)

	_apply_lighting(_pal, _layout)
	set_backdrop(backdrop_for(level.theme))
	_build_practicals()
	post.set_palette(_pal)
	post.reset_controls()

	iso.set_bounds(_layout.bounds_aabb())
	_sync_viewport()
	iso.introduce()
	iso.apply_to(camera)

	var c := new_ctx(level, loadout)
	c.camera = camera
	c.palette = _pal
	c.bounds = _layout.bounds_aabb()
	c.toon_ramp = ToonKit.ramp()
	c.toon_material = ToonKit.toon(Color.WHITE, ToonKit.OUTLINE_PX, _pal.ink)
	c.music_reactive = _builder.reactive
	c.post = post.controls
	c.time = _time
	c.reduce_flashing = reduce_flashing
	c.shake_scale = shake_scale
	c.musicviz_mounted = _mv.mounted()
	for r: MusicReactive in c.music_reactive:
		r.set_level(1.0)
	_apply_quality()
	_load_layers(c)
	level_loaded.emit(level)


func render(frame: RenderFrame) -> void:
	if ctx == null or _builder == null:
		return
	var dt := clampf(frame.dt if frame != null else 0.0, 0.0, 0.1)
	_time += dt
	ctx.time = _time
	ctx.quality = quality
	ctx.screen_shake_enabled = screen_shake_enabled
	ctx.reduce_flashing = reduce_flashing
	ctx.shake_scale = shake_scale
	_mechs.update(frame, dt, _time)
	_traps.update(frame, dt, _time)
	for a: Callable in _builder.animators:
		a.call(_time, dt)
	_direct_cinema(frame)
	_mv.update(frame)
	_update_layers(frame)
	_frame_camera(frame, dt)
	_sync_split()
	post.update(dt)


func screen_up_in_world() -> Vector2:
	return iso.screen_up_in_world()


func screen_to_world(screen_pos: Vector2) -> Vector2:
	_sync_viewport()
	return iso.screen_to_world(screen_pos)


## Sim point at height h -> viewport position (pixels), for UI anchoring.
func world_to_screen(x: float, y: float, h: float = 0.0) -> Vector2:
	_sync_viewport()
	return iso.world_to_screen(Vector3(x, h, y))


func set_quality(q: StringName) -> void:
	super.set_quality(q)
	_apply_quality()
	if _hub != null:
		_hub.set_quality(q == QUALITY_LOW)


## The level's music visualisers (null before the first load).
func musicviz() -> MusicVizHub:
	return _hub


## Where the music visualisers were mounted this level (diagnostics / tools / tests).
func musicviz_counts() -> Dictionary:
	return _mv.counts if _mv != null else {}


## The cassette states the game sends the audio (AudioBase.set_tracks), for the visualisers.
func set_music_tracks(tracks: Array) -> void:
	if _mv != null:
		_mv.set_tracks(tracks)


## The cinematic director's plan for this level's CINEMATIC playback (null clears it; load_level
## clears it too). While a plan is set and the frame is in CINEMATIC mode, the camera follows the
## director (docs/CINEMATIC.md).
func set_cinema_plan(plan: CinemaPlan) -> void:
	_ensure_nodes()
	_cine.set_plan(plan)
	cinema_frame = null


func cinema_director() -> CinemaDirector:
	return _cine


## Accessibility: no large-area flashes, capped chromatic kicks and calmer pulses.
func set_reduce_flashing(on: bool) -> void:
	reduce_flashing = on
	if ctx != null:
		ctx.reduce_flashing = on


## Accessibility: screen-shake scale (0 off, 0.4 reduced, 1 full).
func set_shake_scale(k: float) -> void:
	shake_scale = clampf(k, 0.0, 1.0)
	if ctx != null:
		ctx.shake_scale = shake_scale
	if shake_scale <= 0.0:
		iso.trauma = 0.0


func set_screen_shake(enabled: bool) -> void:
	super.set_screen_shake(enabled)
	if not enabled:
		iso.trauma = 0.0


## Viewport pixels at the bottom covered by the HUD; the camera frames the playfield above it.
func set_bottom_inset(px: float) -> void:
	_bottom_inset = maxf(0.0, px)
	_sync_viewport()


func dispose() -> void:
	super.dispose()
	_unload()


func request_shake(magnitude: float) -> void:
	if screen_shake_enabled and shake_scale > 0.0:
		iso.add_trauma(magnitude * shake_scale)


func request_focus(x: float, y: float, weight: float) -> void:
	iso.request_focus(x, y, weight)


func surface_height(x: float, y: float) -> float:
	return _layout.surface_height(x, y) if _layout != null else 0.0


func accent_for(id: String) -> Color:
	return _mechs.accent_for(id) if _mechs != null else WorldMechAccent.signal_accent(id)


func palette() -> WorldPalette:
	return _pal


func layout() -> WorldLayout:
	return _layout


func camera_rig() -> WorldIsoCamera:
	return iso


## Backdrop plate behind the level (null hides it and leaves the palette's flat background).
func set_backdrop(tex: Texture2D) -> void:
	_ensure_nodes()
	(backdrop.material_override as StandardMaterial3D).albedo_texture = tex
	backdrop.visible = tex != null
	_fit_backdrop()


## The theme's backdrop plate from BACKDROP_DIR, or null when none has been made.
static func backdrop_for(theme: StringName) -> Texture2D:
	for ext: String in ["png", "jpg", "webp"]:
		var path := "%s%s.%s" % [BACKDROP_DIR, theme, ext]
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


func traps() -> WorldTraps:
	return _traps


## Diagnostics: instance counts per element family, and which kit pieces came from models.
func build_stats() -> Dictionary:
	if _builder == null:
		return {}
	var models := _builder.used_models.duplicate()
	models.merge(_mechs.used_models)
	var standins := _builder.used_standins.duplicate()
	standins.merge(_mechs.used_standins)
	var counts := _builder.stats.duplicate()
	counts["trap"] = _traps.list.size() if _traps != null else 0
	return {"counts": counts, "models": models.keys(), "standins": standins.keys(), "reactive": _builder.reactive.size(), "practicals": _practicals.size()}


# ───────────────────────────── internals ─────────────────────────────

func _unload() -> void:
	if _env_root != null:
		remove_child(_env_root)
		_env_root.queue_free()
		_env_root = null
	for p: OmniLight3D in _practicals:
		if is_instance_valid(p):
			p.queue_free()
	_practicals.clear()
	_builder = null
	_mechs = null
	_traps = null
	if _mv != null:
		_mv.dispose()
	if _split != null:
		_split.clear()
	cinema_frame = null
	if actor_layer != null and ctx != null:
		actor_layer.dispose()
	if fx_layer != null and ctx != null:
		fx_layer.dispose()
	ctx = null


func _sync_viewport() -> void:
	var size := Vector2(1600, 900)
	if is_inside_tree():
		size = get_viewport().get_visible_rect().size
	iso.set_viewport(size.x, size.y)
	iso.set_bottom_inset(_bottom_inset)


func _apply_lighting(pal: WorldPalette, L: WorldLayout) -> void:
	var env := world_env.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = pal.background
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = pal.ambient
	env.ambient_light_energy = pal.ambient_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = pal.glow_intensity
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = pal.glow_threshold
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i: int in range(7):
		env.set_glow_level(i, i >= 1 and i <= 4)
	env.fog_enabled = false
	env.ssao_enabled = false
	key_light.light_color = pal.key_light
	key_light.light_energy = pal.sun_energy
	# Sun from the camera's left (+Z, slightly -X): +Z faces read lit, +X faces shaded - the classic
	# iso three-tone block (prototype Renderer.applyLighting).
	var to_light := Vector3(-0.35, 1.0, 0.75).normalized()
	var centre := Vector3.ZERO
	var span := 20.0
	if L != null:
		centre = Vector3((L.min_x + L.max_x) * 0.5, 0.0, (L.min_z + L.max_z) * 0.5)
		span = Vector2(L.max_x - L.min_x, L.max_z - L.min_z).length()
	key_light.global_transform = Transform3D(Basis.looking_at(-to_light, Vector3.UP), centre + to_light * span)
	key_light.directional_shadow_max_distance = WorldIsoCamera.CAMERA_DISTANCE + span * 1.2
	key_light.directional_shadow_split_1 = 0.85


func _build_practicals() -> void:
	var list := _builder.practicals.duplicate()
	list.sort_custom(func(a: WorldBuilder.Practical, b: WorldBuilder.Practical) -> bool: return a.energy > b.energy)
	for i: int in range(mini(list.size(), WorldBuilder.MAX_PRACTICALS)):
		var p: WorldBuilder.Practical = list[i]
		var l := OmniLight3D.new()
		l.name = "Practical%d" % i
		l.light_color = p.color
		l.light_energy = p.energy * _pal.practical_energy
		l.omni_range = p.light_range
		l.omni_attenuation = 1.6
		l.shadow_enabled = false
		l.position = p.pos
		_env_root.add_child(l)
		_practicals.append(l)


func _apply_quality() -> void:
	var high := quality == QUALITY_HIGH
	if key_light != null:
		key_light.shadow_enabled = high
	if world_env != null:
		world_env.environment.glow_enabled = high
	if post != null:
		# The web renderer reads the screen texture back black here, which blanks the view (WebCompat).
		post.set_enabled(high and not WebCompat.is_web())
	for p: OmniLight3D in _practicals:
		if is_instance_valid(p):
			p.visible = high
	if is_inside_tree():
		get_viewport().msaa_3d = Viewport.MSAA_4X if high else Viewport.MSAA_DISABLED


func _frame_camera(frame: RenderFrame, dt: float) -> void:
	_sync_viewport()
	var f := _framing
	f.mode = frame.mode if frame != null else ViewMode.IDLE
	f.dt = dt
	f.time = _time
	f.beat = frame.music.beat if frame != null and frame.music != null else 0.0
	if frame != null and frame.snap != null and f.beat == 0.0:
		f.beat = frame.snap.beat
	f.has_follow = false
	f.has_crowd = false
	f.cinema = cinema_frame if f.mode == ViewMode.CINEMATIC else null
	if frame != null and frame.snap != null:
		_find_follow(frame, f)
		_find_crowd(frame, f)
	iso.update(f)
	iso.apply_to(camera)
	_fit_backdrop()


## CINEMATIC with a plan: advance the director on the playback beat and hand the frame to the camera
## (and, through RenderFrame.cinema, to the fx layer). A frame the game filled itself wins.
func _direct_cinema(frame: RenderFrame) -> void:
	cinema_frame = null
	if frame == null or frame.mode != ViewMode.CINEMATIC:
		return
	if frame.cinema == null and _cine.plan != null:
		var beat := frame.snap.beat if frame.snap != null else (frame.music.beat if frame.music != null else 0.0)
		if frame.prev != null and frame.snap != null:
			beat = lerpf(frame.prev.beat, frame.snap.beat, clampf(frame.alpha, 0.0, 1.0))
		frame.cinema = _cine.advance(beat, frame.snap)
	cinema_frame = frame.cinema
	if cinema_frame != null and cinema_frame.ripple > 0.0 and post != null:
		# Time ripple (rescue / desync / fooled-boss shots): a soft chromatic shimmer in the grade.
		var k := cinema_frame.ripple * (0.25 if reduce_flashing else 0.6)
		post.controls.chromatic = maxf(post.controls.chromatic, k)


func _sync_split() -> void:
	if _split == null:
		return
	if cinema_frame == null or cinema_frame.panes.is_empty() or not is_inside_tree():
		if _split.visible:
			_split.clear()
		return
	var pose := CinemaCameraBridge.pose(cinema_frame, iso.aspect(), iso.fit_size())
	_split.sync(cinema_frame, pose, iso, get_viewport().world_3d, get_viewport().msaa_3d)


## Cover the whole view with the plate, keeping the image's aspect (cropped, never stretched).
func _fit_backdrop() -> void:
	if backdrop == null or not backdrop.visible:
		return
	var tex := (backdrop.material_override as StandardMaterial3D).albedo_texture
	var vp := Vector2(1600, 900)
	if is_inside_tree():
		vp = get_viewport().get_visible_rect().size
	var h := camera.size * 1.04
	var w := h * vp.x / maxf(1.0, vp.y)
	var aspect := float(tex.get_width()) / maxf(1.0, float(tex.get_height()))
	if w / h > aspect:
		h = w / aspect
	else:
		w = h * aspect
	(backdrop.mesh as QuadMesh).size = Vector2(w, h)


## Interpolated position of the self under live control (or the active cassette's self).
func _find_follow(frame: RenderFrame, f: WorldIsoCamera.Framing) -> void:
	var a: ActorSnap = null
	for x: ActorSnap in frame.snap.actors:
		if x.live:
			a = x
			break
	if a == null and frame.active >= 0:
		a = frame.snap.actor(frame.active)
	if a == null:
		return
	var p := Vector2(a.x, a.y)
	if frame.prev != null:
		var pa := frame.prev.actor(a.tape)
		if pa != null:
			p = Vector2(pa.x, pa.y).lerp(Vector2(a.x, a.y), frame.alpha)
	f.follow = p
	f.has_follow = true


## Centre of the selves still alive (ghosts do not pull the camera).
func _find_crowd(frame: RenderFrame, f: WorldIsoCamera.Framing) -> void:
	var n := 0
	var s := Vector2.ZERO
	for a: ActorSnap in frame.snap.actors:
		if a.life != OD.LifeState.ALIVE:
			continue
		s += Vector2(a.x, a.y)
		n += 1
	if n > 0:
		f.crowd = s / float(n)
		f.has_crowd = true
