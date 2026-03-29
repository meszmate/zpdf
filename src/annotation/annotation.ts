import type { PdfRef, PdfObject, PdfStream } from '../core/types.js';
import type { ObjectStore } from '../core/object-store.js';
import type { Color } from '../color/color.js';
import {
  pdfName, pdfNum, pdfStr, pdfDict, pdfArray, pdfStream, pdfBool,
} from '../core/objects.js';
import { generateTextAnnotationAppearance, generateFreeTextAppearance, generateStampAppearance } from './annotation-appearance.js';

/* ------------------------------------------------------------------ */
/*  Types                                                             */
/* ------------------------------------------------------------------ */

export interface AnnotationBase {
  rect: [number, number, number, number]; // [x1, y1, x2, y2]
  flags?: number;
  color?: Color;
  opacity?: number;
  border?: { width: number; style?: 'solid' | 'dashed' | 'beveled' | 'inset' | 'underline' };
}

export interface TextAnnotation extends AnnotationBase {
  type: 'text';
  content: string;
  icon?: 'Comment' | 'Key' | 'Note' | 'Help' | 'NewParagraph' | 'Paragraph' | 'Insert';
  open?: boolean;
}

export interface LinkAnnotation extends AnnotationBase {
  type: 'link';
  uri?: string;
  destination?: { page: number; x?: number; y?: number; zoom?: number };
  highlightMode?: 'none' | 'invert' | 'outline' | 'push';
}

export interface HighlightAnnotation extends AnnotationBase {
  type: 'highlight';
  quadPoints: number[];
}

export interface UnderlineAnnotation extends AnnotationBase {
  type: 'underline';
  quadPoints: number[];
}

export interface StrikeoutAnnotation extends AnnotationBase {
  type: 'strikeout';
  quadPoints: number[];
}

export interface StampAnnotation extends AnnotationBase {
  type: 'stamp';
  stampName?: 'Approved' | 'Experimental' | 'NotApproved' | 'AsIs' | 'Expired' | 'NotForPublicRelease' | 'Confidential' | 'Final' | 'Sold' | 'Departmental' | 'ForComment' | 'TopSecret' | 'Draft' | 'ForPublicRelease';
}

export interface FreeTextAnnotation extends AnnotationBase {
  type: 'freetext';
  content: string;
  fontSize?: number;
  fontColor?: Color;
  alignment?: 0 | 1 | 2;
}

export interface InkAnnotation extends AnnotationBase {
  type: 'ink';
  inkLists: number[][];
}

export type Annotation =
  | TextAnnotation
  | LinkAnnotation
  | HighlightAnnotation
  | UnderlineAnnotation
  | StrikeoutAnnotation
  | StampAnnotation
  | FreeTextAnnotation
  | InkAnnotation;

/* ------------------------------------------------------------------ */
/*  Helpers                                                           */
/* ------------------------------------------------------------------ */

function colorToArray(c: Color): PdfObject[] {
  switch (c.type) {
    case 'rgb':
      return [pdfNum(c.r), pdfNum(c.g), pdfNum(c.b)];
    case 'cmyk':
      return [pdfNum(c.c), pdfNum(c.m), pdfNum(c.y), pdfNum(c.k)];
    case 'grayscale':
      return [pdfNum(c.gray)];
  }
}

const borderStyleMap: Record<string, string> = {
  solid: 'S',
  dashed: 'D',
  beveled: 'B',
  inset: 'I',
  underline: 'U',
};

const highlightModeMap: Record<string, string> = {
  none: 'N',
  invert: 'I',
  outline: 'O',
  push: 'P',
};

function subtypeForAnnotation(annotation: Annotation): string {
  switch (annotation.type) {
    case 'text': return 'Text';
    case 'link': return 'Link';
    case 'highlight': return 'Highlight';
    case 'underline': return 'Underline';
    case 'strikeout': return 'StrikeOut';
    case 'stamp': return 'Stamp';
    case 'freetext': return 'FreeText';
    case 'ink': return 'Ink';
  }
}

/* ------------------------------------------------------------------ */
/*  createAnnotationDict                                              */
/* ------------------------------------------------------------------ */

