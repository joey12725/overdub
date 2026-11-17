extends SceneTree
## Screenshot harness for the actor layer (windowed; needs a GPU):
##   bash tools/gd shot res://tools/shot_actors.gd -- [out_dir] [page ...]
## Builds the real actor layer (Facades.instance_actor_layer) over a plain test floor with fake
## snapshots, steps it for a few dozen frames so cross-fades, trails and timers settle, and saves one
## PNG per page and palette into out_dir (default: %TEMP%/overdub_actor_shots, outside the repo):
##   anims        Moxie in every animation state (scrubbed mid-way), death mid-transition
##   states       the four cassette variants, the live marker, recording ghost, playback ghost,
##                desynced projection + tether + spark, dodge i-frames, stopped, x-ray behind a wall
##   enemies      every enemy with its telegraph filling, target lines, and the boss on memory
##   enemies2     other enemy states: stagger, attack, shield down, asleep, boss phase 3, death
##   projectiles  every projectile archetype in flight, coloured by owner
##   weapons      every melee weapon mid-swing (per-weapon clips) and every ranged weapon in the
##                shot pose, each group on its own loadout; plus a helmet / outfit variant
##   portrait     two Moxies large (base loadout; bare-headed), for model / face / gear checks
##   closeup      the state treatments side by side at a larger size (live, recording ghost,
##                playback ghost, desynced + spark, dodge i-frames, stopped)
##   cassettes    the four cassette selves side by side, large (colour set, ring shape, letter)
##   headgear     every wardrobe headgear on the shipping head, plus bare-headed
##   looks        the wardrobe's showcase mixes (top / pants / shoes zone tints + headgear)
##   feel         combat feel driven by sim events: light hit, heavy hit on the inverted contact
##                frame, crush, clang, near miss, and the same heavy hit under "reduce flashing"
##   speeds       one blade swing at 0.5x / 1x / 2x / 4x tape speed (smear treatment)
##   clips1..5    contact sheet: every clip of the animation library on the shipping skeleton at
##                five fractions, with the clip's weapon in hand
## Pages run once in the warm (upper) and once in the dark (lower) palette; add `warm` or `dark` to
## run only one.

const FRAMES: int = 44
const PAGES: Array[String] = ["anims", "states", "enemies", "enemies2", "projectiles", "weapons", "portrait", "closeup",
	"cassettes", "headgear", "looks", "feel", "speeds", "clips1", "clips2", "clips3", "clips4", "clips5"]
const CLIP_FRACS: Array[float] = [0.0, 0.25, 0.42, 0.6, 0.9]
const CLIPS_PER_PAGE: int = 6

var _out: String = ""
var _pages: Array[String] = []
var _queue: Array = []
var _scene: Node3D = null
var _camera: Camera3D = null
var _layers: Array[ActorLayerBase] = []
var _ctxs: Array[RenderCtx] = []
var _frame: int = 0
var _page: String = ""
var _dark: bool = false
var _cfg: Dictionary = {}
var _loadout: ResolvedLoadout = null
var _settle: int = 0
var _prev_snaps: Array[FrameSnapshot] = []
var _group_loadouts: Array[ResolvedLoadout] = []
var _only: String = ""
var _mats: ActorMaterials = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = OS.get_environment("TEMP").path_join("overdub_actor_shots") if OS.get_environment("TEMP") != "" else "user://shots"
	for a: String in args:
		if PAGES.has(a):
			_pages.append(a)
		elif a == "warm" or a == "dark":
			_only = a
		elif not a.begins_with("-"):
			_out = a
	if _pages.is_empty():
		_pages = PAGES.duplicate()
	DirAccess.make_dir_recursive_absolute(_out)
	for p: String in _pages:
		if _only != "dark":
			_queue.append([p, false])
		if _only != "warm":
			_queue.append([p, true])
	_loadout = _make_loadout()
	print("[shot_actors] writing to ", _out)


func _process(_delta: float) -> bool:
	if _scene == null:
		if _queue.is_empty():
			quit()
			return true
		var job: Array = _queue.pop_front()
		_build(job[0], job[1])
		return false
	if _frame < FRAMES:
		_step()
		_frame += 1
		return false
	_settle += 1
	if _settle < 3:
		return false
	var img := root.get_texture().get_image()
	var path := _out.path_join("%s_%s.png" % [_page, "dark" if _dark else "warm"])
	img.save_png(path)
	print("[shot_actors] saved ", path)
	_teardown()
	return false


# ───────────────────────────── loadout & palettes ─────────────────────────────

## The base loadout, with `overrides` (slot -> item id) swapped in.
func _make_loadout(overrides: Dictionary = {}) -> ResolvedLoadout:
	var errors: Array[String] = []
	var cat := ContentData.load_gear(errors)
	var r := ResolvedLoadout.new()
	if cat == null:
		return r
	r.loadout = cat.base_loadout.copy()
	for slot: StringName in overrides:
		r.loadout.set_slot(slot, overrides[slot])
	for slot: StringName in GearSlot.ALL:
		var item := cat.get_item(r.loadout.get_slot(slot))
		if item == null:
			continue
		if item.look != null:
			r.looks[slot] = item.look
		if slot == GearSlot.MELEE and item.melee != null:
			r.melee = item.melee
		if slot == GearSlot.RANGED and item.ranged != null:
			r.ranged = item.ranged
	return r


func _palette(dark: bool) -> ThemePalette:
	var p := ThemePalette.new()
	if dark:
		p.theme = LevelTheme.LOWER
		p.background = Color("#0d0b14")
		p.floor_color = Color("#2a2838")
		p.floor_alt = Color("#232030")
		p.wall = Color("#35324a")
		p.ink = Color("#07060c")
		p.key_light = Color("#c9b8ff")
		p.key_intensity = 1.6
		p.ambient = Color("#4a3f7a")
		p.ambient_intensity = 0.8
	return p


