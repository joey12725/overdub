import { describe, expect, it } from 'vitest';
import { GEAR_SLOTS } from '../../src/core/types';
import {
  AV_OFFSET_MAX,
  CampaignLogic,
  EndingLogic,
  LoadoutLogic,
  PauseLogic,
  ResultsLogic,
  SettingsLogic,
  TitleLogic,
  campaignNodes,
  loadoutView,
  resultsView,
  DEFAULT_SETTINGS,
} from '../../src/ui/menus/logic';
import { MenuHost } from '../../src/ui/menus/nav';
import { returnIntent } from '../../src/ui/menus/menus';
import { campaign, GEAR, level, loadoutModel, recorder, results } from './fixtures';

describe('title', () => {
  it('with progress: Continue first, New descent asks before erasing', () => {
    const r = recorder();
    const logic = new TitleLogic(r.emit, () => true);
    const host = new MenuHost(logic);
    expect(host.entries.map((e) => e.id)).toEqual(['continue', 'new', 'loadout', 'settings']);
    expect(host.focus).toBe('continue');
    host.navigate('accept');
    expect(r.intents).toEqual([{ type: 'openCampaign' }]);

    host.navigate('down');
    host.navigate('accept');
    expect(logic.confirmingNew).toBe(true);
    // Lands on the safe choice so a double press cannot erase.
    expect(host.focus).toBe('new-no');
    host.navigate('back');
    expect(logic.confirmingNew).toBe(false);
    expect(host.focus).toBe('new');
    expect(r.intents).toHaveLength(1);

    host.navigate('accept');
    host.navigate('right');
    host.navigate('accept');
    expect(r.intents.slice(1)).toEqual([{ type: 'eraseSave' }, { type: 'openCampaign' }]);
  });

  it('without progress: no Continue, New descent goes straight to the path', () => {
    const r = recorder();
    const host = new MenuHost(new TitleLogic(r.emit, () => false));
    expect(host.entries.map((e) => e.id)).toEqual(['new', 'loadout', 'settings']);
    expect(host.focus).toBe('new');
    host.navigate('accept');
    expect(r.intents).toEqual([{ type: 'openCampaign' }]);
  });

  it('jumps to Continue when the save arrives after the title is up', () => {
    let progress = false;
    const host = new MenuHost(new TitleLogic(() => {}, () => progress));
    expect(host.focus).toBe('new');
    progress = true;
    host.refresh();
    expect(host.focus).toBe('continue');
  });

  it('Loadout and Settings emit their open intents', () => {
    const r = recorder();
    const host = new MenuHost(new TitleLogic(r.emit, () => false));
    host.navigate('down');
    host.navigate('accept');
    host.navigate('down');
    host.navigate('accept');
    expect(r.intents).toEqual([{ type: 'openLoadout' }, { type: 'openSettings' }]);
  });
});

