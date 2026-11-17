/**
 * Tiny DOM helpers. update() runs every frame, so every write goes through a cache that skips the
 * DOM entirely when the value has not changed.
 */
import type { SessionAction } from '../../core/types';
import { promptFor, type Device } from './model';

/** Fired (bubbling) from the HUD root when the player clicks a HUD control. detail: { action }. */
export const HUD_ACTION_EVENT = 'overdub:hud-action';

export interface HudActionDetail {
  action: SessionAction;
}

export function h<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  cls?: string,
  html?: string,
): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag);
  if (cls) el.className = cls;
  if (html !== undefined) el.innerHTML = html;
  return el;
}

export function esc(s: string): string {
  return s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
}

/** Write-through cache for one element's text / html / class toggles / style properties. */
export class Bind {
  private text: string | null = null;
  private html: string | null = null;
  private readonly flags = new Map<string, boolean>();
  private readonly props = new Map<string, string>();
  private readonly attrs = new Map<string, string>();
  constructor(readonly el: HTMLElement | SVGElement) {}

  setText(s: string): void {
    if (this.text === s) return;
    this.text = s;
    this.html = null;
    this.el.textContent = s;
  }

  setHtml(s: string): void {
    if (this.html === s) return;
    this.html = s;
    this.text = null;
    this.el.innerHTML = s;
  }

  toggle(cls: string, on: boolean): void {
    if (this.flags.get(cls) === on) return;
    this.flags.set(cls, on);
    this.el.classList.toggle(cls, on);
  }

  style(prop: string, value: string): void {
    if (this.props.get(prop) === value) return;
    this.props.set(prop, value);
    (this.el as HTMLElement).style.setProperty(prop, value);
  }

  attr(name: string, value: string): void {
    if (this.attrs.get(name) === value) return;
    this.attrs.set(name, value);
    this.el.setAttribute(name, value);
  }
}

export function emitAction(from: HTMLElement, action: SessionAction): void {
  from.dispatchEvent(
    new CustomEvent<HudActionDetail>(HUD_ACTION_EVENT, { detail: { action }, bubbles: true, composed: true }),
  );
}

/** Keycap / face-button glyph for an action on the current device. */
export function promptHtml(action: SessionAction, device: Device, withLabel = true, labelOverride?: string): string {
  const p = promptFor(action, device);
  const cap = `<kbd class="odh-cap odh-cap--${p.binding.style}">${esc(p.binding.key)}</kbd>`;
  if (!withLabel) return cap;
  return `<span class="odh-prompt">${cap}<span class="odh-prompt-label">${esc(labelOverride ?? p.label)}</span></span>`;
}

export function prefersReducedMotion(): boolean {
  try {
    return typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;
  } catch {
    return false;
  }
}
