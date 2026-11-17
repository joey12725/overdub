/**
 * Mechanism visuals, driven purely by MechSnap (types.ts): the renderer never infers state, so a
 * review or cinematic replay always shows exactly what the resolved run did (CINE-04).
 *
 * Readability (chapter 19: functional doors and walls must be distinguishable from decorative
 * remnants): every functional piece carries an accent colour shared with whatever drives it
 * (accent.ts), lit when active and dim when not.
 */
import * as THREE from 'three';
import type {
  BreakableDef,
  CoreDef,
  DoorDef,
  ExitDef,
  LaserDef,
  LevelDef,
  MechSnap,
  PlateDef,
  SimEvent,
  SwitchDef,
} from '../../core/types';
import type { RenderFrame } from '../../contracts';
import type { LevelLayout } from '../env/layout';
import { chamferBox, rockGeometry } from '../env/geom';
import { Rng, hashString } from '../env/rng';
import { crackTextures, dashTexture, exitTexture, hazardTexture } from '../env/textures';
import type { MaterialKit } from '../materials';
import { type EnvPalette, mixColor, scaleColor } from '../palettes';
import { EXIT_ACCENT, LASER_BEAM, buildAccentMap, exprAccent } from './accent';

export { buildAccentMap, exprAccent, signalAccent, exprSignals, MECH_ACCENTS } from './accent';

interface MechVisual {
  readonly id: string;
  readonly object: THREE.Object3D;
  apply(snap: MechSnap, dt: number, time: number): void;
  /** Animate even when no snapshot mentions this mechanism this frame. */
  tick(dt: number, time: number): void;
  /** A 'break' / 'core' event for this id, with direction where meaningful. */
  event?(e: SimEvent): void;
}

const damp = (a: number, b: number, rate: number, dt: number): number => b + (a - b) * Math.exp(-rate * dt);

/** A glow whose brightness is set per frame without allocating. */
class Lamp {
  readonly material: THREE.MeshBasicMaterial;
  private readonly base: THREE.Color;

  constructor(kit: MaterialKit, color: number, additive = false, opacity = 1) {
    this.material = kit.glow(color, { intensity: 1, additive, opacity, side: THREE.FrontSide, depthWrite: !additive });
    this.base = new THREE.Color(color);
  }

  set(level: number): void {
    this.material.color.copy(this.base).multiplyScalar(level);
  }
}

function mesh(geo: THREE.BufferGeometry, mat: THREE.Material | THREE.Material[], x = 0, y = 0, z = 0, shadow = true): THREE.Mesh {
  const m = new THREE.Mesh(geo, mat);
  m.position.set(x, y, z);
  m.castShadow = shadow;
  m.receiveShadow = true;
  return m;
}

// ───────────────────────────── door ─────────────────────────────

const DOOR_HEIGHT = 0.95;

