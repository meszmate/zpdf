import type { PdfRef, PdfDict, PdfObject } from '../core/types.js';
import type { Font } from '../font/metrics.js';
import type { Color } from '../color/color.js';
import type { DocumentOptions, LoadOptions, SaveOptions, PageOptions, ImageRef } from './types.js';
import { ObjectStore } from '../core/object-store.js';
import { createCatalog } from '../core/catalog.js';
import { createPageTreeRoot } from '../core/page-tree.js';
import { writePdf } from '../writer/pdf-writer.js';
import { pdfDict, pdfName, pdfNum, pdfStr, pdfArray, pdfBool } from '../core/objects.js';
import { formatPdfDate } from '../utils/string-utils.js';
import { PDFPage } from './page.js';

interface BookmarkEntry {
  title: string;
  pageIndex: number;
  parent?: BookmarkEntry;
  bold?: boolean;
  italic?: boolean;
  color?: Color;
  children: BookmarkEntry[];
}

interface EncryptionOptions {
  userPassword?: string;
  ownerPassword: string;
  permissions?: {
    printing?: boolean;
    modifying?: boolean;
    copying?: boolean;
    annotating?: boolean;
    fillingForms?: boolean;
    contentAccessibility?: boolean;
    documentAssembly?: boolean;
    printingHighQuality?: boolean;
  };
  algorithm?: 'rc4-40' | 'rc4-128' | 'aes-128' | 'aes-256';
}

export class PDFDocument {
  private store: ObjectStore;
  private pages: PDFPage[] = [];
  private options: DocumentOptions;

  // Metadata
  private title?: string;
  private author?: string;
  private subject?: string;
  private keywords?: string[];
  private creator?: string;
  private producer?: string;

  // Bookmarks
  private bookmarks: BookmarkEntry[] = [];

  // Encryption
  private encryptionOptions?: EncryptionOptions;

  // Font tracking: standard fonts keyed by name
  private standardFontCache: Map<string, Font> = new Map();
  private registeredFonts: Font[] = [];

  private constructor(options?: DocumentOptions) {
    this.store = new ObjectStore();
    this.options = options ?? {};

    if (options?.title) this.title = options.title;
    if (options?.author) this.author = options.author;
    if (options?.subject) this.subject = options.subject;
    if (options?.keywords) this.keywords = options.keywords;
    if (options?.creator) this.creator = options.creator;
    if (options?.producer) this.producer = options.producer;
  }

  static create(options?: DocumentOptions): PDFDocument {
    return new PDFDocument(options);
  }

  static async load(_bytes: Uint8Array, _options?: LoadOptions): Promise<PDFDocument> {
    // PDF parsing is a separate concern; this provides the API surface.
    // A full parser would read xref, trailer, decrypt if needed, and populate the store.
    throw new Error('PDFDocument.load() requires the parser module. Use the parser to load existing PDFs.');
  }

  // --- Page management ---

  addPage(options?: PageOptions): PDFPage {
    const page = new PDFPage(
      this.store,
      options,
      (opts) => this.addPage(opts), // callback for multi-page table support
    );
    this.pages.push(page);
    return page;
  }

  getPage(index: number): PDFPage {
    if (index < 0 || index >= this.pages.length) {
      throw new Error(`Page index ${index} out of bounds (0-${this.pages.length - 1})`);
    }
    return this.pages[index];
  }

  getPageCount(): number {
    return this.pages.length;
  }

  removePage(index: number): void {
    if (index < 0 || index >= this.pages.length) {
      throw new Error(`Page index ${index} out of bounds (0-${this.pages.length - 1})`);
    }
    this.pages.splice(index, 1);
  }

  insertPage(index: number, options?: PageOptions): PDFPage {
    if (index < 0 || index > this.pages.length) {
      throw new Error(`Insert index ${index} out of bounds (0-${this.pages.length})`);
    }
    const page = new PDFPage(
      this.store,
      options,
      (opts) => this.addPage(opts),
    );
    this.pages.splice(index, 0, page);
    return page;
  }

  // --- Metadata ---

  setTitle(title: string): void {
    this.title = title;
  }

  setAuthor(author: string): void {
    this.author = author;
  }

  setSubject(subject: string): void {
    this.subject = subject;
  }

  setKeywords(keywords: string[]): void {
    this.keywords = keywords;
  }

  setCreator(creator: string): void {
    this.creator = creator;
  }

  setProducer(producer: string): void {
    this.producer = producer;
  }

