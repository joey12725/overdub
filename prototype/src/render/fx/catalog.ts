/**
 * Effect catalogue: which effects exist, which view modes may show them, and which effects every
 * simulation event triggers.
 *
 * Readability policy (MUSIC-13, CINE-03, chapter 16 "readability"):
 *   core       — tells the player something about the world (a hit landed, a tape desynced, the boss
 *                remembers). Shown in record, review and cinematic, restrained while recording.
 *   review     — secondary texture (footstep dust, impact dust). Review and cinematic only.
 *   cinematic  — the musical flourishes of the winning performance. Cinematic only, never while the
 *                player is in control.
 * 'idle' shows no event effects at all — only the ambient music visuals.
 */
import type { SimEventType } from '../../core/types';
import type { ViewMode } from '../../contracts';

export type FxTier = 'core' | 'review' | 'cinematic';

export const EFFECT_IDS = [
  // core
  'hitBurst',
  'hitStreaks',
  'tierWord',
  'killBurst',
  'killWord',
  'debris',
  'breakWord',
  'clangSpark',
  'clangTell',
  'swingArc',
  'whiffPuff',
  'dodgeAfterimage',
  'muzzleFlash',
  'projectileImpact',
  'interactPing',
  'interactFail',
  'doorPulse',
  'platePulse',
  'laserPulse',
  'coreIgnite',
  'deathShatter',
  'tapeLetter',
  'desyncTear',
  'resyncConverge',
  'wrapBlink',
  'turnChevrons',
  'endStop',
  'telegraphRing',
  'enemySlash',
  'enemyMuzzle',
  'staggerStars',
  'bossShock',
  'bossRecallTell',
  'objectivePulse',
  // review
  'stepDust',
  'impactDust',
  // cinematic
  'inkSplash',
  'speedLineBurst',
  'cineEcho',
  'cineFocus',
  'finaleBurst',
] as const;

export type EffectId = (typeof EFFECT_IDS)[number];

export const EFFECT_TIER: Record<EffectId, FxTier> = {
  hitBurst: 'core',
  hitStreaks: 'core',
  tierWord: 'core',
  killBurst: 'core',
  killWord: 'core',
  debris: 'core',
  breakWord: 'core',
  clangSpark: 'core',
  clangTell: 'core',
  swingArc: 'core',
  whiffPuff: 'core',
  dodgeAfterimage: 'core',
  muzzleFlash: 'core',
  projectileImpact: 'core',
  interactPing: 'core',
  interactFail: 'core',
  doorPulse: 'core',
  platePulse: 'core',
  laserPulse: 'core',
  coreIgnite: 'core',
  deathShatter: 'core',
  tapeLetter: 'core',
  desyncTear: 'core',
  resyncConverge: 'core',
  wrapBlink: 'core',
  turnChevrons: 'core',
  endStop: 'core',
  telegraphRing: 'core',
  enemySlash: 'core',
  enemyMuzzle: 'core',
  staggerStars: 'core',
  bossShock: 'core',
  bossRecallTell: 'core',
  objectivePulse: 'core',
  stepDust: 'review',
  impactDust: 'review',
  inkSplash: 'cinematic',
  speedLineBurst: 'cinematic',
  cineEcho: 'cinematic',
  cineFocus: 'cinematic',
  finaleBurst: 'cinematic',
};

/**
 * Event → effects. Typed as a full Record so adding a SimEventType without a route fails the
 * typecheck; tests/render-fx/routing.test.ts additionally parses the union from core/types.ts so the
 * test suite fails too.
 */
