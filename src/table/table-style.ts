import type { Color } from '../color/color.js';
import type { Font } from '../font/metrics.js';
import type { Alignment } from '../text/text-style.js';

export interface CellStyle {
  padding?: number | { top?: number; right?: number; bottom?: number; left?: number };
  backgroundColor?: Color;
  borderColor?: Color;
  borderWidth?: number;
  borders?: { top?: boolean; right?: boolean; bottom?: boolean; left?: boolean };
  font?: Font;
  fontSize?: number;
  textColor?: Color;
  alignment?: Alignment;
  verticalAlignment?: 'top' | 'middle' | 'bottom';
}

export interface TableStyle {
  borderColor?: Color;
  borderWidth?: number;
  headerStyle?: CellStyle;
  cellStyle?: CellStyle;
  alternateRowColor?: Color;
  width?: number;
}
