extends SceneTree
## Prints the cinematic director's shot list for golden scenarios as a readable timeline.
##
##   bash tools/gd script res://tools/cinema_demo.gd                    # a representative set
##   bash tools/gd script res://tools/cinema_demo.gd ghost-rescue       # one or more by name
##   bash tools/gd script res://tools/cinema_demo.gd --all              # every golden
##   bash tools/gd script res://tools/cinema_demo.gd --json ghost-rescue  # the plan as JSON
##   bash tools/gd script res://tools/cinema_demo.gd --stats            # story-beat kinds over all goldens
##
## Ruler: '|' is a bar line, '.' a beat; in a shot's row '=' is screen time and '*' its key beat.

const DEFAULT := [
	"ghost-rescue",
	"enemy-shielder-two-pairs-kill",
	"combat-knockback-changes-later-hit",
	"desync-route-reopened-by-other",
	"mech-plate-holds-laser-off",
	"boss-coordinated-win",
	"sandbox-bot-two-cassettes",
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var as_json := args.has("--json")
	var names: Array[String] = []
	if args.has("--stats"):
		_stats()
		quit(0)
		return
	if args.has("--all"):
		var idx: Variant = ODJson.read_file("res://tests/goldens/index.json", [])
		if idx is Dictionary:
			for e: Variant in ODJson.array(idx, "scenarios"):
				if e is Dictionary:
					names.append(ODJson.string(e, "name"))
				elif e is String:
					names.append(e)
	for a: String in args:
		if not a.begins_with("--"):
			names.append(a)
	if names.is_empty():
		for n: String in DEFAULT:
			names.append(n)
	for n: String in names:
		var errors: Array[String] = []
		var g := CinemaGolden.load_named(n, errors)
		if g == null:
			print("== %s: %s" % [n, ", ".join(errors)])
			continue
		var plan := g.plan()
		print("")
		print("== %s  (%s)" % [n, "win" if g.resolution.outcome.win else "not a win: planned anyway"])
		print("   " + g.description)
		if as_json:
			print(JSON.stringify(plan.to_dict(), "  "))
		else:
			print(plan.timeline_text())
	quit(0)


## --stats: over every golden, how often each story-beat kind is detected and how often it is
## shown (in some shot's `shows`), plus shot counts per beat. A quick health check of the editor.
func _stats() -> void:
	var idx: Variant = ODJson.read_file("res://tests/goldens/index.json", [])
	var detected: Dictionary[String, int] = {}
	var shown: Dictionary[String, int] = {}
	var scenarios := 0
	var shots := 0
	var beats := 0
	var splits := 0
	for e: Variant in ODJson.array(idx, "scenarios"):
		var n := ODJson.string(e, "name") if e is Dictionary else str(e)
		var g := CinemaGolden.load_named(n, [])
		if g == null:
			continue
		var plan := g.plan()
		scenarios += 1
		shots += plan.shots.size()
		beats += plan.horizon_beats
		for m: CinemaMoment in plan.moments:
			detected[String(m.kind)] = detected.get(String(m.kind), 0) + 1
		var seen := {}
		for s: CinemaShot in plan.shots:
			if s.emphasis == CinemaGrammar.EMPHASIS_SPLIT:
				splits += 1
			for k: StringName in s.shows:
				seen[String(k)] = true
		for k: String in seen.keys():
			shown[k] = shown.get(k, 0) + 1
	print("%d scenarios, %d shots over %d beats (%.1f beats per shot), %d split-screen shots" % [scenarios, shots, beats, float(beats) / maxf(1.0, float(shots)), splits])
	var keys: Array[String] = []
	for k: String in shown.keys():
		keys.append(k)
	for k: String in detected.keys():
		if not keys.has(k):
			keys.append(k)
	keys.sort()
	print("  %-12s %9s %22s" % ["kind", "detected", "scenarios showing it"])
	for k: String in keys:
		print("  %-12s %9d %22d" % [k, detected.get(k, 0), shown.get(k, 0)])