# ───────────────────────────── scene ─────────────────────────────

func _build(page: String, dark: bool) -> void:
	_page = page
	_dark = dark
	_frame = 0
	_settle = 0
	_cfg = _scenario(page)
	var pal := _palette(dark)
	_scene = Node3D.new()
	_scene.name = "ShotScene"
	root.add_child(_scene)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = pal.background
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = pal.ambient
	env.ambient_light_energy = 0.6
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.glow_intensity = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_scene.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = pal.key_light
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.rotation = Vector3(deg_to_rad(-58.0), deg_to_rad(-35.0), 0)
	_scene.add_child(sun)
	var bounds: Rect2 = _cfg["bounds"]
	# Floor checker so positions read.
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = pal.floor_color
	var alt_mat := StandardMaterial3D.new()
	alt_mat.albedo_color = pal.floor_alt
	var tile := BoxMesh.new()
	tile.size = Vector3(1, 0.1, 1)
	for ix: int in range(int(floor(bounds.position.x)) - 1, int(ceil(bounds.end.x)) + 1):
		for iy: int in range(int(floor(bounds.position.y)) - 1, int(ceil(bounds.end.y)) + 1):
			var t := MeshInstance3D.new()
			t.mesh = tile
			t.material_override = floor_mat if (ix + iy) % 2 == 0 else alt_mat
			t.position = Vector3(ix + 0.5, -0.05, iy + 0.5)
			_scene.add_child(t)
	# Walls (x-ray check).
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = pal.wall
	for w: Rect2 in _cfg.get("walls", []):
		var wm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w.size.x, 1.6, w.size.y)
		wm.mesh = bm
		wm.material_override = wall_mat
		wm.position = Vector3(w.position.x + w.size.x * 0.5, 0.8, w.position.y + w.size.y * 0.5)
		_scene.add_child(wm)
	# Orthographic isometric camera (yaw 45, pitch 35) framing the scenario.
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var center := bounds.get_center()
	var basis := Basis.from_euler(Vector3(deg_to_rad(-35.0), deg_to_rad(45.0), 0.0), EULER_ORDER_YXZ)
	var target := Vector3(center.x, 0.6, center.y)
	_camera.transform = Transform3D(basis, target + basis.z * 30.0)
	_camera.size = maxf(bounds.size.x, bounds.size.y) * 0.62 + 1.2
	if _cfg.has("cam_size"):
		_camera.size = _cfg["cam_size"]
	_camera.far = 200.0
	_scene.add_child(_camera)
	_camera.make_current()
	# One actor layer per group of four selves.
	var groups: Array = _cfg["groups"]
	_layers.clear()
	_ctxs.clear()
	_prev_snaps.clear()
	_group_loadouts.clear()
	for g: int in groups.size():
		var layer := Facades.instance_actor_layer()
		_scene.add_child(layer)
		var ctx := RenderCtx.new()
		ctx.camera = _camera
		ctx.palette = pal
		var ov: Dictionary = (groups[g] as Dictionary).get("loadout", {})
		ctx.loadout = _loadout if ov.is_empty() else _make_loadout(ov)
		_group_loadouts.append(ctx.loadout)
		ctx.root = _scene
		var lvl := LevelDef.new()
		for e: Dictionary in (groups[g] as Dictionary).get("enemies", []):
			var ed := EnemyDef.new()
			ed.kind = EntityKind.ENEMY
			ed.id = e["id"]
			ed.type = e["type"]
			ed.facing = e.get("facing", 0.0)
			lvl.entities.append(ed)
		ctx.level = lvl
		ActorOptions.reduce_flashing = (groups[g] as Dictionary).get("reduce_flashing", false)
		layer.load_level(ctx)
		for d: Dictionary in (groups[g] as Dictionary).get("selves", []):
			if d.has("speed"):
				(layer.get("selves") as Array)[int(d["tape"])].set("speed_override", float(d["speed"]))
		_layers.append(layer)
		_ctxs.append(ctx)
		_prev_snaps.append(null)
	ActorOptions.reduce_flashing = false
	_build_rigs(pal)
	for lbl: Array in _cfg.get("labels", []):
		var l := Label3D.new()
		l.text = lbl[2]
		l.font_size = 40
		l.pixel_size = 0.004
		l.outline_size = 10
		l.modulate = Color(1, 1, 1) if dark else Color(0.1, 0.08, 0.08)
		l.outline_modulate = Color(0, 0, 0, 0.8) if dark else Color(1, 1, 1, 0.7)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.position = Vector3(lbl[0], 0.02, lbl[1] + 0.75)
		_scene.add_child(l)


