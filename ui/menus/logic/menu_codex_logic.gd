class_name MenuCodexLogic
extends MenuSource
## The Field Guide (docs/CODEX.md, data/codex/codex.json): every page grouped (Machines, Traps,
## Tape, Force, Gear), locked pages listed but blank until met. Moving focus onto a page shows it;
## back closes the guide (to the campaign screen or the pause menu that opened it). Reads a `Codex`
## the game owns (unlock state, NEW flags); never writes the save. Viewing a page clears its NEW
## flag through Codex.clear_new (not persisted).

var codex: Codex = null
## The page shown (an entry id), "" before the first focus.
var selected: String = ""

var _on_back: Callable
var _focus_req: String = ""


func _init(on_back: Callable) -> void:
	_on_back = on_back


func set_codex(c: Codex) -> void:
	codex = c


## Open on `entry_id` (e.g. the page for what killed the last self), else the last page read, else
## the first unlocked page.
func on_show(entry_id: String = "") -> void:
	if codex == null:
		return
	if entry_id != "" and not codex.entry(entry_id).is_empty():
		selected = entry_id
	if selected == "" or codex.entry(selected).is_empty():
		selected = _first_unlocked()
	_focus_req = "entry:%s" % selected if selected != "" else "back"


func _first_unlocked() -> String:
	for g: Dictionary in codex.groups():
		for e: Dictionary in codex.entries_in(str(g.get("id", ""))):
			if codex.is_unlocked(str(e.get("id", ""))):
				return str(e.get("id", ""))
	return ""


## Entries in display order: [{group, entry}, ...] (both dictionaries from the Codex).
func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if codex == null:
		return out
	for g: Dictionary in codex.groups():
		for e: Dictionary in codex.entries_in(str(g.get("id", ""))):
			out.append({"group": g, "entry": e})
	return out


func menu() -> MenuDef:
	var entries: Array[MenuEntry] = [MenuEntry.make("back", 0, 0, func() -> void: _on_back.call())]
	var r := 1
	for row: Dictionary in rows():
		var id := str((row["entry"] as Dictionary).get("id", ""))
		var e := MenuEntry.make("entry:%s" % id, r, 0, func() -> void: _select(id))
		e.on_focus(func() -> void: _select(id))
		entries.append(e)
		r += 1
	return MenuDef.make(entries, func() -> void: _on_back.call(), "entry:%s" % selected if selected != "" else "back")


func _select(id: String) -> void:
	selected = id
	if codex != null and codex.is_new(id):
		codex.clear_new(id)


func take_focus_request() -> String:
	var r := _focus_req
	_focus_req = ""
	return r
