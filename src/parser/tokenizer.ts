/**
 * PDF lexical scanner / tokenizer.
 * Converts a raw byte stream into a sequence of PDF tokens.
 */

export enum TokenType {
  Boolean,
  Integer,
  Real,
  LiteralString,
  HexString,
  Name,
  ArrayStart,
  ArrayEnd,
  DictStart,
  DictEnd,
  Keyword,
  EOF,
}

export interface Token {
  type: TokenType;
  value: any;
  position: number;
}

// PDF whitespace bytes
const WS = new Set([0x00, 0x09, 0x0a, 0x0c, 0x0d, 0x20]);

// PDF delimiter bytes
const DELIMITERS = new Set([
  0x28, 0x29, // ( )
  0x3c, 0x3e, // < >
  0x5b, 0x5d, // [ ]
  0x7b, 0x7d, // { }
  0x2f,       // /
  0x25,       // %
]);

function isWhitespace(b: number): boolean {
  return WS.has(b);
}

function isDelimiter(b: number): boolean {
  return DELIMITERS.has(b);
}

function isRegularChar(b: number): boolean {
  return !isWhitespace(b) && !isDelimiter(b);
}

function isDigit(b: number): boolean {
  return b >= 0x30 && b <= 0x39;
}

function hexValue(b: number): number {
  if (b >= 0x30 && b <= 0x39) return b - 0x30;
  if (b >= 0x41 && b <= 0x46) return b - 0x41 + 10;
  if (b >= 0x61 && b <= 0x66) return b - 0x61 + 10;
  return -1;
}

export class Tokenizer {
  private data: Uint8Array;
  public position: number;
  private _peeked: Token | null = null;

  constructor(data: Uint8Array, startPos: number = 0) {
    this.data = data;
    this.position = startPos;
  }

  private peekByteAt(pos: number): number {
    if (pos >= this.data.length) return -1;
    return this.data[pos];
  }

  private skipWhitespaceAndComments(): void {
    while (this.position < this.data.length) {
      const b = this.data[this.position];
      if (isWhitespace(b)) {
        this.position++;
        continue;
      }
      if (b === 0x25) { // '%' comment
        this.position++;
        while (this.position < this.data.length) {
          const c = this.data[this.position];
          if (c === 0x0a || c === 0x0d) break;
          this.position++;
        }
        continue;
      }
      break;
    }
  }

  nextToken(): Token {
    if (this._peeked !== null) {
      const t = this._peeked;
      this._peeked = null;
      return t;
    }
    return this._readToken();
  }

  peekToken(): Token {
    if (this._peeked !== null) return this._peeked;
    this._peeked = this._readToken();
    return this._peeked;
  }

  private _readToken(): Token {
    this.skipWhitespaceAndComments();

    if (this.position >= this.data.length) {
      return { type: TokenType.EOF, value: null, position: this.position };
    }

    const startPos = this.position;
    const b = this.data[this.position];

    // Array delimiters
    if (b === 0x5b) { // [
      this.position++;
      return { type: TokenType.ArrayStart, value: '[', position: startPos };
    }
    if (b === 0x5d) { // ]
      this.position++;
      return { type: TokenType.ArrayEnd, value: ']', position: startPos };
    }

    // Dict delimiters << >>
    if (b === 0x3c) { // <
      if (this.peekByteAt(this.position + 1) === 0x3c) {
        this.position += 2;
        return { type: TokenType.DictStart, value: '<<', position: startPos };
      }
      // Hex string
      return this.readHexString(startPos);
    }
    if (b === 0x3e) { // >
      if (this.peekByteAt(this.position + 1) === 0x3e) {
        this.position += 2;
        return { type: TokenType.DictEnd, value: '>>', position: startPos };
      }
      // Unexpected single '>', skip it
      this.position++;
      return { type: TokenType.Keyword, value: '>', position: startPos };
    }

    // Literal string
    if (b === 0x28) { // (
      return this.readLiteralString(startPos);
    }

    // Name
    if (b === 0x2f) { // /
      return this.readName(startPos);
    }

    // Number (digit, +, -, or .)
    if (isDigit(b) || b === 0x2b || b === 0x2d || b === 0x2e) {
      return this.readNumber(startPos);
    }

    // Keyword or boolean
    return this.readKeyword(startPos);
  }

  private readNumber(startPos: number): Token {
    let hasDecimal = false;
    let hasDigits = false;
    const start = this.position;

    // Optional sign
    if (this.data[this.position] === 0x2b || this.data[this.position] === 0x2d) {
      this.position++;
    }

    // Check for leading dot
    if (this.position < this.data.length && this.data[this.position] === 0x2e) {
      hasDecimal = true;
      this.position++;
    }

    // Read digits
    while (this.position < this.data.length && isDigit(this.data[this.position])) {
      hasDigits = true;
      this.position++;
    }

    // Check for decimal point (if not already seen)
    if (!hasDecimal && this.position < this.data.length && this.data[this.position] === 0x2e) {
      hasDecimal = true;
      this.position++;
      // Read fractional digits
      while (this.position < this.data.length && isDigit(this.data[this.position])) {
        hasDigits = true;
        this.position++;
      }
    }

    if (!hasDigits) {
      // Not actually a number (e.g., just a sign), treat as keyword
      this.position = start;
      return this.readKeyword(startPos);
    }

    let numStr = '';
    for (let i = start; i < this.position; i++) {
      numStr += String.fromCharCode(this.data[i]);
    }

    const value = parseFloat(numStr);

    if (hasDecimal) {
      return { type: TokenType.Real, value, position: startPos };
    }
    return { type: TokenType.Integer, value, position: startPos };
  }

