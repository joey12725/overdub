extends SceneTree
## Screenshot tool for the world view: renders data/levels/sandbox.json in each theme with fake
## mechanism states (and a showcase variant with every mechanism and the lower-level props), then
## saves PNGs OUTSIDE the repo and quits.
##
##   bash tools/gd shot res://tools/shot_world.gd [-- <out_dir> [shot names...]]
##
## Campaign modes (the real levels, resolved by their solution plans through GameBot, drawn with the
## real actor / fx layers from the Resolution's snapshots and events):
##   levels [ids...]    one game-camera shot per level mid-run (default: all twelve)
##   cine [ids...]      the cinematic director driving the camera: three shots per level
##   trapwarn [ids...]  the first frame where a trap telegraphs (warn >= 0.5), and its stroke
##   perf [id]          frame-time measurement of a full playback (default 12-master-tape), vsync off
##
## Shot names: upper, mid, lower, core (sandbox per theme), showcase_upper, showcase_lower,
## showcase_core, hud (upper with a 200 px HUD inset), close (cinematic push-in), traps_upper,
## traps_lower (every trap kind of docs/TRAPS.md with fake trap snapshots), all (default).
## Default out_dir: $TEMP/overdub_shots. The fake selves are coloured capsules drawn by this tool
## only (the real actors live in actors/), there to judge floor / self readability and the x-ray.

const SHOTS := ["upper", "mid", "lower", "core", "showcase_upper", "showcase_lower", "showcase_core", "hud", "close", "traps_upper", "traps_lower"]

## Every trap kind placed on the sandbox map (docs/TRAPS.md JSON shape).
const TRAP_DEFS := [
	{"kind": "spikes", "id": "sp1", "cells": [{"c": 2, "r": 2}, {"c": 3, "r": 2}, {"c": 2, "r": 3}, {"c": 3, "r": 3}], "upWhen": {"beat": {"every": 4, "from": 2, "to": 3}}},
	{"kind": "crusher", "id": "cr1", "cells": [{"c": 10, "r": 1}, {"c": 10, "r": 2}], "extendWhen": {"sig": "lever"}},
	{"kind": "crusher", "id": "cr2", "cells": [{"c": 1, "r": 6}], "extendWhen": {"beat": {"every": 2, "from": 0, "to": 1}}},
	{"kind": "conveyor", "id": "belt1", "cells": [{"c": 7, "r": 8}, {"c": 8, "r": 8}, {"c": 9, "r": 8}, {"c": 10, "r": 8}], "dir": "e", "speed": 2},
	{"kind": "flame", "id": "fl1", "c": 13, "r": 3, "dir": "w", "range": 4, "onWhen": {"sig": "trip1"}},
	{"kind": "dart", "id": "d1", "c": 0, "r": 7, "dir": "e", "every": 2},
	{"kind": "bumper", "id": "bm1", "c": 7, "r": 4, "dir": "n", "fireWhen": {"beat": {"every": 4, "from": 3, "to": 3.5}}},
	{"kind": "sensor", "id": "trip1", "from": {"x": 6.2, "y": 5.5}, "to": {"x": 8.8, "y": 5.5}},
	{"kind": "relay", "id": "slam", "trigger": {"sig": "trip1"}, "x": 4.5, "y": 0.5},
	{"kind": "magnet", "id": "mag1", "x": 11.5, "y": 5.5, "radius": 2, "onWhen": {"sig": "lever"}},
]

var _out_dir := ""
var _view: WorldViewBase = null
var _markers: Node3D = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out_dir = OS.get_environment("TEMP").replace("\\", "/") + "/overdub_shots"
	var wanted: Array[String] = []
	for a: String in args:
		if a == "--" or a.is_empty():
			continue
		if a.contains("/") or a.contains("\\") or a.contains(":"):
			_out_dir = a.replace("\\", "/")
		else:
			wanted.append(a)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	for mode: String in ["levels", "cine", "perf", "trapwarn"]:
		if wanted.has(mode):
			wanted.erase(mode)
			_run_campaign.call_deferred(mode, wanted)
			return
	if wanted.is_empty() or wanted.has("all"):
		wanted.assign(SHOTS)
	_run.call_deferred(wanted)


