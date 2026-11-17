class_name DlgStoryDirector
extends RefCounted
## Decides which story sequence plays when (docs/story/INTEGRATION.md "Where each piece appears").
## Node-free: it reads DlgStoryData, records flags in a DlgSeenStore and hands back line arrays; the
## DialoguePlayer decides *when* a box may open (DlgGate).
##
##   intro(level)   first visit only (or replay = true from level select)  -> story.<lvl>.intro
##   outro(level)   first clear only                                       -> story.<lvl>.outro
##   ending()       once per save (replay = true to force)                -> story.ending
##   note_first(level, "death" | "desync" | "ghostTake" | "resetAll" | "loot")
##       queues levels[lvl].first<Kind> if it exists and is unseen (marking the once flag too),
##       else once.first<Kind> if unseen. Queued firsts come out of take_pending() at the next phase
##       that allows a box (never during a take).

var story: DlgStoryData = null
var seen: DlgSeenStore = null
## Queued firsts: [{ "key": "once.firstDeath", "lines": Array[DlgLine] }, ...] in arrival order.
var pending: Array[Dictionary] = []


func _init(p_story: DlgStoryData = null, p_seen: DlgSeenStore = null) -> void:
	story = p_story if p_story != null else DlgStoryData.new()
	seen = p_seen if p_seen != null else DlgSeenStore.new()


static func level_key(level_id: String, section: String) -> String:
	return "story.%s.%s" % [level_id, section]


## Lines to play now ([] when none). Marks the flag (a skipped intro counts as seen).
func intro(level_id: String, replay: bool = false) -> Array[DlgLine]:
	return _section(level_id, "intro", replay)


func outro(level_id: String, replay: bool = false) -> Array[DlgLine]:
	return _section(level_id, "outro", replay)


func ending(replay: bool = false) -> Array[DlgLine]:
	var none: Array[DlgLine] = []
	if seen.has("story.ending") and not replay:
		return none
	var lines := story.ending_lines()
	if not lines.is_empty():
		seen.mark("story.ending")
	return lines


func stinger() -> Array[DlgLine]:
	return story.stinger.duplicate()


## The level's idle toast line, or null.
func idle_line(level_id: String) -> DlgLine:
	var lines := story.level_lines(level_id, "idle")
	return lines[0] if not lines.is_empty() else null


## Record that `kind` happened for the first time this run. Returns true when a sequence was queued.
func note_first(level_id: String, kind: String) -> bool:
	var cap := kind.substr(0, 1).to_upper() + kind.substr(1)
	var section := "first" + cap
	var once_key := "once." + section
	var lkey := level_key(level_id, section)
	if level_id != "" and story.has_level_section(level_id, section) and not seen.has(lkey):
		seen.mark(lkey)
		seen.mark(once_key)
		_queue(lkey, story.level_lines(level_id, section))
		return true
	if not seen.has(once_key):
		var lines := story.once_lines(section)
		if lines.is_empty():
			return false
		seen.mark(once_key)
		_queue(once_key, lines)
		return true
	return false


func has_pending() -> bool:
	return not pending.is_empty()


## The oldest queued first ({} when none). Removes it.
func take_pending() -> Dictionary:
	if pending.is_empty():
		return {}
	var p: Dictionary = pending.pop_front()
	return p


func clear_pending() -> void:
	pending.clear()


func _queue(key: String, lines: Array[DlgLine]) -> void:
	for p: Dictionary in pending:
		if p["key"] == key:
			return
	pending.append({"key": key, "lines": lines})


func _section(level_id: String, section: String, replay: bool) -> Array[DlgLine]:
	var none: Array[DlgLine] = []
	var key := level_key(level_id, section)
	if seen.has(key) and not replay:
		return none
	var lines := story.level_lines(level_id, section)
	if not lines.is_empty():
		seen.mark(key)
	return lines