## Contact-sheet rigs: the shipping model posed directly from the clip library (no anim state), in
## the actor materials with the self outline, with the clip's weapon in the right hand.
func _build_rigs(pal: ThemePalette) -> void:
	var rigs: Array = _cfg.get("rigs", [])
	if rigs.is_empty():
		return
	if _mats == null:
		_mats = ActorMaterials.new()
	_mats.set_palette(pal, null)
	var colors := ActorOptions.tape_colors()
	for d: Dictionary in rigs:
		var rig := ActorRig.new()
		rig.setup(SelfView.MOXIE_PATH, MoxieStandin.instance)
		_scene.add_child(rig)
		MoxieModel.bind_clips(rig.sampler)
		var sk := rig.skeleton
		var rh := MoxieModel.find_bone(sk, MoxieModel.RIGHT_HAND)
		var item: String = d.get("weapon", "")
		if not item.is_empty() and rh >= 0:
			var style := FeelRig.style_for(item)
			var worn := FeelRig.is_worn(style)
			var w: Array = ActorGear.weapon(item, MeleeWeaponDef.new(), null)
			var at := MoxieModel.attach(sk, rh, "At_RightHand")
			at.add_child(w[0])
			(w[0] as Node3D).transform = FeelRig.weapon_attach_transform(sk, rh, true, worn)
			if worn:
				SelfView._keep_gauntlet(w[0], "Gauntlet_R")
				var lh := MoxieModel.find_bone(sk, MoxieModel.LEFT_HAND)
				var w2: Array = ActorGear.weapon(item, MeleeWeaponDef.new(), null)
				var atl := MoxieModel.attach(sk, lh, "At_LeftHand")
				atl.add_child(w2[0])
				var tl := FeelRig.weapon_attach_transform(sk, lh, false, true)
				tl.basis = tl.basis * Basis.from_scale(Vector3(-1, 1, 1))
				(w2[0] as Node3D).transform = tl
				SelfView._keep_gauntlet(w2[0], "Gauntlet_L")
				rig.adopt(w2[0])
			rig.adopt(w[0])
		var no_tints: Dictionary[StringName, Color] = {}
		var none: Array[StringName] = []
		rig.apply_materials(_mats, no_tints, none, none, true, null)
		var c: Color = colors[int(d.get("tape", 0))]
		rig.set_param(&"accent", c)
		rig.set_param(&"outline_color", Color(c, 1.0))
		rig.set_param(&"outline_width", SelfView.HULL_WIDTH * rig.top / ActorGear.STANDIN_TOP)
		rig.set_param(&"xray_color", Color(c, 0.0))
		var pose := ActorClipSampler.Pose.new(rig.sampler.bone_count)
		if not rig.sampler.sample(d["clip"], d["frac"], pose):
			print("[shot_actors] MISSING CLIP ", d["clip"])
		rig.sampler.apply(pose)
		var pos: Vector2 = d["pos"]
		rig.transform = Transform3D(Basis(Vector3.UP, RenderCtx.heading_to_yaw(d.get("facing", PI * 0.25))), Vector3(pos.x, 0, pos.y))


func _teardown() -> void:
	for l: ActorLayerBase in _layers:
		l.dispose()
	_layers.clear()
	_ctxs.clear()
	_scene.queue_free()
	_scene = null


# ───────────────────────────── stepping ─────────────────────────────

func _step() -> void:
	var groups: Array = _cfg["groups"]
	var f := _frame
	for g: int in groups.size():
		var snap := _snapshot(groups[g], f, _group_loadouts[g])
		var rf := RenderFrame.new()
		rf.snap = snap
		rf.prev = _prev_snaps[g] if _prev_snaps[g] != null else snap
		rf.alpha = 1.0
		rf.dt = 1.0 / 60.0
		rf.mode = ViewMode.RECORD
		rf.active = (groups[g] as Dictionary).get("active", -1)
		rf.music.beat_pulse = maxf(0.0, 1.0 - fmod(float(f) / 30.0, 1.0) * 2.0)
		for ev: Dictionary in (groups[g] as Dictionary).get("events", []):
			if int(ev.get("frame", 0)) == f:
				var at: Vector2 = ev.get("at", Vector2.ZERO)
				var se := SimEvent.make(0, ev["type"], at.x, at.y).with_id(ev.get("id", "")).with_detail(ev.get("detail", ""))
				if ev.has("tape"):
					se = se.with_tape(int(ev["tape"]))
				if ev.has("dir"):
					se = se.with_dir(float(ev["dir"]))
				if ev.has("power"):
					se = se.with_power(float(ev["power"]))
				rf.events.append(se)
		ActorOptions.reduce_flashing = (groups[g] as Dictionary).get("reduce_flashing", false)
		_layers[g].update(rf, _ctxs[g])
		_prev_snaps[g] = snap
	ActorOptions.reduce_flashing = false


