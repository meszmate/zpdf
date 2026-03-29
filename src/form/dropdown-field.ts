import type { PdfRef, PdfObject } from '../core/types.js';
import type { ObjectStore } from '../core/object-store.js';
import type { DropdownOptions } from './form.js';
import {
  pdfName, pdfNum, pdfStr, pdfDict, pdfArray,
} from '../core/objects.js';
import { FieldFlags } from './field-flags.js';
import { generateDropdownAppearance } from './field-appearance.js';

export function createDropdown(
  store: ObjectStore,
  pageRef: PdfRef,
  options: DropdownOptions,
): PdfRef {
  const fontSize = options.fontSize ?? 12;

  // Build field flags: Choice + Combo
  let ff = FieldFlags.Combo;
  if (options.readOnly) ff |= FieldFlags.ReadOnly;
  if (options.required) ff |= FieldFlags.Required;
  if (options.editable) ff |= FieldFlags.Edit;

  // Default appearance string
  let daStr = `/Helv ${fontSize} Tf 0 0 0 rg`;

  // Generate appearance stream
  const apStream = generateDropdownAppearance(options);
  const apRef = store.allocRef();
  store.set(apRef, apStream);

  // Build the widget/field dict
  const entries: Record<string, PdfObject> = {
    Type: pdfName('Annot'),
    Subtype: pdfName('Widget'),
    FT: pdfName('Ch'),
    Rect: pdfArray(
      pdfNum(options.rect[0]),
      pdfNum(options.rect[1]),
      pdfNum(options.rect[2]),
      pdfNum(options.rect[3]),
    ),
    T: pdfStr(options.name),
    Ff: pdfNum(ff),
    DA: pdfStr(daStr),
    Opt: pdfArray(...options.options.map(o => pdfStr(o))),
    P: pageRef,
    AP: pdfDict({ N: apRef }),
  };

  if (options.value !== undefined) {
    entries['V'] = pdfStr(options.value);
  }

  // MK dict for visual appearance
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
