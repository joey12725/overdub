/**
 * Melee swing trail. The sector matches the equipped weapon's hit volume (reach and arcDeg, from
 * ctx.loadout.melee) so the trail doubles as an honest read of what the swing covers (WEAPON-04,
 * NEW-01), styled per weapon: blade crescent, blunt wedge, whip lash, gauntlet shock cone.
 */
import * as THREE from 'three';
import type { AnimState, MeleeWeaponDef } from '../../core/types';
import { flatRing, sectorGeometry } from './decals';
import { createFlatMaterial, type FlatMaterial } from './materials';
import { clamp01, easeOutCubic } from './math';

const STYLE_INDEX: Record<MeleeWeaponDef['style'], number> = { blade: 0, blunt: 1, whip: 2, gauntlet: 3 };

type TrailMaterial = THREE.ShaderMaterial & {
  uniforms: {
    uColor: { value: THREE.Color };
    uProgress: { value: number };
    uTail: { value: number };
    uOpacity: { value: number };
    uStyle: { value: number };
    uTime: { value: number };
    uPreview: { value: number };
  };
};

function createTrailMaterial(): TrailMaterial {
  return new THREE.ShaderMaterial({
    vertexShader: /* glsl */ `
      varying vec2 vUv;
      void main() {
        vUv = uv;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `,
    fragmentShader: /* glsl */ `
      uniform vec3 uColor;
      uniform float uProgress;
      uniform float uTail;
      uniform float uOpacity;
      uniform float uStyle;
      uniform float uTime;
      uniform float uPreview;
      varying vec2 vUv;
      void main() {
        float x = vUv.x;
        float r = vUv.y;
        if (uPreview > 0.5) {
          // Windup preview: just the outline of the hit volume, so a heavy is readable before it lands.
          float e = max(step(0.95, r), max(step(x, 0.015), step(0.985, x)));
          float dash = step(0.5, fract(x * 18.0 - uTime * 2.0));
          // Solid outer arc, dashed side edges.
          float a = e * uOpacity * mix(dash, 1.0, step(0.95, r));
          if (a <= 0.003) discard;
          gl_FragColor = vec4(uColor, a);
          #include <colorspace_fragment>
          return;
        }
        if (x > uProgress) discard;
        float tail = clamp(1.0 - (uProgress - x) / max(uTail, 0.001), 0.0, 1.0);
        float shape = 0.0;
        float hot = 0.0;
        if (uStyle < 0.5) {
          shape = smoothstep(0.45, 0.95, r) * (1.0 - smoothstep(0.975, 1.0, r));
          hot = smoothstep(0.86, 0.95, r) * (1.0 - smoothstep(0.95, 0.99, r));
        } else if (uStyle < 1.5) {
          shape = smoothstep(0.1, 0.35, r) * (1.0 - smoothstep(0.96, 1.0, r));
          shape *= 0.75 + 0.25 * step(0.5, fract(r * 6.0));
          hot = smoothstep(0.85, 0.97, r) * 0.6;
        } else if (uStyle < 2.5) {
          float w = 0.8 + 0.12 * sin(x * 26.0 - uTime * 18.0) * x;
          float d = abs(r - w);
          shape = 1.0 - smoothstep(0.015, 0.06, d);
          hot = 1.0 - smoothstep(0.0, 0.02, d);
        } else {
          float rings = 0.5 + 0.5 * sin(r * 28.0 - uTime * 26.0);
          shape = smoothstep(0.05, 0.3, r) * (1.0 - smoothstep(0.9, 1.0, r)) * (0.45 + 0.55 * rings);
          hot = (1.0 - smoothstep(0.0, 0.08, abs(x - uProgress))) * 0.8;
        }
        float a = shape * tail * uOpacity;
        if (a <= 0.003) discard;
        vec3 c = mix(uColor, vec3(1.0), clamp(hot * tail + (1.0 - smoothstep(0.0, 0.05, uProgress - x)) * 0.5, 0.0, 1.0));
        gl_FragColor = vec4(c, a);
        #include <colorspace_fragment>
      }
    `,
    transparent: true,
    depthWrite: false,
    side: THREE.DoubleSide,
    blending: THREE.AdditiveBlending,
    uniforms: {
      uColor: { value: new THREE.Color(1, 1, 1) },
      uProgress: { value: 0 },
      uTail: { value: 0.6 },
      uOpacity: { value: 0 },
      uStyle: { value: 0 },
      uTime: { value: 0 },
      uPreview: { value: 0 },
    },
  }) as TrailMaterial;
}

export class SwingTrail {
  readonly group = new THREE.Group();
  private readonly light: THREE.Mesh;
  private readonly heavy: THREE.Mesh;
  private readonly lightMat: TrailMaterial;
  private readonly heavyMat: TrailMaterial;
  private readonly impact: THREE.Mesh;
  private readonly impactMat: FlatMaterial;
  private readonly style: number;
  private readonly reach: number;
  private readonly styleName: MeleeWeaponDef['style'];
  private fade = 0;
  private fadeHeavy = 0;

