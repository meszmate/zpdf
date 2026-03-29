/**
 * PDF password processing and key derivation per PDF encryption spec.
 */

import { md5 } from './md5.js';
import { rc4 } from './rc4.js';
import { aesEncryptCBC, aesDecryptCBC, generateRandomBytes } from './aes.js';

/**
 * The 32-byte padding string defined in the PDF specification (Table 21, PDF 1.7).
 */
export const PDF_PASSWORD_PADDING = new Uint8Array([
  0x28, 0xbf, 0x4e, 0x5e, 0x4e, 0x75, 0x8a, 0x41,
  0x64, 0x00, 0x4e, 0x56, 0xff, 0xfa, 0x01, 0x08,
  0x2e, 0x2e, 0x00, 0xb6, 0xd0, 0x68, 0x3e, 0x80,
  0x2f, 0x0c, 0xa9, 0xfe, 0x64, 0x53, 0x69, 0x7a,
]);

/**
 * Pad or truncate password to exactly 32 bytes using the PDF padding constant.
 */
export function padPassword(password: string): Uint8Array {
  const result = new Uint8Array(32);
  const passBytes = new Uint8Array(password.length);
  for (let i = 0; i < password.length; i++) {
    passBytes[i] = password.charCodeAt(i) & 0xff;
  }
  const len = Math.min(passBytes.length, 32);
  result.set(passBytes.subarray(0, len));
  if (len < 32) {
    result.set(PDF_PASSWORD_PADDING.subarray(0, 32 - len), len);
  }
  return result;
}

/**
 * Helper: encode a 32-bit integer as 4 little-endian bytes.
 */
function int32LE(value: number): Uint8Array {
  const b = new Uint8Array(4);
  b[0] = value & 0xff;
  b[1] = (value >>> 8) & 0xff;
  b[2] = (value >>> 16) & 0xff;
  b[3] = (value >>> 24) & 0xff;
  return b;
}

/**
 * Concatenate multiple Uint8Arrays.
 */
function concat(...arrays: Uint8Array[]): Uint8Array {
  let total = 0;
  for (const a of arrays) total += a.length;
  const result = new Uint8Array(total);
  let offset = 0;
  for (const a of arrays) {
    result.set(a, offset);
    offset += a.length;
  }
  return result;
}

/**
 * Compute the /O (owner) entry and the owner encryption key.
 *
 * Algorithm 3 (PDF 1.7 spec, section 7.6.3.3):
 * Rev 2: Simple MD5 + RC4
 * Rev 3+: MD5 repeated 50 times + RC4 with 20 key variations
 */
export function computeOwnerKey(
  ownerPassword: string,
  userPassword: string,
  revision: number,
  keyLength: number,
): { ownerEntry: Uint8Array; ownerKey: Uint8Array } {
  const keyBytes = keyLength / 8;

  // Step a: Pad or truncate owner password (or user password if owner not provided)
  const paddedOwner = padPassword(ownerPassword || userPassword);

  // Step b: MD5 hash the padded password
  let hash = md5(paddedOwner);

  // Step c: (Rev 3+) Repeat MD5 50 times
  if (revision >= 3) {
    for (let i = 0; i < 50; i++) {
      hash = md5(hash);
    }
  }

  // Step d: Take first keyBytes of hash as RC4 key
  const ownerKey = hash.subarray(0, keyBytes);

  // Step e: Pad the user password
  const paddedUser = padPassword(userPassword);

  // Step f: RC4 encrypt the padded user password
  let encrypted = rc4(ownerKey, paddedUser);

  // Step g: (Rev 3+) Do 19 more RC4 encryptions with modified keys
  if (revision >= 3) {
    for (let i = 1; i <= 19; i++) {
      const modKey = new Uint8Array(keyBytes);
      for (let j = 0; j < keyBytes; j++) {
        modKey[j] = ownerKey[j] ^ i;
      }
      encrypted = rc4(modKey, encrypted);
    }
  }

  return { ownerEntry: encrypted, ownerKey };
}

/**
 * Compute the /U (user) entry and the file encryption key.
 *
 * Algorithm 2 (for encryption key) and Algorithm 4/5 (for /U value).
 */
