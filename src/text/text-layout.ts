import type { Font } from '../font/metrics.js';
import type { TextStyle, Alignment, RichTextRun, RichTextOptions } from './text-style.js';

export interface LayoutWord {
  text: string;
  width: number;
}

export interface LayoutLine {
  text: string;
  width: number;
  x: number;
  y: number;
  words: LayoutWord[];
}

export interface LayoutResult {
  lines: LayoutLine[];
  totalHeight: number;
  totalWidth: number;
}

export interface RichLayoutRun {
  text: string;
  width: number;
  font: Font;
  fontSize: number;
  color?: import('../color/color.js').Color;
  underline?: boolean;
  strikethrough?: boolean;
  link?: string;
  x: number; // x offset within the line
}

export interface RichLayoutLine {
  runs: RichLayoutRun[];
  width: number;
  x: number;
  y: number;
  height: number; // max line height across runs
}

export interface RichLayoutResult {
  lines: RichLayoutLine[];
  totalHeight: number;
  totalWidth: number;
}

/**
 * Split text into words, preserving explicit newlines as separate tokens.
 * A newline token is represented as '\n'.
 */
function splitIntoWords(text: string): string[] {
  const result: string[] = [];
  const segments = text.split('\n');
  for (let i = 0; i < segments.length; i++) {
    if (i > 0) {
      result.push('\n');
    }
    const words = segments[i].split(/\s+/).filter(w => w.length > 0);
    for (const word of words) {
      result.push(word);
    }
  }
  return result;
}

/**
 * Measure a single word width including optional letter spacing.
 */
function measureWord(font: Font, fontSize: number, word: string, letterSpacing: number): number {
  const baseWidth = font.measureWidth(word, fontSize);
  // Letter spacing applies between characters, so (chars - 1) extra spaces
  if (letterSpacing !== 0 && word.length > 1) {
    return baseWidth + letterSpacing * (word.length - 1);
  }
  return baseWidth;
}

/**
 * Measure a space character width.
 */
function measureSpace(font: Font, fontSize: number, wordSpacing: number): number {
  return font.measureWidth(' ', fontSize) + wordSpacing;
}

/**
 * Layout text into lines respecting maxWidth and maxLines constraints.
 */
export function layoutText(
  text: string,
  style: TextStyle,
  maxWidth?: number,
  maxLines?: number,
): LayoutResult {
  const { font, fontSize, alignment = 'left', lineHeight: lineHeightMultiplier = 1.2 } = style;
  const letterSpacing = style.letterSpacing ?? 0;
  const wordSpacing = style.wordSpacing ?? 0;

  const lineHeight = fontSize * lineHeightMultiplier;
  const words = splitIntoWords(text);
  const spaceWidth = measureSpace(font, fontSize, wordSpacing);

  const lines: LayoutLine[] = [];
  let currentWords: LayoutWord[] = [];
  let currentWidth = 0;

  function finishLine(): void {
    if (maxLines !== undefined && lines.length >= maxLines) {
      return;
    }

    const lineText = currentWords.map(w => w.text).join(' ');
    const lineWidth = currentWidth;
    currentWords = [];
    currentWidth = 0;

    lines.push({
      text: lineText,
      width: lineWidth,
      x: 0, // will be adjusted for alignment
      y: 0, // will be set below
      words: [],
    });
  }

  for (const word of words) {
    if (word === '\n') {
      // Explicit newline: finish current line
      finishLine();
      if (maxLines !== undefined && lines.length >= maxLines) break;
      continue;
    }

    const wordWidth = measureWord(font, fontSize, word, letterSpacing);
    const widthWithWord = currentWords.length === 0
      ? wordWidth
      : currentWidth + spaceWidth + wordWidth;

    if (maxWidth !== undefined && currentWords.length > 0 && widthWithWord > maxWidth) {
      // Word exceeds max width, wrap to next line
      finishLine();
      if (maxLines !== undefined && lines.length >= maxLines) break;
    }

    if (currentWords.length === 0) {
      currentWidth = wordWidth;
    } else {
      currentWidth += spaceWidth + wordWidth;
    }
    currentWords.push({ text: word, width: wordWidth });
  }

  // Finish last line if there are remaining words
  if (currentWords.length > 0) {
    finishLine();
  }

  // If there were no words but text was empty or only whitespace, produce one empty line
  if (lines.length === 0 && text.length > 0) {
    lines.push({
      text: '',
      width: 0,
      x: 0,
      y: 0,
      words: [],
    });
  }

  // Assign y positions (PDF y goes up, so first line is at top, subsequent lines go down)
  // y=0 is the baseline of the first line; subsequent lines are offset negatively
  let totalWidth = 0;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    line.y = i === 0 ? 0 : -(i * lineHeight);

    // Recalculate words for the line
    const lineWords = line.text.split(' ').filter(w => w.length > 0);
    line.words = lineWords.map(w => ({
      text: w,
      width: measureWord(font, fontSize, w, letterSpacing),
    }));

    // Alignment offset
    if (maxWidth !== undefined) {
      switch (alignment) {
        case 'center':
          line.x = (maxWidth - line.width) / 2;
          break;
        case 'right':
          line.x = maxWidth - line.width;
          break;
        case 'justify':
          line.x = 0; // justify handled via word spacing in renderer
          break;
        case 'left':
        default:
          line.x = 0;
          break;
      }
    }

    if (line.width > totalWidth) {
      totalWidth = line.width;
    }
  }

  const totalHeight = lines.length > 0 ? (lines.length - 1) * lineHeight + fontSize : 0;

  return { lines, totalHeight, totalWidth };
}

