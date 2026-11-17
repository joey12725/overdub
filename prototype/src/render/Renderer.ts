/**
 * Renderer shell: owns the WebGL renderer, scene, isometric camera, lights, post chain, the level
 * environment and mechanisms, and hosts the actor and fx layers (layer.ts seam).
 *
 * Per frame: mechanisms and environment animate, layers update (and may request shake / focus),
 * the camera frames the result, then the post chain draws. render() does not allocate.
 */
import * as THREE from 'three';
import type { LevelDef, ResolvedLoadout, TapeIndex } from '../core/types';
import type { IRenderer, RenderFrame } from '../contracts';
import { IsoCamera } from './camera';
import { type EnvBuild, buildEnvironment } from './env/build';
import { backgroundTexture } from './env/textures';
import type { PostControls, RenderCtx, RenderLayer } from './layer';
import { MaterialKit, ResourceBag, createToonRamp } from './materials';
import { MechLayer } from './mechs';
import { type EnvPalette, paletteFor } from './palettes';
import { PostChain } from './post';

/** Maximum number of practical point lights (lamps, neon, the time machine) on 'high'. */
const MAX_PRACTICALS = 6;

export type LayerFactory = () => RenderLayer;

export interface RendererOptions {
  /** Layers to host, in update order. Defaults to the actor and fx layers when they are present. */
  layers?: RenderLayer[];
  /** Use an existing canvas instead of creating one. */
  canvas?: HTMLCanvasElement;
}

interface LoadedLevel {
  level: LevelDef;
  palette: EnvPalette;
  bag: ResourceBag;
  env: EnvBuild;
  mechs: MechLayer;
  ctx: RenderCtx;
  background: THREE.Texture;
  practicals: THREE.PointLight[];
}

export class OverdubRenderer implements IRenderer {
  readonly canvas: HTMLCanvasElement;
  readonly scene = new THREE.Scene();
  readonly iso = new IsoCamera();

  private readonly gl: THREE.WebGLRenderer;
  private readonly post: PostChain;
  private readonly ramp: THREE.DataTexture;
  private readonly layers: RenderLayer[];
  /** Everything the shell builds per level (env, mechs, lights' targets). */
  private readonly world = new THREE.Group();
  /** Group handed to layers as RenderCtx.root. */
  private readonly layerRoot = new THREE.Group();

  private readonly hemi = new THREE.HemisphereLight(0xffffff, 0x444444, 1);
  private readonly key = new THREE.DirectionalLight(0xffffff, 2);
  private readonly fill = new THREE.DirectionalLight(0xffffff, 0.4);

  private quality: 'low' | 'high' = 'high';
  private shakeEnabled = true;
  private loaded: LoadedLevel | null = null;
  private time = 0;
  private cssW = 1;
  private cssH = 1;
  private dpr = 1;
  private disposed = false;

  // Per-frame scratch (no allocation in render()).
  private readonly follow = { x: 0, y: 0 };
  private readonly crowd = { x: 0, y: 0 };
  private readonly framing = {
    mode: 'idle' as RenderFrame['mode'],
    dt: 0,
    time: 0,
    beat: 0,
    follow: null as { x: number; y: number } | null,
    crowd: null as { x: number; y: number } | null,
  };
  private readonly upOut = { x: 0, y: 0 };

