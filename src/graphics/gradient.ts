import type { Color } from '../color/color.js';
import type { Matrix } from '../utils/math.js';
import type { PdfRef, PdfObject } from '../core/types.js';
import { ObjectStore } from '../core/object-store.js';
import { pdfName, pdfNum, pdfDict, pdfArray, pdfBool } from '../core/objects.js';
import { cmykToRgb } from '../color/conversion.js';

export interface GradientStop {
  offset: number;
  color: Color;
}

export interface LinearGradientOptions {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
  stops: GradientStop[];
}

export interface RadialGradientOptions {
  cx1: number;
  cy1: number;
  r1: number;
  cx2: number;
  cy2: number;
  r2: number;
  stops: GradientStop[];
}

function colorToRgbComponents(color: Color): [number, number, number] {
  switch (color.type) {
    case 'rgb':
      return [color.r, color.g, color.b];
    case 'cmyk': {
      const rgb = cmykToRgb(color);
      return [rgb.r, rgb.g, rgb.b];
    }
    case 'grayscale':
      return [color.gray, color.gray, color.gray];
  }
}

function formatNum(n: number): string {
  const s = n.toFixed(6);
  if (s.indexOf('.') !== -1) {
    let end = s.length;
    while (end > 0 && s[end - 1] === '0') end--;
    if (s[end - 1] === '.') end--;
    return s.slice(0, end);
  }
  return s;
}

function createInterpolationFunction(
  store: ObjectStore,
  c0: [number, number, number],
  c1: [number, number, number],
  domain: [number, number] = [0, 1],
): PdfRef {
  const ref = store.allocRef();
  const fnDict = pdfDict({
    FunctionType: pdfNum(2),
    Domain: pdfArray(pdfNum(domain[0]), pdfNum(domain[1])),
    C0: pdfArray(pdfNum(c0[0]), pdfNum(c0[1]), pdfNum(c0[2])),
    C1: pdfArray(pdfNum(c1[0]), pdfNum(c1[1]), pdfNum(c1[2])),
    N: pdfNum(1),
  });
  store.set(ref, fnDict);
  return ref;
}

function createStitchingFunction(
  store: ObjectStore,
  stops: GradientStop[],
): PdfRef {
  if (stops.length === 2) {
    const c0 = colorToRgbComponents(stops[0].color);
    const c1 = colorToRgbComponents(stops[1].color);
    return createInterpolationFunction(store, c0, c1);
  }

  // Create stitching function (Type 3)
  const functions: PdfObject[] = [];
  const bounds: PdfObject[] = [];
  const encode: PdfObject[] = [];

  for (let i = 0; i < stops.length - 1; i++) {
    const c0 = colorToRgbComponents(stops[i].color);
    const c1 = colorToRgbComponents(stops[i + 1].color);
    const fnRef = createInterpolationFunction(store, c0, c1);
    functions.push(fnRef);
    encode.push(pdfNum(0), pdfNum(1));

    if (i > 0) {
      bounds.push(pdfNum(stops[i].offset));
    }
  }

  const ref = store.allocRef();
  const fnDict = pdfDict({
    FunctionType: pdfNum(3),
    Domain: pdfArray(pdfNum(0), pdfNum(1)),
    Functions: pdfArray(...functions),
    Bounds: pdfArray(...bounds),
    Encode: pdfArray(...encode),
  });
  store.set(ref, fnDict);
  return ref;
}

export function createLinearGradient(
  store: ObjectStore,
  options: LinearGradientOptions,
): PdfRef {
  const { x1, y1, x2, y2, stops } = options;

  if (stops.length < 2) {
    throw new Error('Gradient requires at least 2 stops');
  }

  // Sort stops by offset
  const sortedStops = [...stops].sort((a, b) => a.offset - b.offset);

  const fnRef = createStitchingFunction(store, sortedStops);

  const shadingRef = store.allocRef();
  const shadingDict = pdfDict({
    ShadingType: pdfNum(2), // Axial shading
    ColorSpace: pdfName('DeviceRGB'),
    Coords: pdfArray(pdfNum(x1), pdfNum(y1), pdfNum(x2), pdfNum(y2)),
    Function: fnRef,
    Extend: pdfArray(
      { type: 'bool', value: true },
      { type: 'bool', value: true },
    ),
  });
  store.set(shadingRef, shadingDict);
  return shadingRef;
}

export function createRadialGradient(
  store: ObjectStore,
  options: RadialGradientOptions,
): PdfRef {
  const { cx1, cy1, r1, cx2, cy2, r2, stops } = options;

  if (stops.length < 2) {
    throw new Error('Gradient requires at least 2 stops');
  }

  const sortedStops = [...stops].sort((a, b) => a.offset - b.offset);

  const fnRef = createStitchingFunction(store, sortedStops);

  const shadingRef = store.allocRef();
  const shadingDict = pdfDict({
    ShadingType: pdfNum(3), // Radial shading
    ColorSpace: pdfName('DeviceRGB'),
    Coords: pdfArray(
      pdfNum(cx1), pdfNum(cy1), pdfNum(r1),
      pdfNum(cx2), pdfNum(cy2), pdfNum(r2),
    ),
    Function: fnRef,
    Extend: pdfArray(
      { type: 'bool', value: true },
      { type: 'bool', value: true },
    ),
  });
  store.set(shadingRef, shadingDict);
  return shadingRef;
}

export function createGradientPattern(
  store: ObjectStore,
  shadingRef: PdfRef,
  matrix?: Matrix,
): PdfRef {
  const entries: Record<string, PdfObject> = {
    Type: pdfName('Pattern'),
    PatternType: pdfNum(2), // Shading pattern
    Shading: shadingRef,
  };

  if (matrix) {
    entries['Matrix'] = pdfArray(
      pdfNum(matrix[0]), pdfNum(matrix[1]),
      pdfNum(matrix[2]), pdfNum(matrix[3]),
      pdfNum(matrix[4]), pdfNum(matrix[5]),
    );
  }

  const patternRef = store.allocRef();
  store.set(patternRef, pdfDict(entries));
  return patternRef;
}
