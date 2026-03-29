/**
 * TrueType font subsetter.
 * Creates a minimal valid TTF containing only the glyphs actually used.
 */

import type { TrueTypeFontData } from './truetype-parser.js';

export interface SubsetResult {
  subsetBytes: Uint8Array;
  oldToNewGlyphMap: Map<number, number>;
}

// --------------------------------------------------------------------------
// Binary writer helper
// --------------------------------------------------------------------------

class FontWriter {
  private buf: Uint8Array;
  private pos: number;

  constructor(initialSize: number = 65536) {
    this.buf = new Uint8Array(initialSize);
    this.pos = 0;
  }

  private ensure(n: number): void {
    const needed = this.pos + n;
    if (needed <= this.buf.length) return;
    let cap = this.buf.length;
    while (cap < needed) cap *= 2;
    const newBuf = new Uint8Array(cap);
    newBuf.set(this.buf, 0);
    this.buf = newBuf;
  }

  get position(): number { return this.pos; }

  seek(offset: number): void { this.pos = offset; }

  writeUint8(v: number): void {
    this.ensure(1);
    this.buf[this.pos++] = v & 0xff;
  }

  writeUint16(v: number): void {
    this.ensure(2);
    this.buf[this.pos++] = (v >>> 8) & 0xff;
    this.buf[this.pos++] = v & 0xff;
  }

  writeInt16(v: number): void {
    this.writeUint16(v & 0xffff);
  }

  writeUint32(v: number): void {
    this.ensure(4);
    this.buf[this.pos++] = (v >>> 24) & 0xff;
    this.buf[this.pos++] = (v >>> 16) & 0xff;
    this.buf[this.pos++] = (v >>> 8) & 0xff;
    this.buf[this.pos++] = v & 0xff;
  }

  writeInt32(v: number): void {
    this.writeUint32(v >>> 0);
  }

  writeBytes(data: Uint8Array): void {
    this.ensure(data.length);
    this.buf.set(data, this.pos);
    this.pos += data.length;
  }

  // Pad to 4-byte boundary
  pad4(): void {
    while (this.pos % 4 !== 0) {
      this.writeUint8(0);
    }
  }

  toUint8Array(): Uint8Array {
    return this.buf.slice(0, this.pos);
  }
}

// --------------------------------------------------------------------------
// Reader helper for raw font data
// --------------------------------------------------------------------------

class RawReader {
  private view: DataView;

  constructor(private data: Uint8Array) {
    this.view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  }

  uint16(offset: number): number { return this.view.getUint16(offset, false); }
  int16(offset: number): number { return this.view.getInt16(offset, false); }
  uint32(offset: number): number { return this.view.getUint32(offset, false); }
  int32(offset: number): number { return this.view.getInt32(offset, false); }

  slice(offset: number, length: number): Uint8Array {
    return this.data.slice(offset, offset + length);
  }
}

// --------------------------------------------------------------------------
// Compute checksum for a table
// --------------------------------------------------------------------------

function calcChecksum(data: Uint8Array): number {
  let sum = 0;
  const nLongs = Math.ceil(data.length / 4);
  const padded = new Uint8Array(nLongs * 4);
  padded.set(data, 0);
  const view = new DataView(padded.buffer);
  for (let i = 0; i < nLongs; i++) {
    sum = (sum + view.getUint32(i * 4, false)) >>> 0;
  }
  return sum;
}

// --------------------------------------------------------------------------
// Get glyph data from glyf table, handling composite glyphs
// --------------------------------------------------------------------------

function getGlyphOffsets(raw: RawReader, locaOffset: number, indexToLocFormat: number, glyphIndex: number): { offset: number; length: number } {
  if (indexToLocFormat === 0) {
    // Short format: offsets are in 16-bit words (multiply by 2)
    const off1 = raw.uint16(locaOffset + glyphIndex * 2) * 2;
    const off2 = raw.uint16(locaOffset + (glyphIndex + 1) * 2) * 2;
    return { offset: off1, length: off2 - off1 };
  } else {
    // Long format: offsets are 32-bit
    const off1 = raw.uint32(locaOffset + glyphIndex * 4);
    const off2 = raw.uint32(locaOffset + (glyphIndex + 1) * 4);
    return { offset: off1, length: off2 - off1 };
  }
}

