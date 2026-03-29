/**
 * Main PDF parser entry point.
 * Parses a PDF file from raw bytes into a structured document representation.
 */

import type { PdfObject, PdfRef, PdfDict, PdfStream, PdfArray } from '../core/types.js';
import {
  pdfRef, pdfNull, pdfDict, pdfStream, pdfName,
  dictGet, dictGetName, dictGetNumber, dictGetRef, dictGetArray,
  dictGetString as coreDictGetString, dictGetDict, dictGetBool,
  isRef, isDict, isName, isNumber, isString, isStream, isArray, isNull,
} from '../core/objects.js';
import { ObjectStore } from '../core/object-store.js';
import { Tokenizer } from './tokenizer.js';
import { ObjectParser } from './object-parser.js';
import { parseXrefTable, parseXrefStream } from './xref-parser.js';
import type { XrefEntry } from './xref-parser.js';
import { parseTrailer, extractTrailerInfo } from './trailer-parser.js';
import type { TrailerInfo } from './trailer-parser.js';
import { decodeStream } from './stream-decoder.js';
import { parseContentStream } from './content-stream-parser.js';
import { extractText as extractTextItems } from './text-extractor.js';
import type { ExtractedTextItem } from './text-extractor.js';
import { extractImages as extractImageItems } from './image-extractor.js';
import type { ExtractedImage } from './image-extractor.js';
import { repairXref } from './repair.js';
import { md5 } from '../security/md5.js';
import { rc4 } from '../security/rc4.js';

// ---- Public Types ----

export interface ParsedDocument {
  version: string;
  store: ObjectStore;
  catalog: PdfDict;
  catalogRef: PdfRef;
  info?: PdfDict;
  pageCount: number;
  getPage(index: number): ParsedPage;
  getPageRef(index: number): PdfRef;
  getOutline(): OutlineNode[];
  getFormFields(): FormFieldInfo[];
  isEncrypted: boolean;
  prevXrefOffset: number;
  fileId: Uint8Array[];
}

export interface ParsedPage {
  ref: PdfRef;
  dict: PdfDict;
  mediaBox: [number, number, number, number];
  rotation: number;
  extractText(): Promise<ExtractedTextItem[]>;
  extractImages(): Promise<ExtractedImage[]>;
  getAnnotations(): PdfDict[];
}

export interface OutlineNode {
  title: string;
  destination?: any;
  children: OutlineNode[];
  bold: boolean;
  italic: boolean;
}

export interface FormFieldInfo {
  name: string;
  type: string;
  value: any;
  ref: PdfRef;
}

// ---- Encryption Support ----

/**
 * PDF Standard Security Handler (RC4, up to 128-bit).
 * Handles password validation and object decryption.
 */
class SecurityHandler {
  private encryptionKey: Uint8Array;
  private revision: number;
  private keyLength: number; // in bytes

  constructor(
    private encryptDict: PdfDict,
    private fileId: Uint8Array,
    password: string,
  ) {
    this.revision = dictGetNumber(encryptDict, 'R') ?? 2;
    const keyBits = dictGetNumber(encryptDict, 'Length') ?? 40;
    this.keyLength = keyBits / 8;

    this.encryptionKey = this.computeEncryptionKey(password);

    if (!this.validatePassword()) {
      throw new Error('Invalid password');
    }
  }

  private computeEncryptionKey(password: string): Uint8Array {
    // PDF password padding string (32 bytes)
    const padding = new Uint8Array([
      0x28, 0xbf, 0x4e, 0x5e, 0x4e, 0x75, 0x8a, 0x41,
      0x64, 0x00, 0x4b, 0x49, 0x43, 0x4b, 0x53, 0x20,
      0x2d, 0x20, 0x43, 0x6f, 0x70, 0x79, 0x72, 0x69,
      0x67, 0x68, 0x74, 0x20, 0x28, 0x43, 0x29, 0x20,
    ]);

    // Pad or truncate the password to 32 bytes
    const passBytes = new Uint8Array(32);
    for (let i = 0; i < 32; i++) {
      if (i < password.length) {
        passBytes[i] = password.charCodeAt(i) & 0xff;
      } else {
        passBytes[i] = padding[i - password.length];
      }
    }

    // Algorithm 2: compute encryption key
    // Step a: password (padded)
    const buf = new Uint8Array(
      32 +                    // padded password
      32 +                    // O value
      4 +                     // P value
      this.fileId.length +    // file ID
      (this.revision >= 4 ? 4 : 0) // EncryptMetadata flag
    );

    let offset = 0;
    buf.set(passBytes, offset); offset += 32;

    // Step b: O value
    const oValue = this.getStringValue('O');
    if (oValue) {
      buf.set(oValue.subarray(0, 32), offset);
    }
    offset += 32;

    // Step c: P value (as little-endian 32-bit)
    const pValue = dictGetNumber(this.encryptDict, 'P') ?? 0;
    buf[offset] = pValue & 0xff;
    buf[offset + 1] = (pValue >> 8) & 0xff;
    buf[offset + 2] = (pValue >> 16) & 0xff;
    buf[offset + 3] = (pValue >> 24) & 0xff;
    offset += 4;

    // Step d: file ID
    buf.set(this.fileId, offset);
    offset += this.fileId.length;

    // Step e: If R >= 4 and EncryptMetadata is false, append 0xFFFFFFFF
    if (this.revision >= 4) {
      const encryptMetadata = dictGetBool(this.encryptDict, 'EncryptMetadata');
      if (encryptMetadata === false) {
        buf[offset] = 0xff; buf[offset + 1] = 0xff;
        buf[offset + 2] = 0xff; buf[offset + 3] = 0xff;
        offset += 4;
      }
    }

    let hash = md5(buf.subarray(0, offset));

    // Step f: If R >= 3, repeat MD5 50 times
    if (this.revision >= 3) {
      for (let i = 0; i < 50; i++) {
        hash = md5(hash.subarray(0, this.keyLength));
      }
    }

    return hash.subarray(0, this.keyLength);
  }

