/**
 * Isometric orthographic camera and its framing logic.
 *
 * ART-01: the presentation is isometric. The camera looks down at the true isometric pitch
 * (atan(1/√2) ≈ 35.26°) from yaw 45°, i.e. it sits on the +X / +Z side of what it frames, so map
 * row 0 is at the back and tile (0, 0) is the top corner of the diamond.
 *
 * Framing (chapter 16 leaves "show whole level vs follow" open): record mode shows the whole level
 * when it fits at a readable tile size and otherwise follows the active self inside soft bounds.
 * Review frames the action, cinematic drifts and pushes in on focus requests (CINE-03), idle orbits
 * a few degrees behind menus.
 *
 * Nothing here touches WebGL, so the maths is unit-tested in node.
 */
import * as THREE from 'three';
import type { ViewMode } from '../contracts';
import type { LevelBounds } from './env/layout';

export const ISO_YAW = Math.PI / 4;
export const ISO_PITCH = Math.atan(1 / Math.SQRT2);
/** Distance from the look-at point; any value works for an orthographic camera as long as near/far bracket the level. */
export const CAMERA_DISTANCE = 120;
/** Smallest on-screen size of one world unit (CSS px) in record mode before we switch to following. */
export const MIN_PX_PER_UNIT = 42;
/** Never zoom closer than this many world units of vertical view. */
export const MIN_VIEW_SIZE = 5.5;

export interface FramingInput {
  mode: ViewMode;
  /** Wall-clock seconds since last update. */
  dt: number;
  /** Accumulated wall-clock seconds (drives drift / orbit). */
  time: number;
  /** Master beat (cinematic wide-shot rhythm). */
  beat: number;
  /** Position of the self under live control, sim axes. */
  follow: { x: number; y: number } | null;
  /** Centre of the selves that matter right now (alive ones), sim axes. */
  crowd: { x: number; y: number } | null;
}

const damp = (from: number, to: number, rate: number, dt: number): number => to + (from - to) * Math.exp(-rate * dt);

/** Wrap an angle difference into (-π, π]. */
function angleDelta(a: number, b: number): number {
  let d = (b - a) % (Math.PI * 2);
  if (d > Math.PI) d -= Math.PI * 2;
  if (d <= -Math.PI) d += Math.PI * 2;
  return d;
}

export class IsoCamera {
  readonly camera: THREE.OrthographicCamera;

  yaw = ISO_YAW;
  pitch = ISO_PITCH;
  /** Visible world units from the bottom to the top of the viewport. */
  viewSize = 16;
  /** Look-at point on the floor plane (scene X, Z). */
  targetX = 0;
  targetZ = 0;

  private vpW = 1;
  private vpH = 1;
  private bounds: LevelBounds = { minX: 0, minZ: 0, maxX: 1, maxZ: 1, maxY: 0, minY: 0 };

  private trauma = 0;
  private shakeX = 0;
  private shakeY = 0;

  private focusSumX = 0;
  private focusSumY = 0;
  private focusSumW = 0;
  private focusX = 0;
  private focusY = 0;
  private focusW = 0;
  private pushIn = 0;

  // Scratch objects: update()/screenToWorld() must not allocate per frame.
  private readonly v0 = new THREE.Vector3();
  private readonly v1 = new THREE.Vector3();
  private readonly right = new THREE.Vector3();
  private readonly up = new THREE.Vector3();
  private readonly fwd = new THREE.Vector3();

