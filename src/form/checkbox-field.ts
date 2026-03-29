import type { PdfRef, PdfObject } from '../core/types.js';
import type { ObjectStore } from '../core/object-store.js';
import type { CheckboxOptions } from './form.js';
import {
  pdfName, pdfNum, pdfStr, pdfDict, pdfArray,
} from '../core/objects.js';
import { FieldFlags } from './field-flags.js';
import { generateCheckboxAppearance } from './field-appearance.js';

export function createCheckbox(
  store: ObjectStore,
  pageRef: PdfRef,
  options: CheckboxOptions,
): PdfRef {
  // Build field flags
  let ff = 0;
  if (options.readOnly) ff |= FieldFlags.ReadOnly;
  if (options.required) ff |= FieldFlags.Required;

  // Generate appearance streams
  const { on, off } = generateCheckboxAppearance(
    options.checked ?? false,
    options.rect,
    { bg: options.backgroundColor, border: options.borderColor },
  );

  const onRef = store.allocRef();
  store.set(onRef, on);
  const offRef = store.allocRef();
  store.set(offRef, off);

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
    V: pdfName(options.checked ? 'Yes' : 'Off'),
    AS: pdfName(options.checked ? 'Yes' : 'Off'),
    Ff: pdfNum(ff),
    P: pageRef,
    AP: pdfDict({
      N: pdfDict({
        Yes: onRef,
        Off: offRef,
      }),
    }),
  };

  // MK dict
  const mkEntries: Record<string, PdfObject> = {};
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
