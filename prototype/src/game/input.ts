/**
 * Keyboard + mouse + gamepad → PlayerInput (one per local tick) and session / menu actions
 * (IInput in src/contracts.ts). Bindings live in one table (BINDINGS) so HUD prompts can be
 * generated from it via describeBinding(). Final bindings are an open decision (OPEN-20); these are
 * conventional twin-stick / WASD + mouse defaults.
 *
 * Edge semantics: a button press is reported exactly once, on the next sample (gameplay) or drain
 * (actions) after it went down, even if it was released again before that. Key auto-repeat never
 * re-triggers. Losing focus releases everything, so a key held while alt-tabbing never sticks.
 */
import type { IInput } from '../contracts';
import type { PlayerInput, SessionAction } from '../core/types';

export type Device = 'keyboard' | 'gamepad';
export type MenuNav = 'up' | 'down' | 'left' | 'right' | 'accept' | 'back';
export type InputAction = SessionAction | 'pause' | MenuNav;
export type GameplayButton = 'light' | 'heavy' | 'dodge' | 'ranged' | 'interact' | 'ability';

/** Everything that can be bound: gameplay buttons, movement / aim, and queued actions. */
export type BindingId = GameplayButton | 'move' | 'aim' | InputAction;

export interface Binding {
  id: BindingId;
  /** KeyboardEvent.code values. */
  keys: readonly string[];
  /** MouseEvent.button values. */
  mouse?: readonly number[];
  /** Standard-mapping gamepad button indices. */
  pad?: readonly number[];
  /** Fires only after being held this long (seconds) — destructive actions (hold-to-confirm). */
  holdSeconds?: number;
  /** Prompt text when the binding is not a plain key / button (sticks, mouse). */
  label?: Partial<Record<Device, string>>;
}

/** Hold time before resetAll fires: it wipes every cassette (REC-05), so it must be deliberate. */
export const RESET_HOLD_SECONDS = 0.9;
/** With no mouse movement for this long, aim follows the movement direction instead. */
export const MOUSE_AIM_TIMEOUT = 1.5;
const STICK_DEADZONE = 0.22;
const AIM_STICK_THRESHOLD = 0.35;
const NAV_STICK_THRESHOLD = 0.6;

// Standard gamepad mapping: 0 A, 1 B, 2 X, 3 Y, 4 LB, 5 RB, 6 LT, 7 RT, 8 Back, 9 Start,
// 12 up, 13 down, 14 left, 15 right.
export const BINDINGS: readonly Binding[] = [
  // ── gameplay (sampled each local tick) ──
  { id: 'move', keys: ['KeyW', 'KeyA', 'KeyS', 'KeyD', 'ArrowUp', 'ArrowLeft', 'ArrowDown', 'ArrowRight'], label: { keyboard: 'WASD', gamepad: 'Left stick' } },
  { id: 'aim', keys: [], label: { keyboard: 'Mouse', gamepad: 'Right stick' } },
  { id: 'light', keys: [], mouse: [0], pad: [2, 7], label: { keyboard: 'Left click' } },
  { id: 'heavy', keys: [], mouse: [2], pad: [3, 6], label: { keyboard: 'Right click' } },
  { id: 'dodge', keys: ['Space'], pad: [0] },
  { id: 'interact', keys: ['KeyE'], pad: [1] },
  { id: 'ranged', keys: ['KeyQ', 'KeyF'], pad: [5] },
  { id: 'ability', keys: ['ShiftLeft', 'ShiftRight'], pad: [4] },
  // ── menu navigation ──
  { id: 'up', keys: ['ArrowUp', 'KeyW'], pad: [12] },
  { id: 'down', keys: ['ArrowDown', 'KeyS'], pad: [13] },
  { id: 'left', keys: ['ArrowLeft', 'KeyA'], pad: [14] },
  { id: 'right', keys: ['ArrowRight', 'KeyD'], pad: [15] },
  { id: 'accept', keys: ['Enter', 'NumpadEnter', 'Space'], pad: [0] },
  // Esc is bound to 'pause' only; the app reads 'pause' as "back" on menu screens, so one key press
  // never produces both a back and a pause in the same batch.
  { id: 'back', keys: [], pad: [1], label: { keyboard: 'Esc' } },
  { id: 'pause', keys: ['Escape', 'KeyP'], pad: [9] },
  // ── session ──
  { id: 'speedDown', keys: ['KeyQ'], pad: [4] },
  { id: 'speedUp', keys: ['KeyE'], pad: [5] },
  { id: 'cycleEndMode', keys: ['Tab'], pad: [3] },
  { id: 'retryTake', keys: ['KeyR'], pad: [2] },
  { id: 'commit', keys: ['KeyC'] },
  { id: 'endAttempt', keys: ['Backspace', 'Delete'], pad: [1] },
  { id: 'resetAll', keys: ['Backspace', 'Delete'], pad: [8, 3], holdSeconds: RESET_HOLD_SECONDS },
];