  constructor(melee: MeleeWeaponDef, color: THREE.Color) {
    const arc = THREE.MathUtils.degToRad(Math.max(10, Math.min(360, melee.arcDeg)));
    const reach = Math.max(0.4, melee.reach);
    this.reach = reach;
    this.styleName = melee.style;
    this.style = STYLE_INDEX[melee.style];
    const segs = Math.max(8, Math.round(arc * 12));
    this.lightMat = createTrailMaterial();
    this.heavyMat = createTrailMaterial();
    for (const m of [this.lightMat, this.heavyMat]) {
      m.uniforms.uColor.value.copy(color);
      m.uniforms.uStyle.value = this.style;
    }
    this.light = new THREE.Mesh(sectorGeometry(reach * 0.3, reach, arc, segs, false), this.lightMat);
    this.light.position.y = 0.45;
    this.heavy = new THREE.Mesh(sectorGeometry(reach * 0.2, reach, arc, segs, false), this.heavyMat);
    this.heavy.position.y = 0.08;
    this.impactMat = createFlatMaterial(color.getHex(), { additive: true });
    this.impact = new THREE.Mesh(flatRing(0.8, 1.0, 32), this.impactMat);
    this.impact.position.set(0, 0.03, reach * 0.65);
    for (const m of [this.light, this.heavy, this.impact]) {
      m.visible = false;
      m.renderOrder = 6;
      m.frustumCulled = false;
      this.group.add(m);
    }
  }

  /** t = progress through `anim`; dt for fade-out; time for animated texture. */
  update(anim: AnimState, t: number, dt: number, time: number, intensity: number): void {
    const lm = this.lightMat.uniforms;
    const hm = this.heavyMat.uniforms;
    lm.uTime.value = time;
    hm.uTime.value = time;
    lm.uPreview.value = 0;
    hm.uPreview.value = 0;
    const style = this.styleName;
    // Light.
    if (anim === 'lightActive') {
      this.fade = 1;
      lm.uProgress.value = easeOutCubic(t) * 1.02;
      lm.uTail.value = style === 'whip' ? 1.2 : 0.55;
    } else if (anim === 'lightRecover') {
      lm.uProgress.value = 1.02;
      this.fade = Math.max(0, this.fade - dt * 7);
    } else {
      this.fade = Math.max(0, this.fade - dt * 10);
    }
    lm.uOpacity.value = this.fade * 0.9 * intensity;
    this.light.visible = lm.uOpacity.value > 0.01;

    // Heavy.
    let impact = 0;
    if (anim === 'heavyWindup') {
      // Preview the full hit volume while charging: readable commitment.
      hm.uPreview.value = 1;
      hm.uProgress.value = 1;
      hm.uOpacity.value = 0.12 + 0.35 * clamp01(t) * intensity;
      this.fadeHeavy = 0;
      this.heavy.visible = true;
    } else {
      if (anim === 'heavyActive') {
        this.fadeHeavy = 1;
        hm.uProgress.value = easeOutCubic(Math.min(1, t * 1.4)) * 1.02;
        hm.uTail.value = 0.9;
        impact = clamp01((t - 0.35) / 0.65);
      } else if (anim === 'heavyRecover') {
        hm.uProgress.value = 1.02;
        this.fadeHeavy = Math.max(0, this.fadeHeavy - dt * 4);
        impact = 1 + clamp01(t) * 0.5;
      } else {
        this.fadeHeavy = Math.max(0, this.fadeHeavy - dt * 8);
      }
      hm.uOpacity.value = this.fadeHeavy * intensity;
      this.heavy.visible = hm.uOpacity.value > 0.01;
    }

    // Ground shock ring for heavy impacts with blunt/gauntlet weapons.
    const showImpact = (style === 'blunt' || style === 'gauntlet' || style === 'blade') && impact > 0 && this.fadeHeavy > 0.02;
    this.impact.visible = showImpact;
    if (showImpact) {
      const s = this.reach * (0.25 + 0.45 * Math.min(1.5, impact));
      this.impact.scale.set(s, 1, s);
      this.impactMat.uniforms.uOpacity.value = Math.max(0, 1 - impact / 1.5) * this.fadeHeavy * intensity;
    }
  }

  setColor(c: THREE.Color): void {
    this.lightMat.uniforms.uColor.value.copy(c);
    this.heavyMat.uniforms.uColor.value.copy(c);
    this.impactMat.uniforms.uColor.value.copy(c);
  }

  dispose(): void {
    this.light.geometry.dispose();
    this.heavy.geometry.dispose();
    this.impact.geometry.dispose();
    this.lightMat.dispose();
    this.heavyMat.dispose();
    this.impactMat.dispose();
  }
}
