/**
 * DOM-free text formatting for gear, weapons and levels. Everything a player reads about an item's
 * mechanics is produced here so it can be tested in node (APPAREL-03, WEAPON-01..04).
 */
import {
  GEAR_SLOTS,
  LOCAL_HZ,
  type AbilityId,
  type EndMode,
  type GearItem,
  type GearSlot,
  type MeleeSwingDef,
  type MeleeWeaponDef,
  type RangedArchetype,
  type RangedWeaponDef,
  type StatMods,
  type TapeSpeed,
  type Theme,
} from '../../core/types';

// ───────────────────────────── slots ─────────────────────────────

export interface SlotLabel {
  /** Big label on the slot tile. APPAREL-03 requires these categories be plainly identified. */
  title: string;
  /** What kind of thing goes there. */
  kind: string;
  /** Short code for compact places (paper-doll pins). */
  short: string;
  /** Which mechanics this category tends to touch (APPAREL-01 category descriptions). */
  touches: string;
}

const SLOT_LABELS: Record<GearSlot, SlotLabel> = {
  helmet: {
    title: 'HELMET / HEADGEAR',
    kind: 'Headgear',
    short: 'HEAD',
    touches: 'Enemy awareness, hazard protection, beat readability',
  },
  top: {
    title: 'TOP',
    kind: 'Shirt / top / jacket',
    short: 'TOP',
    touches: 'Impact, interaction reach, desync behaviour',
  },
  pants: {
    title: 'PANTS',
    kind: 'Legwear',
    short: 'LEGS',
    touches: 'Acceleration, control, momentum retention, dodge recovery',
  },
  shoes: {
    title: 'SHOES',
    kind: 'Footwear',
    short: 'FEET',
    touches: 'Speed, traction, dodge character, momentum transfer',
  },
  melee: {
    title: 'MELEE',
    kind: 'Melee weapon',
    short: 'MEL',
    touches: 'Reach, arc, swing timing, knockback and stagger',
  },
  ranged: {
    title: 'RANGED',
    kind: 'Ranged weapon',
    short: 'RNG',
    touches: 'Projectile behaviour, speed, range, penetration',
  },
};

export function slotLabel(slot: GearSlot): SlotLabel {
  return SLOT_LABELS[slot];
}

export function allSlotLabels(): { slot: GearSlot; label: SlotLabel }[] {
  return GEAR_SLOTS.map((slot) => ({ slot, label: SLOT_LABELS[slot] }));
}

// ───────────────────────────── numbers ─────────────────────────────

/** Trim trailing zeros: 1.50 → "1.5", 2.00 → "2". */
export function num(n: number, digits = 2): string {
  if (!Number.isFinite(n)) return '—';
  const s = n.toFixed(digits);
  return s.includes('.') ? s.replace(/\.?0+$/, '') : s;
}

/** Local ticks → seconds at 1× (ticks are recorded at LOCAL_HZ in wall time; TIME-02). */
export function ticksToSeconds(ticks: number): string {
  return `${num(ticks / LOCAL_HZ, 2)} s`;
}

export function speedLabel(s: TapeSpeed): string {
  return s === 0.5 ? '½×' : `${s}×`;
}

const END_MODE_LABEL: Record<EndMode, string> = { stop: 'Stop', repeat: 'Repeat', reverse: 'Reverse' };
export function endModeLabel(m: EndMode): string {
  return END_MODE_LABEL[m];
}

const THEME_LABEL: Record<Theme, string> = {
  upper: 'Upper ruins',
  mid: 'Retrofit layer',
  lower: 'Inscribed depths',
  core: 'The core',
};
export function themeLabel(t: Theme): string {
  return THEME_LABEL[t];
}

/** Percent delta for multipliers: 1.1 → "+10%", 0.85 → "−15%". */
export function pct(mul: number): string {
  const d = Math.round((mul - 1) * 100);
  if (d === 0) return '±0%';
  return d > 0 ? `+${d}%` : `−${Math.abs(d)}%`;
}

// ───────────────────────────── stat mods & abilities ─────────────────────────────

