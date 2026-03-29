/**
 * Minimal PDF parser for the modify module.
 * Parses enough structure to identify pages and copy object graphs.
 * This is NOT a full PDF parser - it handles the subset needed for
 * merge, split, and page manipulation operations.
 */

import type { PdfObject, PdfRef, PdfDict, PdfArray, PdfStream } from '../core/types.js';
import { ObjectStore } from '../core/object-store.js';
import {
  pdfDict, pdfArray, pdfName, pdfNum, pdfStr, pdfBool,
  pdfRef, pdfStream, pdfNull, pdfHexStr,
  isRef, isDict, isArray, dictGetRef, dictGetArray, dictGetName,
} from '../core/objects.js';

export interface MiniParsedPdf {
  store: ObjectStore;
  catalogRef: PdfRef;
  pageRefs: PdfRef[];
}

/**
 * Parse a PDF from bytes, extracting objects and page structure.
 */
export function parseMiniPdf(data: Uint8Array): MiniParsedPdf {
  const parser = new PdfByteParser(data);
  return parser.parse();
}

class PdfByteParser {
  private pos = 0;
  private data: Uint8Array;
  private text: string;
  private store = new ObjectStore();
  private xrefOffsets: Map<number, number> = new Map(); // objNum -> byte offset

  constructor(data: Uint8Array) {
    this.data = data;
    // Convert to string for easier parsing of non-binary sections
    this.text = '';
    for (let i = 0; i < data.length; i++) {
      this.text += String.fromCharCode(data[i]);
    }
  }

  parse(): MiniParsedPdf {
    // 1. Find startxref
    const startxrefPos = this.text.lastIndexOf('startxref');
    if (startxrefPos === -1) {
      throw new Error('Cannot find startxref');
    }

    // 2. Read xref offset
    let p = startxrefPos + 9;
    while (p < this.text.length && isWhitespace(this.text.charCodeAt(p))) p++;
    let xrefOffsetStr = '';
    while (p < this.text.length && isDigitChar(this.text.charCodeAt(p))) {
      xrefOffsetStr += this.text[p];
      p++;
    }
    const xrefOffset = parseInt(xrefOffsetStr, 10);

    // 3. Parse xref table (or xref stream)
    let trailerDict: PdfDict | undefined;

    if (this.text.substring(xrefOffset, xrefOffset + 4) === 'xref') {
      this.parseXrefTable(xrefOffset);
      trailerDict = this.parseTrailer();
    } else {
      // Xref stream
      trailerDict = this.parseXrefStream(xrefOffset);
    }

    // Handle Prev (linked xref tables)
    if (trailerDict) {
      const prevObj = trailerDict.entries.get('Prev');
      if (prevObj && prevObj.type === 'number') {
        this.parseXrefTableChain(prevObj.value);
      }
    }

    // 4. Parse all objects using xref offsets
    for (const [objNum, offset] of this.xrefOffsets) {
      if (!this.store.has(pdfRef(objNum))) {
        this.parseObjectAt(offset);
      }
    }

    // 5. Also do a linear scan for objects not in xref (for malformed PDFs)
    this.scanForObjects();

    // 6. Find catalog
    let catalogRef: PdfRef | undefined;
    if (trailerDict) {
      catalogRef = dictGetRef(trailerDict, 'Root');
    }
    if (!catalogRef) {
      // Search for catalog in store
      for (const [ref, obj] of this.store.entries()) {
        if (obj.type === 'dict' && dictGetName(obj, 'Type') === 'Catalog') {
          catalogRef = ref;
          break;
        }
      }
    }
    if (!catalogRef) {
      throw new Error('Cannot find PDF catalog');
    }

    // 7. Collect page refs
    const pageRefs = this.collectPageRefs(catalogRef);

    return {
      store: this.store,
      catalogRef,
      pageRefs,
    };
  }

  private parseXrefTableChain(offset: number): void {
    if (this.text.substring(offset, offset + 4) === 'xref') {
      this.parseXrefTable(offset);
      // Look for another trailer
      const trailerPos = this.text.indexOf('trailer', offset);
      if (trailerPos !== -1) {
        this.pos = trailerPos + 7;
        this.skipWhitespace();
        const dict = this.parseObject() as PdfDict;
        if (dict && dict.type === 'dict') {
          const prevObj = dict.entries.get('Prev');
          if (prevObj && prevObj.type === 'number') {
            this.parseXrefTableChain(prevObj.value);
          }
        }
      }
    }
  }

