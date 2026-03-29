import type { Font } from '../font/metrics.js';
import type { Color } from '../color/color.js';
import type { TextOptions, RichTextRun, RichTextOptions } from './text-style.js';
import { layoutText, layoutRichText } from './text-layout.js';
import type { LayoutLine, RichLayoutLine, RichLayoutRun } from './text-layout.js';

/**
 * Map of font -> resource name (e.g., /F1, /F2).
 * Shared across a single rendering context / page.
 */
const fontNameMap = new Map<string, string>();
let fontCounter = 0;

/**
 * Reset font name tracking. Should be called when starting a new page.
 */
export function resetFontNames(): void {
  fontNameMap.clear();
  fontCounter = 0;
}

/**
 * Get the PDF resource name for a font (e.g., "F1").
 * Allocates a new name if this font hasn't been seen yet.
 */
export function fontResourceName(font: Font): string {
  const key = font.name + (font.ref ? `:${font.ref.objectNumber}` : '');
  let name = fontNameMap.get(key);
  if (!name) {
    fontCounter++;
    name = `F${fontCounter}`;
    fontNameMap.set(key, name);
  }
  return name;
}

/**
 * Get the current raw font name mapping (fontKey -> resourceName).
 * Useful for building page resource dictionaries in combination with
 * external font tracking.
 */
export function getFontNameMapping(): Map<string, string> {
  return new Map(fontNameMap);
}

/**
 * Format a number for PDF output, removing trailing zeros.
 */
function fmt(n: number): string {
  if (Number.isInteger(n)) return n.toString();
  // Use at most 4 decimal places
  const s = n.toFixed(4);
  // Remove trailing zeros
  return s.replace(/\.?0+$/, '');
}

/**
 * Escape a string for use in a PDF literal string (parentheses).
 */
function escapeString(text: string): string {
  let result = '';
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    switch (ch) {
      case '(':
        result += '\\(';
        break;
      case ')':
        result += '\\)';
        break;
      case '\\':
        result += '\\\\';
        break;
      default:
        result += ch;
    }
  }
  return result;
}

/**
 * Generate PDF color-setting operators for the given color.
 * Returns operators for both fill (text) color.
 */
function colorOperators(color: Color): string {
  switch (color.type) {
    case 'rgb':
      return `${fmt(color.r)} ${fmt(color.g)} ${fmt(color.b)} rg`;
    case 'cmyk':
      return `${fmt(color.c)} ${fmt(color.m)} ${fmt(color.y)} ${fmt(color.k)} k`;
    case 'grayscale':
      return `${fmt(color.gray)} g`;
  }
}

/**
 * Generate PDF stroke color-setting operators.
 */
function strokeColorOperators(color: Color): string {
  switch (color.type) {
    case 'rgb':
      return `${fmt(color.r)} ${fmt(color.g)} ${fmt(color.b)} RG`;
    case 'cmyk':
      return `${fmt(color.c)} ${fmt(color.m)} ${fmt(color.y)} ${fmt(color.k)} K`;
    case 'grayscale':
      return `${fmt(color.gray)} G`;
  }
}

/**
 * Generate decoration lines (underline or strikethrough) for a text span.
 */
function renderDecoration(
  x: number,
  y: number,
  width: number,
  fontSize: number,
  font: Font,
  color: Color | undefined,
  underline: boolean | undefined,
  strikethrough: boolean | undefined,
): string {
  const ops: string[] = [];
  const lineWidth = fontSize * 0.05; // decoration line thickness
  const ascent = (font.metrics.ascent / font.metrics.unitsPerEm) * fontSize;
  const descent = (font.metrics.descent / font.metrics.unitsPerEm) * fontSize;

  if (underline) {
    // Draw underline slightly below baseline
    const underlineY = y + descent * 0.5;
    ops.push('q'); // save graphics state
    ops.push(`${fmt(lineWidth)} w`); // line width
    if (color) {
      ops.push(strokeColorOperators(color));
    }
    ops.push(`${fmt(x)} ${fmt(underlineY)} m`);
    ops.push(`${fmt(x + width)} ${fmt(underlineY)} l`);
    ops.push('S'); // stroke
    ops.push('Q'); // restore
  }

  if (strikethrough) {
    // Draw line through the middle of the text (roughly at x-height / 2)
    const strikeY = y + ascent * 0.3;
    ops.push('q');
    ops.push(`${fmt(lineWidth)} w`);
    if (color) {
      ops.push(strokeColorOperators(color));
    }
    ops.push(`${fmt(x)} ${fmt(strikeY)} m`);
    ops.push(`${fmt(x + width)} ${fmt(strikeY)} l`);
    ops.push('S');
    ops.push('Q');
  }

  return ops.join('\n');
}

/**
 * Render plain text to PDF content stream operators.
 */
