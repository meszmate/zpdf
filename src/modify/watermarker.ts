/**
 * Add watermarks to existing PDF pages.
 */

import type { PdfRef, PdfObject, PdfDict, PdfArray } from '../core/types.js';
import type { Color } from '../color/color.js';
import { ObjectStore } from '../core/object-store.js';
import {
  pdfDict, pdfName, pdfNum, pdfStr, pdfArray, pdfStream, pdfRef,
  dictGetRef, dictGetArray, dictGetName, dictGetNumber, dictGet,
  isRef, isDict, isArray,
} from '../core/objects.js';
import { writePdf } from '../writer/pdf-writer.js';
import { parseMiniPdf } from './mini-parser.js';
import { setFillColor } from '../color/operators.js';

export interface WatermarkConfig {
  text: string;
  fontSize?: number;
  color?: Color;
  opacity?: number;
  rotation?: number; // degrees
  position?: 'center' | 'top' | 'bottom';
}

/**
 * Add a text watermark to all pages of a PDF.
 *
 * @param pdfBytes - Source PDF bytes
 * @param config - Watermark configuration
 * @returns Modified PDF with watermark on all pages
 */
export async function addWatermark(
  pdfBytes: Uint8Array,
  config: WatermarkConfig,
): Promise<Uint8Array> {
  const parsed = parseMiniPdf(pdfBytes);
  const store = parsed.store;

  const fontSize = config.fontSize ?? 60;
  const opacity = config.opacity ?? 0.3;
  const rotation = config.rotation ?? 45;
  const position = config.position ?? 'center';

  // Create an ExtGState for transparency
  const gsRef = store.allocRef();
  store.set(gsRef, pdfDict({
    Type: pdfName('ExtGState'),
    CA: pdfNum(opacity),    // stroke opacity
    ca: pdfNum(opacity),    // fill opacity
  }));

  // Process each page
  for (const pageRef of parsed.pageRefs) {
    const pageObj = store.get(pageRef);
    if (!pageObj || pageObj.type !== 'dict') continue;

    // Get page dimensions from MediaBox
    let width = 612;
    let height = 792;
    const mediaBox = dictGetArray(pageObj, 'MediaBox');
    if (mediaBox && mediaBox.length >= 4) {
      const x0 = mediaBox[0].type === 'number' ? mediaBox[0].value : 0;
      const y0 = mediaBox[1].type === 'number' ? mediaBox[1].value : 0;
      const x1 = mediaBox[2].type === 'number' ? mediaBox[2].value : 612;
      const y1 = mediaBox[3].type === 'number' ? mediaBox[3].value : 792;
      width = x1 - x0;
      height = y1 - y0;
    }

    // Calculate watermark position
    let tx: number;
    let ty: number;
    switch (position) {
      case 'top':
        tx = width / 2;
        ty = height - fontSize - 40;
        break;
      case 'bottom':
        tx = width / 2;
        ty = fontSize + 40;
        break;
      case 'center':
      default:
        tx = width / 2;
        ty = height / 2;
        break;
    }

    // Build watermark content stream
    const rotRad = (rotation * Math.PI) / 180;
    const cos = Math.cos(rotRad);
    const sin = Math.sin(rotRad);

    const ops: string[] = [];
    ops.push('q'); // save state
    ops.push('/GS_WM gs'); // set transparency

    // Set color
    if (config.color) {
      ops.push(setFillColor(config.color));
    } else {
      ops.push('0.5 0.5 0.5 rg'); // default gray
    }

    // Position and rotate
    ops.push(`${fmt(cos)} ${fmt(sin)} ${fmt(-sin)} ${fmt(cos)} ${fmt(tx)} ${fmt(ty)} cm`);

    // Draw text centered
    ops.push('BT');
    ops.push(`/F_WM ${fontSize} Tf`);

    // Approximate text width for centering
    const textWidth = config.text.length * fontSize * 0.5;
    ops.push(`${fmt(-textWidth / 2)} ${fmt(-fontSize / 3)} Td`);
    ops.push(`(${escapePdfString(config.text)}) Tj`);
    ops.push('ET');
    ops.push('Q'); // restore state

    const wmContent = ops.join('\n') + '\n';
    const wmData = new TextEncoder().encode(wmContent);

    // Create watermark content stream
    const wmStreamRef = store.allocRef();
    store.set(wmStreamRef, pdfStream({}, wmData));

    // Ensure page has Resources with the GS and font
    const entries = new Map(pageObj.entries);

    // Get or create Resources dict
    let resources = getOrCreateResources(store, entries);

    // Add ExtGState to resources
    let extGState = getOrCreateSubdict(store, resources, 'ExtGState');
    extGState.set('GS_WM', gsRef);
    resources.set('ExtGState', { type: 'dict', entries: extGState });

    // Add a basic Helvetica font for watermark text
    let fontDict = getOrCreateSubdict(store, resources, 'Font');
    if (!fontDict.has('F_WM')) {
      const fontRef = store.allocRef();
      store.set(fontRef, pdfDict({
        Type: pdfName('Font'),
        Subtype: pdfName('Type1'),
        BaseFont: pdfName('Helvetica'),
      }));
      fontDict.set('F_WM', fontRef);
    }
    resources.set('Font', { type: 'dict', entries: fontDict });

    // Update Resources on page
    const resourcesRef = store.allocRef();
    store.set(resourcesRef, { type: 'dict', entries: resources });
    entries.set('Resources', resourcesRef);

    // Append watermark stream to page contents
    const existingContents = entries.get('Contents');
    if (existingContents) {
      if (existingContents.type === 'array') {
        entries.set('Contents', {
          type: 'array',
          items: [...existingContents.items, wmStreamRef],
        });
      } else {
        // Single ref or stream
        entries.set('Contents', pdfArray(existingContents, wmStreamRef));
      }
    } else {
      entries.set('Contents', wmStreamRef);
    }

    store.set(pageRef, { type: 'dict', entries });
  }

  return writePdf(store, parsed.catalogRef, { compress: true });
}

