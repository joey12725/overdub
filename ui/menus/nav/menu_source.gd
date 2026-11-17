class_name MenuSource
extends RefCounted
## Anything that can describe its current menu (prototype ui/menus/nav.ts MenuSource). Every
## screen's logic class extends this.


## The menu as it stands now. Re-read after every command, because accepting an entry may change the
## screen's local state (open a list, show a confirm).
func menu() -> MenuDef:
	return MenuDef.new()


## One-shot focus request after a state change (e.g. opening a list focuses the equipped item);
## "" = none.
func take_focus_request() -> String:
	return ""
