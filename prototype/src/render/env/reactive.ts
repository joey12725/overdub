/**
 * Builders for MusicReactive entries (layer.ts). Each captures the material's authored brightness
 * so the fx layer can scale relative to it without knowing which material type it is.
 */
import * as THREE from 'three';
import type { MusicReactive } from '../layer';

export function reactiveToon(kind: MusicReactive['kind'], material: THREE.MeshToonMaterial, at?: { x: number; y: number }): MusicReactive {
  const base = material.emissiveIntensity;
  return {
    kind,
    material,
    at,
    setLevel(level: number) {
      material.emissiveIntensity = base * Math.max(0, level);
    },
  };
}

export function reactiveGlow(kind: MusicReactive['kind'], material: THREE.MeshBasicMaterial, at?: { x: number; y: number }): MusicReactive {
  const base = material.color.clone();
  return {
    kind,
    material,
    at,
    setLevel(level: number) {
      material.color.copy(base).multiplyScalar(Math.max(0, level));
    },
  };
}

/** Add `entry` unless the same material is already registered (shared materials appear once). */
export function registerReactive(list: MusicReactive[], entry: MusicReactive): void {
  for (const e of list) if (e.material === entry.material) return;
  list.push(entry);
}
