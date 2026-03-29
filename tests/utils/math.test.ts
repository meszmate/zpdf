import { describe, it, expect } from 'vitest';
import {
  identityMatrix, multiplyMatrices, translateMatrix, rotateMatrix,
  scaleMatrix, skewMatrix, transformPoint, invertMatrix,
} from '../../src/utils/math.js';

describe('identityMatrix', () => {
  it('returns [1,0,0,1,0,0]', () => {
    expect(identityMatrix()).toEqual([1, 0, 0, 1, 0, 0]);
  });
});

describe('translateMatrix', () => {
  it('creates a translation matrix', () => {
    const m = translateMatrix(10, 20);
    expect(m).toEqual([1, 0, 0, 1, 10, 20]);
  });

  it('translates a point correctly', () => {
    const m = translateMatrix(5, 10);
    const result = transformPoint(m, { x: 0, y: 0 });
    expect(result.x).toBe(5);
    expect(result.y).toBe(10);
  });
});

describe('scaleMatrix', () => {
  it('creates a scaling matrix', () => {
    const m = scaleMatrix(2, 3);
    expect(m).toEqual([2, 0, 0, 3, 0, 0]);
  });

  it('scales a point correctly', () => {
    const m = scaleMatrix(2, 3);
    const result = transformPoint(m, { x: 5, y: 10 });
    expect(result.x).toBe(10);
    expect(result.y).toBe(30);
  });
});

describe('rotateMatrix', () => {
  it('creates a 90-degree rotation', () => {
    const m = rotateMatrix(90);
    // cos(90) ~ 0, sin(90) ~ 1
    expect(m[0]).toBeCloseTo(0, 10);
    expect(m[1]).toBeCloseTo(1, 10);
    expect(m[2]).toBeCloseTo(-1, 10);
    expect(m[3]).toBeCloseTo(0, 10);
  });

  it('rotates a point 90 degrees', () => {
    const m = rotateMatrix(90);
    const result = transformPoint(m, { x: 1, y: 0 });
    expect(result.x).toBeCloseTo(0, 10);
    expect(result.y).toBeCloseTo(1, 10);
  });

  it('360 degrees is identity', () => {
    const m = rotateMatrix(360);
    const result = transformPoint(m, { x: 5, y: 7 });
    expect(result.x).toBeCloseTo(5, 10);
    expect(result.y).toBeCloseTo(7, 10);
  });
});

describe('skewMatrix', () => {
  it('creates a skew matrix', () => {
    const m = skewMatrix(45, 0);
    expect(m[0]).toBe(1);
    expect(m[1]).toBeCloseTo(0);
    expect(m[2]).toBeCloseTo(1); // tan(45) = 1
    expect(m[3]).toBe(1);
  });
});

describe('multiplyMatrices', () => {
  it('identity * any = any', () => {
    const m = translateMatrix(10, 20);
    const result = multiplyMatrices(identityMatrix(), m);
    expect(result).toEqual(m);
  });

  it('any * identity = any', () => {
    const m = scaleMatrix(2, 3);
    const result = multiplyMatrices(m, identityMatrix());
    expect(result).toEqual(m);
  });

  it('composes translate then scale', () => {
    const t = translateMatrix(10, 20);
    const s = scaleMatrix(2, 2);
    const combined = multiplyMatrices(t, s);
    // translate(10,20) then scale(2,2): point (1,1) -> (12, 22) after translate -> (24, 44) after scale
    const result = transformPoint(combined, { x: 1, y: 1 });
    expect(result.x).toBeCloseTo(22);
    expect(result.y).toBeCloseTo(42);
  });
});

describe('invertMatrix', () => {
  it('inverts identity to identity', () => {
    const inv = invertMatrix(identityMatrix());
    expect(inv).toBeTruthy();
    expect(inv![0]).toBeCloseTo(1);
    expect(inv![3]).toBeCloseTo(1);
    expect(inv![4]).toBeCloseTo(0);
    expect(inv![5]).toBeCloseTo(0);
  });

  it('inverts a translation', () => {
    const m = translateMatrix(10, 20);
    const inv = invertMatrix(m);
    expect(inv).toBeTruthy();
    // Applying the inverse should undo the translation
    const result = transformPoint(inv!, transformPoint(m, { x: 5, y: 7 }));
    expect(result.x).toBeCloseTo(5);
    expect(result.y).toBeCloseTo(7);
  });

  it('inverts a scale', () => {
    const m = scaleMatrix(2, 4);
    const inv = invertMatrix(m);
    expect(inv).toBeTruthy();
    const p = transformPoint(inv!, { x: 10, y: 20 });
    expect(p.x).toBeCloseTo(5);
    expect(p.y).toBeCloseTo(5);
  });

  it('returns null for singular matrix', () => {
    // A matrix with determinant 0
    const result = invertMatrix([0, 0, 0, 0, 0, 0]);
    expect(result).toBeNull();
  });
});

describe('transformPoint', () => {
  it('applies identity transform', () => {
    const p = transformPoint(identityMatrix(), { x: 3, y: 7 });
    expect(p.x).toBe(3);
    expect(p.y).toBe(7);
  });

  it('applies translation', () => {
    const p = transformPoint(translateMatrix(100, 200), { x: 0, y: 0 });
    expect(p.x).toBe(100);
    expect(p.y).toBe(200);
  });
});
