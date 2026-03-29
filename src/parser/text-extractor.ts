/**
 * Extract text from parsed PDF content stream operations.
 * Tracks graphics state, text state, and font encodings
 * to produce positioned text items.
 */

import type { PdfObject, PdfDict, PdfStream, PdfRef } from '../core/types.js';
import {
  dictGet, dictGetName, dictGetNumber, dictGetRef, dictGetArray, dictGetDict,
  isRef, isDict, isName, isNumber, isString, isStream, isArray,
} from '../core/objects.js';
import type { ContentOperation } from './content-stream-parser.js';
import type { ObjectStore } from '../core/object-store.js';
import { decodeStream } from './stream-decoder.js';

export interface ExtractedTextItem {
  text: string;
  x: number;
  y: number;
  width: number;
  fontSize: number;
  fontName: string;
}

/** 6-element affine matrix [a, b, c, d, e, f] */
type Matrix = [number, number, number, number, number, number];

function identityMatrix(): Matrix {
  return [1, 0, 0, 1, 0, 0];
}

function multiplyMatrix(a: Matrix, b: Matrix): Matrix {
  return [
    a[0] * b[0] + a[1] * b[2],
    a[0] * b[1] + a[1] * b[3],
    a[2] * b[0] + a[3] * b[2],
    a[2] * b[1] + a[3] * b[3],
    a[4] * b[0] + a[5] * b[2] + b[4],
    a[4] * b[1] + a[5] * b[3] + b[5],
  ];
}

function transformPoint(m: Matrix, x: number, y: number): [number, number] {
  return [
    m[0] * x + m[2] * y + m[4],
    m[1] * x + m[3] * y + m[5],
  ];
}

interface TextState {
  fontName: string;
  fontSize: number;
  charSpacing: number;
  wordSpacing: number;
  horizontalScale: number; // percentage, default 100
  leading: number;
  rise: number;
  renderMode: number;
}

interface GraphicsState {
  ctm: Matrix;
  textState: TextState;
}

function cloneTextState(ts: TextState): TextState {
  return { ...ts };
}

function cloneGraphicsState(gs: GraphicsState): GraphicsState {
  return {
    ctm: [...gs.ctm] as Matrix,
    textState: cloneTextState(gs.textState),
  };
}

/**
 * Resolve a PdfObject, following indirect references.
 */
function resolve(obj: PdfObject | undefined, store: ObjectStore): PdfObject | undefined {
  if (!obj) return undefined;
  if (isRef(obj)) {
    const resolved = store.get(obj);
    return resolved;
  }
  return obj;
}

/**
 * Parse a /ToUnicode CMap to build a character code -> unicode string mapping.
 */
async function parseToUnicodeCMap(
  cmapObj: PdfObject | undefined,
  store: ObjectStore,
): Promise<Map<number, string> | null> {
  if (!cmapObj) return null;

  const resolved = resolve(cmapObj, store);
  if (!resolved) return null;

  let cmapData: Uint8Array;
  if (isStream(resolved)) {
    cmapData = await decodeStream(resolved);
  } else {
    return null;
  }

  const text = new TextDecoder('latin1').decode(cmapData);
  const map = new Map<number, string>();

  // Parse beginbfchar ... endbfchar sections
  const bfcharRegex = /beginbfchar\s*([\s\S]*?)\s*endbfchar/g;
  let match: RegExpExecArray | null;
  while ((match = bfcharRegex.exec(text)) !== null) {
    const block = match[1];
    const lineRegex = /<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>/g;
    let lineMatch: RegExpExecArray | null;
    while ((lineMatch = lineRegex.exec(block)) !== null) {
      const srcCode = parseInt(lineMatch[1], 16);
      const dstHex = lineMatch[2];
      const unicode = hexToUnicode(dstHex);
      map.set(srcCode, unicode);
    }
  }

  // Parse beginbfrange ... endbfrange sections
  const bfrangeRegex = /beginbfrange\s*([\s\S]*?)\s*endbfrange/g;
  while ((match = bfrangeRegex.exec(text)) !== null) {
    const block = match[1];
    // Two forms:
    // <start> <end> <dstStart>
    // <start> <end> [<dst1> <dst2> ...]
    const rangeRegex = /<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(?:<([0-9A-Fa-f]+)>|\[([\s\S]*?)\])/g;
    let rangeMatch: RegExpExecArray | null;
    while ((rangeMatch = rangeRegex.exec(block)) !== null) {
      const start = parseInt(rangeMatch[1], 16);
      const end = parseInt(rangeMatch[2], 16);

      if (rangeMatch[3] !== undefined) {
        // Single destination start
        let dstCode = parseInt(rangeMatch[3], 16);
        for (let code = start; code <= end; code++) {
          map.set(code, String.fromCodePoint(dstCode));
          dstCode++;
        }
      } else if (rangeMatch[4] !== undefined) {
        // Array of destinations
        const dstArr = rangeMatch[4];
        const dstRegex = /<([0-9A-Fa-f]+)>/g;
        let dstMatch: RegExpExecArray | null;
        let code = start;
        while ((dstMatch = dstRegex.exec(dstArr)) !== null && code <= end) {
          map.set(code, hexToUnicode(dstMatch[1]));
          code++;
        }
      }
    }
  }

  return map.size > 0 ? map : null;
}

