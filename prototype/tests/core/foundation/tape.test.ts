import { describe, expect, it } from 'vitest';
import {
  angleDelta,
  animFromIndex,
  animIndex,
  base64FromBytes,
  bytesFromBase64,
  cloneTape,
  deserializeTape,
  lerpAngle,
  localVelocityAt,
  masterVelocityAt,
  samplePose,
  samplePoseAtSub,
  samplePosInto,
  serializeTape,
  TapeRecorder,
  tapesEqual,
  withEndMode,
  wrapAngle,
} from '../../../src/core/tape';
import { ANIM_STATES, LOCAL_HZ, type Tape } from '../../../src/core/types';

function recordLine(ticks = 10): Tape {
  const rec = new TapeRecorder({ index: 1, speed: 2, endMode: 'repeat', ticks, start: { x: 1, y: 2, facing: 0 } });
  for (let i = 1; i <= ticks; i++) {
    rec.push(1 + i * 0.1, 2 - i * 0.05, i * 0.3, i % 2 ? 'run' : 'idle');
    if (i === 3) rec.addEvent({ tick: 3, kind: 'light', dir: 0.5, x: 1.3, y: 1.85, vx: 6, vy: -3 });
  }
  rec.addEvent({ tick: ticks, kind: 'interact', dir: -1, x: 2, y: 1.5, vx: 0, vy: 0 });
  return rec.finish();
}

describe('angles', () => {
  it('wraps and interpolates along the shortest arc', () => {
    expect(wrapAngle(3 * Math.PI)).toBeCloseTo(Math.PI, 12);
    expect(wrapAngle(-Math.PI)).toBeCloseTo(Math.PI, 12);
    expect(angleDelta(3, -3)).toBeCloseTo(2 * Math.PI - 6, 12);
    expect(lerpAngle(3, -3, 0.5)).toBeCloseTo(Math.PI, 9);
    expect(lerpAngle(0.1, 0.5, 0.5)).toBeCloseTo(0.3, 12);
  });
});

describe('TapeRecorder', () => {
  it('records ticks + 1 samples with the start pose at sample 0', () => {
    const t = recordLine();
    expect(t.ticks).toBe(10);
    expect(t.pos.length).toBe(22);
    expect(t.facing.length).toBe(11);
    expect(t.anim.length).toBe(11);
    expect([t.pos[0], t.pos[1]]).toEqual([1, 2]);
    expect(t.pos[20]).toBe(Math.fround(2));
    expect(animFromIndex(t.anim[1])).toBe('run');
    expect(t.events.map((e) => e.kind)).toEqual(['light', 'interact']);
  });

  it('rejects overfull tapes and out-of-order or future events', () => {
    const rec = new TapeRecorder({ index: 0, speed: 1, endMode: 'stop', ticks: 2, start: { x: 0, y: 0, facing: 0 } });
    expect(() => rec.addEvent({ tick: 1, kind: 'light', dir: 0, x: 0, y: 0, vx: 0, vy: 0 })).toThrow();
    rec.push(0, 0, 0, 'idle');
    rec.addEvent({ tick: 1, kind: 'light', dir: 0, x: 0, y: 0, vx: 0, vy: 0 });
    expect(() => rec.addEvent({ tick: 0, kind: 'light', dir: 0, x: 0, y: 0, vx: 0, vy: 0 })).toThrow();
    rec.push(0, 0, 0, 'idle');
    expect(rec.complete).toBe(true);
    expect(() => rec.push(0, 0, 0, 'idle')).toThrow();
  });

  it('snapshot is a prefix; finish holds the last pose for unrecorded ticks', () => {
    const rec = new TapeRecorder({ index: 0, speed: 1, endMode: 'stop', ticks: 5, start: { x: 0, y: 0, facing: 0 } });
    rec.push(1, 1, 0.5, 'run');
    rec.push(2, 1, 0.5, 'run');
    const snap = rec.snapshot();
    expect(snap.ticks).toBe(2);
    expect(snap.pos.length).toBe(6);
    rec.push(3, 1, 0.5, 'run');
    expect(snap.pos.length).toBe(6); // a copy, unaffected
    const t = rec.finish();
    expect(t.ticks).toBe(5);
    expect(samplePose(t, 5)).toEqual({ x: 3, y: 1, facing: 0.5, anim: 'run' });
  });
});

