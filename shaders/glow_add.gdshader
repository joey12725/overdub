// OVERDUB additive glow (halos, beams, floor light pools, guides). Never writes depth, both faces.
// Uniforms: shaders/README.md.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 1.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform bool use_texture = false;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_scroll = vec2(0.0);
uniform vec2 uv_offset = vec2(0.0);
// Soft radial falloff from the UV centre (0 = flat, 1 = round pool fading to the edge).
uniform float radial : hint_range(0.0, 1.0) = 0.0;
// Fade toward silhouettes (for halo shells): 0 = off.
uniform float fresnel_fade : hint_range(0.0, 1.0) = 0.0;

instance uniform float instance_energy : instance_index(5) = 1.0;
instance uniform vec4 instance_color : source_color, instance_index(6) = vec4(0.0, 0.0, 0.0, 0.0);

void fragment() {
	vec3 c = instance_color.a > 0.0 ? instance_color.rgb : color.rgb;
	float a = opacity;
	if (use_texture) {
		vec4 t = texture(tex, UV * uv_scale + uv_offset + uv_scroll * TIME);
		c *= t.rgb;
		a *= t.a;
	}
	if (radial > 0.0) {
		float d = length(UV - 0.5) * 2.0;
		a *= mix(1.0, pow(clamp(1.0 - d, 0.0, 1.0), 1.6), radial);
	}
	if (fresnel_fade > 0.0) {
		a *= mix(1.0, pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.5), fresnel_fade);
	}
	ALBEDO = c * energy * instance_energy * a;
}
