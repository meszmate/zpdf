/**
 * PNG/TIFF predictor support for FlateDecode and LZWDecode filters.
 */

/**
 * Paeth predictor function as defined in the PNG specification.
 */
export function paethPredictor(a: number, b: number, c: number): number {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

/**
 * Compute bytes per pixel (minimum 1).
 */
function bytesPerPixel(colors: number, bitsPerComponent: number): number {
  return Math.max(1, Math.floor((colors * bitsPerComponent + 7) / 8));
}

/**
 * Compute row stride in bytes.
 */
function rowStride(columns: number, colors: number, bitsPerComponent: number): number {
  return Math.ceil((columns * colors * bitsPerComponent) / 8);
}

// ---------------------------------------------------------------------------
// TIFF Predictor 2 (horizontal differencing)
// ---------------------------------------------------------------------------

function applyTIFFPredictor2(
  data: Uint8Array,
  columns: number,
  colors: number,
  bitsPerComponent: number,
): Uint8Array {
  if (bitsPerComponent !== 8 && bitsPerComponent !== 16) {
    // Only 8 and 16 bpc commonly supported for TIFF predictor
    return data;
  }

  const stride = rowStride(columns, colors, bitsPerComponent);
  const numRows = Math.floor(data.length / stride);
  const out = new Uint8Array(data.length);
  const bytesPC = bitsPerComponent / 8;

  for (let row = 0; row < numRows; row++) {
    const rowOff = row * stride;

    // First pixel: copy as-is
    for (let c = 0; c < colors * bytesPC; c++) {
      out[rowOff + c] = data[rowOff + c];
    }

    // Remaining pixels: store difference from previous
    for (let col = 1; col < columns; col++) {
      for (let c = 0; c < colors; c++) {
        const curOff = rowOff + (col * colors + c) * bytesPC;
        const prevOff = rowOff + ((col - 1) * colors + c) * bytesPC;

        if (bytesPC === 1) {
          out[curOff] = (data[curOff] - data[prevOff]) & 0xff;
        } else {
          // 16-bit
          const cur = (data[curOff] << 8) | data[curOff + 1];
          const prev = (data[prevOff] << 8) | data[prevOff + 1];
          const diff = (cur - prev) & 0xffff;
          out[curOff] = (diff >> 8) & 0xff;
          out[curOff + 1] = diff & 0xff;
        }
      }
    }
  }

  // Copy any trailing bytes
  const processed = numRows * stride;
  if (processed < data.length) {
    out.set(data.subarray(processed), processed);
  }

  return out;
}

function removeTIFFPredictor2(
  data: Uint8Array,
  columns: number,
  colors: number,
  bitsPerComponent: number,
): Uint8Array {
  if (bitsPerComponent !== 8 && bitsPerComponent !== 16) {
    return data;
  }

  const stride = rowStride(columns, colors, bitsPerComponent);
  const numRows = Math.floor(data.length / stride);
  const out = new Uint8Array(data.length);
  const bytesPC = bitsPerComponent / 8;

  for (let row = 0; row < numRows; row++) {
    const rowOff = row * stride;

    // First pixel: copy
    for (let c = 0; c < colors * bytesPC; c++) {
      out[rowOff + c] = data[rowOff + c];
    }

    // Remaining pixels: accumulate
    for (let col = 1; col < columns; col++) {
      for (let c = 0; c < colors; c++) {
        const curOff = rowOff + (col * colors + c) * bytesPC;
        const prevOff = rowOff + ((col - 1) * colors + c) * bytesPC;

        if (bytesPC === 1) {
          out[curOff] = (data[curOff] + out[prevOff]) & 0xff;
        } else {
          const diff = (data[curOff] << 8) | data[curOff + 1];
          const prev = (out[prevOff] << 8) | out[prevOff + 1];
          const val = (diff + prev) & 0xffff;
          out[curOff] = (val >> 8) & 0xff;
          out[curOff + 1] = val & 0xff;
        }
      }
    }
  }

  const processed = numRows * stride;
  if (processed < data.length) {
    out.set(data.subarray(processed), processed);
  }

  return out;
}

// ---------------------------------------------------------------------------
// PNG Filters
// ---------------------------------------------------------------------------

function pngFilterNone(
  row: Uint8Array,
  _prev: Uint8Array,
  _bpp: number,
): Uint8Array {
  return row;
}

function pngFilterSub(
  row: Uint8Array,
  _prev: Uint8Array,
  bpp: number,
): Uint8Array {
  const out = new Uint8Array(row.length);
  for (let i = 0; i < row.length; i++) {
    const a = i >= bpp ? row[i - bpp] : 0;
    out[i] = (row[i] - a) & 0xff;
  }
  return out;
}

function pngFilterUp(
  row: Uint8Array,
  prev: Uint8Array,
  _bpp: number,
): Uint8Array {
  const out = new Uint8Array(row.length);
  for (let i = 0; i < row.length; i++) {
    out[i] = (row[i] - prev[i]) & 0xff;
  }
  return out;
}

function pngFilterAverage(
  row: Uint8Array,
  prev: Uint8Array,
  bpp: number,
): Uint8Array {
  const out = new Uint8Array(row.length);
  for (let i = 0; i < row.length; i++) {
    const a = i >= bpp ? row[i - bpp] : 0;
    const b = prev[i];
    out[i] = (row[i] - Math.floor((a + b) / 2)) & 0xff;
  }
  return out;
}

function pngFilterPaeth(
  row: Uint8Array,
  prev: Uint8Array,
  bpp: number,
): Uint8Array {
  const out = new Uint8Array(row.length);
  for (let i = 0; i < row.length; i++) {
    const a = i >= bpp ? row[i - bpp] : 0;
    const b = prev[i];
    const c = i >= bpp ? prev[i - bpp] : 0;
    out[i] = (row[i] - paethPredictor(a, b, c)) & 0xff;
  }
  return out;
}

function pngUnfilterNone(
  row: Uint8Array,
  _prev: Uint8Array,
  _bpp: number,
): Uint8Array {
  return new Uint8Array(row);
}

function pngUnfilterSub(
  row: Uint8Array,
  _prev: Uint8Array,
  bpp: number,
): Uint8Array {
  const out = new Uint8Array(row.length);
  for (let i = 0; i < row.length; i++) {
    const a = i >= bpp ? out[i - bpp] : 0;
    out[i] = (row[i] + a) & 0xff;
  }
  return out;
}

function pngUnfilterUp(
  row: Uint8Array,
  prev: Uint8Array,
  _bpp: number,
): Uint8Array {
  const out = new Uint8Array(row.length);
  for (let i = 0; i < row.length; i++) {
    out[i] = (row[i] + prev[i]) & 0xff;
  }
  return out;
}

function pngUnfilterAverage(
  row: Uint8Array,
  prev: Uint8Array,
  bpp: number,
): Uint8Array {
  const out = new Uint8Array(row.length);
  for (let i = 0; i < row.length; i++) {
    const a = i >= bpp ? out[i - bpp] : 0;
    const b = prev[i];
    out[i] = (row[i] + Math.floor((a + b) / 2)) & 0xff;
  }
  return out;
}

function pngUnfilterPaeth(
  row: Uint8Array,
  prev: Uint8Array,
  bpp: number,
): Uint8Array {
  const out = new Uint8Array(row.length);
  for (let i = 0; i < row.length; i++) {
    const a = i >= bpp ? out[i - bpp] : 0;
    const b = prev[i];
    const c = i >= bpp ? prev[i - bpp] : 0;
    out[i] = (row[i] + paethPredictor(a, b, c)) & 0xff;
  }
  return out;
}

/**
 * Sum of absolute values of filtered row (used for optimum filter selection).
 */
function filterCost(filtered: Uint8Array): number {
  let sum = 0;
  for (let i = 0; i < filtered.length; i++) {
    const v = filtered[i];
    // Treat as signed byte
    sum += v <= 127 ? v : 256 - v;
  }
  return sum;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Apply predictor encoding to data.
 *
 * @param data - raw pixel data
 * @param predictor - predictor type (1, 2, 10-15)
 * @param columns - number of samples per row
 * @param colors - number of color components
 * @param bitsPerComponent - bits per component (1, 2, 4, 8, 16)
 */
export function applyPredictor(
  data: Uint8Array,
  predictor: number,
  columns: number,
  colors: number,
  bitsPerComponent: number,
): Uint8Array {
  if (predictor === 1) return data;

  if (predictor === 2) {
    return applyTIFFPredictor2(data, columns, colors, bitsPerComponent);
  }

  // PNG predictors (10-15)
  if (predictor < 10 || predictor > 15) {
    throw new Error(`Unsupported predictor: ${predictor}`);
  }

  const stride = rowStride(columns, colors, bitsPerComponent);
  const bpp = bytesPerPixel(colors, bitsPerComponent);
  const numRows = Math.floor(data.length / stride);

  // Output: each row prefixed with 1-byte filter type
  const out = new Uint8Array(numRows * (stride + 1));
  let outPos = 0;

  const zeroRow = new Uint8Array(stride);

  const filters = [pngFilterNone, pngFilterSub, pngFilterUp, pngFilterAverage, pngFilterPaeth];

  for (let row = 0; row < numRows; row++) {
    const rowOff = row * stride;
    const curRow = data.subarray(rowOff, rowOff + stride);
    const prevRow = row > 0 ? data.subarray(rowOff - stride, rowOff) : zeroRow;

    let filterType: number;
    let filtered: Uint8Array;

    if (predictor === 15) {
      // Optimum: try all 5 filters, pick the one with lowest cost
      let bestCost = Infinity;
      let bestType = 0;
      let bestFiltered = curRow;

      for (let ft = 0; ft < 5; ft++) {
        const f = filters[ft](curRow, prevRow, bpp);
        const cost = filterCost(f);
        if (cost < bestCost) {
          bestCost = cost;
          bestType = ft;
          bestFiltered = f;
        }
      }

      filterType = bestType;
      filtered = bestFiltered;
    } else {
      filterType = predictor - 10;
      filtered = filters[filterType](curRow, prevRow, bpp);
    }

    out[outPos++] = filterType;
    out.set(filtered, outPos);
    outPos += stride;
  }

  return out.subarray(0, outPos);
}

/**
 * Remove predictor encoding from data.
 *
 * @param data - predicted data (with PNG filter type bytes or TIFF differences)
 * @param predictor - predictor type (1, 2, 10-15)
 * @param columns - number of samples per row
 * @param colors - number of color components
 * @param bitsPerComponent - bits per component (1, 2, 4, 8, 16)
 */
export function removePredictor(
  data: Uint8Array,
  predictor: number,
  columns: number,
  colors: number,
  bitsPerComponent: number,
): Uint8Array {
  if (predictor === 1) return data;

  if (predictor === 2) {
    return removeTIFFPredictor2(data, columns, colors, bitsPerComponent);
  }

  // PNG predictors (10-15)
  if (predictor < 10 || predictor > 15) {
    throw new Error(`Unsupported predictor: ${predictor}`);
  }

  const stride = rowStride(columns, colors, bitsPerComponent);
  const bpp = bytesPerPixel(colors, bitsPerComponent);
  // Each row in input has 1 filter-type byte + stride data bytes
  const inputRowLen = stride + 1;
  const numRows = Math.floor(data.length / inputRowLen);

  const out = new Uint8Array(numRows * stride);
  const prevRow = new Uint8Array(stride); // starts as zeros

  const unfilters = [
    pngUnfilterNone,
    pngUnfilterSub,
    pngUnfilterUp,
    pngUnfilterAverage,
    pngUnfilterPaeth,
  ];

  for (let row = 0; row < numRows; row++) {
    const inputOff = row * inputRowLen;
    const filterType = data[inputOff];
    const rowData = data.subarray(inputOff + 1, inputOff + 1 + stride);

    if (filterType > 4) {
      throw new Error(`Invalid PNG filter type: ${filterType}`);
    }

    const decoded = unfilters[filterType](rowData, prevRow, bpp);
    out.set(decoded, row * stride);
    prevRow.set(decoded);
  }

  return out;
}
