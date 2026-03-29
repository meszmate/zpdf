/**
 * Embed fonts into PDF object structure.
 */

import type { PdfRef, PdfObject } from '../core/types.js';
import type { ObjectStore } from '../core/object-store.js';
import type { Font, FontMetrics } from './metrics.js';
import type { TrueTypeFontData } from './truetype-parser.js';
import { subsetTrueTypeFont } from './font-subsetter.js';
import { generateToUnicodeCMap } from './glyph-mapping.js';

// --------------------------------------------------------------------------
// Helper: create PDF objects without depending on objects.ts
// --------------------------------------------------------------------------

function name(v: string): PdfObject { return { type: 'name', value: v }; }
function num(v: number): PdfObject { return { type: 'number', value: v }; }
function str(v: string): PdfObject {
  const bytes = new Uint8Array(v.length);
  for (let i = 0; i < v.length; i++) bytes[i] = v.charCodeAt(i) & 0xff;
  return { type: 'string', value: bytes, encoding: 'literal' };
}
function arr(items: PdfObject[]): PdfObject { return { type: 'array', items }; }
function dict(entries: Record<string, PdfObject>): PdfObject {
  return { type: 'dict', entries: new Map(Object.entries(entries)) };
}
function stream(dictEntries: Record<string, PdfObject>, data: Uint8Array): PdfObject {
  return { type: 'stream', dict: new Map(Object.entries(dictEntries)), data };
}

// --------------------------------------------------------------------------
// Embed a standard (Type1) font
// --------------------------------------------------------------------------

export function embedStandardFont(store: ObjectStore, fontName: string): PdfRef {
  const ref = store.allocRef();
  const fontDict = dict({
    Type: name('Font'),
    Subtype: name('Type1'),
    BaseFont: name(fontName),
    Encoding: name('WinAnsiEncoding'),
  });
  store.set(ref, fontDict);
  return ref;
}

// --------------------------------------------------------------------------
// Embed a TrueType font as a Type0 (composite) font with CIDFont descendant
// --------------------------------------------------------------------------

