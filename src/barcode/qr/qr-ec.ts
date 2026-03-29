/**
 * QR Code Reed-Solomon error correction in GF(256).
 * Uses the primitive polynomial x^8 + x^4 + x^3 + x^2 + 1 (0x11D).
 */

// GF(256) lookup tables
const GF_EXP = new Uint8Array(512); // antilog table (double size for convenience)
const GF_LOG = new Uint8Array(256); // log table

// Initialize GF(256) tables with primitive polynomial 0x11D
function initGaloisField(): void {
  let x = 1;
  for (let i = 0; i < 255; i++) {
    GF_EXP[i] = x;
    GF_LOG[x] = i;
    x = x << 1;
    if (x & 0x100) {
      x ^= 0x11D; // primitive polynomial: x^8 + x^4 + x^3 + x^2 + 1
    }
  }
  // Extend the antilog table for easier modular arithmetic
  for (let i = 255; i < 512; i++) {
    GF_EXP[i] = GF_EXP[i - 255];
  }
}

initGaloisField();

/**
 * Multiply two values in GF(256).
 */
function gfMul(a: number, b: number): number {
  if (a === 0 || b === 0) return 0;
  return GF_EXP[(GF_LOG[a] + GF_LOG[b]) % 255];
}

/**
 * Compute the generator polynomial for the given number of EC codewords.
 * The generator polynomial is: (x - alpha^0)(x - alpha^1)...(x - alpha^(n-1))
 * Returns coefficients from highest degree to constant term.
 */
function getGeneratorPolynomial(ecCount: number): number[] {
  // Start with (x - alpha^0) = [1, 1]
  let gen = [1];

  for (let i = 0; i < ecCount; i++) {
    // Multiply gen by (x - alpha^i)
    const newGen = new Array(gen.length + 1).fill(0);
    const alphaI = GF_EXP[i];

    for (let j = 0; j < gen.length; j++) {
      newGen[j] ^= gen[j]; // coefficient * x
      newGen[j + 1] ^= gfMul(gen[j], alphaI); // coefficient * alpha^i
    }

    gen = newGen;
  }

  return gen;
}

/**
 * Generate Reed-Solomon error correction codewords.
 * @param data - Array of data codewords
 * @param ecCount - Number of EC codewords to generate
 * @returns Array of EC codewords
 */
export function generateECCodewords(data: number[], ecCount: number): number[] {
  const generator = getGeneratorPolynomial(ecCount);

  // Create working array: data codewords followed by ecCount zeros
  const work = new Array(data.length + ecCount).fill(0);
  for (let i = 0; i < data.length; i++) {
    work[i] = data[i];
  }

  // Polynomial long division
  for (let i = 0; i < data.length; i++) {
    const coef = work[i];
    if (coef === 0) continue;

    for (let j = 0; j < generator.length; j++) {
      work[i + j] ^= gfMul(generator[j], coef);
    }
  }

  // The remainder is the EC codewords
  return work.slice(data.length);
}

/**
 * EC codewords per block table.
 * Format: [version-1][ecLevel] = { ecPerBlock, blocks: [{dataCodewords, count}] }
 */
export interface BlockInfo {
  ecCodewordsPerBlock: number;
  groups: Array<{ count: number; dataCodewords: number }>;
}

/**
 * Get error correction block configuration for a version and EC level.
 */
export function getECBlockInfo(version: number, ecLevel: 'L' | 'M' | 'Q' | 'H'): BlockInfo {
  const ecIdx = { L: 0, M: 1, Q: 2, H: 3 }[ecLevel];
  const info = EC_BLOCKS[version - 1][ecIdx];
  return info;
}

