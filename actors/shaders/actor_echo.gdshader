// Chromatic-split echo of a desynced body: the same skinned mesh shifted along the camera's right
// axis, additive red (echo_sign +1) or cyan (echo_sign -1). Shift and strength are per instance.
shader_type spatial;
render_mode unshaded, cull_back, blend_add, depth_draw_never, world_vertex_coords;

uniform vec3 echo_tint : source_color = vec3(1.0, 0.25, 0.3);
uniform float echo_sign = 1.0;
instance uniform vec3 echo_shift : instance_index(12) = vec3(0.0);
instance uniform float echo_amt : instance_index(13) = 0.0;

void vertex() {
	VERTEX += echo_shift * echo_sign;
}

void fragment() {
	if (echo_amt <= 0.003) {
		discard;
	}
	ALBEDO = echo_tint;
	ALPHA = echo_amt;
}
