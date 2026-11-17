/**
 * Standalone harness for the menu screens: serves every screen with fake models and a fake game
 * layer that answers intents the way src/game is expected to. Open it through the Vite dev server:
 *   /src/ui/menus/dev/harness.html?screen=loadout&nav=down,accept&device=gamepad&theme=lower&shot=1
 *
 * Query params:
 *   screen   initial screen (title|campaign|loadout|settings|play|pause|results|ending)
 *   nav      comma-separated navigate() commands applied after load
 *   fresh    1 = brand-new save (no cleared levels)
 *   patterns 1 = colour-blind cassette patterns on
 *   device   keyboard|gamepad
 *   theme    upper|lower backdrop behind the UI
 *   shot     1 = hide the dev bar (for screenshots)
 */
import type { CampaignScreenModel, MusicPulse, Screen, UiIntent } from '../../../contracts';
import type {
  DeckView,
  GearItem,
  LevelDef,
  Loadout,
  MeleeSwingDef,
  RangedWeaponDef,
  SaveData,
  SessionView,
  TapeIndex,
  Theme,
} from '../../../core/types';
import { createUi } from '../../index';

// ───────────────────────────── fake content ─────────────────────────────

const swing = (windup: number, active: number, recover: number, impact: number, moveMul = 0.4): MeleeSwingDef => ({
  windup,
  active,
  recover,
  impact,
  moveMul,
});
const ranged = (r: Partial<RangedWeaponDef> & Pick<RangedWeaponDef, 'archetype' | 'speed' | 'range'>): RangedWeaponDef => ({
  impact: 1,
  commit: 10,
  cooldown: 45,
  pierce: 0,
  passesWalls: false,
  lobbed: false,
  count: 1,
  spreadDeg: 0,
  turnRate: 0,
  blast: 0,
  ...r,
});

