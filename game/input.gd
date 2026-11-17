class_name GameInput
extends RefCounted
## Keyboard + mouse + gamepad → PlayerInput (one per local tick) and session / menu actions (port of
## prototype/src/game/input.ts, the contracts.ts IInput facade). Bindings live in one table
## (BINDINGS), installed into Godot's InputMap as actions named "od_<id>", so HUD prompts and the
## InputMap come from the same place (describe_binding(), prompts()). Final bindings are an open
## decision (OPEN-20); these are conventional twin-stick / WASD + mouse defaults.
##
## The app forwards every InputEvent to handle_event() (from _unhandled_input, so clicks on UI
## controls never reach it). Nothing here reads global Input state, so tests drive it with synthetic
## events and an injected clock.
##
## Edge semantics: a button press is reported exactly once, on the next sample (gameplay) or drain
## (actions) after it went down, even if it was released again before that. Key echo never
## re-triggers. Losing focus (release_all) releases everything, so a key held while alt-tabbing never
## sticks.
##
## Hold-to-confirm: resetAll (hold Backspace / Delete, or Back / Y on a pad) fires once after
## RESET_HOLD_SECONDS; skipCinematic (hold Enter / Space / Esc, or A / B / Start) fires once after
## SKIP_HOLD_SECONDS. hold_progress() feeds the HUD's confirm ring.

const RESET_HOLD_SECONDS: float = 0.9
## Hold time before a winning cinematic is skipped (CINE-02: it cannot be skipped by accident).
const SKIP_HOLD_SECONDS: float = 0.6
## With no mouse movement for this long, aim follows the movement direction instead.
const MOUSE_AIM_TIMEOUT: float = 1.5
const STICK_DEADZONE: float = 0.22
const AIM_STICK_THRESHOLD: float = 0.35
const NAV_STICK_THRESHOLD: float = 0.6
## Trigger travel that counts as a press.
const TRIGGER_THRESHOLD: float = 0.5
## Prefix of the InputMap action names.
const ACTION_PREFIX: String = "od_"

const DEVICE_KEYBOARD: StringName = &"keyboard"
const DEVICE_GAMEPAD: StringName = &"gamepad"

# Binding ids (prototype BindingId): gameplay buttons use ActionKind spellings, session actions use
# SessionAction spellings, plus movement / aim, menu navigation, pause and skipCinematic.
const MOVE: StringName = &"move"
const MOVE_UP: StringName = &"moveUp"
const MOVE_DOWN: StringName = &"moveDown"
const MOVE_LEFT: StringName = &"moveLeft"
const MOVE_RIGHT: StringName = &"moveRight"
const AIM: StringName = &"aim"
const NAV_UP: StringName = &"up"
const NAV_DOWN: StringName = &"down"
const NAV_LEFT: StringName = &"left"
const NAV_RIGHT: StringName = &"right"
const ACCEPT: StringName = &"accept"
const BACK: StringName = &"back"
const PAUSE: StringName = &"pause"
## Port addition: hold to skip the winning cinematic (no other input affects it; CINE-02).
const SKIP_CINEMATIC: StringName = &"skipCinematic"

const GAMEPLAY: Array[StringName] = [ActionKind.LIGHT, ActionKind.HEAVY, ActionKind.DODGE, ActionKind.RANGED, ActionKind.INTERACT, ActionKind.ABILITY]
## Session actions triggered by the context-sensitive 'accept' binding.
const ACCEPT_ALIASES: Array[StringName] = [SessionAction.START, SessionAction.RECORD, SessionAction.SKIP, SessionAction.CONTINUE, SessionAction.COMMIT]
const MOVE_VECTORS: Dictionary[StringName, Vector2] = {
	MOVE_UP: Vector2(0, 1),
	MOVE_DOWN: Vector2(0, -1),
	MOVE_LEFT: Vector2(-1, 0),
	MOVE_RIGHT: Vector2(1, 0),
}

