class_name DlgPortraits
extends RefCounted
## Finds and caches portrait textures. Node-free.
##
## Lookup for (who, expression), first hit wins, for each directory in `dirs`:
##   <dir>/<who>_<expression>.png     (the art contract in the dialogue brief: assets/portraits/)
##   <dir>/<who>.<expression>.png     (docs/story/INTEGRATION.md spelling)
## then the same for expression "neutral", then for the character's first listed portrait. A miss
## returns null and the views draw a coloured initial instead. Imported resources are preferred;
## a PNG that exists on disk but has not been imported yet is read directly, so new art shows up
## without an editor import.

const DEFAULT_DIRS: Array[String] = ["res://assets/portraits", "res://assets/story/portraits"]

var dirs: Array[String] = DEFAULT_DIRS.duplicate()
var _cache: Dictionary[String, Texture2D] = {}
var _misses: Dictionary[String, bool] = {}


func _init(p_dirs: Array[String] = []) -> void:
	if not p_dirs.is_empty():
		dirs = p_dirs.duplicate()


## Candidate file paths for an exact (who, expression), in lookup order.
func candidates(who: String, expression: String) -> Array[String]:
	var out: Array[String] = []
	for d: String in dirs:
		out.append("%s/%s_%s.png" % [d, who, expression])
		out.append("%s/%s.%s.png" % [d, who, expression])
	return out


## Texture for (who, expression) with the fallbacks above, or null. `known` = the character's
## portraits list from story.json (may be empty).
func texture(who: String, expression: String, known: Array[String] = []) -> Texture2D:
	var tries: Array[String] = [expression]
	if expression != "neutral":
		tries.append("neutral")
	if not known.is_empty() and not tries.has(known[0]):
		tries.append(known[0])
	for e: String in tries:
		var t := _exact(who, e)
		if t != null:
			return t
	return null


## True when the exact expression exists (no fallback).
func has_exact(who: String, expression: String) -> bool:
	return _exact(who, expression) != null


func clear_cache() -> void:
	_cache.clear()
	_misses.clear()


func _exact(who: String, expression: String) -> Texture2D:
	var key := who + "|" + expression
	if _cache.has(key):
		return _cache[key]
	if _misses.has(key):
		return null
	for p: String in candidates(who, expression):
		var t := load_png(p)
		if t != null:
			_cache[key] = t
			return t
	_misses[key] = true
	return null


## Imported texture if there is one, else the raw PNG from disk (with mipmaps, for small bark chips),
## else null. An import marked `valid=false` (a failed or half-finished import) is skipped without
## asking the loader, so it never pushes an engine error.
static func load_png(p: String) -> Texture2D:
	if ResourceLoader.exists(p) and _import_ok(p):
		var r := load(p)
		if r is Texture2D:
			return r
	if FileAccess.file_exists(p):
		var img := Image.load_from_file(ProjectSettings.globalize_path(p))
		if img != null and not img.is_empty():
			if not img.has_mipmaps():
				img.generate_mipmaps()
			return ImageTexture.create_from_image(img)
	return null


static func _import_ok(p: String) -> bool:
	var meta := p + ".import"
	if not FileAccess.file_exists(meta):
		return true
	return not FileAccess.get_file_as_string(meta).contains("valid=false")
