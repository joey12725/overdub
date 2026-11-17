extends ODTest
## Trap visuals (world/world_traps.gd) driven by MechSnap per docs/TRAPS.md "Snapshot fields", plus
## the painted graffiti lookup and the backdrop plate. Run with `bash tools/gd test world/`.

var _view: WorldViewBase = null
var _sub: int = 0


## Every trap kind on the sandbox map (14 x 10, rim walls).
static func trap_defs() -> Array:
	return [
		{"kind": "spikes", "id": "sp1", "cells": [{"c": 2, "r": 2}, {"c": 3, "r": 2}], "upWhen": {"beat": {"every": 4, "from": 2, "to": 3}}},
		{"kind": "crusher", "id": "cr1", "cells": [{"c": 10, "r": 1}, {"c": 10, "r": 2}], "extendWhen": {"sig": "lever"}},
		{"kind": "crusher", "id": "cr2", "cells": [{"c": 1, "r": 3}], "extendWhen": {"beat": {"every": 2, "from": 0, "to": 1}}},
		{"kind": "conveyor", "id": "belt1", "cells": [{"c": 7, "r": 8}, {"c": 8, "r": 8}, {"c": 9, "r": 8}], "dir": "e", "speed": 2},
		{"kind": "flame", "id": "fl1", "c": 13, "r": 3, "dir": "w", "range": 3, "onWhen": {"sig": "trip1"}},
		{"kind": "dart", "id": "d1", "c": 0, "r": 7, "dir": "e", "every": 2},
		{"kind": "bumper", "id": "bm1", "c": 7, "r": 4, "dir": "n", "fireWhen": {"beat": {"every": 4, "from": 3, "to": 3.5}}},
		{"kind": "sensor", "id": "trip1", "from": {"x": 6.2, "y": 5.5}, "to": {"x": 8.8, "y": 5.5}},
		{"kind": "relay", "id": "slam", "trigger": {"sig": "trip1"}, "x": 4.5, "y": 0.5},
		{"kind": "relay", "id": "hidden", "trigger": {"sig": "trip1"}},
		{"kind": "magnet", "id": "mag1", "x": 11.5, "y": 5.5, "radius": 2, "onWhen": {"sig": "lever"}},
	]


func before_each() -> void:
	_view = Facades.instance_world_view()
	tree().root.add_child(_view)
	_sub = 0


func after_each() -> void:
	if _view != null:
		_view.dispose()
		_view.queue_free()
		_view = null


func _load(theme: StringName = LevelTheme.UPPER) -> WorldTraps:
	_view.load_level(trap_level(theme), ResolvedLoadout.new())
	return _view.call("traps")


## The sandbox with every trap of trap_defs() parsed into its TrapDef entity.
static func trap_level(theme: StringName = LevelTheme.UPPER) -> LevelDef:
	var l := ContentData.load_level("sandbox", [])
	l.theme = theme
	for d: Dictionary in trap_defs():
		var errors: Array[String] = []
		var e := LevelDef.entity_from_dict(d, errors)
		assert(e != null, "trap def parses: %s %s" % [d, errors])
		l.entities.append(e)
	return l


## Render `n` frames of the given trap snapshots; the master clock advances 4 substeps a frame.
func _run(snaps: Array, n: int = 30) -> void:
	for i: int in range(n):
		_sub += OD.FRAME_SUBS
		var snap := FrameSnapshot.new()
		snap.sub = _sub
		for s: MechSnap in snaps:
			snap.mechs.append(s)
		var f := RenderFrame.new()
		f.snap = snap
		f.prev = snap
		f.dt = 1.0 / 60.0
		f.mode = ViewMode.RECORD
		_view.render(f)


func _snap(id: String, kind: StringName, on: bool, t: float = -1.0) -> MechSnap:
	var m := MechSnap.new()
	m.id = id
	m.kind = kind
	m.on = on
	if t >= 0.0:
		m.with_t(t)
	return m


