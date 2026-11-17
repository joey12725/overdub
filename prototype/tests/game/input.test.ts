/**
 * Input: edge-triggered presses, focus loss, camera-relative movement, aim fallbacks, the
 * hold-to-confirm reset and the binding table / prompt text.
 */
import { describe, expect, it } from 'vitest';
import { BINDINGS, createInput, describeBinding, MOUSE_AIM_TIMEOUT, RESET_HOLD_SECONDS, type PadLike } from '../../src/game/input';

function key(type: 'keydown' | 'keyup', code: string, extra: Record<string, unknown> = {}): Event {
  return Object.assign(new Event(type), { code, repeat: false, ...extra });
}

function mouse(type: string, extra: Record<string, unknown>): Event {
  return Object.assign(new Event(type), extra);
}

function rig(pads: (PadLike | null)[] = []) {
  const host = new EventTarget();
  const target = new EventTarget();
  let t = 0;
  const input = createInput(target, {
    host,
    now: () => t,
    getGamepads: () => pads,
    screenToWorld: (px, py) => ({ x: px / 10, y: py / 10 }),
  });
  return {
    host,
    target,
    input,
    advance(dt: number) {
      t += dt;
    },
    press(code: string) {
      host.dispatchEvent(key('keydown', code));
    },
    release(code: string) {
      host.dispatchEvent(key('keyup', code));
    },
  };
}

const UP = { x: 0, y: -1 };

function pad(buttons: number[] = [], axes: number[] = [0, 0, 0, 0]): PadLike {
  return {
    connected: true,
    buttons: Array.from({ length: 17 }, (_, i) => ({ pressed: buttons.includes(i), value: buttons.includes(i) ? 1 : 0 })),
    axes,
  };
}

