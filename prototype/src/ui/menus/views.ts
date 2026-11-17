/**
 * DOM builders for each menu screen. Views read logic state and models; they never emit intents
 * themselves — every interactive element carries data-nav (and optionally data-adjust /
 * data-setting) and the Menus controller routes the pointer through the same MenuHost the
 * keyboard / gamepad uses.
 */
import type { CampaignScreenModel } from '../../contracts';
import type { GearItem, GearSlot } from '../../core/types';
import { CHECK_SVG, CRATE_SVG, DOLL_SVG, LOCK_SVG, LOGO_SVG, TIME_MACHINE_SVG } from './art';
import { cassette, h, svgArt } from './dom';
import {
  compareItems,
  itemDetailRows,
  slotLabel,
  weaponHeadline,
  type CompareRow,
  type StatRow,
} from './format';
import {
  AV_OFFSET_MAX,
  AV_OFFSET_MIN,
  AV_OFFSET_STEP,
  SETTING_ROWS,
  VOLUME_STEP,
  campaignNodes,
  equippedItem,
  formatSetting,
  loadoutView,
  resultsView,
  type CampaignLogic,
  type EndingLogic,
  type LoadoutLogic,
  type PauseLogic,
  type ResultsLogic,
  type SettingsLogic,
  type TitleLogic,
} from './logic';

export type Device = 'keyboard' | 'gamepad';

export interface ScreenView {
  /** Structural key: when it changes the screen is rebuilt; otherwise only focus/patches apply. */
  key(): string;
  build(): HTMLElement;
  /** Called after every focus move / model echo to update dependent regions in place. */
  sync?(root: HTMLElement, focus: string | null): void;
}

// ───────────────────────────── shared pieces ─────────────────────────────

function btn(nav: string, label: string, opts: { sub?: string; tone?: 'primary' | 'danger' | 'ghost'; cls?: string } = {}): HTMLElement {
  return h(
    `button.od-btn${opts.tone ? '.od-btn--' + opts.tone : ''}${opts.cls ? '.' + opts.cls : ''}`,
    { type: 'button', 'data-nav': nav, tabindex: -1 },
    h('span.od-btn-label', null, label),
    opts.sub ? h('span.od-btn-sub', null, opts.sub) : null,
  );
}

export function prompts(device: Device, extra: string[] = []): HTMLElement {
  const items =
    device === 'gamepad'
      ? [['D-pad', 'move'], ['A', 'select'], ['B', 'back']]
      : [['↑↓←→', 'move'], ['Enter', 'select'], ['Esc', 'back']];
  return h(
    'div.od-prompts',
    { 'aria-hidden': 'true' },
    ...items.map(([k, v]) => h('span.od-prompt', null, h('kbd', null, k), ' ', v)),
    ...extra.map((t) => h('span.od-prompt', null, t)),
  );
}

/** Always four cassette outlines so "2 of a possible 4" reads at a glance; offered ones are coloured. */
function tapeStrip(count: number): HTMLElement {
  const wrap = h('span.od-tapes');
  for (let i = 0; i < 4; i++) wrap.append(cassette(i, i < count ? 'on' : 'off'));
  return wrap;
}

function statTable(rows: StatRow[]): HTMLElement {
  return h('dl.od-stats', null, ...rows.flatMap((r) => [h('dt', null, r.label), h('dd', null, r.value)]));
}

function compareTable(rows: CompareRow[]): HTMLElement {
  if (rows.length === 0) return h('p.od-muted', null, 'No mechanical difference.');
  return h(
    'table.od-compare',
    null,
    h('thead', null, h('tr', null, h('th', null, ''), h('th', null, 'Equipped'), h('th', null, 'This'))),
    h(
      'tbody',
      null,
      ...rows.map((r) =>
        h(
          `tr.od-cmp--${r.dir > 0 ? 'better' : r.dir < 0 ? 'worse' : 'same'}`,
          null,
          h('th', null, r.label),
          h('td', null, r.from),
          h('td', null, r.to, r.dir > 0 ? ' ▲' : r.dir < 0 ? ' ▼' : ''),
        ),
      ),
    ),
  );
}

// ───────────────────────────── title ─────────────────────────────