## Snapshot of one group at frame f. Each self spec: timed anims advance their tick so that at the
## capture frame they sit at progress `p`; movement specs move along `v`.
func _snapshot(group: Dictionary, f: int, lo: ResolvedLoadout) -> FrameSnapshot:
	var s := FrameSnapshot.new()
	var cap := float(FRAMES - 1)
	for d: Dictionary in group.get("selves", []):
		var a := ActorSnap.new()
		a.tape = d["tape"]
		var anim: StringName = d.get("anim", AnimState.IDLE)
		a.anim = anim
		var dur := MoxieAnim.duration_ticks(anim, lo.melee, lo.ranged)
		var p: float = d.get("p", 0.5)
		var rate := (p * float(dur) / cap) if dur > 0 else 1.0
		var reverse: bool = d.get("reverse", false)
		var t0 := 200.0
		var tick := t0 + float(f) * rate * (-1.0 if reverse else 1.0)
		a.phase = TapePhase.make(tick, -1 if reverse else 1, 0, false)
		var v: Vector2 = d.get("v", Vector2.ZERO)
		var pos: Vector2 = d["pos"]
		a.x = pos.x + v.x * float(f) / 60.0
		a.y = pos.y + v.y * float(f) / 60.0
		a.vx = v.x
		a.vy = v.y
		a.facing = d.get("facing", PI * 0.5)
		a.live = d.get("live", false)
		a.iframes = d.get("iframes", false)
		a.life = d.get("life", OD.LifeState.ALIVE)
		if d.has("die_at") and f >= int(d["die_at"]):
			a.life = OD.LifeState.GHOST
		elif d.has("die_at"):
			a.life = OD.LifeState.ALIVE
		a.synced = d.get("synced", true)
		if d.has("resync_at"):
			a.synced = f >= int(d["resync_at"])
		if d.has("spark") and not a.synced:
			var sp: Vector2 = d["spark"]
			var sv: Vector2 = d.get("spark_v", Vector2.ZERO)
			a.has_spark = true
			a.spark = sp + sv * float(f) / 60.0
		if anim == AnimState.STOPPED:
			a.phase = TapePhase.make(t0, 0, 0, true)
		s.actors.append(a)
	for d: Dictionary in group.get("enemies", []):
		var e := EnemySnap.new()
		e.id = d["id"]
		e.type = d["type"]
		var pos: Vector2 = d["pos"]
		var v: Vector2 = d.get("v", Vector2.ZERO)
		e.x = pos.x + v.x * float(f) / 60.0
		e.y = pos.y + v.y * float(f) / 60.0
		e.facing = d.get("facing", PI * 0.5)
		e.max_hp = d.get("max_hp", 1)
		e.hp = d.get("hp", e.max_hp)
		e.state = d.get("state", EnemyStateName.IDLE)
		var st: float = d.get("t", 0.5)
		e.state_t = clampf(st * float(f) / cap, 0.0, 1.0) if d.get("scrub", true) else st
		e.target = d.get("target", -1)
		if d.has("shield"):
			e.has_shield = true
			e.shield = d["shield"]
		if e.type == EnemyType.BOSS:
			e.boss_phase = d.get("phase", 1)
			e.boss_recall = d.get("recall", false)
			if e.boss_recall:
				e.boss_recall_tape = d.get("recall_tape", 0)
				e.has_boss_recall_at = true
				e.boss_recall_at = d.get("recall_at", Vector2.ZERO)
		if d.has("die_at") and f >= int(d["die_at"]):
			e.alive = false
			e.state = EnemyStateName.DEAD
		s.enemies.append(e)
	var pid := 1
	for d: Dictionary in group.get("shots", []):
		var p := ProjectileSnap.new()
		p.id = pid
		pid += 1
		p.archetype = d["kind"]
		p.owner_tape = d.get("tape", -1)
		if p.owner_tape < 0:
			p.owner_enemy = "e"
		var pos: Vector2 = d["pos"]
		var dirv: float = d.get("dir", 0.0)
		var spd: float = d.get("speed", 4.0)
		var tt := float(f) / 60.0
		p.x = pos.x + cos(dirv) * spd * tt
		p.y = pos.y + sin(dirv) * spd * tt
		p.dir = dirv
		if p.archetype == RangedArchetype.ARC:
			p.z = maxf(0.0, 3.2 * tt - 4.9 * tt * tt * 0.6) + 0.2
		p.target_id = d.get("target_id", "")
		s.projectiles.append(p)
	return s


# ───────────────────────────── scenarios ─────────────────────────────

func _scenario(page: String) -> Dictionary:
	match page:
		"anims":
			return _anims()
		"states":
			return _states()
		"enemies":
			return _enemies(false)
		"enemies2":
			return _enemies(true)
		"closeup":
			return _closeup()
		"weapons":
			return _weapons()
		"portrait":
			return _portrait()
		"cassettes":
			return _cassettes()
		"headgear":
			return _headgear()
		"looks":
			return _looks()
		"feel":
			return _feel()
		"speeds":
			return _speeds()
		"clips1", "clips2", "clips3", "clips4", "clips5":
			return _clips(int(page.substr(5)) - 1)
		_:
			return _projectiles()


func _grid(i: int, cols: int, dx: float, dy: float) -> Vector2:
	return Vector2(1.5 + float(i % cols) * dx, 1.5 + float(i / cols) * dy)


func _anims() -> Dictionary:
	var states: Array = [
		[AnimState.IDLE, 0.5, "idle"], [AnimState.RUN, 0.5, "run"], [AnimState.LIGHT_WINDUP, 0.8, "light windup"],
		[AnimState.LIGHT_ACTIVE, 0.6, "light hit"], [AnimState.LIGHT_RECOVER, 0.4, "light recover"], [AnimState.HEAVY_WINDUP, 0.9, "heavy windup"],
		[AnimState.HEAVY_ACTIVE, 0.6, "heavy hit"], [AnimState.HEAVY_RECOVER, 0.3, "heavy recover"], [AnimState.DODGE, 0.5, "dodge"],
		[AnimState.RANGED, 0.3, "ranged"], [AnimState.INTERACT, 0.5, "interact"], [AnimState.STOPPED, 0.0, "stopped"],
		[AnimState.LIGHT_ACTIVE, 0.6, "light hit (reverse pass)"], [AnimState.IDLE, 0.5, "death"],
	]
	var groups: Array = []
	var labels: Array = []
	for i: int in states.size():
		var gi := i / 4
		while groups.size() <= gi:
			groups.append({"selves": []})
		var pos := _grid(i, 5, 2.6, 2.9)
		var s: Dictionary = {"tape": i % 4, "pos": pos, "anim": states[i][0], "p": states[i][1], "facing": PI * 0.25}
		if states[i][0] == AnimState.RUN:
			s["v"] = Vector2(3.2, 3.2)
			s["pos"] = pos - Vector2(1.2, 1.2)
		if states[i][0] == AnimState.DODGE:
			s["iframes"] = true
			s["v"] = Vector2(2.5, 2.5)
			s["pos"] = pos - Vector2(0.9, 0.9)
		if states[i][2] == "light hit (reverse pass)":
			s["reverse"] = true
		if states[i][2] == "death":
			s["die_at"] = FRAMES - 16
		(groups[gi]["selves"] as Array).append(s)
		labels.append([pos.x, pos.y, states[i][2]])
	return {"groups": groups, "labels": labels, "bounds": Rect2(0, 0, 13.5, 9.5)}


