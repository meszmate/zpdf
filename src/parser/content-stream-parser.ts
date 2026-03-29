/**
 * Parse PDF page content stream operators and operands.
 */

import type { PdfObject } from '../core/types.js';
import {
  pdfBool, pdfNum, pdfNull, pdfName,
} from '../core/objects.js';
import type { PdfString } from '../core/types.js';
import { Tokenizer, TokenType } from './tokenizer.js';

export interface ContentOperation {
  operator: string;
  operands: PdfObject[];
}

/**
 * Set of all known PDF content stream operators.
 * Used to distinguish operators from operand keywords.
 */
const OPERATORS = new Set([
  // Text state
  'BT', 'ET', 'Tf', 'Td', 'TD', 'Tm', 'T*',
  'Tj', 'TJ', "'", '"',
  'Tc', 'Tw', 'Tz', 'TL', 'Tr', 'Ts',
  // Path construction
  'm', 'l', 'c', 'v', 'y', 'h', 're',
  // Path painting
  'S', 's', 'f', 'F', 'f*', 'B', 'B*', 'b', 'b*', 'n',
  // Clipping
  'W', 'W*',
  // Graphics state
  'q', 'Q', 'cm',
  'w', 'J', 'j', 'M', 'd', 'ri', 'i', 'gs',
  // Color
  'CS', 'cs', 'SC', 'SCN', 'sc', 'scn',
  'G', 'g', 'RG', 'rg', 'K', 'k',
  // XObject
  'Do',
  // Shading
  'sh',
  // Inline image
  'BI', 'ID', 'EI',
  // Marked content
  'BMC', 'BDC', 'EMC', 'MP', 'DP',
]);

/**
 * Parse a content stream into a list of operations (operator + operands).
 */
