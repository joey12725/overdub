class_name WorldGeom
extends RefCounted
## Procedural faceted geometry for the environment (port of prototype render/env/geom.ts, built
## with explicit convex polygons instead of a hull library): chamfered blocks, cliff columns, rocks,
## leaf clumps and grass tufts. Every face is flat (per-face normals), which is what makes the toon
## bands read as graphic, hand-painted planes (ART-02). UVs are planar in world units.
##
## These meshes are the kit's stand-ins until the Blender kit provides a piece (WorldKit decides),
## and the parts that are procedural by design (cliff skirt columns, scatter rocks, tufts).


## Accumulates flat-shaded triangles; build() returns an ArrayMesh with one surface.
class Builder:
	extends RefCounted
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var use_colors: bool = false
	var color: Color = Color.WHITE

	## One triangle, front face clockwise as seen from outside (Godot's convention); the normal
	## points to the front side.
	func tri(a: Vector3, b: Vector3, c: Vector3) -> void:
		var n := (c - a).cross(b - a)
		if n.length_squared() < 1e-14:
			return
		n = n.normalized()
		for p: Vector3 in [a, b, c]:
			verts.append(p)
			normals.append(n)
			uvs.append(_uv(p, n))
			colors.append(color)

	## Convex polygon (any order) whose outward side faces away from `inside`.
	func poly(pts: Array[Vector3], inside: Vector3) -> void:
		if pts.size() < 3:
			return
		var centre := Vector3.ZERO
		for p: Vector3 in pts:
			centre += p
		centre /= float(pts.size())
		# Newell normal of the points in their given order is unreliable when unordered; build a
		# plane normal from the farthest-apart triple instead.
		var n := Vector3.ZERO
		for i: int in range(pts.size()):
			for j: int in range(i + 1, pts.size()):
				var c := (pts[i] - centre).cross(pts[j] - centre)
				if c.length_squared() > n.length_squared():
					n = c
		if n.length_squared() < 1e-14:
			return
		n = n.normalized()
		if n.dot(centre - inside) < 0.0:
			n = -n
		var ax := (pts[0] - centre).normalized()
		if ax.length_squared() < 1e-12:
			ax = n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
		var ay := n.cross(ax)
		var order: Array = []
		for p: Vector3 in pts:
			var d := p - centre
			order.append([atan2(d.dot(ay), d.dot(ax)), p])
		order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for i: int in range(1, order.size() - 1):
			# Counter-clockwise about n seen from outside -> Godot front face is clockwise, so swap.
			tri(order[0][1], order[i + 1][1], order[i][1])

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3) -> void:
		poly([a, b, c, d], inside)

	func append_mesh(m: Builder, xf: Transform3D) -> void:
		var nb := xf.basis.inverse().transposed()
		for i: int in range(m.verts.size()):
			var p := xf * m.verts[i]
			var n := (nb * m.normals[i]).normalized()
			verts.append(p)
			normals.append(n)
			uvs.append(_uv(p, n))
			colors.append(m.colors[i] if i < m.colors.size() else Color.WHITE)

	func build() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_TEX_UV] = uvs
		if use_colors:
			arr[Mesh.ARRAY_COLOR] = colors
		var m := ArrayMesh.new()
		if verts.size() > 0:
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

	static func _uv(p: Vector3, n: Vector3) -> Vector2:
		if absf(n.y) > 0.5:
			return Vector2(p.x, p.z)
		if absf(n.x) > absf(n.z):
			return Vector2(p.z, -p.y)
		return Vector2(p.x, -p.y)


