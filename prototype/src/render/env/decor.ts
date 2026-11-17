/**
 * Decor entities (DecorDef): small procedural models in the house style of the R03 / R04 prop
 * libraries — chunky silhouettes, flat cel colour, yellow utility paint up top, dark plating and
 * neon below. Decor never collides (types.ts DecorDef), so models stay low and compact unless the
 * piece is a deliberate set-piece (arch, time machine).
 *
 * Orientation: `rot` quarter turns rotate the model about +Y; rot 0 faces +Z (toward the camera's
 * left-hand side), rot 1 faces +X.
 */
import * as THREE from 'three';
import type { DecorDef } from '../../core/types';
import type { MusicReactive } from '../layer';
import type { MaterialKit } from '../materials';
import { type EnvPalette, mixColor, scaleColor } from '../palettes';
import { chamferBox, leafClump, rockGeometry, tuftGeometry } from './geom';
import { type LevelLayout, WALL_CUT_HEIGHT } from './layout';
import { reactiveGlow, reactiveToon, registerReactive } from './reactive';
import { Rng, hashString } from './rng';
import { crateTexture, graffitiTexture, runePanelTexture, screenTexture, vineTexture } from './textures';

export interface Practical {
  x: number;
  y: number;
  h: number;
  color: number;
  intensity: number;
  distance: number;
}

export interface DecorCtx {
  kit: MaterialKit;
  pal: EnvPalette;
  layout: LevelLayout;
  seed: number;
  reactive: MusicReactive[];
  /** Per-frame animation callbacks (wall-clock seconds). Must not allocate. */
  animate: ((time: number, dt: number) => void)[];
  practicals: Practical[];
  /** Soft contact shadow under a prop (sim axes, radius in tiles). */
  blob(x: number, y: number, radius: number, strength?: number): void;
}

type Face = 'e' | 's';

const NEON_NAMES: Record<string, (p: EnvPalette) => number> = {
  cyan: (p) => p.neonA,
  pink: (p) => p.neonB,
  magenta: (p) => p.neonB,
  violet: (p) => p.neonC,
  purple: (p) => p.neonC,
  orange: (p) => p.warm,
  amber: (p) => p.accent,
  yellow: (p) => p.hazard,
};

