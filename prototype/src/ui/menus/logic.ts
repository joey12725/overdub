/**
 * DOM-free screen logic. Each class owns only presentation state (which list is open, which confirm
 * is showing, the last settings it was told about) and turns choices into UiIntents. It never
 * mutates game state: the game layer answers intents by calling the IUi set* / show* methods.
 */
import type {
  CampaignScreenModel,
  LoadoutScreenModel,
  ResultsModel,
  UiIntent,
} from '../../contracts';
import { GEAR_SLOTS, type GearItem, type GearSlot, type SaveData } from '../../core/types';
import type { MenuDef, MenuEntry, MenuSource } from './nav';
import { endModeLabel, slotLabel, speedLabel, themeLabel } from './format';

export type Emit = (intent: UiIntent) => void;
export type Settings = SaveData['settings'];

export const DEFAULT_SETTINGS: Settings = {
  master: 0.8,
  music: 0.8,
  sfx: 0.8,
  avOffsetMs: 0,
  screenShake: true,
  patterns: false,
};

export const VOLUME_STEP = 0.05;
export const AV_OFFSET_STEP = 5;
/** Bluetooth headphones commonly add 150–250 ms; leave headroom both ways. */
export const AV_OFFSET_MIN = -300;
export const AV_OFFSET_MAX = 300;

const clamp = (v: number, lo: number, hi: number): number => Math.min(hi, Math.max(lo, v));
/** Volumes are stored on a 0.05 grid so repeated nudges never accumulate float drift. */
const snapVolume = (v: number): number => Math.round(clamp(v, 0, 1) / VOLUME_STEP) * VOLUME_STEP;

// ───────────────────────────── title ─────────────────────────────

export class TitleLogic implements MenuSource {
  /** Showing "New descent erases progress — sure?". */
  confirmingNew = false;
  private focusReq: string | null = null;
  private lastProgress: boolean | null = null;

  constructor(
    private readonly emit: Emit,
    private readonly hasProgress: () => boolean,
  ) {}

  menu(): MenuDef {
    if (this.confirmingNew) {
      return {
        entries: [
          { id: 'new-no', row: 0, col: 0, accept: () => this.cancelNew() },
          {
            id: 'new-yes',
            row: 0,
            col: 1,
            accept: () => {
              this.confirmingNew = false;
              this.emit({ type: 'eraseSave' });
              this.emit({ type: 'openCampaign' });
            },
          },
        ],
        back: () => this.cancelNew(),
        defaultFocus: 'new-no',
      };
    }
    const progress = this.hasProgress();
    const entries: MenuEntry[] = [];
    let row = 0;
    if (progress) entries.push({ id: 'continue', row: row++, col: 0, accept: () => this.emit({ type: 'openCampaign' }) });
    entries.push({
      id: 'new',
      row: row++,
      col: 0,
      accept: () => {
        // A fresh save has nothing to lose, so no confirm step.
        if (this.hasProgress()) this.confirmingNew = true;
        else this.emit({ type: 'openCampaign' });
      },
    });
    entries.push({ id: 'loadout', row: row++, col: 0, accept: () => this.emit({ type: 'openLoadout' }) });
    entries.push({ id: 'settings', row: row++, col: 0, accept: () => this.emit({ type: 'openSettings' }) });
    return { entries, defaultFocus: progress ? 'continue' : 'new' };
  }

  takeFocusRequest(): string | null {
    const r = this.focusReq;
    this.focusReq = null;
    // The save usually arrives after the title is already up; when progress appears (or is
    // erased) the cursor jumps to the sensible default instead of staying on "New descent".
    const p = this.hasProgress();
    if (p !== this.lastProgress && !this.confirmingNew) {
      this.lastProgress = p;
      return r ?? (p ? 'continue' : 'new');
    }
    return r;
  }

  private cancelNew(): void {
    this.confirmingNew = false;
    this.focusReq = 'new';
  }
}

// ───────────────────────────── campaign ─────────────────────────────

export interface CampaignNodeView {
  id: string;
  navId: string;
  index: number;
  /** "01", "02"… depth counter on the descent. */
  depth: string;
  name: string;
  tagline: string;
  theme: CampaignScreenModel['levels'][number]['level']['theme'];
  themeLabel: string;
  maxTapes: number;
  speeds: string[];
  endModes: string[];
  cleared: boolean;
  unlocked: boolean;
  current: boolean;
  /** Last node on the path: the time machine (WORLD-05). */
  final: boolean;
  loot: { count: number; found: boolean; items: { name: string; slot: string; effect: string }[] };
  /** Single-line status for screen readers and the node badge. */
  status: 'cleared' | 'next' | 'open' | 'locked';
}

