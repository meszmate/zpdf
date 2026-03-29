import { describe, it, expect } from 'vitest';
import { ByteBuffer } from '../../src/utils/buffer.js';

describe('ByteBuffer', () => {
  it('starts at position 0', () => {
    const buf = new ByteBuffer();
    expect(buf.getPosition()).toBe(0);
    expect(buf.toUint8Array().length).toBe(0);
  });

  it('writeByte appends a single byte', () => {
    const buf = new ByteBuffer();
    buf.writeByte(0x41);
    buf.writeByte(0x42);
    expect(buf.getPosition()).toBe(2);
    expect(buf.toUint8Array()).toEqual(new Uint8Array([0x41, 0x42]));
  });

  it('writeByte masks to 8 bits', () => {
    const buf = new ByteBuffer();
    buf.writeByte(0x1FF);
    expect(buf.toUint8Array()).toEqual(new Uint8Array([0xFF]));
  });

  it('writeString writes Latin-1 bytes', () => {
    const buf = new ByteBuffer();
    buf.writeString('ABC');
    expect(buf.toUint8Array()).toEqual(new Uint8Array([65, 66, 67]));
  });

  it('write appends a Uint8Array', () => {
    const buf = new ByteBuffer();
    buf.write(new Uint8Array([1, 2, 3]));
    buf.write(new Uint8Array([4, 5]));
    expect(buf.toUint8Array()).toEqual(new Uint8Array([1, 2, 3, 4, 5]));
    expect(buf.getPosition()).toBe(5);
  });

  it('writeUint16BE writes two bytes in big-endian', () => {
    const buf = new ByteBuffer();
    buf.writeUint16BE(0x0102);
    expect(buf.toUint8Array()).toEqual(new Uint8Array([0x01, 0x02]));
  });

  it('writeUint32BE writes four bytes in big-endian', () => {
    const buf = new ByteBuffer();
    buf.writeUint32BE(0x01020304);
    expect(buf.toUint8Array()).toEqual(new Uint8Array([0x01, 0x02, 0x03, 0x04]));
  });

  it('auto-grows when capacity is exceeded', () => {
    const buf = new ByteBuffer(4);
    // Write more than initial capacity
    for (let i = 0; i < 100; i++) {
      buf.writeByte(i);
    }
    expect(buf.getPosition()).toBe(100);
    const arr = buf.toUint8Array();
    expect(arr.length).toBe(100);
    expect(arr[0]).toBe(0);
    expect(arr[99]).toBe(99);
  });

  it('toUint8Array returns a copy', () => {
    const buf = new ByteBuffer();
    buf.writeString('hi');
    const a = buf.toUint8Array();
    const b = buf.toUint8Array();
    expect(a).toEqual(b);
    // Modifying one should not affect the other
    a[0] = 0;
    expect(b[0]).toBe(104); // 'h'
  });

  it('handles negative initial capacity gracefully', () => {
    const buf = new ByteBuffer(-1);
    buf.writeString('test');
    expect(buf.toUint8Array().length).toBe(4);
  });
});
