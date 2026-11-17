/**
 * World-space combat readouts drawn as instanced billboards from a canvas word atlas.
 *
 * The atlas is painted once with local system fonts only (no remote fonts). Each word is inked in
 * three channels so the shader can colour it per readout: red = fill (tinted by tape / tier),
 * green = heavy ink outline, blue = an offset drop shadow — the bold, hand-inked anime-graphic
 * lettering of the references (Mob Psycho 100 / Idaten, chapter 17 "Art style").
 */
import * as THREE from 'three';
import { Rng } from '../curves';
import type { TextPool } from '../pool';
import { WORDS, W_BREAK, W_CLEAR, W_CRUSH, W_KO, W_OVERDUB, W_SMASH } from '../words';

const ATLAS = 1024;
const CELL_W = 512;
const CELL_H = 112;
const COLS = 2;
const FONT_STACK = '"Impact", "Haettenschweiler", "Arial Black", "Franklin Gothic Heavy", "Segoe UI Black", sans-serif';

export interface WordAtlas {
  texture: THREE.Texture;
  /** Per word: u0, v0, u1, v1. */
  rects: THREE.Vector4[];
  /** Per word: width / height of its quad. */
  aspects: number[];
}

/** Paint the readout atlas. Requires a DOM (or OffscreenCanvas); called once on first use. */
export function createWordAtlas(): WordAtlas {
  let canvas: HTMLCanvasElement | OffscreenCanvas;
  if (typeof document !== 'undefined') {
    const c = document.createElement('canvas');
    c.width = ATLAS;
    c.height = ATLAS;
    canvas = c;
  } else if (typeof OffscreenCanvas !== 'undefined') {
    canvas = new OffscreenCanvas(ATLAS, ATLAS);
  } else {
    throw new Error('fx: no canvas available to paint the readout atlas');
  }
  const g = canvas.getContext('2d') as CanvasRenderingContext2D | null;
  if (!g) throw new Error('fx: 2D canvas context unavailable');
  g.clearRect(0, 0, ATLAS, ATLAS);
  const rects: THREE.Vector4[] = [];
  const aspects: number[] = [];
  const rng = new Rng(0x0dd5);

  for (let w = 0; w < WORDS.length; w++) {
    const word = WORDS[w];
    const col = w % COLS;
    const row = Math.floor(w / COLS);
    const cx = col * CELL_W;
    const cy = row * CELL_H;
    g.save();
    g.beginPath();
    g.rect(cx, cy, CELL_W, CELL_H);
    g.clip();

    let px = 84;
    g.font = `italic 900 ${px}px ${FONT_STACK}`;
    const spacing = 2;
    let total = 0;
    for (const ch of word) total += g.measureText(ch).width + spacing;
    const maxW = CELL_W - 70;
    if (total > maxW) {
      px = Math.floor((px * maxW) / total);
      g.font = `italic 900 ${px}px ${FONT_STACK}`;
      total = 0;
      for (const ch of word) total += g.measureText(ch).width + spacing;
    }
    const baseY = cy + CELL_H / 2 + px * 0.36;
    const startX = cx + (CELL_W - total) / 2;
    const loud = w === W_SMASH || w === W_CRUSH || w === W_OVERDUB || w === W_KO || w === W_BREAK || w === W_CLEAR;

    // Per-glyph jitter (rotation, baseline, size) so words look brushed, not typeset.
    const jr: number[] = [];
    const jy: number[] = [];
    const js: number[] = [];
    for (let i = 0; i < word.length; i++) {
      jr.push(rng.sym(0.09));
      jy.push(rng.sym(3.5));
      js.push(1 + rng.sym(0.07));
    }

    const drawGlyphs = (pass: 'shadow' | 'ink' | 'fill') => {
      let x = startX;
      for (let i = 0; i < word.length; i++) {
        const ch = word[i];
        const cw = g.measureText(ch).width;
        g.save();
        const ox = pass === 'shadow' ? 7 : 0;
        const oy = pass === 'shadow' ? 6 : 0;
        g.translate(x + cw / 2 + ox, baseY + jy[i] + oy);
        // Forward lean (italic shear) plus a per-letter wobble.
        g.transform(1, 0, -0.18, 1, 0, 0);
        g.rotate(jr[i]);
        g.scale(js[i], js[i]);
        g.textAlign = 'center';
        g.textBaseline = 'alphabetic';
        if (pass === 'shadow') {
          g.lineWidth = 15;
          g.strokeStyle = '#0000ff';
          g.fillStyle = '#0000ff';
          g.strokeText(ch, 0, 0);
          g.fillText(ch, 0, 0);
        } else if (pass === 'ink') {
          g.lineWidth = 13;
          g.lineJoin = 'miter';
          g.miterLimit = 2.5;
          g.strokeStyle = '#00ff00';
          g.strokeText(ch, 0, 0);
        } else {
          g.fillStyle = '#ff0000';
          g.fillText(ch, 0, 0);
        }
        g.restore();
        x += cw + spacing;
      }
    };

    if (loud) {
      // Speed slashes trailing the word: tapered ink strokes, drawn first so letters sit on top.
      g.fillStyle = '#00ff00';
      for (let k = 0; k < 3; k++) {
        const y = cy + 30 + k * 24 + rng.sym(4);
        const x1 = startX - 8 - k * 10;
        const len = 46 + rng.next() * 30;
        g.beginPath();
        g.moveTo(x1, y - 4);
        g.lineTo(x1 - len, y + 1);
        g.lineTo(x1, y + 5);
        g.closePath();
        g.fill();
      }
    }
    drawGlyphs('shadow');
    drawGlyphs('ink');
    drawGlyphs('fill');
    g.restore();

    const pad = 34;
    const usedW = Math.min(CELL_W, total + pad * 2 + (loud ? 80 : 0));
    const x0 = cx + (CELL_W - usedW) / 2 - (loud ? 40 : 0);
    const x1 = x0 + usedW;
    rects.push(new THREE.Vector4(Math.max(cx, x0) / ATLAS, 1 - (cy + CELL_H) / ATLAS, Math.min(cx + CELL_W, x1) / ATLAS, 1 - cy / ATLAS));
    aspects.push((Math.min(cx + CELL_W, x1) - Math.max(cx, x0)) / CELL_H);
  }

  const texture = new THREE.CanvasTexture(canvas as HTMLCanvasElement);
  // Channels are masks, not colours: keep them out of colour management.
  texture.colorSpace = THREE.NoColorSpace;
  texture.generateMipmaps = true;
  texture.minFilter = THREE.LinearMipmapLinearFilter;
  texture.magFilter = THREE.LinearFilter;
  texture.anisotropy = 4;
  texture.needsUpdate = true;
  return { texture, rects, aspects };
}