function neonColor(variant: string | undefined, pal: EnvPalette, rng: Rng): number {
  if (variant) {
    const v = variant.trim().toLowerCase();
    if (NEON_NAMES[v]) return NEON_NAMES[v](pal);
    if (/^#?[0-9a-f]{6}$/.test(v)) return parseInt(v.replace('#', ''), 16);
  }
  return rng.pick([pal.neonA, pal.neonB, pal.neonC]);
}

function place(obj: THREE.Object3D, def: DecorDef): THREE.Object3D {
  obj.position.set(def.x, 0, def.y);
  obj.rotation.y = ((def.rot ?? 0) * Math.PI) / 2;
  return obj;
}

function m(geo: THREE.BufferGeometry, mat: THREE.Material | THREE.Material[], x = 0, y = 0, z = 0, shadow = true): THREE.Mesh {
  const mesh = new THREE.Mesh(geo, mat);
  mesh.position.set(x, y, z);
  mesh.castShadow = shadow;
  mesh.receiveShadow = true;
  return mesh;
}

/** Utility paint colour for props: yellow up top, darker plated metal deeper down. */
function utilityColor(pal: EnvPalette): number {
  return pal.floorFinish === 'stone' ? pal.hazard : pal.floorFinish === 'mixed' ? mixColor(pal.hazard, pal.metal, 0.35) : pal.metal;
}

/**
 * Locate the camera-visible wall face nearest to a point, for decals and hanging vines.
 * Returns the face's centre on the floor plane, its outward axis and the wall height.
 */
export function findWallFace(layout: LevelLayout, x: number, y: number, prefer?: Face): { c: number; r: number; face: Face; height: number } | null {
  const c = Math.floor(x);
  const r = Math.floor(y);
  const wallAt = (cc: number, rr: number) => layout.at(cc, rr) === '#';
  const tall = (cc: number, rr: number) => wallAt(cc, rr) && layout.wallHeight(cc, rr) > WALL_CUT_HEIGHT + 0.01;
  if (wallAt(c, r)) {
    const faces: Face[] = prefer === 's' ? ['s', 'e'] : ['e', 's'];
    for (const f of faces) {
      const nc = f === 'e' ? c + 1 : c;
      const nr = f === 's' ? r + 1 : r;
      if (!wallAt(nc, nr)) return { c, r, face: f, height: layout.wallHeight(c, r) };
    }
    return null;
  }
  const options: { c: number; r: number; face: Face }[] = [];
  if (tall(c - 1, r)) options.push({ c: c - 1, r, face: 'e' });
  if (tall(c, r - 1)) options.push({ c, r: r - 1, face: 's' });
  if (options.length === 0) return null;
  const pick = options.find((o) => o.face === prefer) ?? options[0];
  return { ...pick, height: layout.wallHeight(pick.c, pick.r) };
}

/** Transform an object so its local +Z faces out of a wall face, at height h, offset `along` the face. */
export function mountOnFace(obj: THREE.Object3D, c: number, r: number, face: Face, h: number, along = 0, out = 0.012): void {
  if (face === 'e') {
    obj.position.set(c + 1 + out, h, r + 0.5 - along);
    obj.rotation.set(0, Math.PI / 2, 0);
  } else {
    obj.position.set(c + 0.5 + along, h, r + 1 + out);
    obj.rotation.set(0, 0, 0);
  }
}

// ───────────────────────────── models ─────────────────────────────

function graffiti(def: DecorDef, ctx: DecorCtx): THREE.Object3D {
  const { kit, pal, layout } = ctx;
  const seed = hashString(`${def.x},${def.y},${def.variant ?? ''}`) ^ ctx.seed;
  const rng = new Rng(seed);
  const color = rng.chance(0.5) ? pal.graffiti : pal.graffitiAlt;
  const tex = kit.texture(graffitiTexture(def.variant, color, scaleColor(color, 0.35), seed));
  // Lit like the surface it is painted on: graffiti is paint, not light (no purple cast up top).
  const mat = kit.toon(0xffffff, { map: tex, transparent: true, decal: true, alphaTest: 0.04 });
  const prefer: Face | undefined = def.rot === 1 || def.rot === 3 ? 'e' : def.rot === undefined ? undefined : 's';
  const face = findWallFace(layout, def.x, def.y, prefer);
  if (face && face.height > 0.6) {
    // Tags sprawl across neighbouring blocks when the wall continues; a lone block keeps them small.
    const tallAt = (cc: number, rr: number) => layout.at(cc, rr) === '#' && layout.wallHeight(cc, rr) >= face.height * 0.8;
    const n = face.face === 'e' ? Number(tallAt(face.c, face.r - 1)) + Number(tallAt(face.c, face.r + 1)) : Number(tallAt(face.c - 1, face.r)) + Number(tallAt(face.c + 1, face.r));
    const size = Math.min(face.height * 0.95, n === 2 ? 1.75 : n === 1 ? 1.35 : 1.05);
    const plane = new THREE.Mesh(kit.geo(`gplane`, () => new THREE.PlaneGeometry(1, 1)), mat);
    plane.scale.setScalar(size);
    const along = face.c === Math.floor(def.x) && face.r === Math.floor(def.y) ? 0 : face.face === 'e' ? -(def.y - (face.r + 0.5)) : def.x - (face.c + 0.5);
    mountOnFace(plane, face.c, face.r, face.face, Math.min(face.height * 0.55, 0.95), Math.max(-0.2, Math.min(0.2, along)));
    plane.renderOrder = 2;
    return plane;
  }
  const plane = new THREE.Mesh(kit.geo(`gplane`, () => new THREE.PlaneGeometry(1, 1)), mat);
  plane.rotation.x = -Math.PI / 2;
  plane.rotation.z = ((def.rot ?? 0) * Math.PI) / 2;
  plane.position.set(def.x, 0.004, def.y);
  plane.scale.setScalar(0.95);
  plane.renderOrder = 2;
  return plane;
}

function vines(def: DecorDef, ctx: DecorCtx): THREE.Object3D {
  const { kit, pal, layout } = ctx;
  const g = new THREE.Group();
  const seed = hashString(`v${def.x},${def.y}`) ^ ctx.seed;
  const tex = kit.texture(vineTexture(pal, seed));
  const mat = kit.toon(0xffffff, { map: tex, transparent: true, alphaTest: 0.35, side: THREE.DoubleSide, depthWrite: true });
  const face = findWallFace(layout, def.x, def.y, def.rot === 1 ? 'e' : undefined);
  const leaf = kit.toon(pal.foliage);
  if (face) {
    for (let i = 0; i < 2; i++) {
      const len = face.height * (0.6 + 0.35 * ((seed >> (i * 3)) & 7) / 7);
      const plane = new THREE.Mesh(kit.geo('vplane', () => new THREE.PlaneGeometry(1, 1)), mat);
      plane.scale.set(0.42, len, 1);
      mountOnFace(plane, face.c, face.r, face.face, face.height - len / 2, (i - 0.5) * 0.4, 0.02 + i * 0.006);
      g.add(plane);
    }
    const top = m(kit.geo(`leaf${seed % 3}:0.55`, () => leafClump(seed % 3, 0.55)), leaf);
    const anchor = new THREE.Object3D();
    mountOnFace(anchor, face.c, face.r, face.face, face.height - 0.08, 0, -0.15);
    top.position.copy(anchor.position);
    g.add(top);
    return g;
  }
  // No wall: a creeping mound with trailing tendrils.
  for (let i = 0; i < 3; i++) {
    const c = m(kit.geo(`leaf${i}`, () => leafClump(i, 0.5)), kit.toon(scaleColor(pal.foliage, 0.85 + i * 0.1)));
    c.position.set(def.x + (i - 1) * 0.2, 0, def.y + ((i * 37) % 5) * 0.05 - 0.1);
    c.scale.set(1, 0.6, 1);
    g.add(c);
  }
  return g;
}

function bush(def: DecorDef, ctx: DecorCtx): THREE.Object3D {
  const { kit, pal } = ctx;
  const g = new THREE.Group();
  const rng = new Rng(hashString(`b${def.x},${def.y}`) ^ ctx.seed);
  const n = rng.int(3, 5);
  for (let i = 0; i < n; i++) {
    const s = rng.int(0, 3);
    const c = m(kit.geo(`leaf${s}`, () => leafClump(s, 0.5)), kit.toon(scaleColor(pal.foliage, rng.range(0.8, 1.15))));
    const a = (i / n) * Math.PI * 2;
    const d = i === 0 ? 0 : rng.range(0.12, 0.24);
    c.position.set(Math.cos(a) * d, 0, Math.sin(a) * d);
    c.scale.setScalar(i === 0 ? 1.2 : rng.range(0.7, 1));
    g.add(c);
  }
  for (let i = 0; i < 3; i++) {
    const t = m(kit.geo(`tuft${i}:0.35`, () => tuftGeometry(i, 0.35)), kit.toon(scaleColor(pal.foliage, 1.15), { side: THREE.DoubleSide }), rng.range(-0.3, 0.3), 0, rng.range(-0.3, 0.3), false);
    g.add(t);
  }
  ctx.blob(def.x, def.y, 0.45);
  return place(g, def);
}

function crate(def: DecorDef, ctx: DecorCtx): THREE.Object3D {
  const { kit, pal } = ctx;
  const g = new THREE.Group();
  const rng = new Rng(hashString(`c${def.x},${def.y}`) ^ ctx.seed);
  const base = rng.chance(0.6) ? utilityColor(pal) : pal.floorFinish === 'stone' ? pal.metal : mixColor(pal.metal, pal.trim, 0.3);
  const tex = kit.texture(crateTexture(pal, base, rng.int(0, 999)));
  const mat = kit.toon(0xffffff, { map: tex });
  const g1 = kit.geo('crate', () => chamferBox(0.62, 0.48, 0.62, 0.05));
  g.add(m(g1, mat));
  if (def.variant === 'stack' || (def.variant === undefined && rng.chance(0.4))) {
    const top = m(kit.geo('crateS', () => chamferBox(0.42, 0.34, 0.42, 0.04)), mat, rng.range(-0.06, 0.06), 0.48, rng.range(-0.06, 0.06));
    top.rotation.y = rng.range(-0.4, 0.4);
    g.add(top);
  }
  ctx.blob(def.x, def.y, 0.5);
  return place(g, def);
}

function barrel(def: DecorDef, ctx: DecorCtx): THREE.Object3D {
  const { kit, pal } = ctx;
  const g = new THREE.Group();
  const rng = new Rng(hashString(`br${def.x},${def.y}`) ^ ctx.seed);
  const colors: Record<string, number> = { red: 0xc8323a, yellow: pal.hazard, pink: pal.graffiti, rust: pal.rust, metal: pal.metal };
  const color = colors[def.variant ?? ''] ?? rng.pick([0xc8323a, pal.hazard, pal.rust, pal.floorFinish === 'stone' ? pal.graffiti : pal.metal]);
  const body = m(kit.geo('barrel', () => new THREE.CylinderGeometry(0.23, 0.23, 0.62, 12)), kit.toon(color), 0, 0.31, 0);
  g.add(body);
  const band = kit.geo('barrelBand', () => new THREE.CylinderGeometry(0.245, 0.245, 0.05, 12));
  const bandMat = kit.toon(scaleColor(color, 0.6));
  g.add(m(band, bandMat, 0, 0.14, 0));
  g.add(m(band, bandMat, 0, 0.48, 0));
  g.add(m(kit.geo('barrelLid', () => new THREE.CylinderGeometry(0.2, 0.2, 0.02, 12)), kit.toon(scaleColor(color, 1.2)), 0, 0.63, 0));
  ctx.blob(def.x, def.y, 0.36);
  return place(g, def);
}

function pipe(def: DecorDef, ctx: DecorCtx): THREE.Object3D {
  const { kit, pal } = ctx;
  const g = new THREE.Group();
  const color = pal.floorFinish === 'metal' ? pal.metal : pal.hazard;
  const mat = kit.toon(color);
  const flange = kit.toon(scaleColor(color, 0.65));
  const r = 0.11;
  // Rises out of the floor, bends, runs one tile along +X, and drops back in.
  const vert = kit.geo('pipeV', () => new THREE.CylinderGeometry(r, r, 0.42, 10));
  const horiz = kit.geo('pipeH', () => new THREE.CylinderGeometry(r, r, 0.7, 10).rotateZ(Math.PI / 2));
  const elbow = kit.geo('pipeE', () => new THREE.TorusGeometry(0.14, r, 8, 10, Math.PI / 2));
  g.add(m(vert, mat, -0.49, 0.21, 0));
  g.add(m(vert, mat, 0.49, 0.21, 0));
  g.add(m(horiz, mat, 0, 0.56, 0));
  const e1 = m(elbow, mat, -0.35, 0.42, 0);
  e1.rotation.z = Math.PI / 2;
  g.add(e1);
  const e2 = m(elbow, mat, 0.35, 0.42, 0);
  g.add(e2);
  const fl = kit.geo('pipeF', () => new THREE.CylinderGeometry(r * 1.4, r * 1.4, 0.05, 10));
  for (const x of [-0.49, 0.49]) g.add(m(fl, flange, x, 0.03, 0));
  const ring = kit.geo('pipeR', () => new THREE.CylinderGeometry(r * 1.3, r * 1.3, 0.06, 10).rotateZ(Math.PI / 2));
  if (pal.floorFinish !== 'stone') {
    const glow = kit.glow(pal.neonB, { intensity: 2.4 });
    registerReactive(ctx.reactive, reactiveGlow('neon', glow));
    g.add(m(ring, glow, 0, 0.56, 0, false));
  } else {
    g.add(m(ring, flange, 0, 0.56, 0));
  }
  return place(g, def);
}

function consoleProp(def: DecorDef, ctx: DecorCtx): THREE.Object3D {
  const { kit, pal } = ctx;
  const g = new THREE.Group();
  const rng = new Rng(hashString(`co${def.x},${def.y}`) ^ ctx.seed);
  const body = pal.floorFinish === 'stone' ? pal.metal : mixColor(pal.metal, pal.trim, 0.2);
  g.add(m(kit.geo('consoleBase', () => chamferBox(0.62, 0.52, 0.42, 0.04)), kit.toon(body)));
  const head = m(kit.geo('consoleHead', () => chamferBox(0.62, 0.08, 0.36, 0.02)), kit.toon(scaleColor(body, 0.8)), 0, 0.56, 0.02);
  // Tilt the desk toward the front (+Z) so the screen faces the room.
  head.rotation.x = 0.5;
  g.add(head);
  const screenColor = pal.neonA;
  const tex = kit.texture(screenTexture(screenColor, rng.int(0, 9999), 'console'));
  const smat = kit.glow(0xffffff, { intensity: 1.6, map: tex });
  registerReactive(ctx.reactive, reactiveGlow('screen', smat, { x: def.x, y: def.y }));
  const screen = new THREE.Mesh(kit.geo('consoleScreen', () => new THREE.PlaneGeometry(0.48, 0.24)), smat);
  // Plane normal (0,0,1) rotated to the desk's tilted up-vector (0, cos .5, sin .5).
  screen.rotation.x = -(Math.PI / 2 - 0.5);
  screen.position.set(0, 0.56 + 0.085 * Math.cos(0.5), 0.02 + 0.085 * Math.sin(0.5));
  g.add(screen);
  const btn = kit.geo('btn', () => new THREE.BoxGeometry(0.06, 0.03, 0.05));
  const colors = [pal.hazard, pal.neonB, 0x7dff9a];
  for (let i = 0; i < 3; i++) g.add(m(btn, kit.glow(colors[i], { intensity: 1.4 }), -0.18 + i * 0.12, 0.44, 0.215, false));
  tex.offset.x = rng.next();
  ctx.animate.push((t) => {
    tex.offset.x = (t * 0.12) % 1;
  });
  ctx.blob(def.x, def.y, 0.45);
  return place(g, def);
}

function generator(def: DecorDef, ctx: DecorCtx): THREE.Object3D {
  const { kit, pal } = ctx;
  const g = new THREE.Group();
  const color = utilityColor(pal);
  g.add(m(kit.geo('genBase', () => chamferBox(0.86, 0.12, 0.62, 0.03)), kit.toon(pal.trim)));
  const drum = m(kit.geo('genDrum', () => new THREE.CylinderGeometry(0.26, 0.26, 0.74, 14).rotateZ(Math.PI / 2)), kit.toon(color), 0, 0.42, 0);
  g.add(drum);
  const capMat = kit.toon(scaleColor(color, 0.65));
  const cap = kit.geo('genCap', () => new THREE.CylinderGeometry(0.29, 0.29, 0.06, 14).rotateZ(Math.PI / 2));
  g.add(m(cap, capMat, -0.36, 0.42, 0));
  g.add(m(cap, capMat, 0.36, 0.42, 0));
  g.add(m(kit.geo('genBox', () => chamferBox(0.3, 0.28, 0.22, 0.03)), kit.toon(pal.metal), 0.12, 0.62, 0.0));
  g.add(m(kit.geo('genStack', () => new THREE.CylinderGeometry(0.05, 0.05, 0.4, 8)), kit.toon(pal.metal), -0.25, 0.75, -0.1));
  const glowColor = pal.floorFinish === 'stone' ? pal.warm : pal.neonB;
  const tube = kit.glow(glowColor, { intensity: 2.6 });
  registerReactive(ctx.reactive, reactiveGlow('neon', tube, { x: def.x, y: def.y }));
  g.add(m(kit.geo('genWin', () => new THREE.BoxGeometry(0.4, 0.06, 0.02)), tube, 0, 0.45, 0.262, false));
  const fan = m(kit.geo('genFan', () => new THREE.BoxGeometry(0.03, 0.34, 0.06)), kit.toon(pal.trim), 0.39, 0.42, 0);
  g.add(fan);
  ctx.animate.push((t) => {
    fan.rotation.x = t * 9;
  });
  ctx.practicals.push({ x: def.x, y: def.y, h: 0.7, color: glowColor, intensity: 3, distance: 3 });
  ctx.blob(def.x, def.y, 0.6);
  return place(g, def);
}

function vent(def: DecorDef, ctx: DecorCtx): THREE.Object3D {
  const { kit, pal } = ctx;
  const g = new THREE.Group();
  // The R03 board's air-conditioner: pale casing, round fan grille.
  const casing = pal.floorFinish === 'stone' ? 0xe8e0d0 : pal.metal;
  g.add(m(kit.geo('ventBox', () => chamferBox(0.64, 0.6, 0.42, 0.05)), kit.toon(casing)));
  const dark = kit.toon(scaleColor(pal.grout, 0.6));
  g.add(m(kit.geo('ventHole', () => new THREE.CylinderGeometry(0.22, 0.22, 0.02, 20).rotateX(Math.PI / 2)), dark, 0, 0.3, 0.212, false));
  const grille = kit.toon(scaleColor(casing, 0.7));
  g.add(m(kit.geo('ventRing', () => new THREE.TorusGeometry(0.22, 0.025, 6, 20)), grille, 0, 0.3, 0.215, false));
  const blades = new THREE.Group();
  blades.position.set(0, 0.3, 0.214);
  const blade = kit.geo('ventBlade', () => new THREE.BoxGeometry(0.06, 0.38, 0.01));
  for (let i = 0; i < 3; i++) {
    const b = m(blade, grille, 0, 0, 0, false);
    b.rotation.z = (i * Math.PI) / 3;
    blades.add(b);
  }
  g.add(blades);
  const slat = kit.geo('ventSlat', () => new THREE.BoxGeometry(0.02, 0.5, 0.36));
  for (let i = 0; i < 4; i++) g.add(m(slat, grille, 0.33, 0.3, -0.14 + i * 0.09 - 0.0, false));
  ctx.animate.push((t) => {
    blades.rotation.z = t * 5;
  });
  ctx.blob(def.x, def.y, 0.45);
  return place(g, def);
}

function arch(def: DecorDef, ctx: DecorCtx): THREE.Object3D {
  const { kit, pal } = ctx;
  const g = new THREE.Group();
  const stone = kit.toon(pal.floorFinish === 'metal' ? pal.metal : pal.stone);
  const capMat = kit.toon(pal.floorFinish === 'metal' ? pal.wallTop : scaleColor(pal.stone, 1.12));
  const pillar = kit.geo('archPillar', () => chamferBox(0.3, 1.3, 0.38, 0.04));
  g.add(m(pillar, stone, -0.62, 0, 0));
  g.add(m(pillar, stone, 0.62, 0, 0));
  const wedge = kit.geo('archWedge', () => chamferBox(0.3, 0.26, 0.38, 0.03, -0.13));
  const n = 7;
  for (let i = 0; i < n; i++) {
    const a = Math.PI - (i / (n - 1)) * Math.PI;
    const w = m(wedge, i === (n - 1) / 2 ? capMat : stone, Math.cos(a) * 0.62, 1.3 + Math.sin(a) * 0.5, 0);
    w.rotation.z = a - Math.PI / 2;
    g.add(w);
  }
  if (pal.floorFinish !== 'stone') {
    // Lower arches are metal door frames with neon strips (R04 environment modules).
    const strip = kit.glow(pal.neonB, { intensity: 2.6 });
    registerReactive(ctx.reactive, reactiveGlow('neon', strip));
    const s = kit.geo('archStrip', () => new THREE.BoxGeometry(0.05, 0.8, 0.04));
    g.add(m(s, strip, -0.47, 0.6, 0.2, false));
    g.add(m(s, strip, 0.47, 0.6, 0.2, false));
  } else {
    const leaf = kit.toon(pal.foliage);
    for (const [x, y] of [
      [-0.55, 1.45],
      [0.3, 1.85],
    ])
      g.add(m(kit.geo('leaf1', () => leafClump(1, 0.5)), leaf, x, y - 0.2, 0.05));
  }
  ctx.blob(def.x - 0.6, def.y, 0.35);
  ctx.blob(def.x + 0.6, def.y, 0.35);
  return place(g, def);
}

function rubble(def: DecorDef, ctx: DecorCtx): THREE.Object3D {
  const { kit, pal } = ctx;
  const g = new THREE.Group();
  const rng = new Rng(hashString(`ru${def.x},${def.y}`) ^ ctx.seed);
  const n = rng.int(4, 7);
  for (let i = 0; i < n; i++) {
    const s = rng.int(0, 5);
    const rock = m(kit.geo(`rock${s}`, () => rockGeometry(s * 977 + 3, 0.34)), kit.toon(scaleColor(pal.stone, rng.range(0.82, 1.1))));
    rock.position.set(rng.range(-0.35, 0.35), 0, rng.range(-0.35, 0.35));
    rock.rotation.y = rng.range(0, Math.PI * 2);
    rock.scale.setScalar(i === 0 ? 1.5 : rng.range(0.6, 1.1));
    g.add(rock);
  }
  ctx.blob(def.x, def.y, 0.5, 0.6);
  return place(g, def);
}

function chest(def: DecorDef, ctx: DecorCtx): THREE.Object3D {
  const { kit, pal } = ctx;
  const g = new THREE.Group();
  const body = pal.floorFinish === 'stone' ? 0x8a5a3a : pal.trim;
  const trimC = pal.hazard;
  g.add(m(kit.geo('chestBase', () => chamferBox(0.62, 0.3, 0.42, 0.03)), kit.toon(body)));
  const band = kit.geo('chestBand', () => new THREE.BoxGeometry(0.06, 0.31, 0.44));
  const bandMat = kit.toon(trimC);
  g.add(m(band, bandMat, -0.24, 0.155, 0, false));
  g.add(m(band, bandMat, 0.24, 0.155, 0, false));
  const open = def.variant === 'open';
  const lidPivot = new THREE.Group();
  lidPivot.position.set(0, 0.3, -0.21);
  const lid = m(kit.geo('chestLid', () => new THREE.CylinderGeometry(0.21, 0.21, 0.62, 10, 1, false, 0, Math.PI).rotateZ(Math.PI / 2).rotateX(Math.PI / 2)), kit.toon(body), 0, 0, 0.21);
  lidPivot.add(lid);
  lidPivot.rotation.x = open ? -1.9 : 0;
  g.add(lidPivot);
  g.add(m(kit.geo('chestLock', () => new THREE.BoxGeometry(0.08, 0.1, 0.03)), bandMat, 0, 0.26, 0.22, false));
  if (open) {
    const glow = kit.glow(pal.accent, { intensity: 2.2 });
    registerReactive(ctx.reactive, reactiveGlow('neon', glow, { x: def.x, y: def.y }));
    g.add(m(kit.geo('chestGlow', () => new THREE.BoxGeometry(0.5, 0.02, 0.3)), glow, 0, 0.29, 0, false));
    ctx.practicals.push({ x: def.x, y: def.y, h: 0.6, color: pal.accent, intensity: 2, distance: 2.4 });
  }
  ctx.blob(def.x, def.y, 0.45);
  return place(g, def);
}

function neon(def: DecorDef, ctx: DecorCtx): THREE.Object3D {
  const { kit, pal } = ctx;
  const g = new THREE.Group();
  const rng = new Rng(hashString(`n${def.x},${def.y}`) ^ ctx.seed);
  const color = neonColor(def.variant, pal, rng);
  const core = kit.glow(color, { intensity: 3 });
  registerReactive(ctx.reactive, reactiveGlow('neon', core, { x: def.x, y: def.y }));
  g.add(m(kit.geo('neonCore', () => new THREE.CylinderGeometry(0.055, 0.055, 0.8, 10)), core, 0, 0.55, 0, false));
  const glass = kit.glow(color, { intensity: 0.5, additive: true, opacity: 0.6 });
  g.add(m(kit.geo('neonGlass', () => new THREE.CylinderGeometry(0.1, 0.1, 0.82, 12, 1, true)), glass, 0, 0.55, 0, false));
  const cap = kit.geo('neonCap', () => new THREE.CylinderGeometry(0.12, 0.13, 0.12, 10));
  const capMat = kit.toon(pal.metal);
  g.add(m(cap, capMat, 0, 0.1, 0));
  g.add(m(cap, capMat, 0, 1.0, 0));
  g.add(m(kit.geo('neonFoot', () => chamferBox(0.32, 0.06, 0.32, 0.02)), kit.toon(pal.trim)));
  ctx.practicals.push({ x: def.x, y: def.y, h: 0.6, color, intensity: 4, distance: 3.2 });
  ctx.blob(def.x, def.y, 0.3);
  return place(g, def);
}

function runePanel(def: DecorDef, ctx: DecorCtx): THREE.Object3D {
  const { kit, pal } = ctx;
  const g = new THREE.Group();
  const seed = hashString(`rp${def.x},${def.y}`) ^ ctx.seed;
  g.add(m(kit.geo('rpSlab', () => chamferBox(0.62, 1.35, 0.2, 0.04)), kit.toon(pal.floorFinish === 'stone' ? pal.stone : pal.metal)));
  g.add(m(kit.geo('rpCap', () => chamferBox(0.7, 0.1, 0.26, 0.03, 1.35)), kit.toon(pal.wallTop)));
  const tex = kit.texture(runePanelTexture(seed));
  const color = def.variant ? neonColor(def.variant, pal, new Rng(seed)) : pal.rune;
  const glyph = kit.glow(color, { intensity: 2.4, map: tex, additive: true });
  registerReactive(ctx.reactive, reactiveGlow('rune', glyph, { x: def.x, y: def.y }));
  const face = new THREE.Mesh(kit.geo('rpFace', () => new THREE.PlaneGeometry(0.42, 1.18)), glyph);
  face.position.set(0, 0.68, 0.104);
  g.add(face);
  ctx.blob(def.x, def.y, 0.4);
  return place(g, def);
}

function waveScreen(def: DecorDef, ctx: DecorCtx): THREE.Object3D {
  const { kit, pal } = ctx;
  const g = new THREE.Group();
  const seed = hashString(`ws${def.x},${def.y}`) ^ ctx.seed;
  const frame = kit.toon(pal.floorFinish === 'stone' ? pal.metal : pal.trim);
  g.add(m(kit.geo('wsFrame', () => chamferBox(1.0, 0.66, 0.12, 0.03, 0.42)), frame));
  const leg = kit.geo('wsLeg', () => new THREE.BoxGeometry(0.06, 0.44, 0.06));
  g.add(m(leg, frame, -0.35, 0.22, 0));
  g.add(m(leg, frame, 0.35, 0.22, 0));
  const color = def.variant ? neonColor(def.variant, pal, new Rng(seed)) : pal.neonA;
  const tex = kit.texture(screenTexture(color, seed, 'wave'));
  tex.repeat.set(1, 1);
  const smat = kit.glow(0xffffff, { intensity: 1.8, map: tex });
  registerReactive(ctx.reactive, reactiveGlow('screen', smat, { x: def.x, y: def.y }));
  const screen = new THREE.Mesh(kit.geo('wsScreen', () => new THREE.PlaneGeometry(0.86, 0.52)), smat);
  screen.position.set(0, 0.75, 0.062);
  g.add(screen);
  ctx.animate.push((t) => {
    tex.offset.x = (t * 0.25) % 1;
  });
  ctx.blob(def.x, def.y, 0.5);
  return place(g, def);
}

function cable(def: DecorDef, ctx: DecorCtx): THREE.Object3D {
  const { kit, pal } = ctx;
  const g = new THREE.Group();
  // Cable spool (R03 prop library) with a loose run trailing off it.
  const spoolMat = kit.toon(pal.floorFinish === 'stone' ? pal.graffiti : pal.trim);
  const disc = kit.geo('spoolDisc', () => new THREE.CylinderGeometry(0.28, 0.28, 0.04, 16).rotateX(Math.PI / 2));
  g.add(m(disc, spoolMat, 0, 0.28, -0.14));
  g.add(m(disc, spoolMat, 0, 0.28, 0.14));
  const coil = kit.toon(pal.floorFinish === 'stone' ? 0x3a3a3a : 0x1e1a24);
  const wrap = kit.geo('spoolWrap', () => new THREE.CylinderGeometry(0.2, 0.2, 0.24, 14).rotateX(Math.PI / 2));
  g.add(m(wrap, coil, 0, 0.28, 0));
  const curve = new THREE.CatmullRomCurve3([
    new THREE.Vector3(0.1, 0.1, 0.05),
    new THREE.Vector3(0.35, 0.02, 0.2),
    new THREE.Vector3(0.55, 0.02, -0.1),
    new THREE.Vector3(0.75, 0.02, 0.15),
  ]);
  g.add(m(kit.geo('cableRun', () => new THREE.TubeGeometry(curve, 16, 0.025, 5, false)), coil, 0, 0, 0, false));
  ctx.blob(def.x, def.y, 0.4);
  return place(g, def);
}

function lamp(def: DecorDef, ctx: DecorCtx): THREE.Object3D {
  const { kit, pal } = ctx;
  const g = new THREE.Group();
  const metal = kit.toon(pal.floorFinish === 'stone' ? 0x3c342e : pal.trim);
  g.add(m(kit.geo('lampFoot', () => chamferBox(0.26, 0.08, 0.26, 0.02)), metal));
  g.add(m(kit.geo('lampPost', () => new THREE.CylinderGeometry(0.035, 0.045, 0.95, 8)), metal, 0, 0.5, 0));
  g.add(m(kit.geo('lampCage', () => new THREE.CylinderGeometry(0.12, 0.12, 0.24, 6, 1, true)), metal, 0, 1.08, 0));
  g.add(m(kit.geo('lampTop', () => new THREE.ConeGeometry(0.16, 0.1, 6)), metal, 0, 1.25, 0));
  const color = def.variant ? neonColor(def.variant, pal, new Rng(1)) : pal.warm;
  const core = kit.glow(color, { intensity: 3 });
  registerReactive(ctx.reactive, reactiveGlow('neon', core, { x: def.x, y: def.y }));
  g.add(m(kit.geo('lampCore', () => new THREE.CylinderGeometry(0.08, 0.08, 0.18, 8)), core, 0, 1.08, 0, false));
  ctx.practicals.push({ x: def.x, y: def.y, h: 1.1, color, intensity: 5, distance: 4 });
  ctx.blob(def.x, def.y, 0.3);
  return place(g, def);
}

/**
 * WORLD-05: the bottom loot is a time machine. Its look is not defined beyond that, so this is a
 * gyroscopic ring gate on a rune dais with cassette-reel housings (tying it to the Walkman / tape
 * mechanics) and a chronal core.
 */
function timeMachine(def: DecorDef, ctx: DecorCtx): THREE.Object3D {
  const { kit, pal } = ctx;
  const g = new THREE.Group();
  const metal = kit.toon(pal.metal);
  const dark = kit.toon(pal.trim);
  const brass = kit.toon(0xc89a3a);
  g.add(m(kit.geo('tmDais1', () => new THREE.CylinderGeometry(1.6, 1.7, 0.22, 8)), dark, 0, 0.11, 0));
  g.add(m(kit.geo('tmDais2', () => new THREE.CylinderGeometry(1.2, 1.3, 0.2, 8)), metal, 0, 0.32, 0));
  const runeRing = kit.glow(pal.accent, { intensity: 2.6 });
  registerReactive(ctx.reactive, reactiveGlow('rune', runeRing, { x: def.x, y: def.y }));
  const ring0 = m(kit.geo('tmRuneRing', () => new THREE.TorusGeometry(1.45, 0.03, 4, 48).rotateX(Math.PI / 2)), runeRing, 0, 0.225, 0, false);
  g.add(ring0);
  // Pylons with neon strips.
  const pylon = kit.geo('tmPylon', () => chamferBox(0.26, 1.7, 0.26, 0.04));
  const strip = kit.glow(pal.neonA, { intensity: 2.6 });
  registerReactive(ctx.reactive, reactiveGlow('neon', strip, { x: def.x, y: def.y }));
  for (let i = 0; i < 4; i++) {
    const a = (i / 4) * Math.PI * 2 + Math.PI / 4;
    const p = m(pylon, metal, Math.cos(a) * 1.45, 0.2, Math.sin(a) * 1.45);
    g.add(p);
    const s = m(kit.geo('tmStrip', () => new THREE.BoxGeometry(0.06, 1.2, 0.06)), strip, Math.cos(a) * 1.32, 1.0, Math.sin(a) * 1.32, false);
    g.add(s);
  }
  // Cassette-reel housings either side.
  const reelMat = kit.toon(pal.hazard);
  const reel = kit.geo('tmReel', () => new THREE.CylinderGeometry(0.34, 0.34, 0.1, 6).rotateX(Math.PI / 2));
  const hub = kit.geo('tmHub', () => new THREE.CylinderGeometry(0.12, 0.12, 0.14, 6).rotateX(Math.PI / 2));
  const reels: THREE.Mesh[] = [];
  for (const x of [-0.9, 0.9]) {
    const housing = m(kit.geo('tmHousing', () => chamferBox(0.6, 0.7, 0.3, 0.05)), dark, x, 0.42, 0.55);
    g.add(housing);
    const r = m(reel, reelMat, x, 0.78, 0.72);
    g.add(r);
    g.add(m(hub, metal, x, 0.78, 0.74));
    reels.push(r);
  }
  // Gyroscope rings.
  const ringOuter = m(kit.geo('tmRingA', () => new THREE.TorusGeometry(1.0, 0.09, 8, 40)), brass, 0, 1.55, 0);
  const ringMid = m(kit.geo('tmRingB', () => new THREE.TorusGeometry(0.78, 0.07, 8, 36)), metal, 0, 0, 0);
  const ringInner = m(kit.geo('tmRingC', () => new THREE.TorusGeometry(0.58, 0.05, 8, 32)), brass, 0, 0, 0);
  const gimbal = new THREE.Group();
  gimbal.position.set(0, 1.55, 0);
  ringOuter.position.set(0, 0, 0);
  gimbal.add(ringOuter);
  ringOuter.add(ringMid);
  ringMid.add(ringInner);
  g.add(gimbal);
  g.add(m(kit.geo('tmStem', () => new THREE.CylinderGeometry(0.1, 0.16, 0.6, 8)), metal, 0, 0.6, 0));
  const coreMat = kit.toon(pal.accent, { emissive: pal.accent, emissiveIntensity: 2.2 });
  registerReactive(ctx.reactive, reactiveToon('core', coreMat, { x: def.x, y: def.y }));
  const core = m(kit.geo('tmCore', () => new THREE.IcosahedronGeometry(0.28, 0)), coreMat, 0, 1.55, 0, false);
  g.add(core);
  const halo = kit.glow(pal.accent, { intensity: 0.9, additive: true, opacity: 0.5 });
  const haloMesh = m(kit.geo('tmHalo', () => new THREE.IcosahedronGeometry(0.42, 1)), halo, 0, 1.55, 0, false);
  g.add(haloMesh);
  ctx.animate.push((t) => {
    gimbal.rotation.y = t * 0.35;
    ringOuter.rotation.x = Math.sin(t * 0.4) * 0.5;
    ringMid.rotation.y = t * 0.9;
    ringInner.rotation.x = t * 1.4;
    core.rotation.set(t * 0.7, t * 1.1, 0);
    const bob = Math.sin(t * 1.6) * 0.06;
    core.position.y = 1.55 + bob;
    haloMesh.position.y = 1.55 + bob;
    haloMesh.scale.setScalar(1 + Math.sin(t * 3.2) * 0.06);
    reels[0].rotation.z = t * 2;
    reels[1].rotation.z = t * 2;
  });
  ctx.practicals.push({ x: def.x, y: def.y, h: 1.6, color: pal.accent, intensity: 9, distance: 6 });
  ctx.blob(def.x, def.y, 1.8, 0.7);
  return place(g, def);
}

const BUILDERS: Record<DecorDef['type'], (def: DecorDef, ctx: DecorCtx) => THREE.Object3D> = {
  graffiti,
  vines,
  bush,
  crate,
  barrel,
  pipe,
  console: consoleProp,
  generator,
  vent,
  arch,
  rubble,
  chest,
  neon,
  runePanel,
  waveScreen,
  cable,
  lamp,
  timeMachine,
};

export function buildDecor(def: DecorDef, ctx: DecorCtx): THREE.Object3D | null {
  const build = BUILDERS[def.type];
  if (!build) return null;
  const obj = build(def, ctx);
  obj.name = `decor:${def.type}`;
  return obj;
}
