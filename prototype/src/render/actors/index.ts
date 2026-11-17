/**
 * Actor layer: everything alive on screen — the four selves (Moxie), enemies and projectiles.
 * Draws into ctx.root through the RenderLayer seam (src/render/layer.ts); never touches the shell.
 *
 * Per frame: interpolate prev → snap by alpha, update pooled views, step particles. Views are
 * created at loadLevel (selves, prewarmed enemy/projectile pools) so the frame loop does not
 * allocate GPU resources; a new enemy/projectile id only allocates if its pool runs dry.
 */
import * as THREE from 'three';
import type { RenderFrame } from '../../contracts';
import {
  TAPE_COLORS,
  TAPE_NAMES,
  type EnemyType,
  type ProjectileSnap,
  type TapeIndex,
} from '../../core/types';
import type { RenderCtx, RenderLayer } from '../layer';
import {
  brokenRingGeometry,
  chevronGeometry,
  flatDisc,
  flatRing,
  letterTexture,
  sectorGeometry,
  unitStripGeometry,
} from './decals';
import { buildEnemySpec, disposeEnemySpec, ENEMY_COLORS, shieldDomeGeometry, type EnemyRigSpec } from './enemyModels';
import { EnemyView, type EnemyFrameEnv, type EnemyShared } from './enemyView';
import {
  createActorInterp,
  createEnemyInterp,
  createProjectileInterp,
  findActor,
  findEnemy,
  findProjectile,
  interpActor,
  interpEnemy,
  interpProjectile,
  type ActorInterp,
} from './interp';
import { applyPaletteLight, createSharedUniforms, type SharedUniforms } from './materials';
import { parseHexColor } from './math';
import { buildMoxieGeometry, disposeMoxieGeometry, type MoxieGeometry } from './moxie';
import { ParticleSystem } from './particles';
import { KeyedPool } from './pool';
import { ProjectileView, type ProjectileFrameEnv, type ProjectileKind, type ProjectileShared } from './projectileView';
import { SelfView, type SelfFrameEnv, type SelfShared } from './selfView';

const ENEMY_TYPES: readonly EnemyType[] = ['grunt', 'stalker', 'turret', 'shielder', 'brute', 'drone', 'boss'];
const PROJECTILE_KINDS: readonly ProjectileKind[] = ['missile', 'pierce', 'phase', 'arc', 'burst', 'bolt', 'shock'];

/** Everything built per level; dropped and disposed on the next loadLevel / dispose. */
interface LevelAssets {
  root: THREE.Group;
  shared: SharedUniforms;
  moxieGeo: MoxieGeometry;
  selves: SelfView[];
  enemySpecs: Map<EnemyType, EnemyRigSpec>;
  enemyPools: Map<EnemyType, KeyedPool<string, EnemyView>>;
  projPools: Map<ProjectileKind, KeyedPool<number, ProjectileView>>;
  /** Same pools as arrays, so the frame loop iterates without Map iterators. */
  enemyPoolList: KeyedPool<string, EnemyView>[];
  projPoolList: KeyedPool<number, ProjectileView>[];
  dust: ParticleSystem;
  glow: ParticleSystem;
  geometries: THREE.BufferGeometry[];
  textures: THREE.Texture[];
  tapeColors: THREE.Color[];
}

export function createActorLayer(): RenderLayer {
  return new ActorLayer();
}

class ActorLayer implements RenderLayer {
  private L: LevelAssets | null = null;
  private time = 0;
  private readonly actorInterp: ActorInterp[] = [createActorInterp(), createActorInterp(), createActorInterp(), createActorInterp()];
  private readonly enemyInterp = createEnemyInterp();
  private readonly projInterp = createProjectileInterp();
  private readonly hits = new Set<string>();
  private readonly camRight = new THREE.Vector3();
  private readonly camQuat = new THREE.Quaternion();
  private readonly camDir = new THREE.Vector3();
  private readonly posScratch = { x: 0, y: 0 };
  private readonly dangerColor = new THREE.Color(ENEMY_COLORS.danger);
  private selfEnv: SelfFrameEnv = {
    dt: 0,
    time: 0,
    beatPulse: 0,
    camRight: this.camRight,
    camQuat: this.camQuat,
    camFwdX: 0,
    camFwdZ: 1,
    isLive: false,
    flourish: 0,
  };
  private enemyEnv: EnemyFrameEnv = {
    dt: 0,
    time: 0,
    camQuat: this.camQuat,
    selfPos: (tape) => {
      const s = this.L?.selves[tape];
      return s && s.isVisible ? s.pos : null;
    },
    tapeColor: (tape) => this.L?.tapeColors[tape] ?? this.dangerColor,
    hitThisFrame: (id) => this.hits.has(id),
  };
  private snapRef: RenderFrame['snap'] | null = null;
  private projEnv: ProjectileFrameEnv = {
    dt: 0,
    time: 0,
    camQuat: this.camQuat,
    enemyPos: (id) => {
      const snap = this.snapRef;
      if (!snap) return null;
      const e = findEnemy(snap.enemies, id, -1);
      if (!e || !e.alive) return null;
      this.posScratch.x = e.x;
      this.posScratch.y = e.y;
      return this.posScratch;
    },
  };