export function titleView(logic: TitleLogic, campaign: () => CampaignScreenModel | null, device: () => Device): ScreenView {
  return {
    key: () => `${logic.confirmingNew}|${campaign() ? campaignNodes(campaign()!).filter((n) => n.cleared).length : -1}|${device()}`,
    build() {
      const c = campaign();
      const cur = c?.levels[c.current];
      const menu = h('nav.od-title-menu', { 'aria-label': 'Main menu' });
      if (logic.confirmingNew) {
        menu.append(
          h(
            'div.od-confirm',
            { role: 'alertdialog' },
            h('p.od-confirm-title', null, 'Start a new descent?'),
            h('p.od-confirm-text', null, 'This erases cleared levels and every piece of gear you found.'),
            h('div.od-row', null, btn('new-no', 'Keep my save', { tone: 'ghost' }), btn('new-yes', 'Erase & start over', { tone: 'danger' })),
          ),
        );
      } else {
        const entries = logic.menu().entries;
        const hasContinue = entries.some((e) => e.id === 'continue');
        for (const e of entries) {
          if (e.id === 'continue')
            menu.append(
              btn('continue', 'Continue', {
                tone: 'primary',
                sub: cur ? `Depth ${String(c!.current + 1).padStart(2, '0')} — ${cur.level.name}` : undefined,
              }),
            );
          if (e.id === 'new')
            menu.append(
              btn('new', 'New descent', hasContinue ? { sub: 'Erases progress' } : { tone: 'primary', sub: 'Into the ruins' }),
            );
          if (e.id === 'loadout') menu.append(btn('loadout', 'Loadout', { sub: 'Gear for all four tapes' }));
          if (e.id === 'settings') menu.append(btn('settings', 'Settings'));
        }
      }
      return h(
        'section.od-screen.od-title',
        { 'aria-label': 'OVERDUB' },
        h('div.od-title-backdrop', { 'aria-hidden': 'true' }, h('i'), h('i'), h('i'), h('i')),
        h(
          'div.od-title-stack',
          null,
          svgArt(LOGO_SVG, 'od-logo'),
          h('p.od-tagline', null, 'Four tapes. One world. A solution worth watching.'),
          menu,
        ),
        prompts(device()),
      );
    },
  };
}

// ───────────────────────────── campaign ─────────────────────────────

export function campaignView(logic: CampaignLogic, version: () => number, device: () => Device): ScreenView {
  return {
    key: () => `${version()}|${logic.lockedPokes}|${device()}`,
    build() {
      const model = logic.model;
      const nodes = model ? campaignNodes(model) : [];
      const list = h('ol.od-descent-list');
      for (const n of nodes) {
        const meta = h(
          'div.od-node-meta',
          null,
          h('span.od-chip-group', { title: `Up to ${n.maxTapes} cassette${n.maxTapes > 1 ? 's' : ''}` }, tapeStrip(n.maxTapes), h('b', null, `${n.maxTapes} tape${n.maxTapes > 1 ? 's' : ''}`)),
          h('span.od-chip-group', null, ...n.speeds.map((s) => h('span.od-chip', null, s))),
          n.endModes.length ? h('span.od-chip-group', null, ...n.endModes.map((s) => h('span.od-chip.od-chip--mode', null, s))) : null,
        );
        const loot = h(
          'div.od-node-loot',
          null,
          svgArt(CRATE_SVG, 'od-ico-wrap'),
          n.loot.count === 0
            ? h('span', null, 'No gear here')
            : n.loot.found
              ? n.loot.items.length
                ? h('span', null, 'Found: ', ...n.loot.items.flatMap((g, i) => [i ? ', ' : '', h('b', { title: g.effect }, g.name)]))
                : h('span', null, `Found ${n.loot.count} item${n.loot.count > 1 ? 's' : ''}`)
              : h('span', null, `${n.loot.count} item${n.loot.count > 1 ? 's' : ''} to find`),
        );
        const badge =
          n.status === 'locked'
            ? h('span.od-badge.od-badge--locked', null, svgArt(LOCK_SVG, 'od-ico-wrap'), 'Locked')
            : n.status === 'cleared'
              ? h('span.od-badge.od-badge--cleared', null, svgArt(CHECK_SVG, 'od-ico-wrap'), 'Cleared · replay')
              : n.status === 'next'
                ? h('span.od-badge.od-badge--next', null, 'Next')
                : h('span.od-badge', null, 'Open');
        const poked = logic.lastPoked === n.navId && logic.lockedPokes > 0;
        list.append(
          h(
            `li.od-node.od-theme-${n.theme}.od-node--${n.status}${n.final ? '.od-node--final' : ''}${poked ? '.od-shake' : ''}`,
            { 'data-nav': n.navId, 'aria-disabled': n.unlocked ? null : 'true' },
            h('div.od-node-pin', { 'aria-hidden': 'true' }, n.final ? svgArt(TIME_MACHINE_SVG, 'od-tm-wrap') : h('span', null, n.depth)),
            h(
              'div.od-node-card',
              null,
              h('div.od-node-head', null, h('span.od-node-depth', null, `DEPTH ${n.depth} · ${n.themeLabel.toUpperCase()}`), badge),
              h('h3.od-node-name', null, n.name),
              h('p.od-node-tag', null, n.tagline),
              meta,
              loot,
            ),
          ),
        );
      }
      return h(
        'section.od-screen.od-campaign',
        { 'aria-label': 'The descent' },
        h(
          'header.od-topbar',
          null,
          btn('back', '◀ Title', { tone: 'ghost', cls: 'od-btn--small' }),
          h('div.od-topbar-title', null, h('h1', null, 'THE DESCENT'), h('p', null, 'Fixed path down. Cleared levels can be replayed with any gear.')),
          btn('loadout', 'Loadout', { cls: 'od-btn--small' }),
        ),
        h('div.od-descent', { 'data-scroll': 'descent', 'data-scroll-center': true }, h('div.od-descent-inner', null, h('div.od-descent-track', { 'aria-hidden': 'true' }), list)),
        prompts(device()),
      );
    },
  };
}