describe('sampling', () => {
  it('interpolates position linearly and facing by shortest arc; anim is the floor sample', () => {
    const t = recordLine();
    const p = samplePose(t, 2.5);
    expect(p.x).toBeCloseTo((t.pos[4] + t.pos[6]) / 2, 6);
    expect(p.y).toBeCloseTo((t.pos[5] + t.pos[7]) / 2, 6);
    expect(p.facing).toBeCloseTo((t.facing[2] + t.facing[3]) / 2, 6);
    expect(p.anim).toBe('idle');
    expect(samplePose(t, 3).anim).toBe('run');
    expect(samplePose(t, -4)).toEqual(samplePose(t, 0));
    expect(samplePose(t, 99)).toEqual(samplePose(t, 10));
    const out = { x: 0, y: 0 };
    samplePosInto(t, 2.5, out);
    expect(out.x).toBe(p.x);
    expect(out.y).toBe(p.y);
  });

  it('samples by master substep with end behaviour applied', () => {
    const t = recordLine(); // speed 2 → 2 subs per tick, repeat
    expect(samplePoseAtSub(t, 5)).toEqual(samplePose(t, 2.5));
    const phase = { tick: 0, dir: 1 as const, traversal: 0, ended: false };
    const p = samplePoseAtSub(t, 2 * 10 + 6, undefined, phase);
    expect(phase).toEqual({ tick: 3, dir: 1, traversal: 1, ended: false });
    expect(p).toEqual(samplePose(t, 3));
  });

  it('interpolates facing across the ±π seam', () => {
    const rec = new TapeRecorder({ index: 0, speed: 1, endMode: 'stop', ticks: 1, start: { x: 0, y: 0, facing: 3 } });
    rec.push(0, 0, -3, 'idle');
    const f = samplePose(rec.finish(), 0.5).facing;
    expect(Math.abs(Math.abs(f) - Math.PI)).toBeLessThan(1e-6);
  });

  it('estimates local and master velocity', () => {
    const t = recordLine();
    const v = localVelocityAt(t, 4.2);
    expect(v.x).toBeCloseTo((t.pos[10] - t.pos[8]) * LOCAL_HZ, 6);
    expect(v.x).toBeCloseTo(6, 4);
    expect(v.y).toBeCloseTo(-3, 4);
    // Last segment at the end tick.
    expect(localVelocityAt(t, 10).x).toBeCloseTo(6, 4);
    // speed 2: master velocity doubles; reversing flips it; stopped is zero.
    expect(masterVelocityAt(t, 4.2, 1).x).toBeCloseTo(12, 4);
    expect(masterVelocityAt(t, 4.2, -1).y).toBeCloseTo(6, 4);
    expect(masterVelocityAt(t, 4.2, 0)).toEqual({ x: 0, y: 0 });
  });
});

describe('copy and serialisation', () => {
  it('cloneTape is deep', () => {
    const t = recordLine();
    const c = cloneTape(t);
    expect(tapesEqual(t, c)).toBe(true);
    c.pos[3] = 99;
    c.events[0].dir = 7;
    expect(t.pos[3]).not.toBe(99);
    expect(t.events[0].dir).toBe(0.5);
    expect(withEndMode(t, 'reverse').endMode).toBe('reverse');
    expect(t.endMode).toBe('repeat');
  });

  it('round-trips through JSON bit-exactly', () => {
    const t = recordLine(37);
    t.events.push({ tick: 37, kind: 'ability', dir: Math.PI / 3, x: 1 / 3, y: -0, vx: 1e-300, vy: -2.5 });
    const json = JSON.stringify(serializeTape(t));
    const back = deserializeTape(JSON.parse(json));
    expect(tapesEqual(t, back)).toBe(true);
    expect(back.pos).toBeInstanceOf(Float32Array);
    expect(back.anim).toBeInstanceOf(Uint8Array);
  });

  it('rejects malformed data', () => {
    const s = serializeTape(recordLine());
    expect(() => deserializeTape({ ...s, ticks: 11 })).toThrow();
    expect(() => deserializeTape({ ...s, v: 2 as 1 })).toThrow();
    expect(() => deserializeTape({ ...s, events: [[0, 99, 0, 0, 0, 0, 0]] })).toThrow();
    expect(() => deserializeTape({ ...s, pos: '!!!!' })).toThrow();
  });

  it('base64 matches the standard alphabet for all padding cases', () => {
    const enc = (s: string): string => base64FromBytes(new TextEncoder().encode(s));
    expect(enc('')).toBe('');
    expect(enc('f')).toBe('Zg==');
    expect(enc('fo')).toBe('Zm8=');
    expect(enc('foo')).toBe('Zm9v');
    expect(enc('foobar')).toBe('Zm9vYmFy');
    const bytes = new Uint8Array(256).map((_, i) => i);
    expect(bytesFromBase64(base64FromBytes(bytes))).toEqual(bytes);
  });

  it('anim indices map both ways', () => {
    ANIM_STATES.forEach((a, i) => {
      expect(animIndex(a)).toBe(i);
      expect(animFromIndex(i)).toBe(a);
    });
    expect(animFromIndex(200)).toBe('idle');
  });
});
