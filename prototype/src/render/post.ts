/**
 * Post chain: scene → ink outlines → bloom → grade (vignette, chromatic split, saturation, flash)
 * → output (sRGB) → FXAA.
 *
 * Ink (ART-02 "clear edges, graphic silhouettes") is a depth-based edge pass rather than inverted
 * hulls: it outlines instanced tiles, decor and actors uniformly at one pixel weight with a single
 * full-screen pass. The orthographic depth buffer is linear, so a second difference of depth is
 * zero on any flat face and non-zero exactly at creases and silhouettes.
 *
 * 'low' quality keeps only the ink pass (it is the art style and costs one cheap full-screen pass);
 * bloom, grade and FXAA are dropped.
 */
import * as THREE from 'three';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js';
import { ShaderPass } from 'three/examples/jsm/postprocessing/ShaderPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { FXAAShader } from 'three/examples/jsm/shaders/FXAAShader.js';
import type { PostControls, ThemePalette } from './layer';

const InkShader = {
  name: 'OverdubInk',
  uniforms: {
    tDiffuse: { value: null as THREE.Texture | null },
    tDepth: { value: null as THREE.Texture | null },
    texel: { value: new THREE.Vector2(1 / 1024, 1 / 1024) },
    thickness: { value: 1 },
    depthRange: { value: 299 },
    worldPerPixel: { value: 0.02 },
    inkColor: { value: new THREE.Color(0x111111) },
    strength: { value: 0.9 },
    creaseStrength: { value: 0.4 },
  },
  vertexShader: /* glsl */ `
    varying vec2 vUv;
    void main() {
      vUv = uv;
      gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
    }`,
  fragmentShader: /* glsl */ `
    uniform sampler2D tDiffuse;
    uniform sampler2D tDepth;
    uniform vec2 texel;
    uniform float thickness;
    uniform float depthRange;
    uniform float worldPerPixel;
    uniform vec3 inkColor;
    uniform float strength;
    uniform float creaseStrength;
    varying vec2 vUv;

    float D(vec2 uv) { return texture2D(tDepth, uv).x * depthRange; }

    void main() {
      vec4 col = texture2D(tDiffuse, vUv);
      vec2 o = texel * thickness;
      float c = D(vUv);
      float l = D(vUv - vec2(o.x, 0.0));
      float r = D(vUv + vec2(o.x, 0.0));
      float d = D(vUv - vec2(0.0, o.y));
      float u = D(vUv + vec2(0.0, o.y));
      // World units spanned by one sample step: edges are judged relative to the pixel size so the
      // line weight stays constant through zoom.
      float px = max(worldPerPixel * thickness, 1e-5);
      // Silhouette: a neighbour within two samples is much nearer than this pixel. Only the far side
      // of an edge inks, so silhouettes are a bold two-sample line sitting on the farther surface.
      vec2 o2 = o * 2.0;
      float jump = max(max(c - l, c - r), max(c - d, c - u));
      jump = max(jump, max(max(c - D(vUv - vec2(o2.x, 0.0)), c - D(vUv + vec2(o2.x, 0.0))),
                           max(c - D(vUv - vec2(0.0, o2.y)), c - D(vUv + vec2(0.0, o2.y)))));
      float sil = smoothstep(5.0 * px, 9.0 * px, jump);
      // Crease: second difference of depth (zero on flat faces in an orthographic view).
      float lap = max(abs(l + r - 2.0 * c), abs(u + d - 2.0 * c));
      float crease = smoothstep(0.7 * px, 1.5 * px, lap) * (1.0 - step(depthRange * 0.999, c));
      float edge = max(sil, crease * creaseStrength) * strength;
      col.rgb = mix(col.rgb, inkColor, clamp(edge, 0.0, 1.0));
      gl_FragColor = col;
    }`,
};

const GradeShader = {
  name: 'OverdubGrade',
  uniforms: {
    tDiffuse: { value: null as THREE.Texture | null },
    vignette: { value: 0.35 },
    chroma: { value: 0 },
    saturation: { value: 1 },
    flash: { value: 0 },
    flashColor: { value: new THREE.Color(1, 1, 1) },
    aspect: { value: 1.6 },
  },
  vertexShader: InkShader.vertexShader,
  fragmentShader: /* glsl */ `
    uniform sampler2D tDiffuse;
    uniform float vignette;
    uniform float chroma;
    uniform float saturation;
    uniform float flash;
    uniform vec3 flashColor;
    uniform float aspect;
    varying vec2 vUv;
    void main() {
      vec2 dir = vUv - 0.5;
      vec3 col;
      if (chroma > 0.0005) {
        vec2 off = dir * chroma * 0.018;
        col.r = texture2D(tDiffuse, vUv + off).r;
        col.g = texture2D(tDiffuse, vUv).g;
        col.b = texture2D(tDiffuse, vUv - off).b;
      } else {
        col = texture2D(tDiffuse, vUv).rgb;
      }
      float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
      col = mix(vec3(luma), col, saturation);
      float v = length(dir * vec2(aspect, 1.0)) / length(vec2(aspect, 1.0) * 0.5);
      col *= 1.0 - vignette * smoothstep(0.45, 1.05, v);
      col = mix(col, flashColor, clamp(flash, 0.0, 1.0));
      gl_FragColor = vec4(col, 1.0);
    }`,
};

