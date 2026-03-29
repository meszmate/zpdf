/**
 * LZW decoding as specified in the PDF specification.
 * Used for reading older PDFs that use LZWDecode filter.
 */

/**
 * Decode LZW compressed data.
 * @param data - compressed input
 * @param earlyChange - controls when code size increases (default 1, per PDF spec)
 */
export function lzwDecode(data: Uint8Array, earlyChange: number = 1): Uint8Array {
  const CLEAR_CODE = 256;
  const EOD_CODE = 257;
  const FIRST_CODE = 258;

  // Bit reader (MSB first, as LZW in PDF uses)
  let bytePos = 0;
  let bitBuf = 0;
  let bitsInBuf = 0;

  function readBits(n: number): number {
    while (bitsInBuf < n) {
      if (bytePos >= data.length) {
        bitBuf = (bitBuf << 8) | 0;
      } else {
        bitBuf = (bitBuf << 8) | data[bytePos++];
      }
      bitsInBuf += 8;
    }
    bitsInBuf -= n;
    return (bitBuf >>> bitsInBuf) & ((1 << n) - 1);
  }

  // Initialize dictionary
  let codeSize = 9;
  let nextCode = FIRST_CODE;
  let maxCode = 1 << codeSize;

  // Dictionary: each entry is [prefix_code, append_byte] or a single byte
  // For efficiency, store dictionary entries as byte arrays
  const dictionary: Uint8Array[] = [];

  function resetDictionary(): void {
    dictionary.length = 0;
    for (let i = 0; i < 256; i++) {
      dictionary[i] = new Uint8Array([i]);
    }
    // 256 = CLEAR, 257 = EOD (placeholder entries)
    dictionary[CLEAR_CODE] = new Uint8Array(0);
    dictionary[EOD_CODE] = new Uint8Array(0);
    nextCode = FIRST_CODE;
    codeSize = 9;
    maxCode = 1 << codeSize;
  }

  resetDictionary();

  const result: number[] = [];
  let prevEntry: Uint8Array | null = null;

  // Read first code (should be CLEAR_CODE per spec, but handle gracefully)
  let code = readBits(codeSize);
  if (code === CLEAR_CODE) {
    resetDictionary();
    code = readBits(codeSize);
    if (code === EOD_CODE) {
      return new Uint8Array(result);
    }
  }

  if (code < dictionary.length && dictionary[code]) {
    const entry = dictionary[code];
    for (let i = 0; i < entry.length; i++) {
      result.push(entry[i]);
    }
    prevEntry = entry;
  }

  while (true) {
    code = readBits(codeSize);

    if (code === EOD_CODE) break;

    if (code === CLEAR_CODE) {
      resetDictionary();
      prevEntry = null;

      code = readBits(codeSize);
      if (code === EOD_CODE) break;

      if (code < dictionary.length && dictionary[code]) {
        const entry = dictionary[code];
        for (let i = 0; i < entry.length; i++) {
          result.push(entry[i]);
        }
        prevEntry = entry;
      }
      continue;
    }

    let entry: Uint8Array;
    if (code < nextCode && dictionary[code]) {
      entry = dictionary[code];
    } else if (code === nextCode) {
      // Code not yet in dictionary: prev + prev[0]
      if (prevEntry) {
        entry = new Uint8Array(prevEntry.length + 1);
        entry.set(prevEntry);
        entry[prevEntry.length] = prevEntry[0];
      } else {
        throw new Error('LZW: invalid code sequence');
      }
    } else {
      throw new Error(`LZW: unexpected code ${code}, next expected ${nextCode}`);
    }

    // Output entry
    for (let i = 0; i < entry.length; i++) {
      result.push(entry[i]);
    }

    // Add new dictionary entry: prev + entry[0]
    if (prevEntry) {
      const newEntry = new Uint8Array(prevEntry.length + 1);
      newEntry.set(prevEntry);
      newEntry[prevEntry.length] = entry[0];
      dictionary[nextCode] = newEntry;
      nextCode++;

      // Increase code size if needed
      // earlyChange=1: increase before reaching max (PDF default)
      // earlyChange=0: increase after reaching max
      if (nextCode + earlyChange > maxCode && codeSize < 12) {
        codeSize++;
        maxCode = 1 << codeSize;
      }
    }

    prevEntry = entry;
  }

  return new Uint8Array(result);
}
