/**
 * QR Code data encoding.
 * Supports numeric, alphanumeric, and byte modes.
 */

export type QRMode = 'numeric' | 'alphanumeric' | 'byte' | 'kanji';
export type QRErrorLevel = 'L' | 'M' | 'Q' | 'H';

const ALPHANUMERIC_CHARS = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';

/**
 * Determine the best encoding mode for the given data.
 */
export function analyzeData(data: string): QRMode {
  if (/^\d+$/.test(data)) return 'numeric';
  let allAlpha = true;
  for (let i = 0; i < data.length; i++) {
    if (ALPHANUMERIC_CHARS.indexOf(data[i]) === -1) {
      allAlpha = false;
      break;
    }
  }
  if (allAlpha) return 'alphanumeric';
  return 'byte';
}

/**
 * Mode indicators (4 bits each).
 */
const MODE_INDICATORS: Record<QRMode, boolean[]> = {
  numeric:      [false, false, false, true],
  alphanumeric: [false, false, true, false],
  byte:         [false, true, false, false],
  kanji:        [true, false, false, false],
};

/**
 * Character count indicator bit lengths by mode and version group.
 * Groups: [1-9, 10-26, 27-40]
 */
const CHAR_COUNT_BITS: Record<QRMode, number[]> = {
  numeric:      [10, 12, 14],
  alphanumeric: [9, 11, 13],
  byte:         [8, 16, 16],
  kanji:        [8, 10, 12],
};

/**
 * Get the version group index (0, 1, or 2) for a QR version.
 */
function getVersionGroup(version: number): number {
  if (version <= 9) return 0;
  if (version <= 26) return 1;
  return 2;
}

/**
 * Get character count indicator length in bits.
 */
function getCharCountBits(mode: QRMode, version: number): number {
  return CHAR_COUNT_BITS[mode][getVersionGroup(version)];
}

/**
 * Data capacity table: [version][ecLevel] = number of data codewords.
 * Versions 1-40, EC levels L, M, Q, H.
 */
const DATA_CODEWORDS: number[][] = [
  // Version 1
  [19, 16, 13, 9],
  // Version 2
  [34, 28, 22, 16],
  // Version 3
  [55, 44, 34, 26],
  // Version 4
  [80, 64, 48, 36],
  // Version 5
  [108, 86, 62, 46],
  // Version 6
  [136, 108, 76, 60],
  // Version 7
  [156, 124, 88, 66],
  // Version 8
  [194, 154, 110, 86],
  // Version 9
  [232, 182, 132, 100],
  // Version 10
  [274, 216, 154, 122],
  // Version 11
  [324, 254, 180, 140],
  // Version 12
  [370, 290, 206, 158],
  // Version 13
  [428, 334, 244, 180],
  // Version 14
  [461, 365, 261, 197],
  // Version 15
  [523, 415, 295, 223],
  // Version 16
  [589, 453, 325, 253],
  // Version 17
  [647, 507, 367, 283],
  // Version 18
  [721, 563, 397, 313],
  // Version 19
  [795, 627, 445, 341],
  // Version 20
  [861, 669, 485, 385],
  // Version 21
  [932, 714, 512, 406],
  // Version 22
  [1006, 782, 568, 442],
  // Version 23
  [1094, 860, 614, 464],
  // Version 24
  [1174, 914, 664, 514],
  // Version 25
  [1276, 1000, 718, 538],
  // Version 26
  [1370, 1062, 754, 596],
  // Version 27
  [1468, 1128, 808, 628],
  // Version 28
  [1531, 1193, 871, 661],
  // Version 29
  [1631, 1267, 911, 701],
  // Version 30
  [1735, 1373, 985, 745],
  // Version 31
  [1843, 1455, 1033, 793],
  // Version 32
  [1955, 1541, 1115, 845],
  // Version 33
  [2071, 1631, 1171, 901],
  // Version 34
  [2191, 1725, 1231, 961],
  // Version 35
  [2306, 1812, 1286, 986],
  // Version 36
  [2434, 1914, 1354, 1054],
  // Version 37
  [2566, 1992, 1426, 1096],
  // Version 38
  [2702, 2102, 1502, 1142],
  // Version 39
  [2812, 2216, 1582, 1222],
  // Version 40
  [2956, 2334, 1666, 1276],
];

function ecLevelIndex(ecLevel: QRErrorLevel): number {
  switch (ecLevel) {
    case 'L': return 0;
    case 'M': return 1;
    case 'Q': return 2;
    case 'H': return 3;
  }
}

/**
 * Get data capacity in codewords for a given version and EC level.
 */
export function getDataCapacity(version: number, ecLevel: QRErrorLevel): number {
  return DATA_CODEWORDS[version - 1][ecLevelIndex(ecLevel)];
}

/**
 * Find the minimum QR version (1-40) that can hold the given data.
 */
export function getMinVersion(data: string, mode: QRMode, ecLevel: QRErrorLevel): number {
  for (let version = 1; version <= 40; version++) {
    const capacity = getDataCapacity(version, ecLevel);
    const dataBits = getEncodedBitLength(data, mode, version);
    if (dataBits <= capacity * 8) {
      return version;
    }
  }
  throw new Error('QR Code: data too long for any version');
}

/**
 * Calculate the encoded bit length for data in a given mode and version.
 */