func test_spec_parsing_and_direction_inference() -> void:
	var specs := WorldTraps.specs_from(WorldTraps.defs_for(trap_level()))
	assert_eq(specs.size(), trap_defs().size(), "every trap kind parses")
	var by_id := {}
	for s: WorldTraps.TrapSpec in specs:
		by_id[s.id] = s
	var cr1: WorldTraps.TrapSpec = by_id["cr1"]
	assert_eq(cr1.crusher_dir(), "s", "crusher dir inferred from its first two cells")
	assert_eq((by_id["cr2"] as WorldTraps.TrapSpec).crusher_dir(), "", "one-cell crusher without dir is a stamper")
	assert_eq(cr1.drivers, ["lever"] as Array[String])
	assert_true((by_id["sp1"] as WorldTraps.TrapSpec).drivers.is_empty(), "beat-driven spikes have no driver signal")
	assert_eq((by_id["fl1"] as WorldTraps.TrapSpec).range_tiles, 3)
	assert_vec_near((by_id["trip1"] as WorldTraps.TrapSpec).to, Vector2(8.8, 5.5), 1e-6)
	assert_true((by_id["slam"] as WorldTraps.TrapSpec).has_pos)
	assert_false((by_id["hidden"] as WorldTraps.TrapSpec).has_pos)
	assert_null_spec(WorldTraps.TrapSpec.from_dict({"kind": "door", "id": "x"}))
	assert_near(WorldTraps.dir_heading("s"), PI * 0.5, 1e-9)
	assert_eq(WorldTraps.dir_step("n"), Vector2i(0, -1))
	var walls := WorldTraps.replaced_walls(specs, WorldLayout.compute(ContentData.load_level("sandbox", [])))
	assert_eq(walls.keys(), [Vector2i(10, 0)], "the crusher housing replaces the wall behind cells[0]")


func assert_null_spec(s: WorldTraps.TrapSpec) -> void:
	assert_true(s == null, "non-trap kinds are not trap specs")


func test_trap_state_reads_optional_fields() -> void:
	var plain := MechSnap.new()
	plain.on = true
	var st := WorldTraps.TrapState.read(plain)
	assert_true(st.on)
	assert_false(st.has_dir or st.has_reach or st.firing, "plain MechSnap: no trap fields")
	assert_near(st.warn, 0.0, 0.0)
	var ts := _snap("x", &"flame", false)
	ts.with_warn(0.4)
	ts.with_dir(1.0)
	ts.with_reach(2.0)
	ts.with_firing(true)
	st = WorldTraps.TrapState.read(ts)
	assert_near(st.warn, 0.4, 1e-6)
	assert_true(st.has_dir and st.has_reach and st.firing)
	assert_near(st.reach, 2.0, 1e-6)
	ts.has_dir = false
	assert_false(WorldTraps.TrapState.read(ts).has_dir, "has_dir false hides dir")


func test_defs_come_from_trap_entities() -> void:
	var defs := WorldTraps.defs_for(trap_level())
	assert_eq(defs.size(), trap_defs().size(), "one dictionary per TrapDef, in entity order")
	assert_eq(String(defs[0]["id"]), "sp1")


func test_sandbox_has_no_traps_by_default() -> void:
	assert_true(WorldTraps.defs_for(ContentData.load_level("sandbox", [])).is_empty())
	_view.load_level(ContentData.load_level("sandbox", []), ResolvedLoadout.new())
	var stats: Dictionary = _view.call("build_stats")
	assert_eq(int(stats["counts"]["trap"]), 0)
	assert_eq(int(stats["counts"]["wall_replaced"]), 0)