  private parseXrefTable(offset: number): void {
    let p = offset + 4; // skip 'xref'
    while (p < this.text.length && isWhitespace(this.text.charCodeAt(p))) p++;

    while (p < this.text.length) {
      // Read subsection: startObj count
      if (this.text.substring(p, p + 7) === 'trailer') break;

      let numStr = '';
      while (p < this.text.length && isDigitChar(this.text.charCodeAt(p))) {
        numStr += this.text[p];
        p++;
      }
      if (numStr.length === 0) break;
      while (p < this.text.length && isWhitespace(this.text.charCodeAt(p))) p++;

      let countStr = '';
      while (p < this.text.length && isDigitChar(this.text.charCodeAt(p))) {
        countStr += this.text[p];
        p++;
      }
      while (p < this.text.length && (this.text.charCodeAt(p) === 10 || this.text.charCodeAt(p) === 13)) p++;

      const startObj = parseInt(numStr, 10);
      const count = parseInt(countStr, 10);

      for (let i = 0; i < count; i++) {
        // Each entry is exactly 20 bytes: offset(10) space gen(5) space type(1) EOL(2)
        const entryStr = this.text.substring(p, p + 20);
        p += 20;

        const entryOffset = parseInt(entryStr.substring(0, 10).trim(), 10);
        const entryType = entryStr.charAt(17);

        if (entryType === 'n' && startObj + i > 0) {
          if (!this.xrefOffsets.has(startObj + i)) {
            this.xrefOffsets.set(startObj + i, entryOffset);
          }
        }
      }
    }
  }

  private parseTrailer(): PdfDict | undefined {
    const trailerPos = this.text.lastIndexOf('trailer');
    if (trailerPos === -1) return undefined;
    this.pos = trailerPos + 7;
    this.skipWhitespace();
    const obj = this.parseObject();
    if (obj && obj.type === 'dict') return obj;
    return undefined;
  }

  private parseXrefStream(offset: number): PdfDict | undefined {
    // Xref stream starts with "objNum gen obj" then the stream dict
    this.pos = offset;
    this.parseObjectAtCurrentPos();
    // Find catalog from the xref stream object itself
    // The xref stream dict contains /Root, /Size etc. just like a trailer
    this.pos = offset;
    this.skipWhitespace();
    // Read obj number
    let numStr = '';
    while (this.pos < this.text.length && isDigitChar(this.text.charCodeAt(this.pos))) {
      numStr += this.text[this.pos]; this.pos++;
    }
    this.skipWhitespace();
    // skip gen
    while (this.pos < this.text.length && isDigitChar(this.text.charCodeAt(this.pos))) this.pos++;
    this.skipWhitespace();
    // skip 'obj'
    if (this.text.substring(this.pos, this.pos + 3) === 'obj') this.pos += 3;
    this.skipWhitespace();

    const obj = this.parseObject();
    if (obj && (obj.type === 'dict' || obj.type === 'stream')) {
      const entries = obj.type === 'dict' ? obj.entries : obj.dict;
      // Extract xref entries from stream data if available
      if (obj.type === 'stream') {
        this.parseXrefStreamData(obj, entries);
      }
      return { type: 'dict', entries: new Map(entries) };
    }
    return undefined;
  }

  private parseXrefStreamData(stream: PdfStream, dict: Map<string, PdfObject>): void {
    // Parse /W array and /Size to decode xref stream
    const wObj = dict.get('W');
    if (!wObj || wObj.type !== 'array') return;
    const w = wObj.items.map(i => i.type === 'number' ? i.value : 0);
    if (w.length < 3) return;

    const sizeObj = dict.get('Size');
    if (!sizeObj || sizeObj.type !== 'number') return;

    const indexObj = dict.get('Index');
    let ranges: number[];
    if (indexObj && indexObj.type === 'array') {
      ranges = indexObj.items.map(i => i.type === 'number' ? i.value : 0);
    } else {
      ranges = [0, sizeObj.value];
    }

    const data = stream.data;
    const entrySize = w[0] + w[1] + w[2];
    let dataPos = 0;

    for (let ri = 0; ri < ranges.length; ri += 2) {
      const startObj = ranges[ri];
      const count = ranges[ri + 1];
      for (let i = 0; i < count && dataPos + entrySize <= data.length; i++) {
        let type = 1; // default type
        if (w[0] > 0) {
          type = readIntBE(data, dataPos, w[0]);
          dataPos += w[0];
        }
        const field1 = w[1] > 0 ? readIntBE(data, dataPos, w[1]) : 0;
        dataPos += w[1];
        const field2 = w[2] > 0 ? readIntBE(data, dataPos, w[2]) : 0;
        dataPos += w[2];

        const objNum = startObj + i;
        if (type === 1 && objNum > 0) {
          // type 1: field1 = offset, field2 = gen
          if (!this.xrefOffsets.has(objNum)) {
            this.xrefOffsets.set(objNum, field1);
          }
        }
        // type 0 = free, type 2 = compressed (in object stream) - skip for now
      }
    }
  }

