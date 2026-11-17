extends SceneTree
## Prove levels solvable headlessly (APP-TEST-03) with the scripted plans in
## data/levels/solutions/<level id>.json (format: game/bot.gd header).
##
##   bash tools/gd script res://tools/bot.gd                      # every plan file
##   bash tools/gd script res://tools/bot.gd -- sandbox           # data/levels/solutions/sandbox.json
##   bash tools/gd script res://tools/bot.gd -- path/to/plan.json # any plan file (res:// or relative)
##
## Prints one line per plan (verdict, takes, survivors, outcome notes, wall time) and exits 0 only
## when every plan loaded and met its "expect" block (default: a win). Draft files (takes with a
## designer `plan` the level tools have not compiled into `inputs` yet) are listed as "skip";
## `-- --strict` counts them as failures.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var paths: Array[String] = []
	for a: String in args:
		if a.begins_with("--"):
			continue
		if a.ends_with(".json"):
			paths.append(a if a.begins_with("res://") or a.begins_with("user://") else "res://" + a.trim_prefix("./"))
		else:
			paths.append(GameBot.PLAN_DIR.path_join(a + ".json"))
	if paths.is_empty():
		paths = GameBot.plan_paths()
	if paths.is_empty():
		print("bot: no plan files in %s" % GameBot.PLAN_DIR)
		quit(1)
		return
	ODCore.ensure_registered()
	var failed := 0
	var drafts := 0
	for p: String in paths:
		var errors: Array[String] = []
		var head := GameBot.load_plan(p, errors)
		if head != null and head.draft:
			# Not compiled by the level tools yet: nothing to replay. `--strict` counts it as a failure.
			drafts += 1
			if args.has("--strict"):
				failed += 1
			print("%s  %s  draft: plans not compiled into inputs yet (level.ts run %s --write)" % ["FAIL" if args.has("--strict") else "skip", p, head.level_id])
			continue
		errors.clear()
		var t0 := Time.get_ticks_msec()
		var run := GameBot.run_plan_file(p, errors)
		var ms := Time.get_ticks_msec() - t0
		if run == null:
			failed += 1
			print("FAIL  %s  (plan error) %s" % [p, "; ".join(errors)])
			continue
		var plan := GameBot.load_plan(p)
		var want_win := plan.expect_win if plan != null and plan.has_expect_win else true
		var ok := run.outcome.win == want_win
		if ok and plan != null and plan.expect_takes >= 0:
			ok = run.takes_recorded == plan.expect_takes
		if not ok:
			failed += 1
		print("%s  %s  %s  [%.2f s]" % ["ok  " if ok else "FAIL", p, GameBot.describe_run(run), ms / 1000.0])
		run.session.dispose()
	print("bot: %d plan(s), %d failed, %d draft(s) skipped" % [paths.size(), failed, drafts])
	quit(0 if failed == 0 else 1)