func test_builds_every_trap_in_every_theme_from_models() -> void:
	for theme: StringName in LevelTheme.ALL:
		var traps := _load(theme)
		assert_eq(traps.list.size(), trap_defs().size() - 1, "%s: all traps but the unplaced relay are drawn" % theme)
		var stats: Dictionary = _view.call("build_stats")
		assert_eq(int(stats["counts"]["wall_replaced"]), 1, "%s: crusher housing replaced one wall" % theme)
		var walls := 0
		for row: String in _view.ctx.level.map:
			walls += row.count("#")
		assert_eq(int(stats["counts"]["wall"]) + 1, walls)
		var models: Array = stats["models"]
		for piece: String in ["trap_spikes", "trap_crusher", "trap_crusher_lane", "trap_crusher_stamper", "trap_conveyor", "trap_flame", "trap_flame_lane", "trap_dart", "trap_dart_lane", "trap_bumper", "trap_sensor", "trap_relay", "trap_magnet"]:
			assert_true(models.has(piece), "%s: %s from the kit model" % [theme, piece])
			assert_false((stats["standins"] as Array).has(piece), "%s: no stand-in for %s" % [theme, piece])


func test_spikes_follow_t_and_warn() -> void:
	var traps := _load()
	var v: WorldTraps.SpikesVisual = traps.visuals["sp1"]
	assert_eq(v.spikes.size(), 2, "one Spikes part per cell")
	_run([_snap("sp1", &"spikes", false, 0.0)], 10)
	assert_near(v.spikes[0].scale.y, WorldTraps.SPIKE_REST, 0.02, "down")
	var w := _snap("sp1", &"spikes", false, 0.0)
	w.with_warn(1.0)
	_run([w], 10)
	assert_true(v.spikes[0].scale.y > WorldTraps.SPIKE_REST + 0.05, "tips rise with the warning")
	_run([_snap("sp1", &"spikes", true, 1.0)], 3)
	assert_true(v.spikes[0].scale.y > 0.9, "snapped up within a few frames")


func test_crusher_head_and_ram_follow_extension() -> void:
	var traps := _load()
	var v: WorldTraps.CrusherVisual = traps.visuals["cr1"]
	assert_false(v.stamper)
	assert_near(v.extended, 2.0 + 0.5 - WorldTraps.HEAD_END_GAP, 1e-6)
	_run([_snap("cr1", &"crusher", true, 1.0)], 2)
	assert_near(v.head.position.z, v.extended, 1e-4, "fully extended head fills the lane")
	assert_near(v.ram.scale.z, v.extended - WorldTraps.RAM_INTO_HEAD, 1e-4)
	_run([_snap("cr1", &"crusher", true, 0.5)], 2)
	assert_near(v.head.position.z, lerpf(v.home, v.extended, 0.5), 1e-4, "retract ramp follows t")
	var w := _snap("cr1", &"crusher", false, 0.0)
	w.with_warn(0.6)
	_run([w], 2)
	assert_true(v.ghost.visible, "ghosted head on the lane while warning")
	assert_near(v.head.position.z, v.home, 1e-4)
	var st: WorldTraps.CrusherVisual = traps.visuals["cr2"]
	assert_true(st.stamper, "one-cell crusher draws the stamper")
	_run([_snap("cr2", &"crusher", true, 1.0)], 2)
	assert_near(st.head.position.y, WorldTraps.STAMP_DOWN_Y, 1e-4)
	assert_near(st.ram.scale.y, WorldTraps.STAMP_ROD - WorldTraps.STAMP_DOWN_Y, 1e-4)


func test_conveyor_scrolls_in_master_time_and_flips() -> void:
	var traps := _load()
	var v: WorldTraps.ConveyorVisual = traps.visuals["belt1"]
	assert_eq(v.cells.size(), 3)
	_run([_snap("belt1", &"conveyor", true)], 30)
	# The first frame only starts the master clock: 29 frames x 4 substeps at 2 tiles per master s.
	var dist := 29.0 * OD.FRAME_SUBS / OD.SUB_HZ * 2.0
	assert_near(v.spin, dist / WorldTraps.ROLLER_R, 1e-3, "rollers turn with the belt distance")
	assert_near(v.scroll, fposmod(dist, 1.0), 1e-4, "chevrons scroll the same distance")
	var before := v.scroll
	_run([_snap("belt1", &"conveyor", false)], 10)
	assert_near(v.scroll, before, 1e-9, "a stopped belt does not scroll")
	var rev := _snap("belt1", &"conveyor", true)
	rev.with_dir(PI)
	_run([rev], 1)
	assert_near(v.cells[0].rotation.y, RenderCtx.heading_to_yaw(PI), 1e-5, "reversal flips the cells at once")


