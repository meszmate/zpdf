/**
 * Standard 14 PDF fonts with complete glyph width tables from AFM data.
 * All widths are in units per 1000 em.
 */
import type { Font, FontMetrics } from './metrics.js';
import { encodeWinAnsi } from './encoding.js';

export type StandardFontName =
  | 'Helvetica' | 'Helvetica-Bold' | 'Helvetica-Oblique' | 'Helvetica-BoldOblique'
  | 'Times-Roman' | 'Times-Bold' | 'Times-Italic' | 'Times-BoldItalic'
  | 'Courier' | 'Courier-Bold' | 'Courier-Oblique' | 'Courier-BoldOblique'
  | 'Symbol' | 'ZapfDingbats';

export const STANDARD_FONT_NAMES: string[] = [
  'Helvetica', 'Helvetica-Bold', 'Helvetica-Oblique', 'Helvetica-BoldOblique',
  'Times-Roman', 'Times-Bold', 'Times-Italic', 'Times-BoldItalic',
  'Courier', 'Courier-Bold', 'Courier-Oblique', 'Courier-BoldOblique',
  'Symbol', 'ZapfDingbats',
];

// --------------------------------------------------------------------------
// Complete WinAnsi width tables (character codes 0-255)
// Source: Adobe AFM files for the standard 14 fonts
// --------------------------------------------------------------------------

// Helvetica widths (WinAnsi encoding, codes 0-255)
const HELVETICA_WIDTHS: number[] = [
  // 0-31: control characters
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  // 32-127
  278,278,355,556,556,889,667,191,333,333,389,584,278,333,278,278,
  556,556,556,556,556,556,556,556,556,556,278,278,584,584,584,556,
  1015,667,667,722,722,667,611,778,722,278,500,667,556,833,722,778,
  667,778,722,667,611,722,667,944,667,667,611,278,278,278,469,556,
  333,556,556,500,556,556,278,556,556,222,222,500,222,833,556,556,
  556,556,333,500,278,556,500,722,500,500,500,334,260,334,584,0,
  // 128-159: WinAnsi specials
  556,0,222,556,333,1000,556,556,333,1000,667,333,1000,0,611,0,
  0,222,222,333,333,350,556,1000,333,1000,500,333,944,0,500,667,
  // 160-255
  278,333,556,556,556,556,260,556,333,737,370,556,584,333,737,333,
  400,584,333,333,333,556,537,278,333,333,365,556,834,834,834,611,
  667,667,667,667,667,667,1000,722,667,667,667,667,278,278,278,278,
  722,722,778,778,778,778,778,584,778,722,722,722,722,667,667,611,
  556,556,556,556,556,556,889,500,556,556,556,556,278,278,278,278,
  556,556,556,556,556,556,556,584,611,556,556,556,556,500,556,500,
];

// Helvetica-Bold widths
const HELVETICA_BOLD_WIDTHS: number[] = [
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  278,333,474,556,556,889,722,238,333,333,389,584,278,333,278,278,
  556,556,556,556,556,556,556,556,556,556,333,333,584,584,584,611,
  975,722,722,722,722,667,611,778,722,278,556,722,611,833,722,778,
  667,778,722,667,611,722,667,944,667,667,611,333,278,333,584,556,
  333,556,611,556,611,556,333,611,611,278,278,556,278,889,611,611,
  611,611,389,556,333,611,556,778,556,556,500,389,280,389,584,0,
  556,0,278,556,500,1000,556,556,333,1000,667,333,1000,0,611,0,
  0,278,278,500,500,350,556,1000,333,1000,556,333,944,0,500,667,
  278,333,556,556,556,556,280,556,333,737,370,556,584,333,737,333,
  400,584,333,333,333,611,556,278,333,333,365,556,834,834,834,611,
  722,722,722,722,722,722,1000,722,667,667,667,667,278,278,278,278,
  722,722,778,778,778,778,778,584,778,722,722,722,722,667,667,611,
  556,556,556,556,556,556,889,556,556,556,556,556,278,278,278,278,
  611,611,611,611,611,611,611,584,611,611,611,611,611,556,611,556,
];

// Helvetica-Oblique (same widths as Helvetica)
const HELVETICA_OBLIQUE_WIDTHS: number[] = HELVETICA_WIDTHS.slice();

