/**
 * Render QR code to PDF drawing operators.
 */

import type { Color } from '../../color/color.js';
import { setFillColor } from '../../color/operators.js';
import { generateQRCode, type QRCodeOptions } from './qr-code.js';

/**
 * Generate a QR code and render it as PDF drawing operators.
 * The QR code is rendered as filled rectangles within a square of the given size.
 *
 * @param data - The string to encode
 * @param x - X position of the QR code (bottom-left)
 * @param y - Y position of the QR code (bottom-left)
 * @param size - Width and height of the QR code in points
 * @param options - QR code options (error level, version, color)
 * @returns PDF operator string
 */
export function renderQRCode(
  data: string,
  x: number,
  y: number,
  size: number,
  options?: QRCodeOptions & { color?: Color },
): string {
  const matrix = generateQRCode(data, options);
  const matrixSize = matrix.length;
  const moduleSize = size / matrixSize;

  const ops: string[] = [];
  ops.push('q'); // save state

  if (options?.color) {
    ops.push(setFillColor(options.color));
  } else {
    ops.push('0 0 0 rg'); // default black
  }

  // Render each dark module as a filled rectangle
  // PDF coordinate system has Y increasing upward, so we flip the rows
  for (let row = 0; row < matrixSize; row++) {
    for (let col = 0; col < matrixSize; col++) {
      if (matrix[row][col]) {
        const mx = x + col * moduleSize;
        // Flip vertically: row 0 is at top of QR code = top of rendered area
        const my = y + (matrixSize - 1 - row) * moduleSize;
        ops.push(`${fmt(mx)} ${fmt(my)} ${fmt(moduleSize)} ${fmt(moduleSize)} re`);
      }
    }
  }

  ops.push('f'); // fill all rectangles at once
  ops.push('Q'); // restore state

  return ops.join('\n') + '\n';
}

function fmt(n: number): string {
  if (Number.isInteger(n)) return n.toString();
  const s = n.toFixed(4);
  let end = s.length;
  while (end > 0 && s[end - 1] === '0') end--;
  if (s[end - 1] === '.') end--;
  return s.slice(0, end);
}
