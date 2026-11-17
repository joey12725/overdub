import { describe, expect, it } from 'vitest';
import * as THREE from 'three';
import { IsoCamera, ISO_PITCH, ISO_YAW, MIN_PX_PER_UNIT } from '../../src/render/camera';
import type { LevelBounds } from '../../src/render/env/layout';

const BOUNDS: LevelBounds = { minX: 0, minZ: 0, maxX: 12, maxZ: 9, maxY: 2, minY: -2 };

function makeCamera(w = 1280, h = 720): IsoCamera {
  const cam = new IsoCamera();
  cam.setViewport(w, h);
  cam.setBounds(BOUNDS);
  cam.introduce();
  cam.viewSize = 14;
  cam.targetX = 6;
  cam.targetZ = 4.5;
  cam.apply();
  return cam;
}

describe('IsoCamera orientation (ART-01 isometric)', () => {
  it('looks down at the true isometric pitch from yaw 45°', () => {
    const cam = makeCamera();
    const dir = new THREE.Vector3();
    cam.camera.getWorldDirection(dir);
    expect(Math.asin(-dir.y)).toBeCloseTo(ISO_PITCH, 6);
    expect(Math.atan2(-dir.x, -dir.z)).toBeCloseTo(ISO_YAW, 6);
    expect(THREE.MathUtils.radToDeg(ISO_PITCH)).toBeCloseTo(35.264, 2);
  });

  it('screenUpInWorld matches the camera up axis projected onto the floor', () => {
    const cam = makeCamera();
    const up = cam.screenUpInWorld();
    expect(up.x).toBeCloseTo(-Math.SQRT1_2, 6);
    expect(up.y).toBeCloseTo(-Math.SQRT1_2, 6);
    expect(Math.hypot(up.x, up.y)).toBeCloseTo(1, 9);

    // Independent derivation from the camera matrices: transform the view-space up axis.
    const viewUp = new THREE.Vector3(0, 1, 0).transformDirection(cam.camera.matrixWorld);
    const len = Math.hypot(viewUp.x, viewUp.z);
    expect(up.x).toBeCloseTo(viewUp.x / len, 9);
    expect(up.y).toBeCloseTo(viewUp.z / len, 9);
  });

  it('walking along screenUpInWorld moves a point straight up the screen', () => {
    const cam = makeCamera();
    const up = cam.screenUpInWorld();
    const a = cam.worldToScreen(6, 4.5);
    const b = cam.worldToScreen(6 + up.x, 4.5 + up.y);
    expect(b.x).toBeCloseTo(a.x, 6);
    expect(b.y).toBeLessThan(a.y);
  });

  it('screenUpInWorld follows the yaw when the camera orbits', () => {
    const cam = makeCamera();
    cam.yaw = ISO_YAW + 0.2;
    cam.apply();
    const up = cam.screenUpInWorld();
    expect(up.x).toBeCloseTo(-Math.sin(ISO_YAW + 0.2), 6);
    expect(up.y).toBeCloseTo(-Math.cos(ISO_YAW + 0.2), 6);
  });
});

describe('IsoCamera projections', () => {
  it('round-trips world → screen → world on the floor plane', () => {
    const cam = makeCamera(1600, 900);
    const pts = [
      [0, 0],
      [6, 4.5],
      [11.5, 8.25],
      [3.3, 7.1],
      [9.9, 0.4],
    ];
    for (const [x, y] of pts) {
      const s = cam.worldToScreen(x, y);
      const w = cam.screenToWorld(s.x, s.y);
      expect(w.x).toBeCloseTo(x, 6);
      expect(w.y).toBeCloseTo(y, 6);
    }
  });

  it('round-trips screen → world → screen', () => {
    const cam = makeCamera(800, 600);
    for (const [px, py] of [
      [0, 0],
      [400, 300],
      [799, 599],
      [123, 456],
    ]) {
      const w = cam.screenToWorld(px, py);
      const s = cam.worldToScreen(w.x, w.y);
      expect(s.x).toBeCloseTo(px, 4);
      expect(s.y).toBeCloseTo(py, 4);
    }
  });

  it('maps the viewport centre to the look-at point', () => {
    const cam = makeCamera(1024, 768);
    const w = cam.screenToWorld(512, 384);
    expect(w.x).toBeCloseTo(6, 6);
    expect(w.y).toBeCloseTo(4.5, 6);
  });

  it('agrees with a Raycaster against the floor plane', () => {
    const cam = makeCamera(1280, 720);
    const rc = new THREE.Raycaster();
    const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
    const hit = new THREE.Vector3();
    for (const [px, py] of [
      [100, 650],
      [640, 360],
      [1200, 40],
    ]) {
      rc.setFromCamera(new THREE.Vector2((px / 1280) * 2 - 1, 1 - (py / 720) * 2), cam.camera);
      rc.ray.intersectPlane(plane, hit);
      const w = cam.screenToWorld(px, py);
      expect(w.x).toBeCloseTo(hit.x, 5);
      expect(w.y).toBeCloseTo(hit.z, 5);
    }
  });

  it('accounts for height in worldToScreen (taller points are higher on screen)', () => {
    const cam = makeCamera();
    const a = cam.worldToScreen(5, 5, 0);
    const b = cam.worldToScreen(5, 5, 2);
    expect(b.x).toBeCloseTo(a.x, 6);
    expect(b.y).toBeLessThan(a.y);
  });
});