func _states() -> Dictionary:
	var row0: Array = []
	var labels: Array = []
	# Four cassette variants, tape A live.
	for i: int in 4:
		var pos := Vector2(1.5 + i * 2.4, 1.5)
		row0.append({"tape": i, "pos": pos, "anim": AnimState.IDLE, "live": i == 0, "facing": PI * 0.3})
		labels.append([pos.x, pos.y, "%s alive%s" % [OD.tape_letter(i), " (LIVE)" if i == 0 else ""]])
	var row1: Array = [
		{"tape": 0, "pos": Vector2(1.5, 4.5), "anim": AnimState.RUN, "life": OD.LifeState.REC_GHOST, "live": true, "v": Vector2(0.6, 0.0), "facing": 0.0},
		{"tape": 1, "pos": Vector2(3.9, 4.5), "anim": AnimState.RUN, "life": OD.LifeState.GHOST, "v": Vector2(0.6, 0.0), "facing": 0.0},
		{"tape": 2, "pos": Vector2(6.3, 4.5), "anim": AnimState.RUN, "synced": false, "spark": Vector2(6.3, 6.6), "spark_v": Vector2(0.8, -0.6), "v": Vector2(0.3, 0.0), "facing": 0.0},
		{"tape": 3, "pos": Vector2(8.7, 4.5), "anim": AnimState.DODGE, "iframes": true, "v": Vector2(2.0, 0.0), "p": 0.55, "facing": 0.0},
	]
	labels.append_array([[1.5, 4.5, "recording ghost"], [3.9, 4.5, "playback ghost"], [6.3, 4.5, "desynced + spark"], [8.7, 4.5, "dodge i-frames"]])
	var row2: Array = [
		{"tape": 0, "pos": Vector2(1.5, 7.8), "anim": AnimState.STOPPED},
		{"tape": 1, "pos": Vector2(3.9, 7.8), "anim": AnimState.IDLE, "synced": false, "spark": Vector2(3.0, 9.2), "spark_v": Vector2(0.9, -1.4), "resync_at": FRAMES - 10},
		{"tape": 2, "pos": Vector2(6.3, 8.6), "anim": AnimState.RUN, "v": Vector2(0.5, 0.0), "facing": 0.0},
		{"tape": 3, "pos": Vector2(8.7, 7.8), "anim": AnimState.RUN, "life": OD.LifeState.GHOST, "synced": false, "spark": Vector2(9.6, 9.4), "spark_v": Vector2(-0.6, -0.2), "v": Vector2(0.5, 0)},
	]
	labels.append_array([[1.5, 7.8, "stopped"], [3.9, 7.8, "resync merge"], [6.3, 8.6, "x-ray (behind wall)"], [8.7, 7.8, "ghost + desync"]])
	return {
		"groups": [{"selves": row0, "active": 0}, {"selves": row1}, {"selves": row2}],
		"labels": labels,
		# A pillar straight between the "x-ray" self and the camera (camera sits toward +x, +z).
		"walls": [Rect2(6.75, 9.05, 1.0, 1.0)],
		"bounds": Rect2(0, 0, 10.5, 10.0),
	}


func _enemies(alt: bool) -> Dictionary:
	var types: Array[StringName] = [EnemyType.GRUNT, EnemyType.STALKER, EnemyType.TURRET, EnemyType.SHIELDER, EnemyType.BRUTE, EnemyType.DRONE]
	var enemies: Array = []
	var selves: Array = []
	var labels: Array = []
	var events: Array = []
	for i: int in types.size():
		var pos := Vector2(2.0 + float(i % 3) * 4.6, 2.0 + float(i / 3) * 4.2)
		var e: Dictionary = {"id": "%s_%d" % [types[i], i], "type": types[i], "pos": pos, "facing": PI * 0.5, "target": i % 4, "state": EnemyStateName.TELEGRAPH, "t": 0.7}
		if types[i] == EnemyType.SHIELDER:
			e["shield"] = true
			e["max_hp"] = 2
		if types[i] == EnemyType.BRUTE:
			e["max_hp"] = 3
			e["hp"] = 2
		if types[i] == EnemyType.DRONE:
			e["max_hp"] = 2
		if alt:
			var alts: Array = [
				[EnemyStateName.STAGGER, "stagger"], [EnemyStateName.MOVE, "move"], [EnemyStateName.ATTACK, "attack"],
				[EnemyStateName.IDLE, "shield down"], [EnemyStateName.ATTACK, "attack"], [EnemyStateName.ASLEEP, "asleep"],
			]
			e["state"] = alts[i][0]
			e["t"] = 0.35
			if types[i] == EnemyType.SHIELDER:
				e["shield"] = false
			if types[i] == EnemyType.STALKER:
				e["v"] = Vector2(0.0, 1.2)
			labels.append([pos.x, pos.y - 0.2, "%s %s" % [types[i], alts[i][1]]])
		else:
			labels.append([pos.x, pos.y - 0.2, "%s telegraph" % types[i]])
		enemies.append(e)
		if i < 4:
			selves.append({"tape": i % 4, "pos": pos + Vector2(0.0, 1.9 if types[i] != EnemyType.TURRET else 3.2), "anim": AnimState.IDLE, "facing": -PI * 0.5})
	var bpos := Vector2(6.6, 11.2)
	var boss: Dictionary = {"id": "boss", "type": EnemyType.BOSS, "pos": bpos, "facing": PI * 0.5, "max_hp": 40, "hp": 30, "state": EnemyStateName.TELEGRAPH, "t": 0.6, "target": 1}
	if alt:
		boss["phase"] = 3
		boss["hp"] = 10
		boss["state"] = EnemyStateName.TELEGRAPH
		events.append({"frame": 0, "type": SimEventType.ENEMY_TELEGRAPH, "id": "boss", "detail": "sweep"})
		labels.append([bpos.x, bpos.y + 1.6, "boss phase 3 (sweep)"])
		enemies.append({"id": "grunt_dead", "type": EnemyType.GRUNT, "pos": Vector2(11.6, 11.0), "state": EnemyStateName.IDLE, "die_at": FRAMES - 12})
		labels.append([11.6, 11.0, "grunt death"])
	else:
		boss["recall"] = true
		boss["recall_tape"] = 2
		boss["recall_at"] = bpos + Vector2(-3.2, -1.6)
		labels.append([bpos.x, bpos.y + 1.6, "boss acting on memory (tape C)"])
	enemies.append(boss)
	var groups: Array = [{"selves": selves, "enemies": enemies, "events": events}]
	return {"groups": groups, "labels": labels, "bounds": Rect2(0, 0, 13.0, 14.0)}


