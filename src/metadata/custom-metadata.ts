import type { PdfDict, PdfObject } from '../core/types.js';
import { pdfStr } from '../core/objects.js';

/**
 * Add or update a custom key-value pair in a PDF Info dictionary.
 * Returns a new PdfDict with the entry set.
 */
export function setCustomMetadata(infoDict: PdfDict, key: string, value: string): PdfDict {
  const newEntries = new Map(infoDict.entries);
  newEntries.set(key, pdfStr(value));
  return { type: 'dict', entries: newEntries };
}

/**
 * Retrieve a custom metadata value from an Info dictionary.
 */
export function getCustomMetadata(infoDict: PdfDict, key: string): string | undefined {
  const obj = infoDict.entries.get(key);
  if (!obj) return undefined;
  if (obj.type === 'string') {
    // Decode the Uint8Array back to string
    const bytes = obj.value;
    // Check for UTF-16BE BOM
    if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) {
      let result = '';
      for (let i = 2; i < bytes.length; i += 2) {
        result += String.fromCharCode((bytes[i] << 8) | bytes[i + 1]);
      }
      return result;
    }
    let result = '';
    for (let i = 0; i < bytes.length; i++) {
      result += String.fromCharCode(bytes[i]);
    }
    return result;
  }
  return undefined;
}
