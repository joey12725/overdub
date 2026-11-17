/**
 * Static vector art for the menus, all procedural (no remote or bitmap assets). Colours follow the
 * Moxie palette in tokens.css: yellow headphones and Walkman as the key colour, ink/charcoal,
 * olive cargo pants, pink graffiti accents (CHAR-05..09, R01).
 */

const REEL = (cx: number, cy: number, r: number, cls: string): string => `
  <g class="${cls}" style="transform-origin:${cx}px ${cy}px">
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="#f3ead8" stroke="#14110f" stroke-width="4"/>
    <circle cx="${cx}" cy="${cy}" r="${r * 0.42}" fill="#14110f"/>
    ${[0, 60, 120, 180, 240, 300]
      .map((a) => {
        const rad = (a * Math.PI) / 180;
        const x1 = cx + Math.cos(rad) * r * 0.42;
        const y1 = cy + Math.sin(rad) * r * 0.42;
        const x2 = cx + Math.cos(rad) * r * 0.86;
        const y2 = cy + Math.sin(rad) * r * 0.86;
        return `<line x1="${x1.toFixed(1)}" y1="${y1.toFixed(1)}" x2="${x2.toFixed(1)}" y2="${y2.toFixed(1)}" stroke="#14110f" stroke-width="4" stroke-linecap="round"/>`;
      })
      .join('')}
    <circle cx="${cx}" cy="${cy}" r="${r * 0.16}" fill="#ffd23f"/>
  </g>`;

/**
 * OVERDUB logotype: the word printed on a cassette label, the shell tilted like a sticker slapped
 * on a wall. The reels spin (CSS) so the title screen reads as "tape is running".
 */
export const LOGO_SVG = `
<svg class="od-logo-svg" viewBox="0 0 820 300" role="img" aria-label="OVERDUB">
  <defs>
    <pattern id="od-logo-hatch" width="10" height="10" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
      <rect width="10" height="10" fill="#ffd23f"/>
      <rect width="4" height="10" fill="#f0bf1f"/>
    </pattern>
    <clipPath id="od-logo-window"><rect x="265" y="196" width="290" height="60" rx="30"/></clipPath>
  </defs>
  <g transform="rotate(-3.5 410 150)">
    <!-- drop shadow, offset like a screen-printed sticker -->
    <rect x="52" y="34" width="730" height="246" rx="28" fill="#ff4fa3"/>
    <!-- shell -->
    <rect x="40" y="22" width="730" height="246" rx="28" fill="#14110f" stroke="#ffd23f" stroke-width="6"/>
    <circle cx="70" cy="50" r="7" fill="#2a2420" stroke="#c9bfa9" stroke-width="2"/>
    <circle cx="740" cy="50" r="7" fill="#2a2420" stroke="#c9bfa9" stroke-width="2"/>
    <circle cx="70" cy="240" r="7" fill="#2a2420" stroke="#c9bfa9" stroke-width="2"/>
    <circle cx="740" cy="240" r="7" fill="#2a2420" stroke="#c9bfa9" stroke-width="2"/>
    <!-- label -->
    <rect x="88" y="42" width="634" height="138" rx="12" fill="url(#od-logo-hatch)" stroke="#14110f" stroke-width="4"/>
    <rect x="88" y="42" width="634" height="26" rx="12" fill="#14110f"/>
    <rect x="88" y="56" width="634" height="12" fill="#14110f"/>
    <text x="106" y="61" font-family="Consolas, 'Cascadia Mono', monospace" font-size="15" font-weight="700" fill="#ffd23f" letter-spacing="3">SIDE A</text>
    <g>
      <rect x="560" y="49" width="30" height="12" rx="2" fill="#ff4d6d"/>
      <rect x="596" y="49" width="30" height="12" rx="2" fill="#ffd23f"/>
      <rect x="632" y="49" width="30" height="12" rx="2" fill="#3ec5ff"/>
      <rect x="668" y="49" width="30" height="12" rx="2" fill="#7dff6b"/>
    </g>
    <!-- wordmark: pink offset print, then ink -->
    <g font-family="'Arial Black', Impact, 'Segoe UI Black', sans-serif" font-weight="900" font-style="italic" font-size="112" text-anchor="middle">
      <text x="413" y="166" textLength="590" lengthAdjust="spacingAndGlyphs" fill="#ff4fa3">OVERDUB</text>
      <text x="406" y="160" textLength="590" lengthAdjust="spacingAndGlyphs" fill="#14110f">OVERDUB</text>
    </g>
    <!-- tape window -->
    <rect x="258" y="190" width="304" height="72" rx="36" fill="#2a2420" stroke="#f3ead8" stroke-width="4"/>
    <g clip-path="url(#od-logo-window)">
      <circle cx="320" cy="226" r="44" fill="#4a2f22"/>
      <circle cx="500" cy="226" r="30" fill="#4a2f22"/>
    </g>
    ${REEL(320, 226, 24, 'od-reel')}
    ${REEL(500, 226, 24, 'od-reel od-reel--b')}
    <!-- bottom guide notch -->
    <path d="M220 268 L250 236 L570 236 L600 268 Z" fill="none" stroke="#c9bfa9" stroke-width="3" opacity=".55"/>
    <rect x="120" y="200" width="104" height="10" rx="5" fill="#ffd23f"/>
    <rect x="120" y="218" width="70" height="10" rx="5" fill="#ff4fa3"/>
    <rect x="596" y="200" width="104" height="10" rx="5" fill="#ffd23f"/>
    <rect x="630" y="218" width="70" height="10" rx="5" fill="#a25bff"/>
  </g>
</svg>`;