const KEY_NAMES: Dictionary[int, String] = {
	KEY_SPACE: "Space",
	KEY_ENTER: "Enter",
	KEY_KP_ENTER: "Enter",
	KEY_ESCAPE: "Esc",
	KEY_TAB: "Tab",
	KEY_BACKSPACE: "Backspace",
	KEY_DELETE: "Del",
	KEY_SHIFT: "Shift",
	KEY_UP: "↑",
	KEY_DOWN: "↓",
	KEY_LEFT: "←",
	KEY_RIGHT: "→",
}
## Godot JoyButton index → prompt text.
const PAD_NAMES: Array[String] = ["A", "B", "X", "Y", "Back", "Guide", "Start", "LS", "RS", "LB", "RB", "D-pad ↑", "D-pad ↓", "D-pad ←", "D-pad →"]
const PAD_STYLES: Dictionary[int, StringName] = {
	JOY_BUTTON_A: ButtonPrompt.STYLE_FACE_A,
	JOY_BUTTON_B: ButtonPrompt.STYLE_FACE_B,
	JOY_BUTTON_X: ButtonPrompt.STYLE_FACE_X,
	JOY_BUTTON_Y: ButtonPrompt.STYLE_FACE_Y,
	JOY_BUTTON_LEFT_SHOULDER: ButtonPrompt.STYLE_SHOULDER,
	JOY_BUTTON_RIGHT_SHOULDER: ButtonPrompt.STYLE_SHOULDER,
	JOY_BUTTON_BACK: ButtonPrompt.STYLE_MENU,
	JOY_BUTTON_START: ButtonPrompt.STYLE_MENU,
}


## One row of the binding table.
class Binding:
	extends RefCounted
	var id: StringName = &""
	## Physical keycodes.
	var keys: Array[int] = []
	## MouseButton indices.
	var mouse: Array[int] = []
	## JoyButton indices.
	var pad: Array[int] = []
	## JoyAxis indices pressed at positive travel (triggers).
	var pad_axes: Array[int] = []
	## Fires only after being held this long (seconds); 0 = on press.
	var hold_seconds: float = 0.0
	## Prompt text per device when the binding is not a plain key / button (sticks, mouse).
	var label: Dictionary[StringName, String] = {}

	static func make(p_id: StringName, p_keys: Array[int], p_mouse: Array[int], p_pad: Array[int], p_axes: Array[int] = [], p_hold: float = 0.0, p_label: Dictionary = {}) -> Binding:
		var b := Binding.new()
		b.id = p_id
		b.keys = p_keys
		b.mouse = p_mouse
		b.pad = p_pad
		b.pad_axes = p_axes
		b.hold_seconds = p_hold
		for k: Variant in p_label:
			b.label[StringName(k)] = String(p_label[k])
		return b

	func action_name() -> StringName:
		return StringName(GameInput.ACTION_PREFIX + String(id))


class HoldState:
	extends RefCounted
	var binding: Binding = null
	var since: float = 0.0
	var fired: bool = false
	var source: String = ""


## The binding table, in prototype order (+ the four move directions and skipCinematic).
static var BINDINGS: Array[Binding] = _build_bindings()

static var _installed: bool = false


