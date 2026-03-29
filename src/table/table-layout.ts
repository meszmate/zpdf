import type { Font } from '../font/metrics.js';
import type { CellStyle } from './table-style.js';
import type { Table } from './table.js';
import type { TableCell } from './cell.js';

export interface LayoutCell {
  x: number;
  y: number;
  width: number;
  height: number;
  content: string;
  style: CellStyle;
  colspan: number;
  rowspan: number;
}

export interface LayoutRow {
  cells: LayoutCell[];
  y: number;
  height: number;
}

export interface TableLayout {
  rows: LayoutRow[];
  totalWidth: number;
  totalHeight: number;
  pageBreaks: number[];  // Row indices where page breaks occur
  headerRows: LayoutRow[];
  headerHeight: number;
}

function getPadding(style: CellStyle): { top: number; right: number; bottom: number; left: number } {
  const p = style.padding;
  if (p === undefined) {
    return { top: 4, right: 4, bottom: 4, left: 4 };
  }
  if (typeof p === 'number') {
    return { top: p, right: p, bottom: p, left: p };
  }
  return {
    top: p.top ?? 4,
    right: p.right ?? 4,
    bottom: p.bottom ?? 4,
    left: p.left ?? 4,
  };
}

function measureCellHeight(content: string, cellWidth: number, font: Font, fontSize: number, padding: { top: number; right: number; bottom: number; left: number }): number {
  const availableWidth = cellWidth - padding.left - padding.right;
  if (availableWidth <= 0) return padding.top + padding.bottom + fontSize * 1.2;

  // Simple word-wrap text measurement
  const words = content.split(/\s+/).filter(w => w.length > 0);
  if (words.length === 0) return padding.top + padding.bottom + fontSize * 1.2;

  const spaceWidth = font.measureWidth(' ', fontSize);
  const lineHeight = fontSize * 1.2;
  let lineCount = 1;
  let currentLineWidth = 0;

  for (const word of words) {
    const wordWidth = font.measureWidth(word, fontSize);
    const widthWithWord = currentLineWidth === 0 ? wordWidth : currentLineWidth + spaceWidth + wordWidth;

    if (currentLineWidth > 0 && widthWithWord > availableWidth) {
      lineCount++;
      currentLineWidth = wordWidth;
    } else {
      currentLineWidth = widthWithWord;
    }
  }

  return padding.top + padding.bottom + lineCount * lineHeight;
}

function resolveColumnWidths(
  table: Table,
  availableWidth: number,
  allRows: TableCell[][],
  defaultFont: Font,
  defaultFontSize: number,
): number[] {
  const specifiedWidths = table.getColumnWidths();
  const style = table.getStyle();

  // Determine the number of columns from the widest row
  let numCols = specifiedWidths.length;
  for (const row of allRows) {
    let colSpan = 0;
    for (const cell of row) {
      colSpan += cell.colspan;
    }
    if (colSpan > numCols) numCols = colSpan;
  }
  if (numCols === 0) numCols = 1;

  const resolved: number[] = new Array(numCols).fill(0);
  let fixedTotal = 0;
  let autoCount = 0;
  let percentTotal = 0;

  for (let i = 0; i < numCols; i++) {
    const spec = i < specifiedWidths.length ? specifiedWidths[i] : 'auto';

    if (typeof spec === 'number') {
      resolved[i] = spec;
      fixedTotal += spec;
    } else if (spec === 'auto') {
      autoCount++;
      resolved[i] = -1; // placeholder
    } else if (typeof spec === 'string' && spec.endsWith('%')) {
      const pct = parseFloat(spec) / 100;
      resolved[i] = availableWidth * pct;
      percentTotal += resolved[i];
    } else {
      autoCount++;
      resolved[i] = -1;
    }
  }

  // Distribute remaining width among 'auto' columns
  const remaining = availableWidth - fixedTotal - percentTotal;
  if (autoCount > 0) {
    const autoWidth = Math.max(remaining / autoCount, 20); // minimum 20pt per column
    for (let i = 0; i < numCols; i++) {
      if (resolved[i] === -1) {
        resolved[i] = autoWidth;
      }
    }
  }

  return resolved;
}

