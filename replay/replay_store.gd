class_name ReplayStore
extends RefCounted
## Keeps the winning performance of every solved level (CINE-01 "once the level is beaten, the player
## should be able to watch the combined result"; LEVEL-09 revisiting) as one JSON file per level:
## `<root>/<level id>.json` (default root user://replays). Node-free; safe to use from the game, the
## campaign screen and tests (pass a scratch root).
##
## Game layer, on a win (GameSession reached CINEMATIC with outcome.win):
##     var store := ReplayStore.new()
##     store.record_win(session.level, session.loadout,
##         session.committed_tapes + [session.pending_tape], session.boss_memory, session.resolution,
##         int(Time.get_unix_time_from_system()))
## Campaign screen:
##     store.list_level_ids()                       -> ids with a kept replay
##     store.quick_check(level, current_loadout)    -> ReplayVerifier.Check without resolving (badge:
##                                                     "watch" / "stale" / none)
##     var check := store.play(level, current_loadout)   (resolves; ~0.3-3 s, or use play_async_config)
##     if check.ok(): start a ReplayPlayback.new(check.resolution, level, check.record)
##
## Policy: a new win on a level replaces its kept replay (the latest solution is the one shown; a
## revisit with new gear is a new performance). Saving is atomic (write a temp file, then rename), so
## a crash never leaves half a replay. Loading never throws: a missing, corrupt, foreign or newer file
## comes back as null / an INVALID check with the reason.

const DEFAULT_ROOT: String = "user://replays"
const EXT: String = ".json"

var root: String = DEFAULT_ROOT


func _init(p_root: String = DEFAULT_ROOT) -> void:
	root = p_root


## File name for a level id: lower-case letters, digits, '-' and '_' kept, anything else '_'.
static func file_stem(level_id: String) -> String:
	var out := ""
	for ch: String in level_id.to_lower():
		var c := ch.unicode_at(0)
		var keep := (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or ch == "-" or ch == "_"
		out += ch if keep else "_"
	return out if not out.is_empty() else "_"


func path_for(level_id: String) -> String:
	return root.path_join(file_stem(level_id) + EXT)


# ───────────────────────────── write ─────────────────────────────


## Build the record of a win and keep it. Returns the record, or null (reason in `errors`) when the
## run is not a keepable win or the disk refused.
func record_win(
	level: LevelDef,
	loadout: ResolvedLoadout,
	tapes: Array,
	boss_memory: BossMemory,
	resolution: Resolution,
	saved_at: int = 0,
	errors: Array[String] = []
) -> ReplayRecord:
	var r := ReplayRecord.from_win(level, loadout, tapes, boss_memory, resolution, errors)
	if r == null:
		return null
	r.saved_at = saved_at
	if not save(r, errors):
		return null
	return r


## Write a record (replacing any kept replay of its level). False + reason on failure.
func save(record: ReplayRecord, errors: Array[String] = []) -> bool:
	if record == null or record.level_id.is_empty():
		errors.append("ReplayStore.save: no record / level id")
		return false
	if not DirAccess.dir_exists_absolute(root):
		var mk := DirAccess.make_dir_recursive_absolute(root)
		if mk != OK:
			errors.append("ReplayStore.save: cannot create %s (error %d)" % [root, mk])
			return false
	var path := path_for(record.level_id)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		errors.append("ReplayStore.save: cannot write %s (error %d)" % [tmp, FileAccess.get_open_error()])
		return false
	f.store_string(ODJson.stringify(record.to_dict(), "\t"))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var mv := DirAccess.rename_absolute(tmp, path)
	if mv != OK:
		errors.append("ReplayStore.save: cannot move %s into place (error %d)" % [tmp, mv])
		DirAccess.remove_absolute(tmp)
		return false
	return true


## Forget a level's replay. True when nothing is kept afterwards.
func remove(level_id: String) -> bool:
	var path := path_for(level_id)
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(path) == OK


# ───────────────────────────── read ─────────────────────────────


func has_replay(level_id: String) -> bool:
	return FileAccess.file_exists(path_for(level_id))


## Level ids that have a kept replay (read from the files, sorted).
func list_level_ids() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for file: String in dir.get_files():
		if not file.ends_with(EXT):
			continue
		var errors: Array[String] = []
		var r := load_record_at(root.path_join(file), errors)
		if r != null and not out.has(r.level_id):
			out.append(r.level_id)
	out.sort()
	return out


## The kept replay of a level, or null (reason in `errors`; nothing appended when simply absent).
func load_record(level_id: String, errors: Array[String] = []) -> ReplayRecord:
	var path := path_for(level_id)
	if not FileAccess.file_exists(path):
		return null
	var r := load_record_at(path, errors)
	if r != null and r.level_id != level_id:
		errors.append("replay %s belongs to level '%s'" % [path, r.level_id])
		return null
	return r


static func load_record_at(path: String, errors: Array[String] = []) -> ReplayRecord:
	var data: Variant = ODJson.read_file(path, errors)
	if data == null:
		return null
	return ReplayRecord.from_dict(data, errors)


# ───────────────────────────── check / play ─────────────────────────────


## Without resolving: is there a replay for this level and do its level (and, if given, gear) still
## match? For badges on the campaign screen.
func quick_check(level: LevelDef, current_loadout: ResolvedLoadout = null) -> ReplayVerifier.Check:
	var errors: Array[String] = []
	var r := load_record(level.id, errors)
	if r == null:
		if errors.is_empty():
			return ReplayVerifier.Check.make(ReplayVerifier.STATUS_MISSING, ReplayVerifier.REASON_NONE, "no replay kept for this level", null)
		return ReplayVerifier.Check.make(ReplayVerifier.STATUS_INVALID, ReplayVerifier.REASON_UNREADABLE, "; ".join(errors), null)
	return ReplayVerifier.quick_check(r, level, current_loadout)


## Load and fully verify a level's replay (resolves on this thread). check.ok() -> check.resolution
## is the run to show; otherwise check.status / check.message say why it is not offered.
func play(level: LevelDef, current_loadout: ResolvedLoadout = null, progress: Callable = Callable(), cancel: ODResolve.CancelToken = null) -> ReplayVerifier.Check:
	var q := quick_check(level, current_loadout)
	if not q.ok():
		return q
	return ReplayVerifier.verify(q.record, level, current_loadout, progress, cancel)