## Chamfered box `size`, bevel `b`, spanning Y from y0 to y0 + size.y, centred on X / Z.
static func chamfer_box_into(bld: Builder, size: Vector3, b: float, y0: float = 0.0, offset: Vector3 = Vector3.ZERO) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	b = minf(b, minf(hx, minf(hy, hz)) * 0.95)
	var c := Vector3(0.0, y0 + hy, 0.0) + offset
	var px := {}
	var py := {}
	var pz := {}
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			for sz: int in [-1, 1]:
				var k := Vector3i(sx, sy, sz)
				px[k] = c + Vector3(sx * hx, sy * (hy - b), sz * (hz - b))
				py[k] = c + Vector3(sx * (hx - b), sy * hy, sz * (hz - b))
				pz[k] = c + Vector3(sx * (hx - b), sy * (hy - b), sz * hz)
	for s: int in [-1, 1]:
		# Main faces.
		bld.poly([px[Vector3i(s, -1, -1)], px[Vector3i(s, -1, 1)], px[Vector3i(s, 1, 1)], px[Vector3i(s, 1, -1)]], c)
		bld.poly([py[Vector3i(-1, s, -1)], py[Vector3i(1, s, -1)], py[Vector3i(1, s, 1)], py[Vector3i(-1, s, 1)]], c)
		bld.poly([pz[Vector3i(-1, -1, s)], pz[Vector3i(1, -1, s)], pz[Vector3i(1, 1, s)], pz[Vector3i(-1, 1, s)]], c)
	if b <= 1e-5:
		return
	for s1: int in [-1, 1]:
		for s2: int in [-1, 1]:
			# Edge bevels: X-Y (along z), X-Z (along y), Y-Z (along x).
			bld.poly([px[Vector3i(s1, s2, -1)], px[Vector3i(s1, s2, 1)], py[Vector3i(s1, s2, 1)], py[Vector3i(s1, s2, -1)]], c)
			bld.poly([px[Vector3i(s1, -1, s2)], px[Vector3i(s1, 1, s2)], pz[Vector3i(s1, 1, s2)], pz[Vector3i(s1, -1, s2)]], c)
			bld.poly([py[Vector3i(-1, s1, s2)], py[Vector3i(1, s1, s2)], pz[Vector3i(1, s1, s2)], pz[Vector3i(-1, s1, s2)]], c)
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			for sz: int in [-1, 1]:
				var k := Vector3i(sx, sy, sz)
				bld.poly([px[k], py[k], pz[k]], c)


static func chamfer_box(size: Vector3, b: float, y0: float = 0.0) -> ArrayMesh:
	var bld := Builder.new()
	chamfer_box_into(bld, size, b, y0)
	return bld.build()


## Plain axis box into a builder (centre, size).
static func box_into(bld: Builder, centre: Vector3, size: Vector3) -> void:
	chamfer_box_into(bld, size, 0.0, centre.y - size.y * 0.5, Vector3(centre.x, 0.0, centre.z))


## Prism (n-gon) cylinder along Y from y0 to y1, radius r (bottom r0 / top r1), centred at (x, z).
static func cylinder_into(bld: Builder, centre: Vector3, r0: float, r1: float, h: float, sides: int = 8, axis: int = 1) -> void:
	var ring0: Array[Vector3] = []
	var ring1: Array[Vector3] = []
	for i: int in range(sides):
		var a := TAU * (float(i) + 0.5) / float(sides)
		ring0.append(Vector3(cos(a) * r0, -h * 0.5, sin(a) * r0))
		ring1.append(Vector3(cos(a) * r1, h * 0.5, sin(a) * r1))
	var rot := Basis.IDENTITY
	if axis == 0:
		rot = Basis(Vector3(0, 0, 1), -PI * 0.5)
	elif axis == 2:
		rot = Basis(Vector3(1, 0, 0), PI * 0.5)
	var inner := centre
	for i: int in range(sides):
		var j := (i + 1) % sides
		bld.poly([centre + rot * ring0[i], centre + rot * ring0[j], centre + rot * ring1[j], centre + rot * ring1[i]], inner)
	var top: Array[Vector3] = []
	var bot: Array[Vector3] = []
	for i: int in range(sides):
		top.append(centre + rot * ring1[i])
		bot.append(centre + rot * ring0[i])
	bld.poly(top, inner)
	bld.poly(bot, inner)


## Torus-ish ring of prisms in the XZ plane (radius R, tube r), around `centre`.
static func ring_into(bld: Builder, centre: Vector3, big_r: float, r: float, segments: int = 16, tube_sides: int = 6, xf: Basis = Basis.IDENTITY) -> void:
	for i: int in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		for j: int in range(tube_sides):
			var b0 := TAU * float(j) / float(tube_sides)
			var b1 := TAU * float(j + 1) / float(tube_sides)
			var p00 := _torus(a0, b0, big_r, r)
			var p01 := _torus(a0, b1, big_r, r)
			var p10 := _torus(a1, b0, big_r, r)
			var p11 := _torus(a1, b1, big_r, r)
			var mid := Vector3(cos((a0 + a1) * 0.5) * big_r, 0.0, sin((a0 + a1) * 0.5) * big_r)
			bld.poly([centre + xf * p00, centre + xf * p10, centre + xf * p11, centre + xf * p01], centre + xf * mid)


static func _torus(a: float, b: float, big_r: float, r: float) -> Vector3:
	var rr := big_r + cos(b) * r
	return Vector3(cos(a) * rr, sin(b) * r, sin(a) * rr)


