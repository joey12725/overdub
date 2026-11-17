shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;
// OVERDUB combat feel: the impact-frame flash, used as a material_overlay on a struck actor.
// amount 0..1 covers the actor in `color`; invert > 0.5 draws the anime "negative" frame instead
// (ink-black body), which the outline pass turns into a white-on-black silhouette.
uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float amount = 0.0;
uniform float invert = 0.0;

void fragment() {
	vec3 c = mix(color.rgb, vec3(0.05, 0.03, 0.07), step(0.5, invert));
	ALBEDO = c;
	ALPHA = clamp(amount, 0.0, 1.0);
	if (ALPHA < 0.01) { discard; }
}
