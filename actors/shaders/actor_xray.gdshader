// X-ray silhouette: drawn on top of everything, but only where the body is hidden behind level
// geometry. Flat colour per instance: the cassette colour for selves, a warning tint for enemies, so
// nothing important is ever hidden.
//
// Godot 4.4 has no stencil / depth-test-greater, so the pass compares its own view depth with the
// opaque depth texture. The model's own layers (pigtails behind the face, a jacket over the top, an
// arm across the chest) are in that depth texture too, so an occluder must not count when it could be
// part of the actor itself. The actor is bounded by a vertical cylinder `xray_volume` (world centre
// x, centre z, radius, top), kept up to date by ActorRig.update_xray(): walking back along the view
// ray from this fragment, the ray leaves that cylinder at depth `my_z - s`; anything nearer than that
// is foreign geometry (a wall, a pillar), anything between is the actor's own body. Fragments outside
// the cylinder (a long weapon held out) fall back to a fixed margin in the w component when the
// radius is 0.
shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
instance uniform vec4 xray_color : source_color, instance_index(14) = vec4(1.0, 1.0, 1.0, 0.0);
instance uniform vec4 xray_volume : instance_index(15) = vec4(0.0, 0.0, 0.0, 0.45);

// Occluders this close to the actor's own volume still count as the actor (skinning slop, an outline
// hull pushed back from the camera).
const float SLOP = 0.06;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// How far (along the view ray, toward the camera) from `p` the ray stays inside the actor volume.
float od_inside_depth(vec3 p, vec3 to_cam) {
	float r = xray_volume.z;
	vec2 q = p.xz - xray_volume.xy;
	vec2 b = to_cam.xz;
	float bb = dot(b, b);
	float s = 0.0;
	float qq = dot(q, q) - r * r;
	if (qq > 0.0) {
		return 0.0;
	}
	if (bb > 1e-6) {
		float qb = dot(q, b);
		float disc = qb * qb - bb * qq;
		s = (-qb + sqrt(max(disc, 0.0))) / bb;
	} else {
		s = 1e3;
	}
	// The camera looks down: going back toward it the ray climbs and leaves through the top.
	if (to_cam.y > 1e-4) {
		s = min(s, max(0.0, (xray_volume.w - p.y) / to_cam.y));
	}
	return max(s, 0.0);
}

void fragment() {
	if (xray_color.a <= 0.003) {
		discard;
	}
	float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = -v.z / v.w;
	float my_z = -VERTEX.z;
	float margin;
	if (xray_volume.z > 0.0) {
		vec3 fwd = -INV_VIEW_MATRIX[2].xyz;
		// Orthographic: every view ray is parallel to the camera's forward axis.
		vec3 to_cam = PROJECTION_MATRIX[3][3] > 0.5 ? -fwd : normalize(CAMERA_POSITION_WORLD - v_world);
		margin = od_inside_depth(v_world, to_cam) * max(dot(to_cam, -fwd), 0.0) + SLOP;
	} else {
		margin = xray_volume.w;
	}
	if (my_z <= scene_z + margin) {
		discard;
	}
	float rim = pow(1.0 - clamp(abs(NORMAL.z), 0.0, 1.0), 2.0);
	float hatch = 0.85 + 0.15 * step(0.5, fract((FRAGCOORD.x + FRAGCOORD.y) * 0.125));
	ALBEDO = xray_color.rgb * (0.8 + 0.6 * rim);
	ALPHA = xray_color.a * (0.42 + 0.58 * rim) * hatch;
}
