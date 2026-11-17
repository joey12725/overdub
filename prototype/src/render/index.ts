/**
 * Render module facade (contracts.ts): `createRenderer(): IRenderer`.
 */
import type { IRenderer } from '../contracts';
import { OverdubRenderer, type RendererOptions } from './Renderer';

export function createRenderer(options?: RendererOptions): IRenderer & OverdubRenderer {
  return new OverdubRenderer(options);
}

export { OverdubRenderer } from './Renderer';
export type { RendererOptions, LayerFactory } from './Renderer';
export { PALETTES, paletteFor } from './palettes';
export type { EnvPalette } from './palettes';
export type { RenderCtx, RenderLayer, ThemePalette, MusicReactive, PostControls } from './layer';
export { signalAccent, buildAccentMap, exprAccent, MECH_ACCENTS } from './mechs/accent';
