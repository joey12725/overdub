extends ODTest
## MUSIC-01: the GDScript Harmonograph reproduces the JS engine. Goldens are written by
## prototype/scripts/export-hg-goldens.cjs from prototype/src/vendor/harmonograph.js:
##   node prototype/scripts/export-hg-goldens.cjs
## Integers (pitches, velocities, steps, lanes, integer formula values, chord tones) must match
## exactly; floats (beats, durations, contour values) within 1e-9.
##
## Input numbers in the goldens are written as "<decimal>@<hex bits>" strings and decoded from the
## bits here, because Godot's JSON parser does not round-trip every double (see the exporter).
##
## Run with `bash tools/gd test harmonograph`.

const DIR := "res://tests/audio/goldens/"
const EPS := 1e-9

var _formulas: Dictionary = {}
var _harmony: Dictionary = {}
var _compile: Dictionary = {}


func before_each() -> void:
	if _formulas.is_empty():
		_formulas = _load("hg_formulas.json")
		_harmony = _load("hg_harmony.json")
		_compile = _load("hg_compile.json")


func _load(file: String) -> Dictionary:
	var v: Variant = load_json(DIR + file)
	if v is Dictionary:
		return _decode(v)
	fail("could not load " + file)
	return {}


## Replaces every "<decimal>@<16 hex>" string with the exact double it encodes.
func _decode(v: Variant) -> Variant:
	if v is String:
		var s: String = v
		var at: int = s.rfind("@")
		if at > 0 and s.length() - at == 17:
			var hex: String = s.substr(at + 1)
			if hex.is_valid_hex_number(false):
				return hex.hex_decode().decode_double(0)
		return s
	if v is Array:
		var out: Array = []
		for x: Variant in v:
			out.append(_decode(x))
		return out
	if v is Dictionary:
		var d: Dictionary = {}
		for k: Variant in v:
			d[k] = _decode(v[k])
		return d
	return v


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= EPS


func _bits(v: float) -> String:
	return PackedFloat64Array([v]).to_byte_array().hex_encode()


# ───────────────────────────── catalogue ─────────────────────────────

func test_catalogue_metadata_matches_engine() -> void:
	var list: Array = _formulas.get("formulas", [])
	var cat := Harmonograph.catalogue()
	assert_eq(cat.size(), list.size(), "formula count")
	assert_eq(cat.size(), 66, "the engine has 66 formulas")
	var bad: PackedStringArray = []
	for i: int in mini(cat.size(), list.size()):
		var g: Dictionary = list[i]
		var f: HGFormula = cat[i]
		var ok: bool = f.id == g["id"] and f.name == g["name"] and f.category == g["category"] and f.equation == g["formula"] and f.integer == g["integer"] and f.has_period == g["hasPeriod"]
		var gp: Array = g["params"]
		ok = ok and f.params.size() == gp.size()
		if ok:
			for j: int in gp.size():
				var a: HGParamDef = f.params[j]
				var b: Dictionary = gp[j]
				# Default values must be bit-identical: they seed chaotic maps.
				ok = ok and a.key == b["key"] and a.label == b["label"] and _bits(a.value) == _bits(float(b["value"]))
				ok = ok and a.min_value == float(b["min"]) and a.max_value == float(b["max"]) and a.step == float(b["step"])
				var det: Array = b["detents"]
				ok = ok and a.detents.size() == det.size()
				if ok:
					for k: int in det.size():
						ok = ok and _bits(a.detents[k]) == _bits(float(det[k]))
		if not ok:
			bad.append(String(g["id"]))
	assert_true(bad.is_empty(), "catalogue entries differ from the engine: " + ", ".join(bad))


# ───────────────────────────── formulas ─────────────────────────────

