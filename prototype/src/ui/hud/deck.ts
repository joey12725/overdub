/**
 * One cassette deck (UI-06, UI-07, NEW-07, NEW-08, NEW-11): an illustrated cassette with spinning
 * reels, a big speed readout, a master-bar span scale, status, end behaviour and the self's run state.
 * During 'setup' the active deck grows a control surface (UI-05, NEW-10).
 */
import {
  TAPE_NAMES,
  type ActionKind,
  type DeckView,
  type EndMode,
  type SessionAction,
  type SessionPhase,
  type TapeIndex,
  type TapeSpeed,
} from '../../core/types';
import { Bind, emitAction, esc, h, promptHtml } from './dom';
import { icon } from './icons';
import {
  deckPresentation,
  endModeInfo,
  formatBars,
  formatSpeed,
  reelSpin,
  spanCopy,
  spanScaleFill,
  speedConsequence,
  tapePackRadii,
  transportBadge,
  type Badge,
  type Device,
} from './model';

export interface DeckContext {
  phase: SessionPhase;
  isActive: boolean;
  beat: number;
  localBars: number;
  /** Speeds the LEVEL offers (span scale reference) and the speeds/end modes selectable right now. */
  levelSpeeds: readonly TapeSpeed[];
  levelEndModes: readonly EndMode[];
  speeds: readonly TapeSpeed[];
  endModes: readonly EndMode[];
  actions: readonly SessionAction[];
  hint: string | null;
  device: Device;
  reduced: boolean;
  /** Seconds since the previous update, for reel integration. */
  dt: number;
  beatPulse: number;
}

const REEL_L = { x: 44, y: 30 };
const REEL_R = { x: 116, y: 30 };
const HUB_R = 9;
const PACK_FULL = 21.5;

function reelHub(cx: number, cy: number, cls: string): string {
  let teeth = '';
  for (let k = 0; k < 6; k++) {
    teeth += `<rect x="${cx - 1.5}" y="${cy - HUB_R + 0.6}" width="3" height="3.4" rx="0.6" transform="rotate(${k * 60} ${cx} ${cy})"/>`;
  }
  return (
    `<g class="odh-hub ${cls}">` +
    `<circle cx="${cx}" cy="${cy}" r="${HUB_R}" class="odh-hub-ring"/>` +
    `<circle cx="${cx}" cy="${cy}" r="${HUB_R - 4}" class="odh-hub-hole"/>` +
    `<g class="odh-hub-teeth">${teeth}</g>` +
    `<path d="M${cx} ${cy - HUB_R - 6}v4" class="odh-hub-spoke"/>` +
    `</g>`
  );
}

const REEL_SVG =
  '<svg class="odh-reels" viewBox="0 0 160 60" aria-hidden="true">' +
  '<rect class="odh-win" x="6" y="5" width="148" height="50" rx="11"/>' +
  '<path class="odh-tape-run" d=""/>' +
  `<circle class="odh-pack odh-pack-l" cx="${REEL_L.x}" cy="${REEL_L.y}" r="${PACK_FULL}"/>` +
  `<circle class="odh-pack odh-pack-r" cx="${REEL_R.x}" cy="${REEL_R.y}" r="${HUB_R}"/>` +
  reelHub(REEL_L.x, REEL_L.y, 'odh-hub-l') +
  reelHub(REEL_R.x, REEL_R.y, 'odh-hub-r') +
  '<g class="odh-dir" transform="translate(80 30)"><path d="M-9 -6l6 6-6 6M1 -6l6 6-6 6"/></g>' +
  '<rect class="odh-win-glare" x="12" y="8" width="136" height="7" rx="3.5"/>' +
  '</svg>';

const FLASH_TEXT: Record<ActionKind | 'death' | 'desync' | 'resync', string> = {
  light: 'LIGHT',
  heavy: 'HEAVY!',
  dodge: 'DODGE',
  ranged: 'FIRE',
  interact: 'SWITCH',
  ability: 'ABILITY',
  death: '✕ DOWN',
  desync: 'DESYNC',
  resync: 'RESYNC',
};