static func _build_bindings() -> Array[Binding]:
	var none: Array[int] = []
	var out: Array[Binding] = []
	# ── gameplay (sampled each local tick) ──
	out.append(Binding.make(MOVE, none, none, none, none, 0.0, {DEVICE_KEYBOARD: "WASD", DEVICE_GAMEPAD: "Left stick"}))
	out.append(Binding.make(MOVE_UP, [KEY_W, KEY_UP], none, none))
	out.append(Binding.make(MOVE_DOWN, [KEY_S, KEY_DOWN], none, none))
	out.append(Binding.make(MOVE_LEFT, [KEY_A, KEY_LEFT], none, none))
	out.append(Binding.make(MOVE_RIGHT, [KEY_D, KEY_RIGHT], none, none))
	out.append(Binding.make(AIM, none, none, none, none, 0.0, {DEVICE_KEYBOARD: "Mouse", DEVICE_GAMEPAD: "Right stick"}))
	out.append(Binding.make(ActionKind.LIGHT, none, [MOUSE_BUTTON_LEFT], [JOY_BUTTON_X], [JOY_AXIS_TRIGGER_RIGHT], 0.0, {DEVICE_KEYBOARD: "Left click"}))
	out.append(Binding.make(ActionKind.HEAVY, none, [MOUSE_BUTTON_RIGHT], [JOY_BUTTON_Y], [JOY_AXIS_TRIGGER_LEFT], 0.0, {DEVICE_KEYBOARD: "Right click"}))
	out.append(Binding.make(ActionKind.DODGE, [KEY_SPACE], none, [JOY_BUTTON_A]))
	out.append(Binding.make(ActionKind.INTERACT, [KEY_E], none, [JOY_BUTTON_B]))
	out.append(Binding.make(ActionKind.RANGED, [KEY_Q, KEY_F], none, [JOY_BUTTON_RIGHT_SHOULDER]))
	out.append(Binding.make(ActionKind.ABILITY, [KEY_SHIFT], none, [JOY_BUTTON_LEFT_SHOULDER]))
	# ── menu navigation ──
	out.append(Binding.make(NAV_UP, [KEY_UP, KEY_W], none, [JOY_BUTTON_DPAD_UP]))
	out.append(Binding.make(NAV_DOWN, [KEY_DOWN, KEY_S], none, [JOY_BUTTON_DPAD_DOWN]))
	out.append(Binding.make(NAV_LEFT, [KEY_LEFT, KEY_A], none, [JOY_BUTTON_DPAD_LEFT]))
	out.append(Binding.make(NAV_RIGHT, [KEY_RIGHT, KEY_D], none, [JOY_BUTTON_DPAD_RIGHT]))
	out.append(Binding.make(ACCEPT, [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE], none, [JOY_BUTTON_A]))
	# Esc is bound to 'pause' only; the app reads 'pause' as "back" on menu screens, so one key press
	# never produces both a back and a pause in the same batch.
	out.append(Binding.make(BACK, none, none, [JOY_BUTTON_B], none, 0.0, {DEVICE_KEYBOARD: "Esc"}))
	out.append(Binding.make(PAUSE, [KEY_ESCAPE, KEY_P], none, [JOY_BUTTON_START]))
	# ── session ──
	out.append(Binding.make(SessionAction.SPEED_DOWN, [KEY_Q], none, [JOY_BUTTON_LEFT_SHOULDER]))
	out.append(Binding.make(SessionAction.SPEED_UP, [KEY_E], none, [JOY_BUTTON_RIGHT_SHOULDER]))
	out.append(Binding.make(SessionAction.CYCLE_END_MODE, [KEY_TAB], none, [JOY_BUTTON_Y]))
	out.append(Binding.make(SessionAction.RETRY_TAKE, [KEY_R], none, [JOY_BUTTON_X]))
	out.append(Binding.make(SessionAction.COMMIT, [KEY_C], none, none))
	out.append(Binding.make(SessionAction.END_ATTEMPT, [KEY_BACKSPACE, KEY_DELETE], none, [JOY_BUTTON_B]))
	out.append(Binding.make(SessionAction.RESET_ALL, [KEY_BACKSPACE, KEY_DELETE], none, [JOY_BUTTON_BACK, JOY_BUTTON_Y], none, RESET_HOLD_SECONDS))
	out.append(Binding.make(SKIP_CINEMATIC, [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE], none, [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_START], none, SKIP_HOLD_SECONDS))
	return out


static func binding(id: StringName) -> Binding:
	for b: Binding in BINDINGS:
		if b.id == id:
			return b
	return null


## Register every binding as an InputMap action ("od_<id>") with its key / mouse / pad events.
## Idempotent; called by the constructor.
static func install_input_map() -> void:
	if _installed:
		return
	_installed = true
	for b: Binding in BINDINGS:
		var name := b.action_name()
		if InputMap.has_action(name):
			InputMap.action_erase_events(name)
		else:
			InputMap.add_action(name, TRIGGER_THRESHOLD)
		for k: int in b.keys:
			var e := InputEventKey.new()
			e.physical_keycode = k as Key
			InputMap.action_add_event(name, e)
		for m: int in b.mouse:
			var e := InputEventMouseButton.new()
			e.button_index = m as MouseButton
			InputMap.action_add_event(name, e)
		for p: int in b.pad:
			var e := InputEventJoypadButton.new()
			e.button_index = p as JoyButton
			e.device = -1
			InputMap.action_add_event(name, e)
		for a: int in b.pad_axes:
			var e := InputEventJoypadMotion.new()
			e.axis = a as JoyAxis
			e.axis_value = 1.0
			e.device = -1
			InputMap.action_add_event(name, e)


