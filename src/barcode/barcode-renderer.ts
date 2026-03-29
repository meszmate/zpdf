import type { Color } from '../color/color.js';
import { setFillColor } from '../color/operators.js';

export interface Bar {
  x: number;
  width: number;
  height: number;
}

/**
 * Render bars as PDF rectangle fill operators.
 * Each bar is drawn as a filled rectangle at the given position.
 */
export function renderBars(
  bars: Bar[],
  x: number,
  y: number,
  height: number,
  color?: Color,
): string {
  const ops: string[] = [];
  ops.push('q'); // save graphics state

  if (color) {
    ops.push(setFillColor(color));
  } else {
    ops.push('0 0 0 rg'); // default black
  }

  for (const bar of bars) {
    const bx = fmt(x + bar.x);
    const by = fmt(y);
    const bw = fmt(bar.width);
    const bh = fmt(bar.height > 0 ? bar.height : height);
    ops.push(`${bx} ${by} ${bw} ${bh} re f`);
  }

  ops.push('Q'); // restore graphics state
  return ops.join('\n') + '\n';
}

function fmt(n: number): string {
  if (Number.isInteger(n)) return n.toString();
  const s = n.toFixed(4);
  // Strip trailing zeros
  let end = s.length;
  while (end > 0 && s[end - 1] === '0') end--;
  if (s[end - 1] === '.') end--;
  return s.slice(0, end);
}
