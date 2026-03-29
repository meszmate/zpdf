/**
 * High-level font management for zpdf.
 * Caches fonts, tracks character usage, and handles embedding.
 */

import type { PdfRef } from '../core/types.js';
import type { ObjectStore } from '../core/object-store.js';
import type { Font } from './metrics.js';
import type { StandardFontName } from './standard-fonts.js';
import { getStandardFont, STANDARD_FONT_NAMES } from './standard-fonts.js';
import { embedStandardFont, embedTrueTypeFont } from './font-embedder.js';
import { parseTrueTypeFont, type TrueTypeFontData } from './truetype-parser.js';

/** A Font that is guaranteed to have a non-null ref (has been embedded). */
export type EmbeddedFont = Font & { ref: PdfRef };

/**
 * Internal record for an embedded TrueType font.
 * Tracks used characters so the font can be re-subset on final save if needed.
 */
interface TrueTypeFontRecord {
  fontData: Uint8Array;
  parsedFont: TrueTypeFontData;
  usedChars: Set<number>;
  font: EmbeddedFont;
  /** SHA-like fingerprint for dedup based on first bytes of font data */
  fingerprint: string;
}

/**
 * FontManager handles loading, caching, and embedding fonts into a PDF.
 */
export class FontManager {
  private store: ObjectStore;
  private standardFontCache: Map<string, EmbeddedFont> = new Map();
  private ttfCache: Map<string, TrueTypeFontRecord> = new Map();

  constructor(store: ObjectStore) {
    this.store = store;
  }

  /**
   * Get a standard PDF font (one of the 14 built-in fonts).
   * The font is embedded (allocated a PDF ref) on first use and cached.
   */
  getStandardFont(fontName: StandardFontName): EmbeddedFont {
    const cached = this.standardFontCache.get(fontName);
    if (cached) return cached;

    const font = getStandardFont(fontName);
    if (!font) {
      throw new Error(`Unknown standard font: ${fontName}. Valid names: ${STANDARD_FONT_NAMES.join(', ')}`);
    }

    const ref = embedStandardFont(this.store, fontName);
    const embeddedFont: EmbeddedFont = {
      ...font,
      ref,
    };

    this.standardFontCache.set(fontName, embeddedFont);
    return embeddedFont;
  }

  /**
   * Embed a TrueType font from raw .ttf file bytes.
   * Returns a Font object with a PDF reference.
   *
   * The font is deduplicated by a fingerprint of the font data.
   * If the same font bytes are embedded twice, the same Font object is returned
   * (but newly used characters are tracked).
   */
  embedFont(fontBytes: Uint8Array): EmbeddedFont {
    const fingerprint = computeFingerprint(fontBytes);

    const existing = this.ttfCache.get(fingerprint);
    if (existing) {
      return existing.font;
    }

    const parsedFont = parseTrueTypeFont(fontBytes);

    // Initially embed with all characters from the cmap (we'll re-subset on finalize)
    // For now, embed with all mapped characters
    const allChars = new Set<number>(parsedFont.cmap.keys());

    const { fontRef, font } = embedTrueTypeFont(this.store, fontBytes, parsedFont, allChars);

    const embeddedFont: EmbeddedFont = {
      ...font,
      ref: fontRef,
    };

    // Wrap encode to track character usage
    const usedChars = new Set<number>();
    const originalEncode = font.encode.bind(font);
    embeddedFont.encode = (text: string): Uint8Array => {
      for (let i = 0; i < text.length; i++) {
        const cp = text.codePointAt(i)!;
        usedChars.add(cp);
        if (cp > 0xffff) i++;
      }
      return originalEncode(text);
    };

    // Also track on measureWidth
    const originalMeasure = font.measureWidth.bind(font);
    embeddedFont.measureWidth = (text: string, fontSize: number): number => {
      for (let i = 0; i < text.length; i++) {
        const cp = text.codePointAt(i)!;
        usedChars.add(cp);
        if (cp > 0xffff) i++;
      }
      return originalMeasure(text, fontSize);
    };

    const record: TrueTypeFontRecord = {
      fontData: fontBytes,
      parsedFont,
      usedChars,
      font: embeddedFont,
      fingerprint,
    };

    this.ttfCache.set(fingerprint, record);
    return embeddedFont;
  }

  /**
   * Get all embedded font refs and their internal names for use in page resources.
   */
  getFontEntries(): Map<string, PdfRef> {
    const entries = new Map<string, PdfRef>();
    let idx = 0;

    for (const [fontName, font] of this.standardFontCache) {
      entries.set(`F${idx++}`, font.ref);
    }

    for (const [, record] of this.ttfCache) {
      entries.set(`F${idx++}`, record.font.ref);
    }

    return entries;
  }

  /**
   * Look up the internal name (e.g., "F0", "F1") for a given font ref.
   */
  getFontName(ref: PdfRef): string | undefined {
    let idx = 0;
    for (const [, font] of this.standardFontCache) {
      if (font.ref.objectNumber === ref.objectNumber && font.ref.generation === ref.generation) {
        return `F${idx}`;
      }
      idx++;
    }
    for (const [, record] of this.ttfCache) {
      if (record.font.ref.objectNumber === ref.objectNumber && record.font.ref.generation === ref.generation) {
        return `F${idx}`;
      }
      idx++;
    }
    return undefined;
  }

  /**
   * Get the set of tracked used characters for a TrueType font.
   * Returns undefined for standard fonts (they don't need subsetting).
   */
  getUsedChars(ref: PdfRef): Set<number> | undefined {
    for (const [, record] of this.ttfCache) {
      if (record.font.ref.objectNumber === ref.objectNumber && record.font.ref.generation === ref.generation) {
        return record.usedChars;
      }
    }
    return undefined;
  }
}

/**
 * Compute a simple fingerprint from font data for deduplication.
 * Uses a combination of file size and sampled bytes.
 */
function computeFingerprint(data: Uint8Array): string {
  // Simple hash: combine length with sampled bytes
  let hash = data.length;
  const step = Math.max(1, Math.floor(data.length / 64));
  for (let i = 0; i < data.length; i += step) {
    hash = ((hash << 5) - hash + data[i]) | 0;
  }
  // Also include first 32 and last 32 bytes
  for (let i = 0; i < Math.min(32, data.length); i++) {
    hash = ((hash << 5) - hash + data[i]) | 0;
  }
  for (let i = Math.max(0, data.length - 32); i < data.length; i++) {
    hash = ((hash << 5) - hash + data[i]) | 0;
  }
  return `ttf:${data.length}:${(hash >>> 0).toString(36)}`;
}