export const EVENT_ROUTES: Record<SimEventType, readonly EffectId[]> = {
  step: ['stepDust'],
  swing: ['swingArc'],
  hit: ['hitBurst', 'hitStreaks', 'tierWord', 'impactDust', 'inkSplash', 'speedLineBurst'],
  whiff: ['whiffPuff'],
  kill: ['killBurst', 'killWord', 'impactDust', 'inkSplash', 'speedLineBurst', 'cineFocus'],
  break: ['debris', 'breakWord', 'impactDust', 'inkSplash', 'speedLineBurst', 'cineFocus'],
  clang: ['clangSpark', 'clangTell'],
  dodge: ['dodgeAfterimage'],
  fire: ['muzzleFlash'],
  projectileHit: ['projectileImpact', 'tierWord', 'inkSplash'],
  interact: ['interactPing'],
  interactFail: ['interactFail'],
  door: ['doorPulse'],
  plate: ['platePulse'],
  laser: ['laserPulse'],
  core: ['coreIgnite', 'speedLineBurst', 'cineFocus'],
  selfDeath: ['deathShatter', 'tapeLetter', 'inkSplash', 'cineFocus'],
  desync: ['desyncTear', 'cineEcho'],
  resync: ['resyncConverge', 'cineEcho', 'cineFocus'],
  tapeWrap: ['wrapBlink', 'tapeLetter'],
  tapeTurn: ['turnChevrons', 'tapeLetter'],
  tapeEnd: ['endStop', 'tapeLetter'],
  enemyTelegraph: ['telegraphRing'],
  enemyAttack: ['enemySlash'],
  enemyShot: ['enemyMuzzle'],
  enemyStagger: ['staggerStars'],
  bossPhase: ['bossShock', 'inkSplash', 'speedLineBurst', 'cineFocus'],
  bossRecall: ['bossRecallTell', 'cineFocus'],
  objective: ['objectivePulse', 'finaleBurst', 'cineFocus'],
};

/** How a view mode dresses effects. */
export interface ModeProfile {
  /** Event-driven effects run at all. */
  events: boolean;
  /** Highest tier allowed. */
  maxTier: FxTier;
  /** Scales particle counts, sizes and alphas. */
  intensity: number;
  /** Scales camera-shake requests. */
  shake: number;
  /** Minimum momentum tier index whose word readout is shown (0 shows every hit). */
  minWordTier: number;
  /** Scale of floating readouts. */
  textScale: number;
  /** Brightness of the ambient music visuals (runes, sigils, contour strips, epicycles). */
  ambient: number;
  /** Strength of the world-speed treatment (worldRate != 1). */
  worldSpeed: number;
  /** Letterbox bar height as a fraction of the screen height, per side. */
  letterbox: number;
}

export const MODE_PROFILES: Record<ViewMode, ModeProfile> = {
  idle: {
    events: false,
    maxTier: 'core',
    intensity: 0,
    shake: 0,
    minWordTier: 99,
    textScale: 0,
    ambient: 1,
    worldSpeed: 0,
    letterbox: 0,
  },
  record: {
    events: true,
    maxTier: 'core',
    intensity: 0.7,
    shake: 0.55,
    minWordTier: 2,
    textScale: 0.8,
    ambient: 0.55,
    worldSpeed: 1,
    letterbox: 0,
  },
  review: {
    events: true,
    maxTier: 'review',
    intensity: 0.9,
    shake: 0.8,
    minWordTier: 1,
    textScale: 0.9,
    ambient: 0.8,
    worldSpeed: 0.6,
    letterbox: 0,
  },
  cinematic: {
    events: true,
    maxTier: 'cinematic',
    intensity: 1.2,
    shake: 1,
    minWordTier: 0,
    textScale: 1.1,
    ambient: 1,
    worldSpeed: 0.4,
    letterbox: 0.085,
  },
};

const TIER_RANK: Record<FxTier, number> = { core: 0, review: 1, cinematic: 2 };

/** True when an effect of `tier` may spawn in `mode`. */
export function tierAllowed(tier: FxTier, mode: ViewMode): boolean {
  const p = MODE_PROFILES[mode];
  return p.events && TIER_RANK[tier] <= TIER_RANK[p.maxTier];
}

export function effectAllowed(id: EffectId, mode: ViewMode): boolean {
  return tierAllowed(EFFECT_TIER[id], mode);
}