static func _key_name(code: int) -> String:
	if KEY_NAMES.has(code):
		return KEY_NAMES[code]
	return OS.get_keycode_string(code as Key)


static func _pad_name(i: int) -> String:
	return PAD_NAMES[i] if i >= 0 and i < PAD_NAMES.size() else "Button %d" % i


## Prompt text for an action on a device ("Space", "Hold Backspace", "RB", "Left click").
## Accept-driven session actions (record, skip, …) describe the accept binding unless they have their
## own. Returns "" for an action with no binding on that device.
static func describe_binding(id: StringName, device: StringName, p_press_twice: bool = false) -> String:
	var b := binding(id)
	var own := false
	if b != null:
		own = (not b.keys.is_empty() or not b.mouse.is_empty()) if device == DEVICE_KEYBOARD else (not b.pad.is_empty() or not b.pad_axes.is_empty())
	if (b == null or not own) and ACCEPT_ALIASES.has(id):
		b = binding(ACCEPT)
	if b == null:
		return ""
	# In press-twice mode the armable holds are plain presses, so their prompt drops the "Hold".
	var hold := "Hold " if b.hold_seconds > 0.0 and not (p_press_twice and PRESS_TWICE_IDS.has(b.id)) else ""
	if b.label.has(device):
		return hold + b.label[device]
	if device == DEVICE_KEYBOARD:
		return hold + _key_name(b.keys[0]) if not b.keys.is_empty() else ""
	if not b.pad.is_empty():
		return hold + _pad_name(b.pad[0])
	if not b.pad_axes.is_empty():
		return hold + ("RT" if b.pad_axes[0] == JOY_AXIS_TRIGGER_RIGHT else "LT")
	return ""


## The ButtonPrompt map for UiBase.set_bindings(): every SessionAction and gameplay ActionKind, plus
## pause and skipCinematic, described for `device` (and for the press-twice hold mode when set).
static func prompts(device: StringName, p_press_twice: bool = false) -> Dictionary[StringName, ButtonPrompt]:
	var out: Dictionary[StringName, ButtonPrompt] = {}
	var ids: Array[StringName] = []
	ids.append_array(SessionAction.ALL)
	ids.append_array(GAMEPLAY)
	ids.append_array([PAUSE, SKIP_CINEMATIC, MOVE, AIM])
	for id: StringName in ids:
		var text := describe_binding(id, device, p_press_twice)
		if text == "" and id == SessionAction.QUIT:
			text = describe_binding(PAUSE, device)
		if text == "":
			continue
		var style := ButtonPrompt.STYLE_KEY
		if device == DEVICE_GAMEPAD:
			var b := binding(id)
			if b == null or b.pad.is_empty():
				b = binding(ACCEPT) if ACCEPT_ALIASES.has(id) else (binding(PAUSE) if id == SessionAction.QUIT else b)
			if b != null and not b.pad.is_empty():
				style = PAD_STYLES.get(b.pad[0], ButtonPrompt.STYLE_KEY)
		out[id] = ButtonPrompt.make(text, style)
	return out

# ───────────────────────────── instance state ─────────────────────────────

## Wall clock in seconds (injectable for tests). Default: Time.get_ticks_usec.
var now_fn: Callable = Callable()
## Viewport position → floor point (sim axes); normally WorldViewBase.screen_to_world. Invalid = none.
var screen_to_world: Callable = Callable()

