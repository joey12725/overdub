/**
 * State → visual style selection for a self (UI-03, GHOST-01, GHOST-05, DESYNC-06).
 *
 * The four readings that must never be confused with each other or with a living self:
 *   recGhost  — live take after death: translucent cassette-coloured hologram, scanlines, broken halo.
 *   ghost     — played-back tape after death: faint grey hollow outline, trailing dust, inert.
 *   desynced  — alive but desynchronised projection: flickering, chromatic split, phased out,
 *               tethered by a dashed line to the recovery spark.
 *   alive     — solid cel-shaded Moxie with a cassette-coloured ink outline.
 *
 * Every (life, synced) combination gets its own id. A death ghost does not become alive because a
 * spark catches up (chapter 06 table), so the death reading dominates and the desync reading is
 * layered on top of it rather than replacing it.
 */
import type { LifeState } from '../../core/types';

export type ActorStyleId =
  | 'alive'
  | 'desynced'
  | 'recGhost'
  | 'recGhostDesynced'
  | 'ghost'
  | 'ghostDesynced';

export const ACTOR_STYLE_IDS: readonly ActorStyleId[] = [
  'alive',
  'desynced',
  'recGhost',
  'recGhostDesynced',
  'ghost',
  'ghostDesynced',
];

export function selectActorStyle(life: LifeState, synced: boolean): ActorStyleId {
  switch (life) {
    case 'alive':
      return synced ? 'alive' : 'desynced';
    case 'recGhost':
      return synced ? 'recGhost' : 'recGhostDesynced';
    case 'ghost':
      return synced ? 'ghost' : 'ghostDesynced';
  }
}

/** How the body is drawn. */
export type BodyMode =
  /** Opaque cel shading, coloured ink hull. */
  | 'solid'
  /** Translucent tape-tinted hologram with scanlines. */
  | 'holo'
  /** Depth-only body: only the hull rim shows, so the silhouette is hollow. */
  | 'hollow'
  /** Translucent, desaturated, flickering body with red/cyan split echoes. */
  | 'phased';

export interface ActorStyleParams {
  body: BodyMode;
  /** Overall body opacity (solid ignores it unless dodging). */
  opacity: number;
  /** 0 = full colour, 1 = greyscale. */
  desat: number;
  /** Ink hull opacity and whether it uses the tape colour (else neutral grey). */
  hullOpacity: number;
  hullTapeColor: boolean;
  /** Hull thickness multiplier. */
  hullScale: number;
  /** Chromatic split echo strength 0..1. */
  chroma: number;
  /** Random-looking visibility flicker strength 0..1. */
  flicker: number;
  /** Floor ring opacity multiplier. */
  ring: number;
  /** Headphone glow multiplier. */
  glow: number;
  /** Floating marker above the head. */
  marker: 'none' | 'brokenHalo';
  /** Particle trail left behind while moving. */
  trail: 'none' | 'dust' | 'holoBits';
  /** Draw the spark + dashed tether when a spark position exists. */
  tether: boolean;
}

const STYLE_TABLE: Record<ActorStyleId, ActorStyleParams> = {
  alive: {
    body: 'solid',
    opacity: 1,
    desat: 0,
    hullOpacity: 1,
    hullTapeColor: true,
    hullScale: 1,
    chroma: 0,
    flicker: 0,
    ring: 1,
    glow: 1,
    marker: 'none',
    trail: 'none',
    tether: false,
  },
  desynced: {
    body: 'phased',
    opacity: 0.42,
    desat: 0.55,
    hullOpacity: 0.7,
    hullTapeColor: true,
    hullScale: 0.8,
    chroma: 1,
    flicker: 0.6,
    ring: 0.35,
    glow: 0.5,
    marker: 'none',
    trail: 'none',
    tether: true,
  },
  recGhost: {
    body: 'holo',
    opacity: 0.55,
    desat: 0,
    hullOpacity: 0.95,
    hullTapeColor: true,
    hullScale: 1.25,
    chroma: 0,
    flicker: 0.15,
    ring: 0.6,
    glow: 1.4,
    marker: 'brokenHalo',
    trail: 'holoBits',
    tether: false,
  },
  recGhostDesynced: {
    body: 'holo',
    opacity: 0.4,
    desat: 0,
    hullOpacity: 0.8,
    hullTapeColor: true,
    hullScale: 1.1,
    chroma: 0.8,
    flicker: 0.55,
    ring: 0.4,
    glow: 1,
    marker: 'brokenHalo',
    trail: 'holoBits',
    tether: true,
  },
  ghost: {
    body: 'hollow',
    opacity: 0,
    desat: 1,
    hullOpacity: 0.6,
    hullTapeColor: false,
    hullScale: 1.1,
    chroma: 0,
    flicker: 0,
    ring: 0.18,
    glow: 0,
    marker: 'none',
    trail: 'dust',
    tether: false,
  },
  ghostDesynced: {
    body: 'hollow',
    opacity: 0,
    desat: 1,
    hullOpacity: 0.45,
    hullTapeColor: false,
    hullScale: 1.1,
    chroma: 0.35,
    flicker: 0.3,
    ring: 0.15,
    glow: 0,
    marker: 'none',
    trail: 'dust',
    tether: true,
  },
};

export function actorStyleParams(id: ActorStyleId): ActorStyleParams {
  return STYLE_TABLE[id];
}

/** Desaturation added on top of the style while a 'stop' tape holds its final pose. */
export const STOPPED_DESAT = 0.45;

/** Body opacity while dodge i-frames are active: visibly flickering between these two values. */
export const IFRAME_OPACITY_LOW = 0.3;
export const IFRAME_OPACITY_HIGH = 0.85;

/** Deterministic flicker in [0, 1] used for i-frames and desync: hard stutter, not a smooth pulse. */
export function flickerValue(time: number, seed: number): number {
  const a = Math.sin(time * 37.0 + seed * 11.0);
  const b = Math.sin(time * 13.7 + seed * 3.1);
  const c = Math.sin(time * 61.3 + seed * 7.7);
  const v = a * 0.5 + b * 0.35 + c * 0.15;
  return v > 0.15 ? 1 : v > -0.35 ? 0.55 : 0.1;
}
