import { describe, it, expect } from 'vitest';
import { encodeCode128, renderCode128 } from '../../src/barcode/code128.js';
import { encodeCode39, renderCode39 } from '../../src/barcode/code39.js';
import { encodeEAN13, renderEAN13 } from '../../src/barcode/ean13.js';
import { generateQRCode } from '../../src/barcode/qr/qr-code.js';

describe('Code 128', () => {
  it('encodes a simple string', () => {
    const bits = encodeCode128('ABC123');
    expect(bits.length).toBeGreaterThan(0);
    // Should contain both true (bar) and false (space) values
    expect(bits.includes(true)).toBe(true);
    expect(bits.includes(false)).toBe(true);
  });

  it('throws on empty data', () => {
    expect(() => encodeCode128('')).toThrow('data cannot be empty');
  });

  it('encodes digits efficiently with Code C', () => {
    const bitsDigits = encodeCode128('123456');
    const bitsAlpha = encodeCode128('ABCDEF');
    // Code C encodes 2 digits per symbol, so digits should be shorter
    expect(bitsDigits.length).toBeLessThan(bitsAlpha.length);
  });

  it('handles lowercase characters', () => {
    const bits = encodeCode128('hello');
    expect(bits.length).toBeGreaterThan(0);
  });

  it('renderCode128 produces PDF operators', () => {
    const ops = renderCode128('TEST', 10, 20, 200, 50);
    expect(ops.length).toBeGreaterThan(0);
    // Should contain rectangle drawing operators
    expect(ops).toContain('re');
  });
});

describe('Code 39', () => {
  it('encodes alphanumeric data', () => {
    const bits = encodeCode39('ABC123');
    expect(bits.length).toBeGreaterThan(0);
    expect(bits.includes(true)).toBe(true);
    expect(bits.includes(false)).toBe(true);
  });

  it('auto-converts to uppercase', () => {
    // Should not throw for lowercase
    const bits = encodeCode39('abc');
    expect(bits.length).toBeGreaterThan(0);
  });

  it('supports special characters', () => {
    const bits = encodeCode39('A-B.C $');
    expect(bits.length).toBeGreaterThan(0);
  });

  it('throws on invalid characters', () => {
    expect(() => encodeCode39('{')).toThrow('invalid character');
  });

  it('renderCode39 produces PDF operators', () => {
    const ops = renderCode39('HELLO', 0, 0, 100, 30);
    expect(ops).toContain('re');
  });
});

describe('EAN-13', () => {
  it('encodes 12 digits and computes check digit', () => {
    const bits = encodeEAN13('590123412345');
    expect(bits.length).toBe(95); // EAN-13 is always 95 modules
  });

  it('encodes 13 digits with valid check digit', () => {
    // "5901234123457" is a valid EAN-13
    const bits = encodeEAN13('5901234123457');
    expect(bits.length).toBe(95);
  });

  it('throws on invalid check digit', () => {
    expect(() => encodeEAN13('5901234123450')).toThrow('invalid check digit');
  });

  it('throws on non-digit input', () => {
    expect(() => encodeEAN13('ABCDEFGHIJKL')).toThrow('must be 12 or 13 digits');
  });

  it('throws on wrong length', () => {
    expect(() => encodeEAN13('123')).toThrow('must be 12 or 13 digits');
  });

  it('starts and ends with guard bars', () => {
    const bits = encodeEAN13('590123412345');
    // Start guard: bar, space, bar (1,0,1)
    expect(bits[0]).toBe(true);
    expect(bits[1]).toBe(false);
    expect(bits[2]).toBe(true);
    // End guard: bar, space, bar
    expect(bits[92]).toBe(true);
    expect(bits[93]).toBe(false);
    expect(bits[94]).toBe(true);
  });

  it('renderEAN13 produces PDF operators', () => {
    const ops = renderEAN13('590123412345', 0, 0, 100, 30);
    expect(ops).toContain('re');
  });
});

describe('QR Code', () => {
  it('generates a QR code matrix', () => {
    const matrix = generateQRCode('Hello');
    expect(matrix.length).toBeGreaterThan(0);
    // QR code version 1 is 21x21
    expect(matrix.length).toBeGreaterThanOrEqual(21);
    expect(matrix[0].length).toBe(matrix.length); // Square
  });

  it('generates larger matrix for more data', () => {
    const small = generateQRCode('Hi');
    const large = generateQRCode('This is a much longer string that needs more space');
    expect(large.length).toBeGreaterThan(small.length);
  });

  it('respects error level option', () => {
    const matrixL = generateQRCode('Test', { errorLevel: 'L' });
    const matrixH = generateQRCode('Test', { errorLevel: 'H' });
    // Higher error level may need a larger version
    expect(matrixH.length).toBeGreaterThanOrEqual(matrixL.length);
  });

  it('respects version option', () => {
    const matrix = generateQRCode('A', { version: 5 });
    // Version 5 is 37x37
    expect(matrix.length).toBe(37);
  });

  it('throws when data is too long for specified version', () => {
    expect(() =>
      generateQRCode('A'.repeat(200), { version: 1 })
    ).toThrow();
  });

  it('contains finder patterns (top-left 7x7)', () => {
    const matrix = generateQRCode('A');
    // Top-left finder: first 7 rows/cols should have the border pattern
    // Top row: true true true true true true true
    for (let i = 0; i < 7; i++) {
      expect(matrix[0][i]).toBe(true);
    }
  });
});