const _ICO_F := [
	[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
	[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
	[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
	[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
]


static func _ico_verts() -> Array[Vector3]:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var raw := [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	var out: Array[Vector3] = []
	for v: Vector3 in raw:
		out.append(v.normalized())
	return out


## Faceted rock: an icosahedron with seeded radial jitter, flattened, resting on Y = 0.
static func rock_into(bld: Builder, seed_v: int, radius: float, centre: Vector3 = Vector3.ZERO, flat: float = 0.7) -> void:
	var rng := WorldRng.new(seed_v)
	var vs := _ico_verts()
	var pts: Array[Vector3] = []
	for v: Vector3 in vs:
		var k := rng.range_f(0.72, 1.12)
		var p := Vector3(v.x * radius * k, v.y * radius * k * flat, v.z * radius * k)
		pts.append(p)
	var min_y := INF
	for p: Vector3 in pts:
		min_y = minf(min_y, p.y)
	for i: int in range(pts.size()):
		pts[i] = pts[i] + centre + Vector3(0.0, -min_y * 0.85, 0.0)
	var mid := centre + Vector3(0.0, -min_y * 0.85, 0.0)
	for f: Array in _ICO_F:
		bld.poly([pts[f[0]], pts[f[1]], pts[f[2]]], mid)


static func rock(seed_v: int, radius: float, flat: float = 0.7) -> ArrayMesh:
	var bld := Builder.new()
	rock_into(bld, seed_v, radius, Vector3.ZERO, flat)
	return bld.build()


## Leaf clump: a few jittered, squashed icosahedra.
static func leaf_clump(seed_v: int, size: float) -> ArrayMesh:
	var bld := Builder.new()
	var rng := WorldRng.new(seed_v * 7919 + 13)
	var n := 3 + (seed_v % 2)
	for i: int in range(n):
		var a := TAU * float(i) / float(n) + rng.range_f(0.0, 1.0)
		var d := 0.0 if i == 0 else rng.range_f(0.12, 0.28) * size
		var c := Vector3(cos(a) * d, rng.range_f(0.0, 0.12) * size, sin(a) * d)
		rock_into(bld, seed_v * 31 + i, size * rng.range_f(0.32, 0.48), c, 0.75)
	return bld.build()


## Grass tuft: crossed thin blades (use a two-sided material).
static func tuft(seed_v: int, size: float) -> ArrayMesh:
	var bld := Builder.new()
	var rng := WorldRng.new(seed_v * 104729 + 7)
	var blades := 5 + (seed_v % 3)
	for i: int in range(blades):
		var a := TAU * float(i) / float(blades) + rng.range_f(-0.3, 0.3)
		var lean := rng.range_f(0.15, 0.45)
		var h := size * rng.range_f(0.6, 1.0)
		var w := size * 0.09
		var base := Vector3(cos(a) * size * 0.08, 0.0, sin(a) * size * 0.08)
		var side := Vector3(-sin(a), 0.0, cos(a)) * w
		var tip := base + Vector3(cos(a) * lean * h, h, sin(a) * lean * h)
		bld.tri(base - side, tip, base + side)
		bld.tri(base + side, tip, base - side)
	return bld.build()


## Cliff column under one tile: tapered, irregular rings from the tile underside down to `depth`.
static func cliff_column(seed_v: int, depth: float, top_y: float) -> ArrayMesh:
	var bld := Builder.new()
	var rng := WorldRng.new(seed_v)
	var levels := 3
	var rings: Array = []
	for l: int in range(levels + 1):
		var t := float(l) / float(levels)
		var y := top_y - depth * t
		var inset := 0.0 if l == 0 else (0.06 + 0.32 * pow(t, 1.3)) + rng.range_f(-0.05, 0.05)
		var ring: Array[Vector3] = []
		# Eight points around a square; corners pulled in irregularly.
		for k: int in range(8):
			var a := TAU * float(k) / 8.0 + PI / 8.0
			var sq := Vector2(cos(a), sin(a))
			sq = sq / maxf(absf(sq.x), absf(sq.y)) * 0.5
			var jitter := 0.0 if l == 0 else rng.range_f(-0.06, 0.06)
			var s := maxf(0.04, 1.0 - inset * 2.0 + jitter)
			ring.append(Vector3(sq.x * s, y, sq.y * s))
		rings.append(ring)
	var axis := Vector3(0.0, top_y - depth * 0.5, 0.0)
	for l: int in range(levels):
		var a: Array[Vector3] = rings[l]
		var b: Array[Vector3] = rings[l + 1]
		for k: int in range(8):
			var k2 := (k + 1) % 8
			var inside := Vector3(0.0, (a[k].y + b[k].y) * 0.5, 0.0)
			bld.poly([a[k], a[k2], b[k2]], inside)
			bld.poly([a[k], b[k2], b[k]], inside)
	var bottom: Array[Vector3] = rings[levels]
	var tip := Vector3(rng.range_f(-0.08, 0.08), top_y - depth - 0.25, rng.range_f(-0.08, 0.08))
	for k: int in range(8):
		bld.poly([bottom[k], bottom[(k + 1) % 8], tip], axis)
	return bld.build()