func _run(wanted: Array[String]) -> void:
	var errors: Array[String] = []
	var base := ContentData.load_level("sandbox", errors)
	if base == null:
		push_error("shot_world: cannot load sandbox %s" % [errors])
		quit(1)
		return
	_view = Facades.instance_world_view()
	root.add_child(_view)
	await process_frame
	for shot: String in wanted:
		var level := base.copy()
		var mode := ViewMode.RECORD
		var inset := 0.0
		var focus := Vector2.INF
		var theme := shot.replace("showcase_", "").replace("traps_", "")
		if shot == "hud":
			theme = "upper"
			inset = 200.0
		if shot == "close":
			theme = "lower"
			mode = ViewMode.CINEMATIC
			focus = Vector2(8.5, 6.5)
		level.theme = StringName(theme)
		if shot.begins_with("showcase") or shot == "close":
			_add_showcase(level)
		if shot.begins_with("traps"):
			_add_traps(level)
		if _view.has_method("set_bottom_inset"):
			_view.call("set_bottom_inset", inset)
		var t0 := Time.get_ticks_msec()
		_view.load_level(level, ResolvedLoadout.new())
		var build_ms := Time.get_ticks_msec() - t0
		_add_markers(level)
		var states := _states_for(shot)
		for i: int in range(150):
			var f := _frame(level, states, mode, 1.0 / 60.0, i)
			if shot.begins_with("traps"):
				_trap_states(f.snap, shot == "traps_lower", i)
			if focus != Vector2.INF:
				_view.request_focus(focus.x, focus.y, 1.0)
			_view.render(f)
			await process_frame
		var img := root.get_texture().get_image()
		var path := "%s/world_%s.png" % [_out_dir, shot]
		img.save_png(path)
		var stats: Dictionary = _view.call("build_stats") if _view.has_method("build_stats") else {}
		print("[shot_world] %s -> %s (build %d ms) %s" % [shot, path, build_ms, stats])
	quit(0)


## Mechanism states per shot (fake MechSnaps), chosen so each theme shows both looks somewhere.
func _states_for(shot: String) -> Dictionary:
	match shot:
		"upper", "hud":
			return {"lever": true, "gate": true, "plate": true, "beam": false, "cracked": false}
		"mid":
			return {"lever": false, "gate": false, "plate": false, "beam": true, "cracked": true}
		"lower", "close":
			return {"lever": true, "gate": true, "plate": false, "beam": true, "cracked": true, "heart": true, "out": true}
		"core":
			return {"lever": false, "gate": false, "plate": true, "beam": false, "cracked": false}
	return {"lever": true, "gate": false, "plate": true, "beam": true, "cracked": true, "heart": true, "out": true}


func _frame(level: LevelDef, states: Dictionary, mode: StringName, dt: float, i: int) -> RenderFrame:
	var snap := FrameSnapshot.new()
	snap.beat = i / 30.0
	for e: EntityDef in level.entities:
		if not states.has(e.id):
			continue
		var m := MechSnap.new()
		m.id = e.id
		m.on = states[e.id]
		m.kind = MechKind.DOOR if e is DoorDef else (MechKind.SWITCH if e is SwitchDef else (MechKind.PLATE if e is PlateDef else (MechKind.LASER if e is LaserDef else (MechKind.BREAKABLE if e is BreakableDef else (MechKind.CORE if e is CoreDef else MechKind.EXIT)))))
		# The breakable shatters a moment into the shot (exercises the 'break' animation path).
		if e is BreakableDef and m.on and i < 40:
			m.on = false
		snap.mechs.append(m)
	var a := ActorSnap.new()
	a.tape = 0
	a.live = true
	a.x = level.start.x
	a.y = level.start.y
	snap.actors.append(a)
	var f := RenderFrame.new()
	f.snap = snap
	f.prev = snap
	f.dt = dt
	f.mode = mode
	f.active = 0
	if i == 40:
		var ev := SimEvent.make(0, SimEventType.BREAK, 5.5, 7.5).with_id("cracked").with_dir(PI)
		f.events.append(ev)
	return f


