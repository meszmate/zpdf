/**
 * Deflate compression using node:zlib with pure JS fallback.
 */

function adler32(data: Uint8Array): number {
  let a = 1;
  let b = 0;
  const MOD = 65521;
  for (let i = 0; i < data.length; i++) {
    a = (a + data[i]) % MOD;
    b = (b + a) % MOD;
  }
  return ((b << 16) | a) >>> 0;
}

/**
 * Pure-TS fallback: wraps raw data in zlib "stored" deflate blocks.
 * Uses zlib header (0x78 0x01) + stored blocks + adler32 checksum.
 * PDF readers can decode this since it is valid zlib/deflate.
 */
function deflateFallback(data: Uint8Array): Uint8Array {
  // Max block size for stored blocks is 65535 bytes
  const MAX_BLOCK = 65535;
  const numBlocks = Math.ceil(data.length / MAX_BLOCK) || 1;

  // zlib header (2) + per-block header (5 each) + data + adler32 (4)
  const outputSize = 2 + numBlocks * 5 + data.length + 4;
  const out = new Uint8Array(outputSize);
  let pos = 0;

  // Zlib header: CMF=0x78 (deflate, window=32K), FLG=0x01 (check bits, no dict, level 0)
  out[pos++] = 0x78;
  out[pos++] = 0x01;

  let offset = 0;
  for (let i = 0; i < numBlocks; i++) {
    const remaining = data.length - offset;
    const blockLen = Math.min(remaining, MAX_BLOCK);
    const isFinal = i === numBlocks - 1;

    // Stored block header: BFINAL (1 bit) + BTYPE=00 (2 bits), rest of byte is 0
    out[pos++] = isFinal ? 0x01 : 0x00;
    // LEN (little-endian 16-bit)
    out[pos++] = blockLen & 0xff;
    out[pos++] = (blockLen >> 8) & 0xff;
    // NLEN (one's complement of LEN)
    out[pos++] = (~blockLen) & 0xff;
    out[pos++] = ((~blockLen) >> 8) & 0xff;

    // Copy data
    out.set(data.subarray(offset, offset + blockLen), pos);
    pos += blockLen;
    offset += blockLen;
  }

  // Adler32 checksum (big-endian)
  const checksum = adler32(data);
  out[pos++] = (checksum >> 24) & 0xff;
  out[pos++] = (checksum >> 16) & 0xff;
  out[pos++] = (checksum >> 8) & 0xff;
  out[pos++] = checksum & 0xff;

  return out.subarray(0, pos);
}

/**
 * Compress data using FlateDecode (zlib deflate).
 * Tries node:zlib first, falls back to pure TS stored-block deflate.
 */
export async function deflate(data: Uint8Array): Promise<Uint8Array> {
  try {
    const zlib = await import('node:zlib');
    const { promisify } = await import('node:util');
    const deflateRaw = promisify(zlib.deflate);
    const result = await deflateRaw(Buffer.from(data));
    return new Uint8Array(result);
  } catch {
    return deflateFallback(data);
  }
}

/**
 * Synchronous version of deflate.
 */
export function deflateSync(data: Uint8Array): Uint8Array {
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    const zlib = require('node:zlib');
    const result = zlib.deflateSync(Buffer.from(data));
    return new Uint8Array(result);
  } catch {
    return deflateFallback(data);
  }
}

export { adler32 };
