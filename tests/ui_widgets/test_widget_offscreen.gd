extends ODTest
## WidgetOffscreen: projection onto the safe rect's border and clustering (chapter 16 off-screen
## indicator; OPEN-20).

const R := Rect2(100, 50, 800, 400) # centre (500, 250)


func _item(p: Vector2, tape: int = 0) -> WidgetOffscreen.Item:
	return WidgetOffscreen.Item.make(WidgetOffscreen.KIND_SELF, tape, WidgetOffscreen.STATE_ALIVE, p)


func test_inside_points_get_no_indicator() -> void:
	var items: Array[WidgetOffscreen.Item] = [_item(Vector2(500, 250)), _item(Vector2(100, 50)), _item(Vector2(900, 450))]
	assert_eq(WidgetOffscreen.layout(items, R, 40.0).size(), 0)


func test_edge_point_on_axis_and_diagonal() -> void:
	assert_vec_near(WidgetOffscreen.edge_point(Vector2(5000, 250), R), Vector2(900, 250), 1e-6)
	assert_vec_near(WidgetOffscreen.edge_point(Vector2(500, -1000), R), Vector2(500, 50), 1e-6)
	# Toward the bottom-left: direction (-1, 1) from the centre hits the bottom edge first (half-height 200 < 400).
	assert_vec_near(WidgetOffscreen.edge_point(Vector2(0, 750), R), Vector2(300, 450), 1e-6)
	assert_eq(WidgetOffscreen.edge_of(Vector2(300, 450), R), WidgetOffscreen.EDGE_BOTTOM)
	assert_eq(WidgetOffscreen.edge_of(Vector2(900, 200), R), WidgetOffscreen.EDGE_RIGHT)


func test_perimeter_roundtrip() -> void:
	for p: Vector2 in [Vector2(100, 50), Vector2(400, 50), Vector2(900, 300), Vector2(600, 450), Vector2(100, 120)]:
		var t := WidgetOffscreen.perimeter_t(p, R)
		assert_vec_near(WidgetOffscreen.point_at(t, R), p, 1e-6, "t=%s" % t)
	assert_eq(WidgetOffscreen.perimeter(R), 2400.0)
	assert_vec_near(WidgetOffscreen.point_at(2400.0 + 10.0, R), Vector2(110, 50), 1e-6, "wraps")


func test_single_offscreen_item_points_at_it() -> void:
	var items: Array[WidgetOffscreen.Item] = [_item(Vector2(2000, 250))]
	var cl := WidgetOffscreen.layout(items, R, 40.0)
	assert_eq(cl.size(), 1)
	assert_vec_near(cl[0].pos, Vector2(900, 250), 1e-6)
	assert_near(cl[0].angle, 0.0, 1e-6)
	assert_eq(cl[0].edge, WidgetOffscreen.EDGE_RIGHT)


func test_neighbours_on_an_edge_cluster_and_far_ones_do_not() -> void:
	var items: Array[WidgetOffscreen.Item] = [
		_item(Vector2(3000, 240), 0), _item(Vector2(3000, 260), 1), _item(Vector2(3000, 300), 2),
		_item(Vector2(-3000, 250), 3),
	]
	var cl := WidgetOffscreen.layout(items, R, 40.0)
	assert_eq(cl.size(), 2)
	var sizes: Array[int] = []
	for c: WidgetOffscreen.Cluster in cl:
		sizes.append(c.items.size())
	sizes.sort()
	assert_eq(sizes, [1, 3])


