shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled, world_vertex_coords;
// OVERDUB combat feel: an afterimage (dodge, fast-tape swings). A flat cassette-coloured cut-out
// that thins into horizontal scan bands as it dies, like a tape ghost, never a soft fade.
instance uniform vec4 tint : source_color = vec4(0.4, 0.9, 1.0, 1.0);
instance uniform float life = 0.0;     // 0 fresh .. 1 gone
instance uniform float opacity = 0.6;

void vertex() {
	// Sit a little behind the live body (away from the camera) so a fresh ghost never covers it.
	VERTEX += CAMERA_DIRECTION_WORLD * 0.3;
}

void fragment() {
	float bands = step(life * 1.15, fract(FRAGCOORD.y / 5.0));
	float rimf = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	ALBEDO = mix(tint.rgb, vec3(1.0), rimf * 0.7);
	ALPHA = opacity * (1.0 - life * 0.6) * bands;
	if (ALPHA < 0.02) { discard; }
}
