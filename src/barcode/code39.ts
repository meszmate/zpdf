import type { Color } from '../color/color.js';
import { renderBars, type Bar } from './barcode-renderer.js';

/**
 * Code 39 character encoding patterns.
 * Each character is encoded as 9 elements: 5 bars and 4 spaces.
 * 'n' = narrow, 'w' = wide. Pattern is: B S B S B S B S B
 * Characters: 0-9, A-Z, -, ., space, $, /, +, %, *
 */
const CHAR_PATTERNS: Record<string, string> = {
  '0': 'nnnwwnwnn',
  '1': 'wnnwnnnnw',
  '2': 'nnwwnnnnw',
  '3': 'wnwwnnnn' + 'n', // wnwwnnnnn
  '4': 'nnnwwnnnw',  // 'nnnwwnnnw' is incorrect, re-check
  '5': 'wnnwwnnnn',
  '6': 'nnwwwnnnn',
  '7': 'nnnwnnwnw',
  '8': 'wnnwnnwnn',
  '9': 'nnwwnnwnn',
  'A': 'wnnnnwnnw',
  'B': 'nnwnnwnnw',
  'C': 'wnwnnwnnn',
  'D': 'nnnnwwnnw',
  'E': 'wnnnwwnnn',
  'F': 'nnwnwwnnn',
  'G': 'nnnnnwwnw',
  'H': 'wnnnnwwnn',
  'I': 'nnwnnwwnn',
  'J': 'nnnnwwwnn',
  'K': 'wnnnnnnww',
  'L': 'nnwnnnnww',
  'M': 'wnwnnnnwn',
  'N': 'nnnnwnnww',
  'O': 'wnnnwnnwn',
  'P': 'nnwnwnnwn',
  'Q': 'nnnnnnwww',
  'R': 'wnnnnnwwn',
  'S': 'nnwnnnwwn',
  'T': 'nnnnwnwwn',
  'U': 'wwnnnnnnw',
  'V': 'nwwnnnnnw',
  'W': 'wwwnnnnnn',
  'X': 'nwnnwnnnw',
  'Y': 'wwnnwnnnn',
  'Z': 'nwwnwnnnn',
  '-': 'nwnnnnwnw',
  '.': 'wwnnnnwnn',
  ' ': 'nwwnnnwnn',
  '$': 'nwnwnwnnn',
  '/': 'nwnwnnnwn',
  '+': 'nwnnnwnwn',
  '%': 'nnnwnwnwn',
  '*': 'nwnnwnwnn',
};

// Corrected Code 39 patterns based on the standard
// Each character = 9 elements (BSBSBSBSB), 3 wide elements, 6 narrow
const CODE39_PATTERNS: Record<string, number[]> = {};

function initPatterns(): void {
  // Standard Code 39 encoding
  // Format: array of 9 widths (bar, space, bar, space, bar, space, bar, space, bar)
  // 1 = narrow, 2 = wide
  const defs: [string, number[]][] = [
    ['0', [1,1,1,2,2,1,2,1,1]],
    ['1', [2,1,1,2,1,1,1,1,2]],
    ['2', [1,1,2,2,1,1,1,1,2]],
    ['3', [2,1,2,2,1,1,1,1,1]],
    ['4', [1,1,1,2,2,1,1,1,2]],
    ['5', [2,1,1,2,2,1,1,1,1]],
    ['6', [1,1,2,2,2,1,1,1,1]],
    ['7', [1,1,1,2,1,1,2,1,2]],
    ['8', [2,1,1,2,1,1,2,1,1]],
    ['9', [1,1,2,2,1,1,2,1,1]],
    ['A', [2,1,1,1,1,2,1,1,2]],
    ['B', [1,1,2,1,1,2,1,1,2]],
    ['C', [2,1,2,1,1,2,1,1,1]],
    ['D', [1,1,1,1,2,2,1,1,2]],
    ['E', [2,1,1,1,2,2,1,1,1]],
    ['F', [1,1,2,1,2,2,1,1,1]],
    ['G', [1,1,1,1,1,2,2,1,2]],
    ['H', [2,1,1,1,1,2,2,1,1]],
    ['I', [1,1,2,1,1,2,2,1,1]],
    ['J', [1,1,1,1,2,2,2,1,1]],
    ['K', [2,1,1,1,1,1,1,2,2]],
    ['L', [1,1,2,1,1,1,1,2,2]],
    ['M', [2,1,2,1,1,1,1,2,1]],
    ['N', [1,1,1,1,2,1,1,2,2]],
    ['O', [2,1,1,1,2,1,1,2,1]],
    ['P', [1,1,2,1,2,1,1,2,1]],
    ['Q', [1,1,1,1,1,1,2,2,2]],
    ['R', [2,1,1,1,1,1,2,2,1]],
    ['S', [1,1,2,1,1,1,2,2,1]],
    ['T', [1,1,1,1,2,1,2,2,1]],
    ['U', [2,2,1,1,1,1,1,1,2]],
    ['V', [1,2,2,1,1,1,1,1,2]],
    ['W', [2,2,2,1,1,1,1,1,1]],
    ['X', [1,2,1,1,2,1,1,1,2]],
    ['Y', [2,2,1,1,2,1,1,1,1]],
    ['Z', [1,2,2,1,2,1,1,1,1]],
    ['-', [1,2,1,1,1,1,2,1,2]],
    ['.', [2,2,1,1,1,1,2,1,1]],
    [' ', [1,2,2,1,1,1,2,1,1]],
    ['$', [1,2,1,2,1,2,1,1,1]],
    ['/', [1,2,1,2,1,1,1,2,1]],
    ['+', [1,2,1,1,1,2,1,2,1]],
    ['%', [1,1,1,2,1,2,1,2,1]],
    ['*', [1,2,1,1,2,1,2,1,1]],
  ];

  for (const [ch, pattern] of defs) {
    CODE39_PATTERNS[ch] = pattern;
  }
}

initPatterns();

/**
 * Encode data as Code 39 barcode.
 * Automatically wraps data in start/stop '*' characters.
 * Returns boolean array: true = bar (dark module), false = space (light module).
 */
export function encodeCode39(data: string): boolean[] {
  const upper = data.toUpperCase();

  // Validate characters
  for (const ch of upper) {
    if (!CODE39_PATTERNS[ch]) {
      throw new Error(`Code 39: invalid character '${ch}'`);
    }
  }

  // Full string with start/stop
  const fullData = '*' + upper + '*';
  const result: boolean[] = [];

  for (let c = 0; c < fullData.length; c++) {
    if (c > 0) {
      // Inter-character gap (narrow space)
      result.push(false);
    }

    const pattern = CODE39_PATTERNS[fullData[c]];
    for (let i = 0; i < pattern.length; i++) {
      const width = pattern[i];
      const isBar = i % 2 === 0; // Even indices are bars, odd are spaces
      for (let w = 0; w < width; w++) {
        result.push(isBar);
      }
    }
  }

  return result;
}

/**
 * Encode data and render as PDF drawing operators.
 */
export function renderCode39(
  data: string,
  x: number,
  y: number,
  width: number,
  height: number,
  color?: Color,
): string {
  const bits = encodeCode39(data);
  const totalModules = bits.length;
  const moduleWidth = width / totalModules;

  const bars: Bar[] = [];
  for (let i = 0; i < bits.length; i++) {
    if (bits[i]) {
      bars.push({
        x: i * moduleWidth,
        width: moduleWidth,
        height,
      });
    }
  }

  return renderBars(bars, x, y, height, color);
}