interface ModMeta {
  label: string;
  /** Lower values are better for the player (cooldowns). */
  lowerIsBetter?: boolean;
  /** Additive mod measured in tiles. */
  additiveUnit?: string;
}

const MOD_META: Record<keyof StatMods, ModMeta> = {
  moveSpeed: { label: 'Run speed' },
  accel: { label: 'Acceleration' },
  momentumRetention: { label: 'Momentum kept on turns' },
  dodgeDistance: { label: 'Dodge distance' },
  dodgeIframes: { label: 'Dodge invulnerability' },
  dodgeCooldown: { label: 'Dodge cooldown', lowerIsBetter: true },
  meleeImpact: { label: 'Melee impact' },
  damage: { label: 'Damage' },
  knockback: { label: 'Knockback' },
  knockbackCap: { label: 'Max knockback' },
  stagger: { label: 'Stagger' },
  approachBonus: { label: 'Running-strike bonus' },
  sparkSpeed: { label: 'Recovery spark speed' },
  interactRadiusAdd: { label: 'Interact reach', additiveUnit: 'tiles' },
  projectileSpeed: { label: 'Projectile speed' },
  rangedCooldown: { label: 'Ranged cooldown', lowerIsBetter: true },
};

export const MOD_KEYS = Object.keys(MOD_META) as (keyof StatMods)[];

function isAdd(key: keyof StatMods): boolean {
  return key.endsWith('Add');
}

export function modLabel(key: keyof StatMods): string {
  return MOD_META[key].label;
}

/** Neutral value of a modifier (1 for multipliers, 0 for adds). */
export function modNeutral(key: keyof StatMods): number {
  return isAdd(key) ? 0 : 1;
}

export function formatModValue(key: keyof StatMods, v: number): string {
  if (isAdd(key)) {
    const unit = MOD_META[key].additiveUnit ?? '';
    const sign = v > 0 ? '+' : v < 0 ? '−' : '±';
    return `${sign}${num(Math.abs(v))}${unit ? ' ' + unit : ''}`;
  }
  return pct(v);
}

/** +1 if the change helps the player, -1 if it hurts, 0 if neutral. */
export function modDirection(key: keyof StatMods, from: number, to: number): -1 | 0 | 1 {
  if (Math.abs(to - from) < 1e-9) return 0;
  const up = to > from ? 1 : -1;
  return (MOD_META[key].lowerIsBetter ? -up : up) as -1 | 1;
}

/** "Run speed +10%", "Interact reach +0.5 tiles". Neutral mods are omitted. */
export function modLines(mods: StatMods | undefined): string[] {
  if (!mods) return [];
  const out: string[] = [];
  for (const key of MOD_KEYS) {
    const v = mods[key];
    if (v === undefined || Math.abs(v - modNeutral(key)) < 1e-9) continue;
    out.push(`${modLabel(key)} ${formatModValue(key, v)}`);
  }
  return out;
}

const ABILITY_TEXT: Record<AbilityId, { name: string; text: string }> = {
  manualDesync: { name: 'Manual desync', text: 'Ability button knocks this self out of sync on purpose.' },
  lowProfile: { name: 'Low profile', text: 'Enemies treat you as farther away than you are.' },
  loudmouth: { name: 'Loudmouth', text: 'Enemies treat you as nearer than you are — draws aggro.' },
  beatSight: { name: 'Beat sight', text: 'Upcoming enemy attack beats show on the master ruler.' },
  laserProof: { name: 'Laser-proof', text: 'Laser beams do not kill you.' },
  heavyStep: { name: 'Heavy step', text: 'Standing on heavy plates holds them down.' },
  phaseDodge: { name: 'Phase dodge', text: 'Dodge passes through enemies and low barriers.' },
  slideStrike: { name: 'Slide strike', text: 'Ending a dodge into a strike adds momentum.' },
  parry: { name: 'Parry', text: 'Heavy attacks reflect projectiles inside the swing arc.' },
  killRefresh: { name: 'Kill refresh', text: 'A melee kill refunds your dodge cooldown.' },
};