func _add_traps(level: LevelDef) -> void:
	for d: Dictionary in TRAP_DEFS:
		var errors: Array[String] = []
		var e := LevelDef.entity_from_dict(d, errors)
		if e == null:
			push_error("shot_world: trap def rejected %s %s" % [d, errors])
			continue
		level.entities.append(e)


## Fake trap snapshots: upper shows the LIVE looks, lower the SAFE / WARNING looks (frame i of 150).
func _trap_states(snap: FrameSnapshot, warning: bool, i: int) -> void:
	snap.sub = i * OD.FRAME_SUBS
	var cyc := fposmod(i / 60.0, 1.0)
	var add := func(id: String, kind: StringName, on: bool) -> MechSnap:
		var m := MechSnap.new()
		m.id = id
		m.kind = kind
		m.on = on
		snap.mechs.append(m)
		return m
	if not warning:
		add.call("sp1", MechKind.SPIKES, true).with_t(1.0)
		add.call("cr1", MechKind.CRUSHER, true).with_t(1.0).with_dir(PI * 0.5)
		add.call("cr2", MechKind.CRUSHER, true).with_t(0.6)
		add.call("belt1", MechKind.CONVEYOR, true).with_dir(0.0)
		add.call("fl1", MechKind.FLAME, true).with_dir(PI).with_reach(4.0)
		add.call("d1", MechKind.DART, true).with_t(cyc).with_dir(0.0).with_firing(cyc < 0.1)
		add.call("bm1", MechKind.BUMPER, true).with_t(0.7).with_dir(-PI * 0.5).with_firing(true)
		add.call("trip1", MechKind.SENSOR, true).with_reach(2.6)
		add.call("slam", MechKind.RELAY, true).with_t(0.0)
		add.call("mag1", MechKind.MAGNET, true)
	else:
		add.call("sp1", MechKind.SPIKES, false).with_t(0.0).with_warn(0.7)
		add.call("cr1", MechKind.CRUSHER, false).with_t(0.0).with_warn(0.8).with_dir(PI * 0.5)
		add.call("cr2", MechKind.CRUSHER, false).with_t(0.0)
		add.call("belt1", MechKind.CONVEYOR, false).with_dir(0.0)
		add.call("fl1", MechKind.FLAME, false).with_dir(PI).with_reach(2.0).with_warn(0.6)
		add.call("d1", MechKind.DART, false).with_t(0.0).with_dir(0.0)
		add.call("bm1", MechKind.BUMPER, false).with_t(0.0).with_dir(-PI * 0.5)
		add.call("trip1", MechKind.SENSOR, false).with_reach(2.6)
		add.call("slam", MechKind.RELAY, false).with_t(0.6).with_warn(1.0)
		add.call("mag1", MechKind.MAGNET, false)


