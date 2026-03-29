import { describe, it, expect } from 'vitest';
import { layoutText } from '../../src/text/text-layout.js';
import { getStandardFont } from '../../src/font/standard-fonts.js';
import type { TextStyle } from '../../src/text/text-style.js';

function makeStyle(overrides?: Partial<TextStyle>): TextStyle {
  return {
    font: getStandardFont('Helvetica')!,
    fontSize: 12,
    ...overrides,
  };
}

describe('layoutText', () => {
  it('lays out a single line with no wrapping', () => {
    const result = layoutText('Hello World', makeStyle());
    expect(result.lines.length).toBe(1);
    expect(result.lines[0].text).toBe('Hello World');
    expect(result.totalWidth).toBeGreaterThan(0);
    expect(result.totalHeight).toBeGreaterThan(0);
  });

  it('wraps text at maxWidth', () => {
    const style = makeStyle();
    // Use a very narrow width to force wrapping
    const result = layoutText('Hello World Test', style, 50);
    expect(result.lines.length).toBeGreaterThan(1);
  });

  it('respects explicit newlines', () => {
    const result = layoutText('Line1\nLine2\nLine3', makeStyle());
    expect(result.lines.length).toBe(3);
    expect(result.lines[0].text).toBe('Line1');
    expect(result.lines[1].text).toBe('Line2');
    expect(result.lines[2].text).toBe('Line3');
  });

  it('respects maxLines', () => {
    const result = layoutText('Word1 Word2 Word3 Word4 Word5', makeStyle(), 50, 2);
    expect(result.lines.length).toBeLessThanOrEqual(2);
  });

  it('assigns y positions descending', () => {
    const result = layoutText('Line1\nLine2', makeStyle());
    expect(result.lines[0].y).toEqual(0);
    expect(result.lines[1].y).toBeLessThan(0);
  });

  it('center alignment offsets x', () => {
    const style = makeStyle({ alignment: 'center' });
    const result = layoutText('Hi', style, 200);
    expect(result.lines[0].x).toBeGreaterThan(0);
  });

  it('right alignment offsets x', () => {
    const style = makeStyle({ alignment: 'right' });
    const result = layoutText('Hi', style, 200);
    expect(result.lines[0].x).toBeGreaterThan(0);
  });

  it('left alignment has x=0', () => {
    const style = makeStyle({ alignment: 'left' });
    const result = layoutText('Hi', style, 200);
    expect(result.lines[0].x).toBe(0);
  });

  it('handles empty text', () => {
    const result = layoutText('', makeStyle());
    expect(result.lines.length).toBe(0);
  });

  it('handles whitespace-only text', () => {
    const result = layoutText('   ', makeStyle());
    // Should produce an empty line since text.length > 0 but no words
    expect(result.lines.length).toBe(1);
    expect(result.lines[0].text).toBe('');
  });

  it('totalHeight accounts for all lines', () => {
    const style = makeStyle({ lineHeight: 1.5 });
    const result = layoutText('A\nB\nC', style);
    // 3 lines, totalHeight = (lines-1)*lineHeight*fontSize + fontSize
    expect(result.totalHeight).toBeGreaterThan(0);
    expect(result.lines.length).toBe(3);
  });
});
