import type { Font } from '../font/metrics.js';
import type { CellStyle } from './table-style.js';
import type { ResourceManager } from '../document/resource-manager.js';
import type { LayoutRow, LayoutCell, TableLayout } from './table-layout.js';
import { setFillColor, setStrokeColor } from '../color/operators.js';
import { grayscale } from '../color/color.js';
import * as ops from '../graphics/operators.js';

function formatNum(n: number): string {
  const s = n.toFixed(6);
  if (s.indexOf('.') !== -1) {
    let end = s.length;
    while (end > 0 && s[end - 1] === '0') end--;
    if (s[end - 1] === '.') end--;
    return s.slice(0, end);
  }
  return s;
}

function escapeText(text: string): string {
  return text
    .replace(/\\/g, '\\\\')
    .replace(/\(/g, '\\(')
    .replace(/\)/g, '\\)');
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

/**
 * Render a set of layout rows to PDF operator strings.
 */
export function renderTableRows(
  rows: LayoutRow[],
  resourceManager: ResourceManager,
  defaultFont: Font,
  defaultFontSize: number,
): string {
  const lines: string[] = [];

  for (const row of rows) {
    for (const cell of row.cells) {
      lines.push(...renderCell(cell, row.height, resourceManager, defaultFont, defaultFontSize));
    }
  }

  return lines.join('\n');
}

/**
 * Render a complete table layout, returning operator strings.
 */
export function renderTable(
  layout: TableLayout,
  resourceManager: ResourceManager,
  defaultFont: Font,
  defaultFontSize: number,
): string {
  return renderTableRows(layout.rows, resourceManager, defaultFont, defaultFontSize);
}

function renderCell(
  cell: LayoutCell,
  rowHeight: number,
  resourceManager: ResourceManager,
  defaultFont: Font,
  defaultFontSize: number,
): string[] {
  const lines: string[] = [];
  const style = cell.style;
  const padding = getPadding(style);

  // Use the row height (which is the max height across all cells in the row)
  // for consistent row rendering
  const effectiveHeight = Math.max(cell.height, rowHeight);

  // Draw background
  if (style.backgroundColor) {
    lines.push(ops.saveState());
    lines.push(setFillColor(style.backgroundColor));
    // PDF y-axis: cell.y is the top of the cell, we draw downward
    lines.push(ops.rect(cell.x, cell.y - effectiveHeight, cell.width, effectiveHeight));
    lines.push(ops.fill());
    lines.push(ops.restoreState());
  }

  // Draw borders
  const borders = style.borders ?? { top: true, right: true, bottom: true, left: true };
  const borderWidth = style.borderWidth ?? 0.5;
  const borderColor = style.borderColor ?? grayscale(0);

  if (borders.top !== false || borders.right !== false || borders.bottom !== false || borders.left !== false) {
    lines.push(ops.saveState());
    lines.push(ops.setLineWidth(borderWidth));
    lines.push(setStrokeColor(borderColor));

    const left = cell.x;
    const right = cell.x + cell.width;
    const top = cell.y;
    const bottom = cell.y - effectiveHeight;

    if (borders.top !== false) {
      lines.push(ops.moveTo(left, top));
      lines.push(ops.lineTo(right, top));
      lines.push(ops.stroke());
    }
    if (borders.bottom !== false) {
      lines.push(ops.moveTo(left, bottom));
      lines.push(ops.lineTo(right, bottom));
      lines.push(ops.stroke());
    }
    if (borders.left !== false) {
      lines.push(ops.moveTo(left, top));
      lines.push(ops.lineTo(left, bottom));
      lines.push(ops.stroke());
    }
    if (borders.right !== false) {
      lines.push(ops.moveTo(right, top));
      lines.push(ops.lineTo(right, bottom));
      lines.push(ops.stroke());
    }

    lines.push(ops.restoreState());
  }

  // Draw text content
  if (cell.content.length > 0) {
    const font = style.font ?? defaultFont;
    const fontSize = style.fontSize ?? defaultFontSize;
    const textColor = style.textColor ?? grayscale(0);
    const alignment = style.alignment ?? 'left';
    const verticalAlignment = style.verticalAlignment ?? 'top';

    const fontName = resourceManager.registerFont(font);
    const availableWidth = cell.width - padding.left - padding.right;
    const lineHeight = fontSize * 1.2;

    // Word-wrap text
    const textLines = wrapText(cell.content, font, fontSize, availableWidth);

    // Calculate total text height
    const totalTextHeight = textLines.length * lineHeight;

    // Vertical alignment
    const contentAreaHeight = effectiveHeight - padding.top - padding.bottom;
    let textStartY: number;
    switch (verticalAlignment) {
      case 'middle':
        textStartY = cell.y - padding.top - (contentAreaHeight - totalTextHeight) / 2 - fontSize * 0.2;
        break;
      case 'bottom':
        textStartY = cell.y - effectiveHeight + padding.bottom + totalTextHeight - lineHeight + fontSize * 0.2;
        break;
      case 'top':
      default:
        textStartY = cell.y - padding.top - fontSize * 0.2;
        break;
    }

    lines.push(ops.saveState());

    // Clip to cell boundaries to prevent text overflow
    lines.push(ops.rect(cell.x + padding.left, cell.y - effectiveHeight + padding.bottom, availableWidth, contentAreaHeight));
    lines.push('W n');

    lines.push(setFillColor(textColor));
    lines.push(ops.beginText());
    lines.push(ops.setFont(fontName, fontSize));

    for (let i = 0; i < textLines.length; i++) {
      const textLine = textLines[i];
      const lineWidth = font.measureWidth(textLine, fontSize);

      // Horizontal alignment
      let textX: number;
      switch (alignment) {
        case 'center':
          textX = cell.x + padding.left + (availableWidth - lineWidth) / 2;
          break;
        case 'right':
          textX = cell.x + padding.left + availableWidth - lineWidth;
          break;
        case 'left':
        default:
          textX = cell.x + padding.left;
          break;
      }

      const textY = textStartY - i * lineHeight;
      lines.push(ops.moveText(textX, textY));
      lines.push(`(${escapeText(textLine)}) Tj`);
    }

    lines.push(ops.endText());
    lines.push(ops.restoreState());
  }

  return lines;
}

/**
 * Word-wrap text to fit within a given width.
 */
function wrapText(text: string, font: Font, fontSize: number, maxWidth: number): string[] {
  if (maxWidth <= 0) return [text];

  const paragraphs = text.split('\n');
  const result: string[] = [];

  for (const paragraph of paragraphs) {
    const words = paragraph.split(/\s+/).filter(w => w.length > 0);
    if (words.length === 0) {
      result.push('');
      continue;
    }

    const spaceWidth = font.measureWidth(' ', fontSize);
    let currentLine = '';
    let currentWidth = 0;

    for (const word of words) {
      const wordWidth = font.measureWidth(word, fontSize);

      if (currentLine === '') {
        currentLine = word;
        currentWidth = wordWidth;
      } else if (currentWidth + spaceWidth + wordWidth <= maxWidth) {
        currentLine += ' ' + word;
        currentWidth += spaceWidth + wordWidth;
      } else {
        result.push(currentLine);
        currentLine = word;
        currentWidth = wordWidth;
      }
    }

    if (currentLine !== '') {
      result.push(currentLine);
    }
  }

  if (result.length === 0) {
    result.push('');
  }

  return result;
}
