import type { PdfRef, PdfObject } from '../core/types.js';
import type { ObjectStore } from '../core/object-store.js';
import type { TextFieldOptions } from './form.js';
import {
  pdfName, pdfNum, pdfStr, pdfDict, pdfArray,
} from '../core/objects.js';
import { FieldFlags } from './field-flags.js';
import { generateTextFieldAppearance } from './field-appearance.js';

export function createTextField(
  store: ObjectStore,
  pageRef: PdfRef,
  options: TextFieldOptions,
): PdfRef {
  const fontSize = options.fontSize ?? 12;

  // Build field flags
  let ff = 0;
  if (options.readOnly) ff |= FieldFlags.ReadOnly;
  if (options.required) ff |= FieldFlags.Required;
  if (options.multiline) ff |= FieldFlags.Multiline;
  if (options.password) ff |= FieldFlags.Password;

  // Build default appearance string
  let daStr = `/Helv ${fontSize} Tf`;
  if (options.fontColor) {
    const fc = options.fontColor;
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

  // Generate appearance stream
  const apStream = generateTextFieldAppearance(options);
  const apRef = store.allocRef();
  store.set(apRef, apStream);

  // Build the widget/field dict
  const entries: Record<string, PdfObject> = {
    Type: pdfName('Annot'),
    Subtype: pdfName('Widget'),
    FT: pdfName('Tx'),
    Rect: pdfArray(
      pdfNum(options.rect[0]),
      pdfNum(options.rect[1]),
      pdfNum(options.rect[2]),
      pdfNum(options.rect[3]),
    ),
    T: pdfStr(options.name),
    DA: pdfStr(daStr),
    Ff: pdfNum(ff),
    P: pageRef,
    AP: pdfDict({ N: apRef }),
  };

  if (options.value !== undefined) {
    entries['V'] = pdfStr(options.value);
  }

  if (options.defaultValue !== undefined) {
    entries['DV'] = pdfStr(options.defaultValue);
  }

  if (options.maxLength !== undefined) {
    entries['MaxLen'] = pdfNum(options.maxLength);
  }

  if (options.alignment !== undefined) {
    entries['Q'] = pdfNum(options.alignment);
  }

  // MK dict for visual appearance properties
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
