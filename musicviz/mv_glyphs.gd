class_name MVGlyphs
extends RefCounted
## Procedural rune glyphs for the rune sequencer (MUSIC-12: "runes ... make the relationship
## visible"). Used when no rune glyph sheet exists under assets/textures/decals/. Each glyph is a few
## straight strokes on a 3 x 4 lattice in the unit box (x right, y down): a stave (one or two
## vertical stems) with branches, angular like carved futhark-style runes. Pure, static and
## deterministic: glyph(i) is the same for the same i everywhere, and glyphs 0..GLYPH_COUNT-1 are
## pairwise different.

const GLYPH_COUNT := 24
## Lattice: columns x = 0.2, 0.5, 0.8; rows y = 0.08, 0.36, 0.64, 0.92.
const XS: Array[float] = [0.2, 0.5, 0.8]
const YS: Array[float] = [0.08, 0.36, 0.64, 0.92]

## Branch catalogue: [from col, from row, to col, to row] (coordinates on the lattice).
const BRANCHES: Array = [
	[1, 0, 2, 1], [1, 0, 0, 1], [1, 1, 2, 0], [1, 1, 0, 0],
	[1, 1, 2, 2], [1, 1, 0, 2], [1, 2, 2, 1], [1, 2, 0, 1],
	[1, 2, 2, 3], [1, 2, 0, 3], [1, 3, 2, 2], [1, 3, 0, 2],
	[0, 1, 2, 1], [0, 2, 2, 2], [2, 0, 2, 1], [0, 0, 0, 1],
	[2, 2, 2, 3], [0, 2, 0, 3],
]


static func _pt(c: int, r: int) -> Vector2:
	return Vector2(XS[c], YS[r])


## The branch pair (i < j) of combination rank `r` among C(BRANCHES.size(), 2).
static func _pair(r: int) -> Vector2i:
	var n := BRANCHES.size()
	var i := 0
	var left := r
	while left >= n - 1 - i:
		left -= n - 1 - i
		i += 1
	return Vector2i(i, i + 1 + left)


## The strokes of glyph `i` (any int; wraps at GLYPH_COUNT): each stroke a 2-point polyline.
## Glyph g uses branch pair number (g·37 + 11) mod C(18, 2) — 37 is coprime to 153, so the pairs of
## glyphs 0..152 are all different — on a single stem (a double stem every third glyph) and odd
## glyphs carry a third branch.
static func glyph(i: int) -> Array[PackedVector2Array]:
	var g := posmod(i, GLYPH_COUNT)
	var n := BRANCHES.size()
	var combos := n * (n - 1) / 2
	var pr := _pair((g * 37 + 11) % combos)
	var out: Array[PackedVector2Array] = []
	if g % 3 == 2:
		out.append(PackedVector2Array([_pt(0, 0), _pt(0, 3)]))
		out.append(PackedVector2Array([_pt(2, 0), _pt(2, 3)]))
	else:
		out.append(PackedVector2Array([_pt(1, 0), _pt(1, 3)]))
	var slots: Array[int] = [pr.x, pr.y]
	if g % 2 == 1:
		var third := (pr.x + pr.y + g) % n
		while slots.has(third):
			third = (third + 1) % n
		slots.append(third)
	for s: int in slots:
		var b: Array = BRANCHES[s]
		out.append(PackedVector2Array([_pt(b[0], b[1]), _pt(b[2], b[3])]))
	return out


## A signature string of glyph i's strokes (for distinctness tests).
static func signature(i: int) -> String:
	var parts: Array[String] = []
	for s: PackedVector2Array in glyph(i):
		var a := s[0]
		var b := s[s.size() - 1]
		var key := "%d,%d-%d,%d" % [roundi(a.x * 10), roundi(a.y * 100), roundi(b.x * 10), roundi(b.y * 100)]
		if b.x < a.x or (b.x == a.x and b.y < a.y):
			key = "%d,%d-%d,%d" % [roundi(b.x * 10), roundi(b.y * 100), roundi(a.x * 10), roundi(a.y * 100)]
		parts.append(key)
	parts.sort()
	return "|".join(parts)
