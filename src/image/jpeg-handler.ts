import type { PdfRef } from '../core/types.js';
import type { ObjectStore } from '../core/object-store.js';
import { pdfStream, pdfName, pdfNum, pdfArray } from '../core/objects.js';
import type { ImageInfo } from './image-utils.js';

/**
 * Read a 16-bit big-endian unsigned integer from a Uint8Array.
 */
function readUint16BE(data: Uint8Array, offset: number): number {
  return (data[offset] << 8) | data[offset + 1];
}

/**
 * Parse a JPEG file to extract image dimensions, color space, and bit depth.
 *
 * JPEG structure:
 * - File starts with SOI marker (FF D8)
 * - Followed by segments, each starting with FF xx (marker)
 * - Most segments have a 2-byte length field after the marker
 * - SOF0 (FF C0) and SOF2 (FF C2) contain image parameters:
 *   - Byte 0-1: marker (FF C0/C2)
 *   - Byte 2-3: segment length
 *   - Byte 4: precision (bits per component)
 *   - Byte 5-6: height
 *   - Byte 7-8: width
 *   - Byte 9: number of components (1=Gray, 3=RGB/YCbCr, 4=CMYK)
 */
export function parseJpeg(data: Uint8Array): ImageInfo {
  if (data.length < 2 || data[0] !== 0xff || data[1] !== 0xd8) {
    throw new Error('Invalid JPEG: missing SOI marker');
  }

  let offset = 2;

  while (offset < data.length - 1) {
    // Find next marker
    if (data[offset] !== 0xff) {
      offset++;
      continue;
    }

    // Skip padding FF bytes
    while (offset < data.length && data[offset] === 0xff) {
      offset++;
    }

    if (offset >= data.length) break;

    const marker = data[offset];
    offset++;

    // Check for SOF markers (Start Of Frame)
    // SOF0 (0xC0) = Baseline DCT
    // SOF1 (0xC1) = Extended sequential DCT
    // SOF2 (0xC2) = Progressive DCT
    // SOF3 (0xC3) = Lossless
    // SOF5-SOF7, SOF9-SOF11, SOF13-SOF15 are also SOF markers
    const isSOF =
      (marker >= 0xc0 && marker <= 0xc3) ||
      (marker >= 0xc5 && marker <= 0xc7) ||
      (marker >= 0xc9 && marker <= 0xcb) ||
      (marker >= 0xcd && marker <= 0xcf);

    if (isSOF) {
      if (offset + 7 > data.length) {
        throw new Error('Invalid JPEG: truncated SOF segment');
      }

      // Skip segment length (2 bytes)
      const precision = data[offset + 2];
      const height = readUint16BE(data, offset + 3);
      const width = readUint16BE(data, offset + 5);
      const numComponents = data[offset + 7];

      let colorSpace: 'DeviceRGB' | 'DeviceGray' | 'DeviceCMYK';
      switch (numComponents) {
        case 1:
          colorSpace = 'DeviceGray';
          break;
        case 3:
          colorSpace = 'DeviceRGB';
          break;
        case 4:
          colorSpace = 'DeviceCMYK';
          break;
        default:
          throw new Error(`Unsupported JPEG component count: ${numComponents}`);
      }

      return {
        width,
        height,
        colorSpace,
        bitsPerComponent: precision,
        hasAlpha: false, // JPEG never has alpha
      };
    }

    // For other markers, skip to next segment
    // Markers with no payload:
    if (marker === 0xd9) {
      // EOI (End Of Image)
      break;
    }
    if (marker === 0x00 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      // Standalone markers (RST0-RST7, TEM) - no payload
      continue;
    }

    // Markers with payload: read length
    if (offset + 1 >= data.length) break;
    const segmentLength = readUint16BE(data, offset);
    offset += segmentLength;
  }

  throw new Error('Invalid JPEG: no SOF marker found');
}

/**
 * Embed a JPEG image into a PDF ObjectStore.
 * JPEG data can be embedded directly as a DCTDecode stream.
 */
export function embedJpeg(
  store: ObjectStore,
  data: Uint8Array,
  info: ImageInfo,
): PdfRef {
  const ref = store.allocRef();

  const streamDict: Record<string, import('../core/types.js').PdfObject> = {
    Type: pdfName('XObject'),
    Subtype: pdfName('Image'),
    Width: pdfNum(info.width),
    Height: pdfNum(info.height),
    ColorSpace: pdfName(info.colorSpace),
    BitsPerComponent: pdfNum(info.bitsPerComponent),
    Filter: pdfName('DCTDecode'),
    Length: pdfNum(data.length),
  };

  // For CMYK JPEGs, add a Decode array to invert the values
  // since JPEG stores CMYK as inverted (YCCK)
  if (info.colorSpace === 'DeviceCMYK') {
    streamDict['Decode'] = pdfArray(
      pdfNum(1), pdfNum(0),
      pdfNum(1), pdfNum(0),
      pdfNum(1), pdfNum(0),
      pdfNum(1), pdfNum(0),
    );
  }

  const stream = pdfStream(streamDict, data);
  store.set(ref, stream);

  return ref;
}