export function computeUserKey(
  password: string,
  ownerEntry: Uint8Array,
  permissions: number,
  fileId: Uint8Array,
  revision: number,
  keyLength: number,
  encryptMetadata: boolean,
): { userEntry: Uint8Array; encryptionKey: Uint8Array } {
  const keyBytes = keyLength / 8;

  // Algorithm 2: Compute encryption key
  // Step a: Pad password
  const paddedPassword = padPassword(password);

  // Step b-f: Build hash input
  const permBytes = int32LE(permissions);
  let hashInput: Uint8Array;

  if (!encryptMetadata && revision >= 4) {
    hashInput = concat(paddedPassword, ownerEntry, permBytes, fileId, new Uint8Array([0xff, 0xff, 0xff, 0xff]));
  } else {
    hashInput = concat(paddedPassword, ownerEntry, permBytes, fileId);
  }

  let hash = md5(hashInput);

  // (Rev 3+): Repeat MD5 50 times, each time hashing only the first keyBytes
  if (revision >= 3) {
    for (let i = 0; i < 50; i++) {
      hash = md5(hash.subarray(0, keyBytes));
    }
  }

  const encryptionKey = hash.subarray(0, keyBytes);

  // Now compute the /U value
  let userEntry: Uint8Array;

  if (revision === 2) {
    // Algorithm 4: RC4-encrypt the padding string
    userEntry = rc4(encryptionKey, PDF_PASSWORD_PADDING);
  } else {
    // Algorithm 5 (Rev 3+):
    // Step a: MD5 of padding + fileId
    const uHash = md5(concat(PDF_PASSWORD_PADDING, fileId));

    // Step b: RC4-encrypt the hash
    let encrypted = rc4(encryptionKey, uHash);

    // Step c: 19 more RC4 encryptions with modified keys
    for (let i = 1; i <= 19; i++) {
      const modKey = new Uint8Array(keyBytes);
      for (let j = 0; j < keyBytes; j++) {
        modKey[j] = encryptionKey[j] ^ i;
      }
      encrypted = rc4(modKey, encrypted);
    }

    // Step d: Pad to 32 bytes with arbitrary data
    userEntry = new Uint8Array(32);
    userEntry.set(encrypted);
    // Remaining bytes are already 0, which is acceptable
  }

  return { userEntry, encryptionKey };
}

/**
 * SHA-256 implementation for Rev 6 (PDF 2.0 / AES-256).
 */
function sha256(data: Uint8Array): Uint8Array {
  const K: number[] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  function rotr(x: number, n: number): number {
    return ((x >>> n) | (x << (32 - n))) >>> 0;
  }

  const originalLen = data.length;
  const bitLen = originalLen * 8;
  const paddedLen = (((originalLen + 8) >>> 6) + 1) << 6;
  const padded = new Uint8Array(paddedLen);
  padded.set(data);
  padded[originalLen] = 0x80;
  const dv = new DataView(padded.buffer, padded.byteOffset, padded.byteLength);
  dv.setUint32(paddedLen - 4, bitLen >>> 0, false);
  dv.setUint32(paddedLen - 8, (bitLen / 0x100000000) >>> 0, false);

  let h0 = 0x6a09e667, h1 = 0xbb67ae85, h2 = 0x3c6ef372, h3 = 0xa54ff53a;
  let h4 = 0x510e527f, h5 = 0x9b05688c, h6 = 0x1f83d9ab, h7 = 0x5be0cd19;

  const W = new Array<number>(64);

  for (let offset = 0; offset < paddedLen; offset += 64) {
    for (let i = 0; i < 16; i++) {
      W[i] = dv.getUint32(offset + i * 4, false);
    }
    for (let i = 16; i < 64; i++) {
      const s0 = rotr(W[i - 15], 7) ^ rotr(W[i - 15], 18) ^ (W[i - 15] >>> 3);
      const s1 = rotr(W[i - 2], 17) ^ rotr(W[i - 2], 19) ^ (W[i - 2] >>> 10);
      W[i] = (W[i - 16] + s0 + W[i - 7] + s1) >>> 0;
    }

    let a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;

    for (let i = 0; i < 64; i++) {
      const S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const ch = ((e & f) ^ ((~e) & g)) >>> 0;
      const temp1 = (h + S1 + ch + K[i] + W[i]) >>> 0;
      const S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      const maj = ((a & b) ^ (a & c) ^ (b & c)) >>> 0;
      const temp2 = (S0 + maj) >>> 0;

      h = g; g = f; f = e;
      e = (d + temp1) >>> 0;
      d = c; c = b; b = a;
      a = (temp1 + temp2) >>> 0;
    }

    h0 = (h0 + a) >>> 0;
    h1 = (h1 + b) >>> 0;
    h2 = (h2 + c) >>> 0;
    h3 = (h3 + d) >>> 0;
    h4 = (h4 + e) >>> 0;
    h5 = (h5 + f) >>> 0;
    h6 = (h6 + g) >>> 0;
    h7 = (h7 + h) >>> 0;
  }

  const result = new Uint8Array(32);
  const rdv = new DataView(result.buffer);
  rdv.setUint32(0, h0, false);
  rdv.setUint32(4, h1, false);
  rdv.setUint32(8, h2, false);
  rdv.setUint32(12, h3, false);
  rdv.setUint32(16, h4, false);
  rdv.setUint32(20, h5, false);
  rdv.setUint32(24, h6, false);
  rdv.setUint32(28, h7, false);
  return result;
}

