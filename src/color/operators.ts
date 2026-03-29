import type { Color } from './color.js';

function formatNum(n: number): string {
  // Use up to 6 decimal places, strip trailing zeros
  const s = n.toFixed(6);
  // Remove trailing zeros after decimal point
  if (s.indexOf('.') !== -1) {
    let end = s.length;
    while (end > 0 && s[end - 1] === '0') end--;
    if (s[end - 1] === '.') end--;
    return s.slice(0, end);
  }
  return s;
}

export function setFillColor(color: Color): string {
  switch (color.type) {
    case 'rgb':
      return `${formatNum(color.r)} ${formatNum(color.g)} ${formatNum(color.b)} rg`;
    case 'cmyk':
      return `${formatNum(color.c)} ${formatNum(color.m)} ${formatNum(color.y)} ${formatNum(color.k)} k`;
    case 'grayscale':
      return `${formatNum(color.gray)} g`;
  }
}

export function setStrokeColor(color: Color): string {
  switch (color.type) {
    case 'rgb':
      return `${formatNum(color.r)} ${formatNum(color.g)} ${formatNum(color.b)} RG`;
    case 'cmyk':
      return `${formatNum(color.c)} ${formatNum(color.m)} ${formatNum(color.y)} ${formatNum(color.k)} K`;
    case 'grayscale':
      return `${formatNum(color.gray)} G`;
  }
}
