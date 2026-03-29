/**
 * Pure TypeScript RC4 cipher implementation.
 * RC4 is symmetric -- the same function encrypts and decrypts.
 */
export function rc4(key: Uint8Array, data: Uint8Array): Uint8Array {
  // KSA (Key-Scheduling Algorithm)
  const S = new Uint8Array(256);
  for (let i = 0; i < 256; i++) S[i] = i;
  let j = 0;
  for (let i = 0; i < 256; i++) {
    j = (j + S[i] + key[i % key.length]) & 0xff;
    const tmp = S[i];
    S[i] = S[j];
    S[j] = tmp;
  }

  // PRGA (Pseudo-Random Generation Algorithm)
  const result = new Uint8Array(data.length);
  let i = 0;
  j = 0;
  for (let k = 0; k < data.length; k++) {
    i = (i + 1) & 0xff;
    j = (j + S[i]) & 0xff;
    const tmp = S[i];
    S[i] = S[j];
    S[j] = tmp;
    result[k] = data[k] ^ S[(S[i] + S[j]) & 0xff];
  }
  return result;
}
