import type { TableStyle } from './table-style.js';
import { TableCell } from './cell.js';

export class Table {
  private rows: TableCell[][] = [];
  private columnWidths: (number | 'auto' | string)[] = [];
  private style: TableStyle;
  private headers: TableCell[][] = [];

  constructor(options?: TableStyle) {
    this.style = options ?? {};
  }

  setColumnWidths(widths: (number | 'auto' | string)[]): this {
    this.columnWidths = widths;
    return this;
  }

  addHeaderRow(cells: (string | TableCell)[]): this {
    const row = cells.map(cell =>
      typeof cell === 'string' ? new TableCell(cell) : cell,
    );
    this.headers.push(row);
    return this;
  }

  addRow(cells: (string | TableCell)[]): this {
    const row = cells.map(cell =>
      typeof cell === 'string' ? new TableCell(cell) : cell,
    );
    this.rows.push(row);
    return this;
  }

  getRows(): TableCell[][] {
    return this.rows;
  }

  getHeaders(): TableCell[][] {
    return this.headers;
  }

  getColumnWidths(): (number | 'auto' | string)[] {
    return this.columnWidths;
  }

  getStyle(): TableStyle {
    return this.style;
  }
}
