import type { PdfRef } from '../core/types.js';

export interface FontMetrics {
  ascent: number;
  descent: number;
  lineGap: number;
  unitsPerEm: number;
  bbox: [number, number, number, number];
  italicAngle: number;
  capHeight: number;
  xHeight: number;
  stemV: number;
  flags: number;
  defaultWidth: number;
  widths: Map<number, number>;
  kerning?: Map<string, number>;
}

export interface Font {
  name: string;
  ref: PdfRef | null;
  metrics: FontMetrics;
  isStandard: boolean;
  encode(text: string): Uint8Array;
  measureWidth(text: string, fontSize: number): number;
  getLineHeight(fontSize: number): number;
}