// ───────────────────────────── loadout ─────────────────────────────

function itemCard(item: GearItem, navId: string, tags: { equipped: boolean; fresh: boolean }): HTMLElement {
  const head = weaponHeadline(item);
  return h(
    `li.od-item${tags.equipped ? '.od-item--equipped' : ''}`,
    { 'data-nav': navId },
    h(
      'div.od-item-top',
      null,
      h('span.od-item-name', null, item.name),
      tags.fresh ? h('span.od-tag.od-tag--new', null, 'NEW') : null,
      tags.equipped ? h('span.od-tag.od-tag--eq', null, 'EQUIPPED') : null,
    ),
    h('p.od-item-effect', null, item.effect),
    head ? h('p.od-item-head', null, head) : null,
  );
}

function details(item: GearItem | null, equipped: GearItem | null, slot: GearSlot): HTMLElement {
  if (!item) return h('div.od-details', null, h('p.od-muted', null, `Nothing owned for ${slotLabel(slot).title}.`));
  const isEq = equipped?.id === item.id;
  const rows = itemDetailRows(item);
  return h(
    'div.od-details',
    null,
    h('div.od-details-kicker', null, slotLabel(item.slot).title, isEq ? ' · equipped' : ''),
    h('h3.od-details-name', null, item.name),
    h('p.od-details-effect', null, item.effect),
    !isEq && equipped
      ? h('div.od-details-block', null, h('h4', null, `Compared with ${equipped.name}`), compareTable(compareItems(equipped, item)))
      : null,
    rows.length ? h('div.od-details-block', null, h('h4', null, 'Mechanics'), statTable(rows)) : null,
    item.lore ? h('p.od-lore', null, item.lore) : null,
  );
}

