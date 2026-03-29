import { describe, it, expect } from 'vitest';
import {
  escapePdfString, formatPdfDate, parsePdfDate,
  numberToString, hexEncode, hexDecode,
} from '../../src/utils/string-utils.js';

describe('escapePdfString', () => {
  it('escapes backslash', () => {
    expect(escapePdfString('\\')).toBe('\\\\');
  });

  it('escapes parentheses', () => {
    expect(escapePdfString('(hello)')).toBe('\\(hello\\)');
  });

  it('escapes special whitespace', () => {
    expect(escapePdfString('\r')).toBe('\\r');
    expect(escapePdfString('\n')).toBe('\\n');
    expect(escapePdfString('\t')).toBe('\\t');
    expect(escapePdfString('\b')).toBe('\\b');
    expect(escapePdfString('\f')).toBe('\\f');
  });

  it('leaves regular characters unchanged', () => {
    expect(escapePdfString('Hello World')).toBe('Hello World');
  });

  it('handles mixed content', () => {
    expect(escapePdfString('a(b)c\\d\n')).toBe('a\\(b\\)c\\\\d\\n');
  });
});

describe('formatPdfDate', () => {
  it('formats a date in PDF format', () => {
    // Use a fixed UTC date to avoid timezone issues
    const date = new Date(Date.UTC(2024, 0, 15, 10, 30, 45));
    const result = formatPdfDate(date);
    expect(result).toMatch(/^D:2024/);
    expect(result).toMatch(/\d{4}\d{2}\d{2}\d{2}\d{2}\d{2}[+-]\d{2}'\d{2}'$/);
  });

  it('produces a string starting with D:', () => {
    const result = formatPdfDate(new Date());
    expect(result.startsWith('D:')).toBe(true);
  });
});

describe('parsePdfDate', () => {
  it('parses a full PDF date string', () => {
    const date = parsePdfDate("D:20240115103045+00'00'");
    expect(date).toBeInstanceOf(Date);
    expect(date!.getUTCFullYear()).toBe(2024);
    expect(date!.getUTCMonth()).toBe(0); // January
    expect(date!.getUTCDate()).toBe(15);
    expect(date!.getUTCHours()).toBe(10);
    expect(date!.getUTCMinutes()).toBe(30);
    expect(date!.getUTCSeconds()).toBe(45);
  });

  it('parses date without D: prefix', () => {
    const date = parsePdfDate('20240115103045Z');
    expect(date).toBeInstanceOf(Date);
    expect(date!.getUTCFullYear()).toBe(2024);
  });

  it('parses date with negative timezone offset', () => {
    const date = parsePdfDate("D:20240115103045-05'00'");
    expect(date).toBeInstanceOf(Date);
    // With -05:00 offset, UTC time should be 15:30:45
    expect(date!.getUTCHours()).toBe(15);
  });

  it('parses year-only date', () => {
    const date = parsePdfDate('D:2024');
    expect(date).toBeInstanceOf(Date);
    expect(date!.getUTCFullYear()).toBe(2024);
  });

  it('returns null for invalid input', () => {
    expect(parsePdfDate('D:XX')).toBeNull();
    expect(parsePdfDate('D:ab')).toBeNull();
  });

  it('returns null for too-short input', () => {
    expect(parsePdfDate('D:20')).toBeNull();
  });

  it('round-trips with formatPdfDate', () => {
    const original = new Date(Date.UTC(2024, 5, 15, 12, 0, 0));
    const formatted = formatPdfDate(original);
    const parsed = parsePdfDate(formatted);
    expect(parsed).toBeInstanceOf(Date);
    // Times should match within a second (timezone rounding)
    expect(Math.abs(parsed!.getTime() - original.getTime())).toBeLessThan(1000);
  });
});

describe('numberToString', () => {
  it('formats integers without decimal', () => {
    expect(numberToString(42)).toBe('42');
    expect(numberToString(0)).toBe('0');
    expect(numberToString(-10)).toBe('-10');
  });

  it('formats floats with stripped trailing zeros', () => {
    expect(numberToString(3.14)).toBe('3.14');
    expect(numberToString(1.5)).toBe('1.5');
    expect(numberToString(1.100000)).toBe('1.1');
  });

  it('handles negative zero', () => {
    expect(numberToString(-0)).toBe('0');
  });

  it('strips trailing decimal point', () => {
    expect(numberToString(5.0)).toBe('5');
  });
});

describe('hexEncode', () => {
  it('encodes bytes to uppercase hex', () => {
    expect(hexEncode(new Uint8Array([0x00, 0xFF, 0x0A]))).toBe('00FF0A');
  });

  it('encodes empty array', () => {
    expect(hexEncode(new Uint8Array([]))).toBe('');
  });
});

describe('hexDecode', () => {
  it('decodes hex string to bytes', () => {
    expect(hexDecode('48656C6C6F')).toEqual(new Uint8Array([0x48, 0x65, 0x6C, 0x6C, 0x6F]));
  });

  it('ignores whitespace', () => {
    expect(hexDecode('48 65 6C')).toEqual(new Uint8Array([0x48, 0x65, 0x6C]));
  });

  it('pads odd-length hex with trailing 0 (PDF spec)', () => {
    expect(hexDecode('F')).toEqual(new Uint8Array([0xF0]));
  });

  it('round-trips with hexEncode', () => {
    const data = new Uint8Array([1, 2, 3, 255, 0]);
    expect(hexDecode(hexEncode(data))).toEqual(data);
  });
});
