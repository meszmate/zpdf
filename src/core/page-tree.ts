import type { PdfRef, PdfDict, PdfObject } from './types.js';
import { pdfDict, pdfName, pdfNum, pdfArray, pdfRef } from './objects.js';

export function createPageTreeRoot(pageRefs: PdfRef[]): PdfDict {
  return pdfDict({
    Type: pdfName('Pages'),
    Kids: pdfArray(...pageRefs),
    Count: pdfNum(pageRefs.length),
  });
}

export function createPageNode(
  parent: PdfRef,
  mediaBox: number[],
  resources: PdfRef | PdfDict,
  contents: PdfRef | PdfRef[],
): PdfDict {
  const entries: Record<string, PdfObject> = {
    Type: pdfName('Page'),
    Parent: parent,
    MediaBox: pdfArray(...mediaBox.map((n) => pdfNum(n))),
    Resources: resources,
  };

  if (Array.isArray(contents)) {
    entries['Contents'] = pdfArray(...contents);
  } else {
    entries['Contents'] = contents;
  }

  return pdfDict(entries);
}