## Sources (e.g. "key:87", "mouse:1", "pad:2", "axis:5") currently held, → true.
var _down: Dictionary[String, bool] = {}
## Held move sources → direction.
var _move: Dictionary[String, Vector2] = {}
var _latched: Dictionary[StringName, bool] = {}
var _queue: Array[StringName] = []
var _holds: Dictionary[String, HoldState] = {}
var _device: StringName = DEVICE_KEYBOARD
var _last_aim: float = 0.0
var _has_mouse: bool = false
var _mouse_pos: Vector2 = Vector2.ZERO
var _mouse_t: float = 0.0
var _axes: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _nav_prev: Vector2i = Vector2i.ZERO
var _disposed: bool = false
## Accessibility "hold actions: press twice" (SaveSettings.hold_mode == "press"): a hold-to-confirm
## in PRESS_TWICE_IDS is armed by the first press and confirmed by a second within PRESS_ARM_SECONDS;
## any other press disarms it. Bindings that share the confirming key or button (Backspace is also
## endAttempt, pad Y is also cycleEndMode) still fire as usual and do not count as "another press":
## the session only accepts them in phases that never offer the armed action. The cinematic skip
## stays hold-only (CINE-02).
var press_twice: bool = false
## Binding id -> wall time it was armed.
var _armed: Dictionary[StringName, float] = {}

const PRESS_ARM_SECONDS: float = 3.0
const PRESS_TWICE_IDS: Array[StringName] = [SessionAction.RESET_ALL]


func _init(p_now: Callable = Callable(), p_screen_to_world: Callable = Callable()) -> void:
	install_input_map()
	now_fn = p_now
	screen_to_world = p_screen_to_world


func _now() -> float:
	if now_fn.is_valid():
		return float(now_fn.call())
	return Time.get_ticks_usec() / 1_000_000.0


## The bindings (InputMap actions) an event matches, in table order.
func _bindings_for(ev: InputEvent) -> Array[Binding]:
	var out: Array[Binding] = []
	for b: Binding in BINDINGS:
		if InputMap.event_is_action(ev, b.action_name(), false):
			out.append(b)
	return out


func _armable(b: Binding) -> bool:
	return press_twice and b.hold_seconds > 0.0 and PRESS_TWICE_IDS.has(b.id)


## `keep_arm`: this press comes from a source that also carries an armable binding, so it must not
## cancel the arm that the same press sets or confirms.
func _press(b: Binding, source: String, keep_arm: bool = false) -> void:
	if _armable(b):
		var t := _now()
		if _armed.has(b.id) and t - _armed[b.id] <= PRESS_ARM_SECONDS:
			_armed.erase(b.id)
			_queue.append(b.id)
		else:
			_armed.clear()
			_armed[b.id] = t
		return
	if not keep_arm and not _armed.is_empty() and not MOVE_VECTORS.has(b.id) and b.id != MOVE and b.id != AIM:
		_armed.clear()
	if b.hold_seconds > 0.0:
		var key := source + "|" + String(b.id)
		if not _holds.has(key):
			var h := HoldState.new()
			h.binding = b
			h.since = _now()
			h.source = source
			_holds[key] = h
		return
	if MOVE_VECTORS.has(b.id):
		_move[source + "|" + String(b.id)] = MOVE_VECTORS[b.id]
		return
	if GAMEPLAY.has(b.id):
		_latched[b.id] = true
	elif b.id != MOVE and b.id != AIM:
		_queue.append(b.id)


func _release_source(source: String) -> void:
	_down.erase(source)
	for k: String in _holds.keys():
		if _holds[k].source == source:
			_holds.erase(k)
	for k: String in _move.keys():
		if k.begins_with(source + "|"):
			_move.erase(k)


func _source_down(source: String, list: Array[Binding]) -> void:
	if _down.has(source):
		return
	_down[source] = true
	var keep_arm := false
	for b: Binding in list:
		if _armable(b):
			keep_arm = true
	for b: Binding in list:
		_press(b, source, keep_arm)