export class PostChain {
  readonly controls: PostControls = { chromatic: 0, flash: 0, flashColor: 0xffffff, saturation: 1, vignette: 1 };
  private composer: EffectComposer;
  private ink: ShaderPass;
  private bloom: UnrealBloomPass;
  private grade: ShaderPass;
  private output: OutputPass;
  private fxaa: ShaderPass;
  /** The scene renders here (colour + depth); the composer's own ping-pong targets carry no depth. */
  private sceneTarget: THREE.WebGLRenderTarget;
  private quality: 'low' | 'high' = 'high';
  private baseVignette = 0.35;
  private width = 1;
  private height = 1;
  private pixelRatio = 1;
  private readonly flashCol = new THREE.Color();

  constructor(
    private readonly renderer: THREE.WebGLRenderer,
    private readonly scene: THREE.Scene,
    private readonly camera: THREE.OrthographicCamera,
  ) {
    const depth = new THREE.DepthTexture(1, 1);
    depth.type = THREE.UnsignedIntType;
    this.sceneTarget = new THREE.WebGLRenderTarget(1, 1, { type: THREE.HalfFloatType, depthTexture: depth, depthBuffer: true });
    this.sceneTarget.texture.name = 'Overdub.scene';
    // Keeping depth off the composer targets means no pass can ever write into the depth texture
    // the ink pass samples (a WebGL feedback loop).
    const pingPong = new THREE.WebGLRenderTarget(1, 1, { type: THREE.HalfFloatType, depthBuffer: false });
    this.composer = new EffectComposer(renderer, pingPong);
    // FXAA first, on the scene colour, so geometry edges are smoothed while ink lines stay crisp.
    // A textureID that is not a uniform stops ShaderPass overwriting the input we bind ourselves.
    this.fxaa = new ShaderPass(FXAAShader, 'tSceneInput');
    this.fxaa.uniforms.tDiffuse.value = this.sceneTarget.texture;
    this.composer.addPass(this.fxaa);
    this.ink = new ShaderPass(InkShader);
    this.ink.uniforms.tDepth.value = this.sceneTarget.depthTexture;
    this.composer.addPass(this.ink);
    this.bloom = new UnrealBloomPass(new THREE.Vector2(256, 256), 0.6, 0.55, 0.95);
    this.composer.addPass(this.bloom);
    this.grade = new ShaderPass(GradeShader);
    this.composer.addPass(this.grade);
    this.output = new OutputPass();
    this.composer.addPass(this.output);
  }

  setPalette(pal: ThemePalette): void {
    (this.ink.uniforms.inkColor.value as THREE.Color).setHex(pal.ink);
    this.bloom.strength = pal.bloom * 0.75;
    // Darker depths take a heavier vignette; upper levels stay open and sunlit.
    this.baseVignette = 0.22 + 0.18 * Math.min(1, pal.bloom);
  }

  setQuality(q: 'low' | 'high'): void {
    this.quality = q;
    const high = q === 'high';
    this.bloom.enabled = high;
    this.grade.enabled = high;
    this.fxaa.enabled = high;
    // Without FXAA the ink pass reads the scene colour directly.
    this.ink.textureID = high ? 'tDiffuse' : 'tSceneInput';
    if (!high) this.ink.uniforms.tDiffuse.value = this.sceneTarget.texture;
  }

  setSize(width: number, height: number, pixelRatio: number): void {
    this.width = Math.max(1, Math.round(width));
    this.height = Math.max(1, Math.round(height));
    this.pixelRatio = pixelRatio;
    const pw = Math.max(1, Math.round(this.width * pixelRatio));
    const ph = Math.max(1, Math.round(this.height * pixelRatio));
    this.sceneTarget.setSize(pw, ph);
    this.composer.setPixelRatio(pixelRatio);
    this.composer.setSize(this.width, this.height);
    (this.ink.uniforms.texel.value as THREE.Vector2).set(1 / pw, 1 / ph);
    this.ink.uniforms.thickness.value = Math.max(1, Math.round(pixelRatio));
    (this.fxaa.uniforms.resolution.value as THREE.Vector2).set(1 / pw, 1 / ph);
    this.grade.uniforms.aspect.value = this.width / this.height;
  }

  /**
   * Render one frame. `worldPerPixel` is world units per CSS pixel (from the camera), used to keep
   * outline sensitivity constant through zoom.
   */
  render(dt: number, worldPerPixel: number): void {
    const c = this.controls;
    // Kicks decay on their own (layer.ts PostControls contract).
    c.chromatic = c.chromatic < 1e-3 ? 0 : c.chromatic * Math.exp(-dt * 6);
    c.flash = c.flash < 1e-3 ? 0 : c.flash * Math.exp(-dt * 8);

    const ink = this.ink.uniforms;
    ink.depthRange.value = this.camera.far - this.camera.near;
    ink.worldPerPixel.value = worldPerPixel / this.pixelRatio;

    if (this.quality === 'high') {
      const g = this.grade.uniforms;
      g.vignette.value = this.baseVignette * c.vignette;
      g.chroma.value = c.chromatic;
      g.saturation.value = c.saturation;
      g.flash.value = c.flash;
      (g.flashColor.value as THREE.Color).copy(this.flashCol.setHex(c.flashColor));
    }
    this.renderer.setRenderTarget(this.sceneTarget);
    this.renderer.render(this.scene, this.camera);
    this.composer.render(dt);
  }

  dispose(): void {
    this.bloom.dispose();
    this.ink.dispose();
    this.grade.dispose();
    this.output.dispose();
    this.fxaa.dispose();
    this.composer.dispose();
    this.sceneTarget.depthTexture?.dispose();
    this.sceneTarget.dispose();
  }
}
