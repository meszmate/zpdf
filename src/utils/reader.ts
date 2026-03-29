const PDF_WHITESPACE = new Set([0x00, 0x09, 0x0a, 0x0c, 0x0d, 0x20]);

export class ByteReader {
  private data: Uint8Array;
  public position: number;
  public readonly length: number;

  constructor(data: Uint8Array) {
    this.data = data;
    this.position = 0;
    this.length = data.length;
  }

  readByte(): number {
    if (this.position >= this.length) {
      throw new RangeError('Unexpected end of data');
    }
    return this.data[this.position++];
  }

  readBytes(n: number): Uint8Array {
    if (this.position + n > this.length) {
      throw new RangeError('Unexpected end of data');
    }
    const result = this.data.slice(this.position, this.position + n);
    this.position += n;
    return result;
  }

  peekByte(): number {
    if (this.position >= this.length) {
      throw new RangeError('Unexpected end of data');
    }
    return this.data[this.position];
  }

  peekBytes(n: number): Uint8Array {
    if (this.position + n > this.length) {
      throw new RangeError('Unexpected end of data');
    }
    return this.data.slice(this.position, this.position + n);
  }

  skip(n: number): void {
    this.position += n;
    if (this.position > this.length) {
      this.position = this.length;
    }
  }

  skipWhitespace(): void {
    while (this.position < this.length && PDF_WHITESPACE.has(this.data[this.position])) {
      this.position++;
    }
  }

  readLine(): string {
    let start = this.position;
    while (this.position < this.length) {
      const b = this.data[this.position];
      if (b === 0x0a || b === 0x0d) {
        const line = this.decodeAscii(start, this.position);
        // consume CR, LF, or CR+LF
        if (b === 0x0d) {
          this.position++;
          if (this.position < this.length && this.data[this.position] === 0x0a) {
            this.position++;
          }
        } else {
          this.position++;
        }
        return line;
      }
      this.position++;
    }
    // reached EOF without line ending
    return this.decodeAscii(start, this.position);
  }

  readUntil(byte: number): Uint8Array {
    const start = this.position;
    while (this.position < this.length && this.data[this.position] !== byte) {
      this.position++;
    }
    return this.data.slice(start, this.position);
  }

  isEOF(): boolean {
    return this.position >= this.length;
  }

  indexOf(pattern: Uint8Array, fromPos?: number): number {
    const start = fromPos ?? this.position;
    const pLen = pattern.length;
    if (pLen === 0) return start;
    const limit = this.length - pLen;
    outer: for (let i = start; i <= limit; i++) {
      for (let j = 0; j < pLen; j++) {
        if (this.data[i + j] !== pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  lastIndexOf(pattern: Uint8Array, fromPos?: number): number {
    const pLen = pattern.length;
    if (pLen === 0) return fromPos ?? this.length;
    const start = fromPos !== undefined ? Math.min(fromPos, this.length - pLen) : this.length - pLen;
    outer: for (let i = start; i >= 0; i--) {
      for (let j = 0; j < pLen; j++) {
        if (this.data[i + j] !== pattern[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  private decodeAscii(start: number, end: number): string {
    let s = '';
    for (let i = start; i < end; i++) {
      s += String.fromCharCode(this.data[i]);
    }
    return s;
  }
}
