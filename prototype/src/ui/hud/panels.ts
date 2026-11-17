/**
 * Phase-specific HUD layers: objective chip, the per-phase banner, the briefing card, the count-in,
 * the recording time-left bar and death banner, and the decision panel.
 */
import { TAPE_NAMES, type Outcome, type SessionAction, type SessionView, type TapeIndex } from '../../core/types';
import { Bind, emitAction, esc, h, promptHtml } from './dom';
import { icon } from './icons';
import { decisionOptions, formatBars, formatSpeed, formatWorldRate, recordingTimeLeft, type Device } from './model';

function tapeVar(i: TapeIndex | null): string {
  return i === null ? 'var(--paper)' : `var(--tape-${TAPE_NAMES[i].toLowerCase()})`;
}

// ───────────────────────────── objective chip ─────────────────────────────

export class ObjectiveChip {
  readonly root = h('div', 'odh-objective');
  private readonly textB: Bind;
  private readonly fillB: Bind;
  private readonly pctB: Bind;
  private readonly survB: Bind;
  private readonly rootB = new Bind(this.root);

  constructor() {
    this.root.innerHTML =
      '<div class="odh-obj-k">OBJECTIVE</div><div class="odh-obj-text"></div>' +
      '<div class="odh-obj-row"><div class="odh-obj-bar"><div class="odh-obj-fill"></div></div><span class="odh-obj-pct"></span></div>' +
      '<div class="odh-obj-surv"></div>';
    this.textB = new Bind(this.root.querySelector('.odh-obj-text') as HTMLElement);
    this.fillB = new Bind(this.root.querySelector('.odh-obj-fill') as HTMLElement);
    this.pctB = new Bind(this.root.querySelector('.odh-obj-pct') as HTMLElement);
    this.survB = new Bind(this.root.querySelector('.odh-obj-surv') as HTMLElement);
  }

  update(view: SessionView): void {
    const o = view.objective;
    this.textB.setText(o.text);
    const p = Math.max(0, Math.min(1, o.complete ? 1 : o.progress));
    this.fillB.style('transform', `scaleX(${p.toFixed(3)})`);
    this.pctB.setHtml(o.complete ? `${icon('resync')}DONE` : `${Math.round(p * 100)}%`);
    this.rootB.toggle('odh-objective--done', o.complete);
    this.survB.setHtml(
      `${icon('survivor')}<b>${o.survivors}</b> ${o.survivors === 1 ? 'self' : 'selves'} alive` +
        `<span class="odh-obj-need">· need 1 at the end</span>`,
    );
  }
}

// ───────────────────────────── top banner (setup / recording / review) ─────────────────────────────

export class PhaseBanner {
  readonly root = h('div', 'odh-banner');
  private readonly rootB = new Bind(this.root);
  private key = '';
  private timeFillB: Bind | null = null;
  private timeTxtB: Bind | null = null;
  private diedB: Bind | null = null;

  constructor() {
    this.root.setAttribute('role', 'status');
    this.root.addEventListener('click', (e) => {
      const b = (e.target as HTMLElement).closest('button');
      if (b && !(b as HTMLButtonElement).disabled && b.dataset.action) emitAction(this.root, b.dataset.action as SessionAction);
    });
  }

  update(view: SessionView, device: Device): void {
    const a = view.active;
    const deck = a !== null ? view.decks[a] : null;
    const key = `${view.phase}|${a}|${device}|${view.actions.join(',')}|${deck?.speed}|${view.level.id}`;
    if (key !== this.key) {
      this.key = key;
      this.build(view, device);
    }
    this.rootB.style('--c', tapeVar(a));
    if (view.phase === 'recording' && deck) {
      const tl = recordingTimeLeft(deck.localProgress, view.level.bars);
      this.timeFillB?.style('transform', `scaleX(${tl.fraction.toFixed(4)})`);
      this.timeTxtB?.setText(tl.text);
      this.timeFillB?.toggle('odh-time-fill--low', tl.fraction < 0.2);
      const died = deck.life === 'recGhost';
      this.diedB?.toggle('odh-died--on', died);
    }
  }