const GEAR: GearItem[] = [
  { id: 'scrap_cap', slot: 'helmet', name: 'Scrap Cap', effect: 'No special effect. Keeps the dust off and leaves your headphones clear.', lore: 'Found it hanging on a rebar hook by the first stairwell.' },
  { id: 'hush_hood', slot: 'helmet', name: 'Hush Hood', effect: 'Enemies judge you as farther away than you are, so they pick other selves first. Stalkers hunt the farthest self, so they pick you.', lore: 'Quilted out of old speaker foam.', abilities: ['lowProfile'] },
  { id: 'click_visor', slot: 'helmet', name: 'Click-Track Visor', effect: 'Upcoming enemy attack beats are marked on the master beat ruler while you record.', lore: 'Pried the metronome out of a rusted drum machine.', abilities: ['beatSight'] },
  { id: 'prism_goggles', slot: 'helmet', name: 'Prism Goggles', effect: 'Laser beams no longer kill you. Enemy shots and strikes still do.', lore: 'Mirror-coated lenses off a burnt-out light rig.', abilities: ['laserProof'] },
  { id: 'crop_top', slot: 'top', name: 'Patchwork Crop Top', effect: 'No special effect. Baseline Moxie.', lore: 'Mine. Obviously.' },
  { id: 'brass_jacket', slot: 'top', name: 'Brass-Knuckle Jacket', effect: 'Melee impact +20%, but the recovery spark is 15% slower.', lore: 'Heavy cuffs. Hits like a door.', mods: { meleeImpact: 1.2, sparkSpeed: 0.85 } },
  { id: 'long_arm_vest', slot: 'top', name: 'Long-Arm Vest', effect: 'Reach switches from 0.75 tiles farther away.', lore: 'Telescoping wrist rig.', mods: { interactRadiusAdd: 0.75 } },
  { id: 'cargo_pants', slot: 'pants', name: 'Olive Cargos', effect: 'No special effect. Pockets for days.', lore: 'Low-rise, high-utility.' },
  { id: 'glide_pants', slot: 'pants', name: 'Glide Track Pants', effect: 'Keep 25% more momentum through turns; accelerate 10% slower.', lore: 'Slick nylon, zero grip.', mods: { momentumRetention: 1.25, accel: 0.9 } },
  { id: 'high_tops', slot: 'shoes', name: 'Chunky High-Tops', effect: 'No special effect. Yellow laces, obviously.', lore: 'Broken in on a thousand stairs.' },
  { id: 'spring_kicks', slot: 'shoes', name: 'Spring Kicks', effect: 'Run 10% faster and dodge 20% farther; dodge cooldown 15% longer.', lore: 'Somebody put actual springs in these.', mods: { moveSpeed: 1.1, dodgeDistance: 1.2, dodgeCooldown: 1.15 } },
  { id: 'lead_boots', slot: 'shoes', name: 'Lead-Lined Boots', effect: 'Your weight holds heavy pressure plates down. Run 10% slower.', lore: 'Ankle day, every day.', mods: { moveSpeed: 0.9 }, abilities: ['heavyStep'] },
  {
    id: 'rebar_blade', slot: 'melee', name: 'Rebar Blade', effect: 'Balanced all-rounder. The yardstick every other weapon is measured against.', lore: 'Sharpened on a curb.',
    melee: { reach: 1.2, arcDeg: 110, light: swing(6, 4, 10, 1.0), heavy: swing(16, 5, 18, 2.2), damageEff: 1, knockbackEff: 1, staggerEff: 1, style: 'blade' },
  },
  {
    id: 'pipe_maul', slot: 'melee', name: 'Pipe Maul', effect: 'Slow, wide, enormous knockback. Heavy swings send enemies flying into hazards.', lore: 'A pipe, a valve, a lot of tape.',
    melee: { reach: 1.4, arcDeg: 140, light: swing(12, 5, 16, 1.4), heavy: swing(26, 6, 26, 3.2), damageEff: 0.8, knockbackEff: 1.6, staggerEff: 1.2, style: 'blunt' },
  },
  {
    id: 'cable_whip', slot: 'melee', name: 'Cable Whip', effect: 'Long reach in a narrow line; little knockback, long stagger.', lore: 'Still sparks at the tip.',
    melee: { reach: 2.3, arcDeg: 40, light: swing(9, 3, 12, 1.1), heavy: swing(18, 4, 20, 1.9), damageEff: 1, knockbackEff: 0.5, staggerEff: 1.5, style: 'whip' },
  },
  {
    id: 'tape_knuckles', slot: 'melee', name: 'Tape-Deck Knuckles', effect: 'Very fast, short reach. Running strikes hit much harder.', lore: 'Two cassette motors, one fist.',
    melee: { reach: 0.9, arcDeg: 70, light: swing(3, 3, 6, 1.0), heavy: swing(10, 4, 12, 1.8), damageEff: 1.1, knockbackEff: 0.8, staggerEff: 0.9, style: 'gauntlet' },
  },
  { id: 'slow_missile', slot: 'ranged', name: 'Homebrew Missile', effect: 'Fires a slow missile that locks the nearest enemy once, at launch.', lore: 'A bottle rocket with ambitions.', ranged: ranged({ archetype: 'missile', speed: 2.5, range: 18, turnRate: 3, impact: 1.2, cooldown: 90, commit: 14 }) },
  { id: 'nail_rail', slot: 'ranged', name: 'Nail Rail', effect: 'Fast nail that pierces up to 3 enemies in a line.', lore: 'Magnet coil, roofing nails.', ranged: ranged({ archetype: 'pierce', speed: 22, range: 12, pierce: 3, impact: 0.9 }) },
  { id: 'ghost_shot', slot: 'ranged', name: 'Phase Popper', effect: 'Shots pass through walls and closed doors.', lore: 'Tuned to the runes. Spooky.', ranged: ranged({ archetype: 'phase', speed: 9, range: 10, passesWalls: true, impact: 0.8 }), downside: 'Weak impact: a phase shot alone rarely kills anything tougher than a grunt.' },
  { id: 'mortar_can', slot: 'ranged', name: 'Mortar Can', effect: 'Lobbed shell over low cover; small blast where it lands.', lore: 'Paint can + spring. Do not shake.', ranged: ranged({ archetype: 'arc', speed: 7, range: 9, lobbed: true, blast: 1.2, minRange: 3, impact: 1.3, cooldown: 75 }) },
  { id: 'scatter', slot: 'ranged', name: 'Scatter Box', effect: 'Five pellets in a 40° spread at short range.', lore: 'Speaker cone full of washers.', ranged: ranged({ archetype: 'burst', speed: 16, range: 4.5, count: 5, spreadDeg: 40, impact: 0.5 }) },
];
const gearById = new Map(GEAR.map((g) => [g.id, g]));

