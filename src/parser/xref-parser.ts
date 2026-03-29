/**
 * Parse cross-reference tables and cross-reference streams.
 */

import type { PdfStream } from '../core/types.js';
import { dictGetNumber, dictGetArray } from '../core/objects.js';

export interface XrefEntry {
  objectNumber: number;
  offset: number;
  generation: number;
  free: boolean;
  compressed?: boolean;
  streamObjectNumber?: number;
  indexInStream?: number;
}

/**
 * Parse a traditional cross-reference table starting at `position`.
 * Returns the parsed entries and the byte position right after the table
 * (where the trailer dictionary begins).
 */
export function parseXrefTable(data: Uint8Array, position: number): { entries: XrefEntry[]; trailerPosition: number } {
  const entries: XrefEntry[] = [];
  let pos = position;

  // Skip "xref" keyword and the following EOL
  pos = skipKeyword(data, pos, 'xref');
  pos = skipEOL(data, pos);

  // Parse subsections: each starts with "startObj count"
  while (pos < data.length) {
    // Skip whitespace
    pos = skipWhitespace(data, pos);

    // Check if we've reached the "trailer" keyword
    if (matchKeyword(data, pos, 'trailer')) {
      break;
    }

    // Read startObj and count from the line
    const line1 = readLine(data, pos);
    pos = line1.nextPos;

    const parts = line1.text.trim().split(/\s+/);
    if (parts.length < 2) break;

    const startObj = parseInt(parts[0], 10);
    const count = parseInt(parts[1], 10);

    if (isNaN(startObj) || isNaN(count)) break;

    // Read `count` entries, each exactly 20 bytes (including the trailing EOL)
    for (let i = 0; i < count; i++) {
      if (pos + 20 > data.length) break;

      // Read the 20-byte entry
      // Format: "OOOOOOOOOO GGGGG n \n" or "OOOOOOOOOO GGGGG f \n"
      // The entry may have \r\n or \r or \n at the end (always 20 bytes total)
      let entryStr = '';
      for (let j = 0; j < 20; j++) {
        entryStr += String.fromCharCode(data[pos + j]);
      }
      pos += 20;

      const offsetStr = entryStr.substring(0, 10).trim();
      const genStr = entryStr.substring(11, 16).trim();
      const flag = entryStr.charAt(17);

      const offset = parseInt(offsetStr, 10);
      const generation = parseInt(genStr, 10);
      const free = flag === 'f';

      if (!isNaN(offset) && !isNaN(generation)) {
        entries.push({
          objectNumber: startObj + i,
          offset,
          generation,
          free,
        });
      }
    }
  }

  // Find the trailer position (skip whitespace to "trailer")
  pos = skipWhitespace(data, pos);
  return { entries, trailerPosition: pos };
}

/**
 * Parse a cross-reference stream (PDF 1.5+).
 * The stream object's dictionary contains /Type /XRef, /W, optional /Index, /Size.
 */
export function parseXrefStream(stream: PdfStream, streamObjNum: number): XrefEntry[] {
  const entries: XrefEntry[] = [];

  // /W [w1 w2 w3] - field widths
  const wArr = dictGetArray(stream, 'W');
  if (!wArr || wArr.length < 3) {
    throw new Error('XRef stream missing /W array');
  }

  const w1 = wArr[0].type === 'number' ? wArr[0].value : 0;
  const w2 = wArr[1].type === 'number' ? wArr[1].value : 0;
  const w3 = wArr[2].type === 'number' ? wArr[2].value : 0;
  const entrySize = w1 + w2 + w3;

  // /Size
  const size = dictGetNumber(stream, 'Size') ?? 0;

  // /Index [start count ...] - subsection ranges (default [0 size])
  const indexArr = dictGetArray(stream, 'Index');
  const subsections: { start: number; count: number }[] = [];

  if (indexArr && indexArr.length >= 2) {
    for (let i = 0; i < indexArr.length; i += 2) {
      const startItem = indexArr[i];
      const countItem = indexArr[i + 1];
      const start = startItem.type === 'number' ? (startItem as import('../core/types.js').PdfNumber).value : 0;
      const count = countItem.type === 'number' ? (countItem as import('../core/types.js').PdfNumber).value : 0;
      subsections.push({ start, count });
    }
  } else {
    subsections.push({ start: 0, count: size });
  }

  const data = stream.data;
  let offset = 0;

  for (const sub of subsections) {
    for (let i = 0; i < sub.count; i++) {
      if (offset + entrySize > data.length) break;

      // Read field values
      const field1 = readField(data, offset, w1);
      offset += w1;
      const field2 = readField(data, offset, w2);
      offset += w2;
      const field3 = readField(data, offset, w3);
      offset += w3;

      const objectNumber = sub.start + i;

      // If w1 is 0, default type is 1 (in-use)
      const type = w1 === 0 ? 1 : field1;

      if (type === 0) {
        // Free object
        entries.push({
          objectNumber,
          offset: field2,    // next free object number
          generation: field3, // generation if reused
          free: true,
        });
      } else if (type === 1) {
        // In-use, uncompressed
        entries.push({
          objectNumber,
          offset: field2,     // byte offset in file
          generation: field3, // generation number
          free: false,
        });
      } else if (type === 2) {
        // Compressed in object stream
        entries.push({
          objectNumber,
          offset: 0,
          generation: 0,
          free: false,
          compressed: true,
          streamObjectNumber: field2, // object number of the object stream
          indexInStream: field3,       // index within the object stream
        });
      }
    }
  }

  return entries;
}

// ---------- Helpers ----------

function readField(data: Uint8Array, offset: number, width: number): number {
  if (width === 0) return 0;
  let value = 0;
  for (let i = 0; i < width; i++) {
    value = value * 256 + (offset + i < data.length ? data[offset + i] : 0);
  }
  return value;
}

function skipWhitespace(data: Uint8Array, pos: number): number {
  while (pos < data.length) {
    const b = data[pos];
    if (b === 0x20 || b === 0x09 || b === 0x0a || b === 0x0d || b === 0x0c || b === 0x00) {
      pos++;
    } else {
      break;
    }
  }
  return pos;
}

function skipEOL(data: Uint8Array, pos: number): number {
  // Skip whitespace including EOL
  while (pos < data.length) {
    const b = data[pos];
    if (b === 0x20 || b === 0x09 || b === 0x0a || b === 0x0d || b === 0x0c) {
      pos++;
    } else {
      break;
    }
  }
  return pos;
}

function skipKeyword(data: Uint8Array, pos: number, keyword: string): number {
  // Skip whitespace first
  pos = skipWhitespace(data, pos);
  for (let i = 0; i < keyword.length; i++) {
    if (pos < data.length && data[pos] === keyword.charCodeAt(i)) {
      pos++;
    }
  }
  return pos;
}

function matchKeyword(data: Uint8Array, pos: number, keyword: string): boolean {
  for (let i = 0; i < keyword.length; i++) {
    if (pos + i >= data.length || data[pos + i] !== keyword.charCodeAt(i)) {
      return false;
    }
  }
  return true;
}

function readLine(data: Uint8Array, pos: number): { text: string; nextPos: number } {
  let text = '';
  while (pos < data.length) {
    const b = data[pos];
    if (b === 0x0a) {
      pos++;
      break;
    }
    if (b === 0x0d) {
      pos++;
      if (pos < data.length && data[pos] === 0x0a) pos++;
      break;
    }
    text += String.fromCharCode(b);
    pos++;
  }
  return { text, nextPos: pos };
}
