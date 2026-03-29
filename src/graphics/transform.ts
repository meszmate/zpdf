import type { Matrix } from '../utils/math.js';
import {
  identityMatrix,
  multiplyMatrices,
  translateMatrix,
  rotateMatrix,
  scaleMatrix,
  skewMatrix,
  transformPoint,
  invertMatrix,
} from '../utils/math.js';
import * as ops from './operators.js';

// Re-export all matrix utilities
export {
  identityMatrix,
  multiplyMatrices,
  translateMatrix,
  rotateMatrix,
  scaleMatrix,
  skewMatrix,
  transformPoint,
  invertMatrix,
};

export type { Matrix };

export function applyTransformOperator(matrix: Matrix): string {
  return ops.concatMatrix(matrix);
}

export function createRotation(angleDeg: number, cx?: number, cy?: number): Matrix {
  if (cx !== undefined && cy !== undefined) {
    // Translate to origin, rotate, translate back
    const t1 = translateMatrix(-cx, -cy);
    const r = rotateMatrix(angleDeg);
    const t2 = translateMatrix(cx, cy);
    return multiplyMatrices(multiplyMatrices(t1, r), t2);
  }
  return rotateMatrix(angleDeg);
}

export function createScaling(sx: number, sy: number, cx?: number, cy?: number): Matrix {
  if (cx !== undefined && cy !== undefined) {
    // Translate to origin, scale, translate back
    const t1 = translateMatrix(-cx, -cy);
    const s = scaleMatrix(sx, sy);
    const t2 = translateMatrix(cx, cy);
    return multiplyMatrices(multiplyMatrices(t1, s), t2);
  }
  return scaleMatrix(sx, sy);
}