// Helvetica-BoldOblique (same widths as Helvetica-Bold)
const HELVETICA_BOLDOBLIQUE_WIDTHS: number[] = HELVETICA_BOLD_WIDTHS.slice();

// Times-Roman widths
const TIMES_ROMAN_WIDTHS: number[] = [
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  250,333,408,500,500,833,778,180,333,333,500,564,250,333,250,278,
  500,500,500,500,500,500,500,500,500,500,278,278,564,564,564,444,
  921,722,667,667,722,611,556,722,722,333,389,722,611,889,722,722,
  556,722,667,556,611,722,722,944,722,722,611,333,278,333,469,500,
  333,444,500,444,500,444,333,500,500,278,278,500,278,778,500,500,
  500,500,333,389,278,500,500,722,500,500,444,480,200,480,541,0,
  500,0,333,500,444,1000,500,500,333,1000,556,333,889,0,611,0,
  0,333,333,444,444,350,500,1000,333,1000,389,333,722,0,444,722,
  250,333,500,500,500,500,200,500,333,760,276,500,564,333,760,333,
  400,564,300,300,333,500,453,250,333,300,310,500,750,750,750,444,
  722,722,722,722,722,722,889,667,611,611,611,611,333,333,333,333,
  722,722,722,722,722,722,722,564,722,722,722,722,722,722,556,500,
  444,444,444,444,444,444,667,444,444,444,444,444,278,278,278,278,
  500,500,500,500,500,500,500,564,500,500,500,500,500,500,500,500,
];

// Times-Bold widths
const TIMES_BOLD_WIDTHS: number[] = [
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  250,333,555,500,500,1000,833,278,333,333,500,570,250,333,250,278,
  500,500,500,500,500,500,500,500,500,500,333,333,570,570,570,500,
  930,722,667,722,722,667,611,778,778,389,500,778,667,944,722,778,
  611,778,722,556,667,722,722,1000,722,722,667,333,278,333,581,500,
  333,500,556,444,556,444,333,500,556,278,333,556,278,833,556,500,
  556,556,444,389,333,556,500,722,500,500,444,394,220,394,520,0,
  500,0,333,500,500,1000,500,500,333,1000,556,333,1000,0,667,0,
  0,333,333,500,500,350,500,1000,333,1000,389,333,722,0,444,722,
  250,333,500,500,500,500,220,500,333,747,300,500,570,333,747,333,
  400,570,300,300,333,556,500,250,333,300,330,500,750,750,750,500,
  722,722,722,722,722,722,1000,722,667,667,667,667,389,389,389,389,
  722,722,778,778,778,778,778,570,778,722,722,722,722,722,611,556,
  500,500,500,500,500,500,722,444,444,444,444,444,278,278,278,278,
  500,556,500,500,500,500,500,570,500,556,556,556,556,500,556,500,
];

// Times-Italic widths
const TIMES_ITALIC_WIDTHS: number[] = [
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  250,333,420,500,500,833,778,214,333,333,500,675,250,333,250,278,
  500,500,500,500,500,500,500,500,500,500,333,333,675,675,675,500,
  920,611,611,667,722,611,611,722,722,333,444,667,556,833,667,722,
  611,722,611,500,556,722,611,833,611,556,556,389,278,389,422,500,
  333,500,500,444,500,444,278,500,500,278,278,444,278,722,500,500,
  500,500,389,389,278,500,444,667,444,444,389,400,275,400,541,0,
  500,0,333,500,556,889,500,500,333,1000,500,333,944,0,556,0,
  0,333,333,556,556,350,500,889,333,980,389,333,667,0,389,556,
  250,389,500,500,500,500,275,500,333,760,276,500,675,333,760,333,
  400,675,300,300,333,500,523,250,333,300,310,500,750,750,750,500,
  611,611,611,611,611,611,889,667,611,611,611,611,333,333,333,333,
  722,667,722,722,722,722,722,675,722,722,722,722,722,556,611,500,
  500,500,500,500,500,500,667,444,444,444,444,444,278,278,278,278,
  500,500,500,500,500,500,500,675,500,500,500,500,500,444,500,444,
];