  loadLevel(ctx: RenderCtx): void {
    this.disposeLevel();
    const root = new THREE.Group();
    root.name = 'actors';
    ctx.root.add(root);
    const shared = createSharedUniforms(ctx.toonRamp);
    const pal = ctx.palette;
    applyPaletteLight(shared, pal.keyLight, pal.keyIntensity, pal.ambient, pal.ambientIntensity);
    const looks = ctx.loadout.looks ?? {};
    const moxieGeo = buildMoxieGeometry(ctx.loadout.melee, looks);
    const tapeColors = TAPE_COLORS.map((c) => new THREE.Color(parseHexColor(c, 0xffffff)));

    const dust = new ParticleSystem(ctx.quality === 'low' ? 384 : 768, { additive: false, overlay: false, soft: 1, renderOrder: 9 });
    const glow = new ParticleSystem(ctx.quality === 'low' ? 384 : 768, { additive: true, overlay: false, soft: 1, renderOrder: 26 });
    root.add(dust.points, glow.points);

    const geometries: THREE.BufferGeometry[] = [];
    const keep = <G extends THREE.BufferGeometry>(g: G): G => {
      geometries.push(g);
      return g;
    };
    const strip = keep(unitStripGeometry());
    const letterPlane = keep(new THREE.PlaneGeometry(0.2, 0.2).rotateX(-Math.PI / 2));
    const barGeo = keep(new THREE.PlaneGeometry(0.03, 0.09));
    const textures: THREE.Texture[] = [];
    const letterTex = TAPE_NAMES.map((n, i) => {
      const t = letterTexture(n, TAPE_COLORS[i]);
      if (t) textures.push(t);
      return t;
    });
    const selfShared: SelfShared = {
      geometry: moxieGeo,
      shared,
      melee: ctx.loadout.melee,
      ranged: ctx.loadout.ranged,
      ink: pal.ink,
      dust,
      glow,
      geo: {
        ring: keep(flatRing(0.34, 0.4, 48)),
        ringOuter: keep(flatRing(0.32, 0.43, 48)),
        disc: keep(flatDisc(0.34, 40)),
        badge: keep(flatDisc(0.12, 20)),
        letter: letterPlane,
        chevron: keep(chevronGeometry(0.16, 0.12, 0.045)),
        halo: keep(brokenRingGeometry(0.13, 0.012, 4)),
        bar: barGeo,
        strip,
        mergeRing: keep(flatRing(0.85, 1.0, 40)),
        flash: keep(new THREE.SphereGeometry(0.045, 8, 6)),
      },
      letterTex,
    };
    const selves: SelfView[] = [];
    for (let i = 0; i < 4; i++) {
      const v = new SelfView(i as TapeIndex, tapeColors[i], selfShared);
      root.add(v.group, v.world);
      selves.push(v);
    }

    // Enemies.
    const enemySpecs = new Map<EnemyType, EnemyRigSpec>();
    const telegraph: Partial<Record<EnemyType, THREE.BufferGeometry>> = {};
    for (const t of ENEMY_TYPES) {
      const spec = buildEnemySpec(t);
      enemySpecs.set(t, spec);
      const tg = spec.telegraph;
      if (tg.kind === 'cone') telegraph[t] = keep(sectorGeometry(0.15, tg.reach, THREE.MathUtils.degToRad(tg.arcDeg), 24, true));
      else if (tg.kind === 'circle') telegraph[t] = keep(sectorGeometry(0, tg.radius, Math.PI * 2, 56, true));
      else if (tg.kind === 'line') {
        const g = unitStripGeometry();
        g.scale(tg.length, 1, tg.width);
        g.rotateY(-Math.PI / 2);
        telegraph[t] = keep(g);
      }
    }
    const dome = keep(shieldDomeGeometry());
    const enemyShared: EnemyShared = {
      shared,
      ink: pal.ink,
      dust,
      glow,
      geo: {
        strip,
        pip: keep(new THREE.PlaneGeometry(0.06, 0.06)),
        shadow: keep(flatDisc(0.32, 24)),
        shock: keep(flatRing(0.85, 1.0, 40)),
        arrow: keep(
          new THREE.ShapeGeometry(new THREE.Shape([new THREE.Vector2(-0.09, 0), new THREE.Vector2(0.09, 0), new THREE.Vector2(0, 0.13)])).rotateX(
            Math.PI / 2,
          ),
        ),
        dome,
        domeEdges: keep(new THREE.EdgesGeometry(dome)),
        bar: keep(new THREE.PlaneGeometry(1, 1).translate(0, 0, 0)),
        telegraph,
      },
    };
    const enemyPools = new Map<EnemyType, KeyedPool<string, EnemyView>>();
    const counts = new Map<EnemyType, number>();
    for (const ent of ctx.level.entities) if (ent.kind === 'enemy') counts.set(ent.type, (counts.get(ent.type) ?? 0) + 1);
    for (const t of ENEMY_TYPES) {
      const spec = enemySpecs.get(t)!;
      const pool = new KeyedPool<string, EnemyView>(
        () => new EnemyView(spec, enemyShared),
        (v) => {
          v.hide();
          root.remove(v.group, v.world);
        },
      );
      enemyPools.set(t, pool);
      const n = counts.get(t) ?? 0;
      // Prewarm by touching fake keys, then clearing: builds the views now, not mid-fight.
      if (n > 0) {
        for (let i = 0; i < n; i++) pool.touch(`__prewarm${i}`);
        pool.clear();
      }
    }

    // Projectiles.
    const projShared: ProjectileShared = {
      dust,
      glow,
      geo: {
        strip,
        orb: keep(new THREE.SphereGeometry(1, 10, 8)),
        lance: keep(new THREE.OctahedronGeometry(1, 0).scale(1, 1, 1)),
        missileBody: keep(
          new THREE.CapsuleGeometry(0.045, 0.2, 3, 8).rotateX(Math.PI / 2),
        ),
        missileFins: keep(finsGeometry()),
        ring: keep(new THREE.RingGeometry(0.8, 1.0, 32)),
        disc: keep(flatDisc(0.14, 16)),
        pellet: keep(new THREE.IcosahedronGeometry(1, 0)),
      },
    };
    const projPools = new Map<ProjectileKind, KeyedPool<number, ProjectileView>>();
    for (const k of PROJECTILE_KINDS) {
      const pool = new KeyedPool<number, ProjectileView>(
        () => new ProjectileView(k, projShared),
        (v) => {
          v.hide();
          root.remove(v.group, v.world);
        },
      );
      projPools.set(k, pool);
      const warm = k === ctx.loadout.ranged.archetype ? Math.max(4, ctx.loadout.ranged.count * 2) : k === 'bolt' || k === 'shock' ? (counts.size > 0 ? 4 : 0) : 0;
      for (let i = 0; i < warm; i++) pool.touch(-1 - i);
      pool.clear();
    }

    this.L = {
      root,
      shared,
      moxieGeo,
      selves,
      enemySpecs,
      enemyPools,
      projPools,
      enemyPoolList: [...enemyPools.values()],
      projPoolList: [...projPools.values()],
      dust,
      glow,
      geometries,
      textures,
      tapeColors,
    };
  }