export function parseContentStream(data: Uint8Array): ContentOperation[] {
  const operations: ContentOperation[] = [];
  const tokenizer = new Tokenizer(data);
  const operands: PdfObject[] = [];

  while (true) {
    const token = tokenizer.nextToken();
    if (token.type === TokenType.EOF) break;

    switch (token.type) {
      case TokenType.Integer:
      case TokenType.Real:
        operands.push(pdfNum(token.value as number));
        break;

      case TokenType.LiteralString:
        operands.push({
          type: 'string',
          value: token.value as Uint8Array,
          encoding: 'literal',
        } as PdfString);
        break;

      case TokenType.HexString:
        operands.push({
          type: 'string',
          value: token.value as Uint8Array,
          encoding: 'hex',
        } as PdfString);
        break;

      case TokenType.Name:
        operands.push(pdfName(token.value as string));
        break;

      case TokenType.Boolean:
        operands.push(pdfBool(token.value as boolean));
        break;

      case TokenType.ArrayStart: {
        // Parse inline array
        const items: PdfObject[] = [];
        let depth = 1;
        while (depth > 0) {
          const inner = tokenizer.nextToken();
          if (inner.type === TokenType.EOF) break;
          if (inner.type === TokenType.ArrayEnd) {
            depth--;
            if (depth === 0) break;
          }
          if (inner.type === TokenType.ArrayStart) {
            depth++;
          }
          // Simplified: push the value for known types
          switch (inner.type) {
            case TokenType.Integer:
            case TokenType.Real:
              items.push(pdfNum(inner.value as number));
              break;
            case TokenType.LiteralString:
              items.push({
                type: 'string',
                value: inner.value as Uint8Array,
                encoding: 'literal',
              } as PdfString);
              break;
            case TokenType.HexString:
              items.push({
                type: 'string',
                value: inner.value as Uint8Array,
                encoding: 'hex',
              } as PdfString);
              break;
            case TokenType.Name:
              items.push(pdfName(inner.value as string));
              break;
            case TokenType.Boolean:
              items.push(pdfBool(inner.value as boolean));
              break;
            case TokenType.Keyword:
              if (inner.value === 'null') items.push(pdfNull());
              else items.push(pdfName(inner.value as string));
              break;
            default:
              break;
          }
        }
        operands.push({ type: 'array', items });
        break;
      }

      case TokenType.DictStart: {
        // Parse inline dict (used in BDC, DP operators)
        const entries = new Map<string, PdfObject>();
        while (true) {
          const kToken = tokenizer.nextToken();
          if (kToken.type === TokenType.DictEnd || kToken.type === TokenType.EOF) break;
          if (kToken.type !== TokenType.Name) continue;
          const key = kToken.value as string;
          const vToken = tokenizer.nextToken();
          if (vToken.type === TokenType.DictEnd || vToken.type === TokenType.EOF) break;
          let val: PdfObject;
          switch (vToken.type) {
            case TokenType.Integer:
            case TokenType.Real:
              val = pdfNum(vToken.value as number);
              break;
            case TokenType.LiteralString:
              val = { type: 'string', value: vToken.value as Uint8Array, encoding: 'literal' } as PdfString;
              break;
            case TokenType.HexString:
              val = { type: 'string', value: vToken.value as Uint8Array, encoding: 'hex' } as PdfString;
              break;
            case TokenType.Name:
              val = pdfName(vToken.value as string);
              break;
            case TokenType.Boolean:
              val = pdfBool(vToken.value as boolean);
              break;
            default:
              val = pdfNull();
              break;
          }
          entries.set(key, val);
        }
        operands.push({ type: 'dict', entries });
        break;
      }

      case TokenType.Keyword: {
        const kw = token.value as string;

        if (kw === 'null') {
          operands.push(pdfNull());
          break;
        }

        if (kw === 'true') {
          operands.push(pdfBool(true));
          break;
        }

        if (kw === 'false') {
          operands.push(pdfBool(false));
          break;
        }

        if (OPERATORS.has(kw)) {
          if (kw === 'BI') {
            // Handle inline image: BI <key-value pairs> ID <data> EI
            const inlineOp = parseInlineImage(tokenizer);
            operations.push(inlineOp);
            operands.length = 0;
          } else {
            operations.push({
              operator: kw,
              operands: operands.splice(0),
            });
          }
        } else {
          // Unknown keyword - treat as operand (name-like)
          operands.push(pdfName(kw));
        }
        break;
      }

      default:
        break;
    }
  }

  // Any remaining operands without an operator (malformed) - ignore
  return operations;
}

/**
 * Parse an inline image: BI <dict entries> ID <image data> EI
 * Returns a ContentOperation with operator 'BI' containing the
 * inline image dict and data.
 */
