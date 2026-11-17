// OVERDUB soft contact shadow / stain: a flat quad that darkens what is under it with a round
// falloff. For props' contact shadows, floor stains and actors' feet. Draw it on a horizontal quad
// a few millimetres above the surface. MultiMesh instance colour: alpha scales opacity, red seeds
// the ragged edge (so neighbouring stains differ).
// Uniforms: shaders/README.md.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(0.12, 0.08, 0.08, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.42;
// 0 = hard disc edge, 1 = fully soft.
uniform float softness : hint_range(0.0, 1.0) = 0.75;
// Irregular edge (stains) 0..1.
uniform float ragged : hint_range(0.0, 1.0) = 0.0;

instance uniform float instance_opacity : instance_index(7) = 1.0;

float h(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 d = (UV - 0.5) * 2.0;
	float r = length(d);
	if (ragged > 0.0) {
		float a = atan(d.y, d.x);
		float k = floor((a + PI) / (TAU / 9.0));
		r *= 1.0 + ragged * 0.35 * (h(vec2(k, COLOR.r * 31.0)) - 0.5);
	}
	float edge = 1.0 - smoothstep(1.0 - softness, 1.0, r);
	ALBEDO = color.rgb;
	ALPHA = clamp(edge * opacity * COLOR.a * instance_opacity, 0.0, 1.0);
}
