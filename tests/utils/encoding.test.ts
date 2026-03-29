import { describe, it, expect } from 'vitest';
import {
  latin1Encode, latin1Decode,
  utf16BEEncode, utf16BEDecode,
  pdfDocEncodingDecode,
  isAscii, textToUtf16BEHex,
} from '../../src/utils/encoding.js';

describe('latin1Encode', () => {
  it('encodes ASCII string', () => {
    expect(latin1Encode('ABC')).toEqual(new Uint8Array([65, 66, 67]));
  });

  it('encodes empty string', () => {
    expect(latin1Encode('')).toEqual(new Uint8Array([]));
  });

  it('masks to lower 8 bits', () => {
    const result = latin1Encode('\u0100'); // 256 -> 0
    expect(result[0]).toBe(0);
  });
});

describe('latin1Decode', () => {
  it('decodes bytes to string', () => {
    expect(latin1Decode(new Uint8Array([72, 101, 108, 108, 111]))).toBe('Hello');
  });

  it('decodes empty array', () => {
    expect(latin1Decode(new Uint8Array([]))).toBe('');
  });

  it('round-trips with encode', () => {
    const text = 'Test 123!';
    expect(latin1Decode(latin1Encode(text))).toBe(text);
  });
});

describe('utf16BEEncode', () => {
  it('encodes with BOM', () => {
    const result = utf16BEEncode('A');
    expect(result[0]).toBe(0xFE);
    expect(result[1]).toBe(0xFF);
    expect(result[2]).toBe(0x00);
    expect(result[3]).toBe(0x41);
    expect(result.length).toBe(4);
  });

  it('encodes multi-byte characters', () => {
    const result = utf16BEEncode('\u00E9'); // e-acute
    expect(result.length).toBe(4);
    expect(result[2]).toBe(0x00);
    expect(result[3]).toBe(0xE9);
  });

  it('encodes empty string', () => {
    const result = utf16BEEncode('');
    expect(result.length).toBe(2); // BOM only
    expect(result[0]).toBe(0xFE);
    expect(result[1]).toBe(0xFF);
  });
});

describe('utf16BEDecode', () => {
  it('decodes with BOM', () => {
    const encoded = utf16BEEncode('Hello');
    expect(utf16BEDecode(encoded)).toBe('Hello');
  });

  it('decodes without BOM', () => {
    const bytes = new Uint8Array([0x00, 0x41, 0x00, 0x42]);
    expect(utf16BEDecode(bytes)).toBe('AB');
  });

  it('round-trips encode/decode', () => {
    const text = 'Unicode: \u00E9\u00F1\u00FC';
    expect(utf16BEDecode(utf16BEEncode(text))).toBe(text);
  });
});

describe('pdfDocEncodingDecode', () => {
  it('decodes ASCII range', () => {
    expect(pdfDocEncodingDecode(new Uint8Array([65, 66, 67]))).toBe('ABC');
  });

  it('decodes PDFDocEncoding special characters', () => {
    // 0x80 -> U+2022 BULLET
    expect(pdfDocEncodingDecode(new Uint8Array([0x80]))).toBe('\u2022');
    // 0x84 -> U+2014 EM DASH
    expect(pdfDocEncodingDecode(new Uint8Array([0x84]))).toBe('\u2014');
    // 0x92 -> U+2122 TRADE MARK SIGN
    expect(pdfDocEncodingDecode(new Uint8Array([0x92]))).toBe('\u2122');
    // 0xA0 -> U+20AC EURO SIGN
    expect(pdfDocEncodingDecode(new Uint8Array([0xA0]))).toBe('\u20AC');
  });

  it('falls back to Latin-1 for unmapped bytes', () => {
    // 0xC0 is not in the special map, should use Latin-1 identity
    expect(pdfDocEncodingDecode(new Uint8Array([0xC0]))).toBe('\u00C0');
  });
});

describe('isAscii', () => {
  it('returns true for ASCII-only strings', () => {
    expect(isAscii('Hello World 123!')).toBe(true);
  });

  it('returns true for empty string', () => {
    expect(isAscii('')).toBe(true);
  });

  it('returns false for non-ASCII', () => {
    expect(isAscii('\u00E9')).toBe(false);
    expect(isAscii('\x7F')).toBe(false); // DEL is > 0x7E
  });

  it('returns true for tilde (0x7E boundary)', () => {
    expect(isAscii('~')).toBe(true);
  });
});

describe('textToUtf16BEHex', () => {
  it('encodes to uppercase hex with BOM', () => {
    const result = textToUtf16BEHex('A');
    expect(result).toBe('FEFF0041');
  });

  it('encodes multiple characters', () => {
    const result = textToUtf16BEHex('AB');
    expect(result).toBe('FEFF00410042');
  });
});
