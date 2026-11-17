// OVERDUB unlit emissive surface (neon tubes, lamps, screens, accents). Colour * energy is written
// in HDR, so energy > ~1.2 blooms through the WorldEnvironment glow. Uniforms: shaders/README.md.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 2.0;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform bool use_texture = false;
uniform vec2 uv_scale = vec2(1.0);
// Scrolls the texture (units per second, TIME-driven): screens, exit chevrons.
uniform vec2 uv_scroll = vec2(0.0);
uniform vec2 uv_offset = vec2(0.0);

// Per-node multiplier on energy (default 1) and colour override (used when a > 0).
instance uniform float instance_energy : instance_index(5) = 1.0;
instance uniform vec4 instance_color : source_color, instance_index(6) = vec4(0.0, 0.0, 0.0, 0.0);

void fragment() {
	vec3 c = instance_color.a > 0.0 ? instance_color.rgb : color.rgb;
	if (use_texture) {
		c *= texture(tex, UV * uv_scale + uv_offset + uv_scroll * TIME).rgb;
	}
	ALBEDO = c * energy * instance_energy;
}
