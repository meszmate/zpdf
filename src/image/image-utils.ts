export interface ImageInfo {
  width: number;
  height: number;
  colorSpace: 'DeviceRGB' | 'DeviceGray' | 'DeviceCMYK';
  bitsPerComponent: number;
  hasAlpha: boolean;
}

export type ImageFormat = 'jpeg' | 'png' | 'unknown';

/**
 * Detect image format by examining magic bytes.
 *
 * JPEG: starts with 0xFF 0xD8 (SOI marker)
 * PNG:  starts with 0x89 0x50 0x4E 0x47 0x0D 0x0A 0x1A 0x0A (8-byte signature)
 */
export function detectImageFormat(data: Uint8Array): ImageFormat {
  if (data.length < 4) {
    return 'unknown';
  }

  // JPEG: FF D8
  if (data[0] === 0xff && data[1] === 0xd8) {
    return 'jpeg';
  }

  // PNG: 89 50 4E 47 0D 0A 1A 0A
  if (
    data.length >= 8 &&
    data[0] === 0x89 &&
    data[1] === 0x50 &&
    data[2] === 0x4e &&
    data[3] === 0x47 &&
    data[4] === 0x0d &&
    data[5] === 0x0a &&
    data[6] === 0x1a &&
    data[7] === 0x0a
  ) {
    return 'png';
  }

  return 'unknown';
}
