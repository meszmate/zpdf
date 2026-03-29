import type { PdfStream, PdfObject } from '../core/types.js';
import type { Color } from '../color/color.js';
import type {
  TextFieldOptions,
  DropdownOptions,
  ButtonOptions,
} from './form.js';
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
  if (color.type === 'rgb') {
    return `${f(color.r)} ${f(color.g)} ${f(color.b)} ${stroke ? 'RG' : 'rg'}`;
  }
  if (color.type === 'cmyk') {
    return `${f(color.c)} ${f(color.m)} ${f(color.y)} ${f(color.k)} ${stroke ? 'K' : 'k'}`;
  }
  return `${f(color.gray)} ${stroke ? 'G' : 'g'}`;
}

function escapeStr(text: string): string {
  return text
    .replace(/\\/g, '\\\\')
    .replace(/\(/g, '\\(')
    .replace(/\)/g, '\\)');
}

function makeStream(content: string, bbox: [number, number, number, number]): PdfStream {
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
/*  Text field appearance                                             */
/* ------------------------------------------------------------------ */

export function generateTextFieldAppearance(options: TextFieldOptions): PdfStream {
  const [x1, y1, x2, y2] = options.rect;
  const w = Math.abs(x2 - x1);
  const h = Math.abs(y2 - y1);
  const bbox: [number, number, number, number] = [0, 0, w, h];
  const fontSize = options.fontSize ?? 12;

  const ops: string[] = [];
  ops.push('q');

  // Background
  if (options.backgroundColor) {
    ops.push(colorOps(options.backgroundColor, false));
  } else {
    ops.push('1 1 1 rg');
  }
  ops.push(`0 0 ${f(w)} ${f(h)} re`);
  ops.push('f');

  // Border
  if (options.borderColor) {
    ops.push(colorOps(options.borderColor, true));
  } else {
    ops.push('0 0 0 RG');
  }
  ops.push('1 w');
  ops.push(`0.5 0.5 ${f(w - 1)} ${f(h - 1)} re`);
  ops.push('S');

  // Text value
  if (options.value) {
    ops.push('BT');

    if (options.fontColor) {
      ops.push(colorOps(options.fontColor, false));
    } else {
      ops.push('0 0 0 rg');
    }

    ops.push(`/Helv ${f(fontSize)} Tf`);

    // Clip to field rect with padding
    const padding = 2;

    if (options.multiline) {
      // Multi-line: render line by line
      const lines = options.value.split('\n');
      let curY = h - fontSize - padding;
      for (let i = 0; i < lines.length; i++) {
        if (curY < 0) break;
        ops.push(`${f(padding)} ${f(curY)} Td`);
        ops.push(`(${escapeStr(lines[i])}) Tj`);
        if (i === 0) {
          // After first Td, subsequent Td are relative
        }
        curY -= fontSize * 1.2;
      }
    } else {
      // Single line: vertically center
      const textY = (h - fontSize) / 2;
      let textX = padding;
      if (options.alignment === 1) {
        textX = w / 2;
      } else if (options.alignment === 2) {
        textX = w - padding;
      }
      ops.push(`${f(textX)} ${f(textY)} Td`);

      const displayText = options.password
        ? '*'.repeat(options.value.length)
        : options.value;
      ops.push(`(${escapeStr(displayText)}) Tj`);
    }

    ops.push('ET');
  }

  ops.push('Q');

  return makeStream(ops.join('\n'), bbox);
}

/* ------------------------------------------------------------------ */
/*  Checkbox appearance                                               */
/* ------------------------------------------------------------------ */

export function generateCheckboxAppearance(
  checked: boolean,
  rect: [number, number, number, number],
  colors?: { bg?: Color; border?: Color },
): { on: PdfStream; off: PdfStream } {
  const w = Math.abs(rect[2] - rect[0]);
  const h = Math.abs(rect[3] - rect[1]);
  const bbox: [number, number, number, number] = [0, 0, w, h];

  // --- Off state ---
  const offOps: string[] = [];
  offOps.push('q');

  // Background
  if (colors?.bg) {
    offOps.push(colorOps(colors.bg, false));
  } else {
    offOps.push('1 1 1 rg');
  }
  offOps.push(`0 0 ${f(w)} ${f(h)} re`);
  offOps.push('f');

  // Border
  if (colors?.border) {
    offOps.push(colorOps(colors.border, true));
  } else {
    offOps.push('0 0 0 RG');
  }
  offOps.push('1 w');
  offOps.push(`0.5 0.5 ${f(w - 1)} ${f(h - 1)} re`);
  offOps.push('S');
  offOps.push('Q');
  const off = makeStream(offOps.join('\n'), bbox);

  // --- On state ---
  const onOps: string[] = [];
  onOps.push('q');

  // Background
  if (colors?.bg) {
    onOps.push(colorOps(colors.bg, false));
  } else {
    onOps.push('1 1 1 rg');
  }
  onOps.push(`0 0 ${f(w)} ${f(h)} re`);
  onOps.push('f');

  // Border
  if (colors?.border) {
    onOps.push(colorOps(colors.border, true));
  } else {
    onOps.push('0 0 0 RG');
  }
  onOps.push('1 w');
  onOps.push(`0.5 0.5 ${f(w - 1)} ${f(h - 1)} re`);
  onOps.push('S');

  // Checkmark
  onOps.push('0 0 0 RG');
  onOps.push('2 w');
  onOps.push('1 J'); // round line cap
  const mx = w * 0.15;
  const my = h * 0.4;
  const cx = w * 0.4;
  const cy = h * 0.15;
  const ex = w * 0.85;
  const ey = h * 0.85;
  onOps.push(`${f(mx)} ${f(my)} m`);
  onOps.push(`${f(cx)} ${f(cy)} l`);
  onOps.push(`${f(ex)} ${f(ey)} l`);
  onOps.push('S');

  onOps.push('Q');
  const on = makeStream(onOps.join('\n'), bbox);

  return { on, off };
}

/* ------------------------------------------------------------------ */
/*  Radio button appearance                                           */
/* ------------------------------------------------------------------ */

export function generateRadioAppearance(
  selected: boolean,
  rect: [number, number, number, number],
): { on: PdfStream; off: PdfStream } {
  const w = Math.abs(rect[2] - rect[0]);
  const h = Math.abs(rect[3] - rect[1]);
  const bbox: [number, number, number, number] = [0, 0, w, h];
  const cx = w / 2;
  const cy = h / 2;
  const r = Math.min(cx, cy) - 1;

  // Helper to draw a circle using 4 Bezier arcs
  function circlePath(radius: number): string {
    const k = 0.5523 * radius;
    const lines: string[] = [];
    lines.push(`${f(cx + radius)} ${f(cy)} m`);
    lines.push(`${f(cx + radius)} ${f(cy + k)} ${f(cx + k)} ${f(cy + radius)} ${f(cx)} ${f(cy + radius)} c`);
    lines.push(`${f(cx - k)} ${f(cy + radius)} ${f(cx - radius)} ${f(cy + k)} ${f(cx - radius)} ${f(cy)} c`);
    lines.push(`${f(cx - radius)} ${f(cy - k)} ${f(cx - k)} ${f(cy - radius)} ${f(cx)} ${f(cy - radius)} c`);
    lines.push(`${f(cx + k)} ${f(cy - radius)} ${f(cx + radius)} ${f(cy - k)} ${f(cx + radius)} ${f(cy)} c`);
    return lines.join('\n');
  }

  // --- Off state (empty circle) ---
  const offOps: string[] = [];
  offOps.push('q');
  offOps.push('1 1 1 rg');
  offOps.push('0 0 0 RG');
  offOps.push('1 w');
  offOps.push(circlePath(r));
  offOps.push('B');
  offOps.push('Q');
  const off = makeStream(offOps.join('\n'), bbox);

  // --- On state (filled circle) ---
  const onOps: string[] = [];
  onOps.push('q');
  onOps.push('1 1 1 rg');
  onOps.push('0 0 0 RG');
  onOps.push('1 w');
  onOps.push(circlePath(r));
  onOps.push('B');

  // Inner filled circle
  onOps.push('0 0 0 rg');
  const innerR = r * 0.5;
  onOps.push(circlePath(innerR));
  onOps.push('f');

  onOps.push('Q');
  const on = makeStream(onOps.join('\n'), bbox);

  return { on, off };
}

/* ------------------------------------------------------------------ */
/*  Dropdown appearance                                               */
/* ------------------------------------------------------------------ */

export function generateDropdownAppearance(options: DropdownOptions): PdfStream {
  const [x1, y1, x2, y2] = options.rect;
  const w = Math.abs(x2 - x1);
  const h = Math.abs(y2 - y1);
  const bbox: [number, number, number, number] = [0, 0, w, h];
  const fontSize = options.fontSize ?? 12;

  const ops: string[] = [];
  ops.push('q');

  // Background
  if (options.backgroundColor) {
    ops.push(colorOps(options.backgroundColor, false));
  } else {
    ops.push('1 1 1 rg');
  }
  ops.push(`0 0 ${f(w)} ${f(h)} re`);
  ops.push('f');

  // Border
  if (options.borderColor) {
    ops.push(colorOps(options.borderColor, true));
  } else {
    ops.push('0 0 0 RG');
  }
  ops.push('1 w');
  ops.push(`0.5 0.5 ${f(w - 1)} ${f(h - 1)} re`);
  ops.push('S');

  // Down arrow indicator
  const arrowSize = Math.min(h * 0.6, 10);
  const arrowX = w - arrowSize - 4;
  const arrowY = (h - arrowSize * 0.5) / 2;
  ops.push('0.5 0.5 0.5 rg');
  ops.push(`${f(arrowX)} ${f(arrowY + arrowSize * 0.5)} m`);
  ops.push(`${f(arrowX + arrowSize)} ${f(arrowY + arrowSize * 0.5)} l`);
  ops.push(`${f(arrowX + arrowSize / 2)} ${f(arrowY)} l`);
  ops.push('f');

  // Selected value text
  if (options.value) {
    ops.push('BT');
    ops.push('0 0 0 rg');
    ops.push(`/Helv ${f(fontSize)} Tf`);
    const textY = (h - fontSize) / 2;
    ops.push(`2 ${f(textY)} Td`);
    ops.push(`(${escapeStr(options.value)}) Tj`);
    ops.push('ET');
  }

  ops.push('Q');

  return makeStream(ops.join('\n'), bbox);
}

/* ------------------------------------------------------------------ */
/*  Button appearance                                                 */
/* ------------------------------------------------------------------ */

export function generateButtonAppearance(options: ButtonOptions): PdfStream {
  const [x1, y1, x2, y2] = options.rect;
  const w = Math.abs(x2 - x1);
  const h = Math.abs(y2 - y1);
  const bbox: [number, number, number, number] = [0, 0, w, h];
  const fontSize = options.fontSize ?? 12;

  const ops: string[] = [];
  ops.push('q');

  // Background
  if (options.backgroundColor) {
    ops.push(colorOps(options.backgroundColor, false));
  } else {
    ops.push('0.9 0.9 0.9 rg');
  }
  ops.push(`0 0 ${f(w)} ${f(h)} re`);
  ops.push('f');

  // Border
  if (options.borderColor) {
    ops.push(colorOps(options.borderColor, true));
  } else {
    ops.push('0 0 0 RG');
  }
  ops.push('1 w');
  ops.push(`0.5 0.5 ${f(w - 1)} ${f(h - 1)} re`);
  ops.push('S');

  // 3D effect: top/left lighter, bottom/right darker
  ops.push('1 1 1 RG');
  ops.push('1 w');
  ops.push(`1 1 m ${f(w - 1)} 1 l S`);
  ops.push(`1 1 m 1 ${f(h - 1)} l S`);
  ops.push('0.5 0.5 0.5 RG');
  ops.push(`${f(w - 1)} 1 m ${f(w - 1)} ${f(h - 1)} l S`);
  ops.push(`1 ${f(h - 1)} m ${f(w - 1)} ${f(h - 1)} l S`);

  // Label
  if (options.label) {
    ops.push('BT');
    ops.push('0 0 0 rg');
    ops.push(`/Helv ${f(fontSize)} Tf`);

    // Center text
    const textWidth = options.label.length * fontSize * 0.6;
    const textX = (w - textWidth) / 2;
    const textY = (h - fontSize) / 2;
    ops.push(`${f(textX)} ${f(textY)} Td`);
    ops.push(`(${escapeStr(options.label)}) Tj`);
    ops.push('ET');
  }

  ops.push('Q');

  return makeStream(ops.join('\n'), bbox);
}
