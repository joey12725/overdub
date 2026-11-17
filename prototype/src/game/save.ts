/**
 * Persistent campaign save (GEAR-01, GEAR-04, LEVEL-08/09) in localStorage.
 *
 * Policy: loading never throws and never returns something the game cannot use. A missing,
 * unreadable, corrupt or foreign save falls back to a fresh one (baseline loadout and inventory);
 * a partly damaged save keeps every field that still validates. Storage failures (private mode,
 * quota, disabled storage) are swallowed: the game keeps running with its in-memory save.
 */
import { BASE_INVENTORY, BASE_LOADOUT, GEAR, sanitiseLoadout } from '../content/index';
import type { SaveData } from '../core/types';

/** Versioned key: a future incompatible format gets a new key instead of misreading this one. */
export const SAVE_KEY = 'overdub.save.v1';

export const DEFAULT_SETTINGS: SaveData['settings'] = {
  master: 0.8,
  music: 0.8,
  sfx: 0.8,
  avOffsetMs: 0,
  screenShake: true,
  patterns: false,
};

/** Range the A/V offset is clamped to, in ms (matches the settings screen). */
export const AV_OFFSET_LIMIT = 300;

/** Minimal Storage surface, so tests and non-browser hosts can pass their own. */
export interface SaveStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

export function freshSave(): SaveData {
  return {
    version: 1,
    cleared: [],
    inventory: [...BASE_INVENTORY],
    loadout: { ...BASE_LOADOUT },
    settings: { ...DEFAULT_SETTINGS },
  };
}

/** The browser's localStorage when it is usable, else null. */
export function defaultStorage(): SaveStorage | null {
  try {
    const g = globalThis as { localStorage?: SaveStorage };
    return g.localStorage ?? null;
  } catch {
    // Accessing localStorage itself throws in some sandboxed iframes.
    return null;
  }
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

function stringList(v: unknown): string[] {
  if (!Array.isArray(v)) return [];
  const out: string[] = [];
  for (const x of v) if (typeof x === 'string' && x.length > 0 && !out.includes(x)) out.push(x);
  return out;
}

function unit(v: unknown, fallback: number): number {
  return typeof v === 'number' && Number.isFinite(v) ? Math.min(1, Math.max(0, v)) : fallback;
}

function bool(v: unknown, fallback: boolean): boolean {
  return typeof v === 'boolean' ? v : fallback;
}

function validSettings(v: unknown): SaveData['settings'] {
  const s = isRecord(v) ? v : {};
  const off = typeof s.avOffsetMs === 'number' && Number.isFinite(s.avOffsetMs) ? s.avOffsetMs : DEFAULT_SETTINGS.avOffsetMs;
  return {
    master: unit(s.master, DEFAULT_SETTINGS.master),
    music: unit(s.music, DEFAULT_SETTINGS.music),
    sfx: unit(s.sfx, DEFAULT_SETTINGS.sfx),
    avOffsetMs: Math.round(Math.min(AV_OFFSET_LIMIT, Math.max(-AV_OFFSET_LIMIT, off))),
    screenShake: bool(s.screenShake, DEFAULT_SETTINGS.screenShake),
    patterns: bool(s.patterns, DEFAULT_SETTINGS.patterns),
  };
}

/**
 * Coerce anything into a usable SaveData. Unknown gear ids are dropped (an item removed from the
 * catalogue cannot be equipped), the baseline items are always owned, and the loadout is
 * sanitised against the inventory so it only ever holds owned items of the right slot.
 */
export function validateSave(raw: unknown): SaveData {
  if (!isRecord(raw) || raw.version !== 1) return freshSave();
  const inventory = [...BASE_INVENTORY];
  for (const id of stringList(raw.inventory)) {
    if (Object.prototype.hasOwnProperty.call(GEAR, id) && !inventory.includes(id)) inventory.push(id);
  }
  const loadoutIn = isRecord(raw.loadout) ? (raw.loadout as Partial<SaveData['loadout']>) : null;
  return {
    version: 1,
    cleared: stringList(raw.cleared),
    inventory,
    loadout: sanitiseLoadout(loadoutIn, inventory),
    settings: validSettings(raw.settings),
  };
}

/** Load the save; any problem yields a fresh save. Never throws. */
export function loadSave(storage: SaveStorage | null = defaultStorage()): SaveData {
  if (!storage) return freshSave();
  let text: string | null;
  try {
    text = storage.getItem(SAVE_KEY);
  } catch {
    return freshSave();
  }
  if (text === null) return freshSave();
  try {
    return validateSave(JSON.parse(text));
  } catch {
    return freshSave();
  }
}

/** Persist the save. Returns false when storage is unavailable or refused the write. Never throws. */
export function writeSave(data: SaveData, storage: SaveStorage | null = defaultStorage()): boolean {
  if (!storage) return false;
  try {
    storage.setItem(SAVE_KEY, JSON.stringify(validateSave(data)));
    return true;
  } catch {
    return false;
  }
}

/** Remove the save entirely. Never throws. */
export function eraseSave(storage: SaveStorage | null = defaultStorage()): boolean {
  if (!storage) return false;
  try {
    storage.removeItem(SAVE_KEY);
    return true;
  } catch {
    return false;
  }
}

/** In-memory SaveStorage (tests, and a fallback when the browser refuses localStorage). */
export function memoryStorage(initial: Record<string, string> = {}): SaveStorage & { data: Map<string, string> } {
  const data = new Map(Object.entries(initial));
  return {
    data,
    getItem: (k) => (data.has(k) ? data.get(k)! : null),
    setItem: (k, v) => void data.set(k, String(v)),
    removeItem: (k) => void data.delete(k),
  };
}