/** Session actions that are triggered by the context-sensitive 'accept' binding. */
const ACCEPT_ALIASES: readonly SessionAction[] = ['start', 'record', 'skip', 'continue', 'commit'];

const GAMEPLAY: readonly GameplayButton[] = ['light', 'heavy', 'dodge', 'ranged', 'interact', 'ability'];
const MOVE_KEYS: Record<string, [number, number]> = {
  KeyW: [0, 1],
  ArrowUp: [0, 1],
  KeyS: [0, -1],
  ArrowDown: [0, -1],
  KeyA: [-1, 0],
  ArrowLeft: [-1, 0],
  KeyD: [1, 0],
  ArrowRight: [1, 0],
};

const KEY_NAMES: Record<string, string> = {
  Space: 'Space',
  Enter: 'Enter',
  NumpadEnter: 'Enter',
  Escape: 'Esc',
  Tab: 'Tab',
  Backspace: 'Backspace',
  Delete: 'Del',
  ShiftLeft: 'Shift',
  ShiftRight: 'Shift',
  ArrowUp: '↑',
  ArrowDown: '↓',
  ArrowLeft: '←',
  ArrowRight: '→',
};
const PAD_NAMES = ['A', 'B', 'X', 'Y', 'LB', 'RB', 'LT', 'RT', 'Back', 'Start', 'LS', 'RS', 'D-pad ↑', 'D-pad ↓', 'D-pad ←', 'D-pad →'];

function keyName(code: string): string {
  if (KEY_NAMES[code]) return KEY_NAMES[code];
  if (code.startsWith('Key')) return code.slice(3);
  if (code.startsWith('Digit')) return code.slice(5);
  return code;
}

/**
 * Prompt text for an action on a device ("Space", "Hold Backspace", "RB", "Left click").
 * Accept-driven session actions (record, skip, …) describe the accept binding unless they have
 * their own. Returns '' for an action with no binding on that device.
 */
export function describeBinding(action: BindingId, device: Device): string {
  let b = BINDINGS.find((x) => x.id === action);
  const own = b && (device === 'keyboard' ? b.keys.length > 0 || (b.mouse?.length ?? 0) > 0 : (b.pad?.length ?? 0) > 0);
  if ((!b || !own) && ACCEPT_ALIASES.includes(action as SessionAction)) b = BINDINGS.find((x) => x.id === 'accept');
  if (!b) return '';
  const hold = b.holdSeconds ? 'Hold ' : '';
  if (b.label?.[device]) return hold + b.label[device]!;
  if (device === 'keyboard') {
    if (b.keys.length > 0) return hold + keyName(b.keys[0]);
    return '';
  }
  if (b.pad && b.pad.length > 0) return hold + (PAD_NAMES[b.pad[0]] ?? `Button ${b.pad[0]}`);
  return '';
}

/** The parts of a gamepad this module reads (lets tests pass plain objects). */
export interface PadLike {
  connected: boolean;
  buttons: readonly { pressed: boolean; value: number }[];
  axes: readonly number[];
}

export interface InputOptions {
  /** Where keyboard / blur listeners go. Defaults to globalThis (the window). */
  host?: EventTarget;
  /** Pointer position → floor point; normally IRenderer.screenToWorld. */
  screenToWorld?: (px: number, py: number) => { x: number; y: number };
  /** Wall clock in seconds. */
  now?: () => number;
  getGamepads?: () => readonly (PadLike | null)[];
}

