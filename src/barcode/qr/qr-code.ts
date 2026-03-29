/**
 * Main QR code generation.
 * Combines encoding, error correction, and matrix construction.
 */

import {
  analyzeData, encodeDataCodewords, getMinVersion, getDataCapacity,
  type QRMode, type QRErrorLevel,
} from './qr-encoder.js';
import { generateECCodewords, getECBlockInfo } from './qr-ec.js';
import { createQRMatrix } from './qr-matrix.js';

export interface QRCodeOptions {
  errorLevel?: QRErrorLevel;
  version?: number;
}

/**
 * Generate a QR code matrix from a data string.
 * Returns a 2D boolean array where true = dark module.
 *
 * @param data - The string to encode
 * @param options - Optional QR code parameters
 */
export function generateQRCode(data: string, options?: QRCodeOptions): boolean[][] {
  const ecLevel: QRErrorLevel = options?.errorLevel ?? 'M';
  const mode: QRMode = analyzeData(data);

  // Determine version
  let version: number;
  if (options?.version) {
    version = options.version;
    // Verify data fits
    const capacity = getDataCapacity(version, ecLevel);
    const testCodewords = encodeDataCodewords(data, mode, version, ecLevel);
    if (testCodewords.length > capacity) {
      throw new Error(`QR Code: data too long for version ${version} with EC level ${ecLevel}`);
    }
  } else {
    version = getMinVersion(data, mode, ecLevel);
  }

  // Encode data into codewords
  const dataCodewords = encodeDataCodewords(data, mode, version, ecLevel);

  // Get EC block configuration
  const blockInfo = getECBlockInfo(version, ecLevel);

  // Split data into blocks and generate EC codewords
  const dataBlocks: number[][] = [];
  const ecBlocks: number[][] = [];

  let dataOffset = 0;
  for (const group of blockInfo.groups) {
    for (let b = 0; b < group.count; b++) {
      const blockData = dataCodewords.slice(dataOffset, dataOffset + group.dataCodewords);
      dataOffset += group.dataCodewords;
      dataBlocks.push(blockData);
      ecBlocks.push(generateECCodewords(blockData, blockInfo.ecCodewordsPerBlock));
    }
  }

  // Interleave data codewords
  const interleavedData: number[] = [];
  const maxDataLen = Math.max(...dataBlocks.map(b => b.length));
  for (let i = 0; i < maxDataLen; i++) {
    for (const block of dataBlocks) {
      if (i < block.length) {
        interleavedData.push(block[i]);
      }
    }
  }

  // Interleave EC codewords
  const interleavedEC: number[] = [];
  const maxECLen = Math.max(...ecBlocks.map(b => b.length));
  for (let i = 0; i < maxECLen; i++) {
    for (const block of ecBlocks) {
      if (i < block.length) {
        interleavedEC.push(block[i]);
      }
    }
  }

  // Combine data + EC codewords
  const allCodewords = [...interleavedData, ...interleavedEC];

  // Convert codewords to bit array
  const dataBits: boolean[] = [];
  for (const cw of allCodewords) {
    for (let bit = 7; bit >= 0; bit--) {
      dataBits.push(((cw >> bit) & 1) === 1);
    }
  }

  // Add remainder bits (version-dependent)
  const remainderBits = getRemainderBits(version);
  for (let i = 0; i < remainderBits; i++) {
    dataBits.push(false);
  }

  // Create and return the matrix
  return createQRMatrix(version, dataBits, ecLevel);
}

/**
 * Number of remainder bits needed for each version.
 */
function getRemainderBits(version: number): number {
  if (version <= 1) return 0;
  if (version <= 6) return 7;
  if (version <= 13) return 0;
  if (version <= 20) return 3;
  if (version <= 27) return 4;
  if (version <= 34) return 3;
  return 0;
}
