/**
 * TrueType font file parser.
 * Parses .ttf files and extracts tables needed for PDF embedding.
 */

export interface TrueTypeTableRecord {
  tag: string;
  checksum: number;
  offset: number;
  length: number;
}

export interface HeadTable {
  unitsPerEm: number;
  xMin: number;
  yMin: number;
  xMax: number;
  yMax: number;
  indexToLocFormat: number; // 0 = short, 1 = long
  macStyle: number;
  flags: number;
  created: bigint;
  modified: bigint;
}

export interface HheaTable {
  ascent: number;
  descent: number;
  lineGap: number;
  advanceWidthMax: number;
  numOfLongHorMetrics: number;
}

export interface HmtxTable {
  advanceWidths: number[];
  leftSideBearings: number[];
}

export interface NameRecord {
  platformID: number;
  encodingID: number;
  languageID: number;
  nameID: number;
  value: string;
}

export interface NameTable {
  fontFamily: string;
  fontSubfamily: string;
  fullName: string;
  postScriptName: string;
  records: NameRecord[];
}

export interface Os2Table {
  version: number;
  xAvgCharWidth: number;
  usWeightClass: number;
  usWidthClass: number;
  fsType: number;
  ySubscriptXSize: number;
  ySubscriptYSize: number;
  ySubscriptXOffset: number;
  ySubscriptYOffset: number;
  ySuperscriptXSize: number;
  ySuperscriptYSize: number;
  ySuperscriptXOffset: number;
  ySuperscriptYOffset: number;
  yStrikeoutSize: number;
  yStrikeoutPosition: number;
  sFamilyClass: number;
  panose: Uint8Array;
  ulUnicodeRange1: number;
  ulUnicodeRange2: number;
  ulUnicodeRange3: number;
  ulUnicodeRange4: number;
  achVendID: string;
  fsSelection: number;
  usFirstCharIndex: number;
  usLastCharIndex: number;
  sTypoAscender: number;
  sTypoDescender: number;
  sTypoLineGap: number;
  usWinAscent: number;
  usWinDescent: number;
  sCapHeight: number;
  sxHeight: number;
}

export interface PostTable {
  format: number;
  italicAngle: number;
  underlinePosition: number;
  underlineThickness: number;
  isFixedPitch: boolean;
}

export interface MaxpTable {
  version: number;
  numGlyphs: number;
}

export interface TrueTypeFontData {
  tables: Map<string, { offset: number; length: number }>;
  head: HeadTable;
  hhea: HheaTable;
  hmtx: HmtxTable;
  cmap: Map<number, number>; // unicode codepoint -> glyphIndex
  name: NameTable;
  os2: Os2Table;
  post: PostTable;
  maxp: MaxpTable;
  rawData: Uint8Array;
}

// --------------------------------------------------------------------------
// Binary reader helper
// --------------------------------------------------------------------------

class FontReader {
  private view: DataView;
  private data: Uint8Array;
  pos: number;

  constructor(data: Uint8Array, offset: number = 0) {
    this.data = data;
    this.view = new DataView(data.buffer, data.byteOffset, data.byteLength);
    this.pos = offset;
  }

  seek(offset: number): void {
    this.pos = offset;
  }

  skip(n: number): void {
    this.pos += n;
  }

  readUint8(): number {
    const v = this.data[this.pos];
    this.pos += 1;
    return v;
  }

  readUint16(): number {
    const v = this.view.getUint16(this.pos, false);
    this.pos += 2;
    return v;
  }

  readInt16(): number {
    const v = this.view.getInt16(this.pos, false);
    this.pos += 2;
    return v;
  }

  readUint32(): number {
    const v = this.view.getUint32(this.pos, false);
    this.pos += 4;
    return v;
  }

  readInt32(): number {
    const v = this.view.getInt32(this.pos, false);
    this.pos += 4;
    return v;
  }