/**
 * Stylised Moxie for the loadout paper doll. Each equipment slot is a group tagged with
 * data-slot so the focused slot can be highlighted (APPAREL-03: slots plainly identified).
 * Base look follows R01: yellow headphones, dark pigtails, light crop top, dark jacket with
 * yellow lining, olive low-rise cargo pants, belt Walkman, chunky high-tops.
 */
export const DOLL_SVG = `
<svg class="od-doll-svg" viewBox="0 0 240 440" aria-hidden="true">
  <g class="od-doll-base">
    <!-- pigtails -->
    <path d="M78 58 C52 44 38 76 46 104 C50 118 40 128 34 138 C58 132 70 112 72 92 Z" fill="#2b1d17"/>
    <path d="M162 58 C188 44 202 76 194 104 C190 118 200 128 206 138 C182 132 170 112 168 92 Z" fill="#2b1d17"/>
    <!-- neck & face -->
    <rect x="110" y="98" width="20" height="22" fill="#c98a62"/>
    <ellipse cx="120" cy="74" rx="30" ry="34" fill="#d9a07a"/>
    <path d="M90 70 C88 40 108 30 122 32 C142 32 156 46 150 72 C142 58 132 52 124 50 C118 60 104 64 90 70 Z" fill="#2b1d17"/>
    <path d="M104 86 l8 2 M128 88 l8 -2" stroke="#14110f" stroke-width="3" stroke-linecap="round"/>
    <path d="M112 98 q8 5 16 0" stroke="#14110f" stroke-width="2.5" fill="none" stroke-linecap="round"/>
    <path d="M97 82 l6 6 M97 88 l5 4" stroke="#ff4fa3" stroke-width="2" stroke-linecap="round"/>
    <!-- arms (skin), fingerless gloves -->
    <path d="M70 128 C56 160 52 196 56 226" stroke="#c98a62" stroke-width="16" fill="none" stroke-linecap="round"/>
    <path d="M170 128 C184 160 188 196 184 226" stroke="#c98a62" stroke-width="16" fill="none" stroke-linecap="round"/>
    <rect x="47" y="214" width="20" height="18" rx="5" fill="#14110f"/>
    <rect x="173" y="214" width="20" height="18" rx="5" fill="#14110f"/>
    <rect x="50" y="198" width="16" height="9" rx="2" fill="#3ec5ff" opacity=".85"/>
    <!-- midriff -->
    <path d="M94 168 L146 168 L148 196 L92 196 Z" fill="#d9a07a"/>
    <!-- belt + Walkman -->
    <rect x="86" y="194" width="68" height="11" rx="3" fill="#14110f"/>
    <rect x="132" y="190" width="22" height="18" rx="3" fill="#ffd23f" stroke="#14110f" stroke-width="2"/>
    <circle cx="139" cy="199" r="3" fill="#14110f"/><circle cx="147" cy="199" r="3" fill="#14110f"/>
    <path d="M143 190 C150 160 146 120 136 104" stroke="#ffd23f" stroke-width="2" fill="none"/>
    <path d="M100 205 l-6 46" stroke="#d6336c" stroke-width="6" stroke-linecap="round"/>
  </g>

  <g class="od-doll-part" data-slot="helmet">
    <path d="M86 70 C84 26 156 26 154 70" stroke="#ffd23f" stroke-width="7" fill="none" stroke-linecap="round"/>
    <rect x="78" y="58" width="18" height="32" rx="8" fill="#ffd23f" stroke="#14110f" stroke-width="3"/>
    <rect x="144" y="58" width="18" height="32" rx="8" fill="#ffd23f" stroke="#14110f" stroke-width="3"/>
    <path d="M150 68 l6 10 l-12 0 z" fill="#14110f"/>
  </g>

  <g class="od-doll-part" data-slot="top">
    <!-- crop top -->
    <path d="M96 120 L144 120 L150 170 L90 170 Z" fill="#f3ead8" stroke="#14110f" stroke-width="3"/>
    <path d="M100 122 L142 168" stroke="#2a2420" stroke-width="6"/>
    <!-- open jacket with yellow lining -->
    <path d="M96 118 C78 118 64 126 60 150 L56 196 L76 196 L84 150 L98 170 Z" fill="#2a2420" stroke="#14110f" stroke-width="3"/>
    <path d="M144 118 C162 118 176 126 180 150 L184 196 L164 196 L156 150 L142 170 Z" fill="#2a2420" stroke="#14110f" stroke-width="3"/>
    <path d="M90 128 L98 168" stroke="#ffd23f" stroke-width="4"/>
    <path d="M150 128 L142 168" stroke="#ffd23f" stroke-width="4"/>
    <path d="M64 150 l10 -6 l2 10 z" fill="#ffd23f"/>
  </g>

  <g class="od-doll-part" data-slot="pants">
    <path d="M88 204 L152 204 L168 352 L128 356 L120 262 L112 356 L72 352 Z" fill="#6b6a3a" stroke="#14110f" stroke-width="3"/>
    <path d="M78 300 l14 -14 l0 14 l14 -14" stroke="#ffd23f" stroke-width="6" fill="none" stroke-linejoin="round"/>
    <path d="M140 240 l10 0 l0 22 l-10 0 z" fill="#585731" stroke="#14110f" stroke-width="2"/>
    <path d="M72 344 L112 348 M128 348 L168 344" stroke="#585731" stroke-width="8"/>
  </g>

  <g class="od-doll-part" data-slot="shoes">
    <path d="M70 356 L112 358 L114 392 L120 404 L60 404 L62 384 Z" fill="#c9bfa9" stroke="#14110f" stroke-width="3"/>
    <path d="M128 358 L170 356 L178 384 L180 404 L120 404 L126 392 Z" fill="#c9bfa9" stroke="#14110f" stroke-width="3"/>
    <rect x="58" y="398" width="64" height="10" rx="4" fill="#2a2420"/>
    <rect x="118" y="398" width="64" height="10" rx="4" fill="#2a2420"/>
    <path d="M76 366 l24 8 M76 376 l24 -8 M140 374 l24 -8 M140 366 l24 8" stroke="#ffd23f" stroke-width="3"/>
  </g>

  <g class="od-doll-part" data-slot="melee">
    <rect x="18" y="120" width="12" height="110" rx="4" fill="#9aa3b5" stroke="#14110f" stroke-width="3" transform="rotate(-14 24 230)"/>
    <rect x="36" y="206" width="22" height="34" rx="5" fill="#14110f" transform="rotate(-14 24 230)"/>
    <path d="M24 130 l6 -12" stroke="#ff4fa3" stroke-width="3" transform="rotate(-14 24 230)"/>
  </g>

  <g class="od-doll-part" data-slot="ranged">
    <rect x="184" y="226" width="44" height="18" rx="5" fill="#2a2420" stroke="#14110f" stroke-width="3"/>
    <rect x="222" y="230" width="12" height="10" rx="2" fill="#3ec5ff"/>
    <rect x="190" y="242" width="12" height="20" rx="3" fill="#14110f"/>
    <circle cx="200" cy="235" r="3" fill="#ffd23f"/>
  </g>
</svg>`;

