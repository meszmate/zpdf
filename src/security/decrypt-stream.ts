/**
 * Decrypt individual PDF objects during parsing.
 */

import type { PdfObject, PdfRef, PdfString, PdfStream, PdfDict } from '../core/types.js';
import { pdfDict, pdfArray, pdfStream, pdfStringRaw } from '../core/objects.js';
import { md5 } from './md5.js';
import { rc4 } from './rc4.js';
import { aesDecryptCBC } from './aes.js';

/**
 * Compute the per-object decryption key.
 * Same algorithm as encryption (Algorithm 1 from PDF spec).
 */
function computeObjectKey(
  encryptionKey: Uint8Array,
  ref: PdfRef,
  isAES: boolean,
): Uint8Array {
  const extra = isAES ? 4 : 0;
  const buf = new Uint8Array(encryptionKey.length + 5 + extra);
  buf.set(encryptionKey);
  const offset = encryptionKey.length;

  buf[offset] = ref.objectNumber & 0xff;
  buf[offset + 1] = (ref.objectNumber >>> 8) & 0xff;
  buf[offset + 2] = (ref.objectNumber >>> 16) & 0xff;
  buf[offset + 3] = ref.generation & 0xff;
  buf[offset + 4] = (ref.generation >>> 8) & 0xff;

  if (isAES) {
    buf[offset + 5] = 0x73; // 's'
    buf[offset + 6] = 0x41; // 'A'
    buf[offset + 7] = 0x6c; // 'l'
    buf[offset + 8] = 0x54; // 'T'
  }

  const hash = md5(buf);
  const keyLen = Math.min(encryptionKey.length + 5, 16);
  return hash.subarray(0, keyLen);
}

/**
 * Decrypt a PDF string value.
 */
function decryptString(
  str: PdfString,
  objectKey: Uint8Array,
  isAES: boolean,
): PdfString {
  if (str.value.length === 0) return str;

  let decrypted: Uint8Array;
  if (isAES) {
    // AES-CBC: first 16 bytes are IV
    if (str.value.length < 32 || str.value.length % 16 !== 0) {
      // Data too short or not aligned; return as-is
      return str;
    }
    try {
      decrypted = aesDecryptCBC(objectKey, str.value);
    } catch {
      // If decryption fails (bad padding etc.), return original
      return str;
    }
  } else {
    decrypted = rc4(objectKey, str.value);
  }

  return pdfStringRaw(decrypted, str.encoding);
}

/**
 * Decrypt a PDF stream's data.
 */
function decryptStreamData(
  stream: PdfStream,
  objectKey: Uint8Array,
  isAES: boolean,
): PdfStream {
  if (stream.data.length === 0) return stream;

  let decrypted: Uint8Array;
  if (isAES) {
    if (stream.data.length < 32 || stream.data.length % 16 !== 0) {
      return stream;
    }
    try {
      decrypted = aesDecryptCBC(objectKey, stream.data);
    } catch {
      return stream;
    }
  } else {
    decrypted = rc4(objectKey, stream.data);
  }

  return pdfStream(stream.dict, decrypted);
}

/**
 * Recursively decrypt strings within arrays and dicts.
 */
function decryptContained(
  obj: PdfObject,
  objectKey: Uint8Array,
  isAES: boolean,
): PdfObject {
  switch (obj.type) {
    case 'string':
      return decryptString(obj, objectKey, isAES);

    case 'array': {
      const items = obj.items.map(item => decryptContained(item, objectKey, isAES));
      return pdfArray(...items);
    }

    case 'dict': {
      const entries = new Map<string, PdfObject>();
      for (const [key, value] of obj.entries) {
        entries.set(key, decryptContained(value, objectKey, isAES));
      }
      return pdfDict(entries);
    }

    default:
      return obj;
  }
}

/**
 * Check if a stream is an XRef stream (should not be decrypted).
 */
function isXRefStream(obj: PdfObject): boolean {
  if (obj.type !== 'stream') return false;
  const typeEntry = obj.dict.get('Type');
  return typeEntry !== undefined && typeEntry.type === 'name' && typeEntry.value === 'XRef';
}

/**
 * Decrypt a PDF object during parsing.
 *
 * @param obj - The PDF object to decrypt
 * @param ref - The object's reference (for computing per-object key)
 * @param encryptionKey - The file encryption key
 * @param algorithm - The encryption algorithm ('rc4-40', 'rc4-128', 'aes-128', 'aes-256')
 * @param revision - The security handler revision (2, 3, 4, or 6)
 * @returns A new PdfObject with decrypted data
 */
export function decryptObject(
  obj: PdfObject,
  ref: PdfRef,
  encryptionKey: Uint8Array,
  algorithm: string,
  revision: number,
): PdfObject {
  // Do not decrypt XRef streams
  if (isXRefStream(obj)) return obj;

  const isAES = algorithm === 'aes-128' || algorithm === 'aes-256';

  // For AES-256 (Rev 6), the encryption key is used directly
  let objectKey: Uint8Array;
  if (revision === 6) {
    objectKey = encryptionKey;
  } else {
    objectKey = computeObjectKey(encryptionKey, ref, isAES);
  }

  switch (obj.type) {
    case 'string':
      return decryptString(obj, objectKey, isAES);

    case 'stream': {
      // Decrypt contained strings in the stream dict, then decrypt the stream data
      const decryptedDict = new Map<string, PdfObject>();
      for (const [key, value] of obj.dict) {
        decryptedDict.set(key, decryptContained(value, objectKey, isAES));
      }
      const streamWithDecryptedDict: PdfStream = { type: 'stream', dict: decryptedDict, data: obj.data };
      return decryptStreamData(streamWithDecryptedDict, objectKey, isAES);
    }

    case 'array':
      return pdfArray(...obj.items.map(item => decryptContained(item, objectKey, isAES)));

    case 'dict': {
      const entries = new Map<string, PdfObject>();
      for (const [key, value] of obj.entries) {
        entries.set(key, decryptContained(value, objectKey, isAES));
      }
      return pdfDict(entries);
    }

    default:
      return obj;
  }
}
