import type { PdfRef } from '../core/types.js';
import type { ObjectStore } from '../core/object-store.js';
import { detectImageFormat } from './image-utils.js';
import { parseJpeg, embedJpeg } from './jpeg-handler.js';
import { embedPng, parsePng } from './png-handler.js';

/**
 * Result of embedding an image, containing the PDF object reference
 * and the original image dimensions.
 */
export interface EmbeddedImage {
  ref: PdfRef;
  width: number;
  height: number;
}

/**
 * Embed an image into a PDF ObjectStore.
 * Auto-detects the image format (JPEG or PNG) and delegates
 * to the appropriate handler.
 *
 * @param store - The ObjectStore to add the image XObject to
 * @param imageBytes - Raw image file bytes
 * @returns The PDF reference and original image dimensions
 */
export async function embedImage(
  store: ObjectStore,
  imageBytes: Uint8Array,
): Promise<EmbeddedImage> {
  const format = detectImageFormat(imageBytes);

  switch (format) {
    case 'jpeg': {
      const info = parseJpeg(imageBytes);
      const ref = embedJpeg(store, imageBytes, info);
      return { ref, width: info.width, height: info.height };
    }

    case 'png': {
      const pngData = await parsePng(imageBytes);
      const ref = await embedPng(store, imageBytes);
      return { ref, width: pngData.width, height: pngData.height };
    }

    default:
      throw new Error('Unsupported image format: unable to detect JPEG or PNG');
  }
}