export function campaignNodes(model: CampaignScreenModel): CampaignNodeView[] {
  const n = model.levels.length;
  return model.levels.map((e, i) => {
    const l = e.level;
    const status: CampaignNodeView['status'] = !e.unlocked
      ? 'locked'
      : e.cleared
        ? 'cleared'
        : i === model.current
          ? 'next'
          : 'open';
    return {
      id: l.id,
      navId: `level:${l.id}`,
      index: i,
      depth: String(i + 1).padStart(2, '0'),
      name: l.name,
      tagline: l.tagline,
      theme: l.theme,
      themeLabel: themeLabel(l.theme),
      maxTapes: l.maxTapes,
      speeds: l.speeds.map(speedLabel),
      endModes: l.endModes.map(endModeLabel),
      cleared: e.cleared,
      unlocked: e.unlocked,
      current: i === model.current,
      final: i === n - 1,
      loot: {
        count: l.loot.length,
        found: e.cleared,
        // Unfound loot stays a mystery: naming it before the clear would spoil the find.
        items: e.cleared && e.loot ? e.loot.map((g) => ({ name: g.name, slot: slotLabel(g.slot).title, effect: g.effect })) : [],
      },
      status,
    };
  });
}

export class CampaignLogic implements MenuSource {
  model: CampaignScreenModel | null = null;
  /** Bumped when the player tries a locked level, so the view can shake it. */
  lockedPokes = 0;
  lastPoked: string | null = null;
  private focusReq: string | null = null;

  constructor(
    private readonly emit: Emit,
    /** Where "back" goes: the title. */
    private readonly onBack: () => void = () => emit({ type: 'openTitle' }),
  ) {}

  setModel(model: CampaignScreenModel): void {
    const first = this.model === null;
    this.model = model;
    const cur = model.levels[model.current];
    // Re-entering the path lands on the next uncleared level (LEVEL-08: the path always moves down).
    if (first && cur) this.focusReq = `level:${cur.level.id}`;
  }

  /** Called when the screen is shown, so returning from a level re-focuses the next one. */
  onShow(): void {
    const cur = this.model?.levels[this.model.current];
    if (cur) this.focusReq = `level:${cur.level.id}`;
  }

  menu(): MenuDef {
    const entries: MenuEntry[] = [
      { id: 'back', row: 0, col: 0, accept: () => this.onBack() },
      { id: 'loadout', row: 0, col: 1, accept: () => this.emit({ type: 'openLoadout' }) },
    ];
    const levels = this.model?.levels ?? [];
    levels.forEach((e, i) => {
      const id = e.level.id;
      entries.push({
        id: `level:${id}`,
        row: i + 1,
        col: 0,
        // Locked levels stay focusable so their name/tagline can be read; accept just refuses
        // (visibly, via the poke counter the view animates).
        links: { right: 'loadout' },
        accept: () => {
          if (e.unlocked) this.emit({ type: 'playLevel', id });
          else this.pokeLocked(`level:${id}`);
        },
      });
    });
    const cur = this.model ? levels[this.model.current] : undefined;
    return { entries, back: () => this.onBack(), defaultFocus: cur ? `level:${cur.level.id}` : 'back' };
  }

  /** Accept pressed on a locked level: purely visual feedback. */
  pokeLocked(navId: string): void {
    this.lockedPokes++;
    this.lastPoked = navId;
  }

  takeFocusRequest(): string | null {
    const r = this.focusReq;
    this.focusReq = null;
    return r;
  }
}

// ───────────────────────────── loadout ─────────────────────────────

export interface SlotView {
  slot: GearSlot;
  navId: string;
  title: string;
  kind: string;
  equipped: GearItem | null;
  owned: number;
  hasFresh: boolean;
}

export interface LoadoutView {
  slots: SlotView[];
  activeSlot: GearSlot;
  /** Every owned item for the active slot, inventory order (GEAR-04: nothing is ever discarded). */
  items: { item: GearItem; navId: string; equipped: boolean; fresh: boolean }[];
  summary: string[];
}

export function itemsForSlot(model: LoadoutScreenModel, slot: GearSlot): GearItem[] {
  return model.inventory.filter((g) => g.slot === slot);
}

