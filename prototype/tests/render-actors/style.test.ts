import { describe, expect, it } from 'vitest';
import type { LifeState } from '../../src/core/types';
import { ACTOR_STYLE_IDS, actorStyleParams, flickerValue, selectActorStyle } from '../../src/render/actors/style';

const LIVES: LifeState[] = ['alive', 'recGhost', 'ghost'];

describe('actor style selection (UI-03, GHOST-01, DESYNC-06)', () => {
  it('maps every life/sync combination to its own style id', () => {
    const seen = new Set<string>();
    for (const life of LIVES)
      for (const synced of [true, false]) {
        const id = selectActorStyle(life, synced);
        expect(ACTOR_STYLE_IDS).toContain(id);
        seen.add(id);
      }
    expect(seen.size).toBe(LIVES.length * 2);
  });

  it('never conflates the four core readings: alive, recGhost, playback ghost, desynced projection', () => {
    const core = [selectActorStyle('alive', true), selectActorStyle('recGhost', true), selectActorStyle('ghost', true), selectActorStyle('alive', false)];
    expect(new Set(core).size).toBe(4);
    // Distinct body treatments, not just distinct names.
    const bodies = core.map((id) => actorStyleParams(id).body);
    expect(new Set(bodies).size).toBe(4);
  });

  it('a living self is solid and wears its cassette colour', () => {
    const p = actorStyleParams('alive');
    expect(p.body).toBe('solid');
    expect(p.opacity).toBe(1);
    expect(p.hullTapeColor).toBe(true);
    expect(p.marker).toBe('none');
  });

  it('the recording ghost is a cassette-coloured hologram with a broken halo', () => {
    const p = actorStyleParams('recGhost');
    expect(p.body).toBe('holo');
    expect(p.hullTapeColor).toBe(true);
    expect(p.marker).toBe('brokenHalo');
    expect(p.opacity).toBeLessThan(1);
  });

  it('the playback ghost is a grey hollow outline that trails dust', () => {
    const p = actorStyleParams('ghost');
    expect(p.body).toBe('hollow');
    expect(p.hullTapeColor).toBe(false);
    expect(p.desat).toBe(1);
    expect(p.trail).toBe('dust');
    expect(p.glow).toBe(0);
  });

  it('a desynced projection is phased, chromatically split and tethered to its spark', () => {
    const p = actorStyleParams('desynced');
    expect(p.body).toBe('phased');
    expect(p.chroma).toBeGreaterThan(0);
    expect(p.flicker).toBeGreaterThan(0);
    expect(p.tether).toBe(true);
    expect(actorStyleParams('alive').tether).toBe(false);
  });

  it('death dominates desync: a dead self never looks alive because it is unsynced', () => {
    expect(actorStyleParams(selectActorStyle('ghost', false)).body).toBe('hollow');
    expect(actorStyleParams(selectActorStyle('recGhost', false)).body).toBe('holo');
    expect(actorStyleParams(selectActorStyle('recGhost', false)).marker).toBe('brokenHalo');
  });

  it('flicker is deterministic and takes only a few discrete levels (a stutter, not a pulse)', () => {
    const levels = new Set<number>();
    for (let t = 0; t < 5; t += 0.013) {
      const v = flickerValue(t, 1.7);
      expect(v).toBeGreaterThanOrEqual(0);
      expect(v).toBeLessThanOrEqual(1);
      levels.add(v);
    }
    expect(levels.size).toBeLessThanOrEqual(3);
    expect(flickerValue(1.234, 2)).toBe(flickerValue(1.234, 2));
  });
});
