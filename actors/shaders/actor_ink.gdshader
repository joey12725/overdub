// Inner ink line of the two-tier outline on a textured self (actor_body -> actor_ink ->
// actor_outline -> x-ray): a thin inverted hull in the room's ink colour hugging the body, with the
// wider cassette-coloured hull of actor_outline behind it. The painted model keeps its own colours;
// identity is the coloured band outside the ink line. Width follows the instance's outline_width
// (the same slot the outer hull reads), so states that thicken or thin the hull move both.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

instance uniform float outline_width : instance_index(11) = 0.012;

uniform vec3 ink_color : source_color = vec3(0.12, 0.08, 0.07);
// Share of outline_width the ink line takes.
uniform float ink_ratio = 0.42;
uniform float depth_push = 0.03;

void vertex() {
	VERTEX += normalize(NORMAL) * outline_width * ink_ratio;
	vec3 fwd_model = inverse(mat3(MODEL_MATRIX)) * -INV_VIEW_MATRIX[2].xyz;
	VERTEX += normalize(fwd_model) * depth_push;
}

void fragment() {
	ALBEDO = ink_color;
}
