/**
 * Mesh sets for a Moxie rig. Each rig part gets five meshes sharing one geometry:
 *   prepass — depth only; lets translucent styles draw a clean silhouette (no inner overdraw) and
 *             makes the playback ghost hollow (only the hull rim survives the depth test).
 *   fill    — the cel-shaded body (opaque twin or transparent twin of the same shader).
 *   hull    — inverted-hull ink outline in the cassette colour (UI-02).
 *   echoA/B — red / cyan world-shifted copies for the desync chromatic split.
 */
import * as THREE from 'three';
import {
  createCelMaterial,
  createDepthOnlyMaterial,
  createEchoMaterial,
  createHullMaterial,
  type CelMaterial,
  type HullMaterial,
  type SharedUniforms,
} from './materials';
import { BONE_NAMES, createMoxieBones, type MoxieBones, type MoxieGeometry } from './moxie';

export type MeshMode = 'solid' | 'fx' | 'hollow';

/** Hull thickness for Moxie in scene units: chunky enough to read as anime ink at iso scale. */
export const MOXIE_HULL = 0.011;

export class MoxieMesh {
  readonly bones: MoxieBones;
  readonly solidMat: CelMaterial;
  readonly fxMat: CelMaterial;
  readonly hullMat: HullMaterial;
  readonly hullFxMat: HullMaterial;
  readonly echoMatA: HullMaterial;
  readonly echoMatB: HullMaterial;
  /**
   * The headphones keep a dark ink outline while solid: on tape B the cassette colour is yellow
   * too, and a yellow rim would swallow the signature yellow cups (CHAR-05).
   */
  readonly inkHullMat: HullMaterial;
  private readonly depthMat: THREE.MeshBasicMaterial;
  private readonly prepass: THREE.Mesh[] = [];
  private readonly fills: THREE.Mesh[] = [];
  private readonly hulls: THREE.Mesh[] = [];
  private readonly echoA: THREE.Mesh[] = [];
  private readonly echoB: THREE.Mesh[] = [];
  private readonly inkHull: boolean[] = [];
  private mode: MeshMode | null = null;
  private echoes: boolean | null = null;

  constructor(geo: MoxieGeometry, shared: SharedUniforms, outline: number, ink: number) {
    this.bones = createMoxieBones();
    this.solidMat = createCelMaterial(shared, false);
    this.fxMat = createCelMaterial(shared, true);
    this.fxMat.depthWrite = false;
    this.hullMat = createHullMaterial(outline, MOXIE_HULL, false);
    this.hullFxMat = createHullMaterial(outline, MOXIE_HULL, true);
    this.echoMatA = createEchoMaterial(0xff2a5a);
    this.echoMatB = createEchoMaterial(0x2ae8ff);
    this.inkHullMat = createHullMaterial(ink, MOXIE_HULL * 0.8, false);
    this.depthMat = createDepthOnlyMaterial();
    for (const name of BONE_NAMES) {
      const g = geo[name];
      if (!g) continue;
      const bone = this.bones.bones[name];
      const pre = new THREE.Mesh(g, this.depthMat);
      const fill = new THREE.Mesh(g, this.solidMat);
      const hull = new THREE.Mesh(g, this.hullMat);
      const ea = new THREE.Mesh(g, this.echoMatA);
      const eb = new THREE.Mesh(g, this.echoMatB);
      pre.renderOrder = 30;
      ea.renderOrder = 33;
      eb.renderOrder = 33;
      for (const m of [pre, fill, hull, ea, eb]) {
        // Parts are tiny and the rig deforms them; the per-part culling test costs more than it saves.
        m.frustumCulled = false;
        bone.add(m);
      }
      this.prepass.push(pre);
      this.fills.push(fill);
      this.hulls.push(hull);
      this.echoA.push(ea);
      this.echoB.push(eb);
      this.inkHull.push(name === 'phones');
    }
    this.setMode('solid', false);
  }

  setMode(mode: MeshMode, echoes: boolean): void {
    if (mode === this.mode && echoes === this.echoes) return;
    this.mode = mode;
    this.echoes = echoes;
    const n = this.fills.length;
    for (let i = 0; i < n; i++) {
      const pre = this.prepass[i];
      const fill = this.fills[i];
      const hull = this.hulls[i];
      pre.visible = mode !== 'solid';
      fill.visible = mode !== 'hollow';
      fill.material = mode === 'solid' ? this.solidMat : this.fxMat;
      fill.renderOrder = mode === 'solid' ? 0 : 31;
      hull.material = mode === 'solid' ? (this.inkHull[i] ? this.inkHullMat : this.hullMat) : this.hullFxMat;
      hull.renderOrder = mode === 'solid' ? 0 : 32;
      this.echoA[i].visible = echoes;
      this.echoB[i].visible = echoes;
    }
  }

  /** The material whose uniforms currently drive the visible body. */
  get bodyMat(): CelMaterial {
    return this.mode === 'solid' ? this.solidMat : this.fxMat;
  }

  setOutline(color: THREE.Color): void {
    this.hullMat.uniforms.uColor.value.copy(color);
    this.hullFxMat.uniforms.uColor.value.copy(color);
  }

  dispose(): void {
    this.solidMat.dispose();
    this.fxMat.dispose();
    this.hullMat.dispose();
    this.hullFxMat.dispose();
    this.echoMatA.dispose();
    this.echoMatB.dispose();
    this.inkHullMat.dispose();
    this.depthMat.dispose();
  }
}

/** Light rig used for dodge afterimages: fill meshes only, one flat additive material. */
export class EchoRig {
  readonly bones: MoxieBones;
  readonly mat: HullMaterial;

  constructor(geo: MoxieGeometry, color: THREE.Color) {
    this.bones = createMoxieBones();
    this.mat = createEchoMaterial(color.getHex());
    this.mat.uniforms.uColor.value.copy(color);
    // Normal blending: additive afterimages stack into a white blob where parts overlap.
    this.mat.blending = THREE.NormalBlending;
    for (const name of BONE_NAMES) {
      const g = geo[name];
      if (!g) continue;
      const m = new THREE.Mesh(g, this.mat);
      m.frustumCulled = false;
      m.renderOrder = 29;
      this.bones.bones[name].add(m);
    }
    this.bones.root.visible = false;
  }

  dispose(): void {
    this.mat.dispose();
  }
}