## Feed one InputEvent (the app forwards _unhandled_input here). Returns true when the event is bound
## (the caller may mark it handled).
func handle_event(ev: InputEvent) -> bool:
	if _disposed or ev == null:
		return false
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var code := int(k.physical_keycode) if k.physical_keycode != KEY_NONE else int(k.keycode)
		var source := "key:%d" % code
		if not k.pressed:
			_release_source(source)
			return false
		if k.ctrl_pressed or k.meta_pressed or k.alt_pressed:
			return false
		var list := _bindings_for(k)
		if list.is_empty():
			return false
		_device = DEVICE_KEYBOARD
		if k.echo:
			return true
		_source_down(source, list)
		return true
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		var source := "mouse:%d" % mb.button_index
		if not mb.pressed:
			_release_source(source)
			return false
		var list := _bindings_for(mb)
		_device = DEVICE_KEYBOARD
		if list.is_empty():
			return false
		_source_down(source, list)
		return true
	if ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		_has_mouse = true
		_mouse_pos = mm.position
		_mouse_t = _now()
		_device = DEVICE_KEYBOARD
		return false
	if ev is InputEventJoypadButton:
		var jb := ev as InputEventJoypadButton
		var source := "pad:%d" % jb.button_index
		if not jb.pressed:
			_release_source(source)
			return false
		_device = DEVICE_GAMEPAD
		var list := _bindings_for(jb)
		_source_down(source, list)
		return not list.is_empty()
	if ev is InputEventJoypadMotion:
		var jm := ev as InputEventJoypadMotion
		var axis := int(jm.axis)
		if axis >= 0 and axis < 4:
			_axes[axis] = jm.axis_value
			var sticks := _sticks()
			if sticks != Vector4.ZERO:
				_device = DEVICE_GAMEPAD
			_stick_nav(sticks)
			return false
		var source := "axis:%d" % axis
		if jm.axis_value >= TRIGGER_THRESHOLD:
			_device = DEVICE_GAMEPAD
			var list := _bindings_for(jm)
			_source_down(source, list)
			return not list.is_empty()
		_release_source(source)
		return false
	return false


## Left stick doubles as menu navigation: one step each time it crosses the threshold.
func _stick_nav(s: Vector4) -> void:
	var nx := int(signf(s.x)) if absf(s.x) >= NAV_STICK_THRESHOLD else 0
	var ny := int(signf(s.y)) if absf(s.y) >= NAV_STICK_THRESHOLD else 0
	if nx != 0 and nx != _nav_prev.x:
		_queue.append(NAV_RIGHT if nx > 0 else NAV_LEFT)
	if ny != 0 and ny != _nav_prev.y:
		_queue.append(NAV_DOWN if ny > 0 else NAV_UP)
	_nav_prev = Vector2i(nx, ny)


static func _deadzone(x: float, y: float, dz: float) -> Vector2:
	var m := sqrt(x * x + y * y)
	if m < dz:
		return Vector2.ZERO
	var k := minf(1.0, (m - dz) / (1.0 - dz)) / m
	return Vector2(x * k, y * k)


## (lx, ly, rx, ry) after the dead zone.
func _sticks() -> Vector4:
	var l := _deadzone(_axes[0], _axes[1], STICK_DEADZONE)
	var r := _deadzone(_axes[2], _axes[3], STICK_DEADZONE)
	return Vector4(l.x, l.y, r.x, r.y)


func _check_holds() -> void:
	var t := _now()
	for h: HoldState in _holds.values():
		if not h.fired and t - h.since >= h.binding.hold_seconds:
			h.fired = true
			_queue.append(h.binding.id)


