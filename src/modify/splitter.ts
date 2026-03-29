/**
 * PDF Splitter - split PDF documents by pages or ranges.
 */

import type { PdfRef } from '../core/types.js';
import { ObjectStore } from '../core/object-store.js';
import { pdfDict, pdfName, pdfNum, pdfArray } from '../core/objects.js';
import { writePdf } from '../writer/pdf-writer.js';
import { copyPages, setPageParent, type SourceDocument } from './page-copier.js';
import { parseMiniPdf } from './mini-parser.js';

export class PDFSplitter {
  /**
   * Split a PDF into individual pages, each as a separate PDF.
   * Returns an array of Uint8Array, one per page.
   */
  static async splitByPage(pdfBytes: Uint8Array): Promise<Uint8Array[]> {
    const parsed = parseMiniPdf(pdfBytes);
    const results: Uint8Array[] = [];

    for (let i = 0; i < parsed.pageRefs.length; i++) {
      const pdf = await PDFSplitter.buildSingleDocument(parsed, [i]);
      results.push(pdf);
    }

    return results;
  }

  /**
   * Split by page ranges (inclusive).
   * Each range is [startIndex, endIndex] (0-based, inclusive).
   * Returns one PDF per range.
   */
  static async splitByRanges(
    pdfBytes: Uint8Array,
    ranges: Array<[number, number]>,
  ): Promise<Uint8Array[]> {
    const parsed = parseMiniPdf(pdfBytes);
    const results: Uint8Array[] = [];

    for (const [start, end] of ranges) {
      if (start < 0 || end >= parsed.pageRefs.length || start > end) {
        throw new Error(`Invalid range [${start}, ${end}] for document with ${parsed.pageRefs.length} pages`);
      }
      const indices = Array.from({ length: end - start + 1 }, (_, i) => start + i);
      const pdf = await PDFSplitter.buildSingleDocument(parsed, indices);
      results.push(pdf);
    }

    return results;
  }

  /**
   * Extract specific pages into a new PDF.
   * @param pdfBytes - Source PDF
   * @param pageIndices - 0-based page indices to extract
   * @returns New PDF containing only the specified pages
   */
  static async extractPages(pdfBytes: Uint8Array, pageIndices: number[]): Promise<Uint8Array> {
    const parsed = parseMiniPdf(pdfBytes);
    return PDFSplitter.buildSingleDocument(parsed, pageIndices);
  }

  /**
   * Build a single PDF document from selected pages of a parsed source.
   */
  private static async buildSingleDocument(
    source: { store: ObjectStore; pageRefs: PdfRef[] },
    pageIndices: number[],
  ): Promise<Uint8Array> {
    const targetStore = new ObjectStore();

    const sourceDoc: SourceDocument = {
      store: source.store,
      pageRefs: source.pageRefs,
    };

    const newPageRefs = copyPages(sourceDoc, { store: targetStore }, pageIndices);

    // Build page tree
    const pagesRef = targetStore.allocRef();
    targetStore.set(pagesRef, pdfDict({
      Type: pdfName('Pages'),
      Kids: pdfArray(...newPageRefs),
      Count: pdfNum(newPageRefs.length),
    }));

    // Set Parent on each page
    for (const pageRef of newPageRefs) {
      setPageParent(targetStore, pageRef, pagesRef);
    }

    // Create catalog
    const catalogRef = targetStore.allocRef();
    targetStore.set(catalogRef, pdfDict({
      Type: pdfName('Catalog'),
      Pages: pagesRef,
    }));

    return writePdf(targetStore, catalogRef, { compress: true });
  }
}
