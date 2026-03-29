/**
 * Decode PDF stream data applying filter chains.
 */

import type { PdfStream, PdfObject, PdfDict } from '../core/types.js';
import { dictGet, dictGetName, dictGetArray, dictGetNumber, isName, isDict, isArray } from '../core/objects.js';
import { inflate } from '../compress/inflate.js';
import { ascii85Decode } from '../compress/ascii85.js';
import { asciiHexDecode } from '../compress/ascii-hex.js';
import { lzwDecode } from '../compress/lzw.js';
import { runLengthDecode } from '../compress/run-length.js';
import { removePredictor } from '../compress/predictor.js';

/**
 * Decode a PDF stream by applying its filter chain.
 * Handles /Filter (single name or array) and /DecodeParms.
 */
export async function decodeStream(stream: PdfStream): Promise<Uint8Array> {
  const filterObj = dictGet(stream, 'Filter');
  if (!filterObj) {
    // No filter, return raw data
    return stream.data;
  }

  // Build the filter list
  const filters: string[] = [];
  if (isName(filterObj)) {
    filters.push(filterObj.value);
  } else if (isArray(filterObj)) {
    for (const item of filterObj.items) {
      if (isName(item)) {
        filters.push(item.value);
      }
    }
  }

  if (filters.length === 0) {
    return stream.data;
  }

  // Build the decode params list (parallel to filters)
  const parmsObj = dictGet(stream, 'DecodeParms');
  const parmsList: (PdfDict | null)[] = [];

  if (!parmsObj) {
    for (let i = 0; i < filters.length; i++) {
      parmsList.push(null);
    }
  } else if (isDict(parmsObj)) {
    // Single dict applies to the single (or first) filter
    parmsList.push(parmsObj);
    for (let i = 1; i < filters.length; i++) {
      parmsList.push(null);
    }
  } else if (isArray(parmsObj)) {
    for (const item of parmsObj.items) {
      if (isDict(item)) {
        parmsList.push(item);
      } else {
        parmsList.push(null);
      }
    }
    // Pad if needed
    while (parmsList.length < filters.length) {
      parmsList.push(null);
    }
  } else {
    for (let i = 0; i < filters.length; i++) {
      parmsList.push(null);
    }
  }

  // Apply filters in order
  let data = stream.data;

  for (let i = 0; i < filters.length; i++) {
    const filterName = filters[i];
    const parms = parmsList[i];

    data = await applyFilter(filterName, data, parms);
  }

  return data;
}

async function applyFilter(name: string, data: Uint8Array, parms: PdfDict | null): Promise<Uint8Array> {
  switch (name) {
    case 'FlateDecode':
    case 'Fl': {
      let decoded = await inflate(data);
      decoded = applyPredictorIfNeeded(decoded, parms);
      return decoded;
    }

    case 'LZWDecode':
    case 'LZW': {
      const earlyChange = parms ? (dictGetNumber(parms, 'EarlyChange') ?? 1) : 1;
      let decoded = lzwDecode(data, earlyChange);
      decoded = applyPredictorIfNeeded(decoded, parms);
      return decoded;
    }

    case 'ASCIIHexDecode':
    case 'AHx':
      return asciiHexDecode(data);

    case 'ASCII85Decode':
    case 'A85':
      return ascii85Decode(data);

    case 'RunLengthDecode':
    case 'RL':
      return runLengthDecode(data);

    case 'DCTDecode':
    case 'DCT':
      // JPEG data - return as-is (image decoder handles it)
      return data;

    case 'JPXDecode':
      // JPEG2000 data - return as-is
      return data;

    case 'CCITTFaxDecode':
    case 'CCF':
      // CCITT fax data - return as-is (needs specialized decoder)
      return data;

    case 'JBIG2Decode':
      // JBIG2 data - return as-is
      return data;

    case 'Crypt':
      // Crypt filter - handled by security layer, pass through
      return data;

    default:
      // Unknown filter - return data as-is
      return data;
  }
}

function applyPredictorIfNeeded(data: Uint8Array, parms: PdfDict | null): Uint8Array {
  if (!parms) return data;

  const predictor = dictGetNumber(parms, 'Predictor') ?? 1;
  if (predictor === 1) return data;

  const columns = dictGetNumber(parms, 'Columns') ?? 1;
  const colors = dictGetNumber(parms, 'Colors') ?? 1;
  const bitsPerComponent = dictGetNumber(parms, 'BitsPerComponent') ?? 8;

  return removePredictor(data, predictor, columns, colors, bitsPerComponent);
}
