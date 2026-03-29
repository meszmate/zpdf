import type { PdfRef } from './types.js';

export function refEquals(a: PdfRef, b: PdfRef): boolean {
  return a.objectNumber === b.objectNumber && a.generation === b.generation;
}

export function refToString(ref: PdfRef): string {
  return `${ref.objectNumber} ${ref.generation} R`;
}

export function refKey(ref: PdfRef): string {
  return `${ref.objectNumber}:${ref.generation}`;
}