/**
 * SHA-384 implementation (SHA-512 truncated to 384 bits).
 */
function sha384(data: Uint8Array): Uint8Array {
  return sha512Truncated(data, 384);
}

/**
 * SHA-512 implementation. Can produce 384 or 512 bit output.
 */
function sha512Truncated(data: Uint8Array, bits: 384 | 512): Uint8Array {
  const K: bigint[] = [
    0x428a2f98d728ae22n, 0x7137449123ef65cdn, 0xb5c0fbcfec4d3b2fn, 0xe9b5dba58189dbbcn,
    0x3956c25bf348b538n, 0x59f111f1b605d019n, 0x923f82a4af194f9bn, 0xab1c5ed5da6d8118n,
    0xd807aa98a3030242n, 0x12835b0145706fben, 0x243185be4ee4b28cn, 0x550c7dc3d5ffb4e2n,
    0x72be5d74f27b896fn, 0x80deb1fe3b1696b1n, 0x9bdc06a725c71235n, 0xc19bf174cf692694n,
    0xe49b69c19ef14ad2n, 0xefbe4786384f25e3n, 0x0fc19dc68b8cd5b5n, 0x240ca1cc77ac9c65n,
    0x2de92c6f592b0275n, 0x4a7484aa6ea6e483n, 0x5cb0a9dcbd41fbd4n, 0x76f988da831153b5n,
    0x983e5152ee66dfabn, 0xa831c66d2db43210n, 0xb00327c898fb213fn, 0xbf597fc7beef0ee4n,
    0xc6e00bf33da88fc2n, 0xd5a79147930aa725n, 0x06ca6351e003826fn, 0x142929670a0e6e70n,
    0x27b70a8546d22ffcn, 0x2e1b21385c26c926n, 0x4d2c6dfc5ac42aedn, 0x53380d139d95b3dfn,
    0x650a73548baf63den, 0x766a0abb3c77b2a8n, 0x81c2c92e47edaee6n, 0x92722c851482353bn,
    0xa2bfe8a14cf10364n, 0xa81a664bbc423001n, 0xc24b8b70d0f89791n, 0xc76c51a30654be30n,
    0xd192e819d6ef5218n, 0xd69906245565a910n, 0xf40e35855771202an, 0x106aa07032bbd1b8n,
    0x19a4c116b8d2d0c8n, 0x1e376c085141ab53n, 0x2748774cdf8eeb99n, 0x34b0bcb5e19b48a8n,
    0x391c0cb3c5c95a63n, 0x4ed8aa4ae3418acbn, 0x5b9cca4f7763e373n, 0x682e6ff3d6b2b8a3n,
    0x748f82ee5defb2fcn, 0x78a5636f43172f60n, 0x84c87814a1f0ab72n, 0x8cc702081a6439ecn,
    0x90befffa23631e28n, 0xa4506cebde82bde9n, 0xbef9a3f7b2c67915n, 0xc67178f2e372532bn,
    0xca273eceea26619cn, 0xd186b8c721c0c207n, 0xeada7dd6cde0eb1en, 0xf57d4f7fee6ed178n,
    0x06f067aa72176fban, 0x0a637dc5a2c898a6n, 0x113f9804bef90daen, 0x1b710b35131c471bn,
    0x28db77f523047d84n, 0x32caab7b40c72493n, 0x3c9ebe0a15c9bebcn, 0x431d67c49c100d4cn,
    0x4cc5d4becb3e42b6n, 0x597f299cfc657e2an, 0x5fcb6fab3ad6faecn, 0x6c44198c4a475817n,
  ];

  const MASK64 = 0xffffffffffffffffn;

  function rotr64(x: bigint, n: number): bigint {
    return ((x >> BigInt(n)) | (x << BigInt(64 - n))) & MASK64;
  }

  let h0: bigint, h1: bigint, h2: bigint, h3: bigint;
  let h4: bigint, h5: bigint, h6: bigint, h7: bigint;

  if (bits === 384) {
    h0 = 0xcbbb9d5dc1059ed8n; h1 = 0x629a292a367cd507n;
    h2 = 0x9159015a3070dd17n; h3 = 0x152fecd8f70e5939n;
    h4 = 0x67332667ffc00b31n; h5 = 0x8eb44a8768581511n;
    h6 = 0xdb0c2e0d64f98fa7n; h7 = 0x47b5481dbefa4fa4n;
  } else {
    h0 = 0x6a09e667f3bcc908n; h1 = 0xbb67ae8584caa73bn;
    h2 = 0x3c6ef372fe94f82bn; h3 = 0xa54ff53a5f1d36f1n;
    h4 = 0x510e527fade682d1n; h5 = 0x9b05688c2b3e6c1fn;
    h6 = 0x1f83d9abfb41bd6bn; h7 = 0x5be0cd19137e2179n;
  }

  const originalLen = data.length;
  const bitLen = BigInt(originalLen) * 8n;
  const paddedLen = (Math.ceil((originalLen + 17) / 128)) * 128;
  const padded = new Uint8Array(paddedLen);
  padded.set(data);
  padded[originalLen] = 0x80;
  const pdv = new DataView(padded.buffer, padded.byteOffset, padded.byteLength);
  pdv.setBigUint64(paddedLen - 8, bitLen, false);

  const W = new Array<bigint>(80);

  for (let offset = 0; offset < paddedLen; offset += 128) {
    const bv = new DataView(padded.buffer, padded.byteOffset + offset, 128);
    for (let i = 0; i < 16; i++) {
      W[i] = bv.getBigUint64(i * 8, false);
    }
    for (let i = 16; i < 80; i++) {
      const s0 = rotr64(W[i - 15], 1) ^ rotr64(W[i - 15], 8) ^ (W[i - 15] >> 7n);
      const s1 = rotr64(W[i - 2], 19) ^ rotr64(W[i - 2], 61) ^ (W[i - 2] >> 6n);
      W[i] = (W[i - 16] + s0 + W[i - 7] + s1) & MASK64;
    }

    let a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;

    for (let i = 0; i < 80; i++) {
      const S1 = rotr64(e, 14) ^ rotr64(e, 18) ^ rotr64(e, 41);
      const ch = ((e & f) ^ ((~e & MASK64) & g)) & MASK64;
      const temp1 = (h + S1 + ch + K[i] + W[i]) & MASK64;
      const S0 = rotr64(a, 28) ^ rotr64(a, 34) ^ rotr64(a, 39);
      const maj = ((a & b) ^ (a & c) ^ (b & c)) & MASK64;
      const temp2 = (S0 + maj) & MASK64;

      h = g; g = f; f = e;
      e = (d + temp1) & MASK64;
      d = c; c = b; b = a;
      a = (temp1 + temp2) & MASK64;
    }

    h0 = (h0 + a) & MASK64;
    h1 = (h1 + b) & MASK64;
    h2 = (h2 + c) & MASK64;
    h3 = (h3 + d) & MASK64;
    h4 = (h4 + e) & MASK64;
    h5 = (h5 + f) & MASK64;
    h6 = (h6 + g) & MASK64;
    h7 = (h7 + h) & MASK64;
  }

  const outputLen = bits / 8;
  const result = new Uint8Array(outputLen);
  const rdv = new DataView(result.buffer);
  rdv.setBigUint64(0, h0, false);
  rdv.setBigUint64(8, h1, false);
  rdv.setBigUint64(16, h2, false);
  rdv.setBigUint64(24, h3, false);
  rdv.setBigUint64(32, h4, false);
  rdv.setBigUint64(40, h5, false);
  if (outputLen > 48) {
    rdv.setBigUint64(48, h6, false);
    rdv.setBigUint64(56, h7, false);
  }
  return result;
}