  constructor(options: RendererOptions = {}) {
    this.canvas = options.canvas ?? document.createElement('canvas');
    this.canvas.style.display = 'block';
    this.canvas.style.touchAction = 'none';
    let gl: THREE.WebGLRenderer;
    try {
      gl = new THREE.WebGLRenderer({ canvas: this.canvas, antialias: false, alpha: false, powerPreference: 'high-performance', stencil: false });
    } catch (err) {
      throw new Error(`OVERDUB needs WebGL2: ${(err as Error).message}`);
    }
    this.gl = gl;
    gl.outputColorSpace = THREE.SRGBColorSpace;
    gl.toneMapping = THREE.NoToneMapping;
    gl.shadowMap.enabled = true;
    gl.shadowMap.type = THREE.PCFSoftShadowMap;
    // Counters accumulate over the scene render and every post pass; reset once per frame.
    gl.info.autoReset = false;

    this.ramp = createToonRamp();
    this.scene.add(this.world, this.layerRoot);
    this.layerRoot.name = 'layers';
    this.world.name = 'world';
    this.scene.add(this.hemi, this.key, this.key.target, this.fill, this.fill.target);
    this.key.castShadow = true;
    this.key.shadow.mapSize.set(2048, 2048);
    this.key.shadow.bias = -0.0004;
    this.key.shadow.normalBias = 0.03;
    this.key.shadow.radius = 2;

    this.post = new PostChain(gl, this.scene, this.iso.camera);
    this.layers = options.layers ?? defaultLayers();
    this.resize(this.canvas.clientWidth || 1280, this.canvas.clientHeight || 720, typeof window !== 'undefined' ? window.devicePixelRatio : 1);
    this.setQuality('high');
  }

  // ───────────── IRenderer ─────────────

  loadLevel(level: LevelDef, loadout: ResolvedLoadout): void {
    this.unloadLevel();
    const palette = paletteFor(level.theme);
    const bag = new ResourceBag();
    const kit = new MaterialKit(this.ramp, bag);
    const env = buildEnvironment(level, palette, kit);
    const mechs = new MechLayer(level, palette, kit, env.layout);
    this.world.add(env.group, mechs.group);

    const background = bag.track(backgroundTexture(palette));
    this.scene.background = background;
    this.applyLighting(palette, env);
    const practicals = this.buildPracticals(env);
    this.post.setPalette(palette);

    this.iso.setBounds(env.layout.bounds);
    this.iso.introduce();

    const ctx: RenderCtx = {
      scene: this.scene,
      camera: this.iso.camera,
      palette,
      level,
      loadout,
      root: this.layerRoot,
      toonRamp: this.ramp,
      quality: this.quality,
      shake: (m: number) => {
        if (this.shakeEnabled) this.iso.addTrauma(m);
      },
      focus: (x: number, y: number, w: number) => this.iso.requestFocus(x, y, w),
      musicReactive: env.reactive,
      post: this.post.controls,
      bounds: { ...env.layout.bounds },
      surfaceHeight: env.surfaceHeight,
      time: this.time,
    };
    for (const r of env.reactive) r.setLevel(1);
    resetPost(this.post.controls);
    this.loaded = { level, palette, bag, env, mechs, ctx, background, practicals };
    for (const layer of this.layers) layer.loadLevel(ctx);
    this.compile();
  }

  render(frame: RenderFrame): void {
    if (this.disposed) return;
    const dt = Math.min(0.1, Math.max(0, frame.dt));
    this.time += dt;
    this.gl.info.reset();
    const L = this.loaded;
    if (L) {
      L.ctx.time = this.time;
      L.ctx.quality = this.quality;
      L.mechs.update(frame, dt, this.time);
      L.env.update(this.time, dt);
      for (let i = 0; i < this.layers.length; i++) this.layers[i].update(frame, L.ctx);
    }
    this.frameCamera(frame, dt);
    this.post.render(dt, this.iso.worldPerPixel());
  }

  resize(width: number, height: number, pixelRatio: number): void {
    this.cssW = Math.max(1, Math.floor(width));
    this.cssH = Math.max(1, Math.floor(height));
    this.dpr = pixelRatio > 0 ? pixelRatio : 1;
    const pr = this.effectivePixelRatio();
    this.gl.setPixelRatio(pr);
    this.gl.setSize(this.cssW, this.cssH, true);
    this.post.setSize(this.cssW, this.cssH, pr);
    this.iso.setViewport(this.cssW, this.cssH);
  }

  screenUpInWorld(): { x: number; y: number } {
    const up = this.iso.screenUpInWorld(this.upOut);
    return { x: up.x, y: up.y };
  }

