import type { Color } from '../color/color.js';
import { renderBars, type Bar } from './barcode-renderer.js';

/**
 * EAN-13 encoding tables.
 * L-codes (left odd parity), G-codes (left even parity), R-codes (right).
 * Each digit 0-9 is encoded as 7 modules.
 */
const L_CODES: number[][] = [
  [0,0,0,1,1,0,1], // 0
  [0,0,1,1,0,0,1], // 1
  [0,0,1,0,0,1,1], // 2
  [0,1,1,1,1,0,1], // 3
  [0,1,0,0,0,1,1], // 4
  [0,1,1,0,0,0,1], // 5
  [0,1,0,1,1,1,1], // 6
  [0,1,1,1,0,1,1], // 7
  [0,1,1,0,1,1,1], // 8
  [0,0,0,1,0,1,1], // 9
];

const G_CODES: number[][] = [
  [0,1,0,0,1,1,1], // 0
  [0,1,1,0,0,1,1], // 1
  [0,0,1,1,0,1,1], // 2
  [0,1,0,0,0,0,1], // 3
  [0,0,1,1,1,0,1], // 4
  [0,1,1,1,0,0,1], // 5
  [0,0,0,0,1,0,1], // 6
  [0,0,1,0,0,0,1], // 7
  [0,0,0,1,0,0,1], // 8
  [0,0,1,0,1,1,1], // 9
];

const R_CODES: number[][] = [
  [1,1,1,0,0,1,0], // 0
  [1,1,0,0,1,1,0], // 1
  [1,1,0,1,1,0,0], // 2
  [1,0,0,0,0,1,0], // 3
  [1,0,1,1,1,0,0], // 4
  [1,0,0,1,1,1,0], // 5
  [1,0,1,0,0,0,0], // 6
  [1,0,0,0,1,0,0], // 7
  [1,0,0,1,0,0,0], // 8
  [1,1,1,0,1,0,0], // 9
];

/**
 * Parity patterns for the first digit (determines L/G encoding for digits 2-7).
 * 0 = L encoding, 1 = G encoding.
 */
const PARITY_PATTERNS: number[][] = [
  [0,0,0,0,0,0], // 0: LLLLLL
  [0,0,1,0,1,1], // 1: LLGLGG
  [0,0,1,1,0,1], // 2: LLGGDG -> LLGGLG
  [0,0,1,1,1,0], // 3: LLGGGL
  [0,1,0,0,1,1], // 4: LGLLGG
  [0,1,1,0,0,1], // 5: LGGLGG -> LGGLLG
  [0,1,1,1,0,0], // 6: LGGGLL
  [0,1,0,1,0,1], // 7: LGLGLG
  [0,1,0,1,1,0], // 8: LGLGGL
  [0,1,1,0,1,0], // 9: LGGLGL
];

// Guard patterns
const START_GUARD = [1, 0, 1];       // bar space bar
const CENTER_GUARD = [0, 1, 0, 1, 0]; // space bar space bar space
const END_GUARD = [1, 0, 1];          // bar space bar

/**
 * Calculate EAN-13 check digit.
 */
function calculateCheckDigit(digits12: number[]): number {
  let sum = 0;
  for (let i = 0; i < 12; i++) {
    sum += digits12[i] * (i % 2 === 0 ? 1 : 3);
  }
  return (10 - (sum % 10)) % 10;
}

/**
 * Encode data as EAN-13 barcode.
 * Data should be 12 or 13 digits. If 12, the check digit is calculated.
 * If 13, the check digit is verified.
 * Returns boolean array: true = bar (dark module), false = space (light module).
 */
export function encodeEAN13(data: string): boolean[] {
  // Validate input
  const cleaned = data.replace(/\s/g, '');
  if (!/^\d{12,13}$/.test(cleaned)) {
    throw new Error('EAN-13: data must be 12 or 13 digits');
  }

  const digits = cleaned.split('').map(Number);

  // Calculate or verify check digit
  if (digits.length === 12) {
    digits.push(calculateCheckDigit(digits));
  } else {
    const expected = calculateCheckDigit(digits.slice(0, 12));
    if (digits[12] !== expected) {
      throw new Error(`EAN-13: invalid check digit. Expected ${expected}, got ${digits[12]}`);
    }
  }

  const firstDigit = digits[0];
  const parityPattern = PARITY_PATTERNS[firstDigit];

  const result: boolean[] = [];

  // Start guard
  for (const bit of START_GUARD) {
    result.push(bit === 1);
  }

  // First group: digits 1-6 (indices 1-6)
  // Encoding determined by first digit via parity pattern
  for (let i = 0; i < 6; i++) {
    const digit = digits[i + 1];
    const encoding = parityPattern[i] === 0 ? L_CODES[digit] : G_CODES[digit];
    for (const bit of encoding) {
      result.push(bit === 1);
    }
  }

  // Center guard
  for (const bit of CENTER_GUARD) {
    result.push(bit === 1);
  }

  // Second group: digits 7-12 (indices 7-12), all R encoding
  for (let i = 0; i < 6; i++) {
    const digit = digits[i + 7];
    const encoding = R_CODES[digit];
    for (const bit of encoding) {
      result.push(bit === 1);
    }
  }

  // End guard
  for (const bit of END_GUARD) {
    result.push(bit === 1);
  }

  return result;
}

/**
 * Encode data and render as PDF drawing operators.
 */
export function renderEAN13(
  data: string,
  x: number,
  y: number,
  width: number,
  height: number,
  color?: Color,
): string {
  const bits = encodeEAN13(data);
  const totalModules = bits.length; // 95 modules
  const moduleWidth = width / totalModules;

  const bars: Bar[] = [];
  for (let i = 0; i < bits.length; i++) {
    if (bits[i]) {
      // Guard bars are taller
      const isGuard = i < 3 || (i >= 45 && i < 50) || i >= 92;
      bars.push({
        x: i * moduleWidth,
        width: moduleWidth,
        height: isGuard ? height * 1.05 : height,
      });
    }
  }

  return renderBars(bars, x, y, height, color);
}
