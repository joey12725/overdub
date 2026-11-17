/**
 * Shaders for the actor layer. One cel shader drives every self/enemy style through uniforms, so a
 * style change is a uniform write (or a swap between the opaque and transparent twin), never a
 * recompile. Geometry carries per-vertex colour plus two flags:
 *   glow   — 1 for emissive parts (screens, headphone glow, eyes): unlit, bloom-bright.
 *   accent — 1 for parts recoloured by the instance accent (cassette colour on the headphones).
 * And `oNormal`, a smoothed normal used to extrude the ink hull without cracks at hard edges.
 */
import * as THREE from 'three';

export interface SharedUniforms {
  uTime: { value: number };
  uRamp: { value: THREE.Texture | null };
  uLightDir: { value: THREE.Vector3 };
  uLit: { value: THREE.Color };
  uShade: { value: THREE.Color };
}

export function createSharedUniforms(ramp: THREE.Texture | null): SharedUniforms {
  return {
    uTime: { value: 0 },
    uRamp: { value: ramp },
    uLightDir: { value: new THREE.Vector3(-0.45, 1, 0.55).normalize() },
    uLit: { value: new THREE.Color(1, 0.97, 0.92) },
    uShade: { value: new THREE.Color(0.55, 0.5, 0.68) },
  };
}

/** Derive lit/shade tints from the theme palette so actors sit in the same light as the room. */
export function applyPaletteLight(
  shared: SharedUniforms,
  keyLight: number,
  keyIntensity: number,
  ambient: number,
  ambientIntensity: number,
): void {
  const key = new THREE.Color(keyLight);
  const amb = new THREE.Color(ambient);
  // Characters must stay readable whatever the room does: clamp toward neutral and keep the
  // shade side a cool, fairly bright tone (anime cel shading, not realistic falloff).
  const k = Math.min(1.25, Math.max(0.85, 0.55 + keyIntensity * 0.35));
  shared.uLit.value.setRGB(1, 1, 1).lerp(key, 0.25).multiplyScalar(k);
  const a = Math.min(0.75, Math.max(0.5, 0.35 + ambientIntensity * 0.3));
  shared.uShade.value.setRGB(0.62, 0.58, 0.78).lerp(amb, 0.3).multiplyScalar(a / 0.62);
}

const CEL_VERT = /* glsl */ `
attribute float glow;
attribute float accent;
varying vec3 vCol;
varying vec3 vNw;
varying vec3 vNv;
varying float vGlow;
varying float vAccent;
varying vec3 vWorld;
void main() {
  #ifdef USE_COLOR
  vCol = color;
  #else
  vCol = vec3(1.0);
  #endif
  vGlow = glow;
  vAccent = accent;
  vec4 wp = modelMatrix * vec4(position, 1.0);
  vWorld = wp.xyz;
  vNw = normalize(mat3(modelMatrix) * normal);
  vNv = normalize(normalMatrix * normal);
  gl_Position = projectionMatrix * viewMatrix * wp;
}
`;

