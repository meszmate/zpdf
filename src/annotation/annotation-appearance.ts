import type { PdfStream } from '../core/types.js';
import type { Color } from '../color/color.js';
import type { TextAnnotation, FreeTextAnnotation, StampAnnotation } from './annotation.js';
import { pdfStream, pdfName, pdfNum, pdfArray } from '../core/objects.js';

/* ------------------------------------------------------------------ */
/*  Helpers                                                           */
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

function colorOps(color: Color, stroke: boolean): string {
  switch (color.type) {
    case 'rgb':
      return `${f(color.r)} ${f(color.g)} ${f(color.b)} ${stroke ? 'RG' : 'rg'}`;
    case 'cmyk':
      return `${f(color.c)} ${f(color.m)} ${f(color.y)} ${f(color.k)} ${stroke ? 'K' : 'k'}`;
    case 'grayscale':
      return `${f(color.gray)} ${stroke ? 'G' : 'g'}`;
  }
}

function makeBBox(rect: [number, number, number, number]): [number, number, number, number] {
  const w = Math.abs(rect[2] - rect[0]);
  const h = Math.abs(rect[3] - rect[1]);
  return [0, 0, w, h];
}

function makeAppearanceStream(content: string, bbox: [number, number, number, number]): PdfStream {
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

/* ------------------------------------------------------------------ */
/*  Escape PDF string for content stream                              */
/* ------------------------------------------------------------------ */

function escapeStr(text: string): string {
  return text
    .replace(/\\/g, '\\\\')
    .replace(/\(/g, '\\(')
    .replace(/\)/g, '\\)');
}

/* ------------------------------------------------------------------ */
/*  Text annotation appearance (note icon)                            */
/* ------------------------------------------------------------------ */

export function generateTextAnnotationAppearance(annotation: TextAnnotation): PdfStream {
  const bbox: [number, number, number, number] = [0, 0, 24, 24];

  // Draw a small note/page icon
  const ops: string[] = [];
  ops.push('q');

  // Background
  ops.push('1 0.85 0.3 rg'); // Yellowish
  ops.push('0 0 24 24 re');
  ops.push('f');

  // Border
  ops.push('0.4 0.3 0 RG');
  ops.push('0.5 w');
  ops.push('0 0 24 24 re');
  ops.push('S');

  // Lines on the note
  ops.push('0.4 0.3 0 RG');
  ops.push('0.5 w');
  ops.push('4 18 m 20 18 l S');
  ops.push('4 14 m 20 14 l S');
  ops.push('4 10 m 20 10 l S');
  ops.push('4 6 m 14 6 l S');

  ops.push('Q');

  return makeAppearanceStream(ops.join('\n'), bbox);
}

/* ------------------------------------------------------------------ */
/*  FreeText annotation appearance                                    */
/* ------------------------------------------------------------------ */

export function generateFreeTextAppearance(annotation: FreeTextAnnotation): PdfStream {
  const bbox = makeBBox(annotation.rect);
  const w = bbox[2];
  const h = bbox[3];
  const fontSize = annotation.fontSize ?? 12;

  const ops: string[] = [];
  ops.push('q');

  // Background (white by default)
  if (annotation.color) {
    ops.push(colorOps(annotation.color, false));
  } else {
    ops.push('1 1 1 rg');
  }
  ops.push(`0 0 ${f(w)} ${f(h)} re`);
  ops.push('f');

  // Border
  ops.push('0 0 0 RG');
  ops.push('0.5 w');
  ops.push(`0 0 ${f(w)} ${f(h)} re`);
  ops.push('S');

  // Text
  ops.push('BT');

  if (annotation.fontColor) {
    ops.push(colorOps(annotation.fontColor, false));
  } else {
    ops.push('0 0 0 rg');
  }

  ops.push(`/Helv ${f(fontSize)} Tf`);

  // Position text with padding
  const padding = 2;
  const textY = h - fontSize - padding;

  // Alignment
  const alignment = annotation.alignment ?? 0;
  let textX = padding;
  if (alignment === 1) {
    textX = w / 2;
  } else if (alignment === 2) {
    textX = w - padding;
  }

  ops.push(`${f(textX)} ${f(textY)} Td`);

  // Split content into lines and render
  const lines = annotation.content.split('\n');
  for (let i = 0; i < lines.length; i++) {
    if (i > 0) {
      ops.push(`0 ${f(-fontSize * 1.2)} Td`);
    }
    ops.push(`(${escapeStr(lines[i])}) Tj`);
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
      Resources: pdfName('<<>>') // Placeholder; in practice the font resource dict would be set
    },
    data,
  );
}

/* ------------------------------------------------------------------ */
/*  Stamp annotation appearance                                       */
/* ------------------------------------------------------------------ */

export function generateStampAppearance(annotation: StampAnnotation): PdfStream {
  const bbox = makeBBox(annotation.rect);
  const w = bbox[2];
  const h = bbox[3];
  const stampText = annotation.stampName ?? 'Draft';

  const ops: string[] = [];
  ops.push('q');

  // Red stamp color
  if (annotation.color) {
    ops.push(colorOps(annotation.color, true));
    ops.push(colorOps(annotation.color, false));
  } else {
    ops.push('1 0 0 RG');
    ops.push('1 0.9 0.9 rg');
  }

  // Rounded rectangle border
  const r = Math.min(8, w * 0.05, h * 0.1);
  ops.push('2 w');
  ops.push(`${f(r)} 0 m`);
  ops.push(`${f(w - r)} 0 l`);
  ops.push(`${f(w)} 0 ${f(w)} ${f(r)} v`);
  ops.push(`${f(w)} ${f(h - r)} l`);
  ops.push(`${f(w)} ${f(h)} ${f(w - r)} ${f(h)} v`);
  ops.push(`${f(r)} ${f(h)} l`);
  ops.push(`0 ${f(h)} 0 ${f(h - r)} v`);
  ops.push(`0 ${f(r)} l`);
  ops.push(`0 0 ${f(r)} 0 v`);
  ops.push('B');

  // Stamp text
  ops.push('BT');
  if (annotation.color) {
    ops.push(colorOps(annotation.color, false));
  } else {
    ops.push('1 0 0 rg');
  }

  // Scale font to fit
  const estFontSize = Math.min(h * 0.6, w / (stampText.length * 0.6));
  const fontSize = Math.max(6, estFontSize);

  ops.push(`/Helv ${f(fontSize)} Tf`);

  // Center text
  const textWidth = stampText.length * fontSize * 0.6;
  const tx = (w - textWidth) / 2;
  const ty = (h - fontSize) / 2;
  ops.push(`${f(tx)} ${f(ty)} Td`);
  ops.push(`(${escapeStr(stampText)}) Tj`);
  ops.push('ET');

  ops.push('Q');

  return makeAppearanceStream(ops.join('\n'), bbox);
}