export interface GameInput extends IInput {
  /** Forget presses that happened before now (call when a take starts, so the record press is not a dodge). */
  clearPresses(): void;
  /** 0..1 progress of a hold-to-confirm (reset all) currently being held; 0 when none. */
  holdProgress(): number;
  /** Swap the pointer projection (the renderer may be created after the input). */
  setScreenToWorld(fn: (px: number, py: number) => { x: number; y: number }): void;
}

interface HoldState {
  binding: Binding;
  since: number;
  fired: boolean;
  source: string;
}

function defaultNow(): number {
  return (typeof performance !== 'undefined' ? performance.now() : Date.now()) / 1000;
}

function defaultPads(): readonly (PadLike | null)[] {
  const nav = (globalThis as { navigator?: { getGamepads?: () => (PadLike | null)[] } }).navigator;
  try {
    return nav?.getGamepads ? Array.from(nav.getGamepads()) : [];
  } catch {
    return [];
  }
}

function isTyping(t: EventTarget | null): boolean {
  const el = t as { tagName?: string; isContentEditable?: boolean } | null;
  if (!el || typeof el.tagName !== 'string') return false;
  const tag = el.tagName.toUpperCase();
  return tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || el.isContentEditable === true;
}

/** Pointer events that land on UI controls are the UI's, not attacks. */
function isUiControl(t: EventTarget | null): boolean {
  const el = t as { closest?: (s: string) => unknown } | null;
  if (!el || typeof el.closest !== 'function') return false;
  return el.closest('button, input, select, textarea, a, [data-nav], [data-ui-control]') !== null;
}

function deadzone(x: number, y: number, dz: number): [number, number] {
  const m = Math.hypot(x, y);
  if (m < dz) return [0, 0];
  const k = Math.min(1, (m - dz) / (1 - dz)) / m;
  return [x * k, y * k];
}

