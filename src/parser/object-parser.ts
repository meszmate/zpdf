/**
 * Recursive descent parser for PDF objects.
 * Transforms token streams into PdfObject values.
 */

import type { PdfObject, PdfRef } from '../core/types.js';
import {
  pdfBool, pdfNum, pdfNull, pdfName, pdfArray, pdfRef,
  pdfStream,
} from '../core/objects.js';
import type { PdfString, PdfDict } from '../core/types.js';
import { Tokenizer, TokenType } from './tokenizer.js';

export class ObjectParser {
  constructor(private tokenizer: Tokenizer) {}

  /**
   * Parse a single PDF object from the token stream.
   */
  parseObject(): PdfObject {
    const token = this.tokenizer.nextToken();

    switch (token.type) {
      case TokenType.Boolean:
        return pdfBool(token.value as boolean);

      case TokenType.Integer: {
        // Look ahead for "N G R" pattern (indirect reference)
        const saved = this.tokenizer.position;
        const next = this.tokenizer.peekToken();
        if (next.type === TokenType.Integer) {
          this.tokenizer.nextToken(); // consume generation number
          const r = this.tokenizer.peekToken();
          if (r.type === TokenType.Keyword && r.value === 'R') {
            this.tokenizer.nextToken(); // consume 'R'
            return pdfRef(token.value as number, next.value as number);
          }
          // Not a reference, backtrack
          this.tokenizer.position = saved;
          // Clear internal peeked token since we manually changed position
          (this.tokenizer as any)._peeked = null;
        }
        return pdfNum(token.value as number);
      }

      case TokenType.Real:
        return pdfNum(token.value as number);

      case TokenType.LiteralString:
        return {
          type: 'string',
          value: token.value as Uint8Array,
          encoding: 'literal',
        } as PdfString;

      case TokenType.HexString:
        return {
          type: 'string',
          value: token.value as Uint8Array,
          encoding: 'hex',
        } as PdfString;

      case TokenType.Name:
        return pdfName(token.value as string);

      case TokenType.ArrayStart:
        return this.parseArray();

      case TokenType.DictStart:
        return this.parseDictOrStream();

      case TokenType.Keyword:
        if (token.value === 'null') return pdfNull();
        if (token.value === 'true') return pdfBool(true);
        if (token.value === 'false') return pdfBool(false);
        // Return as-is for unknown keywords (e.g., operators in content streams)
        return pdfName(token.value as string);

      case TokenType.EOF:
        throw new Error('Unexpected end of data while parsing object');

      default:
        throw new Error(`Unexpected token type: ${token.type} at position ${token.position}`);
    }
  }

  private parseArray(): PdfObject {
    const items: PdfObject[] = [];
    while (true) {
      const peek = this.tokenizer.peekToken();
      if (peek.type === TokenType.ArrayEnd) {
        this.tokenizer.nextToken(); // consume ']'
        break;
      }
      if (peek.type === TokenType.EOF) {
        break;
      }
      items.push(this.parseObject());
    }
    return pdfArray(...items);
  }

  private parseDictOrStream(): PdfObject {
    const entries = new Map<string, PdfObject>();

    while (true) {
      const peek = this.tokenizer.peekToken();
      if (peek.type === TokenType.DictEnd) {
        this.tokenizer.nextToken(); // consume '>>'
        break;
      }
      if (peek.type === TokenType.EOF) {
        break;
      }

      // Key must be a name
      const keyToken = this.tokenizer.nextToken();
      if (keyToken.type !== TokenType.Name) {
        // Tolerate malformed PDFs: skip non-name tokens
        continue;
      }
      const key = keyToken.value as string;

      // Check if next token is DictEnd (value missing)
      const valPeek = this.tokenizer.peekToken();
      if (valPeek.type === TokenType.DictEnd) {
        // Missing value, treat as null
        entries.set(key, pdfNull());
        continue;
      }

      const value = this.parseObject();
      entries.set(key, value);
    }

    const dict: PdfDict = { type: 'dict', entries };

    // Check for stream keyword after the dict
    const afterDict = this.tokenizer.position;
    const peek = this.tokenizer.peekToken();
    if (peek.type === TokenType.Keyword && peek.value === 'stream') {
      this.tokenizer.nextToken(); // consume 'stream'

      // Stream data starts after "stream" keyword and the end-of-line marker
      let pos = this.tokenizer.position;
      const data = (this.tokenizer as any).data as Uint8Array;

      // Skip the EOL after "stream": CR, LF, or CR+LF
      if (pos < data.length && data[pos] === 0x0d) {
        pos++;
        if (pos < data.length && data[pos] === 0x0a) {
          pos++;
        }
      } else if (pos < data.length && data[pos] === 0x0a) {
        pos++;
      }

      // Determine stream length
      const lengthObj = entries.get('Length');
      let streamLength = -1;
      if (lengthObj && lengthObj.type === 'number') {
        streamLength = lengthObj.value;
      }

      let streamData: Uint8Array;
      if (streamLength >= 0 && pos + streamLength <= data.length) {
        streamData = data.slice(pos, pos + streamLength);
        this.tokenizer.position = pos + streamLength;
      } else {
        // Length not known or is a reference - search for "endstream"
        const endPattern = new TextEncoder().encode('endstream');
        let endPos = -1;
        const searchLimit = Math.min(data.length - endPattern.length, data.length);
        outer: for (let i = pos; i <= searchLimit; i++) {
          for (let j = 0; j < endPattern.length; j++) {
            if (data[i + j] !== endPattern[j]) continue outer;
          }
          endPos = i;
          break;
        }

        if (endPos === -1) {
          // Can't find endstream, take rest of data
          streamData = data.slice(pos);
          this.tokenizer.position = data.length;
        } else {
          // Trim trailing whitespace before endstream
          let dataEnd = endPos;
          if (dataEnd > pos && data[dataEnd - 1] === 0x0a) dataEnd--;
          if (dataEnd > pos && data[dataEnd - 1] === 0x0d) dataEnd--;
          streamData = data.slice(pos, dataEnd);
          this.tokenizer.position = endPos + endPattern.length;
        }
      }

      // Clear any peeked token
      (this.tokenizer as any)._peeked = null;

      // Consume 'endstream' keyword if present
      const endKw = this.tokenizer.peekToken();
      if (endKw.type === TokenType.Keyword && endKw.value === 'endstream') {
        this.tokenizer.nextToken();
      }

      return pdfStream(entries, streamData);
    }

    return dict;
  }

  /**
   * Parse an indirect object definition: objNum genNum obj <object> endobj
   */
  parseIndirectObject(): { ref: PdfRef; obj: PdfObject } | null {
    const objNumToken = this.tokenizer.nextToken();
    if (objNumToken.type === TokenType.EOF) return null;
    if (objNumToken.type !== TokenType.Integer) return null;

    const genToken = this.tokenizer.nextToken();
    if (genToken.type !== TokenType.Integer) return null;

    const objKw = this.tokenizer.nextToken();
    if (objKw.type !== TokenType.Keyword || objKw.value !== 'obj') return null;

    const obj = this.parseObject();
    const ref = pdfRef(objNumToken.value as number, genToken.value as number);

    // Consume endobj if present
    const endKw = this.tokenizer.peekToken();
    if (endKw.type === TokenType.Keyword && endKw.value === 'endobj') {
      this.tokenizer.nextToken();
    }

    return { ref, obj };
  }
}