  getTitle(): string | undefined {
    return this.title;
  }

  getAuthor(): string | undefined {
    return this.author;
  }

  getSubject(): string | undefined {
    return this.subject;
  }

  getKeywords(): string[] | undefined {
    return this.keywords;
  }

  // --- Fonts ---

  getStandardFont(name: string): Font {
    const cached = this.standardFontCache.get(name);
    if (cached) return cached;

    // Create a standard PDF font object
    const font = createStandardFont(name, this.store);
    this.standardFontCache.set(name, font);
    this.registeredFonts.push(font);
    return font;
  }

  async embedFont(_fontBytes: Uint8Array): Promise<Font> {
    // Full font embedding requires parsing TrueType/OpenType font files,
    // extracting metrics, subsetting glyphs, and creating CIDFont objects.
    // This is the API surface; implementation would parse the font binary.
    throw new Error('Font embedding requires the font-embedder module. Use getStandardFont() for built-in fonts.');
  }

  // --- Images ---

  async embedImage(_imageBytes: Uint8Array): Promise<ImageRef> {
    // Image embedding requires parsing PNG/JPEG headers, extracting dimensions,
    // and creating XObject image streams.
    // This is the API surface; implementation would parse the image binary.
    throw new Error('Image embedding requires the image-embedder module.');
  }

  // --- Bookmarks ---

  addBookmark(
    title: string,
    pageIndex: number,
    options?: { parent?: BookmarkEntry; bold?: boolean; italic?: boolean; color?: Color },
  ): BookmarkEntry {
    const entry: BookmarkEntry = {
      title,
      pageIndex,
      parent: options?.parent,
      bold: options?.bold,
      italic: options?.italic,
      color: options?.color,
      children: [],
    };

    if (options?.parent) {
      options.parent.children.push(entry);
    } else {
      this.bookmarks.push(entry);
    }

    return entry;
  }

  // --- Encryption ---

  encrypt(options: EncryptionOptions): void {
    this.encryptionOptions = options;
  }

  // --- Save ---

  async save(options?: SaveOptions): Promise<Uint8Array> {
    const version = options?.version ?? this.options.version ?? '1.7';
    const compress = options?.compress ?? this.options.compress ?? false;

    // Use the document's store which already contains fonts and other embedded objects
    const store = this.store;

    // Allocate page tree ref first (needed by pages)
    const pageTreeRef = store.allocRef();

    // Build each page
    const pageRefs: PdfRef[] = [];
    for (const page of this.pages) {
      const { pageRef } = page._build(store, pageTreeRef);
      pageRefs.push(pageRef);
    }

    // Build page tree
    const pageTree = createPageTreeRoot(pageRefs);
    store.set(pageTreeRef, pageTree);

    // Build info dictionary
    let infoRef: PdfRef | undefined;
    if (this.title || this.author || this.subject || this.keywords || this.creator || this.producer) {
      const infoEntries: Record<string, PdfObject> = {};

      if (this.title) infoEntries['Title'] = pdfStr(this.title);
      if (this.author) infoEntries['Author'] = pdfStr(this.author);
      if (this.subject) infoEntries['Subject'] = pdfStr(this.subject);
      if (this.keywords) infoEntries['Keywords'] = pdfStr(this.keywords.join(', '));
      if (this.creator) infoEntries['Creator'] = pdfStr(this.creator);

      const producerStr = this.producer ?? 'zpdf';
      infoEntries['Producer'] = pdfStr(producerStr);

      // Creation and modification dates
      const now = formatPdfDate(new Date());
      infoEntries['CreationDate'] = pdfStr(now);
      infoEntries['ModDate'] = pdfStr(now);

      infoRef = store.allocRef();
      store.set(infoRef, pdfDict(infoEntries));
    }

    // Build outline tree (bookmarks)
    let outlinesRef: PdfRef | undefined;
    if (this.bookmarks.length > 0) {
      outlinesRef = this.buildOutlineTree(store, pageRefs);
    }

    // Build catalog
    const catalog = createCatalog(pageTreeRef, {
      outlines: outlinesRef,
    });
    const catalogRef = store.allocRef();
    store.set(catalogRef, catalog);

    // Write the PDF
    return writePdf(store, catalogRef, {
      version,
      compress,
      info: infoRef,
    });
  }

