/**
 * Pure TypeScript AES-CBC implementation supporting 128-bit and 256-bit keys.
 */

// AES S-box
const SBOX: number[] = [
  0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
  0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
  0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
  0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
  0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
  0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
  0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
  0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
  0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
  0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
  0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
  0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
  0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
  0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
  0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
  0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16,
];

// Inverse S-box
const INV_SBOX: number[] = [
  0x52,0x09,0x6a,0xd5,0x30,0x36,0xa5,0x38,0xbf,0x40,0xa3,0x9e,0x81,0xf3,0xd7,0xfb,
  0x7c,0xe3,0x39,0x82,0x9b,0x2f,0xff,0x87,0x34,0x8e,0x43,0x44,0xc4,0xde,0xe9,0xcb,
  0x54,0x7b,0x94,0x32,0xa6,0xc2,0x23,0x3d,0xee,0x4c,0x95,0x0b,0x42,0xfa,0xc3,0x4e,
  0x08,0x2e,0xa1,0x66,0x28,0xd9,0x24,0xb2,0x76,0x5b,0xa2,0x49,0x6d,0x8b,0xd1,0x25,
  0x72,0xf8,0xf6,0x64,0x86,0x68,0x98,0x16,0xd4,0xa4,0x5c,0xcc,0x5d,0x65,0xb6,0x92,
  0x6c,0x70,0x48,0x50,0xfd,0xed,0xb9,0xda,0x5e,0x15,0x46,0x57,0xa7,0x8d,0x9d,0x84,
  0x90,0xd8,0xab,0x00,0x8c,0xbc,0xd3,0x0a,0xf7,0xe4,0x58,0x05,0xb8,0xb3,0x45,0x06,
  0xd0,0x2c,0x1e,0x8f,0xca,0x3f,0x0f,0x02,0xc1,0xaf,0xbd,0x03,0x01,0x13,0x8a,0x6b,
  0x3a,0x91,0x11,0x41,0x4f,0x67,0xdc,0xea,0x97,0xf2,0xcf,0xce,0xf0,0xb4,0xe6,0x73,
  0x96,0xac,0x74,0x22,0xe7,0xad,0x35,0x85,0xe2,0xf9,0x37,0xe8,0x1c,0x75,0xdf,0x6e,
  0x47,0xf1,0x1a,0x71,0x1d,0x29,0xc5,0x89,0x6f,0xb7,0x62,0x0e,0xaa,0x18,0xbe,0x1b,
  0xfc,0x56,0x3e,0x4b,0xc6,0xd2,0x79,0x20,0x9a,0xdb,0xc0,0xfe,0x78,0xcd,0x5a,0xf4,
  0x1f,0xdd,0xa8,0x33,0x88,0x07,0xc7,0x31,0xb1,0x12,0x10,0x59,0x27,0x80,0xec,0x5f,
  0x60,0x51,0x7f,0xa9,0x19,0xb5,0x4a,0x0d,0x2d,0xe5,0x7a,0x9f,0x93,0xc9,0x9c,0xef,
  0xa0,0xe0,0x3b,0x4d,0xae,0x2a,0xf5,0xb0,0xc8,0xeb,0xbb,0x3c,0x83,0x53,0x99,0x61,
  0x17,0x2b,0x04,0x7e,0xba,0x77,0xd6,0x26,0xe1,0x69,0x14,0x63,0x55,0x21,0x0c,0x7d,
];

// Round constants for key expansion
const RCON: number[] = [
  0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36,
  0x6c, 0xd8, 0xab, 0x4d, 0x9a, 0x2f, 0x5e, 0xbc, 0x63, 0xc6,
  0x97, 0x35, 0x6a, 0xd4, 0xb3, 0x7d, 0xfa, 0xef, 0xc5, 0x91,
];

// Galois field multiplication tables for MixColumns
function gmul(a: number, b: number): number {
  let p = 0;
  for (let i = 0; i < 8; i++) {
    if (b & 1) p ^= a;
    const hiBit = a & 0x80;
    a = (a << 1) & 0xff;
    if (hiBit) a ^= 0x1b;
    b >>>= 1;
  }
  return p;
}

// Precompute multiplication tables for 2, 3, 9, 11, 13, 14
const MUL2 = new Uint8Array(256);
const MUL3 = new Uint8Array(256);
const MUL9 = new Uint8Array(256);
const MUL11 = new Uint8Array(256);
const MUL13 = new Uint8Array(256);
const MUL14 = new Uint8Array(256);
for (let i = 0; i < 256; i++) {
  MUL2[i] = gmul(i, 2);
  MUL3[i] = gmul(i, 3);
  MUL9[i] = gmul(i, 9);
  MUL11[i] = gmul(i, 11);
  MUL13[i] = gmul(i, 13);
  MUL14[i] = gmul(i, 14);
}

/**
 * Rijndael key expansion.
 * Returns expanded key words as Uint8Array.
 */
