/**
 * The application shell driven headlessly with stand-in facades: screens, the fixed-step loop,
 * pause rules, gear lock, results / save, and what reaches the renderer and audio.
 */
import { describe, expect, it } from 'vitest';
import type { IAudio, IRenderer, IUi, MusicPulse, RenderFrame, Screen, UiIntent } from '../../src/contracts';
import { SANDBOX } from '../../src/content/index';
import type { PlayerInput, SessionView } from '../../src/core/types';
import type { BotTake } from '../../src/game/bot';
import { createInput, type GameInput, type InputAction } from '../../src/game/input';
import { memoryStorage, SAVE_KEY } from '../../src/game/save';
import { App } from '../../src/game/shell';
import { planTake } from './plans';

const PULSE: MusicPulse = { beat: 0, beatPulse: 0, barPulse: 0, levels: [0, 0, 0, 0], pitches: [0, 0, 0, 0], chord: 0 };

function fakes() {
  const renders: RenderFrame[] = [];
  const loaded: string[] = [];
  const renderer: IRenderer = {
    canvas: new EventTarget() as unknown as HTMLCanvasElement,
    loadLevel: (level) => void loaded.push(level.id),
    render: (f) => void renders.push(f),
    resize: () => undefined,
    screenUpInWorld: () => ({ x: 0, y: -1 }),
    screenToWorld: (px, py) => ({ x: px, y: py }),
    setQuality: () => undefined,
    dispose: () => undefined,
  };
  const audioLog: { counts: number[]; transports: [number, number, boolean][]; modes: string[]; ui: string[]; events: number } = {
    counts: [],
    transports: [],
    modes: [],
    ui: [],
    events: 0,
  };
  const audio: IAudio = {
    unlock: async () => undefined,
    loadLevel: () => undefined,
    setTransport: (b, r, p) => void audioLog.transports.push([b, r, p]),
    setTracks: () => undefined,
    onEvents: (e) => void (audioLog.events += e.length),
    countIn: (n) => void audioLog.counts.push(n),
    ui: (k) => void audioLog.ui.push(k),
    setMode: (m) => void audioLog.modes.push(m),
    setVolumes: () => undefined,
    pulse: () => PULSE,
    dispose: () => undefined,
  };
  const handlers: ((i: UiIntent) => void)[] = [];
  const uiLog: { screens: Screen[]; toasts: string[]; results: unknown[]; navs: string[]; huds: SessionView[] } = {
    screens: [],
    toasts: [],
    results: [],
    navs: [],
    huds: [],
  };
  const ui: IUi = {
    root: {} as HTMLElement,
    onIntent: (h) => void handlers.push(h),
    showScreen: (s) => void uiLog.screens.push(s),
    updateHud: (v) => void uiLog.huds.push(v),
    setCampaign: () => undefined,
    setLoadout: () => undefined,
    setResults: (m) => void uiLog.results.push(m),
    setSettings: () => undefined,
    toast: (t) => void uiLog.toasts.push(t),
    deckEvent: () => undefined,
    navigate: (d) => void uiLog.navs.push(d),
    dispose: () => undefined,
  };
  const emit = (i: UiIntent) => handlers.forEach((h) => h(i));
  return { renderer, audio, ui, renders, loaded, audioLog, uiLog, emit };
}

/** A GameInput whose ticks come from a bot plan and whose actions are pushed by the test. */
function scriptedInput(getApp: () => App, take: BotTake): GameInput & { push(a: InputAction): void } {
  const queue: InputAction[] = [];
  let tick = 0;
  return {
    push: (a) => void queue.push(a),
    sample(): PlayerInput {
      const s = getApp().session!;
      const snap = s.currentFrame().snap;
      const self = snap.actors.find((a) => a.live)!;
      return take.inputs(tick++, { tick, index: s.activeIndex!, snap, self });
    },
    drainActions: () => queue.splice(0),
    device: () => 'keyboard',
    dispose: () => undefined,
    clearPresses: () => undefined,
    holdProgress: () => 0,
    setScreenToWorld: () => undefined,
  };
}

function key(host: EventTarget, code: string): void {
  host.dispatchEvent(Object.assign(new Event('keydown'), { code, repeat: false }));
  host.dispatchEvent(Object.assign(new Event('keyup'), { code }));
}