export function renderText(text: string, options: TextOptions): string {
  const {
    x,
    y,
    font,
    fontSize,
    color,
    alignment = 'left',
    maxWidth,
    maxLines,
    letterSpacing = 0,
    wordSpacing = 0,
    underline,
    strikethrough,
  } = options;

  const layout = layoutText(text, options, maxWidth, maxLines);
  const ops: string[] = [];
  const resourceName = fontResourceName(font);
  const decorationOps: string[] = [];

  // Begin text block
  ops.push('BT');

  // Set font
  ops.push(`/${resourceName} ${fmt(fontSize)} Tf`);

  // Set color
  if (color) {
    ops.push(colorOperators(color));
  }

  // Set letter spacing if specified
  if (letterSpacing !== 0) {
    ops.push(`${fmt(letterSpacing)} Tc`);
  }

  // Render each line
  for (let i = 0; i < layout.lines.length; i++) {
    const line = layout.lines[i];
    const lineX = x + line.x;
    const lineY = y + line.y;

    // For justify alignment, set word spacing (Tw operator)
    if (alignment === 'justify' && maxWidth !== undefined && line.words.length > 1 && i < layout.lines.length - 1) {
      // Don't justify the last line
      const totalWordWidth = line.words.reduce((sum, w) => sum + w.width, 0);
      const totalSpaces = line.words.length - 1;
      const extraSpace = (maxWidth - totalWordWidth) / totalSpaces;
      ops.push(`${fmt(extraSpace)} Tw`);
    } else if (alignment === 'justify') {
      // Reset word spacing for last line or single-word lines
      if (wordSpacing !== 0) {
        ops.push(`${fmt(wordSpacing)} Tw`);
      } else {
        ops.push('0 Tw');
      }
    } else if (wordSpacing !== 0) {
      ops.push(`${fmt(wordSpacing)} Tw`);
    }

    // Position
    if (i === 0) {
      ops.push(`${fmt(lineX)} ${fmt(lineY)} Td`);
    } else {
      // Move relative to previous position
      const prevLine = layout.lines[i - 1];
      const dx = lineX - (x + prevLine.x);
      const dy = line.y - prevLine.y;
      ops.push(`${fmt(dx)} ${fmt(dy)} Td`);
    }

    // Show text
    ops.push(`(${escapeString(line.text)}) Tj`);

    // Collect decoration operations (rendered outside BT/ET)
    if (underline || strikethrough) {
      const decoOp = renderDecoration(
        lineX, lineY, line.width, fontSize, font, color, underline, strikethrough,
      );
      if (decoOp) decorationOps.push(decoOp);
    }
  }

  // End text block
  ops.push('ET');

  // Add decorations after text block
  if (decorationOps.length > 0) {
    ops.push(...decorationOps);
  }

  return ops.join('\n');
}

/**
 * Render rich text (mixed fonts/sizes/colors) to PDF content stream operators.
 */
export function renderRichText(
  runs: RichTextRun[],
  options: RichTextOptions,
  defaultFont: Font,
  defaultFontSize: number,
): string {
  const layout = layoutRichText(runs, options, defaultFont, defaultFontSize);
  const { x, y, width, alignment = 'left' } = options;
  const ops: string[] = [];
  const decorationOps: string[] = [];

  let currentFontName = '';
  let currentFontSize = 0;

  for (const line of layout.lines) {
    if (line.runs.length === 0) continue;

    const lineBaseX = x + line.x;
    const lineBaseY = y + line.y;

    // For justify alignment, calculate extra word spacing
    let justifyExtraPerGap = 0;
    if (alignment === 'justify' && line.runs.length > 1 && line !== layout.lines[layout.lines.length - 1]) {
      const gaps = line.runs.length - 1;
      justifyExtraPerGap = (width - line.width) / gaps;
    }

    ops.push('BT');

    let cursorX = lineBaseX;
    for (let ri = 0; ri < line.runs.length; ri++) {
      const run = line.runs[ri];
      const runFont = run.font;
      const runFontSize = run.fontSize;
      const resName = fontResourceName(runFont);

      // Set font if changed
      if (resName !== currentFontName || runFontSize !== currentFontSize) {
        ops.push(`/${resName} ${fmt(runFontSize)} Tf`);
        currentFontName = resName;
        currentFontSize = runFontSize;
      }

      // Set color if specified
      if (run.color) {
        ops.push(colorOperators(run.color));
      }

      // Calculate x position for this run, accounting for justify
      let runX = lineBaseX + run.x;
      if (justifyExtraPerGap > 0 && ri > 0) {
        runX += justifyExtraPerGap * ri;
      }

      // Position text
      ops.push(`${fmt(runX)} ${fmt(lineBaseY)} Td`);
      ops.push(`(${escapeString(run.text)}) Tj`);

      // Collect decoration ops
      const actualRunWidth = run.width;
      if (run.underline || run.strikethrough) {
        const decoOp = renderDecoration(
          runX, lineBaseY, actualRunWidth, runFontSize, runFont,
          run.color, run.underline, run.strikethrough,
        );
        if (decoOp) decorationOps.push(decoOp);
      }

      cursorX = runX + actualRunWidth;
    }

    ops.push('ET');
  }

  // Add decorations
  if (decorationOps.length > 0) {
    ops.push(...decorationOps);
  }

  return ops.join('\n');
}