  update(frame: RenderFrame, ctx: RenderCtx): void {
    const L = this.L;
    if (!L) return;
    // The shell clears ctx.root on level change; re-attach if something detached us.
    if (L.root.parent !== ctx.root) ctx.root.add(L.root);
    const dt = Math.min(0.1, Math.max(0, frame.dt));
    this.time += dt;
    L.shared.uTime.value = this.time;
    const snap = frame.snap;
    const prev = frame.prev ?? snap;
    this.snapRef = snap;

    // Camera-derived helpers for billboards, chroma split and the letter badge.
    const cam = ctx.camera;
    cam.updateMatrixWorld();
    this.camRight.setFromMatrixColumn(cam.matrixWorld, 0).normalize();
    cam.getWorldQuaternion(this.camQuat);
    cam.getWorldDirection(this.camDir);
    const h = Math.hypot(this.camDir.x, this.camDir.z) || 1;

    this.hits.clear();
    for (const ev of frame.events) if ((ev.type === 'hit' || ev.type === 'projectileHit') && ev.id) this.hits.add(ev.id);

    // ── selves ──
    const se = this.selfEnv;
    se.dt = dt;
    se.time = this.time;
    se.beatPulse = frame.music?.beatPulse ?? 0;
    se.camFwdX = this.camDir.x / h;
    se.camFwdZ = this.camDir.z / h;
    se.flourish = frame.mode === 'cinematic' ? 1 : 0;
    for (let i = 0; i < 4; i++) {
      const view = L.selves[i];
      const cur = findActor(snap.actors, i as TapeIndex, i);
      if (!cur) {
        if (view.isVisible) view.setVisible(false);
        continue;
      }
      const p = findActor(prev.actors, i as TapeIndex, i);
      const a = interpActor(p, cur, frame.alpha, this.actorInterp[i]);
      se.isLive = cur.live || frame.active === i;
      view.update(a, se);
    }

    // ── enemies ──
    const ee = this.enemyEnv;
    ee.dt = dt;
    ee.time = this.time;
    const ep = L.enemyPoolList;
    for (let i = 0; i < ep.length; i++) ep[i].begin();
    for (let i = 0; i < snap.enemies.length; i++) {
      const cur = snap.enemies[i];
      const pool = L.enemyPools.get(cur.type);
      if (!pool) continue;
      const view = pool.touch(cur.id);
      if (pool.lastNew) {
        view.reset(cur.id);
        L.root.add(view.group, view.world);
      }
      const p = findEnemy(prev.enemies, cur.id, i);
      view.update(interpEnemy(p, cur, frame.alpha, this.enemyInterp), ee);
    }
    for (let i = 0; i < ep.length; i++) ep[i].sweep(this.keepDyingEnemy);

    // ── projectiles ──
    const pe = this.projEnv;
    pe.dt = dt;
    pe.time = this.time;
    const pp = L.projPoolList;
    for (let i = 0; i < pp.length; i++) pp[i].begin();
    for (let i = 0; i < snap.projectiles.length; i++) {
      const cur = snap.projectiles[i];
      const pool = L.projPools.get(cur.archetype);
      if (!pool) continue;
      const view = pool.touch(cur.id);
      if (pool.lastNew) {
        view.reset(cur.id, this.ownerColor(cur.owner, L));
        L.root.add(view.group, view.world);
      }
      const p = findProjectile(prev.projectiles, cur.id, i);
      view.update(interpProjectile(p, cur, frame.alpha, this.projInterp), cur.targetId, pe);
    }
    for (let i = 0; i < pp.length; i++) pp[i].sweep(this.popProjectile);

    L.dust.update(dt);
    L.glow.update(dt);
  }