function badgeHtml(b: Badge, extraCls = ''): string {
  return `<span class="odh-badge odh-tone-${b.tone} ${extraCls}">${icon(b.icon)}<span>${esc(b.label)}</span></span>`;
}

export class DeckEl {
  readonly root: HTMLElement;
  private readonly rootB: Bind;
  private readonly setupEl: HTMLElement;
  private readonly statusB: Bind;
  private readonly speedB: Bind;
  private readonly speedValEl: HTMLElement;
  private readonly spanFillB: Bind;
  private readonly spanTrackB: Bind;
  private readonly spanTxtB: Bind;
  private readonly stateB: Bind;
  private readonly endB: Bind;
  private readonly transportB: Bind;
  private readonly flashEl: HTMLElement;
  private readonly flashB: Bind;
  private readonly hubL: SVGGElement;
  private readonly hubR: SVGGElement;
  private readonly packL: SVGCircleElement;
  private readonly packR: SVGCircleElement;
  private readonly tapeRun: SVGPathElement;
  private readonly dirB: Bind;
  private readonly glowB: Bind;

  private angle = 0;
  private lastHubDeg = NaN;
  private lastProgress = NaN;
  private lastSpeed: TapeSpeed | null | undefined = undefined;
  private setupKey = '';
  private flashAnim: Animation | null = null;
  private popAnim: Animation | null = null;
  private selected: { speed: TapeSpeed | null; speeds: readonly TapeSpeed[] } = { speed: null, speeds: [] };

  constructor(readonly index: TapeIndex) {
    const name = TAPE_NAMES[index];
    this.root = h('div', `odh-deck odh-deck--${index}`);
    this.root.dataset.tape = String(index);
    this.root.style.setProperty('--c', `var(--tape-${name.toLowerCase()})`);
    this.root.setAttribute('role', 'group');
    this.root.setAttribute('aria-label', `Cassette ${name}`);
    this.rootB = new Bind(this.root);

    this.setupEl = h('div', 'odh-setup');
    this.setupEl.addEventListener('click', (e) => this.onSetupClick(e));

    const shell = h('div', 'odh-shell');
    shell.innerHTML =
      '<span class="odh-screw odh-screw--tl"></span><span class="odh-screw odh-screw--tr"></span>' +
      '<span class="odh-screw odh-screw--bl"></span><span class="odh-screw odh-screw--br"></span>' +
      '<div class="odh-glow"></div>' +
      `<div class="odh-label"><span class="odh-letter">${name}</span><span class="odh-label-title">CASSETTE ${name}</span><span class="odh-status"></span></div>` +
      `<div class="odh-mid">${REEL_SVG}<div class="odh-speed"><span class="odh-speed-val">--</span><span class="odh-speed-cap">TAPE SPEED</span></div></div>` +
      '<div class="odh-span"><div class="odh-span-track"><div class="odh-span-fill"></div></div><div class="odh-span-txt"></div></div>' +
      '<div class="odh-foot"><span class="odh-state"></span><span class="odh-end"></span><span class="odh-transport"></span></div>' +
      '<div class="odh-flash"></div>';
    this.root.append(this.setupEl, shell);

    const q = <T extends Element>(sel: string): T => shell.querySelector(sel) as T;
    this.statusB = new Bind(q('.odh-status'));
    this.speedB = new Bind(q('.odh-speed'));
    this.speedValEl = q('.odh-speed-val');
    this.spanFillB = new Bind(q('.odh-span-fill'));
    this.spanTrackB = new Bind(q('.odh-span-track'));
    this.spanTxtB = new Bind(q('.odh-span-txt'));
    this.stateB = new Bind(q('.odh-state'));
    this.endB = new Bind(q('.odh-end'));
    this.transportB = new Bind(q('.odh-transport'));
    this.flashEl = q('.odh-flash');
    this.flashB = new Bind(this.flashEl);
    this.hubL = q('.odh-hub-l');
    this.hubR = q('.odh-hub-r');
    this.packL = q('.odh-pack-l');
    this.packR = q('.odh-pack-r');
    this.tapeRun = q('.odh-tape-run');
    this.dirB = new Bind(q('.odh-dir'));
    this.glowB = new Bind(q('.odh-glow'));
  }

