class_name MenuHost
extends RefCounted
## Binds a MenuSource to a focus cursor (prototype ui/menus/nav.ts MenuHost + moveFocus). After every
## command the menu is re-read from the source, because accepting an entry may change the screen's
## local state (open a list, show a confirm). Focus ids are Strings; "" = no focus.

## Navigation commands: UiBase.NAV_UP / NAV_DOWN / NAV_LEFT / NAV_RIGHT / NAV_ACCEPT / NAV_BACK.

var _source: MenuSource
var _def: MenuDef = MenuDef.new()
var _cur: String = ""
## Notified with the focus id when focus moves or the definition was re-read.
var _on_change: Callable


func _init(source: MenuSource, on_change: Callable = Callable()) -> void:
	_source = source
	_on_change = on_change
	refresh()


var focus: String:
	get:
		return _cur


var entries: Array[MenuEntry]:
	get:
		return _def.entries


var definition: MenuDef:
	get:
		return _def


## Re-read the menu from the source, keeping focus where possible.
func refresh() -> void:
	_def = _source.menu()
	var req := _source.take_focus_request()
	var next := _cur
	if not req.is_empty() and _def.has(req):
		next = req
	if next.is_empty() or not _def.has(next):
		var d := _def.default_focus
		if not d.is_empty() and _def.has(d):
			next = d
		else:
			next = ""
			for e in _def.entries:
				if not e.disabled:
					next = e.id
					break
			if next.is_empty() and not _def.entries.is_empty():
				next = _def.entries[0].id
	_set_focus(next, false)
	if _on_change.is_valid():
		_on_change.call(_cur)


func navigate(cmd: StringName) -> void:
	var entry := _def.find(_cur)
	if cmd == UiBase.NAV_ACCEPT:
		if entry != null and not entry.disabled and entry.accept.is_valid():
			entry.accept.call()
		refresh()
		return
	if cmd == UiBase.NAV_BACK:
		if _def.back.is_valid():
			_def.back.call()
		refresh()
		return
	if (cmd == UiBase.NAV_LEFT or cmd == UiBase.NAV_RIGHT) and entry != null and entry.has_adjust() and not entry.disabled:
		entry.adjust.call(1 if cmd == UiBase.NAV_RIGHT else -1)
		refresh()
		return
	if not (cmd == UiBase.NAV_UP or cmd == UiBase.NAV_DOWN or cmd == UiBase.NAV_LEFT or cmd == UiBase.NAV_RIGHT):
		return
	var next := move_focus(_def.entries, _cur, cmd)
	if next != _cur:
		_set_focus(next, true)
		refresh()


## Mouse hover: focus follows the pointer so the details panels track what is under it.
func hover(id: String) -> void:
	if id == _cur or _def.find(id) == null:
		return
	_set_focus(id, true)
	refresh()


## Mouse click: identical to focusing the entry and pressing accept.
func click(id: String) -> void:
	if _def.find(id) == null:
		return
	if id != _cur:
		_set_focus(id, true)
	navigate(UiBase.NAV_ACCEPT)


## Mouse on a slider / stepper: identical to left/right on that entry.
func adjust(id: String, delta: int) -> void:
	var e := _def.find(id)
	if e == null or e.disabled or not e.has_adjust():
		return
	if id != _cur:
		_set_focus(id, true)
	e.adjust.call(-1 if delta < 0 else 1)
	refresh()


func _set_focus(id: String, notify: bool) -> void:
	var changed := id != _cur
	_cur = id
	if changed and notify:
		var e := _def.find(id)
		if e != null and e.focused.is_valid():
			e.focused.call()


## Pure focus movement. Up/down go to the nearest populated row in that direction and pick the entry
## whose column is closest (ties prefer the lower column, which keeps "down" from a wide button row
## landing on the leftmost choice). Left/right stay on the current row. There is no wrap-around:
## wrapping in a vertical descent list would teleport from the time machine back to the surface.
## Returns "" only for an empty list.
static func move_focus(items: Array[MenuEntry], current: String, dir: StringName) -> String:
	if items.is_empty():
		return ""
	var from: MenuEntry = null
	if not current.is_empty():
		for it in items:
			if it.id == current:
				from = it
				break
	if from == null:
		return items[0].id

	if from.links.has(dir):
		var link: String = from.links[dir]
		for it in items:
			if it.id == link:
				return link

	if dir == UiBase.NAV_LEFT or dir == UiBase.NAV_RIGHT:
		var sign_h := 1 if dir == UiBase.NAV_RIGHT else -1
		var best_h: MenuEntry = null
		for it in items:
			if it == from or it.row != from.row:
				continue
			var d := (it.col - from.col) * sign_h
			if d <= 0:
				continue
			if best_h == null or d < (best_h.col - from.col) * sign_h:
				best_h = it
		return best_h.id if best_h != null else from.id

	var sign_v := 1 if dir == UiBase.NAV_DOWN else -1
	var has_target := false
	var target_row := 0
	for it in items:
		var d := (it.row - from.row) * sign_v
		if d <= 0:
			continue
		if not has_target or d < (target_row - from.row) * sign_v:
			target_row = it.row
			has_target = true
	if not has_target:
		return from.id
	var best: MenuEntry = null
	for it in items:
		if it.row != target_row:
			continue
		if best == null:
			best = it
			continue
		var dc := absi(it.col - from.col)
		var bd := absi(best.col - from.col)
		if dc < bd or (dc == bd and it.col < best.col):
			best = it
	return best.id if best != null else from.id
