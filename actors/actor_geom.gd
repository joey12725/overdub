class_name ActorGeom
extends RefCounted
## Flat ground / overlay shapes for markers, telegraphs and trails (prototype decals.ts). Unit-sized
## meshes placed by transform so pooled views reuse them. All lie in the XZ plane unless noted.

static func _mesh(verts: PackedVector3Array, uvs: PackedVector2Array, idx: PackedInt32Array) -> ArrayMesh:
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms.fill(Vector3.UP)
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## A 1 x 1 strip from x = 0 to x = 1, centred on z = 0; UV.x runs along it, UV.y across.
static func strip() -> ArrayMesh:
	return _mesh(
		PackedVector3Array([Vector3(0, 0, -0.5), Vector3(1, 0, -0.5), Vector3(1, 0, 0.5), Vector3(0, 0, 0.5)]),
		PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]),
		PackedInt32Array([0, 1, 2, 0, 2, 3]))


## Sector centred on +Z (model forward), angles measured from +Z toward +X. radial_uv: UV.x = radius
## fraction (inner 0 -> outer 1), UV.y = angle fraction; otherwise swapped (UV.x = angle fraction,
## UV.y = radius fraction; used by swing trails).
static func sector(inner: float, outer: float, arc: float, segs: int, radial_uv: bool) -> ArrayMesh:
	var n := maxi(2, segs)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i: int in n + 1:
		var f := float(i) / float(n)
		var a := -arc * 0.5 + arc * f
		var s := sin(a)
		var c := cos(a)
		verts.append(Vector3(s * inner, 0, c * inner))
		verts.append(Vector3(s * outer, 0, c * outer))
		if radial_uv:
			uvs.append(Vector2(0, f))
			uvs.append(Vector2(1, f))
		else:
			uvs.append(Vector2(f, 0))
			uvs.append(Vector2(f, 1))
	for i: int in n:
		var k := i * 2
		idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	return _mesh(verts, uvs, idx)


## Flat ring (annulus). UV.x = radius fraction.
static func ring(inner: float, outer: float, segs: int = 48) -> ArrayMesh:
	return sector(inner, outer, TAU, segs, true)


static func disc(r: float, segs: int = 32) -> ArrayMesh:
	return sector(0.0, r, TAU, segs, true)


## Downward-pointing chevron in the XY plane (a billboard marker), centred on the origin.
static func chevron(w: float, h: float, t: float) -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(-w * 0.5, h * 0.5, 0), Vector3(-w * 0.5, h * 0.5 - t, 0), Vector3(0, -h * 0.5 + t, 0),
		Vector3(0, -h * 0.5, 0), Vector3(w * 0.5, h * 0.5 - t, 0), Vector3(w * 0.5, h * 0.5, 0)])
	var uvs := PackedVector2Array()
	uvs.resize(verts.size())
	return _mesh(verts, uvs, PackedInt32Array([0, 1, 2, 0, 2, 3, 3, 2, 4, 3, 4, 5]))


## Triangle arrow pointing +Z on the floor (enemy facing indicator).
static func arrow(w: float, l: float) -> ArrayMesh:
	var verts := PackedVector3Array([Vector3(-w * 0.5, 0, 0), Vector3(w * 0.5, 0, 0), Vector3(0, 0, l)])
	return _mesh(verts, PackedVector2Array([Vector2(0, 0), Vector2(0, 1), Vector2(1, 0.5)]), PackedInt32Array([0, 1, 2]))


## Square quad in the XY plane (billboard pips and bars), centred.
static func quad(w: float, h: float) -> ArrayMesh:
	return _mesh(
		PackedVector3Array([Vector3(-w * 0.5, -h * 0.5, 0), Vector3(w * 0.5, -h * 0.5, 0), Vector3(w * 0.5, h * 0.5, 0), Vector3(-w * 0.5, h * 0.5, 0)]),
		PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]),
		PackedInt32Array([0, 1, 2, 0, 2, 3]))


## Broken halo: uneven ring pieces with gaps, flat in XZ (the recording ghost's marker, GHOST-01).
static func broken_ring(radius: float, width: float, pieces: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var seg := TAU / float(pieces)
	for p: int in pieces:
		# Uneven pieces so it reads as cracked, not as a dashed decoration.
		var length := seg * (0.45 if p == 0 else 0.72 - float(p % 2) * 0.12)
		var start := p * seg + (0.25 if p == 1 else 0.0)
		var lift := 0.03 if p == 0 else 0.0
		var n := 8
		var base := verts.size()
		for i: int in n + 1:
			var a := start + length * float(i) / float(n)
			var c := cos(a)
			var s := sin(a)
			verts.append(Vector3(c * (radius - width), lift, s * (radius - width)))
			verts.append(Vector3(c * (radius + width), lift, s * (radius + width)))
			uvs.append(Vector2(0, 0))
			uvs.append(Vector2(1, 0))
		for i: int in n:
			var k := base + i * 2
			idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	return _mesh(verts, uvs, idx)


## Position / orient / scale a unit strip between two sim points at scene height h with a width.
## Returns the strip length (tiles).
static func place_strip(node: Node3D, x0: float, y0: float, x1: float, y1: float, width: float, h: float) -> float:
	var dx := x1 - x0
	var dz := y1 - y0
	var length := maxf(1e-4, sqrt(dx * dx + dz * dz))
	var yaw := -atan2(dz, dx)
	node.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(length, 1.0, width)), Vector3(x0, h, y0))
	return length