  private scanForObjects(): void {
    // Simple scan for "N G obj" patterns
    const regex = /(\d+)\s+(\d+)\s+obj\b/g;
    let match;
    while ((match = regex.exec(this.text)) !== null) {
      const objNum = parseInt(match[1], 10);
      if (objNum > 0 && !this.store.has(pdfRef(objNum))) {
        this.parseObjectAt(match.index);
      }
    }
  }

  private parseObjectAt(offset: number): void {
    this.pos = offset;
    this.parseObjectAtCurrentPos();
  }

  private parseObjectAtCurrentPos(): void {
    this.skipWhitespace();
    // Read: objNum gen obj
    let numStr = '';
    while (this.pos < this.text.length && isDigitChar(this.text.charCodeAt(this.pos))) {
      numStr += this.text[this.pos]; this.pos++;
    }
    const objNum = parseInt(numStr, 10);
    if (isNaN(objNum)) return;

    this.skipWhitespace();
    let genStr = '';
    while (this.pos < this.text.length && isDigitChar(this.text.charCodeAt(this.pos))) {
      genStr += this.text[this.pos]; this.pos++;
    }
    const gen = parseInt(genStr, 10);

    this.skipWhitespace();
    if (this.text.substring(this.pos, this.pos + 3) !== 'obj') return;
    this.pos += 3;
    this.skipWhitespace();

    const obj = this.parseObject();
    if (!obj) return;

    // Check if this is a stream
    this.skipWhitespace();
    if (obj.type === 'dict' && this.text.substring(this.pos, this.pos + 6) === 'stream') {
      const streamObj = this.parseStreamData(obj);
      const ref = pdfRef(objNum, gen);
      this.store.set(ref, streamObj);
      return;
    }

    const ref = pdfRef(objNum, gen);
    if (obj.type === 'stream') {
      this.store.set(ref, obj);
    } else {
      this.store.set(ref, obj);
    }
  }

  private parseStreamData(dict: PdfDict): PdfStream {
    // Skip 'stream' keyword
    this.pos += 6;
    // Skip \r\n or \n after 'stream'
    if (this.pos < this.text.length && this.data[this.pos] === 0x0D) this.pos++;
    if (this.pos < this.text.length && this.data[this.pos] === 0x0A) this.pos++;

    // Get stream length
    const lengthObj = dict.entries.get('Length');
    let length = 0;
    if (lengthObj) {
      if (lengthObj.type === 'number') {
        length = lengthObj.value;
      } else if (lengthObj.type === 'ref') {
        // Try to resolve ref
        const resolved = this.store.get(lengthObj);
        if (resolved && resolved.type === 'number') {
          length = resolved.value;
        }
      }
    }

    // If length is 0 or unknown, search for 'endstream'
    if (length <= 0) {
      const endIdx = this.text.indexOf('endstream', this.pos);
      if (endIdx !== -1) {
        length = endIdx - this.pos;
        // Trim trailing whitespace
        while (length > 0 && (this.data[this.pos + length - 1] === 0x0A || this.data[this.pos + length - 1] === 0x0D)) {
          length--;
        }
      }
    }

    const streamData = new Uint8Array(length);
    streamData.set(this.data.subarray(this.pos, this.pos + length));
    this.pos += length;

    // Skip to after 'endstream'
    const endstreamIdx = this.text.indexOf('endstream', this.pos);
    if (endstreamIdx !== -1) {
      this.pos = endstreamIdx + 9;
    }

    const streamDict = new Map(dict.entries);
    return { type: 'stream', dict: streamDict, data: streamData };
  }

