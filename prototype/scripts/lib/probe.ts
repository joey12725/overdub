/**
 * `probe`: the numbers designers ask for constantly, measured from the running code — never from
 * memory. Movement is measured by driving the real PlayerController down a long empty corridor;
 * swing numbers come from a real recorded swing event fed through the kernel's own formulas
 * (src/core/tuning.ts); timings come from actionTiming; enemy numbers from ENEMY_STATS.
 * Node-free.
 */
import { getEnemyBehaviour } from '../../src/core/index';
import { Grid } from '../../src/core/grid';
import { actionTiming, interactRadius, PlayerController, runSpeed } from '../../src/core/player';
import { ticksPerBeat } from '../../src/core/time';
import { BASE, ENEMY_STATS, strikeDamage, strikeKnockback, strikeStagger, swingMomentum } from '../../src/core/tuning';
import { ALL_SPEEDS, LOCAL_HZ } from '../../src/core/types';
import type { ActionKind, EnemyType, LevelDef, PlayerInput, ResolvedLoadout, TapeEvent, TapeSpeed } from '../../src/core/types';
import { fmt } from './ascii';

const CORRIDOR = 600;

function corridor(): Grid {
  return Grid.parse(['#'.repeat(CORRIDOR), `#${'.'.repeat(CORRIDOR - 2)}#`, '#'.repeat(CORRIDOR)]);
}

function input(moveX: number, press?: ActionKind): PlayerInput {
  const i: PlayerInput = { moveX, moveY: 0, aim: 0, light: false, heavy: false, dodge: false, ranged: false, interact: false, ability: false };
  if (press) i[press] = true;
  return i;
}

/** Tiles covered in `ticks` local ticks of running east from a standstill. */
export function runDistance(loadout: ResolvedLoadout, ticks: number): number {
  const grid = corridor();
  const pc = new PlayerController({ x: 1.5, y: 1.5, facing: 0 });
  let x = 1.5;
  for (let t = 0; t < ticks; t++) x = pc.step(input(1), grid, loadout, 'alive').x;
  return x - 1.5;
}

/** Tiles a self covers in `beats` MASTER beats when its tape runs at `speed`. */
export function runDistanceInBeats(level: Pick<LevelDef, 'bpm'>, loadout: ResolvedLoadout, beats: number, speed: TapeSpeed): { ticks: number; tiles: number } {
  const ticks = Math.floor(beats * ticksPerBeat(level) * speed + 1e-9);
  return { ticks, tiles: runDistance(loadout, ticks) };
}

/** The event a real controller records for a swing, standing or after a run-up. */
function recordedSwing(loadout: ResolvedLoadout, kind: 'light' | 'heavy', running: boolean): TapeEvent {
  const grid = corridor();
  const pc = new PlayerController({ x: 1.5, y: 1.5, facing: 0 });
  if (running) for (let t = 0; t < 90; t++) pc.step(input(1), grid, loadout, 'alive');
  const res = pc.step(input(running ? 1 : 0, kind), grid, loadout, 'alive');
  const ev = res.events.find((e) => e.kind === kind);
  if (!ev) throw new Error(`probe: the controller did not start a ${kind} swing`);
  return ev;
}

export interface SwingNumbers {
  kind: 'light' | 'heavy';
  running: boolean;
  speed: TapeSpeed;
  momentum: number;
  damage: number;
}

export function swingNumbers(loadout: ResolvedLoadout, speeds: readonly TapeSpeed[]): SwingNumbers[] {
  const out: SwingNumbers[] = [];
  for (const kind of ['light', 'heavy'] as const) {
    for (const running of [false, true]) {
      const ev = recordedSwing(loadout, kind, running);
      for (const speed of speeds) {
        const momentum = swingMomentum(loadout.melee[kind], loadout.mods, speed, ev.vx, ev.vy, ev.dir);
        out.push({ kind, running, speed, momentum, damage: strikeDamage(momentum, loadout.melee.damageEff, loadout.mods.damage) });
      }
    }
  }
  return out;
}

function beatsOf(ticks: number, tpb: number, speed: number): string {
  return fmt(ticks / (tpb * speed));
}

export interface ProbeOptions {
  /** A specific "how far in N beats" question. */
  beats?: number;
  speed?: TapeSpeed;
}