function buildDoor(def: DoorDef, kit: MaterialKit, pal: EnvPalette, layout: LevelLayout, accent: number): MechVisual {
  const root = new THREE.Group();
  root.name = `door:${def.id}`;
  const cells = new Set(def.cells.map((c) => `${c.c},${c.r}`));
  const blocking = (c: number, r: number) => layout.at(c, r) === '#' || cells.has(`${c},${r}`);
  const panelMat = kit.toon(mixColor(pal.metal, accent, 0.12));
  const frameMat = kit.toon(scaleColor(pal.metal, 0.75));
  const strip = new Lamp(kit, accent);
  const slot = new Lamp(kit, accent, true, 0.85);
  const status = new Lamp(kit, 0xff3048);
  const panels: THREE.Object3D[] = [];
  const panelGeo = kit.geo('doorPanel', () => chamferBox(0.98, DOOR_HEIGHT, 0.24, 0.04));
  const stripGeo = kit.geo('doorStrip', () => new THREE.BoxGeometry(0.82, 0.07, 0.26));
  const chevGeo = kit.geo('doorChev', () => new THREE.BoxGeometry(0.06, 0.42, 0.25));
  const postGeo = kit.geo('doorPost', () => chamferBox(0.16, DOOR_HEIGHT + 0.2, 0.34, 0.03));
  const capGeo = kit.geo('doorCap', () => new THREE.BoxGeometry(0.12, 0.06, 0.3));
  const slotGeo = kit.geo('doorSlot', () => new THREE.PlaneGeometry(0.94, 0.12).rotateX(-Math.PI / 2));
  for (const cell of def.cells) {
    // Span along X when the door continues a wall line east-west, otherwise along Z.
    const alongX = blocking(cell.c - 1, cell.r) || blocking(cell.c + 1, cell.r) || !(blocking(cell.c, cell.r - 1) || blocking(cell.c, cell.r + 1));
    const g = new THREE.Group();
    g.position.set(cell.c + 0.5, 0, cell.r + 0.5);
    g.rotation.y = alongX ? 0 : Math.PI / 2;
    const panel = new THREE.Group();
    panel.add(mesh(panelGeo, panelMat));
    panel.add(mesh(stripGeo, strip.material, 0, DOOR_HEIGHT * 0.72, 0, false));
    for (const x of [-0.18, 0, 0.18]) {
      const chev = mesh(chevGeo, strip.material, x, DOOR_HEIGHT * 0.35, 0, false);
      chev.rotation.z = 0.5;
      chev.scale.y = 0.6;
      panel.add(chev);
    }
    g.add(panel);
    panels.push(panel);
    // Frame posts where the door does not butt against another door cell.
    const ends: [number, number, number][] = alongX
      ? [
          [-0.5, cell.c - 1, cell.r],
          [0.5, cell.c + 1, cell.r],
        ]
      : [
          [-0.5, cell.c, cell.r - 1],
          [0.5, cell.c, cell.r + 1],
        ];
    for (const [x, nc, nr] of ends) {
      if (cells.has(`${nc},${nr}`)) continue;
      g.add(mesh(postGeo, frameMat, x, 0, 0));
      g.add(mesh(capGeo, status.material, x, DOOR_HEIGHT + 0.22, 0, false));
    }
    // Lit floor slot on both sides of the threshold: brightens as the door opens.
    for (const z of [-0.2, 0.2]) {
      const s = new THREE.Mesh(slotGeo, slot.material);
      s.position.set(0, 0.006, z);
      g.add(s);
    }
    root.add(g);
  }
  let open = -1;
  const statusClosed = new THREE.Color(0xff3048);
  const statusOpen = new THREE.Color(accent);
  return {
    id: def.id,
    object: root,
    apply(snap, dt) {
      const target = snap.t ?? (snap.on ? 1 : 0);
      open = open < 0 ? target : snap.t !== undefined ? target : damp(open, target, 10, dt);
    },
    tick() {
      const t = Math.max(0, open);
      const e = t * t * (3 - 2 * t);
      for (const p of panels) {
        // Sinks into the floor; a sliver stays as the lit threshold so open still reads as a door.
        p.scale.y = 1 - 0.95 * e;
        p.visible = e < 0.999;
      }
      strip.set(2.4 - 1.8 * e);
      slot.set(0.4 + 2.2 * e);
      status.material.color.copy(statusClosed).lerp(statusOpen, e).multiplyScalar(2.2);
    },
  };
}

// ───────────────────────────── switch ─────────────────────────────

function buildSwitch(def: SwitchDef, kit: MaterialKit, pal: EnvPalette, accent: number): MechVisual {
  const root = new THREE.Group();
  root.name = `switch:${def.id}`;
  root.position.set(def.x, 0, def.y);
  const body = kit.toon(pal.floorFinish === 'stone' ? pal.hazard : mixColor(pal.metal, pal.hazard, 0.25));
  root.add(mesh(kit.geo('swBase', () => chamferBox(0.46, 0.34, 0.4, 0.04)), body));
  root.add(mesh(kit.geo('swTop', () => chamferBox(0.36, 0.06, 0.3, 0.02, 0.34)), kit.toon(pal.trim)));
  const pivot = new THREE.Group();
  pivot.position.set(0, 0.4, 0);
  const handleMat = kit.toon(pal.metal);
  pivot.add(mesh(kit.geo('swArm', () => new THREE.CylinderGeometry(0.03, 0.03, 0.34, 8).translate(0, 0.17, 0)), handleMat));
  const lamp = new Lamp(kit, accent);
  pivot.add(mesh(kit.geo('swKnob', () => new THREE.SphereGeometry(0.075, 12, 8)), lamp.material, 0, 0.36, 0, false));
  root.add(pivot);
  const ring = new Lamp(kit, accent, true, 0.9);
  const ringMesh = new THREE.Mesh(kit.geo('swRing', () => new THREE.RingGeometry(0.36, 0.42, 24).rotateX(-Math.PI / 2)), ring.material);
  ringMesh.position.y = 0.006;
  root.add(ringMesh);
  const face = new Lamp(kit, accent);
  root.add(mesh(kit.geo('swFace', () => new THREE.BoxGeometry(0.2, 0.08, 0.02)), face.material, 0, 0.2, 0.205, false));
  let target = def.initial ? 1 : 0;
  let s = target;
  return {
    id: def.id,
    object: root,
    apply(snap) {
      target = snap.on ? 1 : 0;
    },
    tick(dt, time) {
      s = damp(s, target, 14, dt);
      pivot.rotation.z = 0.65 - 1.3 * s;
      lamp.set(0.35 + 2.4 * s);
      face.set(0.25 + 2 * s);
      ring.set(0.3 + (1.3 + 0.3 * Math.sin(time * 4)) * s);
    },
  };
}

