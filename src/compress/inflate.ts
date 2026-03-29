/**
 * Inflate (decompress) with node:zlib and pure TS fallback.
 * Pure TS supports stored blocks (type 0), fixed Huffman (type 1),
 * and dynamic Huffman (type 2).
 */

import { adler32 } from './deflate.js';

// ---------------------------------------------------------------------------
// Huffman tree
// ---------------------------------------------------------------------------

interface HuffmanTable {
  /** symbol for each index */
  symbols: Int32Array;
  /** counts per bit length */
  counts: Int32Array;
  /** max bits */
  maxBits: number;
}

function buildHuffmanTable(codeLengths: Uint8Array, maxSymbol: number): HuffmanTable {
  let maxBits = 0;
  for (let i = 0; i < maxSymbol; i++) {
    if (codeLengths[i] > maxBits) maxBits = codeLengths[i];
  }
  if (maxBits === 0) maxBits = 1;

  const counts = new Int32Array(maxBits + 1);
  for (let i = 0; i < maxSymbol; i++) {
    if (codeLengths[i] > 0) counts[codeLengths[i]]++;
  }

  // Compute first code for each length
  const offsets = new Int32Array(maxBits + 1);
  let code = 0;
  counts[0] = 0;
  for (let bits = 1; bits <= maxBits; bits++) {
    code = (code + counts[bits - 1]) << 1;
    offsets[bits] = code;
  }

  const tableSize = 1 << maxBits;
  const symbols = new Int32Array(tableSize).fill(-1);

  for (let sym = 0; sym < maxSymbol; sym++) {
    const len = codeLengths[sym];
    if (len === 0) continue;
    const c = offsets[len]++;
    // Fill all entries for this code (with padding)
    const shift = maxBits - len;
    const start = c << shift;
    const end = start + (1 << shift);
    for (let j = start; j < end; j++) {
      // reverse bits for lookup
      let reversed = 0;
      let v = j;
      for (let b = 0; b < maxBits; b++) {
        reversed = (reversed << 1) | (v & 1);
        v >>= 1;
      }
      symbols[reversed] = sym | (len << 24);
    }
  }

  return { symbols, counts, maxBits };
}

function decodeSymbol(table: HuffmanTable, bits: BitReader): number {
  const peekBits = bits.peek(table.maxBits);
  const entry = table.symbols[peekBits];
  if (entry === -1) {
    throw new Error('Invalid Huffman code');
  }
  const sym = entry & 0xffffff;
  const len = entry >>> 24;
  bits.advance(len);
  return sym;
}

// ---------------------------------------------------------------------------
// Bit reader (LSB first, as deflate uses)
// ---------------------------------------------------------------------------

class BitReader {
  private data: Uint8Array;
  private bytePos: number;
  private bitBuf: number;
  private bitCount: number;

  constructor(data: Uint8Array, startByte: number) {
    this.data = data;
    this.bytePos = startByte;
    this.bitBuf = 0;
    this.bitCount = 0;
  }

  private fill(): void {
    while (this.bitCount <= 24 && this.bytePos < this.data.length) {
      this.bitBuf |= this.data[this.bytePos++] << this.bitCount;
      this.bitCount += 8;
    }
  }

  peek(n: number): number {
    this.fill();
    return this.bitBuf & ((1 << n) - 1);
  }

  advance(n: number): void {
    this.bitBuf >>>= n;
    this.bitCount -= n;
  }

  readBits(n: number): number {
    this.fill();
    const val = this.bitBuf & ((1 << n) - 1);
    this.bitBuf >>>= n;
    this.bitCount -= n;
    return val;
  }

  /** Align to next byte boundary */
  alignToByte(): void {
    const skip = this.bitCount & 7;
    if (skip > 0) {
      this.bitBuf >>>= skip;
      this.bitCount -= skip;
    }
  }

  readByte(): number {
    this.alignToByte();
    if (this.bitCount >= 8) {
      const v = this.bitBuf & 0xff;
      this.bitBuf >>>= 8;
      this.bitCount -= 8;
      return v;
    }
    return this.data[this.bytePos++];
  }

  readUint16LE(): number {
    const lo = this.readByte();
    const hi = this.readByte();
    return lo | (hi << 8);
  }

  getBytePos(): number {
    // Effective byte position accounting for buffered bits
    return this.bytePos - (this.bitCount >> 3);
  }
}

// ---------------------------------------------------------------------------
// Fixed Huffman tables (computed once)
// ---------------------------------------------------------------------------

let fixedLitTable: HuffmanTable | null = null;
let fixedDistTable: HuffmanTable | null = null;

function getFixedLitTable(): HuffmanTable {
  if (fixedLitTable) return fixedLitTable;
  const lengths = new Uint8Array(288);
  let i = 0;
  for (; i <= 143; i++) lengths[i] = 8;
  for (; i <= 255; i++) lengths[i] = 9;
  for (; i <= 279; i++) lengths[i] = 7;
  for (; i <= 287; i++) lengths[i] = 8;
  fixedLitTable = buildHuffmanTable(lengths, 288);
  return fixedLitTable;
}

function getFixedDistTable(): HuffmanTable {
  if (fixedDistTable) return fixedDistTable;
  const lengths = new Uint8Array(32);
  for (let i = 0; i < 32; i++) lengths[i] = 5;
  fixedDistTable = buildHuffmanTable(lengths, 32);
  return fixedDistTable;
}

// ---------------------------------------------------------------------------
// Length / distance extra bits tables
// ---------------------------------------------------------------------------

const LENGTH_BASE = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
  35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
];
const LENGTH_EXTRA = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
  3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
];
const DIST_BASE = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
  257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
  8193, 12289, 16385, 24577,
];
const DIST_EXTRA = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
  7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
];

