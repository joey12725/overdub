import { describe, expect, it } from 'vitest';
import type { ViewMode } from '../../src/contracts';
import { EFFECT_IDS, EFFECT_TIER, effectAllowed } from '../../src/render/fx/catalog';
import { TAG_CINE_CONTINUOUS, type FxDirector } from '../../src/render/fx/director';
import { declaredEventTypes, eventOf, frame, makeDirector } from './fixtures';

const CINEMATIC_TAGS = new Set<number>([
  ...EFFECT_IDS.map((id, i) => (EFFECT_TIER[id] === 'cinematic' ? i : -1)).filter((i) => i >= 0),
  TAG_CINE_CONTINUOUS,
]);
const REVIEW_TAGS = new Set<number>(EFFECT_IDS.map((id, i) => (EFFECT_TIER[id] === 'review' ? i : -1)).filter((i) => i >= 0));

function liveTags(d: FxDirector): number[] {
  const tags: number[] = [];
  for (const pool of [d.glow, d.ink]) for (let i = 0; i < pool.capacity; i++) if (pool.alive[i]) tags.push(pool.tag[i]);
  for (let i = 0; i < d.text.capacity; i++) if (d.text.alive[i]) tags.push(d.text.tag[i]);
  return tags;
}

/** Play ~4 seconds of a busy encounter: every event type, several powers, beats and chord changes. */
async function playBusy(mode: ViewMode, worldRate = 1): Promise<{ d: FxDirector; tags: Set<number> }> {
  const types = await declaredEventTypes();
  const d = makeDirector();
  const seen = new Set<number>();
  for (let f = 0; f < 240; f++) {
    const beat = f * (2 / 60) * worldRate;
    const evs = f % 10 === 0 ? types.map((t, i) => eventOf(t, 5 + ((f + i) % 6) * 12, ((i + f) % 4) as 0 | 1 | 2 | 3)) : [];
    d.update(frame(mode, beat, evs, { worldRate }));
    for (const t of liveTags(d)) seen.add(t);
  }
  return { d, tags: seen };
}

describe('mode gating', () => {
  it('never spawns cinematic-only effects in record mode', async () => {
    const { d, tags } = await playBusy('record', 0.5);
    for (const t of tags) expect(CINEMATIC_TAGS.has(t), `tag ${t} (${EFFECT_IDS[t] ?? 'continuous'}) in record`).toBe(false);
    for (const t of tags) expect(REVIEW_TAGS.has(t), `review-tier tag ${t} in record`).toBe(false);
    for (const id of EFFECT_IDS) {
      if (EFFECT_TIER[id] !== 'core') expect(d.spawnCounts[EFFECT_IDS.indexOf(id)], id).toBe(0);
    }
    expect(d.screen.letterbox).toBe(0);
    expect(d.screen.sweepA).toBeLessThan(0.001);
    expect(d.focusW).toBe(0);
    for (let t = 0; t < 4; t++) expect(d.ribbons.count[t]).toBe(0);
    expect(d.shakeOut).toBeLessThanOrEqual(0.55 + 1e-6);
  });

  it('review allows review texture but no cinematic flourishes', async () => {
    const { d, tags } = await playBusy('review');
    for (const t of tags) expect(CINEMATIC_TAGS.has(t)).toBe(false);
    expect(d.spawnCounts[EFFECT_IDS.indexOf('stepDust')]).toBeGreaterThan(0);
    expect(d.spawnCounts[EFFECT_IDS.indexOf('inkSplash')]).toBe(0);
    expect(d.screen.letterbox).toBe(0);
  });

  it('idle shows no event effects at all', async () => {
    const { d, tags } = await playBusy('idle');
    expect(tags.size).toBe(0);
    expect(d.glow.count + d.ink.count + d.text.count).toBe(0);
    expect(Array.from(d.spawnCounts).every((c) => c === 0)).toBe(true);
  });

  it('cinematic adds flourishes: letterbox, ribbons, ink, focus, beat ripples', async () => {
    const { d, tags } = await playBusy('cinematic');
    expect(d.spawnCounts[EFFECT_IDS.indexOf('inkSplash')]).toBeGreaterThan(0);
    expect(d.spawnCounts[EFFECT_IDS.indexOf('finaleBurst')]).toBeGreaterThan(0);
    expect(d.screen.letterbox).toBeGreaterThan(0.07);
    expect(tags.has(TAG_CINE_CONTINUOUS)).toBe(true);
    expect(d.ribbons.count[0]).toBeGreaterThan(10);
    expect(d.focusW).toBeGreaterThan(0);
  });

  it('effectAllowed agrees with the tiers', () => {
    for (const id of EFFECT_IDS) {
      expect(effectAllowed(id, 'idle')).toBe(false);
      expect(effectAllowed(id, 'cinematic')).toBe(true);
      expect(effectAllowed(id, 'record')).toBe(EFFECT_TIER[id] === 'core');
    }
  });

  it('applies the world-speed treatment from worldRate (slowed vs sped world)', () => {
    const slow = makeDirector();
    const fast = makeDirector();
    for (let f = 0; f < 120; f++) {
      slow.update(frame('record', f / 60, [], { worldRate: 0.5 }));
      fast.update(frame('record', f / 60, [], { worldRate: 2 }));
    }
    expect(slow.worldSpeed).toBeLessThan(-0.3);
    expect(fast.worldSpeed).toBeGreaterThan(0.3);
    expect(slow.screen.speedSign).toBe(-1);
    expect(fast.screen.speedSign).toBe(1);
    expect(slow.screen.tintA).toBeGreaterThan(0);
    // Readability: the tint stays faint.
    expect(fast.screen.tintA).toBeLessThan(0.1);
    const normal = makeDirector();
    for (let f = 0; f < 120; f++) normal.update(frame('record', f / 60, [], { worldRate: 1 }));
    expect(normal.screen.tintA).toBe(0);
  });

  it('reaches a steady state: repeated busy frames do not grow any pool', async () => {
    const types = await declaredEventTypes();
    const d = makeDirector();
    const bufs = [d.glow.pos, d.ink.pos, d.text.pos];
    for (let f = 0; f < 600; f++) d.update(frame('cinematic', f / 30, types.map((t) => eventOf(t, 60))));
    expect(d.glow.count).toBeLessThanOrEqual(d.glow.capacity);
    expect(d.ink.count).toBeLessThanOrEqual(d.ink.capacity);
    expect(d.text.count).toBeLessThanOrEqual(d.text.capacity);
    expect([d.glow.pos, d.ink.pos, d.text.pos]).toEqual(bufs);
  });
});
