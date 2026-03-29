import type { PdfRef, PdfObject, PdfDict, PdfStream } from '../core/types.js';
import type { ObjectStore } from '../core/object-store.js';
import {
  pdfName, pdfNum, pdfStr, pdfDict, pdfArray, pdfBool, pdfStream,
  dictGetName, dictGet, dictGetString, dictGetNumber, isDict, isStream,
} from '../core/objects.js';

/* ------------------------------------------------------------------ */
/*  fillFormField                                                     */
/* ------------------------------------------------------------------ */

/**
 * Fill a form field by reference. Updates the /V value and regenerates
 * the appearance stream.
 *
 * @param store   The object store
 * @param fieldRef  Reference to the field dictionary
 * @param value   String value for text/choice fields, boolean for checkboxes
 */
export function fillFormField(
  store: ObjectStore,
  fieldRef: PdfRef,
  value: string | boolean,
): void {
  const fieldObj = store.get(fieldRef);
  if (!fieldObj || (fieldObj.type !== 'dict' && fieldObj.type !== 'stream')) {
    throw new Error(`Field not found or not a dictionary at ref ${fieldRef.objectNumber}`);
  }

  const entries = fieldObj.type === 'dict' ? fieldObj.entries : fieldObj.dict;
  const fieldType = dictGetName(fieldObj as PdfDict, 'FT');

  if (!fieldType) {
    throw new Error(`Field at ref ${fieldRef.objectNumber} has no /FT entry`);
  }

  // Clone entries for modification
  const newEntries = new Map(entries);

  switch (fieldType) {
    case 'Tx': {
      // Text field
      if (typeof value !== 'string') {
        throw new Error('Text field requires a string value');
      }
      newEntries.set('V', pdfStr(value));

      // Regenerate appearance
      const rect = getRect(newEntries);
      if (rect) {
        const apStream = generateSimpleTextAppearance(value, rect, newEntries);
        const apRef = store.allocRef();
        store.set(apRef, apStream);
        newEntries.set('AP', pdfDict({ N: apRef }));
      }
      break;
    }
    case 'Btn': {
      // Check if it's a checkbox or radio
      const ffVal = newEntries.get('Ff');
      const ff = ffVal && ffVal.type === 'number' ? ffVal.value : 0;
      const isRadio = (ff & (1 << 15)) !== 0;
      const isPushbutton = (ff & (1 << 16)) !== 0;

      if (isPushbutton) {
        // Pushbuttons don't have values to fill
        return;
      }

      if (typeof value === 'boolean') {
        // Checkbox
        const nameVal = value ? 'Yes' : 'Off';
        newEntries.set('V', pdfName(nameVal));
        newEntries.set('AS', pdfName(nameVal));
      } else {
        // Radio: set value to the option name
        newEntries.set('V', pdfName(value));
        // Update AS on children if this is a parent
        updateRadioChildren(store, newEntries, value);
      }
      break;
    }
    case 'Ch': {
      // Choice field (dropdown or listbox)
      if (typeof value !== 'string') {
        throw new Error('Choice field requires a string value');
      }
      newEntries.set('V', pdfStr(value));

      // Regenerate appearance
      const rect = getRect(newEntries);
      if (rect) {
        const apStream = generateSimpleTextAppearance(value, rect, newEntries);
        const apRef = store.allocRef();
        store.set(apRef, apStream);
        newEntries.set('AP', pdfDict({ N: apRef }));
      }
      break;
    }
    case 'Sig': {
      // Signature fields cannot be filled with simple values
      throw new Error('Signature fields cannot be filled with fillFormField');
    }
    default:
      throw new Error(`Unknown field type: ${fieldType}`);
  }

  // Write back updated dictionary
  store.set(fieldRef, pdfDict(Object.fromEntries(newEntries)));
}

/* ------------------------------------------------------------------ */
/*  Helpers                                                           */
/* ------------------------------------------------------------------ */

function getRect(entries: Map<string, PdfObject>): [number, number, number, number] | null {
  const rectObj = entries.get('Rect');
  if (!rectObj || rectObj.type !== 'array' || rectObj.items.length < 4) return null;

  const nums = rectObj.items.map(item =>
    item.type === 'number' ? item.value : 0
  );
  return [nums[0], nums[1], nums[2], nums[3]];
}

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

function generateSimpleTextAppearance(
  value: string,
  rect: [number, number, number, number],
  entries: Map<string, PdfObject>,
): PdfStream {
  const w = Math.abs(rect[2] - rect[0]);
  const h = Math.abs(rect[3] - rect[1]);
  const bbox: [number, number, number, number] = [0, 0, w, h];

  // Try to extract font size from DA string
  let fontSize = 12;
  const daObj = entries.get('DA');
  if (daObj && daObj.type === 'string') {
    let daStr = '';
    for (let i = 0; i < daObj.value.length; i++) {
      daStr += String.fromCharCode(daObj.value[i]);
    }
    const match = daStr.match(/(\d+(?:\.\d+)?)\s+Tf/);
    if (match) {
      fontSize = parseFloat(match[1]);
    }
  }

  const ops: string[] = [];
  ops.push('q');

  // White background
  ops.push('1 1 1 rg');
  ops.push(`0 0 ${f(w)} ${f(h)} re`);
  ops.push('f');

  // Border
  ops.push('0 0 0 RG');
  ops.push('1 w');
  ops.push(`0.5 0.5 ${f(w - 1)} ${f(h - 1)} re`);
  ops.push('S');

  // Text
  ops.push('BT');
  ops.push('0 0 0 rg');
  ops.push(`/Helv ${f(fontSize)} Tf`);

  const textY = (h - fontSize) / 2;
  ops.push(`2 ${f(textY)} Td`);
  ops.push(`(${escapeStr(value)}) Tj`);
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

function updateRadioChildren(
  store: ObjectStore,
  parentEntries: Map<string, PdfObject>,
  selectedValue: string,
): void {
  const kidsObj = parentEntries.get('Kids');
  if (!kidsObj || kidsObj.type !== 'array') return;

  for (const kidItem of kidsObj.items) {
    if (kidItem.type !== 'ref') continue;

    const kidObj = store.get(kidItem);
    if (!kidObj || kidObj.type !== 'dict') continue;

    const kidEntries = new Map(kidObj.entries);

    // Check if this kid's appearance dict has the selected value
    const apObj = kidEntries.get('AP');
    if (apObj && apObj.type === 'dict') {
      const nObj = apObj.entries.get('N');
      if (nObj && nObj.type === 'dict') {
        const hasValue = nObj.entries.has(selectedValue);
        kidEntries.set('AS', pdfName(hasValue ? selectedValue : 'Off'));
        store.set(kidItem, pdfDict(Object.fromEntries(kidEntries)));
      }
    }
  }
}
