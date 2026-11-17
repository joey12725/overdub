/**
 * The equipment catalogue (GEAR-01..05, WEAPON-01..04, APPAREL-01..03).
 *
 * Everything here is plain data. StatMods are multipliers on the sim's base numbers (types.ts
 * StatMods), so this file never needs src/core/tuning.ts. Weapon definitions carry absolute numbers
 * in the units types.ts documents: melee timings in LOCAL ticks (1/60 local s), projectile speed in
 * tiles per MASTER second, ranged commit/cooldown in local ticks.
 *
 * Design rules the roster follows:
 *  - Baseline items (BASE_LOADOUT) are plain and never bad: every mandatory level must be beatable
 *    with them (APP-TEST-03). The baseline blade is the momentum yardstick: light.impact = 1.0 with
 *    damageEff 1, so a 1x standing light swing has momentum 1.0 and kills a 1-hit enemy.
 *  - Every other melee weapon also clears that yardstick (light.impact x damageEff >= 1), so
 *    switching weapons changes strategy, never viability (WEAPON-04, NEW-01).
 *  - Clothing items are sidegrades: an upside paid for with a downside, or a situational ability
 *    whose cost is the slot it occupies (APPAREL-02). No item is a strictly better copy of another.
 *  - Each clothing slot changes outcomes, not a defence number (APPAREL-01): helmets bend targeting,
 *    hazards and readability; tops bend hit power and desync; pants bend mobility and dodge
 *    recovery; shoes bend traction, dodge shape and plates.
 *  - `effect` lines state the mechanics in player language with the same numbers as `mods`
 *    (APPAREL-03). Keep them in sync when tuning.
 *
 * Insertion order is meaningful: per slot, baseline first, then roughly the order Moxie digs them
 * out on the way down. UIs list items in this order.
 */
import type { GearItem, Loadout } from '../core/types';

const item = (def: GearItem): GearItem => def;