  readInt64(): bigint {
    const hi = this.view.getInt32(this.pos, false);
    const lo = this.view.getUint32(this.pos + 4, false);
    this.pos += 8;
    return (BigInt(hi) << 32n) | BigInt(lo);
  }

  readFixed(): number {
    const v = this.readInt32();
    return v / 65536;
  }

  readTag(): string {
    let s = '';
    for (let i = 0; i < 4; i++) {
      s += String.fromCharCode(this.data[this.pos + i]);
    }
    this.pos += 4;
    return s;
  }

  readBytes(n: number): Uint8Array {
    const result = this.data.slice(this.pos, this.pos + n);
    this.pos += n;
    return result;
  }

  slice(offset: number, length: number): Uint8Array {
    return this.data.slice(offset, offset + length);
  }
}

// --------------------------------------------------------------------------
// Table parsers
// --------------------------------------------------------------------------

function parseHead(reader: FontReader, offset: number): HeadTable {
  reader.seek(offset);
  const majorVersion = reader.readUint16();
  const minorVersion = reader.readUint16();
  reader.skip(4); // fontRevision (Fixed)
  reader.skip(4); // checksumAdjustment
  const magicNumber = reader.readUint32();
  if (magicNumber !== 0x5F0F3CF5) {
    throw new Error('Invalid TrueType font: bad magic number in head table');
  }
  const flags = reader.readUint16();
  const unitsPerEm = reader.readUint16();
  const created = reader.readInt64();
  const modified = reader.readInt64();
  const xMin = reader.readInt16();
  const yMin = reader.readInt16();
  const xMax = reader.readInt16();
  const yMax = reader.readInt16();
  const macStyle = reader.readUint16();
  reader.skip(2); // lowestRecPPEM
  reader.skip(2); // fontDirectionHint
  const indexToLocFormat = reader.readInt16();
  return { unitsPerEm, xMin, yMin, xMax, yMax, indexToLocFormat, macStyle, flags, created, modified };
}

function parseHhea(reader: FontReader, offset: number): HheaTable {
  reader.seek(offset);
  reader.skip(4); // version
  const ascent = reader.readInt16();
  const descent = reader.readInt16();
  const lineGap = reader.readInt16();
  const advanceWidthMax = reader.readUint16();
  reader.skip(2); // minLeftSideBearing
  reader.skip(2); // minRightSideBearing
  reader.skip(2); // xMaxExtent
  reader.skip(2); // caretSlopeRise
  reader.skip(2); // caretSlopeRun
  reader.skip(2); // caretOffset
  reader.skip(8); // reserved
  reader.skip(2); // metricDataFormat
  const numOfLongHorMetrics = reader.readUint16();
  return { ascent, descent, lineGap, advanceWidthMax, numOfLongHorMetrics };
}

function parseHmtx(reader: FontReader, offset: number, numOfLongHorMetrics: number, numGlyphs: number): HmtxTable {
  reader.seek(offset);
  const advanceWidths = new Array<number>(numGlyphs);
  const leftSideBearings = new Array<number>(numGlyphs);

  let lastWidth = 0;
  for (let i = 0; i < numOfLongHorMetrics; i++) {
    const aw = reader.readUint16();
    const lsb = reader.readInt16();
    advanceWidths[i] = aw;
    leftSideBearings[i] = lsb;
    lastWidth = aw;
  }

  // Remaining glyphs only have lsb, advance width is same as last longHorMetric
  for (let i = numOfLongHorMetrics; i < numGlyphs; i++) {
    advanceWidths[i] = lastWidth;
    leftSideBearings[i] = reader.readInt16();
  }

  return { advanceWidths, leftSideBearings };
}

