import type { PdfObject, PdfRef, PdfStream, PdfName } from '../core/types.js';
import { ObjectStore } from '../core/object-store.js';
import { ByteBuffer } from '../utils/buffer.js';
import { serializeObjectToBuffer } from './object-serializer.js';
import { writeXrefTable, type XrefEntry } from './xref-writer.js';
import { encodeStream } from './stream-encoder.js';

export interface WriterOptions {
  version?: string;
  compress?: boolean;
  linearize?: boolean;
  info?: PdfRef;
}

/**
 * Optionally compress a PdfStream's data using FlateDecode.
 * Returns a new PdfStream with the compressed data and updated dict,
 * or the original if compression is not beneficial.
 */
async function maybeCompressStream(obj: PdfStream): Promise<PdfStream> {
  // Check if already has a filter
  if (obj.dict.has('Filter')) {
    return obj;
  }

  const compressed = await encodeStream(obj.data, ['FlateDecode']);

  // Only use compression if it actually saves space
  if (compressed.length >= obj.data.length) {
    return obj;
  }

  const newDict = new Map(obj.dict);
  newDict.set('Filter', { type: 'name', value: 'FlateDecode' } as PdfName);
  newDict.set('Length', { type: 'number', value: compressed.length });

  return {
    type: 'stream',
    dict: newDict,
    data: compressed,
  };
}

/**
 * Ensure a stream's /Length entry is correct.
 */
function ensureStreamLength(obj: PdfStream): PdfStream {
  const currentLength = obj.dict.get('Length');
  if (currentLength && currentLength.type === 'number' && currentLength.value === obj.data.length) {
    return obj;
  }
  const newDict = new Map(obj.dict);
  newDict.set('Length', { type: 'number', value: obj.data.length });
  return { type: 'stream', dict: newDict, data: obj.data };
}

/**
 * Write a complete PDF file from an ObjectStore.
 *
 * Produces bytes in the standard order:
 *   1. Header (%PDF-x.y + binary comment)
 *   2. Body (indirect objects)
 *   3. Cross-reference table
 *   4. Trailer
 *   5. startxref + %%EOF
 */
export async function writePdf(
  store: ObjectStore,
  catalogRef: PdfRef,
  options: WriterOptions = {}
): Promise<Uint8Array> {
  const version = options.version ?? '1.7';
  const compress = options.compress ?? false;

  const buf = new ByteBuffer(65536);

  // 1. Header
  buf.writeString(`%PDF-${version}\n`);
  // Binary comment to signal binary content to transfer agents
  buf.writeByte(0x25); // %
  buf.writeByte(0xE2);
  buf.writeByte(0xE3);
  buf.writeByte(0xCF);
  buf.writeByte(0xD3);
  buf.writeByte(0x0A); // \n

  // 2. Body - write all objects, tracking offsets
  const xrefEntries: XrefEntry[] = [];

  // Collect all objects and sort by object number for deterministic output
  const allObjects: Array<{ objectNumber: number; generation: number; obj: PdfObject }> = [];
  for (const [ref, obj] of store.entries()) {
    allObjects.push({ objectNumber: ref.objectNumber, generation: ref.generation, obj });
  }
  allObjects.sort((a, b) => a.objectNumber - b.objectNumber || a.generation - b.generation);

  for (const { objectNumber, generation, obj } of allObjects) {
    let finalObj = obj;

    // Handle stream compression and length
    if (finalObj.type === 'stream') {
      if (compress) {
        finalObj = await maybeCompressStream(finalObj as PdfStream);
      }
      finalObj = ensureStreamLength(finalObj as PdfStream);
    }

    const offset = buf.getPosition();
    xrefEntries.push({ objectNumber, offset, generation, free: false });

    buf.writeString(`${objectNumber} ${generation} obj\n`);
    serializeObjectToBuffer(finalObj, buf);
    buf.writeString('\nendobj\n');
  }

  // 3. Cross-reference table
  const xrefOffset = buf.getPosition();
  writeXrefTable(xrefEntries, buf);

  // 4. Trailer
  buf.writeString('trailer\n');
  buf.writeString('<< ');

  // /Size = highest object number + 1
  const maxObjNum = allObjects.length > 0
    ? Math.max(...allObjects.map(o => o.objectNumber))
    : 0;
  buf.writeString(`/Size ${maxObjNum + 1} `);

  // /Root
  buf.writeString(`/Root ${catalogRef.objectNumber} ${catalogRef.generation} R`);

  // /Info (optional)
  if (options.info) {
    buf.writeString(` /Info ${options.info.objectNumber} ${options.info.generation} R`);
  }

  buf.writeString(' >>\n');

  // 5. startxref
  buf.writeString(`startxref\n${xrefOffset}\n%%EOF\n`);

  return buf.toUint8Array();
}
