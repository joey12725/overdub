// Flat marker / ground decal / strip shading (prototype materials.ts createFlatMaterial +
// createStripMaterial). UV.x runs along a strip (0 at its origin, 1 at the far end) or outward along
// a sector's radius; UV.y runs across. Every parameter is per instance, so one material per blend
// mode serves every ring, telegraph, tether and target line.
//   fill   telegraph: a faint full-size backing (back) plus a solid front filling outward to fill
//          (fill >= 2 = plain flat colour)
//   edge   side-edge highlight (cones, strips); negative fades the sides
//   dash   dash period in tiles (0 = solid), scrolled with TIME; len = the strip length in tiles
//   fade   1 = fade toward UV.x = 0 (streak tails)

instance uniform vec4 color : source_color = vec4(1.0);
instance uniform float fill = 2.0;
instance uniform float back = 1.0;
instance uniform float edge = 0.0;
instance uniform float dash = 0.0;
instance uniform float len = 1.0;
instance uniform float fade = 0.0;

void fragment() {
	float a = color.a * mix(1.0, UV.x * UV.x, fade);
	float filled = step(UV.x, fill);
	float front = smoothstep(fill - 0.04, fill, UV.x) * filled * step(fill, 1.5);
	a *= mix(back, 1.0, filled) + front * 0.8;
	float e = 1.0 - smoothstep(0.0, 0.12, min(UV.y, 1.0 - UV.y));
	a *= max(0.0, 1.0 + e * edge);
	if (dash > 0.0) {
		float d = fract(UV.x * len / dash - TIME * 1.5);
		a *= step(0.45, d);
	}
	if (a <= 0.003) {
		discard;
	}
	ALBEDO = color.rgb;
	ALPHA = min(a, 1.0);
}
