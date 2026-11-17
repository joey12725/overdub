// World-space combat readouts drawn from the word atlas (port of prototype gpu/textMesh.ts).
// The atlas is inked in three channels: red = fill (tinted per readout), green = heavy ink outline,
// blue = offset drop shadow - bold, hand-inked anime-graphic lettering (chapter 17 "Art style").
// Per instance (FxTextPool.write_instances): MODEL_MATRIX[0] = (rot, aspect, height),
// [3] = position, INSTANCE_CUSTOM = atlas rect (u0, v0, u1, v1). Readouts must stay legible over
// walls and props, so they ignore depth.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, skip_vertex_transform, blend_mix, shadows_disabled, fog_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 ink : source_color = vec3(0.08, 0.07, 0.06);

varying vec2 v_local;

void vertex() {
	vec4 c0 = MODEL_MATRIX[0];
	vec3 pos = MODEL_MATRIX[3].xyz;
	float rot = c0.x;
	float aspect = c0.y;
	float h = c0.z;
	vec2 c = VERTEX.xy; // -0.5..0.5
	vec4 rect = INSTANCE_CUSTOM;
	UV = vec2(mix(rect.x, rect.z, c.x + 0.5), mix(rect.w, rect.y, c.y + 0.5));
	v_local = c * 2.0;
	vec2 q = vec2(c.x * h * aspect, c.y * h);
	q = vec2(q.x * cos(rot) - q.y * sin(rot), q.x * sin(rot) + q.y * cos(rot));
	vec3 mv = (VIEW_MATRIX * vec4(pos, 1.0)).xyz;
	mv.xy += q;
	VERTEX = mv;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec4 t = texture(atlas, UV);
	float cov = t.a;
	if (cov * COLOR.a < 0.01) {
		discard;
	}
	float sum = max(t.r + t.g + t.b, 1e-3);
	// Fill gets a light top-to-bottom ramp for a printed, graphic feel.
	vec3 tint = COLOR.rgb;
	tint = mix(pow((tint + vec3(0.055)) / 1.055, vec3(2.4)), tint / 12.92, lessThan(tint, vec3(0.04045)));
	vec3 fill = tint * (0.9 + 0.22 * v_local.y) + 0.06;
	vec3 shadow = ink * 0.55 + tint * 0.12;
	ALBEDO = (fill * t.r + ink * t.g + shadow * t.b) / sum;
	ALPHA = cov * COLOR.a;
}