function collectCompositeGlyphs(raw: RawReader, glyfOffset: number, locaOffset: number, indexToLocFormat: number, glyphIndex: number, collected: Set<number>): void {
  if (collected.has(glyphIndex)) return;
  collected.add(glyphIndex);

  const loc = getGlyphOffsets(raw, locaOffset, indexToLocFormat, glyphIndex);
  if (loc.length === 0) return; // Empty glyph (e.g., space)

  const glyphStart = glyfOffset + loc.offset;
  const numberOfContours = raw.int16(glyphStart);

  if (numberOfContours >= 0) return; // Simple glyph, no sub-components

  // Composite glyph - parse components
  let offset = glyphStart + 10; // Skip header (numberOfContours, xMin, yMin, xMax, yMax)
  const MORE_COMPONENTS = 0x0020;
  const ARG_1_AND_2_ARE_WORDS = 0x0001;
  const WE_HAVE_A_SCALE = 0x0008;
  const WE_HAVE_AN_X_AND_Y_SCALE = 0x0040;
  const WE_HAVE_A_TWO_BY_TWO = 0x0080;

  let flags: number;
  do {
    flags = raw.uint16(offset);
    const componentGlyphIndex = raw.uint16(offset + 2);
    offset += 4;

    collectCompositeGlyphs(raw, glyfOffset, locaOffset, indexToLocFormat, componentGlyphIndex, collected);

    // Skip arguments
    if (flags & ARG_1_AND_2_ARE_WORDS) {
      offset += 4;
    } else {
      offset += 2;
    }
    // Skip transformation
    if (flags & WE_HAVE_A_SCALE) {
      offset += 2;
    } else if (flags & WE_HAVE_AN_X_AND_Y_SCALE) {
      offset += 4;
    } else if (flags & WE_HAVE_A_TWO_BY_TWO) {
      offset += 8;
    }
  } while (flags & MORE_COMPONENTS);
}

function remapCompositeGlyph(glyphData: Uint8Array, oldToNew: Map<number, number>): Uint8Array {
  const result = new Uint8Array(glyphData.length);
  result.set(glyphData, 0);
  const view = new DataView(result.buffer, result.byteOffset, result.byteLength);

  const numberOfContours = view.getInt16(0, false);
  if (numberOfContours >= 0) return result; // Simple glyph

  let offset = 10;
  const MORE_COMPONENTS = 0x0020;
  const ARG_1_AND_2_ARE_WORDS = 0x0001;
  const WE_HAVE_A_SCALE = 0x0008;
  const WE_HAVE_AN_X_AND_Y_SCALE = 0x0040;
  const WE_HAVE_A_TWO_BY_TWO = 0x0080;

  let flags: number;
  do {
    flags = view.getUint16(offset, false);
    const oldGlyphIndex = view.getUint16(offset + 2, false);
    const newGlyphIndex = oldToNew.get(oldGlyphIndex) ?? 0;
    view.setUint16(offset + 2, newGlyphIndex, false);
    offset += 4;

    if (flags & ARG_1_AND_2_ARE_WORDS) {
      offset += 4;
    } else {
      offset += 2;
    }
    if (flags & WE_HAVE_A_SCALE) {
      offset += 2;
    } else if (flags & WE_HAVE_AN_X_AND_Y_SCALE) {
      offset += 4;
    } else if (flags & WE_HAVE_A_TWO_BY_TWO) {
      offset += 8;
    }
  } while (flags & MORE_COMPONENTS);

  return result;
}

// --------------------------------------------------------------------------
// Main subsetter
// --------------------------------------------------------------------------

