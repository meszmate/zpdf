import { describe, it, expect } from 'vitest';
import { PathBuilder } from '../../src/graphics/path-builder.js';

describe('PathBuilder', () => {
  it('moveTo generates m operator', () => {
    const path = new PathBuilder();
    path.moveTo(10, 20);
    expect(path.toOperators()).toContain('10');
    expect(path.toOperators()).toContain('20');
    expect(path.toOperators()).toContain('m');
  });

  it('lineTo generates l operator', () => {
    const path = new PathBuilder();
    path.moveTo(0, 0).lineTo(100, 200);
    const ops = path.toOperators();
    expect(ops).toContain('l');
    expect(ops).toContain('100');
  });

  it('curveTo generates c operator', () => {
    const path = new PathBuilder();
    path.moveTo(0, 0).curveTo(10, 20, 30, 40, 50, 60);
    const ops = path.toOperators();
    expect(ops).toContain('c');
  });

  it('closePath generates h operator', () => {
    const path = new PathBuilder();
    path.moveTo(0, 0).lineTo(100, 0).lineTo(100, 100).closePath();
    expect(path.toOperators()).toContain('h');
  });

  it('rect generates re operator', () => {
    const path = new PathBuilder();
    path.rect(10, 20, 100, 50);
    const ops = path.toOperators();
    expect(ops).toContain('re');
    expect(ops).toContain('10');
    expect(ops).toContain('20');
    expect(ops).toContain('100');
    expect(ops).toContain('50');
  });

  it('circle produces closed ellipse path', () => {
    const path = new PathBuilder();
    path.circle(50, 50, 25);
    const ops = path.toOperators();
    // Circle is drawn with moveTo + 4 curveTo + close
    expect(ops).toContain('m');
    expect(ops).toContain('c');
    expect(ops).toContain('h');
  });

  it('ellipse produces closed path', () => {
    const path = new PathBuilder();
    path.ellipse(100, 100, 50, 30);
    const ops = path.toOperators();
    expect(ops).toContain('m');
    expect(ops).toContain('c');
    expect(ops).toContain('h');
  });

  it('polygon creates closed shape', () => {
    const path = new PathBuilder();
    path.polygon([{ x: 0, y: 0 }, { x: 100, y: 0 }, { x: 50, y: 100 }]);
    const ops = path.toOperators();
    expect(ops).toContain('m');
    expect(ops).toContain('l');
    expect(ops).toContain('h');
  });

  it('polygon with fewer than 2 points does nothing', () => {
    const path = new PathBuilder();
    path.polygon([{ x: 0, y: 0 }]);
    expect(path.toOperators()).toBe('');
  });

  it('roundRect generates curves at corners', () => {
    const path = new PathBuilder();
    path.roundRect(0, 0, 100, 50, 10);
    const ops = path.toOperators();
    expect(ops).toContain('m');
    expect(ops).toContain('l');
    expect(ops).toContain('c');
    expect(ops).toContain('h');
  });

  it('chaining returns this', () => {
    const path = new PathBuilder();
    const result = path.moveTo(0, 0).lineTo(1, 1).closePath();
    expect(result).toBe(path);
  });

  it('arc generates bezier curves', () => {
    const path = new PathBuilder();
    path.arc(50, 50, 25, 0, Math.PI / 2);
    const ops = path.toOperators();
    expect(ops).toContain('c');
  });
});
