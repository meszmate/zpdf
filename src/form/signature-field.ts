import type { PdfRef, PdfObject, PdfStream } from '../core/types.js';
import type { ObjectStore } from '../core/object-store.js';
import type { SignatureFieldOptions } from './form.js';
import {
  pdfName, pdfNum, pdfStr, pdfDict, pdfArray, pdfNull, pdfStream,
} from '../core/objects.js';

export function createSignatureField(
  store: ObjectStore,
  pageRef: PdfRef,
  options: SignatureFieldOptions,
): PdfRef {
  // Generate placeholder appearance
  const apStream = generateSignaturePlaceholder(options);
  const apRef = store.allocRef();
  store.set(apRef, apStream);

  // Build signature value dict (placeholder, no actual signature data)
  const sigValueEntries: Record<string, PdfObject> = {
    Type: pdfName('Sig'),
    Filter: pdfName('Adobe.PPKLite'),
    SubFilter: pdfName('adbe.pkcs7.detached'),
  };

  if (options.reason) {
    sigValueEntries['Reason'] = pdfStr(options.reason);
  }
  if (options.location) {
    sigValueEntries['Location'] = pdfStr(options.location);
  }
  if (options.contactInfo) {
    sigValueEntries['ContactInfo'] = pdfStr(options.contactInfo);
  }

  const sigValueRef = store.allocRef();
  store.set(sigValueRef, pdfDict(sigValueEntries));

  // Build the widget/field dict
  const entries: Record<string, PdfObject> = {
    Type: pdfName('Annot'),
    Subtype: pdfName('Widget'),
    FT: pdfName('Sig'),
    Rect: pdfArray(
      pdfNum(options.rect[0]),
      pdfNum(options.rect[1]),
      pdfNum(options.rect[2]),
      pdfNum(options.rect[3]),
    ),
    T: pdfStr(options.name),
    V: sigValueRef,
    P: pageRef,
    AP: pdfDict({ N: apRef }),
  };

  const ref = store.allocRef();
  store.set(ref, pdfDict(entries));
  return ref;
}

/* ------------------------------------------------------------------ */
/*  Signature placeholder appearance                                  */
/* ------------------------------------------------------------------ */

function textEncoder(text: string): Uint8Array {
  const bytes: number[] = [];
  for (let i = 0; i < text.length; i++) {
    bytes.push(text.charCodeAt(i) & 0xff);
  }
  return new Uint8Array(bytes);
}

function f(n: number): string {
  return Number.isInteger(n) ? n.toString() : n.toFixed(4);
}

function escapeStr(text: string): string {
  return text
    .replace(/\\/g, '\\\\')
    .replace(/\(/g, '\\(')
    .replace(/\)/g, '\\)');
}

function generateSignaturePlaceholder(options: SignatureFieldOptions): PdfStream {
  const [x1, y1, x2, y2] = options.rect;
  const w = Math.abs(x2 - x1);
  const h = Math.abs(y2 - y1);
  const bbox: [number, number, number, number] = [0, 0, w, h];

  const ops: string[] = [];
  ops.push('q');

  // Light gray background
  ops.push('0.95 0.95 0.95 rg');
  ops.push(`0 0 ${f(w)} ${f(h)} re`);
  ops.push('f');

  // Dashed border
  ops.push('0.6 0.6 0.6 RG');
  ops.push('1 w');
  ops.push('[4 2] 0 d');
  ops.push(`0.5 0.5 ${f(w - 1)} ${f(h - 1)} re`);
  ops.push('S');

  // Signature label text
  ops.push('BT');
  ops.push('0.4 0.4 0.4 rg');

  const fontSize = Math.min(12, h * 0.25);
  ops.push(`/Helv ${f(fontSize)} Tf`);

  // Title line
  const titleText = `Signature: ${options.name}`;
  const titleWidth = titleText.length * fontSize * 0.6;
  const titleX = Math.max(2, (w - titleWidth) / 2);
  ops.push(`${f(titleX)} ${f(h - fontSize - 4)} Td`);
  ops.push(`(${escapeStr(titleText)}) Tj`);

  // Detail lines
  const detailFontSize = Math.min(9, h * 0.15);
  let detailY = h - fontSize - 4 - detailFontSize * 1.5;

  if (options.reason) {
    ops.push(`/Helv ${f(detailFontSize)} Tf`);
    ops.push(`${f(4 - titleX)} ${f(detailY - (h - fontSize - 4))} Td`);
    ops.push(`(Reason: ${escapeStr(options.reason)}) Tj`);
    detailY -= detailFontSize * 1.5;
  }

  if (options.location) {
    ops.push(`/Helv ${f(detailFontSize)} Tf`);
    const prevY = options.reason
      ? detailY + detailFontSize * 1.5
      : h - fontSize - 4;
    ops.push(`0 ${f(detailY - prevY)} Td`);
    ops.push(`(Location: ${escapeStr(options.location)}) Tj`);
    detailY -= detailFontSize * 1.5;
  }

  if (options.contactInfo) {
    ops.push(`/Helv ${f(detailFontSize)} Tf`);
    const prevY2 = options.location
      ? detailY + detailFontSize * 1.5
      : options.reason
        ? detailY + detailFontSize * 1.5
        : h - fontSize - 4;
    ops.push(`0 ${f(detailY - prevY2)} Td`);
    ops.push(`(Contact: ${escapeStr(options.contactInfo)}) Tj`);
  }

  ops.push('ET');
  ops.push('Q');

  const content = ops.join('\n');
  const data = textEncoder(content);

  return pdfStream(
    {
      Type: pdfName('XObject'),
      Subtype: pdfName('Form'),
      BBox: pdfArray(pdfNum(bbox[0]), pdfNum(bbox[1]), pdfNum(bbox[2]), pdfNum(bbox[3])),
      Length: pdfNum(data.length),
    },
    data,
  );
}
