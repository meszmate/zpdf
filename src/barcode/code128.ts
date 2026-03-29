import type { Color } from '../color/color.js';
import { renderBars, type Bar } from './barcode-renderer.js';

/**
 * Code 128 barcode patterns.
 * Each entry is a 6-element array of bar/space widths (bar, space, bar, space, bar, space).
 * Index is the symbol value (0-106).
 */
const PATTERNS: number[][] = [
  [2,1,2,2,2,2],[2,2,2,1,2,2],[2,2,2,2,2,1],[1,2,1,2,2,3],[1,2,1,3,2,2],
  [1,3,1,2,2,2],[1,2,2,2,1,3],[1,2,2,3,1,2],[1,3,2,2,1,2],[2,2,1,2,1,3],
  [2,2,1,3,1,2],[2,3,1,2,1,2],[1,1,2,2,3,2],[1,2,2,1,3,2],[1,2,2,2,3,1],
  [1,1,3,2,2,2],[1,2,3,1,2,2],[1,2,3,2,2,1],[2,2,3,2,1,1],[2,2,1,1,3,2],
  [2,2,1,2,3,1],[2,1,3,2,1,2],[2,2,3,1,1,2],[3,1,2,1,3,1],[3,1,1,2,2,2],
  [3,2,1,1,2,2],[3,2,1,2,2,1],[3,1,2,2,1,2],[3,2,2,1,1,2],[3,2,2,2,1,1],
  [2,1,2,1,2,3],[2,1,2,3,2,1],[2,3,2,1,2,1],[1,1,1,3,2,3],[1,3,1,1,2,3],
  [1,3,1,3,2,1],[1,1,2,3,1,3],[1,3,2,1,1,3],[1,3,2,3,1,1],[2,1,1,3,1,3],
  [2,3,1,1,1,3],[2,3,1,3,1,1],[1,1,2,1,3,3],[1,1,2,3,3,1],[1,3,2,1,3,1],
  [1,1,3,1,2,3],[1,1,3,3,2,1],[1,3,3,1,2,1],[3,1,3,1,2,1],[2,1,1,3,3,1],
  [2,3,1,1,3,1],[2,1,3,1,1,3],[2,1,3,3,1,1],[2,1,3,1,3,1],[3,1,1,1,2,3],
  [3,1,1,3,2,1],[3,3,1,1,2,1],[3,1,2,1,1,3],[3,1,2,3,1,1],[3,3,2,1,1,1],
  [3,1,4,1,1,1],[2,2,1,4,1,1],[4,3,1,1,1,1],[1,1,1,2,2,4],[1,1,1,4,2,2],
  [1,2,1,1,2,4],[1,2,1,4,2,1],[1,4,1,1,2,2],[1,4,1,2,2,1],[1,1,2,2,1,4],
  [1,1,2,4,1,2],[1,2,2,1,1,4],[1,2,2,4,1,1],[1,4,2,1,1,2],[1,4,2,2,1,1],
  [2,4,1,2,1,1],[2,2,1,1,1,4],[4,1,3,1,1,1],[2,4,1,1,1,2],[1,3,4,1,1,1],
  [1,1,1,2,4,2],[1,2,1,1,4,2],[1,2,1,2,4,1],[1,1,4,2,1,2],[1,2,4,1,1,2],
  [1,2,4,2,1,1],[4,1,1,2,1,2],[4,2,1,1,1,2],[4,2,1,2,1,1],[2,1,2,1,4,1],
  [2,1,4,1,2,1],[4,1,2,1,2,1],[1,1,1,1,4,3],[1,1,1,3,4,1],[1,3,1,1,4,1],
  [1,1,4,1,1,3],[1,1,4,3,1,1],[4,1,1,1,1,3],[4,1,1,3,1,1],[1,1,3,1,4,1],
  [1,1,4,1,3,1],[3,1,1,1,4,1],[4,1,1,1,3,1],[2,1,1,4,1,2],[2,1,1,2,1,4],
  [2,1,1,2,3,2],[2,3,3,1,1,1,2],
];

// Stop pattern (index 106) is 7 elements: 2,3,3,1,1,1,2
const STOP_PATTERN = [2,3,3,1,1,1,2];

