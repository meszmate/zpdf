/**
 * Attempt to repair broken PDFs by scanning for object definitions.
 * Used as a fallback when normal xref parsing fails.
 */

import type { XrefEntry } from './xref-parser.js';

/**
 * Scan the entire file for "N G obj" patterns and build an xref table.
 * This brute-force approach is used when the cross-reference table is
 * corrupt or missing.
 */
export function repairXref(data: Uint8Array): XrefEntry[] {
  const entries: XrefEntry[] = [];
  const seen = new Map<number, XrefEntry>();

  let pos = 0;
  const len = data.length;

  while (pos < len) {
    // Skip to a position that could be the start of an object definition
    // Look for a digit at the start of a line (or start of file)
    if (pos > 0 && !isLineStart(data, pos)) {
      pos = findNextLineStart(data, pos);
      if (pos >= len) break;
    }

    // Try to read "N G obj" pattern starting at this position
    const result = tryParseObjHeader(data, pos);
    if (result) {
      const { objNum, genNum, objStart } = result;

      // Only keep the latest occurrence of each object number
      // (handles incremental updates where objects are redefined)
      const existing = seen.get(objNum);
      if (!existing || existing.offset < objStart) {
        const entry: XrefEntry = {
          objectNumber: objNum,
          offset: objStart,
          generation: genNum,
          free: false,
        };
        seen.set(objNum, entry);
      }

      // Skip past "obj" to avoid re-matching
      pos = result.afterObjKeyword;
      continue;
    }

    pos++;
  }

  // Convert to sorted array
  for (const entry of seen.values()) {
    entries.push(entry);
  }
  entries.sort((a, b) => a.objectNumber - b.objectNumber);

  return entries;
}

/**
 * Check if position is at the start of a line.
 */
function isLineStart(data: Uint8Array, pos: number): boolean {
  if (pos === 0) return true;
  const prev = data[pos - 1];
  return prev === 0x0a || prev === 0x0d;
}

/**
 * Find the start of the next line from the given position.
 */
function findNextLineStart(data: Uint8Array, pos: number): number {
  // Scan forward until we find a line ending
  while (pos < data.length) {
    const b = data[pos];
    if (b === 0x0a) {
      return pos + 1;
    }
    if (b === 0x0d) {
      pos++;
      if (pos < data.length && data[pos] === 0x0a) {
        pos++;
      }
      return pos;
    }
    pos++;
  }
  return pos;
}

/**
 * Try to parse an "N G obj" header starting at the given position.
 * Returns null if the pattern doesn't match.
 */
function tryParseObjHeader(
  data: Uint8Array,
  pos: number,
): { objNum: number; genNum: number; objStart: number; afterObjKeyword: number } | null {
  const start = pos;

  // Read first number (object number)
  if (pos >= data.length || !isDigit(data[pos])) return null;

  let numStr = '';
  while (pos < data.length && isDigit(data[pos])) {
    numStr += String.fromCharCode(data[pos]);
    pos++;
  }
  const objNum = parseInt(numStr, 10);
  if (isNaN(objNum) || objNum < 0) return null;

  // Must be followed by whitespace
  if (pos >= data.length || !isWhitespace(data[pos])) return null;
  while (pos < data.length && isWhitespace(data[pos])) pos++;

  // Read second number (generation number)
  if (pos >= data.length || !isDigit(data[pos])) return null;

  let genStr = '';
  while (pos < data.length && isDigit(data[pos])) {
    genStr += String.fromCharCode(data[pos]);
    pos++;
  }
  const genNum = parseInt(genStr, 10);
  if (isNaN(genNum) || genNum < 0) return null;

  // Must be followed by whitespace
  if (pos >= data.length || !isWhitespace(data[pos])) return null;
  while (pos < data.length && isWhitespace(data[pos])) pos++;

  // Must be followed by "obj" keyword
  if (pos + 3 > data.length) return null;
  if (data[pos] !== 0x6f || data[pos + 1] !== 0x62 || data[pos + 2] !== 0x6a) return null; // "obj"

  // "obj" must be followed by whitespace, delimiter, or EOF
  const afterObj = pos + 3;
  if (afterObj < data.length) {
    const nextByte = data[afterObj];
    if (!isWhitespace(nextByte) && !isDelimiter(nextByte)) return null;
  }

  return {
    objNum,
    genNum,
    objStart: start,
    afterObjKeyword: afterObj,
  };
}

function isDigit(b: number): boolean {
  return b >= 0x30 && b <= 0x39;
}

function isWhitespace(b: number): boolean {
  return b === 0x00 || b === 0x09 || b === 0x0a || b === 0x0c || b === 0x0d || b === 0x20;
}

function isDelimiter(b: number): boolean {
  return (
    b === 0x28 || b === 0x29 || // ( )
    b === 0x3c || b === 0x3e || // < >
    b === 0x5b || b === 0x5d || // [ ]
    b === 0x7b || b === 0x7d || // { }
    b === 0x2f || b === 0x25    // / %
  );
}
