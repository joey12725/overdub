/**
 * Menu shell: owns the menu screens' DOM, routes keyboard/gamepad navigation and pointer input
 * through one MenuHost per screen, and turns choices into UiIntents. Holds no game state.
 */
import type {
  CampaignScreenModel,
  LoadoutScreenModel,
  ResultsModel,
  Screen,
  UiIntent,
} from '../../contracts';
import type { SessionPhase } from '../../core/types';
import { h } from './dom';
import {
  CampaignLogic,
  EndingLogic,
  LoadoutLogic,
  PauseLogic,
  ResultsLogic,
  SettingsLogic,
  TitleLogic,
  type Emit,
  type SettingKey,
  type Settings,
} from './logic';
import { MenuHost, type MenuSource, type NavCommand } from './nav';
import {
  campaignView,
  endingView,
  loadoutScreenView,
  pauseView,
  resultsScreenView,
  settingsView,
  titleView,
  type Device,
  type ScreenView,
} from './views';

export type MenuScreen = Exclude<Screen, 'play'>;

/** Where "back" from a shared screen (loadout, settings) returns, based on where it was opened. */
export function returnIntent(origin: Screen | null): UiIntent {
  return origin === 'title' || origin === null ? { type: 'openTitle' } : { type: 'openCampaign' };
}

export class Menus {
  readonly el: HTMLElement;

  private readonly title: TitleLogic;
  private readonly campaign: CampaignLogic;
  private readonly loadout: LoadoutLogic;
  private readonly settings: SettingsLogic;
  private readonly pause: PauseLogic;
  private readonly results: ResultsLogic;
  private readonly ending: EndingLogic;
  private readonly views: Record<MenuScreen, ScreenView>;

  private screen: Screen | null = null;
  /** Last screen that was not loadout/settings: where those two return to. */
  private origin: Screen | null = null;
  private host: MenuHost | null = null;
  private built: { screen: MenuScreen; key: string; node: HTMLElement } | null = null;
  private lastFocus: string | null = null;
  private device: Device = 'keyboard';
  private campaignModel: CampaignScreenModel | null = null;
  private campaignVersion = 0;
  private loadoutVersion = 0;
  private resultsVersion = 0;
  private playCtx: { levelName: string | null; phase: SessionPhase | null } = { levelName: null, phase: null };
  /** Phase at the moment pause opened; the note about losing the take is about that moment. */
  private pausedPhase: SessionPhase | null = null;
  private readonly listeners: [string, EventListener][] = [];

  constructor(private readonly emit: Emit) {
    this.el = h('div.od-menus');
    const leave = (): void => this.emit(returnIntent(this.origin));
    this.title = new TitleLogic(emit, () => (this.campaignModel?.levels ?? []).some((l) => l.cleared));
    this.campaign = new CampaignLogic(emit);
    this.loadout = new LoadoutLogic(emit, leave);
    this.settings = new SettingsLogic(emit, leave);
    this.pause = new PauseLogic(emit);
    this.results = new ResultsLogic(emit);
    this.ending = new EndingLogic(emit);
    const dev = (): Device => this.device;
    this.views = {
      title: titleView(this.title, () => this.campaignModel, dev),
      campaign: campaignView(this.campaign, () => this.campaignVersion, dev),
      loadout: loadoutScreenView(this.loadout, () => this.loadoutVersion, dev),
      settings: settingsView(this.settings, dev),
      pause: pauseView(
        this.pause,
        () => ({
          levelName: this.playCtx.levelName,
          midTake: this.pausedPhase === 'recording' || this.pausedPhase === 'countin',
        }),
        dev,
      ),
      results: resultsScreenView(this.results, () => this.resultsVersion, dev),
      ending: endingView(
        this.ending,
        () => {
          const levels = this.campaignModel?.levels ?? [];
          return {
            cleared: levels.filter((l) => l.cleared).length,
            total: levels.length,
            gear: this.loadout.model ? this.loadout.model.inventory.length : null,
          };
        },
        dev,
      ),
    };
    this.bindPointer();
  }

  get current(): Screen | null {
    return this.screen;
  }

  get focus(): string | null {
    return this.host?.focus ?? null;
  }

  show(screen: Screen): void {
    const prev = this.screen;
    this.screen = screen;
    if (screen !== 'loadout' && screen !== 'settings' && screen !== 'pause') this.origin = screen;
    if (screen === 'pause' && prev !== 'pause') this.pausedPhase = this.playCtx.phase;
    if (screen === 'play') {
      this.host = null;
      this.built?.node.remove();
      this.built = null;
      this.el.hidden = true;
      return;
    }
    this.el.hidden = false;
    if (prev !== screen) {
      if (screen === 'campaign') this.campaign.onShow();
      if (screen === 'loadout') this.loadout.onShow();
      if (screen === 'settings') this.settings.onShow();
      if (screen === 'pause') this.pause.onShow();
      this.lastFocus = null;
      this.host = null;
      // The host calls back during its own constructor (initial refresh); ignore that call and
      // any from a host that has since been replaced by another screen.
      let host: MenuHost | null = null;
      host = new MenuHost(this.source(screen), () => {
        if (host !== null && this.host === host) this.sync();
      });
      this.host = host;
    }
    this.sync(prev !== screen);
  }

  navigate(cmd: NavCommand): void {
    if (!this.host) return;
    this.host.navigate(cmd);
  }

  setCampaign(model: CampaignScreenModel): void {
    this.campaignModel = model;
    this.campaign.setModel(model);
    this.campaignVersion++;
    this.refreshIf('campaign', 'title', 'ending');
  }