function hexToUnicode(hex: string): string {
  let result = '';
  // UTF-16BE pairs
  for (let i = 0; i < hex.length; i += 4) {
    const chunk = hex.substring(i, Math.min(i + 4, hex.length));
    const codePoint = parseInt(chunk, 16);
    if (!isNaN(codePoint) && codePoint > 0) {
      result += String.fromCodePoint(codePoint);
    }
  }
  return result || '\ufffd';
}

/**
 * Build a character code to unicode mapping from a font's /Encoding and /Differences.
 */
function buildEncodingMap(
  fontDict: PdfDict | PdfStream,
  store: ObjectStore,
): Map<number, string> | null {
  const encodingObj = resolve(dictGet(fontDict, 'Encoding'), store);
  if (!encodingObj) return null;

  const map = new Map<number, string>();

  // Standard base encoding
  let baseEncoding: string | undefined;
  if (isName(encodingObj)) {
    baseEncoding = encodingObj.value;
  } else if (isDict(encodingObj)) {
    const beName = dictGetName(encodingObj, 'BaseEncoding');
    if (beName) baseEncoding = beName;

    // Process /Differences array
    const diffs = dictGetArray(encodingObj, 'Differences');
    if (diffs) {
      let code = 0;
      for (const item of diffs) {
        if (isNumber(item)) {
          code = item.value;
        } else if (isName(item)) {
          const unicode = glyphNameToUnicode(item.value);
          if (unicode) {
            map.set(code, unicode);
          }
          code++;
        }
      }
    }
  }

  // For WinAnsiEncoding base, fill in standard mapping if no differences override
  if (baseEncoding === 'WinAnsiEncoding') {
    for (let i = 0; i < 256; i++) {
      if (!map.has(i)) {
        // Windows-1252 mapping
        const ch = cp1252ToUnicode(i);
        if (ch) map.set(i, ch);
      }
    }
  } else if (baseEncoding === 'MacRomanEncoding') {
    for (let i = 0; i < 256; i++) {
      if (!map.has(i)) {
        const ch = macRomanToUnicode(i);
        if (ch) map.set(i, ch);
      }
    }
  }

  return map.size > 0 ? map : null;
}

/**
 * Map a PostScript glyph name to its Unicode character.
 * Only a subset of common names is handled.
 */