/**
 * Compute encryption key for Rev 6 (PDF 2.0 / AES-256).
 *
 * The Rev 6 algorithm uses an iterative hash-based key derivation
 * based on the ISO 32000-2 specification (section 7.6.4.3.3, Algorithm 2.B).
 *
 * @param password - The password string (UTF-8 encoded, max 127 bytes)
 * @param salt - 8-byte validation or key salt
 * @param userKey - 48-byte /U value (only needed when computing owner key)
 * @returns 32-byte encryption key
 */
export function computeEncryptionKeyR6(
  password: string,
  salt: Uint8Array,
  userKey?: Uint8Array,
): Uint8Array {
  const encoder = new TextEncoder();
  let passBytes = encoder.encode(password);
  if (passBytes.length > 127) {
    passBytes = passBytes.subarray(0, 127);
  }

  const parts: Uint8Array[] = [passBytes, salt];
  if (userKey) {
    parts.push(userKey);
  }
  const input = concat(...parts);

  // Initial hash with SHA-256
  let hash = sha256(input);

  // Iterative key derivation (Algorithm 2.B from ISO 32000-2)
  let round = 0;
  let lastByte = 0;

  while (true) {
    // Build K1: password + hash + (userKey if present), repeated 64 times
    const k1Parts: Uint8Array[] = [passBytes, hash];
    if (userKey) {
      k1Parts.push(userKey);
    }
    const k1Single = concat(...k1Parts);
    const k1 = new Uint8Array(k1Single.length * 64);
    for (let i = 0; i < 64; i++) {
      k1.set(k1Single, i * k1Single.length);
    }

    // AES-128-CBC encrypt K1 using first 16 bytes of hash as key
    // and next 16 bytes as IV
    const aesKey = hash.subarray(0, 16);
    const aesIV = hash.subarray(16, 32);
    const encrypted = aesEncryptCBC(aesKey, k1, aesIV);

    // Determine which SHA to use based on sum of first 16 bytes mod 3
    let sum = 0;
    for (let i = 0; i < 16; i++) {
      sum += encrypted[i];
    }

    const remainder = sum % 3;
    if (remainder === 0) {
      hash = sha256(encrypted);
    } else if (remainder === 1) {
      hash = sha384(encrypted);
    } else {
      hash = sha512Truncated(encrypted, 512);
    }

    lastByte = encrypted[encrypted.length - 1];
    round++;

    // Exit condition: at least 64 rounds, and last byte value <= round - 32
    if (round >= 64 && lastByte <= round - 32) {
      break;
    }
  }

  return hash.subarray(0, 32);
}