export function loadoutScreenView(logic: LoadoutLogic, version: () => number, device: () => Device): ScreenView {
  return {
    key: () => `${version()}|${logic.activeSlot}|${device()}`,
    build() {
      const model = logic.model;
      if (!model) {
        return h('section.od-screen.od-loadout', null, h('div.od-panel', null, h('p', null, 'Loading gear…')), btn('done', 'Done'));
      }
      const v = loadoutView(model, logic.activeSlot);
      const slots = h(
        'ol.od-slots',
        null,
        ...v.slots.map((s) =>
          h(
            `li.od-slot${s.slot === v.activeSlot ? '.od-slot--active' : ''}`,
            { 'data-nav': s.navId, 'data-slot': s.slot },
            h('div.od-slot-label', null, h('span', null, s.title), s.hasFresh ? h('span.od-tag.od-tag--new', null, 'NEW') : null, h('span.od-slot-owned', null, `${s.owned} owned`)),
            h('div.od-slot-name', null, s.equipped ? s.equipped.name : '—'),
            h('div.od-slot-effect', null, s.equipped ? s.equipped.effect : ''),
          ),
        ),
      );
      const pins: [GearSlot, number, number][] = [
        ['helmet', 50, 11],
        ['top', 50, 33],
        ['pants', 50, 62],
        ['shoes', 50, 90],
        ['melee', 9, 38],
        ['ranged', 92, 56],
      ];
      const doll = h(
        'div.od-doll',
        { 'data-active-slot': v.activeSlot },
        svgArt(DOLL_SVG, 'od-doll-art'),
        ...pins.map(([slot, x, y]) =>
          h(
            `button.od-pin${slot === v.activeSlot ? '.od-pin--active' : ''}`,
            { type: 'button', tabindex: -1, 'data-nav': `slot:${slot}`, style: `left:${x}%;top:${y}%`, title: slotLabel(slot).title },
            slotLabel(slot).short,
          ),
        ),
      );
      const summary = h(
        'div.od-summary',
        null,
        h('h4', null, 'Combined effects'),
        v.summary.length ? h('ul', null, ...v.summary.map((s) => h('li', null, s))) : h('p.od-muted', null, 'Baseline Moxie — no modifiers.'),
      );
      const lab = slotLabel(v.activeSlot);
      const list = h(
        'div.od-itemlist',
        { 'data-scroll': `items:${v.activeSlot}` },
        h('ol', null, ...v.items.map((it) => itemCard(it.item, it.navId, it))),
      );
      return h(
        'section.od-screen.od-loadout',
        { 'aria-label': 'Loadout' },
        h(
          'header.od-topbar',
          null,
          h('div.od-topbar-title', null, h('h1', null, 'LOADOUT'), h('p', null, 'One loadout for all four tapes. Swap freely between levels; it locks once a level starts.')),
        ),
        h(
          'div.od-loadout-grid',
          null,
          h('div.od-col.od-col--slots', null, slots, btn('done', 'Done', { tone: 'primary' })),
          h('div.od-col.od-col--doll', null, doll, summary),
          h(
            'div.od-col.od-col--items',
            null,
            h('div.od-items-head', null, h('h2', null, lab.title), h('span', null, `${lab.kind} · ${v.items.length} owned · ${lab.touches}`)),
            list,
            h('div.od-details-slot'),
          ),
        ),
        prompts(device(), [logic.inList ? 'Select equips' : 'Select opens the slot']),
      );
    },
    sync(root, focus) {
      const model = logic.model;
      const slotEl = root.querySelector('.od-details-slot');
      if (!model || !slotEl) return;
      const eq = equippedItem(model, logic.activeSlot);
      let shown: GearItem | null = eq;
      if (focus?.startsWith('item:')) {
        const id = focus.slice(5);
        shown = model.inventory.find((g) => g.id === id) ?? eq;
      }
      slotEl.replaceChildren(details(shown, eq, logic.activeSlot));
      const p = root.querySelector('.od-prompts .od-prompt:last-child');
      if (p) p.textContent = logic.inList ? 'Select equips' : 'Select opens the slot';
    },
  };
}

// ───────────────────────────── settings ─────────────────────────────