const CEL_FRAG = /* glsl */ `
uniform sampler2D uRamp;
uniform float uHasRamp;
uniform vec3 uLightDir;
uniform vec3 uLit;
uniform vec3 uShade;
uniform float uTime;
uniform vec3 uTint;
uniform float uTintAmt;
uniform float uDesat;
uniform vec3 uFlashCol;
uniform float uFlash;
uniform float uOpacity;
uniform vec3 uRimCol;
uniform float uRim;
uniform vec3 uAccent;
uniform float uGlowMul;
uniform float uHolo;
uniform vec3 uHoloCol;
uniform float uPhase;
varying vec3 vCol;
varying vec3 vNw;
varying vec3 vNv;
varying float vGlow;
varying float vAccent;
varying vec3 vWorld;
void main() {
  vec3 base = mix(vCol, uAccent, vAccent);
  vec3 n = normalize(vNw);
  float ndl = dot(n, normalize(uLightDir));
  float r;
  if (uHasRamp > 0.5) {
    r = texture2D(uRamp, vec2(clamp(ndl * 0.5 + 0.5, 0.02, 0.98), 0.5)).r;
  } else {
    r = smoothstep(0.38, 0.46, ndl * 0.5 + 0.5) * 0.85 + smoothstep(0.82, 0.86, ndl * 0.5 + 0.5) * 0.15;
  }
  vec3 lit = mix(base * uShade, base * uLit, r);
  float rim = pow(1.0 - clamp(abs(vNv.z), 0.0, 1.0), 3.0);
  lit += uRimCol * rim * uRim;
  vec3 c = mix(lit, base * uGlowMul, vGlow);
  float lum = dot(c, vec3(0.299, 0.587, 0.114));
  c = mix(c, vec3(lum), uDesat);
  c = mix(c, uTint, uTintAmt);
  float a = uOpacity;
  if (uHolo > 0.0) {
    // Hologram: luminance carried in the cassette colour, world-space scanlines crawling upward,
    // a hot rim, and periodic tear bands.
    float scan = 0.55 + 0.45 * step(0.5, fract(vWorld.y * 38.0 - uTime * 2.2));
    float band = smoothstep(0.96, 1.0, sin(vWorld.y * 5.0 - uTime * 3.1) * 0.5 + 0.5);
    vec3 h = uHoloCol * (0.35 + lum * 1.1) + uHoloCol * rim * 1.6 + vec3(band * 0.6);
    c = mix(c, h * scan, uHolo);
    a *= mix(1.0, scan * (0.75 + rim * 0.6) + band * 0.4, uHolo);
  }
  if (uPhase > 0.0) {
    // Phased-out projection: horizontal slices drop out and shimmer.
    float slice = step(0.25, fract(vWorld.y * 14.0 + floor(uTime * 12.0) * 0.37));
    a *= mix(1.0, slice * (0.6 + 0.4 * rim), uPhase);
  }
  c = mix(c, uFlashCol, uFlash);
  gl_FragColor = vec4(c, a);
  #include <tonemapping_fragment>
  #include <colorspace_fragment>
}
`;

export type CelMaterial = THREE.ShaderMaterial & {
  uniforms: {
    uRamp: { value: THREE.Texture | null };
    uHasRamp: { value: number };
    uLightDir: { value: THREE.Vector3 };
    uLit: { value: THREE.Color };
    uShade: { value: THREE.Color };
    uTime: { value: number };
    uTint: { value: THREE.Color };
    uTintAmt: { value: number };
    uDesat: { value: number };
    uFlashCol: { value: THREE.Color };
    uFlash: { value: number };
    uOpacity: { value: number };
    uRimCol: { value: THREE.Color };
    uRim: { value: number };
    uAccent: { value: THREE.Color };
    uGlowMul: { value: number };
    uHolo: { value: number };
    uHoloCol: { value: THREE.Color };
    uPhase: { value: number };
  };
};

export function createCelMaterial(shared: SharedUniforms, transparent: boolean): CelMaterial {
  const m = new THREE.ShaderMaterial({
    vertexShader: CEL_VERT,
    fragmentShader: CEL_FRAG,
    vertexColors: true,
    transparent,
    depthWrite: true,
    uniforms: {
      uRamp: shared.uRamp,
      uHasRamp: { value: shared.uRamp.value ? 1 : 0 },
      uLightDir: shared.uLightDir,
      uLit: shared.uLit,
      uShade: shared.uShade,
      uTime: shared.uTime,
      uTint: { value: new THREE.Color(1, 1, 1) },
      uTintAmt: { value: 0 },
      uDesat: { value: 0 },
      uFlashCol: { value: new THREE.Color(1, 1, 1) },
      uFlash: { value: 0 },
      uOpacity: { value: 1 },
      uRimCol: { value: new THREE.Color(1, 1, 1) },
      uRim: { value: 0.12 },
      uAccent: { value: new THREE.Color(1, 0.82, 0.25) },
      uGlowMul: { value: 1.6 },
      uHolo: { value: 0 },
      uHoloCol: { value: new THREE.Color(1, 1, 1) },
      uPhase: { value: 0 },
    },
  }) as CelMaterial;
  return m;
}

const HULL_VERT = /* glsl */ `
attribute vec3 oNormal;
uniform float uThick;
uniform vec3 uShift;
void main() {
  vec4 wp = modelMatrix * vec4(position + oNormal * uThick, 1.0);
  wp.xyz += uShift;
  gl_Position = projectionMatrix * viewMatrix * wp;
}
`;

