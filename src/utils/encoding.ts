/**
 * PDF string encoding utilities.
 */

export function latin1Encode(s: string): Uint8Array {
  const result = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) {
    result[i] = s.charCodeAt(i) & 0xff;
  }
  return result;
}

export function latin1Decode(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i++) {
    s += String.fromCharCode(bytes[i]);
  }
  return s;
}

export function utf16BEEncode(s: string): Uint8Array {
  // BOM (0xFE, 0xFF) + 2 bytes per code unit
  const codeUnits: number[] = [];
  for (let i = 0; i < s.length; i++) {
    const code = s.charCodeAt(i);
    codeUnits.push(code);
  }
  const result = new Uint8Array(2 + codeUnits.length * 2);
  result[0] = 0xfe;
  result[1] = 0xff;
  for (let i = 0; i < codeUnits.length; i++) {
    result[2 + i * 2] = (codeUnits[i] >>> 8) & 0xff;
    result[2 + i * 2 + 1] = codeUnits[i] & 0xff;
  }
  return result;
}

export function utf16BEDecode(bytes: Uint8Array): string {
  let offset = 0;
  // Skip BOM if present
  if (bytes.length >= 2 && bytes[0] === 0xfe && bytes[1] === 0xff) {
    offset = 2;
  }
  let s = '';
  for (let i = offset; i + 1 < bytes.length; i += 2) {
    const code = (bytes[i] << 8) | bytes[i + 1];
    s += String.fromCharCode(code);
  }
  return s;
}

/**
 * PDFDocEncoding to Unicode mapping for bytes 0x80-0xFF that differ from Latin-1.
 * Unmapped entries use 0xFFFD (replacement character).
 */
const PDF_DOC_ENCODING_MAP: Record<number, number> = {
  0x80: 0x2022, // BULLET
  0x81: 0x2020, // DAGGER
  0x82: 0x2021, // DOUBLE DAGGER
  0x83: 0x2026, // HORIZONTAL ELLIPSIS
  0x84: 0x2014, // EM DASH
  0x85: 0x2013, // EN DASH
  0x86: 0x0192, // LATIN SMALL LETTER F WITH HOOK
  0x87: 0x2044, // FRACTION SLASH
  0x88: 0x2039, // SINGLE LEFT-POINTING ANGLE QUOTATION MARK
  0x89: 0x203a, // SINGLE RIGHT-POINTING ANGLE QUOTATION MARK
  0x8a: 0x2212, // MINUS SIGN
  0x8b: 0x2030, // PER MILLE SIGN
  0x8c: 0x201e, // DOUBLE LOW-9 QUOTATION MARK
  0x8d: 0x201c, // LEFT DOUBLE QUOTATION MARK
  0x8e: 0x201d, // RIGHT DOUBLE QUOTATION MARK
  0x8f: 0x2018, // LEFT SINGLE QUOTATION MARK
  0x90: 0x2019, // RIGHT SINGLE QUOTATION MARK
  0x91: 0x201a, // SINGLE LOW-9 QUOTATION MARK
  0x92: 0x2122, // TRADE MARK SIGN
  0x93: 0xfb01, // LATIN SMALL LIGATURE FI
  0x94: 0xfb02, // LATIN SMALL LIGATURE FL
  0x95: 0x0141, // LATIN CAPITAL LETTER L WITH STROKE
  0x96: 0x0152, // LATIN CAPITAL LIGATURE OE
  0x97: 0x0160, // LATIN CAPITAL LETTER S WITH CARON
  0x98: 0x0178, // LATIN CAPITAL LETTER Y WITH DIAERESIS
  0x99: 0x017d, // LATIN CAPITAL LETTER Z WITH CARON
  0x9a: 0x0131, // LATIN SMALL LETTER DOTLESS I
  0x9b: 0x0142, // LATIN SMALL LETTER L WITH STROKE
  0x9c: 0x0153, // LATIN SMALL LIGATURE OE
  0x9d: 0x0161, // LATIN SMALL LETTER S WITH CARON
  0x9e: 0x017e, // LATIN SMALL LETTER Z WITH CARON
  0xa0: 0x20ac, // EURO SIGN
};

export function pdfDocEncodingDecode(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i++) {
    const b = bytes[i];
    if (b < 0x80) {
      s += String.fromCharCode(b);
    } else if (b in PDF_DOC_ENCODING_MAP) {
      s += String.fromCharCode(PDF_DOC_ENCODING_MAP[b]);
    } else {
      // For bytes 0x80-0xFF not in the map, use Latin-1 identity mapping
      s += String.fromCharCode(b);
    }
  }
  return s;
}

export function isAscii(s: string): boolean {
  for (let i = 0; i < s.length; i++) {
    if (s.charCodeAt(i) > 0x7e) return false;
  }
  return true;
}

export function textToUtf16BEHex(s: string): string {
  const bytes = utf16BEEncode(s);
  let hex = '';
  for (let i = 0; i < bytes.length; i++) {
    hex += bytes[i].toString(16).padStart(2, '0').toUpperCase();
  }
  return hex;
}