## For every formula and parameter set: 64 values, 64 normals, the probe steps and the period.
func test_formula_values_normals_and_periods() -> void:
	var list: Array = _formulas.get("formulas", [])
	var sets_total: int = 0
	var sets_ok: int = 0
	var samples: int = 0
	var failures: PackedStringArray = []
	var skipped: PackedStringArray = []
	for g: Dictionary in list:
		var id: String = g["id"]
		var integer: bool = g["integer"]
		for pset: Dictionary in g["sets"]:
			sets_total += 1
			var p := HGMath.params_from(pset["params"])
			var P: float = float(pset["P"])
			var problem: String = ""
			var values: Array = pset["values"]
			var normals: Array = pset["normals"]
			for n: int in values.size():
				var v := Harmonograph.value(id, float(n), p, P)
				var nv := Harmonograph.normal(id, float(n), p, P)
				samples += 2
				if not _same(v, float(values[n]), integer):
					problem = "value(%d) = %s, engine %s" % [n, _f(v), _f(float(values[n]))]
					break
				if not _same(nv, float(normals[n]), false):
					problem = "normal(%d) = %s, engine %s" % [n, _f(nv), _f(float(normals[n]))]
					break
			if problem == "":
				for pr: Array in pset["probes"]:
					var n: float = float(pr[0])
					# A sin-driven chaotic map is compared only on the prefix where its stream agrees
					# with V8 to 1e-9; test_sin_maps_diverge_only_through_platform_sin proves why.
					var limit: int = _chaos_limit(id, String(pset["label"]))
					if limit >= 0 and n >= float(limit):
						skipped.append("%s [%s] n=%s (stream leaves 1e-9 of V8 at n=%d)" % [id, pset["label"], _f(n), limit])
						continue
					var v := Harmonograph.value(id, n, p, P)
					var nv := Harmonograph.normal(id, n, p, P)
					samples += 2
					if not _same(v, float(pr[1]), integer) or not _same(nv, float(pr[2]), false):
						problem = "probe n=%s: value %s / normal %s, engine %s / %s" % [_f(n), _f(v), _f(nv), _f(float(pr[1])), _f(float(pr[2]))]
						break
			if problem == "":
				var per := Harmonograph.period(id, p, P)
				var want: float = 0.0 if pset["period"] == null else float(pset["period"])
				samples += 1
				if per != want:
					problem = "period %s, engine %s" % [_f(per), _f(want)]
			if problem == "":
				sets_ok += 1
			else:
				failures.append("%s [%s]: %s" % [id, pset["label"], problem])
	print("    harmonograph goldens: formulas %d, parameter sets %d/%d matched (%d samples)" % [list.size(), sets_ok, sets_total, samples])
	if not skipped.is_empty():
		print("    harmonograph goldens: %d probe(s) beyond the chaotic-divergence prefix not compared:\n      %s" % [skipped.size(), "\n      ".join(skipped)])
	assert_true(skipped.size() <= 12, "only a handful of chaotic probes may be skipped")
	assert_true(failures.is_empty(), "formula mismatches:\n  " + "\n  ".join(failures))


