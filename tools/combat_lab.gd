extends SceneTree
## The combat lab: stages attacker-versus-enemy exchanges and saves every frame, so combat feel can
## be judged without playing (windowed; needs a GPU):
##
##   bash tools/gd shot res://tools/combat_lab.gd -- [out_dir] [key=value ...]
##
##     set=core|all|special     which exchanges (default core): core = every style light + heavy at
##                              1x, blade and blunt at all four tape speeds, and the specials;
##                              all = every style x kind x speed; special = clang, kill, wall, dodge
##     style=blade,blunt        only these styles          kind=light,heavy       speed=0.5,1,2,4
##     model=auto|mannequin|moxie|<res path>   attacker (auto: first candidate under
##                              assets/models/candidates, else the neutral mannequin)
##     enemy=grunt              enemy model under assets/models/enemies
##     reverse=1                also stage each exchange on a reversed tape (the swing rewinds)
##     frames=0                 do not save every frame, only the strips
##
## Output (default %TEMP%/overdub_combat_lab, outside the repo):
##   <exchange>/f_NNN.png     every frame of the exchange, cropped to the action
##   strip_<exchange>.png     the frame before contact-1, contact, and the six after, side by side
##
## The lab runs a tiny scripted stand-in for the simulation that produces the SAME events the sim
## would (SWING / HIT / CLANG / KILL / ENEMY_STAGGER / DODGE / ENEMY_ATTACK, with momentum, damage,
## knockback and stagger from core/tuning.gd and timings from data/gear.json), at a fixed 60 Hz wall
## frame with the tape running at its speed (review at true master speed). The bodies are then posed
## exactly the way docs/COMBAT-FEEL.md tells the actor layer to: CombatFeel.update() first, the
## attacker scrubbed late by its hold lag, the enemy drawn at its lagged position through
## FeelSubject.apply().

const DT: float = 1.0 / 60.0
const CROP: Vector2i = Vector2i(760, 470)
const CELL: Vector2i = Vector2i(380, 235)
const CASSETTE: Array[Color] = [Color("#ffd23f"), Color("#ff4fa3"), Color("#3ec5ff"), Color("#7dff6b")]
const WALL_X: float = 3.1

var _out: String = ""
var _opt: Dictionary[String, String] = {}
var _root3d: Node3D = null
var _camera: Camera3D = null
var _label: Label = null
var _feel: CombatFeel = null
var _moxie: LabPuppet = null
var _enemy: LabPuppet = null
var _wall: MeshInstance3D = null
var _gear: Dictionary = {}
var _shake: float = 0.0
var _cam_base: Vector3 = Vector3.ZERO
var _frame_no: int = 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = OS.get_environment("TEMP").path_join("overdub_combat_lab")
	for a: String in args:
		if a.contains("="):
			_opt[a.get_slice("=", 0)] = a.get_slice("=", 1)
		else:
			_out = a
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_build_scene()
	var gear_text := FileAccess.get_file_as_string("res://data/gear.json")
	for it: Dictionary in JSON.parse_string(gear_text)["items"]:
		_gear[it["id"]] = it
	var list := _exchanges()
	print("combat_lab: ", list.size(), " exchanges -> ", _out)
	for ex: Dictionary in list:
		await _exchange(ex)
	print("combat_lab: done")
	quit(0)


# ───────────────────────────── scene ─────────────────────────────

