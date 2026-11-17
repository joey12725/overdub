/**
 * Seam between the renderer shell (src/render/Renderer.ts + env/ + camera) and the two layers
 * that draw into its scene: actors (src/render/actors) and fx (src/render/fx).
 *
 * Scene convention: 1 tile = 1 scene unit. Sim (x, y) maps to scene (X = x, Z = y); scene Y is up.
 * The floor's top surface is at Y = 0.
 */
import type * as THREE from 'three';
import type { LevelDef, ResolvedLoadout, Theme } from '../core/types';
import type { RenderFrame } from '../contracts';

/** Colours for one depth theme; the env kit, actors and fx all draw from the same palette. */
export interface ThemePalette {
  theme: Theme;
  /** Scene clear colour / fog. */
  background: number;
  fog: number;
  floor: number;
  floorAlt: number;
  wall: number;
  wallTop: number;
  metal: number;
  trim: number;
  /** Yellow utility / hazard accent. */
  hazard: number;
  foliage: number;
  /** Neon / emissive accents (cyan, magenta, violet). */
  neonA: number;
  neonB: number;
  neonC: number;
  graffiti: number;
  /** Ink outline colour. */
  ink: number;
  /** Key light colour and intensity, ambient colour and intensity. */
  keyLight: number;
  keyIntensity: number;
  ambient: number;
  ambientIntensity: number;
  /** Bloom strength 0..2 for the post chain. */
  bloom: number;
}

export interface RenderCtx {
  scene: THREE.Scene;
  camera: THREE.OrthographicCamera;
  palette: ThemePalette;
  level: LevelDef;
  loadout: ResolvedLoadout;
  /** Group that layers should add their objects to (cleared by the shell on level change). */
  root: THREE.Group;
  /** Shared toon gradient texture for MeshToonMaterial. */
  toonRamp: THREE.Texture;
  quality: 'low' | 'high';
  /** Ask the shell for camera shake (magnitude 0..1) — ignored when the setting is off. */
  shake(magnitude: number): void;
  /** Ask the shell to nudge the camera focus toward a world point with a weight (cinematic framing). */
  focus(x: number, y: number, weight: number): void;

  // ── optional members added by the shell (present when built by src/render/Renderer.ts) ──

  /**
   * Music-linked architecture hook (chapter 18 "Musical architecture"): every rune inscription,
   * neon fixture and screen the environment built. The shell sets each to level 1 on load and never
   * touches them again, so the fx layer owns their modulation (e.g. from MusicPulse).
   */
  musicReactive?: MusicReactive[];
  /** Post-processing controls the fx layer may drive (no-ops on 'low' quality). */
  post?: PostControls;
  /** Level extents in scene units (X = sim x, Z = sim y). */
  bounds?: { minX: number; minZ: number; maxX: number; maxZ: number; maxY: number; minY: number };
  /** Height of the top surface at a tile (wall top, barrier top, 0 on floor); for fx placement. */
  surfaceHeight?(x: number, y: number): number;
  /** Wall-clock seconds since the renderer was created (shared animation clock). */
  time?: number;
}

/** One emissive surface the fx layer may pulse with the music. */
export interface MusicReactive {
  /** 'rune' inscriptions (floor glyphs, rune panels, wall etching), 'neon' tubes and strips, 'screen' consoles / wave screens, 'core' the time machine heart. */
  kind: 'rune' | 'neon' | 'screen' | 'core';
  material: THREE.Material;
  /** Sim-axes position when the material belongs to one object; absent for materials shared by many tiles. */
  at?: { x: number; y: number };
  /** Brightness relative to the authored look: 1 = as built, 0 = dark, > 1 brighter (blooms). */
  setLevel(level: number): void;
}

/**
 * Screen treatments. `chromatic` and `flash` are kicks: the shell decays them toward 0 every frame,
 * so a layer sets them on an event and forgets. `saturation` and `vignette` are held values the fx
 * layer owns (defaults 1 and 1).
 */
export interface PostControls {
  /** Chromatic split amount 0..1 (use sparingly). */
  chromatic: number;
  /** Full-screen flash 0..1 toward `flashColor`. */
  flash: number;
  flashColor: number;
  /** 1 = as rendered, 0 = greyscale, > 1 more saturated. */
  saturation: number;
  /** Vignette strength multiplier (1 = the theme's default). */
  vignette: number;
}

export interface RenderLayer {
  /** Build per-level objects. Called after the shell has built the environment. */
  loadLevel(ctx: RenderCtx): void;
  /** Draw one frame. */
  update(frame: RenderFrame, ctx: RenderCtx): void;
  dispose(): void;
}

//   src/render/actors/index.ts  →  export function createActorLayer(): RenderLayer
//   src/render/fx/index.ts      →  export function createFxLayer(): RenderLayer