  private buildOutlineTree(store: ObjectStore, pageRefs: PdfRef[]): PdfRef {
    const outlinesRef = store.allocRef();

    // Flatten all bookmarks with their refs
    interface OutlineItem {
      entry: BookmarkEntry;
      ref: PdfRef;
      parentRef: PdfRef;
      children: OutlineItem[];
    }

    function buildItems(entries: BookmarkEntry[], parentRef: PdfRef): OutlineItem[] {
      return entries.map(entry => {
        const ref = store.allocRef();
        const item: OutlineItem = {
          entry,
          ref,
          parentRef,
          children: [],
        };
        item.children = buildItems(entry.children, ref);
        return item;
      });
    }

    const items = buildItems(this.bookmarks, outlinesRef);

    // Count total outline items
    function countItems(itemList: OutlineItem[]): number {
      let count = 0;
      for (const item of itemList) {
        count += 1 + countItems(item.children);
      }
      return count;
    }

    const totalCount = countItems(items);

    // Write outline items
    function writeItems(itemList: OutlineItem[]): void {
      for (let i = 0; i < itemList.length; i++) {
        const item = itemList[i];
        const entry = item.entry;

        const outlineEntries: Record<string, PdfObject> = {
          Title: pdfStr(entry.title),
          Parent: item.parentRef,
        };

        // Destination: page ref with XYZ fit
        const pageIdx = Math.min(entry.pageIndex, pageRefs.length - 1);
        if (pageIdx >= 0 && pageIdx < pageRefs.length) {
          outlineEntries['Dest'] = pdfArray(
            pageRefs[pageIdx],
            pdfName('XYZ'),
            pdfNum(0),
            pdfNum(0),
            pdfNum(0),
          );
        }

        // Sibling links
        if (i > 0) {
          outlineEntries['Prev'] = itemList[i - 1].ref;
        }
        if (i < itemList.length - 1) {
          outlineEntries['Next'] = itemList[i + 1].ref;
        }

        // Children links
        if (item.children.length > 0) {
          outlineEntries['First'] = item.children[0].ref;
          outlineEntries['Last'] = item.children[item.children.length - 1].ref;
          outlineEntries['Count'] = pdfNum(-item.children.length); // negative = closed
        }

        // Style flags
        let flags = 0;
        if (entry.italic) flags |= 1;
        if (entry.bold) flags |= 2;
        if (flags !== 0) {
          outlineEntries['F'] = pdfNum(flags);
        }

        // Color
        if (entry.color && entry.color.type === 'rgb') {
          outlineEntries['C'] = pdfArray(
            pdfNum(entry.color.r),
            pdfNum(entry.color.g),
            pdfNum(entry.color.b),
          );
        }

        store.set(item.ref, pdfDict(outlineEntries));

        // Recurse into children
        if (item.children.length > 0) {
          writeItems(item.children);
        }
      }
    }

    writeItems(items);

    // Write outlines root
    const outlinesEntries: Record<string, PdfObject> = {
      Type: pdfName('Outlines'),
      Count: pdfNum(totalCount),
    };
    if (items.length > 0) {
      outlinesEntries['First'] = items[0].ref;
      outlinesEntries['Last'] = items[items.length - 1].ref;
    }
    store.set(outlinesRef, pdfDict(outlinesEntries));

    return outlinesRef;
  }
}

/**
 * Create a standard PDF font (one of the 14 base fonts).
 * Returns a Font object with metrics and encoding.
 */
function createStandardFont(name: string, store: ObjectStore): Font {
  // Map common names to PDF standard font names
  const fontNameMap: Record<string, string> = {
    'Helvetica': 'Helvetica',
    'Helvetica-Bold': 'Helvetica-Bold',
    'Helvetica-Oblique': 'Helvetica-Oblique',
    'Helvetica-BoldOblique': 'Helvetica-BoldOblique',
    'Times-Roman': 'Times-Roman',
    'Times-Bold': 'Times-Bold',
    'Times-Italic': 'Times-Italic',
    'Times-BoldItalic': 'Times-BoldItalic',
    'Courier': 'Courier',
    'Courier-Bold': 'Courier-Bold',
    'Courier-Oblique': 'Courier-Oblique',
    'Courier-BoldOblique': 'Courier-BoldOblique',
    'Symbol': 'Symbol',
    'ZapfDingbats': 'ZapfDingbats',
  };

  const pdfFontName = fontNameMap[name] ?? name;

  // Create font dictionary
  const fontDict = pdfDict({
    Type: pdfName('Font'),
    Subtype: pdfName('Type1'),
    BaseFont: pdfName(pdfFontName),
    Encoding: pdfName('WinAnsiEncoding'),
  });

  const fontRef = store.allocRef();
  store.set(fontRef, fontDict);

  // Standard font metrics (approximate values for Helvetica family)
  // Real implementations would load AFM data
  const metricsData = getStandardFontMetrics(pdfFontName);

  const font: Font = {
    name: pdfFontName,
    ref: fontRef,
    metrics: metricsData,
    isStandard: true,

    encode(text: string): Uint8Array {
      // WinAnsi encoding
      const bytes = new Uint8Array(text.length);
      for (let i = 0; i < text.length; i++) {
        const code = text.charCodeAt(i);
        bytes[i] = code <= 0xff ? code : 0x3f; // '?' for unmappable
      }
      return bytes;
    },

    measureWidth(text: string, fontSize: number): number {
      let width = 0;
      for (let i = 0; i < text.length; i++) {
        const code = text.charCodeAt(i);
        const charWidth = metricsData.widths.get(code) ?? metricsData.defaultWidth;
        width += charWidth;
      }
      return (width / metricsData.unitsPerEm) * fontSize;
    },

    getLineHeight(fontSize: number): number {
      const { ascent, descent, lineGap } = metricsData;
      return ((ascent - descent + lineGap) / metricsData.unitsPerEm) * fontSize;
    },
  };

  return font;
}