## The sin-driven maps (sinemap, circle) iterate x through Math.sin. Godot's sin (the platform C
## library) and V8's sin may differ in the last bit for some arguments; in a chaotic regime that
## ulp grows exponentially. For every traced parameter set this test proves, bit by bit, that:
##   1. the port's stream equals the engine's exactly up to the first iterate where sin differs;
##   2. at that iterate the sin ARGUMENT is bit-identical and only sin's result differs (by <= 2 ulp);
##   3. replaying the recurrence with V8's sin results reproduces all 1300 engine iterates exactly,
##      so every other operation (multiply, the circle map's mod / subtract) is bit-exact.
## Hence any divergence is the platform sin alone, and the formula golden compares such a stream
## only up to where it still agrees to 1e-9.
func test_sin_maps_diverge_only_through_platform_sin() -> void:
	var traces: Array = _formulas.get("chaos", [])
	assert_eq(traces.size(), 6, "sinemap and circle traces at three parameter sets")
	for tr: Dictionary in traces:
		var id: String = tr["id"]
		var label: String = tr["label"]
		var p := HGFormulas.clean_params(id, HGMath.params_from(tr["params"]))
		var trace: Array = tr["trace"]
		var seq := HGFormulas.sequence(id, p, trace.size())
		var first: int = -1
		var x_prev: float = 0.217
		for k: int in trace.size():
			if _bits(seq[k]) != String(trace[k][2]):
				first = k
				break
			x_prev = seq[k]
		var tol: int = _tolerance_index(seq, trace)
		if first < 0:
			print("    harmonograph chaos: %s [%s] bit-identical to V8 over %d iterates" % [id, label, trace.size()])
		else:
			var arg: float = PI * x_prev if id == "sinemap" else TAU * x_prev
			assert_eq(_bits(arg), String(trace[first][0]), "%s [%s]: the sin argument at iterate %d is bit-identical" % [id, label, first])
			var mine: float = sin(arg)
			var v8: float = _hex(String(trace[first][1]))
			var ulps: int = absi(_ord(mine) - _ord(v8))
			assert_true(ulps >= 1 and ulps <= 2, "%s [%s]: at iterate %d only sin differs, by %d ulp (platform %s, V8 %s)" % [id, label, first, ulps, _f(mine), _f(v8)])
			print("    harmonograph chaos: %s [%s] bit-identical to V8 for %d iterates; sin(%s) differs by %d ulp at iterate %d; within 1e-9 until iterate %s" % [id, label, first, _f(arg), ulps, first, "end" if tol < 0 else str(tol)])
		# Replay with V8's sin results: the remaining arithmetic must be exact everywhere.
		var x: float = 0.217
		var replay_ok: bool = true
		for k: int in trace.size():
			var arg: float = PI * x if id == "sinemap" else TAU * x
			var s: float = _hex(String(trace[k][1]))
			if id == "sinemap":
				x = p["r"] * s
			else:
				x = HGMath.mod(x + p["omega"] - p["K"] / TAU * s, 1.0)
			if _bits(arg) != String(trace[k][0]) or _bits(x) != String(trace[k][2]):
				replay_ok = false
				fail("%s [%s]: replay with V8 sin differs at iterate %d" % [id, label, k])
				break
		assert_true(replay_ok, "%s [%s]: recurrence exact given V8's sin" % [id, label])


## First iterate where the port's stream leaves 1e-9 of the engine's, or -1.
func _tolerance_index(seq: PackedFloat64Array, trace: Array) -> int:
	for k: int in trace.size():
		if not _near(seq[k], _hex(String(trace[k][2]))):
			return k
	return -1


var _limits: Dictionary = {}


## For a traced (id, label) whose stream leaves 1e-9 of V8, that iterate; else -1. The "empty"
## parameter set cleans to the defaults.
func _chaos_limit(id: String, label: String) -> int:
	if label == "empty":
		label = "default"
	var key: String = id + "|" + label
	if not _limits.has(key):
		_limits[key] = -1
		for tr: Dictionary in _formulas.get("chaos", []):
			if tr["id"] == id and tr["label"] == label:
				var p := HGFormulas.clean_params(id, HGMath.params_from(tr["params"]))
				var trace: Array = tr["trace"]
				_limits[key] = _tolerance_index(HGFormulas.sequence(id, p, trace.size()), trace)
	return _limits[key]


func _hex(h: String) -> float:
	return h.hex_decode().decode_double(0)


## Orders doubles as integers (adjacent doubles differ by 1) for ulp distances.
func _ord(v: float) -> int:
	var i: int = PackedFloat64Array([v]).to_byte_array().decode_s64(0)
	return i if i >= 0 else -9223372036854775807 - 1 - i


func _same(a: float, b: float, exact: bool) -> bool:
	return a == b if exact else _near(a, b)


func _f(v: float) -> String:
	return String.num(v, 17)


# ───────────────────────────── harmony ─────────────────────────────

func test_chord_at_matches_engine() -> void:
	var total: int = 0
	var ok_count: int = 0
	var failures: PackedStringArray = []
	for entry: Dictionary in _harmony.get("chords", []):
		var s := HGState.from_dict(entry["config"])
		s.channels = []
		for row: Array in entry["chords"]:
			total += 1
			var c := Harmonograph.chord_at(s, float(row[0]))
			var want_pcs: Array = row[3]
			var ok: bool = c.degree == int(row[1]) and c.root == int(row[2]) and c.name == String(row[4]) and c.pcs.size() == want_pcs.size()
			if ok:
				for i: int in want_pcs.size():
					ok = ok and c.pcs[i] == int(want_pcs[i])
			if ok:
				ok_count += 1
			elif failures.size() < 10:
				failures.append("%s @%s: got %s, engine %s" % [JSON.stringify(entry["config"]), _f(float(row[0])), JSON.stringify(c.to_dict()), JSON.stringify(row)])
	print("    harmonograph goldens: chordAt %d/%d" % [ok_count, total])
	assert_true(total > 3000, "chord golden present")
	assert_true(failures.is_empty(), "chordAt mismatches:\n  " + "\n  ".join(failures))