  private readLiteralString(startPos: number): Token {
    this.position++; // skip '('
    const bytes: number[] = [];
    let depth = 1;

    while (this.position < this.data.length && depth > 0) {
      const b = this.data[this.position];

      if (b === 0x28) { // (
        depth++;
        bytes.push(b);
        this.position++;
      } else if (b === 0x29) { // )
        depth--;
        if (depth > 0) {
          bytes.push(b);
        }
        this.position++;
      } else if (b === 0x5c) { // backslash
        this.position++;
        if (this.position >= this.data.length) break;
        const esc = this.data[this.position];
        switch (esc) {
          case 0x6e: bytes.push(0x0a); this.position++; break; // \n
          case 0x72: bytes.push(0x0d); this.position++; break; // \r
          case 0x74: bytes.push(0x09); this.position++; break; // \t
          case 0x62: bytes.push(0x08); this.position++; break; // \b
          case 0x66: bytes.push(0x0c); this.position++; break; // \f
          case 0x28: bytes.push(0x28); this.position++; break; // \(
          case 0x29: bytes.push(0x29); this.position++; break; // \)
          case 0x5c: bytes.push(0x5c); this.position++; break; // \\
          case 0x0d: // \<CR> or \<CR><LF> - line continuation
            this.position++;
            if (this.position < this.data.length && this.data[this.position] === 0x0a) {
              this.position++;
            }
            break;
          case 0x0a: // \<LF> - line continuation
            this.position++;
            break;
          default:
            // Octal escape \DDD
            if (esc >= 0x30 && esc <= 0x37) {
              let octal = esc - 0x30;
              this.position++;
              if (this.position < this.data.length && this.data[this.position] >= 0x30 && this.data[this.position] <= 0x37) {
                octal = octal * 8 + (this.data[this.position] - 0x30);
                this.position++;
                if (this.position < this.data.length && this.data[this.position] >= 0x30 && this.data[this.position] <= 0x37) {
                  octal = octal * 8 + (this.data[this.position] - 0x30);
                  this.position++;
                }
              }
              bytes.push(octal & 0xff);
            } else {
              // Unknown escape - just include the character after backslash
              bytes.push(esc);
              this.position++;
            }
            break;
        }
      } else {
        bytes.push(b);
        this.position++;
      }
    }

    return { type: TokenType.LiteralString, value: new Uint8Array(bytes), position: startPos };
  }

  private readHexString(startPos: number): Token {
    this.position++; // skip '<'
    const bytes: number[] = [];
    let high = -1;

    while (this.position < this.data.length) {
      const b = this.data[this.position];
      if (b === 0x3e) { // '>'
        this.position++;
        break;
      }
      if (isWhitespace(b)) {
        this.position++;
        continue;
      }
      const v = hexValue(b);
      if (v >= 0) {
        if (high === -1) {
          high = v;
        } else {
          bytes.push((high << 4) | v);
          high = -1;
        }
      }
      this.position++;
    }

    // Trailing odd nibble
    if (high !== -1) {
      bytes.push(high << 4);
    }

    return { type: TokenType.HexString, value: new Uint8Array(bytes), position: startPos };
  }

  private readName(startPos: number): Token {
    this.position++; // skip '/'
    let name = '';

    while (this.position < this.data.length) {
      const b = this.data[this.position];
      if (isWhitespace(b) || isDelimiter(b)) break;

      if (b === 0x23) { // '#' hex escape
        this.position++;
        if (this.position + 1 < this.data.length) {
          const h1 = hexValue(this.data[this.position]);
          const h2 = hexValue(this.data[this.position + 1]);
          if (h1 >= 0 && h2 >= 0) {
            name += String.fromCharCode((h1 << 4) | h2);
            this.position += 2;
            continue;
          }
        }
        // Invalid hex escape, just include '#'
        name += '#';
        continue;
      }

      name += String.fromCharCode(b);
      this.position++;
    }

    return { type: TokenType.Name, value: name, position: startPos };
  }

  private readKeyword(startPos: number): Token {
    let word = '';
    while (this.position < this.data.length) {
      const b = this.data[this.position];
      if (isWhitespace(b) || isDelimiter(b)) break;
      word += String.fromCharCode(b);
      this.position++;
    }

    if (word === 'true') {
      return { type: TokenType.Boolean, value: true, position: startPos };
    }
    if (word === 'false') {
      return { type: TokenType.Boolean, value: false, position: startPos };
    }

    return { type: TokenType.Keyword, value: word, position: startPos };
  }
}