func test_cluster_wraps_round_the_perimeter_seam() -> void:
	# The top-left corner of R is at direction (-400, -200) from the centre. Rays just either side of
	# it pin just right of the corner on the top edge (t ~ 10) and just below it on the left edge
	# (t ~ 2395): neighbours across the perimeter's seam at t = 0.
	var c := R.get_center()
	var pa := c + Vector2(-400, -205) * 100.0
	var pb := c + Vector2(-400, -195) * 100.0
	var ta := WidgetOffscreen.perimeter_t(WidgetOffscreen.edge_point(pa, R), R)
	var tb := WidgetOffscreen.perimeter_t(WidgetOffscreen.edge_point(pb, R), R)
	assert_true(ta < 20.0, "ta=%s" % ta)
	assert_true(tb > 2380.0, "tb=%s" % tb)
	var items: Array[WidgetOffscreen.Item] = [_item(pa, 0), _item(pb, 1)]
	var cl := WidgetOffscreen.layout(items, R, 40.0)
	assert_eq(cl.size(), 1, "merged across t = 0")
	assert_eq(cl[0].items.size(), 2)
	assert_true(WidgetOffscreen.is_inside(cl[0].pos, R.grow(0.01)))
	assert_true(cl[0].pos.distance_to(R.position) < 20.0, "sits at the corner: %s" % cl[0].pos)


func test_behind_camera_mirrors() -> void:
	var it := _item(Vector2(600, 250))
	it.behind = true
	var cl := WidgetOffscreen.layout([it] as Array[WidgetOffscreen.Item], R, 40.0)
	assert_eq(cl.size(), 1)
	assert_eq(cl[0].edge, WidgetOffscreen.EDGE_LEFT, "a point ahead-right that is behind shows on the left")


func test_safe_rect_insets_and_margin() -> void:
	var r := WidgetOffscreen.safe_rect(Rect2(0, 0, 1600, 900), 120.0, 200.0, 20.0)
	assert_eq(r, Rect2(20, 140, 1560, 540))


func test_layout_is_deterministic_and_sorted() -> void:
	var items: Array[WidgetOffscreen.Item] = []
	for k: int in 12:
		var a := TAU * k / 12.0
		items.append(_item(Vector2(500, 250) + Vector2.from_angle(a) * 5000.0, k % 4))
	var c1 := WidgetOffscreen.layout(items, R, 30.0)
	var c2 := WidgetOffscreen.layout(items, R, 30.0)
	assert_eq(c1.size(), c2.size())
	for i: int in c1.size():
		assert_vec_near(c1[i].pos, c2[i].pos, 1e-9)
		if i > 0:
			assert_true(c1[i].t >= c1[i - 1].t)


func test_self_state_mapping() -> void:
	var a := ActorSnap.new()
	assert_eq(WidgetOffscreen.self_state(a), WidgetOffscreen.STATE_ALIVE)
	a.synced = false
	assert_eq(WidgetOffscreen.self_state(a), WidgetOffscreen.STATE_DESYNC)
	a.life = OD.LifeState.GHOST
	assert_eq(WidgetOffscreen.self_state(a), WidgetOffscreen.STATE_GHOST)
	a.life = OD.LifeState.REC_GHOST
	assert_eq(WidgetOffscreen.self_state(a), WidgetOffscreen.STATE_REC_GHOST)


func test_collect_items_covers_selves_sparks_and_telegraphs() -> void:
	var snap := FrameSnapshot.new()
	var a := ActorSnap.new()
	a.tape = 2
	a.synced = false
	a.has_spark = true
	a.spark = Vector2(1, 1)
	snap.actors.append(a)
	var e := EnemySnap.new()
	e.id = "t1"
	e.type = EnemyType.TURRET
	e.state = EnemyStateName.TELEGRAPH
	e.state_t = 0.5
	snap.enemies.append(e)
	var idle := EnemySnap.new()
	idle.id = "g1"
	snap.enemies.append(idle)
	var pulses := PackedFloat32Array([0, 0, 0.7, 0])
	var items := WidgetOffscreenIndicators.collect_items(snap, WidgetFixtures.flat_projector(), pulses)
	assert_eq(items.size(), 3)
	assert_eq(items[0].kind, WidgetOffscreen.KIND_SELF)
	assert_eq(items[0].state, WidgetOffscreen.STATE_DESYNC)
	assert_near(items[0].pulse, 0.7, 1e-6)
	assert_eq(items[1].kind, WidgetOffscreen.KIND_SPARK)
	assert_eq(items[2].kind, WidgetOffscreen.KIND_THREAT)
	assert_eq(items[2].id, "t1")
