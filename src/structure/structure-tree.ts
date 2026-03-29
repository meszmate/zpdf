import type { PdfRef, PdfObject } from '../core/types.js';
import { ObjectStore } from '../core/object-store.js';
import {
  pdfDict, pdfName, pdfNum, pdfArray, pdfStr, pdfBool,
} from '../core/objects.js';
import type { StructureTag } from './tags.js';

export interface StructureElement {
  tag: StructureTag;
  mcid?: number;
  altText?: string;
  actualText?: string;
  lang?: string;
  children: StructureElement[];
  /** Internal: which page index this element is on */
  pageIndex?: number;
}

/**
 * Builds a PDF structure tree for tagged/accessible PDFs.
 */
export class StructureTree {
  private root: StructureElement = { tag: 'Document', children: [] };
  private mcidCounter = 0;

  /**
   * Add a structure element under the parent identified by parentPath.
   * parentPath is an array of child indices from root. An empty array means add to root.
   * Returns the MCID assigned to this element for use in content stream BDC operators.
   */
  addElement(
    parentPath: number[],
    tag: StructureTag,
    options?: { altText?: string; actualText?: string; lang?: string; pageIndex?: number },
  ): number {
    let parent = this.root;
    for (const idx of parentPath) {
      if (idx < 0 || idx >= parent.children.length) {
        throw new Error(`Invalid parent path index ${idx}`);
      }
      parent = parent.children[idx];
    }
    const mcid = this.mcidCounter++;
    const element: StructureElement = {
      tag,
      mcid,
      altText: options?.altText,
      actualText: options?.actualText,
      lang: options?.lang,
      pageIndex: options?.pageIndex ?? 0,
      children: [],
    };
    parent.children.push(element);
    return mcid;
  }

  getRoot(): StructureElement {
    return this.root;
  }

  /**
   * Build the structure tree as PDF objects and store them.
   * Returns a ref to the StructTreeRoot dict.
   */
  build(store: ObjectStore, pageRefs: PdfRef[]): PdfRef {
    // parentTree maps MCID -> struct element ref
    const parentTreeEntries: Array<{ mcid: number; elemRef: PdfRef }> = [];

    const treeRootRef = store.allocRef();

    // Recursively build structure elements
    const buildElement = (
      elem: StructureElement,
      parentRef: PdfRef,
    ): PdfRef => {
      const elemRef = store.allocRef();
      const kids: PdfObject[] = [];

      for (const child of elem.children) {
        if (child.children.length > 0) {
          // Non-leaf: recurse
          const childRef = buildElement(child, elemRef);
          kids.push(childRef);
          // If child also has an mcid, add a marked-content reference as well
          if (child.mcid !== undefined) {
            parentTreeEntries.push({ mcid: child.mcid, elemRef });
          }
        } else {
          // Leaf: create marked-content reference dict
          if (child.mcid !== undefined) {
            const childElemRef = store.allocRef();
            const pageIdx = child.pageIndex ?? 0;
            const pageRef = pageIdx < pageRefs.length ? pageRefs[pageIdx] : pageRefs[0];

            const childEntries: Record<string, PdfObject> = {
              Type: pdfName('StructElem'),
              S: pdfName(child.tag),
              P: elemRef,
              Pg: pageRef,
              K: pdfNum(child.mcid),
            };
            if (child.altText) childEntries['Alt'] = pdfStr(child.altText);
            if (child.actualText) childEntries['ActualText'] = pdfStr(child.actualText);
            if (child.lang) childEntries['Lang'] = pdfStr(child.lang);

            store.set(childElemRef, pdfDict(childEntries));
            kids.push(childElemRef);
            parentTreeEntries.push({ mcid: child.mcid, elemRef: childElemRef });
          }
        }
      }

      const entries: Record<string, PdfObject> = {
        Type: pdfName('StructElem'),
        S: pdfName(elem.tag),
        P: parentRef,
      };
      if (kids.length === 1) {
        entries['K'] = kids[0];
      } else if (kids.length > 1) {
        entries['K'] = pdfArray(...kids);
      }
      if (elem.altText) entries['Alt'] = pdfStr(elem.altText);
      if (elem.actualText) entries['ActualText'] = pdfStr(elem.actualText);
      if (elem.lang) entries['Lang'] = pdfStr(elem.lang);
      if (elem.pageIndex !== undefined && elem.pageIndex < pageRefs.length) {
        entries['Pg'] = pageRefs[elem.pageIndex];
      }

      store.set(elemRef, pdfDict(entries));
      return elemRef;
    };

    // Build root element children
    const rootKids: PdfObject[] = [];
    for (const child of this.root.children) {
      if (child.children.length > 0 || child.mcid !== undefined) {
        const childRef = buildElement(child, treeRootRef);
        rootKids.push(childRef);
      }
    }

    // Build parent tree as a number tree
    // Sort entries by MCID
    parentTreeEntries.sort((a, b) => a.mcid - b.mcid);
    const numsArray: PdfObject[] = [];
    for (const entry of parentTreeEntries) {
      numsArray.push(pdfNum(entry.mcid));
      numsArray.push(entry.elemRef);
    }

    const parentTreeRef = store.allocRef();
    store.set(parentTreeRef, pdfDict({
      Nums: pdfArray(...numsArray),
    }));

    // Build StructTreeRoot
    const treeRootEntries: Record<string, PdfObject> = {
      Type: pdfName('StructTreeRoot'),
      ParentTree: parentTreeRef,
    };
    if (rootKids.length === 1) {
      treeRootEntries['K'] = rootKids[0];
    } else if (rootKids.length > 0) {
      treeRootEntries['K'] = pdfArray(...rootKids);
    }

    store.set(treeRootRef, pdfDict(treeRootEntries));
    return treeRootRef;
  }
}