export function equippedItem(model: LoadoutScreenModel, slot: GearSlot): GearItem | null {
  const id = model.loadout[slot];
  return model.inventory.find((g) => g.id === id) ?? null;
}

export function loadoutView(model: LoadoutScreenModel, activeSlot: GearSlot): LoadoutView {
  const fresh = new Set(model.fresh);
  return {
    slots: GEAR_SLOTS.map((slot) => {
      const lab = slotLabel(slot);
      const owned = itemsForSlot(model, slot);
      return {
        slot,
        navId: `slot:${slot}`,
        title: lab.title,
        kind: lab.kind,
        equipped: equippedItem(model, slot),
        owned: owned.length,
        hasFresh: owned.some((g) => fresh.has(g.id)),
      };
    }),
    activeSlot,
    items: itemsForSlot(model, activeSlot).map((item) => ({
      item,
      navId: `item:${item.id}`,
      equipped: model.loadout[activeSlot] === item.id,
      fresh: fresh.has(item.id),
    })),
    summary: model.summary,
  };
}

export class LoadoutLogic implements MenuSource {
  model: LoadoutScreenModel | null = null;
  activeSlot: GearSlot = 'helmet';
  /** Focus is inside the item list (vs. the slot column). */
  inList = false;
  private focusReq: string | null = null;

  constructor(
    private readonly emit: Emit,
    private readonly leave: () => void,
  ) {}

  setModel(model: LoadoutScreenModel): void {
    this.model = model;
  }

  onShow(): void {
    this.inList = false;
    this.focusReq = `slot:${this.activeSlot}`;
  }

  /** Open the item list for a slot (accept on a slot tile, or a paper-doll pin click). */
  openSlot(slot: GearSlot): void {
    this.activeSlot = slot;
    if (!this.model) return;
    const items = itemsForSlot(this.model, slot);
    if (items.length === 0) return;
    const eq = this.model.loadout[slot];
    this.inList = true;
    this.focusReq = `item:${items.some((g) => g.id === eq) ? eq : items[0].id}`;
  }

  menu(): MenuDef {
    const entries: MenuEntry[] = [];
    const model = this.model;
    const items = model ? itemsForSlot(model, this.activeSlot) : [];
    const eqId = model?.loadout[this.activeSlot];
    const firstItem = items.some((g) => g.id === eqId) ? `item:${eqId}` : items[0] ? `item:${items[0].id}` : undefined;

    GEAR_SLOTS.forEach((slot, row) => {
      entries.push({
        id: `slot:${slot}`,
        row,
        col: 0,
        links: slot === this.activeSlot && firstItem ? { right: firstItem } : undefined,
        focused: () => {
          // The list always previews the slot under the cursor, so browsing slots shows options.
          this.activeSlot = slot;
          this.inList = false;
        },
        accept: () => this.openSlot(slot),
      });
    });
    entries.push({
      id: 'done',
      row: GEAR_SLOTS.length,
      col: 0,
      focused: () => {
        this.inList = false;
      },
      accept: () => this.leave(),
    });

    items.forEach((item, i) => {
      const id = `item:${item.id}`;
      const links: MenuEntry['links'] = { left: `slot:${this.activeSlot}` };
      // Keep the cursor inside the list at its ends instead of falling into the slot column.
      if (i === 0) links.up = id;
      if (i === items.length - 1) links.down = id;
      entries.push({
        id,
        row: i,
        col: 1,
        links,
        focused: () => {
          this.inList = true;
        },
        accept: () => {
          if (model && model.loadout[this.activeSlot] !== item.id) this.emit({ type: 'equip', slot: this.activeSlot, id: item.id });
        },
      });
    });

    return {
      entries,
      back: () => {
        if (this.inList) {
          this.inList = false;
          this.focusReq = `slot:${this.activeSlot}`;
        } else this.leave();
      },
      defaultFocus: `slot:${this.activeSlot}`,
    };
  }

  takeFocusRequest(): string | null {
    const r = this.focusReq;
    this.focusReq = null;
    return r;
  }
}

// ───────────────────────────── settings ─────────────────────────────

export type SettingKey = keyof Settings;

export interface SettingRow {
  key: SettingKey;
  label: string;
  kind: 'volume' | 'offset' | 'toggle';
  help: string;
}