## One local tick of gameplay input. `screen_up` is the world-space (sim axes) direction screen-up
## maps to (WorldViewBase.screen_up_in_world); `actor_pos` is the live self's position, or null.
func sample(screen_up: Vector2, actor_pos: Variant = null) -> PlayerInput:
	_check_holds()
	var sticks := _sticks()
	# Screen axes in world space. Screen right is screen up turned a quarter clockwise in sim axes
	# (x right, y down, viewed from above), which holds for any rotation of the iso camera.
	var ul := sqrt(screen_up.x * screen_up.x + screen_up.y * screen_up.y)
	if ul == 0.0:
		ul = 1.0
	var ux := screen_up.x / ul
	var uy := screen_up.y / ul
	var rx := -uy
	var ry := ux
	var sum := Vector2.ZERO
	for v: Vector2 in _move.values():
		sum += v
	var sx := signf(sum.x)
	var sy := signf(sum.y)
	if sticks.x != 0.0 or sticks.y != 0.0:
		sx = sticks.x
		sy = -sticks.y
	var mx := rx * sx + ux * sy
	var my := ry * sx + uy * sy
	var ml := sqrt(mx * mx + my * my)
	if ml > 1.0:
		mx /= ml
		my /= ml
	var moving := ml > 1e-6

	var aim := _last_aim
	var t := _now()
	var has_actor := actor_pos is Vector2
	var apos: Vector2 = actor_pos if has_actor else Vector2.ZERO
	if _device == DEVICE_GAMEPAD:
		if sqrt(sticks.z * sticks.z + sticks.w * sticks.w) >= AIM_STICK_THRESHOLD:
			var ax := rx * sticks.z + ux * -sticks.w
			var ay := ry * sticks.z + uy * -sticks.w
			aim = atan2(ay, ax)
		elif moving:
			aim = atan2(my, mx)
	else:
		var can_point := _has_mouse and screen_to_world.is_valid() and has_actor
		var recent := _has_mouse and t - _mouse_t <= MOUSE_AIM_TIMEOUT
		if recent and can_point:
			aim = _aim_at_pointer(apos, aim)
		elif moving:
			aim = atan2(my, mx)
		elif can_point:
			# Standing still with an idle mouse: keep pointing where the cursor rests.
			aim = _aim_at_pointer(apos, aim)
	if is_nan(aim) or is_inf(aim):
		aim = _last_aim
	_last_aim = aim

	var out := PlayerInput.make(mx, my, aim)
	out.light = _latched.has(ActionKind.LIGHT)
	out.heavy = _latched.has(ActionKind.HEAVY)
	out.dodge = _latched.has(ActionKind.DODGE)
	out.ranged = _latched.has(ActionKind.RANGED)
	out.interact = _latched.has(ActionKind.INTERACT)
	out.ability = _latched.has(ActionKind.ABILITY)
	_latched.clear()
	return out


func _aim_at_pointer(apos: Vector2, fallback: float) -> float:
	var w: Variant = screen_to_world.call(_mouse_pos)
	if not (w is Vector2):
		return fallback
	var dx: float = (w as Vector2).x - apos.x
	var dy: float = (w as Vector2).y - apos.y
	return atan2(dy, dx) if sqrt(dx * dx + dy * dy) > 0.05 else fallback


## Queued session / menu actions (binding ids) since the last drain, in press order.
func drain_actions() -> Array[StringName]:
	_check_holds()
	var out := _queue
	_queue = []
	return out


## DEVICE_KEYBOARD / DEVICE_GAMEPAD: whichever was used last.
func device() -> StringName:
	return _device


## Forget presses that happened before now (call when a take starts, so the record press is not a
## dodge).
func clear_presses() -> void:
	_latched.clear()
	_queue.clear()


## Forget holds in progress (call when the cinematic starts, so a button already held from the take
## cannot skip it); the button must be pressed again.
func cancel_holds() -> void:
	_holds.clear()
	_armed.clear()


## Drop a press-twice arm without touching holds in progress (the armed action is not on offer, or
## the hold mode changed).
func disarm() -> void:
	_armed.clear()


## True while `id` is armed by a first press (press-twice mode) and waiting for the second.
func is_armed(id: StringName) -> bool:
	return _armed.has(id) and _now() - _armed[id] <= PRESS_ARM_SECONDS


## 0..1 progress of a hold-to-confirm currently being held (only `id`'s when given); 0 when none.
func hold_progress(id: StringName = &"") -> float:
	var t := _now()
	var best := 0.0
	for a: StringName in _armed.keys():
		if t - _armed[a] > PRESS_ARM_SECONDS:
			_armed.erase(a)
		elif id == &"" or a == id:
			best = 1.0
	for h: HoldState in _holds.values():
		if h.fired or (id != &"" and h.binding.id != id):
			continue
		best = maxf(best, minf(1.0, (t - h.since) / h.binding.hold_seconds))
	return best


## Losing focus / a pad disconnecting: release every key, button and stick.
func release_all() -> void:
	_down.clear()
	_move.clear()
	_holds.clear()
	_armed.clear()
	_latched.clear()
	_axes = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	_nav_prev = Vector2i.ZERO


func dispose() -> void:
	release_all()
	_queue.clear()
	_disposed = true