export function subsetTrueTypeFont(
  fontData: Uint8Array,
  parsedFont: TrueTypeFontData,
  usedGlyphs: Set<number>,
): SubsetResult {
  const raw = new RawReader(fontData);
  const { tables, head, hhea, maxp, hmtx } = parsedFont;

  // We need glyf and loca tables
  const glyfEntry = tables.get('glyf');
  const locaEntry = tables.get('loca');
  if (!glyfEntry || !locaEntry) {
    throw new Error('Font missing glyf or loca table; cannot subset');
  }

  // Step 1: Collect all needed glyphs (including .notdef=0 and composite dependencies)
  const allGlyphs = new Set<number>();
  allGlyphs.add(0); // Always include .notdef

  for (const gid of usedGlyphs) {
    collectCompositeGlyphs(raw, glyfEntry.offset, locaEntry.offset, head.indexToLocFormat, gid, allGlyphs);
  }

  // Step 2: Sort glyph indices and create old->new mapping
  const sortedGlyphs = Array.from(allGlyphs).sort((a, b) => a - b);
  const oldToNew = new Map<number, number>();
  for (let i = 0; i < sortedGlyphs.length; i++) {
    oldToNew.set(sortedGlyphs[i], i);
  }

  const newNumGlyphs = sortedGlyphs.length;

  // Step 3: Extract and remap glyph data, build new loca
  const glyphDatas: Uint8Array[] = [];
  const newLocaOffsets: number[] = [];
  let currentOffset = 0;

  for (const oldGid of sortedGlyphs) {
    newLocaOffsets.push(currentOffset);
    const loc = getGlyphOffsets(raw, locaEntry.offset, head.indexToLocFormat, oldGid);
    if (loc.length === 0) {
      glyphDatas.push(new Uint8Array(0));
    } else {
      let glyphBytes = raw.slice(glyfEntry.offset + loc.offset, loc.length);
      // Remap composite glyph references
      glyphBytes = remapCompositeGlyph(glyphBytes, oldToNew);
      glyphDatas.push(glyphBytes);
      // Pad to even boundary for loca
      const paddedLen = (glyphBytes.length + 1) & ~1;
      currentOffset += paddedLen;
    }
  }
  newLocaOffsets.push(currentOffset); // Final offset entry

  // Step 4: Decide loca format (short if possible)
  const useShortLoca = currentOffset <= 0x1FFFE; // max offset in short format
  const newIndexToLocFormat = useShortLoca ? 0 : 1;

  // Step 5: Build tables
  const tableBuilders: { tag: string; data: Uint8Array }[] = [];

  // -- head table --
  const headData = raw.slice(tables.get('head')!.offset, tables.get('head')!.length);
  const headView = new DataView(headData.buffer, headData.byteOffset, headData.byteLength);
  // Update indexToLocFormat
  headView.setInt16(50, newIndexToLocFormat, false);
  // Zero out checksumAdjustment (offset 8)
  headView.setUint32(8, 0, false);
  tableBuilders.push({ tag: 'head', data: headData });

  // -- hhea table --
  const hheaData = raw.slice(tables.get('hhea')!.offset, tables.get('hhea')!.length);
  const hheaView = new DataView(hheaData.buffer, hheaData.byteOffset, hheaData.byteLength);
  // Update numOfLongHorMetrics to newNumGlyphs
  hheaView.setUint16(hheaData.length - 2, newNumGlyphs, false);
  tableBuilders.push({ tag: 'hhea', data: hheaData });

  // -- hmtx table --
  const hmtxWriter = new FontWriter(newNumGlyphs * 4);
  for (const oldGid of sortedGlyphs) {
    hmtxWriter.writeUint16(hmtx.advanceWidths[oldGid] || 0);
    hmtxWriter.writeInt16(hmtx.leftSideBearings[oldGid] || 0);
  }
  tableBuilders.push({ tag: 'hmtx', data: hmtxWriter.toUint8Array() });

  // -- maxp table --
  const maxpData = raw.slice(tables.get('maxp')!.offset, tables.get('maxp')!.length);
  const maxpView = new DataView(maxpData.buffer, maxpData.byteOffset, maxpData.byteLength);
  maxpView.setUint16(4, newNumGlyphs, false); // numGlyphs
  tableBuilders.push({ tag: 'maxp', data: maxpData });

  // -- loca table --
  const locaWriter = new FontWriter((newNumGlyphs + 1) * (useShortLoca ? 2 : 4));
  for (const off of newLocaOffsets) {
    if (useShortLoca) {
      locaWriter.writeUint16(off >>> 1);
    } else {
      locaWriter.writeUint32(off);
    }
  }
  tableBuilders.push({ tag: 'loca', data: locaWriter.toUint8Array() });

  // -- glyf table --
  const glyfWriter = new FontWriter(currentOffset + 16);
  for (const gdata of glyphDatas) {
    glyfWriter.writeBytes(gdata);
    // Pad to 2-byte boundary
    if (gdata.length % 2 !== 0) {
      glyfWriter.writeUint8(0);
    }
  }
  tableBuilders.push({ tag: 'glyf', data: glyfWriter.toUint8Array() });

  // -- cmap table (format 4 for BMP) --
  const cmapData = buildCmapTable(parsedFont.cmap, oldToNew);
  tableBuilders.push({ tag: 'cmap', data: cmapData });

  // -- name table (copy original) --
  if (tables.has('name')) {
    const nameEntry = tables.get('name')!;
    tableBuilders.push({ tag: 'name', data: raw.slice(nameEntry.offset, nameEntry.length) });
  }

  // -- post table (minimal format 3) --
  const postWriter = new FontWriter(32);
  postWriter.writeUint32(0x00030000); // format 3.0 (no glyph names)
  // italicAngle as Fixed
  const ia = parsedFont.post.italicAngle;
  const iaInt = Math.floor(ia);
  const iaFrac = Math.round((ia - iaInt) * 65536);
  postWriter.writeInt32(((iaInt & 0xffff) << 16) | (iaFrac & 0xffff));
  postWriter.writeInt16(parsedFont.post.underlinePosition);
  postWriter.writeInt16(parsedFont.post.underlineThickness);
  postWriter.writeUint32(parsedFont.post.isFixedPitch ? 1 : 0);
  postWriter.writeUint32(0); // minMemType42
  postWriter.writeUint32(0); // maxMemType42
  postWriter.writeUint32(0); // minMemType1
  postWriter.writeUint32(0); // maxMemType1
  tableBuilders.push({ tag: 'post', data: postWriter.toUint8Array() });

  // -- OS/2 table (copy original if present) --
  if (tables.has('OS/2')) {
    const os2Entry = tables.get('OS/2')!;
    tableBuilders.push({ tag: 'OS/2', data: raw.slice(os2Entry.offset, os2Entry.length) });
  }

  // Step 6: Assemble the final TTF
  const numTables = tableBuilders.length;
  // Calculate searchRange, entrySelector, rangeShift
  let searchRange = 1;
  let entrySelector = 0;
  while (searchRange * 2 <= numTables) {
    searchRange *= 2;
    entrySelector++;
  }
  searchRange *= 16;
  const rangeShift = numTables * 16 - searchRange;

  // Sort tables by tag for consistent output
  tableBuilders.sort((a, b) => a.tag < b.tag ? -1 : a.tag > b.tag ? 1 : 0);

  const headerSize = 12 + numTables * 16;
  // Calculate total size
  let totalSize = headerSize;
  for (const t of tableBuilders) {
    totalSize += (t.data.length + 3) & ~3; // 4-byte aligned
  }

  const out = new FontWriter(totalSize + 16);

  // Offset table
  out.writeUint32(0x00010000); // sfVersion
  out.writeUint16(numTables);
  out.writeUint16(searchRange);
  out.writeUint16(entrySelector);
  out.writeUint16(rangeShift);

  // Table directory placeholder - will fill in offsets after writing data
  const dirStart = out.position;
  for (let i = 0; i < numTables; i++) {
    out.writeUint32(0); // tag
    out.writeUint32(0); // checksum
    out.writeUint32(0); // offset
    out.writeUint32(0); // length
  }

  // Write table data and record positions
  const tablePositions: { tag: string; checksum: number; offset: number; length: number }[] = [];
  for (const t of tableBuilders) {
    out.pad4();
    const tableOffset = out.position;
    out.writeBytes(t.data);
    const checksum = calcChecksum(t.data);
    tablePositions.push({ tag: t.tag, checksum, offset: tableOffset, length: t.data.length });
  }

  // Go back and fill in table directory
  const result = out.toUint8Array();
  const resultView = new DataView(result.buffer, result.byteOffset, result.byteLength);
  for (let i = 0; i < numTables; i++) {
    const dirOffset = dirStart + i * 16;
    const tp = tablePositions[i];
    // Write tag
    for (let j = 0; j < 4; j++) {
      result[dirOffset + j] = tp.tag.charCodeAt(j);
    }
    resultView.setUint32(dirOffset + 4, tp.checksum, false);
    resultView.setUint32(dirOffset + 8, tp.offset, false);
    resultView.setUint32(dirOffset + 12, tp.length, false);
  }

  return { subsetBytes: result, oldToNewGlyphMap: oldToNew };
}

