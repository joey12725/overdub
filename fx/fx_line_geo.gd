class_name FxLineGeo
extends RefCounted
## Thick soft polylines expanded into triangles (the Godot side of prototype gpu/polyline.ts).
## Lines on an isometric screen must have real width, so every polyline becomes a strip whose
## cross-section the fx line shaders soften (UV.x = signed distance across the line, -1..1).
##
## Two uses: FxLineGeo.Builder accumulates static geometry into an ArrayMesh (runes, sigils, rails),
## and draw_immediate() appends a line to an ImmediateMesh surface for the few lines that change
## every frame (epicycle chain and trace, ribbons, playheads).


## Side vector at point i of `pts`: perpendicular to the local tangent within the plane whose normal
## is `normal` (Vector3.UP lays the line flat on the floor).
static func side_at(pts: PackedVector3Array, i: int, normal: Vector3, closed: bool) -> Vector3:
	var n := pts.size()
	var a: Vector3
	var b: Vector3
	if closed:
		# The last point repeats the first: skip it when wrapping so the seam gets a real tangent.
		var m := n - 1 if (n > 2 and pts[0].distance_to(pts[n - 1]) < 1e-5) else n
		var ii := i % m
		a = pts[(ii - 1 + m) % m]
		b = pts[(ii + 1) % m]
	else:
		a = pts[maxi(0, i - 1)]
		b = pts[mini(n - 1, i + 1)]
	var t := b - a
	if t.length_squared() < 1e-12:
		t = Vector3.RIGHT if absf(normal.x) < 0.9 else Vector3.FORWARD
	var s := normal.cross(t)
	if s.length_squared() < 1e-12:
		return Vector3.UP
	return s.normalized()


## Accumulates strips for one ArrayMesh surface.
class Builder:
	extends RefCounted
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var custom := PackedFloat32Array()
	var indices := PackedInt32Array()

	## Append a strip through `pts`. `custom0` is copied to every vertex (CUSTOM0 in the shader);
	## `col` is the vertex colour. `alt` (same length as pts, optional) is a second figure whose
	## extruded positions go into CUSTOM0.xyz instead (morph targets); its w carries custom0.w.
	func add(pts: PackedVector3Array, normal: Vector3, width: float, closed: bool, col: Color = Color.WHITE, custom0: Vector4 = Vector4.ZERO, alt: PackedVector3Array = PackedVector3Array()) -> void:
		var n := pts.size()
		if n < 2:
			return
		var base := verts.size()
		var hw := width * 0.5
		var use_alt := alt.size() == n
		for i: int in n:
			var s := FxLineGeo.side_at(pts, i, normal, closed)
			verts.append(pts[i] + s * hw)
			verts.append(pts[i] - s * hw)
			uvs.append(Vector2(1.0, 0.0))
			uvs.append(Vector2(-1.0, 0.0))
			colors.append(col)
			colors.append(col)
			if use_alt:
				var sa := FxLineGeo.side_at(alt, i, normal, closed)
				var pa := alt[i] + sa * hw
				var pb := alt[i] - sa * hw
				custom.append_array(PackedFloat32Array([pa.x, pa.y, pa.z, custom0.w, pb.x, pb.y, pb.z, custom0.w]))
			else:
				custom.append_array(PackedFloat32Array([custom0.x, custom0.y, custom0.z, custom0.w, custom0.x, custom0.y, custom0.z, custom0.w]))
		for i: int in n - 1:
			var v := base + i * 2
			indices.append_array(PackedInt32Array([v, v + 1, v + 2, v + 1, v + 3, v + 2]))

	func is_empty() -> bool:
		return verts.is_empty()

	## The accumulated geometry as an ArrayMesh with one surface (null when empty).
	func commit() -> ArrayMesh:
		if verts.is_empty():
			return null
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		var flags := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		return mesh


## Append one strip to an ImmediateMesh surface that is between surface_begin(PRIMITIVE_TRIANGLES)
## and surface_end(). `cols` gives per-point colours (sRGB + alpha); `widths` per-point widths
## (both optional: `col` / `width` are used when they are empty).
static func draw_immediate(im: ImmediateMesh, pts: PackedVector3Array, normal: Vector3, width: float, col: Color, closed: bool = false, cols: PackedColorArray = PackedColorArray(), widths: PackedFloat32Array = PackedFloat32Array()) -> void:
	var n := pts.size()
	if n < 2:
		return
	var per_col := cols.size() == n
	var per_w := widths.size() == n
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_c := col
	for i: int in n:
		var s := side_at(pts, i, normal, closed)
		var hw := (widths[i] if per_w else width) * 0.5
		var l := pts[i] + s * hw
		var r := pts[i] - s * hw
		var c := cols[i] if per_col else col
		if i > 0:
			_tri(im, prev_l, prev_c, 1.0, prev_r, prev_c, -1.0, l, c, 1.0)
			_tri(im, prev_r, prev_c, -1.0, r, c, -1.0, l, c, 1.0)
		prev_l = l
		prev_r = r
		prev_c = c


static func _tri(im: ImmediateMesh, a: Vector3, ca: Color, ea: float, b: Vector3, cb: Color, eb: float, c: Vector3, cc: Color, ec: float) -> void:
	im.surface_set_color(ca)
	im.surface_set_uv(Vector2(ea, 0.0))
	im.surface_add_vertex(a)
	im.surface_set_color(cb)
	im.surface_set_uv(Vector2(eb, 0.0))
	im.surface_add_vertex(b)
	im.surface_set_color(cc)
	im.surface_set_uv(Vector2(ec, 0.0))
	im.surface_add_vertex(c)