describe('campaign (LEVEL-08, LEVEL-09)', () => {
  it('focuses the next uncleared level and walks the path vertically', () => {
    const r = recorder();
    const logic = new CampaignLogic(r.emit);
    logic.setModel(campaign(2));
    const host = new MenuHost(logic);
    expect(host.focus).toBe('level:L3');
    host.navigate('up');
    expect(host.focus).toBe('level:L2');
    host.navigate('up');
    host.navigate('up');
    expect(host.focus).toBe('back');
    host.navigate('right');
    expect(host.focus).toBe('loadout');
  });

  it('cleared levels are replayable; locked levels refuse without emitting', () => {
    const r = recorder();
    const logic = new CampaignLogic(r.emit);
    logic.setModel(campaign(2));
    const host = new MenuHost(logic);
    host.navigate('up');
    host.navigate('accept');
    expect(r.intents).toEqual([{ type: 'playLevel', id: 'L2' }]);
    host.navigate('down');
    host.navigate('down');
    expect(host.focus).toBe('level:L4');
    host.navigate('accept');
    expect(r.intents).toHaveLength(1);
    expect(logic.lockedPokes).toBe(1);
    expect(logic.lastPoked).toBe('level:L4');
  });

  it('right from any level reaches the loadout button; back returns to title', () => {
    const r = recorder();
    const logic = new CampaignLogic(r.emit);
    logic.setModel(campaign(1));
    const host = new MenuHost(logic);
    host.navigate('right');
    expect(host.focus).toBe('loadout');
    host.navigate('accept');
    host.navigate('back');
    expect(r.intents).toEqual([{ type: 'openLoadout' }, { type: 'openTitle' }]);
  });

  it('node view-models carry tapes, speeds, end modes, status and hide unfound loot', () => {
    const model = campaign(1, 3);
    model.levels[0].loot = [GEAR[6]];
    model.levels[2].level = level(2, { theme: 'core', maxTapes: 4, speeds: [0.5, 1, 2, 4], endModes: ['stop', 'reverse'], loot: ['x'] });
    const nodes = campaignNodes(model);
    expect(nodes.map((n) => n.status)).toEqual(['cleared', 'next', 'locked']);
    expect(nodes[0].loot).toEqual({ count: 1, found: true, items: [{ name: 'Boots', slot: 'SHOES', effect: 'Faster dodge.' }] });
    expect(nodes[2].loot.items).toEqual([]);
    expect(nodes[2].speeds).toEqual(['½×', '1×', '2×', '4×']);
    expect(nodes[2].endModes).toEqual(['Stop', 'Reverse']);
    expect(nodes[2].final).toBe(true);
    expect(nodes[2].maxTapes).toBe(4);
    expect(nodes[2].depth).toBe('03');
  });
});

describe('loadout (APPAREL-03, GEAR-03/04, APP-TEST-02)', () => {
  function setup() {
    const r = recorder();
    let left = 0;
    const logic = new LoadoutLogic(r.emit, () => left++);
    logic.setModel(loadoutModel());
    logic.onShow();
    const host = new MenuHost(logic);
    return { r, logic, host, left: () => left };
  }

  it('lists six slots in order, then Done', () => {
    const { host } = setup();
    const col0 = host.entries.filter((e) => e.col === 0).sort((a, b) => a.row - b.row);
    expect(col0.map((e) => e.id)).toEqual([...GEAR_SLOTS.map((s) => `slot:${s}`), 'done']);
    expect(host.focus).toBe('slot:helmet');
  });

  it('moving between slots previews that slot; accept enters its list on the equipped item', () => {
    const { host, logic } = setup();
    host.navigate('down');
    host.navigate('down');
    expect(host.focus).toBe('slot:pants');
    expect(logic.activeSlot).toBe('pants');
    host.navigate('accept');
    expect(logic.inList).toBe(true);
    expect(host.focus).toBe('item:cargo');
  });

  it('equipping emits an equip intent; re-picking the equipped item emits nothing', () => {
    const { host, r } = setup();
    host.navigate('accept');
    expect(host.focus).toBe('item:cap');
    host.navigate('accept');
    expect(r.intents).toEqual([]);
    host.navigate('down');
    expect(host.focus).toBe('item:hood');
    host.navigate('accept');
    expect(r.intents).toEqual([{ type: 'equip', slot: 'helmet', id: 'hood' }]);
  });

  it('the list keeps the cursor at its ends and left/back return to the slot', () => {
    const { host, logic, left } = setup();
    for (let i = 0; i < 5; i++) host.navigate('down');
    expect(host.focus).toBe('slot:ranged');
    host.navigate('right');
    expect(host.focus).toBe('item:missile');
    host.navigate('up');
    expect(host.focus).toBe('item:missile');
    host.navigate('down');
    host.navigate('down');
    expect(host.focus).toBe('item:rail');
    host.navigate('left');
    expect(host.focus).toBe('slot:ranged');
    host.navigate('right');
    host.navigate('back');
    expect(host.focus).toBe('slot:ranged');
    expect(logic.inList).toBe(false);
    expect(left()).toBe(0);
    host.navigate('back');
    expect(left()).toBe(1);
  });

  it('Done leaves', () => {
    const { host, left } = setup();
    for (let i = 0; i < 6; i++) host.navigate('down');
    expect(host.focus).toBe('done');
    host.navigate('accept');
    expect(left()).toBe(1);
  });

  it('view-model marks equipped and fresh items and reflects a changed loadout (APP-TEST-02)', () => {
    const before = loadoutView(loadoutModel(), 'shoes');
    expect(before.items.map((i) => [i.item.id, i.equipped, i.fresh])).toEqual([
      ['kicks', true, false],
      ['boots', false, true],
    ]);
    expect(before.slots.find((s) => s.slot === 'shoes')!.hasFresh).toBe(true);
    const after = loadoutView(loadoutModel({ loadout: { ...loadoutModel().loadout, shoes: 'boots' }, summary: ['Boots: Faster dodge.'] }), 'shoes');
    const shoes = after.slots.find((s) => s.slot === 'shoes')!;
    expect(shoes.equipped?.effect).toBe('Faster dodge.');
    expect(after.summary).toEqual(['Boots: Faster dodge.']);
    // Categories stay distinct: each slot tile keeps its own title.
    expect(new Set(after.slots.map((s) => s.title)).size).toBe(6);
  });

  it('openSlot (paper-doll pin) on an empty slot does not enter a list', () => {
    const r = recorder();
    const logic = new LoadoutLogic(r.emit, () => {});
    logic.setModel(loadoutModel({ inventory: GEAR.filter((g) => g.slot !== 'top') }));
    logic.openSlot('top');
    expect(logic.inList).toBe(false);
    expect(logic.activeSlot).toBe('top');
  });
});