  screenToWorld(px: number, py: number): { x: number; y: number } {
    return this.iso.screenToWorld(px, py);
  }

  setQuality(q: 'low' | 'high'): void {
    this.quality = q;
    const high = q === 'high';
    this.gl.shadowMap.enabled = high;
    this.key.castShadow = high;
    this.post.setQuality(q);
    if (this.loaded) {
      this.loaded.ctx.quality = q;
      for (const p of this.loaded.practicals) p.visible = high;
    }
    this.resize(this.cssW, this.cssH, this.dpr);
  }

  /** Honour the player's screen-shake setting (SaveData.settings.screenShake). */
  setScreenShake(enabled: boolean): void {
    this.shakeEnabled = enabled;
  }

  /** Post controls (also exposed to layers as RenderCtx.post). */
  get postControls(): PostControls {
    return this.post.controls;
  }

  /** The RenderCtx handed to layers for the current level (null before the first loadLevel). */
  get context(): RenderCtx | null {
    return this.loaded?.ctx ?? null;
  }

  /** Draw-call / triangle counters of the last frame, for the dev harness. */
  stats(): { calls: number; triangles: number; geometries: number; textures: number } {
    const i = this.gl.info;
    return { calls: i.render.calls, triangles: i.render.triangles, geometries: i.memory.geometries, textures: i.memory.textures };
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.unloadLevel();
    for (const layer of this.layers) layer.dispose();
    this.post.dispose();
    this.ramp.dispose();
    this.key.shadow.map?.dispose();
    this.key.dispose();
    this.fill.dispose();
    this.hemi.dispose();
    this.gl.dispose();
  }

  // ───────────── internals ─────────────

  private effectivePixelRatio(): number {
    return this.quality === 'low' ? Math.min(this.dpr, 1) : Math.min(this.dpr, 2);
  }

  private unloadLevel(): void {
    const L = this.loaded;
    if (!L) return;
    // Layers own their objects (they may cache geometry across levels); the shell only detaches them.
    this.layerRoot.clear();
    // InstancedMesh owns GPU instance buffers that only its own dispose() releases.
    this.world.traverse((o) => {
      if ((o as THREE.InstancedMesh).isInstancedMesh) (o as THREE.InstancedMesh).dispose();
    });
    this.world.clear();
    for (const p of L.practicals) {
      p.parent?.remove(p);
      p.dispose();
    }
    L.bag.dispose();
    this.scene.background = null;
    this.loaded = null;
  }

  private applyLighting(pal: EnvPalette, env: EnvBuild): void {
    const b = env.layout.bounds;
    const cx = (b.minX + b.maxX) / 2;
    const cz = (b.minZ + b.maxZ) / 2;
    const span = Math.hypot(b.maxX - b.minX, b.maxZ - b.minZ);
    this.hemi.color.setHex(pal.ambient);
    this.hemi.groundColor.setHex(pal.bounce);
    this.hemi.intensity = pal.ambientIntensity;
    this.key.color.setHex(pal.keyLight);
    this.key.intensity = pal.keyIntensity;
    // Sun from the camera's left (+Z, slightly -X): the +Z faces read lit, the +X faces shaded,
    // the classic iso three-tone block.
    const dir = new THREE.Vector3(-0.35, 1, 0.75).normalize();
    this.key.position.set(cx + dir.x * span, dir.y * span, cz + dir.z * span);
    this.key.target.position.set(cx, 0, cz);
    const cam = this.key.shadow.camera;
    const half = span * 0.6 + 2;
    cam.left = -half;
    cam.right = half;
    cam.top = half;
    cam.bottom = -half;
    cam.near = 0.5;
    cam.far = span * 2.5 + 10;
    cam.updateProjectionMatrix();
    this.key.target.updateMatrixWorld();
    this.fill.color.setHex(pal.fill);
    this.fill.intensity = pal.fillIntensity;
    this.fill.position.set(cx + span, span * 0.4, cz - span * 0.6);
    this.fill.target.position.set(cx, 0, cz);
    this.fill.target.updateMatrixWorld();
  }