const HULL_FRAG = /* glsl */ `
uniform vec3 uColor;
uniform float uOpacity;
void main() {
  gl_FragColor = vec4(uColor, uOpacity);
  #include <colorspace_fragment>
}
`;

export type HullMaterial = THREE.ShaderMaterial & {
  uniforms: {
    uThick: { value: number };
    uShift: { value: THREE.Vector3 };
    uColor: { value: THREE.Color };
    uOpacity: { value: number };
  };
};

/**
 * Inverted-hull ink outline. Mesh scale must be (near) uniform: thickness is in the mesh's local
 * units, which is fine because every rig part is built at final size with unit scale.
 */
export function createHullMaterial(color: number, thick: number, transparent: boolean): HullMaterial {
  return new THREE.ShaderMaterial({
    vertexShader: HULL_VERT,
    fragmentShader: HULL_FRAG,
    side: THREE.BackSide,
    transparent,
    depthWrite: !transparent,
    uniforms: {
      uThick: { value: thick },
      uShift: { value: new THREE.Vector3() },
      uColor: { value: new THREE.Color(color) },
      uOpacity: { value: 1 },
    },
  }) as HullMaterial;
}

/** Chromatic-split echo: the same geometry, shifted in world space, additive red or cyan. */
export function createEchoMaterial(color: number): HullMaterial {
  const m = new THREE.ShaderMaterial({
    vertexShader: HULL_VERT,
    fragmentShader: HULL_FRAG,
    side: THREE.FrontSide,
    transparent: true,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
    uniforms: {
      uThick: { value: 0 },
      uShift: { value: new THREE.Vector3() },
      uColor: { value: new THREE.Color(color) },
      uOpacity: { value: 0.35 },
    },
  }) as HullMaterial;
  return m;
}

/** Depth-only body for the hollow ghost: hides the hull's interior so only the rim remains. */
export function createDepthOnlyMaterial(): THREE.MeshBasicMaterial {
  const m = new THREE.MeshBasicMaterial({ colorWrite: false, transparent: true });
  m.depthWrite = true;
  return m;
}

const FLAT_VERT = /* glsl */ `
varying vec2 vUv;
void main() {
  vUv = uv;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
`;

/** Simple additive/alpha glow material for markers and decals. */
export type FlatMaterial = THREE.ShaderMaterial & {
  uniforms: { uColor: { value: THREE.Color }; uOpacity: { value: number } };
};

export function createFlatMaterial(color: number, opts: { additive?: boolean; overlay?: boolean } = {}): FlatMaterial {
  return new THREE.ShaderMaterial({
    vertexShader: FLAT_VERT,
    fragmentShader: /* glsl */ `
      uniform vec3 uColor;
      uniform float uOpacity;
      void main() {
        gl_FragColor = vec4(uColor, uOpacity);
        #include <colorspace_fragment>
      }
    `,
    transparent: true,
    depthWrite: false,
    depthTest: !opts.overlay,
    side: THREE.DoubleSide,
    blending: opts.additive ? THREE.AdditiveBlending : THREE.NormalBlending,
    uniforms: { uColor: { value: new THREE.Color(color) }, uOpacity: { value: 1 } },
  }) as FlatMaterial;
}

/**
 * Ground decal / strip material. UV.x runs along the strip (0 at origin, 1 at the far end), UV.y
 * across it. Used for telegraph fills (uFill), dashed tethers (uDash > 0), aim lines and targets.
 */
export type StripMaterial = THREE.ShaderMaterial & {
  uniforms: {
    uColor: { value: THREE.Color };
    uOpacity: { value: number };
    uFill: { value: number };
    uDash: { value: number };
    uLength: { value: number };
    uTime: { value: number };
    uEdge: { value: number };
    uBack: { value: number };
    uFade: { value: number };
  };
};