function parseCmap(reader: FontReader, offset: number): Map<number, number> {
  reader.seek(offset);
  const version = reader.readUint16();
  const numTables = reader.readUint16();

  // Collect all subtable entries
  const subtables: { platformID: number; encodingID: number; subtableOffset: number }[] = [];
  for (let i = 0; i < numTables; i++) {
    const platformID = reader.readUint16();
    const encodingID = reader.readUint16();
    const subtableOffset = reader.readUint32();
    subtables.push({ platformID, encodingID, subtableOffset });
  }

  // Prefer platform 3 encoding 10 (Windows UCS-4), then 3/1 (Windows BMP), then 0/3, then 0/4, then 1/0
  let chosen: { platformID: number; encodingID: number; subtableOffset: number } | undefined;
  const priority = [
    { p: 3, e: 10 },
    { p: 0, e: 4 },
    { p: 0, e: 3 },
    { p: 3, e: 1 },
    { p: 0, e: 1 },
    { p: 0, e: 0 },
    { p: 1, e: 0 },
  ];
  for (const pref of priority) {
    chosen = subtables.find(s => s.platformID === pref.p && s.encodingID === pref.e);
    if (chosen) break;
  }

  if (!chosen && subtables.length > 0) {
    chosen = subtables[0];
  }

  if (!chosen) {
    return new Map();
  }

  const absOffset = offset + chosen.subtableOffset;
  reader.seek(absOffset);
  const format = reader.readUint16();

  if (format === 0) {
    return parseCmapFormat0(reader, absOffset);
  } else if (format === 4) {
    return parseCmapFormat4(reader, absOffset);
  } else if (format === 6) {
    return parseCmapFormat6(reader, absOffset);
  } else if (format === 12) {
    return parseCmapFormat12(reader, absOffset);
  }

  // Try fallback: look for any format 4 or 12 subtable
  for (const st of subtables) {
    const abs = offset + st.subtableOffset;
    reader.seek(abs);
    const fmt = reader.readUint16();
    if (fmt === 4) return parseCmapFormat4(reader, abs);
    if (fmt === 12) return parseCmapFormat12(reader, abs);
  }

  return new Map();
}

function parseCmapFormat0(reader: FontReader, offset: number): Map<number, number> {
  reader.seek(offset + 2); // skip format
  reader.skip(2); // length
  reader.skip(2); // language
  const map = new Map<number, number>();
  for (let i = 0; i < 256; i++) {
    const glyphIndex = reader.readUint8();
    if (glyphIndex !== 0) {
      map.set(i, glyphIndex);
    }
  }
  return map;
}

function parseCmapFormat4(reader: FontReader, offset: number): Map<number, number> {
  reader.seek(offset + 2); // skip format
  const length = reader.readUint16();
  reader.skip(2); // language
  const segCountX2 = reader.readUint16();
  const segCount = segCountX2 / 2;
  reader.skip(6); // searchRange, entrySelector, rangeShift

  const endCodes: number[] = [];
  for (let i = 0; i < segCount; i++) endCodes.push(reader.readUint16());
  reader.skip(2); // reservedPad

  const startCodes: number[] = [];
  for (let i = 0; i < segCount; i++) startCodes.push(reader.readUint16());

  const idDeltas: number[] = [];
  for (let i = 0; i < segCount; i++) idDeltas.push(reader.readInt16());

  const idRangeOffsetPos = reader.pos;
  const idRangeOffsets: number[] = [];
  for (let i = 0; i < segCount; i++) idRangeOffsets.push(reader.readUint16());

  const map = new Map<number, number>();

  for (let i = 0; i < segCount; i++) {
    const start = startCodes[i];
    const end = endCodes[i];
    const delta = idDeltas[i];
    const rangeOffset = idRangeOffsets[i];

    if (start === 0xFFFF) continue;

    for (let charCode = start; charCode <= end; charCode++) {
      let glyphIndex: number;
      if (rangeOffset === 0) {
        glyphIndex = (charCode + delta) & 0xFFFF;
      } else {
        const glyphDataOffset = idRangeOffsetPos + i * 2 + rangeOffset + (charCode - start) * 2;
        reader.seek(glyphDataOffset);
        glyphIndex = reader.readUint16();
        if (glyphIndex !== 0) {
          glyphIndex = (glyphIndex + delta) & 0xFFFF;
        }
      }
      if (glyphIndex !== 0) {
        map.set(charCode, glyphIndex);
      }
    }
  }

  return map;
}

