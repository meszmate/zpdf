/**
 * Copy pages between PDF documents.
 * Uses RefRemapper to deep-copy page objects and all their dependencies.
 */

import type { PdfRef, PdfDict, PdfObject } from '../core/types.js';
import { ObjectStore } from '../core/object-store.js';
import { RefRemapper } from './ref-remapper.js';

export interface SourceDocument {
  store: ObjectStore;
  pageRefs: PdfRef[];
}

/**
 * Copy pages from a source document to a target store.
 * Returns an array of new page refs in the target store.
 *
 * @param source - Source document with store and page refs
 * @param target - Target store to copy into
 * @param pageIndices - Which pages to copy (0-based indices)
 * @returns Array of new PdfRef for copied pages in target store
 */
export function copyPages(
  source: SourceDocument,
  target: { store: ObjectStore },
  pageIndices: number[],
): PdfRef[] {
  const remapper = new RefRemapper(target.store);
  const newPageRefs: PdfRef[] = [];

  for (const pageIndex of pageIndices) {
    if (pageIndex < 0 || pageIndex >= source.pageRefs.length) {
      throw new Error(`Page index ${pageIndex} out of range (0-${source.pageRefs.length - 1})`);
    }

    const sourcePageRef = source.pageRefs[pageIndex];
    const sourcePageObj = source.store.get(sourcePageRef);
    if (!sourcePageObj || sourcePageObj.type !== 'dict') {
      throw new Error(`Page ${pageIndex} is not a valid dict`);
    }

    // Deep-copy the page and all its dependencies
    const newPageRef = remapper.copyObjectGraph(sourcePageRef, source.store);

    // Strip /Parent reference (will be set by new page tree)
    const newPageObj = target.store.get(newPageRef);
    if (newPageObj && newPageObj.type === 'dict') {
      const strippedEntries = new Map(newPageObj.entries);
      strippedEntries.delete('Parent');
      target.store.set(newPageRef, { type: 'dict', entries: strippedEntries });
    }

    newPageRefs.push(newPageRef);
  }

  return newPageRefs;
}

/**
 * Set the Parent reference on a page dict.
 */
export function setPageParent(store: ObjectStore, pageRef: PdfRef, parentRef: PdfRef): void {
  const obj = store.get(pageRef);
  if (!obj || obj.type !== 'dict') return;
  const entries = new Map(obj.entries);
  entries.set('Parent', parentRef);
  store.set(pageRef, { type: 'dict', entries });
}
