/**
 * WinAnsi encoding: maps Unicode code points to WinAnsi character codes (0-255).
 * This covers the Windows-1252 / CP1252 character set used by PDF Type1 fonts.
 */
export const WIN_ANSI_ENCODING: Map<number, number> = new Map();
export const MAC_ROMAN_ENCODING: Map<number, number> = new Map();

// WinAnsi is largely Latin-1 with differences in 0x80-0x9F range
// First, identity mapping for 0x00-0x7F and 0xA0-0xFF
for (let i = 0; i < 128; i++) {
  WIN_ANSI_ENCODING.set(i, i);
}
for (let i = 0xa0; i <= 0xff; i++) {
  WIN_ANSI_ENCODING.set(i, i);
}

// WinAnsi 0x80-0x9F range (Windows-1252 specific mappings)
const winAnsiSpecial: [number, number][] = [
  [0x20AC, 0x80], // Euro sign
  [0x201A, 0x82], // Single low-9 quotation mark
  [0x0192, 0x83], // Latin small f with hook
  [0x201E, 0x84], // Double low-9 quotation mark
  [0x2026, 0x85], // Horizontal ellipsis
  [0x2020, 0x86], // Dagger
  [0x2021, 0x87], // Double dagger
  [0x02C6, 0x88], // Modifier letter circumflex accent
  [0x2030, 0x89], // Per mille sign
  [0x0160, 0x8A], // Latin capital S with caron
  [0x2039, 0x8B], // Single left-pointing angle quotation
  [0x0152, 0x8C], // Latin capital ligature OE
  [0x017D, 0x8E], // Latin capital Z with caron
  [0x2018, 0x91], // Left single quotation mark
  [0x2019, 0x92], // Right single quotation mark
  [0x201C, 0x93], // Left double quotation mark
  [0x201D, 0x94], // Right double quotation mark
  [0x2022, 0x95], // Bullet
  [0x2013, 0x96], // En dash
  [0x2014, 0x97], // Em dash
  [0x02DC, 0x98], // Small tilde
  [0x2122, 0x99], // Trade mark sign
  [0x0161, 0x9A], // Latin small s with caron
  [0x203A, 0x9B], // Single right-pointing angle quotation
  [0x0153, 0x9C], // Latin small ligature oe
  [0x017E, 0x9E], // Latin small z with caron
  [0x0178, 0x9F], // Latin capital Y with diaeresis
];
for (const [unicode, code] of winAnsiSpecial) {
  WIN_ANSI_ENCODING.set(unicode, code);
}

// Mac Roman encoding
const macRomanTable: number[] = [
  // 0x80-0xFF: Mac Roman specific mappings (Unicode code points)
  0x00C4, 0x00C5, 0x00C7, 0x00C9, 0x00D1, 0x00D6, 0x00DC, 0x00E1,
  0x00E0, 0x00E2, 0x00E4, 0x00E3, 0x00E5, 0x00E7, 0x00E9, 0x00E8,
  0x00EA, 0x00EB, 0x00ED, 0x00EC, 0x00EE, 0x00EF, 0x00F1, 0x00F3,
  0x00F2, 0x00F4, 0x00F6, 0x00F5, 0x00FA, 0x00F9, 0x00FB, 0x00FC,
  0x2020, 0x00B0, 0x00A2, 0x00A3, 0x00A7, 0x2022, 0x00B6, 0x00DF,
  0x00AE, 0x00A9, 0x2122, 0x00B4, 0x00A8, 0x2260, 0x00C6, 0x00D8,
  0x221E, 0x00B1, 0x2264, 0x2265, 0x00A5, 0x00B5, 0x2202, 0x2211,
  0x220F, 0x03C0, 0x222B, 0x00AA, 0x00BA, 0x2126, 0x00E6, 0x00F8,
  0x00BF, 0x00A1, 0x00AC, 0x221A, 0x0192, 0x2248, 0x2206, 0x00AB,
  0x00BB, 0x2026, 0x00A0, 0x00C0, 0x00C3, 0x00D5, 0x0152, 0x0153,
  0x2013, 0x2014, 0x201C, 0x201D, 0x2018, 0x2019, 0x00F7, 0x25CA,
  0x00FF, 0x0178, 0x2044, 0x20AC, 0x2039, 0x203A, 0xFB01, 0xFB02,
  0x2021, 0x00B7, 0x201A, 0x201E, 0x2030, 0x00C2, 0x00CA, 0x00C1,
  0x00CB, 0x00C8, 0x00CD, 0x00CE, 0x00CF, 0x00CC, 0x00D3, 0x00D4,
  0xF8FF, 0x00D2, 0x00DA, 0x00DB, 0x00D9, 0x0131, 0x02C6, 0x02DC,
  0x00AF, 0x02D8, 0x02D9, 0x02DA, 0x00B8, 0x02DD, 0x02DB, 0x02C7,
];

// 0x00-0x7F identity mapping for Mac Roman
for (let i = 0; i < 128; i++) {
  MAC_ROMAN_ENCODING.set(i, i);
}
// 0x80-0xFF
for (let i = 0; i < macRomanTable.length; i++) {
  MAC_ROMAN_ENCODING.set(macRomanTable[i], 0x80 + i);
}

/**
 * Encode a string using WinAnsi (Windows-1252) encoding.
 * Characters that cannot be encoded are replaced with '?' (0x3F).
 */
export function encodeWinAnsi(text: string): Uint8Array {
  const result = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) {
    const cp = text.codePointAt(i)!;
    const code = WIN_ANSI_ENCODING.get(cp);
    if (code !== undefined) {
      result[i] = code;
    } else {
      result[i] = 0x3f; // '?'
    }
    // Skip surrogate pair trailing unit
    if (cp > 0xffff) i++;
  }
  return result;
}

/**
 * Encode a string using Mac Roman encoding.
 * Characters that cannot be encoded are replaced with '?' (0x3F).
 */
export function encodeMacRoman(text: string): Uint8Array {
  const result = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) {
    const cp = text.codePointAt(i)!;
    const code = MAC_ROMAN_ENCODING.get(cp);
    if (code !== undefined) {
      result[i] = code;
    } else {
      result[i] = 0x3f;
    }
    if (cp > 0xffff) i++;
  }
  return result;
}

/**
 * Check if all characters in a string can be encoded in WinAnsi.
 */
export function isWinAnsiEncodable(text: string): boolean {
  for (let i = 0; i < text.length; i++) {
    const cp = text.codePointAt(i)!;
    if (!WIN_ANSI_ENCODING.has(cp)) return false;
    if (cp > 0xffff) i++;
  }
  return true;
}
