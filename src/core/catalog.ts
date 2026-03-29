import type { PdfRef, PdfDict, PdfObject } from './types.js';
import { pdfDict, pdfName } from './objects.js';

export interface CatalogOptions {
  outlines?: PdfRef;
  names?: PdfRef;
  acroForm?: PdfRef;
  markInfo?: PdfDict;
  structTreeRoot?: PdfRef;
  ocProperties?: PdfRef;
  metadata?: PdfRef;
}

export function createCatalog(pagesRef: PdfRef, options?: CatalogOptions): PdfDict {
  const entries: Record<string, PdfObject> = {
    Type: pdfName('Catalog'),
    Pages: pagesRef,
  };

  if (options) {
    if (options.outlines) entries['Outlines'] = options.outlines;
    if (options.names) entries['Names'] = options.names;
    if (options.acroForm) entries['AcroForm'] = options.acroForm;
    if (options.markInfo) entries['MarkInfo'] = options.markInfo;
    if (options.structTreeRoot) entries['StructTreeRoot'] = options.structTreeRoot;
    if (options.ocProperties) entries['OCProperties'] = options.ocProperties;
    if (options.metadata) entries['Metadata'] = options.metadata;
  }

  return pdfDict(entries);
}