function glyphNameToUnicode(name: string): string | null {
  // Common glyph names
  const commonGlyphs: Record<string, number> = {
    space: 0x0020, exclam: 0x0021, quotedbl: 0x0022, numbersign: 0x0023,
    dollar: 0x0024, percent: 0x0025, ampersand: 0x0026, quotesingle: 0x0027,
    parenleft: 0x0028, parenright: 0x0029, asterisk: 0x002a, plus: 0x002b,
    comma: 0x002c, hyphen: 0x002d, period: 0x002e, slash: 0x002f,
    zero: 0x0030, one: 0x0031, two: 0x0032, three: 0x0033,
    four: 0x0034, five: 0x0035, six: 0x0036, seven: 0x0037,
    eight: 0x0038, nine: 0x0039, colon: 0x003a, semicolon: 0x003b,
    less: 0x003c, equal: 0x003d, greater: 0x003e, question: 0x003f,
    at: 0x0040,
    A: 0x0041, B: 0x0042, C: 0x0043, D: 0x0044, E: 0x0045,
    F: 0x0046, G: 0x0047, H: 0x0048, I: 0x0049, J: 0x004a,
    K: 0x004b, L: 0x004c, M: 0x004d, N: 0x004e, O: 0x004f,
    P: 0x0050, Q: 0x0051, R: 0x0052, S: 0x0053, T: 0x0054,
    U: 0x0055, V: 0x0056, W: 0x0057, X: 0x0058, Y: 0x0059,
    Z: 0x005a,
    bracketleft: 0x005b, backslash: 0x005c, bracketright: 0x005d,
    asciicircum: 0x005e, underscore: 0x005f, grave: 0x0060,
    a: 0x0061, b: 0x0062, c: 0x0063, d: 0x0064, e: 0x0065,
    f: 0x0066, g: 0x0067, h: 0x0068, i: 0x0069, j: 0x006a,
    k: 0x006b, l: 0x006c, m: 0x006d, n: 0x006e, o: 0x006f,
    p: 0x0070, q: 0x0071, r: 0x0072, s: 0x0073, t: 0x0074,
    u: 0x0075, v: 0x0076, w: 0x0077, x: 0x0078, y: 0x0079,
    z: 0x007a,
    braceleft: 0x007b, bar: 0x007c, braceright: 0x007d, asciitilde: 0x007e,
    // Extended
    bullet: 0x2022, endash: 0x2013, emdash: 0x2014,
    quotedblleft: 0x201c, quotedblright: 0x201d,
    quoteleft: 0x2018, quoteright: 0x2019,
    ellipsis: 0x2026, trademark: 0x2122, copyright: 0x00a9,
    registered: 0x00ae, degree: 0x00b0,
    fi: 0xfb01, fl: 0xfb02,
    minus: 0x2212,
    // Accented
    Agrave: 0x00c0, Aacute: 0x00c1, Acircumflex: 0x00c2, Atilde: 0x00c3,
    Adieresis: 0x00c4, Aring: 0x00c5, AE: 0x00c6, Ccedilla: 0x00c7,
    Egrave: 0x00c8, Eacute: 0x00c9, Ecircumflex: 0x00ca, Edieresis: 0x00cb,
    Igrave: 0x00cc, Iacute: 0x00cd, Icircumflex: 0x00ce, Idieresis: 0x00cf,
    Eth: 0x00d0, Ntilde: 0x00d1, Ograve: 0x00d2, Oacute: 0x00d3,
    Ocircumflex: 0x00d4, Otilde: 0x00d5, Odieresis: 0x00d6, multiply: 0x00d7,
    Oslash: 0x00d8, Ugrave: 0x00d9, Uacute: 0x00da, Ucircumflex: 0x00db,
    Udieresis: 0x00dc, Yacute: 0x00dd, Thorn: 0x00de, germandbls: 0x00df,
    agrave: 0x00e0, aacute: 0x00e1, acircumflex: 0x00e2, atilde: 0x00e3,
    adieresis: 0x00e4, aring: 0x00e5, ae: 0x00e6, ccedilla: 0x00e7,
    egrave: 0x00e8, eacute: 0x00e9, ecircumflex: 0x00ea, edieresis: 0x00eb,
    igrave: 0x00ec, iacute: 0x00ed, icircumflex: 0x00ee, idieresis: 0x00ef,
    eth: 0x00f0, ntilde: 0x00f1, ograve: 0x00f2, oacute: 0x00f3,
    ocircumflex: 0x00f4, otilde: 0x00f5, odieresis: 0x00f6, divide: 0x00f7,
    oslash: 0x00f8, ugrave: 0x00f9, uacute: 0x00fa, ucircumflex: 0x00fb,
    udieresis: 0x00fc, yacute: 0x00fd, thorn: 0x00fe, ydieresis: 0x00ff,
    OE: 0x0152, oe: 0x0153, Scaron: 0x0160, scaron: 0x0161,
    Ydieresis: 0x0178, Zcaron: 0x017d, zcaron: 0x017e,
    Euro: 0x20ac,
  };

  const cp = commonGlyphs[name];
  if (cp !== undefined) return String.fromCodePoint(cp);

  // Try "uniXXXX" format
  if (name.startsWith('uni') && name.length === 7) {
    const code = parseInt(name.substring(3), 16);
    if (!isNaN(code) && code > 0) return String.fromCodePoint(code);
  }

  // Single character name
  if (name.length === 1) return name;

  return null;
}