function parseCmapFormat6(reader: FontReader, offset: number): Map<number, number> {
  reader.seek(offset + 2); // skip format
  reader.skip(2); // length
  reader.skip(2); // language
  const firstCode = reader.readUint16();
  const entryCount = reader.readUint16();
  const map = new Map<number, number>();
  for (let i = 0; i < entryCount; i++) {
    const glyphIndex = reader.readUint16();
    if (glyphIndex !== 0) {
      map.set(firstCode + i, glyphIndex);
    }
  }
  return map;
}

function parseCmapFormat12(reader: FontReader, offset: number): Map<number, number> {
  reader.seek(offset + 2); // skip format (already read as 16-bit, but format 12 has 16-bit reserved)
  reader.skip(2); // reserved
  reader.skip(4); // length (32-bit)
  reader.skip(4); // language (32-bit)
  const numGroups = reader.readUint32();

  const map = new Map<number, number>();
  for (let i = 0; i < numGroups; i++) {
    const startCharCode = reader.readUint32();
    const endCharCode = reader.readUint32();
    const startGlyphID = reader.readUint32();
    for (let c = startCharCode; c <= endCharCode; c++) {
      const glyphID = startGlyphID + (c - startCharCode);
      if (glyphID !== 0) {
        map.set(c, glyphID);
      }
    }
  }

  return map;
}

function parseName(reader: FontReader, offset: number): NameTable {
  reader.seek(offset);
  const format = reader.readUint16();
  const count = reader.readUint16();
  const stringOffset = reader.readUint16();
  const storageOffset = offset + stringOffset;

  const records: NameRecord[] = [];
  let fontFamily = '';
  let fontSubfamily = '';
  let fullName = '';
  let postScriptName = '';

  for (let i = 0; i < count; i++) {
    const platformID = reader.readUint16();
    const encodingID = reader.readUint16();
    const languageID = reader.readUint16();
    const nameID = reader.readUint16();
    const length = reader.readUint16();
    const strOffset = reader.readUint16();

    const strBytes = reader.slice(storageOffset + strOffset, length);
    let value: string;

    if (platformID === 3 || platformID === 0) {
      // Unicode BMP or Windows - UTF-16BE
      value = '';
      for (let j = 0; j + 1 < strBytes.length; j += 2) {
        value += String.fromCharCode((strBytes[j] << 8) | strBytes[j + 1]);
      }
    } else if (platformID === 1) {
      // Mac Roman - approximate as Latin1
      value = '';
      for (let j = 0; j < strBytes.length; j++) {
        value += String.fromCharCode(strBytes[j]);
      }
    } else {
      value = '';
      for (let j = 0; j < strBytes.length; j++) {
        value += String.fromCharCode(strBytes[j]);
      }
    }

    records.push({ platformID, encodingID, languageID, nameID, value });

    // Prefer Windows English (platformID=3, languageID=0x0409) or fall back to any
    const isPreferred = (platformID === 3 && languageID === 0x0409) || (platformID === 1 && languageID === 0);

    if (nameID === 1 && (isPreferred || !fontFamily)) fontFamily = value;
    if (nameID === 2 && (isPreferred || !fontSubfamily)) fontSubfamily = value;
    if (nameID === 4 && (isPreferred || !fullName)) fullName = value;
    if (nameID === 6 && (isPreferred || !postScriptName)) postScriptName = value;
  }

  return { fontFamily, fontSubfamily, fullName, postScriptName, records };
}