// Times-BoldItalic widths
const TIMES_BOLDITALIC_WIDTHS: number[] = [
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  250,389,555,500,500,833,778,278,333,333,500,570,250,333,250,278,
  500,500,500,500,500,500,500,500,500,500,333,333,570,570,570,500,
  832,667,667,667,722,667,667,722,778,389,500,667,611,889,722,722,
  611,722,667,556,611,722,667,889,667,611,611,333,278,333,570,500,
  333,500,500,444,500,444,333,500,556,278,278,500,278,778,556,500,
  500,500,389,389,278,556,444,667,500,444,389,348,220,348,570,0,
  500,0,333,500,500,1000,500,500,333,1000,556,333,944,0,611,0,
  0,333,333,500,500,350,500,1000,333,1000,389,333,722,0,389,611,
  250,389,500,500,500,500,220,500,333,747,266,500,606,333,747,333,
  400,570,300,300,333,576,500,250,333,300,300,500,750,750,750,500,
  667,667,667,667,667,667,944,667,667,667,667,667,389,389,389,389,
  722,722,722,722,722,722,722,570,722,722,722,722,722,611,611,500,
  500,500,500,500,500,500,722,444,444,444,444,444,278,278,278,278,
  500,556,500,500,500,500,500,570,500,556,556,556,556,444,500,444,
];

// Courier (monospaced - all printable glyphs 600)
const COURIER_WIDTHS: number[] = new Array(256).fill(600);
for (let i = 0; i < 32; i++) COURIER_WIDTHS[i] = 0;
COURIER_WIDTHS[127] = 0;
COURIER_WIDTHS[129] = 0;
COURIER_WIDTHS[141] = 0;
COURIER_WIDTHS[143] = 0;
COURIER_WIDTHS[144] = 0;
COURIER_WIDTHS[157] = 0;

const COURIER_BOLD_WIDTHS: number[] = COURIER_WIDTHS.slice();
const COURIER_OBLIQUE_WIDTHS: number[] = COURIER_WIDTHS.slice();
const COURIER_BOLDOBLIQUE_WIDTHS: number[] = COURIER_WIDTHS.slice();

// Symbol font widths (Symbol encoding)
const SYMBOL_WIDTHS: number[] = [
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  250,333,713,500,549,833,778,439,333,333,500,549,250,549,250,278,
  500,500,500,500,500,500,500,500,500,500,278,278,549,549,549,444,
  549,722,667,722,612,611,763,603,722,333,631,722,686,889,722,722,
  768,741,556,592,611,690,439,768,645,795,611,333,863,333,658,500,
  500,631,549,549,494,439,521,411,603,329,603,549,549,576,521,549,
  549,521,549,603,439,576,713,686,493,686,494,480,200,480,549,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  250,620,247,549,167,713,500,753,753,753,753,1042,987,603,987,603,
  400,549,411,549,549,713,494,460,549,549,549,549,1000,603,1000,658,
  823,686,795,987,768,768,823,768,768,713,713,713,713,713,713,713,
  768,713,790,790,890,823,549,250,713,603,603,1042,987,603,987,603,
  494,329,790,790,786,713,384,384,384,384,384,384,494,494,494,494,
  0,329,274,686,686,686,384,384,384,384,384,384,494,494,494,0,
];

// ZapfDingbats widths
const ZAPFDINGBATS_WIDTHS: number[] = [
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  278,974,961,974,980,719,789,790,791,690,960,939,549,855,911,933,
  911,945,974,755,846,762,761,571,677,763,760,759,754,494,552,537,
  577,692,786,788,788,790,793,794,816,823,789,841,823,833,816,831,
  923,744,723,749,790,792,695,776,768,792,759,707,708,682,701,826,
  815,789,789,707,687,696,689,786,787,713,791,785,791,873,761,762,
  762,759,759,892,892,788,784,438,138,277,415,392,392,668,668,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  278,390,549,549,549,549,549,549,549,549,549,549,549,549,549,549,
  549,549,549,549,549,549,549,549,549,549,549,549,549,549,549,549,
  549,549,549,549,549,549,549,549,549,549,549,549,549,549,549,549,
  549,549,549,549,549,549,549,549,549,549,549,549,549,549,549,549,
  549,549,549,549,549,549,549,549,549,549,549,549,549,549,549,549,
  549,549,549,549,549,549,549,549,549,549,549,549,549,549,549,549,
];

// --------------------------------------------------------------------------
// Font metrics data from AFM files
// --------------------------------------------------------------------------

