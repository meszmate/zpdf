import type { PdfObject, PdfBool, PdfNumber, PdfString, PdfName, PdfArray, PdfDict, PdfStream, PdfNull, PdfRef } from '../core/types.js';
import { ByteBuffer } from '../utils/buffer.js';

const ENCODER = new TextEncoder();

/**
 * Characters that must be encoded in a PDF name (outside 0x21-0x7E or #, plus delimiters).
 * PDF spec: name characters outside the regular printable ASCII range or that are
 * delimiter/whitespace must be written as #XX.
 */
function isNameRegularChar(code: number): boolean {
  // Regular characters are 0x21..0x7E except for delimiter characters and #
  // Delimiters: ( ) < > [ ] { } / %
  // '#' = 0x23
  if (code < 0x21 || code > 0x7E) return false;
  if (code === 0x23) return false; // #
  if (code === 0x28 || code === 0x29) return false; // ( )
  if (code === 0x3C || code === 0x3E) return false; // < >
  if (code === 0x5B || code === 0x5D) return false; // [ ]
  if (code === 0x7B || code === 0x7D) return false; // { }
  if (code === 0x2F) return false; // /
  if (code === 0x25) return false; // %
  return true;
}

function formatNumber(value: number): string {
  if (Number.isInteger(value)) {
    return value.toString();
  }
  // Use up to 6 decimal places, strip trailing zeros
  let s = value.toFixed(6);
  // Strip trailing zeros after decimal point
  if (s.includes('.')) {
    s = s.replace(/0+$/, '');
    s = s.replace(/\.$/, '');
  }
  return s;
}

function serializeBool(obj: PdfBool, buf: ByteBuffer): void {
  buf.writeString(obj.value ? 'true' : 'false');
}

function serializeNumber(obj: PdfNumber, buf: ByteBuffer): void {
  buf.writeString(formatNumber(obj.value));
}

function serializeLiteralString(data: Uint8Array, buf: ByteBuffer): void {
  buf.writeByte(0x28); // (
  for (let i = 0; i < data.length; i++) {
    const b = data[i];
    switch (b) {
      case 0x0A: // \n
        buf.writeByte(0x5C); buf.writeByte(0x6E);
        break;
      case 0x0D: // \r
        buf.writeByte(0x5C); buf.writeByte(0x72);
        break;
      case 0x09: // \t
        buf.writeByte(0x5C); buf.writeByte(0x74);
        break;
      case 0x08: // \b
        buf.writeByte(0x5C); buf.writeByte(0x62);
        break;
      case 0x0C: // \f
        buf.writeByte(0x5C); buf.writeByte(0x66);
        break;
      case 0x28: // (
        buf.writeByte(0x5C); buf.writeByte(0x28);
        break;
      case 0x29: // )
        buf.writeByte(0x5C); buf.writeByte(0x29);
        break;
      case 0x5C: // backslash
        buf.writeByte(0x5C); buf.writeByte(0x5C);
        break;
      default:
        buf.writeByte(b);
    }
  }
  buf.writeByte(0x29); // )
}

const HEX_CHARS = '0123456789abcdef';

function serializeHexString(data: Uint8Array, buf: ByteBuffer): void {
  buf.writeByte(0x3C); // <
  for (let i = 0; i < data.length; i++) {
    const b = data[i];
    buf.writeByte(HEX_CHARS.charCodeAt((b >> 4) & 0x0F));
    buf.writeByte(HEX_CHARS.charCodeAt(b & 0x0F));
  }
  buf.writeByte(0x3E); // >
}

function serializeString(obj: PdfString, buf: ByteBuffer): void {
  if (obj.encoding === 'hex') {
    serializeHexString(obj.value, buf);
  } else {
    serializeLiteralString(obj.value, buf);
  }
}

function serializeName(obj: PdfName, buf: ByteBuffer): void {
  buf.writeByte(0x2F); // /
  const name = obj.value;
  for (let i = 0; i < name.length; i++) {
    const code = name.charCodeAt(i);
    if (isNameRegularChar(code)) {
      buf.writeByte(code);
    } else {
      // Encode as #XX
      buf.writeByte(0x23); // #
      buf.writeByte(HEX_CHARS.charCodeAt((code >> 4) & 0x0F));
      buf.writeByte(HEX_CHARS.charCodeAt(code & 0x0F));
    }
  }
}

function serializeArray(obj: PdfArray, buf: ByteBuffer): void {
  buf.writeByte(0x5B); // [
  for (let i = 0; i < obj.items.length; i++) {
    if (i > 0) buf.writeByte(0x20); // space
    serializeObjectToBuffer(obj.items[i], buf);
  }
  buf.writeByte(0x5D); // ]
}

function serializeDict(entries: Map<string, PdfObject>, buf: ByteBuffer): void {
  buf.writeString('<< ');
  let first = true;
  for (const [key, value] of entries) {
    if (!first) buf.writeByte(0x20);
    first = false;
    // Write key as a name
    serializeName({ type: 'name', value: key }, buf);
    buf.writeByte(0x20);
    serializeObjectToBuffer(value, buf);
  }
  buf.writeString(' >>');
}

function serializeDictObj(obj: PdfDict, buf: ByteBuffer): void {
  serializeDict(obj.entries, buf);
}

function serializeStream(obj: PdfStream, buf: ByteBuffer): void {
  serializeDict(obj.dict, buf);
  buf.writeByte(0x0A); // \n
  buf.writeString('stream\n');
  buf.write(obj.data);
  buf.writeString('\nendstream');
}

function serializeNull(_obj: PdfNull, buf: ByteBuffer): void {
  buf.writeString('null');
}

function serializeRef(obj: PdfRef, buf: ByteBuffer): void {
  buf.writeString(`${obj.objectNumber} ${obj.generation} R`);
}

/**
 * Serialize a PdfObject directly into a ByteBuffer.
 */
export function serializeObjectToBuffer(obj: PdfObject, buf: ByteBuffer): void {
  switch (obj.type) {
    case 'bool': serializeBool(obj, buf); break;
    case 'number': serializeNumber(obj, buf); break;
    case 'string': serializeString(obj, buf); break;
    case 'name': serializeName(obj, buf); break;
    case 'array': serializeArray(obj, buf); break;
    case 'dict': serializeDictObj(obj, buf); break;
    case 'stream': serializeStream(obj, buf); break;
    case 'null': serializeNull(obj, buf); break;
    case 'ref': serializeRef(obj, buf); break;
  }
}

/**
 * Serialize a PdfObject to a Uint8Array.
 */
export function serializeObject(obj: PdfObject): Uint8Array {
  const buf = new ByteBuffer(256);
  serializeObjectToBuffer(obj, buf);
  return buf.toUint8Array();
}