/** Convert Windows-1252 byte to Unicode character */
function cp1252ToUnicode(code: number): string | null {
  if (code < 0x80 || code >= 0xa0) {
    return String.fromCharCode(code);
  }
  const cp1252Map: Record<number, number> = {
    0x80: 0x20ac, 0x82: 0x201a, 0x83: 0x0192, 0x84: 0x201e,
    0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02c6,
    0x89: 0x2030, 0x8a: 0x0160, 0x8b: 0x2039, 0x8c: 0x0152,
    0x8e: 0x017d, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201c,
    0x94: 0x201d, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
    0x98: 0x02dc, 0x99: 0x2122, 0x9a: 0x0161, 0x9b: 0x203a,
    0x9c: 0x0153, 0x9e: 0x017e, 0x9f: 0x0178,
  };
  const mapped = cp1252Map[code];
  return mapped !== undefined ? String.fromCodePoint(mapped) : null;
}

/** Convert Mac Roman byte to Unicode character */
function macRomanToUnicode(code: number): string | null {
  if (code < 0x80) return String.fromCharCode(code);
  const macTable: number[] = [
    0x00c4,0x00c5,0x00c7,0x00c9,0x00d1,0x00d6,0x00dc,0x00e1,
    0x00e0,0x00e2,0x00e4,0x00e3,0x00e5,0x00e7,0x00e9,0x00e8,
    0x00ea,0x00eb,0x00ed,0x00ec,0x00ee,0x00ef,0x00f1,0x00f3,
    0x00f2,0x00f4,0x00f6,0x00f5,0x00fa,0x00f9,0x00fb,0x00fc,
    0x2020,0x00b0,0x00a2,0x00a3,0x00a7,0x2022,0x00b6,0x00df,
    0x00ae,0x00a9,0x2122,0x00b4,0x00a8,0x2260,0x00c6,0x00d8,
    0x221e,0x00b1,0x2264,0x2265,0x00a5,0x00b5,0x2202,0x2211,
    0x220f,0x03c0,0x222b,0x00aa,0x00ba,0x2126,0x00e6,0x00f8,
    0x00bf,0x00a1,0x00ac,0x221a,0x0192,0x2248,0x2206,0x00ab,
    0x00bb,0x2026,0x00a0,0x00c0,0x00c3,0x00d5,0x0152,0x0153,
    0x2013,0x2014,0x201c,0x201d,0x2018,0x2019,0x00f7,0x25ca,
    0x00ff,0x0178,0x2044,0x20ac,0x2039,0x203a,0xfb01,0xfb02,
    0x2021,0x00b7,0x201a,0x201e,0x2030,0x00c2,0x00ca,0x00c1,
    0x00cb,0x00c8,0x00cd,0x00ce,0x00cf,0x00cc,0x00d3,0x00d4,
    0xf8ff,0x00d2,0x00da,0x00db,0x00d9,0x0131,0x02c6,0x02dc,
    0x00af,0x02d8,0x02d9,0x02da,0x00b8,0x02dd,0x02db,0x02c7,
  ];
  const idx = code - 0x80;
  if (idx >= 0 && idx < macTable.length) {
    return String.fromCodePoint(macTable[idx]);
  }
  return null;
}

/**
 * Get font information and build a decoding function for a font.
 */
