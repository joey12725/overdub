/**
 * UI facade (IUi): the in-level HUD (src/ui/hud), the menu screens (src/ui/menus) and toasts, mounted
 * in one root above the 3D canvas. The UI never mutates game state; it only emits UiIntents.
 */
import './tokens.css';
import './shell.css';
import type {
  CampaignScreenModel,
  IUi,
  LoadoutScreenModel,
  MusicPulse,
  ResultsModel,
  Screen,
  UiIntent,
} from '../contracts';
import type { ActionKind, SaveData, SessionView, TapeIndex } from '../core/types';
import { HUD_ACTION_EVENT, type HudActionDetail } from './hud/dom';
import { createHud, type Hud } from './hud/index';
import { h } from './menus/dom';
import { Menus } from './menus/menus';

const TOAST_MS = 3200;
const TOAST_MAX = 4;

export function createUi(): IUi {
  const handlers: ((intent: UiIntent) => void)[] = [];
  const emit = (intent: UiIntent): void => {
    for (const fn of handlers) fn(intent);
  };

  const root = h('div.od-ui', { 'data-screen': 'title' });
  const hudLayer = h('div.od-hud-layer');
  const toasts = h('div.od-toasts', { 'aria-live': 'polite', role: 'status' });
  const menus = new Menus(emit);
  const hud: Hud = createHud();
  hudLayer.append(hud.el);
  hudLayer.hidden = true;
  root.append(hudLayer, menus.el, toasts);

  let screen: Screen = 'title';
  const timers = new Set<ReturnType<typeof setTimeout>>();

  // HUD controls (record, commit, retry…) are clickable; the HUD reports them as a bubbling DOM
  // event and they leave the UI as ordinary session intents, same as every other choice.
  const onHudAction = (e: Event): void => {
    const detail = (e as CustomEvent<HudActionDetail>).detail;
    if (detail && typeof detail.action === 'string') emit({ type: 'session', action: detail.action });
  };
  root.addEventListener(HUD_ACTION_EVENT, onHudAction);

  const ui: IUi = {
    root,
    onIntent(handler) {
      handlers.push(handler);
    },
    showScreen(next: Screen) {
      screen = next;
      root.dataset.screen = next;
      // The HUD stays visible (dimmed by the overlay) under pause, so the decks remain readable.
      hudLayer.hidden = !(next === 'play' || next === 'pause');
      menus.show(next);
    },
    updateHud(view: SessionView, pulse: MusicPulse) {
      menus.setPlayContext(view.level.name, view.phase);
      if (screen === 'play' || screen === 'pause') hud.update(view, pulse);
    },
    setCampaign(model: CampaignScreenModel) {
      menus.setCampaign(model);
    },
    setLoadout(model: LoadoutScreenModel) {
      menus.setLoadout(model);
    },
    setResults(model: ResultsModel) {
      menus.setResults(model);
    },
    setSettings(settings: SaveData['settings']) {
      menus.setSettings(settings);
      // Colour-blind cassette patterns apply to the HUD decks too; the class lives on the shared root.
      root.classList.toggle('od-patterns', settings.patterns);
    },
    toast(text: string, tone: 'info' | 'good' | 'warn' = 'info') {
      const el = h(`div.od-toast.od-toast--${tone}`, null, text);
      toasts.append(el);
      while (toasts.childElementCount > TOAST_MAX) toasts.firstElementChild?.remove();
      const t = setTimeout(() => {
        timers.delete(t);
        el.classList.add('od-toast--out');
        const t2 = setTimeout(() => {
          timers.delete(t2);
          el.remove();
        }, 260);
        timers.add(t2);
      }, TOAST_MS);
      timers.add(t);
    },
    deckEvent(tape: TapeIndex, kind: ActionKind | 'death' | 'desync' | 'resync') {
      hud.deckEvent(tape, kind);
    },
    navigate(dir) {
      if (screen === 'play') return;
      menus.navigate(dir);
    },
    setDevice(device) {
      hud.setDevice(device);
      menus.setDevice(device);
    },
    dispose() {
      for (const t of timers) clearTimeout(t);
      timers.clear();
      handlers.length = 0;
      root.removeEventListener(HUD_ACTION_EVENT, onHudAction);
      hud.dispose();
      menus.dispose();
      root.remove();
    },
  };
  menus.show('title');
  return ui;
}
