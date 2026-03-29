import type { Matrix } from '../utils/math.js';

function formatNum(n: number): string {
  const s = n.toFixed(6);
  if (s.indexOf('.') !== -1) {
    let end = s.length;
    while (end > 0 && s[end - 1] === '0') end--;
    if (s[end - 1] === '.') end--;
    return s.slice(0, end);
  }
  return s;
}

// Escape special characters in a PDF string for use in text operators
function escapeText(text: string): string {
  return text
    .replace(/\\/g, '\\\\')
    .replace(/\(/g, '\\(')
    .replace(/\)/g, '\\)');
}

// --- Graphics state operators ---

export function saveState(): string {
  return 'q';
}

export function restoreState(): string {
  return 'Q';
}

export function concatMatrix(m: Matrix): string {
  return `${formatNum(m[0])} ${formatNum(m[1])} ${formatNum(m[2])} ${formatNum(m[3])} ${formatNum(m[4])} ${formatNum(m[5])} cm`;
}

export function setLineWidth(w: number): string {
  return `${formatNum(w)} w`;
}

export function setLineCap(cap: 0 | 1 | 2): string {
  return `${cap} J`;
}

export function setLineJoin(join: 0 | 1 | 2): string {
  return `${join} j`;
}

export function setMiterLimit(limit: number): string {
  return `${formatNum(limit)} M`;
}

export function setDashPattern(array: number[], phase: number): string {
  const items = array.map(formatNum).join(' ');
  return `[${items}] ${formatNum(phase)} d`;
}

// --- Path construction operators ---

export function moveTo(x: number, y: number): string {
  return `${formatNum(x)} ${formatNum(y)} m`;
}

export function lineTo(x: number, y: number): string {
  return `${formatNum(x)} ${formatNum(y)} l`;
}

export function curveTo(
  x1: number, y1: number,
  x2: number, y2: number,
  x3: number, y3: number,
): string {
  return `${formatNum(x1)} ${formatNum(y1)} ${formatNum(x2)} ${formatNum(y2)} ${formatNum(x3)} ${formatNum(y3)} c`;
}

export function curveToV(
  x2: number, y2: number,
  x3: number, y3: number,
): string {
  return `${formatNum(x2)} ${formatNum(y2)} ${formatNum(x3)} ${formatNum(y3)} v`;
}

export function curveToY(
  x1: number, y1: number,
  x3: number, y3: number,
): string {
  return `${formatNum(x1)} ${formatNum(y1)} ${formatNum(x3)} ${formatNum(y3)} y`;
}

export function rect(x: number, y: number, w: number, h: number): string {
  return `${formatNum(x)} ${formatNum(y)} ${formatNum(w)} ${formatNum(h)} re`;
}

export function closePath(): string {
  return 'h';
}

// --- Path painting operators ---

export function stroke(): string {
  return 'S';
}

export function fill(): string {
  return 'f';
}

export function fillAndStroke(): string {
  return 'B';
}

export function fillEvenOdd(): string {
  return 'f*';
}

export function closeAndStroke(): string {
  return 's';
}

export function closeFillAndStroke(): string {
  return 'b';
}

// --- Clipping operators ---

export function clip(): string {
  return 'W n';
}

export function clipEvenOdd(): string {
  return 'W* n';
}

// --- Text operators ---

export function beginText(): string {
  return 'BT';
}

export function endText(): string {
  return 'ET';
}

export function setFont(name: string, size: number): string {
  return `/${name} ${formatNum(size)} Tf`;
}

export function moveText(tx: number, ty: number): string {
  return `${formatNum(tx)} ${formatNum(ty)} Td`;
}

export function showText(text: string): string {
  return `(${escapeText(text)}) Tj`;
}

export function showTextArray(items: (string | number)[]): string {
  const parts = items.map((item) => {
    if (typeof item === 'string') {
      return `(${escapeText(item)})`;
    }
    return formatNum(item);
  });
  return `[${parts.join(' ')}] TJ`;
}

export function setCharSpacing(spacing: number): string {
  return `${formatNum(spacing)} Tc`;
}

export function setWordSpacing(spacing: number): string {
  return `${formatNum(spacing)} Tw`;
}

export function setTextLeading(leading: number): string {
  return `${formatNum(leading)} TL`;
}

export function setTextRise(rise: number): string {
  return `${formatNum(rise)} Ts`;
}

export function setTextScale(scale: number): string {
  return `${formatNum(scale)} Tz`;
}

// --- XObject / ExtGState operators ---

export function drawXObject(name: string): string {
  return `/${name} Do`;
}

export function setExtGState(name: string): string {
  return `/${name} gs`;
}

// --- Marked content operators ---

export function beginMarkedContent(tag: string): string {
  return `/${tag} BMC`;
}

export function beginMarkedContentWithProperties(tag: string, name: string): string {
  return `/${tag} /${name} BDC`;
}

export function endMarkedContent(): string {
  return 'EMC';
}