export function settingsPanel(logic: SettingsLogic): HTMLElement {
  const rows = SETTING_ROWS.map((r) => {
    const v = logic.settings[r.key];
    let control: HTMLElement;
    if (r.kind === 'toggle') {
      control = h(
        'span.od-switch',
        { 'data-setting-view': r.key, 'aria-checked': v ? 'true' : 'false', role: 'switch' },
        h('span.od-switch-knob'),
        h('span.od-switch-text', null, formatSetting(r.key, v)),
      );
    } else {
      const isOffset = r.kind === 'offset';
      control = h(
        'span.od-slider',
        null,
        h('button.od-step', { type: 'button', tabindex: -1, 'data-adjust': '-1', 'aria-label': 'Decrease' }, '−'),
        h('input', {
          type: 'range',
          tabindex: -1,
          'data-setting': r.key,
          min: isOffset ? AV_OFFSET_MIN : 0,
          max: isOffset ? AV_OFFSET_MAX : 1,
          step: isOffset ? AV_OFFSET_STEP : VOLUME_STEP,
          value: String(v),
          'aria-label': r.label,
        }),
        h('button.od-step', { type: 'button', tabindex: -1, 'data-adjust': '1', 'aria-label': 'Increase' }, '+'),
        h('output.od-slider-val', { 'data-setting-view': r.key }, formatSetting(r.key, v)),
      );
    }
    return h(
      'li.od-set-row',
      { 'data-nav': r.key },
      h('div.od-set-text', null, h('span.od-set-label', null, r.label), h('span.od-set-help', null, r.help)),
      control,
    );
  });
  const erase = logic.confirmingErase
    ? h(
        'li.od-set-row.od-set-row--erase',
        null,
        h('div.od-set-text', null, h('span.od-set-label', null, 'Erase everything?'), h('span.od-set-help', null, 'Cleared levels, found gear and your loadout are wiped. This cannot be undone.')),
        h('span.od-row', null, btn('erase-no', 'Keep', { tone: 'ghost', cls: 'od-btn--small' }), btn('erase-yes', 'Erase save', { tone: 'danger', cls: 'od-btn--small' })),
      )
    : h(
        'li.od-set-row.od-set-row--erase',
        null,
        h('div.od-set-text', null, h('span.od-set-label', null, 'Save data'), h('span.od-set-help', null, 'Progress saves automatically on this device.')),
        btn('erase', 'Erase save…', { tone: 'danger', cls: 'od-btn--small' }),
      );
  return h(
    'div.od-panel.od-settings-panel',
    null,
    h('h1.od-panel-title', null, 'SETTINGS'),
    h('ol.od-set-list', null, ...rows, erase),
    btn('back', 'Back', { tone: 'ghost' }),
  );
}

/** Update slider positions and value labels in place (no rebuild, so a drag in progress survives). */
export function patchSettings(root: HTMLElement, logic: SettingsLogic): void {
  for (const r of SETTING_ROWS) {
    const v = logic.settings[r.key];
    const input = root.querySelector<HTMLInputElement>(`input[data-setting="${r.key}"]`);
    if (input && document.activeElement !== input && input.value !== String(v)) input.value = String(v);
    if (input) {
      const lo = Number(input.min);
      const hi = Number(input.max);
      input.style.setProperty('--fill', `${(((Number(v) - lo) / (hi - lo)) * 100).toFixed(1)}%`);
    }
    root.querySelectorAll<HTMLElement>(`[data-setting-view="${r.key}"]`).forEach((el) => {
      if (el.classList.contains('od-switch')) {
        el.setAttribute('aria-checked', v ? 'true' : 'false');
        const t = el.querySelector('.od-switch-text');
        if (t) t.textContent = formatSetting(r.key, v);
      } else el.textContent = formatSetting(r.key, v);
    });
  }
}

export function settingsView(logic: SettingsLogic, device: () => Device): ScreenView {
  return {
    key: () => `${logic.confirmingErase}|${device()}`,
    build: () => h('section.od-screen.od-settings', { 'aria-label': 'Settings' }, settingsPanel(logic), prompts(device(), ['←→ adjust'])),
    sync: (root) => patchSettings(root, logic),
  };
}

// ───────────────────────────── pause ─────────────────────────────

export function pauseView(
  logic: PauseLogic,
  ctx: () => { levelName: string | null; midTake: boolean },
  device: () => Device,
): ScreenView {
  return {
    key: () => `${logic.sub}|${logic.settings.confirmingErase}|${ctx().levelName}|${ctx().midTake}|${device()}`,
    build() {
      if (logic.sub === 'settings') {
        return h('section.od-screen.od-pause', { 'aria-label': 'Settings' }, settingsPanel(logic.settings), prompts(device(), ['←→ adjust']));
      }
      const c = ctx();
      return h(
        'section.od-screen.od-pause',
        { 'aria-label': 'Paused' },
        h(
          'div.od-panel.od-pause-panel',
          null,
          h('div.od-pause-head', null, h('h1.od-panel-title', null, 'PAUSED'), c.levelName ? h('p.od-muted', null, c.levelName) : null),
          c.midTake ? h('p.od-note.od-note--warn', null, 'No tactical pause: the take in progress goes back to setup.') : null,
          h(
            'nav.od-pause-menu',
            null,
            btn('resume', 'Resume', { tone: 'primary' }),
            btn('restart', 'Restart level', { sub: 'Wipes every cassette (reset all)' }),
            btn('settings', 'Settings'),
            btn('quit', 'Quit to path', { sub: 'Leaves this attempt' }),
          ),
          h('p.od-note', null, svgArt(LOCK_SVG, 'od-ico-wrap'), 'Loadout is locked for this attempt — change gear between levels.'),
        ),
        prompts(device()),
      );
    },
    sync(root) {
      if (logic.sub === 'settings') patchSettings(root, logic.settings);
    },
  };
}

