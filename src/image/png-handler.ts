import type { PdfRef, PdfObject } from '../core/types.js';
import type { ObjectStore } from '../core/object-store.js';
import { pdfStream, pdfName, pdfNum, pdfArray, pdfHexStr } from '../core/objects.js';
import { inflate } from '../compress/inflate.js';
import { deflate } from '../compress/deflate.js';
import type { ImageInfo } from './image-utils.js';

/**
 * Extended image info for PNG with parsed pixel data.
 */
export interface PngData extends ImageInfo {
  rawPixels: Uint8Array;
  alphaChannel?: Uint8Array;
  palette?: Uint8Array;
  paletteAlpha?: Uint8Array;
}

/**
 * Read a 32-bit big-endian unsigned integer.
 */
function readUint32BE(data: Uint8Array, offset: number): number {
  return (
    ((data[offset] << 24) |
      (data[offset + 1] << 16) |
      (data[offset + 2] << 8) |
      data[offset + 3]) >>> 0
  );
}

/**
 * Read a 16-bit big-endian unsigned integer.
 */
function readUint16BE(data: Uint8Array, offset: number): number {
  return (data[offset] << 8) | data[offset + 1];
}

/**
 * PNG color type constants.
 */
const COLOR_TYPE_GRAYSCALE = 0;
const COLOR_TYPE_RGB = 2;
const COLOR_TYPE_INDEXED = 3;
const COLOR_TYPE_GRAYSCALE_ALPHA = 4;
const COLOR_TYPE_RGBA = 6;

/**
 * Apply Paeth predictor filter for PNG row filtering.
 */
