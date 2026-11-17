class_name FxTextPool
extends RefCounted
## Floating world-space words: tier readouts, CLANG, DESYNC, tape letters... (port of
## prototype/src/render/fx/pool.ts TextPool). Same fixed-capacity, recycle-the-oldest discipline as
## FxSpritePool; FxWordRenderer draws them from the baked word atlas.

## Floats per instance in the MultiMesh buffer (3x4 transform rows + colour + custom).
const STRIDE := 20

var capacity: int
var pos: PackedVector3Array
var vel: PackedVector3Array
var tint: PackedColorArray
## World height of the word at rest.
var height: PackedFloat32Array
var life: PackedFloat32Array
var age: PackedFloat32Array
var freeze: PackedFloat32Array
var rot: PackedFloat32Array
## Extra scale at birth that settles quickly (the "pop").
var pop: PackedFloat32Array
var alpha: PackedFloat32Array
var word: PackedByteArray
var tag: PackedByteArray
var alive: PackedByteArray

var _free: PackedInt32Array
var _free_top: int = 0
var _live: int = 0
var _hi: int = 0


func _init(p_capacity: int) -> void:
	capacity = p_capacity
	pos.resize(capacity)
	vel.resize(capacity)
	tint.resize(capacity)
	height.resize(capacity)
	life.resize(capacity)
	age.resize(capacity)
	freeze.resize(capacity)
	rot.resize(capacity)
	pop.resize(capacity)
	alpha.resize(capacity)
	word.resize(capacity)
	tag.resize(capacity)
	alive.resize(capacity)
	_free.resize(capacity)
	clear()


func count() -> int:
	return _live


func clear() -> void:
	alive.fill(0)
	_live = 0
	_hi = 0
	for i: int in capacity:
		_free[i] = capacity - 1 - i
	_free_top = capacity


func _steal() -> int:
	var best := 0
	var best_t := -INF
	for i: int in capacity:
		if alive[i] == 0:
			return i
		var t := age[i] / maxf(1e-6, life[i])
		if t > best_t:
			best_t = t
			best = i
	return best


func spawn(p_tag: int, p_word: int) -> int:
	var i: int
	if _free_top > 0:
		_free_top -= 1
		i = _free[_free_top]
		_live += 1
	else:
		i = _steal()
	if i + 1 > _hi:
		_hi = i + 1
	alive[i] = 1
	tag[i] = p_tag
	word[i] = p_word
	pos[i] = Vector3.ZERO
	vel[i] = Vector3(0.0, 0.55, 0.0)
	tint[i] = Color.WHITE
	height[i] = 0.5
	life[i] = 0.9
	age[i] = 0.0
	freeze[i] = 0.0
	rot[i] = 0.0
	pop[i] = 0.6
	alpha[i] = 1.0
	return i


func kill(i: int) -> void:
	if alive[i] == 0:
		return
	alive[i] = 0
	_free[_free_top] = i
	_free_top += 1
	_live -= 1


func update(dt: float) -> void:
	if _live == 0:
		return
	# Words decelerate as they rise so they settle readable instead of flying off.
	var k := exp(-2.5 * dt)
	for i: int in _hi:
		if alive[i] == 0:
			continue
		if freeze[i] > 0.0:
			freeze[i] -= dt
			continue
		var a := age[i] + dt
		if a >= life[i]:
			kill(i)
			continue
		age[i] = a
		if a < 0.0:
			continue
		var v := vel[i] * k
		vel[i] = v
		pos[i] += v * dt


## Displayed height of word slot i right now (pop: start oversized, overshoot slightly, settle).
func display_height(i: int) -> float:
	var frozen := freeze[i] > 0.0
	var a := maxf(0.0, age[i])
	var settle := 1.0 if frozen else exp(-a * 13.0) * cos(a * 18.0)
	return height[i] * (1.0 + pop[i] * settle)


## Pack live words into a MultiMesh buffer (STRIDE floats each: 3x4 transform rows, colour, custom).
## Layout, read back as MODEL_MATRIX[0] = (rot, aspect, height), [3] = position, INSTANCE_CUSTOM = rect:
##   row0: rot, word, 0, pos.x    row1: aspect, 0, 0, pos.y    row2: height, 0, 0, pos.z
##   tint r, g, b, a    atlas rect u0, v0, u1, v1.
## `rects` / `aspects` come from FxWordAtlas (per word index); missing entries pack a zero rect.
func write_instances(buf: PackedFloat32Array, rects: Array[Rect2] = [], aspects: PackedFloat32Array = PackedFloat32Array()) -> int:
	var n := 0
	for i: int in _hi:
		if alive[i] == 0 or age[i] < 0.0:
			continue
		var t := minf(1.0, age[i] / maxf(1e-6, life[i]))
		var fade := 1.0 if t < 0.7 else 1.0 - (t - 0.7) / 0.3
		var a := alpha[i] * fade
		if a <= 0.002:
			continue
		var o := n * STRIDE
		var p := pos[i]
		var c := tint[i]
		var w := word[i]
		var rect := rects[w] if w < rects.size() else Rect2()
		buf[o] = rot[i]
		buf[o + 1] = float(w)
		buf[o + 2] = 0.0
		buf[o + 3] = p.x
		buf[o + 4] = aspects[w] if w < aspects.size() else 3.0
		buf[o + 5] = 0.0
		buf[o + 6] = 0.0
		buf[o + 7] = p.y
		buf[o + 8] = display_height(i)
		buf[o + 9] = 0.0
		buf[o + 10] = 0.0
		buf[o + 11] = p.z
		buf[o + 12] = c.r
		buf[o + 13] = c.g
		buf[o + 14] = c.b
		buf[o + 15] = a
		buf[o + 16] = rect.position.x
		buf[o + 17] = rect.position.y
		buf[o + 18] = rect.end.x
		buf[o + 19] = rect.end.y
		n += 1
	return n