function getStandardFontMetrics(fontName: string): import('../font/metrics.js').FontMetrics {
  // Provide approximate metrics for standard fonts.
  // In a full implementation these would come from AFM files.

  const isCourier = fontName.startsWith('Courier');
  const isTimes = fontName.startsWith('Times');
  const isSymbol = fontName === 'Symbol';
  const isZapf = fontName === 'ZapfDingbats';
  const isBold = fontName.includes('Bold');

  // Build a basic width table
  const widths = new Map<number, number>();

  if (isCourier) {
    // Courier is monospaced at 600 units
    for (let i = 0; i < 256; i++) {
      widths.set(i, 600);
    }
    return {
      ascent: 629,
      descent: -157,
      lineGap: 0,
      unitsPerEm: 1000,
      bbox: [-23, -250, 715, 805],
      italicAngle: fontName.includes('Oblique') ? -12 : 0,
      capHeight: 562,
      xHeight: 426,
      stemV: isBold ? 106 : 51,
      flags: 0x21, // FixedPitch + Nonsymbolic
      defaultWidth: 600,
      widths,
    };
  }

  if (isTimes) {
    // Times Roman approximate widths
    const defaultW = isBold ? 560 : 500;
    for (let i = 0; i < 256; i++) {
      widths.set(i, defaultW);
    }
    // Override common character widths
    setTimesWidths(widths, isBold);

    return {
      ascent: 683,
      descent: -217,
      lineGap: 0,
      unitsPerEm: 1000,
      bbox: [-168, -218, 1000, 898],
      italicAngle: fontName.includes('Italic') ? -15 : 0,
      capHeight: 662,
      xHeight: 450,
      stemV: isBold ? 139 : 87,
      flags: 0x02, // Nonsymbolic
      defaultWidth: defaultW,
      widths,
    };
  }

  if (isSymbol || isZapf) {
    for (let i = 0; i < 256; i++) {
      widths.set(i, 500);
    }
    return {
      ascent: 800,
      descent: -200,
      lineGap: 0,
      unitsPerEm: 1000,
      bbox: [0, -200, 1000, 800],
      italicAngle: 0,
      capHeight: 700,
      xHeight: 500,
      stemV: 85,
      flags: 0x04, // Symbolic
      defaultWidth: 500,
      widths,
    };
  }

  // Helvetica (default)
  const defaultW = isBold ? 590 : 556;
  for (let i = 0; i < 256; i++) {
    widths.set(i, defaultW);
  }
  setHelveticaWidths(widths, isBold);

  return {
    ascent: 718,
    descent: -207,
    lineGap: 0,
    unitsPerEm: 1000,
    bbox: [-166, -225, 1000, 931],
    italicAngle: fontName.includes('Oblique') ? -12 : 0,
    capHeight: 718,
    xHeight: 523,
    stemV: isBold ? 140 : 88,
    flags: 0x20, // Nonsymbolic
    defaultWidth: defaultW,
    widths,
  };
}