  /** Bound once: an enemy that left the snapshot plays out its death before its view is recycled. */
  private readonly keepDyingEnemy = (v: EnemyView): boolean => {
    v.vanish(this.enemyEnv);
    return v.dying;
  };

  private readonly popProjectile = (v: ProjectileView): boolean => {
    v.pop();
    return false;
  };

  private ownerColor(owner: ProjectileSnap['owner'], L: LevelAssets): THREE.Color {
    if ('tape' in owner) return L.tapeColors[owner.tape] ?? this.dangerColor;
    return this.dangerColor;
  }

  private disposeLevel(): void {
    const L = this.L;
    if (!L) return;
    L.root.parent?.remove(L.root);
    for (const s of L.selves) s.dispose();
    for (const pool of L.enemyPools.values()) for (const v of pool.all()) v.dispose();
    for (const pool of L.projPools.values()) for (const v of pool.all()) v.dispose();
    for (const spec of L.enemySpecs.values()) disposeEnemySpec(spec);
    disposeMoxieGeometry(L.moxieGeo);
    for (const g of L.geometries) g.dispose();
    for (const t of L.textures) t.dispose();
    L.dust.dispose();
    L.glow.dispose();
    this.L = null;
  }

  dispose(): void {
    this.disposeLevel();
  }
}

function finsGeometry(): THREE.BufferGeometry {
  // Four swept fins and a coloured nose band for the missile.
  const parts: THREE.BufferGeometry[] = [];
  for (let i = 0; i < 4; i++) {
    const f = new THREE.BoxGeometry(0.008, 0.07, 0.07);
    f.translate(0, 0.055, -0.1);
    f.rotateZ((i * Math.PI) / 2 + Math.PI / 4);
    parts.push(f.toNonIndexed());
    f.dispose();
  }
  const band = new THREE.CylinderGeometry(0.05, 0.05, 0.03, 10).rotateX(Math.PI / 2);
  band.translate(0, 0, 0.08);
  parts.push(band.toNonIndexed());
  band.dispose();
  let total = 0;
  for (const p of parts) total += p.getAttribute('position').count;
  const pos = new Float32Array(total * 3);
  const nrm = new Float32Array(total * 3);
  let off = 0;
  for (const p of parts) {
    const n = p.getAttribute('position').count;
    pos.set(p.getAttribute('position').array as Float32Array, off * 3);
    nrm.set(p.getAttribute('normal').array as Float32Array, off * 3);
    off += n;
    p.dispose();
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.BufferAttribute(nrm, 3));
  g.computeBoundingSphere();
  return g;
}