export function createStripMaterial(color: number, opts: { additive?: boolean; overlay?: boolean } = {}): StripMaterial {
  return new THREE.ShaderMaterial({
    vertexShader: FLAT_VERT,
    fragmentShader: /* glsl */ `
      uniform vec3 uColor;
      uniform float uOpacity;
      uniform float uFill;
      uniform float uDash;
      uniform float uLength;
      uniform float uTime;
      uniform float uEdge;
      uniform float uBack;
      uniform float uFade;
      varying vec2 vUv;
      void main() {
        float a = uOpacity * mix(1.0, vUv.x * vUv.x, uFade);
        // Telegraph: a faint full-size backing plus a solid front filling outward to uFill.
        float filled = step(vUv.x, uFill);
        float front = smoothstep(uFill - 0.04, uFill, vUv.x) * filled;
        a *= mix(uBack, 1.0, filled) + front * 0.8;
        // Hard edges read as a graphic decal, not a soft glow.
        float edge = 1.0 - smoothstep(0.0, 0.12, min(vUv.y, 1.0 - vUv.y));
        a *= 1.0 + edge * uEdge;
        if (uDash > 0.0) {
          float d = fract(vUv.x * uLength / uDash - uTime * 1.5);
          a *= step(0.45, d);
        }
        if (a <= 0.003) discard;
        gl_FragColor = vec4(uColor, min(a, 1.0));
        #include <colorspace_fragment>
      }
    `,
    transparent: true,
    depthWrite: false,
    depthTest: !opts.overlay,
    side: THREE.DoubleSide,
    blending: opts.additive ? THREE.AdditiveBlending : THREE.NormalBlending,
    uniforms: {
      uColor: { value: new THREE.Color(color) },
      uOpacity: { value: 1 },
      uFill: { value: 1 },
      uDash: { value: 0 },
      uLength: { value: 1 },
      uTime: { value: 0 },
      uEdge: { value: 0 },
      uBack: { value: 1 },
      uFade: { value: 0 },
    },
  }) as StripMaterial;
}

/**
 * Point sprites with per-vertex size (world units) and colour+alpha. The size uniform is updated
 * from the drawing buffer each draw so points stay the right size at any resolution/zoom.
 */
export type PointsMaterial = THREE.ShaderMaterial & {
  uniforms: { uPxPerUnit: { value: number }; uSoft: { value: number } };
};

export function createPointsMaterial(opts: { additive: boolean; overlay: boolean; soft: number }): PointsMaterial {
  return new THREE.ShaderMaterial({
    vertexShader: /* glsl */ `
      attribute float size;
      attribute vec4 rgba;
      uniform float uPxPerUnit;
      varying vec4 vRgba;
      void main() {
        vRgba = rgba;
        vec4 mv = modelViewMatrix * vec4(position, 1.0);
        gl_Position = projectionMatrix * mv;
        gl_PointSize = max(1.0, size * uPxPerUnit);
      }
    `,
    fragmentShader: /* glsl */ `
      uniform float uSoft;
      varying vec4 vRgba;
      void main() {
        vec2 d = gl_PointCoord - 0.5;
        float r = length(d) * 2.0;
        if (r > 1.0 || vRgba.a <= 0.002) discard;
        float core = 1.0 - smoothstep(0.0, 1.0, r);
        float a = vRgba.a * mix(1.0, core, uSoft);
        gl_FragColor = vec4(vRgba.rgb * (1.0 + (1.0 - r) * 0.6 * uSoft), a);
        #include <colorspace_fragment>
      }
    `,
    transparent: true,
    depthWrite: false,
    depthTest: !opts.overlay,
    blending: opts.additive ? THREE.AdditiveBlending : THREE.NormalBlending,
    uniforms: { uPxPerUnit: { value: 40 }, uSoft: { value: opts.soft } },
  }) as PointsMaterial;
}

const tmpSize = new THREE.Vector2();

/** Pixels per world unit for an orthographic camera at the renderer's current drawing size. */
export function pixelsPerUnit(renderer: THREE.WebGLRenderer, camera: THREE.Camera): number {
  renderer.getDrawingBufferSize(tmpSize);
  const cam = camera as THREE.OrthographicCamera;
  if (cam.isOrthographicCamera) {
    const h = (cam.top - cam.bottom) / cam.zoom;
    return h > 0 ? tmpSize.y / h : 40;
  }
  return tmpSize.y / 20;
}