export function abilityName(a: AbilityId): string {
  return ABILITY_TEXT[a]?.name ?? a;
}

export function abilityLine(a: AbilityId): string {
  const t = ABILITY_TEXT[a];
  return t ? `${t.name}: ${t.text}` : a;
}

// ───────────────────────────── weapons ─────────────────────────────

export interface StatRow {
  label: string;
  value: string;
}

function swingRow(name: string, s: MeleeSwingDef): StatRow {
  const total = s.windup + s.active + s.recover;
  return {
    label: name,
    value: `${ticksToSeconds(s.windup)} windup · ${ticksToSeconds(s.active)} hit · ${ticksToSeconds(s.recover)} recover (${ticksToSeconds(total)} total at 1×)`,
  };
}

/** Qualitative word for an efficiency multiplier, so "1.4×" reads as a character, not a spreadsheet. */
export function effWord(eff: number): string {
  if (eff >= 1.35) return 'very high';
  if (eff >= 1.1) return 'high';
  if (eff > 0.9) return 'standard';
  if (eff > 0.65) return 'low';
  return 'very low';
}

const MELEE_STYLE: Record<MeleeWeaponDef['style'], string> = {
  blade: 'Blade',
  blunt: 'Blunt',
  whip: 'Whip',
  gauntlet: 'Gauntlet',
};

/** Readable numbers for a melee weapon (WEAPON-04: reach, arc, windup, recovery, impact, stagger, knockback). */
export function meleeStatRows(m: MeleeWeaponDef): StatRow[] {
  return [
    { label: 'Style', value: MELEE_STYLE[m.style] },
    { label: 'Reach', value: `${num(m.reach)} tiles` },
    { label: 'Arc', value: `${num(m.arcDeg, 0)}°` },
    swingRow('Light', m.light),
    swingRow('Heavy', m.heavy),
    { label: 'Impact', value: `light ${num(m.light.impact)} · heavy ${num(m.heavy.impact)}` },
    { label: 'Damage', value: `${num(m.damageEff)}× (${effWord(m.damageEff)})` },
    { label: 'Knockback', value: `${num(m.knockbackEff)}× (${effWord(m.knockbackEff)})` },
    { label: 'Stagger', value: `${num(m.staggerEff)}× (${effWord(m.staggerEff)})` },
  ];
}

const ARCHETYPE: Record<RangedArchetype, { name: string; blurb: string; downside: string }> = {
  missile: {
    name: 'Homing missile',
    blurb: 'Locks the nearest enemy once, at launch, and tracks it.',
    // WEAPON-02: the slowness is the point.
    downside: 'Very slow, and never retargets — the fight has time to change before it lands.',
  },
  pierce: {
    name: 'Piercing shot',
    blurb: 'Fast straight shot that passes through enemies in a line.',
    downside: 'Flies dead straight with no tracking; it must be aimed into the line.',
  },
  phase: {
    name: 'Phase shot',
    blurb: 'Passes through walls and closed doors.',
    downside: 'Flies straight with no tracking; walls never stop it, so neither does cover you meant to hide behind.',
  },
  arc: {
    name: 'Lobbed shot',
    blurb: 'Arcs over low cover and enemies, hitting a small area where it lands.',
    downside: 'Lands where you aimed, not where the target went — slow to arrive.',
  },
  burst: {
    name: 'Burst',
    blurb: 'Several projectiles in a spread at short range.',
    downside: 'Short range; the spread thins out with distance.',
  },
};

export function archetypeName(a: RangedArchetype): string {
  return ARCHETYPE[a].name;
}

/**
 * The weapon's stated downside. Item data may carry its own (GearItem.downside); otherwise the
 * archetype's inherent trade-off is stated, plus any numeric outliers that a player would feel.
 */
export function rangedDownside(item: Pick<GearItem, 'downside'> & { ranged: RangedWeaponDef }): string {
  if (item.downside) return item.downside;
  const r = item.ranged;
  const extra: string[] = [];
  if (r.cooldown >= LOCAL_HZ) extra.push(`long cooldown (${ticksToSeconds(r.cooldown)})`);
  if (r.commit >= LOCAL_HZ / 3) extra.push(`you are committed for ${ticksToSeconds(r.commit)} per shot`);
  const base = ARCHETYPE[r.archetype].downside;
  return extra.length ? `${base} Also: ${extra.join('; ')}.` : base;
}