  private validatePassword(): boolean {
    // Try user password validation
    if (this.revision === 2) {
      return this.validateUserPasswordR2();
    }
    return this.validateUserPasswordR3();
  }

  private validateUserPasswordR2(): boolean {
    const padding = new Uint8Array([
      0x28, 0xbf, 0x4e, 0x5e, 0x4e, 0x75, 0x8a, 0x41,
      0x64, 0x00, 0x4b, 0x49, 0x43, 0x4b, 0x53, 0x20,
      0x2d, 0x20, 0x43, 0x6f, 0x70, 0x79, 0x72, 0x69,
      0x67, 0x68, 0x74, 0x20, 0x28, 0x43, 0x29, 0x20,
    ]);

    const computed = rc4(this.encryptionKey, padding);
    const uValue = this.getStringValue('U');
    if (!uValue) return false;

    for (let i = 0; i < 32; i++) {
      if (computed[i] !== uValue[i]) return false;
    }
    return true;
  }

  private validateUserPasswordR3(): boolean {
    const padding = new Uint8Array([
      0x28, 0xbf, 0x4e, 0x5e, 0x4e, 0x75, 0x8a, 0x41,
      0x64, 0x00, 0x4b, 0x49, 0x43, 0x4b, 0x53, 0x20,
      0x2d, 0x20, 0x43, 0x6f, 0x70, 0x79, 0x72, 0x69,
      0x67, 0x68, 0x74, 0x20, 0x28, 0x43, 0x29, 0x20,
    ]);

    // Hash padding + file ID
    const buf = new Uint8Array(32 + this.fileId.length);
    buf.set(padding);
    buf.set(this.fileId, 32);
    let hash = md5(buf);

    // RC4 with encryption key
    let result = rc4(this.encryptionKey, hash);

    // 19 more iterations
    for (let i = 1; i <= 19; i++) {
      const key = new Uint8Array(this.encryptionKey.length);
      for (let j = 0; j < this.encryptionKey.length; j++) {
        key[j] = this.encryptionKey[j] ^ i;
      }
      result = rc4(key, result);
    }

    // Compare first 16 bytes with U value
    const uValue = this.getStringValue('U');
    if (!uValue) return false;

    for (let i = 0; i < 16; i++) {
      if (result[i] !== uValue[i]) return false;
    }
    return true;
  }

  private getStringValue(key: string): Uint8Array | null {
    const obj = dictGet(this.encryptDict, key);
    if (obj && isString(obj)) return obj.value;
    return null;
  }

  /**
   * Compute the decryption key for a specific indirect object.
   */
  computeObjectKey(objNum: number, genNum: number): Uint8Array {
    // Algorithm 1: compute per-object key
    const buf = new Uint8Array(this.encryptionKey.length + 5);
    buf.set(this.encryptionKey);
    const offset = this.encryptionKey.length;
    buf[offset] = objNum & 0xff;
    buf[offset + 1] = (objNum >> 8) & 0xff;
    buf[offset + 2] = (objNum >> 16) & 0xff;
    buf[offset + 3] = genNum & 0xff;
    buf[offset + 4] = (genNum >> 8) & 0xff;

    const hash = md5(buf);
    const keyLen = Math.min(this.encryptionKey.length + 5, 16);
    return hash.subarray(0, keyLen);
  }

  /**
   * Decrypt data for a specific indirect object.
   */
  decryptData(data: Uint8Array, objNum: number, genNum: number): Uint8Array {
    const key = this.computeObjectKey(objNum, genNum);
    return rc4(key, data);
  }