  update(d: DeckView, ctx: DeckContext): void {
    const settingUp = ctx.phase === 'setup' && ctx.isActive;
    this.rootB.toggle('odh-deck--active', ctx.isActive);
    this.rootB.toggle('odh-deck--setup', settingUp);
    this.rootB.attr('data-status', d.status);
    this.rootB.attr('data-life', d.life ?? 'none');
    this.rootB.attr('data-synced', d.synced ? '1' : '0');

    // Status + run state (NEW-08, NEW-11): icon + word + tone, never colour alone.
    const pres = deckPresentation(d.status, d.life, d.synced);
    this.statusB.setHtml(
      (d.status === 'recording' ? '<span class="odh-rec-lamp"></span>' : '') + badgeHtml(pres.status, 'odh-badge--status'),
    );
    this.stateB.setHtml(pres.state ? badgeHtml(pres.state) : '');

    // Speed readout (UI-07). Pops when it changes so the switch is felt (NEW-10).
    const speedText = formatSpeed(d.speed);
    if (this.speedValEl.textContent !== speedText) this.speedValEl.textContent = speedText;
    this.speedB.toggle('odh-speed--none', d.speed === null);
    if (this.lastSpeed !== undefined && this.lastSpeed !== d.speed && d.speed !== null && !ctx.reduced) {
      this.popAnim?.cancel();
      this.popAnim = this.speedValEl.animate(
        [
          { transform: 'scale(1.45) rotate(-6deg)', filter: 'brightness(1.6)' },
          { transform: 'scale(0.94) rotate(1deg)', offset: 0.55 },
          { transform: 'scale(1) rotate(0deg)', filter: 'none' },
        ],
        { duration: 320, easing: 'cubic-bezier(0.2, 0.8, 0.2, 1)' },
      );
    }
    this.lastSpeed = d.speed;

    // Span scale: one pass of this tape in master bars, against the slowest offered speed (UI-07).
    if (d.speed !== null && d.status !== 'unavailable') {
      const slowest = Math.min(...(ctx.levelSpeeds.length ? ctx.levelSpeeds : [d.speed]));
      const maxBars = ctx.localBars / slowest;
      const fill = spanScaleFill(d.speed, ctx.levelSpeeds);
      this.spanFillB.style('transform', `scaleX(${fill.toFixed(4)})`);
      this.spanTrackB.style('--notches', String(Math.max(1, Math.round(maxBars))));
      this.spanTxtB.setHtml(
        `<b>1 pass</b> = ${esc(formatBars(d.spanBars))} master ${d.spanBars === 1 ? 'bar' : 'bars'}` +
          `<span class="odh-span-local"> · ${esc(formatBars(ctx.localBars))} local</span>`,
      );
      this.spanTrackB.toggle('odh-span-track--off', false);
    } else {
      this.spanFillB.style('transform', 'scaleX(0)');
      this.spanTrackB.toggle('odh-span-track--off', true);
      this.spanTxtB.setHtml(d.status === 'unavailable' ? 'not offered here' : 'speed not chosen yet');
    }

    // End behaviour: only worth a chip when the level offers a choice.
    if (d.endMode !== null && ctx.levelEndModes.length > 1 && d.status !== 'unavailable') {
      const em = endModeInfo(d.endMode);
      this.endB.setHtml(badgeHtml(em, 'odh-badge--end'));
    } else {
      this.endB.setHtml('');
    }
    const tb = transportBadge(d, ctx.beat);
    this.transportB.setHtml(tb && ctx.phase !== 'setup' ? badgeHtml(tb, 'odh-badge--transport') : '');

    this.updateReels(d, ctx, settingUp);

    // Beat pulse lives only on the active deck's halo so the rest of the HUD stays still.
    if (ctx.isActive && !ctx.reduced) {
      this.glowB.style('opacity', (0.55 + 0.45 * ctx.beatPulse).toFixed(2));
    } else {
      this.glowB.style('opacity', ctx.isActive ? '0.8' : '0');
    }

    if (settingUp) this.renderSetup(d, ctx);
    else if (this.setupKey !== '') {
      this.setupKey = '';
      this.setupEl.innerHTML = '';
    }
  }

