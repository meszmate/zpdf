import type { PdfName, PdfArray, PdfObject } from '../core/types.js';
import { pdfName, pdfNum, pdfArray } from '../core/objects.js';

export function createDeviceRGBColorSpace(): PdfName {
  return pdfName('DeviceRGB');
}

export function createDeviceCMYKColorSpace(): PdfName {
  return pdfName('DeviceCMYK');
}

export function createDeviceGrayColorSpace(): PdfName {
  return pdfName('DeviceGray');
}

export function createIndexedColorSpace(
  base: PdfObject,
  maxIndex: number,
  lookup: Uint8Array,
): PdfArray {
  return pdfArray(
    pdfName('Indexed'),
    base,
    pdfNum(maxIndex),
    { type: 'string', value: lookup, encoding: 'hex' } as PdfObject,
  );
}
