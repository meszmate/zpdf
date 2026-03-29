/**
 * Platform detection and dynamic imports.
 */

export function isNode(): boolean {
  return (
    typeof process !== 'undefined' &&
    typeof process.versions !== 'undefined' &&
    typeof process.versions.node !== 'undefined'
  );
}

export function isBrowser(): boolean {
  return typeof globalThis !== 'undefined' && typeof (globalThis as any).window !== 'undefined';
}

export async function getZlib(): Promise<any> {
  if (!isNode()) return null;
  try {
    return await import('node:zlib');
  } catch {
    return null;
  }
}

export function getSubtleCrypto(): any {
  if (typeof globalThis !== 'undefined' && globalThis.crypto && globalThis.crypto.subtle) {
    return globalThis.crypto.subtle;
  }
  if (typeof crypto !== 'undefined' && crypto.subtle) {
    return crypto.subtle;
  }
  return null;
}