// --------------------------------------------------------------------------
// Build a cmap table with format 4 subtable
// --------------------------------------------------------------------------

function buildCmapTable(originalCmap: Map<number, number>, oldToNew: Map<number, number>): Uint8Array {
  // Build new mapping: unicode -> new glyph index
  const newMapping: [number, number][] = [];
  for (const [unicode, oldGid] of originalCmap) {
    const newGid = oldToNew.get(oldGid);
    if (newGid !== undefined && unicode <= 0xFFFF) {
      newMapping.push([unicode, newGid]);
    }
  }
  newMapping.sort((a, b) => a[0] - b[0]);

  // Build segments for format 4
  const segments: { start: number; end: number; glyphs: number[] }[] = [];
  let currentSeg: { start: number; end: number; glyphs: number[] } | null = null;

  for (const [unicode, gid] of newMapping) {
    if (currentSeg && unicode === currentSeg.end + 1) {
      currentSeg.end = unicode;
      currentSeg.glyphs.push(gid);
    } else {
      if (currentSeg) segments.push(currentSeg);
      currentSeg = { start: unicode, end: unicode, glyphs: [gid] };
    }
  }
  if (currentSeg) segments.push(currentSeg);
  // Add sentinel segment
  segments.push({ start: 0xFFFF, end: 0xFFFF, glyphs: [0] });

  const segCount = segments.length;

  // For simplicity, use idRangeOffset approach for all segments
  // Calculate sizes
  const glyphIdArrayEntries: number[] = [];
  const idRangeOffsets: number[] = [];
  const idDeltas: number[] = [];
  const startCodes: number[] = [];
  const endCodes: number[] = [];

  for (const seg of segments) {
    startCodes.push(seg.start);
    endCodes.push(seg.end);

    if (seg.start === 0xFFFF) {
      idDeltas.push(1);
      idRangeOffsets.push(0);
    } else {
      // Check if we can use delta encoding
      let canUseDelta = true;
      const delta = (seg.glyphs[0] - seg.start) & 0xFFFF;
      for (let i = 0; i < seg.glyphs.length; i++) {
        if (((seg.start + i + delta) & 0xFFFF) !== seg.glyphs[i]) {
          canUseDelta = false;
          break;
        }
      }

      if (canUseDelta) {
        idDeltas.push(delta > 0x7FFF ? delta - 0x10000 : delta);
        idRangeOffsets.push(0);
      } else {
        idDeltas.push(0);
        // idRangeOffset is relative to its own position in the idRangeOffset array
        // offset = (segCount - currentSegIndex + glyphIdArrayEntries.length) * 2
        const currentArrayPos = glyphIdArrayEntries.length;
        idRangeOffsets.push(-1); // placeholder, will fix below
        for (const gid of seg.glyphs) {
          glyphIdArrayEntries.push(gid);
        }
      }
    }
  }

  // Fix up idRangeOffsets
  for (let i = 0; i < segCount; i++) {
    if (idRangeOffsets[i] === -1) {
      // Count how many glyphs come before this segment's glyphs in the array
      let glyphsBefore = 0;
      for (let j = 0; j < i; j++) {
        if (idRangeOffsets[j] === -1 || (idRangeOffsets[j] !== 0 && segments[j].start !== 0xFFFF)) {
          glyphsBefore += segments[j].glyphs.length;
        }
      }
      // Recalculate
      let arrayOffset = 0;
      for (let j = 0; j < i; j++) {
        if (idRangeOffsets[j] !== 0 && segments[j].start !== 0xFFFF) {
          // This has been recorded already
        }
      }
      // Simple approach: rebuild
    }
  }

  // Rebuild with a simpler approach: all segments use glyphIdArray
  const glyphIds: number[] = [];
  const rangeOffsets: number[] = [];
  const deltas: number[] = [];

  for (let i = 0; i < segCount; i++) {
    const seg = segments[i];
    if (seg.start === 0xFFFF) {
      deltas.push(1);
      rangeOffsets.push(0);
    } else {
      // Check delta approach
      let canUseDelta = true;
      const d = (seg.glyphs[0] - seg.start) & 0xFFFF;
      for (let j = 0; j < seg.glyphs.length; j++) {
        if (((seg.start + j + d) & 0xFFFF) !== seg.glyphs[j]) {
          canUseDelta = false;
          break;
        }
      }
      if (canUseDelta) {
        deltas.push(d > 0x7FFF ? d - 0x10000 : d);
        rangeOffsets.push(0);
      } else {
        deltas.push(0);
        // Offset from this entry to the start of its glyph data in glyphIdArray
        // Position of this rangeOffset entry: at position (segCount - 1 - i) entries from end of rangeOffset array
        // Distance in uint16 units: (segCount - i) + currentGlyphIdsLength
        const ofs = (segCount - i + glyphIds.length) * 2;
        rangeOffsets.push(ofs);
        for (const gid of seg.glyphs) {
          glyphIds.push(gid);
        }
      }
    }
  }

  // Build format 4 subtable
  const subtableLength = 14 + segCount * 8 + glyphIds.length * 2;
  let entrySelector = 0;
  let searchRange2 = 1;
  while (searchRange2 * 2 <= segCount) {
    searchRange2 *= 2;
    entrySelector++;
  }
  searchRange2 *= 2;
  const rangeShift2 = segCount * 2 - searchRange2;

  const writer = new FontWriter(4 + 8 + subtableLength);

  // cmap header
  writer.writeUint16(0); // version
  writer.writeUint16(1); // numTables

  // Encoding record: platform 3 (Windows), encoding 1 (BMP)
  writer.writeUint16(3); // platformID
  writer.writeUint16(1); // encodingID
  writer.writeUint32(12); // offset to subtable

  // Format 4 subtable
  writer.writeUint16(4); // format
  writer.writeUint16(subtableLength); // length
  writer.writeUint16(0); // language
  writer.writeUint16(segCount * 2); // segCountX2
  writer.writeUint16(searchRange2);
  writer.writeUint16(entrySelector);
  writer.writeUint16(rangeShift2);

  for (const ec of endCodes) writer.writeUint16(ec);
  writer.writeUint16(0); // reservedPad
  for (const sc of startCodes) writer.writeUint16(sc);
  for (const d of deltas) writer.writeInt16(d);
  for (const ro of rangeOffsets) writer.writeUint16(ro);
  for (const gid of glyphIds) writer.writeUint16(gid);

  return writer.toUint8Array();
}
