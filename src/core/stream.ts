import type { PdfStream, PdfObject } from './types.js';
import { pdfStream, pdfName, pdfNum, pdfArray } from './objects.js';
import { getZlib } from '../utils/platform.js';

export function getStreamFilters(stream: PdfStream): string[] {
  const filter = stream.dict.get('Filter');
  if (!filter) return [];
  if (filter.type === 'name') return [filter.value];
  if (filter.type === 'array') {
    return filter.items
      .filter((item) => item.type === 'name')
      .map((item) => (item as { type: 'name'; value: string }).value);
  }
  return [];
}

export function getStreamLength(stream: PdfStream): number {
  const len = stream.dict.get('Length');
  if (len && len.type === 'number') return len.value;
  return stream.data.length;
}

export async function createFlateStream(
  dict: Record<string, PdfObject>,
  data: Uint8Array,
): Promise<PdfStream> {
  const zlib = await getZlib();
  let compressed: Uint8Array;

  if (zlib) {
    compressed = await new Promise<Uint8Array>((resolve, reject) => {
      zlib.deflate(data, (err: Error | null, result: Buffer) => {
        if (err) reject(err);
        else resolve(new Uint8Array(result));
      });
    });
  } else {
    // If no zlib available, fall back to uncompressed
    return pdfStream(
      { ...dict, Length: pdfNum(data.length) },
      data,
    );
  }

  const mergedDict: Record<string, PdfObject> = {
    ...dict,
    Filter: pdfName('FlateDecode'),
    Length: pdfNum(compressed.length),
  };

  // If the original dict already had a Filter, combine them
  if (dict['Filter']) {
    const existing = dict['Filter'];
    if (existing.type === 'name') {
      mergedDict['Filter'] = pdfArray(pdfName('FlateDecode'), existing);
    } else if (existing.type === 'array') {
      mergedDict['Filter'] = pdfArray(pdfName('FlateDecode'), ...existing.items);
    }
  }

  return pdfStream(mergedDict, compressed);
}
