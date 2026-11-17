// One epicycle circle of the edge hologram: a quad scaled to the circle's radius whose fragment
// draws a soft ring of constant world width. Instance uniforms carry radius, width and colour so
// the sixteen circles share one material.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled, fog_disabled;

instance uniform float radius = 1.0;
instance uniform float line_width = 0.025;
instance uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.2);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float th = clamp(line_width / max(radius, 1e-3), 0.004, 0.5);
	float e = abs(r - (1.0 - th)) / th;
	float a = tint.a * pow(max(0.0, 1.0 - e * e), 1.5);
	if (a < 0.003) {
		discard;
	}
	vec3 c = mix(tint.rgb, vec3(1.0), (1.0 - smoothstep(0.0, 0.45, e)) * 0.35);
	ALBEDO = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
	ALPHA = a;
}
