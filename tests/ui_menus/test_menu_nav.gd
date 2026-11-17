extends ODTest
## Menu focus model (port of prototype tests/ui-menus/nav.test.ts).


class FnSource:
	extends MenuSource
	var fn: Callable
	var req_fn: Callable

	func _init(p_fn: Callable, p_req: Callable = Callable()) -> void:
		fn = p_fn
		req_fn = p_req

	func menu() -> MenuDef:
		return fn.call()

	func take_focus_request() -> String:
		return req_fn.call() if req_fn.is_valid() else ""


class Log:
	extends RefCounted
	var lines: Array[String] = []
	var value: int = 0
	var req: String = ""


func _grid() -> Array[MenuEntry]:
	return [
		MenuEntry.make("a", 0, 0),
		MenuEntry.make("b", 0, 1),
		MenuEntry.make("c", 0, 2),
		MenuEntry.make("d", 1, 0),
		MenuEntry.make("e", 3, 2),
	]


func test_moves_along_a_row_and_stops_at_the_ends() -> void:
	var g := _grid()
	assert_eq(MenuHost.move_focus(g, "a", UiBase.NAV_RIGHT), "b")
	assert_eq(MenuHost.move_focus(g, "b", UiBase.NAV_RIGHT), "c")
	assert_eq(MenuHost.move_focus(g, "c", UiBase.NAV_RIGHT), "c")
	assert_eq(MenuHost.move_focus(g, "a", UiBase.NAV_LEFT), "a")


func test_moves_to_nearest_populated_row_closest_column() -> void:
	var g := _grid()
	assert_eq(MenuHost.move_focus(g, "c", UiBase.NAV_DOWN), "d")
	assert_eq(MenuHost.move_focus(g, "d", UiBase.NAV_DOWN), "e")
	assert_eq(MenuHost.move_focus(g, "e", UiBase.NAV_UP), "d")
	assert_eq(MenuHost.move_focus(g, "d", UiBase.NAV_UP), "a")
	assert_eq(MenuHost.move_focus(g, "e", UiBase.NAV_DOWN), "e")


func test_prefers_the_lower_column_on_a_tie() -> void:
	var items: Array[MenuEntry] = [MenuEntry.make("top", 0, 1), MenuEntry.make("l", 1, 0), MenuEntry.make("r", 1, 2)]
	assert_eq(MenuHost.move_focus(items, "top", UiBase.NAV_DOWN), "l")


func test_honours_explicit_links_over_geometry() -> void:
	var items: Array[MenuEntry] = [
		MenuEntry.make("x", 0, 0).link(UiBase.NAV_DOWN, "z"),
		MenuEntry.make("y", 1, 0),
		MenuEntry.make("z", 5, 3),
	]
	assert_eq(MenuHost.move_focus(items, "x", UiBase.NAV_DOWN), "z")


func test_recovers_from_a_missing_current_focus() -> void:
	var g := _grid()
	assert_eq(MenuHost.move_focus(g, "", UiBase.NAV_DOWN), "a")
	assert_eq(MenuHost.move_focus(g, "gone", UiBase.NAV_DOWN), "a")
	assert_eq(MenuHost.move_focus([] as Array[MenuEntry], "a", UiBase.NAV_DOWN), "")


func _make_host(log: Log) -> MenuHost:
	var def := func() -> MenuDef:
		var locked := MenuEntry.make("locked", 2, 0, func() -> void: log.lines.append("locked"))
		locked.disabled = true
		var entries: Array[MenuEntry] = [
			MenuEntry.make("one", 0, 0, func() -> void: log.lines.append("one")),
			MenuEntry.make("slider", 1, 0).on_adjust(func(d: int) -> void: log.value += d),
			locked,
		]
		return MenuDef.make(entries, func() -> void: log.lines.append("back"), "one")
	return MenuHost.new(FnSource.new(def))


func test_host_starts_on_default_focus_and_accepts() -> void:
	var log := Log.new()
	var host := _make_host(log)
	assert_eq(host.focus, "one")
	host.navigate(UiBase.NAV_ACCEPT)
	assert_eq(log.lines, ["one"])


func test_host_left_right_adjust_instead_of_moving() -> void:
	var log := Log.new()
	var host := _make_host(log)
	host.navigate(UiBase.NAV_DOWN)
	assert_eq(host.focus, "slider")
	host.navigate(UiBase.NAV_RIGHT)
	host.navigate(UiBase.NAV_RIGHT)
	host.navigate(UiBase.NAV_LEFT)
	assert_eq(log.value, 1)
	assert_eq(host.focus, "slider")


func test_host_disabled_entries_focus_but_do_not_activate() -> void:
	var log := Log.new()
	var host := _make_host(log)
	host.navigate(UiBase.NAV_DOWN)
	host.navigate(UiBase.NAV_DOWN)
	assert_eq(host.focus, "locked")
	host.navigate(UiBase.NAV_ACCEPT)
	assert_eq(log.lines, [])


func test_host_back_runs_the_back_handler() -> void:
	var log := Log.new()
	var host := _make_host(log)
	host.navigate(UiBase.NAV_BACK)
	assert_eq(log.lines, ["back"])


func test_host_pointer_hover_click_adjust() -> void:
	var log := Log.new()
	var host := _make_host(log)
	host.hover("slider")
	assert_eq(host.focus, "slider")
	host.click("one")
	assert_eq(host.focus, "one")
	assert_eq(log.lines, ["one"])
	host.adjust("slider", -1)
	assert_eq(log.value, -1)
	host.click("nope")
	assert_eq(log.lines, ["one"])


func test_host_calls_focused_and_honours_focus_requests() -> void:
	var log := Log.new()
	var def := func() -> MenuDef:
		var entries: Array[MenuEntry] = [
			MenuEntry.make("a", 0, 0, func() -> void: log.req = "c").on_focus(func() -> void: log.lines.append("a")),
			MenuEntry.make("b", 1, 0).on_focus(func() -> void: log.lines.append("b")),
			MenuEntry.make("c", 2, 0),
		]
		return MenuDef.make(entries)
	var req := func() -> String:
		var r := log.req
		log.req = ""
		return r
	var host := MenuHost.new(FnSource.new(def, req))
	host.navigate(UiBase.NAV_DOWN)
	assert_eq(log.lines, ["b"])
	host.hover("a")
	host.navigate(UiBase.NAV_ACCEPT)
	assert_eq(host.focus, "c")
