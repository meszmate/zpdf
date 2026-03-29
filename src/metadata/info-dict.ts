import type { PdfDict } from '../core/types.js';
import { pdfDict, pdfStr, pdfName } from '../core/objects.js';
import { formatPdfDate } from '../utils/string-utils.js';

export interface DocumentInfo {
  title?: string;
  author?: string;
  subject?: string;
  keywords?: string[];
  creator?: string;
  producer?: string;
  creationDate?: Date;
  modDate?: Date;
  custom?: Record<string, string>;
}

/**
 * Create a PDF Info dictionary from document metadata.
 */
export function createInfoDict(info: DocumentInfo): PdfDict {
  const entries: Record<string, ReturnType<typeof pdfStr>> = {};

  if (info.title) entries['Title'] = pdfStr(info.title);
  if (info.author) entries['Author'] = pdfStr(info.author);
  if (info.subject) entries['Subject'] = pdfStr(info.subject);
  if (info.keywords && info.keywords.length > 0) {
    entries['Keywords'] = pdfStr(info.keywords.join(', '));
  }
  if (info.creator) entries['Creator'] = pdfStr(info.creator);
  if (info.producer) entries['Producer'] = pdfStr(info.producer);
  if (info.creationDate) {
    entries['CreationDate'] = pdfStr(formatPdfDate(info.creationDate));
  }
  if (info.modDate) {
    entries['ModDate'] = pdfStr(formatPdfDate(info.modDate));
  }
  if (info.custom) {
    for (const [key, value] of Object.entries(info.custom)) {
      entries[key] = pdfStr(value);
    }
  }

  return pdfDict(entries);
}
