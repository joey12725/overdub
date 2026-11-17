/**
 * Inline SVG icons for the HUD. Every state the HUD shows carries an icon as well as a word and a
 * colour, so no state is ever conveyed by colour alone (NEW-11). Drawn chunky so they survive small
 * sizes and read as inked stickers rather than thin UI glyphs.
 */
import type { IconId } from './model';

const P: Record<IconId, string> = {
  lock: '<rect x="5" y="10.5" width="14" height="10" rx="2" fill="currentColor"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5" fill="none" stroke="currentColor" stroke-width="2.6"/>',
  rec: '<circle cx="12" cy="12" r="7" fill="currentColor"/>',
  arm: '<circle cx="12" cy="12" r="7.5" fill="none" stroke="currentColor" stroke-width="2.6"/><circle cx="12" cy="12" r="3" fill="currentColor"/>',
  empty: '<rect x="4" y="7" width="16" height="10" rx="2" fill="none" stroke="currentColor" stroke-width="2.4" stroke-dasharray="3 2.2"/>',
  none: '<circle cx="12" cy="12" r="8" fill="none" stroke="currentColor" stroke-width="2.4"/><path d="M6.5 17.5l11-11" stroke="currentColor" stroke-width="2.4"/>',
  take: '<path d="M5 4h14v16l-7-4-7 4z" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linejoin="round"/><path d="M12 8v4" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"/><circle cx="12" cy="14.3" r="1.3" fill="currentColor"/>',
  alive: '<path d="M12 20s-7.5-4.4-7.5-10A4.3 4.3 0 0 1 12 7.4 4.3 4.3 0 0 1 19.5 10c0 5.6-7.5 10-7.5 10z" fill="currentColor"/>',
  ghost: '<path d="M5 20V11a7 7 0 0 1 14 0v9l-2.4-2-2.3 2-2.3-2-2.3 2-2.3-2z" fill="currentColor"/><path d="M8.6 10.2l2 2m0-2l-2 2M13.4 10.2l2 2m0-2l-2 2" stroke="#14110f" stroke-width="1.6"/>',
  recGhost: '<path d="M5 20V11a7 7 0 0 1 14 0v9l-2.4-2-2.3 2-2.3-2-2.3 2-2.3-2z" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linejoin="round"/><circle cx="12" cy="11.5" r="2.6" fill="currentColor"/>',
  desync: '<path d="M3 13l4-5 3 7 4-9 3 6 4-3" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/><circle cx="20" cy="18" r="2" fill="currentColor"/>',
  resync: '<circle cx="12" cy="12" r="8" fill="none" stroke="currentColor" stroke-width="2.4"/><path d="M8 12.3l2.7 2.7L16.2 9.4" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>',
  stop: '<rect x="6" y="6" width="12" height="12" rx="1.5" fill="currentColor"/>',
  repeat: '<path d="M5 11V9.5A3.5 3.5 0 0 1 8.5 6H18m-3-3l3 3-3 3M19 13v1.5a3.5 3.5 0 0 1-3.5 3.5H6m3 3l-3-3 3-3" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>',
  reverse: '<path d="M4 8h14m-3-3.5L18.5 8 15 11.5M20 16H6m3 3.5L5.5 16 9 12.5" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>',
  play: '<path d="M7 5l12 7-12 7z" fill="currentColor"/>',
  rewind: '<path d="M17 5L5 12l12 7z" fill="currentColor"/>',
  hold: '<rect x="6" y="5" width="4" height="14" rx="1" fill="currentColor"/><rect x="14" y="5" width="4" height="14" rx="1" fill="currentColor"/>',
  cue: '<path d="M6 5v14" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"/><path d="M9 6l10 6-10 6z" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linejoin="round"/>',
  death: '<path d="M6 6l12 12M18 6L6 18" stroke="currentColor" stroke-width="3.2" stroke-linecap="round"/>',
  survivor: '<circle cx="12" cy="8" r="3.6" fill="currentColor"/><path d="M5 20a7 7 0 0 1 14 0z" fill="currentColor"/>',
  world: '<circle cx="12" cy="12" r="8" fill="none" stroke="currentColor" stroke-width="2.2"/><path d="M4 12h16M12 4c-3 3.5-3 12.5 0 16M12 4c3 3.5 3 12.5 0 16" fill="none" stroke="currentColor" stroke-width="1.8"/>',
};

export function icon(id: IconId, cls = 'odh-ico'): string {
  return `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true" focusable="false">${P[id]}</svg>`;
}
