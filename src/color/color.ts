export interface RGB {
  readonly type: 'rgb';
  readonly r: number;
  readonly g: number;
  readonly b: number;
}

export interface CMYK {
  readonly type: 'cmyk';
  readonly c: number;
  readonly m: number;
  readonly y: number;
  readonly k: number;
}

export interface Grayscale {
  readonly type: 'grayscale';
  readonly gray: number;
}

export type Color = RGB | CMYK | Grayscale;

function clamp(v: number, min: number, max: number): number {
  return v < min ? min : v > max ? max : v;
}

export function rgb(r: number, g: number, b: number): RGB {
  return {
    type: 'rgb',
    r: clamp(r / 255, 0, 1),
    g: clamp(g / 255, 0, 1),
    b: clamp(b / 255, 0, 1),
  };
}

export function cmyk(c: number, m: number, y: number, k: number): CMYK {
  return {
    type: 'cmyk',
    c: clamp(c / 100, 0, 1),
    m: clamp(m / 100, 0, 1),
    y: clamp(y / 100, 0, 1),
    k: clamp(k / 100, 0, 1),
  };
}

export function grayscale(gray: number): Grayscale {
  return {
    type: 'grayscale',
    gray: clamp(gray, 0, 1),
  };
}

export function hexColor(hex: string): RGB {
  let h = hex.startsWith('#') ? hex.slice(1) : hex;
  if (h.length === 3) {
    h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
  }
  if (h.length !== 6) {
    throw new Error(`Invalid hex color: ${hex}`);
  }
  const n = parseInt(h, 16);
  if (isNaN(n)) {
    throw new Error(`Invalid hex color: ${hex}`);
  }
  return rgb((n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff);
}