const LEVEL_SPECS: [string, string, Theme, 1 | 2 | 3 | 4, LevelDef['speeds'], LevelDef['endModes'], string[]][] = [
  ['First Take', 'One cassette. Learn the groove.', 'upper', 1, [1], [], ['spring_kicks']],
  ['Double Time', 'A faster tape hits harder.', 'upper', 1, [1, 2], [], ['pipe_maul']],
  ['Call and Response', 'Two of you. One door.', 'upper', 2, [0.5, 1, 2], [], ['hush_hood', 'nail_rail']],
  ['Sunken Switchyard', 'Hold the plate. Watch your back.', 'mid', 3, [0.5, 1, 2], ['stop'], ['brass_jacket']],
  ['Loop Hole', 'When the tape runs out, start again.', 'mid', 3, [0.5, 1, 2], ['stop', 'repeat'], ['glide_pants', 'mortar_can']],
  ['Rune Furnace', 'Lasers on the beat. Something remembers.', 'lower', 4, [0.5, 1, 2, 4], ['stop', 'repeat', 'reverse'], ['prism_goggles']],
  ['Neon Vault', 'Four tapes. No mercy.', 'lower', 4, [0.5, 1, 2, 4], ['stop', 'repeat', 'reverse'], ['cable_whip', 'ghost_shot']],
  ['The Time Machine', 'It was real the whole time.', 'core', 4, [0.5, 1, 2, 4], ['stop', 'repeat', 'reverse'], []],
];

const LEVELS: LevelDef[] = LEVEL_SPECS.map(([name, tagline, theme, maxTapes, speeds, endModes, loot], index) => ({
  id: `L${index + 1}`,
  index,
  name,
  tagline,
  theme,
  bpm: 120,
  bars: 4,
  horizonBars: 8,
  maxTapes,
  speeds,
  endModes,
  map: ['#####', '#...#', '#####'],
  start: { x: 1.5, y: 1.5 },
  entities: [],
  objective: { type: 'reach', text: 'Reach the exit' },
  music: {
    root: 0,
    scale: 'minor',
    progression: [0, 5, 3, 4],
    tracks: [
      { role: 'drums', formula: 'x' },
      { role: 'bass', formula: 'x' },
      { role: 'chord', formula: 'x' },
      { role: 'melody', formula: 'x' },
    ],
  },
  loot,
  briefing: [],
}));

// ───────────────────────────── fake game ─────────────────────────────

const params = new URLSearchParams(location.search);
const freshSave = params.get('fresh') === '1';
if (params.get('shot') === '1') document.body.classList.add('shot');
document.getElementById('fake-world')!.dataset.theme = params.get('theme') ?? 'upper';

const BASE: Loadout = { helmet: 'scrap_cap', top: 'crop_top', pants: 'cargo_pants', shoes: 'high_tops', melee: 'rebar_blade', ranged: 'slow_missile' };
let cleared = new Set<string>(freshSave ? [] : ['L1', 'L2', 'L3', 'L4']);
let inventory: string[] = freshSave ? Object.values(BASE) : GEAR.map((g) => g.id).filter((id) => !['cable_whip', 'ghost_shot', 'prism_goggles'].includes(id));
let loadout: Loadout = freshSave ? { ...BASE } : { ...BASE, melee: 'pipe_maul', shoes: 'spring_kicks' };
let fresh: string[] = freshSave ? [] : ['brass_jacket'];
let settings: SaveData['settings'] = { master: 0.8, music: 0.7, sfx: 0.9, avOffsetMs: 0, screenShake: true, patterns: params.get('patterns') === '1' };
let screen: Screen = 'title';
let playing: LevelDef = LEVELS[4];

const ui = createUi();
document.body.append(ui.root);
if (params.get('device') === 'gamepad') ui.setDevice?.('gamepad');

function campaignModel(): CampaignScreenModel {
  const firstOpen = LEVELS.findIndex((l) => !cleared.has(l.id));
  const current = firstOpen < 0 ? LEVELS.length - 1 : firstOpen;
  return {
    levels: LEVELS.map((level, i) => ({
      level,
      cleared: cleared.has(level.id),
      unlocked: i <= current,
      loot: level.loot.map((id) => gearById.get(id)!).filter(Boolean),
    })),
    current,
  };
}

function summary(): string[] {
  const out: string[] = [];
  for (const id of Object.values(loadout)) {
    const g = gearById.get(id);
    if (g && !g.effect.startsWith('No special effect') && !g.melee && !g.ranged) out.push(`${g.name}: ${g.effect}`);
  }
  return out;
}

function pushAll(): void {
  ui.setCampaign(campaignModel());
  ui.setLoadout({ inventory: inventory.map((id) => gearById.get(id)!), loadout, summary: summary(), fresh });
  ui.setSettings(settings);
  ui.setResults({
    level: LEVELS[3],
    outcome: { win: true, objectiveComplete: true, survivors: [0, 2], notes: ['Tape B died at beat 9 — its plate hold still counted.', 'Tape C’s 2× heavy broke the wall on beat 14.'] },
    tapesUsed: 3,
    loot: [gearById.get('brass_jacket')!, gearById.get('glide_pants')!],
    hasNext: true,
    nextId: 'L5',
  });
}