async function getFontDecoder(
  fontName: string,
  resources: PdfDict,
  store: ObjectStore,
): Promise<{
  decode: (bytes: Uint8Array) => string;
  widths: Map<number, number>;
  defaultWidth: number;
  isTwoByteFont: boolean;
}> {
  const defaultResult = {
    decode: (bytes: Uint8Array) => {
      let s = '';
      for (let i = 0; i < bytes.length; i++) {
        s += String.fromCharCode(bytes[i]);
      }
      return s;
    },
    widths: new Map<number, number>(),
    defaultWidth: 600,
    isTwoByteFont: false,
  };

  const fontsDictObj = resolve(dictGet(resources, 'Font'), store);
  if (!fontsDictObj || !isDict(fontsDictObj)) return defaultResult;

  const fontObj = resolve(dictGet(fontsDictObj, fontName), store);
  if (!fontObj) return defaultResult;
  if (!isDict(fontObj) && !isStream(fontObj)) return defaultResult;

  const fontDict = fontObj as PdfDict;
  const subtype = dictGetName(fontDict, 'Subtype');

  // Try to get ToUnicode CMap
  const toUnicodeRef = dictGet(fontDict, 'ToUnicode');
  const toUnicodeMap = await parseToUnicodeCMap(toUnicodeRef, store);

  // Build encoding-based map
  const encodingMap = buildEncodingMap(fontDict, store);

  // Get widths
  const widthMap = new Map<number, number>();
  const firstChar = dictGetNumber(fontDict, 'FirstChar') ?? 0;
  const widthsArr = dictGetArray(fontDict, 'Widths');
  if (widthsArr) {
    for (let i = 0; i < widthsArr.length; i++) {
      const w = widthsArr[i];
      if (isNumber(w)) {
        widthMap.set(firstChar + i, w.value);
      }
    }
  }

  // Default width
  let defaultWidth = 1000;
  const dw = dictGetNumber(fontDict, 'DW');
  if (dw !== undefined) defaultWidth = dw;

  // For Type0 (composite) fonts, handle CIDFont widths
  const isCIDFont = subtype === 'Type0';
  let isTwoByteFont = false;

  if (isCIDFont) {
    isTwoByteFont = true;
    defaultWidth = 1000;

    // Get descendant font
    const descendantsArr = dictGetArray(fontDict, 'DescendantFonts');
    if (descendantsArr && descendantsArr.length > 0) {
      const cidFontObj = resolve(descendantsArr[0], store);
      if (cidFontObj && isDict(cidFontObj)) {
        const cidDw = dictGetNumber(cidFontObj, 'DW');
        if (cidDw !== undefined) defaultWidth = cidDw;

        // Parse /W array for CID widths
        const wArr = dictGetArray(cidFontObj, 'W');
        if (wArr) {
          let i = 0;
          while (i < wArr.length) {
            const first = wArr[i];
            if (!isNumber(first)) { i++; continue; }
            const startCID = first.value;
            i++;
            if (i >= wArr.length) break;

            const next = wArr[i];
            if (isArray(next)) {
              // Array form: startCID [w1, w2, ...]
              for (let j = 0; j < next.items.length; j++) {
                const wItem = next.items[j];
                if (isNumber(wItem)) {
                  widthMap.set(startCID + j, wItem.value);
                }
              }
              i++;
            } else if (isNumber(next)) {
              // Range form: startCID endCID width
              const endCID = next.value;
              i++;
              const wItem2 = wArr[i];
              if (i < wArr.length && isNumber(wItem2)) {
                const w = wItem2.value;
                for (let cid = startCID; cid <= endCID; cid++) {
                  widthMap.set(cid, w);
                }
                i++;
              }
            } else {
              i++;
            }
          }
        }
      }
    }
  }

  // Build decode function
  const decode = (bytes: Uint8Array): string => {
    if (isTwoByteFont && toUnicodeMap) {
      let result = '';
      // Try 2-byte codes first, fall back to 1-byte
      let i = 0;
      while (i < bytes.length) {
        if (i + 1 < bytes.length) {
          const code16 = (bytes[i] << 8) | bytes[i + 1];
          const mapped = toUnicodeMap.get(code16);
          if (mapped) {
            result += mapped;
            i += 2;
            continue;
          }
        }
        // Try single byte
        const mapped = toUnicodeMap.get(bytes[i]);
        if (mapped) {
          result += mapped;
        } else {
          result += String.fromCharCode(bytes[i]);
        }
        i++;
      }
      return result;
    }

    let result = '';
    for (let i = 0; i < bytes.length; i++) {
      const code = bytes[i];
      if (toUnicodeMap) {
        const mapped = toUnicodeMap.get(code);
        if (mapped) {
          result += mapped;
          continue;
        }
      }
      if (encodingMap) {
        const mapped = encodingMap.get(code);
        if (mapped) {
          result += mapped;
          continue;
        }
      }
      result += String.fromCharCode(code);
    }
    return result;
  };

  return { decode, widths: widthMap, defaultWidth, isTwoByteFont };
}

/**
 * Extract text items from a parsed content stream.
 */
