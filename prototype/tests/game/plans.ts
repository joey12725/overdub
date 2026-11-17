/**
 * Closed-loop bot controllers for game-layer tests: a small step list (go to, interact, wait) plus
 * reflexes (strike enemies in reach, dodge incoming bolts). Deterministic: it reads only the
 * session's own snapshots.
 */
import type { BotContext, BotTake } from '../../src/game/bot';
import { idleInput, steerTo } from '../../src/game/bot';
import type { EndMode, PlayerInput, TapeSpeed } from '../../src/core/types';

export type PlanStep =
  | { kind: 'goto'; x: number; y: number; tol?: number }
  | { kind: 'interact' }
  | { kind: 'wait'; ticks: number }
  | { kind: 'hold'; x: number; y: number };

export interface ReflexOptions {
  /** Strike enemies whose centre is within this distance. */
  strikeRange?: number;
  /** Ticks between swings. */
  swingEvery?: number;
  /** Dodge enemy bolts closer than this that are heading at the self. */
  dodgeRange?: number;
  /** Enemy ids to leave alone. */
  ignore?: string[];
  heavy?: boolean;
}

export function planTake(speed: TapeSpeed, endMode: EndMode, steps: PlanStep[], reflex: ReflexOptions = {}): BotTake {
  let i = 0;
  let waitLeft = -1;
  let lastSwing = -1000;
  let lastDodge = -1000;
  const strikeRange = reflex.strikeRange ?? 1.45;
  const swingEvery = reflex.swingEvery ?? 22;
  const dodgeRange = reflex.dodgeRange ?? 0;
  return {
    speed,
    endMode,
    inputs(tick: number, ctx: BotContext): PlayerInput {
      const self = ctx.self;
      // Reflex: dodge a bolt that is about to arrive.
      if (dodgeRange > 0 && tick - lastDodge > 40) {
        for (const p of ctx.snap.projectiles) {
          if (!('enemy' in p.owner)) continue;
          const dx = self.x - p.x;
          const dy = self.y - p.y;
          const d = Math.hypot(dx, dy);
          const heading = Math.cos(p.dir) * dx + Math.sin(p.dir) * dy;
          if (d < dodgeRange && heading > 0) {
            lastDodge = tick;
            const inp = idleInput(p.dir + Math.PI / 2);
            inp.moveX = Math.cos(p.dir + Math.PI / 2);
            inp.moveY = Math.sin(p.dir + Math.PI / 2);
            inp.dodge = true;
            return inp;
          }
        }
      }
      // Reflex: strike the nearest living enemy in reach.
      if (self.life === 'alive' || self.life === 'recGhost') {
        let best: { x: number; y: number; d: number } | null = null;
        for (const e of ctx.snap.enemies) {
          if (!e.alive || reflex.ignore?.includes(e.id)) continue;
          const d = Math.hypot(e.x - self.x, e.y - self.y);
          if (d < strikeRange && (!best || d < best.d)) best = { x: e.x, y: e.y, d };
        }
        if (best) {
          const inp = idleInput(Math.atan2(best.y - self.y, best.x - self.x));
          if (tick - lastSwing >= swingEvery) {
            lastSwing = tick;
            if (reflex.heavy) inp.heavy = true;
            else inp.light = true;
          }
          return inp;
        }
      }
      while (i < steps.length) {
        const s = steps[i];
        if (s.kind === 'goto') {
          if (Math.hypot(s.x - self.x, s.y - self.y) <= (s.tol ?? 0.15)) {
            i++;
            continue;
          }
          return steerTo(self, s.x, s.y, 0.02);
        }
        if (s.kind === 'interact') {
          i++;
          const inp = idleInput(self.facing);
          inp.interact = true;
          return inp;
        }
        if (s.kind === 'wait') {
          if (waitLeft < 0) waitLeft = s.ticks;
          if (waitLeft-- > 0) return idleInput(self.facing);
          waitLeft = -1;
          i++;
          continue;
        }
        return steerTo(self, s.x, s.y, 0.05);
      }
      return idleInput(self.facing);
    },
  };
}