function deck(i: TapeIndex, status: DeckView['status'], speed: DeckView['speed'], progress: number): DeckView {
  return {
    index: i,
    status,
    speed,
    endMode: speed ? 'stop' : null,
    localProgress: progress,
    transport: status === 'recording' || status === 'committed' ? 1 : 0,
    reelRate: speed ?? 0,
    life: status === 'empty' || status === 'unavailable' ? null : 'alive',
    synced: true,
    spanBars: speed ? 4 / speed : 0,
    marks: [],
    stateMarks: [],
  };
}

function fakeView(): SessionView {
  return {
    phase: 'recording',
    level: playing,
    decks: [deck(0, 'committed', 0.5, 0.6), deck(1, 'committed', 2, 1), deck(2, 'recording', 1, 0.6), deck(3, playing.maxTapes > 3 ? 'empty' : 'unavailable', null, 0)],
    active: 2,
    beat: 9.5,
    horizonBeats: 32,
    worldRate: 1,
    count: 0,
    speeds: playing.speeds,
    endModes: playing.endModes,
    objective: { complete: false, progress: 0.4, survivors: 3, text: 'Reach the exit' },
    outcome: null,
    actions: [],
    threatBeats: [],
    hint: null,
  };
}

const pulse: MusicPulse = { beat: 9.5, beatPulse: 0.3, barPulse: 0.1, levels: [0.5, 0.4, 0.8, 0], pitches: [0.3, 0.5, 0.7, 0], chord: 1 };

function show(s: Screen): void {
  screen = s;
  if (s === 'loadout') pushAll();
  ui.showScreen(s);
  if (s === 'play' || s === 'pause') ui.updateHud(fakeView(), pulse);
  if (s === 'loadout') fresh = [];
}

const logEl = document.getElementById('dev-log')!;
const log: string[] = [];
ui.onIntent((intent: UiIntent) => {
  log.push(JSON.stringify(intent));
  while (log.length > 6) log.shift();
  logEl.textContent = log.join('\n');
  switch (intent.type) {
    case 'openTitle':
      return show('title');
    case 'openCampaign':
      return show('campaign');
    case 'openLoadout':
      return show('loadout');
    case 'openSettings':
      return show('settings');
    case 'playLevel':
      playing = LEVELS.find((l) => l.id === intent.id) ?? playing;
      ui.toast(`Entering ${playing.name}`, 'info');
      return show('play');
    case 'equip':
      loadout = { ...loadout, [intent.slot]: intent.id };
      ui.setLoadout({ inventory: inventory.map((id) => gearById.get(id)!), loadout, summary: summary(), fresh });
      ui.toast(`Equipped ${gearById.get(intent.id)?.name}`, 'good');
      return;
    case 'setting':
      settings = { ...settings, [intent.key]: intent.value };
      ui.setSettings(settings);
      return;
    case 'resume':
      return show('play');
    case 'eraseSave':
      cleared = new Set();
      inventory = Object.values(BASE);
      loadout = { ...BASE };
      fresh = [];
      pushAll();
      ui.toast('Save erased', 'warn');
      return;
    case 'session':
      if (intent.action === 'continue' || intent.action === 'quit') return show('campaign');
      return;
  }
});

window.addEventListener('keydown', (e) => {
  const map: Record<string, Parameters<typeof ui.navigate>[0]> = {
    ArrowUp: 'up',
    ArrowDown: 'down',
    ArrowLeft: 'left',
    ArrowRight: 'right',
    Enter: 'accept',
    ' ': 'accept',
    Escape: 'back',
  };
  if (screen === 'play' && e.key === 'Escape') {
    e.preventDefault();
    show('pause');
    return;
  }
  const cmd = map[e.key];
  if (cmd) {
    e.preventDefault();
    ui.navigate(cmd);
  }
});

const bar = document.getElementById('dev-bar')!;
const screens: Screen[] = ['title', 'campaign', 'loadout', 'settings', 'play', 'pause', 'results', 'ending'];
for (const s of screens) {
  const b = document.createElement('button');
  b.textContent = s;
  b.onclick = () => show(s);
  bar.append(b);
}
const tb = document.createElement('button');
tb.textContent = 'toast';
tb.onclick = () => ui.toast('Tape B desynced', (['info', 'good', 'warn'] as const)[log.length % 3]);
bar.append(tb);

pushAll();
const initial = (params.get('screen') as Screen | null) ?? 'title';
show(screens.includes(initial) ? initial : 'title');
for (const cmd of (params.get('nav') ?? '').split(',').filter(Boolean)) {
  ui.navigate(cmd as Parameters<typeof ui.navigate>[0]);
}
(window as unknown as { __ui: typeof ui }).__ui = ui;
