extends ODTest
## Input: edge-triggered presses, focus loss, camera-relative movement, aim fallbacks, the
## hold-to-confirm reset and cinematic skip, and the binding table / prompt text / InputMap. Port of
## prototype/tests/game/input.test.ts (driven with synthetic InputEvents and an injected clock).

const UP := Vector2(0, -1)

var _t: float = 0.0


func _rig() -> GameInput:
	_t = 0.0
	return GameInput.new(func() -> float: return _t, func(p: Vector2) -> Vector2: return p / 10.0)


func _key(inp: GameInput, code: Key, pressed: bool, echo: bool = false, ctrl: bool = false) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	e.echo = echo
	e.ctrl_pressed = ctrl
	inp.handle_event(e)


func _press(inp: GameInput, code: Key) -> void:
	_key(inp, code, true)


func _release(inp: GameInput, code: Key) -> void:
	_key(inp, code, false)


func _tap(inp: GameInput, code: Key) -> void:
	_press(inp, code)
	_release(inp, code)


func _mouse(inp: GameInput, button: MouseButton, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	inp.handle_event(e)


func _move_mouse(inp: GameInput, pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	inp.handle_event(e)


func _pad_button(inp: GameInput, button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = pressed
	e.pressure = 1.0 if pressed else 0.0
	inp.handle_event(e)


func _pad_axis(inp: GameInput, axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	inp.handle_event(e)


func test_reports_a_press_exactly_once_even_if_released_before_the_next_sample_echo_is_ignored() -> void:
	var r := _rig()
	_press(r, KEY_SPACE)
	_release(r, KEY_SPACE)
	assert_true(r.sample(UP).dodge)
	assert_false(r.sample(UP).dodge)
	_press(r, KEY_SPACE)
	_key(r, KEY_SPACE, true, true)
	_press(r, KEY_SPACE)
	assert_true(r.sample(UP).dodge)
	assert_false(r.sample(UP).dodge)
	var acts := r.drain_actions()
	assert_eq(acts.count(GameInput.ACCEPT), 2)
	assert_eq(r.drain_actions().size(), 0)


func test_mouse_buttons_are_light_and_heavy_unbound_buttons_do_nothing() -> void:
	var r := _rig()
	_mouse(r, MOUSE_BUTTON_LEFT, true)
	_mouse(r, MOUSE_BUTTON_RIGHT, true)
	var s := r.sample(UP)
	assert_eq([s.light, s.heavy], [true, true])
	_mouse(r, MOUSE_BUTTON_LEFT, false)
	_mouse(r, MOUSE_BUTTON_RIGHT, false)
	_mouse(r, MOUSE_BUTTON_WHEEL_UP, true)
	_mouse(r, MOUSE_BUTTON_MIDDLE, true)
	s = r.sample(UP)
	assert_false(s.light or s.heavy)
	assert_eq(r.drain_actions().size(), 0)


func test_losing_focus_releases_every_key_and_drops_pending_presses() -> void:
	var r := _rig()
	_press(r, KEY_D)
	_press(r, KEY_E)
	r.release_all()
	var s := r.sample(UP)
	assert_eq(s.move_x, 0.0)
	assert_false(s.interact)
	# The key-up that never arrived does not matter; a fresh press works again.
	_press(r, KEY_D)
	assert_near(r.sample(UP).move_x, 1.0, 1e-9)


func test_movement_is_camera_relative_w_walks_toward_screen_up_in_world_axes() -> void:
	var r := _rig()
	_press(r, KEY_W)
	var s := r.sample(UP)
	assert_near(s.move_x, 0.0, 1e-9)
	assert_near(s.move_y, -1.0, 1e-9)
	# An iso camera whose screen-up points to world (-1, -1)/√2: D walks to world (1, -1)/√2.
	var iso := Vector2(-sqrt(0.5), -sqrt(0.5))
	_release(r, KEY_W)
	_press(r, KEY_D)
	s = r.sample(iso)
	# Vector2 is single precision, so `iso` itself is only good to ~1e-7.
	assert_near(s.move_x, sqrt(0.5), 1e-6)
	assert_near(s.move_y, -sqrt(0.5), 1e-6)
	# Diagonals are clamped to unit length; W and ↑ together are still one step.
	_press(r, KEY_W)
	_press(r, KEY_UP)
	s = r.sample(UP)
	# Vector2 is single precision: its length is only good to ~1e-7.
	assert_near(Vector2(s.move_x, s.move_y).length(), 1.0, 1e-6)


func test_aims_at_the_mouse_with_no_recent_mouse_movement_aim_follows_movement() -> void:
	var r := _rig()
	_move_mouse(r, Vector2(50, 0))
	var s := r.sample(UP, Vector2.ZERO)
	assert_near(s.aim, 0.0, 1e-9)
	_press(r, KEY_S)
	s = r.sample(UP, Vector2.ZERO)
	assert_near(s.aim, 0.0, 1e-9)  # mouse still recent: aim stays on the cursor
	_t += GameInput.MOUSE_AIM_TIMEOUT + 0.1
	s = r.sample(UP, Vector2.ZERO)
	assert_near(s.aim, PI / 2.0, 1e-9)  # S = screen-down = world +y


func test_backspace_taps_end_a_playback_holding_it_fires_reset_all_once() -> void:
	var r := _rig()
	_press(r, KEY_BACKSPACE)
	assert_eq(r.drain_actions(), [SessionAction.END_ATTEMPT])
	_t += GameInput.RESET_HOLD_SECONDS / 2.0
	assert_near(r.hold_progress(), 0.5, 1e-5)
	assert_eq(r.drain_actions().size(), 0)
	_t += GameInput.RESET_HOLD_SECONDS / 2.0 + 0.01
	assert_eq(r.drain_actions(), [SessionAction.RESET_ALL])
	_t += 2.0
	assert_eq(r.drain_actions().size(), 0)
	_release(r, KEY_BACKSPACE)
	# Released early: nothing.
	_press(r, KEY_DELETE)
	r.drain_actions()
	_t += GameInput.RESET_HOLD_SECONDS / 3.0
	_release(r, KEY_DELETE)
	_t += GameInput.RESET_HOLD_SECONDS
	assert_eq(r.drain_actions().size(), 0)
	assert_eq(r.hold_progress(), 0.0)


func test_session_keys_map_to_session_actions_esc_pauses() -> void:
	var r := _rig()
	for code: Key in [KEY_Q, KEY_E, KEY_TAB, KEY_R, KEY_C, KEY_ESCAPE, KEY_ENTER, KEY_LEFT]:
		_tap(r, code)
	assert_eq(r.drain_actions(), [SessionAction.SPEED_DOWN, SessionAction.SPEED_UP, SessionAction.CYCLE_END_MODE, SessionAction.RETRY_TAKE, SessionAction.COMMIT, GameInput.PAUSE, GameInput.ACCEPT, GameInput.NAV_LEFT])


func test_clear_presses_forgets_the_press_that_started_a_take() -> void:
	var r := _rig()
	_press(r, KEY_SPACE)
	r.clear_presses()
	assert_false(r.sample(UP).dodge)
	assert_eq(r.drain_actions().size(), 0)


func test_ignores_shortcuts_with_ctrl() -> void:
	var r := _rig()
	_key(r, KEY_R, true, false, true)
	_key(r, KEY_SPACE, true, false, true)
	assert_eq(r.drain_actions().size(), 0)
	assert_false(r.sample(UP).dodge)


func test_gamepad_edges_once_per_press_left_stick_moves_right_stick_aims_falls_back_to_move_direction() -> void:
	var r := _rig()
	_pad_button(r, JOY_BUTTON_A, true)
	var s := r.sample(UP)
	assert_eq(r.device(), GameInput.DEVICE_GAMEPAD)
	assert_true(s.dodge)
	assert_eq(r.drain_actions(), [GameInput.ACCEPT])
	s = r.sample(UP)
	assert_false(s.dodge, "still held: no new edge")
	_pad_button(r, JOY_BUTTON_A, false)
	_pad_axis(r, JOY_AXIS_LEFT_X, 1.0)
	s = r.sample(UP)
	assert_near(s.move_x, 1.0, 1e-6)
	assert_near(s.aim, 0.0, 1e-6)
	_pad_axis(r, JOY_AXIS_LEFT_X, 0.0)
	_pad_axis(r, JOY_AXIS_RIGHT_Y, 1.0)
	s = r.sample(UP)
	assert_near(s.aim, PI / 2.0, 1e-6)  # right stick down = screen-down = world +y
	_pad_axis(r, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_pad_axis(r, JOY_AXIS_TRIGGER_LEFT, 1.0)
	s = r.sample(UP)
	assert_eq([s.light, s.heavy], [true, true])
	# Trigger still held (more motion events): no new edge.
	_pad_axis(r, JOY_AXIS_TRIGGER_RIGHT, 0.9)
	assert_false(r.sample(UP).light)
	_pad_button(r, JOY_BUTTON_START, true)
	assert_has(r.drain_actions(), GameInput.PAUSE)


func test_gamepad_left_stick_navigates_menus_one_step_per_crossing() -> void:
	var r := _rig()
	_pad_axis(r, JOY_AXIS_LEFT_Y, 0.9)
	_pad_axis(r, JOY_AXIS_LEFT_Y, 1.0)
	_pad_axis(r, JOY_AXIS_LEFT_Y, 0.0)
	_pad_axis(r, JOY_AXIS_LEFT_X, -0.8)
	assert_eq(r.drain_actions(), [GameInput.NAV_DOWN, GameInput.NAV_LEFT])
	assert_eq(r.device(), GameInput.DEVICE_GAMEPAD)
	_move_mouse(r, Vector2(3, 3))
	assert_eq(r.device(), GameInput.DEVICE_KEYBOARD)


func test_cine_02_skip_cinematic_needs_a_hold_and_cancel_holds_forgets_a_hold_in_progress() -> void:
	var r := _rig()
	_press(r, KEY_ENTER)
	assert_eq(r.drain_actions(), [GameInput.ACCEPT])
	_t += GameInput.SKIP_HOLD_SECONDS * 0.5
	assert_near(r.hold_progress(GameInput.SKIP_CINEMATIC), 0.5, 1e-5)
	assert_eq(r.hold_progress(SessionAction.RESET_ALL), 0.0)
	r.cancel_holds()
	_t += GameInput.SKIP_HOLD_SECONDS
	assert_eq(r.drain_actions().size(), 0, "a hold cancelled at the cinematic's start never fires")
	_release(r, KEY_ENTER)
	_press(r, KEY_ENTER)
	r.drain_actions()
	_t += GameInput.SKIP_HOLD_SECONDS + 0.01
	assert_eq(r.drain_actions(), [GameInput.SKIP_CINEMATIC])


func test_describes_bindings_for_both_devices_from_the_one_table() -> void:
	assert_eq(GameInput.describe_binding(ActionKind.DODGE, GameInput.DEVICE_KEYBOARD), "Space")
	assert_eq(GameInput.describe_binding(ActionKind.DODGE, GameInput.DEVICE_GAMEPAD), "A")
	assert_eq(GameInput.describe_binding(ActionKind.LIGHT, GameInput.DEVICE_KEYBOARD), "Left click")
	assert_eq(GameInput.describe_binding(ActionKind.RANGED, GameInput.DEVICE_GAMEPAD), "RB")
	assert_eq(GameInput.describe_binding(SessionAction.RESET_ALL, GameInput.DEVICE_KEYBOARD), "Hold Backspace")
	assert_eq(GameInput.describe_binding(SessionAction.RECORD, GameInput.DEVICE_KEYBOARD), "Enter")
	assert_eq(GameInput.describe_binding(SessionAction.COMMIT, GameInput.DEVICE_KEYBOARD), "C")
	assert_eq(GameInput.describe_binding(SessionAction.COMMIT, GameInput.DEVICE_GAMEPAD), "A")
	assert_eq(GameInput.describe_binding(GameInput.PAUSE, GameInput.DEVICE_KEYBOARD), "Esc")
	assert_eq(GameInput.describe_binding(GameInput.MOVE, GameInput.DEVICE_GAMEPAD), "Left stick")
	assert_eq(GameInput.describe_binding(GameInput.SKIP_CINEMATIC, GameInput.DEVICE_KEYBOARD), "Hold Enter")
	# Every bound id is described on at least one device.
	for b: GameInput.Binding in GameInput.BINDINGS:
		assert_ne(GameInput.describe_binding(b.id, GameInput.DEVICE_KEYBOARD) + GameInput.describe_binding(b.id, GameInput.DEVICE_GAMEPAD), "", String(b.id))


func test_prompts_cover_session_actions_and_gameplay_buttons_with_pad_styles() -> void:
	var kb := GameInput.prompts(GameInput.DEVICE_KEYBOARD)
	for a: StringName in SessionAction.ALL:
		assert_true(kb.has(a), String(a))
	for a: StringName in GameInput.GAMEPLAY:
		assert_true(kb.has(a), String(a))
	assert_eq(kb[SessionAction.RESET_ALL].key, "Hold Backspace")
	assert_eq(kb[SessionAction.QUIT].key, "Esc")
	var pad := GameInput.prompts(GameInput.DEVICE_GAMEPAD)
	assert_eq(pad[SessionAction.RECORD].key, "A")
	assert_eq(pad[SessionAction.RECORD].style, ButtonPrompt.STYLE_FACE_A)
	assert_eq(pad[SessionAction.RETRY_TAKE].style, ButtonPrompt.STYLE_FACE_X)
	assert_eq(pad[SessionAction.SPEED_UP].style, ButtonPrompt.STYLE_SHOULDER)
	assert_eq(pad[SessionAction.QUIT].key, "Start")


func test_bindings_are_installed_in_the_input_map() -> void:
	_rig()
	assert_true(InputMap.has_action(&"od_dodge"))
	assert_true(InputMap.has_action(&"od_resetAll"))
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	assert_true(InputMap.event_is_action(space, &"od_dodge"))
	assert_true(InputMap.event_is_action(space, &"od_accept"))
	assert_false(InputMap.event_is_action(space, &"od_pause"))
	var rt := InputEventJoypadMotion.new()
	rt.axis = JOY_AXIS_TRIGGER_RIGHT
	rt.axis_value = 1.0
	assert_true(InputMap.event_is_action(rt, &"od_light"))


func test_dispose_stops_listening() -> void:
	var r := _rig()
	r.dispose()
	_press(r, KEY_SPACE)
	assert_false(r.sample(UP).dodge)
