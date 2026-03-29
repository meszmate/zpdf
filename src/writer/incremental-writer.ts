import type { PdfRef, PdfStream } from '../core/types.js';
import { ObjectStore } from '../core/object-store.js';
import { ByteBuffer } from '../utils/buffer.js';
import { serializeObjectToBuffer } from './object-serializer.js';
import { writeXrefTable, type XrefEntry } from './xref-writer.js';

/**
 * Ensure a stream's /Length entry matches its data length.
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
 * Append an incremental update to an existing PDF.
 *
 * This is used for modifying a PDF without rewriting the entire file.
 * Only the modified/new objects are appended, along with a new xref table
 * and trailer that references the previous xref via /Prev.
 *
 * @param existingBytes - The bytes of the existing PDF file
 * @param store - ObjectStore containing at least the modified/new objects
 * @param catalogRef - Reference to the document catalog
 * @param modifiedRefs - Array of PdfRef that were modified or newly created
 * @param prevXrefOffset - Byte offset of the previous xref table in the existing file
 * @returns The complete PDF bytes (existing + appended update)
 */
export async function writeIncrementalUpdate(
  existingBytes: Uint8Array,
  store: ObjectStore,
  catalogRef: PdfRef,
  modifiedRefs: PdfRef[],
  prevXrefOffset: number
): Promise<Uint8Array> {
  const buf = new ByteBuffer(existingBytes.length + 4096);

  // Write the existing PDF content
  buf.write(existingBytes);

  // Ensure we start on a new line after existing content
  if (existingBytes.length > 0 && existingBytes[existingBytes.length - 1] !== 0x0A) {
    buf.writeByte(0x0A);
  }

  // Write only the modified/new objects and track their offsets
  const xrefEntries: XrefEntry[] = [];

  // Sort modified refs by object number for deterministic output
  const sortedRefs = [...modifiedRefs].sort(
    (a, b) => a.objectNumber - b.objectNumber || a.generation - b.generation
  );

  for (const ref of sortedRefs) {
    let obj = store.get(ref);
    if (obj === undefined) {
      // Object was deleted - add a free entry
      xrefEntries.push({
        objectNumber: ref.objectNumber,
        offset: 0,
        generation: ref.generation + 1,
        free: true,
      });
      continue;
    }

    // Ensure stream length is correct
    if (obj.type === 'stream') {
      obj = ensureStreamLength(obj as PdfStream);
    }

    const offset = buf.getPosition();
    xrefEntries.push({
      objectNumber: ref.objectNumber,
      offset,
      generation: ref.generation,
      free: false,
    });

    buf.writeString(`${ref.objectNumber} ${ref.generation} obj\n`);
    serializeObjectToBuffer(obj, buf);
    buf.writeString('\nendobj\n');
  }

  // Write new xref table (only for changed entries)
  const xrefOffset = buf.getPosition();
  writeXrefTable(xrefEntries, buf);

  // Compute the /Size value: must be at least as large as the largest object number + 1
  // across both the existing file and the new objects
  const maxObjNum = sortedRefs.length > 0
    ? Math.max(...sortedRefs.map(r => r.objectNumber), store.nextObjectNumber - 1)
    : store.nextObjectNumber - 1;

  // Write new trailer with /Prev pointing to old xref
  buf.writeString('trailer\n');
  buf.writeString('<< ');
  buf.writeString(`/Size ${maxObjNum + 1} `);
  buf.writeString(`/Root ${catalogRef.objectNumber} ${catalogRef.generation} R `);
  buf.writeString(`/Prev ${prevXrefOffset}`);
  buf.writeString(' >>\n');

  // startxref + EOF
  buf.writeString(`startxref\n${xrefOffset}\n%%EOF\n`);

  return buf.toUint8Array();
}
