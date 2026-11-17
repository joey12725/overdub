import { describe, expect, it } from 'vitest';
import { MenuHost, moveFocus, type MenuDef, type NavItem } from '../../src/ui/menus/nav';

const grid: NavItem[] = [
  { id: 'a', row: 0, col: 0 },
  { id: 'b', row: 0, col: 1 },
  { id: 'c', row: 0, col: 2 },
  { id: 'd', row: 1, col: 0 },
  { id: 'e', row: 3, col: 2 },
];

describe('moveFocus', () => {
  it('moves along a row and stops at the ends (no wrap)', () => {
    expect(moveFocus(grid, 'a', 'right')).toBe('b');
    expect(moveFocus(grid, 'b', 'right')).toBe('c');
    expect(moveFocus(grid, 'c', 'right')).toBe('c');
    expect(moveFocus(grid, 'a', 'left')).toBe('a');
  });

  it('moves to the nearest populated row, choosing the closest column', () => {
    expect(moveFocus(grid, 'c', 'down')).toBe('d');
    expect(moveFocus(grid, 'd', 'down')).toBe('e');
    expect(moveFocus(grid, 'e', 'up')).toBe('d');
    expect(moveFocus(grid, 'd', 'up')).toBe('a');
    expect(moveFocus(grid, 'e', 'down')).toBe('e');
  });

  it('prefers the lower column on a tie', () => {
    const items: NavItem[] = [
      { id: 'top', row: 0, col: 1 },
      { id: 'l', row: 1, col: 0 },
      { id: 'r', row: 1, col: 2 },
    ];
    expect(moveFocus(items, 'top', 'down')).toBe('l');
  });

  it('honours explicit links over geometry', () => {
    const items: NavItem[] = [
      { id: 'x', row: 0, col: 0, links: { down: 'z' } },
      { id: 'y', row: 1, col: 0 },
      { id: 'z', row: 5, col: 3 },
    ];
    expect(moveFocus(items, 'x', 'down')).toBe('z');
  });

  it('recovers from a missing current focus', () => {
    expect(moveFocus(grid, null, 'down')).toBe('a');
    expect(moveFocus(grid, 'gone', 'down')).toBe('a');
    expect(moveFocus([], 'a', 'down')).toBeNull();
  });
});

describe('MenuHost', () => {
  function make() {
    const log: string[] = [];
    let value = 0;
    const def = (): MenuDef => ({
      entries: [
        { id: 'one', row: 0, col: 0, accept: () => log.push('one') },
        { id: 'slider', row: 1, col: 0, adjust: (d) => (value += d) },
        { id: 'locked', row: 2, col: 0, disabled: true, accept: () => log.push('locked') },
      ],
      back: () => log.push('back'),
      defaultFocus: 'one',
    });
    const host = new MenuHost({ menu: def });
    return { host, log, get value() { return value; } };
  }

  it('starts on the default focus and activates with accept', () => {
    const t = make();
    expect(t.host.focus).toBe('one');
    t.host.navigate('accept');
    expect(t.log).toEqual(['one']);
  });

  it('left/right adjust an adjustable entry instead of moving', () => {
    const t = make();
    t.host.navigate('down');
    expect(t.host.focus).toBe('slider');
    t.host.navigate('right');
    t.host.navigate('right');
    t.host.navigate('left');
    expect(t.value).toBe(1);
    expect(t.host.focus).toBe('slider');
  });

  it('disabled entries can be focused but not activated', () => {
    const t = make();
    t.host.navigate('down');
    t.host.navigate('down');
    expect(t.host.focus).toBe('locked');
    t.host.navigate('accept');
    expect(t.log).toEqual([]);
  });

  it('back runs the menu back handler', () => {
    const t = make();
    t.host.navigate('back');
    expect(t.log).toEqual(['back']);
  });

  it('pointer hover focuses and click equals focus + accept', () => {
    const t = make();
    t.host.hover('slider');
    expect(t.host.focus).toBe('slider');
    t.host.click('one');
    expect(t.host.focus).toBe('one');
    expect(t.log).toEqual(['one']);
    t.host.adjust('slider', -1);
    expect(t.value).toBe(-1);
    t.host.click('nope');
    expect(t.log).toEqual(['one']);
  });

  it('calls focused() when an entry gains focus and honours focus requests', () => {
    const seen: string[] = [];
    let req: string | null = null;
    const host = new MenuHost({
      menu: () => ({
        entries: [
          { id: 'a', row: 0, col: 0, focused: () => seen.push('a'), accept: () => (req = 'c') },
          { id: 'b', row: 1, col: 0, focused: () => seen.push('b') },
          { id: 'c', row: 2, col: 0 },
        ],
      }),
      takeFocusRequest: () => {
        const r = req;
        req = null;
        return r;
      },
    });
    host.navigate('down');
    expect(seen).toEqual(['b']);
    host.hover('a');
    host.navigate('accept');
    expect(host.focus).toBe('c');
  });
});