  setLoadout(model: LoadoutScreenModel): void {
    this.loadout.setModel(model);
    this.loadoutVersion++;
    this.refreshIf('loadout', 'ending');
  }

  setResults(model: ResultsModel): void {
    this.results.setModel(model);
    this.resultsVersion++;
    this.refreshIf('results');
  }

  setSettings(s: Settings): void {
    this.settings.setModel(s);
    this.pause.settings.setModel(s);
    this.el.classList.toggle('od-patterns', s.patterns);
    this.refreshIf('settings', 'pause');
  }

  setDevice(d: Device): void {
    if (d === this.device) return;
    this.device = d;
    this.sync();
  }

  /** Context from the HUD feed, used by the pause overlay. */
  setPlayContext(levelName: string, phase: SessionPhase): void {
    this.playCtx = { levelName, phase };
  }

  dispose(): void {
    for (const [type, fn] of this.listeners) this.el.removeEventListener(type, fn);
    this.listeners.length = 0;
    this.host = null;
    this.el.remove();
  }

  // ───────────────────────────── internals ─────────────────────────────

  private source(screen: MenuScreen): MenuSource {
    switch (screen) {
      case 'title':
        return this.title;
      case 'campaign':
        return this.campaign;
      case 'loadout':
        return this.loadout;
      case 'settings':
        return this.settings;
      case 'pause':
        return this.pause;
      case 'results':
        return this.results;
      case 'ending':
        return this.ending;
    }
  }

  private refreshIf(...screens: Screen[]): void {
    if (this.screen && screens.includes(this.screen) && this.host) this.host.refresh();
  }

  /** Rebuild the screen if its structure changed, then re-apply focus and in-place patches. */
  private sync(entering = false): void {
    const screen = this.screen;
    if (!screen || screen === 'play' || !this.host) return;
    const view = this.views[screen];
    const key = view.key();
    if (!this.built || this.built.screen !== screen || this.built.key !== key) {
      const scroll = new Map<string, number>();
      this.built?.node.querySelectorAll<HTMLElement>('[data-scroll]').forEach((el) => scroll.set(el.dataset.scroll!, el.scrollTop));
      const node = view.build();
      if (entering) node.classList.add('od-enter');
      if (this.built) this.built.node.replaceWith(node);
      else this.el.append(node);
      node.querySelectorAll<HTMLElement>('[data-scroll]').forEach((el) => {
        const t = scroll.get(el.dataset.scroll!);
        if (t !== undefined) el.scrollTop = t;
      });
      this.built = { screen, key, node };
      this.lastFocus = null;
    }
    const node = this.built.node;
    const focus = this.host.focus;
    node.querySelectorAll('.is-focus').forEach((el) => el.classList.remove('is-focus'));
    let first: HTMLElement | null = null;
    if (focus !== null) {
      for (const el of Array.from(node.querySelectorAll<HTMLElement>('[data-nav]'))) {
        if (el.dataset.nav !== focus) continue;
        el.classList.add('is-focus');
        if (!first) first = el;
      }
    }
    view.sync?.(node, focus);
    if (first !== null && focus !== this.lastFocus && !this.pointerDriven) {
      // Long scrolling lists (the descent) keep the cursor centred so what comes next is visible.
      const centre = first.closest('[data-scroll-center]') !== null;
      first.scrollIntoView?.({ block: centre ? 'center' : 'nearest', inline: 'nearest' });
    }
    this.lastFocus = focus;
  }

  /** True while handling a pointer event: the pointer already shows where it is, so never auto-scroll. */
  private pointerDriven = false;

  private bindPointer(): void {
    const on = (type: string, fn: (e: Event) => void): void => {
      this.el.addEventListener(type, fn);
      this.listeners.push([type, fn]);
    };
    const navOf = (t: EventTarget | null): string | null => {
      const el = (t as Element | null)?.closest?.('[data-nav]') as HTMLElement | null;
      return el && this.built?.node.contains(el) ? el.dataset.nav ?? null : null;
    };
    const withPointer = (fn: () => void): void => {
      this.pointerDriven = true;
      try {
        fn();
      } finally {
        this.pointerDriven = false;
      }
    };
    on('pointerover', (e) => {
      const id = navOf(e.target);
      if (id && this.host) withPointer(() => this.host!.hover(id));
    });
    // Keep DOM focus off menu buttons: Enter/Space on a DOM-focused button would fire a click on top
    // of the game's own 'accept' and double-activate. Visible focus is our .is-focus class instead.
    on('mousedown', (e) => {
      const t = e.target as Element;
      if (!t.closest('input')) e.preventDefault();
    });
    on('click', (e) => {
      if (!this.host) return;
      const t = e.target as Element;
      if (t.closest('input')) return;
      const id = navOf(t);
      if (!id) return;
      const adj = t.closest('[data-adjust]') as HTMLElement | null;
      withPointer(() => {
        if (adj) this.host!.adjust(id, Number(adj.dataset.adjust) < 0 ? -1 : 1);
        else this.host!.click(id);
      });
    });
    on('input', (e) => {
      const input = e.target as HTMLInputElement;
      const key = input.dataset.setting as SettingKey | undefined;
      if (!key) return;
      const logic = this.screen === 'pause' ? this.pause.settings : this.settings;
      logic.setValue(key, Number(input.value));
      withPointer(() => this.sync());
    });
    on('change', (e) => {
      // Release DOM focus after a drag so arrow keys go back to menu navigation.
      (e.target as HTMLElement).blur?.();
    });
  }
}
