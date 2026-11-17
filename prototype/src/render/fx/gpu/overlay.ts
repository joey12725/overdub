/**
 * Camera-space overlay: letterbox bars, world-speed tint and speed lines, the bar-synced light
 * sweep, flashes, cinematic radial ink speed lines and the desync / recall glitch tear.
 *
 * Drawn as one full-screen quad straight in clip space (works with any camera, no scene-graph
 * parenting). Premultiplied output lets one pass both darken ("over": letterbox, ink lines, tint)
 * and brighten ("add": flashes, sweep). Everything except the letterbox stays faint or confined to
 * the screen edges so actors, sparks and telegraphs remain readable (chapter 16).
 */
import * as THREE from 'three';
import type { ScreenFx } from '../director';

const VERT = /* glsl */ `
varying vec2 vUv;
void main() {
  vUv = position.xy * 0.5 + 0.5;
  gl_Position = vec4(position.xy, 0.0, 1.0);
}
`;

const FRAG = /* glsl */ `
uniform float uAspect;
uniform float uTime;
uniform float uLetterbox;
uniform vec4 uFlash;
uniform vec4 uTint;
uniform vec2 uSpeed;
uniform vec2 uSweep;
uniform vec3 uBurst;
uniform vec4 uGlitch;
uniform vec3 uInk;
varying vec2 vUv;

float hash11(float p) { return fract(sin(p * 91.345) * 47453.5453); }

void main() {
  vec2 uv = vUv;
  vec2 p = uv * 2.0 - 1.0;
  vec2 pa = vec2(p.x * uAspect, p.y);
  float r = length(pa) / max(uAspect, 1.0);
  float ang = atan(p.y, p.x * uAspect);
  vec3 add = vec3(0.0);
  vec3 overCol = vec3(0.0);
  float overA = 0.0;

  // World-speed tint, weighted to the edges so the playfield centre stays true-colour.
  float vig = smoothstep(0.45, 1.3, r);
  float tintA = uTint.a * (0.35 + 0.65 * vig);
  overCol = uTint.rgb; overA = tintA;

  // World-speed lines: streaming outward when the world is sped up, slow inward ripples when it
  // is slowed. Confined to the outer ring of the screen.
  if (uSpeed.x > 0.001) {
    float edge = smoothstep(0.6, 1.05, r);
    if (uSpeed.y > 0.0) {
      float lane = floor(ang * 38.0);
      float h = hash11(lane);
      float flow = fract(r * 1.6 - uTime * (1.2 + h) + h * 7.0);
      float line = step(0.78, h) * smoothstep(0.0, 0.1, flow) * (1.0 - smoothstep(0.35, 0.6, flow));
      add += uTint.rgb * line * edge * uSpeed.x * 0.14;
    } else {
      float ring = fract(r * 4.0 + uTime * 0.22);
      float band = smoothstep(0.0, 0.04, ring) * (1.0 - smoothstep(0.04, 0.1, ring));
      add += uTint.rgb * band * edge * uSpeed.x * 0.08;
    }
  }

  // Bar-synced light sweep (cinematic): a soft diagonal band crossing once per bar.
  if (uSweep.y > 0.001) {
    float d = (uv.x * 0.8 + uv.y * 0.45) - (uSweep.x * 1.9 - 0.45);
    add += vec3(1.0, 0.97, 0.9) * exp(-d * d * 60.0) * uSweep.y;
  }

  // Radial ink speed lines around a cinematic impact. The inner radius stays clear so the impact,
  // the actors and the sparks are never covered.
  if (uBurst.z > 0.01) {
    vec2 q = vec2((p.x - uBurst.x) * uAspect, p.y - uBurst.y);
    float rq = length(q);
    float aq = atan(q.y, q.x);
    float lane = floor(aq * 30.0);
    float h = hash11(lane + 13.0);
    float lw = fract(aq * 30.0);
    float thin = 1.0 - smoothstep(0.0, 0.18 + 0.25 * h, abs(lw - 0.5) * 2.0 * (0.4 + rq));
    float mask = smoothstep(0.45 + 0.2 * h, 1.1, rq) * step(0.55, h);
    float ink = thin * mask * uBurst.z * 0.6;
    overCol = mix(overCol, uInk, ink / max(overA + ink, 1e-3));
    overA = overA + ink * (1.0 - overA);
  }

  // Glitch tear (desync, boss recall): a few horizontal bands flicker in the tape colour.
  if (uGlitch.a > 0.01) {
    float row = floor(uv.y * 90.0);
    float h = hash11(row + floor(uTime * 24.0) * 3.1);
    // Each torn row covers only a short horizontal span so it reads as tape damage, not a UI bar.
    float x0 = hash11(row * 1.7 + floor(uTime * 24.0));
    float span = step(x0, uv.x) * step(uv.x, x0 + 0.08 + 0.25 * hash11(row + 5.0));
    float band = step(0.95 - uGlitch.a * 0.08, h) * span;
    add += uGlitch.rgb * band * uGlitch.a * 0.16;
  }

  // Chord / impact flashes.
  add += uFlash.rgb * uFlash.a * (0.55 + 0.45 * vig);

  // Letterbox bars (cinematic) — solid ink, drawn last.
  float lb = uLetterbox;
  if (lb > 0.0005 && (uv.y < lb || uv.y > 1.0 - lb)) {
    gl_FragColor = vec4(uInk, 1.0);
    return;
  }

  // Premultiplied: rgb = over·a + add, alpha = a  (blend: ONE, ONE_MINUS_SRC_ALPHA).
  if (overA < 0.001 && dot(add, vec3(1.0)) < 0.002) discard;
  gl_FragColor = vec4(overCol * overA + add, overA);
}
`;