  /**
   * Decrypt a string value for a specific indirect object.
   */
  decryptString(str: Uint8Array, objNum: number, genNum: number): Uint8Array {
    return this.decryptData(str, objNum, genNum);
  }
}

// ---- Main Parser ----

/**
 * Parse a PDF document from raw bytes.
 */
export async function parsePdf(data: Uint8Array, password?: string): Promise<ParsedDocument> {
  // 1. Find PDF version from header
  const version = parseVersion(data);

  // 2. Find startxref offset
  const startXrefOffset = findStartXref(data);

  // 3. Parse cross-reference tables and trailers
  let xrefEntries: XrefEntry[] = [];
  let trailerInfo: TrailerInfo;
  let useRepair = false;

  try {
    const result = await parseXrefChain(data, startXrefOffset);
    xrefEntries = result.entries;
    trailerInfo = result.trailer;
  } catch {
    // Xref parsing failed, try repair
    useRepair = true;
    xrefEntries = repairXref(data);
    // We still need a trailer - try to find it
    trailerInfo = findTrailerByScanning(data);
  }

  // 4. Build object store with lazy loading
  const store = new ObjectStore();
  const xrefMap = buildXrefMap(xrefEntries);

  // Security handler for encrypted documents
  let securityHandler: SecurityHandler | null = null;
  const isEncrypted = !!trailerInfo.encrypt;
  const fileId: Uint8Array[] = trailerInfo.id ? [trailerInfo.id[0], trailerInfo.id[1]] : [];

  // Set up decryption if encrypted
  if (isEncrypted && trailerInfo.encrypt) {
    // We need to parse the encrypt dict first
    const encryptEntry = xrefMap.get(trailerInfo.encrypt.objectNumber);
    if (encryptEntry) {
      const encryptObj = parseObjectAtOffset(data, encryptEntry.offset);
      if (encryptObj && isDict(encryptObj)) {
        store.set(trailerInfo.encrypt, encryptObj);
        try {
          securityHandler = new SecurityHandler(
            encryptObj,
            fileId.length > 0 ? fileId[0] : new Uint8Array(0),
            password ?? '',
          );
        } catch {
          // Try empty password if provided password failed
          if (password) {
            try {
              securityHandler = new SecurityHandler(
                encryptObj,
                fileId.length > 0 ? fileId[0] : new Uint8Array(0),
                '',
              );
            } catch {
              throw new Error('Invalid password');
            }
          } else {
            throw new Error('Document is encrypted and requires a password');
          }
        }
      }
    }
  }

  // Load all objects from xref
  for (const entry of xrefEntries) {
    if (entry.free) continue;
    if (store.has(pdfRef(entry.objectNumber, entry.generation))) continue;

    if (entry.compressed) {
      // Will be loaded when the object stream is decoded
      continue;
    }

    try {
      let obj = parseObjectAtOffset(data, entry.offset);
      if (obj) {
        // Decrypt if needed
        if (securityHandler && !isEncryptDict(trailerInfo, entry.objectNumber)) {
          obj = decryptObject(obj, entry.objectNumber, entry.generation, securityHandler);
        }
        store.set(pdfRef(entry.objectNumber, entry.generation), obj);
      }
    } catch {
      // Skip objects that fail to parse
    }
  }

  // Load compressed objects from object streams
  const compressedEntries = xrefEntries.filter(e => e.compressed);
  if (compressedEntries.length > 0) {
    await loadCompressedObjects(data, compressedEntries, xrefMap, store, securityHandler, trailerInfo);
  }

  // 5. Resolve catalog
  const catalogObj = resolveObj(trailerInfo.root, store);
  if (!catalogObj || !isDict(catalogObj)) {
    throw new Error('Failed to resolve document catalog');
  }
  const catalog = catalogObj;

  // 6. Resolve info dict
  let info: PdfDict | undefined;
  if (trailerInfo.info) {
    const infoObj = resolveObj(trailerInfo.info, store);
    if (infoObj && isDict(infoObj)) {
      info = infoObj;
    }
  }

  // 7. Build page list
  const pageList = buildPageList(catalog, store);

  // 8. Build document
  const doc: ParsedDocument = {
    version,
    store,
    catalog,
    catalogRef: trailerInfo.root,
    info,
    pageCount: pageList.length,
    isEncrypted,
    prevXrefOffset: startXrefOffset,
    fileId,

    getPage(index: number): ParsedPage {
      if (index < 0 || index >= pageList.length) {
        throw new RangeError(`Page index ${index} out of range (0-${pageList.length - 1})`);
      }
      return createParsedPage(pageList[index], store);
    },

    getPageRef(index: number): PdfRef {
      if (index < 0 || index >= pageList.length) {
        throw new RangeError(`Page index ${index} out of range (0-${pageList.length - 1})`);
      }
      return pageList[index].ref;
    },

    getOutline(): OutlineNode[] {
      return parseOutlines(catalog, store);
    },

    getFormFields(): FormFieldInfo[] {
      return parseFormFields(catalog, store);
    },
  };

  return doc;
}

