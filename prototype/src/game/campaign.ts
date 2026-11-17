/**
 * Fixed-path campaign progression (LEVEL-08, LEVEL-09, GEAR-01..04, APPAREL-02).
 *
 *  - The path is LEVELS in index order. The first level is always open; every other level opens
 *    once the one before it is cleared. Cleared levels can always be replayed (LEVEL-09).
 *  - Clearing a level awards its loot into the inventory the first time only; nothing is ever
 *    removed from the inventory (GEAR-04).
 *  - The loadout can change only between levels (GEAR-03): while a level attempt is in progress
 *    `equip` refuses, so a committed tape is never reinterpreted under different gear.
 *  - Every loadout is sanitised against the inventory (owned items of the right slot only).
 *
 * Pure state + functions over SaveData; persistence is the caller's job (see save.ts).
 */
import type { CampaignScreenModel, LoadoutScreenModel } from '../contracts';
import { describeLoadout, GEAR, itemsForSlot, resolveLoadout, sanitiseLoadout } from '../content/index';
import { GEAR_SLOTS, type GearItem, type GearSlot, type LevelDef, type ResolvedLoadout, type SaveData } from '../core/types';
import { validateSave } from './save';

export interface ClearResult {
  /** True the first time this level is cleared. */
  firstClear: boolean;
  /** Items newly added to the inventory by this clear (empty on revisits). */
  loot: GearItem[];
}

function gearItems(ids: readonly string[]): GearItem[] {
  const out: GearItem[] = [];
  for (const id of ids) {
    const it = Object.prototype.hasOwnProperty.call(GEAR, id) ? GEAR[id] : undefined;
    if (it) out.push(it);
  }
  return out;
}

export class Campaign {
  readonly levels: readonly LevelDef[];
  private _save: SaveData;
  private _activeLevel: string | null = null;
  /** Item ids picked up since the loadout screen was last opened. */
  private fresh: string[] = [];

  constructor(levels: readonly LevelDef[], save: SaveData) {
    this.levels = [...levels].sort((a, b) => a.index - b.index);
    this._save = validateSave(save);
  }

  get save(): SaveData {
    return this._save;
  }

  /** Id of the level whose attempt is in progress (gear is locked), or null between levels. */
  get activeLevel(): string | null {
    return this._activeLevel;
  }

  level(id: string): LevelDef | null {
    return this.levels.find((l) => l.id === id) ?? null;
  }

  isCleared(id: string): boolean {
    return this._save.cleared.includes(id);
  }

  /** LEVEL-08: the first level and every level after a cleared one; LEVEL-09: cleared levels stay open. */
  isUnlocked(id: string): boolean {
    const i = this.levels.findIndex((l) => l.id === id);
    if (i < 0) return false;
    if (i === 0 || this.isCleared(id)) return true;
    return this.isCleared(this.levels[i - 1].id);
  }

  /** Index (into `levels`) of the next uncleared level; the last level once everything is cleared. */
  currentIndex(): number {
    const i = this.levels.findIndex((l) => !this.isCleared(l.id));
    return i < 0 ? Math.max(0, this.levels.length - 1) : i;
  }

  /** The level after `id` on the path, or null after the final level. */
  nextLevel(id: string): LevelDef | null {
    const i = this.levels.findIndex((l) => l.id === id);
    return i >= 0 && i + 1 < this.levels.length ? this.levels[i + 1] : null;
  }

  allCleared(): boolean {
    return this.levels.length > 0 && this.levels.every((l) => this.isCleared(l.id));
  }

  /** Lock gear for a level attempt. Returns false (and changes nothing) if the level is locked. */
  beginLevel(id: string): boolean {
    if (!this.isUnlocked(id)) return false;
    this._activeLevel = id;
    return true;
  }

  /** The attempt is over (won, quit or abandoned): gear may change again. */
  endLevel(): void {
    this._activeLevel = null;
  }

  /**
   * Record a clear. Loot is awarded only on the first clear, and only items not already owned are
   * reported as new.
   */
  recordClear(id: string): ClearResult {
    const level = this.level(id);
    if (!level) return { firstClear: false, loot: [] };
    if (this.isCleared(id)) return { firstClear: false, loot: [] };
    const inventory = [...this._save.inventory];
    const loot: GearItem[] = [];
    for (const it of gearItems(level.loot)) {
      if (inventory.includes(it.id)) continue;
      inventory.push(it.id);
      loot.push(it);
      this.fresh.push(it.id);
    }
    this._save = { ...this._save, cleared: [...this._save.cleared, id], inventory };
    return { firstClear: true, loot };
  }

  /**
   * Equip an owned item between levels (GEAR-03). Returns false when a level attempt is active,
   * the item is unknown, not owned, or belongs to another slot.
   */
  equip(slot: GearSlot, id: string): boolean {
    if (this._activeLevel !== null) return false;
    const item = Object.prototype.hasOwnProperty.call(GEAR, id) ? GEAR[id] : undefined;
    if (!item || item.slot !== slot) return false;
    if (!itemsForSlot(this._save.inventory, slot).some((it) => it.id === id)) return false;
    const loadout = sanitiseLoadout({ ...this._save.loadout, [slot]: id }, this._save.inventory);
    if (loadout[slot] !== id) return false;
    this._save = { ...this._save, loadout };
    return true;
  }

  setSettings(settings: SaveData['settings']): void {
    this._save = validateSave({ ...this._save, settings });
  }

  /** Replace the whole save (erase / load). Ends any active attempt's gear lock. */
  replaceSave(save: SaveData): void {
    this._save = validateSave(save);
    this._activeLevel = null;
    this.fresh = [];
  }

  resolvedLoadout(): ResolvedLoadout {
    return resolveLoadout(sanitiseLoadout(this._save.loadout, this._save.inventory));
  }

  campaignModel(): CampaignScreenModel {
    return {
      levels: this.levels.map((level) => {
        const cleared = this.isCleared(level.id);
        return { level, cleared, unlocked: this.isUnlocked(level.id), loot: cleared ? gearItems(level.loot) : undefined };
      }),
      current: this.currentIndex(),
    };
  }

  /** Loadout screen model. `consumeFresh` clears the "new" markers (the screen is being opened). */
  loadoutModel(consumeFresh = false): LoadoutScreenModel {
    const inventory: GearItem[] = [];
    for (const slot of GEAR_SLOTS) inventory.push(...itemsForSlot(this._save.inventory, slot));
    const model: LoadoutScreenModel = {
      inventory,
      loadout: { ...this._save.loadout },
      summary: describeLoadout(this._save.loadout),
      fresh: [...this.fresh],
    };
    if (consumeFresh) this.fresh = [];
    return model;
  }
}