function paethPredictor(a: number, b: number, c: number): number {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

/**
 * Remove PNG row filters from decompressed IDAT data.
 *
 * Each row is prefixed with a filter type byte:
 *   0 = None
 *   1 = Sub (byte to left)
 *   2 = Up (byte above)
 *   3 = Average (avg of left and above)
 *   4 = Paeth (predictor of left, above, upper-left)
 */
function unfilterRows(
  rawData: Uint8Array,
  width: number,
  height: number,
  bytesPerPixel: number,
): Uint8Array {
  const stride = width * bytesPerPixel; // bytes per row (without filter byte)
  const rowSize = stride + 1; // with filter byte

  if (rawData.length < rowSize * height) {
    throw new Error(
      `PNG IDAT data too short: expected ${rowSize * height}, got ${rawData.length}`,
    );
  }

  const output = new Uint8Array(stride * height);

  for (let row = 0; row < height; row++) {
    const filterType = rawData[row * rowSize];
    const rowOffset = row * rowSize + 1; // skip filter byte
    const outOffset = row * stride;

    switch (filterType) {
      case 0: // None
        for (let i = 0; i < stride; i++) {
          output[outOffset + i] = rawData[rowOffset + i];
        }
        break;

      case 1: // Sub
        for (let i = 0; i < stride; i++) {
          const left = i >= bytesPerPixel ? output[outOffset + i - bytesPerPixel] : 0;
          output[outOffset + i] = (rawData[rowOffset + i] + left) & 0xff;
        }
        break;

      case 2: // Up
        for (let i = 0; i < stride; i++) {
          const above = row > 0 ? output[outOffset - stride + i] : 0;
          output[outOffset + i] = (rawData[rowOffset + i] + above) & 0xff;
        }
        break;

      case 3: // Average
        for (let i = 0; i < stride; i++) {
          const left = i >= bytesPerPixel ? output[outOffset + i - bytesPerPixel] : 0;
          const above = row > 0 ? output[outOffset - stride + i] : 0;
          output[outOffset + i] = (rawData[rowOffset + i] + Math.floor((left + above) / 2)) & 0xff;
        }
        break;

      case 4: // Paeth
        for (let i = 0; i < stride; i++) {
          const left = i >= bytesPerPixel ? output[outOffset + i - bytesPerPixel] : 0;
          const above = row > 0 ? output[outOffset - stride + i] : 0;
          const upperLeft =
            row > 0 && i >= bytesPerPixel
              ? output[outOffset - stride + i - bytesPerPixel]
              : 0;
          output[outOffset + i] =
            (rawData[rowOffset + i] + paethPredictor(left, above, upperLeft)) & 0xff;
        }
        break;

      default:
        throw new Error(`Unknown PNG filter type: ${filterType}`);
    }
  }

  return output;
}

/**
 * Parse a PNG file into its constituent data.
 * Handles color types: 0 (grayscale), 2 (RGB), 3 (indexed),
 * 4 (grayscale+alpha), 6 (RGBA).
 */
export async function parsePng(data: Uint8Array): Promise<PngData> {
  // Verify PNG signature
  if (
    data.length < 8 ||
    data[0] !== 0x89 ||
    data[1] !== 0x50 ||
    data[2] !== 0x4e ||
    data[3] !== 0x47 ||
    data[4] !== 0x0d ||
    data[5] !== 0x0a ||
    data[6] !== 0x1a ||
    data[7] !== 0x0a
  ) {
    throw new Error('Invalid PNG: bad signature');
  }

  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colorType = 0;
  let palette: Uint8Array | undefined;
  let paletteAlpha: Uint8Array | undefined;
  const idatChunks: Uint8Array[] = [];

  let offset = 8; // skip signature

  // Parse chunks
  while (offset + 8 <= data.length) {
    const chunkLength = readUint32BE(data, offset);
    const chunkType = String.fromCharCode(
      data[offset + 4],
      data[offset + 5],
      data[offset + 6],
      data[offset + 7],
    );
    const chunkDataOffset = offset + 8;

    if (chunkDataOffset + chunkLength > data.length) {
      throw new Error(`PNG chunk "${chunkType}" extends beyond file`);
    }

    switch (chunkType) {
      case 'IHDR': {
        if (chunkLength < 13) {
          throw new Error('Invalid PNG IHDR chunk');
        }
        width = readUint32BE(data, chunkDataOffset);
        height = readUint32BE(data, chunkDataOffset + 4);
        bitDepth = data[chunkDataOffset + 8];
        colorType = data[chunkDataOffset + 9];
        const compressionMethod = data[chunkDataOffset + 10];
        const filterMethod = data[chunkDataOffset + 11];
        const interlaceMethod = data[chunkDataOffset + 12];

        if (compressionMethod !== 0) {
          throw new Error(`Unsupported PNG compression method: ${compressionMethod}`);
        }
        if (filterMethod !== 0) {
          throw new Error(`Unsupported PNG filter method: ${filterMethod}`);
        }
        if (interlaceMethod !== 0) {
          throw new Error('Interlaced PNGs are not supported');
        }
        break;
      }

      case 'PLTE': {
        palette = data.slice(chunkDataOffset, chunkDataOffset + chunkLength);
        break;
      }

      case 'tRNS': {
        paletteAlpha = data.slice(chunkDataOffset, chunkDataOffset + chunkLength);
        break;
      }

      case 'IDAT': {
        idatChunks.push(data.slice(chunkDataOffset, chunkDataOffset + chunkLength));
        break;
      }

      case 'IEND': {
        // End of PNG
        break;
      }

      // Skip other chunks (gAMA, cHRM, sRGB, iCCP, tEXt, etc.)
    }

    // Move to next chunk: length + type (4) + data + CRC (4)
    offset = chunkDataOffset + chunkLength + 4;
  }

  if (width === 0 || height === 0) {
    throw new Error('Invalid PNG: missing IHDR chunk');
  }

  if (idatChunks.length === 0) {
    throw new Error('Invalid PNG: no IDAT chunks');
  }

  // Concatenate all IDAT chunks and decompress
  let totalIdatLength = 0;
  for (const chunk of idatChunks) {
    totalIdatLength += chunk.length;
  }
  const compressedData = new Uint8Array(totalIdatLength);
  let idatOffset = 0;
  for (const chunk of idatChunks) {
    compressedData.set(chunk, idatOffset);
    idatOffset += chunk.length;
  }

  const inflatedData = await inflate(compressedData);

  // Determine bytes per pixel based on color type and bit depth
  let bytesPerPixel: number;
  let samplesPerPixel: number;

  switch (colorType) {
    case COLOR_TYPE_GRAYSCALE:
      samplesPerPixel = 1;
      break;
    case COLOR_TYPE_RGB:
      samplesPerPixel = 3;
      break;
    case COLOR_TYPE_INDEXED:
      samplesPerPixel = 1; // index into palette
      break;
    case COLOR_TYPE_GRAYSCALE_ALPHA:
      samplesPerPixel = 2;
      break;
    case COLOR_TYPE_RGBA:
      samplesPerPixel = 4;
      break;
    default:
      throw new Error(`Unsupported PNG color type: ${colorType}`);
  }

  // For bit depths < 8, bytes per pixel is fractional, but row stride calculation
  // must account for the actual bits
  if (bitDepth < 8) {
    // For sub-byte bit depths, calculate stride differently
    const bitsPerRow = width * samplesPerPixel * bitDepth;
    const bytesPerRow = Math.ceil(bitsPerRow / 8);
    bytesPerPixel = 1; // filter operates on bytes, so bpp for filter is 1

    // Unfilter using byte-level stride
    const unfiltered = unfilterRows(inflatedData, bytesPerRow, height, bytesPerPixel);

    // For indexed with sub-byte depths, unpack to 1 byte per index
    if (colorType === COLOR_TYPE_INDEXED) {
      const rawPixels = unpackSubBytePixels(unfiltered, width, height, bitDepth, bytesPerRow);
      return buildPngData(width, height, bitDepth, colorType, rawPixels, palette, paletteAlpha);
    }

    // For grayscale with sub-byte depths, unpack and scale to 8 bits
    if (colorType === COLOR_TYPE_GRAYSCALE) {
      const rawPixels = unpackSubBytePixels(unfiltered, width, height, bitDepth, bytesPerRow);
      // Scale to 8-bit
      const maxVal = (1 << bitDepth) - 1;
      const scaled = new Uint8Array(rawPixels.length);
      for (let i = 0; i < rawPixels.length; i++) {
        scaled[i] = Math.round((rawPixels[i] / maxVal) * 255);
      }
      return buildPngData(width, height, 8, colorType, scaled, palette, paletteAlpha);
    }

    throw new Error(`Unsupported sub-byte bit depth ${bitDepth} for color type ${colorType}`);
  }

  // 8 or 16 bits per sample
  if (bitDepth === 16) {
    // For 16-bit images, bytesPerPixel is doubled
    bytesPerPixel = samplesPerPixel * 2;
  } else {
    bytesPerPixel = samplesPerPixel;
  }

  const unfiltered = unfilterRows(inflatedData, width * bytesPerPixel, height, bytesPerPixel);

  // For 16-bit, downsample to 8-bit
  let pixels: Uint8Array;
  if (bitDepth === 16) {
    const pixelCount = width * height * samplesPerPixel;
    pixels = new Uint8Array(pixelCount);
    for (let i = 0; i < pixelCount; i++) {
      // Take the high byte of each 16-bit sample
      pixels[i] = unfiltered[i * 2];
    }
  } else {
    pixels = unfiltered;
  }

  return buildPngData(width, height, bitDepth > 8 ? 8 : bitDepth, colorType, pixels, palette, paletteAlpha);
}

/**
 * Unpack sub-byte pixels (1, 2, 4 bits) into one byte per pixel.
 */
function unpackSubBytePixels(
  filtered: Uint8Array,
  width: number,
  height: number,
  bitDepth: number,
  bytesPerRow: number,
): Uint8Array {
  const output = new Uint8Array(width * height);
  const mask = (1 << bitDepth) - 1;
  const pixelsPerByte = 8 / bitDepth;

  for (let row = 0; row < height; row++) {
    const rowStart = row * bytesPerRow;
    for (let col = 0; col < width; col++) {
      const byteIndex = rowStart + Math.floor(col / pixelsPerByte);
      const bitOffset = (pixelsPerByte - 1 - (col % pixelsPerByte)) * bitDepth;
      output[row * width + col] = (filtered[byteIndex] >> bitOffset) & mask;
    }
  }

  return output;
}

/**
 * Build PngData from parsed/unfiltered pixel data, splitting alpha if needed.
 */
function buildPngData(
  width: number,
  height: number,
  bitDepth: number,
  colorType: number,
  pixels: Uint8Array,
  palette?: Uint8Array,
  paletteAlpha?: Uint8Array,
): PngData {
  const totalPixels = width * height;

  switch (colorType) {
    case COLOR_TYPE_GRAYSCALE: {
      return {
        width,
        height,
        colorSpace: 'DeviceGray',
        bitsPerComponent: 8,
        hasAlpha: false,
        rawPixels: pixels,
        palette,
        paletteAlpha,
      };
    }

    case COLOR_TYPE_RGB: {
      return {
        width,
        height,
        colorSpace: 'DeviceRGB',
        bitsPerComponent: 8,
        hasAlpha: false,
        rawPixels: pixels,
        palette,
        paletteAlpha,
      };
    }

    case COLOR_TYPE_INDEXED: {
      if (!palette) {
        throw new Error('PNG indexed color type requires PLTE chunk');
      }
      // For indexed, the raw pixels are palette indices
      // We check if tRNS chunk provides alpha for any palette entry
      const hasAlpha = paletteAlpha !== undefined && paletteAlpha.length > 0;
      return {
        width,
        height,
        colorSpace: 'DeviceRGB', // Will use Indexed color space in embedder
        bitsPerComponent: bitDepth <= 8 ? bitDepth : 8,
        hasAlpha,
        rawPixels: pixels,
        palette,
        paletteAlpha,
      };
    }

    case COLOR_TYPE_GRAYSCALE_ALPHA: {
      // Split into gray and alpha channels
      const grayPixels = new Uint8Array(totalPixels);
      const alphaChannel = new Uint8Array(totalPixels);
      for (let i = 0; i < totalPixels; i++) {
        grayPixels[i] = pixels[i * 2];
        alphaChannel[i] = pixels[i * 2 + 1];
      }
      return {
        width,
        height,
        colorSpace: 'DeviceGray',
        bitsPerComponent: 8,
        hasAlpha: true,
        rawPixels: grayPixels,
        alphaChannel,
        palette,
        paletteAlpha,
      };
    }

    case COLOR_TYPE_RGBA: {
      // Split into RGB and alpha channels
      const rgbPixels = new Uint8Array(totalPixels * 3);
      const alpha = new Uint8Array(totalPixels);
      for (let i = 0; i < totalPixels; i++) {
        rgbPixels[i * 3] = pixels[i * 4];
        rgbPixels[i * 3 + 1] = pixels[i * 4 + 1];
        rgbPixels[i * 3 + 2] = pixels[i * 4 + 2];
        alpha[i] = pixels[i * 4 + 3];
      }
      return {
        width,
        height,
        colorSpace: 'DeviceRGB',
        bitsPerComponent: 8,
        hasAlpha: true,
        rawPixels: rgbPixels,
        alphaChannel: alpha,
        palette,
        paletteAlpha,
      };
    }

    default:
      throw new Error(`Unsupported PNG color type: ${colorType}`);
  }
}

/**
 * Embed a PNG image into a PDF ObjectStore.
 * Creates an Image XObject with FlateDecode compression.
 * For images with alpha, creates a separate SMask soft-mask image.
 * For indexed images, creates an Indexed color space with palette.
 */
export async function embedPng(
  store: ObjectStore,
  data: Uint8Array,
): Promise<PdfRef> {
  const png = await parsePng(data);
  const ref = store.allocRef();

  const streamDict: Record<string, PdfObject> = {
    Type: pdfName('XObject'),
    Subtype: pdfName('Image'),
    Width: pdfNum(png.width),
    Height: pdfNum(png.height),
    BitsPerComponent: pdfNum(png.bitsPerComponent),
    Filter: pdfName('FlateDecode'),
  };

  // Handle indexed (palette-based) images
  if (png.palette && png.rawPixels.length === png.width * png.height) {
    // Check if pixel values are palette indices (indexed color type)
    // The rawPixels are indices, palette holds the RGB values
    const paletteEntries = png.palette.length / 3;
    const maxIndex = (1 << png.bitsPerComponent) - 1;

    // Build Indexed color space: [/Indexed /DeviceRGB hival paletteString]
    const paletteHex = Array.from(png.palette)
      .map(b => b.toString(16).padStart(2, '0'))
      .join('');

    streamDict['ColorSpace'] = pdfArray(
      pdfName('Indexed'),
      pdfName('DeviceRGB'),
      pdfNum(paletteEntries - 1),
      pdfHexStr(paletteHex),
    );

    // Handle palette alpha via tRNS
    if (png.paletteAlpha && png.paletteAlpha.length > 0) {
      // Create an SMask image from the palette alpha values
      // Expand palette alpha to per-pixel alpha
      const pixelAlpha = new Uint8Array(png.width * png.height);
      for (let i = 0; i < pixelAlpha.length; i++) {
        const idx = png.rawPixels[i];
        pixelAlpha[i] = idx < png.paletteAlpha.length ? png.paletteAlpha[idx] : 255;
      }

      // Check if there are any non-opaque pixels
      let hasTransparency = false;
      for (let i = 0; i < pixelAlpha.length; i++) {
        if (pixelAlpha[i] < 255) {
          hasTransparency = true;
          break;
        }
      }

      if (hasTransparency) {
        const compressedAlpha = await deflate(pixelAlpha);
        const smaskRef = store.allocRef();
        const smaskStream = pdfStream(
          {
            Type: pdfName('XObject'),
            Subtype: pdfName('Image'),
            Width: pdfNum(png.width),
            Height: pdfNum(png.height),
            ColorSpace: pdfName('DeviceGray'),
            BitsPerComponent: pdfNum(8),
            Filter: pdfName('FlateDecode'),
            Length: pdfNum(compressedAlpha.length),
          },
          compressedAlpha,
        );
        store.set(smaskRef, smaskStream);
        streamDict['SMask'] = smaskRef;
      }
    }

    const compressedPixels = await deflate(png.rawPixels);
    streamDict['Length'] = pdfNum(compressedPixels.length);
    const stream = pdfStream(streamDict, compressedPixels);
    store.set(ref, stream);
    return ref;
  }

  // Non-indexed images
  streamDict['ColorSpace'] = pdfName(png.colorSpace);

  // Handle alpha channel via SMask
  if (png.hasAlpha && png.alphaChannel) {
    const compressedAlpha = await deflate(png.alphaChannel);
    const smaskRef = store.allocRef();
    const smaskStream = pdfStream(
      {
        Type: pdfName('XObject'),
        Subtype: pdfName('Image'),
        Width: pdfNum(png.width),
        Height: pdfNum(png.height),
        ColorSpace: pdfName('DeviceGray'),
        BitsPerComponent: pdfNum(8),
        Filter: pdfName('FlateDecode'),
        Length: pdfNum(compressedAlpha.length),
      },
      compressedAlpha,
    );
    store.set(smaskRef, smaskStream);
    streamDict['SMask'] = smaskRef;
  }

  // Compress pixel data
  const compressedPixels = await deflate(png.rawPixels);
  streamDict['Length'] = pdfNum(compressedPixels.length);

  const stream = pdfStream(streamDict, compressedPixels);
  store.set(ref, stream);

  return ref;
}
