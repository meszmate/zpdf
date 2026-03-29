import type { Matrix } from '../utils/math.js';
import type { PdfRef, PdfObject } from '../core/types.js';
import { ObjectStore } from '../core/object-store.js';
import { pdfName, pdfNum, pdfDict, pdfArray, pdfStream } from '../core/objects.js';

export interface TilingPatternOptions {
  bbox: [number, number, number, number];
  xStep: number;
  yStep: number;
  paintType: 1 | 2;
  tilingType: 1 | 2 | 3;
  matrix?: Matrix;
  content: string;
}

export function createTilingPattern(
  store: ObjectStore,
  options: TilingPatternOptions,
): PdfRef {
  const { bbox, xStep, yStep, paintType, tilingType, matrix, content } = options;

  const contentBytes = new TextEncoder().encode(content);

  const dictEntries: Record<string, PdfObject> = {
    Type: pdfName('Pattern'),
    PatternType: pdfNum(1), // Tiling pattern
    PaintType: pdfNum(paintType),
    TilingType: pdfNum(tilingType),
    BBox: pdfArray(pdfNum(bbox[0]), pdfNum(bbox[1]), pdfNum(bbox[2]), pdfNum(bbox[3])),
    XStep: pdfNum(xStep),
    YStep: pdfNum(yStep),
    Length: pdfNum(contentBytes.length),
  };

  if (matrix) {
    dictEntries['Matrix'] = pdfArray(
      pdfNum(matrix[0]), pdfNum(matrix[1]),
      pdfNum(matrix[2]), pdfNum(matrix[3]),
      pdfNum(matrix[4]), pdfNum(matrix[5]),
    );
  }

  const stream = pdfStream(dictEntries, contentBytes);
  const ref = store.allocRef();
  store.set(ref, stream);
  return ref;
}