export const SETTING_ROWS: SettingRow[] = [
  { key: 'master', label: 'Master volume', kind: 'volume', help: 'Everything.' },
  { key: 'music', label: 'Music', kind: 'volume', help: 'The four cassette layers and the world groove.' },
  { key: 'sfx', label: 'Sound effects', kind: 'volume', help: 'Hits, steps, doors — they still land on the beat.' },
  {
    key: 'avOffsetMs',
    label: 'Audio / visual offset',
    kind: 'offset',
    help: 'Delays the picture to match late audio (e.g. Bluetooth headphones). Positive = picture later.',
  },
  { key: 'screenShake', label: 'Screen shake', kind: 'toggle', help: 'Camera kick on heavy impacts.' },
  {
    key: 'patterns',
    label: 'Cassette patterns',
    kind: 'toggle',
    help: 'Adds a stripe / dot / zigzag pattern to each cassette so tapes read without colour.',
  },
];

export function formatSetting(key: SettingKey, v: number | boolean): string {
  if (typeof v === 'boolean') return v ? 'On' : 'Off';
  if (key === 'avOffsetMs') return `${v > 0 ? '+' : v < 0 ? '−' : ''}${Math.abs(Math.round(v))} ms`;
  return `${Math.round(v * 100)}%`;
}

export class SettingsLogic implements MenuSource {
  settings: Settings = { ...DEFAULT_SETTINGS };
  confirmingErase = false;
  private focusReq: string | null = null;

  constructor(
    private readonly emit: Emit,
    private readonly leave: () => void,
  ) {}

  setModel(s: Settings): void {
    this.settings = { ...s };
  }

  onShow(): void {
    this.confirmingErase = false;
  }

  /** Set an absolute value (mouse drag on a slider). Emits only real changes. */
  setValue(key: SettingKey, value: number | boolean): void {
    let v = value;
    if (typeof v === 'number') {
      v = key === 'avOffsetMs' ? Math.round(clamp(v, AV_OFFSET_MIN, AV_OFFSET_MAX) / AV_OFFSET_STEP) * AV_OFFSET_STEP : snapVolume(v);
      v = Math.round(v * 1000) / 1000;
    }
    if (this.settings[key] === v) return;
    // Shown immediately; the game's setSettings() echo overwrites it with the authoritative value.
    (this.settings as Record<SettingKey, number | boolean>)[key] = v;
    this.emit({ type: 'setting', key, value: v });
  }

  nudge(key: SettingKey, delta: -1 | 1): void {
    const cur = this.settings[key];
    if (typeof cur === 'boolean') this.setValue(key, !cur);
    else this.setValue(key, cur + delta * (key === 'avOffsetMs' ? AV_OFFSET_STEP : VOLUME_STEP));
  }

  menu(): MenuDef {
    const entries: MenuEntry[] = SETTING_ROWS.map((r, row) => ({
      id: r.key,
      row,
      col: 0,
      adjust: (d: -1 | 1) => this.nudge(r.key, d),
      accept: r.kind === 'toggle' ? () => this.nudge(r.key, 1) : undefined,
    }));
    const eraseRow = SETTING_ROWS.length;
    if (this.confirmingErase) {
      entries.push({ id: 'erase-no', row: eraseRow, col: 0, accept: () => this.cancelErase() });
      entries.push({
        id: 'erase-yes',
        row: eraseRow,
        col: 1,
        accept: () => {
          this.confirmingErase = false;
          this.focusReq = 'erase';
          this.emit({ type: 'eraseSave' });
        },
      });
    } else {
      entries.push({
        id: 'erase',
        row: eraseRow,
        col: 0,
        accept: () => {
          this.confirmingErase = true;
          // Land on "keep" so a double-press can never erase a save.
          this.focusReq = 'erase-no';
        },
      });
    }
    entries.push({ id: 'back', row: eraseRow + 1, col: 0, accept: () => this.leave() });
    return {
      entries,
      back: () => {
        if (this.confirmingErase) this.cancelErase();
        else this.leave();
      },
      defaultFocus: 'master',
    };
  }

  takeFocusRequest(): string | null {
    const r = this.focusReq;
    this.focusReq = null;
    return r;
  }

  private cancelErase(): void {
    this.confirmingErase = false;
    this.focusReq = 'erase';
  }
}

// ───────────────────────────── pause ─────────────────────────────

export class PauseLogic implements MenuSource {
  sub: 'menu' | 'settings' = 'menu';
  readonly settings: SettingsLogic;
  private focusReq: string | null = null;

