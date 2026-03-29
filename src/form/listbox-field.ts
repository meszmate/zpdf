import type { PdfRef, PdfObject } from '../core/types.js';
import type { ObjectStore } from '../core/object-store.js';
import type { ListboxOptions } from './form.js';
import {
  pdfName, pdfNum, pdfStr, pdfDict, pdfArray,
} from '../core/objects.js';
import { FieldFlags } from './field-flags.js';
import { pdfStream } from '../core/objects.js';

export function createListbox(
  store: ObjectStore,
  pageRef: PdfRef,
  options: ListboxOptions,
): PdfRef {
  const fontSize = options.fontSize ?? 12;

  // Build field flags: Choice (no Combo flag = listbox)
  let ff = 0;
  if (options.readOnly) ff |= FieldFlags.ReadOnly;
  if (options.required) ff |= FieldFlags.Required;
  if (options.multiSelect) ff |= FieldFlags.MultiSelect;

  // Default appearance string
  const daStr = `/Helv ${fontSize} Tf 0 0 0 rg`;

  // Generate appearance stream
  const apStream = generateListboxAppearance(options);
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

  // Set selected values
  if (options.selected && options.selected.length > 0) {
    if (options.selected.length === 1) {
      entries['V'] = pdfStr(options.selected[0]);
    } else {
      entries['V'] = pdfArray(...options.selected.map(s => pdfStr(s)));
    }
  }

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

/* ------------------------------------------------------------------ */
/*  Listbox appearance generation                                     */
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

function generateListboxAppearance(options: ListboxOptions): PdfObject {
  const [x1, y1, x2, y2] = options.rect;
  const w = Math.abs(x2 - x1);
  const h = Math.abs(y2 - y1);
  const bbox: [number, number, number, number] = [0, 0, w, h];
  const fontSize = options.fontSize ?? 12;
  const lineHeight = fontSize * 1.2;

  const ops: string[] = [];
  ops.push('q');

  // Background
  if (options.backgroundColor) {
    const bg = options.backgroundColor;
    if (bg.type === 'rgb') {
      ops.push(`${f(bg.r)} ${f(bg.g)} ${f(bg.b)} rg`);
    } else if (bg.type === 'grayscale') {
      ops.push(`${f(bg.gray)} g`);
    } else {
      ops.push(`${f(bg.c)} ${f(bg.m)} ${f(bg.y)} ${f(bg.k)} k`);
    }
  } else {
    ops.push('1 1 1 rg');
  }
  ops.push(`0 0 ${f(w)} ${f(h)} re`);
  ops.push('f');

  // Border
  if (options.borderColor) {
    const bc = options.borderColor;
    if (bc.type === 'rgb') {
      ops.push(`${f(bc.r)} ${f(bc.g)} ${f(bc.b)} RG`);
    } else if (bc.type === 'grayscale') {
      ops.push(`${f(bc.gray)} G`);
    } else {
      ops.push(`${f(bc.c)} ${f(bc.m)} ${f(bc.y)} ${f(bc.k)} K`);
    }
  } else {
    ops.push('0 0 0 RG');
  }
  ops.push('1 w');
  ops.push(`0.5 0.5 ${f(w - 1)} ${f(h - 1)} re`);
  ops.push('S');

  // Render options list
  const selectedSet = new Set(options.selected ?? []);
  let curY = h - lineHeight;

  for (let i = 0; i < options.options.length; i++) {
    if (curY < -lineHeight) break;

    const optText = options.options[i];

    // Highlight selected
    if (selectedSet.has(optText)) {
      ops.push('0 0 0.5 rg'); // Blue highlight
      ops.push(`0 ${f(curY)} ${f(w)} ${f(lineHeight)} re`);
      ops.push('f');
      ops.push('1 1 1 rg'); // White text for selected
    } else {
      ops.push('0 0 0 rg');
    }

    ops.push('BT');
    ops.push(`/Helv ${f(fontSize)} Tf`);
    ops.push(`2 ${f(curY + (lineHeight - fontSize) / 2)} Td`);
    ops.push(`(${escapeStr(optText)}) Tj`);
    ops.push('ET');

    curY -= lineHeight;
  }

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
