class_name MenuNavItem
extends PanelContainer
## A focusable menu element (prototype: any element carrying data-nav). Shows the one shared focus
## look when `focused`, reports hover and click to the menu controller, and never takes Godot
## keyboard focus: the game owns the keys and drives focus through UiBase.navigate().

signal hovered(nav_id: String)
signal clicked(nav_id: String)

var nav_id: String = ""
var style_normal: StyleBox = StyleBoxEmpty.new()
var style_focus: StyleBox = StyleBoxEmpty.new()
## Optional: func(focused: bool) -> void, recolours children when focus changes.
var restyle: Callable = Callable()
var focused: bool = false


static func make(p_nav: String, p_normal: StyleBox, p_focus: StyleBox, p_restyle: Callable = Callable()) -> MenuNavItem:
	var n := MenuNavItem.new()
	n.nav_id = p_nav
	n.style_normal = p_normal
	n.style_focus = p_focus
	n.restyle = p_restyle
	return n


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	# PASS: hover and clicks reach us, the wheel still scrolls the list we sit in.
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void: hovered.emit(nav_id))


func _ready() -> void:
	_apply()


func set_focused(f: bool) -> void:
	if f == focused and is_inside_tree():
		return
	focused = f
	_apply()


func _apply() -> void:
	add_theme_stylebox_override("panel", style_focus if focused else style_normal)
	if restyle.is_valid():
		restyle.call(focused)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		accept_event()
		clicked.emit(nav_id)
