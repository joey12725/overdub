class_name MenuEntry
extends RefCounted
## One focusable cell of a menu (prototype ui/menus/nav.ts NavItem + MenuEntry).
##
## Menus are laid out on a loose grid (row, col). Keyboard / gamepad navigation moves between
## neighbouring cells; the mouse focuses (hover) and activates (click) entries by id. Both paths go
## through the same MenuHost, so a click and an "accept" can never behave differently.

var id: String = ""
var row: int = 0
var col: int = 0
## Focusable (so it can be read, e.g. a locked level) but accept does nothing.
var disabled: bool = false
## Explicit neighbours that override the geometric search: UiBase.NAV_UP/DOWN/LEFT/RIGHT -> entry id.
var links: Dictionary[StringName, String] = {}
## Accept / click. Empty Callable = nothing happens.
var accept: Callable = Callable()
## Left / right on this entry adjusts a value instead of moving focus (sliders, toggles).
## Called with an int delta of -1 or +1.
var adjust: Callable = Callable()
## Called when the entry gains focus (hover or keyboard).
var focused: Callable = Callable()


static func make(p_id: String, p_row: int, p_col: int, p_accept: Callable = Callable()) -> MenuEntry:
	var e := MenuEntry.new()
	e.id = p_id
	e.row = p_row
	e.col = p_col
	e.accept = p_accept
	return e


## Chainable: add an explicit neighbour.
func link(dir: StringName, target: String) -> MenuEntry:
	links[dir] = target
	return self


## Chainable: set the focus callback.
func on_focus(fn: Callable) -> MenuEntry:
	focused = fn
	return self


## Chainable: set the adjust callback.
func on_adjust(fn: Callable) -> MenuEntry:
	adjust = fn
	return self


func has_adjust() -> bool:
	return adjust.is_valid()