/**
 * Layout rich text (mixed fonts/sizes) into lines.
 */
export function layoutRichText(
  runs: RichTextRun[],
  options: RichTextOptions,
  defaultFont: Font,
  defaultFontSize: number,
): RichLayoutResult {
  const { width, alignment = 'left', lineHeight: lineHeightMultiplier = 1.2, maxLines } = options;

  // First, flatten all runs into word-level fragments with their style info
  interface StyledWord {
    text: string;
    font: Font;
    fontSize: number;
    color?: import('../color/color.js').Color;
    underline?: boolean;
    strikethrough?: boolean;
    link?: string;
    width: number;
    spaceWidth: number;
    lineHeight: number;
    isNewline: boolean;
  }

  const styledWords: StyledWord[] = [];

  for (const run of runs) {
    const font = run.font ?? defaultFont;
    const fontSize = run.fontSize ?? defaultFontSize;
    const lh = fontSize * lineHeightMultiplier;
    const sw = font.measureWidth(' ', fontSize);

    const segments = run.text.split('\n');
    for (let si = 0; si < segments.length; si++) {
      if (si > 0) {
        styledWords.push({
          text: '\n',
          font,
          fontSize,
          color: run.color,
          underline: run.underline,
          strikethrough: run.strikethrough,
          link: run.link,
          width: 0,
          spaceWidth: sw,
          lineHeight: lh,
          isNewline: true,
        });
      }
      const words = segments[si].split(/\s+/).filter(w => w.length > 0);
      for (const word of words) {
        styledWords.push({
          text: word,
          font,
          fontSize,
          color: run.color,
          underline: run.underline,
          strikethrough: run.strikethrough,
          link: run.link,
          width: font.measureWidth(word, fontSize),
          spaceWidth: sw,
          lineHeight: lh,
          isNewline: false,
        });
      }
    }
  }

  // Break into lines
  const lines: RichLayoutLine[] = [];
  let currentLineWords: StyledWord[] = [];
  let currentLineWidth = 0;

  function finishRichLine(): void {
    if (maxLines !== undefined && lines.length >= maxLines) return;
    if (currentLineWords.length === 0) {
      // Empty line (from explicit newline)
      const defaultLH = defaultFontSize * lineHeightMultiplier;
      lines.push({
        runs: [],
        width: 0,
        x: 0,
        y: 0,
        height: defaultLH,
      });
      currentLineWords = [];
      currentLineWidth = 0;
      return;
    }

    // Build runs for this line, merging consecutive words with same style
    const lineRuns: RichLayoutRun[] = [];
    let xOffset = 0;
    let maxHeight = 0;

    for (let i = 0; i < currentLineWords.length; i++) {
      const w = currentLineWords[i];
      if (w.lineHeight > maxHeight) maxHeight = w.lineHeight;

      // Add space before word if not the first
      if (i > 0) {
        xOffset += currentLineWords[i - 1].spaceWidth;
      }

      lineRuns.push({
        text: w.text,
        width: w.width,
        font: w.font,
        fontSize: w.fontSize,
        color: w.color,
        underline: w.underline,
        strikethrough: w.strikethrough,
        link: w.link,
        x: xOffset,
      });

      xOffset += w.width;
    }

    lines.push({
      runs: lineRuns,
      width: currentLineWidth,
      x: 0,
      y: 0,
      height: maxHeight,
    });

    currentLineWords = [];
    currentLineWidth = 0;
  }

  for (const sw of styledWords) {
    if (sw.isNewline) {
      finishRichLine();
      if (maxLines !== undefined && lines.length >= maxLines) break;
      continue;
    }

    const widthWithWord = currentLineWords.length === 0
      ? sw.width
      : currentLineWidth + currentLineWords[currentLineWords.length - 1].spaceWidth + sw.width;

    if (currentLineWords.length > 0 && widthWithWord > width) {
      finishRichLine();
      if (maxLines !== undefined && lines.length >= maxLines) break;
    }

    if (currentLineWords.length === 0) {
      currentLineWidth = sw.width;
    } else {
      currentLineWidth += currentLineWords[currentLineWords.length - 1].spaceWidth + sw.width;
    }
    currentLineWords.push(sw);
  }

  if (currentLineWords.length > 0) {
    finishRichLine();
  }

  // Set y positions and alignment
  let yPos = 0;
  let totalWidth = 0;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    line.y = -yPos;
    yPos += line.height;

    // Alignment
    switch (alignment) {
      case 'center':
        line.x = (width - line.width) / 2;
        break;
      case 'right':
        line.x = width - line.width;
        break;
      case 'justify':
      case 'left':
      default:
        line.x = 0;
        break;
    }

    if (line.width > totalWidth) totalWidth = line.width;
  }

  const totalHeight = yPos;

  return { lines, totalHeight, totalWidth };
}