function parseInlineImage(tokenizer: Tokenizer): ContentOperation {
  // Parse key-value pairs until ID keyword
  const entries = new Map<string, PdfObject>();

  while (true) {
    const token = tokenizer.nextToken();
    if (token.type === TokenType.EOF) break;
    if (token.type === TokenType.Keyword && token.value === 'ID') break;

    // Key is a name
    let key: string;
    if (token.type === TokenType.Name) {
      key = token.value as string;
    } else {
      // Inline images sometimes use abbreviations without /
      // Treat keyword tokens as abbreviated names
      key = String(token.value);
    }

    // Expand common inline image abbreviations
    key = expandAbbreviation(key);

    const valToken = tokenizer.nextToken();
    if (valToken.type === TokenType.EOF) break;
    if (valToken.type === TokenType.Keyword && valToken.value === 'ID') {
      break;
    }

    let val: PdfObject;
    switch (valToken.type) {
      case TokenType.Integer:
      case TokenType.Real:
        val = pdfNum(valToken.value as number);
        break;
      case TokenType.Name:
        val = pdfName(expandFilterAbbreviation(valToken.value as string));
        break;
      case TokenType.Boolean:
        val = pdfBool(valToken.value as boolean);
        break;
      case TokenType.LiteralString:
        val = { type: 'string', value: valToken.value as Uint8Array, encoding: 'literal' } as PdfString;
        break;
      case TokenType.HexString:
        val = { type: 'string', value: valToken.value as Uint8Array, encoding: 'hex' } as PdfString;
        break;
      case TokenType.ArrayStart: {
        const items: PdfObject[] = [];
        while (true) {
          const inner = tokenizer.nextToken();
          if (inner.type === TokenType.ArrayEnd || inner.type === TokenType.EOF) break;
          if (inner.type === TokenType.Name) {
            items.push(pdfName(expandFilterAbbreviation(inner.value as string)));
          } else if (inner.type === TokenType.Integer || inner.type === TokenType.Real) {
            items.push(pdfNum(inner.value as number));
          }
        }
        val = { type: 'array', items };
        break;
      }
      default:
        val = pdfNull();
        break;
    }

    entries.set(key, val);
  }

  // After ID keyword, there's a single whitespace byte, then the image data
  // Find EI keyword (preceded by whitespace)
  const rawData = (tokenizer as any).data as Uint8Array;
  let pos = tokenizer.position;

  // Skip exactly one whitespace byte after ID
  if (pos < rawData.length && (rawData[pos] === 0x20 || rawData[pos] === 0x0a || rawData[pos] === 0x0d)) {
    pos++;
  }

  // Search for EI preceded by whitespace
  const dataStart = pos;
  let dataEnd = pos;
  let found = false;

  while (pos < rawData.length - 1) {
    // Look for whitespace followed by "EI" followed by whitespace or delimiter or EOF
    if (rawData[pos] === 0x0a || rawData[pos] === 0x0d || rawData[pos] === 0x20) {
      if (pos + 2 < rawData.length &&
          rawData[pos + 1] === 0x45 && // E
          rawData[pos + 2] === 0x49) { // I
        // Check that EI is followed by whitespace, delimiter, or EOF
        const afterEI = pos + 3;
        if (afterEI >= rawData.length ||
            rawData[afterEI] === 0x20 || rawData[afterEI] === 0x0a ||
            rawData[afterEI] === 0x0d || rawData[afterEI] === 0x09 ||
            rawData[afterEI] === 0x00 ||
            rawData[afterEI] === 0x2f || rawData[afterEI] === 0x25) {
          dataEnd = pos;
          tokenizer.position = afterEI;
          (tokenizer as any)._peeked = null;
          found = true;
          break;
        }
      }
    }
    pos++;
  }

  if (!found) {
    dataEnd = rawData.length;
    tokenizer.position = rawData.length;
    (tokenizer as any)._peeked = null;
  }

  const imageData = rawData.slice(dataStart, dataEnd);

  // Build a PdfStream-like dict operand and the image data as a string operand
  const dictObj: PdfObject = { type: 'dict', entries };
  const dataObj: PdfObject = {
    type: 'string',
    value: imageData,
    encoding: 'literal' as const,
  };

  return {
    operator: 'BI',
    operands: [dictObj, dataObj],
  };
}

/** Expand inline image dictionary key abbreviations */
function expandAbbreviation(key: string): string {
  switch (key) {
    case 'BPC': return 'BitsPerComponent';
    case 'CS': return 'ColorSpace';
    case 'D': return 'Decode';
    case 'DP': return 'DecodeParms';
    case 'F': return 'Filter';
    case 'H': return 'Height';
    case 'IM': return 'ImageMask';
    case 'I': return 'Interpolate';
    case 'W': return 'Width';
    default: return key;
  }
}

/** Expand inline image filter abbreviations */
function expandFilterAbbreviation(name: string): string {
  switch (name) {
    case 'AHx': return 'ASCIIHexDecode';
    case 'A85': return 'ASCII85Decode';
    case 'LZW': return 'LZWDecode';
    case 'Fl': return 'FlateDecode';
    case 'RL': return 'RunLengthDecode';
    case 'CCF': return 'CCITTFaxDecode';
    case 'DCT': return 'DCTDecode';
    // Color space abbreviations
    case 'G': return 'DeviceGray';
    case 'RGB': return 'DeviceRGB';
    case 'CMYK': return 'DeviceCMYK';
    case 'I': return 'Indexed';
    default: return name;
  }
}