function getEncodedBitLength(data: string, mode: QRMode, version: number): number {
  const charCountBits = getCharCountBits(mode, version);
  let dataBits = 4 + charCountBits; // mode indicator + char count

  switch (mode) {
    case 'numeric': {
      const groups = Math.floor(data.length / 3);
      const remainder = data.length % 3;
      dataBits += groups * 10;
      if (remainder === 2) dataBits += 7;
      else if (remainder === 1) dataBits += 4;
      break;
    }
    case 'alphanumeric': {
      const pairs = Math.floor(data.length / 2);
      const remainder = data.length % 2;
      dataBits += pairs * 11 + remainder * 6;
      break;
    }
    case 'byte': {
      dataBits += data.length * 8;
      break;
    }
    case 'kanji': {
      dataBits += data.length * 13;
      break;
    }
  }

  return dataBits;
}

/**
 * Convert a number to bits array of given length.
 */
function toBits(value: number, length: number): boolean[] {
  const bits: boolean[] = [];
  for (let i = length - 1; i >= 0; i--) {
    bits.push(((value >> i) & 1) === 1);
  }
  return bits;
}

/**
 * Encode data into a bit stream for QR code.
 */
export function encodeData(data: string, mode: QRMode, version: number): boolean[] {
  const bits: boolean[] = [];

  // Mode indicator (4 bits)
  bits.push(...MODE_INDICATORS[mode]);

  // Character count indicator
  const charCountBits = getCharCountBits(mode, version);
  bits.push(...toBits(data.length, charCountBits));

  // Data encoding
  switch (mode) {
    case 'numeric':
      encodeNumeric(data, bits);
      break;
    case 'alphanumeric':
      encodeAlphanumeric(data, bits);
      break;
    case 'byte':
      encodeByte(data, bits);
      break;
    default:
      throw new Error(`QR Code: unsupported mode ${mode}`);
  }

  // Terminator: up to 4 zero bits
  const capacity = getDataCapacity(version, 'L') * 8; // We'll truncate later
  const terminatorLength = Math.min(4, capacity - bits.length);
  for (let i = 0; i < terminatorLength; i++) {
    bits.push(false);
  }

  // Pad to byte boundary
  while (bits.length % 8 !== 0) {
    bits.push(false);
  }

  return bits;
}

/**
 * Encode data into a complete codeword sequence (including padding).
 */
export function encodeDataCodewords(
  data: string,
  mode: QRMode,
  version: number,
  ecLevel: QRErrorLevel,
): number[] {
  const bits: boolean[] = [];

  // Mode indicator (4 bits)
  bits.push(...MODE_INDICATORS[mode]);

  // Character count indicator
  const charCountBits = getCharCountBits(mode, version);
  bits.push(...toBits(data.length, charCountBits));

  // Data encoding
  switch (mode) {
    case 'numeric':
      encodeNumeric(data, bits);
      break;
    case 'alphanumeric':
      encodeAlphanumeric(data, bits);
      break;
    case 'byte':
      encodeByte(data, bits);
      break;
    default:
      throw new Error(`QR Code: unsupported mode ${mode}`);
  }

  const totalDataCodewords = getDataCapacity(version, ecLevel);
  const totalDataBits = totalDataCodewords * 8;

  // Terminator
  const terminatorLength = Math.min(4, totalDataBits - bits.length);
  for (let i = 0; i < terminatorLength; i++) {
    bits.push(false);
  }

  // Pad to byte boundary
  while (bits.length % 8 !== 0 && bits.length < totalDataBits) {
    bits.push(false);
  }

  // Convert to codewords
  const codewords: number[] = [];
  for (let i = 0; i < bits.length; i += 8) {
    let byte = 0;
    for (let j = 0; j < 8 && i + j < bits.length; j++) {
      byte = (byte << 1) | (bits[i + j] ? 1 : 0);
    }
    codewords.push(byte);
  }

  // Pad codewords with alternating 0xEC, 0x11
  const padBytes = [0xEC, 0x11];
  let padIdx = 0;
  while (codewords.length < totalDataCodewords) {
    codewords.push(padBytes[padIdx]);
    padIdx = (padIdx + 1) % 2;
  }

  return codewords;
}

function encodeNumeric(data: string, bits: boolean[]): void {
  // Groups of 3 digits -> 10 bits
  let i = 0;
  while (i + 2 < data.length) {
    const group = parseInt(data.substring(i, i + 3), 10);
    bits.push(...toBits(group, 10));
    i += 3;
  }
  // Remaining 2 digits -> 7 bits
  if (data.length - i === 2) {
    const group = parseInt(data.substring(i, i + 2), 10);
    bits.push(...toBits(group, 7));
  }
  // Remaining 1 digit -> 4 bits
  else if (data.length - i === 1) {
    const group = parseInt(data[i], 10);
    bits.push(...toBits(group, 4));
  }
}

function encodeAlphanumeric(data: string, bits: boolean[]): void {
  // Pairs of characters -> 11 bits
  let i = 0;
  while (i + 1 < data.length) {
    const v1 = ALPHANUMERIC_CHARS.indexOf(data[i]);
    const v2 = ALPHANUMERIC_CHARS.indexOf(data[i + 1]);
    bits.push(...toBits(v1 * 45 + v2, 11));
    i += 2;
  }
  // Remaining character -> 6 bits
  if (i < data.length) {
    const v = ALPHANUMERIC_CHARS.indexOf(data[i]);
    bits.push(...toBits(v, 6));
  }
}

function encodeByte(data: string, bits: boolean[]): void {
  // Encode as UTF-8 bytes
  const encoder = new TextEncoder();
  const bytes = encoder.encode(data);
  for (const byte of bytes) {
    bits.push(...toBits(byte, 8));
  }
}
