// Fragment of the translucent body twin (actor_body_fx / actor_body_fx_ds): recording-ghost
// hologram (holo), desynced projection (phase), dodge i-frames (body_opacity flicker) and the hollow
// playback ghost (hollow: depth plus a faint rim, so the outline pass behind it shows only the
// silhouette edge). Include after actor_body.gdshaderinc.

void od_body_fx(vec3 normal, mat4 inv_view, out vec3 albedo_out, out float alpha_out) {
	vec3 c = od_cel(normal, inv_view);
	float rim = od_rim(normal);
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	float a = body_opacity;
	if (holo > 0.0) {
		// Hologram: luminance carried in the cassette colour, world-space scanlines crawling upward,
		// a hot rim and periodic tear bands.
		float scan = 0.55 + 0.45 * step(0.5, fract(v_world.y * 38.0 - TIME * 2.2));
		float band = smoothstep(0.96, 1.0, sin(v_world.y * 5.0 - TIME * 3.1) * 0.5 + 0.5);
		vec3 hc = accent.rgb * (0.35 + lum * 1.1) + accent.rgb * rim * 1.6 + vec3(band * 0.6);
		c = mix(c, hc * scan, holo);
		a *= mix(1.0, scan * (0.75 + rim * 0.6) + band * 0.4, holo);
	}
	if (phase > 0.0) {
		// Phased-out projection: horizontal slices drop out and shimmer.
		float slice = step(0.25, fract(v_world.y * 14.0 + floor(TIME * 12.0) * 0.37));
		a *= mix(1.0, slice * (0.6 + 0.4 * rim), phase);
		c = mix(c, c + accent.rgb * rim * 0.6, phase);
	}
	if (hollow > 0.0) {
		c = mix(c, vec3(0.62, 0.65, 0.72), hollow);
		a = mix(a, rim * 0.22, hollow);
	}
	albedo_out = mix(c, flash_col.rgb, flash_col.a);
	alpha_out = clamp(a + flash_col.a * 0.5, 0.0, 1.0);
}