func _projectiles() -> Dictionary:
	var kinds: Array = [
		[RangedArchetype.MISSILE, 0, 1.2, "missile (lock)"], [RangedArchetype.PIERCE, 1, 9.0, "pierce"], [RangedArchetype.PHASE, 2, 3.0, "phase"],
		[RangedArchetype.ARC, 3, 3.0, "arc"], [RangedArchetype.BURST, 0, 6.0, "burst"], [RangedArchetype.BOLT, -1, 5.0, "enemy bolt"],
		[RangedArchetype.SHOCK, -1, 3.0, "enemy shock"],
	]
	var shots: Array = []
	var labels: Array = []
	for i: int in kinds.size():
		var pos := Vector2(1.0, 1.2 + float(i) * 1.5)
		var d: Dictionary = {"kind": kinds[i][0], "tape": kinds[i][1], "speed": kinds[i][2], "pos": pos, "dir": 0.0}
		# Label where the shot is at the capture frame.
		var travel: float = float(kinds[i][2]) * float(FRAMES - 1) / 60.0
		if kinds[i][0] == RangedArchetype.MISSILE:
			d["target_id"] = "lock_target"
		if kinds[i][0] == RangedArchetype.BURST:
			for k: int in 3:
				var dk := d.duplicate()
				dk["dir"] = (float(k) - 1.0) * 0.18
				shots.append(dk)
			labels.append([pos.x + travel, pos.y - 0.75, kinds[i][3]])
			continue
		shots.append(d)
		labels.append([pos.x + travel, pos.y - 0.75, kinds[i][3]])
	var enemies: Array = [{"id": "lock_target", "type": EnemyType.GRUNT, "pos": Vector2(6.5, 1.2), "facing": PI, "state": EnemyStateName.IDLE}]
	var selves: Array = [{"tape": 0, "pos": Vector2(0.2, 1.2), "anim": AnimState.RANGED, "p": 0.6, "facing": 0.0}]
	return {"groups": [{"selves": selves, "enemies": enemies, "shots": shots}], "labels": labels, "bounds": Rect2(0, 0, 9.0, 11.5)}


func _closeup() -> Dictionary:
	var specs: Array = [
		[{"tape": 0, "anim": AnimState.IDLE, "live": true}, "A live"],
		[{"tape": 0, "anim": AnimState.IDLE, "life": OD.LifeState.REC_GHOST}, "recording ghost"],
		[{"tape": 1, "anim": AnimState.IDLE, "life": OD.LifeState.GHOST}, "playback ghost"],
		[{"tape": 2, "anim": AnimState.IDLE, "synced": false, "spark_off": Vector2(-0.9, 1.1), "spark_v": Vector2(0.3, -0.2)}, "desynced"],
		[{"tape": 3, "anim": AnimState.DODGE, "iframes": true, "p": 0.5, "v": Vector2(1.4, 0.0)}, "dodge i-frames"],
		[{"tape": 1, "anim": AnimState.STOPPED}, "stopped"],
	]
	# One view per tape per layer: tape A appears twice and tape B twice, so three layers.
	var group_of: Array[int] = [0, 1, 1, 1, 1, 2]
	var groups: Array = [{"selves": [], "active": 0}, {"selves": []}, {"selves": []}]
	var labels: Array = []
	for i: int in specs.size():
		var d: Dictionary = (specs[i][0] as Dictionary).duplicate()
		var pos := Vector2(0.9 + float(i) * 1.45, 1.2)
		d["pos"] = pos - (d.get("v", Vector2.ZERO) as Vector2) * 0.5
		d["facing"] = PI * 0.3
		if d.has("spark_off"):
			d["spark"] = pos + (d["spark_off"] as Vector2)
		(groups[group_of[i]]["selves"] as Array).append(d)
		labels.append([pos.x, pos.y, specs[i][1]])
	return {"groups": groups, "labels": labels, "walls": [], "bounds": Rect2(0, 0, 9.0, 2.6)}