func test_degree_midi_scale_notes_fold_euclid_groove() -> void:
	var bad: PackedStringArray = []
	var checks: int = 0
	for e: Dictionary in _harmony.get("degreeMidi", []):
		var vals: Array = e["values"]
		for i: int in vals.size():
			checks += 1
			var d: int = int(e["from"]) + i
			if Harmonograph.degree_midi_in(d, int(e["root"]), String(e["scale"])) != int(vals[i]):
				bad.append("degreeMidi(%d, %s %s)" % [d, e["root"], e["scale"]])
	for e: Dictionary in _harmony.get("scaleNotes", []):
		checks += 1
		var c := HGChannel.new()
		var cd: Dictionary = e["channel"]
		c.low = float(cd["low"])
		c.high = float(cd["high"])
		c.octave = float(cd["octave"])
		var s := HGState.new()
		s.root = int(e["state"]["root"])
		s.scale = String(e["state"]["scale"])
		var got := Harmonograph.scale_notes(c, s)
		if not ODJson.deep_equal(got, e["notes"]):
			bad.append("scaleNotes %s -> %s" % [JSON.stringify(e), str(got)])
	for e: Dictionary in _harmony.get("fold", []):
		var vals: Array = e["values"]
		var i: int = 0
		for d: int in range(-20, 31):
			for prev: float in [0.0, 3.0, 9.0]:
				checks += 1
				var got := Harmonograph.fold(float(d), int(e["len"]), String(e["mode"]), prev, int(e["octave"]))
				if got != float(vals[i]):
					bad.append("fold(%d, %s, %s, %s, %s) = %s, engine %s" % [d, e["len"], e["mode"], prev, e["octave"], got, vals[i]])
				i += 1
	for e: Dictionary in _harmony.get("euclid", []):
		var vals: Array = e["values"]
		for i: int in vals.size():
			checks += 1
			var step: float = float(i - 4)
			if Harmonograph.euclid(step, float(e["k"]), float(e["n"]), float(e["rot"])) != float(vals[i]):
				bad.append("euclid(%s, %s, %s, %s)" % [step, e["k"], e["n"], e["rot"]])
	for e: Dictionary in _harmony.get("groove", []):
		checks += 1
		var g := HGFormulas.groove_pattern(HGMath.params_from(e["params"]))
		if g.k != float(e["k"]) or g.n != float(e["n"]) or g.rotation != float(e["rotation"]):
			bad.append("groovePattern %s" % JSON.stringify(e))
	assert_true(checks > 5000, "harmony goldens present (%d checks)" % checks)
	var genres: Array = _harmony.get("genres", [])
	assert_eq(genres, Harmonograph.GENRE_NAMES, "genre order (the groove genre index)")
	assert_eq(_harmony.get("scales", []), Harmonograph.SCALE_NAMES, "scale order")
	for name: String in Harmonograph.SCALE_NAMES:
		assert_true(Harmonograph.SCALES.has(name), "scale " + name)
	print("    harmonograph goldens: degreeMidi / scaleNotes / fold / euclid / groove %d checks, %d mismatches" % [checks, bad.size()])
	assert_true(bad.is_empty(), "mismatches:\n  " + "\n  ".join(bad.slice(0, 20)))


# ───────────────────────────── states and compilation ─────────────────────────────

func test_initial_state_matches_engine() -> void:
	var want: Dictionary = _compile.get("initialState", {})
	want.erase("queuedSection")
	var got := Harmonograph.initial_state().to_dict()
	var diff := ODJson.first_difference(got, want)
	assert_true(diff == "", "initial_state() differs from the engine's initialState(): " + diff)
	# from_dict(to_dict()) is lossless.
	var again := HGState.from_dict(got).to_dict()
	assert_true(ODJson.first_difference(again, got) == "", "HGState round trip: " + ODJson.first_difference(again, got))


