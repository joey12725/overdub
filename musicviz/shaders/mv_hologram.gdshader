// Hologram projection for the epicycle showpiece (musicviz/, MUSIC-12): a light-like, camera-facing
// (Y-axis billboard) quad showing an MVCanvas texture with scanlines, a slow vertical sweep, a faint
// flicker and soft edges. Visual only: no depth write, no shadows.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_premul_alpha;

// The canvas texture is sRGB (source_color): read as linear it would wash every colour pale.
uniform sampler2D tex : source_color, filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float energy = 2.2;
uniform float scan_density = 220.0;
uniform float scan_strength = 0.35;
uniform float flicker = 0.06;
uniform float intensity = 1.0;
uniform bool billboard = true;
// 1 = purely additive light (dark depths); toward 0 = drawn over the scene so its ink and
// colour hold up against pale sunlit stone (warm ruins).
uniform float additive : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
			vec4(0.0, 1.0, 0.0, 0.0),
			vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
			MODEL_MATRIX[3]);
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	vec4 c = texture(tex, UV);
	float scan = 1.0 - scan_strength * (0.5 + 0.5 * sin(UV.y * scan_density + TIME * 6.0));
	float sweep = smoothstep(0.0, 0.08, 0.08 - abs(fract(UV.y * 0.5 - TIME * 0.12) - 0.5) + 0.04);
	float fl = 1.0 - flicker * (0.5 + 0.5 * sin(TIME * 37.0) * sin(TIME * 11.3));
	vec2 e = min(UV, 1.0 - UV);
	float edge = smoothstep(0.0, 0.06, min(e.x, e.y));
	float bottom = mix(0.75, 1.0, smoothstep(1.0, 0.7, UV.y));
	float k = scan * fl * edge * bottom * (1.0 + 0.6 * sweep) * intensity;
	// Premultiplied blend: out = ALBEDO + dst * (1 - ALPHA). The texture is premultiplied, so
	// ALPHA = 0 adds the light and ALPHA = c.a draws it over the scene.
	k = clamp(k, 0.0, 1.0);
	ALBEDO = c.rgb * tint.rgb * energy * k;
	ALPHA = clamp(c.a * k * (1.0 - additive), 0.0, 1.0);
}