func _weapons() -> Dictionary:
	var melee: Array[String] = ["splice_blade", "stylus_shiv", "amp_sledge", "reel_lash", "speaker_knuckles", "vinyl_glaive"]
	var ranged: Array[String] = ["mixtape_rocket", "needle_rail", "bleed_emitter", "bass_drop", "static_spray", "mixtape_rocket"]
	var outfits: Array[Dictionary] = [
		{}, {GearSlot.HELMET: "prism_goggles", GearSlot.TOP: "patchcord_hoodie"}, {GearSlot.HELMET: "feedback_crown", GearSlot.PANTS: "parachute_pants"},
		{GearSlot.HELMET: "hush_hood", GearSlot.SHOES: "spring_soles"}, {GearSlot.HELMET: "rabbit_ears", GearSlot.TOP: "encore_tee"}, {GearSlot.HELMET: "click_visor", GearSlot.TOP: "dropout_jacket"},
	]
	var groups: Array = []
	var labels: Array = []
	for i: int in melee.size():
		var ov: Dictionary = outfits[i].duplicate()
		ov[GearSlot.MELEE] = melee[i]
		ov[GearSlot.RANGED] = ranged[i]
		var x := 1.4 + float(i) * 2.1
		var heavy := i % 2 == 1
		groups.append({"loadout": ov, "selves": [
			{"tape": i % 4, "pos": Vector2(x, 1.5), "anim": AnimState.HEAVY_ACTIVE if heavy else AnimState.LIGHT_ACTIVE, "p": 0.45, "facing": 0.0, "speed": 1.0},
			{"tape": (i + 1) % 4, "pos": Vector2(x, 4.4), "anim": AnimState.RANGED, "p": 0.35, "facing": PI * 0.25},
		]})
		labels.append([x, 1.5, "%s %s" % [melee[i], "heavy" if heavy else "light"]])
		labels.append([x, 4.4, ranged[i]])
	return {"groups": groups, "labels": labels, "walls": [], "bounds": Rect2(0, 0, 13.0, 5.6)}


func _portrait() -> Dictionary:
	return {
		"groups": [
			{"selves": [{"tape": 0, "pos": Vector2(0.9, 1.0), "anim": AnimState.IDLE, "facing": PI * 0.25, "live": true}]},
			{"loadout": {GearSlot.HELMET: ""}, "selves": [{"tape": 2, "pos": Vector2(2.3, 1.0), "anim": AnimState.STOPPED, "facing": PI * 0.25}]},
		],
		"labels": [], "walls": [], "bounds": Rect2(0, 0, 3.2, 1.6),
	}


func _cassettes() -> Dictionary:
	var selves: Array = []
	var labels: Array = []
	for i: int in 4:
		var pos := Vector2(0.8 + float(i) * 1.25, 0.9 + float(3 - i) * 0.35)
		selves.append({"tape": i, "pos": pos, "anim": AnimState.IDLE, "facing": PI * 0.25, "live": i == 0})
		labels.append([pos.x, pos.y, OD.tape_letter(i)])
	return {"groups": [{"selves": selves, "active": 0}], "labels": labels, "walls": [], "bounds": Rect2(0, 0, 5.2, 2.6), "cam_size": 4.2}


func _headgear() -> Dictionary:
	var ids: Array[String] = ["", "scrap_cap", "hush_hood", "feedback_crown", "click_visor", "prism_goggles", "rabbit_ears"]
	var groups: Array = []
	var labels: Array = []
	for i: int in ids.size():
		var pos := Vector2(0.7 + float(i % 4) * 1.3 + float(i / 4) * 0.65, 0.8 + float(i / 4) * 1.9)
		groups.append({"loadout": {GearSlot.HELMET: ids[i]} if ids[i] != "" else {GearSlot.HELMET: "none"}, "selves": [
			{"tape": i % 4, "pos": pos, "anim": AnimState.IDLE, "facing": PI * 0.25}]})
		labels.append([pos.x, pos.y, ids[i] if ids[i] != "" else "bare"])
	return {"groups": groups, "labels": labels, "walls": [], "bounds": Rect2(0, 0, 5.4, 3.6), "cam_size": 4.3}


func _looks() -> Dictionary:
	var mix_table: Dictionary = Wardrobe.data().get("mixes", {})
	var mix_ids: Array = mix_table.keys()
	var groups: Array = []
	var labels: Array = []
	var n := mini(6, mix_ids.size())
	for i: int in n:
		var m: Dictionary = mix_table[mix_ids[i]]
		m["id"] = mix_ids[i]
		var ov: Dictionary = {}
		var items: Variant = m.get("items", m.get("loadout", m))
		if items is Dictionary:
			for slot: StringName in [GearSlot.HELMET, GearSlot.TOP, GearSlot.PANTS, GearSlot.SHOES]:
				if (items as Dictionary).has(String(slot)):
					ov[slot] = str((items as Dictionary)[String(slot)])
		elif items is Array:
			for id: Variant in items as Array:
				var sl := Wardrobe.slot_of(str(id))
				if sl != "":
					ov[StringName(sl)] = str(id)
		var pos := Vector2(0.7 + float(i % 3) * 1.5 + float(i / 3) * 0.75, 0.8 + float(i / 3) * 1.9)
		groups.append({"loadout": ov, "selves": [{"tape": i % 4, "pos": pos, "anim": AnimState.IDLE, "facing": PI * (0.25 if i % 2 == 0 else 1.1)}]})
		labels.append([pos.x, pos.y, str(m.get("id", m.get("name", "mix %d" % i)))])
	return {"groups": groups, "labels": labels, "walls": [], "bounds": Rect2(0, 0, 5.0, 3.6), "cam_size": 5.2}


