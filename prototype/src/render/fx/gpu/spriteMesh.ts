/**
 * GPU side of a SpritePool: one instanced quad mesh whose fragment shader draws every procedural
 * shape (shapes.ts). Instance buffers are allocated once at full pool capacity and refilled in place.
 */
import * as THREE from 'three';
import type { SpritePool } from '../pool';

const VERT = /* glsl */ `
attribute vec4 iPosSize;
attribute vec4 iColor;
attribute vec4 iDir;
attribute vec4 iParams;
varying vec2 vUv;
varying vec4 vColor;
varying float vShape;
varying float vParam;
varying float vT;
void main() {
  float shapeMode = iParams.x;
  float mode = floor(shapeMode / 32.0 + 0.001);
  vShape = shapeMode - mode * 32.0;
  vParam = iParams.y;
  vT = iParams.w;
  float rot = iParams.z;
  vec2 c = position.xy * 2.0;
  vUv = c;
  vColor = iColor;
  float s = iPosSize.w;
  float cr = cos(rot);
  float sr = sin(rot);
  vec2 rc = vec2(c.x * cr - c.y * sr, c.x * sr + c.y * cr);
  vec4 mv;
  if (mode < 0.5) {
    mv = modelViewMatrix * vec4(iPosSize.xyz, 1.0);
    mv.xy += rc * s;
  } else if (mode < 1.5) {
    vec3 wp = iPosSize.xyz + vec3(rc.x * s, 0.0, rc.y * s);
    mv = modelViewMatrix * vec4(wp, 1.0);
  } else {
    vec4 a = modelViewMatrix * vec4(iPosSize.xyz, 1.0);
    vec4 b = modelViewMatrix * vec4(iPosSize.xyz + iDir.xyz, 1.0);
    vec2 d = b.xy - a.xy;
    float L = length(d);
    d = L > 1e-5 ? d / L : vec2(1.0, 0.0);
    vec2 n = vec2(-d.y, d.x);
    mv = a;
    mv.xy += d * c.x * s * iDir.w + n * c.y * s;
  }
  gl_Position = projectionMatrix * mv;
}
`;

const FRAG = /* glsl */ `
uniform float uAdditive;
varying vec2 vUv;
varying vec4 vColor;
varying float vShape;
varying float vParam;
varying float vT;

float ringMask(float r, float rad, float th) {
  return smoothstep(th, th * 0.35, abs(r - rad));
}
float hash11(float p) {
  return fract(sin(p * 127.1) * 43758.5453);
}

void main() {
  vec2 p = vUv;
  float r = length(p);
  float ang = atan(p.y, p.x);
  float a = 0.0;
  float core = 0.0;
  vec3 col = vColor.rgb;
  float s = floor(vShape + 0.5);

  if (s < 0.5) { // glow
    a = exp(-r * r * 3.5) * (1.0 - smoothstep(0.8, 1.0, r));
    core = exp(-r * r * 14.0);
  } else if (s < 1.5) { // 4-point spark star
    float star = 0.05 / (abs(p.x * p.y) * 6.0 + 0.05);
    a = clamp(star * (1.0 - r), 0.0, 1.0);
    core = exp(-r * r * 20.0);
  } else if (s < 2.5) { // streak (tapered diamond)
    float d = 1.0 - abs(p.x) - abs(p.y) * 1.2;
    a = smoothstep(0.0, 0.35, d);
    core = smoothstep(0.4, 0.9, d);
  } else if (s < 3.5) { // ring
    float th = max(vParam, 0.02);
    a = ringMask(r, 1.0 - th, th);
    core = a * 0.4;
  } else if (s < 4.5) { // debris chunk with an ink border
    float m = max(abs(p.x), abs(p.y));
    a = 1.0 - smoothstep(0.78, 0.84, m);
    col *= mix(1.0, 0.18, smoothstep(0.58, 0.66, m));
  } else if (s < 5.5) { // chevron pointing +x
    float d = abs(p.x - 0.15 + abs(p.y) * 1.05);
    a = (1.0 - smoothstep(0.18, 0.26, d)) * (1.0 - smoothstep(0.78, 0.86, abs(p.y)));
    core = a * 0.3;
  } else if (s < 6.5) { // ink splat
    float seed = vParam;
    float rr = 0.62 + 0.14 * sin(ang * 5.0 + seed) + 0.08 * sin(ang * 11.0 + seed * 2.3) + 0.05 * sin(ang * 17.0 + seed * 4.1);
    a = 1.0 - smoothstep(rr - 0.04, rr, r);
    for (int k = 0; k < 4; k++) {
      float fk = float(k);
      float da = hash11(seed + fk) * 6.2831;
      float dr = 0.78 + 0.16 * hash11(seed * 1.7 + fk);
      vec2 dc = vec2(cos(da), sin(da)) * dr;
      float ds = 0.05 + 0.06 * hash11(seed * 3.1 + fk);
      a = max(a, 1.0 - smoothstep(ds - 0.02, ds, length(p - dc)));
    }
  } else if (s < 7.5) { // arc: crescent around +x with half-width vParam (radians)
    float hw = max(vParam, 0.05);
    float along = 1.0 - smoothstep(hw * 0.7, hw, abs(ang));
    float taper = 1.0 - abs(ang) / hw;
    float th = 0.08 + 0.12 * clamp(taper, 0.0, 1.0);
    a = ringMask(r, 0.8, th) * along;
    a = max(a, along * smoothstep(0.82, 0.3, r) * 0.18 * smoothstep(0.2, 0.8, r));
    core = a * 0.3;
  } else if (s < 8.5) { // cross
    float d1 = abs(p.x - p.y) * 0.7071;
    float d2 = abs(p.x + p.y) * 0.7071;
    a = (1.0 - smoothstep(0.1, 0.17, min(d1, d2))) * (1.0 - smoothstep(0.75, 0.85, r));
  } else if (s < 9.5) { // dashed ring
    float th = max(vParam, 0.02);
    float dash = step(0.0, sin(ang * 12.0 + vT * 6.0));
    a = ringMask(r, 1.0 - th, th) * dash;
  } else if (s < 10.5) { // glitch slabs
    float row = floor((p.y + 1.0) * 7.0);
    float h = hash11(row + vParam + floor(vT * 18.0) * 7.0);
    float off = (h - 0.5) * 0.7;
    float w = 0.35 + 0.6 * hash11(row * 3.7 + vParam);
    float inRow = step(0.25, fract((p.y + 1.0) * 7.0));
    a = (1.0 - step(w, abs(p.x - off))) * inRow * step(0.25, h) * (1.0 - smoothstep(0.85, 1.0, abs(p.y)));
    col = mix(col, vec3(1.0), step(0.85, h) * 0.6);
  } else if (s < 11.5) { // 5-point star
    float rr = 0.5 + 0.32 * cos(ang * 5.0);
    a = 1.0 - smoothstep(rr - 0.06, rr, r);
    core = a * 0.4;
  } else if (s < 12.5) { // stop square
    float m = max(abs(p.x), abs(p.y));
    a = max(1.0 - smoothstep(0.08, 0.14, abs(m - 0.66)), (1.0 - step(0.42, m)) * 0.7);
  } else if (s < 13.5) { // shard (triangle)
    float tri = max(-p.y - 0.7, abs(p.x) * 1.7 + p.y - 0.8);
    a = 1.0 - smoothstep(-0.04, 0.0, tri);
  } else { // hard dot
    a = 1.0 - smoothstep(0.5, 0.62, r);
    core = 1.0 - smoothstep(0.1, 0.35, r);
  }

  a *= vColor.a;
  if (a < 0.004) discard;
  col = mix(col, vec3(1.0), clamp(core, 0.0, 1.0) * 0.55 * uAdditive);
  gl_FragColor = vec4(col, a);
}
`;

