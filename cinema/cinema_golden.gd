class_name CinemaGolden
extends RefCounted
## Loads a prototype golden scenario (tests/goldens/<name>.json) as planner input: the level, the
## authoritative Resolution (its sampled snapshots stand in for the dense frames) and a Context
## whose prior events are the self deaths of the scenario's live recordings (the earlier runs of
## the attempt). Used by tests/cinema and tools/cinema_demo.gd; the game itself passes the real
## Resolution.

var name: String = ""
var description: String = ""
var level: LevelDef = null
var resolution: Resolution = null
var ctx: CinemaTypes.Context = CinemaTypes.Context.new()


static func load_named(scenario: String, errors: Array[String] = []) -> CinemaGolden:
	return load_path("res://tests/goldens/%s.json" % scenario, errors)


static func load_path(path: String, errors: Array[String] = []) -> CinemaGolden:
	var data: Variant = ODJson.read_file(path, errors)
	if not (data is Dictionary):
		errors.append("not a golden: " + path)
		return null
	return from_dict(data, errors)


static func from_dict(g: Dictionary, errors: Array[String] = []) -> CinemaGolden:
	var o := CinemaGolden.new()
	o.name = ODJson.string(g, "name")
	o.description = ODJson.string(g, "description")
	o.level = LevelDef.from_dict(ODJson.dict(g, "level"), errors)
	var expected := ODJson.dict(g, "expected")
	var r := ODJson.dict(expected, "resolution")
	var res := Resolution.new()
	res.outcome = Outcome.from_dict(ODJson.dict(r, "outcome"))
	res.horizon_subs = ODJson.integer(r, "horizonSubs")
	for v: Variant in ODJson.array(r, "snapshots"):
		if v is Dictionary:
			res.frames.append(FrameSnapshot.from_dict(v))
	for v: Variant in ODJson.array(r, "events"):
		if v is Dictionary:
			res.events.append(SimEvent.from_dict(v))
	o.resolution = res
	for rec: Variant in ODJson.array(expected, "recordings"):
		if not (rec is Dictionary):
			continue
		for v: Variant in ODJson.array(rec, "events"):
			if v is Dictionary and ODJson.string(v, "type") == String(SimEventType.SELF_DEATH):
				o.ctx.prior_events.append(SimEvent.from_dict(v))
	return o


func plan() -> CinemaPlan:
	return CinemaPlanner.plan(resolution, level, ctx)