## Extra entities for the showcase shots: every mechanism kind and the lower-level props.
func _add_showcase(level: LevelDef) -> void:
	var core := CoreDef.new()
	core.id = "heart"
	core.x = 11.5
	core.y = 2.5
	level.entities.append(core)
	var ex := ExitDef.new()
	ex.id = "out"
	ex.c = 11
	ex.r = 7
	ex.w = 2
	ex.h = 2
	level.entities.append(ex)
	for spec: Array in [[DecorType.NEON, 6.6, 1.4, "cyan"], [DecorType.GENERATOR, 9.5, 1.5, ""], [DecorType.WAVE_SCREEN, 7.5, 3.4, ""], [DecorType.CHEST, 2.5, 7.5, "open"], [DecorType.BARREL, 6.4, 5.4, ""], [DecorType.GRAFFITI, 0.6, 7.0, "smiley"], [DecorType.VENT, 4.4, 1.5, ""], [DecorType.NEON, 12.4, 5.5, "pink"]]:
		var d := DecorDef.new()
		d.type = spec[0]
		d.x = spec[1]
		d.y = spec[2]
		d.variant = spec[3]
		level.entities.append(d)
	if level.theme == LevelTheme.CORE:
		# WORLD-05: the depth's set piece.
		var tm := DecorDef.new()
		tm.type = DecorType.TIME_MACHINE
		tm.x = 10.0
		tm.y = 3.0
		level.entities.append(tm)


## Tool-only stand-ins for selves and enemies (coloured capsules) to judge readability and x-ray.
func _add_markers(level: LevelDef) -> void:
	if _markers != null:
		_markers.queue_free()
	_markers = Node3D.new()
	_markers.name = "ShotMarkers"
	_view.add_child(_markers)
	var spots := [[level.start, OD.TAPE_COLORS_RGB[0]], [Vector2(9.5, 3.5), OD.TAPE_COLORS_RGB[1]], [Vector2(4.5, 6.5), OD.TAPE_COLORS_RGB[2]], [Vector2(12.4, 3.0), OD.TAPE_COLORS_RGB[3]], [Vector2(6.3, 3.4), OD.TAPE_COLORS_RGB[2]]]
	for e: EntityDef in level.entities:
		if e is EnemyDef:
			spots.append([Vector2((e as EnemyDef).x, (e as EnemyDef).y), Color("#e8e2d6")])
	for s: Array in spots:
		var p: Vector2 = s[0]
		var col: Color = s[1]
		var mi := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.22
		cap.height = 1.1
		mi.mesh = cap
		var m := ToonKit.toon(col)
		ToonKit.with_xray(m)
		mi.material_override = m
		mi.position = Vector3(p.x, 0.55, p.y)
		mi.set_instance_shader_parameter(&"instance_outline", col.darkened(0.55))
		mi.set_instance_shader_parameter(&"instance_xray", Color(col.r, col.g, col.b, 0.6))
		_markers.add_child(mi)


# ───────────────────────────── campaign modes ─────────────────────────────

const CAMPAIGN := ["01-soft-open", "02-hit-harder", "03-hold-the-door", "04-second-opinion", "05-dead-air", "06-crossfire", "07-out-of-phase", "08-loop-pedal", "09-rewind", "10-heavy-rotation", "11-the-archivist", "12-master-tape"]
const FRAME_DT := float(OD.FRAME_SUBS) / float(OD.SUB_HZ)


func _run_campaign(mode: String, ids: Array[String]) -> void:
	if ids.is_empty():
		ids.assign(["12-master-tape"] if mode == "perf" else CAMPAIGN)
	_view = Facades.instance_world_view()
	root.add_child(_view)
	await process_frame
	var lo := LoadoutRules.resolve_loadout(CampaignData.base_loadout())
	for id: String in ids:
		var lv := CampaignData.level(id)
		if lv == null:
			print("[shot_world] %s: no such level" % id)
			continue
		var t0 := Time.get_ticks_msec()
		var errors: Array[String] = []
		var run := GameBot.run_plan_file("%s/%s.json" % [GameBot.PLAN_DIR, id], errors)
		var res: Resolution = run.session.resolution if run != null and run.session != null else null
		if res == null or res.frames.size() < 4:
			print("[shot_world] %s: no resolution (%s)" % [id, ", ".join(errors)])
			continue
		print("[shot_world] %s: resolved %s in %d ms, %d frames, %d events" % [id, GameBot.describe_run(run), Time.get_ticks_msec() - t0, res.frames.size(), res.events.size()])
		if _view.has_method("set_bottom_inset"):
			_view.call("set_bottom_inset", 0.0)
		t0 = Time.get_ticks_msec()
		_view.load_level(lv, lo)
		print("[shot_world] %s: built in %d ms %s musicviz %s" % [id, Time.get_ticks_msec() - t0, _view.call("build_stats"), _view.call("musicviz_counts")])
		match mode:
			"levels":
				await _shot_level(id, res)
			"cine":
				await _shot_cine(id, lv, res)
			"trapwarn":
				await _shot_trapwarn(id, res)
			"perf":
				await _perf(id, res)
	quit(0)