// ---- Helper Functions ----

function parseVersion(data: Uint8Array): string {
  // Look for %PDF-X.Y in the first 1024 bytes
  const limit = Math.min(1024, data.length);
  let headerStr = '';
  for (let i = 0; i < limit; i++) {
    headerStr += String.fromCharCode(data[i]);
  }

  const match = headerStr.match(/%PDF-(\d+\.\d+)/);
  if (match) return match[1];
  return '1.0';
}

function findStartXref(data: Uint8Array): number {
  // Search backwards from the end for "startxref"
  const keyword = new TextEncoder().encode('startxref');
  const searchStart = Math.max(0, data.length - 1024);

  let pos = -1;
  outer: for (let i = data.length - keyword.length; i >= searchStart; i--) {
    for (let j = 0; j < keyword.length; j++) {
      if (data[i + j] !== keyword[j]) continue outer;
    }
    pos = i;
    break;
  }

  if (pos === -1) {
    throw new Error('Could not find startxref');
  }

  // Read the offset number after "startxref"
  let p = pos + keyword.length;
  // Skip whitespace
  while (p < data.length && isWS(data[p])) p++;

  let numStr = '';
  while (p < data.length && data[p] >= 0x30 && data[p] <= 0x39) {
    numStr += String.fromCharCode(data[p]);
    p++;
  }

  const offset = parseInt(numStr, 10);
  if (isNaN(offset)) {
    throw new Error('Invalid startxref offset');
  }

  return offset;
}

/**
 * Parse the chain of xref tables/streams linked by /Prev.
 */
async function parseXrefChain(
  data: Uint8Array,
  startOffset: number,
): Promise<{ entries: XrefEntry[]; trailer: TrailerInfo }> {
  const allEntries: XrefEntry[] = [];
  const seenOffsets = new Set<number>();
  let currentOffset = startOffset;
  let mainTrailer: TrailerInfo | null = null;

  while (currentOffset >= 0 && !seenOffsets.has(currentOffset)) {
    seenOffsets.add(currentOffset);

    if (currentOffset >= data.length) break;

    // Determine if this is a traditional xref table or an xref stream
    let pos = currentOffset;
    // Skip whitespace
    while (pos < data.length && isWS(data[pos])) pos++;

    if (matchBytes(data, pos, 'xref')) {
      // Traditional xref table
      const { entries, trailerPosition } = parseXrefTable(data, pos);
      allEntries.push(...entries);

      // Parse trailer
      const trailer = parseTrailer(data, trailerPosition);
      if (!mainTrailer) mainTrailer = trailer;

      if (trailer.prev !== undefined) {
        currentOffset = trailer.prev;
      } else {
        break;
      }
    } else {
      // Xref stream - parse the indirect object at this offset
      const obj = parseObjectAtOffset(data, pos);
      if (!obj || !isStream(obj as PdfObject)) {
        throw new Error('Expected xref stream at offset ' + currentOffset);
      }

      const streamObj = obj as PdfStream;

      // Decode the stream to get xref data
      const decoded = await decodeStream(streamObj);
      const decodedStream = pdfStream(streamObj.dict, decoded);

      // Parse xref entries from the decoded stream
      const entries = parseXrefStream(decodedStream, 0);
      allEntries.push(...entries);

      // The stream's dictionary IS the trailer
      const trailerDict: PdfDict = { type: 'dict', entries: new Map(streamObj.dict) };
      const trailer = extractTrailerInfo(trailerDict);
      if (!mainTrailer) mainTrailer = trailer;

      if (trailer.prev !== undefined) {
        currentOffset = trailer.prev;
      } else {
        break;
      }
    }
  }

  if (!mainTrailer) {
    throw new Error('No trailer found');
  }

  return { entries: allEntries, trailer: mainTrailer };
}

/**
 * Parse an indirect object at the given file offset.
 * Returns the parsed object value (not the wrapper).
 */
function parseObjectAtOffset(data: Uint8Array, offset: number): PdfObject | null {
  if (offset >= data.length) return null;

  try {
    const tokenizer = new Tokenizer(data, offset);
    const parser = new ObjectParser(tokenizer);
    const result = parser.parseIndirectObject();
    if (result) return result.obj;
    return null;
  } catch {
    return null;
  }
}

/**
 * Build a map from object number to xref entry for quick lookup.
 */
