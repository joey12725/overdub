extends SceneTree
## Headless check of data/accessibility/** through AccessKit:
##   bash tools/gd script res://art/accessibility/check_data.gd
## Prints one line per check and exits 1 on the first failure.

var _fails: int = 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("ok   ", what)
	else:
		_fails += 1
		print("FAIL ", what)


func _init() -> void:
	var sets := AccessKit.set_ids()
	_check(sets.has("default") and sets.has("high_contrast") and sets.has("legacy"), "three colour sets: %s" % [sets])
	for id: String in sets:
		var c := AccessKit.colors(id)
		_check(c.size() == 4 and AccessKit.deep(id).size() == 4 and AccessKit.night(id).size() == 4, "%s: 4 colours, deep, night" % id)
		_check(AccessKit.on_color(id).size() == 4 and AccessKit.text_on_panel(id).size() == 4, "%s: on_color and text_on_panel" % id)
		_check(AccessKit.color_names(id).size() == 4, "%s: names %s" % [id, AccessKit.color_names(id)])
	_check(AccessKit.colors("legacy")[0].is_equal_approx(OD.tape_color(0)), "legacy set equals OD.TAPE_COLORS (the analysis baseline)")
	_check(AccessKit.colors("nope")[0].is_equal_approx(AccessKit.colors("default")[0]), "unknown set falls back to default")
	var letters := ""
	var shapes: Array[String] = []
	var pats: Array[String] = []
	for t in 4:
		letters += AccessKit.letter(t)
		shapes.append(AccessKit.shape_id(t))
		pats.append(AccessKit.pattern_id(t))
		var poly := AccessKit.shape_polygon(t)
		_check(poly.size() >= 3 and not Geometry2D.triangulate_polygon(poly).is_empty(), "tape %d polygon triangulates (%d points)" % [t, poly.size()])
		var lo := Vector2(9, 9)
		var hi := Vector2(-9, -9)
		for p: Vector2 in poly:
			lo = lo.min(p)
			hi = hi.max(p)
		_check(lo.x >= -1.001 and lo.y >= -1.001 and hi.x <= 1.001 and hi.y <= 1.001, "tape %d polygon inside the unit box" % t)
		var pt := AccessKit.pattern_texture(t)
		_check(pt != null and pt.get_size() == Vector2(128, 128), "tape %d pattern texture 128 px" % t)
		if pt != null:
			_check(_seamless(pt.get_image()), "tape %d pattern wraps without a seam" % t)
		for ring: bool in [false, true]:
			var st := AccessKit.shape_texture(t, ring)
			_check(st != null and st.get_size() == Vector2(128, 128), "tape %d shape texture (ring=%s)" % [t, ring])
		var mesh := AccessKit.ring_mesh(t, 0.45, 0.07)
		var ok := mesh.get_surface_count() == 1
		if ok:
			var aabb := mesh.get_aabb()
			ok = aabb.size.x > 0.6 and aabb.size.x <= 0.91 and aabb.size.z > 0.6 and aabb.size.z <= 0.91 and absf(aabb.size.y) < 1e-5
		_check(ok, "tape %d ring mesh is flat and about 0.9 m across" % t)
	_check(letters == "ABCD", "letters %s" % letters)
	_check(shapes == ["circle", "triangle", "square", "plus"], "shapes %s" % [shapes])
	_check(pats == ["stripes", "dots", "chevrons", "grid"], "patterns %s" % [pats])
	var d := AccessKit.option_defaults()
	_check(d.get("patterns") == false and d.get("reduceFlashing") == false and d.get("screenShake") == "full"
		and d.get("cassettePalette") == "default" and d.get("holdMode") == "hold" and is_equal_approx(float(d.get("textScale")), 1.0)
		and int(d.get("avOffsetMs")) == 0 and d.get("highContrast") == false, "option defaults %s" % [d])
	var s := SaveSettings.new()
	_check(d.get("patterns") == s.patterns and int(d.get("avOffsetMs")) == s.av_offset_ms and s.screen_shake, "defaults agree with SaveSettings where the field exists")
	_check(is_equal_approx(AccessKit.clamp_flash_alpha(0.5, false), 0.25) and is_equal_approx(AccessKit.clamp_flash_alpha(0.5, true), 0.06), "flash alpha clamps 0.25 / 0.06")
	_check(int(AccessKit.flash_limits(true).get("max_large_area_flashes_per_second", -1)) == 0, "reduced mode allows no large-area flash")
	var k := AccessKit.keyline_px(1080.0, true)
	_check(is_equal_approx(k.x, 3.0) and is_equal_approx(k.y, 2.0) and is_equal_approx(AccessKit.keyline_px(1080.0, false).y, 0.0), "keylines 2 px ink; 3 px ink + 2 px paper in high contrast")
	print("accessibility data: %s" % ("ALL OK" if _fails == 0 else "%d FAILED" % _fails))
	quit(0 if _fails == 0 else 1)


## Every row / column continues across the wrap no more abruptly than it does inside the tile.
func _seamless(img: Image) -> bool:
	if img == null:
		return false
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var seam := 0.0
	var inner := 0.0
	for y in h:
		seam += absf(img.get_pixel(0, y).r - img.get_pixel(w - 1, y).r)
	for x in range(1, w):
		var s := 0.0
		for y in h:
			s += absf(img.get_pixel(x, y).r - img.get_pixel(x - 1, y).r)
		inner = maxf(inner, s)
	var seam_v := 0.0
	var inner_v := 0.0
	for x in w:
		seam_v += absf(img.get_pixel(x, 0).r - img.get_pixel(x, h - 1).r)
	for y in range(1, h):
		var s2 := 0.0
		for x in w:
			s2 += absf(img.get_pixel(x, y).r - img.get_pixel(x, y - 1).r)
		inner_v = maxf(inner_v, s2)
	return seam <= inner + 0.05 and seam_v <= inner_v + 0.05
