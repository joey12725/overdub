// Screen overlay (port of prototype gpu/overlay.ts): letterbox bars, world-speed tint and speed lines,
// the bar-synced light sweep, flashes, cinematic radial ink speed lines and the desync / recall glitch
// tear. Premultiplied output lets one pass both darken ("over": letterbox, ink lines, tint) and
// brighten ("add": flashes, sweep). Everything except the letterbox stays faint or confined to the
// screen edges so actors, sparks and telegraphs remain readable (chapter 16).
shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

uniform float aspect = 1.7778;
uniform float time = 0.0;
uniform float letterbox = 0.0;
uniform vec4 flash = vec4(0.0);
uniform vec4 tint = vec4(0.0);
uniform vec2 speed = vec2(0.0);
uniform vec2 sweep = vec2(0.0);
// Burst centre in NDC (x right, y up) and amount.
uniform vec3 burst = vec3(0.0);
uniform vec4 glitch = vec4(0.0);
uniform vec3 ink = vec3(0.08, 0.07, 0.06);

float hash11(float p) {
	return fract(sin(p * 91.345) * 47453.5453);
}

void fragment() {
	// y up, like the prototype's clip-space quad.
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	vec2 p = uv * 2.0 - 1.0;
	vec2 pa = vec2(p.x * aspect, p.y);
	float r = length(pa) / max(aspect, 1.0);
	float ang = atan(p.y, p.x * aspect);
	vec3 add = vec3(0.0);
	vec3 over_col = vec3(0.0);
	float over_a = 0.0;

	// World-speed tint, weighted to the edges so the playfield centre stays true-colour.
	float vig = smoothstep(0.45, 1.3, r);
	over_col = tint.rgb;
	over_a = tint.a * (0.35 + 0.65 * vig);

	// World-speed lines: streaming outward when the world is sped up, slow inward ripples when it is
	// slowed. Confined to the outer ring of the screen.
	if (speed.x > 0.001) {
		float edge = smoothstep(0.6, 1.05, r);
		if (speed.y > 0.0) {
			float lane = floor(ang * 38.0);
			float h = hash11(lane);
			float flow = fract(r * 1.6 - time * (1.2 + h) + h * 7.0);
			float ln = step(0.78, h) * smoothstep(0.0, 0.1, flow) * (1.0 - smoothstep(0.35, 0.6, flow));
			add += tint.rgb * ln * edge * speed.x * 0.14;
		} else {
			float ring = fract(r * 4.0 + time * 0.22);
			float band = smoothstep(0.0, 0.04, ring) * (1.0 - smoothstep(0.04, 0.1, ring));
			add += tint.rgb * band * edge * speed.x * 0.08;
		}
	}

	// Bar-synced light sweep (cinematic): a soft diagonal band crossing once per bar.
	if (sweep.y > 0.001) {
		float d = (uv.x * 0.8 + uv.y * 0.45) - (sweep.x * 1.9 - 0.45);
		add += vec3(1.0, 0.97, 0.9) * exp(-d * d * 60.0) * sweep.y;
	}

	// Radial ink speed lines around a cinematic impact: manga-style wedges that converge on the impact
	// but are drawn only in the outer rim of the screen. Both the burst's inner radius and the screen
	// centre stay clear, so the impact, the actors and the sparks are never covered.
	if (burst.z > 0.01) {
		vec2 q = vec2((p.x - burst.x) * aspect, p.y - burst.y);
		float rq = length(q);
		float aq = atan(q.y, q.x);
		float lane = floor(aq * 30.0);
		float h = hash11(lane + 13.0);
		float lw = fract(aq * 30.0);
		// Constant angular width = a wedge that thickens outward; each lane gets its own taper.
		float thin = 1.0 - smoothstep(0.05, 0.16 + 0.22 * h, abs(lw - 0.5) * 2.0);
		float rim = smoothstep(0.62 + 0.12 * h, 1.05, r);
		float mask = smoothstep(0.5 + 0.2 * h, 1.1, rq) * rim * step(0.5, h);
		float k = thin * mask * burst.z * 0.7;
		over_col = mix(over_col, ink, k / max(over_a + k, 1e-3));
		over_a = over_a + k * (1.0 - over_a);
	}

	// Glitch tear (desync, boss recall): a few horizontal bands flicker in the tape colour.
	if (glitch.a > 0.01) {
		float row = floor(uv.y * 90.0);
		float h = hash11(row + floor(time * 24.0) * 3.1);
		// Each torn row covers only a short horizontal span so it reads as tape damage, not a UI bar.
		float x0 = hash11(row * 1.7 + floor(time * 24.0));
		float span = step(x0, uv.x) * step(uv.x, x0 + 0.08 + 0.25 * hash11(row + 5.0));
		float band = step(0.95 - glitch.a * 0.08, h) * span;
		// Scan texture inside the torn row plus a red / cyan split at its ends: VHS damage, not a bar.
		float scan = 0.55 + 0.45 * sin(uv.x * 900.0 + time * 40.0 + row);
		float split = step(x0 - 0.012, uv.x) * step(uv.x, x0) * step(0.95 - glitch.a * 0.08, h);
		vec3 tear = glitch.rgb * band * scan + vec3(1.0, 0.15, 0.3) * split;
		add += tear * glitch.a * 0.32;
	}

	// Chord / impact flashes.
	add += flash.rgb * flash.a * (0.55 + 0.45 * vig);

	// Letterbox bars (cinematic) - solid ink, drawn last.
	if (letterbox > 0.0005 && (uv.y < letterbox || uv.y > 1.0 - letterbox)) {
		COLOR = vec4(ink, 1.0);
	} else {
		COLOR = vec4(over_col * over_a + add, over_a);
	}
}