function buildXrefMap(entries: XrefEntry[]): Map<number, XrefEntry> {
  const map = new Map<number, XrefEntry>();
  // Process in order so later entries (from newer xref sections) override earlier ones
  for (const entry of entries) {
    if (!entry.free) {
      map.set(entry.objectNumber, entry);
    }
  }
  return map;
}

/**
 * Load compressed objects from object streams.
 */
async function loadCompressedObjects(
  data: Uint8Array,
  compressedEntries: XrefEntry[],
  xrefMap: Map<number, XrefEntry>,
  store: ObjectStore,
  securityHandler: SecurityHandler | null,
  trailerInfo: TrailerInfo,
): Promise<void> {
  // Group by stream object number
  const byStream = new Map<number, XrefEntry[]>();
  for (const entry of compressedEntries) {
    const streamObjNum = entry.streamObjectNumber!;
    if (!byStream.has(streamObjNum)) {
      byStream.set(streamObjNum, []);
    }
    byStream.get(streamObjNum)!.push(entry);
  }

  for (const [streamObjNum, entries] of byStream) {
    // Get the object stream
    let streamObj = store.get(pdfRef(streamObjNum, 0));
    if (!streamObj) {
      // Try to load it
      const streamEntry = xrefMap.get(streamObjNum);
      if (!streamEntry) continue;
      const parsed = parseObjectAtOffset(data, streamEntry.offset);
      if (!parsed) continue;
      // Decrypt if needed
      let obj = parsed;
      if (securityHandler && !isEncryptDict(trailerInfo, streamObjNum)) {
        obj = decryptObject(obj, streamObjNum, 0, securityHandler);
      }
      store.set(pdfRef(streamObjNum, 0), obj);
      streamObj = obj;
    }

    if (!isStream(streamObj)) continue;

    try {
      // Decode the object stream
      const decoded = await decodeStream(streamObj as PdfStream);

      // Parse the object stream contents
      const n = dictGetNumber(streamObj as PdfStream, 'N') ?? 0;
      const first = dictGetNumber(streamObj as PdfStream, 'First') ?? 0;

      // The header contains N pairs of (objNum, offset)
      const headerTokenizer = new Tokenizer(decoded, 0);
      const offsets: { objNum: number; offset: number }[] = [];

      for (let i = 0; i < n; i++) {
        const numToken = headerTokenizer.nextToken();
        const offsetToken = headerTokenizer.nextToken();
        if (numToken.type === 1 && offsetToken.type === 1) { // Integer tokens
          offsets.push({
            objNum: numToken.value as number,
            offset: (offsetToken.value as number) + first,
          });
        }
      }

      // Parse each object
      for (const entry of entries) {
        const objIndex = entry.indexInStream!;
        if (objIndex >= offsets.length) continue;

        const { objNum, offset: objOffset } = offsets[objIndex];
        if (objNum !== entry.objectNumber) continue;

        try {
          const objTokenizer = new Tokenizer(decoded, objOffset);
          const objParser = new ObjectParser(objTokenizer);
          const obj = objParser.parseObject();
          store.set(pdfRef(entry.objectNumber, 0), obj);
        } catch {
          // Skip objects that fail to parse
        }
      }
    } catch {
      // Skip object streams that fail to decode
    }
  }
}

/**
 * Resolve a reference to its actual object.
 */
function resolveObj(ref: PdfRef, store: ObjectStore): PdfObject | undefined {
  return store.get(ref);
}

/**
 * Recursively resolve a PdfObject (follows refs).
 */
function deepResolve(obj: PdfObject | undefined, store: ObjectStore): PdfObject | undefined {
  if (!obj) return undefined;
  if (isRef(obj)) return store.get(obj);
  return obj;
}

/**
 * Build a flat list of page dicts by traversing the page tree.
 */
function buildPageList(
  catalog: PdfDict,
  store: ObjectStore,
): { ref: PdfRef; dict: PdfDict }[] {
  const pages: { ref: PdfRef; dict: PdfDict }[] = [];
  const pagesRef = dictGetRef(catalog, 'Pages');
  if (!pagesRef) return pages;

  const pagesObj = deepResolve(pagesRef, store);
  if (!pagesObj || !isDict(pagesObj)) return pages;

  traversePageTree(pagesRef, pagesObj, store, pages);
  return pages;
}

function traversePageTree(
  nodeRef: PdfRef,
  nodeDict: PdfDict,
  store: ObjectStore,
  pages: { ref: PdfRef; dict: PdfDict }[],
): void {
  const type = dictGetName(nodeDict, 'Type');

  if (type === 'Page') {
    pages.push({ ref: nodeRef, dict: nodeDict });
    return;
  }

  // Pages node (or no explicit type - assume Pages)
  const kids = dictGetArray(nodeDict, 'Kids');
  if (!kids) return;

  for (const kidObj of kids) {
    if (!isRef(kidObj)) continue;
    const kidDict = deepResolve(kidObj, store);
    if (kidDict && isDict(kidDict)) {
      traversePageTree(kidObj, kidDict, store, pages);
    }
  }
}