  constructor(private readonly emit: Emit) {
    this.settings = new SettingsLogic(emit, () => {
      this.sub = 'menu';
      this.focusReq = 'settings';
    });
  }

  onShow(): void {
    this.sub = 'menu';
    this.focusReq = 'resume';
  }

  menu(): MenuDef {
    if (this.sub === 'settings') return this.settings.menu();
    return {
      entries: [
        { id: 'resume', row: 0, col: 0, accept: () => this.emit({ type: 'resume' }) },
        {
          id: 'restart',
          row: 1,
          col: 0,
          accept: () => {
            // REC-05: restart = wipe every cassette; then leave the pause overlay.
            this.emit({ type: 'session', action: 'resetAll' });
            this.emit({ type: 'resume' });
          },
        },
        {
          id: 'settings',
          row: 2,
          col: 0,
          accept: () => {
            // Settings open inside the pause overlay so "back" returns here without a round-trip
            // through the game's screen state.
            this.sub = 'settings';
            this.settings.onShow();
          },
        },
        { id: 'quit', row: 3, col: 0, accept: () => this.emit({ type: 'session', action: 'quit' }) },
      ],
      back: () => this.emit({ type: 'resume' }),
      defaultFocus: 'resume',
    };
  }

  takeFocusRequest(): string | null {
    if (this.sub === 'settings') return this.settings.takeFocusRequest();
    const r = this.focusReq;
    this.focusReq = null;
    return r;
  }
}

// ───────────────────────────── results ─────────────────────────────

export interface ResultsView {
  title: string;
  win: boolean;
  levelName: string;
  depth: string;
  tapesUsed: number;
  maxTapes: number;
  notes: string[];
  loot: { name: string; slot: string; effect: string; lore: string }[];
  hasNext: boolean;
}

export function resultsView(m: ResultsModel): ResultsView {
  return {
    title: m.outcome.win ? 'LEVEL CLEARED' : 'ATTEMPT ENDED',
    win: m.outcome.win,
    levelName: m.level.name,
    depth: String(m.level.index + 1).padStart(2, '0'),
    tapesUsed: m.tapesUsed,
    maxTapes: m.level.maxTapes,
    notes: m.outcome.notes,
    loot: m.loot.map((g) => ({ name: g.name, slot: slotLabel(g.slot).title, effect: g.effect, lore: g.lore })),
    hasNext: m.hasNext,
  };
}

export class ResultsLogic implements MenuSource {
  model: ResultsModel | null = null;
  private focusReq: string | null = null;

  constructor(private readonly emit: Emit) {}

  setModel(m: ResultsModel): void {
    this.model = m;
    this.focusReq = m.hasNext ? 'next' : 'path';
  }

  menu(): MenuDef {
    const m = this.model;
    const entries: MenuEntry[] = [];
    let col = 0;
    if (m?.hasNext) {
      entries.push({
        id: 'next',
        row: 0,
        col: col++,
        accept: () =>
          this.emit(m.nextId ? { type: 'playLevel', id: m.nextId } : { type: 'session', action: 'continue' }),
      });
    }
    if (m) entries.push({ id: 'replay', row: 0, col: col++, accept: () => this.emit({ type: 'playLevel', id: m.level.id }) });
    entries.push({ id: 'path', row: 0, col: col++, accept: () => this.emit({ type: 'session', action: 'continue' }) });
    entries.push({ id: 'loadout', row: 0, col: col++, accept: () => this.emit({ type: 'openLoadout' }) });
    return {
      entries,
      back: () => this.emit({ type: 'session', action: 'continue' }),
      defaultFocus: m?.hasNext ? 'next' : 'path',
    };
  }

  takeFocusRequest(): string | null {
    const r = this.focusReq;
    this.focusReq = null;
    return r;
  }
}

// ───────────────────────────── ending ─────────────────────────────

export class EndingLogic implements MenuSource {
  constructor(private readonly emit: Emit) {}

  menu(): MenuDef {
    return {
      entries: [
        { id: 'path', row: 0, col: 0, accept: () => this.emit({ type: 'openCampaign' }) },
        { id: 'title', row: 0, col: 1, accept: () => this.emit({ type: 'openTitle' }) },
      ],
      back: () => this.emit({ type: 'openCampaign' }),
      defaultFocus: 'path',
    };
  }
}
