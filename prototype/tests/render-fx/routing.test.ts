import { describe, expect, it } from 'vitest';
import { EFFECT_IDS, EFFECT_TIER, EVENT_ROUTES } from '../../src/render/fx/catalog';
import { declaredEventTypes, eventOf, frame, makeDirector } from './fixtures';

describe('event → effect routing', () => {
  it('maps every SimEventType declared in core/types.ts (fails when a new event type has no route)', async () => {
    const declared = await declaredEventTypes();
    expect(declared.length).toBeGreaterThan(20);
    const routed = Object.keys(EVENT_ROUTES).sort();
    const missing = declared.filter((t) => !(t in EVENT_ROUTES));
    expect(missing, `SimEventTypes without an fx route: ${missing.join(', ')}`).toEqual([]);
    const stale = routed.filter((t) => !declared.includes(t as never));
    expect(stale, `fx routes for event types that no longer exist: ${stale.join(', ')}`).toEqual([]);
  });

  it('routes every event to at least one known effect, and every effect is reachable', () => {
    const used = new Set<string>();
    for (const [type, effects] of Object.entries(EVENT_ROUTES)) {
      expect(effects.length, type).toBeGreaterThan(0);
      for (const id of effects) {
        expect(EFFECT_IDS, `${type} → ${id}`).toContain(id);
        used.add(id);
      }
    }
    for (const id of EFFECT_IDS) {
      expect(EFFECT_TIER[id], id).toBeDefined();
      expect(used.has(id), `effect ${id} is never triggered`).toBe(true);
    }
  });

  it('every event type gives the player at least one non-cinematic tell (except pure texture)', () => {
    // Cinematic flourishes must be extra, never the only feedback (MUSIC-13: readability while recording).
    for (const [type, effects] of Object.entries(EVENT_ROUTES)) {
      const hasCore = effects.some((id) => EFFECT_TIER[id] === 'core');
      if (type === 'step') continue;
      expect(hasCore, type).toBe(true);
    }
  });

  it('runs every effect in cinematic mode without throwing and actually spawns something', async () => {
    const types = await declaredEventTypes();
    for (const type of types) {
      const d = makeDirector();
      d.update(frame('cinematic', 4.2, [eventOf(type, 40)]));
      const sprites = d.glow.count + d.ink.count + d.text.count;
      const screen = d.screen.burstAmt + d.screen.flashA + d.screen.glitch + d.focusW;
      expect(sprites + screen, `${type} produced nothing`).toBeGreaterThan(0);
      for (const id of EVENT_ROUTES[type]) {
        expect(d.spawnCounts[EFFECT_IDS.indexOf(id)], `${type} → ${id}`).toBeGreaterThan(0);
      }
    }
  });

  it('tolerates events with missing optional fields', async () => {
    const types = await declaredEventTypes();
    const d = makeDirector();
    const evs = types.map((type, i) => ({ sub: i, type, x: 3, y: 3 }));
    expect(() => d.update(frame('cinematic', 2, evs))).not.toThrow();
    for (let i = 0; i < d.glow.capacity * 3; i++) expect(Number.isFinite(d.glow.pos[i])).toBe(true);
  });
});
