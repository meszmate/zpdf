/**
 * ASCII85 (Base85) encoding and decoding.
 */

/**
 * Encode data using ASCII85 with <~ ~> delimiters.
 */
export function ascii85Encode(data: Uint8Array): Uint8Array {
  const result: number[] = [];

  // Opening delimiter: <~
  result.push(0x3c, 0x7e); // '<', '~'

  let i = 0;
  while (i < data.length) {
    const remaining = data.length - i;

    if (remaining >= 4) {
      // Full 4-byte group
      const value =
        ((data[i] << 24) | (data[i + 1] << 16) | (data[i + 2] << 8) | data[i + 3]) >>> 0;

      if (value === 0) {
        // Special case: all zeros -> 'z'
        result.push(0x7a); // 'z'
      } else {
        const c4 = value % 85;
        const r4 = (value - c4) / 85;
        const c3 = r4 % 85;
        const r3 = (r4 - c3) / 85;
        const c2 = r3 % 85;
        const r2 = (r3 - c2) / 85;
        const c1 = r2 % 85;
        const c0 = (r2 - c1) / 85;

        result.push(c0 + 33, c1 + 33, c2 + 33, c3 + 33, c4 + 33);
      }
      i += 4;
    } else {
      // Partial group: pad with zeros
      let value = 0;
      for (let j = 0; j < remaining; j++) {
        value |= data[i + j] << (24 - j * 8);
      }
      value >>>= 0;

      const c4 = value % 85;
      const r4 = (value - c4) / 85;
      const c3 = r4 % 85;
      const r3 = (r4 - c3) / 85;
      const c2 = r3 % 85;
      const r2 = (r3 - c2) / 85;
      const c1 = r2 % 85;
      const c0 = (r2 - c1) / 85;

      const chars = [c0 + 33, c1 + 33, c2 + 33, c3 + 33, c4 + 33];
      // Output remaining+1 characters
      for (let j = 0; j < remaining + 1; j++) {
        result.push(chars[j]);
      }
      i += remaining;
    }
  }

  // Closing delimiter: ~>
  result.push(0x7e, 0x3e); // '~', '>'

  return new Uint8Array(result);
}

/**
 * Decode ASCII85 data. Handles <~ ~> delimiters and 'z' shorthand.
 */
export function ascii85Decode(data: Uint8Array): Uint8Array {
  // Find the data between <~ and ~>
  let start = 0;
  let end = data.length;

  // Skip <~ if present
  for (let i = 0; i < data.length - 1; i++) {
    if (data[i] === 0x3c && data[i + 1] === 0x7e) {
      start = i + 2;
      break;
    }
  }

  // Find ~> if present
  for (let i = start; i < data.length - 1; i++) {
    if (data[i] === 0x7e && data[i + 1] === 0x3e) {
      end = i;
      break;
    }
  }

  // Filter out whitespace and collect valid characters
  const chars: number[] = [];
  for (let i = start; i < end; i++) {
    const c = data[i];
    // Skip whitespace
    if (c === 0x20 || c === 0x09 || c === 0x0a || c === 0x0d || c === 0x0c) continue;
    if (c === 0x7a) {
      // 'z' -> four zero bytes
      chars.push(33, 33, 33, 33, 33); // all '!'
    } else if (c >= 33 && c <= 117) {
      chars.push(c);
    }
  }

  const result: number[] = [];
  let i = 0;

  while (i < chars.length) {
    const remaining = chars.length - i;

    if (remaining >= 5) {
      // Full 5-character group
      const value =
        (chars[i] - 33) * 85 * 85 * 85 * 85 +
        (chars[i + 1] - 33) * 85 * 85 * 85 +
        (chars[i + 2] - 33) * 85 * 85 +
        (chars[i + 3] - 33) * 85 +
        (chars[i + 4] - 33);

      result.push(
        (value >>> 24) & 0xff,
        (value >>> 16) & 0xff,
        (value >>> 8) & 0xff,
        value & 0xff,
      );
      i += 5;
    } else {
      // Partial group: pad with 'u' (117 = 84 + 33)
      const group = [33, 33, 33, 33, 33]; // default to '!'
      for (let j = 0; j < remaining; j++) {
        group[j] = chars[i + j];
      }
      // Pad remainder with 'u' (value 84)
      for (let j = remaining; j < 5; j++) {
        group[j] = 117; // 'u'
      }

      const value =
        (group[0] - 33) * 85 * 85 * 85 * 85 +
        (group[1] - 33) * 85 * 85 * 85 +
        (group[2] - 33) * 85 * 85 +
        (group[3] - 33) * 85 +
        (group[4] - 33);

      const outputBytes = remaining - 1;
      if (outputBytes >= 1) result.push((value >>> 24) & 0xff);
      if (outputBytes >= 2) result.push((value >>> 16) & 0xff);
      if (outputBytes >= 3) result.push((value >>> 8) & 0xff);
      if (outputBytes >= 4) result.push(value & 0xff);
      i += remaining;
    }
  }

  return new Uint8Array(result);
}