/**
 * Compute the /U and /UE values for Rev 6.
 */
export function computeUserKeyR6(
  password: string,
): { userEntry: Uint8Array; userKeyEncryption: Uint8Array; encryptionKey: Uint8Array } {
  const encoder = new TextEncoder();
  let passBytes = encoder.encode(password);
  if (passBytes.length > 127) {
    passBytes = passBytes.subarray(0, 127);
  }

  // Generate random validation salt (8 bytes) and key salt (8 bytes)
  const validationSalt = generateRandomBytes(8);
  const keySalt = generateRandomBytes(8);

  // /U = SHA-256(password + validation salt) + validation salt + key salt
  const uHash = sha256(concat(passBytes, validationSalt));
  const userEntry = new Uint8Array(48);
  userEntry.set(uHash, 0);
  userEntry.set(validationSalt, 32);
  userEntry.set(keySalt, 40);

  // Generate the file encryption key (32 random bytes)
  const encryptionKey = generateRandomBytes(32);

  // /UE = AES-256-CBC encrypt the file encryption key
  const ueKey = computeEncryptionKeyR6(password, keySalt);
  const iv = new Uint8Array(16); // zero IV
  const userKeyEncryption = aesEncryptCBC(ueKey, encryptionKey, iv);

  return { userEntry, userKeyEncryption, encryptionKey };
}

