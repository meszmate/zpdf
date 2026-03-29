import { describe, it, expect } from 'vitest';
import { serializeObject } from '../../src/writer/object-serializer.js';
import {
  pdfBool, pdfNum, pdfStr, pdfLiteralStr, pdfHexStr, pdfName,
  pdfArray, pdfDict, pdfStream, pdfRef, pdfNull,
} from '../../src/core/objects.js';

function serialize(obj: any): string {
  return new TextDecoder().decode(serializeObject(obj));
}

describe('serializeObject', () => {
  it('serializes true boolean', () => {
    expect(serialize(pdfBool(true))).toBe('true');
  });

  it('serializes false boolean', () => {
    expect(serialize(pdfBool(false))).toBe('false');
  });

  it('serializes integer', () => {
    expect(serialize(pdfNum(42))).toBe('42');
  });

  it('serializes float', () => {
    const result = serialize(pdfNum(3.14));
    expect(parseFloat(result)).toBeCloseTo(3.14);
  });

  it('serializes zero', () => {
    expect(serialize(pdfNum(0))).toBe('0');
  });

  it('serializes literal string', () => {
    const result = serialize(pdfLiteralStr('Hello'));
    expect(result).toBe('(Hello)');
  });

  it('escapes special characters in literal strings', () => {
    const result = serialize(pdfLiteralStr('a(b)c\\d'));
    expect(result).toBe('(a\\(b\\)c\\\\d)');
  });

  it('serializes hex string', () => {
    const result = serialize(pdfHexStr('ABCD'));
    expect(result).toBe('<abcd>');
  });

  it('serializes name', () => {
    expect(serialize(pdfName('Type'))).toBe('/Type');
  });

  it('encodes special characters in names with #XX', () => {
    const result = serialize(pdfName('A B'));
    expect(result).toContain('#20'); // space encoded as #20
  });

  it('serializes empty array', () => {
    expect(serialize(pdfArray())).toBe('[]');
  });

  it('serializes array with items', () => {
    const result = serialize(pdfArray(pdfNum(1), pdfNum(2)));
    expect(result).toBe('[1 2]');
  });

  it('serializes dict', () => {
    const result = serialize(pdfDict({ Type: pdfName('Page') }));
    expect(result).toContain('<<');
    expect(result).toContain('>>');
    expect(result).toContain('/Type');
    expect(result).toContain('/Page');
  });

  it('serializes null', () => {
    expect(serialize(pdfNull())).toBe('null');
  });

  it('serializes reference', () => {
    expect(serialize(pdfRef(10, 0))).toBe('10 0 R');
  });

  it('serializes reference with non-zero generation', () => {
    expect(serialize(pdfRef(5, 2))).toBe('5 2 R');
  });

  it('serializes stream', () => {
    const data = new TextEncoder().encode('test data');
    const result = serialize(pdfStream({ Length: pdfNum(9) }, data));
    expect(result).toContain('<<');
    expect(result).toContain('stream');
    expect(result).toContain('test data');
    expect(result).toContain('endstream');
  });

  it('serializes nested structures', () => {
    const obj = pdfDict({
      Type: pdfName('Catalog'),
      Pages: pdfRef(2),
      Metadata: pdfArray(pdfBool(true), pdfNull()),
    });
    const result = serialize(obj);
    expect(result).toContain('/Type');
    expect(result).toContain('/Catalog');
    expect(result).toContain('2 0 R');
    expect(result).toContain('true');
    expect(result).toContain('null');
  });
});