describe('settings', () => {
  function setup() {
    const r = recorder();
    let left = 0;
    const logic = new SettingsLogic(r.emit, () => left++);
    logic.setModel({ ...DEFAULT_SETTINGS, master: 0.5, music: 1, avOffsetMs: 0 });
    const host = new MenuHost(logic);
    return { r, logic, host, left: () => left };
  }

  it('left/right nudge volumes by 5% and clamp at the ends', () => {
    const { host, r } = setup();
    host.navigate('right');
    host.navigate('left');
    host.navigate('left');
    host.navigate('down');
    host.navigate('right');
    expect(r.intents).toEqual([
      { type: 'setting', key: 'master', value: 0.55 },
      { type: 'setting', key: 'master', value: 0.5 },
      { type: 'setting', key: 'master', value: 0.45 },
    ]);
  });

  it('audio/visual offset steps in 5 ms and clamps', () => {
    const { host, logic, r } = setup();
    for (let i = 0; i < 3; i++) host.navigate('down');
    expect(host.focus).toBe('avOffsetMs');
    host.navigate('left');
    expect(r.intents.at(-1)).toEqual({ type: 'setting', key: 'avOffsetMs', value: -5 });
    logic.setValue('avOffsetMs', 9999);
    expect(logic.settings.avOffsetMs).toBe(AV_OFFSET_MAX);
  });

  it('toggles flip on accept and on left/right', () => {
    const { host, r } = setup();
    for (let i = 0; i < 4; i++) host.navigate('down');
    expect(host.focus).toBe('screenShake');
    host.navigate('accept');
    host.navigate('down');
    host.navigate('right');
    expect(r.intents).toEqual([
      { type: 'setting', key: 'screenShake', value: false },
      { type: 'setting', key: 'patterns', value: true },
    ]);
  });

  it('erase save needs a confirm step that defaults to keep', () => {
    const { host, r, logic } = setup();
    for (let i = 0; i < 6; i++) host.navigate('down');
    expect(host.focus).toBe('erase');
    host.navigate('accept');
    expect(host.focus).toBe('erase-no');
    host.navigate('accept');
    expect(logic.confirmingErase).toBe(false);
    expect(r.intents).toEqual([]);
    host.navigate('accept');
    host.navigate('right');
    host.navigate('accept');
    expect(r.intents).toEqual([{ type: 'eraseSave' }]);
  });

  it('back cancels a confirm first, then leaves', () => {
    const { host, left } = setup();
    for (let i = 0; i < 6; i++) host.navigate('down');
    host.navigate('accept');
    host.navigate('back');
    expect(left()).toBe(0);
    host.navigate('back');
    expect(left()).toBe(1);
  });

  it('the setSettings echo replaces optimistic values', () => {
    const { logic } = setup();
    logic.nudge('music', -1);
    expect(logic.settings.music).toBe(0.95);
    logic.setModel({ ...DEFAULT_SETTINGS, music: 0.3 });
    expect(logic.settings.music).toBe(0.3);
  });
});

