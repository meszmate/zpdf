import type { Font } from '../font/metrics.js';
import type { Color } from '../color/color.js';

export type Alignment = 'left' | 'center' | 'right' | 'justify';

export interface TextStyle {
  font: Font;
  fontSize: number;
  color?: Color;
  lineHeight?: number; // multiplier, default 1.2
  letterSpacing?: number; // in points
  wordSpacing?: number; // in points
  alignment?: Alignment;
  underline?: boolean;
  strikethrough?: boolean;
}

export interface TextOptions extends TextStyle {
  x: number;
  y: number;
  maxWidth?: number;
  maxLines?: number;
}

export interface RichTextRun {
  text: string;
  font?: Font;
  fontSize?: number;
  color?: Color;
  bold?: boolean;
  italic?: boolean;
  underline?: boolean;
  strikethrough?: boolean;
  link?: string;
}

export interface RichTextOptions {
  x: number;
  y: number;
  width: number;
  alignment?: Alignment;
  lineHeight?: number;
  maxLines?: number;
}
