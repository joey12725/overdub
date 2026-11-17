extends SceneTree
## Foundation micro-benchmarks (run headless: `bash tools/gd script res://tools/bench_foundation.gd`).
##
##   1. 2000 A* re-plans on the prototype's deterministic 40×40 maze (path.test.ts "performance"):
##      Pathfinder.find_path with allow_partial and default smoothing, toggling a dynamic solid every
##      50 plans so the reachability cache and walk mask are rebuilt on the way.
##   2. 100k ODTime.tape_phase_at calls (allocating) and 100k tape_phase_into calls (scratch reuse) on
##      a 480-tick reverse tape at 2× across a 16-bar horizon.
##   3. 100k TapeLib.sample_pose_at_sub calls with scratch outs (the playback hot path).
##
## Prints one line per benchmark and quits with code 0 (1 if a plan failed).


func _initialize() -> void:
	var ok := _run()
	quit(0 if ok else 1)


func _run() -> bool:
	print("[bench] Godot %s, %s" % [Engine.get_version_info().string, OS.get_processor_name()])
	var ok := _bench_paths()
	_bench_phase()
	return ok


## The prototype's maze: border walls, every 4th row walled with p 0.8, every 6th column with p 0.5,
## from the 32-bit LCG seeded 99 (`||` short-circuits, so the LCG advances only when needed).
static func _maze_40() -> Array[String]:
	var seed := 99
	var rows: Array[String] = []
	for r in 40:
		var s := ""
		for c in 40:
			var wall := r == 0 or c == 0 or r == 39 or c == 39
			if not wall and r % 4 == 0:
				seed = (seed * 1664525 + 1013904223) & 0xffffffff
				wall = seed / 4294967296.0 < 0.8
			if not wall and c % 6 == 0:
				seed = (seed * 1664525 + 1013904223) & 0xffffffff
				wall = seed / 4294967296.0 < 0.5
			s += "#" if wall else "."
		rows.append(s)
	return rows


func _bench_paths() -> bool:
	var g := ODGrid.parse(_maze_40())
	var pf := Pathfinder.new(g)
	var open: Array[Vector2i] = []
	for r in 40:
		for c in 40:
			if g.is_walkable(c, r):
				open.append(Vector2i(c, r))
	var opts := Pathfinder.PathOpts.make(true)
	var n := 2000
	var found := 0
	var expanded := 0
	var points := 0
	var t0 := Time.get_ticks_usec()
	for i in n:
		var a := open[(i * 7919) % open.size()]
		var b := open[(i * 104729 + 13) % open.size()]
		if i % 50 == 0:
			g.set_dynamic_solid(b.x, (b.y + 1) % 40, i % 100 == 0)
		var res := pf.find_path(a.x + 0.5, a.y + 0.5, b.x + 0.5, b.y + 0.5, opts)
		if res != null:
			found += 1
			points += res.points.size()
		expanded += pf.last_expanded
	var us := Time.get_ticks_usec() - t0
	print("[bench] A* re-plans: %d plans on 40x40 (%d open tiles) in %.1f ms = %.3f ms/plan; %d found, %.0f nodes expanded/plan, %.1f waypoints/plan" % [
		n, open.size(), us / 1000.0, us / 1000.0 / n, found, float(expanded) / n, float(points) / maxi(1, found)])
	# The same plans without smoothing isolate the search cost.
	var raw := Pathfinder.PathOpts.make(true, false)
	var t1 := Time.get_ticks_usec()
	for i in n:
		var a := open[(i * 7919) % open.size()]
		var b := open[(i * 104729 + 13) % open.size()]
		pf.find_path(a.x + 0.5, a.y + 0.5, b.x + 0.5, b.y + 0.5, raw)
	var us_raw := Time.get_ticks_usec() - t1
	print("[bench] A* search only (smooth off): %.1f ms = %.3f ms/plan" % [us_raw / 1000.0, us_raw / 1000.0 / n])
	return found == n


func _bench_phase() -> void:
	var tape := ODTape.create(0, 2.0, OD.EndMode.REVERSE, 480)
	var horizon := 16 * 4 * 120
	var n := 100000
	var acc := 0.0
	var t0 := Time.get_ticks_usec()
	for i in n:
		acc += ODTime.tape_phase_at(tape, i % horizon).tick
	var us_alloc := Time.get_ticks_usec() - t0
	var scratch := TapePhase.new()
	var t1 := Time.get_ticks_usec()
	for i in n:
		acc += ODTime.tape_phase_into(tape, i % horizon, scratch).tick
	var us_into := Time.get_ticks_usec() - t1
	print("[bench] tape_phase_at: %d calls in %.1f ms = %.3f us/call; tape_phase_into (scratch): %.1f ms = %.3f us/call" % [
		n, us_alloc / 1000.0, float(us_alloc) / n, us_into / 1000.0, float(us_into) / n])
	var pose := TapeLib.PoseSample.new()
	var t2 := Time.get_ticks_usec()
	for i in n:
		acc += TapeLib.sample_pose_at_sub(tape, i % horizon, pose, scratch).x
	var us_pose := Time.get_ticks_usec() - t2
	print("[bench] sample_pose_at_sub (scratch outs): %d calls in %.1f ms = %.3f us/call (checksum %.3f)" % [
		n, us_pose / 1000.0, float(us_pose) / n, acc])
