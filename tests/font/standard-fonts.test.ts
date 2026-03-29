import { describe, it, expect } from 'vitest';
import { StandardFonts, getStandardFont, STANDARD_FONT_NAMES } from '../../src/font/standard-fonts.js';
import { encodeWinAnsi, isWinAnsiEncodable } from '../../src/font/encoding.js';

describe('StandardFonts', () => {
  it('contains all 14 standard fonts', () => {
    expect(STANDARD_FONT_NAMES.length).toBe(14);
    for (const name of STANDARD_FONT_NAMES) {
      expect(StandardFonts[name]).toBeDefined();
    }
  });

  it('getStandardFont returns font by name', () => {
    const font = getStandardFont('Helvetica');
    expect(font).toBeDefined();
    expect(font!.name).toBe('Helvetica');
    expect(font!.isStandard).toBe(true);
  });

  it('getStandardFont returns undefined for unknown name', () => {
    expect(getStandardFont('NotAFont')).toBeUndefined();
  });

  it('Helvetica measures text width', () => {
    const font = getStandardFont('Helvetica')!;
    const width = font.measureWidth('Hello', 12);
    expect(width).toBeGreaterThan(0);
    // "Hello" in Helvetica at 12pt should be roughly 24-30pt
    expect(width).toBeGreaterThan(20);
    expect(width).toBeLessThan(40);
  });

  it('Courier is monospaced at 600 units per glyph', () => {
    const font = getStandardFont('Courier')!;
    // At 10pt, each char = 600/1000 * 10 = 6pt
    const singleChar = font.measureWidth('X', 10);
    expect(singleChar).toBeCloseTo(6, 1);

    const threeChars = font.measureWidth('XXX', 10);
    expect(threeChars).toBeCloseTo(18, 1);
  });

  it('measureWidth scales with fontSize', () => {
    const font = getStandardFont('Helvetica')!;
    const w12 = font.measureWidth('A', 12);
    const w24 = font.measureWidth('A', 24);
    expect(w24).toBeCloseTo(w12 * 2, 5);
  });

  it('encode returns Uint8Array for WinAnsi text', () => {
    const font = getStandardFont('Helvetica')!;
    const encoded = font.encode('ABC');
    expect(encoded).toBeInstanceOf(Uint8Array);
    expect(encoded.length).toBe(3);
    expect(encoded[0]).toBe(65); // A
    expect(encoded[1]).toBe(66); // B
    expect(encoded[2]).toBe(67); // C
  });

  it('getLineHeight returns a positive value', () => {
    const font = getStandardFont('Helvetica')!;
    const lh = font.getLineHeight(12);
    expect(lh).toBeGreaterThan(0);
    // Helvetica: (718 - (-207) + 0) / 1000 * 12 = 11.1
    expect(lh).toBeCloseTo(11.1, 0);
  });

  it('font metrics have expected properties', () => {
    const font = getStandardFont('Times-Roman')!;
    const m = font.metrics;
    expect(m.ascent).toBe(683);
    expect(m.descent).toBe(-217);
    expect(m.unitsPerEm).toBe(1000);
    expect(m.bbox).toHaveLength(4);
    expect(m.widths).toBeInstanceOf(Map);
    expect(m.widths.size).toBeGreaterThan(0);
  });

  it('Symbol and ZapfDingbats are marked symbolic', () => {
    const symbol = getStandardFont('Symbol')!;
    const zapf = getStandardFont('ZapfDingbats')!;
    expect(symbol.metrics.flags & 0x04).toBeTruthy();
    expect(zapf.metrics.flags & 0x04).toBeTruthy();
  });

  it('Helvetica space width matches expected value', () => {
    const font = getStandardFont('Helvetica')!;
    // Space (code 32) width is 278 in Helvetica
    const spaceWidth = font.metrics.widths.get(32);
    expect(spaceWidth).toBe(278);
  });
});

describe('encodeWinAnsi', () => {
  it('encodes ASCII characters', () => {
    const result = encodeWinAnsi('Hello');
    expect(result).toEqual(new Uint8Array([72, 101, 108, 108, 111]));
  });

  it('encodes Euro sign to 0x80', () => {
    const result = encodeWinAnsi('\u20AC');
    expect(result[0]).toBe(0x80);
  });

  it('replaces unmappable characters with ?', () => {
    const result = encodeWinAnsi('\u4E00'); // CJK character
    expect(result[0]).toBe(0x3F); // '?'
  });
});

describe('isWinAnsiEncodable', () => {
  it('returns true for ASCII', () => {
    expect(isWinAnsiEncodable('Hello World 123')).toBe(true);
  });

  it('returns true for Euro sign', () => {
    expect(isWinAnsiEncodable('\u20AC')).toBe(true);
  });

  it('returns false for CJK characters', () => {
    expect(isWinAnsiEncodable('\u4E00')).toBe(false);
  });
});