/**
 * Compute the /O and /OE values for Rev 6.
 */
export function computeOwnerKeyR6(
  ownerPassword: string,
  userEntry: Uint8Array,
): { ownerEntry: Uint8Array; ownerKeyEncryption: Uint8Array; encryptionKey: Uint8Array } {
  const encoder = new TextEncoder();
  let passBytes = encoder.encode(ownerPassword);
  if (passBytes.length > 127) {
    passBytes = passBytes.subarray(0, 127);
  }

  const validationSalt = generateRandomBytes(8);
  const keySalt = generateRandomBytes(8);

  // /O = SHA-256(password + validation salt + /U) + validation salt + key salt
  const oHash = sha256(concat(passBytes, validationSalt, userEntry));
  const ownerEntry = new Uint8Array(48);
  ownerEntry.set(oHash, 0);
  ownerEntry.set(validationSalt, 32);
  ownerEntry.set(keySalt, 40);

  const oeKey = computeEncryptionKeyR6(ownerPassword, keySalt, userEntry);
  const encryptionKey = generateRandomBytes(32);
  const iv = new Uint8Array(16);
  const ownerKeyEncryption = aesEncryptCBC(oeKey, encryptionKey, iv);

  return { ownerEntry, ownerKeyEncryption, encryptionKey };
}

/**
 * Validate a user password for Rev 6.
 */
export function validateUserPasswordR6(password: string, userEntry: Uint8Array): boolean {
  const encoder = new TextEncoder();
  let passBytes = encoder.encode(password);
  if (passBytes.length > 127) {
    passBytes = passBytes.subarray(0, 127);
  }

  const validationSalt = userEntry.subarray(32, 40);
  const hash = sha256(concat(passBytes, validationSalt));

  for (let i = 0; i < 32; i++) {
    if (hash[i] !== userEntry[i]) return false;
  }
  return true;
}

/**
 * Validate an owner password for Rev 6.
 */
export function validateOwnerPasswordR6(password: string, ownerEntry: Uint8Array, userEntry: Uint8Array): boolean {
  const encoder = new TextEncoder();
  let passBytes = encoder.encode(password);
  if (passBytes.length > 127) {
    passBytes = passBytes.subarray(0, 127);
  }

  const validationSalt = ownerEntry.subarray(32, 40);
  const hash = sha256(concat(passBytes, validationSalt, userEntry));

  for (let i = 0; i < 32; i++) {
    if (hash[i] !== ownerEntry[i]) return false;
  }
  return true;
}

/**
 * Recover the file encryption key from /UE for Rev 6.
 */
export function recoverFileKeyFromUserR6(password: string, userEntry: Uint8Array, ueEntry: Uint8Array): Uint8Array {
  const keySalt = userEntry.subarray(40, 48);
  const key = computeEncryptionKeyR6(password, keySalt);

  // /UE is AES-256-CBC encrypted with zero IV
  const iv = new Uint8Array(16);
  const dataWithIV = concat(iv, ueEntry);
  return aesDecryptCBC(key, dataWithIV);
}

/**
 * Recover the file encryption key from /OE for Rev 6.
 */
export function recoverFileKeyFromOwnerR6(password: string, ownerEntry: Uint8Array, userEntry: Uint8Array, oeEntry: Uint8Array): Uint8Array {
  const keySalt = ownerEntry.subarray(40, 48);
  const key = computeEncryptionKeyR6(password, keySalt, userEntry);

  const iv = new Uint8Array(16);
  const dataWithIV = concat(iv, oeEntry);
  return aesDecryptCBC(key, dataWithIV);
}
