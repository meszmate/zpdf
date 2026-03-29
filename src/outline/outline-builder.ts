import type { PdfRef, PdfObject } from '../core/types.js';
import type { ObjectStore } from '../core/object-store.js';
import type { Color } from '../color/color.js';
import type { OutlineItemOptions } from './outline-item.js';
import type { OutlineTree } from './outline.js';
import {
  pdfName, pdfNum, pdfStr, pdfDict, pdfArray, pdfNull,
} from '../core/objects.js';

/* ------------------------------------------------------------------ */
/*  buildOutline                                                      */
/* ------------------------------------------------------------------ */

/**
 * Build a PDF outline (bookmarks) dictionary hierarchy from an OutlineTree.
 * Returns a ref to the /Type /Outlines root dictionary, or null if empty.
 */
export function buildOutline(
  store: ObjectStore,
  tree: OutlineTree,
): PdfRef | null {
  const items = tree.getItems();
  if (items.length === 0) return null;

  // Allocate the root /Outlines dict ref
  const rootRef = store.allocRef();

  // Build item hierarchy recursively
  const { firstRef, lastRef, totalCount } = buildItemList(store, items, rootRef);

  // Create the root /Outlines dict
  const rootEntries: Record<string, PdfObject> = {
    Type: pdfName('Outlines'),
    First: firstRef,
    Last: lastRef,
    Count: pdfNum(totalCount),
  };

  store.set(rootRef, pdfDict(rootEntries));

  return rootRef;
}

/* ------------------------------------------------------------------ */
/*  Build a list of sibling outline items                             */
/* ------------------------------------------------------------------ */

interface BuildResult {
  firstRef: PdfRef;
  lastRef: PdfRef;
  totalCount: number;
}

function buildItemList(
  store: ObjectStore,
  items: OutlineItemOptions[],
  parentRef: PdfRef,
): BuildResult {
  // Allocate refs for all items upfront so we can set /Next and /Prev
  const refs: PdfRef[] = [];
  for (let i = 0; i < items.length; i++) {
    refs.push(store.allocRef());
  }

  let totalCount = items.length;

  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    const ref = refs[i];
    const entries: Record<string, PdfObject> = {};

    // Title (required)
    entries['Title'] = pdfStr(item.title);

    // Parent
    entries['Parent'] = parentRef;

    // Destination: [pageRef /XYZ x y zoom] or [pageRef /Fit]
    const dest = item.destination;
    if (dest.x !== undefined || dest.y !== undefined) {
      entries['Dest'] = pdfArray(
        dest.page,
        pdfName('XYZ'),
        pdfNum(dest.x ?? 0),
        pdfNum(dest.y ?? 0),
        pdfNum(dest.zoom ?? 0),
      );
    } else {
      entries['Dest'] = pdfArray(dest.page, pdfName('Fit'));
    }

    // Sibling links
    if (i > 0) {
      entries['Prev'] = refs[i - 1];
    }
    if (i < items.length - 1) {
      entries['Next'] = refs[i + 1];
    }

    // Color
    if (item.color) {
      entries['C'] = colorToOutlineArray(item.color);
    }

    // Flags: 1 = italic, 2 = bold
    let flags = 0;
    if (item.italic) flags |= 1;
    if (item.bold) flags |= 2;
    if (flags !== 0) {
      entries['F'] = pdfNum(flags);
    }

    // Children
    if (item.children && item.children.length > 0) {
      const childResult = buildItemList(store, item.children, ref);
      entries['First'] = childResult.firstRef;
      entries['Last'] = childResult.lastRef;
      entries['Count'] = pdfNum(childResult.totalCount);
      totalCount += childResult.totalCount;
    }

    store.set(ref, pdfDict(entries));
  }

  return {
    firstRef: refs[0],
    lastRef: refs[refs.length - 1],
    totalCount,
  };
}

/* ------------------------------------------------------------------ */
/*  Helpers                                                           */
/* ------------------------------------------------------------------ */

function colorToOutlineArray(c: Color): PdfObject {
  // PDF outline /C entry is always RGB (3 numbers)
  if (c.type === 'rgb') {
    return pdfArray(pdfNum(c.r), pdfNum(c.g), pdfNum(c.b));
  }
  if (c.type === 'grayscale') {
    return pdfArray(pdfNum(c.gray), pdfNum(c.gray), pdfNum(c.gray));
  }
  // CMYK -> rough RGB conversion for outline color
  const r = (1 - c.c) * (1 - c.k);
  const g = (1 - c.m) * (1 - c.k);
  const b = (1 - c.y) * (1 - c.k);
  return pdfArray(pdfNum(r), pdfNum(g), pdfNum(b));
}
