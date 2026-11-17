/**
 * Procedural sprite shapes and orientation modes, shared by the CPU pools and the sprite shader.
 * Shapes are drawn analytically in the fragment shader so no texture is needed.
 */

export const SHAPE_GLOW = 0;
export const SHAPE_SPARK = 1;
export const SHAPE_STREAK = 2;
export const SHAPE_RING = 3;
export const SHAPE_DEBRIS = 4;
export const SHAPE_CHEVRON = 5;
export const SHAPE_INK = 6;
export const SHAPE_ARC = 7;
export const SHAPE_CROSS = 8;
export const SHAPE_DASHRING = 9;
export const SHAPE_GLITCH = 10;
export const SHAPE_STAR = 11;
export const SHAPE_STOP = 12;
export const SHAPE_SHARD = 13;
export const SHAPE_DOT = 14;

/** Camera-facing quad. */
export const MODE_BILLBOARD = 0;
/** Lies flat on the floor (XZ plane), rotated by `rot`. */
export const MODE_FLOOR = 1;
/** Camera-facing quad stretched along a world direction (`dir`, length factor `stretch`). */
export const MODE_STREAK = 2;
