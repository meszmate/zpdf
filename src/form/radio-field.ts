import type { PdfRef, PdfObject } from '../core/types.js';
import type { ObjectStore } from '../core/object-store.js';
import type { RadioGroupOptions } from './form.js';
import {
  pdfName, pdfNum, pdfStr, pdfDict, pdfArray,
} from '../core/objects.js';
import { FieldFlags } from './field-flags.js';
import { generateRadioAppearance } from './field-appearance.js';

export function createRadioGroup(
  store: ObjectStore,
  pageRef: PdfRef,
  options: RadioGroupOptions,
): { groupRef: PdfRef; widgetRefs: PdfRef[] } {
  // Build field flags for radio group
  let ff = FieldFlags.Radio | FieldFlags.NoToggleToOff;
  if (options.readOnly) ff |= FieldFlags.ReadOnly;
  if (options.required) ff |= FieldFlags.Required;

  // Determine selected value
  let selectedValue: string | null = null;
  for (const opt of options.options) {
    if (opt.selected) {
      selectedValue = opt.value;
      break;
    }
  }

  // Allocate group ref first so children can reference it
  const groupRef = store.allocRef();

  // Create child widget annotations
  const widgetRefs: PdfRef[] = [];

  for (const opt of options.options) {
    const isSelected = opt.value === selectedValue;

    // Generate appearance streams
    const { on, off } = generateRadioAppearance(isSelected, opt.rect);

    const onRef = store.allocRef();
    store.set(onRef, on);
    const offRef = store.allocRef();
    store.set(offRef, off);

    const widgetEntries: Record<string, PdfObject> = {
      Type: pdfName('Annot'),
      Subtype: pdfName('Widget'),
      Rect: pdfArray(
        pdfNum(opt.rect[0]),
        pdfNum(opt.rect[1]),
        pdfNum(opt.rect[2]),
        pdfNum(opt.rect[3]),
      ),
      Parent: groupRef,
      AS: pdfName(isSelected ? opt.value : 'Off'),
      P: pageRef,
      AP: pdfDict({
        N: pdfDict({
          [opt.value]: onRef,
          Off: offRef,
        }),
      }),
    };

    const widgetRef = store.allocRef();
    store.set(widgetRef, pdfDict(widgetEntries));
    widgetRefs.push(widgetRef);
  }

  // Create the parent radio group field
  const groupEntries: Record<string, PdfObject> = {
    FT: pdfName('Btn'),
    Ff: pdfNum(ff),
    T: pdfStr(options.name),
    Kids: pdfArray(...widgetRefs),
  };

  if (selectedValue !== null) {
    groupEntries['V'] = pdfName(selectedValue);
  } else {
    groupEntries['V'] = pdfName('Off');
  }

  store.set(groupRef, pdfDict(groupEntries));

  return { groupRef, widgetRefs };
}