/** Padlock for locked levels. */
export const LOCK_SVG = `
<svg viewBox="0 0 24 24" class="od-ico" aria-hidden="true">
  <rect x="5" y="10" width="14" height="11" rx="2" fill="currentColor"/>
  <path d="M8 10V7a4 4 0 0 1 8 0v3" stroke="currentColor" stroke-width="2.4" fill="none"/>
  <circle cx="12" cy="15" r="1.6" fill="#14110f"/>
</svg>`;

/** Check for cleared levels. */
export const CHECK_SVG = `
<svg viewBox="0 0 24 24" class="od-ico" aria-hidden="true">
  <path d="M4 12.5l5 5L20 6" stroke="currentColor" stroke-width="3.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
</svg>`;

/** The time machine at the bottom of the descent (WORLD-05): a ringed gate with clock hands. */
export const TIME_MACHINE_SVG = `
<svg viewBox="0 0 64 64" class="od-tm" aria-hidden="true">
  <circle cx="32" cy="32" r="27" fill="none" stroke="#a25bff" stroke-width="4"/>
  <circle cx="32" cy="32" r="20" fill="#14110f" stroke="#4ff3ff" stroke-width="3" stroke-dasharray="4 3"/>
  <g class="od-tm-hands">
    <path d="M32 32 L32 18" stroke="#ffd23f" stroke-width="3" stroke-linecap="round"/>
    <path d="M32 32 L42 36" stroke="#ff4fa3" stroke-width="3" stroke-linecap="round"/>
  </g>
  <circle cx="32" cy="32" r="3" fill="#ffd23f"/>
  <path d="M8 54 L56 54" stroke="#ffd23f" stroke-width="3" stroke-dasharray="6 4"/>
</svg>`;

/** Crate for loot counts. */
export const CRATE_SVG = `
<svg viewBox="0 0 24 24" class="od-ico" aria-hidden="true">
  <rect x="3" y="7" width="18" height="13" rx="2" fill="currentColor"/>
  <rect x="3" y="4" width="18" height="5" rx="1.5" fill="currentColor" opacity=".75"/>
  <rect x="10" y="9" width="4" height="4" rx="1" fill="#14110f"/>
</svg>`;
