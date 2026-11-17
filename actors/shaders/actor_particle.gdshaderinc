// Camera-facing soft round particles for a MultiMesh: per-instance transform (position + size in
// the basis scale) and colour (rgb + alpha). Used by ActorParticles (dust, glow, smoke, bursts) and
// the recovery spark's comet trail.

uniform float soft = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 d = UV - 0.5;
	float r = length(d) * 2.0;
	if (r > 1.0 || COLOR.a <= 0.002) {
		discard;
	}
	float core = 1.0 - smoothstep(0.0, 1.0, r);
	ALBEDO = COLOR.rgb * (1.0 + (1.0 - r) * 0.6 * soft);
	ALPHA = COLOR.a * mix(1.0, core, soft);
}
