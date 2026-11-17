// Inverted-hull ink outline (next pass of an opaque body). Colour per instance: the cassette
// colour for selves (UI-02), ink for enemies. Width is in model units; models are built at final
// size with unit scale and the camera is orthographic, so it reads as a constant screen width.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

instance uniform vec4 outline_color : source_color, instance_index(10) = vec4(0.12, 0.08, 0.07, 1.0);
instance uniform float outline_width : instance_index(11) = 0.012;

// Push the hull this far (world units) away from the camera: a hull that pokes through an outer
// layer (legs under baggy trousers, a body under a jacket) then sits behind that layer and is
// depth-culled, while the silhouette, with only floor or background behind it, keeps its ink.
uniform float depth_push = 0.045;

void vertex() {
	VERTEX += normalize(NORMAL) * outline_width;
	// Camera forward (it looks down its -Z) in model space, normalised against the model's scale.
	vec3 fwd_model = inverse(mat3(MODEL_MATRIX)) * -INV_VIEW_MATRIX[2].xyz;
	VERTEX += normalize(fwd_model) * depth_push;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
