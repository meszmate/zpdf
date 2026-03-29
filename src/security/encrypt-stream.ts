/**
 * Encrypt individual PDF objects for writing encrypted PDFs.
 */

import type { PdfObject, PdfRef, PdfString, PdfStream, PdfArray, PdfDict } from '../core/types.js';
import { pdfDict, pdfArray, pdfStream, pdfStringRaw } from '../core/objects.js';
import { md5 } from './md5.js';
import { rc4 } from './rc4.js';
import { aesEncryptCBC } from './aes.js';

/**
 * Compute the per-object encryption key.
 *
 * Per PDF spec section 7.6.2 (Algorithm 1):
 * - Take the file encryption key
 * - Append the low-order 3 bytes of the object number (little-endian)
 * - Append the low-order 2 bytes of the generation number (little-endian)
 * - For AES: append "sAlT" (0x73, 0x41, 0x6C, 0x54)
 * - MD5 hash the result
 * - Use the first (keyLength + 5) bytes, capped at 16
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

  // Object number: low-order 3 bytes, little-endian
  buf[offset] = ref.objectNumber & 0xff;
  buf[offset + 1] = (ref.objectNumber >>> 8) & 0xff;
  buf[offset + 2] = (ref.objectNumber >>> 16) & 0xff;

  // Generation number: low-order 2 bytes, little-endian
  buf[offset + 3] = ref.generation & 0xff;
  buf[offset + 4] = (ref.generation >>> 8) & 0xff;

  // For AES, append "sAlT"
  if (isAES) {
    buf[offset + 5] = 0x73; // 's'
    buf[offset + 6] = 0x41; // 'A'
    buf[offset + 7] = 0x6c; // 'l'
    buf[offset + 8] = 0x54; // 'T'
  }

  const hash = md5(buf);

  // Key length is min(encryptionKey.length + 5, 16)
  const keyLen = Math.min(encryptionKey.length + 5, 16);
  return hash.subarray(0, keyLen);
}

/**
 * Encrypt a PDF string value.
 */
function encryptString(
  str: PdfString,
  objectKey: Uint8Array,
  isAES: boolean,
): PdfString {
  if (str.value.length === 0) return str;

  let encrypted: Uint8Array;
  if (isAES) {
    // AES-CBC with random IV prepended
    encrypted = aesEncryptCBC(objectKey, str.value);
  } else {
    encrypted = rc4(objectKey, str.value);
  }

  return pdfStringRaw(encrypted, str.encoding);
}

/**
 * Encrypt a PDF stream's data.
 */
function encryptStreamData(
  stream: PdfStream,
  objectKey: Uint8Array,
  isAES: boolean,
): PdfStream {
  let encrypted: Uint8Array;
  if (isAES) {
    encrypted = aesEncryptCBC(objectKey, stream.data);
  } else {
    encrypted = rc4(objectKey, stream.data);
  }

  return pdfStream(stream.dict, encrypted);
}

/**
 * Recursively encrypt strings within arrays and dicts.
 */
function encryptContained(
  obj: PdfObject,
  objectKey: Uint8Array,
  isAES: boolean,
): PdfObject {
  switch (obj.type) {
    case 'string':
      return encryptString(obj, objectKey, isAES);

    case 'array': {
      const items = obj.items.map(item => encryptContained(item, objectKey, isAES));
      return pdfArray(...items);
    }

    case 'dict': {
      const entries = new Map<string, PdfObject>();
      for (const [key, value] of obj.entries) {
        entries.set(key, encryptContained(value, objectKey, isAES));
      }
      return pdfDict(entries);
    }

    default:
      return obj;
  }
}

/**
 * Check if a stream is an XRef stream (should not be encrypted).
 */
function isXRefStream(obj: PdfObject): boolean {
  if (obj.type !== 'stream') return false;
  const typeEntry = obj.dict.get('Type');
  return typeEntry !== undefined && typeEntry.type === 'name' && typeEntry.value === 'XRef';
}

/**
 * Encrypt a PDF object for writing.
 *
 * @param obj - The PDF object to encrypt
 * @param ref - The object's reference (for computing per-object key)
 * @param encryptionKey - The file encryption key
 * @param algorithm - The encryption algorithm ('rc4-40', 'rc4-128', 'aes-128', 'aes-256')
 * @param revision - The security handler revision (2, 3, 4, or 6)
 * @returns A new PdfObject with encrypted data
 */
export function encryptObject(
  obj: PdfObject,
  ref: PdfRef,
  encryptionKey: Uint8Array,
  algorithm: string,
  revision: number,
): PdfObject {
  // Do not encrypt XRef streams
  if (isXRefStream(obj)) return obj;

  const isAES = algorithm === 'aes-128' || algorithm === 'aes-256';

  // For AES-256 (Rev 6), the encryption key is used directly (no per-object key derivation)
  let objectKey: Uint8Array;
  if (revision === 6) {
    objectKey = encryptionKey;
  } else {
    objectKey = computeObjectKey(encryptionKey, ref, isAES);
  }

  switch (obj.type) {
    case 'string':
      return encryptString(obj, objectKey, isAES);

    case 'stream':
      // Encrypt contained strings in the stream dict, then encrypt the stream data
      const encryptedDict = new Map<string, PdfObject>();
      for (const [key, value] of obj.dict) {
        encryptedDict.set(key, encryptContained(value, objectKey, isAES));
      }
      const streamWithEncryptedDict: PdfStream = { type: 'stream', dict: encryptedDict, data: obj.data };
      return encryptStreamData(streamWithEncryptedDict, objectKey, isAES);

    case 'array':
      return pdfArray(...obj.items.map(item => encryptContained(item, objectKey, isAES)));

    case 'dict': {
      const entries = new Map<string, PdfObject>();
      for (const [key, value] of obj.entries) {
        entries.set(key, encryptContained(value, objectKey, isAES));
      }
      return pdfDict(entries);
    }

    default:
      return obj;
  }
}