function setHelveticaWidths(widths: Map<number, number>, bold: boolean): void {
  // Key character widths for Helvetica / Helvetica-Bold
  const w = bold
    ? {
        space: 278, exclam: 333, quotedbl: 474, numbersign: 556, dollar: 556,
        percent: 889, ampersand: 722, quotesingle: 238, parenleft: 333,
        parenright: 333, asterisk: 389, plus: 584, comma: 278, hyphen: 333,
        period: 278, slash: 278, zero: 556, one: 556, two: 556, three: 556,
        four: 556, five: 556, six: 556, seven: 556, eight: 556, nine: 556,
        colon: 333, semicolon: 333, less: 584, equal: 584, greater: 584,
        question: 611, at: 975, A: 722, B: 722, C: 722, D: 722, E: 667,
        F: 611, G: 778, H: 722, I: 278, J: 556, K: 722, L: 611, M: 833,
        N: 722, O: 778, P: 667, Q: 778, R: 722, S: 667, T: 611, U: 722,
        V: 667, W: 944, X: 667, Y: 667, Z: 611, bracketleft: 333,
        backslash: 278, bracketright: 333, asciicircum: 584, underscore: 556,
        grave: 333, a: 556, b: 611, c: 556, d: 611, e: 556, f: 333,
        g: 611, h: 611, i: 278, j: 278, k: 556, l: 278, m: 889, n: 611,
        o: 611, p: 611, q: 611, r: 389, s: 556, t: 333, u: 611, v: 556,
        w: 778, x: 556, y: 556, z: 500,
      }
    : {
        space: 278, exclam: 278, quotedbl: 355, numbersign: 556, dollar: 556,
        percent: 889, ampersand: 667, quotesingle: 191, parenleft: 333,
        parenright: 333, asterisk: 389, plus: 584, comma: 278, hyphen: 333,
        period: 278, slash: 278, zero: 556, one: 556, two: 556, three: 556,
        four: 556, five: 556, six: 556, seven: 556, eight: 556, nine: 556,
        colon: 278, semicolon: 278, less: 584, equal: 584, greater: 584,
        question: 556, at: 1015, A: 667, B: 667, C: 722, D: 722, E: 667,
        F: 611, G: 778, H: 722, I: 278, J: 500, K: 667, L: 556, M: 833,
        N: 722, O: 778, P: 667, Q: 778, R: 722, S: 667, T: 611, U: 722,
        V: 667, W: 944, X: 667, Y: 667, Z: 611, bracketleft: 278,
        backslash: 278, bracketright: 278, asciicircum: 469, underscore: 556,
        grave: 333, a: 556, b: 556, c: 500, d: 556, e: 556, f: 278,
        g: 556, h: 556, i: 222, j: 222, k: 500, l: 222, m: 833, n: 556,
        o: 556, p: 556, q: 556, r: 333, s: 500, t: 278, u: 556, v: 500,
        w: 722, x: 500, y: 500, z: 500,
      };

  widths.set(32, w.space);
  widths.set(33, w.exclam);
  widths.set(34, w.quotedbl);
  widths.set(35, w.numbersign);
  widths.set(36, w.dollar);
  widths.set(37, w.percent);
  widths.set(38, w.ampersand);
  widths.set(39, w.quotesingle);
  widths.set(40, w.parenleft);
  widths.set(41, w.parenright);
  widths.set(42, w.asterisk);
  widths.set(43, w.plus);
  widths.set(44, w.comma);
  widths.set(45, w.hyphen);
  widths.set(46, w.period);
  widths.set(47, w.slash);
  widths.set(48, w.zero);
  widths.set(49, w.one);
  widths.set(50, w.two);
  widths.set(51, w.three);
  widths.set(52, w.four);
  widths.set(53, w.five);
  widths.set(54, w.six);
  widths.set(55, w.seven);
  widths.set(56, w.eight);
  widths.set(57, w.nine);
  widths.set(58, w.colon);
  widths.set(59, w.semicolon);
  widths.set(60, w.less);
  widths.set(61, w.equal);
  widths.set(62, w.greater);
  widths.set(63, w.question);
  widths.set(64, w.at);

  // Uppercase A-Z (65-90)
  const upper = [w.A, w.B, w.C, w.D, w.E, w.F, w.G, w.H, w.I, w.J, w.K, w.L, w.M, w.N, w.O, w.P, w.Q, w.R, w.S, w.T, w.U, w.V, w.W, w.X, w.Y, w.Z];
  for (let i = 0; i < 26; i++) {
    widths.set(65 + i, upper[i]);
  }

  widths.set(91, w.bracketleft);
  widths.set(92, w.backslash);
  widths.set(93, w.bracketright);
  widths.set(94, w.asciicircum);
  widths.set(95, w.underscore);
  widths.set(96, w.grave);

  // Lowercase a-z (97-122)
  const lower = [w.a, w.b, w.c, w.d, w.e, w.f, w.g, w.h, w.i, w.j, w.k, w.l, w.m, w.n, w.o, w.p, w.q, w.r, w.s, w.t, w.u, w.v, w.w, w.x, w.y, w.z];
  for (let i = 0; i < 26; i++) {
    widths.set(97 + i, lower[i]);
  }
}

