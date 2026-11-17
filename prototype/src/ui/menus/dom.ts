/** Tiny DOM builders. Text always goes through textContent, never innerHTML. */

type Child = Node | string | number | null | undefined | false;
type Attrs = Record<string, string | number | boolean | null | undefined>;

function append(el: Element, children: Child[]): void {
  for (const c of children) {
    if (c === null || c === undefined || c === false) continue;
    el.append(typeof c === 'string' || typeof c === 'number' ? document.createTextNode(String(c)) : c);
  }
}

function setAttrs(el: Element, attrs: Attrs | undefined): void {
  if (!attrs) return;
  for (const [k, v] of Object.entries(attrs)) {
    if (v === null || v === undefined || v === false) continue;
    el.setAttribute(k, v === true ? '' : String(v));
  }
}

/** `h('div.a.b', { 'data-x': 1 }, child, …)` */
export function h(tag: string, attrs?: Attrs | null, ...children: Child[]): HTMLElement {
  const [name, ...classes] = tag.split('.');
  const el = document.createElement(name || 'div');
  if (classes.length) el.className = classes.join(' ');
  setAttrs(el, attrs ?? undefined);
  append(el, children);
  return el;
}

/**
 * Static SVG artwork. Only ever called with string literals authored in this module tree (no
 * player or save data), so parsing markup is safe here.
 */
export function svgArt(markup: string, className?: string): HTMLElement {
  const wrap = document.createElement('span');
  if (className) wrap.className = className;
  wrap.innerHTML = markup;
  return wrap;
}

/** A small CSS-drawn cassette in a tape's identity colour (pattern overlay when enabled). */
export function cassette(tape: number, state: 'on' | 'off' = 'on', title?: string): HTMLElement {
  return h(`span.od-cass.od-cass--${state}`, { 'data-tape': tape, title: title ?? null, 'aria-hidden': 'true' }, h('i'), h('i'));
}
