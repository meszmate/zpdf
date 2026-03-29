/**
 * Extract images from PDF page content streams.
 */

import type { PdfObject, PdfDict, PdfStream } from '../core/types.js';
import {
  dictGet, dictGetName, dictGetNumber, dictGetArray, dictGetRef,
  isRef, isDict, isName, isNumber, isStream, isArray,
} from '../core/objects.js';
import type { ContentOperation } from './content-stream-parser.js';
import type { ObjectStore } from '../core/object-store.js';
import { decodeStream } from './stream-decoder.js';

export interface ExtractedImage {
  width: number;
  height: number;
  colorSpace: string;
  bitsPerComponent: number;
  data: Uint8Array;
  filter?: string;
}

/**
 * Resolve a PdfObject, following indirect references.
 */
function resolve(obj: PdfObject | undefined, store: ObjectStore): PdfObject | undefined {
  if (!obj) return undefined;
  if (isRef(obj)) return store.get(obj);
  return obj;
}

/**
 * Get the color space name as a string from various possible representations.
 */
function resolveColorSpaceName(csObj: PdfObject | undefined, store: ObjectStore): string {
  if (!csObj) return 'DeviceGray';

  const resolved = resolve(csObj, store);
  if (!resolved) return 'DeviceGray';

  if (isName(resolved)) return resolved.value;

  if (isArray(resolved) && resolved.items.length > 0) {
    const first = resolved.items[0];
    if (isName(first)) {
      // Return the base color space name for known patterns
      switch (first.value) {
        case 'ICCBased': {
          // Try to determine the number of components from the ICC profile stream
          if (resolved.items.length > 1) {
            const profileObj = resolve(resolved.items[1], store);
            if (profileObj && (isDict(profileObj) || isStream(profileObj))) {
              const n = dictGetNumber(profileObj as PdfDict, 'N');
              if (n === 1) return 'DeviceGray';
              if (n === 3) return 'DeviceRGB';
              if (n === 4) return 'DeviceCMYK';
            }
          }
          return 'ICCBased';
        }
        case 'Indexed':
        case 'I':
          return 'Indexed';
        case 'CalGray':
          return 'CalGray';
        case 'CalRGB':
          return 'CalRGB';
        case 'Lab':
          return 'Lab';
        case 'Separation':
          return 'Separation';
        case 'DeviceN':
          return 'DeviceN';
        case 'Pattern':
          return 'Pattern';
        default:
          return first.value;
      }
    }
  }

  return 'DeviceGray';
}

/**
 * Extract images from a list of content stream operations.
 * Looks for Do operators that reference image XObjects.
 */
export async function extractImages(
  operations: ContentOperation[],
  resources: PdfDict,
  store: ObjectStore,
): Promise<ExtractedImage[]> {
  const images: ExtractedImage[] = [];

  // Get the XObject resource dictionary
  const xObjDictObj = resolve(dictGet(resources, 'XObject'), store);
  if (!xObjDictObj || !isDict(xObjDictObj)) {
    return images;
  }

  // Find all Do operators
  for (const op of operations) {
    if (op.operator !== 'Do') continue;
    if (op.operands.length < 1) continue;

    const nameObj = op.operands[0];
    if (!isName(nameObj)) continue;

    const xobjName = nameObj.value;

    // Look up the XObject
    const xobjObj = resolve(dictGet(xObjDictObj, xobjName), store);
    if (!xobjObj || !isStream(xobjObj)) continue;

    const xobjStream = xobjObj as PdfStream;

    // Check that it's an Image subtype
    const subtype = dictGetName(xobjStream, 'Subtype');
    if (subtype !== 'Image') continue;

    // Extract image properties
    const width = dictGetNumber(xobjStream, 'Width') ?? 0;
    const height = dictGetNumber(xobjStream, 'Height') ?? 0;
    const bitsPerComponent = dictGetNumber(xobjStream, 'BitsPerComponent') ?? 8;

    // Color space
    const csObj = dictGet(xobjStream, 'ColorSpace');
    const colorSpace = resolveColorSpaceName(csObj, store);

    // Filter name (for information)
    let filterName: string | undefined;
    const filterObj = dictGet(xobjStream, 'Filter');
    if (filterObj && isName(filterObj)) {
      filterName = filterObj.value;
    } else if (filterObj && isArray(filterObj) && filterObj.items.length > 0) {
      const first = filterObj.items[0];
      if (isName(first)) filterName = first.value;
    }

    // Decode the stream
    let data: Uint8Array;
    try {
      // For DCT and JPX, we might want the raw encoded data
      if (filterName === 'DCTDecode' || filterName === 'JPXDecode') {
        data = xobjStream.data;
      } else {
        data = await decodeStream(xobjStream);
      }
    } catch {
      // If decoding fails, use raw data
      data = xobjStream.data;
    }

    images.push({
      width,
      height,
      colorSpace,
      bitsPerComponent,
      data,
      filter: filterName,
    });
  }

  // Also handle inline images (BI operator)
  for (const op of operations) {
    if (op.operator !== 'BI') continue;
    if (op.operands.length < 2) continue;

    const dictObj = op.operands[0];
    const dataObj = op.operands[1];

    if (!isDict(dictObj)) continue;

    const width = dictGetNumber(dictObj, 'Width') ?? dictGetNumber(dictObj, 'W') ?? 0;
    const height = dictGetNumber(dictObj, 'Height') ?? dictGetNumber(dictObj, 'H') ?? 0;
    const bpc = dictGetNumber(dictObj, 'BitsPerComponent') ?? dictGetNumber(dictObj, 'BPC') ?? 8;

    const csObj = dictGet(dictObj, 'ColorSpace') ?? dictGet(dictObj, 'CS');
    const colorSpace = resolveColorSpaceName(csObj, store);

    let filterName: string | undefined;
    const filterObj = dictGet(dictObj, 'Filter') ?? dictGet(dictObj, 'F');
    if (filterObj && isName(filterObj)) {
      filterName = filterObj.value;
    }

    // The image data is the second operand (a PdfString containing raw bytes)
    let data: Uint8Array;
    if (dataObj.type === 'string') {
      data = dataObj.value;
    } else {
      data = new Uint8Array(0);
    }

    images.push({
      width,
      height,
      colorSpace,
      bitsPerComponent: bpc,
      data,
      filter: filterName,
    });
  }

  return images;
}
