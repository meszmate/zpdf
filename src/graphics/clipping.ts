import { PathBuilder } from './path-builder.js';
import * as ops from './operators.js';

export function clipRect(x: number, y: number, w: number, h: number): string {
  const lines: string[] = [];
  lines.push(ops.rect(x, y, w, h));
  lines.push(ops.clip());
  return lines.join('\n');
}

export function clipPath(path: PathBuilder, evenOdd: boolean = false): string {
  const lines: string[] = [];
  lines.push(path.toOperators());
  lines.push(evenOdd ? ops.clipEvenOdd() : ops.clip());
  return lines.join('\n');
}