  private build(view: SessionView, device: Device): void {
    this.timeFillB = this.timeTxtB = this.diedB = null;
    const a = view.active;
    const name = a !== null ? TAPE_NAMES[a] : '';
    const deck = a !== null ? view.decks[a] : null;
    const can = (x: SessionAction) => view.actions.includes(x);
    let html = '';
    switch (view.phase) {
      case 'setup': {
        const offered = view.decks.filter((d) => d.status !== 'unavailable').length;
        html = `<div class="odh-banner-pill"><span class="odh-banner-k">TAKE ${a !== null ? a + 1 : '-'} / ${offered}</span><span class="odh-banner-main">SET UP TAPE ${esc(
          name,
        )}</span><span class="odh-banner-sub">every take starts at master beat 0</span></div>`;
        break;
      }
      case 'recording':
        html =
          `<div class="odh-banner-rec"><span class="odh-rec-lamp"></span><span class="odh-banner-main">REC · TAPE ${esc(name)}</span>` +
          `<span class="odh-banner-speed">${esc(formatSpeed(deck?.speed ?? null))}</span></div>` +
          '<div class="odh-time"><div class="odh-time-track"><div class="odh-time-fill"></div></div><span class="odh-time-txt"></span></div>' +
          `<div class="odh-died">${icon('recGhost')}<span><b>YOU DIED</b> — keep playing: this take continues as a ghost</span></div>`;
        break;
      case 'review':
        html =
          `<div class="odh-banner-pill odh-banner-pill--review">${icon('play')}<span class="odh-banner-main">WATCHING THE COMBINED TAKE</span><span class="odh-banner-sub">every tape together, at true master speed</span></div>` +
          `<div class="odh-banner-prompts">${
            can('skip') ? `<button type="button" class="odh-chipbtn" data-action="skip">${promptHtml('skip', device)}</button>` : ''
          }${
            can('endAttempt')
              ? `<button type="button" class="odh-chipbtn odh-chipbtn--warn" data-action="endAttempt">${promptHtml('endAttempt', device)}</button>`
              : ''
          }</div>`;
        break;
      case 'cinematic':
        html = `<div class="odh-banner-pill odh-banner-pill--cine"><span class="odh-banner-main">THE PERFORMANCE</span></div>`;
        break;
      default:
        html = '';
    }
    this.root.innerHTML = html;
    this.rootB.attr('data-phase', view.phase);
    if (view.phase === 'recording') {
      this.timeFillB = new Bind(this.root.querySelector('.odh-time-fill') as HTMLElement);
      this.timeTxtB = new Bind(this.root.querySelector('.odh-time-txt') as HTMLElement);
      this.diedB = new Bind(this.root.querySelector('.odh-died') as HTMLElement);
    }
  }
}

// ───────────────────────────── count-in (UI-04) ─────────────────────────────

export class CountIn {
  readonly root = h('div', 'odh-countin');
  private readonly rootB = new Bind(this.root);
  private readonly nums: HTMLElement[] = [];
  private readonly subB: Bind;
  private readonly recEl: HTMLElement;
  private lastCount = 0;
  private lastPhase = '';
  private anim: Animation | null = null;

  constructor() {
    const row = h('div', 'odh-count-row');
    [5, 6, 7, 8].forEach((n, k) => {
      if (k > 0) row.append(h('span', 'odh-count-dot', '·'));
      const el = h('span', 'odh-count-n', String(n));
      this.nums.push(el);
      row.append(el);
    });
    const sub = h('div', 'odh-count-sub');
    this.recEl = h('div', 'odh-rec-stamp', '<span class="odh-rec-lamp"></span>REC');
    this.root.append(row, sub, this.recEl);
    this.subB = new Bind(sub);
  }

  update(view: SessionView, reduced: boolean): void {
    const counting = view.phase === 'countin';
    this.rootB.toggle('odh-countin--on', counting);
    const a = view.active;
    this.rootB.style('--c', tapeVar(a));
    if (counting) {
      const deck = a !== null ? view.decks[a] : null;
      const rate = deck?.speed ? 1 / deck.speed : 1;
      this.subB.setText(
        `TAPE ${a !== null ? TAPE_NAMES[a] : ''} · ${formatSpeed(deck?.speed ?? null)} · ${formatWorldRate(rate)} while you record`,
      );
      if (view.count !== this.lastCount) {
        this.nums.forEach((el, k) => {
          const n = 5 + k;
          el.classList.toggle('odh-count-n--on', n === view.count);
          el.classList.toggle('odh-count-n--past', view.count !== 0 && n < view.count);
        });
        const on = this.nums[view.count - 5];
        if (on && !reduced && typeof on.animate === 'function') {
          on.animate(
            [
              { transform: 'scale(1.7) rotate(-8deg)', opacity: 0.2 },
              { transform: 'scale(0.92) rotate(2deg)', opacity: 1, offset: 0.4 },
              { transform: 'scale(1) rotate(-3deg)', opacity: 1 },
            ],
            { duration: 260, easing: 'cubic-bezier(0.2, 0.8, 0.2, 1)' },
          );
        }
      }
    }
    // "REC" stamp the moment the count-in hands over to the take.
    if (view.phase === 'recording' && this.lastPhase === 'countin' && typeof this.recEl.animate === 'function') {
      this.anim?.cancel();
      this.anim = this.recEl.animate(
        reduced
          ? [{ opacity: 1 }, { opacity: 1, offset: 0.7 }, { opacity: 0 }]
          : [
              { opacity: 0, transform: 'translate(-50%, -50%) scale(2.2) rotate(-10deg)' },
              { opacity: 1, transform: 'translate(-50%, -50%) scale(1) rotate(-6deg)', offset: 0.18 },
              { opacity: 1, transform: 'translate(-50%, -50%) scale(1) rotate(-6deg)', offset: 0.7 },
              { opacity: 0, transform: 'translate(-50%, -50%) scale(1.15) rotate(-6deg)' },
            ],
        { duration: 900, easing: 'ease-out', fill: 'forwards' },
      );
    }
    this.lastCount = counting ? view.count : 0;
    this.lastPhase = view.phase;
  }
}