export function embedTrueTypeFont(
  store: ObjectStore,
  fontData: Uint8Array,
  parsedFont: TrueTypeFontData,
  usedChars: Set<number>,
): { fontRef: PdfRef; font: Font } {
  const { head, hhea, hmtx, cmap, os2, post, maxp } = parsedFont;
  const unitsPerEm = head.unitsPerEm;
  const scale = 1000 / unitsPerEm;

  // Collect glyph indices for used characters
  const usedGlyphs = new Set<number>();
  const charToGlyph = new Map<number, number>(); // unicode -> glyphIndex
  for (const charCode of usedChars) {
    const gid = cmap.get(charCode);
    if (gid !== undefined) {
      usedGlyphs.add(gid);
      charToGlyph.set(charCode, gid);
    }
  }

  // Subset the font
  const { subsetBytes, oldToNewGlyphMap } = subsetTrueTypeFont(fontData, parsedFont, usedGlyphs);

  // Build CID -> unicode mapping for ToUnicode CMap
  // In our CID scheme: CID = new glyph index
  const cidToUnicode = new Map<number, number>();
  // Also build char -> CID for encoding
  const charToCID = new Map<number, number>();

  for (const [unicode, oldGid] of charToGlyph) {
    const newGid = oldToNewGlyphMap.get(oldGid);
    if (newGid !== undefined) {
      cidToUnicode.set(newGid, unicode);
      charToCID.set(unicode, newGid);
    }
  }

  // Generate ToUnicode CMap
  const toUnicodeCMapStr = generateToUnicodeCMap(cidToUnicode);
  const toUnicodeCMapBytes = new Uint8Array(toUnicodeCMapStr.length);
  for (let i = 0; i < toUnicodeCMapStr.length; i++) {
    toUnicodeCMapBytes[i] = toUnicodeCMapStr.charCodeAt(i) & 0xff;
  }

  // Embed ToUnicode CMap stream
  const toUnicodeRef = store.allocRef();
  store.set(toUnicodeRef, stream(
    { Length: num(toUnicodeCMapBytes.length) },
    toUnicodeCMapBytes,
  ));

  // Embed font program stream
  const fontFileRef = store.allocRef();
  store.set(fontFileRef, stream(
    {
      Length: num(subsetBytes.length),
      Length1: num(subsetBytes.length),
    },
    subsetBytes,
  ));

  // Build widths array: [CID, [width, ...], CID, [width, ...], ...]
  // Group consecutive CIDs
  const cidWidthEntries: PdfObject[] = [];
  const sortedCIDs = Array.from(cidToUnicode.keys()).sort((a, b) => a - b);

  let i = 0;
  while (i < sortedCIDs.length) {
    const startCID = sortedCIDs[i];
    const widths: PdfObject[] = [];

    let j = i;
    while (j < sortedCIDs.length && sortedCIDs[j] === startCID + (j - i)) {
      const newGid = sortedCIDs[j];
      // Find original glyph ID
      let origGid = 0;
      for (const [oldG, newG] of oldToNewGlyphMap) {
        if (newG === newGid) { origGid = oldG; break; }
      }
      const advWidth = hmtx.advanceWidths[origGid] || 0;
      widths.push(num(Math.round(advWidth * scale)));
      j++;
    }

    cidWidthEntries.push(num(startCID));
    cidWidthEntries.push(arr(widths));
    i = j;
  }

  // Compute default width
  const defaultWidth = Math.round((hmtx.advanceWidths[0] || 0) * scale);

  // Font descriptor
  const ascent = Math.round(os2.sTypoAscender * scale);
  const descent = Math.round(os2.sTypoDescender * scale);
  const capHeight = Math.round((os2.sCapHeight || os2.sTypoAscender) * scale);
  const xHeight = Math.round((os2.sxHeight || Math.round(os2.sTypoAscender * 0.5)) * scale);
  const bbox = [
    Math.round(head.xMin * scale),
    Math.round(head.yMin * scale),
    Math.round(head.xMax * scale),
    Math.round(head.yMax * scale),
  ];

  // Determine flags
  let flags = 0;
  if (post.isFixedPitch) flags |= 1;       // FixedPitch
  flags |= 4;                                // Symbolic (for TrueType we set Symbolic)
  if (post.italicAngle !== 0) flags |= 64;  // Italic

  // Compute stemV from weight class
  const stemV = Math.round(50 + (os2.usWeightClass / 65) ** 2);

  const fontDescriptorRef = store.allocRef();
  store.set(fontDescriptorRef, dict({
    Type: name('FontDescriptor'),
    FontName: name(parsedFont.name.postScriptName || parsedFont.name.fontFamily || 'Unknown'),
    Flags: num(flags),
    FontBBox: arr(bbox.map(v => num(v))),
    ItalicAngle: num(post.italicAngle),
    Ascent: num(ascent),
    Descent: num(descent),
    CapHeight: num(capHeight),
    XHeight: num(xHeight),
    StemV: num(stemV),
    FontFile2: { type: 'ref', objectNumber: fontFileRef.objectNumber, generation: fontFileRef.generation },
  }));

  // CIDFont (descendant)
  const cidFontRef = store.allocRef();
  store.set(cidFontRef, dict({
    Type: name('Font'),
    Subtype: name('CIDFontType2'),
    BaseFont: name(parsedFont.name.postScriptName || parsedFont.name.fontFamily || 'Unknown'),
    CIDSystemInfo: dict({
      Registry: str('Adobe'),
      Ordering: str('Identity'),
      Supplement: num(0),
    }),
    FontDescriptor: { type: 'ref', objectNumber: fontDescriptorRef.objectNumber, generation: fontDescriptorRef.generation },
    DW: num(defaultWidth),
    W: arr(cidWidthEntries),
  }));

  // Type0 font (top-level)
  const fontRef = store.allocRef();
  store.set(fontRef, dict({
    Type: name('Font'),
    Subtype: name('Type0'),
    BaseFont: name(parsedFont.name.postScriptName || parsedFont.name.fontFamily || 'Unknown'),
    Encoding: name('Identity-H'),
    DescendantFonts: arr([
      { type: 'ref', objectNumber: cidFontRef.objectNumber, generation: cidFontRef.generation },
    ]),
    ToUnicode: { type: 'ref', objectNumber: toUnicodeRef.objectNumber, generation: toUnicodeRef.generation },
  }));

  // Build font metrics for the Font object
  const widthMap = new Map<number, number>();
  for (const [unicode, oldGid] of charToGlyph) {
    const w = hmtx.advanceWidths[oldGid] || 0;
    widthMap.set(unicode, Math.round(w * scale));
  }

  const fontMetrics: FontMetrics = {
    ascent,
    descent,
    lineGap: Math.round((os2.sTypoLineGap || hhea.lineGap) * scale),
    unitsPerEm: 1000,
    bbox: bbox as [number, number, number, number],
    italicAngle: post.italicAngle,
    capHeight,
    xHeight,
    stemV,
    flags,
    defaultWidth,
    widths: widthMap,
  };

  // The charToCID map is captured in closure for encoding
  const frozenCharToCID = new Map(charToCID);

  const font: Font = {
    name: parsedFont.name.postScriptName || parsedFont.name.fontFamily || 'Unknown',
    ref: fontRef,
    metrics: fontMetrics,
    isStandard: false,

    encode(text: string): Uint8Array {
      // Encode as big-endian CID values (2 bytes per character)
      const result = new Uint8Array(text.length * 2);
      let pos = 0;
      for (let idx = 0; idx < text.length; idx++) {
        const cp = text.codePointAt(idx)!;
        const cid = frozenCharToCID.get(cp) ?? 0;
        result[pos++] = (cid >>> 8) & 0xff;
        result[pos++] = cid & 0xff;
        if (cp > 0xffff) idx++; // Skip surrogate pair
      }
      return result.slice(0, pos);
    },

    measureWidth(text: string, fontSize: number): number {
      let total = 0;
      for (let idx = 0; idx < text.length; idx++) {
        const cp = text.codePointAt(idx)!;
        const w = widthMap.get(cp);
        total += w !== undefined ? w : defaultWidth;
        if (cp > 0xffff) idx++;
      }
      return (total / 1000) * fontSize;
    },

    getLineHeight(fontSize: number): number {
      return ((ascent - descent + (fontMetrics.lineGap || 0)) / 1000) * fontSize;
    },
  };

  return { fontRef, font };
}
