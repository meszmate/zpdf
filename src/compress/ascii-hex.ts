/**
 * ASCIIHex encoding and decoding for PDF streams.
 */

const HEX_CHARS = new Uint8Array([
  0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, // 0-7
  0x38, 0x39, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, // 8-9, A-F
]);

function hexVal(c: number): number {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;       // '0'-'9'
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;  // 'A'-'F'
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;  // 'a'-'f'
  return -1;
}

/**
 * Encode data as ASCIIHex with '>' terminator.
 */
export function asciiHexEncode(data: Uint8Array): Uint8Array {
  // Each byte -> 2 hex chars + 1 for '>'
  const out = new Uint8Array(data.length * 2 + 1);
  let pos = 0;
  for (let i = 0; i < data.length; i++) {
    out[pos++] = HEX_CHARS[data[i] >> 4];
    out[pos++] = HEX_CHARS[data[i] & 0x0f];
  }
  out[pos++] = 0x3e; // '>'
  return out.subarray(0, pos);
}

/**
 * Decode ASCIIHex data. Ignores whitespace, stops at '>' or end.
 * If odd number of hex digits, the last digit is treated as if followed by 0.
 */
export function asciiHexDecode(data: Uint8Array): Uint8Array {
  const result: number[] = [];
  let high = -1;

  for (let i = 0; i < data.length; i++) {
    const c = data[i];

    // '>' = EOD marker
    if (c === 0x3e) break;

    // Skip whitespace
    if (c === 0x20 || c === 0x09 || c === 0x0a || c === 0x0d || c === 0x0c || c === 0x00) {
      continue;
    }

    const v = hexVal(c);
    if (v === -1) continue; // skip invalid characters

    if (high === -1) {
      high = v;
    } else {
      result.push((high << 4) | v);
      high = -1;
    }
  }

  // Handle trailing odd nibble
  if (high !== -1) {
    result.push(high << 4);
  }

  return new Uint8Array(result);
}