describe('input', () => {
  it('reports a press exactly once, even if released before the next sample; auto-repeat is ignored', () => {
    const r = rig();
    r.press('Space');
    r.release('Space');
    expect(r.input.sample(UP, null).dodge).toBe(true);
    expect(r.input.sample(UP, null).dodge).toBe(false);
    r.press('Space');
    r.host.dispatchEvent(key('keydown', 'Space', { repeat: true }));
    r.host.dispatchEvent(key('keydown', 'Space'));
    expect(r.input.sample(UP, null).dodge).toBe(true);
    expect(r.input.sample(UP, null).dodge).toBe(false);
    const acts = r.input.drainActions();
    expect(acts.filter((a) => a === 'accept')).toHaveLength(2);
    expect(r.input.drainActions()).toEqual([]);
  });

  it('mouse buttons are light / heavy; clicks on UI controls are not attacks', () => {
    const r = rig();
    r.target.dispatchEvent(mouse('mousedown', { button: 0 }));
    r.target.dispatchEvent(mouse('mousedown', { button: 2 }));
    let s = r.input.sample(UP, null);
    expect([s.light, s.heavy]).toEqual([true, true]);
    r.host.dispatchEvent(mouse('mouseup', { button: 0 }));
    r.host.dispatchEvent(mouse('mouseup', { button: 2 }));
    const button = Object.assign(new EventTarget(), { closest: () => ({}) });
    button.addEventListener('mousedown', () => undefined);
    const ev = mouse('mousedown', { button: 0 });
    Object.defineProperty(ev, 'target', { value: button });
    r.target.dispatchEvent(ev);
    s = r.input.sample(UP, null);
    expect(s.light).toBe(false);
  });

  it('losing focus releases every key and drops pending presses', () => {
    const r = rig();
    r.press('KeyD');
    r.press('KeyE');
    r.host.dispatchEvent(new Event('blur'));
    const s = r.input.sample(UP, null);
    expect(s.moveX).toBe(0);
    expect(s.interact).toBe(false);
    // The key-up that never arrived does not matter; a fresh press works again.
    r.press('KeyD');
    expect(r.input.sample(UP, null).moveX).toBeCloseTo(1, 9);
  });

  it('movement is camera-relative: W walks toward screen-up in world axes', () => {
    const r = rig();
    r.press('KeyW');
    let s = r.input.sample(UP, null);
    expect([s.moveX, s.moveY].map((v) => Math.round(v * 1e9) / 1e9)).toEqual([0, -1]);
    // An iso camera whose screen-up points to world (-1, -1)/√2: D walks to world (1, -1)/√2.
    const iso = { x: -Math.SQRT1_2, y: -Math.SQRT1_2 };
    r.release('KeyW');
    r.press('KeyD');
    s = r.input.sample(iso, null);
    expect(s.moveX).toBeCloseTo(Math.SQRT1_2, 9);
    expect(s.moveY).toBeCloseTo(-Math.SQRT1_2, 9);
    // Diagonals are clamped to unit length.
    r.press('KeyW');
    s = r.input.sample(UP, null);
    expect(Math.hypot(s.moveX, s.moveY)).toBeCloseTo(1, 9);
  });

  it('aims at the mouse; with no recent mouse movement aim follows movement', () => {
    const r = rig();
    r.host.dispatchEvent(mouse('mousemove', { clientX: 50, clientY: 0 }));
    let s = r.input.sample(UP, { x: 0, y: 0 });
    expect(s.aim).toBeCloseTo(0, 9);
    r.press('KeyS');
    s = r.input.sample(UP, { x: 0, y: 0 });
    expect(s.aim).toBeCloseTo(0, 9); // mouse still recent: aim stays on the cursor
    r.advance(MOUSE_AIM_TIMEOUT + 0.1);
    s = r.input.sample(UP, { x: 0, y: 0 });
    expect(s.aim).toBeCloseTo(Math.PI / 2, 9); // S = screen-down = world +y
  });

  it('Backspace taps end a playback; holding it fires resetAll once (hold-to-confirm)', () => {
    const r = rig();
    r.press('Backspace');
    expect(r.input.drainActions()).toEqual(['endAttempt']);
    r.advance(RESET_HOLD_SECONDS / 2);
    expect(r.input.holdProgress()).toBeCloseTo(0.5, 5);
    expect(r.input.drainActions()).toEqual([]);
    r.advance(RESET_HOLD_SECONDS / 2 + 0.01);
    expect(r.input.drainActions()).toEqual(['resetAll']);
    r.advance(2);
    expect(r.input.drainActions()).toEqual([]);
    r.release('Backspace');
    // Released early: nothing.
    r.press('Delete');
    r.input.drainActions();
    r.advance(RESET_HOLD_SECONDS / 3);
    r.release('Delete');
    r.advance(RESET_HOLD_SECONDS);
    expect(r.input.drainActions()).toEqual([]);
    expect(r.input.holdProgress()).toBe(0);
  });

  it('session keys map to session actions; Esc pauses', () => {
    const r = rig();
    for (const code of ['KeyQ', 'KeyE', 'Tab', 'KeyR', 'KeyC', 'Escape', 'Enter', 'ArrowLeft']) {
      r.press(code);
      r.release(code);
    }
    expect(r.input.drainActions()).toEqual(['speedDown', 'speedUp', 'cycleEndMode', 'retryTake', 'commit', 'pause', 'accept', 'left']);
  });

  it('clearPresses forgets the press that started a take', () => {
    const r = rig();
    r.press('Space');
    r.input.clearPresses();
    expect(r.input.sample(UP, null).dodge).toBe(false);
    expect(r.input.drainActions()).toEqual([]);
  });

  it('ignores keys typed into form fields and browser shortcuts', () => {
    const r = rig();
    const field = Object.assign(new EventTarget(), { tagName: 'INPUT' });
    const ev = key('keydown', 'Space');
    Object.defineProperty(ev, 'target', { value: field });
    r.host.dispatchEvent(ev);
    r.host.dispatchEvent(key('keydown', 'KeyR', { ctrlKey: true }));
    expect(r.input.drainActions()).toEqual([]);
    expect(r.input.sample(UP, null).dodge).toBe(false);
  });

  it('gamepad: edges once per press, left stick moves, right stick aims, falls back to move direction', () => {
    const pads: (PadLike | null)[] = [pad([0])];
    const r = rig(pads);
    let s = r.input.sample(UP, null);
    expect(r.input.device()).toBe('gamepad');
    expect(s.dodge).toBe(true);
    expect(r.input.drainActions()).toEqual(['accept']);
    s = r.input.sample(UP, null);
    expect(s.dodge).toBe(false); // still held: no new edge
    pads[0] = pad([], [1, 0, 0, 0]);
    s = r.input.sample(UP, null);
    expect(s.moveX).toBeCloseTo(1, 6);
    expect(s.aim).toBeCloseTo(0, 6);
    pads[0] = pad([], [0, 0, 0, 1]);
    s = r.input.sample(UP, null);
    expect(s.aim).toBeCloseTo(Math.PI / 2, 6); // right stick down = screen-down = world +y
    pads[0] = pad([7, 6]);
    s = r.input.sample(UP, null);
    expect([s.light, s.heavy]).toEqual([true, true]);
    pads[0] = pad([9]);
    expect(r.input.drainActions()).toContain('pause');
  });

  it('describes bindings for both devices from the one table', () => {
    expect(describeBinding('dodge', 'keyboard')).toBe('Space');
    expect(describeBinding('dodge', 'gamepad')).toBe('A');
    expect(describeBinding('light', 'keyboard')).toBe('Left click');
    expect(describeBinding('ranged', 'gamepad')).toBe('RB');
    expect(describeBinding('resetAll', 'keyboard')).toBe('Hold Backspace');
    expect(describeBinding('record', 'keyboard')).toBe('Enter');
    expect(describeBinding('commit', 'keyboard')).toBe('C');
    expect(describeBinding('commit', 'gamepad')).toBe('A');
    expect(describeBinding('pause', 'keyboard')).toBe('Esc');
    expect(describeBinding('move', 'gamepad')).toBe('Left stick');
    // Every bound id is described on at least one device.
    for (const b of BINDINGS) expect(describeBinding(b.id, 'keyboard') + describeBinding(b.id, 'gamepad')).not.toBe('');
  });

  it('dispose removes listeners', () => {
    const r = rig();
    r.input.dispose();
    r.press('Space');
    expect(r.input.sample(UP, null).dodge).toBe(false);
  });
});
