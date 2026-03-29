import { describe, it, expect } from 'vitest';
import { rgb, cmyk, grayscale, hexColor } from '../../src/color/color.js';
import { rgbToCmyk, cmykToRgb, rgbToGrayscale, grayscaleToRgb } from '../../src/color/conversion.js';
import { NAMED_COLORS } from '../../src/color/named-colors.js';

describe('rgb', () => {
  it('creates an RGB color with values normalized to 0-1', () => {
    const c = rgb(255, 128, 0);
    expect(c.type).toBe('rgb');
    expect(c.r).toBeCloseTo(1.0);
    expect(c.g).toBeCloseTo(128 / 255);
    expect(c.b).toBeCloseTo(0);
  });

  it('clamps values to 0-1', () => {
    const c = rgb(300, -10, 128);
    expect(c.r).toBe(1);
    expect(c.g).toBe(0);
    expect(c.b).toBeCloseTo(128 / 255);
  });

  it('black is all zeros', () => {
    const c = rgb(0, 0, 0);
    expect(c.r).toBe(0);
    expect(c.g).toBe(0);
    expect(c.b).toBe(0);
  });
});

describe('cmyk', () => {
  it('creates a CMYK color with values normalized from percentages', () => {
    const c = cmyk(100, 50, 0, 25);
    expect(c.type).toBe('cmyk');
    expect(c.c).toBeCloseTo(1.0);
    expect(c.m).toBeCloseTo(0.5);
    expect(c.y).toBe(0);
    expect(c.k).toBeCloseTo(0.25);
  });

  it('clamps values', () => {
    const c = cmyk(150, -10, 50, 50);
    expect(c.c).toBe(1);
    expect(c.m).toBe(0);
  });
});

describe('grayscale', () => {
  it('creates a grayscale color', () => {
    const c = grayscale(0.5);
    expect(c.type).toBe('grayscale');
    expect(c.gray).toBeCloseTo(0.5);
  });

  it('clamps values', () => {
    expect(grayscale(-0.5).gray).toBe(0);
    expect(grayscale(1.5).gray).toBe(1);
  });
});

describe('hexColor', () => {
  it('parses 6-digit hex with #', () => {
    const c = hexColor('#FF0000');
    expect(c.r).toBeCloseTo(1.0);
    expect(c.g).toBeCloseTo(0);
    expect(c.b).toBeCloseTo(0);
  });

  it('parses 6-digit hex without #', () => {
    const c = hexColor('00FF00');
    expect(c.g).toBeCloseTo(1.0);
  });

  it('parses 3-digit shorthand', () => {
    const c = hexColor('#F00');
    expect(c.r).toBeCloseTo(1.0);
    expect(c.g).toBeCloseTo(0);
    expect(c.b).toBeCloseTo(0);
  });

  it('throws on invalid hex', () => {
    expect(() => hexColor('#GGGG')).toThrow('Invalid hex color');
    expect(() => hexColor('12345')).toThrow('Invalid hex color');
  });
});

describe('color conversions', () => {
  it('rgbToCmyk converts black', () => {
    const result = rgbToCmyk({ type: 'rgb', r: 0, g: 0, b: 0 });
    expect(result.k).toBe(1);
    expect(result.c).toBe(0);
    expect(result.m).toBe(0);
    expect(result.y).toBe(0);
  });

  it('rgbToCmyk converts white', () => {
    const result = rgbToCmyk({ type: 'rgb', r: 1, g: 1, b: 1 });
    expect(result.k).toBeCloseTo(0);
    expect(result.c).toBeCloseTo(0);
    expect(result.m).toBeCloseTo(0);
    expect(result.y).toBeCloseTo(0);
  });

  it('rgbToCmyk converts red', () => {
    const result = rgbToCmyk({ type: 'rgb', r: 1, g: 0, b: 0 });
    expect(result.c).toBeCloseTo(0);
    expect(result.m).toBeCloseTo(1);
    expect(result.y).toBeCloseTo(1);
    expect(result.k).toBeCloseTo(0);
  });

  it('cmykToRgb round-trips', () => {
    const original = { type: 'rgb' as const, r: 0.5, g: 0.3, b: 0.8 };
    const cmykVal = rgbToCmyk(original);
    const back = cmykToRgb(cmykVal);
    expect(back.r).toBeCloseTo(original.r, 5);
    expect(back.g).toBeCloseTo(original.g, 5);
    expect(back.b).toBeCloseTo(original.b, 5);
  });

  it('rgbToGrayscale uses BT.709 coefficients', () => {
    const result = rgbToGrayscale({ type: 'rgb', r: 1, g: 0, b: 0 });
    expect(result.gray).toBeCloseTo(0.2126);
  });

  it('grayscaleToRgb creates equal R/G/B', () => {
    const result = grayscaleToRgb({ type: 'grayscale', gray: 0.5 });
    expect(result.r).toBeCloseTo(0.5);
    expect(result.g).toBeCloseTo(0.5);
    expect(result.b).toBeCloseTo(0.5);
  });
});

describe('named colors', () => {
  it('contains standard web colors', () => {
    expect(NAMED_COLORS.red).toBeDefined();
    expect(NAMED_COLORS.red.r).toBeCloseTo(1);
    expect(NAMED_COLORS.red.g).toBeCloseTo(0);
    expect(NAMED_COLORS.red.b).toBeCloseTo(0);

    expect(NAMED_COLORS.blue).toBeDefined();
    expect(NAMED_COLORS.blue.r).toBeCloseTo(0);
    expect(NAMED_COLORS.blue.g).toBeCloseTo(0);
    expect(NAMED_COLORS.blue.b).toBeCloseTo(1);
  });

  it('contains black and white', () => {
    expect(NAMED_COLORS.black.r).toBe(0);
    expect(NAMED_COLORS.black.g).toBe(0);
    expect(NAMED_COLORS.black.b).toBe(0);

    expect(NAMED_COLORS.white.r).toBeCloseTo(1);
    expect(NAMED_COLORS.white.g).toBeCloseTo(1);
    expect(NAMED_COLORS.white.b).toBeCloseTo(1);
  });

  it('all colors have type rgb', () => {
    for (const [name, color] of Object.entries(NAMED_COLORS)) {
      expect(color.type).toBe('rgb');
      expect(color.r).toBeGreaterThanOrEqual(0);
      expect(color.r).toBeLessThanOrEqual(1);
    }
  });
});
