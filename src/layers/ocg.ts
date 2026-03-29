import type { PdfRef } from '../core/types.js';
import { ObjectStore } from '../core/object-store.js';
import { pdfDict, pdfName, pdfStr, pdfArray } from '../core/objects.js';

/**
 * Create an Optional Content Group (OCG).
 * An OCG represents a named layer that can be toggled on/off.
 */
export function createOCG(store: ObjectStore, name: string, visible: boolean = true): PdfRef {
  const ref = store.allocRef();
  store.set(ref, pdfDict({
    Type: pdfName('OCG'),
    Name: pdfStr(name),
  }));
  return ref;
}

/**
 * Create an Optional Content Membership Dictionary (OCMD).
 * An OCMD defines visibility based on the state of one or more OCGs
 * using a visibility policy.
 */
export function createOCMD(
  store: ObjectStore,
  ocgs: PdfRef[],
  policy: 'AllOn' | 'AnyOn' | 'AnyOff' | 'AllOff' = 'AnyOn',
): PdfRef {
  const ref = store.allocRef();
  store.set(ref, pdfDict({
    Type: pdfName('OCMD'),
    OCGs: pdfArray(...ocgs),
    P: pdfName(policy),
  }));
  return ref;
}
