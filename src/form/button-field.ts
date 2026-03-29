import type { PdfRef, PdfObject } from '../core/types.js';
import type { ObjectStore } from '../core/object-store.js';
import type { ButtonOptions } from './form.js';
import {
  pdfName, pdfNum, pdfStr, pdfDict, pdfArray,
} from '../core/objects.js';
import { FieldFlags } from './field-flags.js';
import { generateButtonAppearance } from './field-appearance.js';

export function createButton(
  store: ObjectStore,
  pageRef: PdfRef,
  options: ButtonOptions,
): PdfRef {
  // Pushbutton flag
  const ff = FieldFlags.Pushbutton;

  // Generate appearance stream
  const apStream = generateButtonAppearance(options);
  const apRef = store.allocRef();
  store.set(apRef, apStream);

  // Build the widget/field dict
  const entries: Record<string, PdfObject> = {
    Type: pdfName('Annot'),
    Subtype: pdfName('Widget'),
    FT: pdfName('Btn'),
    Rect: pdfArray(
      pdfNum(options.rect[0]),
      pdfNum(options.rect[1]),
      pdfNum(options.rect[2]),
      pdfNum(options.rect[3]),
    ),
    T: pdfStr(options.name),
    Ff: pdfNum(ff),
    P: pageRef,
    AP: pdfDict({ N: apRef }),
  };

  // MK dict with caption
  const mkEntries: Record<string, PdfObject> = {};
  if (options.label) {
    mkEntries['CA'] = pdfStr(options.label);
  }
  if (options.backgroundColor) {
    const bg = options.backgroundColor;
    if (bg.type === 'rgb') {
      mkEntries['BG'] = pdfArray(pdfNum(bg.r), pdfNum(bg.g), pdfNum(bg.b));
    } else if (bg.type === 'grayscale') {
      mkEntries['BG'] = pdfArray(pdfNum(bg.gray));
    } else {
      mkEntries['BG'] = pdfArray(pdfNum(bg.c), pdfNum(bg.m), pdfNum(bg.y), pdfNum(bg.k));
    }
  }
  if (options.borderColor) {
    const bc = options.borderColor;
    if (bc.type === 'rgb') {
      mkEntries['BC'] = pdfArray(pdfNum(bc.r), pdfNum(bc.g), pdfNum(bc.b));
    } else if (bc.type === 'grayscale') {
      mkEntries['BC'] = pdfArray(pdfNum(bc.gray));
    } else {
      mkEntries['BC'] = pdfArray(pdfNum(bc.c), pdfNum(bc.m), pdfNum(bc.y), pdfNum(bc.k));
    }
  }
  if (Object.keys(mkEntries).length > 0) {
    entries['MK'] = pdfDict(mkEntries);
  }

  const ref = store.allocRef();
  store.set(ref, pdfDict(entries));
  return ref;
}