export async function extractText(
  operations: ContentOperation[],
  resources: PdfDict,
  store: ObjectStore,
): Promise<ExtractedTextItem[]> {
  const items: ExtractedTextItem[] = [];

  // Graphics state stack
  const stateStack: GraphicsState[] = [];
  let gs: GraphicsState = {
    ctm: identityMatrix(),
    textState: {
      fontName: '',
      fontSize: 12,
      charSpacing: 0,
      wordSpacing: 0,
      horizontalScale: 100,
      leading: 0,
      rise: 0,
      renderMode: 0,
    },
  };

  // Text matrices
  let textMatrix: Matrix = identityMatrix();
  let textLineMatrix: Matrix = identityMatrix();
  let inTextObject = false;

  // Font decoder cache
  const fontDecoderCache = new Map<string, Awaited<ReturnType<typeof getFontDecoder>>>();

  async function getDecoder(fontName: string) {
    if (fontDecoderCache.has(fontName)) return fontDecoderCache.get(fontName)!;
    const decoder = await getFontDecoder(fontName, resources, store);
    fontDecoderCache.set(fontName, decoder);
    return decoder;
  }

  function getEffectiveFontSize(): number {
    return gs.textState.fontSize;
  }

  /**
   * Show a string and advance the text position.
   */
  async function showString(bytes: Uint8Array): Promise<void> {
    const fontName = gs.textState.fontName;
    const fontSize = getEffectiveFontSize();
    const decoder = await getDecoder(fontName);
    const text = decoder.decode(bytes);

    if (text.length === 0) return;

    // Compute the position using text matrix * CTM
    const combined = multiplyMatrix(textMatrix, gs.ctm);
    const [x, y] = transformPoint(combined, 0, gs.textState.rise);

    // Compute text width
    const hScale = gs.textState.horizontalScale / 100;
    let totalWidth = 0;

    if (decoder.isTwoByteFont) {
      // For CID fonts, process 2-byte codes
      let i = 0;
      while (i < bytes.length) {
        let code: number;
        if (i + 1 < bytes.length) {
          code = (bytes[i] << 8) | bytes[i + 1];
          // Check if this 2-byte code has a width
          const w = decoder.widths.get(code);
          if (w !== undefined) {
            totalWidth += w;
            i += 2;
            continue;
          }
        }
        code = bytes[i];
        const w = decoder.widths.get(code) ?? decoder.defaultWidth;
        totalWidth += w;
        i++;
      }
    } else {
      for (let i = 0; i < bytes.length; i++) {
        const code = bytes[i];
        const w = decoder.widths.get(code) ?? decoder.defaultWidth;
        totalWidth += w;
        // Add char spacing
        totalWidth += gs.textState.charSpacing * 1000 / fontSize;
        // Word spacing (for space character, code 32)
        if (code === 32) {
          totalWidth += gs.textState.wordSpacing * 1000 / fontSize;
        }
      }
    }

    const widthInTextSpace = (totalWidth / 1000) * fontSize * hScale;

    items.push({
      text,
      x,
      y,
      width: widthInTextSpace,
      fontSize: Math.abs(fontSize * combined[3]) || Math.abs(fontSize * combined[0]) || fontSize,
      fontName,
    });

    // Advance text matrix
    const tx = widthInTextSpace;
    textMatrix = multiplyMatrix([1, 0, 0, 1, tx, 0], textMatrix);
  }

  for (const op of operations) {
    switch (op.operator) {
      // Graphics state
      case 'q':
        stateStack.push(cloneGraphicsState(gs));
        break;

      case 'Q':
        if (stateStack.length > 0) {
          gs = stateStack.pop()!;
        }
        break;

      case 'cm': {
        if (op.operands.length >= 6) {
          const m: Matrix = [
            numVal(op.operands[0]),
            numVal(op.operands[1]),
            numVal(op.operands[2]),
            numVal(op.operands[3]),
            numVal(op.operands[4]),
            numVal(op.operands[5]),
          ];
          gs.ctm = multiplyMatrix(m, gs.ctm);
        }
        break;
      }

      // Text object
      case 'BT':
        inTextObject = true;
        textMatrix = identityMatrix();
        textLineMatrix = identityMatrix();
        break;

      case 'ET':
        inTextObject = false;
        break;

      // Text state
      case 'Tf': {
        if (op.operands.length >= 2) {
          const nameObj = op.operands[0];
          if (isName(nameObj)) {
            gs.textState.fontName = nameObj.value;
          }
          gs.textState.fontSize = numVal(op.operands[1]);
        }
        break;
      }

      case 'Tc':
        if (op.operands.length >= 1) {
          gs.textState.charSpacing = numVal(op.operands[0]);
        }
        break;

      case 'Tw':
        if (op.operands.length >= 1) {
          gs.textState.wordSpacing = numVal(op.operands[0]);
        }
        break;

      case 'Tz':
        if (op.operands.length >= 1) {
          gs.textState.horizontalScale = numVal(op.operands[0]);
        }
        break;

      case 'TL':
        if (op.operands.length >= 1) {
          gs.textState.leading = numVal(op.operands[0]);
        }
        break;

      case 'Tr':
        if (op.operands.length >= 1) {
          gs.textState.renderMode = numVal(op.operands[0]);
        }
        break;

      case 'Ts':
        if (op.operands.length >= 1) {
          gs.textState.rise = numVal(op.operands[0]);
        }
        break;

      // Text positioning
      case 'Td': {
        if (op.operands.length >= 2) {
          const tx = numVal(op.operands[0]);
          const ty = numVal(op.operands[1]);
          textLineMatrix = multiplyMatrix([1, 0, 0, 1, tx, ty], textLineMatrix);
          textMatrix = [...textLineMatrix] as Matrix;
        }
        break;
      }

      case 'TD': {
        if (op.operands.length >= 2) {
          const tx = numVal(op.operands[0]);
          const ty = numVal(op.operands[1]);
          gs.textState.leading = -ty;
          textLineMatrix = multiplyMatrix([1, 0, 0, 1, tx, ty], textLineMatrix);
          textMatrix = [...textLineMatrix] as Matrix;
        }
        break;
      }

      case 'Tm': {
        if (op.operands.length >= 6) {
          textMatrix = [
            numVal(op.operands[0]),
            numVal(op.operands[1]),
            numVal(op.operands[2]),
            numVal(op.operands[3]),
            numVal(op.operands[4]),
            numVal(op.operands[5]),
          ];
          textLineMatrix = [...textMatrix] as Matrix;
        }
        break;
      }

      case 'T*': {
        const tx = 0;
        const ty = -gs.textState.leading;
        textLineMatrix = multiplyMatrix([1, 0, 0, 1, tx, ty], textLineMatrix);
        textMatrix = [...textLineMatrix] as Matrix;
        break;
      }

      // Text showing
      case 'Tj': {
        if (op.operands.length >= 1 && isString(op.operands[0])) {
          await showString(op.operands[0].value);
        }
        break;
      }

      case 'TJ': {
        if (op.operands.length >= 1 && isArray(op.operands[0])) {
          for (const item of op.operands[0].items) {
            if (isString(item)) {
              await showString(item.value);
            } else if (isNumber(item)) {
              // Negative number = move right (advance), positive = move left (kern)
              const displacement = -item.value / 1000 * gs.textState.fontSize *
                (gs.textState.horizontalScale / 100);
              textMatrix = multiplyMatrix([1, 0, 0, 1, displacement, 0], textMatrix);
            }
          }
        }
        break;
      }

      case "'": {
        // Move to next line and show string
        const tx = 0;
        const ty = -gs.textState.leading;
        textLineMatrix = multiplyMatrix([1, 0, 0, 1, tx, ty], textLineMatrix);
        textMatrix = [...textLineMatrix] as Matrix;
        if (op.operands.length >= 1 && isString(op.operands[0])) {
          await showString(op.operands[0].value);
        }
        break;
      }

      case '"': {
        // Set word and char spacing, move to next line, show string
        if (op.operands.length >= 3) {
          gs.textState.wordSpacing = numVal(op.operands[0]);
          gs.textState.charSpacing = numVal(op.operands[1]);
          const tx = 0;
          const ty = -gs.textState.leading;
          textLineMatrix = multiplyMatrix([1, 0, 0, 1, tx, ty], textLineMatrix);
          textMatrix = [...textLineMatrix] as Matrix;
          if (isString(op.operands[2])) {
            await showString(op.operands[2].value);
          }
        }
        break;
      }

      default:
        break;
    }
  }

  return items;
}

function numVal(obj: PdfObject): number {
  if (isNumber(obj)) return obj.value;
  return 0;
}
