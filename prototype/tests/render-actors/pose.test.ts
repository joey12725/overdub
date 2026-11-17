import { describe, expect, it } from 'vitest';
import { ANIM_STATES, type MeleeWeaponDef } from '../../src/core/types';
import {
  animDurationTicks,
  animProgress,
  blendPose,
  computePose,
  createPose,
  createPoseParams,
  POSE_KEYS,
  POSE_STATES,
  type MeleeStyle,
} from '../../src/render/actors/pose';

const STYLES: MeleeStyle[] = ['blade', 'blunt', 'whip', 'gauntlet'];

const MELEE: Pick<MeleeWeaponDef, 'light' | 'heavy'> = {
  light: { windup: 8, active: 6, recover: 12, impact: 1, moveMul: 0.5 },
  heavy: { windup: 22, active: 8, recover: 22, impact: 2, moveMul: 0.3 },
};

describe('pose functions', () => {
  it('cover every AnimState plus the death transition', () => {
    for (const s of ANIM_STATES) expect(POSE_STATES).toContain(s);
    expect(POSE_STATES).toContain('death');
  });

  it('return finite joint values for every state across t in [0, 1], every weapon style and motion', () => {
    const out = createPose();
    const p = createPoseParams();
    for (const style of STYLES)
      for (const speed of [0, 0.4, 1])
        for (const state of POSE_STATES)
          for (let i = 0; i <= 20; i++) {
            const t = i / 20;
            p.style = style;
            p.speed = speed;
            p.time = t * 7.3;
            p.stride = t * 40;
            p.beat = t;
            p.leanF = speed * 1.4 - 0.2;
            p.leanS = -speed;
            computePose(state, t, p, out);
            for (const k of POSE_KEYS) {
              if (!Number.isFinite(out[k])) throw new Error(`${state} ${style} t=${t}: ${k}=${out[k]}`);
              // Sanity bound: no joint flips more than a full turn.
              expect(Math.abs(out[k])).toBeLessThan(Math.PI * 2);
            }
          }
  });

  it('survives garbage progress values', () => {
    const out = createPose();
    const p = createPoseParams();
    for (const t of [Number.NaN, -5, 7, Infinity]) {
      computePose('heavyActive', t, p, out);
      for (const k of POSE_KEYS) expect(Number.isFinite(out[k])).toBe(true);
    }
  });

  it('light and heavy windups have clearly different silhouettes', () => {
    const p = createPoseParams();
    const light = computePose('lightWindup', 1, p, createPose());
    const heavy = computePose('heavyWindup', 1, p, createPose());
    // Heavy hauls the weapon overhead from a deep crouch; light draws it sideways.
    expect(heavy.armRRaise).toBeGreaterThan(2.3);
    expect(light.armRRaise).toBeLessThan(1.5);
    expect(light.armROut).toBeGreaterThan(1);
    expect(heavy.rootY).toBeLessThan(light.rootY - 0.05);
    expect(heavy.kneeL).toBeGreaterThan(light.kneeL + 0.5);
  });

  it('swing progress drives the trail: 0 before the active frame, 1 by its end', () => {
    const p = createPoseParams();
    const o = createPose();
    expect(computePose('lightWindup', 1, p, o).swing).toBe(0);
    expect(computePose('lightActive', 0, p, o).swing).toBeCloseTo(0);
    expect(computePose('lightActive', 1, p, o).swing).toBeCloseTo(1);
    expect(computePose('heavyActive', 1, p, o).swing).toBeCloseTo(1);
  });

  it('dodge stretches along the motion and leans forward mid-dash', () => {
    const p = createPoseParams();
    const mid = computePose('dodge', 0.5, p, createPose());
    expect(mid.stretch).toBeGreaterThan(0.2);
    expect(mid.hipsPitch).toBeGreaterThan(0.4);
  });

  it('the stopped pose is held: independent of time and beat', () => {
    const p = createPoseParams();
    const a = computePose('stopped', 0, p, createPose());
    p.time = 12.3;
    const b = computePose('stopped', 0.7, p, createPose());
    for (const k of POSE_KEYS) {
      if (k === 'phonesBob' || k === 'headPitch') continue;
      expect(b[k]).toBeCloseTo(a[k]);
    }
  });

  it('run trails the pigtails behind more at speed', () => {
    const p = createPoseParams();
    p.speed = 0.1;
    const slow = computePose('run', 0, p, createPose());
    p.speed = 1;
    const fast = computePose('run', 0, p, createPose());
    expect(fast.pigLSwing).toBeGreaterThan(slow.pigLSwing + 0.4);
    expect(fast.hipsPitch).toBeGreaterThan(slow.hipsPitch);
  });

  it('blendPose interpolates every key', () => {
    const a = createPose();
    const b = createPose();
    for (const k of POSE_KEYS) b[k] = 1;
    const o = blendPose(a, b, 0.25, createPose());
    for (const k of POSE_KEYS) expect(o[k]).toBeCloseTo(0.25);
  });
});

describe('animation timing', () => {
  it('reads timed-state lengths from the equipped weapons', () => {
    expect(animDurationTicks('lightWindup', MELEE, { commit: 18 })).toBe(8);
    expect(animDurationTicks('heavyRecover', MELEE, { commit: 18 })).toBe(22);
    expect(animDurationTicks('ranged', MELEE, { commit: 18 })).toBe(18);
    expect(animDurationTicks('idle', MELEE, { commit: 18 })).toBe(0);
    expect(animDurationTicks('dodge', MELEE, { commit: 18 })).toBeGreaterThan(0);
  });

  it('progress runs forward, clamps, and runs backward on a reverse pass', () => {
    expect(animProgress(10, 10, 1, 8)).toBe(0);
    expect(animProgress(10, 14, 1, 8)).toBeCloseTo(0.5);
    expect(animProgress(10, 30, 1, 8)).toBe(1);
    // Reverse: entered at the recorded end, ticks decreasing → motion rewinds.
    expect(animProgress(30, 28, -1, 8)).toBeCloseTo(0.75);
    expect(animProgress(30, 22, -1, 8)).toBe(0);
    expect(animProgress(0, 5, 1, 0)).toBe(0);
  });
});