function parseOs2(reader: FontReader, offset: number, tableLength: number): Os2Table {
  reader.seek(offset);
  const version = reader.readUint16();
  const xAvgCharWidth = reader.readInt16();
  const usWeightClass = reader.readUint16();
  const usWidthClass = reader.readUint16();
  const fsType = reader.readUint16();
  const ySubscriptXSize = reader.readInt16();
  const ySubscriptYSize = reader.readInt16();
  const ySubscriptXOffset = reader.readInt16();
  const ySubscriptYOffset = reader.readInt16();
  const ySuperscriptXSize = reader.readInt16();
  const ySuperscriptYSize = reader.readInt16();
  const ySuperscriptXOffset = reader.readInt16();
  const ySuperscriptYOffset = reader.readInt16();
  const yStrikeoutSize = reader.readInt16();
  const yStrikeoutPosition = reader.readInt16();
  const sFamilyClass = reader.readInt16();
  const panose = reader.readBytes(10);
  const ulUnicodeRange1 = reader.readUint32();
  const ulUnicodeRange2 = reader.readUint32();
  const ulUnicodeRange3 = reader.readUint32();
  const ulUnicodeRange4 = reader.readUint32();
  let achVendID = '';
  for (let i = 0; i < 4; i++) achVendID += String.fromCharCode(reader.readUint8());
  const fsSelection = reader.readUint16();
  const usFirstCharIndex = reader.readUint16();
  const usLastCharIndex = reader.readUint16();
  const sTypoAscender = reader.readInt16();
  const sTypoDescender = reader.readInt16();
  const sTypoLineGap = reader.readInt16();
  const usWinAscent = reader.readUint16();
  const usWinDescent = reader.readUint16();

  // Version 2+ fields
  let sCapHeight = 0;
  let sxHeight = 0;
  if (version >= 2 && tableLength >= 96) {
    reader.skip(8); // ulCodePageRange1, ulCodePageRange2
    sxHeight = reader.readInt16();
    sCapHeight = reader.readInt16();
  }

  return {
    version, xAvgCharWidth, usWeightClass, usWidthClass, fsType,
    ySubscriptXSize, ySubscriptYSize, ySubscriptXOffset, ySubscriptYOffset,
    ySuperscriptXSize, ySuperscriptYSize, ySuperscriptXOffset, ySuperscriptYOffset,
    yStrikeoutSize, yStrikeoutPosition, sFamilyClass, panose,
    ulUnicodeRange1, ulUnicodeRange2, ulUnicodeRange3, ulUnicodeRange4,
    achVendID, fsSelection, usFirstCharIndex, usLastCharIndex,
    sTypoAscender, sTypoDescender, sTypoLineGap, usWinAscent, usWinDescent,
    sCapHeight, sxHeight,
  };
}

function parsePost(reader: FontReader, offset: number): PostTable {
  reader.seek(offset);
  const format = reader.readFixed();
  const italicAngle = reader.readFixed();
  const underlinePosition = reader.readInt16();
  const underlineThickness = reader.readInt16();
  const isFixedPitch = reader.readUint32() !== 0;
  return { format, italicAngle, underlinePosition, underlineThickness, isFixedPitch };
}

function parseMaxp(reader: FontReader, offset: number): MaxpTable {
  reader.seek(offset);
  const version = reader.readFixed();
  const numGlyphs = reader.readUint16();
  return { version, numGlyphs };
}

// --------------------------------------------------------------------------
// Main parser
// --------------------------------------------------------------------------

