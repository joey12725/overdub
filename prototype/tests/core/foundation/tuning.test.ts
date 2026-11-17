import { describe, expect, it } from 'vitest';
import {
  BASE,
  ENEMY_STATS,
  NEUTRAL_MODS,
  neutralMods,
  strikeApproach,
  strikeDamage,
  strikeKnockback,
  strikeStagger,
  swingMomentum,
  TUTORIAL_WALL_THRESHOLD,
} from '../../../src/core/tuning';
import { BASE_MELEE } from '../../helpers/loadout';

const mods = NEUTRAL_MODS;
const run = BASE.runSpeed;

function dmg(swing: 'light' | 'heavy', speed: number, vx: number): number {
  const m = swingMomentum(BASE_MELEE[swing], mods, speed, vx, 0, 0);
  return strikeDamage(m, BASE_MELEE.damageEff, mods.damage);
}

describe('architecture combat targets', () => {
  it('a 1x standing light kills a 1-hit enemy; a 0.5x one does not, even running', () => {
    expect(dmg('light', 1, 0)).toBeGreaterThanOrEqual(ENEMY_STATS.grunt.hp);
    expect(dmg('light', 0.5, 0)).toBe(0);
    expect(dmg('light', 0.5, run)).toBe(0);
  });

  it('a 2x running heavy breaks the tutorial wall; slower or standing heavies do not', () => {
    const m = (speed: number, vx: number): number => swingMomentum(BASE_MELEE.heavy, mods, speed, vx, 0, 0);
    expect(m(2, run)).toBeGreaterThanOrEqual(TUTORIAL_WALL_THRESHOLD);
    expect(m(1, run)).toBeLessThan(TUTORIAL_WALL_THRESHOLD);
    expect(m(2, 0)).toBeLessThan(TUTORIAL_WALL_THRESHOLD);
  });

  it('tape speed is counted once: momentum is linear in speed', () => {
    const m1 = swingMomentum(BASE_MELEE.light, mods, 1, run, 0, 0);
    expect(swingMomentum(BASE_MELEE.light, mods, 2, run, 0, 0)).toBeCloseTo(2 * m1, 12);
    expect(swingMomentum(BASE_MELEE.light, mods, 4, run, 0, 0)).toBeCloseTo(4 * m1, 12);
  });

  it('direction matters (MOM-03): approach is clamped to [-0.5, 1]', () => {
    expect(strikeApproach(run, 0, 0)).toBe(1);
    expect(strikeApproach(2 * run, 0, 0)).toBe(1);
    expect(strikeApproach(-run, 0, 0)).toBe(-0.5);
    expect(strikeApproach(0, run, 0)).toBeCloseTo(0, 12);
    const into = swingMomentum(BASE_MELEE.heavy, mods, 1, run, 0, 0);
    const away = swingMomentum(BASE_MELEE.heavy, mods, 1, -run, 0, 0);
    expect(into).toBeGreaterThan(away);
    expect(away).toBeGreaterThan(0);
  });

  it('knockback divides by mass and is capped; stagger divides by poise; immovables ignore both', () => {
    expect(strikeKnockback(2, 1, 1, 1, 1)).toBe(2);
    expect(strikeKnockback(2, 1, 1, 1, 4)).toBe(0.5);
    expect(strikeKnockback(100, 1, 1, 1, 1)).toBe(BASE.knockbackCap);
    expect(strikeKnockback(100, 1, 1, 2, 1)).toBe(BASE.knockbackCap * 2);
    expect(strikeKnockback(5, 1, 1, 1, ENEMY_STATS.turret.mass)).toBe(0);
    expect(strikeStagger(4, 1, 1, 2)).toBe(2);
    expect(strikeStagger(4, 1, 1, Infinity)).toBe(0);
    expect(strikeDamage(-3, 1, 1)).toBe(0);
  });

  it('the brute takes several standing lights but one 1x running heavy (momentum lesson)', () => {
    expect(dmg('light', 1, 0)).toBeLessThan(ENEMY_STATS.brute.hp);
    expect(dmg('heavy', 1, run)).toBeGreaterThanOrEqual(ENEMY_STATS.brute.hp);
  });
});

describe('base stats', () => {
  it('fit comfortably through 1-tile corridors and spark outruns a 1x runner', () => {
    expect(BASE.actorRadius * 2).toBeLessThan(1);
    expect(BASE.sparkSpeed).toBeGreaterThan(BASE.runSpeed);
    expect(BASE.dodgeIframeStart + BASE.dodgeIframes).toBeLessThanOrEqual(BASE.dodgeTicks);
  });

  it('neutralMods is a fresh identity copy', () => {
    const m = neutralMods();
    m.moveSpeed = 3;
    expect(NEUTRAL_MODS.moveSpeed).toBe(1);
    expect(m.interactRadiusAdd).toBe(0);
    for (const [k, v] of Object.entries(NEUTRAL_MODS)) expect(v).toBe(k.endsWith('Add') ? 0 : 1);
  });
});