func test_compile_channel_matches_engine() -> void:
	var r := _replay(_compile.get("states", []), false)
	print("    harmonograph goldens: compileChannel %d/%d channel windows matched (%d states, %d notes)" % [r[0], r[1], r[2], r[3]])
	assert_true(r[1] > 400, "compile goldens present")
	assert_true(r[4].is_empty(), "compileChannel mismatches:\n  " + "\n  ".join(r[4]))


func test_compile_timeline_matches_engine() -> void:
	var r := _replay(_compile.get("timelines", []), true)
	print("    harmonograph goldens: compileTimeline %d/%d channel windows matched (%d notes)" % [r[0], r[1], r[3]])
	assert_true(r[1] >= 12, "timeline goldens present")
	assert_true(r[4].is_empty(), "compileTimeline mismatches:\n  " + "\n  ".join(r[4]))


func test_sum_period_and_ratio_choices_match_engine() -> void:
	var states: Dictionary = {}
	for st: Dictionary in _compile.get("states", []):
		states[st["name"]] = st["state"]
	var bad: PackedStringArray = []
	var count: int = 0
	for e: Dictionary in _compile.get("sumPeriods", []):
		var s := HGState.from_dict(states[e["state"]])
		var c: HGChannel = s.channels[int(e["channel"])]
		var want: float = 0.0 if e["period"] == null else float(e["period"])
		count += 1
		if Harmonograph.sum_period(c, s) != want:
			bad.append("%s ch%s sumPeriod %s, engine %s" % [e["state"], e["channel"], Harmonograph.sum_period(c, s), want])
		var ratios: Array = e["ratios"]
		for j: int in ratios.size():
			if not ODJson.deep_equal(Harmonograph.ratio_choices(c, c.terms[j], s), ratios[j]):
				bad.append("%s ch%s term %d ratioChoices" % [e["state"], e["channel"], j])
	assert_true(count > 50, "sum period goldens present")
	assert_true(bad.is_empty(), "\n  ".join(bad.slice(0, 20)))


## Returns [matched, total, states, notes, failures].
func _replay(list: Array, timeline: bool) -> Array:
	var matched: int = 0
	var total: int = 0
	var notes: int = 0
	var failures: PackedStringArray = []
	for st: Dictionary in list:
		var s := HGState.from_dict(st["state"])
		for comp: Dictionary in st["compiles"]:
			total += 1
			var ch: int = int(comp["channel"])
			var start: float = float(comp["start"])
			var bars: float = float(comp["bars"])
			var got: Array[HGNote] = Harmonograph.compile_timeline(s, ch, start, bars) if timeline else Harmonograph.compile_channel(s, ch, start, bars)
			var want: Array = comp["notes"]
			notes += want.size()
			var problem := _compare_notes(got, want)
			if problem == "":
				matched += 1
			else:
				failures.append("%s ch%d [%s+%s bars] (%s %s): %s" % [st["name"], ch, _f(start), _f(bars), s.channels[ch].type, s.channels[ch].formula, problem])
	return [matched, total, list.size(), notes, failures]


func _compare_notes(got: Array[HGNote], want: Array) -> String:
	for i: int in mini(got.size(), want.size()):
		var a: HGNote = got[i]
		var w: Array = want[i]
		var ok: bool = a.pitch == int(w[0]) and a.velocity == int(w[1]) and _near(a.beat, float(w[2])) and _near(a.duration, float(w[3]))
		ok = ok and a.step == int(w[4]) and a.lane == int(w[5]) and a.roll == (int(w[7]) == 1)
		if w[6] == null:
			ok = ok and not a.has_formula_value
		else:
			ok = ok and a.has_formula_value and _near(a.formula_value, float(w[6]))
		if not ok:
			return "note %d: got %s, engine %s" % [i, JSON.stringify(a.to_dict()), JSON.stringify(w)]
	if got.size() != want.size():
		return "%d notes, engine %d" % [got.size(), want.size()]
	return ""