/** Readable numbers for a ranged weapon (WEAPON-01..03). */
export function rangedStatRows(r: RangedWeaponDef): StatRow[] {
  const rows: StatRow[] = [
    { label: 'Type', value: ARCHETYPE[r.archetype].name },
    { label: 'Behaviour', value: ARCHETYPE[r.archetype].blurb },
    { label: 'Speed', value: `${num(r.speed, 1)} tiles/s${r.speed < 4 ? ' (very slow)' : r.speed >= 14 ? ' (fast)' : ''}` },
    { label: 'Range', value: `${num(r.range, 1)} tiles` },
    { label: 'Impact', value: num(r.impact) },
    { label: 'Fire', value: `${ticksToSeconds(r.commit)} commit · ${ticksToSeconds(r.cooldown)} cooldown` },
  ];
  if (r.count > 1) rows.push({ label: 'Spread', value: `${r.count} projectiles over ${num(r.spreadDeg, 0)}°` });
  if (r.pierce > 0) rows.push({ label: 'Pierce', value: `passes through ${r.pierce} ${r.pierce === 1 ? 'enemy' : 'enemies'}` });
  if (r.passesWalls) rows.push({ label: 'Walls', value: 'passes through walls and closed doors' });
  if (r.lobbed) rows.push({ label: 'Trajectory', value: 'lobbed over low cover' });
  if (r.turnRate > 0) rows.push({ label: 'Homing', value: `${num((r.turnRate * 180) / Math.PI, 0)}°/s turn, one lock at launch` });
  if (r.blast > 0) rows.push({ label: 'Blast', value: `${num(r.blast)} tile radius` });
  if (r.minRange !== undefined && r.minRange > 0)
    rows.push({ label: 'Min range', value: `never lands closer than ${num(r.minRange)} tiles` });
  return rows;
}

/** Every player-readable mechanical line for an item, effect first (APPAREL-03). */
export function itemDetailRows(item: GearItem): StatRow[] {
  const rows: StatRow[] = [];
  if (item.melee) rows.push(...meleeStatRows(item.melee));
  if (item.ranged) {
    rows.push(...rangedStatRows(item.ranged));
    rows.push({ label: 'Downside', value: rangedDownside({ downside: item.downside, ranged: item.ranged }) });
  }
  for (const line of modLines(item.mods)) {
    const i = line.lastIndexOf(' ');
    rows.push({ label: line.slice(0, i), value: line.slice(i + 1) });
  }
  for (const a of item.abilities ?? []) rows.push({ label: abilityName(a), value: ABILITY_TEXT[a]?.text ?? '' });
  return rows;
}

/** Compact one-liner for weapon cards in lists. */
export function weaponHeadline(item: GearItem): string | null {
  if (item.melee) {
    const m = item.melee;
    return `${MELEE_STYLE[m.style]} · reach ${num(m.reach)} · ${num(m.arcDeg, 0)}° arc · light ${ticksToSeconds(
      m.light.windup,
    )} windup`;
  }
  if (item.ranged) {
    const r = item.ranged;
    return `${ARCHETYPE[r.archetype].name} · ${num(r.speed, 1)} tiles/s · ${num(r.range, 1)} tiles`;
  }
  return null;
}

// ───────────────────────────── comparison ─────────────────────────────

export interface CompareRow {
  label: string;
  from: string;
  to: string;
  /** +1 better for the player, -1 worse, 0 unchanged / not comparable. */
  dir: -1 | 0 | 1;
}

function cmpNum(label: string, a: number, b: number, fmt: (n: number) => string, lowerIsBetter = false): CompareRow {
  const d = Math.abs(b - a) < 1e-9 ? 0 : b > a ? 1 : -1;
  return { label, from: fmt(a), to: fmt(b), dir: (lowerIsBetter ? -d : d) as -1 | 0 | 1 };
}