func test_flame_reach_lanes_and_jet() -> void:
	var traps := _load()
	var v: WorldTraps.FlameVisual = traps.visuals["fl1"]
	assert_eq(v.lanes.size(), 3)
	var s := _snap("fl1", &"flame", true)
	s.with_reach(2.0)
	_run([s], 20)
	assert_true(v.lanes[0].visible and v.lanes[1].visible and not v.lanes[2].visible, "scorch only as far as reach")
	assert_true(v.jet.visible)
	assert_near(v.jet.scale.z, 2.0 - (WorldTraps.NOZZLE_MOUTH_Z - 0.5), 0.01, "jet length = reach - 0.345")
	var off := _snap("fl1", &"flame", false)
	off.with_reach(3.0)
	_run([off], 20)
	assert_false(v.jet.visible, "no jet while off")
	assert_true(v.lanes[2].visible, "the danger lane is shown while off")


func test_dart_pips_shutter_and_flash() -> void:
	var traps := _load()
	var v: WorldTraps.DartVisual = traps.visuals["d1"]
	assert_eq(v.pips.size(), WorldTraps.PIPS)
	_run([_snap("d1", &"dart", true, 0.5)], 3)
	var lit := 0
	for p: Node3D in v.pips:
		var mi := WorldTraps._meshes(p)[0]
		if float(mi.get_instance_shader_parameter(&"instance_energy")) > 0.5:
			lit += 1
	assert_eq(lit, 4, "half way to the next shot: four pips lit")
	_run([_snap("d1", &"dart", true, 0.9)], 1)
	assert_false(v.flash.visible)
	_run([_snap("d1", &"dart", true, 0.05)], 1)
	assert_true(v.flash.visible, "a wrap of the progress is a shot: muzzle flash")
	_run([_snap("d1", &"dart", false, 0.0)], 40)
	assert_false(v.flash.visible)
	assert_near(v.shutter.position.y, v.shutter_rest.y - WorldTraps.SHUTTER_TRAVEL, 1e-3, "disabled: shutter closed")
	var lane_tiles := 0
	for ch: Node in v.node.get_children():
		if ch.get_child_count() > 0 and String(ch.get_child(0).name).contains("dart_lane"):
			lane_tiles += 1
	assert_true(lane_tiles >= 10, "lane drawn down the open row (%d tiles)" % lane_tiles)


func test_bumper_sensor_relay_magnet() -> void:
	var traps := _load()
	var b: WorldTraps.BumperVisual = traps.visuals["bm1"]
	_run([_snap("bm1", &"bumper", true, 1.0)], 1)
	assert_near(b.pad.position.y - b.pad_rest.y, WorldTraps.PAD_POP, 1e-5)
	assert_near(b.spring.scale.y, WorldTraps.SPRING_REST + WorldTraps.PAD_POP, 1e-5)
	var s: WorldTraps.SensorVisual = traps.visuals["trip1"]
	assert_near(s.length, 2.6, 1e-5)
	var cut := _snap("trip1", &"sensor", true)
	cut.with_reach(1.25)
	_run([cut], 1)
	assert_near(s.beam.scale.z, 1.25, 1e-5, "beam drawn only as long as reach")
	var r: WorldTraps.RelayVisual = traps.visuals["slam"]
	assert_eq(r.ticks.size(), WorldTraps.TICKS)
	assert_near(r.node.get_child(0).position.y, _view.surface_height(4.5, 0.5), 1e-5, "relay sits on the wall top")
	var on := _snap("slam", &"relay", true, 0.0)
	_run([on], 1)
	assert_near(float(WorldTraps._meshes(r.lamp)[0].get_instance_shader_parameter(&"instance_energy")), 3.0, 1e-5, "output on: lamp solid")
	var m: WorldTraps.MagnetVisual = traps.visuals["mag1"]
	assert_near(m.radius, 2.0, 1e-6)
	_run([_snap("mag1", &"magnet", true)], 30)
	assert_true(m.pulses[0].visible, "contracting rings while pulling")
	assert_true(m.pulses[0].scale.x <= 2.0 + 1e-6 and m.pulses[0].scale.x >= 0.6 - 1e-6)