export const GEAR: Record<string, GearItem> = {
  // ─────────────────────────────── helmets / headgear ───────────────────────────────
  // Targeting, hazards, timeline readability, cassette perks. None of them hide the yellow cans.

  scrap_cap: item({
    id: 'scrap_cap',
    slot: 'helmet',
    name: 'Scrap Cap',
    effect: 'No special effect. Keeps the dust off and leaves your headphones clear.',
    lore: 'Found it hanging on a rebar hook by the first stairwell. Does nothing. Never lets me down.',
    look: { color: '#3b3442', variant: 'cap' },
  }),

  hush_hood: item({
    id: 'hush_hood',
    slot: 'helmet',
    name: 'Hush Hood',
    effect:
      'Enemies judge you as farther away than you are, so they pick other selves first. Stalkers hunt the farthest self, so they pick you.',
    lore: 'Quilted out of old speaker foam. Nobody hears me coming, nobody bothers looking.',
    abilities: ['lowProfile'],
    look: { color: '#4a4f5c', variant: 'hood' },
  }),

  feedback_crown: item({
    id: 'feedback_crown',
    slot: 'helmet',
    name: 'Feedback Crown',
    effect:
      'Enemies judge you as nearer than you are and come for you first. Stalkers hunt the farthest self, so they lose interest in you.',
    lore: 'A ring of blown tweeters wired to squeal. Great for pulling heat off the other me\'s.',
    abilities: ['loudmouth'],
    look: { color: '#ff4fa3', variant: 'crown' },
  }),

  click_visor: item({
    id: 'click_visor',
    slot: 'helmet',
    name: 'Click-Track Visor',
    effect: 'Upcoming enemy attack beats are marked on the master beat ruler while you record.',
    lore: 'Pried the metronome out of a rusted drum machine. It ticks before anything swings. Always right.',
    abilities: ['beatSight'],
    look: { color: '#ffd23f', variant: 'visor' },
  }),

  prism_goggles: item({
    id: 'prism_goggles',
    slot: 'helmet',
    name: 'Prism Goggles',
    effect: 'Laser beams no longer kill you. Enemy shots and strikes still do.',
    lore: 'Mirror-coated lenses off a burnt-out light rig. Beams just slide right off. Mostly.',
    abilities: ['laserProof'],
    look: { color: '#7fe7ff', variant: 'goggles' },
  }),

  rabbit_ears: item({
    id: 'rabbit_ears',
    slot: 'helmet',
    name: 'Rabbit-Ear Aerials',
    effect: 'Your recovery spark travels 40% faster, so a desynced self rejoins its tape sooner.',
    lore: 'Two telescoping aerials zip-tied to my cans. Pulls my own signal home through the static.',
    mods: { sparkSpeed: 1.4 },
    look: { color: '#c9c9d1', variant: 'antenna' },
  }),

  // ─────────────────────────────── tops / jackets ───────────────────────────────
  // Hit power and hit type, interaction reach, desync behaviour.

  lined_bomber: item({
    id: 'lined_bomber',
    slot: 'top',
    name: 'Lined Bomber',
    effect: 'No special effect. Crop top and the jacket with the yellow lining.',
    lore: 'Ten pockets, one cassette-sized burn hole. I\'m not leaving it behind for anything.',
    look: { color: '#25212b', variant: 'bomber' },
  }),

  ballast_puffer: item({
    id: 'ballast_puffer',
    slot: 'top',
    name: 'Ballast Puffer',
    effect: 'Melee swings carry 25% more momentum, but you run 8% slower.',
    lore: 'Somebody sewed lead fishing weights into the quilting. It\'s heavy. Hits like it, too.',
    mods: { meleeImpact: 1.25, moveSpeed: 0.92 },
    look: { color: '#5d6b3a', variant: 'puffer' },
  }),

  razor_mesh: item({
    id: 'razor_mesh',
    slot: 'top',
    name: 'Razor Mesh Tee',
    effect: 'Hits deal 35% more damage, but knock enemies back 40% less and stagger them 20% less.',
    lore: 'Mesh shirt stitched with snapped guitar strings. Cuts deep. Doesn\'t push.',
    mods: { damage: 1.35, knockback: 0.6, stagger: 0.8 },
    look: { color: '#1a1a1f', variant: 'mesh' },
  }),

  sub_vest: item({
    id: 'sub_vest',
    slot: 'top',
    name: 'Subwoofer Vest',
    effect: 'Knockback is 40% stronger and can carry enemies 50% farther, but hits deal 25% less damage.',
    lore: 'Twin eight-inch drivers on a harness. Every punch comes with a bass drop.',
    mods: { knockback: 1.4, knockbackCap: 1.5, damage: 0.75 },
    look: { color: '#2f2f38', variant: 'vest' },
  }),

  patchcord_hoodie: item({
    id: 'patchcord_hoodie',
    slot: 'top',
    name: 'Patch-Cord Hoodie',
    effect: 'You can work switches from 0.75 tiles farther away, but your dodges travel 10% shorter.',
    lore: 'Swapped the drawstrings for patch cables with grabber clips. Things snag. Useful things, sometimes.',
    mods: { interactRadiusAdd: 0.75, dodgeDistance: 0.9 },
    look: { color: '#3ec5ff', variant: 'hoodie' },
  }),

  dropout_jacket: item({
    id: 'dropout_jacket',
    slot: 'top',
    name: 'Dropout Jacket',
    effect:
      'Press the ability button to desync on purpose. Your spark travels 15% faster, but melee swings carry 10% less momentum.',
    lore: 'Lining\'s woven from chewed-up tape. Wear it long enough and you start skipping.',
    abilities: ['manualDesync'],
    mods: { sparkSpeed: 1.15, meleeImpact: 0.9 },
    look: { color: '#8a5cff', variant: 'jacket' },
  }),

  mirrorball_vest: item({
    id: 'mirrorball_vest',
    slot: 'top',
    name: 'Mirrorball Vest',
    effect: 'Heavy swings reflect projectiles caught inside their arc, but you run 5% slower.',
    lore: 'Glued every tile off a cracked disco ball onto a vest. Shots come in, shots go back out.',
    abilities: ['parry'],
    mods: { moveSpeed: 0.95 },
    look: { color: '#d8dbe6', variant: 'mirror' },
  }),

  encore_tee: item({
    id: 'encore_tee',
    slot: 'top',
    name: 'Encore Tee',
    effect: 'A melee kill instantly refreshes your dodge, but the dodge cooldown is otherwise 25% longer.',
    lore: 'Faded tour shirt, back print rubbed to nothing. Every takedown is another curtain call.',
    abilities: ['killRefresh'],
    mods: { dodgeCooldown: 1.25 },
    look: { color: '#ff4d6d', variant: 'tee' },
  }),

  // ─────────────────────────────── pants / legwear ───────────────────────────────
  // Acceleration, momentum retention, dodge recovery.

  olive_cargos: item({
    id: 'olive_cargos',
    slot: 'pants',
    name: 'Olive Cargos',
    effect: 'No special effect. Low-rise, roomy, more pockets than sense.',
    lore: 'My cargos. A belt loop for the Walkman. That\'s the whole review.',
    look: { color: '#5b5e3c', variant: 'cargo' },
  }),

  snap_trackies: item({
    id: 'snap_trackies',
    slot: 'pants',
    name: 'Snap Trackies',
    effect:
      'You reach full speed and change direction 40% quicker, but carry 20% less speed through turns and actions.',
    lore: 'Tear-away track pants. Every snap button pops on the downbeat if you move right.',
    mods: { accel: 1.4, momentumRetention: 0.8 },
    look: { color: '#2b2f6b', variant: 'track' },
  }),

  flywheel_cargos: item({
    id: 'flywheel_cargos',
    slot: 'pants',
    name: 'Flywheel Cargos',
    effect:
      'You keep 30% more speed through turns and actions and get 15% more from running into a strike, but get going 20% slower.',
    lore: 'Little tape-deck flywheels in the knee pockets. Once they spin up they do NOT want to stop.',
    mods: { momentumRetention: 1.3, approachBonus: 1.15, accel: 0.8 },
    look: { color: '#6e5a3a', variant: 'cargo-heavy' },
  }),

  kneepad_joggers: item({
    id: 'kneepad_joggers',
    slot: 'pants',
    name: 'Kneepad Joggers',
    effect: 'Dodge cooldown is 30% shorter, but each dodge covers 15% less ground.',
    lore: 'Skate pads strapped over joggers. Hit the floor, get up, hit the floor again.',
    mods: { dodgeCooldown: 0.7, dodgeDistance: 0.85 },
    look: { color: '#3a3a40', variant: 'joggers' },
  }),

  parachute_pants: item({
    id: 'parachute_pants',
    slot: 'pants',
    name: 'Parachute Pants',
    effect: 'Dodge invulnerability lasts 30% longer, but the dodge cooldown is 20% longer.',
    lore: 'So much nylon that stuff just passes through the gap. Takes forever to settle back down.',
    mods: { dodgeIframes: 1.3, dodgeCooldown: 1.2 },
    look: { color: '#b14cff', variant: 'parachute' },
  }),

  bandolier_cargos: item({
    id: 'bandolier_cargos',
    slot: 'pants',
    name: 'Bandolier Cargos',
    effect: 'Your ranged weapon recharges 30% faster, but the loaded pockets make you accelerate 10% slower.',
    lore: 'Every pocket packed with spare cells and rockets. I rattle. I also never run dry.',
    mods: { rangedCooldown: 0.7, accel: 0.9 },
    look: { color: '#4d4a2e', variant: 'bandolier' },
  }),

  // ─────────────────────────────── shoes / boots ───────────────────────────────
  // Traction, speed, dodge shape, momentum transfer, plates.

  beater_hightops: item({
    id: 'beater_hightops',
    slot: 'shoes',
    name: 'Beater High-Tops',
    effect: 'No special effect. Chunky, scuffed, reliable.',
    lore: 'Third pair this year. The soles squeak on the beat, I swear.',
    look: { color: '#f2efe6', variant: 'hightop' },
  }),

  slick_sliders: item({
    id: 'slick_sliders',
    slot: 'shoes',
    name: 'Slick Sliders',
    effect: 'Striking straight out of a dodge adds momentum to the hit, but slick soles accelerate 15% slower.',
    lore: 'Waxed the soles with something from a jar marked HEAD CLEANER. Slide in, swing out.',
    abilities: ['slideStrike'],
    mods: { accel: 0.85 },
    look: { color: '#ffd23f', variant: 'slider' },
  }),

  anvil_platforms: item({
    id: 'anvil_platforms',
    slot: 'shoes',
    name: 'Anvil Platforms',
    effect: 'Standing still, you weigh enough to hold heavy pressure plates and count double on normal ones. You run 10% slower.',
    lore: 'Platform boots with amp-casing soles. Floors notice me now.',
    abilities: ['heavyStep'],
    mods: { moveSpeed: 0.9 },
    look: { color: '#3d3d46', variant: 'platform' },
  }),

  static_runners: item({
    id: 'static_runners',
    slot: 'shoes',
    name: 'Static Runners',
    effect: 'Dodges pass through enemies and low barriers, but cover 15% less ground.',
    lore: 'They crackle when I move. Mid-dodge I\'m about half here, which is enough.',
    abilities: ['phaseDodge'],
    mods: { dodgeDistance: 0.85 },
    look: { color: '#3ec5ff', variant: 'runner' },
  }),

  spring_soles: item({
    id: 'spring_soles',
    slot: 'shoes',
    name: 'Spring Soles',
    effect: 'Dodge travels 30% farther, but its cooldown is 20% longer.',
    lore: 'Pulled the springs out of a cassette door and stacked them in the heels. Boing.',
    mods: { dodgeDistance: 1.3, dodgeCooldown: 1.2 },
    look: { color: '#7dff6b', variant: 'spring' },
  }),

  grip_sprinters: item({
    id: 'grip_sprinters',
    slot: 'shoes',
    name: 'Grip Sprinters',
    effect: 'You run 12% faster, but dodge invulnerability is 20% shorter.',
    lore: 'Spiked track shoes. Grip like crazy, forgive nothing.',
    mods: { moveSpeed: 1.12, dodgeIframes: 0.8 },
    look: { color: '#ff7a2f', variant: 'spike' },
  }),

  // ─────────────────────────────── melee weapons ───────────────────────────────
  // Distinct tools (WEAPON-04): reach, arc, windup/recovery, and where the momentum goes.
  // Timings are local ticks (60 per local second); they stretch or shrink in master time with tape speed.

  splice_blade: item({
    id: 'splice_blade',
    slot: 'melee',
    name: 'Splice Blade',
    effect:
      'Balanced blade: 1.3-tile reach, 100° arc. A standing 1× light drops a grunt; heavies hit 1.8× as hard.',
    lore: 'Started as a tape-splicing knife. I kept sharpening it and it kept getting bigger.',
    melee: {
      reach: 1.3,
      arcDeg: 100,
      light: { windup: 6, active: 4, recover: 10, impact: 1.0, moveMul: 0.7 },
      heavy: { windup: 16, active: 5, recover: 20, impact: 1.8, moveMul: 0.4 },
      damageEff: 1,
      knockbackEff: 1,
      staggerEff: 1,
      style: 'blade',
    },
    look: { color: '#e8e6df', variant: 'blade' },
  }),

  stylus_shiv: item({
    id: 'stylus_shiv',
    slot: 'melee',
    name: 'Stylus Shiv',
    effect:
      'Very quick, short blade: 1.0-tile reach, 70° arc. Hits deal 25% more damage per momentum but barely knock back.',
    lore: 'A record-player tone arm, needle filed to a point. Quick in, quick out.',
    melee: {
      reach: 1.0,
      arcDeg: 70,
      light: { windup: 3, active: 3, recover: 6, impact: 0.85, moveMul: 0.9 },
      heavy: { windup: 9, active: 4, recover: 12, impact: 1.4, moveMul: 0.7 },
      damageEff: 1.25,
      knockbackEff: 0.5,
      staggerEff: 0.7,
      style: 'blade',
    },
    look: { color: '#c0c4cc', variant: 'shiv' },
  }),

  amp_sledge: item({
    id: 'amp_sledge',
    slot: 'melee',
    name: 'Amp Sledge',
    effect:
      'Slow, crushing hammer: 1.4-tile reach, 120° arc. Huge knockback and stagger, 20% less damage per momentum. Heavies wind up for almost half a second.',
    lore: 'Guitar amp head on a scaffold pole. Still hums when it connects.',
    melee: {
      reach: 1.4,
      arcDeg: 120,
      light: { windup: 12, active: 5, recover: 18, impact: 1.4, moveMul: 0.5 },
      heavy: { windup: 28, active: 6, recover: 32, impact: 2.8, moveMul: 0.2 },
      damageEff: 0.8,
      knockbackEff: 1.8,
      staggerEff: 1.3,
      style: 'blunt',
    },
    look: { color: '#ffd23f', variant: 'sledge' },
  }),

  reel_lash: item({
    id: 'reel_lash',
    slot: 'melee',
    name: 'Reel Lash',
    effect:
      'Longest reach (2.6 tiles) in a narrow 30° line. Little knockback, strong stagger: pins enemies where they stand.',
    lore: 'Steel-cored tape on a hand reel. Snap it out, wind it back. Don\'t let it tangle.',
    melee: {
      reach: 2.6,
      arcDeg: 30,
      light: { windup: 9, active: 3, recover: 14, impact: 1.0, moveMul: 0.6 },
      heavy: { windup: 18, active: 4, recover: 22, impact: 1.6, moveMul: 0.35 },
      damageEff: 1.05,
      knockbackEff: 0.6,
      staggerEff: 1.5,
      style: 'whip',
    },
    look: { color: '#5a3b2a', variant: 'whip' },
  }),

  speaker_knuckles: item({
    id: 'speaker_knuckles',
    slot: 'melee',
    name: 'Speaker Knuckles',
    effect:
      'Fastest lights you\'ll find, but only 0.85-tile reach and an 80° arc. Strong stagger, modest knockback; you can keep moving while you punch.',
    lore: 'Tweeter cones riveted over fingerless gloves. They pop on every hit.',
    melee: {
      reach: 0.85,
      arcDeg: 80,
      light: { windup: 2, active: 3, recover: 5, impact: 0.9, moveMul: 0.95 },
      heavy: { windup: 7, active: 4, recover: 14, impact: 1.5, moveMul: 0.75 },
      damageEff: 1.15,
      knockbackEff: 0.8,
      staggerEff: 1.6,
      style: 'gauntlet',
    },
    look: { color: '#ff4fa3', variant: 'gauntlet' },
  }),

  vinyl_glaive: item({
    id: 'vinyl_glaive',
    slot: 'melee',
    name: 'Vinyl Glaive',
    effect:
      'Sweeping 200° arc at 1.8-tile reach catches anything in front of you. Slow to recover; extra knockback, weaker stagger.',
    lore: 'A sharpened twelve-inch on a broom handle. Spins like it\'s at 45.',
    melee: {
      reach: 1.8,
      arcDeg: 200,
      light: { windup: 10, active: 6, recover: 14, impact: 0.9, moveMul: 0.55 },
      heavy: { windup: 20, active: 8, recover: 24, impact: 1.6, moveMul: 0.3 },
      damageEff: 1.15,
      knockbackEff: 1.2,
      staggerEff: 0.8,
      style: 'blade',
    },
    look: { color: '#1b1b1f', variant: 'glaive' },
  }),

  // ─────────────────────────────── ranged weapons ───────────────────────────────
  // One per archetype, each with its stated downside (WEAPON-01..03, NEW-02..05). Melee stays primary,
  // so every ranged weapon is a commitment with a long cooldown. Speeds are tiles per MASTER second.

  mixtape_rocket: item({
    id: 'mixtape_rocket',
    slot: 'ranged',
    name: 'Mixtape Rocket',
    effect:
      'Very slow homing rocket (3 tiles/s). Locks onto the nearest enemy once at launch and chases it; it never switches targets.',
    lore: 'Cassette shell, bottle-rocket guts, a chip that picks a target and sticks with it. Like me.',
    ranged: {
      archetype: 'missile',
      speed: 3,
      range: 20,
      impact: 1.5,
      commit: 12,
      cooldown: 90,
      pierce: 0,
      passesWalls: false,
      lobbed: false,
      count: 1,
      spreadDeg: 0,
      turnRate: 3,
      blast: 0,
      radius: 0.35,
    },
    look: { color: '#ff4d6d', variant: 'launcher' },
  }),

  needle_rail: item({
    id: 'needle_rail',
    slot: 'ranged',
    name: 'Needle Rail',
    effect:
      'Fast needle (24 tiles/s) that punches through up to 3 enemies in a line. Very thin: you have to line it up exactly.',
    lore: 'Magnet coils off a dead tape head, firing phonograph needles. Straight line, no forgiveness.',
    ranged: {
      archetype: 'pierce',
      speed: 24,
      range: 12,
      impact: 1.0,
      commit: 8,
      cooldown: 75,
      pierce: 3,
      passesWalls: false,
      lobbed: false,
      count: 1,
      spreadDeg: 0,
      turnRate: 0,
      blast: 0,
      radius: 0.12,
    },
    look: { color: '#c0c4cc', variant: 'rail' },
  }),

  bleed_emitter: item({
    id: 'bleed_emitter',
    slot: 'ranged',
    name: 'Bleedthrough Emitter',
    effect:
      'Shot passes through walls and closed doors, but it is slow (6 tiles/s), short (8 tiles), only just drops a grunt and takes 2.5 s to recharge.',
    lore: 'Plays the B-side through the A-side. Also through rock. Slowly.',
    ranged: {
      archetype: 'phase',
      speed: 6,
      range: 8,
      impact: 1.0,
      commit: 14,
      cooldown: 150,
      pierce: 0,
      passesWalls: true,
      lobbed: false,
      count: 1,
      spreadDeg: 0,
      turnRate: 0,
      blast: 0,
      radius: 0.3,
    },
    look: { color: '#8a5cff', variant: 'emitter' },
  }),

  bass_drop: item({
    id: 'bass_drop',
    slot: 'ranged',
    name: 'Bass Drop',
    effect:
      'Lobs a shell over low cover and enemies; it bursts in a 1.2-tile blast where it lands, but never lands closer than 3 tiles.',
    lore: 'A subwoofer cone loaded into a mortar tube. Point it up, wait for the drop.',
    ranged: {
      archetype: 'arc',
      speed: 7,
      range: 7,
      impact: 1.3,
      commit: 16,
      cooldown: 100,
      pierce: 0,
      passesWalls: false,
      lobbed: true,
      count: 1,
      spreadDeg: 0,
      turnRate: 0,
      blast: 1.2,
      radius: 0.3,
      minRange: 3,
    },
    look: { color: '#7dff6b', variant: 'mortar' },
  }),

  static_spray: item({
    id: 'static_spray',
    slot: 'ranged',
    name: 'Static Spray',
    effect: 'Five pellets in a 40° fan, quick to fire, but they fizzle out after 3.5 tiles.',
    lore: 'A shorted-out boombox that spits sparks when you crank it. Get close. Closer.',
    ranged: {
      archetype: 'burst',
      speed: 16,
      range: 3.5,
      impact: 1.0,
      commit: 6,
      cooldown: 60,
      pierce: 0,
      passesWalls: false,
      lobbed: false,
      count: 5,
      spreadDeg: 40,
      turnRate: 0,
      blast: 0,
      radius: 0.2,
    },
    look: { color: '#3ec5ff', variant: 'boombox' },
  }),
};

/**
 * The starting loadout (one plain item per slot). Baseline items are always owned (GEAR-04: never
 * lost) and every mandatory level must be beatable with them (APP-TEST-03).
 */
export const BASE_LOADOUT: Loadout = {
  helmet: 'scrap_cap',
  top: 'lined_bomber',
  pants: 'olive_cargos',
  shoes: 'beater_hightops',
  melee: 'splice_blade',
  ranged: 'mixtape_rocket',
};

/** Ids of the baseline items, i.e. the inventory a fresh save starts with. */
export const BASE_INVENTORY: readonly string[] = Object.values(BASE_LOADOUT);