function setTimesWidths(widths: Map<number, number>, bold: boolean): void {
  const w = bold
    ? {
        space: 250, exclam: 333, quotedbl: 555, numbersign: 500, dollar: 500,
        percent: 1000, ampersand: 833, quotesingle: 278, parenleft: 333,
        parenright: 333, asterisk: 500, plus: 570, comma: 250, hyphen: 333,
        period: 250, slash: 278, zero: 500, one: 500, two: 500, three: 500,
        four: 500, five: 500, six: 500, seven: 500, eight: 500, nine: 500,
        colon: 333, semicolon: 333, A: 722, B: 667, C: 722, D: 722, E: 667,
        F: 611, G: 778, H: 778, I: 389, J: 500, K: 778, L: 667, M: 944,
        N: 722, O: 778, P: 611, Q: 778, R: 722, S: 556, T: 667, U: 722,
        V: 722, W: 1000, X: 722, Y: 722, Z: 667,
        a: 500, b: 556, c: 444, d: 556, e: 444, f: 333, g: 500, h: 556,
        i: 278, j: 333, k: 556, l: 278, m: 833, n: 556, o: 500, p: 556,
        q: 556, r: 444, s: 389, t: 333, u: 556, v: 500, w: 722, x: 500,
        y: 500, z: 444,
      }
    : {
        space: 250, exclam: 333, quotedbl: 408, numbersign: 500, dollar: 500,
        percent: 833, ampersand: 778, quotesingle: 180, parenleft: 333,
        parenright: 333, asterisk: 500, plus: 564, comma: 250, hyphen: 333,
        period: 250, slash: 278, zero: 500, one: 500, two: 500, three: 500,
        four: 500, five: 500, six: 500, seven: 500, eight: 500, nine: 500,
        colon: 278, semicolon: 278, A: 722, B: 667, C: 667, D: 722, E: 611,
        F: 556, G: 722, H: 722, I: 333, J: 389, K: 722, L: 611, M: 889,
        N: 722, O: 722, P: 556, Q: 722, R: 667, S: 556, T: 611, U: 722,
        V: 722, W: 944, X: 722, Y: 722, Z: 611,
        a: 444, b: 500, c: 444, d: 500, e: 444, f: 333, g: 500, h: 500,
        i: 278, j: 278, k: 500, l: 278, m: 778, n: 500, o: 500, p: 500,
        q: 500, r: 333, s: 389, t: 278, u: 500, v: 500, w: 722, x: 500,
        y: 500, z: 444,
      };

  widths.set(32, w.space);
  widths.set(33, w.exclam);
  widths.set(34, w.quotedbl);
  widths.set(35, w.numbersign);
  widths.set(36, w.dollar);
  widths.set(37, w.percent);
  widths.set(38, w.ampersand);
  widths.set(39, w.quotesingle);
  widths.set(40, w.parenleft);
  widths.set(41, w.parenright);
  widths.set(42, w.asterisk);
  widths.set(43, w.plus);
  widths.set(44, w.comma);
  widths.set(45, w.hyphen);
  widths.set(46, w.period);
  widths.set(47, w.slash);
  for (let i = 0; i <= 9; i++) widths.set(48 + i, w.zero);
  widths.set(58, w.colon);
  widths.set(59, w.semicolon);

  const upper = [w.A, w.B, w.C, w.D, w.E, w.F, w.G, w.H, w.I, w.J, w.K, w.L, w.M, w.N, w.O, w.P, w.Q, w.R, w.S, w.T, w.U, w.V, w.W, w.X, w.Y, w.Z];
  for (let i = 0; i < 26; i++) widths.set(65 + i, upper[i]);

  const lower = [w.a, w.b, w.c, w.d, w.e, w.f, w.g, w.h, w.i, w.j, w.k, w.l, w.m, w.n, w.o, w.p, w.q, w.r, w.s, w.t, w.u, w.v, w.w, w.x, w.y, w.z];
  for (let i = 0; i < 26; i++) widths.set(97 + i, lower[i]);
}