## Six exchanges, each its own layer: a self mid-swing on an enemy with the sim's events fed in on
## chosen frames before the capture (the last stepped frame is FRAMES - 1).
func _feel() -> Dictionary:
	var last := FRAMES - 1
	var specs: Array = [
		# label, melee, heavy, power, clang, frames before capture the hit lands, reduce flashing
		["light hit, +1 frame", "splice_blade", false, 1.2, false, 1, false],
		["heavy hit, contact frame (inverted)", "amp_sledge", true, 5.0, false, 0, false],
		["crush, +2 frames", "amp_sledge", true, 9.0, false, 2, false],
		["clang, +1 frame", "stylus_shiv", false, 0.6, true, 1, false],
		["heavy hit, +3 frames (hold, squash)", "vinyl_glaive", true, 5.0, false, 3, false],
		["heavy hit, reduce flashing", "amp_sledge", true, 5.0, false, 0, true],
	]
	var groups: Array = []
	var labels: Array = []
	for i: int in specs.size():
		var sp: Array = specs[i]
		var pos := Vector2(1.6 + float(i % 3) * 3.4, 1.6 + float(i / 3) * 3.6)
		var epos := pos + Vector2(1.05, 0.0)
		var eid := "grunt_%d" % i
		var heavy: bool = sp[2]
		var events: Array = [{"frame": last - int(sp[5]), "type": SimEventType.HIT, "id": eid, "tape": i % 4, "at": epos, "dir": 0.0, "power": sp[3]}]
		if sp[4]:
			events.append({"frame": last - int(sp[5]), "type": SimEventType.CLANG, "id": eid, "tape": i % 4, "at": epos, "dir": 0.0, "power": sp[3]})
		groups.append({"loadout": {GearSlot.MELEE: sp[1]}, "events": events, "reduce_flashing": sp[6],
			"selves": [{"tape": i % 4, "pos": pos, "anim": AnimState.HEAVY_ACTIVE if heavy else AnimState.LIGHT_ACTIVE, "p": 0.5, "facing": 0.0, "speed": 1.0}],
			"enemies": [{"id": eid, "type": EnemyType.GRUNT, "pos": epos, "facing": PI, "state": EnemyStateName.STAGGER, "t": 0.2, "max_hp": 3, "hp": 2}]})
		labels.append([pos.x + 0.4, pos.y + 0.9, sp[0]])
	# Near miss: an enemy attack through a dodging self's i-frames.
	var npos := Vector2(5.0, 8.6)
	groups.append({"events": [{"frame": last - 2, "type": SimEventType.ENEMY_ATTACK, "id": "grunt_nm", "at": npos + Vector2(0.5, 0.5)}],
		"selves": [{"tape": 2, "pos": npos, "anim": AnimState.DODGE, "iframes": true, "p": 0.5, "v": Vector2(1.5, -1.5), "facing": -PI * 0.25}],
		"enemies": [{"id": "grunt_nm", "type": EnemyType.GRUNT, "pos": npos + Vector2(1.1, 1.1), "facing": PI * 1.25, "state": EnemyStateName.ATTACK, "t": 0.6}]})
	labels.append([npos.x + 0.4, npos.y + 0.9, "near miss (dodge i-frames)"])
	return {"groups": groups, "labels": labels, "walls": [], "bounds": Rect2(0, 0, 11.0, 10.4)}


func _speeds() -> Dictionary:
	var groups: Array = []
	var labels: Array = []
	var speeds: Array[float] = [0.5, 1.0, 2.0, 4.0]
	for i: int in speeds.size():
		for k: int in 2:
			var pos := Vector2(1.5 + float(i) * 2.6, 1.5 + float(k) * 3.0)
			groups.append({"loadout": {GearSlot.MELEE: "splice_blade" if k == 0 else "amp_sledge"}, "selves": [
				{"tape": i, "pos": pos, "anim": AnimState.LIGHT_ACTIVE if k == 0 else AnimState.HEAVY_ACTIVE, "p": 0.55, "facing": 0.0, "speed": speeds[i]}]})
			labels.append([pos.x, pos.y, "%s %sx" % ["blade light" if k == 0 else "sledge heavy", str(speeds[i])]])
	return {"groups": groups, "labels": labels, "walls": [], "bounds": Rect2(0, 0, 11.0, 6.4)}


func _clips(page: int) -> Dictionary:
	var lib := load(FeelRig.LIBRARY_PATH) as AnimationLibrary
	var names: Array[String] = []
	if lib != null:
		for n: StringName in lib.get_animation_list():
			names.append(String(n))
	names.sort()
	var item_of: Dictionary = {}
	for id: String in FeelRig.STYLE_OF_ITEM:
		item_of[FeelRig.STYLE_OF_ITEM[id]] = id
	var rigs: Array = []
	var labels: Array = []
	var from := page * CLIPS_PER_PAGE
	for r: int in CLIPS_PER_PAGE:
		if from + r >= names.size():
			break
		var clip := names[from + r]
		var weapon := "splice_blade"
		var us := clip.find("_")
		if us >= 0 and item_of.has(clip.substr(us + 1)):
			weapon = item_of[clip.substr(us + 1)]
		# Rows run down the screen (+x +y on the floor), columns across it (+x -y).
		var row := Vector2(1.0, 7.0) + Vector2(1.85, 1.85) * float(r)
		for c: int in CLIP_FRACS.size():
			var pos := row + Vector2(1.1, -1.1) * float(c)
			rigs.append({"clip": StringName(clip), "frac": CLIP_FRACS[c], "pos": pos, "weapon": weapon, "tape": r % 4, "facing": 0.0})
		labels.append([row.x - 1.5, row.y + 0.75, clip])
	return {"groups": [], "rigs": rigs, "labels": labels, "walls": [], "bounds": Rect2(-0.5, 0.9, 16.7, 17.0), "cam_size": 11.0}