// ───────────────────────────── plate ─────────────────────────────

function buildPlate(def: PlateDef, kit: MaterialKit, pal: EnvPalette, accent: number): MechVisual {
  const root = new THREE.Group();
  root.name = `plate:${def.id}`;
  root.position.set(def.c + 0.5, 0, def.r + 0.5);
  const size = def.heavy ? 0.84 : 0.7;
  let frameMat: THREE.Material | THREE.Material[];
  if (def.heavy) {
    const t = kit.texture(hazardTexture(pal, hashString(def.id)));
    t.repeat.set(3, 3);
    frameMat = [kit.toon(pal.trim), kit.toon(0xffffff, { map: t })];
  } else {
    frameMat = kit.toon(pal.trim);
  }
  root.add(mesh(kit.geo(`plFrame${def.heavy ? 'H' : ''}`, () => chamferBox(size + 0.12, 0.035, size + 0.12, 0.01)), frameMat, 0, 0, 0, false));
  const pad = mesh(kit.geo(`plPad${def.heavy ? 'H' : ''}`, () => chamferBox(size - 0.06, 0.07, size - 0.06, 0.02)), kit.toon(mixColor(pal.metal, accent, 0.2)), 0, 0, 0, false);
  root.add(pad);
  const edge = new Lamp(kit, accent);
  const e = size / 2;
  const bar = kit.geo(`plBar${def.heavy ? 'H' : ''}`, () => new THREE.BoxGeometry(size, 0.03, 0.04));
  for (const [x, z, r] of [
    [0, -e, 0],
    [0, e, 0],
    [-e, 0, Math.PI / 2],
    [e, 0, Math.PI / 2],
  ]) {
    const b = mesh(bar, edge.material, x, 0.03, z, false);
    b.rotation.y = r;
    root.add(b);
  }
  const glow = new Lamp(kit, accent, true, 0.9);
  const glowMesh = new THREE.Mesh(kit.geo('plGlow', () => new THREE.PlaneGeometry(1, 1).rotateX(-Math.PI / 2)), glow.material);
  glowMesh.position.y = 0.075;
  glowMesh.scale.setScalar(size * 0.55);
  root.add(glowMesh);
  let target = 0;
  let s = 0;
  return {
    id: def.id,
    object: root,
    apply(snap) {
      target = snap.on ? 1 : 0;
    },
    tick(dt) {
      s = damp(s, target, 18, dt);
      pad.position.y = -0.045 * s;
      glowMesh.position.y = 0.075 - 0.045 * s;
      edge.set(0.45 + 2.3 * s);
      glow.set(0.0 + 1.1 * s);
    },
  };
}

// ───────────────────────────── breakable ─────────────────────────────

const BREAKABLE_HEIGHT = 1.0;

