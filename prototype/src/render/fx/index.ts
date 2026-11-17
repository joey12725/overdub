/**
 * Effects, music-linked visuals and the cinematic layer (CINE-03, MUSIC-12, MUSIC-13).
 *
 *   createFxLayer(): RenderLayer   — the only export the renderer shell needs.
 *
 * Structure:
 *   director.ts     CPU: events → pooled sprites/readouts, world-speed + cinematic state (testable headless)
 *   gpu/*           instanced sprite mesh, readout atlas, thick polylines, screen overlay
 *   music/ambient   runes, contour strips, sigils and epicycles driven by RenderFrame.music
 *
 * Everything this layer adds lives under one group in ctx.root; meshes carry userData.fx = true and
 * userData.noOutline = true (and the overlay userData.fxOverlay = true) so an outline / depth pre-pass
 * in the shell can skip them.
 */
import * as THREE from 'three';
import type { RenderFrame } from '../../contracts';
import type { RenderCtx, RenderLayer } from '../layer';
import { MODE_PROFILES } from './catalog';
import { TAPE_HEX, hexToRgb } from './colors';
import { FxDirector, RIBBON_POINTS, TEXT_CAPACITY } from './director';
import { FACING_FLOOR, PolylineBatch } from './gpu/polyline';
import { ScreenOverlay } from './gpu/overlay';
import { SpriteMesh } from './gpu/spriteMesh';
import { TextMesh, createWordAtlas, type WordAtlas } from './gpu/textMesh';
import { MusicAmbient } from './music/ambient';

export { EVENT_ROUTES, EFFECT_IDS, EFFECT_TIER, MODE_PROFILES } from './catalog';
export { FxDirector } from './director';

class FxLayer implements RenderLayer {
  private group: THREE.Group | null = null;
  private director: FxDirector | null = null;
  private glowMesh: SpriteMesh | null = null;
  private inkMesh: SpriteMesh | null = null;
  private textMesh: TextMesh | null = null;
  private overlay: ScreenOverlay | null = null;
  private ambient: MusicAmbient | null = null;
  private ribbons: PolylineBatch | null = null;
  private atlas: WordAtlas | null = null;
  private quality: 'low' | 'high' = 'high';
  private readonly view = new THREE.Vector3();
  private readonly rgb = new Float32Array(12);
  private time = 0;

  loadLevel(ctx: RenderCtx): void {
    this.disposeLevel();
    this.quality = ctx.quality;
    const group = new THREE.Group();
    group.name = 'fx';
    group.userData.fx = true;
    ctx.root.add(group);
    this.group = group;

    const loadout = ctx.loadout;
    const ref = loadout.melee.light.impact * (loadout.mods.meleeImpact ?? 1);
    const director = new FxDirector({
      palette: ctx.palette,
      level: ctx.level,
      refMomentum: ref > 0 ? ref : 1,
      meleeReach: loadout.melee.reach,
      meleeArcDeg: loadout.melee.arcDeg,
      quality: ctx.quality,
    });
    this.director = director;

    // Ink (normal blend) draws before the glow so glows sit on top of splashes; both draw before
    // the actor layer's transparent telegraphs (renderOrder ≥ 0 there) only where we choose low orders.
    this.inkMesh = new SpriteMesh(director.ink.capacity, false, 1);
    this.glowMesh = new SpriteMesh(director.glow.capacity, true, 5);
    group.add(this.inkMesh.mesh, this.glowMesh.mesh);

    this.ambient = new MusicAmbient(ctx.level, ctx.palette, ctx.quality);
    group.add(this.ambient.createMesh());

    this.ribbons = new PolylineBatch(4 * RIBBON_POINTS);
    for (let t = 0; t < 4; t++) this.ribbons.addLine(RIBBON_POINTS, FACING_FLOOR, false);
    group.add(this.ribbons.finalize(3));
    for (let t = 0; t < 4; t++) hexToRgb(TAPE_HEX[t], this.rgb, t * 3);

    if (!this.atlas) {
      try {
        this.atlas = createWordAtlas();
      } catch (err) {
        // Without a canvas the readouts cannot be painted; every other effect still works.
        console.warn('[fx] readout atlas unavailable:', err);
      }
    }
    if (this.atlas) {
      this.textMesh = new TextMesh(TEXT_CAPACITY, this.atlas, ctx.palette.ink);
      group.add(this.textMesh.mesh);
    }

    this.overlay = new ScreenOverlay();
    this.overlay.setInk(ctx.palette.ink);
    group.add(this.overlay.mesh);
  }