  private updateReels(d: DeckView, ctx: DeckContext, settingUp: boolean): void {
    // In setup the armed reels preview the chosen speed so the reel behaviour changes with the
    // readout (NEW-10); otherwise they follow the deck's real transport.
    let rps = settingUp && d.speed !== null ? reelSpin(d.speed, 1) : reelSpin(d.reelRate, d.transport);
    if (ctx.reduced) rps *= 0.4;
    this.angle = (this.angle + rps * 360 * Math.min(ctx.dt, 0.1)) % 360;
    const deg = Math.round(this.angle * 10) / 10;
    if (deg !== this.lastHubDeg) {
      this.lastHubDeg = deg;
      this.hubL.setAttribute('transform', `rotate(${deg} ${REEL_L.x} ${REEL_L.y})`);
      this.hubR.setAttribute('transform', `rotate(${deg} ${REEL_R.x} ${REEL_R.y})`);
    }
    const dir = settingUp && d.speed !== null ? 1 : d.transport;
    this.dirB.attr('data-dir', String(dir));

    const p = Math.round(Math.max(0, Math.min(1, d.localProgress)) * 400) / 400;
    if (p !== this.lastProgress) {
      this.lastProgress = p;
      const [rl, rr] = tapePackRadii(p, HUB_R, PACK_FULL);
      this.packL.setAttribute('r', rl.toFixed(2));
      this.packR.setAttribute('r', rr.toFixed(2));
      this.tapeRun.setAttribute(
        'd',
        `M${REEL_L.x - rl * 0.6} ${REEL_L.y + rl * 0.8}L64 53H96L${REEL_R.x + rr * 0.6} ${REEL_R.y + rr * 0.8}`,
      );
    }
  }