export function parseTrueTypeFont(data: Uint8Array): TrueTypeFontData {
  const reader = new FontReader(data);

  // Read offset table
  const sfVersion = reader.readUint32();
  // Accept TrueType (0x00010000) and OpenType with TrueType outlines ('true' = 0x74727565)
  if (sfVersion !== 0x00010000 && sfVersion !== 0x74727565) {
    // Could be a TTC (TrueType Collection) - check for 'ttcf'
    if (sfVersion === 0x74746366) {
      throw new Error('TrueType Collections (.ttc) are not supported. Extract individual fonts first.');
    }
    // Could be OpenType with CFF outlines
    if (sfVersion === 0x4F54544F) {
      throw new Error('OpenType fonts with CFF outlines (OTF) are not supported. Use TrueType (.ttf) fonts.');
    }
    throw new Error(`Unsupported font format. Expected TrueType, got signature: 0x${sfVersion.toString(16)}`);
  }

  const numTables = reader.readUint16();
  reader.skip(6); // searchRange, entrySelector, rangeShift

  // Read table directory
  const tables = new Map<string, { offset: number; length: number }>();
  for (let i = 0; i < numTables; i++) {
    const tag = reader.readTag();
    const checksum = reader.readUint32();
    const tableOffset = reader.readUint32();
    const tableLength = reader.readUint32();
    tables.set(tag, { offset: tableOffset, length: tableLength });
  }

  // Verify required tables exist
  const required = ['head', 'hhea', 'hmtx', 'cmap', 'maxp'];
  for (const tag of required) {
    if (!tables.has(tag)) {
      throw new Error(`Required TrueType table '${tag}' not found`);
    }
  }

  // Parse maxp first (needed for numGlyphs)
  const maxpEntry = tables.get('maxp')!;
  const maxp = parseMaxp(reader, maxpEntry.offset);

  // Parse head
  const headEntry = tables.get('head')!;
  const head = parseHead(reader, headEntry.offset);

  // Parse hhea
  const hheaEntry = tables.get('hhea')!;
  const hhea = parseHhea(reader, hheaEntry.offset);

  // Parse hmtx
  const hmtxEntry = tables.get('hmtx')!;
  const hmtx = parseHmtx(reader, hmtxEntry.offset, hhea.numOfLongHorMetrics, maxp.numGlyphs);

  // Parse cmap
  const cmapEntry = tables.get('cmap')!;
  const cmap = parseCmap(reader, cmapEntry.offset);

  // Parse name (optional but expected)
  let name: NameTable = { fontFamily: 'Unknown', fontSubfamily: 'Regular', fullName: 'Unknown', postScriptName: 'Unknown', records: [] };
  if (tables.has('name')) {
    const nameEntry = tables.get('name')!;
    name = parseName(reader, nameEntry.offset);
  }

  // Parse OS/2 (optional but expected)
  let os2: Os2Table = {
    version: 0, xAvgCharWidth: 0, usWeightClass: 400, usWidthClass: 5, fsType: 0,
    ySubscriptXSize: 0, ySubscriptYSize: 0, ySubscriptXOffset: 0, ySubscriptYOffset: 0,
    ySuperscriptXSize: 0, ySuperscriptYSize: 0, ySuperscriptXOffset: 0, ySuperscriptYOffset: 0,
    yStrikeoutSize: 0, yStrikeoutPosition: 0, sFamilyClass: 0, panose: new Uint8Array(10),
    ulUnicodeRange1: 0, ulUnicodeRange2: 0, ulUnicodeRange3: 0, ulUnicodeRange4: 0,
    achVendID: '', fsSelection: 0, usFirstCharIndex: 0, usLastCharIndex: 0,
    sTypoAscender: hhea.ascent, sTypoDescender: hhea.descent, sTypoLineGap: hhea.lineGap,
    usWinAscent: hhea.ascent, usWinDescent: Math.abs(hhea.descent),
    sCapHeight: 0, sxHeight: 0,
  };
  if (tables.has('OS/2')) {
    const os2Entry = tables.get('OS/2')!;
    os2 = parseOs2(reader, os2Entry.offset, os2Entry.length);
  }

  // Parse post (optional)
  let post: PostTable = { format: 3, italicAngle: 0, underlinePosition: -100, underlineThickness: 50, isFixedPitch: false };
  if (tables.has('post')) {
    const postEntry = tables.get('post')!;
    post = parsePost(reader, postEntry.offset);
  }

  return {
    tables,
    head,
    hhea,
    hmtx,
    cmap,
    name,
    os2,
    post,
    maxp,
    rawData: data,
  };
}
