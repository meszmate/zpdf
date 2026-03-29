/**
 * Page manipulation operations.
 * Low-level functions for modifying page properties.
 */

import type { PdfRef, PdfObject } from '../core/types.js';
import { ObjectStore } from '../core/object-store.js';
import { pdfNum, pdfArray, pdfName } from '../core/objects.js';

/**
 * Set the rotation angle on a page.
 * @param store - Object store
 * @param pageRef - Reference to the page dict
 * @param degrees - Rotation angle: 0, 90, 180, or 270
 */
export function rotatePage(
  store: ObjectStore,
  pageRef: PdfRef,
  degrees: 0 | 90 | 180 | 270,
): void {
  const obj = store.get(pageRef);
  if (!obj || obj.type !== 'dict') {
    throw new Error('Page ref does not point to a dict');
  }

  const entries = new Map(obj.entries);

  if (degrees === 0) {
    entries.delete('Rotate');
  } else {
    entries.set('Rotate', pdfNum(degrees));
  }

  store.set(pageRef, { type: 'dict', entries });
}

/**
 * Resize a page by updating its /MediaBox.
 * @param store - Object store
 * @param pageRef - Reference to the page dict
 * @param width - New page width in points
 * @param height - New page height in points
 */
export function resizePage(
  store: ObjectStore,
  pageRef: PdfRef,
  width: number,
  height: number,
): void {
  const obj = store.get(pageRef);
  if (!obj || obj.type !== 'dict') {
    throw new Error('Page ref does not point to a dict');
  }

  const entries = new Map(obj.entries);
  entries.set('MediaBox', pdfArray(pdfNum(0), pdfNum(0), pdfNum(width), pdfNum(height)));

  // Also update CropBox if it exists, to match
  if (entries.has('CropBox')) {
    entries.set('CropBox', pdfArray(pdfNum(0), pdfNum(0), pdfNum(width), pdfNum(height)));
  }

  store.set(pageRef, { type: 'dict', entries });
}

/**
 * Reorder pages according to the given index mapping.
 * @param pageRefs - Current ordered array of page refs
 * @param newOrder - Array of indices into pageRefs defining the new order.
 *                   For example [2,0,1] moves page 2 to front, then page 0, then page 1.
 * @returns New array of page refs in the specified order
 */
export function reorderPages(pageRefs: PdfRef[], newOrder: number[]): PdfRef[] {
  if (newOrder.length !== pageRefs.length) {
    throw new Error(`newOrder length (${newOrder.length}) does not match pageRefs length (${pageRefs.length})`);
  }

  // Validate indices
  const seen = new Set<number>();
  for (const idx of newOrder) {
    if (idx < 0 || idx >= pageRefs.length) {
      throw new Error(`Index ${idx} out of range (0-${pageRefs.length - 1})`);
    }
    if (seen.has(idx)) {
      throw new Error(`Duplicate index ${idx} in newOrder`);
    }
    seen.add(idx);
  }

  return newOrder.map(i => pageRefs[i]);
}

/**
 * Remove a page at the given index from the page refs array.
 * @param pageRefs - Current array of page refs
 * @param index - 0-based index of the page to remove
 * @returns New array without the page at index
 */
export function deletePage(pageRefs: PdfRef[], index: number): PdfRef[] {
  if (index < 0 || index >= pageRefs.length) {
    throw new Error(`Index ${index} out of range (0-${pageRefs.length - 1})`);
  }
  if (pageRefs.length <= 1) {
    throw new Error('Cannot delete the last page');
  }

  return [...pageRefs.slice(0, index), ...pageRefs.slice(index + 1)];
}