interface StandardFontData {
  widths: number[];
  ascent: number;
  descent: number;
  lineGap: number;
  bbox: [number, number, number, number];
  italicAngle: number;
  capHeight: number;
  xHeight: number;
  stemV: number;
  flags: number;
  defaultWidth: number;
  isSymbolic: boolean;
}

const FONT_DATA: Record<string, StandardFontData> = {
  'Helvetica': {
    widths: HELVETICA_WIDTHS,
    ascent: 718, descent: -207, lineGap: 0,
    bbox: [-166, -225, 1000, 931],
    italicAngle: 0, capHeight: 718, xHeight: 523, stemV: 88,
    flags: 0x20, // nonsymbolic
    defaultWidth: 278,
    isSymbolic: false,
  },
  'Helvetica-Bold': {
    widths: HELVETICA_BOLD_WIDTHS,
    ascent: 718, descent: -207, lineGap: 0,
    bbox: [-170, -228, 1003, 962],
    italicAngle: 0, capHeight: 718, xHeight: 532, stemV: 140,
    flags: 0x40020, // nonsymbolic + forceBold
    defaultWidth: 278,
    isSymbolic: false,
  },
  'Helvetica-Oblique': {
    widths: HELVETICA_OBLIQUE_WIDTHS,
    ascent: 718, descent: -207, lineGap: 0,
    bbox: [-170, -225, 1116, 931],
    italicAngle: -12, capHeight: 718, xHeight: 523, stemV: 88,
    flags: 0x60, // nonsymbolic + italic
    defaultWidth: 278,
    isSymbolic: false,
  },
  'Helvetica-BoldOblique': {
    widths: HELVETICA_BOLDOBLIQUE_WIDTHS,
    ascent: 718, descent: -207, lineGap: 0,
    bbox: [-174, -228, 1114, 962],
    italicAngle: -12, capHeight: 718, xHeight: 532, stemV: 140,
    flags: 0x40060, // nonsymbolic + italic + forceBold
    defaultWidth: 278,
    isSymbolic: false,
  },
  'Times-Roman': {
    widths: TIMES_ROMAN_WIDTHS,
    ascent: 683, descent: -217, lineGap: 0,
    bbox: [-168, -218, 1000, 898],
    italicAngle: 0, capHeight: 662, xHeight: 450, stemV: 84,
    flags: 0x22, // nonsymbolic + serif
    defaultWidth: 250,
    isSymbolic: false,
  },
  'Times-Bold': {
    widths: TIMES_BOLD_WIDTHS,
    ascent: 683, descent: -217, lineGap: 0,
    bbox: [-168, -218, 1000, 935],
    italicAngle: 0, capHeight: 676, xHeight: 461, stemV: 139,
    flags: 0x40022, // nonsymbolic + serif + forceBold
    defaultWidth: 250,
    isSymbolic: false,
  },
  'Times-Italic': {
    widths: TIMES_ITALIC_WIDTHS,
    ascent: 683, descent: -217, lineGap: 0,
    bbox: [-169, -217, 1010, 883],
    italicAngle: -15.5, capHeight: 653, xHeight: 441, stemV: 76,
    flags: 0x62, // nonsymbolic + serif + italic
    defaultWidth: 250,
    isSymbolic: false,
  },
  'Times-BoldItalic': {
    widths: TIMES_BOLDITALIC_WIDTHS,
    ascent: 683, descent: -217, lineGap: 0,
    bbox: [-200, -218, 996, 921],
    italicAngle: -15, capHeight: 669, xHeight: 462, stemV: 121,
    flags: 0x40062, // nonsymbolic + serif + italic + forceBold
    defaultWidth: 250,
    isSymbolic: false,
  },
  'Courier': {
    widths: COURIER_WIDTHS,
    ascent: 629, descent: -157, lineGap: 0,
    bbox: [-23, -250, 715, 805],
    italicAngle: 0, capHeight: 562, xHeight: 426, stemV: 51,
    flags: 0x21, // nonsymbolic + fixedPitch
    defaultWidth: 600,
    isSymbolic: false,
  },
  'Courier-Bold': {
    widths: COURIER_BOLD_WIDTHS,
    ascent: 629, descent: -157, lineGap: 0,
    bbox: [-113, -250, 749, 801],
    italicAngle: 0, capHeight: 562, xHeight: 439, stemV: 106,
    flags: 0x40021, // nonsymbolic + fixedPitch + forceBold
    defaultWidth: 600,
    isSymbolic: false,
  },
  'Courier-Oblique': {
    widths: COURIER_OBLIQUE_WIDTHS,
    ascent: 629, descent: -157, lineGap: 0,
    bbox: [-27, -250, 849, 805],
    italicAngle: -12, capHeight: 562, xHeight: 426, stemV: 51,
    flags: 0x61, // nonsymbolic + fixedPitch + italic
    defaultWidth: 600,
    isSymbolic: false,
  },
  'Courier-BoldOblique': {
    widths: COURIER_BOLDOBLIQUE_WIDTHS,
    ascent: 629, descent: -157, lineGap: 0,
    bbox: [-57, -250, 869, 801],
    italicAngle: -12, capHeight: 562, xHeight: 439, stemV: 106,
    flags: 0x40061, // nonsymbolic + fixedPitch + italic + forceBold
    defaultWidth: 600,
    isSymbolic: false,
  },
  'Symbol': {
    widths: SYMBOL_WIDTHS,
    ascent: 1010, descent: -293, lineGap: 0,
    bbox: [-180, -293, 1090, 1010],
    italicAngle: 0, capHeight: 1010, xHeight: 0, stemV: 85,
    flags: 0x04, // symbolic
    defaultWidth: 250,
    isSymbolic: true,
  },
  'ZapfDingbats': {
    widths: ZAPFDINGBATS_WIDTHS,
    ascent: 820, descent: -143, lineGap: 0,
    bbox: [-1, -143, 981, 820],
    italicAngle: 0, capHeight: 820, xHeight: 0, stemV: 90,
    flags: 0x04, // symbolic
    defaultWidth: 278,
    isSymbolic: true,
  },
};