const VERT = /* glsl */ `
#define WORD_COUNT ${WORDS.length}
attribute vec4 iPosSize;
attribute vec4 iColor;
attribute vec4 iParams;
uniform vec4 uRects[WORD_COUNT];
uniform float uAspects[WORD_COUNT];
varying vec2 vUv;
varying vec2 vLocal;
varying vec4 vColor;
void main() {
  int w = int(iParams.x + 0.5);
  vec4 rect = uRects[w];
  float aspect = uAspects[w];
  vec2 c = position.xy; // -0.5..0.5
  vUv = vec2(mix(rect.x, rect.z, c.x + 0.5), mix(rect.y, rect.w, c.y + 0.5));
  vLocal = c * 2.0;
  vColor = iColor;
  float h = iPosSize.w;
  vec2 q = vec2(c.x * h * aspect, c.y * h);
  float r = iParams.y;
  q = vec2(q.x * cos(r) - q.y * sin(r), q.x * sin(r) + q.y * cos(r));
  vec4 mv = modelViewMatrix * vec4(iPosSize.xyz, 1.0);
  mv.xy += q;
  gl_Position = projectionMatrix * mv;
}
`;

const FRAG = /* glsl */ `
uniform sampler2D uAtlas;
uniform vec3 uInk;
varying vec2 vUv;
varying vec2 vLocal;
varying vec4 vColor;
void main() {
  vec4 t = texture2D(uAtlas, vUv);
  float cov = t.a;
  if (cov * vColor.a < 0.01) discard;
  float sum = max(t.r + t.g + t.b, 1e-3);
  // Fill gets a light top-to-bottom ramp for a printed, graphic feel.
  vec3 fill = vColor.rgb * (0.9 + 0.22 * vLocal.y) + 0.08;
  vec3 shadow = vColor.rgb * 0.38;
  vec3 col = (fill * t.r + uInk * t.g + shadow * t.b) / sum;
  gl_FragColor = vec4(col, cov * vColor.a);
}
`;

function markRange(attr: THREE.InstancedBufferAttribute, n: number): void {
  attr.clearUpdateRanges();
  attr.addUpdateRange(0, n * 4);
  attr.needsUpdate = true;
}

export class TextMesh {
  readonly mesh: THREE.Mesh;
  private readonly geo: THREE.InstancedBufferGeometry;
  private readonly mat: THREE.ShaderMaterial;
  private readonly posSize: THREE.InstancedBufferAttribute;
  private readonly color: THREE.InstancedBufferAttribute;
  private readonly params: THREE.InstancedBufferAttribute;

  constructor(capacity: number, atlas: WordAtlas, ink: number) {
    const base = new THREE.PlaneGeometry(1, 1);
    const geo = new THREE.InstancedBufferGeometry();
    geo.index = base.index;
    geo.setAttribute('position', base.getAttribute('position'));
    const mk = () => {
      const a = new THREE.InstancedBufferAttribute(new Float32Array(capacity * 4), 4);
      a.setUsage(THREE.DynamicDrawUsage);
      return a;
    };
    this.posSize = mk();
    this.color = mk();
    this.params = mk();
    geo.setAttribute('iPosSize', this.posSize);
    geo.setAttribute('iColor', this.color);
    geo.setAttribute('iParams', this.params);
    geo.instanceCount = 0;
    this.geo = geo;
    this.mat = new THREE.ShaderMaterial({
      vertexShader: VERT,
      fragmentShader: FRAG,
      uniforms: {
        uAtlas: { value: atlas.texture },
        uRects: { value: atlas.rects },
        uAspects: { value: atlas.aspects },
        uInk: { value: new THREE.Color(ink) },
      },
      transparent: true,
      depthWrite: false,
      // Readouts must stay legible over walls and props.
      depthTest: false,
    });
    this.mesh = new THREE.Mesh(geo, this.mat);
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = 9000;
    this.mesh.name = 'fx-text';
    this.mesh.userData.fx = true;
    this.mesh.userData.noOutline = true;
  }

  setInk(ink: number): void {
    (this.mat.uniforms.uInk.value as THREE.Color).setHex(ink);
  }

  sync(pool: TextPool): void {
    const n = pool.writeInstances(this.posSize.array as Float32Array, this.color.array as Float32Array, this.params.array as Float32Array);
    this.geo.instanceCount = n;
    if (n > 0) {
      markRange(this.posSize, n);
      markRange(this.color, n);
      markRange(this.params, n);
    }
    this.mesh.visible = n > 0;
  }

  dispose(): void {
    this.geo.dispose();
    this.mat.dispose();
  }
}
