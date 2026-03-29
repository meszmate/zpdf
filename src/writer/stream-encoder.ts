import { deflate } from '../compress/deflate.js';

const HEX_CHARS = '0123456789ABCDEF';

/**
 * Encode data using ASCIIHexDecode filter.
 * Each byte is represented as two hex characters, terminated by '>'.
 */
function encodeASCIIHex(data: Uint8Array): Uint8Array {
  // Each byte -> 2 hex chars, plus '>' terminator
  const out = new Uint8Array(data.length * 2 + 1);
  let pos = 0;
  for (let i = 0; i < data.length; i++) {
    const b = data[i];
    out[pos++] = HEX_CHARS.charCodeAt((b >> 4) & 0x0F);
    out[pos++] = HEX_CHARS.charCodeAt(b & 0x0F);
  }
  out[pos++] = 0x3E; // >
  return out.subarray(0, pos);
}

/**
 * Encode data using ASCII85Decode filter (also known as Btoa).
 * Encodes 4 bytes into 5 ASCII characters in the range '!' (33) to 'u' (117).
 * Special case: 4 zero bytes encode as 'z'.
 * Enclosed in <~ ... ~>.
 */
function encodeASCII85(data: Uint8Array): Uint8Array {
  const buf: number[] = [];

  // Opening delimiter
  buf.push(0x3C, 0x7E); // <~

  const len = data.length;
  let i = 0;

  // Process full 4-byte groups
  while (i + 4 <= len) {
    const val = ((data[i] << 24) | (data[i + 1] << 16) | (data[i + 2] << 8) | data[i + 3]) >>> 0;
    i += 4;

    if (val === 0) {
      buf.push(0x7A); // 'z'
    } else {
      let v = val;
      const c5 = (v % 85); v = (v - c5) / 85;
      const c4 = (v % 85); v = (v - c4) / 85;
      const c3 = (v % 85); v = (v - c3) / 85;
      const c2 = (v % 85); v = (v - c2) / 85;
      const c1 = v;
      buf.push(c1 + 33, c2 + 33, c3 + 33, c4 + 33, c5 + 33);
    }
  }

  // Handle remaining bytes (1-3)
  const remaining = len - i;
  if (remaining > 0) {
    // Pad with zeros to make 4 bytes
    let val = 0;
    for (let j = 0; j < 4; j++) {
      val = (val << 8) | (i + j < len ? data[i + j] : 0);
    }
    val = val >>> 0;

    let v = val;
    const c5 = (v % 85); v = (v - c5) / 85;
    const c4 = (v % 85); v = (v - c4) / 85;
    const c3 = (v % 85); v = (v - c3) / 85;
    const c2 = (v % 85); v = (v - c2) / 85;
    const c1 = v;
    const chars = [c1 + 33, c2 + 33, c3 + 33, c4 + 33, c5 + 33];

    // Output remaining+1 characters
    for (let j = 0; j < remaining + 1; j++) {
      buf.push(chars[j]);
    }
  }

  // Closing delimiter
  buf.push(0x7E, 0x3E); // ~>

  return new Uint8Array(buf);
}

/**
 * Apply compression/encoding filters to stream data.
 *
 * Filters are applied in the order given (matching the PDF /Filter array order,
 * which is the order the reader would decode them -- so we encode in that same
 * order, meaning the first filter is applied first during encoding).
 *
 * Supported filters:
 *   - FlateDecode: zlib deflate compression
 *   - ASCIIHexDecode: hex encoding
 *   - ASCII85Decode: base-85 encoding
 */
export async function encodeStream(
  data: Uint8Array,
  filters: string[]
): Promise<Uint8Array> {
  let result = data;

  for (const filter of filters) {
    switch (filter) {
      case 'FlateDecode':
        result = await deflate(result);
        break;
      case 'ASCIIHexDecode':
        result = encodeASCIIHex(result);
        break;
      case 'ASCII85Decode':
        result = encodeASCII85(result);
        break;
      default:
        throw new Error(`Unsupported stream filter: ${filter}`);
    }
  }

  return result;
}