function keyExpansion(key: Uint8Array): Uint8Array {
  const keyLen = key.length; // 16 or 32
  const Nk = keyLen / 4; // 4 or 8
  const Nr = Nk + 6; // 10 or 14
  const totalWords = 4 * (Nr + 1);
  const w = new Uint8Array(totalWords * 4);

  // Copy key into first Nk words
  w.set(key);

  for (let i = Nk; i < totalWords; i++) {
    const offset = i * 4;
    const prev = offset - 4;
    const nkBack = offset - Nk * 4;

    let t0 = w[prev];
    let t1 = w[prev + 1];
    let t2 = w[prev + 2];
    let t3 = w[prev + 3];

    if (i % Nk === 0) {
      // RotWord + SubWord + Rcon
      const tmp = t0;
      t0 = SBOX[t1] ^ RCON[(i / Nk) - 1];
      t1 = SBOX[t2];
      t2 = SBOX[t3];
      t3 = SBOX[tmp];
    } else if (Nk > 6 && i % Nk === 4) {
      // SubWord only for AES-256
      t0 = SBOX[t0];
      t1 = SBOX[t1];
      t2 = SBOX[t2];
      t3 = SBOX[t3];
    }

    w[offset] = w[nkBack] ^ t0;
    w[offset + 1] = w[nkBack + 1] ^ t1;
    w[offset + 2] = w[nkBack + 2] ^ t2;
    w[offset + 3] = w[nkBack + 3] ^ t3;
  }

  return w;
}

// State is a 4x4 column-major byte matrix stored as 16-byte array
// state[row + 4*col]

function subBytes(state: Uint8Array): void {
  for (let i = 0; i < 16; i++) state[i] = SBOX[state[i]];
}

function invSubBytes(state: Uint8Array): void {
  for (let i = 0; i < 16; i++) state[i] = INV_SBOX[state[i]];
}

function shiftRows(state: Uint8Array): void {
  // Row 1: shift left 1
  let t = state[1];
  state[1] = state[5]; state[5] = state[9]; state[9] = state[13]; state[13] = t;
  // Row 2: shift left 2
  t = state[2]; state[2] = state[10]; state[10] = t;
  t = state[6]; state[6] = state[14]; state[14] = t;
  // Row 3: shift left 3 (= shift right 1)
  t = state[15];
  state[15] = state[11]; state[11] = state[7]; state[7] = state[3]; state[3] = t;
}

function invShiftRows(state: Uint8Array): void {
  // Row 1: shift right 1
  let t = state[13];
  state[13] = state[9]; state[9] = state[5]; state[5] = state[1]; state[1] = t;
  // Row 2: shift right 2
  t = state[2]; state[2] = state[10]; state[10] = t;
  t = state[6]; state[6] = state[14]; state[14] = t;
  // Row 3: shift right 3 (= shift left 1)
  t = state[3];
  state[3] = state[7]; state[7] = state[11]; state[11] = state[15]; state[15] = t;
}

function mixColumns(state: Uint8Array): void {
  for (let c = 0; c < 4; c++) {
    const i = c * 4;
    const s0 = state[i], s1 = state[i + 1], s2 = state[i + 2], s3 = state[i + 3];
    state[i]     = MUL2[s0] ^ MUL3[s1] ^ s2       ^ s3;
    state[i + 1] = s0       ^ MUL2[s1] ^ MUL3[s2] ^ s3;
    state[i + 2] = s0       ^ s1       ^ MUL2[s2]  ^ MUL3[s3];
    state[i + 3] = MUL3[s0] ^ s1       ^ s2        ^ MUL2[s3];
  }
}

function invMixColumns(state: Uint8Array): void {
  for (let c = 0; c < 4; c++) {
    const i = c * 4;
    const s0 = state[i], s1 = state[i + 1], s2 = state[i + 2], s3 = state[i + 3];
    state[i]     = MUL14[s0] ^ MUL11[s1] ^ MUL13[s2] ^ MUL9[s3];
    state[i + 1] = MUL9[s0]  ^ MUL14[s1] ^ MUL11[s2] ^ MUL13[s3];
    state[i + 2] = MUL13[s0] ^ MUL9[s1]  ^ MUL14[s2] ^ MUL11[s3];
    state[i + 3] = MUL11[s0] ^ MUL13[s1] ^ MUL9[s2]  ^ MUL14[s3];
  }
}

function addRoundKey(state: Uint8Array, expandedKey: Uint8Array, round: number): void {
  const offset = round * 16;
  for (let i = 0; i < 16; i++) {
    state[i] ^= expandedKey[offset + i];
  }
}

function aesEncryptBlock(block: Uint8Array, expandedKey: Uint8Array, Nr: number): Uint8Array {
  const state = new Uint8Array(16);
  // Input is row-major, state is column-major
  for (let r = 0; r < 4; r++) {
    for (let c = 0; c < 4; c++) {
      state[r + 4 * c] = block[r * 4 + c];
    }
  }

  addRoundKey(state, expandedKey, 0);

  for (let round = 1; round < Nr; round++) {
    subBytes(state);
    shiftRows(state);
    mixColumns(state);
    addRoundKey(state, expandedKey, round);
  }

  subBytes(state);
  shiftRows(state);
  addRoundKey(state, expandedKey, Nr);

  // Convert back to row-major
  const output = new Uint8Array(16);
  for (let r = 0; r < 4; r++) {
    for (let c = 0; c < 4; c++) {
      output[r * 4 + c] = state[r + 4 * c];
    }
  }
  return output;
}