// Code length alphabet order
const CL_ORDER = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];

// ---------------------------------------------------------------------------
// Core inflate (pure TS)
// ---------------------------------------------------------------------------

function inflatePure(data: Uint8Array): Uint8Array {
  // Detect and skip zlib header
  let startByte = 0;
  let hasZlibHeader = false;
  if (data.length >= 2) {
    const cmf = data[0];
    const flg = data[1];
    const cm = cmf & 0x0f;
    if (cm === 8 && ((cmf * 256 + flg) % 31 === 0)) {
      hasZlibHeader = true;
      startByte = 2;
      // Check for FDICT
      if (flg & 0x20) {
        startByte = 6; // skip 4-byte dict id
      }
    }
  }

  const bits = new BitReader(data, startByte);
  // Use a growing output buffer
  let output = new Uint8Array(data.length * 4 || 1024);
  let outPos = 0;

  function ensureCapacity(needed: number): void {
    if (outPos + needed > output.length) {
      let newLen = output.length * 2;
      while (newLen < outPos + needed) newLen *= 2;
      const newBuf = new Uint8Array(newLen);
      newBuf.set(output);
      output = newBuf;
    }
  }

  let bfinal = 0;
  do {
    bfinal = bits.readBits(1);
    const btype = bits.readBits(2);

    if (btype === 0) {
      // Stored block
      bits.alignToByte();
      const len = bits.readUint16LE();
      bits.readUint16LE(); // nlen (skip)
      ensureCapacity(len);
      for (let i = 0; i < len; i++) {
        output[outPos++] = bits.readByte();
      }
    } else if (btype === 1 || btype === 2) {
      let litTable: HuffmanTable;
      let distTable: HuffmanTable;

      if (btype === 1) {
        litTable = getFixedLitTable();
        distTable = getFixedDistTable();
      } else {
        // Dynamic Huffman
        const hlit = bits.readBits(5) + 257;
        const hdist = bits.readBits(5) + 1;
        const hclen = bits.readBits(4) + 4;

        // Read code length code lengths
        const clLengths = new Uint8Array(19);
        for (let i = 0; i < hclen; i++) {
          clLengths[CL_ORDER[i]] = bits.readBits(3);
        }
        const clTable = buildHuffmanTable(clLengths, 19);

        // Read literal/length + distance code lengths
        const totalCodes = hlit + hdist;
        const codeLengths = new Uint8Array(totalCodes);
        let idx = 0;
        while (idx < totalCodes) {
          const sym = decodeSymbol(clTable, bits);
          if (sym < 16) {
            codeLengths[idx++] = sym;
          } else if (sym === 16) {
            const repeat = bits.readBits(2) + 3;
            const prev = idx > 0 ? codeLengths[idx - 1] : 0;
            for (let r = 0; r < repeat && idx < totalCodes; r++) {
              codeLengths[idx++] = prev;
            }
          } else if (sym === 17) {
            const repeat = bits.readBits(3) + 3;
            for (let r = 0; r < repeat && idx < totalCodes; r++) {
              codeLengths[idx++] = 0;
            }
          } else if (sym === 18) {
            const repeat = bits.readBits(7) + 11;
            for (let r = 0; r < repeat && idx < totalCodes; r++) {
              codeLengths[idx++] = 0;
            }
          }
        }

        litTable = buildHuffmanTable(codeLengths.subarray(0, hlit), hlit);
        distTable = buildHuffmanTable(codeLengths.subarray(hlit, hlit + hdist), hdist);
      }

      // Decode data
      for (;;) {
        const sym = decodeSymbol(litTable, bits);
        if (sym === 256) break; // end of block
        if (sym < 256) {
          ensureCapacity(1);
          output[outPos++] = sym;
        } else {
          // Length
          const lenIdx = sym - 257;
          const length = LENGTH_BASE[lenIdx] + bits.readBits(LENGTH_EXTRA[lenIdx]);
          // Distance
          const distSym = decodeSymbol(distTable, bits);
          const distance = DIST_BASE[distSym] + bits.readBits(DIST_EXTRA[distSym]);

          ensureCapacity(length);
          for (let i = 0; i < length; i++) {
            output[outPos] = output[outPos - distance];
            outPos++;
          }
        }
      }
    } else {
      throw new Error(`Invalid deflate block type: ${btype}`);
    }
  } while (!bfinal);

  const result = output.subarray(0, outPos);

  // Verify adler32 if zlib header was present
  if (hasZlibHeader) {
    const bytePos = bits.getBytePos();
    if (bytePos + 4 <= data.length) {
      const expected =
        ((data[bytePos] << 24) |
          (data[bytePos + 1] << 16) |
          (data[bytePos + 2] << 8) |
          data[bytePos + 3]) >>> 0;
      const actual = adler32(result);
      if (expected !== actual) {
        throw new Error(
          `Adler32 checksum mismatch: expected 0x${expected.toString(16)}, got 0x${actual.toString(16)}`,
        );
      }
    }
  }

  return result;
}

/**
 * Decompress zlib/deflate data.
 * Tries node:zlib first, falls back to pure TS implementation.
 */
export async function inflate(data: Uint8Array): Promise<Uint8Array> {
  try {
    const zlib = await import('node:zlib');
    const { promisify } = await import('node:util');
    const inflateRaw = promisify(zlib.inflate);
    const result = await inflateRaw(Buffer.from(data));
    return new Uint8Array(result);
  } catch {
    return inflatePure(data);
  }
}

/**
 * Synchronous version of inflate.
 */
export function inflateSync(data: Uint8Array): Uint8Array {
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const zlib = require('node:zlib');
    const result = zlib.inflateSync(Buffer.from(data));
    return new Uint8Array(result);
  } catch {
    return inflatePure(data);
  }
}