func _pulse(beat: float, tapes: int) -> MusicPulse:
	var m := MusicPulse.new()
	m.beat = beat
	m.beat_pulse = exp(-6.0 * fposmod(beat, 1.0))
	m.bar_pulse = exp(-3.0 * fposmod(beat, 4.0))
	for t: int in 4:
		m.levels[t] = (0.55 + 0.35 * sin(beat * 1.7 + t)) if t < tapes else 0.0
		m.pitches[t] = 0.5 + 0.3 * sin(beat * 0.9 + t * 1.3)
	m.chord = int(floor(beat / 4.0)) % 4
	return m


func _play_frame(res: Resolution, k: int, mode: StringName, tapes: int) -> RenderFrame:
	var snap := res.frames[k]
	var prev := res.frames[maxi(0, k - 1)]
	var f := RenderFrame.new()
	f.snap = snap
	f.prev = prev
	f.alpha = 1.0
	f.dt = FRAME_DT
	f.mode = mode
	f.world_rate = 1.0
	f.active = -1
	f.music = _pulse(snap.beat, tapes)
	for ev: SimEvent in res.events:
		if ev.sub > prev.sub and ev.sub <= snap.sub:
			f.events.append(ev)
	return f


func _save(name: String) -> void:
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [_out_dir, name]
	img.save_png(path)
	print("[shot_world] -> %s" % path)


func _tapes(res: Resolution) -> int:
	return res.frames[res.frames.size() - 1].actors.size()


## Mid-run at the game camera (review framing: the whole level, or following the action).
func _shot_level(id: String, res: Resolution) -> void:
	var n := res.frames.size()
	var k1 := int(n * 0.45)
	for k: int in range(maxi(1, k1 - 150), k1 + 1):
		_view.render(_play_frame(res, k, ViewMode.REVIEW, _tapes(res)))
		await process_frame
	_save("level_%s" % id)


## The director drives the camera: capture the middle of three planned shots (the climax first).
func _shot_cine(id: String, lv: LevelDef, res: Resolution) -> void:
	var plan := CinemaPlanner.plan(res, lv, CinemaTypes.Context.new())
	_view.call("set_cinema_plan", plan)
	print("[shot_world] %s plan:\n%s" % [id, plan.timeline_text()])
	var picks: Array[float] = []
	var best := -1
	for i: int in plan.shots.size():
		var s: CinemaShot = plan.shots[i]
		if best < 0 or (s.emphasis != CinemaGrammar.EMPHASIS_NONE and plan.shots[best].emphasis == CinemaGrammar.EMPHASIS_NONE):
			if i > 0:
				best = i
	if best < 0:
		best = mini(1, plan.shots.size() - 1)
	for i: int in [best, 0, plan.shots.size() - 1]:
		var s: CinemaShot = plan.shots[i]
		picks.append(lerpf(float(s.start_beat), float(s.end_beat), 0.6))
	var n := res.frames.size()
	var taken := {}
	var cuts := 0
	for k: int in range(1, n):
		var f := _play_frame(res, k, ViewMode.CINEMATIC, _tapes(res))
		_view.render(f)
		var cf: CinemaFrame = _view.get("cinema_frame")
		if cf != null and cf.cut:
			cuts += 1
		await process_frame
		for j: int in picks.size():
			if not taken.has(j) and f.snap.beat >= picks[j]:
				taken[j] = true
				var shot: CinemaShot = cf.shot if cf != null else null
				print("[shot_world] %s cine %d at beat %.2f: shot %d %s/%s letterbox %.3f panes %d target %s span %.1f" % [id, j, f.snap.beat, cf.shot_index if cf != null else -1, shot.kind if shot != null else "-", shot.framing if shot != null else "-", cf.letterbox if cf != null else 0.0, cf.panes.size() if cf != null else 0, cf.target if cf != null else Vector2.ZERO, cf.span if cf != null else 0.0])
				_save("cine_%s_%d" % [id, j])
		if taken.size() == picks.size():
			break
	print("[shot_world] %s cine: %d hard cuts seen" % [id, cuts])
	_view.call("set_cinema_plan", null)