// Code set values
const START_A = 103;
const START_B = 104;
const START_C = 105;
const CODE_A = 101;
const CODE_B = 100;
const CODE_C = 99;
const FNC1 = 102;

/**
 * Encode data as Code 128 barcode.
 * Auto-selects between Code A, B, and C for optimal encoding.
 * Code C is used for even-length sequences of digits.
 * Returns array of booleans (true = bar/dark, false = space/light).
 */
export function encodeCode128(data: string): boolean[] {
  if (data.length === 0) {
    throw new Error('Code 128: data cannot be empty');
  }

  const symbols = selectSymbols(data);
  return symbolsToBooleans(symbols);
}

/**
 * Select the optimal sequence of Code 128 symbols for the given data.
 */
function selectSymbols(data: string): number[] {
  const symbols: number[] = [];
  let pos = 0;
  let currentSet: 'A' | 'B' | 'C' | null = null;

  while (pos < data.length) {
    // Count consecutive digits from current position
    let digitCount = 0;
    while (pos + digitCount < data.length && isDigit(data[pos + digitCount])) {
      digitCount++;
    }

    // Use Code C for sequences of 4+ digits (or 2+ at start)
    if (digitCount >= 4 || (digitCount >= 2 && (currentSet === null || currentSet === 'C'))) {
      // Ensure even number of digits for Code C
      const useDigits = digitCount % 2 === 0 ? digitCount : digitCount - 1;

      if (useDigits >= 2) {
        if (currentSet === null) {
          symbols.push(START_C);
          currentSet = 'C';
        } else if (currentSet !== 'C') {
          symbols.push(CODE_C);
          currentSet = 'C';
        }

        for (let i = 0; i < useDigits; i += 2) {
          const val = parseInt(data[pos + i] + data[pos + i + 1], 10);
          symbols.push(val);
        }
        pos += useDigits;
        continue;
      }
    }

    // Determine if we need Code A or Code B
    const ch = data.charCodeAt(pos);

    if (ch < 32) {
      // Control character: needs Code A
      if (currentSet === null) {
        symbols.push(START_A);
        currentSet = 'A';
      } else if (currentSet !== 'A') {
        symbols.push(CODE_A);
        currentSet = 'A';
      }
      symbols.push(ch + 64); // Code A: control chars are 64-95
    } else if (ch >= 96) {
      // Lowercase: needs Code B
      if (currentSet === null) {
        symbols.push(START_B);
        currentSet = 'B';
      } else if (currentSet !== 'B') {
        symbols.push(CODE_B);
        currentSet = 'B';
      }
      symbols.push(ch - 32); // Code B: chars 32-127 map to values 0-95
    } else {
      // Printable ASCII 32-95: works in both A and B
      if (currentSet === null) {
        symbols.push(START_B);
        currentSet = 'B';
      } else if (currentSet === 'C') {
        symbols.push(CODE_B);
        currentSet = 'B';
      }

      if (currentSet === 'A') {
        symbols.push(ch - 32); // Code A: chars 32-95 map to values 0-63
      } else {
        symbols.push(ch - 32); // Code B: chars 32-127 map to values 0-95
      }
    }
    pos++;
  }

  // If no data was processed (shouldn't happen), default to Code B
  if (symbols.length === 0) {
    symbols.push(START_B);
  }

  // Calculate checksum
  let checksum = symbols[0]; // start code value
  for (let i = 1; i < symbols.length; i++) {
    checksum += symbols[i] * i;
  }
  checksum = checksum % 103;
  symbols.push(checksum);

  // Add stop
  symbols.push(106); // stop symbol

  return symbols;
}

function isDigit(ch: string): boolean {
  return ch >= '0' && ch <= '9';
}

/**
 * Convert symbol values to boolean array of bars and spaces.
 */
function symbolsToBooleans(symbols: number[]): boolean[] {
  const result: boolean[] = [];

  for (let s = 0; s < symbols.length; s++) {
    const sym = symbols[s];
    const pattern = sym === 106 ? STOP_PATTERN : PATTERNS[sym];

    for (let i = 0; i < pattern.length; i++) {
      const width = pattern[i];
      const isBar = i % 2 === 0; // even indices are bars, odd are spaces
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
export function renderCode128(
  data: string,
  x: number,
  y: number,
  width: number,
  height: number,
  color?: Color,
): string {
  const bits = encodeCode128(data);
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
