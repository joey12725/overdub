class_name ActorPool
extends RefCounted
## Keyed mark-and-sweep pool of views (prototype pool.ts KeyedPool). Each frame: begin(), touch(key)
## for every key present in the snapshot, then sweep() releases the views whose keys were not
## touched. Views are created by the factory only when the free list is empty, so steady-state
## frames allocate nothing (dense arrays + swap-remove; the index dictionary is updated in place).

var _factory: Callable
var _on_release: Callable
var _index: Dictionary = {}
var _keys: Array = []
var _views: Array[Node] = []
var _gens: PackedInt32Array = PackedInt32Array()
var _free: Array[Node] = []
var _gen: int = 0
var created: int = 0
## True when the last touch() acquired a view (the caller resets it for the new key).
var last_new: bool = false


func _init(factory: Callable, on_release: Callable) -> void:
	_factory = factory
	_on_release = on_release


func begin() -> void:
	_gen += 1


func touch(key: Variant) -> Node:
	var i: int = _index.get(key, -1)
	if i >= 0:
		_gens[i] = _gen
		last_new = false
		return _views[i]
	var v: Node
	if _free.is_empty():
		v = _factory.call()
		created += 1
	else:
		v = _free.pop_back()
	_index[key] = _views.size()
	_keys.append(key)
	_views.append(v)
	_gens.append(_gen)
	last_new = true
	return v


## Release every view not touched since begin(). `keep` (view -> bool) may veto a release, e.g.
## while a death burst plays; vetoed views stay and are offered again next sweep.
func sweep(keep: Callable = Callable()) -> void:
	var i := _views.size() - 1
	while i >= 0:
		if _gens[i] != _gen and not (keep.is_valid() and keep.call(_views[i])):
			_remove_at(i)
		i -= 1


func _remove_at(i: int) -> void:
	var v := _views[i]
	var key: Variant = _keys[i]
	var last := _views.size() - 1
	if i != last:
		_views[i] = _views[last]
		_keys[i] = _keys[last]
		_gens[i] = _gens[last]
		_index[_keys[i]] = i
	_views.resize(last)
	_keys.resize(last)
	_gens.resize(last)
	_index.erase(key)
	if _on_release.is_valid():
		_on_release.call(v)
	_free.append(v)


## Build n views up front so the first frames do not allocate.
func prewarm(n: int) -> void:
	for i: int in n:
		_free.append(_factory.call())
		created += 1


func size() -> int:
	return _views.size()


func free_count() -> int:
	return _free.size()


func get_view(key: Variant) -> Node:
	var i: int = _index.get(key, -1)
	return _views[i] if i >= 0 else null


## Release everything (level change).
func clear() -> void:
	var i := _views.size() - 1
	while i >= 0:
		_remove_at(i)
		i -= 1


## Every view, live and free (for disposal); empties the pool.
func drain() -> Array[Node]:
	var out: Array[Node] = []
	out.append_array(_views)
	out.append_array(_free)
	_views.clear()
	_keys.clear()
	_gens.resize(0)
	_index.clear()
	_free.clear()
	return out