  constructor() {
    this.camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 1, CAMERA_DISTANCE * 2.5);
    this.apply();
  }

  // ───────────── configuration ─────────────

  /** Viewport size in CSS pixels. */
  setViewport(width: number, height: number): void {
    this.vpW = Math.max(1, width);
    this.vpH = Math.max(1, height);
    this.apply();
  }

  get viewportWidth(): number {
    return this.vpW;
  }

  get viewportHeight(): number {
    return this.vpH;
  }

  get aspect(): number {
    return this.vpW / this.vpH;
  }

  setBounds(bounds: LevelBounds): void {
    this.bounds = { ...bounds };
  }

  /**
   * Called on level load: centre on the level and start zoomed out so the first frames ease in to
   * the fitted framing ("smooth zoom to fit").
   */
  introduce(): void {
    this.yaw = ISO_YAW;
    this.pitch = ISO_PITCH;
    const fit = this.fitSize();
    const c = this.levelCentre();
    this.targetX = c.x;
    this.targetZ = c.z;
    this.viewSize = fit * 1.55;
    this.trauma = 0;
    this.focusW = 0;
    this.pushIn = 0;
    this.focusSumW = 0;
    this.apply();
  }

  /** Camera shake request, magnitude 0..1 (trauma model: shake grows with trauma squared). */
  addTrauma(magnitude: number): void {
    if (!(magnitude > 0)) return;
    this.trauma = Math.min(1, this.trauma + magnitude);
  }

  /** Weighted focus request for this frame (sim axes). Consumed by the next update(). */
  requestFocus(x: number, y: number, weight: number): void {
    if (!(weight > 0) || !Number.isFinite(x) || !Number.isFinite(y)) return;
    this.focusSumX += x * weight;
    this.focusSumY += y * weight;
    this.focusSumW += weight;
  }

  // ───────────── basis helpers ─────────────

  /** Unit camera basis for a yaw/pitch, independent of position. */
  private basis(yaw: number, pitch: number): void {
    const cp = Math.cos(pitch);
    const sp = Math.sin(pitch);
    // Direction from target to camera.
    this.fwd.set(-Math.sin(yaw) * cp, -sp, -Math.cos(yaw) * cp); // camera looks along fwd
    this.right.set(Math.cos(yaw), 0, -Math.sin(yaw));
    // up = right × fwd
    this.up.crossVectors(this.right, this.fwd).normalize();
  }

  // Screen-basis extents of the level box, refreshed by extents().
  private eMinR = 0;
  private eMaxR = 0;
  private eMinU = 0;
  private eMaxU = 0;
  /** Scratch output of floorPointFor / levelCentre / clampTarget. */
  private readonly pt = { x: 0, z: 0 };

  /** Screen-basis extents of the level's bounding box at the current yaw (stored in eMin/eMax). */
  private extents(): void {
    this.basis(this.yaw, this.pitch);
    const b = this.bounds;
    let minR = Infinity;
    let maxR = -Infinity;
    let minU = Infinity;
    let maxU = -Infinity;
    for (let i = 0; i < 8; i++) {
      const x = i & 1 ? b.maxX : b.minX;
      const y = i & 2 ? b.maxY : b.minY * 0.55; // the deep cliff fades into the background; frame its upper half
      const z = i & 4 ? b.maxZ : b.minZ;
      const rr = x * this.right.x + y * this.right.y + z * this.right.z;
      const uu = x * this.up.x + y * this.up.y + z * this.up.z;
      if (rr < minR) minR = rr;
      if (rr > maxR) maxR = rr;
      if (uu < minU) minU = uu;
      if (uu > maxU) maxU = uu;
    }
    this.eMinR = minR;
    this.eMaxR = maxR;
    this.eMinU = minU;
    this.eMaxU = maxU;
  }

  /** Vertical view size that fits the whole level with a margin. */
  fitSize(margin = 1.1): number {
    this.extents();
    const w = this.eMaxR - this.eMinR;
    const h = this.eMaxU - this.eMinU;
    return Math.max(MIN_VIEW_SIZE, Math.max(h, w / this.aspect) * margin);
  }

  /** View size at which one world unit is MIN_PX_PER_UNIT CSS pixels tall. */
  readableSize(): number {
    return Math.max(MIN_VIEW_SIZE, this.vpH / MIN_PX_PER_UNIT);
  }

  /** Floor point whose projection is at screen-basis coordinates (r, u); written to this.pt. */
  private floorPointFor(r: number, u: number): { x: number; z: number } {
    // Solve x*right.x + z*right.z = r ; x*up.x + z*up.z = u  (point on Y = 0).
    const a = this.right.x;
    const b = this.right.z;
    const c = this.up.x;
    const d = this.up.z;
    const det = a * d - b * c;
    if (Math.abs(det) < 1e-9) {
      this.pt.x = this.targetX;
      this.pt.z = this.targetZ;
    } else {
      this.pt.x = (r * d - b * u) / det;
      this.pt.z = (a * u - c * r) / det;
    }
    return this.pt;
  }

  /** Floor point that centres the level's projected bounding box on screen (scratch object; copy it). */
  levelCentre(): { x: number; z: number } {
    this.extents();
    return this.floorPointFor((this.eMinR + this.eMaxR) / 2, (this.eMinU + this.eMaxU) / 2);
  }

  /**
   * Clamp a desired look-at point so the view stays inside the level's projected extents plus a
   * soft margin; on an axis where the view is wider than the level, centre that axis.
   */
  private clampTarget(x: number, z: number, size: number, margin: number): { x: number; z: number } {
    this.extents();
    const halfH = size / 2;
    const halfW = (size * this.aspect) / 2;
    let r = x * this.right.x + z * this.right.z;
    let u = x * this.up.x + z * this.up.z;
    const loR = this.eMinR + halfW - margin;
    const hiR = this.eMaxR - halfW + margin;
    const loU = this.eMinU + halfH - margin;
    const hiU = this.eMaxU - halfH + margin;
    r = loR > hiR ? (this.eMinR + this.eMaxR) / 2 : Math.min(hiR, Math.max(loR, r));
    u = loU > hiU ? (this.eMinU + this.eMaxU) / 2 : Math.min(hiU, Math.max(loU, u));
    return this.floorPointFor(r, u);
  }

  // ───────────── per-frame framing ─────────────

  update(input: FramingInput): void {
    const dt = Math.min(0.1, Math.max(0, input.dt));
    const t = input.time;

    // Focus requests from layers this frame.
    if (this.focusSumW > 0) {
      const fx = this.focusSumX / this.focusSumW;
      const fy = this.focusSumY / this.focusSumW;
      if (this.focusW < 0.02) {
        this.focusX = fx;
        this.focusY = fy;
      } else {
        this.focusX = damp(this.focusX, fx, 4, dt);
        this.focusY = damp(this.focusY, fy, 4, dt);
      }
    }
    this.focusW = damp(this.focusW, Math.min(1, this.focusSumW), this.focusSumW > this.focusW ? 6 : 0.9, dt);
    this.focusSumX = 0;
    this.focusSumY = 0;
    this.focusSumW = 0;

    let targetYaw = ISO_YAW;
    if (input.mode === 'idle') targetYaw = ISO_YAW + THREE.MathUtils.degToRad(5) * Math.sin(t * 0.12);
    if (input.mode === 'cinematic') targetYaw = ISO_YAW + THREE.MathUtils.degToRad(3.5) * Math.sin(t * 0.09);
    this.yaw += angleDelta(this.yaw, targetYaw) * (1 - Math.exp(-2.2 * dt));

    const fit = this.fitSize();
    const readable = this.readableSize();
    const centre = this.levelCentre();
    const cx = centre.x;
    const cz = centre.z;
    let size: number;
    let tx = cx;
    let tz = cz;
    let sizeRate = 2.4;
    let moveRate = 3.2;

    switch (input.mode) {
      case 'record':
      case 'review': {
        const subj = input.follow ?? input.crowd;
        let hasSubject = subj !== null;
        let sx = subj ? subj.x : cx;
        let sy = subj ? subj.y : cz;
        if (input.mode === 'review' && this.focusW > 0.05) {
          // Review frames the action, so layers' focus requests pull the view a little.
          const k = Math.min(0.6, this.focusW * 0.6);
          sx += (this.focusX - sx) * k;
          sy += (this.focusY - sy) * k;
          hasSubject = true;
        }
        if (fit <= readable) {
          // Whole level fits at a readable size: hold it still and centred (readability first).
          size = fit;
        } else {
          size = readable;
          if (hasSubject) {
            const p = this.clampTarget(sx, sy, size, 1);
            tx = p.x;
            tz = p.z;
          }
          moveRate = 2.6;
        }
        break;
      }
      case 'cinematic': {
        const base = Math.min(fit, readable * 1.35);
        // Every 16 beats, widen for the whole-room picture for three beats so the causal chain
        // stays legible (CINE-03 spectacle must not hide how the solution works).
        const cycle = ((input.beat % 16) + 16) % 16;
        const wide = cycle >= 13;
        const wantPush = wide ? 0 : Math.min(1, this.focusW) * 0.85;
        this.pushIn = damp(this.pushIn, wantPush, wantPush > this.pushIn ? 1.6 : 0.8, dt);
        size = Math.max(MIN_VIEW_SIZE, base * (1 - 0.4 * this.pushIn));
        let sx = cx;
        let sy = cz;
        if (this.focusW > 0.02) {
          sx = this.focusX;
          sy = this.focusY;
        } else if (input.crowd) {
          sx = input.crowd.x;
          sy = input.crowd.y;
        }
        const k = base >= fit * 0.999 ? 0.25 + 0.65 * this.pushIn : 0.85;
        const driftR = Math.sin(t * 0.13) * 0.06 * size;
        const driftU = Math.cos(t * 0.11) * 0.035 * size;
        const px = cx + (sx - cx) * k + this.right.x * driftR + this.up.x * driftU;
        const pz = cz + (sy - cz) * k + this.right.z * driftR + this.up.z * driftU;
        const p = this.clampTarget(px, pz, size, 1.5);
        tx = p.x;
        tz = p.z;
        sizeRate = 1.4;
        moveRate = 1.6;
        break;
      }
      case 'idle':
      default: {
        size = fit * 1.08;
        sizeRate = 1.2;
        moveRate = 1.2;
        break;
      }
    }

    this.viewSize = damp(this.viewSize, size, sizeRate, dt);
    this.targetX = damp(this.targetX, tx, moveRate, dt);
    this.targetZ = damp(this.targetZ, tz, moveRate, dt);

    // Shake: trauma² keeps small hits subtle and big hits punchy; smooth pseudo-noise, no allocation.
    this.trauma = Math.max(0, this.trauma - dt * 1.7);
    const amp = this.trauma * this.trauma * 0.045 * this.viewSize;
    this.shakeX = amp * (Math.sin(t * 47.3) * 0.6 + Math.sin(t * 89.1 + 1.7) * 0.4);
    this.shakeY = amp * (Math.sin(t * 53.9 + 0.6) * 0.6 + Math.sin(t * 77.7 + 2.9) * 0.4);

    this.apply();
  }

  /** Recompute the camera transform and projection from the current state. */
  apply(): void {
    this.basis(this.yaw, this.pitch);
    const cam = this.camera;
    const tx = this.targetX + this.right.x * this.shakeX + this.up.x * this.shakeY;
    const ty = this.up.y * this.shakeY;
    const tz = this.targetZ + this.right.z * this.shakeX + this.up.z * this.shakeY;
    cam.position.set(tx - this.fwd.x * CAMERA_DISTANCE, ty - this.fwd.y * CAMERA_DISTANCE, tz - this.fwd.z * CAMERA_DISTANCE);
    cam.up.set(0, 1, 0);
    cam.lookAt(tx, ty, tz);
    const halfH = this.viewSize / 2;
    const halfW = halfH * this.aspect;
    cam.left = -halfW;
    cam.right = halfW;
    cam.top = halfH;
    cam.bottom = -halfH;
    cam.near = 1;
    cam.far = CAMERA_DISTANCE * 2.5;
    cam.updateProjectionMatrix();
    cam.updateMatrixWorld(true);
  }

  // ───────────── projections ─────────────

  /**
   * Sim-axes unit direction that "up on screen" maps to on the floor: the camera's up vector
   * projected onto the floor plane.
   */
  screenUpInWorld(out: { x: number; y: number } = { x: 0, y: 0 }): { x: number; y: number } {
    const e = this.camera.matrixWorld.elements;
    // Column 1 of the world matrix is the camera's up axis in world space.
    const ux = e[4];
    const uz = e[6];
    const len = Math.hypot(ux, uz);
    if (len < 1e-9) {
      out.x = 0;
      out.y = -1;
    } else {
      out.x = ux / len;
      out.y = uz / len;
    }
    return out;
  }

  /** CSS-pixel position (relative to the canvas) → point on the floor plane (Y = 0), sim axes. */
  screenToWorld(px: number, py: number, out: { x: number; y: number } = { x: 0, y: 0 }): { x: number; y: number } {
    const ndcX = (px / this.vpW) * 2 - 1;
    const ndcY = 1 - (py / this.vpH) * 2;
    const origin = this.v0.set(ndcX, ndcY, -1).unproject(this.camera);
    const far = this.v1.set(ndcX, ndcY, 1).unproject(this.camera);
    const dx = far.x - origin.x;
    const dy = far.y - origin.y;
    const dz = far.z - origin.z;
    if (Math.abs(dy) < 1e-9) {
      out.x = origin.x;
      out.y = origin.z;
      return out;
    }
    const k = -origin.y / dy;
    out.x = origin.x + dx * k;
    out.y = origin.z + dz * k;
    return out;
  }

  /** Sim point (x, y) at height h → CSS-pixel position relative to the canvas. */
  worldToScreen(x: number, y: number, h = 0, out: { x: number; y: number } = { x: 0, y: 0 }): { x: number; y: number } {
    const p = this.v0.set(x, h, y).project(this.camera);
    out.x = ((p.x + 1) / 2) * this.vpW;
    out.y = ((1 - p.y) / 2) * this.vpH;
    return out;
  }

  /** World units per CSS pixel at the current zoom (used for pixel-consistent outlines). */
  worldPerPixel(): number {
    return this.viewSize / this.vpH;
  }
}