export function createAnnotationDict(
  store: ObjectStore,
  annotation: Annotation,
  pageRef: PdfRef,
): PdfRef {
  const entries: Record<string, PdfObject> = {};

  // Common entries
  entries['Type'] = pdfName('Annot');
  entries['Subtype'] = pdfName(subtypeForAnnotation(annotation));
  entries['Rect'] = pdfArray(
    pdfNum(annotation.rect[0]),
    pdfNum(annotation.rect[1]),
    pdfNum(annotation.rect[2]),
    pdfNum(annotation.rect[3]),
  );
  entries['P'] = pageRef;

  if (annotation.flags !== undefined) {
    entries['F'] = pdfNum(annotation.flags);
  }

  if (annotation.color) {
    entries['C'] = pdfArray(...colorToArray(annotation.color));
  }

  if (annotation.opacity !== undefined) {
    entries['CA'] = pdfNum(annotation.opacity);
  }

  if (annotation.border) {
    const bsEntries: Record<string, PdfObject> = {
      Type: pdfName('Border'),
      W: pdfNum(annotation.border.width),
    };
    if (annotation.border.style) {
      bsEntries['S'] = pdfName(borderStyleMap[annotation.border.style] ?? 'S');
    }
    entries['BS'] = pdfDict(bsEntries);
  }

  // Type-specific entries
  switch (annotation.type) {
    case 'text': {
      entries['Contents'] = pdfStr(annotation.content);
      if (annotation.icon) {
        entries['Name'] = pdfName(annotation.icon);
      }
      if (annotation.open !== undefined) {
        entries['Open'] = pdfBool(annotation.open);
      }
      // Appearance stream
      const apStream = generateTextAnnotationAppearance(annotation);
      const apRef = store.allocRef();
      store.set(apRef, apStream);
      entries['AP'] = pdfDict({ N: apRef });
      break;
    }
    case 'link': {
      if (annotation.uri) {
        entries['A'] = pdfDict({
          S: pdfName('URI'),
          URI: pdfStr(annotation.uri),
        });
      } else if (annotation.destination) {
        const dest = annotation.destination;
        const destItems: PdfObject[] = [pdfNum(dest.page)];
        if (dest.x !== undefined && dest.y !== undefined) {
          destItems.push(pdfName('XYZ'));
          destItems.push(pdfNum(dest.x));
          destItems.push(pdfNum(dest.y));
          destItems.push(pdfNum(dest.zoom ?? 0));
        } else {
          destItems.push(pdfName('Fit'));
        }
        entries['Dest'] = pdfArray(...destItems);
      }
      if (annotation.highlightMode) {
        entries['H'] = pdfName(highlightModeMap[annotation.highlightMode] ?? 'I');
      }
      break;
    }
    case 'highlight':
    case 'underline':
    case 'strikeout': {
      entries['QuadPoints'] = pdfArray(...annotation.quadPoints.map(n => pdfNum(n)));
      break;
    }
    case 'stamp': {
      if (annotation.stampName) {
        entries['Name'] = pdfName(annotation.stampName);
      }
      const stampAp = generateStampAppearance(annotation);
      const stampApRef = store.allocRef();
      store.set(stampApRef, stampAp);
      entries['AP'] = pdfDict({ N: stampApRef });
      break;
    }
    case 'freetext': {
      entries['Contents'] = pdfStr(annotation.content);

      // Build /DA string
      const fontSize = annotation.fontSize ?? 12;
      let daStr = `/Helv ${fontSize} Tf`;
      if (annotation.fontColor) {
        const fc = annotation.fontColor;
        if (fc.type === 'rgb') {
          daStr += ` ${fc.r.toFixed(3)} ${fc.g.toFixed(3)} ${fc.b.toFixed(3)} rg`;
        } else if (fc.type === 'grayscale') {
          daStr += ` ${fc.gray.toFixed(3)} g`;
        } else {
          daStr += ` ${fc.c.toFixed(3)} ${fc.m.toFixed(3)} ${fc.y.toFixed(3)} ${fc.k.toFixed(3)} k`;
        }
      } else {
        daStr += ' 0 0 0 rg';
      }
      entries['DA'] = pdfStr(daStr);

      if (annotation.alignment !== undefined) {
        entries['Q'] = pdfNum(annotation.alignment);
      }

      const ftAp = generateFreeTextAppearance(annotation);
      const ftApRef = store.allocRef();
      store.set(ftApRef, ftAp);
      entries['AP'] = pdfDict({ N: ftApRef });
      break;
    }
    case 'ink': {
      const inkListArray = annotation.inkLists.map(list =>
        pdfArray(...list.map(n => pdfNum(n)))
      );
      entries['InkList'] = pdfArray(...inkListArray);
      break;
    }
  }

  const ref = store.allocRef();
  store.set(ref, pdfDict(entries));
  return ref;
}