  private renderSetup(d: DeckView, ctx: DeckContext): void {
    const speeds = [...ctx.speeds].sort((a, b) => a - b);
    const key = [
      d.speed,
      d.endMode,
      speeds.join(','),
      ctx.endModes.join(','),
      ctx.device,
      ctx.hint ?? '',
      ctx.actions.join(','),
      ctx.localBars,
    ].join('|');
    this.selected = { speed: d.speed, speeds };
    if (key === this.setupKey) return;
    this.setupKey = key;
    const name = TAPE_NAMES[this.index];
    const can = (a: SessionAction) => ctx.actions.includes(a);

    const speedBtns = speeds
      .map(
        (s) =>
          `<button type="button" class="odh-seg${s === d.speed ? ' odh-seg--on' : ''}" data-speed="${s}"${
            can('speedUp') || can('speedDown') ? '' : ' disabled'
          } aria-pressed="${s === d.speed}">${formatSpeed(s)}</button>`,
      )
      .join('');
    const endBtns =
      ctx.endModes.length > 1
        ? `<div class="odh-setup-row odh-setup-row--end"><span class="odh-setup-k">AT THE END</span>${promptHtml(
            'cycleEndMode',
            ctx.device,
            false,
          )}<div class="odh-segs">${ctx.endModes
            .map((m) => {
              const info = endModeInfo(m);
              return `<button type="button" class="odh-seg odh-seg--end${m === d.endMode ? ' odh-seg--on' : ''}" data-end="${m}"${
                can('cycleEndMode') ? '' : ' disabled'
              } aria-pressed="${m === d.endMode}">${icon(info.icon)}${info.label}</button>`;
            })
            .join('')}</div></div>` +
          (d.endMode ? `<div class="odh-setup-copy odh-setup-copy--end">${esc(endModeInfo(d.endMode).copy)}</div>` : '')
        : '';

    this.setupEl.innerHTML =
      `<div class="odh-setup-head"><span class="odh-setup-tag">SET UP</span><span class="odh-setup-name">TAPE ${name}</span></div>` +
      `<div class="odh-setup-row"><span class="odh-setup-k">SPEED</span>${promptHtml('speedDown', ctx.device, false)}<div class="odh-segs">${speedBtns}</div>${promptHtml(
        'speedUp',
        ctx.device,
        false,
      )}</div>` +
      (d.speed !== null
        ? `<div class="odh-setup-copy">${esc(speedConsequence(d.speed))}</div>` +
          `<div class="odh-setup-conv">${esc(spanCopy(ctx.localBars, d.speed))} per pass</div>`
        : '') +
      endBtns +
      (ctx.hint ? `<div class="odh-setup-hint">${esc(ctx.hint)}</div>` : '') +
      `<button type="button" class="odh-recbtn" data-action="record"${can('record') ? '' : ' disabled'}><span class="odh-recbtn-dot"></span><span class="odh-recbtn-txt">RECORD</span>${promptHtml(
        'record',
        ctx.device,
        false,
      )}</button>`;
  }

  private onSetupClick(e: Event): void {
    const t = (e.target as HTMLElement).closest('button');
    if (!t || (t as HTMLButtonElement).disabled) return;
    if (t.dataset.action === 'record') {
      emitAction(this.root, 'record');
      return;
    }
    if (t.dataset.speed) {
      const target = Number(t.dataset.speed) as TapeSpeed;
      const { speed, speeds } = this.selected;
      const from = speed === null ? -1 : speeds.indexOf(speed);
      const to = speeds.indexOf(target);
      if (from < 0 || to < 0) return;
      // The session only knows up/down, so a direct pick is expressed as the steps to reach it.
      const act: SessionAction = to > from ? 'speedUp' : 'speedDown';
      for (let i = 0; i < Math.abs(to - from); i++) emitAction(this.root, act);
      return;
    }
    if (t.dataset.end && !t.classList.contains('odh-seg--on')) {
      const buttons = Array.from(this.setupEl.querySelectorAll<HTMLButtonElement>('[data-end]'));
      const cur = buttons.findIndex((b) => b.classList.contains('odh-seg--on'));
      const to = buttons.indexOf(t as HTMLButtonElement);
      const steps = cur < 0 ? 1 : (to - cur + buttons.length) % buttons.length;
      for (let i = 0; i < steps; i++) emitAction(this.root, 'cycleEndMode');
    }
  }

  flash(kind: ActionKind | 'death' | 'desync' | 'resync', reduced: boolean): void {
    this.flashB.attr('data-kind', kind);
    this.flashEl.textContent = FLASH_TEXT[kind];
    this.flashAnim?.cancel();
    if (typeof this.flashEl.animate !== 'function') return;
    const big = kind === 'death' || kind === 'desync' || kind === 'resync' || kind === 'heavy';
    this.flashAnim = this.flashEl.animate(
      reduced
        ? [{ opacity: 1 }, { opacity: 1, offset: 0.6 }, { opacity: 0 }]
        : [
            { opacity: 1, transform: `scale(${big ? 1.25 : 1.1}) rotate(-4deg)` },
            { opacity: 1, transform: 'scale(1) rotate(-2deg)', offset: 0.35 },
            { opacity: 0, transform: 'scale(1) rotate(-2deg)' },
          ],
      { duration: big ? 900 : 480, easing: 'ease-out', fill: 'forwards' },
    );
  }
}
