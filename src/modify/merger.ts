/**
 * PDF Merger - merge multiple PDF documents into one.
 */

import type { PdfRef, PdfObject } from '../core/types.js';
import { ObjectStore } from '../core/object-store.js';
import { pdfDict, pdfName, pdfNum, pdfArray } from '../core/objects.js';
import { writePdf } from '../writer/pdf-writer.js';
import { copyPages, setPageParent, type SourceDocument } from './page-copier.js';
import { parseMiniPdf, type MiniParsedPdf } from './mini-parser.js';

export class PDFMerger {
  private documents: Array<{ data: Uint8Array; pages?: number[] }> = [];

  /**
   * Add a PDF to the merge queue.
   * @param pdfBytes - Raw PDF bytes
   * @param pages - Optional array of 0-based page indices to include. If omitted, all pages are included.
   */
  add(pdfBytes: Uint8Array, pages?: number[]): this {
    this.documents.push({ data: pdfBytes, pages });
    return this;
  }

  /**
   * Merge all added PDFs into a single PDF.
   * @returns The merged PDF as a Uint8Array
   */
  async merge(): Promise<Uint8Array> {
    if (this.documents.length === 0) {
      throw new Error('No documents to merge');
    }

    // Parse all input PDFs
    const parsed: MiniParsedPdf[] = [];
    for (const doc of this.documents) {
      parsed.push(parseMiniPdf(doc.data));
    }

    // Create new target store and catalog
    const targetStore = new ObjectStore();

    // Copy pages from each document
    const allPageRefs: PdfRef[] = [];

    for (let i = 0; i < parsed.length; i++) {
      const source: SourceDocument = {
        store: parsed[i].store,
        pageRefs: parsed[i].pageRefs,
      };

      const pageIndices = this.documents[i].pages ??
        Array.from({ length: source.pageRefs.length }, (_, idx) => idx);

      const newRefs = copyPages(source, { store: targetStore }, pageIndices);
      allPageRefs.push(...newRefs);
    }

    // Build page tree
    const pagesRef = targetStore.allocRef();
    targetStore.set(pagesRef, pdfDict({
      Type: pdfName('Pages'),
      Kids: pdfArray(...allPageRefs),
      Count: pdfNum(allPageRefs.length),
    }));

    // Set Parent on each page
    for (const pageRef of allPageRefs) {
      setPageParent(targetStore, pageRef, pagesRef);
    }

    // Create catalog
    const catalogRef = targetStore.allocRef();
    targetStore.set(catalogRef, pdfDict({
      Type: pdfName('Catalog'),
      Pages: pagesRef,
    }));

    // Write the merged PDF
    return writePdf(targetStore, catalogRef, { compress: true });
  }
}