/**
 * Get inherited page properties by walking up the parent chain.
 */
function getInheritedProperty(
  pageDict: PdfDict,
  key: string,
  store: ObjectStore,
): PdfObject | undefined {
  let obj = dictGet(pageDict, key);
  if (obj) return obj;

  // Walk up parent chain
  let parent = dictGet(pageDict, 'Parent');
  const visited = new Set<string>();

  while (parent) {
    const resolved = deepResolve(parent, store);
    if (!resolved || !isDict(resolved)) break;

    // Prevent infinite loops
    const parentKey = isRef(parent) ? `${parent.objectNumber}:${parent.generation}` : 'inline';
    if (visited.has(parentKey)) break;
    visited.add(parentKey);

    obj = dictGet(resolved, key);
    if (obj) return obj;

    parent = dictGet(resolved, 'Parent');
  }

  return undefined;
}

/**
 * Create a ParsedPage from a page dict.
 */
function createParsedPage(
  page: { ref: PdfRef; dict: PdfDict },
  store: ObjectStore,
): ParsedPage {
  const { ref, dict } = page;

  // MediaBox (required, but may be inherited)
  const mediaBoxObj = getInheritedProperty(dict, 'MediaBox', store);
  let mediaBox: [number, number, number, number] = [0, 0, 612, 792]; // default Letter
  if (mediaBoxObj) {
    const resolved = deepResolve(mediaBoxObj, store);
    if (resolved && isArray(resolved) && resolved.items.length >= 4) {
      mediaBox = [
        numVal(resolved.items[0]),
        numVal(resolved.items[1]),
        numVal(resolved.items[2]),
        numVal(resolved.items[3]),
      ];
    }
  }

  // Rotation
  const rotObj = getInheritedProperty(dict, 'Rotate', store);
  let rotation = 0;
  if (rotObj) {
    const resolved = deepResolve(rotObj, store);
    if (resolved && isNumber(resolved)) {
      rotation = resolved.value;
    }
  }

  return {
    ref,
    dict,
    mediaBox,
    rotation,

    async extractText(): Promise<ExtractedTextItem[]> {
      const contentData = await getPageContentData(dict, store);
      if (!contentData || contentData.length === 0) return [];

      const operations = parseContentStream(contentData);

      // Get resources (may be inherited)
      const resourcesObj = getInheritedProperty(dict, 'Resources', store);
      const resources = resourcesObj ? deepResolve(resourcesObj, store) : undefined;
      const resourcesDict = (resources && isDict(resources)) ? resources : pdfDict();

      return extractTextItems(operations, resourcesDict, store);
    },

    async extractImages(): Promise<ExtractedImage[]> {
      const contentData = await getPageContentData(dict, store);
      if (!contentData || contentData.length === 0) return [];

      const operations = parseContentStream(contentData);

      const resourcesObj = getInheritedProperty(dict, 'Resources', store);
      const resources = resourcesObj ? deepResolve(resourcesObj, store) : undefined;
      const resourcesDict = (resources && isDict(resources)) ? resources : pdfDict();

      return extractImageItems(operations, resourcesDict, store);
    },

    getAnnotations(): PdfDict[] {
      const annots = dictGetArray(dict, 'Annots');
      if (!annots) return [];

      const result: PdfDict[] = [];
      for (const annotObj of annots) {
        const resolved = deepResolve(annotObj, store);
        if (resolved && isDict(resolved)) {
          result.push(resolved);
        }
      }
      return result;
    },
  };
}

/**
 * Get the content stream data for a page.
 * Handles both single stream and array of streams (concatenated).
 */
async function getPageContentData(
  pageDict: PdfDict,
  store: ObjectStore,
): Promise<Uint8Array | null> {
  const contentsObj = dictGet(pageDict, 'Contents');
  if (!contentsObj) return null;

  const resolved = deepResolve(contentsObj, store);
  if (!resolved) return null;

  if (isStream(resolved)) {
    return await decodeStream(resolved);
  }

  if (isArray(resolved)) {
    const parts: Uint8Array[] = [];
    for (const item of resolved.items) {
      const streamObj = deepResolve(item, store);
      if (streamObj && isStream(streamObj)) {
        const decoded = await decodeStream(streamObj);
        parts.push(decoded);
        // Add a space between content streams to avoid operator merging
        parts.push(new Uint8Array([0x20]));
      }
    }
    if (parts.length === 0) return null;

    // Concatenate
    let totalLen = 0;
    for (const p of parts) totalLen += p.length;
    const result = new Uint8Array(totalLen);
    let offset = 0;
    for (const p of parts) {
      result.set(p, offset);
      offset += p.length;
    }
    return result;
  }

  return null;
}