describe('IsoCamera framing', () => {
  it('fits a small level whole and centres it in record mode', () => {
    const cam = new IsoCamera();
    cam.setViewport(1600, 900);
    cam.setBounds(BOUNDS);
    cam.introduce();
    for (let i = 0; i < 400; i++) cam.update({ mode: 'record', dt: 1 / 60, time: i / 60, beat: 0, follow: { x: 1, y: 1 }, crowd: null });
    expect(cam.viewSize).toBeCloseTo(cam.fitSize(), 2);
    // every corner of the floor is on screen
    for (const [x, y] of [
      [0, 0],
      [12, 0],
      [0, 9],
      [12, 9],
    ]) {
      const s = cam.worldToScreen(x, y);
      expect(s.x).toBeGreaterThanOrEqual(0);
      expect(s.x).toBeLessThanOrEqual(1600);
      expect(s.y).toBeGreaterThanOrEqual(0);
      expect(s.y).toBeLessThanOrEqual(900);
    }
  });

  it('follows the active self inside soft bounds when the level is too big to read', () => {
    const cam = new IsoCamera();
    cam.setViewport(800, 450);
    const big: LevelBounds = { minX: 0, minZ: 0, maxX: 60, maxZ: 50, maxY: 2, minY: -2 };
    cam.setBounds(big);
    cam.introduce();
    const follow = { x: 30, y: 25 };
    for (let i = 0; i < 600; i++) cam.update({ mode: 'record', dt: 1 / 60, time: i / 60, beat: 0, follow, crowd: null });
    expect(cam.viewSize).toBeCloseTo(450 / MIN_PX_PER_UNIT, 2);
    const s = cam.worldToScreen(follow.x, follow.y);
    expect(s.x).toBeCloseTo(400, 0);
    expect(s.y).toBeCloseTo(225, 0);
  });

  it('decays shake back to rest', () => {
    const cam = makeCamera();
    cam.addTrauma(1);
    for (let i = 0; i < 120; i++) cam.update({ mode: 'record', dt: 1 / 60, time: i / 60, beat: 0, follow: null, crowd: null });
    const before = cam.camera.position.clone();
    cam.update({ mode: 'record', dt: 1 / 60, time: 3, beat: 0, follow: null, crowd: null });
    expect(cam.camera.position.distanceTo(before)).toBeLessThan(1e-3);
  });

  it('pushes in on focus requests in cinematic mode and widens on the wide-shot beats', () => {
    const cam = new IsoCamera();
    cam.setViewport(1600, 900);
    cam.setBounds(BOUNDS);
    cam.introduce();
    for (let i = 0; i < 300; i++) {
      cam.requestFocus(2, 2, 1);
      cam.update({ mode: 'cinematic', dt: 1 / 60, time: i / 60, beat: 4, follow: null, crowd: null });
    }
    const pushed = cam.viewSize;
    expect(pushed).toBeLessThan(cam.fitSize() * 0.8);
    for (let i = 0; i < 400; i++) {
      cam.requestFocus(2, 2, 1);
      cam.update({ mode: 'cinematic', dt: 1 / 60, time: 5 + i / 60, beat: 14, follow: null, crowd: null });
    }
    expect(cam.viewSize).toBeGreaterThan(pushed);
  });
});
