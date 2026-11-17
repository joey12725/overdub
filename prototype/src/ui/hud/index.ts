/**
 * In-level HUD: four persistent cassette decks and the master beat ruler (UI-01..07, NEW-07..11),
 * plus the per-phase prompts. Driven entirely by SessionView; holds no game state.
 *
 * Clicking a HUD control dispatches a bubbling `HUD_ACTION_EVENT` CustomEvent from `hud.el` with
 * `detail.action: SessionAction`; the mounting UI turns it into a session intent.
 */
import '../tokens.css';
import './hud.css';
import type { ActionKind, SessionView, TapeIndex } from '../../core/types';
import type { MusicPulse } from '../../contracts';
import { DeckEl, type DeckContext } from './deck';
import { Bind, h, prefersReducedMotion } from './dom';
import type { Device } from './model';
import { BriefingCard, CountIn, DecisionPanel, ObjectiveChip, PhaseBanner } from './panels';
import { RulerEl } from './ruler';

export { HUD_ACTION_EVENT, type HudActionDetail } from './dom';

export interface Hud {
  readonly el: HTMLElement;
  update(view: SessionView, pulse: MusicPulse): void;
  deckEvent(tape: TapeIndex, kind: ActionKind | 'death' | 'desync' | 'resync'): void;
  setDevice(device: 'keyboard' | 'gamepad'): void;
  dispose(): void;
}

export function createHud(): Hud {
  const el = h('div', 'odh');
  el.setAttribute('aria-label', 'Cassette decks and master beat ruler');
  const elB = new Bind(el);

  const top = h('div', 'odh-top');
  const objective = new ObjectiveChip();
  const banner = new PhaseBanner();
  top.append(objective.root, banner.root);

  const center = h('div', 'odh-center');
  const briefing = new BriefingCard();
  const countIn = new CountIn();
  const decision = new DecisionPanel();
  center.append(briefing.root, countIn.root, decision.root);

  const dock = h('div', 'odh-dock');
  const deckRow = h('div', 'odh-decks');
  const decks = ([0, 1, 2, 3] as TapeIndex[]).map((i) => new DeckEl(i));
  for (const d of decks) deckRow.append(d.root);
  const ruler = new RulerEl();
  dock.append(deckRow, ruler.root);

  el.append(top, center, dock);

  let device: Device = 'keyboard';
  let lastNow = 0;
  let reduced = prefersReducedMotion();
  let mql: MediaQueryList | null = null;
  const onMotion = (e: MediaQueryListEvent) => {
    reduced = e.matches;
    elB.toggle('odh--reduced', reduced);
  };
  try {
    if (typeof matchMedia === 'function') {
      mql = matchMedia('(prefers-reduced-motion: reduce)');
      mql.addEventListener('change', onMotion);
    }
  } catch {
    mql = null;
  }
  elB.toggle('odh--reduced', reduced);

  // Deck-row column widths only change when the active cassette / phase does.
  let colKey = '';

  return {
    el,

    update(view: SessionView, pulse: MusicPulse): void {
      const now = typeof performance !== 'undefined' ? performance.now() : Date.now();
      const dt = lastNow === 0 ? 0 : Math.max(0, (now - lastNow) / 1000);
      lastNow = now;

      elB.attr('data-phase', view.phase);
      const slim = view.phase === 'cinematic';
      elB.toggle('odh--slim', slim);
      ruler.setSlim(slim);
      elB.style('--active-c', view.active !== null ? `var(--tape-${'abcd'[view.active]})` : 'var(--paper)');

      const ck = `${view.phase}|${view.active}`;
      if (ck !== colKey) {
        colKey = ck;
        const grow = view.phase === 'setup' ? 1.75 : slim ? 1 : 1.18;
        deckRow.style.gridTemplateColumns = [0, 1, 2, 3]
          .map((i) => (view.active === i ? `minmax(0, ${grow}fr)` : 'minmax(0, 1fr)'))
          .join(' ');
      }

      const ctx: DeckContext = {
        phase: view.phase,
        isActive: false,
        beat: view.beat,
        localBars: view.level.bars,
        levelSpeeds: view.level.speeds,
        levelEndModes: view.level.endModes,
        speeds: view.speeds,
        endModes: view.endModes,
        actions: view.actions,
        hint: view.hint,
        device,
        reduced,
        dt,
        beatPulse: pulse.beatPulse,
      };
      for (let i = 0; i < 4; i++) {
        ctx.isActive = view.active === i;
        decks[i].update(view.decks[i], ctx);
      }

      objective.update(view);
      banner.update(view, device);
      countIn.update(view, reduced);
      briefing.update(view, device);
      decision.update(view, device);
      ruler.update(view, pulse, now, reduced);
    },

    deckEvent(tape: TapeIndex, kind: ActionKind | 'death' | 'desync' | 'resync'): void {
      decks[tape]?.flash(kind, reduced);
    },

    setDevice(d: 'keyboard' | 'gamepad'): void {
      device = d;
      elB.attr('data-device', d);
    },

    dispose(): void {
      mql?.removeEventListener('change', onMotion);
      ruler.dispose();
      el.remove();
    },
  };
}