## The first trap telegraph (warn >= 0.5) and, a little later, the stroke.
func _shot_trapwarn(id: String, res: Resolution) -> void:
	var n := res.frames.size()
	var kw := -1
	for k: int in n:
		for m: MechSnap in res.frames[k].mechs:
			if m.has_warn and m.warn >= 0.5:
				kw = k
				break
		if kw >= 0:
			break
	if kw < 0:
		print("[shot_world] %s: no trap telegraph in the run" % id)
		return
	for k: int in range(maxi(1, kw - 90), mini(n, kw + 40)):
		_view.render(_play_frame(res, k, ViewMode.REVIEW, _tapes(res)))
		await process_frame
		if k == kw:
			var desc: Array[String] = []
			for m: MechSnap in res.frames[k].mechs:
				if m.has_warn and m.warn > 0.0:
					desc.append("%s warn %.2f" % [m.id, m.warn])
			print("[shot_world] %s warn at frame %d: %s" % [id, k, ", ".join(desc)])
			_save("trapwarn_%s_a" % id)
	_save("trapwarn_%s_b" % id)


## Frame time over a whole playback (review and cinematic), vsync off, real layers.
func _perf(id: String, res: Resolution) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var lv := CampaignData.level(id)
	for mode: StringName in [ViewMode.REVIEW, ViewMode.CINEMATIC]:
		if mode == ViewMode.CINEMATIC:
			_view.call("set_cinema_plan", CinemaPlanner.plan(res, lv, CinemaTypes.Context.new()))
		var times := PackedFloat32Array()
		var n := res.frames.size()
		var last := Time.get_ticks_usec()
		var cpu := 0.0
		for k: int in range(1, n):
			var c0 := Time.get_ticks_usec()
			_view.render(_play_frame(res, k, mode, _tapes(res)))
			cpu += Time.get_ticks_usec() - c0
			await process_frame
			var now := Time.get_ticks_usec()
			if k > 30:
				times.append((now - last) / 1000.0)
			last = now
		var sorted := times.duplicate()
		sorted.sort()
		var sum := 0.0
		for t: float in times:
			sum += t
		var avg := sum / maxf(1.0, times.size())
		print("[shot_world] PERF %s %s selves=%d frames=%d avg %.2f ms (%.0f fps) p50 %.2f p95 %.2f p99 %.2f max %.2f; world.render cpu avg %.2f ms" % [id, mode, _tapes(res), times.size(), avg, 1000.0 / maxf(0.01, avg), sorted[sorted.size() / 2], sorted[int(sorted.size() * 0.95)], sorted[int(sorted.size() * 0.99)], sorted[sorted.size() - 1], cpu / 1000.0 / maxf(1.0, n - 1)])
		var hub: MusicVizHub = _view.call("musicviz")
		if hub != null:
			print("[shot_world] PERF musicviz %.0f us/frame: %s" % [hub.frame_cost_usec(), ", ".join(hub.cost_report())])
		_save("perf_%s_%s" % [id, mode])
	_view.call("set_cinema_plan", null)