  update(frame: RenderFrame, ctx: RenderCtx): void {
    const d = this.director;
    if (!d || !this.group) return;
    if (ctx.quality !== this.quality) {
      this.quality = ctx.quality;
      d.setQuality(ctx.quality);
    }
    if (this.group.parent !== ctx.root) ctx.root.add(this.group);
    const dt = Math.min(0.1, Math.max(0, frame.dt));
    this.time += dt;

    d.update(frame);

    if (d.shakeOut > 0.001) ctx.shake(d.shakeOut);
    if (frame.mode === 'cinematic' && d.focusW > 0) ctx.focus(d.focusX, d.focusY, d.focusW);

    this.glowMesh?.sync(d.glow);
    this.inkMesh?.sync(d.ink);
    this.textMesh?.sync(d.text);
    this.overlay?.sync(d.screen, ctx.camera);

    ctx.camera.getWorldDirection(this.view);
    this.syncRibbons(d);
    const prof = MODE_PROFILES[frame.mode] ?? MODE_PROFILES.idle;
    this.ambient?.update(frame.music, prof.ambient, dt, ctx.camera);
  }

  private syncRibbons(d: FxDirector): void {
    const rb = this.ribbons;
    if (!rb) return;
    const tr = d.ribbons;
    for (let t = 0; t < 4; t++) {
      const n = tr.count[t];
      const alpha = tr.alpha[t];
      if (n < 2 || alpha < 0.01) {
        rb.setLineAlpha(t, 0);
        continue;
      }
      // Desynced selves' ribbons stutter; ghosts' are faint and greyed toward white.
      const flicker = tr.state[t] === 2 ? (Math.sin(this.time * 38 + t) > -0.2 ? 1 : 0.25) : 1;
      rb.setLineAlpha(t, alpha * flicker);
      const o3 = t * 3;
      const ghost = tr.state[t] === 1;
      const r = ghost ? 0.5 + this.rgb[o3] * 0.5 : this.rgb[o3];
      const g = ghost ? 0.5 + this.rgb[o3 + 1] * 0.5 : this.rgb[o3 + 1];
      const b = ghost ? 0.5 + this.rgb[o3 + 2] * 0.5 : this.rgb[o3 + 2];
      for (let i = 0; i < RIBBON_POINTS; i++) {
        // Unused points collapse onto the oldest real point with zero width and alpha.
        const k = i < RIBBON_POINTS - n ? 0 : i - (RIBBON_POINTS - n);
        const o = tr.pointIndex(t, k);
        rb.setPoint(t, i, tr.pts[o], tr.pts[o + 1] + t * 0.002, tr.pts[o + 2]);
        const f = i < RIBBON_POINTS - n ? 0 : k / (n - 1);
        rb.setWidth(t, i, 0.04 + 0.2 * f);
        rb.setColor(t, i, r, g, b, 0.75 * f * f);
      }
    }
    rb.commit(this.view);
  }

  private disposeLevel(): void {
    this.group?.parent?.remove(this.group);
    this.glowMesh?.dispose();
    this.inkMesh?.dispose();
    this.textMesh?.dispose();
    this.overlay?.dispose();
    this.ambient?.dispose();
    this.ribbons?.dispose();
    this.group = null;
    this.director = null;
    this.glowMesh = null;
    this.inkMesh = null;
    this.textMesh = null;
    this.overlay = null;
    this.ambient = null;
    this.ribbons = null;
  }

  dispose(): void {
    this.disposeLevel();
    this.atlas?.texture.dispose();
    this.atlas = null;
  }
}

export function createFxLayer(): RenderLayer {
  return new FxLayer();
}