  private parseObject(): PdfObject | null {
    this.skipWhitespace();
    if (this.pos >= this.text.length) return null;

    const ch = this.text[this.pos];

    // Dict or hex string
    if (ch === '<') {
      if (this.pos + 1 < this.text.length && this.text[this.pos + 1] === '<') {
        return this.parseDictionary();
      }
      return this.parseHexString();
    }

    // Array
    if (ch === '[') {
      return this.parseArray();
    }

    // String
    if (ch === '(') {
      return this.parseLiteralString();
    }

    // Name
    if (ch === '/') {
      return this.parseName();
    }

    // Number or ref
    if (isDigitChar(ch.charCodeAt(0)) || ch === '-' || ch === '+' || ch === '.') {
      return this.parseNumberOrRef();
    }

    // Keywords: true, false, null
    if (this.text.substring(this.pos, this.pos + 4) === 'true') {
      this.pos += 4;
      return pdfBool(true);
    }
    if (this.text.substring(this.pos, this.pos + 5) === 'false') {
      this.pos += 5;
      return pdfBool(false);
    }
    if (this.text.substring(this.pos, this.pos + 4) === 'null') {
      this.pos += 4;
      return pdfNull();
    }

    // endobj, endstream etc. - stop parsing
    return null;
  }

  private parseDictionary(): PdfDict {
    this.pos += 2; // skip '<<'
    const entries = new Map<string, PdfObject>();

    while (this.pos < this.text.length) {
      this.skipWhitespace();
      if (this.pos >= this.text.length) break;
      if (this.text[this.pos] === '>' && this.text[this.pos + 1] === '>') {
        this.pos += 2;
        break;
      }

      // Key must be a name
      if (this.text[this.pos] !== '/') break;
      const name = this.parseName();
      if (name.type !== 'name') break;

      this.skipWhitespace();
      const value = this.parseObject();
      if (value) {
        entries.set(name.value, value);
      }
    }

    return { type: 'dict', entries };
  }

  private parseArray(): PdfArray {
    this.pos++; // skip '['
    const items: PdfObject[] = [];

    while (this.pos < this.text.length) {
      this.skipWhitespace();
      if (this.pos >= this.text.length) break;
      if (this.text[this.pos] === ']') {
        this.pos++;
        break;
      }
      const obj = this.parseObject();
      if (obj) {
        items.push(obj);
      } else {
        break;
      }
    }

    return { type: 'array', items };
  }

  private parseName(): PdfObject {
    this.pos++; // skip '/'
    let name = '';
    while (this.pos < this.text.length) {
      const c = this.text.charCodeAt(this.pos);
      if (isWhitespace(c) || c === 0x2F || c === 0x3C || c === 0x3E ||
          c === 0x5B || c === 0x5D || c === 0x28 || c === 0x29) break;

      if (this.text[this.pos] === '#' && this.pos + 2 < this.text.length) {
        // Hex escape
        const hex = this.text.substring(this.pos + 1, this.pos + 3);
        name += String.fromCharCode(parseInt(hex, 16));
        this.pos += 3;
      } else {
        name += this.text[this.pos];
        this.pos++;
      }
    }
    return pdfName(name);
  }

  private parseLiteralString(): PdfObject {
    this.pos++; // skip '('
    const bytes: number[] = [];
    let depth = 1;

    while (this.pos < this.text.length && depth > 0) {
      const c = this.data[this.pos];
      if (c === 0x5C) { // backslash
        this.pos++;
        if (this.pos >= this.data.length) break;
        const next = this.data[this.pos];
        switch (next) {
          case 0x6E: bytes.push(0x0A); break; // \n
          case 0x72: bytes.push(0x0D); break; // \r
          case 0x74: bytes.push(0x09); break; // \t
          case 0x62: bytes.push(0x08); break; // \b
          case 0x66: bytes.push(0x0C); break; // \f
          case 0x28: bytes.push(0x28); break; // \(
          case 0x29: bytes.push(0x29); break; // \)
          case 0x5C: bytes.push(0x5C); break; // \\
          case 0x0D: // line continuation
            if (this.pos + 1 < this.data.length && this.data[this.pos + 1] === 0x0A) this.pos++;
            break;
          case 0x0A: break; // line continuation
          default:
            // Octal escape
            if (next >= 0x30 && next <= 0x37) {
              let octal = String.fromCharCode(next);
              if (this.pos + 1 < this.data.length && this.data[this.pos + 1] >= 0x30 && this.data[this.pos + 1] <= 0x37) {
                this.pos++;
                octal += String.fromCharCode(this.data[this.pos]);
                if (this.pos + 1 < this.data.length && this.data[this.pos + 1] >= 0x30 && this.data[this.pos + 1] <= 0x37) {
                  this.pos++;
                  octal += String.fromCharCode(this.data[this.pos]);
                }
              }
              bytes.push(parseInt(octal, 8));
            } else {
              bytes.push(next);
            }
        }
      } else if (c === 0x28) { // (
        depth++;
        bytes.push(c);
      } else if (c === 0x29) { // )
        depth--;
        if (depth > 0) bytes.push(c);
      } else {
        bytes.push(c);
      }
      this.pos++;
    }

    return { type: 'string', value: new Uint8Array(bytes), encoding: 'literal' };
  }