func test_trap_wires_share_accents() -> void:
	_load()
	# The flame reads trip1, the sensor publishes it: one wire colour.
	var acc: Color = _view.call("accent_for", "trip1")
	var traps: WorldTraps = _view.call("traps")
	assert_eq(traps._accent(traps.visuals["fl1"].spec), acc)
	assert_eq(traps._accent(traps.visuals["trip1"].spec), acc)
	assert_eq(traps._accent(traps.visuals["sp1"].spec), WorldMechAccent.BEAT_ACCENT, "beat-driven: beat accent")


func test_painted_graffiti_lookup() -> void:
	var files := WorldGraffiti.painted_files()
	if files.is_empty():
		assert_true(WorldGraffiti.painted("MOX", 1) == null, "no painted tags: procedural only")
		return
	assert_true(WorldGraffiti.painted("5 6 7 8", 1) != null, "'5 6 7 8' matches 5678.png")
	assert_true(WorldGraffiti.painted("Moxie was here!", 1) != null, "punctuation and case ignored")
	assert_true(WorldGraffiti.painted("REC", 1) != null, "REC has painted art (rec.png)")
	assert_true(WorldGraffiti.painted("ZQXJ WOMBAT", 1) == null, "a word without a file: procedural tag")
	assert_true(WorldGraffiti.painted("<<", 1) != null, "'<<' uses its alias (rewind.png)")
	assert_eq(WorldGraffiti.painted("<<", 1), WorldGraffiti.painted("<<", 9), "alias, not a random pick")
	assert_true(WorldGraffiti.painted("??", 1) == null, "symbol-only tag without an alias stays procedural")
	# Every word the campaign levels paint has art, so no level falls back to the procedural tag.
	for v: String in ["ROLL TAPE", "ON AIR", "MIND THE TEETH", "+1", "3/4", "x2", "A/B", "WAIT 4 UR SPARK"]:
		assert_true(WorldGraffiti.painted(v, 1) != null, "painted art for '%s'" % v)
	assert_true(WorldGraffiti.painted("", 7) != null, "empty variant picks a painted tag")
	assert_eq(WorldGraffiti.painted("", 7), WorldGraffiti.painted("", 7), "deterministic pick")


func test_backdrop_plate_covers_view() -> void:
	_view.load_level(ContentData.load_level("sandbox", []), ResolvedLoadout.new())
	var bd: MeshInstance3D = _view.get("backdrop")
	assert_eq(bd.visible, _view.call("backdrop_for", LevelTheme.UPPER) != null, "plate only when the theme has one")
	var img := Image.create(64, 32, false, Image.FORMAT_RGB8)
	_view.call("set_backdrop", ImageTexture.create_from_image(img))
	_run([], 2)
	assert_true(bd.visible)
	var cam: Camera3D = _view.ctx.camera
	var q := (bd.mesh as QuadMesh).size
	assert_true(q.y >= cam.size - 1e-4, "covers the view height")
	var vp := _view.get_viewport().get_visible_rect().size
	assert_true(q.x >= cam.size * vp.x / vp.y - 1e-3, "covers the view width")
	assert_near(q.x / q.y, 2.0, 1e-4, "image aspect kept")
	assert_true(-bd.position.z < WorldIsoCamera.FAR, "inside the far plane")
	_view.call("set_backdrop", null)
	assert_false(bd.visible)
