/**
 * RunLength encoding and decoding per PDF specification.
 *
 * Format:
 *   0-127:   Copy next (N+1) literal bytes
 *   128:     EOD (end of data)
 *   129-255: Repeat the next byte (257-N) times
 */

/**
 * Encode data using RunLength encoding.
 */
export function runLengthEncode(data: Uint8Array): Uint8Array {
  if (data.length === 0) {
    return new Uint8Array([128]); // EOD only
  }

  const result: number[] = [];
  let i = 0;

  while (i < data.length) {
    // Look ahead for a run of identical bytes
    let runLen = 1;
    while (
      i + runLen < data.length &&
      runLen < 128 &&
      data[i + runLen] === data[i]
    ) {
      runLen++;
    }

    if (runLen >= 2) {
      // Emit a run: length byte = 257 - runLen, then the repeated byte
      result.push(257 - runLen);
      result.push(data[i]);
      i += runLen;
    } else {
      // Collect literal (non-run) bytes, up to 128
      const litStart = i;
      let litLen = 0;

      while (i < data.length && litLen < 128) {
        // Check if starting a run of 2+ would be better
        if (
          i + 1 < data.length &&
          data[i] === data[i + 1] &&
          litLen > 0
        ) {
          // Stop literal here; next iteration will handle the run
          break;
        }
        litLen++;
        i++;
      }

      // Emit literal: length byte = litLen - 1, then the bytes
      result.push(litLen - 1);
      for (let j = litStart; j < litStart + litLen; j++) {
        result.push(data[j]);
      }
    }
  }

  // EOD marker
  result.push(128);

  return new Uint8Array(result);
}

/**
 * Decode RunLength encoded data.
 */
export function runLengthDecode(data: Uint8Array): Uint8Array {
  const result: number[] = [];
  let i = 0;

  while (i < data.length) {
    const n = data[i++];

    if (n === 128) {
      // EOD
      break;
    } else if (n <= 127) {
      // Copy next n+1 bytes literally
      const count = n + 1;
      for (let j = 0; j < count && i < data.length; j++) {
        result.push(data[i++]);
      }
    } else {
      // n is 129-255: repeat next byte (257-n) times
      const count = 257 - n;
      if (i < data.length) {
        const byte = data[i++];
        for (let j = 0; j < count; j++) {
          result.push(byte);
        }
      }
    }
  }

  return new Uint8Array(result);
}