describe('app shell', () => {
  it('menus, count-in, pause-aborts-take, gear lock and quitting', () => {
    const f = fakes();
    const host = new EventTarget();
    const input = createInput(f.renderer.canvas, { host });
    const storage = memoryStorage();
    const app = new App(null, { renderer: f.renderer, audio: f.audio, ui: f.ui, input, storage, levels: [SANDBOX], host });
    expect(app.screen).toBe('title');
    expect(f.loaded).toContain('sandbox'); // backdrop
    app.frame(0);
    expect(f.renders.at(-1)!.mode).toBe('idle');

    // Menu keys go to the UI.
    key(host, 'ArrowDown');
    key(host, 'Enter');
    key(host, 'Escape');
    app.frame(16);
    expect(f.uiLog.navs).toEqual(['down', 'accept', 'back']);

    f.emit({ type: 'playLevel', id: 'sandbox' });
    expect(app.screen).toBe('play');
    expect(app.session!.phase).toBe('briefing');
    key(host, 'Enter');
    app.frame(32);
    expect(app.session!.phase).toBe('setup');
    key(host, 'KeyE');
    app.frame(48);
    expect(app.session!.speed).toBe(2);
    key(host, 'ArrowLeft');
    app.frame(64);
    expect(app.session!.speed).toBe(1);

    // GEAR-03: no loadout changes mid-level.
    f.emit({ type: 'openLoadout' });
    expect(app.screen).toBe('play');
    expect(f.uiLog.toasts.at(-1)).toMatch(/locked/);
    f.emit({ type: 'equip', slot: 'melee', id: 'splice_blade' });
    expect(f.uiLog.toasts.at(-1)).toMatch(/cannot be equipped/);

    key(host, 'Space');
    app.frame(80);
    expect(app.session!.phase).toBe('countin');
    app.runFor(2.1);
    expect(f.audioLog.counts).toEqual([5, 6, 7, 8]);
    expect(app.session!.phase).toBe('recording');
    app.runFor(1);
    const ticked = app.session!.liveSim!.localTick;
    expect(ticked).toBeGreaterThan(50);
    expect(ticked).toBeLessThanOrEqual(66);
    const rec = f.renders.at(-1)!;
    expect(rec.mode).toBe('record');
    expect(rec.active).toBe(0);
    expect(rec.worldRate).toBe(1);
    expect(f.audioLog.transports.at(-1)![2]).toBe(true);

    // OPEN-21: pausing mid-take abandons it.
    key(host, 'Escape');
    app.frame(5000);
    expect(app.screen).toBe('pause');
    expect(app.session!.phase).toBe('setup');
    expect(app.session!.liveSim).toBeNull();
    expect(f.audioLog.transports.at(-1)![2]).toBe(false);
    f.emit({ type: 'resume' });
    expect(app.screen).toBe('play');

    f.emit({ type: 'session', action: 'quit' });
    expect(app.screen).toBe('campaign');
    expect(app.session).toBeNull();
    f.emit({ type: 'openLoadout' });
    expect(app.screen).toBe('loadout');
    app.dispose();
  });

  it('a winning take plays the cinematic, records the clear and loot, and ends on the ending screen', () => {
    const f = fakes();
    const storage = memoryStorage();
    let app: App | null = null;
    const take = planTake(
      1,
      'stop',
      [
        { kind: 'goto', x: 3.5, y: 2.3 },
        { kind: 'interact' },
        { kind: 'goto', x: 4.5, y: 3.5 },
        { kind: 'goto', x: 7.0, y: 3.5 },
        { kind: 'goto', x: 11.5, y: 3.4 },
        { kind: 'hold', x: 11.5, y: 3.4 },
      ],
      { dodgeRange: 1.2 },
    );
    const input = scriptedInput(() => app!, take);
    app = new App(null, { renderer: f.renderer, audio: f.audio, ui: f.ui, input, storage, levels: [SANDBOX], host: null });
    f.emit({ type: 'playLevel', id: 'sandbox' });
    input.push('accept'); // briefing → setup
    app.frame(0);
    input.push('accept'); // record
    app.frame(16);
    expect(app.session!.phase).toBe('countin');
    let frames = 0;
    while (app.session!.phase !== 'cinematic' && frames < 5000) {
      app.frame(16 + ++frames * (1000 / 60));
    }
    expect(app.session!.phase).toBe('cinematic');
    // 4-beat count-in (2 s) + 8 bars at 120 bpm (16 s) of wall time, one local tick per 1/60 s.
    expect(frames).toBeGreaterThanOrEqual(18 * 60 - 3);
    expect(frames).toBeLessThanOrEqual(18 * 60 + 3);
    app.frame(16 + ++frames * (1000 / 60));
    expect(f.renders.at(-1)!.mode).toBe('cinematic');
    expect(f.renders.at(-1)!.active).toBeNull();
    // CINE-02: gameplay keys during the cinematic change nothing.
    input.push('retryTake');
    input.push('resetAll');
    app.frame(16 + ++frames * (1000 / 60));
    expect(app.session!.phase).toBe('cinematic');
    while (app.screen !== 'results' && frames < 20000) app.frame(16 + ++frames * (1000 / 60));
    expect(app.screen).toBe('results');
    expect(app.save.cleared).toEqual(['sandbox']);
    for (const id of SANDBOX.loot) expect(app.save.inventory).toContain(id);
    expect(JSON.parse(storage.data.get(SAVE_KEY)!).cleared).toEqual(['sandbox']);
    const results = f.uiLog.results.at(-1) as { hasNext: boolean; tapesUsed: number; outcome: { win: boolean } };
    expect(results).toMatchObject({ hasNext: false, tapesUsed: 1, outcome: { win: true } });
    expect(f.uiLog.toasts.filter((t) => t.startsWith('New gear'))).toHaveLength(SANDBOX.loot.length);
    expect(f.audioLog.events).toBeGreaterThan(0);

    // After the level, gear may change again (GEAR-03) …
    f.emit({ type: 'equip', slot: 'melee', id: 'reel_lash' });
    expect(app.save.loadout.melee).toBe('reel_lash');
    // … and continuing past the final level shows the ending.
    f.emit({ type: 'session', action: 'continue' });
    expect(app.screen).toBe('ending');
    app.dispose();
  });

  it('settings apply live and persist; erasing the save starts fresh', () => {
    const f = fakes();
    const storage = memoryStorage();
    const volumes: number[][] = [];
    f.audio.setVolumes = (...v: number[]) => void volumes.push(v);
    const app = new App(null, { renderer: f.renderer, audio: f.audio, ui: f.ui, storage, levels: [SANDBOX], host: null });
    f.emit({ type: 'setting', key: 'music', value: 0.3 });
    expect(volumes.at(-1)).toEqual([0.8, 0.3, 0.8]);
    expect(JSON.parse(storage.data.get(SAVE_KEY)!).settings.music).toBe(0.3);
    f.emit({ type: 'eraseSave' });
    expect(app.save.settings.music).toBe(0.8);
    expect(app.save.cleared).toEqual([]);
    app.setQuality('low');
    expect(app.renderQuality).toBe('low');
    app.dispose();
  });
});
