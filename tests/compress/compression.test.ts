import { describe, it, expect } from 'vitest';
import { deflate, deflateSync, adler32 } from '../../src/compress/deflate.js';
import { inflate, inflateSync } from '../../src/compress/inflate.js';
import { ascii85Encode, ascii85Decode } from '../../src/compress/ascii85.js';
import { asciiHexEncode, asciiHexDecode } from '../../src/compress/ascii-hex.js';
import { runLengthEncode, runLengthDecode } from '../../src/compress/run-length.js';
import { lzwDecode } from '../../src/compress/lzw.js';
import { paethPredictor, applyPredictor, removePredictor } from '../../src/compress/predictor.js';
import { crc32 } from '../../src/utils/crc32.js';

describe('deflate/inflate', () => {
  it('round-trips with async API', async () => {
    const data = new TextEncoder().encode('Hello, World! This is a test of deflate compression.');
    const compressed = await deflate(data);
    const decompressed = await inflate(compressed);
    expect(decompressed).toEqual(data);
  });

  it('round-trips with sync API', () => {
    const data = new TextEncoder().encode('Sync round-trip test data for zlib compression.');
    const compressed = deflateSync(data);
    const decompressed = inflateSync(compressed);
    expect(decompressed).toEqual(data);
  });

  it('compresses and decompresses empty data', async () => {
    const data = new Uint8Array(0);
    const compressed = await deflate(data);
    const decompressed = await inflate(compressed);
    expect(decompressed).toEqual(data);
  });

  it('compresses and decompresses large repetitive data', async () => {
    const data = new Uint8Array(10000);
    for (let i = 0; i < data.length; i++) data[i] = i % 256;
    const compressed = await deflate(data);
    const decompressed = await inflate(compressed);
    expect(decompressed).toEqual(data);
  });
});

describe('adler32', () => {
  it('computes correct checksum for empty data', () => {
    expect(adler32(new Uint8Array(0))).toBe(1);
  });

  it('computes correct checksum for known data', () => {
    // adler32("Wikipedia") = 0x11E60398
    const data = new TextEncoder().encode('Wikipedia');
    expect(adler32(data)).toBe(0x11E60398);
  });
});

describe('ascii85', () => {
  it('encodes and decodes round-trip', () => {
    const data = new TextEncoder().encode('Hello, World!');
    const encoded = ascii85Encode(data);
    const decoded = ascii85Decode(encoded);
    expect(decoded).toEqual(data);
  });

  it('encodes all-zero block as z', () => {
    const data = new Uint8Array(4); // four zero bytes
    const encoded = ascii85Encode(data);
    const str = new TextDecoder().decode(encoded);
    expect(str).toContain('z');
  });

  it('handles partial groups', () => {
    const data = new Uint8Array([1, 2, 3]); // 3 bytes = partial group
    const encoded = ascii85Encode(data);
    const decoded = ascii85Decode(encoded);
    expect(decoded).toEqual(data);
  });

  it('includes <~ ~> delimiters', () => {
    const encoded = ascii85Encode(new Uint8Array([65]));
    const str = new TextDecoder().decode(encoded);
    expect(str.startsWith('<~')).toBe(true);
    expect(str.endsWith('~>')).toBe(true);
  });
});

describe('asciiHex', () => {
  it('encodes bytes to hex with > terminator', () => {
    const encoded = asciiHexEncode(new Uint8Array([0x48, 0x65]));
    const str = new TextDecoder().decode(encoded);
    expect(str).toBe('4865>');
  });

  it('decodes hex string', () => {
    const data = new TextEncoder().encode('48656C6C6F>');
    const decoded = asciiHexDecode(data);
    expect(decoded).toEqual(new Uint8Array([0x48, 0x65, 0x6C, 0x6C, 0x6F]));
  });

  it('round-trips', () => {
    const original = new Uint8Array([0, 127, 255, 128, 1]);
    const decoded = asciiHexDecode(asciiHexEncode(original));
    expect(decoded).toEqual(original);
  });

  it('ignores whitespace in decoding', () => {
    const data = new TextEncoder().encode('48 65\n6C>');
    const decoded = asciiHexDecode(data);
    expect(decoded).toEqual(new Uint8Array([0x48, 0x65, 0x6C]));
  });

  it('handles odd trailing nibble', () => {
    const data = new TextEncoder().encode('F>');
    const decoded = asciiHexDecode(data);
    expect(decoded).toEqual(new Uint8Array([0xF0]));
  });
});