export function probeLines(level: LevelDef | null, loadout: ResolvedLoadout, opts: ProbeOptions = {}): string[] {
  const bpm = level?.bpm ?? 120;
  const tempo = { bpm };
  const tpb = ticksPerBeat(tempo);
  const speeds: TapeSpeed[] = level ? [...level.speeds].sort((a, b) => a - b) : [...ALL_SPEEDS];
  const out: string[] = [];
  const gear = Object.values(loadout.loadout).join(', ');
  out.push(`Probe for ${level ? `"${level.id}"` : 'no level'} at ${bpm} bpm (${tpb} local ticks per beat), loadout: ${gear}`);
  out.push('Beats are MASTER beats (the shared world clock). A tape at speed S lives S local beats per master beat.');
  out.push('');

  // ── movement ──
  const top = runSpeed(loadout);
  let toTop = 0;
  {
    const grid = corridor();
    const pc = new PlayerController({ x: 1.5, y: 1.5, facing: 0 });
    while (toTop < 600 && pc.step(input(1), grid, loadout, 'alive').vx < top - 1e-6) toTop++;
    toTop++;
  }
  out.push('RUNNING (from a standstill, straight line)');
  out.push(`  top speed ${fmt(top)} tiles per local second = ${fmt((top * 60) / bpm)} tiles per local beat; reached after ${toTop} ticks; body radius ${BASE.actorRadius} tiles`);
  const beatCols = [0.5, 1, 2, 3, 4, 6, 8];
  out.push(`  tiles covered in N master beats:   ${beatCols.map((b) => `N=${b}`.padStart(7)).join('')}`);
  for (const s of speeds) {
    out.push(`    at ${`${s}x`.padEnd(5)} (${String(tpb * s).padStart(3)} ticks per beat)       ${beatCols.map((b) => fmt(runDistanceInBeats(tempo, loadout, b, s).tiles).padStart(7)).join('')}`);
  }
  if (opts.beats !== undefined) {
    for (const s of opts.speed !== undefined ? [opts.speed] : speeds) {
      const r = runDistanceInBeats(tempo, loadout, opts.beats, s);
      out.push(`  => in ${opts.beats} master beat(s) a ${s}x self runs ${fmt(r.tiles)} tiles (${r.ticks} local ticks)`);
    }
  }
  const dodge = actionTiming('dodge', loadout);
  out.push(`  dodge: ${fmt(BASE.dodgeDistance * loadout.mods.dodgeDistance)} tiles in ${dodge.commit} ticks, invulnerable ticks ${dodge.iframeStart}..${dodge.iframeEnd - 1}, next dodge ${dodge.cooldown} ticks after it starts`);
  out.push(`  interact reach ${fmt(interactRadius(loadout))} tiles from the body centre`);
  out.push('');

  // ── swings ──
  const mel = loadout.melee;
  out.push(`MELEE  (${loadout.loadout.melee}: reach ${mel.reach} tiles from the body centre, arc ${mel.arcDeg} degrees, plus the target's radius)`);
  out.push('  momentum = impact x tape speed x (1 + approach bonus); running straight into the swing is the full bonus,');
  out.push(`  running away halves it. damage = whole points of momentum. Knockback / stagger shown against a grunt (mass ${ENEMY_STATS.grunt.mass}, poise ${ENEMY_STATS.grunt.poise}).`);
  out.push('  swing            speed   momentum   damage   knockback   stagger');
  const swings = swingNumbers(loadout, speeds);
  for (const w of swings) {
    const kb = strikeKnockback(w.momentum, mel.knockbackEff, loadout.mods.knockback, loadout.mods.knockbackCap, ENEMY_STATS.grunt.mass);
    const st = strikeStagger(w.momentum, mel.staggerEff, loadout.mods.stagger, ENEMY_STATS.grunt.poise);
    out.push(`  ${`${w.kind} ${w.running ? 'running ' : 'standing'}`.padEnd(15)}  ${`${w.speed}x`.padEnd(6)}  ${fmt(w.momentum).padStart(8)}   ${String(w.damage).padStart(6)}   ${`${fmt(kb)} t`.padStart(9)}   ${`${fmt(st)} s`.padStart(7)}`);
  }
  out.push(`  knockback is capped at ${fmt(BASE.knockbackCap * loadout.mods.knockbackCap)} tiles and divided by the enemy's mass; stagger (master seconds) by its poise.`);
  if (level) {
    for (const e of level.entities) {
      if (e.kind !== 'breakable' && e.kind !== 'core') continue;
      const need = e.kind === 'breakable' ? e.threshold : e.threshold ?? 1;
      const ok = swings.filter((w) => w.momentum >= need).map((w) => `${w.speed}x ${w.kind} ${w.running ? 'running' : 'standing'}`);
      out.push(`  ${e.kind} "${e.id}" needs momentum ${need}: ${ok.length ? ok.join(', ') : 'NO baseline swing at an offered speed reaches it'}`);
    }
  }
  out.push('');

  // ── action timing ──
  out.push('ACTIONS  (local ticks; the same real time at every speed, so they take 1/speed as long on the master clock)');
  out.push(`  action     commits   effect on tick   active ticks   move while committed   again after   = commit in master beats at ${speeds.map((s) => `${s}x`).join(' / ')}`);
  for (const kind of ['light', 'heavy', 'dodge', 'ranged', 'interact', 'ability'] as const) {
    const t = actionTiming(kind, loadout);
    const active = kind === 'light' || kind === 'heavy' ? `${t.activeStart}..${t.activeEnd - 1}` : '-';
    out.push(
      `  ${kind.padEnd(9)}  ${String(t.commit).padStart(7)}   ${String(t.effect).padStart(14)}   ${active.padStart(12)}   ${`x${t.moveMul}`.padStart(20)}   ${String(t.cooldown).padStart(11)}     ${speeds.map((s) => beatsOf(t.commit, tpb, s)).join(' / ')}`,
    );
  }
  out.push('  "effect on tick": ticks after the press that the hit frame opens / the shot launches. A press made while the body');
  out.push(`  is committed is remembered for ${BASE.inputBufferTicks} ticks, then dropped. 1 local tick = 1/${LOCAL_HZ} s.`);
  const r = loadout.ranged;
  out.push(`  ranged weapon ${loadout.loadout.ranged}: ${r.archetype}, flies ${fmt(r.speed * loadout.mods.projectileSpeed)} tiles per master second (${fmt((r.speed * loadout.mods.projectileSpeed * 60) / bpm)} per beat), range ${r.range} tiles, momentum ${r.impact}${r.turnRate ? ', homing' : ''}`);
  out.push('');

  // ── enemies ──
  out.push('ENEMIES  (speeds per MASTER beat; an enemy acts on its beat grid: beats offset, offset + every, ...)');
  out.push('  type       hp   walk tiles/beat   reach    attacks every   offset   telegraph beats   shot tiles/beat   mass   poise   radius');
  const present = new Set<string>(level ? level.entities.filter((e) => e.kind === 'enemy').map((e) => (e.kind === 'enemy' ? e.type : '')) : []);
  for (const type of Object.keys(ENEMY_STATS) as EnemyType[]) {
    const s = ENEMY_STATS[type];
    let flags = '';
    try {
      const b = getEnemyBehaviour(type);
      flags = `${b.heavyBody ? '  holds heavy plates' : ''}${b.hovering ? '  hovers (ignores low barriers and plates)' : ''}`;
    } catch {
      flags = '  (no behaviour registered)';
    }
    const inf = (v: number): string => (v === Infinity ? 'fixed' : String(v));
    out.push(
      `  ${type.padEnd(9)}  ${String(s.hp).padStart(2)}   ${fmt((s.speed * 60) / bpm).padStart(15)}   ${String(s.reach).padStart(5)}    ${String(s.every).padStart(13)}   ${String(s.offset).padStart(6)}   ${String(s.telegraphBeats).padStart(15)}   ${(s.shotSpeed ? fmt((s.shotSpeed * 60) / bpm) : '-').padStart(15)}   ${inf(s.mass).padStart(4)}   ${inf(s.poise).padStart(5)}   ${String(s.radius).padStart(6)}${present.has(type) ? '  <- in this level' : ''}${flags}`,
    );
  }
  out.push('  One enemy hit kills a self. Enemies ignore dead and desynced selves. Per-enemy "hp" and "beat" in the level file override these.');
  return out;
}
