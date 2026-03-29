import type { PdfRef } from '../core/types.js';
import type { Color } from '../color/color.js';

export interface OutlineItemOptions {
  title: string;
  destination: { page: PdfRef; x?: number; y?: number; zoom?: number };
  bold?: boolean;
  italic?: boolean;
  color?: Color;
  children?: OutlineItemOptions[];
}
