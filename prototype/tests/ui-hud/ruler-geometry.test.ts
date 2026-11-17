import { describe, expect, it } from 'vitest';
import { rulerGeometry } from '../../src/ui/hud/ruler';

describe('ruler geometry', () => {
  for (const [w, h, em, slim] of [
    [1240, 100, 12, false],
    [1880, 150, 17, false],
    [3800, 260, 29, false],
    [960, 90, 11, false],
    [700, 46, 12, true],
  ] as [number, number, number, boolean][]) {
    it(`fits four non-overlapping lanes in ${w}×${h}${slim ? ' (slim)' : ''}`, () => {
      const g = rulerGeometry(w, h, em, slim);
      expect(g.trackX).toBe(g.gutter);
      expect(g.trackX + g.trackW).toBeLessThanOrEqual(w);
      expect(g.laneY[0]).toBeGreaterThanOrEqual(g.bandH);
      for (let i = 1; i < 4; i++) expect(g.laneY[i]).toBeGreaterThanOrEqual(g.laneY[i - 1] + g.laneH);
      expect(g.laneY[3] + g.laneH).toBeLessThanOrEqual(h + 1e-9);
      expect(g.laneH).toBeGreaterThanOrEqual(3);
    });
  }
});