/**
 * Parse document outlines (bookmarks).
 */
function parseOutlines(catalog: PdfDict, store: ObjectStore): OutlineNode[] {
  const outlinesRef = dictGet(catalog, 'Outlines');
  if (!outlinesRef) return [];

  const outlinesDict = deepResolve(outlinesRef, store);
  if (!outlinesDict || !isDict(outlinesDict)) return [];

  const firstRef = dictGet(outlinesDict, 'First');
  if (!firstRef) return [];

  return parseOutlineLevel(firstRef, store);
}

function parseOutlineLevel(firstRef: PdfObject, store: ObjectStore): OutlineNode[] {
  const nodes: OutlineNode[] = [];
  let currentRef: PdfObject | undefined = firstRef;
  const visited = new Set<string>();

  while (currentRef) {
    const current = deepResolve(currentRef, store);
    if (!current || !isDict(current)) break;

    // Prevent infinite loops
    const key = isRef(currentRef)
      ? `${currentRef.objectNumber}:${currentRef.generation}`
      : `inline:${nodes.length}`;
    if (visited.has(key)) break;
    visited.add(key);

    // Title
    const titleStr = dictGetString(current, 'Title') ?? '';
    // Decode title: check for UTF-16BE BOM
    let title = titleStr;
    const titleObj = dictGet(current, 'Title');
    if (titleObj && isString(titleObj)) {
      title = decodeStringValue(titleObj.value);
    }

    // Destination
    let destination: any = undefined;
    const dest = dictGet(current, 'Dest');
    if (dest) {
      destination = pdfObjToJs(dest, store);
    } else {
      const action = dictGet(current, 'A');
      if (action) {
        const actionDict = deepResolve(action, store);
        if (actionDict && isDict(actionDict)) {
          const actionType = dictGetName(actionDict, 'S');
          if (actionType === 'GoTo') {
            const d = dictGet(actionDict, 'D');
            if (d) destination = pdfObjToJs(d, store);
          }
        }
      }
    }

    // Font style flags (/F entry)
    const flags = dictGetNumber(current, 'F') ?? 0;
    const italic = (flags & 1) !== 0;
    const bold = (flags & 2) !== 0;

    // Children
    const childFirst = dictGet(current, 'First');
    const children = childFirst ? parseOutlineLevel(childFirst, store) : [];

    nodes.push({ title, destination, children, bold, italic });

    // Next sibling
    currentRef = dictGet(current, 'Next');
  }

  return nodes;
}

/**
 * Parse AcroForm fields.
 */
function parseFormFields(catalog: PdfDict, store: ObjectStore): FormFieldInfo[] {
  const acroFormRef = dictGet(catalog, 'AcroForm');
  if (!acroFormRef) return [];

  const acroForm = deepResolve(acroFormRef, store);
  if (!acroForm || !isDict(acroForm)) return [];

  const fields = dictGetArray(acroForm, 'Fields');
  if (!fields) return [];

  const result: FormFieldInfo[] = [];
  collectFormFields(fields, store, '', result);
  return result;
}

function collectFormFields(
  fieldRefs: PdfObject[],
  store: ObjectStore,
  parentName: string,
  result: FormFieldInfo[],
): void {
  for (const fieldRef of fieldRefs) {
    const ref = isRef(fieldRef) ? fieldRef : null;
    const field = deepResolve(fieldRef, store);
    if (!field || !isDict(field)) continue;

    // Field name
    const partialName = dictGetString(field, 'T') ?? '';
    const fullName = parentName
      ? (partialName ? `${parentName}.${partialName}` : parentName)
      : partialName;

    // Field type (may be inherited from parent)
    const ft = dictGetName(field, 'FT') ?? '';

    // Field value
    const vObj = dictGet(field, 'V');
    let value: any = null;
    if (vObj) {
      if (isString(vObj)) {
        value = decodeStringValue(vObj.value);
      } else if (isName(vObj)) {
        value = vObj.value;
      } else if (isNumber(vObj)) {
        value = vObj.value;
      }
    }

    // Check for kids
    const kids = dictGetArray(field, 'Kids');
    if (kids && kids.length > 0) {
      // Check if kids are widget annotations or field children
      const firstKid = deepResolve(kids[0], store);
      if (firstKid && isDict(firstKid) && dictGetName(firstKid, 'Type') === 'Annot') {
        // Widget kids - this is a terminal field
        if (ft) {
          result.push({
            name: fullName,
            type: ft,
            value,
            ref: ref ?? pdfRef(0, 0),
          });
        }
      } else {
        // Field children
        collectFormFields(kids, store, fullName, result);
      }
    } else {
      // Terminal field
      if (ft || value !== null) {
        result.push({
          name: fullName,
          type: ft,
          value,
          ref: ref ?? pdfRef(0, 0),
        });
      }
    }
  }
}