function buildBreakable(def: BreakableDef, kit: MaterialKit, pal: EnvPalette, accent: number, seed: number): MechVisual {
  const root = new THREE.Group();
  root.name = `breakable:${def.id}`;
  root.position.set(def.c + 0.5, 0, def.r + 0.5);
  const tex = crackTextures(pal, hashString(def.id) ^ seed);
  kit.texture(tex.map);
  kit.texture(tex.emissiveMap);
  const glowColor = mixColor(pal.warm, accent, 0.35);
  const side = kit.toon(0xffffff, { map: tex.map, emissiveMap: tex.emissiveMap, emissive: glowColor, emissiveIntensity: 1.4 });
  const top = kit.toon(scaleColor(mixColor(pal.wallTop, pal.rust, 0.2), 0.9));
  const block = mesh(kit.geo('brkBlock', () => chamferBox(0.96, BREAKABLE_HEIGHT, 0.96, 0.07)), [side, top]);
  root.add(block);
  // Hazard tag so the breakable reads as functional even at a glance (chapter 19).
  const tagLamp = new Lamp(kit, accent);
  const tag = mesh(kit.geo('brkTag', () => new THREE.BoxGeometry(0.5, 0.06, 0.02)), tagLamp.material, 0, BREAKABLE_HEIGHT * 0.82, 0.49, false);
  root.add(tag);
  const tag2 = mesh(kit.geo('brkTag', () => new THREE.BoxGeometry(0.5, 0.06, 0.02)), tagLamp.material, 0.49, BREAKABLE_HEIGHT * 0.82, 0, false);
  tag2.rotation.y = Math.PI / 2;
  root.add(tag2);
  tagLamp.set(1.8);

  const rng = new Rng(hashString(def.id) ^ 0xb7ea);
  const chunkMat = [side, top];
  const N = 12;
  const chunks: THREE.Mesh[] = [];
  const vel = new Float32Array(N * 3);
  const spin = new Float32Array(N * 3);
  const rest = new Float32Array(N * 3);
  const start = new Float32Array(N * 3);
  for (let i = 0; i < N; i++) {
    const s = rng.int(0, 3);
    const c = mesh(kit.geo(`brkChunk${s}`, () => rockGeometry(s * 31 + 7, 0.36, 0.8)), chunkMat[0]);
    c.visible = false;
    c.scale.setScalar(rng.range(0.6, 1.25));
    root.add(c);
    chunks.push(c);
    start[i * 3] = rng.range(-0.35, 0.35);
    start[i * 3 + 1] = rng.range(0.1, BREAKABLE_HEIGHT - 0.1);
    start[i * 3 + 2] = rng.range(-0.35, 0.35);
    const a = rng.range(0, Math.PI * 2);
    const d = rng.range(0.25, 0.9);
    rest[i * 3] = Math.cos(a) * d;
    rest[i * 3 + 1] = 0;
    rest[i * 3 + 2] = Math.sin(a) * d;
  }
  let broken = false;
  let first = true;
  let flying = 0;
  let pushX = 0;
  let pushZ = 0;
  const settle = () => {
    for (let i = 0; i < N; i++) {
      chunks[i].visible = true;
      chunks[i].position.set(rest[i * 3], 0, rest[i * 3 + 2]);
      chunks[i].rotation.set(0, i * 1.7, 0);
    }
    flying = 0;
  };
  const shatter = () => {
    for (let i = 0; i < N; i++) {
      const c = chunks[i];
      c.visible = true;
      c.position.set(start[i * 3], start[i * 3 + 1], start[i * 3 + 2]);
      const ox = start[i * 3];
      const oz = start[i * 3 + 2];
      vel[i * 3] = ox * 3 + pushX * rng.range(1.5, 3.5);
      vel[i * 3 + 1] = rng.range(1.5, 4);
      vel[i * 3 + 2] = oz * 3 + pushZ * rng.range(1.5, 3.5);
      spin[i * 3] = rng.range(-9, 9);
      spin[i * 3 + 1] = rng.range(-9, 9);
      spin[i * 3 + 2] = rng.range(-9, 9);
    }
    flying = 2.2;
  };
  return {
    id: def.id,
    object: root,
    event(e) {
      if (e.type === 'break' && e.dir !== undefined) {
        pushX = Math.cos(e.dir);
        pushZ = Math.sin(e.dir);
      }
    },
    apply(snap) {
      if (snap.on === broken && !first) return;
      const wasFirst = first;
      first = false;
      broken = snap.on;
      block.visible = !broken;
      tag.visible = !broken;
      tag2.visible = !broken;
      if (broken) {
        // Already broken when we first see it (e.g. joining a replay mid-way): show the rubble.
        if (wasFirst) settle();
        else shatter();
      } else {
        for (const c of chunks) c.visible = false;
        flying = 0;
        pushX = 0;
        pushZ = 0;
      }
    },
    tick(dt) {
      if (flying <= 0) return;
      flying -= dt;
      const step = Math.min(dt, 1 / 30);
      for (let i = 0; i < N; i++) {
        const c = chunks[i];
        vel[i * 3 + 1] -= 14 * step;
        c.position.x += vel[i * 3] * step;
        c.position.y += vel[i * 3 + 1] * step;
        c.position.z += vel[i * 3 + 2] * step;
        if (c.position.y < 0) {
          c.position.y = 0;
          vel[i * 3 + 1] *= -0.3;
          vel[i * 3] *= 0.6;
          vel[i * 3 + 2] *= 0.6;
          spin[i * 3] *= 0.5;
          spin[i * 3 + 2] *= 0.5;
        }
        c.rotation.x += spin[i * 3] * step;
        c.rotation.y += spin[i * 3 + 1] * step;
        c.rotation.z += spin[i * 3 + 2] * step;
      }
      if (flying <= 0) {
        for (const c of chunks) {
          c.position.y = 0;
          c.rotation.x = 0;
          c.rotation.z = 0;
        }
      }
    },
  };
}

