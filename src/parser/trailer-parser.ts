/**
 * Parse the PDF trailer dictionary.
 */

import type { PdfRef, PdfDict } from '../core/types.js';
import { dictGetNumber, dictGetRef, dictGetArray, isString } from '../core/objects.js';
import { Tokenizer } from './tokenizer.js';
import { ObjectParser } from './object-parser.js';

export interface TrailerInfo {
  size: number;
  root: PdfRef;
  info?: PdfRef;
  id?: [Uint8Array, Uint8Array];
  encrypt?: PdfRef;
  prev?: number;
}

/**
 * Parse "trailer << ... >>" starting at the given position.
 * `position` should point to the 't' of "trailer".
 */
export function parseTrailer(data: Uint8Array, position: number): TrailerInfo {
  let pos = position;

  // Skip "trailer" keyword
  const trailerKw = 'trailer';
  for (let i = 0; i < trailerKw.length; i++) {
    if (pos < data.length && data[pos] === trailerKw.charCodeAt(i)) {
      pos++;
    }
  }

  // Skip whitespace/EOL after "trailer"
  while (pos < data.length) {
    const b = data[pos];
    if (b === 0x20 || b === 0x09 || b === 0x0a || b === 0x0d || b === 0x0c) {
      pos++;
    } else {
      break;
    }
  }

  // Parse the trailer dictionary
  const tokenizer = new Tokenizer(data, pos);
  const parser = new ObjectParser(tokenizer);
  const obj = parser.parseObject();

  if (obj.type !== 'dict') {
    throw new Error('Expected trailer dictionary');
  }

  return extractTrailerInfo(obj);
}

/**
 * Extract TrailerInfo fields from a trailer dictionary.
 * Works for both traditional trailer dicts and xref stream dicts.
 */
export function extractTrailerInfo(dict: PdfDict): TrailerInfo {
  const size = dictGetNumber(dict, 'Size');
  if (size === undefined) {
    throw new Error('Trailer missing /Size');
  }

  const root = dictGetRef(dict, 'Root');
  if (!root) {
    throw new Error('Trailer missing /Root');
  }

  const info: TrailerInfo = { size, root };

  const infoRef = dictGetRef(dict, 'Info');
  if (infoRef) info.info = infoRef;

  const encryptRef = dictGetRef(dict, 'Encrypt');
  if (encryptRef) info.encrypt = encryptRef;

  const prev = dictGetNumber(dict, 'Prev');
  if (prev !== undefined) info.prev = prev;

  // /ID is an array of two strings
  const idArr = dictGetArray(dict, 'ID');
  if (idArr && idArr.length >= 2) {
    const id0 = idArr[0];
    const id1 = idArr[1];
    if (isString(id0) && isString(id1)) {
      info.id = [id0.value, id1.value];
    }
  }

  return info;
}
