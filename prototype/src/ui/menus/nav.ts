/**
 * DOM-free menu focus model shared by every menu screen.
 *
 * Menus are laid out on a loose grid (row, col). Keyboard / gamepad navigation moves between
 * neighbouring cells; the mouse simply focuses (hover) and activates (click) entries by id. Both
 * paths go through the same MenuHost so a click and an "accept" can never behave differently.
 */

export type NavDir = 'up' | 'down' | 'left' | 'right';
export type NavCommand = NavDir | 'accept' | 'back';

export interface NavItem {
  id: string;
  row: number;
  col: number;
  /** Focusable (so it can be read, e.g. a locked level) but accept does nothing. */
  disabled?: boolean;
  /** Explicit neighbours that override the geometric search. */
  links?: Partial<Record<NavDir, string>>;
}

export interface MenuEntry extends NavItem {
  /** Accept / click. */
  accept?: () => void;
  /** Left / right on this entry adjusts a value instead of moving focus (sliders, toggles). */
  adjust?: (delta: -1 | 1) => void;
  /** Called when the entry gains focus (hover or keyboard). */
  focused?: () => void;
}

export interface MenuDef {
  entries: MenuEntry[];
  /** Back / cancel. */
  back?: () => void;
  /** Focus used when the current focus no longer exists in this definition. */
  defaultFocus?: string;
}

/** Anything that can describe its current menu. Screen logic classes implement this. */
export interface MenuSource {
  menu(): MenuDef;
  /** One-shot focus request after a state change (e.g. opening a list focuses the equipped item). */
  takeFocusRequest?(): string | null;
}

/**
 * Pure focus movement. Up/down go to the nearest populated row in that direction and pick the entry
 * whose column is closest (ties prefer the lower column, which keeps "down" from a wide button row
 * landing on the leftmost choice). Left/right stay on the current row. There is no wrap-around:
 * wrapping in a vertical descent list would teleport from the time machine back to the surface.
 */
export function moveFocus(items: readonly NavItem[], current: string | null, dir: NavDir): string | null {
  if (items.length === 0) return null;
  const from = current === null ? undefined : items.find((i) => i.id === current);
  if (!from) return items[0].id;

  const link = from.links?.[dir];
  if (link !== undefined && items.some((i) => i.id === link)) return link;

  if (dir === 'left' || dir === 'right') {
    const sign = dir === 'right' ? 1 : -1;
    let best: NavItem | undefined;
    for (const it of items) {
      if (it === from || it.row !== from.row) continue;
      const d = (it.col - from.col) * sign;
      if (d <= 0) continue;
      if (!best || d < (best.col - from.col) * sign) best = it;
    }
    return best ? best.id : from.id;
  }

  const sign = dir === 'down' ? 1 : -1;
  let targetRow: number | undefined;
  for (const it of items) {
    const d = (it.row - from.row) * sign;
    if (d <= 0) continue;
    if (targetRow === undefined || d < (targetRow - from.row) * sign) targetRow = it.row;
  }
  if (targetRow === undefined) return from.id;
  let best: NavItem | undefined;
  for (const it of items) {
    if (it.row !== targetRow) continue;
    if (!best) {
      best = it;
      continue;
    }
    const d = Math.abs(it.col - from.col);
    const bd = Math.abs(best.col - from.col);
    if (d < bd || (d === bd && it.col < best.col)) best = it;
  }
  return best ? best.id : from.id;
}

/**
 * Binds a MenuSource to a focus cursor. After every command the menu is re-read from the source,
 * because accepting an entry may change the screen's local state (open a list, show a confirm).
 */
export class MenuHost {
  private def: MenuDef = { entries: [] };
  private cur: string | null = null;

  constructor(
    private readonly source: MenuSource,
    /** Notified when focus moves or the definition was re-read. */
    private readonly onChange: (focus: string | null) => void = () => {},
  ) {
    this.refresh();
  }

  get focus(): string | null {
    return this.cur;
  }

  get entries(): readonly MenuEntry[] {
    return this.def.entries;
  }

  /** Re-read the menu from the source, keeping focus where possible. */
  refresh(): void {
    this.def = this.source.menu();
    const req = this.source.takeFocusRequest?.() ?? null;
    const ids = this.def.entries;
    let next: string | null = this.cur;
    if (req !== null && ids.some((e) => e.id === req)) next = req;
    if (next === null || !ids.some((e) => e.id === next)) {
      const d = this.def.defaultFocus;
      next = d !== undefined && ids.some((e) => e.id === d) ? d : ids.find((e) => !e.disabled)?.id ?? ids[0]?.id ?? null;
    }
    this.setFocus(next, false);
    this.onChange(this.cur);
  }

  navigate(cmd: NavCommand): void {
    const entry = this.entry(this.cur);
    if (cmd === 'accept') {
      if (entry && !entry.disabled) entry.accept?.();
      this.refresh();
      return;
    }
    if (cmd === 'back') {
      this.def.back?.();
      this.refresh();
      return;
    }
    if ((cmd === 'left' || cmd === 'right') && entry?.adjust && !entry.disabled) {
      entry.adjust(cmd === 'right' ? 1 : -1);
      this.refresh();
      return;
    }
    const next = moveFocus(this.def.entries, this.cur, cmd);
    if (next !== this.cur) {
      this.setFocus(next, true);
      this.refresh();
    }
  }

  /** Mouse hover: focus follows the pointer so the details panels track what is under it. */
  hover(id: string): void {
    if (id === this.cur || !this.entry(id)) return;
    this.setFocus(id, true);
    this.refresh();
  }

  /** Mouse click: identical to focusing the entry and pressing accept. */
  click(id: string): void {
    if (!this.entry(id)) return;
    if (id !== this.cur) this.setFocus(id, true);
    this.navigate('accept');
  }

  /** Mouse on a slider / stepper: identical to left/right on the focused entry. */
  adjust(id: string, delta: -1 | 1): void {
    const e = this.entry(id);
    if (!e || e.disabled || !e.adjust) return;
    if (id !== this.cur) this.setFocus(id, true);
    e.adjust(delta);
    this.refresh();
  }

  private entry(id: string | null): MenuEntry | undefined {
    return id === null ? undefined : this.def.entries.find((e) => e.id === id);
  }

  private setFocus(id: string | null, notify: boolean): void {
    const changed = id !== this.cur;
    this.cur = id;
    if (changed && notify) this.entry(id)?.focused?.();
  }
}
