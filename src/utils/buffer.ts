const DEFAULT_CAPACITY = 1024;

export class ByteBuffer {
  private buf: Uint8Array;
  private pos: number;

  constructor(initialCapacity: number = DEFAULT_CAPACITY) {
    this.buf = new Uint8Array(initialCapacity > 0 ? initialCapacity : DEFAULT_CAPACITY);
    this.pos = 0;
  }

  private ensureCapacity(needed: number): void {
    const required = this.pos + needed;
    if (required <= this.buf.length) return;
    let newCap = this.buf.length;
    while (newCap < required) {
      newCap *= 2;
    }
    const newBuf = new Uint8Array(newCap);
    newBuf.set(this.buf, 0);
    this.buf = newBuf;
  }

  write(bytes: Uint8Array): void {
    this.ensureCapacity(bytes.length);
    this.buf.set(bytes, this.pos);
    this.pos += bytes.length;
  }

  writeByte(b: number): void {
    this.ensureCapacity(1);
    this.buf[this.pos++] = b & 0xff;
  }

  writeString(s: string): void {
    this.ensureCapacity(s.length);
    for (let i = 0; i < s.length; i++) {
      this.buf[this.pos++] = s.charCodeAt(i) & 0xff;
    }
  }

  writeUint16BE(n: number): void {
    this.ensureCapacity(2);
    this.buf[this.pos++] = (n >>> 8) & 0xff;
    this.buf[this.pos++] = n & 0xff;
  }

  writeUint32BE(n: number): void {
    this.ensureCapacity(4);
    this.buf[this.pos++] = (n >>> 24) & 0xff;
    this.buf[this.pos++] = (n >>> 16) & 0xff;
    this.buf[this.pos++] = (n >>> 8) & 0xff;
    this.buf[this.pos++] = n & 0xff;
  }

  getPosition(): number {
    return this.pos;
  }

  toUint8Array(): Uint8Array {
    return this.buf.slice(0, this.pos);
  }
}
