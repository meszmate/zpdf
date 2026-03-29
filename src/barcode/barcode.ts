/**
 * Unified barcode API.
 * Delegates to specific barcode implementations.
 */

import type { Color } from '../color/color.js';
import { renderCode128 } from './code128.js';
import { renderCode39 } from './code39.js';
import { renderEAN13 } from './ean13.js';
import { renderQRCode } from './qr/qr-renderer.js';

export type BarcodeType = 'code128' | 'code39' | 'ean13' | 'qr';

export interface BarcodeOptions {
  x: number;
  y: number;
  width: number;
  height: number;
  color?: Color;
  errorLevel?: 'L' | 'M' | 'Q' | 'H'; // QR only
}

/**
 * Draw a barcode of the specified type and return PDF drawing operators.
 *
 * @param type - Barcode type: 'code128', 'code39', 'ean13', or 'qr'
 * @param data - Data to encode
 * @param options - Position, size, and optional color/error level
 * @returns PDF operator string
 */
export function drawBarcode(type: BarcodeType, data: string, options: BarcodeOptions): string {
  switch (type) {
    case 'code128':
      return renderCode128(data, options.x, options.y, options.width, options.height, options.color);
    case 'code39':
      return renderCode39(data, options.x, options.y, options.width, options.height, options.color);
    case 'ean13':
      return renderEAN13(data, options.x, options.y, options.width, options.height, options.color);
    case 'qr':
      // QR codes are square; use the minimum of width/height
      const size = Math.min(options.width, options.height);
      return renderQRCode(data, options.x, options.y, size, {
        errorLevel: options.errorLevel ?? 'M',
        color: options.color,
      });
    default:
      throw new Error(`Unknown barcode type: ${type}`);
  }
}