// ───────────────────────────── laser ─────────────────────────────

const BEAM_Y = 0.45;

function buildLaser(def: LaserDef, kit: MaterialKit, pal: EnvPalette, accent: number): MechVisual {
  const root = new THREE.Group();
  root.name = `laser:${def.id}`;
  const dx = def.to.x - def.from.x;
  const dz = def.to.y - def.from.y;
  const len = Math.max(0.01, Math.hypot(dx, dz));
  const ang = Math.atan2(dz, dx);
  const body = kit.toon(pal.trim);
  const ringLamp = new Lamp(kit, accent);
  const lens = new Lamp(kit, LASER_BEAM);
  for (const [p, flip] of [
    [def.from, 0],
    [def.to, Math.PI],
  ] as const) {
    const g = new THREE.Group();
    g.position.set(p.x, 0, p.y);
    g.rotation.y = -ang + flip;
    g.add(mesh(kit.geo('lzBase', () => chamferBox(0.36, 0.7, 0.36, 0.04)), body));
    g.add(mesh(kit.geo('lzRing', () => new THREE.BoxGeometry(0.38, 0.05, 0.38)), ringLamp.material, 0, 0.62, 0, false));
    const l = mesh(kit.geo('lzLens', () => new THREE.CylinderGeometry(0.08, 0.08, 0.06, 12).rotateZ(Math.PI / 2)), lens.material, 0.19, BEAM_Y, 0, false);
    g.add(l);
    root.add(g);
  }
  const beam = new THREE.Group();
  beam.position.set((def.from.x + def.to.x) / 2, BEAM_Y, (def.from.y + def.to.y) / 2);
  beam.rotation.y = -ang;
  const coreLamp = new Lamp(kit, mixColor(LASER_BEAM, 0xffffff, 0.35));
  const haloLamp = new Lamp(kit, LASER_BEAM, true, 0.55);
  const core = mesh(kit.geo('lzCore', () => new THREE.CylinderGeometry(0.035, 0.035, 1, 8).rotateZ(Math.PI / 2)), coreLamp.material, 0, 0, 0, false);
  core.scale.x = len;
  const halo = mesh(kit.geo('lzHalo', () => new THREE.CylinderGeometry(0.11, 0.11, 1, 10, 1, true).rotateZ(Math.PI / 2)), haloLamp.material, 0, 0, 0, false);
  halo.scale.x = len;
  beam.add(core, halo);
  root.add(beam);
  // Off: a faint dashed guide on the floor shows where the beam will be.
  const dashTex = kit.texture(dashTexture());
  dashTex.repeat.set(len * 3, 1);
  const guideMat = kit.glow(LASER_BEAM, { intensity: 0.8, additive: true, opacity: 0.6, map: dashTex, depthWrite: false });
  const guide = new THREE.Mesh(kit.geo(`lzGuide`, () => new THREE.PlaneGeometry(1, 0.08).rotateX(-Math.PI / 2)), guideMat);
  guide.position.set(beam.position.x, 0.008, beam.position.z);
  guide.rotation.y = -ang;
  guide.scale.x = len;
  root.add(guide);
  let target = 0;
  let s = 0;
  return {
    id: def.id,
    object: root,
    apply(snap) {
      target = snap.on ? 1 : 0;
    },
    tick(dt, time) {
      s = damp(s, target, 30, dt);
      const flicker = 1 + 0.08 * Math.sin(time * 61) + 0.05 * Math.sin(time * 23);
      beam.visible = s > 0.02;
      core.scale.y = core.scale.z = 0.4 + 0.6 * s;
      halo.scale.y = halo.scale.z = (0.6 + 0.4 * s) * flicker;
      coreLamp.set(3.2 * s * flicker);
      haloLamp.set(1.4 * s);
      lens.set(0.4 + 2.6 * s);
      ringLamp.set(0.5 + 1.8 * s);
      guide.visible = s < 0.98;
      guideMat.opacity = 0.55 * (1 - s);
      dashTex.offset.x = -time * 0.6;
    },
  };
}

