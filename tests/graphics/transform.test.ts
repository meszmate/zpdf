import { describe, it, expect } from 'vitest';
import {
  identityMatrix, multiplyMatrices, translateMatrix, rotateMatrix,
  scaleMatrix, skewMatrix, transformPoint, invertMatrix,
  applyTransformOperator, createRotation, createScaling,
} from '../../src/graphics/transform.js';

describe('transform module re-exports', () => {
  it('identityMatrix works', () => {
    expect(identityMatrix()).toEqual([1, 0, 0, 1, 0, 0]);
  });

  it('translateMatrix works', () => {
    expect(translateMatrix(10, 20)).toEqual([1, 0, 0, 1, 10, 20]);
  });

  it('scaleMatrix works', () => {
    expect(scaleMatrix(2, 3)).toEqual([2, 0, 0, 3, 0, 0]);
  });
});

describe('applyTransformOperator', () => {
  it('generates cm operator string', () => {
    const result = applyTransformOperator([1, 0, 0, 1, 10, 20]);
    expect(result).toContain('cm');
    expect(result).toContain('10');
    expect(result).toContain('20');
  });
});

describe('createRotation', () => {
  it('creates a simple rotation without center', () => {
    const m = createRotation(90);
    const p = transformPoint(m, { x: 1, y: 0 });
    expect(p.x).toBeCloseTo(0);
    expect(p.y).toBeCloseTo(1);
  });

  it('creates a rotation around a center point', () => {
    const m = createRotation(180, 50, 50);
    // Point (100, 50) rotated 180 around (50,50) should be (0, 50)
    const p = transformPoint(m, { x: 100, y: 50 });
    expect(p.x).toBeCloseTo(0);
    expect(p.y).toBeCloseTo(50);
  });
});

describe('createScaling', () => {
  it('creates simple scaling without center', () => {
    const m = createScaling(2, 3);
    expect(m).toEqual(scaleMatrix(2, 3));
  });

  it('creates scaling around a center point', () => {
    const m = createScaling(2, 2, 50, 50);
    // Point (100, 100) scaled 2x around (50,50):
    // translate to origin: (50, 50)
    // scale: (100, 100)
    // translate back: (150, 150)
    const p = transformPoint(m, { x: 100, y: 100 });
    expect(p.x).toBeCloseTo(150);
    expect(p.y).toBeCloseTo(150);
  });
});
