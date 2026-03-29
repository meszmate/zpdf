import type { PageSizeName, Orientation } from './page-sizes.js';
import type { Color } from '../color/color.js';
import type { Font } from '../font/metrics.js';
import type { BlendMode } from '../graphics/state.js';
import type { Matrix } from '../utils/math.js';
import type { PdfRef } from '../core/types.js';

export interface DocumentOptions {
  version?: string;
  compress?: boolean;
  title?: string;
  author?: string;
  subject?: string;
  keywords?: string[];
  creator?: string;
  producer?: string;
}

export interface LoadOptions {
  password?: string;
}

export interface SaveOptions {
  version?: string;
  compress?: boolean;
}

export interface PageOptions {
  size?: PageSizeName | [number, number];
  orientation?: Orientation;
  margins?: Margins;
}

export interface Margins {
  top?: number;
  bottom?: number;
  left?: number;
  right?: number;
}

export interface LineOptions {
  x1: number; y1: number;
  x2: number; y2: number;
  color?: Color;
  lineWidth?: number;
  dashPattern?: { array: number[]; phase: number };
  opacity?: number;
}

export interface RectOptions {
  x: number; y: number;
  width: number; height: number;
  color?: Color;
  borderColor?: Color;
  borderWidth?: number;
  borderRadius?: number;
  opacity?: number;
  dashPattern?: { array: number[]; phase: number };
}

export interface CircleOptions {
  cx: number; cy: number;
  radius: number;
  color?: Color;
  borderColor?: Color;
  borderWidth?: number;
  opacity?: number;
}

export interface EllipseOptions {
  cx: number; cy: number;
  rx: number; ry: number;
  color?: Color;
  borderColor?: Color;
  borderWidth?: number;
  opacity?: number;
}

export interface PolygonOptions {
  points: Array<{ x: number; y: number }>;
  color?: Color;
  borderColor?: Color;
  borderWidth?: number;
  closePath?: boolean;
  opacity?: number;
}

export interface PathOptions {
  color?: Color;
  borderColor?: Color;
  borderWidth?: number;
  opacity?: number;
  evenOdd?: boolean;
}

export interface ImageDrawOptions {
  x: number; y: number;
  width?: number;
  height?: number;
  opacity?: number;
}

export interface WatermarkOptions {
  text: string;
  font?: Font;
  fontSize?: number;
  color?: Color;
  opacity?: number;
  rotation?: number;
}

export interface HeaderFooterContext {
  pageNumber: number;
  totalPages: number;
  width: number;
  drawText(text: string, options: { x: number; y: number; font: Font; fontSize: number; color?: Color }): void;
  drawLine(options: LineOptions): void;
}

export interface ImageRef {
  ref: PdfRef;
  width: number;
  height: number;
}

export type { PdfRef };