export function layoutTable(
  table: Table,
  x: number,
  y: number,
  availableWidth: number,
  availableHeight: number,
  defaultFont: Font,
  defaultFontSize: number,
): TableLayout {
  const style = table.getStyle();
  const tableWidth = style.width ?? availableWidth;
  const headers = table.getHeaders();
  const bodyRows = table.getRows();
  const allRows = [...headers, ...bodyRows];

  const colWidths = resolveColumnWidths(table, tableWidth, allRows, defaultFont, defaultFontSize);
  const numCols = colWidths.length;

  // Function to layout a single set of rows
  function layoutRows(
    rows: TableCell[][],
    isHeader: boolean,
    startY: number,
  ): LayoutRow[] {
    const layoutRowList: LayoutRow[] = [];

    // Track rowspan occupancy: maps (rowOffset, colIndex) to the cell that spans into it
    const rowspanMap: Map<string, { cell: TableCell; startRow: number; startCol: number }> = new Map();

    for (let rowIdx = 0; rowIdx < rows.length; rowIdx++) {
      const row = rows[rowIdx];
      const cellLayouts: LayoutCell[] = [];
      let maxHeight = 0;
      let colIdx = 0;

      for (let cellIdx = 0; cellIdx < row.length; cellIdx++) {
        // Skip columns occupied by rowspan
        while (colIdx < numCols && rowspanMap.has(`${rowIdx}:${colIdx}`)) {
          colIdx++;
        }
        if (colIdx >= numCols) break;

        const cell = row[cellIdx];
        const effectiveStyle = mergeCellStyle(style, cell.style, isHeader, rowIdx);

        // Calculate cell width (spanning multiple columns)
        let cellWidth = 0;
        for (let c = 0; c < cell.colspan && (colIdx + c) < numCols; c++) {
          cellWidth += colWidths[colIdx + c];
        }

        const font = effectiveStyle.font ?? defaultFont;
        const fontSize = effectiveStyle.fontSize ?? defaultFontSize;
        const padding = getPadding(effectiveStyle);

        const cellHeight = measureCellHeight(cell.content, cellWidth, font, fontSize, padding);

        // Calculate x position
        let cellX = x;
        for (let c = 0; c < colIdx; c++) {
          cellX += colWidths[c];
        }

        cellLayouts.push({
          x: cellX,
          y: 0, // set later
          width: cellWidth,
          height: cellHeight,
          content: cell.content,
          style: effectiveStyle,
          colspan: cell.colspan,
          rowspan: cell.rowspan,
        });

        if (cellHeight > maxHeight) maxHeight = cellHeight;

        // Register rowspan for future rows
        if (cell.rowspan > 1) {
          for (let r = 1; r < cell.rowspan; r++) {
            for (let c = 0; c < cell.colspan; c++) {
              rowspanMap.set(`${rowIdx + r}:${colIdx + c}`, {
                cell,
                startRow: rowIdx,
                startCol: colIdx,
              });
            }
          }
        }

        colIdx += cell.colspan;
      }

      // Set y position (PDF y goes down from the top of the table)
      const rowY = startY;
      for (const cl of cellLayouts) {
        cl.y = rowY;
      }

      layoutRowList.push({
        cells: cellLayouts,
        y: rowY,
        height: maxHeight,
      });

      startY -= maxHeight;
    }

    return layoutRowList;
  }

  // Layout header rows
  const headerLayoutRows = layoutRows(headers, true, y);
  let headerHeight = 0;
  for (const hr of headerLayoutRows) {
    headerHeight += hr.height;
  }

  // Layout body rows
  let currentY = y - headerHeight;
  const bodyLayoutRows = layoutRows(bodyRows, false, currentY);

  // Determine page breaks
  const pageBreaks: number[] = [];
  let usedHeight = headerHeight;

  for (let i = 0; i < bodyLayoutRows.length; i++) {
    usedHeight += bodyLayoutRows[i].height;
    if (usedHeight > availableHeight && i > 0) {
      pageBreaks.push(i);
      usedHeight = headerHeight + bodyLayoutRows[i].height;
    }
  }

  // Combine all rows
  const allLayoutRows = [...headerLayoutRows, ...bodyLayoutRows];

  let totalHeight = 0;
  for (const row of allLayoutRows) {
    totalHeight += row.height;
  }

  return {
    rows: allLayoutRows,
    totalWidth: colWidths.reduce((a, b) => a + b, 0),
    totalHeight,
    pageBreaks,
    headerRows: headerLayoutRows,
    headerHeight,
  };
}

function mergeCellStyle(
  tableStyle: import('./table-style.js').TableStyle,
  cellOverride: CellStyle,
  isHeader: boolean,
  rowIndex: number,
): CellStyle {
  // Start with table-level defaults
  const base: CellStyle = isHeader
    ? { ...tableStyle.headerStyle }
    : { ...tableStyle.cellStyle };

  // Apply alternate row coloring for body rows
  if (!isHeader && tableStyle.alternateRowColor && rowIndex % 2 === 1) {
    if (!base.backgroundColor) {
      base.backgroundColor = tableStyle.alternateRowColor;
    }
  }

  // Apply table-level border defaults
  if (base.borderColor === undefined && tableStyle.borderColor) {
    base.borderColor = tableStyle.borderColor;
  }
  if (base.borderWidth === undefined && tableStyle.borderWidth !== undefined) {
    base.borderWidth = tableStyle.borderWidth;
  }

  // Override with cell-specific style
  const result: CellStyle = { ...base };
  if (cellOverride.padding !== undefined) result.padding = cellOverride.padding;
  if (cellOverride.backgroundColor !== undefined) result.backgroundColor = cellOverride.backgroundColor;
  if (cellOverride.borderColor !== undefined) result.borderColor = cellOverride.borderColor;
  if (cellOverride.borderWidth !== undefined) result.borderWidth = cellOverride.borderWidth;
  if (cellOverride.borders !== undefined) result.borders = cellOverride.borders;
  if (cellOverride.font !== undefined) result.font = cellOverride.font;
  if (cellOverride.fontSize !== undefined) result.fontSize = cellOverride.fontSize;
  if (cellOverride.textColor !== undefined) result.textColor = cellOverride.textColor;
  if (cellOverride.alignment !== undefined) result.alignment = cellOverride.alignment;
  if (cellOverride.verticalAlignment !== undefined) result.verticalAlignment = cellOverride.verticalAlignment;

  return result;
}
