class_name MenuScreenView
extends RefCounted
## Builds one menu screen's Controls (prototype ui/menus/views.ts ScreenView). Views read logic state
## and models; they never emit intents themselves. Every interactive element is a MenuNavItem whose
## nav_id matches a MenuEntry id; MenuController routes the pointer through the same MenuHost the
## keyboard / gamepad uses.

var ctl: MenuController


func _init(p_ctl: MenuController) -> void:
	ctl = p_ctl


## Structural key: when it changes the screen is rebuilt; otherwise only focus / patches apply.
func key() -> String:
	return ""


## A full-rect Control holding the whole screen.
func build() -> Control:
	return Control.new()


## Called after every focus move / model echo to update dependent regions in place.
func sync(_root: Control, _focus: String) -> void:
	pass


## Full-rect screen root that swallows the mouse so clicks never fall through to the world.
static func screen_root(name: String) -> Control:
	var c := Control.new()
	c.name = name
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	return c


## Bottom-left prompts strip anchored to a screen root.
func add_prompts(root: Control, extra: Array[String] = []) -> HBoxContainer:
	var p := MenuWidgets.prompts(ctl.device, extra)
	p.name = "Prompts"
	p.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 28)
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(p)
	return p


## A centred column of fixed width filling the screen height (for panels that size to content).
static func centred(root: Control, child: Control, width: float) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	child.custom_minimum_size.x = width
	cc.add_child(child)
	root.add_child(cc)
	return cc
