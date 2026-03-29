import type { CellStyle } from './table-style.js';

export class TableCell {
  content: string;
  colspan: number;
  rowspan: number;
  style: CellStyle;

  constructor(content: string, options?: { colspan?: number; rowspan?: number; style?: CellStyle }) {
    this.content = content;
    this.colspan = options?.colspan ?? 1;
    this.rowspan = options?.rowspan ?? 1;
    this.style = options?.style ?? {};
  }
}