describe('pause', () => {
  it('resume / restart / settings / quit; loadout is not offered mid-attempt', () => {
    const r = recorder();
    const logic = new PauseLogic(r.emit);
    logic.onShow();
    const host = new MenuHost(logic);
    expect(host.entries.map((e) => e.id)).toEqual(['resume', 'restart', 'settings', 'quit']);
    host.navigate('accept');
    host.navigate('down');
    host.navigate('accept');
    host.navigate('down');
    host.navigate('down');
    host.navigate('accept');
    expect(r.intents).toEqual([
      { type: 'resume' },
      { type: 'session', action: 'resetAll' },
      { type: 'resume' },
      { type: 'session', action: 'quit' },
    ]);
  });

  it('settings open inside the overlay and back returns to the Settings button', () => {
    const r = recorder();
    const logic = new PauseLogic(r.emit);
    logic.onShow();
    const host = new MenuHost(logic);
    host.navigate('down');
    host.navigate('down');
    host.navigate('accept');
    expect(logic.sub).toBe('settings');
    expect(host.focus).toBe('master');
    host.navigate('right');
    host.navigate('back');
    expect(logic.sub).toBe('menu');
    expect(host.focus).toBe('settings');
    expect(r.intents).toEqual([{ type: 'setting', key: 'master', value: 0.85 }]);
    host.navigate('back');
    expect(r.intents.at(-1)).toEqual({ type: 'resume' });
  });
});

describe('results', () => {
  it('next level uses nextId when given, else continues to the path', () => {
    const r = recorder();
    const logic = new ResultsLogic(r.emit);
    logic.setModel(results({ nextId: 'L4' }));
    const host = new MenuHost(logic);
    expect(host.entries.map((e) => e.id)).toEqual(['next', 'replay', 'path', 'loadout']);
    expect(host.focus).toBe('next');
    host.navigate('accept');
    host.navigate('right');
    host.navigate('accept');
    host.navigate('right');
    host.navigate('accept');
    host.navigate('right');
    host.navigate('accept');
    expect(r.intents).toEqual([
      { type: 'playLevel', id: 'L4' },
      { type: 'playLevel', id: 'L3' },
      { type: 'session', action: 'continue' },
      { type: 'openLoadout' },
    ]);
    logic.setModel(results());
    host.refresh();
    host.navigate('accept');
    expect(r.intents.at(-1)).toEqual({ type: 'session', action: 'continue' });
  });

  it('without a next level, focus starts on Path', () => {
    const logic = new ResultsLogic(() => {});
    logic.setModel(results({ hasNext: false }));
    const host = new MenuHost(logic);
    expect(host.entries.map((e) => e.id)).toEqual(['replay', 'path', 'loadout']);
    expect(host.focus).toBe('path');
  });

  it('view shows tapes used, notes and loot effect lines', () => {
    const v = resultsView(results());
    expect(v.title).toBe('LEVEL CLEARED');
    expect(v.tapesUsed).toBe(2);
    expect(v.maxTapes).toBe(3);
    expect(v.notes).toEqual(['Tape A held the plate.']);
    expect(v.loot).toEqual([{ name: 'Hood', slot: 'HELMET / HEADGEAR', effect: 'Enemies think you are farther away.', lore: 'quiet' }]);
  });
});

describe('ending and return routing', () => {
  it('ending offers path and title', () => {
    const r = recorder();
    const host = new MenuHost(new EndingLogic(r.emit));
    host.navigate('accept');
    host.navigate('right');
    host.navigate('accept');
    expect(r.intents).toEqual([{ type: 'openCampaign' }, { type: 'openTitle' }]);
  });

  it('loadout/settings return to where they were opened from', () => {
    expect(returnIntent('title')).toEqual({ type: 'openTitle' });
    expect(returnIntent(null)).toEqual({ type: 'openTitle' });
    expect(returnIntent('campaign')).toEqual({ type: 'openCampaign' });
    expect(returnIntent('results')).toEqual({ type: 'openCampaign' });
  });
});