export class ScreenOverlay {
  readonly mesh: THREE.Mesh;
  private readonly mat: THREE.ShaderMaterial;
  private readonly geo: THREE.PlaneGeometry;
  private readonly v = new THREE.Vector3();

  constructor() {
    this.geo = new THREE.PlaneGeometry(2, 2);
    this.mat = new THREE.ShaderMaterial({
      vertexShader: VERT,
      fragmentShader: FRAG,
      uniforms: {
        uAspect: { value: 16 / 9 },
        uTime: { value: 0 },
        uLetterbox: { value: 0 },
        uFlash: { value: new THREE.Vector4() },
        uTint: { value: new THREE.Vector4() },
        uSpeed: { value: new THREE.Vector2() },
        uSweep: { value: new THREE.Vector2() },
        uBurst: { value: new THREE.Vector3() },
        uGlitch: { value: new THREE.Vector4() },
        uInk: { value: new THREE.Color(0x14110f) },
      },
      transparent: true,
      depthTest: false,
      depthWrite: false,
      blending: THREE.CustomBlending,
      blendSrc: THREE.OneFactor,
      blendDst: THREE.OneMinusSrcAlphaFactor,
      blendSrcAlpha: THREE.ZeroFactor,
      blendDstAlpha: THREE.OneFactor,
    });
    this.mesh = new THREE.Mesh(this.geo, this.mat);
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = 10000;
    this.mesh.name = 'fx-overlay';
    this.mesh.userData.fx = true;
    this.mesh.userData.fxOverlay = true;
    this.mesh.userData.noOutline = true;
  }

  setInk(ink: number): void {
    (this.mat.uniforms.uInk.value as THREE.Color).setHex(ink);
  }

  sync(sc: ScreenFx, camera: THREE.OrthographicCamera): void {
    const u = this.mat.uniforms;
    const w = camera.right - camera.left;
    const h = camera.top - camera.bottom;
    u.uAspect.value = h !== 0 ? Math.abs(w / h) : 1;
    u.uTime.value = sc.time;
    u.uLetterbox.value = sc.letterbox;
    (u.uFlash.value as THREE.Vector4).set(sc.flash[0], sc.flash[1], sc.flash[2], sc.flashA);
    (u.uTint.value as THREE.Vector4).set(sc.tint[0], sc.tint[1], sc.tint[2], sc.tintA);
    (u.uSpeed.value as THREE.Vector2).set(sc.speed, sc.speedSign);
    (u.uSweep.value as THREE.Vector2).set(sc.sweepPos, sc.sweepA);
    if (sc.burstAmt > 0) {
      this.v.set(sc.burst[0], sc.burst[1], sc.burst[2]).project(camera);
      (u.uBurst.value as THREE.Vector3).set(this.v.x, this.v.y, sc.burstAmt);
    } else {
      (u.uBurst.value as THREE.Vector3).set(0, 0, 0);
    }
    (u.uGlitch.value as THREE.Vector4).set(sc.glitchColor[0], sc.glitchColor[1], sc.glitchColor[2], sc.glitch);
    const active =
      sc.letterbox > 0.0005 || sc.flashA > 0.002 || sc.tintA > 0.001 || sc.speed > 0.001 || sc.sweepA > 0.002 || sc.burstAmt > 0.01 || sc.glitch > 0.01;
    this.mesh.visible = active;
  }

  dispose(): void {
    this.geo.dispose();
    this.mat.dispose();
  }
}
