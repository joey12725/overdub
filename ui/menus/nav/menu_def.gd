class_name MenuDef
extends RefCounted
## A screen's current menu (prototype ui/menus/nav.ts MenuDef): its entries, what "back" does and
## where focus goes when the current focus no longer exists.

var entries: Array[MenuEntry] = []
## Back / cancel. Empty Callable = back does nothing.
var back: Callable = Callable()
## Focus used when the current focus no longer exists in this definition; "" = none.
var default_focus: String = ""


static func make(p_entries: Array[MenuEntry], p_back: Callable = Callable(), p_default: String = "") -> MenuDef:
	var d := MenuDef.new()
	d.entries = p_entries
	d.back = p_back
	d.default_focus = p_default
	return d


func find(id: String) -> MenuEntry:
	if id.is_empty():
		return null
	for e in entries:
		if e.id == id:
			return e
	return null


func has(id: String) -> bool:
	return find(id) != null


func ids() -> Array[String]:
	var out: Array[String] = []
	for e in entries:
		out.append(e.id)
	return out