  private parseHexString(): PdfObject {
    this.pos++; // skip '<'
    let hex = '';
    while (this.pos < this.text.length && this.text[this.pos] !== '>') {
      const c = this.text[this.pos];
      if (!isWhitespace(c.charCodeAt(0))) {
        hex += c;
      }
      this.pos++;
    }
    if (this.pos < this.text.length) this.pos++; // skip '>'
    return pdfHexStr(hex);
  }

  private parseNumberOrRef(): PdfObject {
    const savedPos = this.pos;

    // Try to read a number
    let numStr = '';
    if (this.text[this.pos] === '-' || this.text[this.pos] === '+') {
      numStr += this.text[this.pos];
      this.pos++;
    }
    while (this.pos < this.text.length && (isDigitChar(this.text.charCodeAt(this.pos)) || this.text[this.pos] === '.')) {
      numStr += this.text[this.pos];
      this.pos++;
    }

    const num = parseFloat(numStr);
    if (isNaN(num)) {
      this.pos = savedPos;
      return pdfNull();
    }

    // Check if this is a reference: N G R
    if (Number.isInteger(num) && num >= 0) {
      const afterNum = this.pos;
      this.skipWhitespace();
      let genStr = '';
      while (this.pos < this.text.length && isDigitChar(this.text.charCodeAt(this.pos))) {
        genStr += this.text[this.pos];
        this.pos++;
      }
      if (genStr.length > 0) {
        this.skipWhitespace();
        if (this.pos < this.text.length && this.text[this.pos] === 'R') {
          this.pos++;
          return pdfRef(num, parseInt(genStr, 10));
        }
      }
      // Not a reference, revert
      this.pos = afterNum;
    }

    return pdfNum(num);
  }

  private skipWhitespace(): void {
    while (this.pos < this.text.length) {
      const c = this.text.charCodeAt(this.pos);
      if (isWhitespace(c)) {
        this.pos++;
      } else if (c === 0x25) { // % comment
        while (this.pos < this.text.length && this.text.charCodeAt(this.pos) !== 0x0A && this.text.charCodeAt(this.pos) !== 0x0D) {
          this.pos++;
        }
      } else {
        break;
      }
    }
  }

  /**
   * Collect all page refs from the page tree.
   */
  private collectPageRefs(catalogRef: PdfRef): PdfRef[] {
    const catalog = this.resolveRef(catalogRef);
    if (!catalog || catalog.type !== 'dict') return [];

    const pagesRef = catalog.entries.get('Pages');
    if (!pagesRef) return [];

    const pages: PdfRef[] = [];
    this.collectPagesRecursive(pagesRef, pages);
    return pages;
  }

  private collectPagesRecursive(obj: PdfObject, pages: PdfRef[]): void {
    let resolved: PdfObject | undefined;
    let ref: PdfRef | undefined;

    if (obj.type === 'ref') {
      ref = obj;
      resolved = this.store.get(obj);
    } else {
      resolved = obj;
    }

    if (!resolved || resolved.type !== 'dict') return;

    const type = dictGetName(resolved, 'Type');

    if (type === 'Page') {
      if (ref) pages.push(ref);
      return;
    }

    if (type === 'Pages') {
      const kids = dictGetArray(resolved, 'Kids');
      if (kids) {
        for (const kid of kids) {
          this.collectPagesRecursive(kid, pages);
        }
      }
    }
  }

  private resolveRef(obj: PdfObject): PdfDict | undefined {
    if (obj.type === 'ref') {
      const resolved = this.store.get(obj);
      if (resolved && resolved.type === 'dict') return resolved;
      return undefined;
    }
    if (obj.type === 'dict') return obj;
    return undefined;
  }
}

function isWhitespace(c: number): boolean {
  return c === 0x20 || c === 0x09 || c === 0x0A || c === 0x0D || c === 0x0C || c === 0x00;
}

function isDigitChar(c: number): boolean {
  return c >= 0x30 && c <= 0x39;
}

function readIntBE(data: Uint8Array, offset: number, length: number): number {
  let val = 0;
  for (let i = 0; i < length; i++) {
    val = (val << 8) | data[offset + i];
  }
  return val;
}