export function createInput(target: EventTarget, options: InputOptions = {}): GameInput {
  // Outside a browser (headless tools) there is no window to listen on; keyboard input is simply absent.
  const g = globalThis as unknown as Partial<EventTarget>;
  const host: EventTarget = options.host ?? (typeof g.addEventListener === 'function' ? (globalThis as unknown as EventTarget) : new EventTarget());
  const now = options.now ?? defaultNow;
  const getPads = options.getGamepads ?? defaultPads;
  let screenToWorld = options.screenToWorld ?? null;

  const keysDown = new Set<string>();
  const mouseDown = new Set<number>();
  const latched = new Set<GameplayButton>();
  const queue: InputAction[] = [];
  const holds = new Map<string, HoldState>();
  let device: Device = 'keyboard';
  let lastAim = 0;
  let mouse: { cx: number; cy: number; t: number } | null = null;
  let padPrev: boolean[] = [];
  let padNavPrev = { x: 0, y: 0 };

  const bindingsForKey = (code: string) => BINDINGS.filter((b) => b.keys.includes(code));

  const press = (b: Binding, source: string): void => {
    if (b.holdSeconds) {
      if (!holds.has(source + b.id)) holds.set(source + b.id, { binding: b, since: now(), fired: false, source });
      return;
    }
    if ((GAMEPLAY as readonly string[]).includes(b.id)) latched.add(b.id as GameplayButton);
    else if (b.id !== 'move' && b.id !== 'aim') queue.push(b.id as InputAction);
  };

  const releaseHolds = (source: string): void => {
    for (const [k, h] of holds) if (h.source === source) holds.delete(k);
  };

  const checkHolds = (): void => {
    const t = now();
    for (const h of holds.values()) {
      if (!h.fired && t - h.since >= (h.binding.holdSeconds ?? 0)) {
        h.fired = true;
        queue.push(h.binding.id as InputAction);
      }
    }
  };

  const onKeyDown = (ev: Event): void => {
    const e = ev as KeyboardEvent;
    if (isTyping(e.target)) return;
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    const list = bindingsForKey(e.code);
    if (list.length === 0) return;
    e.preventDefault?.();
    device = 'keyboard';
    if (e.repeat || keysDown.has(e.code)) return;
    keysDown.add(e.code);
    for (const b of list) press(b, 'key:' + e.code);
  };

  const onKeyUp = (ev: Event): void => {
    const e = ev as KeyboardEvent;
    keysDown.delete(e.code);
    releaseHolds('key:' + e.code);
  };

  const onMouseDown = (ev: Event): void => {
    const e = ev as MouseEvent;
    if (isUiControl(e.target)) return;
    device = 'keyboard';
    if (mouseDown.has(e.button)) return;
    mouseDown.add(e.button);
    for (const b of BINDINGS) if (b.mouse?.includes(e.button)) press(b, 'mouse:' + e.button);
  };

  const onMouseUp = (ev: Event): void => {
    mouseDown.delete((ev as MouseEvent).button);
  };

  const onMouseMove = (ev: Event): void => {
    const e = ev as MouseEvent;
    mouse = { cx: e.clientX, cy: e.clientY, t: now() };
    device = 'keyboard';
  };

  const onContextMenu = (ev: Event): void => {
    if (!isUiControl(ev.target)) ev.preventDefault?.();
  };

  const releaseAll = (): void => {
    keysDown.clear();
    mouseDown.clear();
    holds.clear();
    latched.clear();
    // Buttons still physically held on a pad must not read as fresh presses on return.
    padPrev = padPrev.map(() => true);
  };

  const onVisibility = (): void => {
    const doc = (globalThis as { document?: { visibilityState?: string } }).document;
    if (doc?.visibilityState === 'hidden') releaseAll();
  };

  host.addEventListener('keydown', onKeyDown);
  host.addEventListener('keyup', onKeyUp);
  host.addEventListener('blur', releaseAll);
  host.addEventListener('mousemove', onMouseMove);
  host.addEventListener('mouseup', onMouseUp);
  host.addEventListener('visibilitychange', onVisibility);
  target.addEventListener('mousedown', onMouseDown);
  target.addEventListener('contextmenu', onContextMenu);

  const pad = (): PadLike | null => {
    for (const p of getPads()) if (p && p.connected) return p;
    return null;
  };

  /** Read the pad once: edges become latches / queued actions; returns stick state. */
  const pollPad = (): { lx: number; ly: number; rx: number; ry: number } | null => {
    const p = pad();
    if (!p) {
      padPrev = [];
      releaseHolds('pad');
      return null;
    }
    const pressed = p.buttons.map((b) => b.pressed || b.value > 0.5);
    for (let i = 0; i < pressed.length; i++) {
      const was = padPrev[i] ?? false;
      if (pressed[i] && !was) {
        device = 'gamepad';
        for (const b of BINDINGS) if (b.pad?.includes(i)) press(b, 'pad');
      }
    }
    // A hold is cancelled as soon as none of its pad buttons is down.
    for (const [k, h] of holds) {
      if (h.source === 'pad' && !(h.binding.pad ?? []).some((i) => pressed[i])) holds.delete(k);
    }
    padPrev = pressed;
    const [lx, ly] = deadzone(p.axes[0] ?? 0, p.axes[1] ?? 0, STICK_DEADZONE);
    const [rx, ry] = deadzone(p.axes[2] ?? 0, p.axes[3] ?? 0, STICK_DEADZONE);
    if (lx !== 0 || ly !== 0 || rx !== 0 || ry !== 0) {
      device = 'gamepad';
    }
    // Left stick doubles as menu navigation: one step each time it crosses the threshold.
    const nx = Math.abs(lx) >= NAV_STICK_THRESHOLD ? Math.sign(lx) : 0;
    const ny = Math.abs(ly) >= NAV_STICK_THRESHOLD ? Math.sign(ly) : 0;
    if (nx !== 0 && nx !== padNavPrev.x) queue.push(nx > 0 ? 'right' : 'left');
    if (ny !== 0 && ny !== padNavPrev.y) queue.push(ny > 0 ? 'down' : 'up');
    padNavPrev = { x: nx, y: ny };
    return { lx, ly, rx, ry };
  };

  const pointerPx = (): { px: number; py: number } | null => {
    if (!mouse) return null;
    const el = target as { getBoundingClientRect?: () => { left: number; top: number } };
    const r = typeof el.getBoundingClientRect === 'function' ? el.getBoundingClientRect() : { left: 0, top: 0 };
    return { px: mouse.cx - r.left, py: mouse.cy - r.top };
  };

  const input: GameInput = {
    sample(screenUp, actorPos) {
      const sticks = pollPad();
      checkHolds();
      // Screen axes in world space. Screen right is screen up turned a quarter clockwise in sim axes
      // (x right, y down, viewed from above), which holds for any rotation of the iso camera.
      const ul = Math.hypot(screenUp.x, screenUp.y) || 1;
      const ux = screenUp.x / ul;
      const uy = screenUp.y / ul;
      const rx = -uy;
      const ry = ux;
      let sx = 0;
      let sy = 0;
      for (const code of keysDown) {
        const m = MOVE_KEYS[code];
        if (m) {
          sx += m[0];
          sy += m[1];
        }
      }
      sx = Math.sign(sx);
      sy = Math.sign(sy);
      if (sticks && (sticks.lx !== 0 || sticks.ly !== 0)) {
        sx = sticks.lx;
        sy = -sticks.ly;
      }
      let mx = rx * sx + ux * sy;
      let my = ry * sx + uy * sy;
      const ml = Math.hypot(mx, my);
      if (ml > 1) {
        mx /= ml;
        my /= ml;
      }
      const moving = ml > 1e-6;

      let aim = lastAim;
      const t = now();
      if (device === 'gamepad') {
        if (sticks && Math.hypot(sticks.rx, sticks.ry) >= AIM_STICK_THRESHOLD) {
          const ax = rx * sticks.rx + ux * -sticks.ry;
          const ay = ry * sticks.rx + uy * -sticks.ry;
          aim = Math.atan2(ay, ax);
        } else if (moving) {
          aim = Math.atan2(my, mx);
        }
      }
      if (device === 'keyboard') {
        const p = pointerPx();
        const recentMouse = mouse !== null && t - mouse.t <= MOUSE_AIM_TIMEOUT;
        if (recentMouse && p && screenToWorld && actorPos) {
          const w = screenToWorld(p.px, p.py);
          const dx = w.x - actorPos.x;
          const dy = w.y - actorPos.y;
          if (Math.hypot(dx, dy) > 0.05) aim = Math.atan2(dy, dx);
        } else if (moving) {
          aim = Math.atan2(my, mx);
        } else if (p && screenToWorld && actorPos) {
          // Standing still with an idle mouse: keep pointing where the cursor rests.
          const w = screenToWorld(p.px, p.py);
          const dx = w.x - actorPos.x;
          const dy = w.y - actorPos.y;
          if (Math.hypot(dx, dy) > 0.05) aim = Math.atan2(dy, dx);
        }
      }
      if (!Number.isFinite(aim)) aim = lastAim;
      lastAim = aim;

      const out: PlayerInput = {
        moveX: mx,
        moveY: my,
        aim,
        light: latched.has('light'),
        heavy: latched.has('heavy'),
        dodge: latched.has('dodge'),
        ranged: latched.has('ranged'),
        interact: latched.has('interact'),
        ability: latched.has('ability'),
      };
      latched.clear();
      return out;
    },
    drainActions() {
      pollPad();
      checkHolds();
      return queue.splice(0, queue.length);
    },
    device() {
      return device;
    },
    clearPresses() {
      latched.clear();
      queue.length = 0;
    },
    holdProgress() {
      const t = now();
      let best = 0;
      for (const h of holds.values()) {
        if (h.fired) continue;
        best = Math.max(best, Math.min(1, (t - h.since) / (h.binding.holdSeconds ?? 1)));
      }
      return best;
    },
    setScreenToWorld(fn) {
      screenToWorld = fn;
    },
    dispose() {
      host.removeEventListener('keydown', onKeyDown);
      host.removeEventListener('keyup', onKeyUp);
      host.removeEventListener('blur', releaseAll);
      host.removeEventListener('mousemove', onMouseMove);
      host.removeEventListener('mouseup', onMouseUp);
      host.removeEventListener('visibilitychange', onVisibility);
      target.removeEventListener('mousedown', onMouseDown);
      target.removeEventListener('contextmenu', onContextMenu);
      releaseAll();
    },
  };
  return input;
}