// ───────────────────────────── results ─────────────────────────────

export function resultsScreenView(logic: ResultsLogic, version: () => number, device: () => Device): ScreenView {
  return {
    key: () => `${version()}|${device()}`,
    build() {
      const m = logic.model;
      if (!m) return h('section.od-screen.od-results', null, btn('path', 'Path'));
      const v = resultsView(m);
      const tapes = h('span.od-tapes.od-tapes--big');
      for (let i = 0; i < 4; i++) tapes.append(cassette(i, i < v.tapesUsed ? 'on' : 'off'));
      const labels: Record<string, string> = { next: 'Next level', replay: 'Replay', path: 'Path', loadout: 'Loadout' };
      return h(
        'section.od-screen.od-results',
        { 'aria-label': v.title },
        h(
          'div.od-panel.od-results-panel',
          null,
          h('div.od-results-kicker', null, `DEPTH ${v.depth} · ${v.levelName}`),
          h(`h1.od-results-title${v.win ? '' : '.od-results-title--fail'}`, null, v.title),
          h(
            'div.od-results-tapes',
            null,
            tapes,
            h('span', null, h('b', null, String(v.tapesUsed)), ` of ${v.maxTapes} tape${v.maxTapes > 1 ? 's' : ''} used`),
          ),
          v.notes.length ? h('ul.od-notes', null, ...v.notes.map((n) => h('li', null, n))) : null,
          h(
            'div.od-loot',
            null,
            h('h4', null, 'Loot'),
            v.loot.length
              ? h(
                  'ul.od-loot-list',
                  null,
                  ...v.loot.map((g) =>
                    h(
                      'li.od-loot-card',
                      null,
                      h('div.od-item-top', null, h('span.od-tag.od-tag--new', null, 'NEW'), h('span.od-loot-slot', null, g.slot)),
                      h('div.od-item-name', null, g.name),
                      h('p.od-item-effect', null, g.effect),
                      g.lore ? h('p.od-lore', null, g.lore) : null,
                    ),
                  ),
                )
              : h('p.od-muted', null, 'Nothing new this time — this level’s gear is already yours.'),
          ),
          h('nav.od-row.od-results-actions', null, ...logic.menu().entries.map((e, i) => btn(e.id, labels[e.id] ?? e.id, { tone: i === 0 ? 'primary' : undefined }))),
        ),
        prompts(device()),
      );
    },
  };
}

// ───────────────────────────── ending ─────────────────────────────

export function endingView(
  _logic: EndingLogic,
  stats: () => { cleared: number; total: number; gear: number | null },
  device: () => Device,
): ScreenView {
  return {
    key: () => `${JSON.stringify(stats())}|${device()}`,
    build() {
      const s = stats();
      return h(
        'section.od-screen.od-ending',
        { 'aria-label': 'The time machine' },
        h(
          'div.od-ending-card',
          null,
          svgArt(TIME_MACHINE_SVG, 'od-ending-tm'),
          h('div.od-ending-kicker', null, 'THE BOTTOM OF THE DESCENT'),
          h('h1.od-ending-title', null, 'She found it.'),
          h('p.od-ending-text', null, 'Past the last door and the last take: the time machine. What Moxie does with it is her business.'),
          h(
            'p.od-ending-stats',
            null,
            `${s.cleared} / ${s.total} levels cleared`,
            s.gear !== null ? ` · ${s.gear} pieces of gear found` : '',
          ),
          h('nav.od-row', null, btn('path', 'Back to the path', { tone: 'primary' }), btn('title', 'Title', { tone: 'ghost' })),
        ),
        prompts(device()),
      );
    },
  };
}