export class SpriteMesh {
  readonly mesh: THREE.Mesh;
  private readonly geo: THREE.InstancedBufferGeometry;
  private readonly mat: THREE.ShaderMaterial;
  private readonly posSize: THREE.InstancedBufferAttribute;
  private readonly color: THREE.InstancedBufferAttribute;
  private readonly dir: THREE.InstancedBufferAttribute;
  private readonly params: THREE.InstancedBufferAttribute;

  constructor(capacity: number, additive: boolean, renderOrder: number) {
    const base = new THREE.PlaneGeometry(1, 1);
    const geo = new THREE.InstancedBufferGeometry();
    geo.index = base.index;
    geo.setAttribute('position', base.getAttribute('position'));
    const mk = () => {
      const a = new THREE.InstancedBufferAttribute(new Float32Array(capacity * 4), 4);
      a.setUsage(THREE.DynamicDrawUsage);
      return a;
    };
    this.posSize = mk();
    this.color = mk();
    this.dir = mk();
    this.params = mk();
    geo.setAttribute('iPosSize', this.posSize);
    geo.setAttribute('iColor', this.color);
    geo.setAttribute('iDir', this.dir);
    geo.setAttribute('iParams', this.params);
    geo.instanceCount = 0;
    this.geo = geo;
    this.mat = new THREE.ShaderMaterial({
      vertexShader: VERT,
      fragmentShader: FRAG,
      uniforms: { uAdditive: { value: additive ? 1 : 0 } },
      transparent: true,
      depthWrite: false,
      depthTest: true,
      blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
      side: THREE.DoubleSide,
      // Floor-mode sprites sit a hair above the floor; pull them forward so they never z-fight decals.
      polygonOffset: true,
      polygonOffsetFactor: -2,
      polygonOffsetUnits: -4,
    });
    this.mesh = new THREE.Mesh(geo, this.mat);
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = renderOrder;
    this.mesh.name = additive ? 'fx-glow' : 'fx-ink';
    this.mesh.userData.fx = true;
    this.mesh.userData.noOutline = true;
  }

  sync(pool: SpritePool): void {
    const n = pool.writeInstances(
      this.posSize.array as Float32Array,
      this.color.array as Float32Array,
      this.dir.array as Float32Array,
      this.params.array as Float32Array,
    );
    this.geo.instanceCount = n;
    if (n > 0) {
      this.markRange(this.posSize, n);
      this.markRange(this.color, n);
      this.markRange(this.dir, n);
      this.markRange(this.params, n);
    }
    this.mesh.visible = n > 0;
  }

  private markRange(attr: THREE.InstancedBufferAttribute, n: number): void {
    attr.clearUpdateRanges();
    attr.addUpdateRange(0, n * 4);
    attr.needsUpdate = true;
  }

  dispose(): void {
    this.geo.dispose();
    this.mat.dispose();
  }
}