// ───────────────────────────── core ─────────────────────────────

function buildCore(def: CoreDef, kit: MaterialKit, pal: EnvPalette, accent: number): MechVisual {
  const root = new THREE.Group();
  root.name = `core:${def.id}`;
  root.position.set(def.x, 0, def.y);
  const metal = kit.toon(pal.metal);
  root.add(mesh(kit.geo('coreBase', () => new THREE.CylinderGeometry(0.36, 0.42, 0.22, 8)), kit.toon(pal.trim)));
  root.add(mesh(kit.geo('coreStem', () => new THREE.CylinderGeometry(0.16, 0.24, 0.3, 8)), metal, 0, 0.36, 0));
  const crystalMat = kit.toon(mixColor(pal.metal, accent, 0.3), { emissive: accent, emissiveIntensity: 0.15 });
  const crystal = mesh(kit.geo('coreCrystal', () => new THREE.OctahedronGeometry(0.24, 0).scale(1, 1.5, 1)), crystalMat, 0, 0.95, 0);
  root.add(crystal);
  const ring = new Lamp(kit, accent);
  const ringMesh = mesh(kit.geo('coreRing', () => new THREE.TorusGeometry(0.34, 0.025, 6, 32).rotateX(Math.PI / 2)), ring.material, 0, 0.55, 0, false);
  root.add(ringMesh);
  const halo = new Lamp(kit, accent, true, 0.6);
  const haloMesh = mesh(kit.geo('coreHalo', () => new THREE.IcosahedronGeometry(0.42, 1)), halo.material, 0, 0.95, 0, false);
  root.add(haloMesh);
  let target = 0;
  let s = 0;
  let spin = 0;
  let flash = 0;
  return {
    id: def.id,
    object: root,
    apply(snap) {
      const next = snap.on ? 1 : 0;
      if (next === 1 && target === 0 && s < 0.5) flash = 1;
      target = next;
    },
    tick(dt, time) {
      s = damp(s, target, 5, dt);
      flash = Math.max(0, flash - dt * 2.5);
      spin += dt * (0.5 + 3 * s);
      crystal.rotation.y = spin;
      crystal.position.y = 0.95 + s * (0.12 + Math.sin(time * 2.2) * 0.05);
      crystalMat.emissiveIntensity = 0.15 + 2.4 * s + flash * 2;
      ring.set(0.3 + 2.2 * s);
      ringMesh.scale.setScalar(1 + flash * 0.8);
      ringMesh.rotation.y = -spin * 0.5;
      halo.set(0.6 * s + flash);
      haloMesh.visible = s > 0.02 || flash > 0;
      haloMesh.position.y = crystal.position.y;
      haloMesh.scale.setScalar(1 + 0.08 * Math.sin(time * 5) + flash * 0.6);
    },
  };
}

// ───────────────────────────── exit ─────────────────────────────