// ───────────────────────────── briefing card ─────────────────────────────

export class BriefingCard {
  readonly root = h('div', 'odh-card odh-briefing');
  private key = '';

  constructor() {
    this.root.addEventListener('click', (e) => {
      const b = (e.target as HTMLElement).closest('button');
      if (b && !(b as HTMLButtonElement).disabled) emitAction(this.root, 'start');
    });
  }

  update(view: SessionView, device: Device): void {
    const on = view.phase === 'briefing';
    this.root.classList.toggle('odh-on', on);
    if (!on) return;
    const L = view.level;
    const key = `${L.id}|${device}|${view.actions.join(',')}`;
    if (key === this.key) return;
    this.key = key;
    const speeds = [...L.speeds].sort((x, y) => x - y).map(formatSpeed).join(' / ');
    this.root.innerHTML =
      `<div class="odh-card-tag">LEVEL ${String(L.index + 1).padStart(2, '0')}</div>` +
      `<h1 class="odh-card-title">${esc(L.name)}</h1>` +
      `<div class="odh-card-tagline">${esc(L.tagline)}</div>` +
      (L.briefing.length ? `<ul class="odh-card-lines">${L.briefing.map((l) => `<li>${esc(l)}</li>`).join('')}</ul>` : '') +
      `<div class="odh-card-facts">` +
      `<span><b>${esc(L.objective.text)}</b></span>` +
      `<span>${L.maxTapes} ${L.maxTapes === 1 ? 'cassette' : 'cassettes'}</span>` +
      `<span>speeds ${esc(speeds)}</span>` +
      `<span>${esc(formatBars(L.bars))} local bars per take</span>` +
      `</div>` +
      `<button type="button" class="odh-bigbtn"${view.actions.includes('start') ? '' : ' disabled'}>${promptHtml('start', device)}</button>`;
  }
}

// ───────────────────────────── decision panel (REC-04, REC-05, REC-07) ─────────────────────────────

function verdict(outcome: Outcome | null): { title: string; tone: string; sub: string } {
  if (!outcome) return { title: 'TAKE RECORDED', tone: 'neutral', sub: 'decide what happens to this take' };
  if (outcome.win) return { title: 'THE COMBINED RUN WORKS', tone: 'win', sub: 'objective complete with a survivor at the end' };
  if (outcome.reason === 'noSurvivor')
    return { title: 'NO SURVIVOR AT THE END', tone: 'fail', sub: 'at least one self must be alive when the horizon ends' };
  return { title: 'OBJECTIVE NOT COMPLETE', tone: 'fail', sub: 'the combined run never finished the job' };
}

export class DecisionPanel {
  readonly root = h('div', 'odh-card odh-decision');
  private key = '';

  constructor() {
    this.root.addEventListener('click', (e) => {
      const b = (e.target as HTMLElement).closest('button');
      if (b && !(b as HTMLButtonElement).disabled && b.dataset.action) emitAction(this.root, b.dataset.action as SessionAction);
    });
  }

  update(view: SessionView, device: Device): void {
    const on = view.phase === 'decision';
    this.root.classList.toggle('odh-on', on);
    if (!on) return;
    const o = view.outcome;
    const key = `${view.actions.join(',')}|${device}|${view.active}|${o ? `${o.win}${o.reason}${o.notes.join('\n')}${o.survivors.join()}` : '-'}`;
    if (key === this.key) return;
    this.key = key;
    const v = verdict(o);
    this.root.style.setProperty('--c', tapeVar(view.active));
    const opts = decisionOptions(view.actions, view.active);
    const survivors = o
      ? `<div class="odh-dec-surv">${icon('survivor')}${
          o.survivors.length ? `survivors: ${o.survivors.map((t) => `<b class="odh-t${t}">${TAPE_NAMES[t]}</b>`).join(' ')}` : 'no survivors'
        }</div>`
      : '';
    this.root.innerHTML =
      `<div class="odh-dec-head odh-dec-head--${v.tone}"><span class="odh-dec-title">${esc(v.title)}</span><span class="odh-dec-sub">${esc(
        v.sub,
      )}</span></div>` +
      survivors +
      (o && o.notes.length ? `<ul class="odh-dec-notes">${o.notes.map((n) => `<li>${esc(n)}</li>`).join('')}</ul>` : '') +
      `<div class="odh-dec-opts">${opts
        .map(
          (op) =>
            `<button type="button" class="odh-dec-opt odh-dec-opt--${op.tone}" data-action="${op.action}"${
              op.enabled ? '' : ' disabled'
            }><span class="odh-dec-opt-top">${promptHtml(op.action, device, false)}<span class="odh-dec-opt-title">${esc(
              op.title,
            )}</span></span><span class="odh-dec-opt-detail">${esc(op.detail)}</span></button>`,
        )
        .join('')}</div>`;
  }
}