// --------------------------------------------------------------------------
// Create Font objects
// --------------------------------------------------------------------------

function widthArrayToMap(widths: number[]): Map<number, number> {
  const map = new Map<number, number>();
  for (let i = 0; i < widths.length; i++) {
    if (widths[i] !== 0) {
      map.set(i, widths[i]);
    }
  }
  return map;
}

function createStandardFont(name: string, data: StandardFontData): Font {
  const widthMap = widthArrayToMap(data.widths);
  const metrics: FontMetrics = {
    ascent: data.ascent,
    descent: data.descent,
    lineGap: data.lineGap,
    unitsPerEm: 1000,
    bbox: data.bbox,
    italicAngle: data.italicAngle,
    capHeight: data.capHeight,
    xHeight: data.xHeight,
    stemV: data.stemV,
    flags: data.flags,
    defaultWidth: data.defaultWidth,
    widths: widthMap,
  };

  const widthsArr = data.widths;
  const isSymbolic = data.isSymbolic;

  return {
    name,
    ref: null,
    metrics,
    isStandard: true,

    encode(text: string): Uint8Array {
      if (isSymbolic) {
        // Symbol and ZapfDingbats use their own encoding (identity for byte values)
        const result = new Uint8Array(text.length);
        for (let i = 0; i < text.length; i++) {
          result[i] = text.charCodeAt(i) & 0xff;
        }
        return result;
      }
      return encodeWinAnsi(text);
    },

    measureWidth(text: string, fontSize: number): number {
      let totalWidth = 0;
      const encoded = this.encode(text);
      for (let i = 0; i < encoded.length; i++) {
        const code = encoded[i];
        const w = widthsArr[code];
        totalWidth += w !== undefined ? w : data.defaultWidth;
      }
      return (totalWidth / 1000) * fontSize;
    },

    getLineHeight(fontSize: number): number {
      const ascent = data.ascent;
      const descent = data.descent;
      const gap = data.lineGap;
      return ((ascent - descent + gap) / 1000) * fontSize;
    },
  };
}

// Build the StandardFonts map
const fontMap = new Map<string, Font>();
for (const [name, data] of Object.entries(FONT_DATA)) {
  fontMap.set(name, createStandardFont(name, data));
}

export const StandardFonts: Record<string, Font> = Object.fromEntries(fontMap);

export function getStandardFont(name: string): Font | undefined {
  return fontMap.get(name);
}
