import type { RGB, CMYK, Grayscale } from './color.js';

export function rgbToCmyk(color: RGB): CMYK {
  const r = color.r;
  const g = color.g;
  const b = color.b;
  const k = 1 - Math.max(r, g, b);
  if (k >= 1) {
    return { type: 'cmyk', c: 0, m: 0, y: 0, k: 1 };
  }
  const invK = 1 / (1 - k);
  return {
    type: 'cmyk',
    c: (1 - r - k) * invK,
    m: (1 - g - k) * invK,
    y: (1 - b - k) * invK,
    k,
  };
}

export function cmykToRgb(color: CMYK): RGB {
  const { c, m, y, k } = color;
  return {
    type: 'rgb',
    r: (1 - c) * (1 - k),
    g: (1 - m) * (1 - k),
    b: (1 - y) * (1 - k),
  };
}

export function rgbToGrayscale(color: RGB): Grayscale {
  // ITU-R BT.709 luminance coefficients
  return {
    type: 'grayscale',
    gray: 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b,
  };
}

export function grayscaleToRgb(color: Grayscale): RGB {
  return {
    type: 'rgb',
    r: color.gray,
    g: color.gray,
    b: color.gray,
  };
}
