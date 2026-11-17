extends ODTest
## WidgetThreat: placing 'beatSight' attack beats on the master ruler.


func test_ticks_map_like_the_ruler_and_drop_past_and_beyond_horizon() -> void:
	var beats: Array[float] = [20.0, 9.0, 4.0, 70.0, 12.5]
	var t := WidgetThreat.ticks(beats, 8.0, 64.0, 10.0, 640.0)
	assert_eq(t.size(), 3)
	assert_eq(t[0].beat, 9.0)
	assert_eq(t[1].beat, 12.5)
	assert_eq(t[2].beat, 20.0)
	assert_near(t[0].x, 10.0 + 9.0 / 64.0 * 640.0, 1e-9)


func test_imminence_and_countdown() -> void:
	var beats: Array[float] = [8.0, 8.5, 11.2]
	var t := WidgetThreat.ticks(beats, 8.0, 64.0, 0.0, 6400.0)
	assert_eq(t[0].imminence, 1.0)
	assert_eq(t[0].countdown, 0)
	assert_near(t[1].imminence, 0.5, 1e-9)
	assert_eq(t[1].countdown, 1)
	assert_eq(t[2].imminence, 0.0)
	assert_eq(t[2].countdown, 4)
	assert_eq(WidgetThreat.next_tick(t), t[0])


func test_close_beats_merge_with_a_count() -> void:
	var beats: Array[float] = [10.0, 10.05, 10.1, 30.0]
	var t := WidgetThreat.ticks(beats, 0.0, 64.0, 0.0, 640.0)
	assert_eq(t.size(), 2)
	assert_eq(t[0].count, 3)
	assert_eq(t[0].beat, 10.0)


func test_far_ticks_fade_in() -> void:
	var beats: Array[float] = [1.0, 7.9]
	var t := WidgetThreat.ticks(beats, 0.0, 64.0, 0.0, 640.0, 8.0)
	assert_eq(t[0].alpha, 1.0)
	assert_true(t[1].alpha < 0.5)


func test_empty() -> void:
	var beats: Array[float] = []
	assert_eq(WidgetThreat.ticks(beats, 0.0, 64.0, 0.0, 640.0).size(), 0)
	assert_eq(WidgetThreat.next_tick([] as Array[WidgetThreat.Tick]), null)