// EC block configurations for versions 1-40, each EC level
// Format: { ecCodewordsPerBlock, groups: [{ count, dataCodewords }] }
const EC_BLOCKS: BlockInfo[][] = [
  // Version 1
  [
    { ecCodewordsPerBlock: 7, groups: [{ count: 1, dataCodewords: 19 }] },
    { ecCodewordsPerBlock: 10, groups: [{ count: 1, dataCodewords: 16 }] },
    { ecCodewordsPerBlock: 13, groups: [{ count: 1, dataCodewords: 13 }] },
    { ecCodewordsPerBlock: 17, groups: [{ count: 1, dataCodewords: 9 }] },
  ],
  // Version 2
  [
    { ecCodewordsPerBlock: 10, groups: [{ count: 1, dataCodewords: 34 }] },
    { ecCodewordsPerBlock: 16, groups: [{ count: 1, dataCodewords: 28 }] },
    { ecCodewordsPerBlock: 22, groups: [{ count: 1, dataCodewords: 22 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 1, dataCodewords: 16 }] },
  ],
  // Version 3
  [
    { ecCodewordsPerBlock: 15, groups: [{ count: 1, dataCodewords: 55 }] },
    { ecCodewordsPerBlock: 26, groups: [{ count: 1, dataCodewords: 44 }] },
    { ecCodewordsPerBlock: 18, groups: [{ count: 2, dataCodewords: 17 }] },
    { ecCodewordsPerBlock: 22, groups: [{ count: 2, dataCodewords: 13 }] },
  ],
  // Version 4
  [
    { ecCodewordsPerBlock: 20, groups: [{ count: 1, dataCodewords: 80 }] },
    { ecCodewordsPerBlock: 18, groups: [{ count: 2, dataCodewords: 32 }] },
    { ecCodewordsPerBlock: 26, groups: [{ count: 2, dataCodewords: 24 }] },
    { ecCodewordsPerBlock: 16, groups: [{ count: 4, dataCodewords: 9 }] },
  ],
  // Version 5
  [
    { ecCodewordsPerBlock: 26, groups: [{ count: 1, dataCodewords: 108 }] },
    { ecCodewordsPerBlock: 24, groups: [{ count: 2, dataCodewords: 43 }] },
    { ecCodewordsPerBlock: 18, groups: [{ count: 2, dataCodewords: 15 }, { count: 2, dataCodewords: 16 }] },
    { ecCodewordsPerBlock: 22, groups: [{ count: 2, dataCodewords: 11 }, { count: 2, dataCodewords: 12 }] },
  ],
  // Version 6
  [
    { ecCodewordsPerBlock: 18, groups: [{ count: 2, dataCodewords: 68 }] },
    { ecCodewordsPerBlock: 16, groups: [{ count: 4, dataCodewords: 27 }] },
    { ecCodewordsPerBlock: 24, groups: [{ count: 4, dataCodewords: 19 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 4, dataCodewords: 15 }] },
  ],
  // Version 7
  [
    { ecCodewordsPerBlock: 20, groups: [{ count: 2, dataCodewords: 78 }] },
    { ecCodewordsPerBlock: 18, groups: [{ count: 4, dataCodewords: 31 }] },
    { ecCodewordsPerBlock: 18, groups: [{ count: 2, dataCodewords: 14 }, { count: 4, dataCodewords: 15 }] },
    { ecCodewordsPerBlock: 26, groups: [{ count: 4, dataCodewords: 13 }, { count: 1, dataCodewords: 14 }] },
  ],
  // Version 8
  [
    { ecCodewordsPerBlock: 24, groups: [{ count: 2, dataCodewords: 97 }] },
    { ecCodewordsPerBlock: 22, groups: [{ count: 2, dataCodewords: 38 }, { count: 2, dataCodewords: 39 }] },
    { ecCodewordsPerBlock: 22, groups: [{ count: 4, dataCodewords: 18 }, { count: 2, dataCodewords: 19 }] },
    { ecCodewordsPerBlock: 26, groups: [{ count: 4, dataCodewords: 14 }, { count: 2, dataCodewords: 15 }] },
  ],
  // Version 9
  [
    { ecCodewordsPerBlock: 30, groups: [{ count: 2, dataCodewords: 116 }] },
    { ecCodewordsPerBlock: 22, groups: [{ count: 3, dataCodewords: 36 }, { count: 2, dataCodewords: 37 }] },
    { ecCodewordsPerBlock: 20, groups: [{ count: 4, dataCodewords: 16 }, { count: 4, dataCodewords: 17 }] },
    { ecCodewordsPerBlock: 24, groups: [{ count: 4, dataCodewords: 12 }, { count: 4, dataCodewords: 13 }] },
  ],
  // Version 10
  [
    { ecCodewordsPerBlock: 18, groups: [{ count: 2, dataCodewords: 68 }, { count: 2, dataCodewords: 69 }] },
    { ecCodewordsPerBlock: 26, groups: [{ count: 4, dataCodewords: 43 }, { count: 1, dataCodewords: 44 }] },
    { ecCodewordsPerBlock: 24, groups: [{ count: 6, dataCodewords: 19 }, { count: 2, dataCodewords: 20 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 6, dataCodewords: 15 }, { count: 2, dataCodewords: 16 }] },
  ],
  // Version 11
  [
    { ecCodewordsPerBlock: 20, groups: [{ count: 4, dataCodewords: 81 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 1, dataCodewords: 50 }, { count: 4, dataCodewords: 51 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 4, dataCodewords: 22 }, { count: 4, dataCodewords: 23 }] },
    { ecCodewordsPerBlock: 24, groups: [{ count: 3, dataCodewords: 12 }, { count: 8, dataCodewords: 13 }] },
  ],
  // Version 12
  [
    { ecCodewordsPerBlock: 24, groups: [{ count: 2, dataCodewords: 92 }, { count: 2, dataCodewords: 93 }] },
    { ecCodewordsPerBlock: 22, groups: [{ count: 6, dataCodewords: 36 }, { count: 2, dataCodewords: 37 }] },
    { ecCodewordsPerBlock: 26, groups: [{ count: 4, dataCodewords: 20 }, { count: 6, dataCodewords: 21 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 7, dataCodewords: 14 }, { count: 4, dataCodewords: 15 }] },
  ],
  // Version 13
  [
    { ecCodewordsPerBlock: 26, groups: [{ count: 4, dataCodewords: 107 }] },
    { ecCodewordsPerBlock: 22, groups: [{ count: 8, dataCodewords: 37 }, { count: 1, dataCodewords: 38 }] },
    { ecCodewordsPerBlock: 24, groups: [{ count: 8, dataCodewords: 20 }, { count: 4, dataCodewords: 21 }] },
    { ecCodewordsPerBlock: 22, groups: [{ count: 12, dataCodewords: 11 }, { count: 4, dataCodewords: 12 }] },
  ],
  // Version 14
  [
    { ecCodewordsPerBlock: 30, groups: [{ count: 3, dataCodewords: 115 }, { count: 1, dataCodewords: 116 }] },
    { ecCodewordsPerBlock: 24, groups: [{ count: 4, dataCodewords: 40 }, { count: 5, dataCodewords: 41 }] },
    { ecCodewordsPerBlock: 20, groups: [{ count: 11, dataCodewords: 16 }, { count: 5, dataCodewords: 17 }] },
    { ecCodewordsPerBlock: 24, groups: [{ count: 11, dataCodewords: 12 }, { count: 5, dataCodewords: 13 }] },
  ],
  // Version 15
  [
    { ecCodewordsPerBlock: 22, groups: [{ count: 5, dataCodewords: 87 }, { count: 1, dataCodewords: 88 }] },
    { ecCodewordsPerBlock: 24, groups: [{ count: 5, dataCodewords: 41 }, { count: 5, dataCodewords: 42 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 5, dataCodewords: 24 }, { count: 7, dataCodewords: 25 }] },
    { ecCodewordsPerBlock: 24, groups: [{ count: 11, dataCodewords: 12 }, { count: 7, dataCodewords: 13 }] },
  ],
  // Version 16
  [
    { ecCodewordsPerBlock: 24, groups: [{ count: 5, dataCodewords: 98 }, { count: 1, dataCodewords: 99 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 7, dataCodewords: 45 }, { count: 3, dataCodewords: 46 }] },
    { ecCodewordsPerBlock: 24, groups: [{ count: 15, dataCodewords: 19 }, { count: 2, dataCodewords: 20 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 3, dataCodewords: 15 }, { count: 13, dataCodewords: 16 }] },
  ],
  // Version 17
  [
    { ecCodewordsPerBlock: 28, groups: [{ count: 1, dataCodewords: 107 }, { count: 5, dataCodewords: 108 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 10, dataCodewords: 46 }, { count: 1, dataCodewords: 47 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 1, dataCodewords: 22 }, { count: 15, dataCodewords: 23 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 2, dataCodewords: 14 }, { count: 17, dataCodewords: 15 }] },
  ],
  // Version 18
  [
    { ecCodewordsPerBlock: 30, groups: [{ count: 5, dataCodewords: 120 }, { count: 1, dataCodewords: 121 }] },
    { ecCodewordsPerBlock: 26, groups: [{ count: 9, dataCodewords: 43 }, { count: 4, dataCodewords: 44 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 17, dataCodewords: 22 }, { count: 1, dataCodewords: 23 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 2, dataCodewords: 14 }, { count: 19, dataCodewords: 15 }] },
  ],
  // Version 19
  [
    { ecCodewordsPerBlock: 28, groups: [{ count: 3, dataCodewords: 113 }, { count: 4, dataCodewords: 114 }] },
    { ecCodewordsPerBlock: 26, groups: [{ count: 3, dataCodewords: 44 }, { count: 11, dataCodewords: 45 }] },
    { ecCodewordsPerBlock: 26, groups: [{ count: 17, dataCodewords: 21 }, { count: 4, dataCodewords: 22 }] },
    { ecCodewordsPerBlock: 26, groups: [{ count: 9, dataCodewords: 13 }, { count: 16, dataCodewords: 14 }] },
  ],
  // Version 20
  [
    { ecCodewordsPerBlock: 28, groups: [{ count: 3, dataCodewords: 107 }, { count: 5, dataCodewords: 108 }] },
    { ecCodewordsPerBlock: 26, groups: [{ count: 3, dataCodewords: 41 }, { count: 13, dataCodewords: 42 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 15, dataCodewords: 24 }, { count: 5, dataCodewords: 25 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 15, dataCodewords: 15 }, { count: 10, dataCodewords: 16 }] },
  ],
  // Version 21
  [
    { ecCodewordsPerBlock: 28, groups: [{ count: 4, dataCodewords: 116 }, { count: 4, dataCodewords: 117 }] },
    { ecCodewordsPerBlock: 26, groups: [{ count: 17, dataCodewords: 42 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 17, dataCodewords: 22 }, { count: 6, dataCodewords: 23 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 19, dataCodewords: 16 }, { count: 6, dataCodewords: 17 }] },
  ],
  // Version 22
  [
    { ecCodewordsPerBlock: 28, groups: [{ count: 2, dataCodewords: 111 }, { count: 7, dataCodewords: 112 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 17, dataCodewords: 46 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 7, dataCodewords: 24 }, { count: 16, dataCodewords: 25 }] },
    { ecCodewordsPerBlock: 24, groups: [{ count: 34, dataCodewords: 13 }] },
  ],
  // Version 23
  [
    { ecCodewordsPerBlock: 30, groups: [{ count: 4, dataCodewords: 121 }, { count: 5, dataCodewords: 122 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 4, dataCodewords: 47 }, { count: 14, dataCodewords: 48 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 11, dataCodewords: 24 }, { count: 14, dataCodewords: 25 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 16, dataCodewords: 15 }, { count: 14, dataCodewords: 16 }] },
  ],
  // Version 24
  [
    { ecCodewordsPerBlock: 30, groups: [{ count: 6, dataCodewords: 117 }, { count: 4, dataCodewords: 118 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 6, dataCodewords: 45 }, { count: 14, dataCodewords: 46 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 11, dataCodewords: 24 }, { count: 16, dataCodewords: 25 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 30, dataCodewords: 16 }, { count: 2, dataCodewords: 17 }] },
  ],
  // Version 25
  [
    { ecCodewordsPerBlock: 26, groups: [{ count: 8, dataCodewords: 106 }, { count: 4, dataCodewords: 107 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 8, dataCodewords: 47 }, { count: 13, dataCodewords: 48 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 7, dataCodewords: 24 }, { count: 22, dataCodewords: 25 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 22, dataCodewords: 15 }, { count: 13, dataCodewords: 16 }] },
  ],
  // Version 26
  [
    { ecCodewordsPerBlock: 28, groups: [{ count: 10, dataCodewords: 114 }, { count: 2, dataCodewords: 115 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 19, dataCodewords: 46 }, { count: 4, dataCodewords: 47 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 28, dataCodewords: 22 }, { count: 6, dataCodewords: 23 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 33, dataCodewords: 16 }, { count: 4, dataCodewords: 17 }] },
  ],
  // Version 27
  [
    { ecCodewordsPerBlock: 30, groups: [{ count: 8, dataCodewords: 122 }, { count: 4, dataCodewords: 123 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 22, dataCodewords: 45 }, { count: 3, dataCodewords: 46 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 8, dataCodewords: 23 }, { count: 26, dataCodewords: 24 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 12, dataCodewords: 15 }, { count: 28, dataCodewords: 16 }] },
  ],
  // Version 28
  [
    { ecCodewordsPerBlock: 30, groups: [{ count: 3, dataCodewords: 117 }, { count: 10, dataCodewords: 118 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 3, dataCodewords: 45 }, { count: 23, dataCodewords: 46 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 4, dataCodewords: 24 }, { count: 31, dataCodewords: 25 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 11, dataCodewords: 15 }, { count: 31, dataCodewords: 16 }] },
  ],
  // Version 29
  [
    { ecCodewordsPerBlock: 30, groups: [{ count: 7, dataCodewords: 116 }, { count: 7, dataCodewords: 117 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 21, dataCodewords: 45 }, { count: 7, dataCodewords: 46 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 1, dataCodewords: 23 }, { count: 37, dataCodewords: 24 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 19, dataCodewords: 15 }, { count: 26, dataCodewords: 16 }] },
  ],
  // Version 30
  [
    { ecCodewordsPerBlock: 30, groups: [{ count: 5, dataCodewords: 115 }, { count: 10, dataCodewords: 116 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 19, dataCodewords: 47 }, { count: 10, dataCodewords: 48 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 15, dataCodewords: 24 }, { count: 25, dataCodewords: 25 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 23, dataCodewords: 15 }, { count: 25, dataCodewords: 16 }] },
  ],
  // Version 31
  [
    { ecCodewordsPerBlock: 30, groups: [{ count: 13, dataCodewords: 115 }, { count: 3, dataCodewords: 116 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 2, dataCodewords: 46 }, { count: 29, dataCodewords: 47 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 42, dataCodewords: 24 }, { count: 1, dataCodewords: 25 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 23, dataCodewords: 15 }, { count: 28, dataCodewords: 16 }] },
  ],
  // Version 32
  [
    { ecCodewordsPerBlock: 30, groups: [{ count: 17, dataCodewords: 115 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 10, dataCodewords: 46 }, { count: 23, dataCodewords: 47 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 10, dataCodewords: 24 }, { count: 35, dataCodewords: 25 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 19, dataCodewords: 15 }, { count: 35, dataCodewords: 16 }] },
  ],
  // Version 33
  [
    { ecCodewordsPerBlock: 30, groups: [{ count: 17, dataCodewords: 115 }, { count: 1, dataCodewords: 116 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 14, dataCodewords: 46 }, { count: 21, dataCodewords: 47 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 29, dataCodewords: 24 }, { count: 19, dataCodewords: 25 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 11, dataCodewords: 15 }, { count: 46, dataCodewords: 16 }] },
  ],
  // Version 34
  [
    { ecCodewordsPerBlock: 30, groups: [{ count: 13, dataCodewords: 115 }, { count: 6, dataCodewords: 116 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 14, dataCodewords: 46 }, { count: 23, dataCodewords: 47 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 44, dataCodewords: 24 }, { count: 7, dataCodewords: 25 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 59, dataCodewords: 16 }, { count: 1, dataCodewords: 17 }] },
  ],
  // Version 35
  [
    { ecCodewordsPerBlock: 30, groups: [{ count: 12, dataCodewords: 121 }, { count: 7, dataCodewords: 122 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 12, dataCodewords: 47 }, { count: 26, dataCodewords: 48 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 39, dataCodewords: 24 }, { count: 14, dataCodewords: 25 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 22, dataCodewords: 15 }, { count: 41, dataCodewords: 16 }] },
  ],
  // Version 36
  [
    { ecCodewordsPerBlock: 30, groups: [{ count: 6, dataCodewords: 121 }, { count: 14, dataCodewords: 122 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 6, dataCodewords: 47 }, { count: 34, dataCodewords: 48 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 46, dataCodewords: 24 }, { count: 10, dataCodewords: 25 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 2, dataCodewords: 15 }, { count: 64, dataCodewords: 16 }] },
  ],
  // Version 37
  [
    { ecCodewordsPerBlock: 30, groups: [{ count: 17, dataCodewords: 122 }, { count: 4, dataCodewords: 123 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 29, dataCodewords: 46 }, { count: 14, dataCodewords: 47 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 49, dataCodewords: 24 }, { count: 10, dataCodewords: 25 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 24, dataCodewords: 15 }, { count: 46, dataCodewords: 16 }] },
  ],
  // Version 38
  [
    { ecCodewordsPerBlock: 30, groups: [{ count: 4, dataCodewords: 122 }, { count: 18, dataCodewords: 123 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 13, dataCodewords: 46 }, { count: 32, dataCodewords: 47 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 48, dataCodewords: 24 }, { count: 14, dataCodewords: 25 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 42, dataCodewords: 15 }, { count: 32, dataCodewords: 16 }] },
  ],
  // Version 39
  [
    { ecCodewordsPerBlock: 30, groups: [{ count: 20, dataCodewords: 117 }, { count: 4, dataCodewords: 118 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 40, dataCodewords: 47 }, { count: 7, dataCodewords: 48 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 43, dataCodewords: 24 }, { count: 22, dataCodewords: 25 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 10, dataCodewords: 15 }, { count: 67, dataCodewords: 16 }] },
  ],
  // Version 40
  [
    { ecCodewordsPerBlock: 30, groups: [{ count: 19, dataCodewords: 118 }, { count: 6, dataCodewords: 119 }] },
    { ecCodewordsPerBlock: 28, groups: [{ count: 18, dataCodewords: 47 }, { count: 31, dataCodewords: 48 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 34, dataCodewords: 24 }, { count: 34, dataCodewords: 25 }] },
    { ecCodewordsPerBlock: 30, groups: [{ count: 20, dataCodewords: 15 }, { count: 61, dataCodewords: 16 }] },
  ],
];
