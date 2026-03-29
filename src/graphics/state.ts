import type { Color } from '../color/color.js';
import type { Matrix } from '../utils/math.js';
import type { PdfDict } from '../core/types.js';
import { pdfDict, pdfName, pdfNum, pdfBool } from '../core/objects.js';
import { setFillColor, setStrokeColor } from '../color/operators.js';
import * as ops from './operators.js';

export type BlendMode =
  | 'Normal'
  | 'Multiply'
  | 'Screen'
  | 'Overlay'
  | 'Darken'
  | 'Lighten'
  | 'ColorDodge'
  | 'ColorBurn'
  | 'HardLight'
  | 'SoftLight'
  | 'Difference'
  | 'Exclusion'
  | 'Hue'
  | 'Saturation'
  | 'Color'
  | 'Luminosity';

export interface GraphicsState {
  lineWidth?: number;
  lineCap?: 0 | 1 | 2;
  lineJoin?: 0 | 1 | 2;
  miterLimit?: number;
  dashPattern?: { array: number[]; phase: number };
  fillColor?: Color;
  strokeColor?: Color;
  fillOpacity?: number;
  strokeOpacity?: number;
  blendMode?: BlendMode;
  transform?: Matrix;
}

export function createExtGState(state: Partial<GraphicsState>): PdfDict {
  const entries: Record<string, any> = {
    Type: pdfName('ExtGState'),
  };

  if (state.fillOpacity !== undefined) {
    entries['ca'] = pdfNum(state.fillOpacity);
  }
  if (state.strokeOpacity !== undefined) {
    entries['CA'] = pdfNum(state.strokeOpacity);
  }
  if (state.blendMode !== undefined) {
    entries['BM'] = pdfName(state.blendMode);
  }
  if (state.lineWidth !== undefined) {
    entries['LW'] = pdfNum(state.lineWidth);
  }
  if (state.lineCap !== undefined) {
    entries['LC'] = pdfNum(state.lineCap);
  }
  if (state.lineJoin !== undefined) {
    entries['LJ'] = pdfNum(state.lineJoin);
  }
  if (state.miterLimit !== undefined) {
    entries['ML'] = pdfNum(state.miterLimit);
  }

  return pdfDict(entries);
}

export function graphicsStateToOperators(state: GraphicsState): string {
  const lines: string[] = [];

  if (state.transform) {
    lines.push(ops.concatMatrix(state.transform));
  }
  if (state.lineWidth !== undefined) {
    lines.push(ops.setLineWidth(state.lineWidth));
  }
  if (state.lineCap !== undefined) {
    lines.push(ops.setLineCap(state.lineCap));
  }
  if (state.lineJoin !== undefined) {
    lines.push(ops.setLineJoin(state.lineJoin));
  }
  if (state.miterLimit !== undefined) {
    lines.push(ops.setMiterLimit(state.miterLimit));
  }
  if (state.dashPattern) {
    lines.push(ops.setDashPattern(state.dashPattern.array, state.dashPattern.phase));
  }
  if (state.fillColor) {
    lines.push(setFillColor(state.fillColor));
  }
  if (state.strokeColor) {
    lines.push(setStrokeColor(state.strokeColor));
  }

  return lines.join('\n');
}