describe('runLength', () => {
  it('encodes and decodes round-trip', () => {
    const data = new Uint8Array([1, 2, 3, 3, 3, 3, 3, 4, 5]);
    const encoded = runLengthEncode(data);
    const decoded = runLengthDecode(encoded);
    expect(decoded).toEqual(data);
  });

  it('handles empty data', () => {
    const encoded = runLengthEncode(new Uint8Array(0));
    expect(encoded).toEqual(new Uint8Array([128])); // EOD only
    const decoded = runLengthDecode(encoded);
    expect(decoded.length).toBe(0);
  });

  it('handles all identical bytes', () => {
    const data = new Uint8Array(10).fill(0xAB);
    const encoded = runLengthEncode(data);
    const decoded = runLengthDecode(encoded);
    expect(decoded).toEqual(data);
  });

  it('handles all unique bytes', () => {
    const data = new Uint8Array([1, 2, 3, 4, 5]);
    const encoded = runLengthEncode(data);
    const decoded = runLengthDecode(encoded);
    expect(decoded).toEqual(data);
  });

  it('ends with EOD marker (128)', () => {
    const encoded = runLengthEncode(new Uint8Array([1]));
    expect(encoded[encoded.length - 1]).toBe(128);
  });
});

describe('lzwDecode', () => {
  it('decodes basic LZW data', () => {
    // LZW-encode a simple sequence manually:
    // Clear code (256), then raw bytes followed by EOD (257).
    // For a trivial test, just verify it doesn't crash on valid input.
    // A proper LZW stream starts with clear code.
    // This is MSB-first with 9-bit codes initially.
    // Let's test that the function exists and handles edge cases.

    // Encode "ABABAB" in LZW:
    // Clear=256, EOD=257, A=65, B=66
    // Codes: 256, 65, 66, 258, 260, 257
    // 258=AB, 259=BA, 260=ABA
    // Actually let's just make sure decode doesn't crash
    // and test with known data from another encoder if available.

    // Instead, test with a simple single-byte input
    // which is: CLEAR(256) + byte(0) + EOD(257)
    // In 9-bit MSB codes: 256=100000000, 0=000000000, 257=100000001
    // Packed into bytes MSB-first:
    // 100000000 000000000 100000001 (pad)
    // 10000000 00000000 00100000 001(00000)
    // = 0x80 0x00 0x20 0x20
    const data = new Uint8Array([0x80, 0x00, 0x20, 0x20]);
    const result = lzwDecode(data);
    expect(result).toEqual(new Uint8Array([0]));
  });
});

describe('crc32', () => {
  it('computes CRC32 for empty data', () => {
    expect(crc32(new Uint8Array(0))).toBe(0);
  });

  it('computes known CRC32 for "123456789"', () => {
    const data = new TextEncoder().encode('123456789');
    // Known CRC32 of "123456789" is 0xCBF43926
    expect(crc32(data)).toBe(0xCBF43926);
  });
});

describe('predictor', () => {
  it('paethPredictor returns correct values', () => {
    expect(paethPredictor(0, 0, 0)).toBe(0);
    expect(paethPredictor(10, 20, 15)).toBe(15); // p=15, pa=5, pb=5, pc=0 -> c
    expect(paethPredictor(0, 100, 0)).toBe(100); // p=100, pa=100, pb=0, pc=100 -> b
  });

  it('predictor 1 is no-op', () => {
    const data = new Uint8Array([1, 2, 3, 4]);
    expect(applyPredictor(data, 1, 4, 1, 8)).toBe(data);
    expect(removePredictor(data, 1, 4, 1, 8)).toBe(data);
  });

  it('PNG None predictor (10) round-trips', () => {
    const data = new Uint8Array([10, 20, 30, 40]);
    const encoded = applyPredictor(data, 10, 4, 1, 8);
    // Each row prefixed with filter type 0
    expect(encoded[0]).toBe(0); // filter type None
    const decoded = removePredictor(encoded, 10, 4, 1, 8);
    expect(decoded).toEqual(data);
  });

  it('PNG Sub predictor (11) round-trips', () => {
    const data = new Uint8Array([10, 20, 30, 40, 50, 60]);
    const encoded = applyPredictor(data, 11, 6, 1, 8);
    const decoded = removePredictor(encoded, 11, 6, 1, 8);
    expect(decoded).toEqual(data);
  });

  it('PNG Up predictor (12) round-trips', () => {
    // Two rows of 3 bytes each
    const data = new Uint8Array([10, 20, 30, 40, 50, 60]);
    const encoded = applyPredictor(data, 12, 3, 1, 8);
    const decoded = removePredictor(encoded, 12, 3, 1, 8);
    expect(decoded).toEqual(data);
  });

  it('PNG Paeth predictor (14) round-trips', () => {
    const data = new Uint8Array([10, 20, 30, 40, 50, 60]);
    const encoded = applyPredictor(data, 14, 3, 1, 8);
    const decoded = removePredictor(encoded, 14, 3, 1, 8);
    expect(decoded).toEqual(data);
  });

  it('PNG Optimum predictor (15) round-trips', () => {
    const data = new Uint8Array([10, 20, 30, 40, 50, 60, 70, 80, 90]);
    const encoded = applyPredictor(data, 15, 3, 1, 8);
    const decoded = removePredictor(encoded, 15, 3, 1, 8);
    expect(decoded).toEqual(data);
  });

  it('throws on unsupported predictor', () => {
    expect(() => applyPredictor(new Uint8Array([1]), 5, 1, 1, 8)).toThrow('Unsupported predictor');
  });
});
