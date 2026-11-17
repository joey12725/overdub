// OVERDUB x-ray silhouette: a flat, see-through colour drawn only where the mesh is hidden behind
// other geometry (walls, props), so selves and enemies are never lost (GODOT-PORT "Presentation").
//
// Godot 4.4 has no depth-test-greater, so the pass runs with the depth test off and compares its
// own view depth with the opaque depth buffer: a fragment is drawn only when something opaque is at
// least `occlusion_margin` world units nearer to the camera. Use it as an extra next_pass after the
// outline (ToonKit.with_xray()). Uniforms: shaders/README.md.
shader_type spatial;
render_mode unshaded, cull_back, depth_test_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec4 xray_color : source_color = vec4(0.95, 0.95, 1.0, 0.55);
// Minimum gap (world units) between the occluder and this fragment; keeps the mesh's own limbs
// (arm in front of torso) from counting as occluders.
uniform float occlusion_margin = 0.35;
// Rim emphasis 0..1: silhouette edges more opaque than the interior.
uniform float rim_boost : hint_range(0.0, 1.0) = 0.6;
// Screen-space dither stripes (0 = solid fill); reads as "behind" at a glance.
uniform float stripe_strength : hint_range(0.0, 1.0) = 0.35;

// Per-node override: when a > 0 it replaces xray_color (cassette colour for selves).
instance uniform vec4 instance_xray : source_color, instance_index(4) = vec4(0.0, 0.0, 0.0, 0.0);

void fragment() {
	float raw = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	float scene_z = scene_view.z / scene_view.w;
	// View space looks down -Z: a larger z is nearer the camera.
	if (scene_z < VERTEX.z + occlusion_margin) {
		discard;
	}
	vec4 c = instance_xray.a > 0.0 ? instance_xray : xray_color;
	float rim = 1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float stripes = step(0.5, fract((FRAGCOORD.x + FRAGCOORD.y) * 0.125));
	ALBEDO = c.rgb;
	ALPHA = clamp(c.a * (1.0 - stripe_strength * stripes) + rim * rim_boost * c.a, 0.0, 1.0);
}
