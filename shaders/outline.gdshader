// OVERDUB ink outline: inverted hull, used as the toon material's next_pass.
// The hull is pushed out in clip space, so the line is `thickness_px` screen pixels wide at any
// zoom (orthographic or perspective). Uniforms: shaders/README.md.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, blend_mix, shadows_disabled, fog_disabled;

uniform vec4 outline_color : source_color = vec4(0.09, 0.06, 0.06, 1.0);
// Line width in viewport pixels.
uniform float thickness_px = 2.0;
// Use the smoothed normal ToonKit bakes into CUSTOM0 (closes the gaps hard-edged meshes get).
// Ignored where a vertex has no CUSTOM0 data. Skinned meshes keep NORMAL (CUSTOM0 is not skinned).
uniform bool use_smooth_normal = true;
// Push the hull slightly away from the camera (world units) so it never pokes through thin parts.
uniform float depth_push = 0.0;

// Per-node override: when a > 0 it replaces outline_color (selves carry their cassette colour).
instance uniform vec4 instance_outline : source_color, instance_index(2) = vec4(0.0, 0.0, 0.0, 0.0);
// Per-node width multiplier (0 hides the outline on that node). Default 1.
instance uniform float instance_outline_scale : instance_index(3) = 1.0;

void vertex() {
	vec3 n = NORMAL;
	if (use_smooth_normal && dot(CUSTOM0.xyz, CUSTOM0.xyz) > 0.25) {
		n = CUSTOM0.xyz;
	}
	vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view_pos.z -= depth_push;
	vec4 clip = PROJECTION_MATRIX * view_pos;
	vec3 n_view = normalize((MODELVIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec2 dir_px = (PROJECTION_MATRIX * vec4(n_view, 0.0)).xy * VIEWPORT_SIZE;
	float len = length(dir_px);
	if (len > 1e-6) {
		dir_px /= len;
		clip.xy += dir_px * (thickness_px * instance_outline_scale * 2.0) / VIEWPORT_SIZE * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	vec4 c = instance_outline.a > 0.0 ? instance_outline : outline_color;
	ALBEDO = c.rgb;
}