function aesDecryptBlock(block: Uint8Array, expandedKey: Uint8Array, Nr: number): Uint8Array {
  const state = new Uint8Array(16);
  for (let r = 0; r < 4; r++) {
    for (let c = 0; c < 4; c++) {
      state[r + 4 * c] = block[r * 4 + c];
    }
  }

  addRoundKey(state, expandedKey, Nr);

  for (let round = Nr - 1; round >= 1; round--) {
    invShiftRows(state);
    invSubBytes(state);
    addRoundKey(state, expandedKey, round);
    invMixColumns(state);
  }

  invShiftRows(state);
  invSubBytes(state);
  addRoundKey(state, expandedKey, 0);

  const output = new Uint8Array(16);
  for (let r = 0; r < 4; r++) {
    for (let c = 0; c < 4; c++) {
      output[r * 4 + c] = state[r + 4 * c];
    }
  }
  return output;
}

/**
 * Generate random bytes. Uses crypto.getRandomValues when available,
 * falls back to Math.random.
 */
export function generateRandomBytes(n: number): Uint8Array {
  const buf = new Uint8Array(n);
  if (typeof globalThis !== 'undefined' && globalThis.crypto && globalThis.crypto.getRandomValues) {
    globalThis.crypto.getRandomValues(buf);
  } else {
    for (let i = 0; i < n; i++) {
      buf[i] = (Math.random() * 256) | 0;
    }
  }
  return buf;
}

/**
 * AES-CBC encryption with PKCS#7 padding.
 * If iv is not provided, generates random 16 bytes and prepends to output.
 */
export function aesEncryptCBC(key: Uint8Array, data: Uint8Array, iv?: Uint8Array): Uint8Array {
  if (key.length !== 16 && key.length !== 32) {
    throw new Error(`AES key must be 16 or 32 bytes, got ${key.length}`);
  }

  const Nr = key.length === 16 ? 10 : 14;
  const expandedKey = keyExpansion(key);

  const prependIV = iv === undefined;
  if (!iv) {
    iv = generateRandomBytes(16);
  }

  // PKCS#7 padding
  const padLen = 16 - (data.length % 16);
  const padded = new Uint8Array(data.length + padLen);
  padded.set(data);
  for (let i = data.length; i < padded.length; i++) {
    padded[i] = padLen;
  }

  const numBlocks = padded.length / 16;
  const encrypted = new Uint8Array(numBlocks * 16);
  let prevBlock = iv;

  for (let i = 0; i < numBlocks; i++) {
    const plainBlock = padded.subarray(i * 16, i * 16 + 16);
    // XOR with previous ciphertext block (or IV)
    const xored = new Uint8Array(16);
    for (let j = 0; j < 16; j++) {
      xored[j] = plainBlock[j] ^ prevBlock[j];
    }
    const cipherBlock = aesEncryptBlock(xored, expandedKey, Nr);
    encrypted.set(cipherBlock, i * 16);
    prevBlock = cipherBlock;
  }

  if (prependIV) {
    const result = new Uint8Array(16 + encrypted.length);
    result.set(iv);
    result.set(encrypted, 16);
    return result;
  }
  return encrypted;
}

/**
 * AES-CBC decryption. First 16 bytes of data are treated as IV.
 * Removes PKCS#7 padding.
 */
export function aesDecryptCBC(key: Uint8Array, data: Uint8Array): Uint8Array {
  if (key.length !== 16 && key.length !== 32) {
    throw new Error(`AES key must be 16 or 32 bytes, got ${key.length}`);
  }
  if (data.length < 32 || data.length % 16 !== 0) {
    throw new Error(`Invalid AES-CBC data length: ${data.length}`);
  }

  const Nr = key.length === 16 ? 10 : 14;
  const expandedKey = keyExpansion(key);

  const iv = data.subarray(0, 16);
  const ciphertext = data.subarray(16);
  const numBlocks = ciphertext.length / 16;
  const decrypted = new Uint8Array(ciphertext.length);

  let prevBlock = iv;
  for (let i = 0; i < numBlocks; i++) {
    const cipherBlock = ciphertext.subarray(i * 16, i * 16 + 16);
    const plainBlock = aesDecryptBlock(cipherBlock, expandedKey, Nr);
    for (let j = 0; j < 16; j++) {
      decrypted[i * 16 + j] = plainBlock[j] ^ prevBlock[j];
    }
    prevBlock = cipherBlock;
  }

  // Remove PKCS#7 padding
  const padByte = decrypted[decrypted.length - 1];
  if (padByte < 1 || padByte > 16) {
    throw new Error(`Invalid PKCS#7 padding byte: ${padByte}`);
  }
  // Verify all padding bytes
  for (let i = decrypted.length - padByte; i < decrypted.length; i++) {
    if (decrypted[i] !== padByte) {
      throw new Error('Invalid PKCS#7 padding');
    }
  }

  return decrypted.subarray(0, decrypted.length - padByte);
}
