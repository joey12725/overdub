/**
 * Shared material kit. ART-02: anime / cel-shaded direction, so every lit surface is a
 * MeshToonMaterial over one stepped gradient ramp; glows are unlit basic materials pushed above 1
 * so the bloom pass picks them up.
 *
 * Ownership: a MaterialKit tracks everything it creates in a ResourceBag; disposing the bag on
 * level change frees every geometry, material and texture the level built. The toon ramp belongs
 * to the renderer and outlives levels.
 */
import * as THREE from 'three';

/** Anything with a dispose() (geometries, materials, textures, render targets). */
export interface Disposable {
  dispose(): void;
}

export class ResourceBag {
  private items = new Set<Disposable>();

  track<T extends Disposable>(item: T): T {
    this.items.add(item);
    return item;
  }

  get size(): number {
    return this.items.size;
  }

  dispose(): void {
    for (const item of this.items) item.dispose();
    this.items.clear();
  }
}

/**
 * Stepped irradiance ramp: deep shadow, shadow, lit, highlight. Four flat bands give the
 * graphic shading of the reference boards without banding artefacts on large faces.
 */
export function createToonRamp(): THREE.DataTexture {
  const bands = [0.42, 0.62, 0.86, 1.0];
  const width = 8;
  const data = new Uint8Array(width * 4);
  for (let i = 0; i < width; i++) {
    const v = Math.round(bands[Math.min(bands.length - 1, Math.floor((i / width) * bands.length))] * 255);
    data[i * 4] = v;
    data[i * 4 + 1] = v;
    data[i * 4 + 2] = v;
    data[i * 4 + 3] = 255;
  }
  const tex = new THREE.DataTexture(data, width, 1, THREE.RGBAFormat);
  tex.minFilter = THREE.NearestFilter;
  tex.magFilter = THREE.NearestFilter;
  tex.generateMipmaps = false;
  tex.colorSpace = THREE.NoColorSpace;
  tex.needsUpdate = true;
  return tex;
}

export interface ToonOptions {
  map?: THREE.Texture | null;
  emissive?: number;
  emissiveIntensity?: number;
  emissiveMap?: THREE.Texture | null;
  vertexColors?: boolean;
  transparent?: boolean;
  opacity?: number;
  side?: THREE.Side;
  /** Decals: draw over coplanar surfaces without z-fighting. */
  decal?: boolean;
  alphaTest?: number;
  depthWrite?: boolean;
}

export interface GlowOptions {
  /** HDR multiplier on the colour; > 1 blooms. */
  intensity?: number;
  additive?: boolean;
  opacity?: number;
  map?: THREE.Texture | null;
  side?: THREE.Side;
  depthWrite?: boolean;
}

export class MaterialKit {
  private toonCache = new Map<string, THREE.MeshToonMaterial>();
  private glowCache = new Map<string, THREE.MeshBasicMaterial>();
  private geoCache = new Map<string, THREE.BufferGeometry>();

  constructor(
    readonly ramp: THREE.Texture,
    readonly bag: ResourceBag,
  ) {}

  /** Cel-shaded lit material. Plain colour materials are shared; textured ones are unique. */
  toon(color: number, opts: ToonOptions = {}): THREE.MeshToonMaterial {
    const cacheable = !opts.map && !opts.emissiveMap && !opts.transparent && !opts.decal && opts.side === undefined && opts.alphaTest === undefined;
    const key = cacheable ? `${color}|${opts.emissive ?? 0}|${opts.emissiveIntensity ?? 1}|${opts.vertexColors ? 1 : 0}` : '';
    if (cacheable) {
      const hit = this.toonCache.get(key);
      if (hit) return hit;
    }
    const m = new THREE.MeshToonMaterial({
      color,
      gradientMap: this.ramp,
      map: opts.map ?? null,
      emissive: opts.emissive ?? 0x000000,
      emissiveIntensity: opts.emissiveIntensity ?? 1,
      emissiveMap: opts.emissiveMap ?? null,
      vertexColors: opts.vertexColors ?? false,
      transparent: opts.transparent ?? false,
      opacity: opts.opacity ?? 1,
      side: opts.side ?? THREE.FrontSide,
      alphaTest: opts.alphaTest ?? 0,
    });
    if (opts.depthWrite !== undefined) m.depthWrite = opts.depthWrite;
    if (opts.decal) {
      m.polygonOffset = true;
      m.polygonOffsetFactor = -2;
      m.polygonOffsetUnits = -2;
      m.depthWrite = false;
    }
    this.bag.track(m);
    if (cacheable) this.toonCache.set(key, m);
    return m;
  }

  /** Unlit emissive material for neon, beams and screens. */
  glow(color: number, opts: GlowOptions = {}): THREE.MeshBasicMaterial {
    const intensity = opts.intensity ?? 2.2;
    const cacheable = !opts.map && opts.side === undefined && opts.depthWrite === undefined;
    const key = `${color}|${intensity}|${opts.additive ? 1 : 0}|${opts.opacity ?? 1}`;
    if (cacheable) {
      const hit = this.glowCache.get(key);
      if (hit) return hit;
    }
    const c = new THREE.Color(color).multiplyScalar(intensity);
    const m = new THREE.MeshBasicMaterial({
      color: c,
      map: opts.map ?? null,
      transparent: opts.additive || (opts.opacity ?? 1) < 1,
      opacity: opts.opacity ?? 1,
      blending: opts.additive ? THREE.AdditiveBlending : THREE.NormalBlending,
      depthWrite: opts.depthWrite ?? !opts.additive,
      side: opts.side ?? THREE.FrontSide,
      toneMapped: false,
      fog: false,
    });
    this.bag.track(m);
    if (cacheable) this.glowCache.set(key, m);
    return m;
  }

  /** Cache a geometry by key; created once per level and freed with the bag. */
  geo<T extends THREE.BufferGeometry>(key: string, make: () => T): T {
    const hit = this.geoCache.get(key);
    if (hit) return hit as T;
    const g = this.bag.track(make());
    this.geoCache.set(key, g);
    return g;
  }

  texture<T extends THREE.Texture>(tex: T): T {
    return this.bag.track(tex);
  }
}

/** Configure a canvas texture for colour data (sRGB, mipmapped, repeat-wrapped). */
export function colorTexture(canvas: HTMLCanvasElement, repeat = true): THREE.CanvasTexture {
  const t = new THREE.CanvasTexture(canvas);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  if (repeat) {
    t.wrapS = THREE.RepeatWrapping;
    t.wrapT = THREE.RepeatWrapping;
  }
  t.needsUpdate = true;
  return t;
}