func _build_scene() -> void:
	_root3d = Node3D.new()
	get_root().add_child(_root3d)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#3b3a44")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#fff4e0")
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	_root3d.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 160, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	_root3d.add_child(sun)
	# Floor: one-tile checker so reach, knockback and travel can be read off the frames.
	for i: int in range(-6, 9):
		for j: int in range(-4, 5):
			var t := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(1, 0.2, 1)
			t.mesh = bm
			t.position = Vector3(i + 0.5, -0.1, j + 0.5)
			t.material_override = ToonKit.toon(Color("#c9b592") if (i + j) % 2 == 0 else Color("#bba783"), 0.0)
			_root3d.add_child(t)
	_wall = MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(0.6, 1.9, 5.0)
	_wall.mesh = wm
	_wall.position = Vector3(WALL_X + 0.3, 0.95, 0.0)
	_wall.material_override = ToonKit.toon(Color("#8d7f6d"))
	_root3d.add_child(_wall)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 6.4
	_camera.rotation_degrees = Vector3(-35, 45, 0)
	_camera.near = 0.1
	_camera.far = 100.0
	_root3d.add_child(_camera)
	_cam_base = Vector3(1.0, 0.6, 0.0) + _camera.global_transform.basis.z * 30.0
	_camera.position = _cam_base
	_camera.current = true
	var layer := CanvasLayer.new()
	get_root().add_child(layer)
	_label = Label.new()
	_label.add_theme_font_size_override(&"font_size", 20)
	_label.add_theme_color_override(&"font_color", Color("#ffd23f"))
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(_label)
	# Attacker.
	var path := _moxie_path()
	_moxie = LabPuppet.make(path, true)
	_root3d.add_child(_moxie)
	ToonKit.apply_toon(_moxie.model)
	print("combat_lab: attacker ", path, " scale ", _moxie.body_scale, " clips ", _moxie.clips.size())
	_enemy = LabPuppet.make("res://assets/models/enemies/%s.glb" % _opt.get("enemy", "grunt"), false)
	_root3d.add_child(_enemy)
	ToonKit.apply_toon(_enemy.model)
	_feel = CombatFeel.new()
	_root3d.add_child(_feel)
	_feel.setup(_camera)
	_feel.shake_callable = func(m: float) -> void: _shake = maxf(_shake, m)
	_feel.solid_at = func(x: float, _y: float) -> bool: return _wall.visible and x >= WALL_X


func _moxie_path() -> String:
	var m: String = _opt.get("model", "auto")
	if m == "mannequin":
		return FeelRig.MANNEQUIN_PATH
	if m == "moxie":
		return "res://assets/models/moxie.glb"
	if m != "auto":
		return m
	var dir := DirAccess.open("res://assets/models/candidates")
	if dir != null:
		var subs := dir.get_directories()
		subs.sort()
		for sub: String in subs:
			var d := DirAccess.open("res://assets/models/candidates/" + sub)
			if d == null:
				continue
			for f: String in d.get_files():
				if f.ends_with(".glb"):
					return "res://assets/models/candidates/%s/%s" % [sub, f]
	return FeelRig.MANNEQUIN_PATH


# ───────────────────────────── exchange list ─────────────────────────────

func _exchanges() -> Array[Dictionary]:
	var styles: Array[String] = FeelRig.STYLES.duplicate()
	var kinds: Array[String] = ["light", "heavy"]
	var speeds: Array[float] = [0.5, 1.0, 2.0, 4.0]
	if _opt.has("style"):
		styles.assign(_opt["style"].split(","))
	if _opt.has("kind"):
		kinds.assign(_opt["kind"].split(","))
	if _opt.has("speed"):
		speeds.clear()
		for s: String in _opt["speed"].split(","):
			speeds.append(s.to_float())
	var which: String = _opt.get("set", "core")
	var out: Array[Dictionary] = []
	if which != "special":
		for st: String in styles:
			for kd: String in kinds:
				for sp: float in speeds:
					var core := is_equal_approx(sp, 1.0) or st == "blade" or st == "blunt"
					if which == "all" or core or _opt.has("speed"):
						out.append({"name": "%s_%s_%sx" % [st, kd, _sp(sp)], "style": st, "kind": kd, "speed": sp})
						if _opt.get("reverse", "0") == "1":
							out.append({"name": "%s_%s_%sx_rev" % [st, kd, _sp(sp)], "style": st, "kind": kd, "speed": sp, "reverse": true})
	if which != "all" or _opt.has("special"):
		if not _opt.has("style") and not _opt.has("speed") or which == "special":
			out.append({"name": "special_clang_blade_light_0.5x", "style": "blade", "kind": "light", "speed": 0.5})
			out.append({"name": "special_kill_blade_heavy_1x", "style": "blade", "kind": "heavy", "speed": 1.0, "hp": 1})
			out.append({"name": "special_kill_gauntlet_light_4x", "style": "gauntlet", "kind": "light", "speed": 4.0, "hp": 1})
			out.append({"name": "special_wall_blunt_heavy_2x", "style": "blunt", "kind": "heavy", "speed": 2.0, "wall": true})
			out.append({"name": "special_wall_polearm_light_2x", "style": "polearm", "kind": "light", "speed": 2.0, "wall": true})
			out.append({"name": "special_runin_blade_heavy_2x", "style": "blade", "kind": "heavy", "speed": 2.0, "run": true})
			out.append({"name": "special_dodge_near_miss", "style": "blade", "kind": "dodge", "speed": 1.0})
	return out