function cmpSwing(name: string, a: MeleeSwingDef, b: MeleeSwingDef): CompareRow[] {
  const ta = a.windup + a.active + a.recover;
  const tb = b.windup + b.active + b.recover;
  return [
    cmpNum(`${name} windup`, a.windup, b.windup, ticksToSeconds, true),
    cmpNum(`${name} total`, ta, tb, ticksToSeconds, true),
    cmpNum(`${name} impact`, a.impact, b.impact, (n) => num(n)),
  ];
}

/**
 * Comparison of a candidate against the currently equipped item of the same slot. Rows that are
 * identical are kept only when they help orient the reader (weapons always show their core numbers).
 */
export function compareItems(equipped: GearItem, candidate: GearItem): CompareRow[] {
  const rows: CompareRow[] = [];
  if (equipped.melee && candidate.melee) {
    const a = equipped.melee;
    const b = candidate.melee;
    rows.push(cmpNum('Reach', a.reach, b.reach, (n) => `${num(n)} tiles`));
    rows.push(cmpNum('Arc', a.arcDeg, b.arcDeg, (n) => `${num(n, 0)}°`));
    rows.push(...cmpSwing('Light', a.light, b.light));
    rows.push(...cmpSwing('Heavy', a.heavy, b.heavy));
    rows.push(cmpNum('Damage', a.damageEff, b.damageEff, (n) => `${num(n)}×`));
    rows.push(cmpNum('Knockback', a.knockbackEff, b.knockbackEff, (n) => `${num(n)}×`));
    rows.push(cmpNum('Stagger', a.staggerEff, b.staggerEff, (n) => `${num(n)}×`));
  }
  if (equipped.ranged && candidate.ranged) {
    const a = equipped.ranged;
    const b = candidate.ranged;
    rows.push({
      label: 'Type',
      from: archetypeName(a.archetype),
      to: archetypeName(b.archetype),
      dir: 0,
    });
    rows.push(cmpNum('Speed', a.speed, b.speed, (n) => `${num(n, 1)} t/s`));
    rows.push(cmpNum('Range', a.range, b.range, (n) => `${num(n, 1)} tiles`));
    rows.push(cmpNum('Impact', a.impact, b.impact, (n) => num(n)));
    rows.push(cmpNum('Cooldown', a.cooldown, b.cooldown, ticksToSeconds, true));
    rows.push(cmpNum('Commit', a.commit, b.commit, ticksToSeconds, true));
    if (a.pierce !== b.pierce) rows.push(cmpNum('Pierce', a.pierce, b.pierce, (n) => String(n)));
    if (a.count !== b.count) rows.push(cmpNum('Projectiles', a.count, b.count, (n) => String(n)));
    if (a.blast !== b.blast) rows.push(cmpNum('Blast', a.blast, b.blast, (n) => `${num(n)} tiles`));
    if (a.passesWalls !== b.passesWalls)
      rows.push({ label: 'Through walls', from: a.passesWalls ? 'yes' : 'no', to: b.passesWalls ? 'yes' : 'no', dir: 0 });
    if (a.lobbed !== b.lobbed)
      rows.push({ label: 'Lobbed', from: a.lobbed ? 'yes' : 'no', to: b.lobbed ? 'yes' : 'no', dir: 0 });
  }
  for (const key of MOD_KEYS) {
    const a = equipped.mods?.[key] ?? modNeutral(key);
    const b = candidate.mods?.[key] ?? modNeutral(key);
    if (Math.abs(a - b) < 1e-9) continue;
    rows.push({
      label: modLabel(key),
      from: formatModValue(key, a),
      to: formatModValue(key, b),
      dir: modDirection(key, a, b),
    });
  }
  const aa = new Set(equipped.abilities ?? []);
  const bb = new Set(candidate.abilities ?? []);
  for (const a of aa) if (!bb.has(a)) rows.push({ label: abilityName(a), from: 'yes', to: 'lost', dir: -1 });
  for (const b of bb) if (!aa.has(b)) rows.push({ label: abilityName(b), from: '—', to: 'gained', dir: 1 });
  return rows;
}
