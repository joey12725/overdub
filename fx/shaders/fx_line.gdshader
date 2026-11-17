// Soft glowing thick lines (port of prototype gpu/polyline.ts): ribbons, epicycles, ticks, frames.
// Geometry is pre-expanded into triangles; UV.x is the signed distance across the line (-1..1),
// COLOR the authored sRGB colour and alpha. Additive, depth-tested so walls still occlude.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled, fog_disabled;

uniform float gain = 1.0;

void fragment() {
	float e = abs(UV.x);
	float a = COLOR.a * pow(max(0.0, 1.0 - e * e), 1.5);
	if (a < 0.003) {
		discard;
	}
	vec3 c = mix(COLOR.rgb, vec3(1.0), (1.0 - smoothstep(0.0, 0.45, e)) * 0.35);
	ALBEDO = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045))) * gain;
	ALPHA = a;
}