  private buildPracticals(env: EnvBuild): THREE.PointLight[] {
    // Brightest first; the cap keeps fragment cost bounded on every material.
    const sorted = [...env.practicals].sort((a, b) => b.intensity - a.intensity).slice(0, MAX_PRACTICALS);
    const out: THREE.PointLight[] = [];
    for (const p of sorted) {
      // Practicals are accents, not area lights: modest intensity, quadratic falloff.
      const light = new THREE.PointLight(p.color, p.intensity * 0.45, p.distance, 2);
      light.position.set(p.x, p.h, p.y);
      light.castShadow = false;
      light.visible = this.quality === 'high';
      this.world.add(light);
      out.push(light);
    }
    return out;
  }

  /** Pre-compile shaders so the first rendered frame does not hitch. */
  private compile(): void {
    try {
      this.gl.compile(this.scene, this.iso.camera);
    } catch {
      // compile is an optimisation; a failure here surfaces on the first render instead.
    }
  }

  private frameCamera(frame: RenderFrame, dt: number): void {
    const f = this.framing;
    f.mode = frame.mode;
    f.dt = dt;
    f.time = this.time;
    f.beat = frame.music?.beat ?? frame.snap.beat;
    f.follow = this.findFollow(frame, frame.active);
    f.crowd = this.findCrowd(frame);
    this.iso.update(f);
  }

  /** Interpolated position of the self under live control (or the active cassette's self). */
  private findFollow(frame: RenderFrame, active: TapeIndex | null): { x: number; y: number } | null {
    const actors = frame.snap.actors;
    let idx = -1;
    for (let i = 0; i < actors.length; i++) {
      if (actors[i].live) {
        idx = i;
        break;
      }
    }
    if (idx < 0 && active !== null) {
      for (let i = 0; i < actors.length; i++) {
        if (actors[i].tape === active) {
          idx = i;
          break;
        }
      }
    }
    if (idx < 0) return null;
    const a = actors[idx];
    let px = a.x;
    let py = a.y;
    const prev = frame.prev.actors;
    for (let i = 0; i < prev.length; i++) {
      if (prev[i].tape === a.tape) {
        px = prev[i].x;
        py = prev[i].y;
        break;
      }
    }
    const t = frame.alpha;
    this.follow.x = px + (a.x - px) * t;
    this.follow.y = py + (a.y - py) * t;
    return this.follow;
  }

  /** Centre of the selves still alive (ghosts do not pull the camera). */
  private findCrowd(frame: RenderFrame): { x: number; y: number } | null {
    const actors = frame.snap.actors;
    let n = 0;
    let sx = 0;
    let sy = 0;
    for (let i = 0; i < actors.length; i++) {
      const a = actors[i];
      if (a.life !== 'alive') continue;
      sx += a.x;
      sy += a.y;
      n++;
    }
    if (n === 0) return null;
    this.crowd.x = sx / n;
    this.crowd.y = sy / n;
    return this.crowd;
  }
}

function resetPost(c: PostControls): void {
  c.chromatic = 0;
  c.flash = 0;
  c.flashColor = 0xffffff;
  c.saturation = 1;
  c.vignette = 1;
}

/**
 * The actor and fx layers live in sibling directories written by other engineers. They are picked
 * up through Vite's eager glob so the shell builds and runs whether or not they exist yet; once
 * present, each module's factory is called exactly once per renderer.
 */
function defaultLayers(): RenderLayer[] {
  const modules = import.meta.glob(['./actors/index.ts', './fx/index.ts'], { eager: true }) as Record<string, Record<string, unknown>>;
  const out: RenderLayer[] = [];
  const pick = (path: string, name: string) => {
    const mod = modules[path];
    const factory = mod?.[name];
    if (typeof factory === 'function') out.push((factory as LayerFactory)());
  };
  pick('./actors/index.ts', 'createActorLayer');
  pick('./fx/index.ts', 'createFxLayer');
  return out;
}
