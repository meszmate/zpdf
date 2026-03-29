import type { Color } from '../color/color.js';
import { setFillColor, setStrokeColor } from '../color/operators.js';
import { PathBuilder } from './path-builder.js';
import * as ops from './operators.js';

export interface StrokeOptions {
  color?: Color;
  lineWidth?: number;
  lineCap?: 0 | 1 | 2;
  lineJoin?: 0 | 1 | 2;
  dashPattern?: { array: number[]; phase: number };
  opacity?: number;
}

export interface FillOptions {
  color?: Color;
  opacity?: number;
  evenOdd?: boolean;
}

export function strokePath(path: PathBuilder, options: StrokeOptions = {}): string {
  const lines: string[] = [];
  lines.push(ops.saveState());

  if (options.lineWidth !== undefined) {
    lines.push(ops.setLineWidth(options.lineWidth));
  }
  if (options.lineCap !== undefined) {
    lines.push(ops.setLineCap(options.lineCap));
  }
  if (options.lineJoin !== undefined) {
    lines.push(ops.setLineJoin(options.lineJoin));
  }
  if (options.dashPattern) {
    lines.push(ops.setDashPattern(options.dashPattern.array, options.dashPattern.phase));
  }
  if (options.color) {
    lines.push(setStrokeColor(options.color));
  }

  lines.push(path.toOperators());
  lines.push(ops.stroke());
  lines.push(ops.restoreState());

  return lines.join('\n');
}

export function fillPath(path: PathBuilder, options: FillOptions = {}): string {
  const lines: string[] = [];
  lines.push(ops.saveState());

  if (options.color) {
    lines.push(setFillColor(options.color));
  }

  lines.push(path.toOperators());
  lines.push(options.evenOdd ? ops.fillEvenOdd() : ops.fill());
  lines.push(ops.restoreState());

  return lines.join('\n');
}

export function fillAndStrokePath(
  path: PathBuilder,
  strokeOpts: StrokeOptions = {},
  fillOpts: FillOptions = {},
): string {
  const lines: string[] = [];
  lines.push(ops.saveState());

  if (strokeOpts.lineWidth !== undefined) {
    lines.push(ops.setLineWidth(strokeOpts.lineWidth));
  }
  if (strokeOpts.lineCap !== undefined) {
    lines.push(ops.setLineCap(strokeOpts.lineCap));
  }
  if (strokeOpts.lineJoin !== undefined) {
    lines.push(ops.setLineJoin(strokeOpts.lineJoin));
  }
  if (strokeOpts.dashPattern) {
    lines.push(ops.setDashPattern(strokeOpts.dashPattern.array, strokeOpts.dashPattern.phase));
  }
  if (strokeOpts.color) {
    lines.push(setStrokeColor(strokeOpts.color));
  }
  if (fillOpts.color) {
    lines.push(setFillColor(fillOpts.color));
  }

  lines.push(path.toOperators());

  if (fillOpts.evenOdd) {
    // B* = fill (even-odd) and stroke
    lines.push('B*');
  } else {
    lines.push(ops.fillAndStroke());
  }

  lines.push(ops.restoreState());

  return lines.join('\n');
}
