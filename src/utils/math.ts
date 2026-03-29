export interface Point {
  x: number;
  y: number;
}

export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

/**
 * 2D affine transformation matrix [a, b, c, d, e, f].
 * Represents the matrix:
 *   | a  b  0 |
 *   | c  d  0 |
 *   | e  f  1 |
 */
export type Matrix = [number, number, number, number, number, number];

export function identityMatrix(): Matrix {
  return [1, 0, 0, 1, 0, 0];
}

export function multiplyMatrices(a: Matrix, b: Matrix): Matrix {
  return [
    a[0] * b[0] + a[1] * b[2],
    a[0] * b[1] + a[1] * b[3],
    a[2] * b[0] + a[3] * b[2],
    a[2] * b[1] + a[3] * b[3],
    a[4] * b[0] + a[5] * b[2] + b[4],
    a[4] * b[1] + a[5] * b[3] + b[5],
  ];
}

export function translateMatrix(tx: number, ty: number): Matrix {
  return [1, 0, 0, 1, tx, ty];
}

export function rotateMatrix(angleDeg: number): Matrix {
  const rad = (angleDeg * Math.PI) / 180;
  const cos = Math.cos(rad);
  const sin = Math.sin(rad);
  return [cos, sin, -sin, cos, 0, 0];
}

export function scaleMatrix(sx: number, sy: number): Matrix {
  return [sx, 0, 0, sy, 0, 0];
}

export function skewMatrix(ax: number, ay: number): Matrix {
  const tanA = Math.tan((ax * Math.PI) / 180);
  const tanB = Math.tan((ay * Math.PI) / 180);
  return [1, tanB, tanA, 1, 0, 0];
}

export function transformPoint(m: Matrix, p: Point): Point {
  return {
    x: m[0] * p.x + m[2] * p.y + m[4],
    y: m[1] * p.x + m[3] * p.y + m[5],
  };
}

export function invertMatrix(m: Matrix): Matrix | null {
  const [a, b, c, d, e, f] = m;
  const det = a * d - b * c;
  if (Math.abs(det) < 1e-12) return null;
  const invDet = 1 / det;
  return [
    d * invDet,
    -b * invDet,
    -c * invDet,
    a * invDet,
    (c * f - d * e) * invDet,
    (b * e - a * f) * invDet,
  ];
}
