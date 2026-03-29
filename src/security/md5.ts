/**
 * Pure TypeScript MD5 implementation (RFC 1321).
 */

// Per-round shift amounts
const S: number[] = [
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
  5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20,
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
];

// Precomputed T[i] = floor(2^32 * abs(sin(i + 1)))
const T: number[] = [
  0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
  0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
  0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
  0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
  0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
  0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
  0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
  0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
  0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
  0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
  0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
  0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
  0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
  0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
  0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
  0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
];

function rotateLeft(x: number, n: number): number {
  return ((x << n) | (x >>> (32 - n))) >>> 0;
}

function toLittleEndian32(buf: Uint8Array, offset: number): number {
  return (
    (buf[offset]) |
    (buf[offset + 1] << 8) |
    (buf[offset + 2] << 16) |
    (buf[offset + 3] << 24)
  ) >>> 0;
}

function storeLittleEndian32(buf: Uint8Array, offset: number, val: number): void {
  buf[offset] = val & 0xff;
  buf[offset + 1] = (val >>> 8) & 0xff;
  buf[offset + 2] = (val >>> 16) & 0xff;
  buf[offset + 3] = (val >>> 24) & 0xff;
}

export function md5(data: Uint8Array): Uint8Array {
  const originalLength = data.length;
  const bitLength = originalLength * 8;

  // Padding: append 0x80, then zeros, then 64-bit length (little-endian)
  // Total padded length must be multiple of 64 bytes
  const paddedLength = (((originalLength + 8) >>> 6) + 1) << 6;
  const padded = new Uint8Array(paddedLength);
  padded.set(data);
  padded[originalLength] = 0x80;

  // Store 64-bit bit-length in little-endian at the end
  // JavaScript bitwise operators only handle 32 bits, so split into low/high
  storeLittleEndian32(padded, paddedLength - 8, bitLength >>> 0);
  storeLittleEndian32(padded, paddedLength - 4, (bitLength / 0x100000000) >>> 0);

  // Initialize hash values
  let a0 = 0x67452301;
  let b0 = 0xefcdab89;
  let c0 = 0x98badcfe;
  let d0 = 0x10325476;

  // Process each 64-byte block
  const M = new Array<number>(16);
  for (let offset = 0; offset < paddedLength; offset += 64) {
    // Break block into 16 32-bit little-endian words
    for (let j = 0; j < 16; j++) {
      M[j] = toLittleEndian32(padded, offset + j * 4);
    }

    let A = a0;
    let B = b0;
    let C = c0;
    let D = d0;

    for (let i = 0; i < 64; i++) {
      let F: number;
      let g: number;

      if (i < 16) {
        // Round 1: F(B,C,D) = (B & C) | (~B & D)
        F = ((B & C) | ((~B) & D)) >>> 0;
        g = i;
      } else if (i < 32) {
        // Round 2: G(B,C,D) = (B & D) | (C & ~D)
        F = ((D & B) | (C & (~D))) >>> 0;
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        // Round 3: H(B,C,D) = B ^ C ^ D
        F = (B ^ C ^ D) >>> 0;
        g = (3 * i + 5) % 16;
      } else {
        // Round 4: I(B,C,D) = C ^ (B | ~D)
        F = (C ^ (B | (~D))) >>> 0;
        g = (7 * i) % 16;
      }

      const temp = D;
      D = C;
      C = B;
      B = (B + rotateLeft((A + F + T[i] + M[g]) >>> 0, S[i])) >>> 0;
      A = temp;
    }

    a0 = (a0 + A) >>> 0;
    b0 = (b0 + B) >>> 0;
    c0 = (c0 + C) >>> 0;
    d0 = (d0 + D) >>> 0;
  }

  // Produce the 16-byte digest
  const result = new Uint8Array(16);
  storeLittleEndian32(result, 0, a0);
  storeLittleEndian32(result, 4, b0);
  storeLittleEndian32(result, 8, c0);
  storeLittleEndian32(result, 12, d0);
  return result;
}