function buildExit(def: ExitDef, kit: MaterialKit, pal: EnvPalette): MechVisual {
  const root = new THREE.Group();
  root.name = `exit:${def.id}`;
  root.position.set(def.c + def.w / 2, 0, def.r + def.h / 2);
  const tex = kit.texture(exitTexture());
  tex.repeat.set(def.w, def.h);
  const lamp = new Lamp(kit, EXIT_ACCENT, true, 0.9);
  lamp.material.map = tex;
  lamp.material.depthWrite = false;
  lamp.material.polygonOffset = true;
  lamp.material.polygonOffsetFactor = -2;
  lamp.material.polygonOffsetUnits = -2;
  lamp.material.needsUpdate = true;
  const plane = new THREE.Mesh(kit.geo(`exitPlane`, () => new THREE.PlaneGeometry(1, 1).rotateX(-Math.PI / 2)), lamp.material);
  plane.scale.set(def.w - 0.08, 1, def.h - 0.08);
  plane.position.y = 0.008;
  root.add(plane);
  const pylon = kit.geo('exitPylon', () => chamferBox(0.12, 0.36, 0.12, 0.02));
  const pylonMat = kit.toon(pal.metal);
  const tipLamp = new Lamp(kit, EXIT_ACCENT);
  for (const [sx, sz] of [
    [-1, -1],
    [1, -1],
    [-1, 1],
    [1, 1],
  ]) {
    const x = (sx * (def.w - 0.14)) / 2;
    const z = (sz * (def.h - 0.14)) / 2;
    root.add(mesh(pylon, pylonMat, x, 0, z));
    root.add(mesh(kit.geo('exitTip', () => new THREE.BoxGeometry(0.1, 0.06, 0.1)), tipLamp.material, x, 0.38, z, false));
  }
  let target = 0;
  let s = 0;
  return {
    id: def.id,
    object: root,
    apply(snap) {
      target = snap.on ? 1 : 0;
    },
    tick(dt, time) {
      s = damp(s, target, 8, dt);
      const breathe = 0.5 + 0.5 * Math.sin(time * 3);
      lamp.set(0.55 + 0.2 * breathe + 1.9 * s);
      tipLamp.set(0.8 + 2 * s);
      tex.offset.y = -time * (0.2 + 0.6 * s);
    },
  };
}

// ───────────────────────────── layer ─────────────────────────────

export class MechLayer {
  readonly group = new THREE.Group();
  private visuals = new Map<string, MechVisual>();
  private list: MechVisual[] = [];
  /** Signal id → accent colour for this level (shared with fx / actors via accentFor). */
  readonly accents: Map<string, number>;

  constructor(level: LevelDef, pal: EnvPalette, kit: MaterialKit, layout: LevelLayout) {
    this.group.name = 'mechs';
    this.accents = buildAccentMap(level);
    const acc = (id: string) => this.accents.get(id) ?? exprAccent({ sig: id });
    for (const e of level.entities) {
      let v: MechVisual | null = null;
      switch (e.kind) {
        case 'door':
          v = buildDoor(e, kit, pal, layout, exprAccent(e.openWhen, this.accents));
          break;
        case 'switch':
          v = buildSwitch(e, kit, pal, acc(e.id));
          break;
        case 'plate':
          v = buildPlate(e, kit, pal, acc(e.id));
          break;
        case 'breakable':
          v = buildBreakable(e, kit, pal, acc(e.id), layout.seed);
          break;
        case 'laser':
          v = buildLaser(e, kit, pal, exprAccent(e.onWhen, this.accents));
          break;
        case 'core':
          v = buildCore(e, kit, pal, acc(e.id));
          break;
        case 'exit':
          v = buildExit(e, kit, pal);
          break;
        default:
          break;
      }
      if (v) {
        this.visuals.set(v.id, v);
        this.list.push(v);
        this.group.add(v.object);
      }
    }
    // Initial state from the level data, so the first frame is right even before a snapshot.
    for (const e of level.entities) {
      if (e.kind === 'switch') this.visuals.get(e.id)?.apply({ id: e.id, kind: 'switch', on: !!e.initial }, 0, 0);
    }
  }

  /** Accent colour for a mechanism / signal id (the colour the player learns for that wire). */
  accentFor(id: string): number | undefined {
    return this.accents.get(id);
  }

  update(frame: RenderFrame, dt: number, time: number): void {
    const events = frame.events;
    for (let i = 0; i < events.length; i++) {
      const e = events[i];
      if (e.id === undefined) continue;
      const v = this.visuals.get(e.id);
      if (v?.event) v.event(e);
    }
    const mechs = frame.snap.mechs;
    for (let i = 0; i < mechs.length; i++) {
      const v = this.visuals.get(mechs[i].id);
      if (v) v.apply(mechs[i], dt, time);
    }
    for (let i = 0; i < this.list.length; i++) this.list[i].tick(dt, time);
  }
}