static func _sp(s: float) -> String:
	return "0.5" if s < 0.75 else str(int(s))


# ───────────────────────────── one exchange ─────────────────────────────

func _exchange(ex: Dictionary) -> void:
	var style: String = ex["style"]
	var item_id: String = FeelRig.STYLE_OF_ITEM.find_key(style)
	var item: Dictionary = _gear[item_id]
	var mel: Dictionary = item["melee"]
	var speed: float = ex["speed"]
	var kind: String = ex["kind"]
	var heavy := kind == "heavy"
	var is_dodge := kind == "dodge"
	var reverse: bool = ex.get("reverse", false)
	var swing: Dictionary = mel["heavy" if heavy else "light"]
	var windup := int(swing["windup"])
	var active := int(swing["active"])
	var recover := int(swing["recover"])
	var total := windup + active + recover
	var reach: float = mel["reach"]
	var tape := FeelTune.speed_index(speed)
	var tint: Color = CASSETTE[tape]
	_wall.visible = ex.get("wall", false)
	# The wall exchanges are shot from the opposite corner, so the wall is BEHIND the action.
	_camera.rotation_degrees = Vector3(-35, 225 if _wall.visible else 45, 0)
	_cam_base = Vector3(1.0, 0.6, 0.0) + _camera.global_transform.basis.z * 30.0
	_camera.position = _cam_base
	_feel.clear()
	_moxie.equip(item_id)
	var weapon_len := reach * 0.72 if style == "whip" else _weapon_len(item_id)
	_feel.track_self(tape, _moxie, tint, speed, style, weapon_len, _moxie.body_scale)
	_feel.track_enemy("e1", _enemy, 0.38, 1.3)
	# Sim state.
	var run_in: bool = ex.get("run", false)
	var ax := -3.0 if run_in else 0.0
	var ex_x := (WALL_X - 1.35) if ex.get("wall", false) else minf(reach * 0.78, 1.5)
	var e_pos := Vector2(ex_x if not run_in else 1.2, 0.0)
	if not run_in and not ex.get("wall", false):
		ax = 0.0
	elif ex.get("wall", false):
		ax = e_pos.x - minf(reach * 0.78, 1.5)
	var a_pos := Vector2(ax, 0.0)
	var hp: int = ex.get("hp", 99)
	var e_alive := true
	var knock := Vector2.ZERO
	var knock_left := 0.0
	var stagger_left := 0.0
	var stagger_total := 0.001
	var death_t := -1.0
	var tick := 0.0                      # local tick since the exchange began
	var pre := 20.0 * maxf(speed, 1.0) if not run_in else 0.0
	var swing_start := pre
	if run_in:
		# Run until the enemy is inside reach when the wind-up ends.
		swing_start = 9999.0
	var swing_end := swing_start + float(total)
	var hit_done := false
	var contact_frame := -1
	var dodge_start := 22.0
	var dodge_ticks := 14.0
	var enemy_attack_frame := -1
	var dir_name := "%s/%s" % [_out, ex["name"]]
	var save_frames: bool = _opt.get("frames", "1") != "0"
	if save_frames:
		DirAccess.make_dir_recursive_absolute(dir_name)
	var images: Array[Image] = []
	var frames_after := 46
	var f := 0
	var end_frame := -1
	var momentum := 0.0
	var tier_txt := ""
	var enemy_clip: StringName = &"idle"
	var enemy_frac := 0.0
	var telegraph_from := 8
	while true:
		var events: Array[SimEvent] = []
		var vx := 0.0
		# ── scripted sim step (one wall frame = `speed` local ticks) ──
		tick += speed
		var a_anim: StringName = AnimState.IDLE
		var iframes := false
		if is_dodge:
			# The enemy telegraphs and strikes; she dodges through it.
			var attack_at := telegraph_from + 30
			if f < telegraph_from:
				enemy_clip = &"idle"; enemy_frac = float(f) / 60.0
			elif f < attack_at:
				enemy_clip = &"telegraph"; enemy_frac = float(f - telegraph_from) / 30.0
			elif f < attack_at + 24:
				enemy_clip = &"attack"; enemy_frac = float(f - attack_at) / 24.0
			else:
				enemy_clip = &"idle"; enemy_frac = float(f) / 60.0
			dodge_start = float(attack_at) - 5.0
			var dt_ := tick - dodge_start
			if dt_ >= 0.0 and dt_ < dodge_ticks:
				a_anim = AnimState.DODGE
				vx = 2.4 / (dodge_ticks / 60.0)
				a_pos.x += vx * DT
				iframes = dt_ >= 1.0 and dt_ < 11.0
				if is_equal_approx(dt_, 0.0) or (dt_ < speed and dt_ >= 0.0):
					events.append(SimEvent.make(f * 4, SimEventType.DODGE, a_pos.x, a_pos.y).with_tape(tape))
			if f == attack_at + 4:
				events.append(SimEvent.make(f * 4, SimEventType.ENEMY_ATTACK, e_pos.x, e_pos.y).with_id("e1"))
				enemy_attack_frame = f
				contact_frame = f
		else:
			if run_in and swing_start > 9000.0:
				a_anim = AnimState.RUN
				vx = 4.5
				a_pos.x += vx * DT * speed
				# Start the wind-up so that the hit lands with the enemy just inside reach.
				var ahead := 4.5 * 0.4 * float(windup) / 60.0
				if e_pos.x - a_pos.x - ahead <= reach * 0.8:
					swing_start = tick
					swing_end = swing_start + float(total)
			var st := tick - swing_start
			if st >= 0.0 and st < float(total):
				if st < float(windup):
					a_anim = AnimState.HEAVY_WINDUP if heavy else AnimState.LIGHT_WINDUP
				elif st < float(windup + active):
					a_anim = AnimState.HEAVY_ACTIVE if heavy else AnimState.LIGHT_ACTIVE
				else:
					a_anim = AnimState.HEAVY_RECOVER if heavy else AnimState.LIGHT_RECOVER
				if run_in:
					vx = 4.5 * float(swing["moveMul"])
					a_pos.x += vx * DT * speed
				if st >= float(windup) and not hit_done:
					hit_done = true
					contact_frame = f
					var approach := Tuning.strike_approach(vx, 0.0, 0.0)
					momentum = Tuning.strike_momentum(float(swing["impact"]), 1.0, speed, approach)
					var dmg := Tuning.strike_damage(momentum, float(mel["damageEff"]), 1.0)
					var stats := Tuning.enemy_stats(EnemyType.GRUNT)
					var kb := Tuning.strike_knockback(momentum, float(mel["knockbackEff"]), 1.0, 1.0, stats.mass)
					var stg := Tuning.strike_stagger(momentum, float(mel["staggerEff"]), 1.0, stats.poise)
					events.append(SimEvent.make(f * 4, SimEventType.SWING, a_pos.x, a_pos.y).with_tape(tape).with_dir(0.0).with_detail(kind))
					events.append(SimEvent.make(f * 4, SimEventType.HIT, e_pos.x, e_pos.y).with_id("e1").with_tape(tape).with_power(momentum).with_dir(0.0).with_detail(kind))
					if dmg <= 0:
						events.append(SimEvent.make(f * 4, SimEventType.CLANG, e_pos.x, e_pos.y).with_id("e1").with_tape(tape).with_power(momentum).with_dir(0.0).with_detail("momentum"))
					hp -= dmg
					if kb > 0.0:
						knock = Vector2(kb / Tuning.KNOCKBACK_SECONDS, 0.0)
						knock_left = Tuning.KNOCKBACK_SECONDS
					if hp <= 0:
						e_alive = false
						death_t = 0.0
						events.append(SimEvent.make(f * 4, SimEventType.KILL, e_pos.x, e_pos.y).with_id("e1").with_tape(tape))
					elif stg > 0.0:
						stagger_total = maxf(0.25, stg * 0.5)
						stagger_left = stagger_total
						events.append(SimEvent.make(f * 4, SimEventType.ENEMY_STAGGER, e_pos.x, e_pos.y).with_id("e1").with_power(stg))
					tier_txt = "m=%.2f %s dmg=%d kb=%.2f" % [momentum, FeelTune.TIER_NAMES[FeelTune.hit_tier(momentum, dmg <= 0)].to_upper(), dmg, kb]
					end_frame = f + frames_after
			# Enemy: knockback slide in master time, blocked by the wall.
			if knock_left > 0.0:
				var step := minf(DT, knock_left)
				var nx := e_pos.x + knock.x * step
				var limit := WALL_X - 0.38
				if _wall.visible and nx > limit:
					nx = limit
					knock_left = 0.0
					stagger_total = maxf(stagger_total, 0.5)
					stagger_left = stagger_total
				e_pos.x = nx
				knock_left -= step
			if death_t >= 0.0:
				death_t += DT
				enemy_clip = &"death"; enemy_frac = clampf(death_t / 0.6, 0.0, 1.0)
			elif stagger_left > 0.0:
				stagger_left -= DT
				enemy_clip = &"stagger"; enemy_frac = 1.0 - clampf(stagger_left / stagger_total, 0.0, 1.0)
			else:
				enemy_clip = &"idle"; enemy_frac = float(f) / 90.0
		# ── snapshot ──
		var snap := FrameSnapshot.new()
		snap.sub = f * 4
		var asnap := ActorSnap.new()
		asnap.tape = tape
		asnap.x = a_pos.x
		asnap.y = a_pos.y
		asnap.facing = 0.0
		asnap.anim = a_anim
		asnap.iframes = iframes
		asnap.vx = vx
		snap.actors.append(asnap)
		var esnap := EnemySnap.new()
		esnap.id = "e1"
		esnap.x = e_pos.x
		esnap.y = e_pos.y
		esnap.alive = e_alive
		snap.enemies.append(esnap)
		# ── presentation: exactly the documented integration ──
		_feel.update(events, snap, DT)
		var afx := _feel.self_fx(tape)
		var efx := _feel.enemy_fx("e1")
		# Attacker: scrub the clip late by the hold lag (in local ticks at the current tape rate).
		var shown_tick := tick - FeelHold.lag_ticks(afx.lag, 60.0 * speed)
		var a_base := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(afx.pos.x if afx.has_pos else a_pos.x, 0.0, a_pos.y))
		var st2 := shown_tick - swing_start
		if is_dodge:
			var d2 := shown_tick - dodge_start
			if d2 >= 0.0 and d2 < dodge_ticks:
				_moxie.pose(&"dodge", d2 / dodge_ticks)
			else:
				_moxie.pose(&"countin", shown_tick / 60.0)
			_feel.hide_swing(tape)
		elif st2 >= 0.0 and st2 < float(total):
			var frac := 0.0
			if st2 < float(windup):
				frac = 0.4 * st2 / float(windup)
			elif st2 < float(windup + active):
				frac = 0.4 + 0.2 * (st2 - float(windup)) / float(active)
			else:
				frac = 0.6 + 0.4 * (st2 - float(windup + active)) / float(recover)
			var clip := FeelRig.melee_clip(heavy, style, _moxie.has_clip)
			var shown := 1.0 - frac if reverse else frac
			_moxie.pose(clip, shown)
			_feel.update_swing(tape, _moxie.clips[clip], shown, -1 if reverse else 1, heavy, a_base)
		else:
			if run_in and swing_start > 9000.0:
				_moxie.pose(&"run", (a_pos.x + 3.0) / 2.7)
			else:
				_moxie.pose(&"countin", shown_tick / 60.0)
			_feel.hide_swing(tape)
		_moxie.transform = afx.apply(a_base)
		# Enemy: lagged position, feel deformation, stagger / death scrubbed late by its own lag.
		var ep := efx.pos if efx.has_pos else e_pos
		var e_base := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(ep.x, 0.0, ep.y))
		_enemy.transform = efx.apply(e_base)
		var shown_e := enemy_frac
		if enemy_clip == &"stagger" or enemy_clip == &"death":
			shown_e = maxf(0.0, enemy_frac - efx.lag / (0.6 if enemy_clip == &"death" else stagger_total))
		_enemy.pose(enemy_clip, shown_e)
		# Lab camera shake (the game routes this through RenderCtx.shake).
		_shake = maxf(0.0, _shake - DT * 3.2)
		var sh := _shake * _shake * 0.22
		_camera.position = _cam_base + _camera.global_transform.basis.x * sin(float(_frame_no) * 37.7) * sh + _camera.global_transform.basis.y * cos(float(_frame_no) * 29.3) * sh
		var rel := "" if contact_frame < 0 else "  contact%+d" % (f - contact_frame)
		_label.text = " %s   f%03d%s   %s" % [ex["name"], f, rel, tier_txt]
		_frame_no += 1
		await process_frame
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image()
		var mid := _camera.unproject_position(Vector3((a_pos.x + e_pos.x) * 0.5 + (0.6 if is_dodge else 0.2), 0.75, 0.0))
		var r := Rect2i(Vector2i(mid) - CROP / 2, CROP)
		r.position.x = clampi(r.position.x, 0, img.get_width() - CROP.x)
		r.position.y = clampi(r.position.y, 0, img.get_height() - CROP.y)
		var crop := img.get_region(r)
		# The label lives in the corner of the window: stamp it into the crop.
		crop.blit_rect(img, Rect2i(0, 0, CROP.x, 30), Vector2i(0, 0))
		if save_frames:
			crop.save_png("%s/f_%03d.png" % [dir_name, f])
		images.append(crop)
		f += 1
		if is_dodge and f > enemy_attack_frame + 34 and enemy_attack_frame >= 0:
			break
		if end_frame >= 0 and f > end_frame and tick > swing_end + 6.0:
			break
		if f > 400:
			break
	# Strip: two frames before contact, contact, six after.
	if contact_frame >= 0:
		var first := contact_frame - 2
		var strip := Image.create(CELL.x * 9, CELL.y, false, Image.FORMAT_RGB8)
		for k: int in 9:
			var idx := clampi(first + k, 0, images.size() - 1)
			var cell: Image = images[idx].duplicate()
			cell.convert(Image.FORMAT_RGB8)
			cell.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
			strip.blit_rect(cell, Rect2i(Vector2i.ZERO, CELL), Vector2i(CELL.x * k, 0))
		strip.save_png("%s/strip_%s.png" % [_out, ex["name"]])
	print("  ", ex["name"], ": ", f, " frames, ", tier_txt)


func _weapon_len(item_id: String) -> float:
	var path := "res://assets/models/weapons/%s.glb" % item_id
	if not ResourceLoader.exists(path):
		return 0.8
	var n := (load(path) as PackedScene).instantiate() as Node3D
	var top := 0.3
	for c: Node in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var ab := mi.transform * mi.get_aabb()
		top = maxf(top, ab.position.y + ab.size.y)
	n.free()
	return top