/**
 * Try to find trailer info by scanning the file when xref is broken.
 */
function findTrailerByScanning(data: Uint8Array): TrailerInfo {
  // Search for "trailer" keyword anywhere in the file
  const trailerKw = new TextEncoder().encode('trailer');

  // Search backwards to find the last trailer
  for (let i = data.length - trailerKw.length; i >= 0; i--) {
    let match = true;
    for (let j = 0; j < trailerKw.length; j++) {
      if (data[i + j] !== trailerKw[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      try {
        return parseTrailer(data, i);
      } catch {
        continue;
      }
    }
  }

  // If no trailer found, try to find /Root and /Size in the file
  // This is a last resort for severely damaged files
  throw new Error('Could not find trailer dictionary');
}

/**
 * Decrypt a PDF object (recursively for dicts and arrays).
 */
function decryptObject(
  obj: PdfObject,
  objNum: number,
  genNum: number,
  handler: SecurityHandler,
): PdfObject {
  if (isString(obj)) {
    const decrypted = handler.decryptString(obj.value, objNum, genNum);
    return { type: 'string', value: decrypted, encoding: obj.encoding };
  }

  if (isStream(obj)) {
    const decryptedData = handler.decryptData(obj.data, objNum, genNum);
    // Also decrypt strings in the stream dictionary
    const newDict = new Map<string, PdfObject>();
    for (const [key, val] of obj.dict) {
      newDict.set(key, decryptObject(val, objNum, genNum, handler));
    }
    return { type: 'stream', dict: newDict, data: decryptedData };
  }

  if (isDict(obj)) {
    const newEntries = new Map<string, PdfObject>();
    for (const [key, val] of obj.entries) {
      newEntries.set(key, decryptObject(val, objNum, genNum, handler));
    }
    return { type: 'dict', entries: newEntries };
  }

  if (isArray(obj)) {
    const newItems = obj.items.map(item => decryptObject(item, objNum, genNum, handler));
    return { type: 'array', items: newItems };
  }

  return obj;
}

/**
 * Check if an object number is the encrypt dict (which must not be decrypted).
 */
function isEncryptDict(trailerInfo: TrailerInfo, objNum: number): boolean {
  return !!trailerInfo.encrypt && trailerInfo.encrypt.objectNumber === objNum;
}

/**
 * Decode a PDF string value to a JavaScript string.
 * Handles UTF-16BE (with BOM) and PDFDocEncoding.
 */
function decodeStringValue(bytes: Uint8Array): string {
  if (bytes.length >= 2 && bytes[0] === 0xfe && bytes[1] === 0xff) {
    // UTF-16BE with BOM
    let result = '';
    for (let i = 2; i + 1 < bytes.length; i += 2) {
      result += String.fromCharCode((bytes[i] << 8) | bytes[i + 1]);
    }
    return result;
  }

  // PDFDocEncoding (similar to Latin-1 for most characters)
  let result = '';
  for (let i = 0; i < bytes.length; i++) {
    result += String.fromCharCode(bytes[i]);
  }
  return result;
}

/**
 * Convert a PdfObject to a plain JavaScript value (for destinations, etc.).
 */
function pdfObjToJs(obj: PdfObject, store: ObjectStore): any {
  if (isNull(obj)) return null;
  if (isNumber(obj)) return obj.value;
  if (isName(obj)) return obj.value;
  if (isString(obj)) return decodeStringValue(obj.value);
  if (isRef(obj)) return { ref: obj.objectNumber, gen: obj.generation };
  if (isArray(obj)) return obj.items.map(item => pdfObjToJs(item, store));
  if (isDict(obj)) {
    const result: Record<string, any> = {};
    for (const [key, val] of obj.entries) {
      result[key] = pdfObjToJs(val, store);
    }
    return result;
  }
  return null;
}

function numVal(obj: PdfObject): number {
  if (isNumber(obj)) return obj.value;
  return 0;
}

function isWS(b: number): boolean {
  return b === 0x00 || b === 0x09 || b === 0x0a || b === 0x0c || b === 0x0d || b === 0x20;
}

function matchBytes(data: Uint8Array, pos: number, str: string): boolean {
  for (let i = 0; i < str.length; i++) {
    if (pos + i >= data.length || data[pos + i] !== str.charCodeAt(i)) return false;
  }
  return true;
}

function dictGetString(dict: PdfDict | PdfStream, key: string): string | undefined {
  const obj = dict.type === 'dict' ? dict.entries.get(key) : dict.dict.get(key);
  if (obj && obj.type === 'string') {
    return decodeStringValue(obj.value);
  }
  return undefined;
}