/**
 * Get existing Resources from page entries or create a new Map.
 */
function getOrCreateResources(
  store: ObjectStore,
  entries: Map<string, PdfObject>,
): Map<string, PdfObject> {
  const res = entries.get('Resources');
  if (res) {
    if (res.type === 'dict') {
      return new Map(res.entries);
    }
    if (res.type === 'ref') {
      const resolved = store.get(res);
      if (resolved && resolved.type === 'dict') {
        return new Map(resolved.entries);
      }
    }
  }
  return new Map();
}

/**
 * Get or create a sub-dictionary from a resources map.
 */
function getOrCreateSubdict(
  store: ObjectStore,
  resources: Map<string, PdfObject>,
  key: string,
): Map<string, PdfObject> {
  const existing = resources.get(key);
  if (existing) {
    if (existing.type === 'dict') {
      return new Map(existing.entries);
    }
    if (existing.type === 'ref') {
      const resolved = store.get(existing);
      if (resolved && resolved.type === 'dict') {
        return new Map(resolved.entries);
      }
    }
  }
  return new Map();
}

function fmt(n: number): string {
  if (Number.isInteger(n)) return n.toString();
  const s = n.toFixed(6);
  let end = s.length;
  while (end > 0 && s[end - 1] === '0') end--;
  if (s[end - 1] === '.') end--;
  return s.slice(0, end);
}

function escapePdfString(s: string): string {
  let result = '';
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    switch (ch) {
      case '\\': result += '\\\\'; break;
      case '(': result += '\\('; break;
      case ')': result += '\\)'; break;
      case '\r': result += '\\r'; break;
      case '\n': result += '\\n'; break;
      default: result += ch;
    }
  }
  return result;
}
